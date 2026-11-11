/// M2 engine-wiring tests — the evidence-lock for the core↔UI seam:
///  * Aether argument mapping (all 11 protocol tiles, country gating, scan),
///  * zeptun TOML,
///  * the end-to-end probe against a REAL local SOCKS5 server,
///  * the PlatformEngineAdapter state walks (proxy/tunnel modes, permission
///    denial, engine death, disconnect cleanup) over a mocked
///    `aethone/engine` channel + a fake embedded core;
///  * v4.26 device-test round 4 regressions: the lost-cancel window, the
///    zombie walk, the durable-job resume, the late `down: destroy`, and
///    the resume-window holder identity.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aethone/connection/app_tunnel.dart';
import 'package:aethone/connection/aether_ffi.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/core_settings.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/platform_engine_adapter.dart';
import 'package:aethone/connection/smart_scorecard.dart';
import 'package:aethone/connection/tunnel_probe.dart';
import 'package:aethone/core/app_assets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channelName = 'aethone/engine';

/// v4.34 — the displaced port the SMART TOUR test binds exclusively
/// (1819 + 41000; nothing else in the suite ever binds 42819).
const int _tourPortOffset = 41000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  group('AetherArguments.build — protocol table (evidence-locked)', () {
    // v4.20: [protocol] is the WARP LEG; a family member rides in [chain].
    List<String> build(
      ProtocolId id, {
      String? country,
      int scan = 5,
      ProtocolId? chain,
    }) => AetherArguments.build(
          protocol: (id.isTor || id.isPsiphon) ? ProtocolId.wireguard : id,
          chain: chain ?? ((id.isTor || id.isPsiphon) ? id : null),
          countryCode: country,
          scanSpeed: scan,
          filesDir: '/data/files',
          nativeLibraryDir: '/data/lib',
        );

    test('masque', () {
      expect(
        build(ProtocolId.masque),
        containsAllInOrder(['--protocol', 'masque']),
      );
    });
    test('wireguard', () {
      expect(
        build(ProtocolId.wireguard),
        containsAllInOrder(['--protocol', 'wg']),
      );
    });
    test('gool', () {
      expect(build(ProtocolId.gool), containsAllInOrder(['--protocol', 'gool']));
    });
    test('goolClassic sets BOTH the protocol and the classic submode', () {
      expect(
        build(ProtocolId.goolClassic),
        containsAllInOrder(['--protocol', 'gool', '--gool-classic']),
      );
    });
    test('mim', () {
      expect(build(ProtocolId.mim), containsAllInOrder(['--protocol', 'mim']));
    });

    test(
      'v4.20 CHAIN keeps the WARP leg: --psiphon AND --protocol wg together '
      '(«اول وایرگارد وصل شه و بعد سایفون»)',
      () {
        final args = build(ProtocolId.wireguard, chain: ProtocolId.psiphonChain);
        expect(args, contains('--psiphon'));
        expect(args, containsAllInOrder(['--protocol', 'wg']));
        expect(
          args,
          containsAllInOrder(['--psiphon-bin', '/data/lib/libpsiphon.so']),
        );
        expect(
          args,
          containsAllInOrder(['--psiphon-dir', '/data/files/aether/psiphon']),
        );
      },
    );
    test('v4.20 CHAIN honors a DIFFERENT leg too (gool under psiphon)', () {
      final args = build(ProtocolId.gool, chain: ProtocolId.psiphonChain);
      expect(args, containsAllInOrder(['--protocol', 'gool', '--psiphon']));
    });
    test('torChain rides on the leg (--tor + --protocol wg)', () {
      final args = build(ProtocolId.wireguard, chain: ProtocolId.torChain);
      expect(args, contains('--tor'));
      expect(args, containsAllInOrder(['--protocol', 'wg']));
    });
    test(
      'v4.20 tor modes carry the lyrebird PT + a writable state dir '
      '(without --tor-pt the auto-bridge plan finds NO transport on Android)',
      () {
        for (final chain in [
          ProtocolId.torChain,
          ProtocolId.torReverse,
          ProtocolId.torOnly,
        ]) {
          final args = build(ProtocolId.wireguard, chain: chain);
          expect(args, containsAllInOrder([
            '--tor-pt',
            'obfs4=/data/lib/liblyrebird.so',
          ]), reason: '$chain must claim obfs4 on the packaged lyrebird');
          expect(args, containsAllInOrder([
            '--tor-pt',
            'snowflake=/data/lib/liblyrebird.so',
          ]), reason: 'aether PT_BINARIES maps lyrebird to snowflake too');
          expect(
            args,
            containsAllInOrder(['--tor-dir', '/data/files/aether/tor-state']),
            reason: '$chain needs a writable tor state dir',
          );
        }
        // PT args are ONLY for the tor family — psiphon/plain never see them.
        expect(
          build(ProtocolId.wireguard, chain: ProtocolId.psiphonChain),
          isNot(contains('--tor-pt')),
        );
        expect(build(ProtocolId.wireguard), isNot(contains('--tor-pt')));
      },
    );
    test(
      'v4.20 REVERSE maps the UDP-to-WARP legs to masque (the core refuses '
      'wg/gool-classic on reverse: lib.rs L203-218/L229-244)',
      () {
        final args = build(ProtocolId.wireguard, chain: ProtocolId.torReverse);
        expect(args, contains('--tor-reverse'));
        expect(args, containsAllInOrder(['--protocol', 'masque']));
        expect(args, isNot(contains('wg')));

        final psiphonArgs = build(
          ProtocolId.goolClassic,
          chain: ProtocolId.psiphonReverse,
        );
        expect(psiphonArgs, contains('--psiphon-reverse'));
        expect(psiphonArgs, containsAllInOrder(['--protocol', 'masque']));
      },
    );
    test(
      'v4.20 ONLY modes pass the core default protocol (the interactive '
      'select_protocol menu must never hang a headless job)',
      () {
        final tor = build(ProtocolId.wireguard, chain: ProtocolId.torOnly);
        expect(tor, contains('--tor-only'));
        expect(tor, containsAllInOrder(['--protocol', 'masque']));

        final psiphon = build(ProtocolId.gool, chain: ProtocolId.psiphonOnly);
        expect(psiphon, contains('--psiphon-only'));
        expect(psiphon, containsAllInOrder(['--protocol', 'masque']));
        expect(psiphon, containsAllInOrder([
          '--psiphon-bin',
          '/data/lib/libpsiphon.so',
        ]));
      },
    );
    test('psiphonReverse still gets the PT binary (its exit is WARP)', () {
      final args = build(ProtocolId.masque, chain: ProtocolId.psiphonReverse);
      expect(args, contains('--psiphon-reverse'));
      expect(args, containsAllInOrder(['--psiphon-bin', '/data/lib/libpsiphon.so']));
    });
    test('psiphonOnly', () {
      final args = build(ProtocolId.masque, chain: ProtocolId.psiphonOnly);
      expect(args, contains('--psiphon-only'));
      expect(args, containsAllInOrder(['--psiphon-bin', '/data/lib/libpsiphon.so']));
    });
    test('auto falls back to the core default protocol (masque)', () {
      expect(
        build(ProtocolId.auto),
        containsAllInOrder(['--protocol', 'masque']),
      );
    });
    test('effectiveMode: the overlay wins; auto resolves to masque', () {
      expect(
        AetherArguments.effectiveMode(ProtocolId.wireguard, ProtocolId.torChain),
        ProtocolId.torChain,
      );
      expect(
        AetherArguments.effectiveMode(ProtocolId.auto, null),
        ProtocolId.masque,
      );
      expect(
        AetherArguments.effectiveMode(ProtocolId.gool, null),
        ProtocolId.gool,
      );
    });

    test('common args are always present', () {
      final args = build(ProtocolId.masque);
      expect(args, containsAllInOrder(['--bind', '127.0.0.1:1819']));
      expect(args, containsAllInOrder(['--config', '/data/files/aether/warp.toml']));
      expect(args, containsAllInOrder(['--log-level', 'info']));
      expect(args, containsAllInOrder(['--scan', 'turbo'])); // scanSpeed 5
    });
  });

  group('AetherArguments.build — country pinning is honest per exit kind', () {
    List<String> build(ProtocolId id, ProtocolId? chain, String country) =>
        AetherArguments.build(
          protocol: id,
          chain: chain,
          countryCode: country,
          filesDir: '/f',
          nativeLibraryDir: '/l',
        );

    test('WARP-exit mode pins --exit-loc (uppercased)', () {
      expect(
        build(ProtocolId.masque, null, 'de'),
        containsAllInOrder(['--exit-loc', 'DE']),
      );
      expect(
        build(ProtocolId.wireguard, null, 'nl'),
        containsAllInOrder(['--exit-loc', 'NL']),
      );
      // psiphonReverse exits through WARP → exit-loc applies.
      expect(
        build(ProtocolId.masque, ProtocolId.psiphonReverse, 'de'),
        containsAllInOrder(['--exit-loc', 'DE']),
      );
    });

    test('Psiphon-exit mode pins --psiphon-region (lowercased)', () {
      expect(
        build(ProtocolId.wireguard, ProtocolId.psiphonChain, 'de'),
        containsAllInOrder(['--psiphon-region', 'de']),
      );
      expect(
        build(ProtocolId.masque, ProtocolId.psiphonOnly, 'de'),
        containsAllInOrder(['--psiphon-region', 'de']),
      );
    });

    test('Tor exits are NOT pinned (would be a lie)', () {
      final args = build(ProtocolId.wireguard, ProtocolId.torChain, 'de');
      expect(args, isNot(contains('--exit-loc')));
      expect(args, isNot(contains('--psiphon-region')));
    });
  });

  group('AetherArguments.scanProfile — «سرعت اسکن» 1..5', () {
    test('5=turbo 4=balanced 3=thorough 2=verified 1=ironclad; clamped', () {
      expect(AetherArguments.scanProfile(5), 'turbo');
      expect(AetherArguments.scanProfile(4), 'balanced');
      expect(AetherArguments.scanProfile(3), 'thorough');
      expect(AetherArguments.scanProfile(2), 'verified');
      expect(AetherArguments.scanProfile(1), 'ironclad');
      expect(AetherArguments.scanProfile(99), 'turbo');
      expect(AetherArguments.scanProfile(0), 'ironclad');
    });
  });

  // v4.31 — the round-7 settings expansion: every new knob folds into the
  // pinned CLI surface exactly once, and only when it differs from the
  // core's own default.
  group('AetherArguments.coreArgs — the v4.31 expansion', () {
    List<String> build({
      ProtocolId protocol = ProtocolId.masque,
      ProtocolId? chain,
      CoreSettings? core,
    }) => AetherArguments.build(
          protocol: protocol,
          chain: chain,
          core: core,
          filesDir: '/data/files',
          nativeLibraryDir: '/data/lib',
        );

    test('manual tor bridges: one --tor-bridge per line (comments skipped)',
        () {
      final core = CoreSettings()
        ..torBridges = TorBridgePolicy.custom
        ..torBridgeLines = '# from bridgedb\n'
            'obfs4 1.2.3.4:443 FINGERPRINT cert=abc iat-mode=0\n'
            '\n'
            'webtunnel 5.6.7.8:8443 FINGERPRINT2 url=https://x/y\n';
      final args = build(
        protocol: ProtocolId.wireguard,
        chain: ProtocolId.torChain,
        core: core,
      );
      expect(
        args,
        containsAllInOrder([
          '--tor-bridge',
          'obfs4 1.2.3.4:443 FINGERPRINT cert=abc iat-mode=0',
        ]),
      );
      expect(
        args,
        containsAllInOrder([
          '--tor-bridge',
          'webtunnel 5.6.7.8:8443 FINGERPRINT2 url=https://x/y',
        ]),
      );
      expect(args, isNot(contains('--no-tor-bridges')));
    });

    test('bridge policy off still passes --no-tor-bridges only', () {
      final core = CoreSettings()..torBridges = TorBridgePolicy.off;
      final args = build(
        protocol: ProtocolId.wireguard,
        chain: ProtocolId.torOnly,
        core: core,
      );
      expect(args, contains('--no-tor-bridges'));
      expect(args, isNot(contains('--tor-bridge')));
    });

    // v4.37 — the NON-INTERACTIVE decree: the IP version is EXPLICIT for
    // every value (an unset AETHER_IP made the core prompt stdin when the
    // app was launched from a terminal — «IP version to scan:»).
    test('IP version: v4 → -4, v6 → -6, dual → --dual (all explicit)', () {
      expect(
        build(core: CoreSettings()..ipVersion = IpVersion.v4),
        contains('-4'),
      );
      expect(
        build(core: CoreSettings()..ipVersion = IpVersion.v6),
        contains('-6'),
      );
      expect(
        build(core: CoreSettings()..ipVersion = IpVersion.dual),
        contains('--dual'),
      );
      final plain = build(core: CoreSettings());
      expect(plain, contains('-4')); // the v4 default is EXPLICIT now
      expect(plain, isNot(contains('-6')));
      expect(plain, isNot(contains('--dual')));
    });

    // v4.37 — the MASQUE transport is explicit both ways: an unset
    // AETHER_MASQUE_HTTP2 on the H3 side prompted «MASQUE transport:».
    test('transport: h2 → --h2, h3 → --h3 (both explicit)', () {
      expect(
        build(core: CoreSettings()..h2Transport = true),
        contains('--h2'),
      );
      expect(
        build(core: CoreSettings()..h2Transport = false),
        contains('--h3'),
      );
      expect(
        build(core: CoreSettings()..h2Transport = false),
        isNot(contains('--h2')),
      );
    });

    // v4.37 — the quick-reconnect prompt («Reconnect to it now without
    // rescanning? [Y/n]») is answered explicitly: --quick-reconnect carries
    // the exact value the non-TTY default already produced.
    test('quick reconnect is explicit (--quick-reconnect always present)',
        () {
      expect(build(core: CoreSettings()), contains('--quick-reconnect'));
      expect(
        build(protocol: ProtocolId.wireguard, chain: ProtocolId.psiphonChain),
        contains('--quick-reconnect'),
      );
    });

    test('upstream: plain modes only', () {
      final core = CoreSettings()
        ..upstreamProxy = 'socks5://10.0.0.5:1080';
      expect(
        build(core: core),
        containsAllInOrder(['--upstream', 'socks5://10.0.0.5:1080']),
      );
      // The family modes own AETHER_UPSTREAM internally — a user value
      // there would fight the chain itself.
      expect(
        build(chain: ProtocolId.psiphonChain, core: core),
        isNot(contains('--upstream')),
      );
    });

    test('ECH: auto / manual / off fold their own flags', () {
      final auto = CoreSettings()
        ..echMode = EchMode.auto
        ..echDns = 'https://1.1.1.1/dns-query'
        ..echDomain = 'cloudflare-ech.com';
      expect(
        build(core: auto),
        containsAllInOrder([
          '--ech',
          'auto',
          '--ech-dns',
          'https://1.1.1.1/dns-query',
          '--ech-domain',
          'cloudflare-ech.com',
        ]),
      );

      final manual = CoreSettings()
        ..echMode = EchMode.manual
        ..echKey = 'AEDW BASE64==';
      expect(build(core: manual), containsAllInOrder(['--ech', 'AEDW BASE64==']));

      expect(build(core: CoreSettings()), isNot(contains('--ech')));
    });

    test('psiphon sets + server entries fold under the family gate', () {
      final core = CoreSettings()
        ..cdnSets = 'psiphon-akamai,vercel'
        ..psiphonServerEntries = '[{"ipAddress":"1.2.3.4"}]';
      final args = build(
        protocol: ProtocolId.wireguard,
        chain: ProtocolId.psiphonChain,
        core: core,
      );
      expect(
        args,
        containsAllInOrder(['--psiphon-cdn-sets', 'psiphon-akamai,vercel']),
      );
      expect(
        args,
        containsAllInOrder([
          '--psiphon-server-entries',
          '[{"ipAddress":"1.2.3.4"}]',
        ]),
      );
      // Plain modes carry no psiphon flags at all.
      final plain = build(core: core);
      expect(plain, isNot(contains('--psiphon-cdn-sets')));
      expect(plain, isNot(contains('--psiphon-server-entries')));
    });

    test('the family leg protocol maps to its own --protocol pair', () {
      expect(
        AetherArguments.legProtocolId(AetherLegProtocol.masque),
        ProtocolId.masque,
      );
      expect(
        AetherArguments.legProtocolId(AetherLegProtocol.goolClassic),
        ProtocolId.goolClassic,
      );
    });

    test('readyBudget widens with the family timeout settings', () {
      const base = Duration(seconds: 360);
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.torChain),
        base,
      );
      expect(
        PlatformEngineAdapter.readyBudget(
          ProtocolId.torChain,
          core: CoreSettings()..torBridgeSecs = 600,
        ),
        const Duration(seconds: 630),
      );
      expect(
        PlatformEngineAdapter.readyBudget(
          ProtocolId.psiphonChain,
          core: CoreSettings()..psiphonReadySecs = 300,
        ),
        const Duration(seconds: 330),
      );
    });

    test('CoreSettings roundtrips the new fields', () {
      final s = CoreSettings()
        ..torBridges = TorBridgePolicy.custom
        ..torBridgeLines = 'obfs4 1.2.3.4:443 cert=abc iat-mode=0'
        ..torDirectSecs = 120
        ..torBridgeSecs = 500
        ..cdnSets = 'vercel'
        ..psiphonReadySecs = 240
        ..psiphonServerEntries = '[]'
        ..torLegProtocol = AetherLegProtocol.gool
        ..psiphonLegProtocol = AetherLegProtocol.masque
        ..ipVersion = IpVersion.dual
        ..upstreamProxy = 'socks5://h:1'
        ..echMode = EchMode.auto
        ..echKey = 'K=='
        ..echDns = 'https://d'
        ..echDomain = 'dom';
      final back = CoreSettings.fromJson(
        (jsonDecode(jsonEncode(s.toJson())) as Map).cast<String, dynamic>(),
      );
      expect(back.encode(), s.encode());
    });

    // v4.31c — the v4.31 single-field migration: an old blob's
    // aetherLegProtocol seeds BOTH family legs; a new blob's per-family
    // values win over the legacy key.
    test('CoreSettings migrates the legacy aetherLegProtocol into both '
        'families', () {
      final migrated = CoreSettings.fromJson({
        'v': 1,
        'aetherLegProtocol': 'gool',
      });
      expect(migrated.torLegProtocol, AetherLegProtocol.gool);
      expect(migrated.psiphonLegProtocol, AetherLegProtocol.gool);
      // The legacy field no longer round-trips (dropped from toJson).
      expect(migrated.toJson().containsKey('aetherLegProtocol'), isFalse);

      // Per-family values beat the legacy key when both are present.
      final perFamily = CoreSettings.fromJson({
        'v': 1,
        'aetherLegProtocol': 'gool',
        'torLegProtocol': 'mim',
        'psiphonLegProtocol': 'masque',
      });
      expect(perFamily.torLegProtocol, AetherLegProtocol.mim);
      expect(perFamily.psiphonLegProtocol, AetherLegProtocol.masque);
      // A no-legacy, no-new-keys blob keeps the WireGuard default.
      final bare = CoreSettings.fromJson({'v': 1});
      expect(bare.torLegProtocol, AetherLegProtocol.wireguard);
      expect(bare.psiphonLegProtocol, AetherLegProtocol.wireguard);
    });
  });

  group('ZeptunConfigToml.build', () {
    test('mobile preset + socks5 handler on the given port + fake-IP DNS', () {
      final toml = ZeptunConfigToml.build(socksPort: 1820, tcpOnly: false);
      expect(toml, contains('preset = "mobile"'));
      expect(toml, contains('kind = "socks5"'));
      expect(toml, contains('server = "127.0.0.1:1820"'));
      expect(toml, contains('fake_ip = true'));
      // UDP stays relayed (the plain UDP-carrying legs).
      expect(toml, isNot(contains('udp = ')));
    });

    // v4.31 — the TCP-only modes (every tor/psiphon family member): zeptun
    // REFUSES UDP flows (ICMP port-unreachable) instead of relaying them
    // into the core's silent drop-everything UDP relay.
    // v4.31b — the document schema's form: `udp` is a ?bool in zeptun's
    // config-document layer (config_json.zig), so the ONLY accepted values
    // are the bare words true/false. v4.31's `udp = "disabled"` (a quoted
    // string) failed zeptun_create_from_toml with ConfigError →
    // nativeStart rc≠0 → «establish-failed» on every tcpOnly connect.
    test('tcpOnly adds handler.socks5.udp = false (bool, not the enum tag)', () {
      final toml = ZeptunConfigToml.build(socksPort: 1821, tcpOnly: true);
      expect(toml, contains('preset = "mobile"'));
      expect(toml, contains('server = "127.0.0.1:1821"'));
      expect(toml, contains('udp = false'));
      // The quoted enum tag is REJECTED by the pinned parser (config_toml
      // scalar: a bool field accepts only the words true/false).
      expect(toml, isNot(contains('"disabled"')));
      expect(toml, contains('fake_ip = true'));
    });

    // v4.38 — the psiphon family's strict-socks handshake (the round-13
    // addendum defect: proxy worked, tunnel showed Connected with no data,
    // in every version). psiphon's goptlib listener (socksFlushReadBuffer,
    // psiphon/common/goptlib/socks.go) rejects ANY byte buffered after a
    // SOCKS message, so zeptun's pipelined handshake (greeting+request in
    // one write) and its optimistic data (payload riding the request write)
    // each killed every TCP flow of the psiphon TUNNEL while the walk's
    // sequential probe passed. Both keys are ?bool in the document schema
    // (config_json.zig), same bare-word form as `udp`.
    test('socksStrict adds pipeline = false + optimistic_data = false '
        '(the psiphon goptlib handshake fix)', () {
      final toml = ZeptunConfigToml.build(
        socksPort: 1821,
        tcpOnly: true,
        socksStrict: true,
      );
      expect(toml, contains('server = "127.0.0.1:1821"'));
      expect(toml, contains('pipeline = false'));
      expect(toml, contains('optimistic_data = false'));
      expect(toml, contains('fake_ip = true'));
    });

    test('every non-psiphon mode keeps the pipelined default (no strict keys)',
        () {
      // The plain WARP legs (1819) and the tor family (1820, aether's own
      // sequential socks.rs) read the stream with exact-size reads —
      // pipelining is harmless there and stays enabled.
      final plain = ZeptunConfigToml.build(socksPort: 1819, tcpOnly: false);
      expect(plain, isNot(contains('pipeline = ')));
      expect(plain, isNot(contains('optimistic_data = ')));
      final tor = ZeptunConfigToml.build(socksPort: 1820, tcpOnly: true);
      expect(tor, isNot(contains('pipeline = ')));
      expect(tor, isNot(contains('optimistic_data = ')));
    });
  });

  group('TunnelProbe.parseBody', () {
    const body = 'fl=x\nh=www.cloudflare.com\nip=162.158.1.1\nts=1700000000.000\n'
        'visit_scheme=https\nuag=test\ncolo=FRA\nloc=DE\ntls=TLSv1.3\n'
        'sni=plaintext\nwarp=on\ngateway=off\nrbi=off\nkex=X25519\n';

    test('parses exit country, ip, warp and lowercases the code', () {
      final r = TunnelProbe.parseBody(body, 123);
      expect(r.exitCountryCode, 'de');
      expect(r.exitIp, '162.158.1.1');
      expect(r.warp, isTrue);
      expect(r.pingMs, 123);
    });

    test('parses an HTTP-wrapped trace body', () {
      final r = TunnelProbe.parseBody(
        'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$body',
        7,
      );
      expect(r.exitCountryCode, 'de');
      expect(r.pingMs, 7);
    });

    test('a body without loc= fails the probe (never fabricated)', () {
      expect(
        () => TunnelProbe.parseBody('fl=x\nip=1.2.3.4\n', 5),
        throwsA(isA<SocketException>()),
      );
    });

    // v4.31 — the Tor-network pseudo country (owner round 7: «اسمش رو هم
    // T1 نوشته بود»): the trace still succeeds, the raw code stays for the
    // resolver, and the STATS event carries null (no «T1» name, no fake
    // flag).
    test('loc=T1 (the Tor network) parses as a PSEUDO country', () {
      final r = TunnelProbe.parseBody(
        'fl=x\nip=185.220.101.1\ncolo=FRA\nloc=T1\ntls=TLSv1.3\nwarp=off\n',
        42,
      );
      expect(r.exitCountryCode, 't1');
      expect(r.exitIp, '185.220.101.1');
      expect(r.countryIsPseudo, isTrue);
      final stats = PlatformEngineAdapter.statsEvent(r);
      expect(stats.exitCountryCode, isNull);
      expect(stats.pingMs, 42);
    });

    test('a real country is not pseudo', () {
      const body = 'fl=x\nip=1.1.1.1\nloc=DE\nwarp=off\n';
      final r = TunnelProbe.parseBody(body, 1);
      expect(r.countryIsPseudo, isFalse);
      expect(PlatformEngineAdapter.statsEvent(r).exitCountryCode, 'de');
    });
  });

  group('TunnelProbe against a REAL local SOCKS5 listener', () {
    test('listener readiness', () async {
      final server = await _FakeSocks5Server().start();
      try {
        expect(await TunnelProbe.isListenerReady(server.port), isTrue);
        expect(await TunnelProbe.waitForListener(server.port), isTrue);
      } finally {
        await server.dispose();
      }
      expect(await TunnelProbe.isListenerReady(1), isFalse);
    });

    test('full probe: SOCKS5 CONNECT (domain) + trace → ping + exit country', () async {
      final server = await _FakeSocks5Server().start();
      try {
        final result = await TunnelProbe().trace(port: server.port);
        expect(result.exitCountryCode, 'de');
        expect(result.warp, isTrue);
        expect(result.pingMs, greaterThanOrEqualTo(0));
        // The CONNECT request dialed the DOMAIN through the proxy.
        expect(server.lastConnectTarget, 'www.cloudflare.com');
        expect(server.lastConnectWasDomain, isTrue);
      } finally {
        await server.dispose();
      }
    });

    test('a SOCKS5 server that refuses CONNECT fails the probe', () async {
      final bad = await _FakeSocks5Server(refuseConnect: true).start();
      try {
        await expectLater(
          TunnelProbe().trace(port: bad.port),
          throwsA(isA<SocketException>()),
        );
      } finally {
        await bad.dispose();
      }
    });
  });

  group('PlatformEngineAdapter — state walks (mocked channel, fake core)', () {
    late _FakeSocks5Server listener;

    setUp(() async {
      // The adapter uses the evidence-locked ports; masque = 1819.
      listener = await _FakeSocks5Server().startOn(1819);
    });

    tearDown(() async {
      await listener.dispose();
    });

    test('proxy mode: connecting → connected ONLY via the probe; core args locked', () async {
      mockChannel();
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.proxy,
          selectedCountryCode: 'de',
        ),
      );

      await adapter.connect();
      // The adapter's broadcast controller delivers asynchronously — drain
      // the microtask queue before asserting on emitted events.
      await pumpEventQueue();

      expect(statesOf(events), [VpnState.connecting, VpnState.connected]);
      final stats = events.whereType<EngineStatsUpdated>().single;
      expect(stats.exitCountryCode, 'de');
      expect(stats.pingMs, isNotNull);

      // The core received the evidence-locked argument set.
      expect(core.startedArgs.single, containsAllInOrder(['--protocol', 'masque']));
      expect(core.startedArgs.single, containsAllInOrder(['--exit-loc', 'DE']));
      expect(
        core.startedArgs.single,
        containsAllInOrder(['--config', '/data/test/files/aether/warp.toml']),
      );

      // Steady state: the ticker refreshes REAL stats (job alive + probe).
      await adapter.debugTick();
      await pumpEventQueue();
      expect(events.whereType<EngineStatsUpdated>().length, 2);

      // Disconnect: job cancelled + freed; no VPN to stop in proxy mode.
      await adapter.disconnect();
      await pumpEventQueue();
      expect(core.cancelled, [42]);
      expect(core.freed, [42]);
      expect(statesOf(events).last, VpnState.disconnected);
    });

    test(
      'v4.21 per-family location: a psiphon pick pins --psiphon-region; '
      'AUTO passes no flag (the core\'s own choice)', () async {
      mockChannel();
      final listener = await _FakeSocks5Server().startOn(1821);
      try {
        final core = _FakeCore();
        final adapter = PlatformEngineAdapter(coreFactory: () => core);
        final events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.psiphonChain,
            connectionMode: ConnectionMode.proxy,
            psiphonLocation: 'de',
          ),
        );
        await adapter.connect();
        await pumpEventQueue();
        expect(statesOf(events).last, VpnState.connected);
        expect(
          core.startedArgs.single,
          containsAllInOrder(['--psiphon-region', 'de']),
        );
        await adapter.disconnect();
        await pumpEventQueue();

        // AUTO: no region flag at all — the core picks its own egress
        // (owner: «این انتخاب خودکار قابلیت خود هسته هاست»).
        final core2 = _FakeCore();
        final adapter2 = PlatformEngineAdapter(coreFactory: () => core2);
        adapter2.events.listen(events.add);
        adapter2.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.psiphonChain,
            connectionMode: ConnectionMode.proxy,
            psiphonLocation: 'auto',
          ),
        );
        await adapter2.connect();
        await pumpEventQueue();
        expect(core2.startedArgs.single, isNot(contains('--psiphon-region')));
        await adapter2.disconnect();
        await pumpEventQueue();
      } finally {
        await listener.dispose();
      }
    });

    test(
      'v4.31c per-family legs: torChain rides torLegProtocol, psiphonChain '
      'its own — never the other family\'s pick', () async {
        mockChannel();
        // torChain serves 1820; psiphonChain serves 1821.
        final torListener = await _FakeSocks5Server().startOn(1820);
        final psiphonListener = await _FakeSocks5Server().startOn(1821);
        try {
          // TOR family: gool under tor (torLegProtocol = gool).
          final core = _FakeCore();
          final adapter = PlatformEngineAdapter(coreFactory: () => core);
          final events = <EngineEvent>[];
          adapter.events.listen(events.add);
          adapter.bind(
            _FixedConfig(
              selectedProtocol: ProtocolId.torChain,
              connectionMode: ConnectionMode.proxy,
              coreSettings: CoreSettings()
                ..torLegProtocol = AetherLegProtocol.gool
                ..psiphonLegProtocol = AetherLegProtocol.mim,
            ),
          );
          await adapter.connect();
          await pumpEventQueue();
          expect(statesOf(events).last, VpnState.connected);
          expect(
            core.startedArgs.single,
            containsAllInOrder(['--protocol', 'gool', '--tor']),
          );
          await adapter.disconnect();
          await pumpEventQueue();

          // PSIPHON family on the SAME settings: mim under psiphon — the
          // psiphon leg, not the tor pick.
          final core2 = _FakeCore();
          final adapter2 = PlatformEngineAdapter(coreFactory: () => core2);
          adapter2.events.listen(events.add);
          adapter2.bind(
            _FixedConfig(
              selectedProtocol: ProtocolId.psiphonChain,
              connectionMode: ConnectionMode.proxy,
              coreSettings: CoreSettings()
                ..torLegProtocol = AetherLegProtocol.gool
                ..psiphonLegProtocol = AetherLegProtocol.mim,
            ),
          );
          await adapter2.connect();
          await pumpEventQueue();
          expect(
            core2.startedArgs.single,
            containsAllInOrder(['--protocol', 'mim', '--psiphon']),
          );
          await adapter2.disconnect();
          await pumpEventQueue();

          // Defaults stay the v4.19 fixed WireGuard leg per family.
          final core3 = _FakeCore();
          final adapter3 = PlatformEngineAdapter(coreFactory: () => core3);
          adapter3.events.listen(events.add);
          adapter3.bind(
            _FixedConfig(
              selectedProtocol: ProtocolId.psiphonChain,
              connectionMode: ConnectionMode.proxy,
            ),
          );
          await adapter3.connect();
          await pumpEventQueue();
          expect(
            core3.startedArgs.single,
            containsAllInOrder(['--protocol', 'wg', '--psiphon']),
          );
          await adapter3.disconnect();
          await pumpEventQueue();
        } finally {
          await torListener.dispose();
          await psiphonListener.dispose();
        }
      },
    );

    test(
      'v4.21 per-family location: a tor pick pins --exit-loc on torReverse; '
      'tor-exit modes never carry a country pin', () async {
      mockChannel();
      // Reuses the group's setUp listener on 1819 (torReverse serves the
      // main --bind listener).
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.torReverse,
          connectionMode: ConnectionMode.proxy,
          torLocation: 'nl',
        ),
      );
      await adapter.connect();
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.connected);
      // torReverse exits through WARP → the pick lands on --exit-loc.
      expect(
        core.startedArgs.single,
        containsAllInOrder(['--exit-loc', 'NL']),
      );
      await adapter.disconnect();
      await pumpEventQueue();

      // torChain/torOnly: no pin exists in the core — the pick stays a UI
      // memory and NEVER reaches the command line (asserted at the pure
      // builder level).
      expect(
        AetherArguments.build(
          protocol: ProtocolId.wireguard,
          chain: ProtocolId.torChain,
          countryCode: 'de',
          filesDir: '/data/test/files',
          nativeLibraryDir: '/data/test/lib',
        ),
        isNot(contains('--exit-loc')),
      );
    });

    test('tunnel mode: permission → VpnService → zeptun counters in stats', () async {
      var stopped = false;
      final startedPorts = <int>[];
      mockChannel(
        onStartVpn: startedPorts.add,
        onStopVpn: () => stopped = true,
      );
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      // The service comes up shortly after startVpn (as the real one does);
      // the mock emits 'up' 150 ms later — pump real time until connected.
      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await pumpEventQueue();

      expect(startedPorts, [1819]);
      expect(statesOf(events), [VpnState.connecting, VpnState.connected]);

      await adapter.debugTick();
      await pumpEventQueue();
      final stats = events.whereType<EngineStatsUpdated>();
      // TUN tx (222) = download; TUN rx (111) = upload.
      expect(stats.last.downBytes, 222);
      expect(stats.last.upBytes, 111);

      await adapter.disconnect();
      await pumpEventQueue();
      expect(stopped, isTrue);
      expect(core.freed, [42]);
      expect(statesOf(events).last, VpnState.disconnected);
    });

    // v4.38 — the psiphon family's strict-socks handshake rides the walk's
    // startVpn call (the round-13 addendum defect: psiphon tunnel showed
    // Connected with no data while proxy worked). psiphonChain (1821) and
    // psiphonOnly (1819→psiphon's own listener) dial goptlib, which rejects
    // pipelined bytes — they must ask the platform for the sequential
    // client; the tor family (aether's own sequential socks.rs) and every
    // plain leg must NOT.
    test(
      'tunnel mode: socksStrict=true only for the psiphon family '
      '(psiphonChain/psiphonOnly); tor and plain legs stay pipelined',
      () async {
        final startArgs = <Map<Object?, Object?>>[];
        mockChannel(
          onStartVpnArgs: startArgs.add,
        );
        // 1819 comes from the group's setUp; the tor (1820) and psiphon
        // chain (1821) listeners are this test's own.
        final torListener = await _FakeSocks5Server().startOn(1820);
        final psiphonListener = await _FakeSocks5Server().startOn(1821);
        try {
          Future<List<VpnState>> walk(ProtocolId protocol) async {
            final core = _FakeCore();
            final adapter = PlatformEngineAdapter(coreFactory: () => core);
            final events = <EngineEvent>[];
            adapter.events.listen(events.add);
            adapter.bind(
              _FixedConfig(
                selectedProtocol: protocol,
                connectionMode: ConnectionMode.tunnel,
              ),
            );
            unawaited(adapter.connect());
            await Future<void>.delayed(const Duration(milliseconds: 600));
            await pumpEventQueue();
            final states = statesOf(events);
            await adapter.disconnect();
            await pumpEventQueue();
            return states;
          }

          // psiphonChain → strict (goptlib at 1821).
          expect(
            await walk(ProtocolId.psiphonChain),
            [VpnState.connecting, VpnState.connected],
          );
          expect(startArgs.last['socksStrict'], isTrue);
          expect(startArgs.last['tcpOnly'], isTrue);
          expect(startArgs.last['port'], 1821);

          // psiphonOnly → strict (the 1819 listener is handed to psiphon
          // itself, psiphon.rs run_only).
          await walk(ProtocolId.psiphonOnly);
          expect(startArgs.last['socksStrict'], isTrue);
          expect(startArgs.last['port'], 1819);

          // torChain → NOT strict (1820 is aether's own sequential
          // listener; pipelining is harmless there).
          await walk(ProtocolId.torChain);
          expect(startArgs.last['socksStrict'], isFalse);
          expect(startArgs.last['tcpOnly'], isTrue);
          expect(startArgs.last['port'], 1820);

          // a plain WARP leg → NOT strict.
          await walk(ProtocolId.wireguard);
          expect(startArgs.last['socksStrict'], isFalse);
          expect(startArgs.last['tcpOnly'], isFalse);
          expect(startArgs.last['port'], 1819);
        } finally {
          await torListener.dispose();
          await psiphonListener.dispose();
        }
      },
    );

    test('VPN permission denial → failed(vpnPermissionDenied), nothing started', () async {
      var vpnStarted = false;
      mockChannel(
        prepareVpn: () => {'needsPermission': true},
        onStartVpn: (_) => vpnStarted = true,
      );
      // Deny after a short delay (the user tapped "cancel").
      Timer(const Duration(milliseconds: 100), () {
        emitTunnelEvent({'event': 'permission', 'granted': false});
      });

      final adapter = PlatformEngineAdapter(coreFactory: _FakeCore.new);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      await adapter.connect();
      await pumpEventQueue();

      expect(vpnStarted, isFalse);
      expect(statesOf(events), [
        VpnState.waitingForPermissions,
        VpnState.failed,
      ]);
      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.errorCode, 'vpnPermissionDenied');
    });

    test('engine death while connected → failed + tunnel torn down', () async {
      var stopped = false;
      mockChannel(onStopVpn: () => stopped = true);
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.connected);

      // The core exits on its own → the adapter must stop faking.
      core.pollState = 'done';
      await adapter.debugTick();
      await pumpEventQueue();

      expect(stopped, isTrue);
      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.state, VpnState.failed);
      expect(failure.errorCode, 'engineClosed');
    });

    test('missing native core → honest failure (libraryMissing), never fake', () async {
      mockChannel();
      final adapter = PlatformEngineAdapter(); // no factory: real AetherCore
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.proxy,
        ),
      );

      await adapter.connect();
      await pumpEventQueue();

      final failure = events.whereType<EngineStateChanged>().last;
      expect(failure.state, VpnState.failed);
      expect(failure.errorCode, 'libraryMissing');
    });

    test(
      'v4.20 probe-RETRY: a chain listener whose data path comes up LATE '
      'still connects (the single 20 s probe used to fail these modes — '
      'owner: «تور وصل نمیشه، سایفون وصل نمیشه»)', () async {
      mockChannel();
      // psiphonChain serves 1821; the first two probes are refused (the
      // inner protocol is still bootstrapping), the third succeeds.
      final slow = await _FakeSocks5Server(refuseFirstN: 2).startOn(1821);
      try {
        final core = _FakeCore();
        final adapter = PlatformEngineAdapter(coreFactory: () => core);
        final events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.psiphonChain,
            connectionMode: ConnectionMode.proxy,
          ),
        );

        await adapter.connect(); // retries inside (~2 × 2 s)
        await pumpEventQueue();

        expect(statesOf(events), [VpnState.connecting, VpnState.connected]);
        final stats = events.whereType<EngineStatsUpdated>().first;
        expect(stats.exitCountryCode, 'de');
        // v4.21 — the single-knob selection with the FIXED WireGuard leg
        // under the family mode: `--protocol wg --psiphon` (the adapter's
        // leg+overlay seam stays ready for the promised AETHER-leg option).
        expect(core.startedArgs.single, containsAllInOrder(['--protocol', 'wg']));
        expect(core.startedArgs.single, contains('--psiphon'));
        expect(core.startedArgs.single, containsAllInOrder([
          '--psiphon-bin', '/data/test/lib/libpsiphon.so',
        ]));

        // v4.34 — teardown: end CONNECTED no more (the leaked ticker kept
        // probing 1821 past this test's lifetime).
        await adapter.disconnect();
        await pumpEventQueue();
      } finally {
        await slow.dispose();
      }
    });

    test(
      'v4.20 probe-retry: a core that dies mid-bootstrap fails FAST with '
      'the CORE\'s own error (never a probe-budget timeout)', () async {
      mockChannel();
      // All probes refused on the psiphon port; the core dies 300 ms in.
      final refusing = await _FakeSocks5Server(refuseConnect: true).startOn(1821);
      try {
        final core = _FakeCore();
        final adapter = PlatformEngineAdapter(coreFactory: () => core);
        final events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.psiphonChain,
            connectionMode: ConnectionMode.proxy,
          ),
        );

        final walking = adapter.connect();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        core.pollState = 'error'; // the core exits on its own, mid-bootstrap
        await walking;
        await pumpEventQueue();

        final failure = events.whereType<EngineStateChanged>().last;
        expect(failure.state, VpnState.failed);
        expect(failure.errorCode, 'coreExited');
        expect(failure.message, contains('the core failed'));
      } finally {
        await refusing.dispose();
      }
    });

    test(
      'v4.20 tunnel ORDER: the VpnService starts BEFORE the core (a '
      'foreground-service start is only legal while the app is visible — the '
      'old order raced the user backgrounding the app mid-wait)', () async {
      final order = <String>[];
      mockChannel(onStartVpn: (_) => order.add('vpn'));
      final core = _OrderRecordingCore(order);
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await pumpEventQueue();

      expect(order, ['vpn', 'core']); // FGS first, core second
      expect(statesOf(events), [VpnState.connecting, VpnState.connected]);

      // v4.34 — teardown: this test used to end CONNECTED, leaving its
      // health ticker probing port 1819 for the rest of the FILE run —
      // the SMART TOUR test's fake server on 1819 then served the phantom
      // traces and its deterministic delay schedule shifted (the tour
      // picked goolClassic instead of wireguard under file-wide load).
      await adapter.disconnect();
      await pumpEventQueue();
    });

    test('v4.20 readyBudget mirrors the core\'s own timeouts per mode', () {
      // tor.rs: DIRECT_PROBE 75 s + BRIDGE_PROBE 360 s.
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.torChain),
        const Duration(seconds: 360),
      );
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.torReverse),
        const Duration(seconds: 360),
      );
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.torOnly),
        const Duration(seconds: 360),
      );
      // psiphon.rs: READY_TIMEOUT 180 s (+ margin).
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.psiphonChain),
        const Duration(seconds: 210),
      );
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.psiphonReverse),
        const Duration(seconds: 210),
      );
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.psiphonOnly),
        const Duration(seconds: 210),
      );
      // Plain WARP = registration + scan ≈ the listener budget.
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.masque),
        const Duration(seconds: 120),
      );
      expect(
        PlatformEngineAdapter.readyBudget(ProtocolId.wireguard),
        const Duration(seconds: 120),
      );
    });

    test(
      'v4.26 lost-cancel: a cancel during the walk STARTUP is honored — '
      'no startVpn, no core, no tunnel (the old walk connected anyway and '
      'the UI showed «disconnected» while the tunnel ran — owner: «فقط اتصال '
      'هسته اول قطع میشه و همچنان تونل برقراره»)', () async {
      var vpnStarts = 0;
      mockChannel(
        prepareVpn: () async {
          // A slow permission round-trip: the cancel lands while the walk
          // is parked in the platform reply (the old lost-cancel window).
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return <String, Object?>{'needsPermission': false};
        },
        onStartVpn: (_) => vpnStarts++,
      );
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await adapter.disconnect(); // mid-startup cancel
      // Let the slow reply land after the cancel.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();

      expect(vpnStarts, 0); // the tunnel was NEVER started
      expect(core.startedArgs, isEmpty); // neither was the core
      expect(statesOf(events), [VpnState.disconnected]);
      expect(
        events
            .whereType<EngineStateChanged>()
            .where((e) => e.state == VpnState.failed),
        isEmpty,
      );
    });

    test(
      'v4.26 zombie walk: a cancelled walk can never hijack the NEXT '
      'session — exactly ONE Connected, no late failure, no stopVpn aimed '
      'at the new session', () async {
      var stopVpnCalls = 0;
      mockChannel(onStopVpn: () => stopVpnCalls++);
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      // torChain walks the 1820 listener — nothing serves it YET.
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.torChain,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      // First connect: parks in the listener wait (no 1820 listener).
      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await adapter.disconnect(); // cancel mid-listener-wait
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.disconnected);

      // The inner protocol "comes up" — the listener appears NOW.
      final listener = await _FakeSocks5Server().startOn(1820);
      try {
        // The fake's jobCancel flipped it to done; the NEW job is running.
        core.pollState = 'running';
        await adapter.connect(); // the reconnect
        await pumpEventQueue();
        expect(statesOf(events).last, VpnState.connected);

        // Drain well past the OLD zombie's poll interval: it must stay
        // dead — no second Connected (the zombie used to "succeed" against
        // the NEW listener), no failure, no extra stopVpn.
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        await pumpEventQueue();
        final connectedCount =
            events
                .whereType<EngineStateChanged>()
                .where((e) => e.state == VpnState.connected)
                .length;
        expect(connectedCount, 1);
        expect(
          events
              .whereType<EngineStateChanged>()
              .where((e) => e.state == VpnState.failed),
          isEmpty,
        );
        // cancel(1) + the reconnect's startup hygiene(1) — nothing after.
        expect(stopVpnCalls, 2);

        // v4.34 — teardown: the second session used to stay CONNECTED
        // (its ticker probing 1820 past this test's lifetime).
        await adapter.disconnect();
        await pumpEventQueue();
      } finally {
        await listener.dispose();
      }
    });

    test(
      'v4.26 resume: a recreated isolate ADOPTS the durable job id — the '
      'disconnect after reopening the app cancels the core AND stops the '
      'VPN (the orphaned-core bug needed a force-close — owner: «باید اپ رو '
      'کلا بندی تا اتصال تونل قطع بشه»)', () async {
      var stopVpn = 0;
      var coreJobCleared = false;
      mockChannel(
        vpnStatus: () => <String, Object?>{'running': true, 'port': 1819},
        getCoreJob: () => 42,
        onStopVpn: () => stopVpn++,
        onClearCoreJob: () => coreJobCleared = true,
      );
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      // The resync walk (what bind() does on a real Android restart):
      // vpnStatus says the tunnel is up, the listener (this group's 1819
      // server) answers → resume + ADOPT job 42.
      await adapter.debugResync();
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.connected);
      expect(core.startedArgs, isEmpty); // resumed — nothing re-spawned

      await adapter.disconnect();
      await pumpEventQueue();

      // THE FIX: the adopted job is cancelled + freed, the service stopped
      // and the durable id cleared (nothing left bound for the next walk).
      expect(core.cancelled, [42]);
      expect(core.freed, [42]);
      expect(stopVpn, 1);
      expect(coreJobCleared, isTrue);
      expect(statesOf(events).last, VpnState.disconnected);
    });

    test(
      'v4.26 the late `down: destroy` of OUR OWN stop never flips a clean '
      'disconnect into failed', () async {
      var stopVpn = 0;
      mockChannel(onStopVpn: () => stopVpn++);
      final adapter = PlatformEngineAdapter(coreFactory: _FakeCore.new);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      unawaited(adapter.connect());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.connected);

      await adapter.disconnect();
      await pumpEventQueue();
      expect(statesOf(events).last, VpnState.disconnected);

      // The system delivers the service's onDestroy AFTER the disconnect
      // finished (session 1 — the session we stopped ourselves).
      await emitTunnelEvent({
        'event': 'down',
        'reason': 'destroy',
        'session': 1,
      });
      await pumpEventQueue();

      expect(statesOf(events).last, VpnState.disconnected); // never failed
      expect(
        events
            .whereType<EngineStateChanged>()
            .where((e) => e.state == VpnState.failed),
        isEmpty,
      );
      expect(stopVpn, 1);
    });
  });

  group('v4.32 SMART AUTO (scorecard + the candidate walk)', () {
    test('scorecard: fresh card explores in sheet order; tiers order the '
        'rest', () {
      final card = SmartScorecard();
      // Fresh: never-tried tier, the exploration ladder order.
      expect(
        card.rank(),
        smartCandidates,
        reason: 'a fresh card keeps the protocol sheet ladder',
      );

      // One candidate trusted (recent success + measured ping), one with a
      // failure streak, three untouched.
      final now = DateTime(2026, 11, 5, 12);
      card
        ..record(ProtocolId.wireguard, true, 90, now: now)
        ..record(ProtocolId.masque, false, null, now: now)
        ..record(ProtocolId.masque, false, null, now: now);
      final ranked = card.rank(now: now);
      expect(ranked.first, ProtocolId.wireguard,
          reason: 'the trusted candidate leads');
      expect(ranked.indexOf(ProtocolId.masque) > ranked.indexOf(ProtocolId.gool),
          isTrue,
          reason: 'the failed streak sits behind the untouched tier');
      // All five candidates present, no duplicates.
      expect(ranked.toSet().length, smartCandidates.length);
    });

    test('scorecard: failure streaks downgrade, EWMA smooths, roundtrips', () {
      final card = SmartScorecard();
      final now = DateTime(2026, 11, 5, 12);
      // wireguard: 2 successes with pings 100 and 200 → EWMA 120.
      card
        ..record(ProtocolId.wireguard, true, 100, now: now)
        ..record(ProtocolId.wireguard, true, 200, now: now);
      expect(card.scoreOf(ProtocolId.wireguard).ewmaPingMs, 120);
      // masque: a success then a failure streak — the streak is what
      // counts now, and successes stay recorded.
      card
        ..record(ProtocolId.masque, true, 50, now: now)
        ..record(ProtocolId.masque, false, null, now: now)
        ..record(ProtocolId.masque, false, null, now: now);
      final s = card.scoreOf(ProtocolId.masque);
      expect(s.consecutiveFailures, 2);
      expect(s.successes, 1);
      expect(s.attempts, 3);

      // Persistence roundtrip (the exact disk shape).
      final back = SmartScorecard.fromJson(
        (jsonDecode(card.encode()) as Map).cast<String, dynamic>(),
      );
      expect(back.encode(), card.encode());
    });

    test('the SMART TOUR (v4.34): short windows skip the dead candidate, '
        'every connector is quality-measured, the best one wins the final '
        'session', () async {
      mockChannel();
      // Connect #0 is refused (candidate 1's data path is dead) and every
      // NON-wireguard connect answers 250 ms slower — the tour's
      // measurement phase then picks wireguard deterministically instead
      // of a wall-clock coin flip (a 30 ms margin flaked under CI load).
      final listener = await _FakeSocks5Server(
        refuseFirstN: 1,
        connectDelaysMs: const [
          0, // #0 masque-H2 probe — REFUSED
          250, 250, 250, // #1-3 masque-H3 (probe + 2 quality)
          0, 0, 0, // #4-6 wireguard
          250, 250, 250, // #7-9 gool
          250, 250, 250, // #10-12 mim
          250, 250, 250, // #13-15 gool-classic
          0, // #16 the winner's own reconnect probe
        ],
      ).startOn(1819 + _tourPortOffset);
      try {
        final core = _FlakySmartCore(failFirstN: 1);
        final scorecard = SmartScorecard();
        // v4.34 — cross-file port hygiene: the tour's delay schedule is
        // only deterministic on a port NOTHING else in the (parallel,
        // one-process) suite can touch — the pinned 1819 could be probed
        // by another file's walk mid-tour (CI run #61 flipped the winner).
        final adapter = PlatformEngineAdapter(
          coreFactory: () => core,
          scorecard: scorecard,
          portOffset: _tourPortOffset,
        );
        final events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.auto,
            connectionMode: ConnectionMode.proxy,
            protocolModeSmart: true,
          ),
        );

        await adapter.connect();
        await pumpEventQueue();

        // Connected — ONCE, at the end of the tour (the measurement
        // attempts never flash a Connected).
        expect(statesOf(events).last, VpnState.connected);
        expect(
          statesOf(events).where((s) => s == VpnState.connected).length,
          1,
          reason: 'only the winner emits Connected',
        );

        // The plan: masque ×2 (the app-default H2 first, then H3) + the
        // other four candidates — six tour entries.
        final attempts = events.whereType<EngineSmartAttempt>().toList();
        final entries = attempts.where((e) => !e.measuring).toList();
        final measuring = attempts.where((e) => e.measuring).toList();
        expect(entries.length, 6, reason: 'the six-entry tour');
        expect(entries.first.candidate, ProtocolId.masque);
        expect(entries.first.attempt, 1);
        expect(entries.first.total, 6);
        // masque-H2 died with its core — no measurement for IT; every
        // later connector (masque-H3 included) was measured.
        expect(measuring.length, 5);
        expect(measuring.first.candidate, ProtocolId.masque);

        // THE PICK — wireguard (its measurement probes answered 0 ms;
        // everyone else's 250 ms).
        final resolved = events.whereType<EngineSmartResolved>().single;
        expect(resolved.protocol, ProtocolId.wireguard);

        // Every candidate really ran its own protocol: masque H2 first
        // (the app default carries --h2), masque H3 second (no --h2),
        // wireguard third, and the winner's reconnect is the 7th start.
        expect(
          core.startedArgs.first,
          containsAllInOrder(['--protocol', 'masque']),
        );
        expect(core.startedArgs.first, contains('--h2'));
        expect(
          core.startedArgs[1],
          containsAllInOrder(['--protocol', 'masque']),
        );
        expect(core.startedArgs[1].contains('--h2'), isFalse);
        expect(
          core.startedArgs[2],
          containsAllInOrder(['--protocol', 'wg']),
        );
        expect(core.startedArgs.last, containsAllInOrder(['--protocol', 'wg']),
            reason: 'the winner reconnects as the real session');

        // The scorecard recorded both masque stories (an H2 failure + an
        // H3 success) and every connector's success.
        final m = scorecard.scoreOf(ProtocolId.masque);
        expect(m.attempts, 2);
        expect(m.successes, 1);
        expect(m.consecutiveFailures, 0);
        expect(scorecard.scoreOf(ProtocolId.wireguard).successes, 1);
        expect(scorecard.scoreOf(ProtocolId.gool).successes, 1);

        await adapter.disconnect();
        await pumpEventQueue();
      } finally {
        await listener.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the SMART TOUR: exhaustion fails honestly with the last reason',
        () async {
      mockChannel();
      // Every CONNECT refused + every core start instantly 'done' — no
      // candidate can ever leave the ground.
      final listener = await _FakeSocks5Server(refuseConnect: true).startOn(
        1819,
      );
      try {
        final core = _FlakySmartCore(failFirstN: 99);
        final adapter = PlatformEngineAdapter(coreFactory: () => core);
        final events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.auto,
            connectionMode: ConnectionMode.proxy,
            protocolModeSmart: true,
          ),
        );

        await adapter.connect();
        await pumpEventQueue();

        // ALL six tour entries attempted (masque ×2 + the other four —
        // spec §7.2), then the honest exhaustion failure — no hidden
        // fallback, no fake connected.
        final attempts = events.whereType<EngineSmartAttempt>().toList();
        expect(
          attempts.where((e) => !e.measuring).length,
          6,
        );
        expect(attempts.where((e) => e.measuring), isEmpty,
            reason: 'nothing ever connected');
        expect(statesOf(events).last, VpnState.failed);
        final fail = events.whereType<EngineStateChanged>().last;
        expect(fail.errorCode, 'smartExhausted');
        expect(fail.message, contains('coreExited'));
        expect(core.startedArgs.length, 6);
      } finally {
        await listener.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('SMART is dormant on a MANUAL tile and on AUTO without the opt-in',
        () async {
      mockChannel();
      final listener = await _FakeSocks5Server().startOn(1819);
      try {
        // Manual wireguard tile + SMART on: the plain single walk.
        var core = _FlakySmartCore(failFirstN: 0);
        var adapter = PlatformEngineAdapter(coreFactory: () => core);
        var events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.wireguard,
            connectionMode: ConnectionMode.proxy,
            protocolModeSmart: true,
          ),
        );
        await adapter.connect();
        await pumpEventQueue();
        expect(statesOf(events).last, VpnState.connected);
        expect(events.whereType<EngineSmartAttempt>(), isEmpty,
            reason: 'a manual pick is never rewritten (§7.6)');
        expect(
          core.startedArgs.single,
          containsAllInOrder(['--protocol', 'wg']),
        );
        await adapter.disconnect();
        await pumpEventQueue();

        // AUTO tile, SMART off: the core's own default (masque), one walk.
        core = _FlakySmartCore(failFirstN: 0);
        adapter = PlatformEngineAdapter(coreFactory: () => core);
        events = <EngineEvent>[];
        adapter.events.listen(events.add);
        adapter.bind(
          _FixedConfig(
            selectedProtocol: ProtocolId.auto,
            connectionMode: ConnectionMode.proxy,
            protocolModeSmart: false,
          ),
        );
        await adapter.connect();
        await pumpEventQueue();
        expect(statesOf(events).last, VpnState.connected);
        expect(events.whereType<EngineSmartAttempt>(), isEmpty);
        expect(
          core.startedArgs.single,
          containsAllInOrder(['--protocol', 'masque']),
        );
        await adapter.disconnect();
        await pumpEventQueue();
      } finally {
        await listener.dispose();
      }
    });
  });

  group('v4.26 device-test round 4 — the resume window (own listeners)', () {
    test(
      'a disconnect DURING the resume probe stops the VPN service — not the '
      'core hold (the tunnel used to survive it: `_activeMode` was still the '
      'proxy default until the probe finished)', () async {
      var stopVpn = 0;
      var stopCoreHold = 0;
      mockChannel(
        vpnStatus: () => <String, Object?>{'running': true, 'port': 1819},
        getCoreJob: () => 42,
        onStopVpn: () => stopVpn++,
        onStopCoreHold: () => stopCoreHold++,
      );
      final core = _FakeCore();
      final adapter = PlatformEngineAdapter(coreFactory: () => core);
      final events = <EngineEvent>[];
      adapter.events.listen(events.add);
      adapter.bind(
        _FixedConfig(
          selectedProtocol: ProtocolId.masque,
          connectionMode: ConnectionMode.tunnel,
        ),
      );

      // The resume's end-to-end probe hangs on a slow data path (the first
      // CONNECT reply is delayed past the disconnect below).
      final slow = await _FakeSocks5Server(hangFirstConnect: true).startOn(
        1819,
      );
      try {
        unawaited(adapter.debugResync());
        await Future<void>.delayed(const Duration(milliseconds: 150));

        await adapter.disconnect(); // lands mid-probe
        await pumpEventQueue();

        // The RIGHT holder was stopped (the old code stopped the core hold
        // and left the VpnService — and with it the TUN — running).
        expect(stopVpn, 1);
        expect(stopCoreHold, 0);
        expect(statesOf(events), [VpnState.disconnected]);
        expect(
          events
              .whereType<EngineStateChanged>()
              .where((e) => e.state == VpnState.failed),
          isEmpty,
        );

        // The hung resume eventually completes — into a superseded
        // generation: it must stay silent (no late connected).
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await pumpEventQueue();
        expect(statesOf(events), [VpnState.disconnected]);
      } finally {
        await slow.dispose();
      }
    });
  });
}

