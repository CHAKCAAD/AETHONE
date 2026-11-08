/// The Firefox VPN sign-in page (Phase 2): the REAL accounts.firefox.com
/// page (context=fx_desktop_v3) inside an embedded WebView, bridged to
/// the app by the WebChannel hook (firefox_web_channel.dart — adapted
/// from FoxyVPN's MIT BrowserLoginScreen; the protocol is Mozilla's).
///
/// Flow: the user signs in on MOZILLA'S OWN PAGE (the password never
/// transits AETHONE code) → the page's `fxaccounts:login` WebChannel
/// message hands the 64-hex session token to the bridge → the engine's
/// `--login` role exchanges it for the same-account OAuth pair (the
/// token travels ONLY on the child's stdin pipe) → the pair lands in the
/// Keystore vault → the WebView's cookies are cleared (the browser
/// session dies locally) → the page pops back to the Firefox settings
/// page with the account signed in.
///
/// Non-Mozilla links open in the external browser (the WebView stays on
/// Mozilla properties only). The back gesture during the exchange
/// cancels it cleanly (stdin close → grace → kill; no orphan).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/firefox/firefox_protocol.dart';
import '../../../connection/firefox/firefox_web_channel.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';

/// The login screen's phases (its own status strip under the top bar).
enum _LoginPhase { browsing, exchanging, success, failed }

class FirefoxLoginScreen extends StatefulWidget {
  const FirefoxLoginScreen({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<FirefoxLoginScreen> createState() => _FirefoxLoginScreenState();
}

class _FirefoxLoginScreenState extends State<FirefoxLoginScreen> {
  final FirefoxWebChannelBridge _bridge = FirefoxWebChannelBridge();
  WebViewController? _controller;
  _LoginPhase _phase = _LoginPhase.browsing;
  String? _errorText;
  String _currentUrl = kFirefoxLoginUrl;

  @override
  void dispose() {
    // A dismissal mid-exchange cancels the engine child (stdin close →
    // grace → kill) — no orphan survives the dismissed page.
    unawaited(widget.store.firefoxLoginCancel());
    super.dispose();
  }

  void _onSessionToken(String token) async {
    if (_phase == _LoginPhase.exchanging || _phase == _LoginPhase.success) {
      return;
    }
    setState(() => _phase = _LoginPhase.exchanging);
    final result = await widget.store.firefoxCompleteLogin(token);
    if (!mounted) return;
    if (result.isCompleted) {
      // Kill the browser session locally: the WebView's cookies (which
      // hold the sign-in session) are wiped after the pair is vaulted.
      try {
        await WebViewCookieManager().clearCookies();
      } catch (_) {
        // best-effort hygiene; the pair is already vaulted
      }
      await widget.store.refreshFirefoxAccount();
      if (!mounted) return;
      setState(() => _phase = _LoginPhase.success);
      // A beat of success, then back to the settings page.
      Timer(const Duration(milliseconds: 1400), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else if (result.state == FirefoxLoginState.cancelled) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _phase = _LoginPhase.failed;
        _errorText = _failureText(result.failCode, result.message);
      });
    }
  }

  String _failureText(String failCode, String message) {
    final strings = AppStrings.of(context);
    switch (failCode) {
      case 'sessionRejected':
        return strings.firefoxLoginRejected;
      case 'loginTimeout':
        return strings.firefoxLoginTimeout;
      case 'sessionTokenInvalid':
        return strings.firefoxLoginRejected;
      default:
        return '${strings.firefoxLoginFailed}: $failCode';
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Scaffold(
      backgroundColor: AethColors.bgScreen,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- The top bar (back + title + subtitle) ----
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back,
                      color: AethColors.textPrimary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.firefoxLoginTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AethColors.textPrimary,
                        ),
                      ),
                      Text(
                        strings.firefoxLoginSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w400,
                          fontSize: 11,
                          color: AethColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16 * s),
              ],
            ),
            // ---- The status strip ----
            SizedBox(height: 6 * s),
            _statusStrip(strings, s),
            // ---- The page ----
            Expanded(
              child: _phase == _LoginPhase.success
                  ? _successPane(strings, s)
                  : _webViewPane(strings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusStrip(AppStrings strings, double s) {
    final (label, color) = switch (_phase) {
      _LoginPhase.browsing => (strings.firefoxLoginWaiting, AethColors.textSecondary),
      _LoginPhase.exchanging => (strings.firefoxLoginExchanging, AethColors.accentConnected),
      _LoginPhase.success => (strings.firefoxLoginSuccess, AethColors.accentConnected),
      _LoginPhase.failed => (_errorText ?? strings.firefoxLoginFailed, AethColors.statusDisconnected),
    };
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 4 * s),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'IRANYekanX',
          fontWeight: FontWeight.w500,
          fontSize: 11 * s,
          height: 1.4,
          color: color,
        ),
      ),
    );
  }

  Widget _successPane(AppStrings strings, double s) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64 * s, color: AethColors.accentConnected),
          SizedBox(height: 12 * s),
          Text(
            strings.firefoxLoginSuccess,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w600,
              fontSize: 15 * s,
              color: AethColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _webViewPane(AppStrings strings) {
    final controller = _controller;
    if (controller != null) {
      return WebViewWidget(controller: controller);
    }
    // Honest: no WebView platform here (desktop builds, tests, web) —
    // never a fake page. Desktop keeps the phase-1 controlled-injection
    // path for the owner's real session pair.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          strings.firefoxLoginUnavailable,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w500,
            fontSize: 13,
            color: AethColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // The WebView exists on Android (the shipping surface). Desktop
    // builds and the test host render the honest unavailable pane — the
    // login engine itself would also honestly fail (engineNotWired
    // default) on hosts without the firefox engine.
    if (!Platform.isAndroid) {
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(firefoxLoginUserAgent(Platform.operatingSystemVersion))
      ..addJavaScriptChannel(
        'aethoneFxChannel',
        onMessageReceived: (message) {
          final result = _bridge.handle(message.message, _currentUrl);
          final reply = result.replyScript;
          if (reply != null) {
            _controller?.runJavaScript(reply);
          }
          final token = result.sessionToken;
          if (token != null) {
            _onSessionToken(token);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            final host = uri?.host.toLowerCase() ?? '';
            final isMozilla = host == 'accounts.firefox.com' ||
                host.endsWith('.firefox.com') ||
                host == 'mozilla.org' ||
                host.endsWith('.mozilla.org');
            if (isMozilla) {
              return NavigationDecision.navigate;
            }
            // Everything else leaves the app (stays Mozilla-only here).
            final launched = await _launchExternal(request.url);
            if (!launched && mounted) {
              setState(() => _phase = _LoginPhase.failed);
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            _currentUrl = url;
            _controller?.runJavaScript(FirefoxWebChannelBridge.hookScript);
          },
          onPageFinished: (url) {
            _currentUrl = url;
            _controller?.runJavaScript(FirefoxWebChannelBridge.hookScript);
          },
        ),
      )
      ..loadRequest(Uri.parse(kFirefoxLoginUrl));
    _controller = controller;
  }

  Future<bool> _launchExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
