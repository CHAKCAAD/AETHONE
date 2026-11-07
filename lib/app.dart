import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'connection/connection_store.dart';
import 'connection/desktop_window.dart';
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
    // tk joins when its Material-localizations coverage is handled
    // (onboarding step) — AppStrings already carries tk→en fallback.
  ];

  @override
  State<AethoneApp> createState() => _AethoneAppState();
}

class _AethoneAppState extends State<AethoneApp>
    with SingleTickerProviderStateMixin {
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
  }

  @override
  void dispose() {
    _autoThemeTick?.cancel();
    widget.store.removeListener(_onStoreChanged);
    _themeClock.dispose();
    super.dispose();
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
  /// v4.23 — 'tk' (the wizard's Turkmenistan tile) maps onto the English
  /// Material locale: flutter_localizations has no Turkmen coverage, and
  /// AppStrings' tk table is the documented en fallback. The store keeps
  /// the raw 'tk' so both language pages show the pick as selected.
  Locale? _locale(String? code) => switch (code) {
        'fa' => const Locale('fa'),
        'en' => const Locale('en'),
        'ru' => const Locale('ru'),
        'zh' => const Locale('zh', 'CN'),
        'tk' => const Locale('en'),
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