/// The mocked `aethone/engine` channel (v4.26: hoisted to top level — the
/// round-4 groups share it; it captures nothing group-local).
void mockChannel({
  FutureOr<Map<Object?, Object?>?> Function()? prepareVpn,
  void Function(int port)? onStartVpn,
  // v4.38 — the FULL startVpn arguments (the psiphon strict-socks flag
  // rides here): the port-only callback stays for the older tests.
  void Function(Map<Object?, Object?> args)? onStartVpnArgs,
  void Function()? onStopVpn,
  Map<Object?, Object?> Function()? counters,
  Map<Object?, Object?> Function()? vpnStatus,
  Map<Object?, Object?> Function()? coreHoldStatus,
  int? Function()? getCoreJob,
  void Function(int?)? onSetCoreJob,
  void Function()? onClearCoreJob,
  void Function()? onStopCoreHold,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel(_channelName), (call) async {
        switch (call.method) {
          case 'paths':
            return <String, Object?>{
              'filesDir': '/data/test/files',
              'nativeLibraryDir': '/data/test/lib',
            };
          case 'prepareVpn':
            return prepareVpn?.call() ??
                <String, Object?>{'needsPermission': false};
          case 'startVpn':
            final port = (call.arguments as Map?)?['port'] as int? ?? 1819;
            onStartVpn?.call(port);
            onStartVpnArgs?.call(
                ((call.arguments as Map?) ?? const {}).cast<Object?, Object?>());
            // The real service establishes the TUN + zeptun and THEN
            // emits 'up' — the mock mirrors that timing.
            Timer(const Duration(milliseconds: 150), () {
              unawaited(emitTunnelEvent({'event': 'up', 'port': port}));
            });
            return null;
          case 'stopVpn':
            onStopVpn?.call();
            return null;
          // v4.26 — the process-durable job-id seam.
          case 'setCoreJob':
            onSetCoreJob?.call((call.arguments as Map?)?['job'] as int?);
            return null;
          case 'clearCoreJob':
            onClearCoreJob?.call();
            return null;
          case 'getCoreJob':
            return <String, Object?>{'job': getCoreJob?.call()};
          case 'vpnStatus':
            return vpnStatus?.call() ??
                <String, Object?>{'running': false, 'port': null};
          case 'coreHoldStatus':
            return coreHoldStatus?.call() ??
                <String, Object?>{'running': false, 'port': null};
          case 'stopCoreHold':
            onStopCoreHold?.call();
            return null;
          case 'zeptunCounters':
            return counters?.call() ??
                <String, Object?>{'rxBytes': 111, 'txBytes': 222};
        }
        return null;
      });
}

