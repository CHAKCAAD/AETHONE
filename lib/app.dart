import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'connection/connection_store.dart';
import 'core/design_tokens.dart';
import 'features/home/home_screen.dart';

/// The AETHONE app shell. Locale: device locale when supported, else Persian
/// (the design language). The onboarding flow (later step) takes over
/// first-run language selection per the prompt annex §7.
class AethoneApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // v4.22 — the language sub-page writes store.appLocale; the shell
    // listens so a change rebuilds MaterialApp with the new locale (null =
    // follow the system, the default).
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return MaterialApp(
          title: 'AETHONE',
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          locale: _locale(store.appLocale),
          supportedLocales: supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(store: store),
        );
      },
    );
  }

  /// The user override → a supported Locale (zh carries the CN script);
  /// null keeps the device locale (MaterialApp resolves it against
  /// [supportedLocales], else Persian — the design language).
  Locale? _locale(String? code) => switch (code) {
        'fa' => const Locale('fa'),
        'en' => const Locale('en'),
        'ru' => const Locale('ru'),
        'zh' => const Locale('zh', 'CN'),
        _ => null,
      };

  ThemeData _theme() {
    const scheme = ColorScheme.dark(
      primary: AethColors.accentConnected,
      error: AethColors.statusDisconnected,
      surface: AethColors.bgScreen,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AethColors.bgScreen,
      fontFamily: 'IRANYekanX',
    );
  }
}
