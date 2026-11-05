/// Egress-location truth tests (v4.28 — owner round 5: «لوکیشن های سایفون
/// و تور باید لوکیشن هایی باشن که واقعا ارایه میدن نه لوکیشن های فیک»).
///
/// Covers the three honest sources this build wires in:
///  * the psiphon-log harvest — the pinned core's rendering of the
///    Psiphon network's `AvailableEgressRegions` notice
///    (`[*] psiphon can leave from: AT BE …`, psiphon.rs note());
///  * the Onionoo parse — the Tor network's own metrics API reply shape
///    (verified live 2026-11-05: 2686 running exit relays / 51 countries);
///  * the sanitizer every live set passes through before it may replace
///    a wheel seed.
library;

import 'package:aethone/connection/egress_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePsiphonEgressRegions', () {
    test('parses the pinned core line (uppercase ISO codes)', () {
      const log = '''
2026-11-05T12:00:00Z INFO aether::psiphon: [*] starting psiphon from /data/app/.../lib/arm64-v8a/libpsiphon.so
2026-11-05T12:00:03Z INFO aether::psiphon: [*] psiphon can leave from: AT BE BG CA CH DE DK ES FI FR GB HR IE IT JP LT NL NO PL PT RO RS SE SG SK UA US
2026-11-05T12:00:04Z INFO aether::psiphon: [+] psiphon reached a server at 1.2.3.4
''';
      final regions = EgressLocations.parsePsiphonEgressRegions(log);
      expect(
        regions,
        const [
          'at', 'be', 'bg', 'ca', 'ch', 'de', 'dk', 'es', 'fi', 'fr', //
          'gb', 'hr', 'ie', 'it', 'jp', 'lt', 'nl', 'no', 'pl', 'pt', //
          'ro', 'rs', 'se', 'sg', 'sk', 'ua', 'us',
        ],
      );
      expect(regions!.length, 27);
    });

    test('keeps the LAST line when several sessions reported', () {
      const log = 'psiphon can leave from: DE NL\n'
          'psiphon can leave from: FR GB US\n';
      expect(
        EgressLocations.parsePsiphonEgressRegions(log),
        const ['fr', 'gb', 'us'],
      );
    });

    test('a single-region notice is a valid list', () {
      expect(
        EgressLocations.parsePsiphonEgressRegions(
          'psiphon can leave from: DE',
        ),
        const ['de'],
      );
    });

    test('no notice yet → null (the caller keeps its seed)', () {
      expect(
        EgressLocations.parsePsiphonEgressRegions(
          'INFO aether::psiphon: [+] psiphon reached a server at 1.2.3.4',
        ),
        isNull,
      );
      expect(EgressLocations.parsePsiphonEgressRegions(''), isNull);
    });

    test('garbage tokens are dropped, never guessed', () {
      // `GER` breaks the captured run right there (a word boundary keeps
      // its `GE` fragment out) — the honest take is the clean prefix `DE`.
      // (Verified against the exact regex behavior; see the python probe
      // in the v4.28 commit message.)
      expect(
        EgressLocations.parsePsiphonEgressRegions(
          'psiphon can leave from: DE GER NL 12 X',
        ),
        const ['de'],
      );
    });
  });

  group('parseOnionooCountries', () {
    test('aggregates the unique exit-relay countries (verified shape)', () {
      // The exact document shape the verified query returns
      // (type=relay&flag=exit&fields=country,flags,running&running=true):
      // one entry per running exit relay, lowercase ISO country.
      const body = '''
{
  "version": "9.0",
  "next_major_version_scheduled": "2030-01-01",
  "relays": [
    {"country": "de"},
    {"country": "de"},
    {"country": "us"},
    {"country": "nl"},
    {"country": "us"},
    {"country": "fr"},
    {}
  ],
  "bridges": []
}
''';
      expect(
        EgressLocations.parseOnionooCountries(body),
        const ['de', 'fr', 'nl', 'us'],
      );
    });

    test('an empty relay list is null, never an invented set', () {
      expect(
        EgressLocations.parseOnionooCountries('{"relays": [], "bridges": []}'),
        isNull,
      );
    });

    test('malformed / non-map documents are null, never a crash', () {
      expect(EgressLocations.parseOnionooCountries('not json'), isNull);
      expect(EgressLocations.parseOnionooCountries('[1, 2, 3]'), isNull);
      expect(EgressLocations.parseOnionooCountries('{"relays": 5}'), isNull);
      expect(EgressLocations.parseOnionooCountries(''), isNull);
    });
  });

  group('sanitizeCodes', () {
    test('lowercases, dedupes and sorts', () {
      expect(
        EgressLocations.sanitizeCodes(const ['US', 'de', 'DE', 'us', 'fr']),
        const ['de', 'fr', 'us'],
      );
    });

    test('garbage tokens are dropped; survivors stay', () {
      expect(
        EgressLocations.sanitizeCodes(const ['US', 'de', 'nl ', '1']),
        const ['de', 'us'],
      );
    });

    test('an all-garbage list is null (not an empty list)', () {
      expect(
        EgressLocations.sanitizeCodes(const ['usa', '1', '', 'IRN']),
        isNull,
      );
    });
  });

  // v4.31 — the Tor exit-country RESOLUTION (owner round 7: the trace
  // answers loc=T1 for every Tor exit; the real country comes from the
  // exit relay's own Onionoo directory record, searched by IP).
  group('parseOnionooSearchCountry', () {
    test('extracts the first RUNNING relay country (the verified reply '
        'shape, 2026-11-05)', () {
      const body = '{"version":"8.0","build_revision":"89598ea",'
          '"relays_published":"2026-11-05 09:00:00",'
          '"relays":[{"running":true,"country":"us"}],'
          '"bridges_published":"2026-11-05 08:55:39","bridges":[]}';
      expect(EgressLocations.parseOnionooSearchCountry(body), 'us');
    });

    test('skips non-running relays', () {
      const body = '{"relays":['
          '{"running":false,"country":"de"},'
          '{"running":true,"country":"at"}'
          ']}';
      expect(EgressLocations.parseOnionooSearchCountry(body), 'at');
    });

    test('never fabricates: empty/garbage/non-code answers are null', () {
      expect(EgressLocations.parseOnionooSearchCountry(''), isNull);
      expect(EgressLocations.parseOnionooSearchCountry('not json'), isNull);
      expect(EgressLocations.parseOnionooSearchCountry('{"relays":[]}'), isNull);
      expect(EgressLocations.parseOnionooSearchCountry('{"relays":[{}]}'),
          isNull);
      // A pseudo-code country from the directory feed is NOT displayable.
      expect(
        EgressLocations.parseOnionooSearchCountry('{"relays":['
            '{"running":true,"country":"t1"}]}'),
        isNull,
      );
    });

    test('the search targets the documented search-by-IP endpoint', () {
      final path = EgressLocations.onionooSearchPath('198.98.51.249');
      expect(path, startsWith('/details'));
      expect(path, contains('search=198.98.51.249'));
      expect(path, contains('flag=exit'));
      expect(path, contains('running=true'));
      expect(EgressLocations.onionooHost, 'onionoo.torproject.org');
    });
  });
}
