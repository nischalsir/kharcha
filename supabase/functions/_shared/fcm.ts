// Firebase Cloud Messaging transport.
//
// Uses the FCM HTTP v1 API directly with a service-account access token rather
// than the `firebase-admin` SDK, which keeps the dependency surface to a JWT
// signer and means there is no Admin SDK private key in the client bundle or in
// the function source. The service account JSON lives only in the Edge Function
// secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
//
// Scope requested is the narrowest that can send: `https://www.googleapis.com/auth/firebase.messaging`.

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const FCM_ENDPOINT = 'https://fcm.googleapis.com/v1';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const DEFAULT_TTL_SECONDS = 3600;

export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

let cachedToken: { value: string; expiresAt: number } | null = null;

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlEncodeText(text: string): string {
  return base64UrlEncode(new TextEncoder().encode(text));
}

/** Reads and parses the service account, or null when it is not configured. */
export function readServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (
      typeof parsed?.project_id === 'string' &&
      typeof parsed?.client_email === 'string' &&
      typeof parsed?.private_key === 'string'
    ) {
      return {
        project_id: parsed.project_id,
        client_email: parsed.client_email,
        private_key: parsed.private_key,
      };
    }
  } catch {
    // Fall through: a malformed secret is a configuration error worth
    // surfacing as "not configured" rather than crashing the isolate.
  }
  return null;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  // Strip the PEM armour and decode to DER for WebCrypto, which only takes
  // PKCS#8 bytes.
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function fetchAccessToken(
  account: ServiceAccount,
): Promise<{ value: string; expiresIn: number }> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncodeText(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64UrlEncodeText(
    JSON.stringify({
      iss: account.client_email,
      scope: SCOPE,
      aud: TOKEN_ENDPOINT,
      iat: now,
      exp: now + 3600,
    }),
  );
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) {
    throw new Error(`FCM auth failed with ${response.status}`);
  }
  const payload = await response.json();
  if (typeof payload?.access_token !== 'string') {
    throw new Error('FCM auth response had no access token');
  }
  // Google's own lifetime, not a guess: the token is minted with exp = now+3600
  // but `expires_in` is authoritative and has changed over time.
  const expiresIn =
    typeof payload?.expires_in === 'number' && payload.expires_in > 0
      ? payload.expires_in
      : DEFAULT_TTL_SECONDS;
  return { value: payload.access_token, expiresIn };
}

/**
 * Returns a cached access token, refreshing it shortly before it expires.
 *
 * Cached per isolate: each refresh is an RSA signature plus a network round
 * trip, so a batch send of 500 tokens must not pay that 500 times.
 */
async function getAccessToken(account: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.value;
  }
  const value = await fetchAccessToken(account);
  cachedToken = { value: value.value, expiresAt: now + value.expiresIn * 1000 };
  return value.value;
}

export type FcmMessage = {
  token?: string;
  topic?: string;
  data: Record<string, string>;
  android?: {
    priority?: 'normal' | 'high';
    ttl?: string;
    collapseKey?: string;
    notification?: { channelId: string; sound?: string };
  };
};

export type SendResult =
  | { ok: true; name: string }
  | { ok: false; token: string; status: number; code: string; unregistered: boolean };

/**
 * FCM error codes that mean the token is permanently dead.
 *
 * UNREGISTERED means the app was uninstalled or the token was replaced;
 * INVALID_ARGUMENT on a token is likewise unrecoverable. Either way the row
 * should be deleted rather than retried, otherwise every future send pays for
 * a guaranteed failure.
 */
const DEAD_TOKEN_CODES = new Set([
  'UNREGISTERED',
  'INVALID_ARGUMENT',
  'SENDER_ID_MISMATCH',
]);

/** Sends one message. Never throws; failures are returned as data. */
export async function sendMessage(message: FcmMessage): Promise<SendResult> {
  const account = readServiceAccount();
  if (!account) {
    return {
      ok: false,
      token: message.token ?? message.topic ?? '',
      status: 0,
      code: 'NO_SERVICE_ACCOUNT',
      unregistered: false,
    };
  }

  try {
    const accessToken = await getAccessToken(account);
    const target = message.token ? { token: message.token } : { topic: message.topic };

    // FCM v1 nests the payload under `message`. Spreading `...message` after
    // `target` would overwrite that key with the flat payload and send a
    // malformed body that fails with UNSPECIFIED_ERROR, so the target is
    // destructured out and reassembled explicitly.
    const { token, topic, ...rest } = message;
    void token;
    void topic;

    const response = await fetch(
      `${FCM_ENDPOINT}/projects/${account.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message: { ...target, ...rest } }),
      },
    );

    if (response.ok) {
      const payload = await response.json();
      return { ok: true, name: payload?.name ?? '' };
    }

    let code = `HTTP_${response.status}`;
    try {
      const payload = await response.json();
      const status = payload?.error?.status;
      if (typeof status === 'string') code = status;
      else if (Array.isArray(payload?.error?.details)) {
        const details = payload.error.details as Array<{ errorCode?: unknown }>;
        const match = details.find((detail) => typeof detail?.errorCode === 'string');
        if (typeof match?.errorCode === 'string') code = match.errorCode;
      }
    } catch {
      // Non-JSON error body; the HTTP status is enough to classify.
    }

    return {
      ok: false,
      token: message.token ?? message.topic ?? '',
      status: response.status,
      code,
      unregistered: DEAD_TOKEN_CODES.has(code),
    };
  } catch (error) {
    return {
      ok: false,
      token: message.token ?? message.topic ?? '',
      status: 0,
      code: error instanceof Error ? error.message : 'NETWORK_ERROR',
      unregistered: false,
    };
  }
}
