// Signs Cloudinary uploads for the signed-in user, and deletes their media.
//
// The API secret never leaves the server. The CLIENT never chooses where a
// file goes: the public id is derived here from the verified user id, so one
// user cannot overwrite another user's avatar by asking for a different path.
//
//   POST { "action": "upload",  "kind": "avatar" }
//     -> { uploadUrl, params: { api_key, timestamp, signature, public_id, ... } }
//        The app POSTs the image to uploadUrl with exactly these params.
//   POST { "action": "destroy", "kind": "avatar" }
//     -> { ok: true }   (performed server side)
//
// Secrets: CLOUDINARY_URL (cloudinary://<key>:<secret>@<cloud>), or
// CLOUDINARY_CLOUD_NAME + CLOUDINARY_API_KEY + CLOUDINARY_API_SECRET.
import { badRequest, getUser, json, serverError, unauthorized } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

interface CloudinaryConfig {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
}

function readConfig(): CloudinaryConfig | null {
  const url = Deno.env.get("CLOUDINARY_URL");
  if (url) {
    const match = url.match(/^cloudinary:\/\/([^:]+):([^@]+)@(.+)$/);
    if (match) {
      return { apiKey: match[1], apiSecret: match[2], cloudName: match[3] };
    }
  }
  const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
  const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
  const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
  if (cloudName && apiKey && apiSecret) return { cloudName, apiKey, apiSecret };
  return null;
}

/** Cloudinary's signature: SHA-1 of the sorted params plus the secret. */
export async function sign(
  params: Record<string, string>,
  apiSecret: string,
): Promise<string> {
  const payload = Object.keys(params)
    .sort()
    .map((key) => `${key}=${params[key]}`)
    .join("&");
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(payload + apiSecret),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Where each kind of media lives. Keyed by user id, decided server side. */
function publicIdFor(kind: string, userId: string): string | null {
  switch (kind) {
    case "avatar":
      return `kharcha/avatars/${userId}`;
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const user = await getUser(req);
  if (!user) return unauthorized();

  const config = readConfig();
  if (!config) return serverError("Cloudinary is not configured on the server.");

  let body: { action?: unknown; kind?: unknown };
  try {
    body = await req.json();
  } catch {
    return badRequest("Invalid JSON body");
  }
  const action = typeof body.action === "string" ? body.action : "";
  const kind = typeof body.kind === "string" ? body.kind : "";
  const publicId = publicIdFor(kind, user.id);
  if (!publicId) return badRequest("Unknown media kind");

  const timestamp = String(Math.floor(Date.now() / 1000));

  if (action === "upload") {
    // Everything that affects where or how the file is stored is signed, so
    // the client cannot alter it without invalidating the signature.
    const params: Record<string, string> = {
      public_id: publicId,
      overwrite: "true",
      invalidate: "true",
      timestamp,
      // Cap the stored original; delivery transforms resize further.
      transformation: "c_limit,w_1024,h_1024",
      allowed_formats: "jpg,jpeg,png,webp,heic",
    };
    const signature = await sign(params, config.apiSecret);
    return json({
      uploadUrl: `https://api.cloudinary.com/v1_1/${config.cloudName}/image/upload`,
      cloudName: config.cloudName,
      params: { ...params, api_key: config.apiKey, signature },
    });
  }

  if (action === "destroy") {
    const params: Record<string, string> = {
      public_id: publicId,
      invalidate: "true",
      timestamp,
    };
    const signature = await sign(params, config.apiSecret);
    const form = new FormData();
    for (const [key, value] of Object.entries(params)) form.append(key, value);
    form.append("api_key", config.apiKey);
    form.append("signature", signature);
    const res = await fetch(
      `https://api.cloudinary.com/v1_1/${config.cloudName}/image/destroy`,
      { method: "POST", body: form },
    );
    if (!res.ok) {
      console.error("media-sign: destroy failed", res.status, await res.text());
      return serverError("Could not delete the image.");
    }
    return json({ ok: true });
  }

  return badRequest("Unknown action");
});
