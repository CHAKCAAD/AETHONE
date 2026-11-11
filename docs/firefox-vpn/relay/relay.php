<?php
/**
 * AETHONE control-plane relay — PHP edition (2026-11-12).
 *
 * The same relay as docs/firefox-vpn/relay/worker.js, for a host you
 * already have: upload this ONE file, open its address with ?secret=…
 * Requirements: HTTPS, PHP 7.3+, the curl extension. The wire protocol
 * is the community relay protocol (docs/firefox-vpn/relay.md) — a
 * worker, a PHP file or any other endpoint built from that spec are
 * interchangeable.
 *
 *   https://YOUR-DOMAIN/relay.php?secret=SECRET                 → status page
 *   https://YOUR-DOMAIN/relay.php?secret=SECRET&health=1        → health JSON
 *   https://YOUR-DOMAIN/relay.php?secret=SECRET&url=https://…   → forwarded
 *
 * Only the hosts in $ALLOWED are forwarded (never an open proxy). The
 * VPN traffic itself never passes through here — only the control-plane
 * requests (sign-in, Guardian, server list, geo files) do.
 */

// A long random string only you know. REQUIRED: without it nothing is
// relayed — the sign-in and the account tokens cross this endpoint.
$SECRET = '';

// The control-plane hosts the engine may reach through the relay.
$ALLOWED = array(
    'mozilla.org', 'mozilla.com', 'firefox.com',           // accounts, Guardian, server list
    'github.com', 'githubusercontent.com', 'jsdelivr.net', // geo files, flags
);

// ---------------------------------------------------------------------------

/** Answer with the relay's own refusal (the client surfaces it). */
function relay_refuse(int $status, string $reason): void {
    http_response_code($status);
    header('Content-Type: text/plain; charset=utf-8');
    header('X-Relay-Error: ' . $reason); // header injection-safe: fixed texts only
    echo $reason;
    exit;
}

/** The shared-pool health answer: local proof the endpoint is alive. */
function relay_health(): void {
    http_response_code(200);
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    echo '{"relay":"aethone","version":1,"ready":true}';
    exit;
}

/** The browser status page (no url parameter). */
function relay_page(string $kind): void {
    $states = array(
        'ok'    => array('color' => '#10b981', 'status' => 200, 'badge' => 'Working',
                         'title' => 'Your AETHONE relay is ready',
                         'body'  => 'Put this page\'s full address — including <code>?secret=…</code> — in AETHONE: Settings → Firefox → Relay server → Personal relay.'),
        'wrong' => array('color' => '#ef4444', 'status' => 403, 'badge' => 'Wrong secret',
                         'title' => 'This address has no secret, or the wrong one',
                         'body'  => 'The address must end in <code>?secret=</code> followed by exactly the $SECRET set in this file.'),
        'unset' => array('color' => '#f59e0b', 'status' => 503, 'badge' => 'Not set up',
                         'title' => 'Set a secret first',
                         'body'  => 'Set <code>$SECRET</code> in this file to a long random text, upload it again, then open this address with <code>?secret=…</code> at the end.'),
    );
    $s = $states[$kind];
    http_response_code($s['status']);
    header('Content-Type: text/html; charset=utf-8');
    $c = $s['color'];
    echo <<<HTML
<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AETHONE relay</title>
<style>
:root{--c:$c}
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
<span class="badge">{$s['badge']}</span><h1>{$s['title']}</h1><p>{$s['body']}</p></div></html>
HTML;
    exit;
}

// ---- the walk -------------------------------------------------------------

if ($SECRET === '') {
    isset($_GET['url']) || isset($_GET['health'])
        ? relay_refuse(503, 'no secret is set in the relay')
        : relay_page('unset');
}
if (!isset($_GET['secret']) || !hash_equals($SECRET, $_GET['secret'])) {
    isset($_GET['url']) || isset($_GET['health'])
        ? relay_refuse(403, 'wrong secret')
        : relay_page('wrong');
}
if (isset($_GET['health'])) {
    $_SERVER['REQUEST_METHOD'] === 'GET'
        ? relay_health()
        : relay_refuse(405, 'health requires GET');
}
if (!isset($_GET['url'])) {
    relay_page('ok');
}

