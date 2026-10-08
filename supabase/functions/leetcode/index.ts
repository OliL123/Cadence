// leetcode — relays one public LeetCode stats query for the Career page.
//
// LeetCode's GraphQL API doesn't allow browser requests (no CORS), so the
// web app asks this function instead. It accepts only a username and runs
// one fixed read-only query — solved counts, streak and recent solves, all
// public on the profile page — so it can't be used to proxy anything else.
// No secrets needed. Deploy it with the name `leetcode`.

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

const QUERY = `
query($u: String!) {
  matchedUser(username: $u) {
    username
    submitStatsGlobal { acSubmissionNum { difficulty count } }
    userCalendar { streak }
  }
  recentAcSubmissionList(username: $u, limit: 5) { title titleSlug timestamp }
}`;

Deno.serve(async (req) => {
  const headers = { ...cors(req), "Content-Type": "application/json" };
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response('{"error":"method"}', { status: 405, headers });

  let username = "";
  try {
    username = String((await req.json())?.username ?? "");
  } catch {
    // fall through to the check below
  }
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(username)) {
    return new Response('{"error":"bad_username"}', { status: 400, headers });
  }

  const r = await fetch("https://leetcode.com/graphql", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Referer": "https://leetcode.com" },
    body: JSON.stringify({ query: QUERY, variables: { u: username } }),
  });
  if (!r.ok) {
    return new Response(JSON.stringify({ error: "leetcode", status: r.status }), { status: 502, headers });
  }
  return new Response(await r.text(), { headers });
});