List<VpnState> statesOf(List<EngineEvent> events) =>
    events.whereType<EngineStateChanged>().map((e) => e.state).toList();

/// Records the walk order into [order] (v4.20 tunnel-order test).
class _OrderRecordingCore extends _FakeCore {
  _OrderRecordingCore(this.order);

  final List<String> order;

  @override
  int coreStart(List<String> args) {
    order.add('core');
    return super.coreStart(args);
  }
}

/// v4.32 — the SMART-walk fake: the FIRST [failFirstN] core starts exit
/// instantly (pollState 'done' — the walk's coreExited path), every later
/// start runs. Paired with a listener that refuses the matching probes,
/// this shapes per-candidate failure without any timing magic.
class _FlakySmartCore implements AetherCoreApi {
  _FlakySmartCore({required this.failFirstN});

  final int failFirstN;
  List<List<String>> startedArgs = [];
  final List<int> cancelled = [];
  final List<int> freed = [];
  bool _done = false;

  @override
  int coreStart(List<String> args) {
    startedArgs.add(args);
    _done = startedArgs.length <= failFirstN;
    return 42;
  }

  @override
  AetherReply jobPoll(int id) => _done
      ? AetherReply(true, const {
          'state': 'done',
          'result': {'state': 'closed'},
        })
      : AetherReply(true, const {'state': 'running'});

