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
