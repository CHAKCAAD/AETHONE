// v1.0.2 — the Lantern location catalog the sidecar reports: every country
// Lantern ever announced (`locations`) joins the live servers' countries.
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/connection/platform_engine_adapter.dart';

void main() {
  test('catalog + live servers merge into one sorted lowercase set', () {
    final reply = <String, Object?>{
      'ok': true,
      'data': {
        'servers': [
          {'tag': 'a', 'country_code': 'NL'},
          {'tag': 'b', 'country_code': 'DE'},
        ],
        'locations': [
          {'country': 'Japan', 'country_code': 'JP', 'assigned': false},
          {'country': 'Germany', 'country_code': 'DE', 'assigned': true},
          {'country': 'bogus', 'country_code': 'XYZ'},
        ],
      },
    };
    expect(PlatformEngineAdapter.lanternCountriesOf(reply), ['de', 'jp', 'nl']);
  });

  test('a missing or malformed reply yields nothing', () {
    expect(PlatformEngineAdapter.lanternCountriesOf(null), isEmpty);
    expect(
      PlatformEngineAdapter.lanternCountriesOf({'data': 'x'}),
      isEmpty,
    );
  });
}
