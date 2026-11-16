/// The Firefox VPN sign-in page — TWO methods, the arman-vpn-client
/// pattern (the owner's round 8: «از پروژه arman-vpn-client الگو بگیر»):
///
///  * DIRECT (the DEFAULT, arman's own default sign-in): an email +
///    password FORM. The engine's `--login` password mode runs the
///    whole FxA flow itself — when Mozilla emails the confirmation
///    code the engine asks (`loginNeedsCode`) and the SAME child takes
///    the answer. No WebView, no browser page, no Fastly anti-bot
///    wall: the password never transits anything but the child's
///    stdin pipe, and the accounts that need the browser (Google /
///    Apple sign-ins, no password) are pointed at the second tab.
///
///  * BROWSER (the alternative): the REAL accounts.firefox.com page
///    inside an embedded WebView, bridged by the WebChannel hook
///    (firefox_web_channel.dart; the protocol is Mozilla's). Created
///    LAZILY — switching to this tab is what boots the WebView and its
///    DNS-aware proxy; the direct path never pays for it (the
///    round-5/6 «بسته شدن برنامه» memory pressure had its heaviest
///    page here).
///
/// 1.9.0 — the reference's OWN network posture, end to end: NOTHING is
/// booted for the sign-in. Both methods walk DIRECT on the engine's
/// hardened control plane (the raced DoH resolver — Cloudflare +
/// Google + Quad9 at once with the system fallback and the
/// block-page filter — plus the uTLS Firefox ClientHello), exactly
/// the way arman-vpn-client's core drives its own account requests
/// with no account and the VPN off. The old login carrier (the
/// in-process Aether core booted at screen open) is GONE: it was the
/// memory pressure the owner felt as «بسته شدن برنامه» on top of the
/// WebView, and it never made the sign-in work — the reference
/// project needs no tunnel to sign in, and neither do we now.
///
/// The back gesture during any exchange cancels it cleanly (stdin
/// close → grace → kill; no orphan).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/firefox/firefox_errors.dart';
import '../../../connection/firefox/firefox_protocol.dart';
import '../../../connection/firefox/firefox_web_channel.dart';
import '../../../connection/firefox/firefox_webview_dns_proxy.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import '../home/widgets/hero_logo.dart' show ScanRings;

/// The sign-in methods (the segmented control at the top of the page).
enum _LoginMethod { form, browser }

/// The form's own phases (its half of the status strip).
enum _FormPhase { idle, connecting, submitting, needsCode, verifying, success, failed }

/// The browser tab's phases (the historical strip).
enum _LoginPhase { browsing, exchanging, success, failed }

/// Keeps the digits of a typed or pasted code and drops everything
/// else (spaces, dashes); Persian and Arabic-Indic digits, which a
/// Persian keyboard types, become 0-9 (arman-vpn-client's _CodeDigits,
/// ported verbatim — the emailed codes are digits).
class FirefoxLoginCodeDigits extends TextInputFormatter {
  const FirefoxLoginCodeDigits();

  static String? _digit(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return String.fromCharCode(rune);
    if (rune >= 0x6F0 && rune <= 0x6F9) return '${rune - 0x6F0}';
    if (rune >= 0x660 && rune <= 0x669) return '${rune - 0x660}';
    return null;
  }

