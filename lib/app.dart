import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'connection/connection_store.dart';
import 'connection/desktop_window.dart';
import 'connection/platform_engine_adapter.dart';
import 'core/app_theme.dart';
import 'core/design_tokens.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_flow.dart';

/// The AETHONE app shell. Locale: device locale when supported, else Persian
/// (the design language). The first-run wizard (v4.23, «صفحه شروع»)
/// takes over until [ConnectionStore.onboardingComplete].
///
/// v4.34 — LIGHT MODE (owner round 10): the shell owns a 420 ms tween that
/// lerps [AethPal.night] ↔ [AethPal.light] into the process-wide
/// [AethThemeSync.palette] every frame and rebuilds the whole tree, so every
/// surface — Flutter widgets and CustomPaint canvases alike — cross-fades
/// together («تغیر بین دوحالت باید با انیمیشن و به نرمی اتفاق بیفته»).
/// The master animation kill-switch collapses the tween to a jump.
class AethoneApp extends StatefulWidget {
  AethoneApp({super.key, ConnectionStore? store})
      : store = store ?? ConnectionStore();

  final ConnectionStore store;

  static const supportedLocales = [
    Locale('fa'),
    Locale('en'),
    Locale('ru'),
    Locale('zh', 'CN'),
    // v4.42 — tk (Turkmen) is a FIRST-CLASS locale now: the v4.41
    // approach (mapping tk → the English Material locale) silently
    // killed the whole Turkmen table — AppStrings resolves through the
    // MATERIAL locale, so it read 'en' and rendered English no matter
    // what the store held (the owner's report: «زبان ترکمنی اپ کار
    // نمیکنه و به جاش زبان انگلیسی نمایش داده میشه»). tk now rides
    // its own Locale with the three fallback delegates below feeding
    // the framework widgets their English strings.
    Locale('tk'),
  ];

  @override
  State<AethoneApp> createState() => _AethoneAppState();
}

