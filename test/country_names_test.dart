import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/core/country_names.dart';

/// v4.12 — owner defect: «بخش اسم پرچم کشورها باید اسم کشورها باشه نه کد
/// کشورها». The old 24-entry table fell back to the raw upper-cased code
/// («KP») for the other ~240 flags. This guard keeps the table COMPLETE:
/// every flag artwork committed in design/flags_png must resolve to a real
/// Persian name (never the code fallback).
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
}
