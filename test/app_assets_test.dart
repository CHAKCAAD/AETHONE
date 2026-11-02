import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:aethone/l10n/app_strings.dart';

/// Every asset the manifest references must exist in the repository — this is
/// the guard that keeps the app honest about using ONLY the committed design
/// package (owner rule). Runs on the CI checkout where the whole repo exists.
void main() {
  test('every referenced asset exists in the repo', () {
    final missing = <String>[];
    for (final path in AppAssets.allReferenced) {
      if (!File(path).existsSync()) missing.add(path);
    }
    expect(missing, isEmpty, reason: 'missing assets: $missing');
  });

  test('every referenced asset is BUNDLED (declared in pubspec)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The filesystem check above passes even when an asset is missing from
    // pubspec.yaml — the file exists but never ships, and the app silently
    // renders nothing (the v4.11 Off.svg/Activity 4.svg/Right 2.svg bug).
    // rootBundle fails loudly for anything not declared.
    final notBundled = <String>[];
    for (final path in AppAssets.allReferenced) {
      try {
        await rootBundle.load(path);
      } catch (_) {
        notBundled.add(path);
      }
    }
    expect(
      notBundled,
      isEmpty,
      reason: 'assets missing from the bundle (pubspec): $notBundled',
    );
  });

  test('flag helper resolves existing files', () {
    for (final code in ['ir', 'tm', 'ru', 'cn', 'de', 'us', 'fr']) {
      expect(
        File(AppAssets.flag(code)).existsSync(),
        isTrue,
        reason: 'flag $code',
      );
    }
  });

  test(
    'all five UI languages resolve strings (tk documented to fall back)',
    () {
      for (final lang in ['fa', 'en', 'ru', 'zh', 'tk']) {
        final s = AppStrings.forLocale(lang);
        expect(s.statusConnected, isNotEmpty);
        expect(s.statusDisconnected, isNotEmpty);
        expect(s.protocol, isNotEmpty);
      }
    },
  );

  test('fa strings are the exact reference-screen texts', () {
    final fa = AppStrings.forLocale('fa');
    expect(fa.statusDisconnected, 'غیرفعال');
    expect(fa.statusConnected, 'متصل');
    expect(fa.offline, 'آفلاین');
    expect(fa.protocol, 'پروتکل');
  });

  test('ping format matches the reference (146 ms)', () {
    expect(AppStrings.forLocale('fa').pingMs(146), '146 ms');
  });
}
