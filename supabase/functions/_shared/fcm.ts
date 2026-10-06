// Firebase Cloud Messaging transport.
//
// Uses the FCM HTTP v1 API directly with a service-account access token rather
// than the `firebase-admin` SDK, which keeps the dependency surface to a JWT
// signer and means there is no Admin SDK private key in the client bundle or in
// the function source. The service account JSON lives only in the Edge Function
// secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
//
// Scope requested is the narrowest that can send: `https://www.googleapis.com/auth/firebase.messaging`.

import { resolveChannel } from './push_types.ts';

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
  // PKCS#8 bytes. A key pasted into the dashboard or a shell often arrives with
  // its newlines double-escaped, leaving literal `\n` pairs after JSON.parse;
  // those are not whitespace, so they are turned back into newlines first or
  // atob() fails with "Failed to decode base64".
  const body = pem
    .replace(/\\[rn]/g, '\n')
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
  /**
   * The app version the device behind `token` last reported, when known. It
   * decides which of the two shapes below the message takes; it is never sent.
   */
  appVersion?: string | null;
  data: Record<string, string>;
  android?: {
    priority?: 'normal' | 'high';
    ttl?: string;
    collapseKey?: string;
  };
};

/**
 * The first app version that leaves a message Android has already drawn
 * alone. Older versions draw every message themselves from `data`.
 */
const SYSTEM_DRAWN_FROM = [2, 3, 0];

/**
 * Whether a device on [appVersion] should be sent a message Android draws
 * itself (a `notification` block beside the `data`).
 *
 * A data-only message is only seen if the phone lets the app start in the
 * background and run long enough to draw it. Many phones do not once the app
 * has been swiped away, so nothing arrived until it was opened again. A
 * message with a `notification` block is drawn by Android without the app
 * having to do anything, which is how every other app's notifications
 * arrive.
 *
 * Only for versions that know about it: an older app would draw its own copy
 * as well and show everything twice. No reported version means an older app.
 */
export function systemDrawn(appVersion: string | null | undefined): boolean {
  if (typeof appVersion !== 'string') return false;
  const parts = appVersion.trim().replace(/^v/i, '').split(/[.+-]/);
  for (let i = 0; i < SYSTEM_DRAWN_FROM.length; i++) {
    const part = Number.parseInt(parts[i] ?? '0', 10);
    if (!Number.isFinite(part)) return false;
    if (part !== SYSTEM_DRAWN_FROM[i]) return part > SYSTEM_DRAWN_FROM[i];
  }
  return true;
}

/**
 * The `message` object FCM is sent for [message].
 *
 * Always carries the whole notification in `data`, which is what the app
 * reads: to draw it while it is open, to open the right page on a tap, and to
 * keep it on its Notifications page. For a device that can take it (see
 * [systemDrawn]) the title and body are also given to Android to draw, in the
 * channel the category belongs to; `collapseKey` becomes its tag, so a newer
 * one replaces the older one in the shade as well as in the queue.
 */
export function buildFcmBody(message: FcmMessage): Record<string, unknown> {
  const { token, topic, appVersion, ...rest } = message;
  const target = token ? { token } : { topic };
  const title = rest.data.title;
  const body = rest.data.body;
  if (!token || !systemDrawn(appVersion) || !title || !body) {
    return { ...target, ...rest };
  }
  const tag = rest.android?.collapseKey;
  const image = pictureUrl(rest.data.image);
  return {
    ...target,
    ...rest,
    notification: { title, body },
    android: {
      ...rest.android,
      notification: {
        channelId: resolveChannel(rest.data.category ?? ''),
        ...(tag ? { tag } : {}),
        // Android fetches and draws the picture itself. It stays in `data` as
        // well, which is where the app reads it to draw the same picture when
        // it is the one drawing.
        ...(image ? { image } : {}),
      },
    },
  };
}

/**
 * The picture a notification carries (`data.image`), or undefined when there
 * is none or it is not a link a phone will fetch. Android only loads a
 * notification picture over https.
 */
export function pictureUrl(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 500) return undefined;
  try {
    return new URL(trimmed).protocol === 'https:' ? trimmed : undefined;
  } catch {
    return undefined;
  }
}

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

    const response = await fetch(
      `${FCM_ENDPOINT}/projects/${account.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        // FCM v1 nests the payload under `message`.
        body: JSON.stringify({ message: buildFcmBody(message) }),
      },
    );

    if (response.ok) {
      const payload = await response.json();
      return { ok: true, name: payload?.name ?? '' };
    }

    let code = `HTTP_${response.status}`;
    try {
      const payload = await response.json();
      // The FCM-specific `errorCode` in `details` wins over the generic gRPC
      // `status`: an uninstalled app comes back as status NOT_FOUND with
      // errorCode UNREGISTERED, and only the latter marks the token as dead.
      const details = Array.isArray(payload?.error?.details)
        ? payload.error.details as Array<{ errorCode?: unknown }>
        : [];
      const match = details.find((detail) => typeof detail?.errorCode === 'string');
      const status = payload?.error?.status;
      if (typeof match?.errorCode === 'string') code = match.errorCode;
      else if (typeof status === 'string') code = status;
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
