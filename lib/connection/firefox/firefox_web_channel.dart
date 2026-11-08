/// The FxA WebChannel bridge — the pure-Dart message mapping between the
/// accounts.firefox.com sign-in page (loaded with `context=fx_desktop_v3`,
/// which makes the page speak the WebChannel protocol) and the app.
///
/// ADAPTED from FoxyVPN's `BrowserLoginScreen.kt` WebChannel bridge
/// (https://github.com/Vauth/FoxyVPN — MIT License, Copyright (c) 2026
/// Vauth). The adaptation: the bridge is a pure, WebView-free Dart class
/// (fully unit-testable — the screen only wires it to
/// webview_flutter's JavaScriptChannel), the JS channel is named
/// `aethoneFxChannel`, and the reply entrypoint is
/// `window.__aethoneFxReply`. The WebChannel message protocol itself
/// (the commands, the `WebChannelMessageToChrome` /
/// `WebChannelMessageToContent` events, the `fx_desktop_v3` context) is
/// Mozilla's, as spoken by accounts.firefox.com.
///
/// Security notes:
///  * the hook only ever forwards payloads whose page host is
///    accounts.firefox.com or a *.firefox.com subdomain;
///  * the only secret this layer ever surfaces is the 64-hex session
///    token from the `fxaccounts:login` / `oauth_login` messages — it is
///    handed to the login client's STDIN pipe (never logged, never
///    persisted; see firefox_login.dart);
///  * after a completed exchange the login screen clears the WebView's
///    cookies, which kills the browser session locally (the equivalent
///    of the reference's POST /session/destroy hygiene).
library;

import 'dart:convert';

/// The sign-in page URL (the `fx_desktop_v3` context makes the page use
/// the WebChannel; `service=sync&action=email` opens the email-first
/// flow — the same URL the MIT reference loads).
const String kFirefoxLoginUrl =
    'https://accounts.firefox.com/?context=fx_desktop_v3&service=sync&action=email';

/// The pinned Firefox identity major version (matches the engine's
/// control-plane pin, `defaultFirefoxVersion` in the vendored
/// firefox_identity.go — one identity everywhere).
const String kFirefoxIdentityVersion = '159.0';

/// The WebView user agent: Firefox-on-Android, matching the pinned
/// identity (the FxA page must believe it runs inside Firefox for the
/// WebChannel to engage).
String firefoxLoginUserAgent(String androidVersion) =>
    'Mozilla/5.0 (Android $androidVersion; Mobile; '
    'rv:$kFirefoxIdentityVersion) Gecko/$kFirefoxIdentityVersion '
    'Firefox/$kFirefoxIdentityVersion';

/// WebChannel command names the FxA page sends.
abstract final class FirefoxWebChannelCommands {
  static const fxaStatus = 'fxaccounts:fxa_status';
  static const canLinkAccount = 'fxaccounts:can_link_account';
  static const login = 'fxaccounts:login';
  static const oauthLogin = 'fxaccounts:oauth_login';
}

/// The outcome of one WebChannel message: an optional JS reply script to
/// evaluate in the page and/or the captured session token.
class FirefoxWebChannelResult {
  const FirefoxWebChannelResult({this.replyScript, this.sessionToken});

  /// A JS snippet for `WebViewController.runJavaScript` (null = no
  /// reply needed).
  final String? replyScript;

  /// The 64-hex session token when this message was a completed sign-in;
  /// null otherwise. SECRET — goes to the login client's stdin pipe only.
  final String? sessionToken;
}

/// The pure message mapping. One instance per login screen; stateless
/// apart from the duplicate-token guard.
class FirefoxWebChannelBridge {
  String? _lastSessionToken;

  /// The JavaScript hook injected into the page on every navigation:
  /// forwards the page's WebChannel messages to the
  /// `aethoneFxChannel` JavaScriptChannel (host-restricted) and exposes
  /// `window.__aethoneFxReply` for the answers.
  static String get hookScript => _hookJs;

