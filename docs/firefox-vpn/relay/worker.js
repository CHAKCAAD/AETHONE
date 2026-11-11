// AETHONE control-plane relay — Cloudflare Worker edition (2026-11-12).
//
// WHAT THIS IS. A tiny forwarding endpoint for the AETHONE (Firefox VPN)
// engine's CONTROL-PLANE requests, for networks where Mozilla's side
// refuses the region (Guardian answers HTTP 451 unavailable_in_region)
// or cannot be reached at all. The engine puts the target URL in this
// worker's `url` query parameter (next to the worker's own `secret`):
//
//     https://YOUR-WORKER.workers.dev/?secret=SECRET&url=https://vpn.mozilla.org/api/v1/fpn/token
//
// The method, headers and body are forwarded as they are; the target's
// response comes back as this worker's response. The VPN traffic itself
// NEVER passes through here — only sign-in, Guardian, server-list and
// geo-file requests do. The wire protocol is the community relay
// protocol (docs/firefox-vpn/relay.md): a worker or PHP file built from
// that spec is interchangeable with this one.
//
// DEPLOY: Cloudflare dashboard → Workers & Pages → Create → Worker,
// paste this file, set SECRET below (or bind a Worker secret named
// SECRET — safer), Deploy. Then open
// https://YOUR-WORKER.workers.dev/?secret=SECRET in a browser: the
// status page tells you whether it works. No domain, no server needed.
//
// PROTOCOL NOTES.
//   ?secret=WRONG           → 403 + X-Relay-Error (the client surfaces it)
//   ?health=1 (+ secret)    → {"relay":"aethone","version":1,"ready":true}
//                             (the shared-pool health shape; answers ONLY
//                             about this worker — nothing is forwarded)
//   ?url=https://…          → forwarded (see ALLOWED below)
//   no secret set at all    → 503 + the setup page
//
// Only the hosts in ALLOWED are forwarded, so this is never an open
// proxy; hop-by-hop and Cloudflare-injected headers are dropped, and
// every forwarded response is marked X-Aethone-Relay: 1 so the client
// can tell a real Mozilla answer from a Cloudflare error page.

// A long random string only you know. The relay URL ends in
// ?secret=THIS. Without one, nothing is relayed: the sign-in and the
// account tokens cross this worker.
const SECRET = "";

// The control-plane hosts the engine may reach through the relay.
// mozilla.org  — accounts (FxA), Guardian (vpn.mozilla.org), RemoteSettings
// firefox.com  — Mozilla's alias domain family
// github.com / githubusercontent.com / jsdelivr.net — geo files, flags
const ALLOWED = [
  "mozilla.org",
  "mozilla.com",
  "firefox.com",
  "github.com",
  "githubusercontent.com",
  "jsdelivr.net",
];

// Headers that describe this hop, not the request being forwarded.
const HOP_HEADERS = new Set([
  "host", "connection", "content-length", "keep-alive",
  "proxy-authenticate", "proxy-authorization", "te", "trailer",
  "transfer-encoding", "upgrade", "forwarded", "x-forwarded-for",
  "x-forwarded-proto", "x-forwarded-host", "x-real-ip", "true-client-ip",
]);

function refuse(status, reason) {
  return new Response(reason, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", "X-Relay-Error": reason },
  });
}