class _AethoneAppState extends State<AethoneApp>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The mode tween: 0.0 = night, 1.0 = light. Driven linearly; the easing
  /// curve is applied when the palette is read (the curve shapes the COLORS,
  /// the controller stays a plain clock — a mid-flight reversal simply
  /// retargets `animateTo` from wherever it is, no snapping).
  late final AnimationController _themeClock;

  /// The mode the clock is currently aimed at (the last one the store
  /// handed us) — a store notification that does not move it is ignored.
  AethThemeMode? _clockTarget;

  /// v4.40 — the AUTO schedule tick (owner round 15: «از ساعت 6 صبح تا 6
  /// عصر حالت بایت لایت مود باشه و از ساعت 6 عصر تا 6 صبح فردا هم نایت
  /// مود»): while the pick is AUTO, one check per 30 s moves the mode at
  /// the 06:00/18:00 boundary through the SAME 420 ms cross-fade a manual
  /// flip takes. A fixed pick keeps the timer idle.
  Timer? _autoThemeTick;
  AethThemePick? _armedForPick;

  static const Duration _themeFade = Duration(milliseconds: 420);

  @override
  void initState() {
    super.initState();
    _themeClock = AnimationController(
      vsync: this,
      value: widget.store.themeMode == AethThemeMode.light ? 1 : 0,
      duration: _themeFade,
    );
    // The cold start renders the persisted mode with NO animation (the
    // restore ran before the first frame — the palette is right from the
    // very first paint, never a flash of the default).
    _applyPalette(_themeClock.value);
    _themeClock.addListener(() => _applyPalette(_themeClock.value));
    widget.store.addListener(_onStoreChanged);
    _clockTarget = widget.store.themeMode;
    _armAutoThemeTick();
    // v1.0.1 — the phone surfaces' quick-connect ask (home-screen widget
    // «اتصال» button / QS tile): the launch intent parked it on the
    // activity; pull it now and again on every resume (the singleTop
    // re-launch path while the app sat in the background).
    WidgetsBinding.instance.addObserver(this);
    unawaited(_consumeQuickConnect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoThemeTick?.cancel();
    widget.store.removeListener(_onStoreChanged);
    _themeClock.dispose();
    super.dispose();
  }

  /// v1.0.1 — the widget/tile connect delegation. The flag is CONSUMED
  /// unconditionally (a wizard-owned first run must not leave an armed
  /// surprise for the next resume); the connect itself runs the store's
  /// normal single-flight path — exactly the in-app button's flow.
  Future<void> _consumeQuickConnect() async {
    final asked = await PlatformEngineAdapter.takeQuickConnect();
    if (!asked) return;
    if (!widget.store.onboardingComplete) return; // consumed, not armed
    unawaited(widget.store.connect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumeQuickConnect());
    }
  }

  /// (Re-)arms the per-minute AUTO check. Armed ONLY on a pick CHANGE —
  /// the store notifies every stats tick (5 s) and a re-arm-per-notify
  /// would reset the 30 s interval forever (the boundary would never
  /// fire).
  void _armAutoThemeTick() {
    final pick = widget.store.themePick;
    if (pick == _armedForPick) return;
    _armedForPick = pick;
    _autoThemeTick?.cancel();
    _autoThemeTick = null;
    if (pick != AethThemePick.auto) return;
    _autoThemeTick = Timer.periodic(const Duration(seconds: 30), (_) {
      widget.store.applyAutoThemeSchedule(DateTime.now());
    });
    // The boundary may have crossed while nobody watched (a suspended
    // laptop, a fresh restore): resolve RIGHT NOW too.
    widget.store.applyAutoThemeSchedule(DateTime.now());
  }

  void _onStoreChanged() {
    final target = widget.store.themeMode;
    // v4.40 — a pick change re-arms the AUTO schedule timer.
    _armAutoThemeTick();
    if (target == _clockTarget) return;
    _clockTarget = target;
    // The master animation kill-switch collapses the cross-fade to a jump
    // (the same decree that freezes every other animated surface).
    if (!widget.store.animationsEnabled) {
      _themeClock
        ..stop()
        ..value = target == AethThemeMode.light ? 1 : 0;
      _applyPalette(_themeClock.value);
      // A value-only move does not tick the listener — apply explicitly.
      setState(() {});
      return;
    }
    _themeClock.animateTo(
      target == AethThemeMode.light ? 1 : 0,
      curve: Curves.linear,
    );
  }

  void _applyPalette(double t) {
    AethThemeSync.palette =
        AethPal.lerp(AethPal.night, AethPal.light, Curves.easeInOut.transform(t));
    // v4.40 — the binary light-ness the protocol-icon variants read: the
    // clock's midpoint is the same moment the colors cross.
    AethThemeSync.light = t > 0.5;
  }

  @override
  Widget build(BuildContext context) {
    // v4.22 — the language sub-page writes store.appLocale; the shell
    // listens so a change rebuilds MaterialApp with the new locale (null =
    // follow the system, the default). v4.34 — the theme clock is merged in
    // so every cross-fade frame rebuilds the tree with the fresh palette.
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, _themeClock]),
      builder: (context, _) {
        return MaterialApp(
          title: 'AETHONE',
          debugShowCheckedModeBanner: false,
          // v4.40 — the root navigator the close-dialog needs (a context
          // that survives every route; see DesktopWindowBridge).
          navigatorKey: appNavigatorKey,
          theme: _theme(),
          locale: _locale(widget.store.appLocale),
          supportedLocales: AethoneApp.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            // v4.42 — the Turkmen seam: each fallback claims ONLY the tk
            // locale and loads the matching English Global* resources,
            // so every framework-owned string keeps rendering while
            // AppStrings resolves the real tk table from the locale.
            _TkMaterialLocalizationsDelegate(),
            _TkWidgetsLocalizationsDelegate(),
            _TkCupertinoLocalizationsDelegate(),
          ],
          home: widget.store.onboardingComplete
              ? HomeScreen(store: widget.store)
              : OnboardingFlow(store: widget.store),
        );
      },
    );
  }

  /// The user override → a supported Locale (zh carries the CN script);
  /// null keeps the device locale (MaterialApp resolves it against
  /// [AethoneApp.supportedLocales], else Persian — the design language).
  /// v4.42 — 'tk' maps onto ITSELF (the v4.23 English mapping was the
  /// Turkmen bug: AppStrings reads the Material locale, saw 'en', and
  /// rendered English forever). The framework's own widgets (tooltips,
  /// text-selection handles) get their English strings from the
  /// [_tkFallbackDelegates] below — flutter_localizations ships no
  /// Turkmen coverage, so the fallback delegates load the English
  /// Global* resources for exactly the tk locale.
  Locale? _locale(String? code) => switch (code) {
        'fa' => const Locale('fa'),
        'en' => const Locale('en'),
        'ru' => const Locale('ru'),
        'zh' => const Locale('zh', 'CN'),
        'tk' => const Locale('tk'),
        _ => null,
      };

  ThemeData _theme() {
    // v4.34 — the Material scaffolding follows the same lerped palette the
    // widgets read (scaffold bg, brightness); the accents never change.
    final light = _themeClock.value > 0.5;
    final scheme = light
        ? const ColorScheme.light(
            primary: AethColors.accentConnected,
            error: AethColors.statusDisconnected,
            surface: Color(0xFFEDEDED), // AethPal.light.bgScreen
          )
        : const ColorScheme.dark(
            primary: AethColors.accentConnected,
            error: AethColors.statusDisconnected,
            surface: Color(0xFF141C16), // AethPal.night.bgScreen
          );
    return ThemeData(
      useMaterial3: true,
      brightness: light ? Brightness.light : Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AethColors.bgScreen,
      fontFamily: 'IRANYekanX',
    );
  }
}

// ---------------------------------------------------------------------------
// v4.42 — the Turkmen fallback delegates: flutter_localizations ships no
// 'tk' coverage, and the v4.41 "map tk → the English Material locale"
// workaround silently killed the whole app-owned Turkmen table (AppStrings
// resolves through the MATERIAL locale, so it read 'en'). With tk as a
// real locale, these three delegates claim exactly the tk locale and load
// the matching ENGLISH Global* resources for the framework widgets — the
// standard recipe for locales the ecosystem does not cover yet.
// ---------------------------------------------------------------------------

class _TkMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _TkMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tk';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_TkMaterialLocalizationsDelegate old) => false;
}

class _TkWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _TkWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tk';

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_TkWidgetsLocalizationsDelegate old) => false;
}

class _TkCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _TkCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tk';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_TkCupertinoLocalizationsDelegate old) => false;
}