  @override
  bool jobCancel(int id) {
    cancelled.add(id);
    _done = true; // cooperative cancel lands (the walk's grace poll ends)
    return true;
  }

  @override
  bool jobFree(int id) {
    freed.add(id);
    return true;
  }
}

/// Simulates the platform→Dart direction (Kotlin emits `onTunnelEvent`).
Future<void> emitTunnelEvent(Map<String, Object?> args) async {
  final data = const StandardMethodCodec()
      .encodeMethodCall(MethodCall('onTunnelEvent', args));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_channelName, data, (ByteData? _) {});
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A minimal REAL-socket SOCKS5 server: greeting → CONNECT (ATYP=domain) →
/// serves the cloudflare-trace body. [refuseConnect] makes it answer REP≠0.
class _FakeSocks5Server {
  _FakeSocks5Server({
    this.refuseConnect = false,
    this.refuseFirstN = 0,
    this.hangFirstConnect = false,
    this.connectDelaysMs = const [],
  });

  final bool refuseConnect;

  /// v4.20 — refuse the first N CONNECTs, then serve normally: the
  /// stand-in for a chained protocol whose data path comes up LATE
  /// (aether binds the listener before the inner protocol is ready).
  final int refuseFirstN;

  /// v4.26 — delay the FIRST CONNECT reply by 600 ms: the stand-in for a
  /// resumed session whose data path is slow (the resume-window test
  /// disconnects while the resume probe is still in flight).
  final bool hangFirstConnect;