// The browser-facing status page (no url parameter): green when the
// secret matched, red when it did not, amber when SECRET is unset.
function statusPage(kind) {
  const states = {
    ok: {
      color: "#10b981", status: 200, badge: "Working",
      title: "Your AETHONE relay is ready",
      body: "Put this page's full address — including <code>?secret=…</code> — in AETHONE: Settings → Firefox → Relay server → Personal relay.",
    },
    wrong: {
      color: "#ef4444", status: 403, badge: "Wrong secret",
      title: "This address has no secret, or the wrong one",
      body: "The address must end in <code>?secret=</code> followed by exactly the SECRET set in the worker script.",
    },
    unset: {
      color: "#f59e0b", status: 503, badge: "Not set up",
      title: "Set a secret first",
      body: "Edit the script, set <code>SECRET</code> to a long random text, deploy again, then open this address with <code>?secret=…</code> at the end.",
    },
  };
  const s = states[kind];
  const html = `<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AETHONE relay</title>
<style>
:root{--c:${s.color}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;
color:#1d2040;background:#eef0fb;font:16px/1.65 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.card{width:min(560px,100%);background:#fff;border-radius:22px;padding:34px 32px;
border-top:5px solid var(--c);box-shadow:0 24px 70px rgba(20,27,61,.18)}
.brand{font-weight:700;color:#5d6385;font-size:14px;letter-spacing:.02em}
.badge{display:inline-block;margin-top:22px;padding:6px 14px;border-radius:999px;
font-weight:700;font-size:14px;color:var(--c);background:color-mix(in srgb,var(--c) 15%,transparent)}
h1{font-size:23px;line-height:1.3;margin:14px 0 8px}
p{margin:0;color:#5d6385}
code{background:#eef;color:#5b5bd6;padding:1px 6px;border-radius:6px}
</style>
<div class="card"><div class="brand">AETHONE relay</div>
<span class="badge">${s.badge}</span><h1>${s.title}</h1><p>${s.body}</p></div></html>`;
  return new Response(html, { status: s.status, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

// The shared-pool health answer: a LOCAL proof the worker is alive and
// correctly configured. It forwards nothing to Mozilla.
function health() {
  return new Response(
    JSON.stringify({ relay: "aethone", version: 1, ready: true }),
    { status: 200, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } },
  );
}

export default {
  async fetch(request, env = {}) {
    const here = new URL(request.url);
    const wantsHealth = here.searchParams.get("health") === "1";
    const isBrowser = !here.searchParams.has("url") && !wantsHealth;

    const secret = env.SECRET || SECRET;
    if (!secret) {
      return isBrowser ? statusPage("unset") : refuse(503, "no secret is set in the relay");
    }
    if (here.searchParams.get("secret") !== secret) {
      return isBrowser ? statusPage("wrong") : refuse(403, "wrong secret");
    }
    if (wantsHealth) {
      return request.method === "GET" ? health() : refuse(405, "health requires GET");
    }
    if (isBrowser) {
      return statusPage("ok");
    }

    let target;
    try {
      target = new URL(here.searchParams.get("url") || "");
    } catch {
      return refuse(400, "url must be an https URL");
    }
    if (target.protocol !== "https:") {
      return refuse(400, "url must be an https URL");
    }
    if (target.username || target.password || target.hash ||
        (target.port && target.port !== "443")) {
      return refuse(400, "target must not carry credentials, a fragment or a non-HTTPS port");
    }
    const host = target.hostname.toLowerCase();
    const allowed = ALLOWED.some((d) => host === d || host.endsWith("." + d));
    if (!allowed) {
      return refuse(403, `host not allowed: ${host}`);
    }

    const headers = new Headers();
    for (const [name, value] of request.headers) {
      const lower = name.toLowerCase();
      if (HOP_HEADERS.has(lower) || lower.startsWith("cf-")) continue;
      headers.set(name, value);
    }

    // Control-plane bodies are small (sign-in, tokens); read whole.
    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    const body = hasBody ? await request.arrayBuffer() : undefined;

    // Redirects go back to the client, which follows them through the
    // relay again (its cookie jar is scoped to the TARGET, not here).
    try {
      const upstream = await fetch(target, {
        method: request.method,
        headers,
        body,
        redirect: "manual",
      });
      const out = new Headers(upstream.headers);
      // Mark a genuinely FORWARDED answer so the client can tell it
      // from an error page Cloudflare itself generated.
      out.set("X-Aethone-Relay", "1");
      return new Response(upstream.body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers: out,
      });
    } catch {
      return refuse(502, "upstream request failed");
    }
  },
};