  static String _digits(String text) =>
      text.runes.map(_digit).whereType<String>().join();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _digits(newValue.text);
    if (text == newValue.text) return newValue;
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final cursor = _digits(newValue.text.substring(0, end)).length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

class FirefoxLoginScreen extends StatefulWidget {
  const FirefoxLoginScreen({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<FirefoxLoginScreen> createState() => _FirefoxLoginScreenState();
}

class _FirefoxLoginScreenState extends State<FirefoxLoginScreen> {
  // ---- the method pick (the form is the DEFAULT — arman's posture) ----
  _LoginMethod _method = _LoginMethod.form;

  // ---- the form's state ----
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  _FormPhase _formPhase = _FormPhase.idle;
  String? _formError;
  String _codeEmail = '';
  String _codeLastError = '';

  // ---- the browser tab's state (created LAZILY) ----
  final FirefoxWebChannelBridge _bridge = FirefoxWebChannelBridge();
  WebViewController? _controller;
  FirefoxWebViewDnsProxy? _webViewDnsProxy;
  bool _webViewInitializing = true;
  bool _browserCreated = false;
  // 2.0.0 — the main frame's load failed (the honest inline error path:
  // a blocked network no longer reads as a silent blank page).
  bool _pageLoadFailed = false;
  _LoginPhase _phase = _LoginPhase.browsing;
  String? _errorText;
  String _currentUrl = kFirefoxLoginUrl;

  @override
  void initState() {
    super.initState();
    // 1.9.0 — NOTHING boots at screen open (the reference posture): no
    // carrier, no core, no proxy. The form submits direct; the browser
    // tab brings up its own WebView + loopback proxy lazily when the
    // user switches to it. The screen is as light as the reference's.
  }

  @override
  void dispose() {
    // Cancel any in-flight login (either method) and stop the browser
    // tab's proxy if it was ever created.
    unawaited(_teardownLoginNetwork());
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _teardownLoginNetwork() async {
    await widget.store.firefoxLoginCancel();
    await _webViewDnsProxy?.stop();
  }

  // ---- the DIRECT form (the arman default) -----------------------------

  Future<void> _submitForm() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || email.length > 254) {
      setState(() => _formError = AppStrings.of(context).firefoxLoginEmailInvalid);
      return;
    }
    if (password.isEmpty) {
      setState(() => _formError = AppStrings.of(context).firefoxLoginPasswordEmpty);
      return;
    }
    setState(() {
      _formPhase = _FormPhase.submitting;
      _formError = null;
    });
    // 1.9.0 — the reference posture: DIRECT. The engine's own raced
    // resolver + the uTLS Firefox ClientHello carry the walk; nothing
    // is booted and nothing is awaited before the submit.
    final result = await widget.store.firefoxPasswordLogin(email, password);
    if (!mounted) return;
    _handleFormResult(result);
  }

  Future<void> _submitCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _formPhase = _FormPhase.verifying;
      _formError = null;
    });
    final result = await widget.store.firefoxPasswordLoginCode(code);
    if (!mounted) return;
    _handleFormResult(result);
  }

  void _handleFormResult(FirefoxLoginResult result) {
    if (result.isCompleted) {
      setState(() => _formPhase = _FormPhase.success);
      _finishSignIn();
    } else if (result.state == FirefoxLoginState.needsCode) {
      setState(() {
        _formPhase = _FormPhase.needsCode;
        _codeEmail = result.email;
        _codeLastError = result.lastError;
        _code.clear();
      });
    } else if (result.state == FirefoxLoginState.cancelled) {
      // The dispose path's cancel — nothing to render.
    } else {
      setState(() {
        _formPhase = _FormPhase.failed;
        _formError = _failureText(result.failCode);
      });
    }
  }

  /// The shared closing choreography: refresh the account state, land
  /// the remaining-data value, a beat of success, then pop.
  Future<void> _finishSignIn() async {
    await widget.store.refreshFirefoxAccount();
    if (!mounted) return;
    final quotaLanded = widget.store
        .refreshFirefoxQuota()
        .timeout(const Duration(seconds: 12), onTimeout: () => false);
    Timer(const Duration(milliseconds: 1400), () async {
      await quotaLanded;
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  /// The failure text by the CLASSIFIED code only — the granular
  /// password errnos keep their own texts (the arman SignInError
  /// model), the transport classes map through [firefoxErrorText],
  /// and the raw chain is never rendered.
  String _failureText(String failCode) {
    final strings = AppStrings.of(context);
    switch (failCode) {
      case 'noAccount':
        return strings.firefoxLoginNoAccount;
      case 'wrongPassword':
        return strings.firefoxLoginWrongPassword;
      case 'tooManyAttempts':
        return strings.firefoxLoginTooManyAttempts;
      case 'requestBlocked':
        return strings.firefoxLoginRequestBlocked;
      case 'secondaryEmail':
        return strings.firefoxLoginSecondaryEmail;
      case 'invalidEmail':
        return strings.firefoxLoginInvalidEmail;
      case 'unverifiedAccount':
        return strings.firefoxLoginUnverifiedAccount;
      case 'emailCaseInvalid':
        return strings.firefoxLoginEmailCase;
      case 'codeExpired':
        return strings.firefoxLoginCodeExpired;
      case 'codeAttemptsExhausted':
        return strings.firefoxLoginCodeAttempts;
      case 'sessionTokenInvalid':
        return strings.firefoxLoginRejected;
      case 'loginTimeout':
        return strings.firefoxLoginTimeout;
      default:
        return strings.firefoxErrorText(FirefoxErrors.classify(failCode).code);
    }
  }

  // ---- the BROWSER tab (lazy — today's flow, unchanged) ----------------

  void _switchToBrowser() {
    setState(() => _method = _LoginMethod.browser);
    if (!_browserCreated) {
      _browserCreated = true;
      unawaited(_initializeLoginWebView(_webViewDnsProxy = FirefoxWebViewDnsProxy()));
    }
  }

  /// 2.0.0 — the browser tab's honest retry: tear the WebView and its
  /// proxy down and bring them up again (a blocked first load is not a
  /// permanent state of the tab).
  Future<void> _retryBrowser() async {
    await _webViewDnsProxy?.stop();
    _webViewDnsProxy = FirefoxWebViewDnsProxy();
    if (!mounted) return;
    setState(() {
      _controller = null;
      _webViewInitializing = true;
      _pageLoadFailed = false;
      _phase = _LoginPhase.browsing;
      _errorText = null;
    });
    unawaited(_initializeLoginWebView(_webViewDnsProxy!));
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
      _finishSignIn();
    } else if (result.state == FirefoxLoginState.cancelled) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _phase = _LoginPhase.failed;
        _errorText = _failureText(result.failCode);
      });
    }
  }

  /// Brings up the selected DNS resolver and the loopback CONNECT proxy
  /// BEFORE creating/loading Chromium's WebView (the reference's
  /// sign-in proxy: the core's own resolver, no account, no tunnel).
  /// The AndroidX callback is awaited by [FirefoxWebViewDnsProxy.start],
  /// so the first navigation cannot race the process-scoped WebView
  /// proxy installation.
  Future<void> _initializeLoginWebView(FirefoxWebViewDnsProxy proxy) async {
    try {
      await widget.store.loadFirefoxDnsSettings();
      await proxy.start(
        Map<String, dynamic>.from(widget.store.firefoxDnsConfig),
        upstreamSocks: null,
      );
      if (!mounted) {
        await proxy.stop();
        return;
      }

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(
        firefoxLoginUserAgent(Platform.operatingSystemVersion),
      );
      await controller.addJavaScriptChannel(
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
      );
      await controller.setNavigationDelegate(
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
            // 2.0.0 — a new navigation resets the load-failure mark; the
            // honest error only sticks while the failure is the current
            // state of the page.
            if (_pageLoadFailed) {
              setState(() => _pageLoadFailed = false);
            }
            _controller?.runJavaScript(FirefoxWebChannelBridge.hookScript);
          },
          onPageFinished: (url) {
            _currentUrl = url;
            _controller?.runJavaScript(FirefoxWebChannelBridge.hookScript);
          },
          // 2.0.0 — the main frame's failure surfaces inline (the
          // owner's round-10 report: without a VPN the tab "never
          // opens" — a blank WebView with no explanation). Sub-frame
          // errors are ignored (an ad or a font failing must not read
          // as the page failing).
          onWebResourceError: (error) {
            // isForMainFrame is nullable on some platforms; null means
            // unknown — treat only an explicit true as the page failing.
            final mainFrame = error.isForMainFrame ?? false;
            if (mainFrame && mounted && _controller != null) {
              setState(() => _pageLoadFailed = true);
            }
          },
        ),
      );

      if (!mounted) {
        await proxy.stop();
        return;
      }
      setState(() {
        _controller = controller;
        _webViewInitializing = false;
      });
      await controller.loadRequest(Uri.parse(kFirefoxLoginUrl));
    } catch (_) {
      await proxy.stop();
      if (!mounted) return;
      setState(() {
        _webViewInitializing = false;
        _phase = _LoginPhase.failed;
        _errorText = AppStrings.of(context).firefoxLoginUnavailable;
      });
    }
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

  // ---- the page ---------------------------------------------------------

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
                        _method == _LoginMethod.form
                            ? strings.firefoxLoginSubtitleForm
                            : strings.firefoxLoginSubtitle,
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
            // ---- The method picker (the form is the DEFAULT) ----
            SizedBox(height: 6 * s),
            _methodPicker(strings, s),
            // ---- The status strip ----
            SizedBox(height: 6 * s),
            _statusStrip(strings, s),
            // ---- The page body ----
            Expanded(
              child: _method == _LoginMethod.form
                  ? _formPane(strings, s)
                  : _browserPane(strings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodPicker(AppStrings strings, double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * s),
      child: Row(
        children: [
          Expanded(
            child: _methodChip(
              strings.firefoxLoginMethodForm,
              _LoginMethod.form,
              s,
            ),
          ),
          SizedBox(width: 8 * s),
          Expanded(
            child: _methodChip(
              strings.firefoxLoginMethodBrowser,
              _LoginMethod.browser,
              s,
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodChip(String label, _LoginMethod method, double s) {
    final selected = _method == method;
    return GestureDetector(
      onTap: () {
        if (method == _LoginMethod.browser) {
          _switchToBrowser();
        } else {
          setState(() => _method = _LoginMethod.form);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: 9 * s),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AethColors.accentConnected : AethColors.sheetDescCard,
          borderRadius: BorderRadius.circular(12 * s),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12 * s,
            color: selected ? AethColors.bgScreen : AethColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _statusStrip(AppStrings strings, double s) {
    final (label, color) = _method == _LoginMethod.form
        ? _formStrip(strings)
        : _browserStrip(strings);
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

  (String, Color) _formStrip(AppStrings strings) {
    return switch (_formPhase) {
      _FormPhase.idle => (strings.firefoxLoginFormHint, AethColors.textSecondary),
      _FormPhase.submitting => (strings.firefoxLoginSubmitting, AethColors.accentConnected),
      _FormPhase.needsCode => (
          strings.firefoxLoginCodeSent(_codeEmail),
          AethColors.accentConnected
        ),
      _FormPhase.verifying => (strings.firefoxLoginCodeVerifying, AethColors.accentConnected),
      _FormPhase.success => (strings.firefoxLoginSuccess, AethColors.accentConnected),
      _FormPhase.failed => (_formError ?? strings.firefoxLoginFailed, AethColors.statusDisconnected),
      _FormPhase.connecting => (strings.statusConnecting, AethColors.accentConnected),
    };
  }

  (String, Color) _browserStrip(AppStrings strings) {
    final (label, color) = switch (_phase) {
      // While the WebView and its loopback proxy come up the strip says
      // what is really happening: connecting.
      _LoginPhase.browsing => _webViewInitializing
          ? (strings.statusConnecting, AethColors.accentConnected)
          : (strings.firefoxLoginWaiting, AethColors.textSecondary),
      _LoginPhase.exchanging => (strings.firefoxLoginExchanging, AethColors.accentConnected),
      _LoginPhase.success => (strings.firefoxLoginSuccess, AethColors.accentConnected),
      _LoginPhase.failed => (_errorText ?? strings.firefoxLoginFailed, AethColors.statusDisconnected),
    };
    return (label, color);
  }

  // ---- the form pane ----------------------------------------------------

  Widget _formPane(AppStrings strings, double s) {
    if (_formPhase == _FormPhase.success) {
      return _successPane(strings, s);
    }
    final busy = _formPhase == _FormPhase.submitting ||
        _formPhase == _FormPhase.verifying;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 14 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_formPhase == _FormPhase.needsCode) ...[
            _codeCard(strings, s),
          ] else ...[
            _loginField(
              strings: strings,
              s: s,
              label: strings.firefoxLoginEmail,
              controller: _email,
              focusNode: _emailFocus,
              keyId: 'firefox-login-email',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username,
              ],
            ),
            SizedBox(height: 12 * s),
            _loginField(
              strings: strings,
              s: s,
              label: strings.firefoxLoginPassword,
              controller: _password,
              focusNode: _passwordFocus,
              keyId: 'firefox-login-password',
              obscure: _obscure,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submitForm(),
              trailing: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20 * s,
                  color: AethColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            SizedBox(height: 14 * s),
          ],
          if (_formError != null) ...[
            _errorBox(strings, s, _formError!),
            SizedBox(height: 12 * s),
          ],
          _primaryButton(
            s: s,
            label: _formPhase == _FormPhase.needsCode
                ? strings.firefoxLoginCodeVerify
                : strings.firefoxLoginSubmit,
            busy: busy,
            onTap: _formPhase == _FormPhase.needsCode ? _submitCode : _submitForm,
          ),
          SizedBox(height: 10 * s),
          Text(
            _formPhase == _FormPhase.needsCode
                ? strings.firefoxLoginFormHint
                : strings.firefoxLoginBrowserHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w400,
              fontSize: 10.5 * s,
              height: 1.6,
              color: AethColors.textSecondary,
            ),
          ),
          if (_formPhase == _FormPhase.needsCode) ...[
            SizedBox(height: 6 * s),
            GestureDetector(
              onTap: () => setState(() {
                _formPhase = _FormPhase.idle;
                _formError = null;
                _codeLastError = '';
                _code.clear();
              }),
              child: Text(
                strings.firefoxLoginStartOver,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w500,
                  fontSize: 10.5 * s,
                  color: AethColors.accentConnected,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _codeCard(AppStrings strings, double s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _loginField(
          strings: strings,
          s: s,
          label: strings.firefoxLoginCodeLabel,
          controller: _code,
          keyId: 'firefox-login-code',
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: const [FirefoxLoginCodeDigits()],
          textAlign: TextAlign.center,
          letterSpacing: 6,
          autofocusCode: true,
          onSubmitted: (_) => _submitCode(),
        ),
        if (_codeLastError.isNotEmpty) ...[
          SizedBox(height: 10 * s),
          _errorBox(strings, s, _codeLastText(strings)),
        ],
      ],
    );
  }

  String _codeLastText(AppStrings strings) => switch (_codeLastError) {
        'wrongCode' => strings.firefoxLoginWrongCode,
        'badCodeInput' => strings.firefoxLoginWrongCode,
        'network' => strings.firefoxLoginNetworkRetry,
        _ => strings.firefoxLoginWrongCode,
      };

  Widget _loginField({
    required AppStrings strings,
    required double s,
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    String? keyId,
    bool obscure = false,
    Widget? trailing,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    TextAlign? textAlign,
    double? letterSpacing,
    bool autofocusCode = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w600,
              fontSize: 12 * s,
              color: AethColors.textPrimary,
            ),
          ),
          SizedBox(height: 8 * s),
          Directionality(
            // The credentials are typed LEFT-TO-RIGHT, also in Persian
            // (arman's rule — an RTL password field mangles input).
            textDirection: TextDirection.ltr,
            child: TextField(
              key: keyId == null ? null : ValueKey('field-$keyId'),
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              enableSuggestions: !obscure,
              autocorrect: false,
              autofocus: autofocusCode,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              inputFormatters: inputFormatters,
              textAlign: textAlign ?? TextAlign.start,
              onSubmitted: onSubmitted,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w400,
                fontSize: 13 * s,
                letterSpacing: letterSpacing,
                color: AethColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w400,
                  fontSize: 12 * s,
                  color: AethColors.textSecondary,
                ),
                suffixIcon: trailing,
                filled: true,
                fillColor: AethColors.sheetDescCard,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12 * s,
                  vertical: 10 * s,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12 * s),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12 * s),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12 * s),
                  borderSide: const BorderSide(color: AethColors.accentConnected),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required double s,
    required String label,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(vertical: 12 * s),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: busy ? AethColors.accentConnected : AethColors.accentConnected,
          borderRadius: BorderRadius.circular(12 * s),
        ),
        child: busy
            ? SizedBox(
                width: 20 * s,
                height: 20 * s,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w600,
                  fontSize: 13 * s,
                  color: AethColors.bgScreen,
                ),
              ),
      ),
    );
  }

  Widget _errorBox(AppStrings strings, double s, String message) {
    return Container(
      padding: EdgeInsets.all(10 * s),
      decoration: BoxDecoration(
        color: AethColors.statusDisconnected.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10 * s),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: 'IRANYekanX',
          fontWeight: FontWeight.w500,
          fontSize: 11.5 * s,
          height: 1.5,
          color: AethColors.statusDisconnected,
        ),
      ),
    );
  }

  // ---- the browser pane (today's, unchanged) ----------------------------

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

  Widget _browserPane(AppStrings strings) {
    final controller = _controller;
    if (controller != null) {
      // 2.0.0 — a failed main-frame load keeps the WebView (Chromium's
      // own error page is honest) but gains an in-pane retry bar, so a
      // blocked network never strands the tab.
      if (_pageLoadFailed) {
        return Stack(
          children: [
            WebViewWidget(controller: controller),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: AethColors.bgScreen,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.firefoxBrowserTabFailed,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: AethColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: _retryBrowser,
                      icon: const Icon(Icons.refresh,
                          size: 16, color: AethColors.accentConnected),
                      label: Text(
                        strings.firefoxBrowserTabRetry,
                        style: const TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: AethColors.accentConnected,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return WebViewWidget(controller: controller);
    }
    // 2.0.0 — the honest message pane (the owner's round-10 report:
    // «مرورگر اصلاً باز نمی‌شه»): while the WebView and its proxy come
    // up the pane SHOWS its loading; a failed load (or no WebView
    // platform) shows the failure, a retry button, and the honest hint
    // that this method needs an unblocked network — never a blank
    // silent page.
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final loading = _webViewInitializing && Platform.isAndroid;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 28 * s),
      child: Column(
        children: [
          SizedBox(height: 24 * s),
          if (loading) ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: ScanRings(
                  color: AethColors.accentConnected, size: 28),
            ),
            SizedBox(height: 14 * s),
            Text(
              strings.firefoxBrowserTabLoading,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AethColors.textPrimary,
              ),
            ),
          ] else ...[
            Icon(
              Icons.public_off_outlined,
              size: 30 * s,
              color: AethColors.statusDisconnected,
            ),
            SizedBox(height: 12 * s),
            Text(
              _errorText ?? strings.firefoxBrowserTabFailed,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AethColors.textPrimary,
              ),
            ),
            SizedBox(height: 14 * s),
            // The retry: bring the WebView and its proxy up again.
            TextButton.icon(
              onPressed: _retryBrowser,
              icon: Icon(Icons.refresh,
                  size: 18 * s, color: AethColors.accentConnected),
              label: Text(
                strings.firefoxBrowserTabRetry,
                style: const TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AethColors.accentConnected,
                ),
              ),
            ),
          ],
          SizedBox(height: 18 * s),
          Text(
            strings.firefoxBrowserTabHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w400,
              fontSize: 11,
              color: AethColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