$target = filter_var($_GET['url'], FILTER_VALIDATE_URL);
if ($target === false) {
    relay_refuse(400, 'url must be an https URL');
}
$parts = parse_url($target);
if ($parts === false || ($parts['scheme'] ?? '') !== 'https' || ($parts['host'] ?? '') === '') {
    relay_refuse(400, 'url must be an https URL');
}
if (isset($parts['user']) || isset($parts['pass']) || isset($parts['fragment']) ||
    (isset($parts['port']) && (int) $parts['port'] !== 443)) {
    relay_refuse(400, 'target must not carry credentials, a fragment or a non-HTTPS port');
}
$host = strtolower($parts['host']);
$allowed = false;
foreach ($ALLOWED as $domain) {
    if ($host === $domain || substr($host, -strlen($domain) - 1) === '.' . $domain) {
        $allowed = true;
        break;
    }
}
if (!$allowed) {
    relay_refuse(403, 'host not allowed: ' . $host);
}

// Copy the request's headers, minus this hop's own.
$hop = array('host', 'connection', 'content-length', 'keep-alive',
    'proxy-authenticate', 'proxy-authorization', 'te', 'trailer',
    'transfer-encoding', 'upgrade', 'forwarded', 'x-forwarded-for',
    'x-forwarded-proto', 'x-forwarded-host', 'x-real-ip', 'true-client-ip');
$forward = array();
foreach ($_SERVER as $key => $value) {
    if (strpos($key, 'HTTP_') !== 0) continue;
    $name = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($key, 5)))));
    if (in_array(strtolower($name), $hop, true)) continue;
    $forward[$name] = $value;
}

$ch = curl_init($target);
// The headers ride as "Name: value" lines (curl's format).
$lines = array();
foreach ($forward as $name => $value) {
    $lines[] = $name . ': ' . $value;
}
curl_setopt_array($ch, array(
    CURLOPT_CUSTOMREQUEST => $_SERVER['REQUEST_METHOD'],
    CURLOPT_HTTPHEADER => $lines,
    CURLOPT_HEADER => true,                     // split status/headers/body below
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => false,            // redirects go back to the client
    CURLOPT_TIMEOUT => 30,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_SSL_VERIFYPEER => true,             // the target is verified, never downgraded
    CURLOPT_SSL_VERIFYHOST => 2,
));

$method = $_SERVER['REQUEST_METHOD'];
if ($method !== 'GET' && $method !== 'HEAD') {
    curl_setopt($ch, CURLOPT_POSTFIELDS, file_get_contents('php://input'));
    // keep the client's own Content-Type header, not curl's default
    if (isset($_SERVER['CONTENT_TYPE'])) {
        $lines[] = 'Content-Type: ' . $_SERVER['CONTENT_TYPE'];
        curl_setopt($ch, CURLOPT_HTTPHEADER, $lines);
    }
}

$raw = curl_exec($ch);
if ($raw === false) {
    curl_close($ch);
    relay_refuse(502, 'upstream request failed');
}
$status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
$headerSize = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$rawHeaders = substr($raw, 0, $headerSize);
$responseBody = substr($raw, $headerSize);
curl_close($ch);

http_response_code($status);
header('X-Aethone-Relay: 1');
foreach (explode("\r\n", $rawHeaders) as $line) {
    if ($line === '' || strpos($line, ':') === false) continue;
    list($name, $value) = explode(':', $line, 2);
    $lower = strtolower(trim($name));
    if (in_array($lower, array('transfer-encoding', 'content-length', 'connection', 'keep-alive', 'content-encoding'), true)) {
        continue; // this hop re-chunks and re-lengths the body itself
    }
    header(trim($name) . ': ' . trim($value));
}
echo $responseBody;
