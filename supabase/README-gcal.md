# Keeping Google Calendar connected (web)

The web app used Google's browser-only token flow, which never issues a refresh
token — so every renewal opened a Google popup (e.g. each time a laptop woke from
sleep). Now it uses the authorization-code flow: you approve once, the
`gcal-token` Edge Function stores a refresh token for your Sync account, and the
app renews access silently from then on.

Until these steps are done the app still works: it just never pops up on its
own, and shows **Reconnect Google** once the one-hour access runs out.

## 1. Create the token table

Supabase Dashboard → **SQL Editor** → paste and run
[`migrations/gcal_tokens.sql`](migrations/gcal_tokens.sql).

## 2. Add the Google client secret

Google Cloud Console → **APIs & Services → Credentials** → open the **Web
client** (`61656841317-scqp…apps.googleusercontent.com`) → copy its **Client
secret**.

Supabase Dashboard → **Edge Functions → Secrets** → add:

| Name                   | Value                                   |
|------------------------|-----------------------------------------|
| `GOOGLE_CLIENT_ID`     | `61656841317-scqpj3kd9empq6vio94degulpd40plvr.apps.googleusercontent.com` |
| `GOOGLE_CLIENT_SECRET` | the secret you just copied              |

The secret stays on Supabase — it is never in the app or this repo.

## 3. Deploy the function

Either with the CLI from this repo:

```bash
supabase functions deploy gcal-token --project-ref mfpkswkpwfdltlzutzed
```

or in the Dashboard: **Edge Functions → Deploy a new function → Via editor**,
name it exactly `gcal-token`, and paste
[`functions/gcal-token/index.ts`](functions/gcal-token/index.ts).

## 4. Stop Google expiring it after a week

While the OAuth consent screen is in **Testing**, Google revokes refresh tokens
after **7 days**. Google Cloud Console → **Google Auth Platform → Audience** →
**Publish app** (to *In production*). Your app is unverified, so Google shows a
"Google hasn't verified this app" screen during sign-in — click **Advanced →
Go to … (unsafe)**. That's expected for a personal app and allows up to 100 users.

## 5. Reconnect once on each device

Reload the app, then in the TODAY card tap **Connect / Reconnect Google** and
approve. You must be signed in to **Sync** — the refresh token is stored against
that account, which is also what lets your other devices share it.

### Checking it works

The app pings the function on startup. If the calendar card still says
**Reconnect Google** after an hour, the function isn't reachable or the secrets
are missing — **Edge Functions → gcal-token → Logs** will show why.