  /// Handles one raw payload posted by the hook (already a JSON string).
  /// [originUrl] is the page's URL — the host is re-verified here (the
  /// JS-side check is defense in depth, not the only gate).
  FirefoxWebChannelResult handle(String payload, String originUrl) {
    if (!_allowedOrigin(originUrl)) {
      return const FirefoxWebChannelResult();
    }
    Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return const FirefoxWebChannelResult();
      envelope = decoded;
    } catch (_) {
      return const FirefoxWebChannelResult();
    }
    final channelId = (envelope['id'] as String?) ?? '';
    final message = envelope['message'];
    if (message is! Map) return const FirefoxWebChannelResult();
    final command = (message['command'] as String?) ?? '';
    final data = message['data'];
    final dataMap = data is Map ? data : const <String, dynamic>{};
    final messageId = (message['messageId'] as String?) ?? '';

    switch (command) {
      case FirefoxWebChannelCommands.fxaStatus:
        return FirefoxWebChannelResult(
          replyScript:
              _reply(channelId, messageId, command, '{"capabilities":{},"signedInUser":null}'),
        );
      case FirefoxWebChannelCommands.canLinkAccount:
        return FirefoxWebChannelResult(
          replyScript: _reply(channelId, messageId, command, '{"ok":true}'),
        );
      case FirefoxWebChannelCommands.login:
      case FirefoxWebChannelCommands.oauthLogin:
        final token = _cleanToken((dataMap['sessionToken'] as String?) ??
            (dataMap['token'] as String?) ??
            '');
        String? captured;
        if (token != null && token != _lastSessionToken) {
          _lastSessionToken = token;
          captured = token;
        }
        return FirefoxWebChannelResult(
          replyScript: messageId.isEmpty
              ? null
              : _reply(channelId, messageId, command, '{"ok":true}'),
          sessionToken: captured,
        );
      default:
        return FirefoxWebChannelResult(
          replyScript:
              messageId.isEmpty ? null : _reply(channelId, messageId, command, '{"ok":true}'),
        );
    }
  }

  /// jsonEncode produces a valid JS string literal for ASCII payloads —
  /// exactly the reference's `JSONObject.quote` role.
  static String _reply(
      String channelId, String messageId, String command, String dataJson) {
    return 'window.__aethoneFxReply && window.__aethoneFxReply('
        '${jsonEncode(channelId.isEmpty ? 'account_updates' : channelId)}, '
        '${jsonEncode(messageId)}, ${jsonEncode(command)}, $dataJson);';
  }

  static String? _cleanToken(String raw) {
    final clean = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s"]'), '');
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(clean) ? clean : null;
  }

  static bool _allowedOrigin(String url) {
    Uri? parsed;
    try {
      parsed = Uri.parse(url);
    } catch (_) {
      return false;
    }
    final host = (parsed.host).toLowerCase();
    return host == 'accounts.firefox.com' || host.endsWith('.firefox.com');
  }
}

const String _hookJs = '''
(function() {
  if (window.__aethoneFxHooked) return;
  window.__aethoneFxHooked = true;
  var send = function(o) {
    try {
      var host = window.location.hostname;
      if (host !== 'accounts.firefox.com' && !host.endsWith('.firefox.com')) return;
      var payload = typeof o === 'string' ? o : JSON.stringify(o);
      aethoneFxChannel.postMessage(payload);
    } catch (e) {}
  };
  var onChannel = function(e) {
    var d = e.detail;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
    if (d && d.message) send(d);
  };
  window.addEventListener('WebChannelMessageToChrome', onChannel);
  document.addEventListener('WebChannelMessageToChrome', onChannel);
  window.__aethoneFxReply = function(id, messageId, command, data) {
    var detail = { id: id, message: { messageId: messageId, command: command, data: data } };
    window.dispatchEvent(new CustomEvent('WebChannelMessageToContent', { detail: detail }));
    document.dispatchEvent(new CustomEvent('WebChannelMessageToContent', { detail: detail }));
  };
})();
''';
