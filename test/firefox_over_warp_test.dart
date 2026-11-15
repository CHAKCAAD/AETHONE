import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/connection/core_settings.dart';
import 'package:aethone/connection/firefox/firefox_protocol.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/l10n/app_strings.dart';

void main() {
  group('Firefox over WARP settings', () {
    test('defaults the Aether carrier to WireGuard and persists the choice', () {
      final defaults = CoreSettings();
      expect(defaults.firefoxLegProtocol, AetherLegProtocol.wireguard);

      defaults.firefoxLegProtocol = AetherLegProtocol.mim;
      final restored = CoreSettings.fromJson(defaults.toJson());
      expect(restored.firefoxLegProtocol, AetherLegProtocol.mim);
    });

    test('maps every selectable carrier to its Aether CLI protocol', () {
      final expected = <AetherLegProtocol, List<String>>{
        AetherLegProtocol.wireguard: ['--protocol', 'wg'],
        AetherLegProtocol.masque: ['--protocol', 'masque'],
        AetherLegProtocol.gool: ['--protocol', 'gool'],
        AetherLegProtocol.goolClassic: [
          '--protocol',
          'gool',
          '--gool-classic',
        ],
        AetherLegProtocol.mim: ['--protocol', 'mim'],
      };

      for (final entry in expected.entries) {
        final args = AetherArguments.build(
          protocol: AetherArguments.legProtocolId(entry.key),
          filesDir: '/tmp/aethone-test',
          nativeLibraryDir: '/tmp/aethone-test/lib',
          core: CoreSettings(),
        );
        final index = args.indexOf('--protocol');
        expect(index, greaterThanOrEqualTo(0));
        expect(args.sublist(index, index + entry.value.length), entry.value);
        expect(args, isNot(contains('--tor')));
        expect(args, isNot(contains('--psiphon')));
      }
    });

    test('sends the selected loopback carrier in the Firefox engine config', () {
      const config = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'access', refreshToken: 'refresh'),
        upstreamSocks: 'socks5://127.0.0.1:1819',
      );
      expect(config.toJson()['upstreamSocks'], 'socks5://127.0.0.1:1819');
    });

    test('v1.5.0: the carrier-mode pick defaults to over-WARP, '
        'persists and migrates (the direct mode)', () {
      // The standing «دیفالت اور وارپ» decree survives the round trip.
      final defaults = CoreSettings();
      expect(defaults.firefoxCarrierMode, FirefoxCarrierMode.overWarp);

      defaults.firefoxCarrierMode = FirefoxCarrierMode.direct;
      final restored = CoreSettings.fromJson(defaults.toJson());
      expect(restored.firefoxCarrierMode, FirefoxCarrierMode.direct);

      // A legacy blob (versioned, pre-round-3: no carrierMode field)
      // migrates to the over-WARP default; its own leg pick survives.
      final legacy = CoreSettings.fromJson({
        'v': 1,
        'firefoxLegProtocol': 'masque',
      });
      expect(legacy.firefoxCarrierMode, FirefoxCarrierMode.overWarp);
      expect(legacy.firefoxLegProtocol, AetherLegProtocol.masque);
    });

    test('a carrier-less config keeps the legacy direct shape '
        '(no seam keys — the engine stays on its 1.2.0/1.5.0 path)', () {
      const config = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'access'),
      );
      final blob = config.toJson();
      expect(blob.containsKey('upstreamSocks'), isFalse);
      expect(blob.containsKey('dataPlaneDirect'), isFalse);
      expect(blob['dns'], {'mode': 'system'});
    });

    test('v1.6.0: the DIRECT mode sends the carrier AND the direct-data '
        'flag (the initial stages ride the Aether carrier, then the data '
        'connection dials the Fastly edge itself — arman\'s relay posture)',
        () {
      const config = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'access'),
        upstreamSocks: 'socks5://127.0.0.1:1819',
        dataPlaneDirect: true,
      );
      final blob = config.toJson();
      expect(blob['upstreamSocks'], 'socks5://127.0.0.1:1819');
      expect(blob['dataPlaneDirect'], isTrue);
    });

    test('v1.6.0: the over-WARP mode carries the data plane too '
        '(dataPlaneDirect stays absent from the wire)', () {
      const config = FirefoxEngineConfig(
        socksListen: '127.0.0.1:1822',
        auth: FirefoxSessionAuth(accessToken: 'access'),
        upstreamSocks: 'socks5://127.0.0.1:1819',
      );
      final blob = config.toJson();
      expect(blob['upstreamSocks'], 'socks5://127.0.0.1:1819');
      expect(blob.containsKey('dataPlaneDirect'), isFalse);
    });

    test('v1.5.0: the mode strings exist in each supported locale', () {
      for (final locale in ['fa', 'en', 'ru', 'zh', 'tk']) {
        final strings = AppStrings.forLocale(locale);
        expect(strings.secFirefoxMode, isNotEmpty);
        expect(strings.firefoxModeOverWarp, isNotEmpty);
        expect(strings.firefoxModeDirect, isNotEmpty);
        expect(strings.firefoxModeOverWarpDesc, isNotEmpty);
        expect(strings.firefoxModeDirectDesc, isNotEmpty);
        expect(strings.firefoxTransportDirectDesc, isNotEmpty);
      }
    });

    test('provides the carrier description in each supported locale', () {
      for (final locale in ['fa', 'en', 'ru', 'zh', 'tk']) {
        final strings = AppStrings.forLocale(locale);
        expect(strings.secFirefoxCarrier, isNotEmpty);
        expect(strings.firefoxCarrierLabel, isNotEmpty);
        expect(strings.firefoxLegDesc, isNotEmpty);
      }
    });
  });
}
