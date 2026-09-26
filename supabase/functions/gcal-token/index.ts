// gcal-token — keeps Google Calendar connected on the web without popups.
//
// Google's browser-only "token model" never issues a refresh token, so every
// renewal opened a Google popup (e.g. each time a laptop woke from sleep). The
// authorization-code flow does issue one, but exchanging and refreshing it
// needs the OAuth client *secret*, which must never ship in the web app. This
// function holds the secret and does those calls on the app's behalf.
//
// The refresh token is stored here, per signed-in Sync user, never on a device.
// That matters beyond hygiene: Google only issues a refresh token on the FIRST
// grant for an account, so a second device connecting the same Google account
// gets none. Keeping one per user lets every device renew from it.
//
// Setup (once) — see supabase/README-gcal.md:
//   1. run supabase/migrations/gcal_tokens.sql in the SQL editor
//   2. supabase secrets set GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=...
//   3. supabase functions deploy gcal-token
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the runtime.

import { createClient } from "npm:@supabase/supabase-js@2";

const CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";
const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

// Only the published apps (and local dev) may call this from a browser.
const ALLOWED_ORIGINS = ["https://olil123.github.io", "http://localhost:8080"];

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "Content-Type": "application/json" },
  });
}

async function google(url: string, params: Record<string, string>) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
  let body: Record<string, unknown> = {};
  try {
    body = await r.json();
  } catch {
    // the revoke endpoint returns an empty body on success
  }
  return { ok: r.ok, status: r.status, body };
}

async function storedToken(uid: string): Promise<string | null> {
  const { data } = await admin.from("gcal_tokens").select("refresh_token").eq("user_id", uid).maybeSingle();
  return (data?.refresh_token as string | undefined) ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);

  let action = "", code = "";
  try {
    const b = await req.json();
    action = String(b.action ?? "");
    code = String(b.code ?? "");
  } catch {
    return json(req, { error: "bad_request" }, 400);
  }

  // The app probes this at startup so it only switches to the code flow once
  // the secrets are actually in place.
  if (action === "ping") {
    return json(req, { ok: true, configured: CLIENT_ID !== "" && CLIENT_SECRET !== "" });
  }
  if (!CLIENT_ID || !CLIENT_SECRET) return json(req, { error: "not_configured" }, 503);

  // Everything else acts on the caller's own stored token, so it needs a real
  // signed-in session (the anon key alone doesn't identify anyone).
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who, error: whoErr } = await admin.auth.getUser(jwt);
  if (whoErr || !who?.user) return json(req, { error: "not_signed_in" }, 401);
  const uid = who.user.id;

  if (action === "exchange") {
    if (!code) return json(req, { error: "missing_code" }, 400);
    const r = await google("https://oauth2.googleapis.com/token", {
      code,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: "postmessage", // what the GIS popup code flow always uses
      grant_type: "authorization_code",
    });
    if (!r.ok) return json(req, { error: r.body.error ?? "exchange_failed" }, 400);
    const rt = r.body.refresh_token as string | undefined;
    if (rt) {
      await admin.from("gcal_tokens").upsert({ user_id: uid, refresh_token: rt, updated_at: new Date().toISOString() });
    } else if (!(await storedToken(uid))) {
      // Google withheld a refresh token (the grant already existed) and we have
      // none on file, so this connection couldn't last. Revoke the grant so the
      // user's next Connect is a fresh one that does include it.
      await google("https://oauth2.googleapis.com/revoke", { token: String(r.body.access_token ?? "") });
      return json(req, { error: "no_refresh_token" }, 409);
    }
    return json(req, { access_token: r.body.access_token, expires_in: r.body.expires_in });
  }

  if (action === "refresh") {
    const rt = await storedToken(uid);
    if (!rt) return json(req, { error: "no_refresh_token" }, 404);
    const r = await google("https://oauth2.googleapis.com/token", {
      refresh_token: rt,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      grant_type: "refresh_token",
    });
    if (!r.ok) {
      // invalid_grant = revoked, password changed, or the 7-day expiry Google
      // applies while the consent screen is in Testing. Forget it so the app
      // offers Reconnect; anything else is transient and the token is kept.
      if (r.body.error === "invalid_grant") {
        await admin.from("gcal_tokens").delete().eq("user_id", uid);
        return json(req, { error: "invalid_grant" }, 400);
      }
      return json(req, { error: r.body.error ?? "refresh_failed" }, 502);
    }
    return json(req, { access_token: r.body.access_token, expires_in: r.body.expires_in });
  }

  if (action === "revoke") {
    const rt = await storedToken(uid);
    if (rt) await google("https://oauth2.googleapis.com/revoke", { token: rt });
    await admin.from("gcal_tokens").delete().eq("user_id", uid);
    return json(req, { ok: true });
  }

  return json(req, { error: "unknown_action" }, 400);
});