  /// v4.34 — per-CONNECT response delay (ms, indexed by connect number,
  /// 0 beyond the list): the SMART TOUR test makes wireguard's
  /// measurement probes measurably the fastest, so the tour's pick is
  /// deterministic instead of a wall-clock coin flip.
  final List<int> connectDelaysMs;

  int _connectsSeen = 0;
  ServerSocket? _server;
  int get port => _server!.port;
  String? lastConnectTarget;
  bool lastConnectWasDomain = false;

  Future<_FakeSocks5Server> start() => startOn(0);

  Future<_FakeSocks5Server> startOn(int port) async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handle, onError: (Object _) {});
    return this;
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handle(Socket socket) async {
    final reader = StreamIterator<Uint8List>(socket);
    try {
      // --- greeting [VER NMETHODS METHODS...] → [VER METHOD] ---
      if (!await reader.moveNext()) return;
      socket.add(const <int>[0x05, 0x00]);
      await socket.flush();

      // --- CONNECT request ---
      if (!await reader.moveNext()) return;
      final req = reader.current;
      if (req.length < 5) return;
      final atyp = req[3];
      String target;
      if (atyp == 0x03) {
        final len = req[4];
        target = ascii.decode(req.sublist(5, 5 + len));
        lastConnectWasDomain = true;
      } else if (atyp == 0x01) {
        target = req.sublist(4, 8).join('.');
        lastConnectWasDomain = false;
      } else {
        return;
      }
      lastConnectTarget = target;

      final connectIndex = _connectsSeen++;
      if (hangFirstConnect && connectIndex == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      if (refuseConnect || connectIndex < refuseFirstN) {
        socket.add(const <int>[0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        await socket.close();
        return;
      }
      socket.add(const <int>[0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await socket.flush();

      // --- HTTP request until the blank line, then the trace body ---
      final http = BytesBuilder();
      while (await reader.moveNext()) {
        http.add(reader.current);
        final text = ascii.decode(http.toBytes(), allowInvalid: true);
        if (text.contains('\r\n\r\n') || text.length > 4096) break;
      }
      // v4.34 — the per-connect delay lands INSIDE the probe's ping
      // window (request written → first response byte).
      final delay = connectDelaysMs.length > connectIndex
          ? connectDelaysMs[connectIndex]
          : 0;
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      socket.add(
        ascii.encode(
          'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n'
          '\r\nfl=x\nh=www.cloudflare.com\nip=162.158.1.1\ncolo=FRA\nloc=DE\n'
          'tls=TLSv1.3\nsni=plaintext\nwarp=on\ngateway=off\nrbi=off\nkex=X25519\n',
        ),
      );
      await socket.flush();
      await socket.close();
    } catch (_) {
      // A listener-check connection (connect + destroy) lands here — fine.
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }
}

/// Fake embedded core: records the arguments, plays a job state.
class _FakeCore implements AetherCoreApi {
  List<List<String>> startedArgs = [];
  String pollState = 'running';
  String? pollError;
  final List<int> cancelled = [];
  final List<int> freed = [];

  @override
  int coreStart(List<String> args) {
    startedArgs.add(args);
    return 42;
  }

  @override
  AetherReply jobPoll(int id) {
    if (pollState == 'done') {
      return AetherReply(true, {
        'state': 'done',
        'result': const {'state': 'closed'},
      });
    }
    if (pollState == 'error') {
      return AetherReply(false, {'error': pollError ?? 'the core failed'});
    }
    return AetherReply(true, const {'state': 'running'});
  }

  @override
  bool jobCancel(int id) {
    cancelled.add(id);
    pollState = 'done'; // cooperative cancel lands
    return true;
  }

  @override
  bool jobFree(int id) {
    freed.add(id);
    return true;
  }
}

/// A config source with fixed user choices (interface getter names).
class _FixedConfig implements EngineConfigSource {
  // PHASE-2 (firefox-vpn) — the new config surface (defaults).
  @override
  String get firefoxLocation => 'auto';
  @override
  String get firefoxTransport => 'h2';
  @override
  Map<String, dynamic> get firefoxDnsConfig => const {'mode': 'system'};
  /// v4.41 — the seam's new members (routing profile + per-app pick).
  @override
  String? get routingRegion => null;
  @override
  AppTunnelMode get appTunnelMode => AppTunnelMode.all;
  @override
  Set<String> get appTunnelApps => const <String>{};

  _FixedConfig({
    ProtocolId? selectedProtocol,
    ConnectionMode? connectionMode,
    this.selectedCountryCode,
    this.psiphonLocation = 'auto',
    this.torLocation = 'auto',
    this.protocolModeSmart = false,
    CoreSettings? coreSettings,
  }) : selectedProtocol = selectedProtocol ?? ProtocolId.masque,
       connectionMode = connectionMode ?? ConnectionMode.proxy,
       coreSettings = coreSettings ?? CoreSettings();

  /// v4.21 — the single-knob committed mode (a plain tile or a family
  /// member; the v4.20 chain split was reverted by the owner's decree).
  @override
  final ProtocolId selectedProtocol;

  @override
  final ConnectionMode connectionMode;
  @override
  final String? selectedCountryCode;

  /// v4.21 — the per-family location picks ('auto' or an ISO code).
  @override
  final String psiphonLocation;
  @override
  final String torLocation;

  @override
  int get scanSpeed => 5;

  /// v4.32 — the SMART opt-in (the SMART walk tests flip it on with the
  /// AUTO tile).
  @override
  final bool protocolModeSmart;

  /// v4.22 — the fine-grained core layer (the fakes run the defaults;
  /// walk tests may inject their own — e.g. the v4.31c per-family legs).
  @override
  final CoreSettings coreSettings;
}
