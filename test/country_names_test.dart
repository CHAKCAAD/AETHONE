import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/core/country_names.dart';

/// v4.12 — owner defect: «بخش اسم پرچم کشورها باید اسم کشورها باشه نه کد
/// کشورها». The old 24-entry table fell back to the raw upper-cased code
/// («KP») for the other ~240 flags. This guard keeps the table COMPLETE:
/// every flag artwork committed in design/flags_png must resolve to a real
/// Persian name (never the code fallback).
///
/// v4.46 — the names are now LOCALE-AWARE (owner decree: the location
/// header used to read Persian in every language). The fa table is the
/// owner's hand-written map, carried over verbatim; en/ru/zh/tk come from
/// CLDR. The guards below lock BOTH halves: the fa completeness (no code
/// fallback anywhere) and the per-language resolution.
void main() {
  final flagDir = Directory('design/flags_png');
  final codes = flagDir.existsSync()
      ? flagDir
            .listSync()
            .whereType<File>()
            .map((f) {
              final name = f.uri.pathSegments.last;
              return name.endsWith('.png')
                  ? name.substring(0, name.length - 4)
                  : null;
            })
            .whereType<String>()
            .toList()
      : <String>[];
  codes.sort();

  test('flag asset folder is present with the full artwork set', () {
    expect(
      codes.length,
      greaterThanOrEqualTo(266),
      reason: 'the owner flag pack ships 266 artworks',
    );
  });

  test(
    'EVERY committed flag code has a real Persian name (no code fallback)',
    () {
      final missing = <String>[];
      for (final code in codes) {
        final name = countryName(code);
        if (name == null || name == code.toUpperCase()) missing.add(code);
      }
      expect(
        missing,
        isEmpty,
        reason: 'codes still showing as raw codes: $missing',
      );
    },
  );

  test('spot checks: the names the owner first sees', () {
    expect(countryName('ir'), 'ایران');
    expect(countryName('de'), 'آلمان');
    expect(countryName('us'), 'آمریکا');
    expect(countryName('gb'), 'بریتانیا');
    expect(countryName('gb-eng'), 'انگلستان');
    expect(countryName('kp'), 'کره شمالی');
    expect(countryName('xk'), 'کوزوو');
    expect(countryName(null), isNull);
    // v4.21 — the AUTO sentinel of the family location wheels.
    expect(countryName('auto'), 'خودکار');
  });

  test('v4.46 — the names follow the app language (CLDR)', () {
    // English
    expect(countryName('ir', locale: 'en'), 'Iran');
    expect(countryName('de', locale: 'en'), 'Germany');
    expect(countryName('us', locale: 'en'), 'United States');
    expect(countryName('tm', locale: 'en'), 'Turkmenistan');
    expect(countryName('auto', locale: 'en'), 'Automatic');
    // Russian
    expect(countryName('ir', locale: 'ru'), 'Иран');
    expect(countryName('de', locale: 'ru'), 'Германия');
    expect(countryName('auto', locale: 'ru'), 'Автоматически');
    // Chinese (the app's zh_CN locale)
    expect(countryName('ir', locale: 'zh'), '伊朗');
    expect(countryName('de', locale: 'zh'), '德国');
    expect(countryName('auto', locale: 'zh'), '自动');
    // Turkmen
    expect(countryName('ir', locale: 'tk'), 'Eýran');
    expect(countryName('tm', locale: 'tk'), 'Türkmenistan');
    expect(countryName('auto', locale: 'tk'), 'Awtomatiki');
    // The subdivision flags localize too (not only in Persian).
    expect(countryName('gb-eng', locale: 'en'), 'England');
    expect(countryName('gb-eng', locale: 'ru'), 'Англия');
  });

  test('v4.46 — unknown languages and codes resolve honestly', () {
    // An unmapped locale resolves the ENGLISH table (the motion line's
    // round-23 rule); a missing code falls back to the upper-cased code.
    expect(countryName('ir', locale: 'zz'), 'Iran');
    expect(countryName('ir', locale: 'en'), isNot('ایران'));
    expect(countryName('qq'), 'QQ');
    expect(countryName('qq', locale: 'en'), 'QQ');
  });
}
