/// PlatformEngineAdapter — the M2 production adapter that wires the REAL
/// cores to the UI (architecture B+, prompt §3/§7):
///
///  * **Aether (Rust/WARP)** runs IN-PROCESS through its C API
///    (`libaether.so`, see [AetherCore]) with the exact CLI flags of the
///    pinned commit — the mapping lives in [AetherArguments] below and is
///    evidence-locked to `docs/CLI_REFERENCE.md` + `transport_modes.dart`.
///  * **zeptun (Zig/TUN)** is started by the Android `VpnService` through its
///    own JNI bridge (`libzeptun-jni.so`, class `dev.zeptun.Zeptun`) — only
///    in «تونل» mode.
///  * **Connected** is emitted ONLY after the end-to-end probe
///    ([TunnelProbe]) succeeded through the tunnel (§6.6) — the probe also
///    produces the real ping and exit-country values.
///
/// Honest gaps (documented, not hidden): SMART auto mode is not implemented
/// in the pinned core (SMART_AUTO_SPEC.md); the OS kill-switch/always-on
/// integration lands with a later step. Proxy mode serves the local SOCKS
/// listener only. The core's own log lines are captured process-wide by the
/// Kotlin layer (stderr → filesDir/logs/core-log.txt) and shown by the
/// settings diagnostics page.
///
/// v4.21 lifecycle hardening (owner device-test round 3):
///  * every coreStart is preceded by a full `AETHER_*` environment cleanup
///    (aether_env.dart — the in-process core's CLI parser only ever SETS
///    env vars, so session N+1 inherited session N's mode and died at
///    startup: engineClosed, state: null);
///  * the core's REAL exit reason (`result.error` of a done job) is carried
///    into the failed screen instead of the anonymous "state: null";
///  * tunnel platform events are SESSION-TAGGED — a stale service
///    instance's late `down/destroy` can no longer kill the next walk;
///  * the connect walk waits for the previous session's listener port to
///    actually come free before starting the new core (bind-race guard).
///
/// v4.26 connection-logic round (owner device-test round 4 — «منطق اتصال رو
/// چک کن و عملکرد برنامه رو طبق منطق اتصال اصلاح کن»):
///  * WALK GENERATIONS replace the boolean `_disconnecting` cancellation —
///    a cancelled walk can never resume, never emit a late failure, never
///    kill the NEXT session's engines, and a cancel during the walk's own
///    startup cleanup can no longer be LOST (the old bug established a
///    tunnel while the UI showed «disconnected»);
///  * the job id is PROCESS-DURABLE (Kotlin companion): a recreated
///    isolate adopts it on resync, so a disconnect after reopening the app
///    actually CANCELS the core (no more orphaned listener blocking the
///    next connect until a force-close);
///  * the resume sets the holder identity BEFORE its probe (a disconnect
///    during the resume probe used to stop the core hold instead of the
///    VPN service and left the tunnel running);
///  * the expected `down: destroy` of OUR OWN stop is filtered (no spurious
///    failed screen after a clean disconnect);
///  * the stats ticker is generation-scoped and non-reentrant.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_assets.dart';
import 'aether_env.dart';
import 'aether_ffi.dart';
import 'connection_state.dart';
import 'core_log.dart';
import 'core_settings.dart';
import 'egress_locations.dart';
import 'engine.dart';
import 'smart_scorecard.dart';
import 'tunnel_probe.dart';
import 'transport_modes.dart';

/// Builds the Aether CLI arguments (evidence-locked; pure and unit-tested).
///
/// v4.20 — the selection is TWO independent knobs (owner device test:
/// «منظورم این بود اول وایرگارد وصل شه و بعد سایفون نه اینکه کلا وایرگارد
/// به جاش وصل شه»):
///  * [protocol] — the WARP-leg tile (AUTO..MIM; WireGuard is the cold
///    default per the v4.19 decree). In a CHAIN mode this is the protocol
///    of the WARP tunnel the inner exit rides on — the core combines
///    `--protocol wg --psiphon` into "WireGuard WARP first, Psiphon over
///    it" (lib.rs L222-227: run_chain dials the held --bind listener).
///  * [chain] — the overlay family member (torChain…psiphonOnly) or null
///    for a plain connection.
class AetherArguments {
  static List<String> build({
    required ProtocolId protocol,
    ProtocolId? chain,
    String? countryCode,
    int scanSpeed = 5,
    CoreSettings? core,
    required String filesDir,
    required String nativeLibraryDir,
    String? lyrebirdPath,
    String? psiphonPath,
  }) {
    final overlay = chain;
    final modeId = effectiveMode(protocol, overlay);
    final mode = TransportModes.byId(modeId);
    final args = <String>[
      // Listener + identity storage (writable app dir — the core creates
      // parents itself, config.rs write_private).
      '--bind', '127.0.0.1:1819',
      '--config', '$filesDir/aether/warp.toml',
      '--log-level', 'info',
      // Endpoint-scan profile («سرعت اسکن», 1..5 → the five pinned modes).
      '--scan', scanProfile(scanSpeed),
      // v4.37 — the last interactive prompt, killed the same way: with a
      // saved last-connection gateway the core asks «Reconnect to it now
      // without rescanning? [Y/n]» on stdin (want_quick_reconnect, lib.rs)
      // — a TTY launch hung there from the SECOND connect on. `--quick-
      // reconnect` sets AETHER_QUICK_RECONNECT=1, the exact value the
      // non-TTY default already produced (prompt_line None → yes): the
      // cached gateway is still VERIFIED before reuse, and the user's
      // scan-profile choice keeps governing every fresh scan.
      '--quick-reconnect',
    ];

    // --- the WARP-leg protocol FIRST, then the overlay on top of it —
    // the args read exactly like the owner's decree («اول وایرگارد وصل شه
    // و بعد سایفون»): --protocol wg --psiphon = WireGuard WARP first,
    // Psiphon over it.
    args.addAll(protocolArgs(protocol, overlay));

    // --- the overlay family's own flag (cli.rs L584-600) ---
    if (overlay != null) {
      switch (overlay) {
        case ProtocolId.torChain:
          args.add('--tor');
        case ProtocolId.torReverse:
          args.add('--tor-reverse');
        case ProtocolId.torOnly:
          args.add('--tor-only');
        case ProtocolId.psiphonChain:
          args.add('--psiphon');
        case ProtocolId.psiphonReverse:
          args.add('--psiphon-reverse');
        case ProtocolId.psiphonOnly:
          args.add('--psiphon-only');
        default:
          break; // a plain tile — no overlay flag
      }
    }

    // --- tor family: the pluggable transport + a writable state dir.
    // The packaged PT is lyrebird (aether's own pt-build.sh builds
    // gitlab.torproject.org/.../lyrebird). bridges.rs search_dirs() only
    // scans DESKTOP paths (/usr/lib/tor/…, $HOME/.local/share/…) and the
    // binary is renamed liblyrebird.so for jniLibs extraction — without an
    // explicit --tor-pt the auto-bridge plan finds NO transport on Android
    // and Tor can never bootstrap (owner: «تور وصل نمیشه»). The protocol
    // claims mirror aether's own PT_BINARIES row for lyrebird
    // (bridges.rs L32-52); arti uses only the methods the binary itself
    // reports over the PT protocol, so an over-claim costs one failed
    // bridge, never a fake exit.
    if (overlay != null && overlay.isTor) {
      // v4.36 — the desktop runners resolve the binary's own name
      // (lyrebird / lyrebird.exe beside the executable); Android keeps the
      // jniLibs name verbatim (liblyrebird.so, extractNativeLibs).
      final lyrebird = lyrebirdPath ?? '$nativeLibraryDir/liblyrebird.so';
      for (final pt in const [
        'obfs4',
        'snowflake',
        'webtunnel',
        'meek_lite',
        'obfs3',
        'scramblesuit',
      ]) {
        args.addAll(['--tor-pt', '$pt=$lyrebird']);
      }
      // Explicit (not the warp.toml-sibling default) so tests + logs read
      // the same path the core uses.
      args.addAll(['--tor-dir', '$filesDir/aether/tor-state']);
    }

    // --- psiphon family: binary + writable state dir. The Go binary is
    // packaged renamed to libpsiphon.so so the installer extracts it with
    // the exec bit (extractNativeLibs) — evidence: psiphon.rs BINARY_NAMES
    // = psiphon-tunnel-core/psiphon and `--psiphon-bin` is "the
    // psiphon-tunnel-core binary to run" (cli.rs). v4.18 shipped
    // liblyrebird.so here — lyrebird is Tor's obfs4 PT, NOT the psiphon
    // client; fixed in v4.19 (owner device test: «از کارکرد تور و سایفون
    // مطمن نیستم»).
    if (overlay != null && overlay.isPsiphon) {
      // v4.36 — same desktop resolution as the tor PT above; Android keeps
      // libpsiphon.so verbatim.
      final psiphon = psiphonPath ?? '$nativeLibraryDir/libpsiphon.so';
      args.addAll([
        '--psiphon-bin', psiphon,
        '--psiphon-dir', '$filesDir/aether/psiphon',
      ]);
    }

    // Country pinning — only where the core can actually honor it:
    //  * WARP-exit modes → --exit-loc (allow-list policy, exitloc.rs);
    //  * Psiphon-exit modes → --psiphon-region (lyrebird egress region);
    //  * Tor exits are what they are — passing a pin would be a lie.
    final country = countryCode?.trim().toUpperCase();
    if (country != null && country.length == 2) {
      if (mode.exitKind == ExitKind.warp) {
        args.addAll(['--exit-loc', country]);
      } else if (mode.exitKind == ExitKind.psiphonExit) {
        args.addAll(['--psiphon-region', country.toLowerCase()]);
      }
    }

    // --- v4.22 — the fine-grained core layer (the settings sub-pages).
    // Folded ONLY when a layer was handed in: a null core means the CORE's
    // OWN defaults, arg-silent (v4.34 — the `?? CoreSettings()` fallback is
    // gone: a fresh CoreSettings now deliberately carries the APP defaults
    // — `--h2` + `--noize balanced`, owner round 10 — which must never leak
    // into a null-core build; the adapter always passes the store's layer).
    if (core != null) {
      args.addAll(coreArgs(core, protocol, overlay));
    }
    return args;
  }

  /// The [CoreSettings] → CLI folding (v4.22). Every entry cites its
  /// pinned-core arm in docs/CLI_REFERENCE.md; skipped when the value
  /// equals the core's own default (the evidence-locked arg list stays
  /// as quiet as before for a fresh CoreSettings).
  ///
  /// The tor family's log verbosity has NO CLI flag in the pin
  /// (AETHER_TOR_LOG, cli.rs L432 — env-only): the adapter injects it
  /// through the process environment instead.
  static List<String> coreArgs(
    CoreSettings core,
    ProtocolId leg,
    ProtocolId? overlay,
  ) {
    final a = <String>[];

    // -- TLS ClientHello fragmentation (the owner's Iran headline; the
    // core's own USAGE blesses it for this market: “as Iran's does”).
    final frag = core.effectiveFragment;
    if (core.fragmentPreset != FragmentPreset.off) {
      a.add('--fragment');
      if (frag.size.isNotEmpty) a.addAll(['--fragment-size', frag.size]);
      if (frag.delay.isNotEmpty) a.addAll(['--fragment-delay', frag.delay]);
    }

    // -- transport (#35-37, #40).
    // v4.37 — the MASQUE transport is EXPLICIT both ways. `--h2` alone left
    // AETHER_MASQUE_HTTP2 unset on the H3 side, so `select_masque_transport()`
    // (lib.rs) printed "MASQUE transport:" and waited on stdin (same
    // non-interactive decree as -4 above). `--h3` sets AETHER_MASQUE_HTTP2=0,
    // which masque_h2::enabled() treats exactly like unset — same behavior,
    // no hidden prompt.
    if (core.h2Transport) {
      a.add('--h2');
    } else {
      a.add('--h3');
    }
    if (!core.quicV2) a.add('--no-quic-v2');
    final dns = core.dns.trim();
    if (dns.isNotEmpty && dns != '1.1.1.1,1.0.0.1') {
      a.addAll(['--dns', dns]);
    }

    // -- v4.31 dial layer: the IP version (#11-13; v4 = the core's own
    // default — pass nothing) and the upstream proxy (#3, PLAIN modes
    // only: the reverse family modes own AETHER_UPSTREAM internally for
    // their carrier, lib.rs L203-244 — a user value there would fight
    // the chain itself).
    switch (core.ipVersion) {
      // v4.37 — the NON-INTERACTIVE decree (owner round 13): every prompt
      // the pinned core asks stdin for is now answered by an explicit flag.
      // The old "v4 = the core's own default, pass nothing" left AETHER_IP
      // unset, so `select_ip_version()` (lib.rs) printed "IP version to
      // scan:" and WAITED on stdin whenever the app was launched from a
      // terminal (prompt_line: is_terminal → read_line — the owner's sudo
      // run hung exactly there). `-4` sets AETHER_IP=v4 — the same value the
      // prompt's default would produce, so behavior is unchanged on every
      // platform; only the hidden stdin dependency is gone.
      case IpVersion.v4:
        a.add('-4');
      case IpVersion.v6:
        a.add('-6');
      case IpVersion.dual:
        a.add('--dual');
    }
    if (overlay == null) {
      final upstream = core.upstreamProxy.trim();
      if (upstream.isNotEmpty) a.addAll(['--upstream', upstream]);
    }

    // -- v4.31 ECH — encrypted SNI (#45-47), independent of the TLS
    // fingerprint switches: `--ech auto` looks the key up over DoH
    // (`--ech-dns`, default udp://1.1.1.1), `manual` takes the base64
    // key verbatim. Without a usable key the handshake neither leaks
    // the name nor proceeds (cli.rs L154-167) — honest.
    switch (core.echMode) {
      case EchMode.off:
        break;
      case EchMode.auto:
        a.addAll(['--ech', 'auto']);
      case EchMode.manual:
        final key = core.echKey.trim();
        if (key.isNotEmpty) a.addAll(['--ech', key]);
    }
    if (core.echMode != EchMode.off) {
      final echDns = core.echDns.trim();
      if (echDns.isNotEmpty) a.addAll(['--ech-dns', echDns]);
      final echDomain = core.echDomain.trim();
      if (echDomain.isNotEmpty) a.addAll(['--ech-domain', echDomain]);
    }

    // -- engine-wide: noize (#34), perf (#111), log level (#113).
    if (core.noize != NoizeProfile.defaultValue) {
      a.addAll(['--noize', core.noize.name]);
    }
    if (core.perf != PerfProfile.auto) a.addAll(['--perf', core.perf.name]);
    if (core.logLevel != CoreLogLevel.info) {
      a.addAll(['--log-level', core.logLevel.name]);
    }

    // -- WireGuard keepalive (#65) — only while a WG leg actually runs
    // (the plain WireGuard tile or any chain/reverse family mode).
    if (core.keepalive != 5 &&
        (leg == ProtocolId.wireguard || overlay != null)) {
      a.addAll(['--keepalive', '${core.keepalive}']);
    }

    // -- custom TLS (#44-64) — ONLY under tlsCustom; off = the core's own
    // Chrome-mimicking fingerprint, exactly as every build before v4.22.
    if (core.tlsCustom) {
      if (core.disableGrease) a.add('--disable-grease');
      if (core.greaseSigalgs) a.add('--enable-grease-sigalgs');
      if (core.echGrease) a.add('--enable-ech-grease');
      if (!core.sessionTicket) a.add('--disable-session-ticket');
      if (!core.ocsp) a.add('--disable-ocsp-stapling');
      if (!core.sct) a.add('--disable-sct');
      if (!core.extPermutation) a.add('--disable-extension-permutation');
      if (core.tlsVerify) a.add('--tls-verify');
      final groups = core.tlsGroups.trim();
      if (groups.isNotEmpty) a.addAll(['--tls-groups', groups]);
      final shares = core.keyShares.trim();
      if (shares.isNotEmpty) a.addAll(['--tls-key-shares', shares]);
      final c12 = core.ciphers12.trim();
      if (c12.isNotEmpty) a.addAll(['--tls-ciphers', c12]);
      final c13 = core.ciphers13.trim();
      if (c13.isNotEmpty) a.addAll(['--tls13-ciphers', c13]);
      final sni = core.masqueSni.trim();
      if (sni.isNotEmpty) a.addAll(['--masque-sni', sni]);
    }

    // -- routing lists (#101-102).
    final block = core.routeBlock.trim();
    if (block.isNotEmpty) a.addAll(['--route-block', block]);
    final direct = core.routeDirect.trim();
    if (direct.isNotEmpty) a.addAll(['--route-direct', direct]);

    // -- psiphon family (#87-94).
    if (overlay != null && overlay.isPsiphon) {
      if (core.psiphonFronting != PsiphonFronting.auto) {
        a.addAll(['--psiphon-mode', core.psiphonFronting.name]);
      }
      final cdnSni = core.cdnSni.trim();
      if (cdnSni.isNotEmpty) a.addAll(['--psiphon-cdn-sni', cdnSni]);
      final cdnIps = core.cdnIps.trim();
      if (cdnIps.isNotEmpty) a.addAll(['--psiphon-cdn-ips', cdnIps]);
      // v4.31 — the built-in fronting edge lists (#91); empty = all.
      final cdnSets = core.cdnSets.trim();
      if (cdnSets.isNotEmpty) a.addAll(['--psiphon-cdn-sets', cdnSets]);
      // v4.31 — pasted server entries (#94); empty = built-in discovery.
      final entries = core.psiphonServerEntries.trim();
      if (entries.isNotEmpty) {
        a.addAll(['--psiphon-server-entries', entries]);
      }
    }

    // -- tor family (#70-72).
    if (overlay != null && overlay.isTor) {
      if (core.torBridges == TorBridgePolicy.off) {
        a.add('--no-tor-bridges');
      } else if (core.torBridges == TorBridgePolicy.custom) {
        // v4.31 — the owner's manual bridge lines (round 7: «وارد کردن
        // دستی پل های تور»): one `--tor-bridge` per non-empty line — the
        // core's append() joins them with ';' into AETHER_TOR_BRIDGES,
        // which tor.rs parses as Bridges::Manual(lines). Comment/empty
        // lines are skipped.
        for (final raw in core.torBridgeLines.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          a.addAll(['--tor-bridge', line]);
        }
      }
    }

    return a;
  }

  /// v4.31 — the family-leg setting → the [ProtocolId] the arg builder
  /// speaks (the enum order mirrors the protocol sheet's own tiles).
  static ProtocolId legProtocolId(AetherLegProtocol leg) => switch (leg) {
    AetherLegProtocol.wireguard => ProtocolId.wireguard,
    AetherLegProtocol.masque => ProtocolId.masque,
    AetherLegProtocol.gool => ProtocolId.gool,
    AetherLegProtocol.goolClassic => ProtocolId.goolClassic,
    AetherLegProtocol.mim => ProtocolId.mim,
  };

  /// The mode the ENGINE actually runs: the overlay when one is selected,
  /// else the leg tile (AUTO resolves to the core's own default, MASQUE).
  static ProtocolId effectiveMode(ProtocolId leg, ProtocolId? overlay) {
    if (overlay != null) return overlay;
    return leg == ProtocolId.auto ? ProtocolId.masque : leg;
  }

  /// The `--protocol` argument pair(s) for the WARP leg, mapped per overlay
  /// family (evidence: lib.rs L131-139, L203-218, L229-244; cli.rs L637-653):
  ///  * ONLY modes return before the protocol session ever runs — pass the
  ///    core default so `select_protocol()`'s INTERACTIVE menu (lib.rs
  ///    L3281-3337) can never hang the headless job;
  ///  * REVERSE modes carry TCP only: the core REFUSES the UDP-to-WARP legs
  ///    (WireGuard, GOOL Classic) with its own error and forces the HTTP/2
  ///    carrier regardless — map those legs to MASQUE honestly (the
  ///    core's own error text blesses "--masque or --gool");
  ///  * CHAIN modes take the leg VERBATIM: `--protocol wg --psiphon` is
  ///    exactly "WireGuard WARP first, Psiphon over it".
  static List<String> protocolArgs(ProtocolId leg, ProtocolId? overlay) {
    if (overlay == ProtocolId.torOnly || overlay == ProtocolId.psiphonOnly) {
      return const ['--protocol', 'masque'];
    }
    var l = leg;
    if (overlay == ProtocolId.torReverse ||
        overlay == ProtocolId.psiphonReverse) {
      if (l == ProtocolId.auto ||
          l == ProtocolId.wireguard ||
          l == ProtocolId.goolClassic) {
        l = ProtocolId.masque;
      }
    }
    return switch (l) {
      ProtocolId.wireguard => const ['--protocol', 'wg'],
      ProtocolId.gool => const ['--protocol', 'gool'],
      // GOOL classic is NOT a protocol value: parser sets
      // AETHER_PROTOCOL=gool AND AETHER_GOOL_MODE=classic (cli.rs L644-647).
      ProtocolId.goolClassic => const ['--protocol', 'gool', '--gool-classic'],
      ProtocolId.mim => const ['--protocol', 'mim'],
      // masque + auto (auto = the core's own default) + unreachable family
      // members (the overlay, not the leg, carries those) all land on the
      // core default.
      _ => const ['--protocol', 'masque'],
    };
  }

  /// «سرعت اسکن» 1..5 → the five pinned scan profiles (CLI_REFERENCE #28-33).
  /// 5 = fastest (turbo, the sheet's default) … 1 = deepest (ironclad).
  static String scanProfile(int speed) => switch (speed.clamp(1, 5)) {
    5 => 'turbo',
    4 => 'balanced',
    3 => 'thorough',
    2 => 'verified',
    _ => 'ironclad',
  };
}

/// The zeptun TOML handed to `nativeStart` (zeptun config keys, frozen pin:
/// preset mobile + socks5 handler + fake-IP DNS = remote resolution through
/// the core; the fd is injected by the JNI bridge itself).
///
/// v4.31 — [tcpOnly] adds `handler.socks5.udp = false` for the
/// tor/psiphon family modes: zeptun then refuses every UDP flow at open
/// and answers ICMP port-unreachable (src/stack/udp.zig →
/// icmp.sendUnreachable), the honest "this network has no UDP" that apps
/// fall back from — instead of relaying into the core's silent
/// drop-everything UDP relay (socks.rs accepts the ASSOCIATE, drops all
/// non-DNS datagrams). Fake-IP DNS keeps working: zeptun answers it
/// locally in front of the handler (src/stack/dns.zig).
///
/// v4.31b — the VALUE FORM is the document schema's bool, not the enum
/// tag: the TOML/JSON document layer (config_json.zig L59) declares
/// `udp: ?bool` and maps it `if (u) .enabled else .disabled`; the parser
/// (config_toml.zig scalar) accepts ONLY the bare words `true`/`false`
/// for it. v4.31 shipped `udp = "disabled"` — a quoted string — so
/// `zeptun_create_from_toml` failed with ConfigError and nativeStart's
/// rc≠0 surfaced as «establish-failed» on EVERY tcpOnly mode (owner
/// round 8: psiphon/tor fail immediately, aether modes fine — they omit
/// the line). The `enabled`/`disabled` enum tags exist only on the
/// in-process Config struct and the CLI flags (--socks5-no-udp), never
/// in a config document.
///
/// v4.38 — [socksStrict] adds `pipeline = false` + `optimistic_data =
/// false` for the psiphon family's tunnel modes (psiphonChain/psiphonOnly):
/// their SOCKS target is psiphon-tunnel-core's goptlib server, whose
/// `socksFlushReadBuffer` (psiphon/common/goptlib/socks.go) rejects ANY
/// byte left buffered after a SOCKS message — zeptun's pipelined
/// handshake (greeting+request in one write; handler.zig `d.pipelined`,
/// auto→on without auth) and its optimistic data (request + early
/// payload, `sendWithEarly`) each tripped it, so every TCP flow of the
/// psiphon TUNNEL died at the handshake while the same port's proxy-mode
/// probe (strictly sequential) passed — the owner's round-13 addendum
/// defect, in every version. Byte-level proof:
/// scripts/psiphon_socks_pipeline_check.py. Both keys are ?bool in the
/// document schema (config_json.zig socks5 struct), same bool form as
/// `udp`. The mobile preset here matches AethoneVpnService.kt; the
/// desktop preset variant lives in desktop_shared/desktop_engine.cpp.
class ZeptunConfigToml {
  static String build({
    required int socksPort,
    required bool tcpOnly,
    bool socksStrict = false,
  }) =>
      '''
preset = "mobile"

[handler]
kind = "socks5"

[handler.socks5]
server = "127.0.0.1:$socksPort"
${tcpOnly ? 'udp = false' : ''}
${socksStrict ? 'pipeline = false\noptimistic_data = false' : ''}

[dns]
fake_ip = true
''';
}

/// The production adapter. Talks to the platform over the `aethone/engine`
/// MethodChannel (see MainActivity.kt / AethoneVpnService.kt) and to Aether
/// over dart:ffi. One active connection at a time; disconnect always cleans
/// BOTH engines even if connect failed halfway.
class PlatformEngineAdapter implements EngineAdapter {
  PlatformEngineAdapter({
    Duration? statsInterval,
    this._coreFactory,
    SmartScorecard? scorecard,
    this.portOffset = 0,
  })  : _statsInterval = statsInterval ?? const Duration(seconds: 5),
        _scorecard = scorecard ?? SmartScorecard();

  /// TEST-ONLY port displacement (production is ALWAYS 0 — the
  /// evidence-locked 1819/1820/1821 map). `flutter test` runs every file
  /// in its own isolate but ONE process: the suite's fake SOCKS servers
  /// and the cross-file adapter walks share the very ports the real app
  /// pins. A test that needs a port DEAD (a core-failure walk) or a port
  /// EXCLUSIVE (a deterministic connect schedule) displaces its walk off
  /// the pinned map; nothing else in the suite ever binds the displaced
  /// numbers, so no parallel-file listener or stray probe can poison it.
  final int portOffset;

  /// v4.32 — the SMART scorecard: engine-owned truth (attempts, failure
  /// streaks, EWMA probe ping) ordering the plain-Aether candidates. The
  /// store hands the SAME instance it later restores from disk (an
  /// in-place [SmartScorecard.loadFrom] keeps the reference live).
  final SmartScorecard _scorecard;

  static const MethodChannel _channel = MethodChannel('aethone/engine');

  /// Listener-bind budget: the core binds its listeners at START for every
  /// mode (lib.rs L128) — this wait is a cheap sanity bound; the real
  /// end-to-end wait lives in the probe-retry loop below.
  static const Duration _listenerBudget = Duration(seconds: 120);
  static const Duration _tunnelUpBudget = Duration(seconds: 30);

  /// v4.37 — the Linux desktop tunnelUp budget: the helper path shows a
  /// Polkit password prompt DURING the up wait (pkexec can sit on the
  /// dialog for minutes), so the budget widens to the permission round's
  /// own 180 s — the exact precedent of `_permissionBudget` for Android's
  /// VPN consent dialog. Every other platform (Windows zeptun, Android
  /// VpnService, tests) keeps the 30 s default.
  static bool get _isLinuxDesktopEngine =>
      Platform.isLinux &&
      Platform.environment['AETHONE_DESKTOP_ENGINE'] == '1';
  Duration get _tunnelUpWaitBudget =>
      _isLinuxDesktopEngine ? _permissionBudget : _tunnelUpBudget;
  static const Duration _probeTimeout = Duration(seconds: 20);
  static const Duration _permissionBudget = Duration(seconds: 180);
  /// v4.19 — how often the connect walk re-checks the core's health while
  /// waiting (owner device test #2: the app must FOLLOW the core — a core
  /// that dies during registration must fail the walk with the CORE's own
  /// error, not a generic listener timeout).
  static const Duration _coreHealthInterval = Duration(seconds: 1);

  /// v4.20 — pause between end-to-end probe attempts. The chain/only
  /// listeners are held-bound BEFORE their inner protocol is ready (a
  /// SOCKS greeting on them simply hangs — socks.rs L1931 test) — the walk
  /// RETRIES the probe until the mode's own ready budget runs out instead
  /// of failing on the first 20 s attempt (owner: «تور وصل نمیشه»,
  /// «سایفون وصل نمیشه» — both were this walk bug, not core failures).
  static const Duration _probeRetryInterval = Duration(seconds: 2);

  /// v4.21 — how long the walk waits for the previous session's SOCKS
  /// port to come free after a cancel (bind-race guard). The job's abort
  /// is asynchronous on the Rust runtime; 4 s is generous — a listener
  /// release takes milliseconds once the task is polled.
  static const Duration _portFreeBudget = Duration(seconds: 4);

  /// v4.21 — how long a DISCONNECT waits for the core job to reach `done`
  /// after `jobCancel` before freeing the registry entry (the v4.19 code
  /// waited only 1 s — a slow abort left the job running with its
  /// listeners bound while the UI already showed `disconnected`, and the
  /// NEXT connect lost the bind race).
  static const Duration _cancelGrace = Duration(seconds: 5);

  // ---- v4.34 — the SMART TOUR budgets (owner round 10:
  // «برای یک پروتکل تلاش کنه اگه در مدت کوتاهی وصل نشد بره سراغ بعدی،
  // … کیفیت اتصال اونی که وصل میشه رو بسنجه و در نهایت بهترین پروتکل رو
  // انتخاب کنه») --------------------------------------------------------
  //
  // The design follows the Happy-Eyeballs v2 shape (RFC 8305 §5: a SHORT
  // per-candidate attempt window instead of one long blocking try, then
  // move on — its "Connection Attempt Delay" idea, scaled from 250 ms
  // socket connects to full VPN sessions) plus the standard auto-protocol
  // practice of ranking by measured latency and keeping the winner
  // remembered (our scorecard).

  /// One candidate's whole connect window (listener wait + end-to-end
  /// probe). The old walk let a failing plain candidate sit on
  /// «در حال اتصال» for up to ~4 minutes (120 s listener + 120 s probe
  /// budget); 25 s is enough for a healthy plain Aether leg (WARP
  /// registration + scan ≈ 5–15 s) and short enough to tour all five
  /// candidates inside a couple of minutes (owner: «اگه در مدت کوتاهی
  /// وصل نشد بره سراغ بعدی»).
  static const Duration _smartAttemptWindow = Duration(seconds: 25);

  /// How many EXTRA probes the measurement phase fires at a connected
  /// candidate (the connecting probe itself is sample #1).
  static const int _smartQualityExtraProbes = 2;

  /// Per-probe timeout + the whole measurement phase's budget (a slow
  /// candidate must not stall the tour; its connecting ping already
  /// counts).
  static const Duration _smartQualityProbeTimeout = Duration(seconds: 8);
  static const Duration _smartQualityBudget = Duration(seconds: 12);

  /// v4.34 — a trace failure over a LIVE listener is DEGRADED, not dead
  /// (tor circuits legitimately exceed the 20 s trace budget while real
  /// traffic flows — owner round 10: «روی حالت تور اپ میره روی اتصال مجدد
  /// ولی اتصال برقراره و دیتا داره جا به جا میشه»). This many
  /// CONTINUOUS degraded ticks (~5 s each) still declare the session
  /// unhealthy — a tunnel that cannot complete a single trace for a
  /// minute is genuinely unusable, whatever the listener says.
  static const int _degradedTicksBudget = 12;

  /// v4.34 — how many times the Tor exit-country resolution may retry
  /// from the stats tick (the walk-time fetch races the circuit build;
  /// owner round 10: Tor showed «انتخاب خودکار» while the exit was
  /// actually the Netherlands).
  /// v4.40 — raised 4 → 10 (owner round 15: tor AUTO kept showing «خودکار»
  /// after connect): with the ip-api fallback each retry now has TWO
  /// independent resolvers, and a slow Tor circuit deserves more than
  /// ~20 s of chances while the connection itself works fine.
  static const int _exitResolveMaxTries = 10;

  /// The end-to-end ready budget per effective mode, mirroring the core's
  /// own timeouts (psiphon.rs READY_TIMEOUT 180 s; tor.rs DIRECT_PROBE 75 s
  /// + BRIDGE_PROBE 360 s; plain WARP = registration + scan ≈ listener
  /// budget). v4.31 — the family TIMEOUT settings widen their own budget
  /// (the app must never give up on a core it is still giving time to).
  static Duration readyBudget(ProtocolId mode, {CoreSettings? core}) {
    Duration atLeast(Duration base, int? userSecs) => userSecs == null
        ? base
        : base < Duration(seconds: userSecs + 30)
        ? Duration(seconds: userSecs + 30)
        : base;
    return switch (mode) {
      ProtocolId.torChain ||
      ProtocolId.torReverse ||
      ProtocolId.torOnly => atLeast(
        const Duration(seconds: 360),
        core?.torBridgeSecs == 360 ? null : core?.torBridgeSecs,
      ),
      ProtocolId.psiphonChain ||
      ProtocolId.psiphonReverse ||
      ProtocolId.psiphonOnly => atLeast(
        const Duration(seconds: 210),
        core?.psiphonReadySecs == 180 ? null : core?.psiphonReadySecs,
      ),
      _ => const Duration(seconds: 120),
    };
  }

  final Duration _statsInterval;
  final AetherCoreApi Function()? _coreFactory;
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  /// v4.21 — monotonic tunnel-session stamp. Every `startVpn` carries a new
  /// id; the service echoes it on every event it emits, and Dart DROPS
  /// events from any session other than the current one (a stale service
  /// instance being torn down after a quick reconnect used to deliver a
  /// late `down/destroy` that failed the NEW walk: owner device-test
  /// «در حالت تونل … ارور tunnelStartFailed / destroy»).
  int _tunnelSession = 0;

  /// v4.26 — the tunnel session WE tore down ourselves (a user disconnect
  /// or a walk cleanup). The service's asynchronous `onDestroy` emits its
  /// `down: destroy` event whenever the system gets around to processing
  /// the stop — which can land long after [disconnect] already finished and
  /// reset `_disconnecting`. Without this stamp that late event surfaced as
  /// a spurious `failed(tunnelDown)` right after a clean disconnect (owner
  /// device-test round 4).
  int? _tornDownTunnelSession;

  /// v4.26 — monotonic WALK generation. Every user action (connect or
  /// disconnect) bumps it; a walk captures the value at its start and is
  /// STALE the moment the field moves. This replaces the old boolean
  /// `_disconnecting` walk-cancellation, whose flag was reset by the
  /// disconnect's own completion and wiped again by the next connect:
  ///  * a cancelled walk kept polling for up to its full budget (120 s
  ///    listener / 360 s tor probe) and then emitted a late `failed`;
  ///  * its failure-path cleanup could STOP THE NEXT SESSION's service and
  ///    cancel its job (the «retry after cancel randomly dies» bug);
  ///  * worst of all, a cancel landing during the walk's own startup
  ///    cleanup was LOST — `_disconnecting` was already reset when the
  ///    walk resumed, so it went on to startVpn + coreStart and CONNECTED
  ///    anyway: a live tunnel with the UI showing «disconnected» that only
  ///    a force-close could end (owner: «فقط اتصال هسته اول قطع میشه و
  ///    همچنان تونل برقراره»).
  int _walkGeneration = 0;

  /// True when [gen] is no longer the live walk generation.
  bool _stale(int gen) => gen != _walkGeneration;

  /// v4.26 — re-entrancy guard for the 5 s stats ticker (a 20 s probe used
  /// to stack up to four concurrent probes on one core).
  bool _ticking = false;

  /// v4.34 — CONTINUOUS degraded-health ticks (trace failing while the
  /// SOCKS listener still answers). See [_degradedTicksBudget].
  int _degradedTicks = 0;

  /// v4.34 — Tor exit-country resolution attempts this session (the
  /// tick-driven retries; see [_exitResolveMaxTries]).
  int _exitResolveTries = 0;

  /// The generation the current ticker belongs to (dropped with its walk).
  int? _tickerGeneration;

  EngineConfigSource? _config;
  AetherCoreApi? _core;
  int? _jobId;
  Timer? _ticker;
  int _probeStrikes = 0;
  bool _connecting = false;
  bool _disconnecting = false;
  Completer<bool>? _tunnelUp;

  /// v4.20 — the platform's own reason a tunnel came down during the walk
  /// ("establish-failed", "start-threw:…", zeptun rc…) — carried into the
  /// tunnelStartFailed message so the failed screen can NAME the stage
  /// (owner: the tunnel failure was previously an anonymous miss).
  String? _tunnelDownReason;

  /// v4.20 — liveness of the tunnel leg while the walk is in flight: a
  /// service that dies between 'up' and Connected must NOT be papered over
  /// by a probe that only ever tests the LOCAL SOCKS listener.
  bool _tunnelAlive = false;
  Completer<bool>? _permissionAnswer;
  int _activePort = 1819;
  ConnectionMode _activeMode = ConnectionMode.proxy;

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  void bind(EngineConfigSource config) {
    _config = config;
    _channel.setMethodCallHandler(_onPlatformCall);
    _resyncAfterRestart();
  }

  // ---- v4.40: the desktop window/tray hooks ---------------------------------
  //
  // The native runners route the close button and the tray menu's toggle
  // entry into Dart as method calls; the DesktopWindowBridge registers
  // itself here (main()). Null on Android and in the test hosts — the
  // events simply never fire.
  static void Function()? onWindowCloseRequested;
  static void Function()? onTrayToggleConnection;

  @override
  Future<void> connect() async {
    // v4.26 — a fresh user intent supersedes ANY residue: the generation
    // bump invalidates a zombie walk from an already-cancelled session
    // (the store's single-flight guard means the only walk that can still
    // be unwinding here is one the user cancelled). There is deliberately
    // NO `_connecting` early-return any more: that guard used to swallow
    // the reconnect-after-cancel SILENTLY while the store had already
    // entered `starting` — the app hung on «در حال اتصال» forever.
    final gen = ++_walkGeneration;
    _connecting = true;
    _probeStrikes = 0;
    _coreFailureDuringStart = null;
    try {
      // v4.32 — SMART AUTO (app-layer, SMART_AUTO_SPEC.md): when the user
      // opted into SMART and the committed tile is AUTO, the candidates
      // run one-by-one (scorecard-ordered) instead of the core's fixed
      // default resolution. Everything else — a manual tile (spec §7.6:
      // never rewritten), a family mode (§6.7: excluded from the
      // auto-set), AUTO without the SMART opt-in — takes the plain walk.
      final config = _config;
      if (config != null &&
          config.protocolModeSmart &&
          config.selectedProtocol == ProtocolId.auto) {
        await _smartConnect(gen, config);
      } else {
        await _connectInner(gen);
      }
    } on AetherFfiException catch (e) {
      if (!_stale(gen)) _emitFail(e.code, e.message);
    } catch (e) {
      if (!_stale(gen)) _emitFail('engineException', e.toString());
    } finally {
      // Only the LIVE walk may clear the flag — a stale walk's finally
      // must not clobber a newer session's marker (event filtering reads
      // it in _onPlatformCall).
      if (!_stale(gen)) _connecting = false;
    }
  }

  /// v4.32 — the SMART walk (REWORKED v4.34 into a full TOUR, owner round
  /// 10: «اگه متصل نشه همینجوری روی حالت در حال اتصال برای مدت خیلی زیادی
  /// میمونه … برای یک پروتکل تلاش کنه اگه در مدت کوتاهی وصل نشد بره سراغ
  /// بعدی … کیفیت اتصال اونی که وصل میشه رو بسنجه … در نهایت بهترین
  /// پروتکل رو انتخاب کنه»):
  ///
  ///  1. THE PLAN — the scorecard-ordered candidates, with MASQUE
  ///     expanded into TWO profile variants (HTTP/2 and HTTP/3 — owner:
  ///     «با ماسک میتونه هم با حالت HTTP3 و هم HTTP2 اتصال رو تست کنه»);
  ///     the user's own transport order goes first. Other fragment/TLS
  ///     profile fan-outs are deliberately NOT toured — every variant
  ///     costs a full connect cycle, and a 5×N matrix would hold the user
  ///     on «در حال اتصال» for many minutes.
  ///  2. THE TOUR — each entry gets ONE short window
  ///     ([_smartAttemptWindow]): a candidate that cannot connect inside
  ///     it is SKIPPED (Happy-Eyeballs-shaped, RFC 8305 §5). A candidate
  ///     that connects is NOT settled on: the walk measures its quality
  ///     (up to 3 fresh probes, best ping wins), records it, tears the
  ///     measurement session down and moves on.
  ///  3. THE PICK — the connector with the BEST measured ping wins (ties
  ///     keep the tour order, which is the scorecard's own ranking); the
  ///     winner is reconnected with the FULL budgets as the real session
  ///     (it just connected moments ago — and if that reconnect dies, the
  ///     next-best connector takes its place).
  ///  4. Exhaustion fails honestly with the last reason (§7.5: never a
  ///     hidden fallback).
  ///
  /// Each attempt is a FULL walk — its own hard cleanup first (§7.4), its
  /// own tunnel session stamp, its own probe; the chain stays explicit
  /// and observable (§7.2: an [EngineSmartAttempt] precedes every
  /// candidate, and one more with `measuring: true` marks the quality
  /// phase).
  Future<void> _smartConnect(int gen, EngineConfigSource config) async {
    final plan = _smartPlan(config);
    var lastCode = 'smartExhausted';
    var lastMsg = 'no candidate was ever attempted';
    final connectors = <_SmartConnector>[];

    for (var i = 0; i < plan.length; i++) {
      if (_stale(gen)) return; // cancelled / superseded — silent
      final entry = plan[i];
      _controller.add(
        EngineSmartAttempt(entry.candidate, i + 1, plan.length),
      );
      var connectPingMs = 0;
      var failed = false;
      final ok = await _connectInner(
        gen,
        legOverride: entry.candidate,
        coreOverride: entry.settings,
        attemptWindow: _smartAttemptWindow,
        smartMeasure: true,
        onCandidateFail: (code, msg) {
          lastCode = code;
          lastMsg = msg;
          failed = true;
        },
        onProbePing: (ping) => connectPingMs = ping,
      );
      if (_stale(gen)) return; // cancelled mid-attempt — silent

      if (ok) {
        // Connected inside the window — MEASURE, don't settle (the store
        // stays in `connecting` the whole tour: no fake Connected flash).
        _controller.add(
          EngineSmartAttempt(entry.candidate, i + 1, plan.length,
              measuring: true),
        );
        final qualityMs = await _measureSmartQuality(gen, connectPingMs);
        if (_stale(gen)) return;
        _scorecard.record(
          entry.candidate,
          true,
          qualityMs > 0 ? qualityMs : null,
        );
        unawaited(saveScorecard(_scorecard));
        connectors.add(
          _SmartConnector(
            candidate: entry.candidate,
            settings: entry.settings,
            qualityMs: qualityMs > 0 ? qualityMs : connectPingMs,
            tourIndex: i,
          ),
        );
        // Tear the measurement session down so the next candidate (and
        // the final winner) starts from a clean port.
        await _hardCleanup();
        await _waitForPortFree(gen, _activePort);
        if (_stale(gen)) return;
        continue;
      }

      _scorecard.record(entry.candidate, false, null);
      unawaited(saveScorecard(_scorecard));
      if (!failed) {
        // The walk returned without failing or connecting — a stale-path
        // return that already stayed silent; the loop stays silent too.
        return;
      }
      // v4.32 — the inter-attempt bind-race guard: the failed candidate's
      // job was cancelled (its listener aborts asynchronously on the Rust
      // runtime), and the failure path's own _hardCleanup already nulled
      // _jobId — so the NEXT attempt's `hadPreviousSession` is false and
      // the walk's built-in `_waitForPortFree` would be SKIPPED. Wait for
      // the dying listener HERE (bounded by _portFreeBudget): the next
      // candidate's core must not race it on the same port («address
      // already in use» — the exact v4.21 reconnect bug).
      await _waitForPortFree(gen, _activePort);
      if (_stale(gen)) return;
      // The honest next candidate.
    }

    if (connectors.isEmpty) {
      _emitFail(
        'smartExhausted',
        'SMART tried ${plan.length} candidates; the last failure was '
        '$lastCode — $lastMsg',
      );
      return;
    }

    // THE PICK — best measured quality first (ties keep the tour order,
    // which is the scorecard's own ranking).
    connectors.sort(
      (a, b) {
        final byQuality = a.qualityMs.compareTo(b.qualityMs);
        if (byQuality != 0) return byQuality;
        return a.tourIndex.compareTo(b.tourIndex);
      },
    );
    for (final winner in connectors) {
      if (_stale(gen)) return;
      final landed = await _connectInner(
        gen,
        legOverride: winner.candidate,
        coreOverride: winner.settings,
      );
      if (_stale(gen)) return;
      if (landed) {
        _controller.add(EngineSmartResolved(winner.candidate));
        return;
      }
      // The winner's network shifted mid-tour — try the next-best
      // connector with the full budgets (its own failure already spoke).
      await _waitForPortFree(gen, _activePort);
      if (_stale(gen)) return;
    }
    _emitFail(
      'smartExhausted',
      'SMART measured ${connectors.length} working candidate(s) but none '
      'could hold a session on reconnect',
    );
  }

  /// One plan entry: the candidate tile + (for masque) the exact
  /// per-attempt core settings that variant runs with.
  ({ProtocolId candidate, CoreSettings? settings}) _smartPlanEntry(
    ProtocolId candidate,
    CoreSettings? settings,
  ) => (candidate: candidate, settings: settings);

  /// v4.34 — the tour plan: scorecard-ranked candidates, masque EXPANDED
  /// into its two transports (the user's own pick first — the new default
  /// is HTTP/2, owner round 10: «راستی حالت دیفالت مسک رو بزار روی HTTP2»).
  List<({ProtocolId candidate, CoreSettings? settings})> _smartPlan(
    EngineConfigSource config,
  ) {
    CoreSettings? masqueVariant(bool h2) {
      if (config.coreSettings.h2Transport == h2) return null; // the default
      return CoreSettings.fromJson(
        (jsonDecode(jsonEncode(config.coreSettings.toJson()))
            as Map).cast<String, dynamic>(),
      )..h2Transport = h2;
    }

    final plan = <({ProtocolId candidate, CoreSettings? settings})>[];
    for (final candidate in _scorecard.rank()) {
      if (candidate == ProtocolId.masque) {
        plan.add(_smartPlanEntry(
          candidate,
          masqueVariant(config.coreSettings.h2Transport),
        ));
        plan.add(_smartPlanEntry(
          candidate,
          masqueVariant(!config.coreSettings.h2Transport),
        ));
      } else {
        plan.add(_smartPlanEntry(candidate, null));
      }
    }
    return plan;
  }

  /// v4.34 — the measurement phase: up to [_smartQualityExtraProbes] fresh
  /// traces at the LIVE candidate (each bounded by
  /// [_smartQualityProbeTimeout], the whole phase by [_smartQualityBudget]);
  /// the BEST ping wins (min-of-N — the standard robust latency estimator:
  /// a single jitter spike must not cost a candidate the tour). A probe
  /// that fails outright keeps the connecting ping and ends the phase —
  /// a flaky-but-working candidate keeps its place, a stalled one was
  /// already caught by the window.
  Future<int> _measureSmartQuality(int gen, int connectPingMs) async {
    var best = connectPingMs;
    final deadline = DateTime.now().add(_smartQualityBudget);
    for (var i = 0; i < _smartQualityExtraProbes; i++) {
      if (_stale(gen)) return best > 0 ? best : connectPingMs;
      if (!DateTime.now().isBefore(deadline)) break;
      try {
        final r = await TunnelProbe().trace(
          port: _activePort,
          timeout: _smartQualityProbeTimeout,
        );
        if (r.pingMs > 0 && (best <= 0 || r.pingMs < best)) best = r.pingMs;
      } catch (_) {
        break; // the connecting probe already spoke for this candidate
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return best > 0 ? best : connectPingMs;
  }

  /// Runs ONE connect attempt. v4.32: returns whether the walk REACHED
  /// Connected (every other path is a failure or a silent stale return).
  /// [legOverride] pins the protocol tile (the SMART candidates);
  /// v4.34 adds:
  ///  * [coreOverride] — the SMART plan's per-variant core settings (the
  ///    masque HTTP/2 vs HTTP/3 tour); null = the user's own settings;
  ///  * [attemptWindow] — the SMART tour's SHORT per-candidate budget
  ///    (listener wait + end-to-end probe share it via a common deadline);
  ///    null = the full walk budgets;
  ///  * [smartMeasure] — the tour's measurement attempts: the walk returns
  ///    true right after the probe WITHOUT emitting Connected, starting
  ///    the ticker or resolving the exit country (the tour owns the
  ///    teardown; the user sees ONE Connected — the winner's);
  /// [onCandidateFail] reroutes the failure emissions to the SMART loop
  /// (which tries the next candidate instead of failing the session) —
  /// EXCEPT permission denials, which no candidate can cure. [onProbePing]
  /// hands the successful walk's probe latency to the scorecard.
  Future<bool> _connectInner(
    int gen, {
    ProtocolId? legOverride,
    CoreSettings? coreOverride,
    Duration? attemptWindow,
    bool smartMeasure = false,
    void Function(String code, String message)? onCandidateFail,
    void Function(int pingMs)? onProbePing,
  }) async {
    final config = _config;
    if (config == null) {
      _emitFail('notBound', 'the adapter was never bound to a config source');
      return false;
    }

    /// The failure seam: the SMART loop swallows per-candidate failures
    /// (it owns the terminal exhaustion event); everything else emits.
    void fail(String code, String msg) {
      if (onCandidateFail != null && code != 'vpnPermissionDenied') {
        onCandidateFail(code, msg);
      } else {
        _emitFail(code, msg);
      }
    }

    // Stale-state hygiene: never start a second core over a live one.
    // v4.21: this also WAITS for the previous session's listener port to
    // come free (bind-race guard) — a freed-but-still-aborting job used to
    // hold 127.0.0.1:1819 for a few scheduler turns and the fresh core
    // died instantly on "address already in use".
    final hadPreviousSession = _jobId != null;
    await _hardCleanup();
    // v4.26 — THE LOST-CANCEL FIX: a cancel that lands while this walk is
    // parked in the cleanup above (or in the permission round-trip below)
    // has already bumped the generation; the walk dies HERE, before any
    // startVpn/coreStart — the old boolean flag was already reset by then
    // and the walk went on to establish a tunnel nobody owned.
    if (_stale(gen)) return false;

    // v4.21 — the v4.20 chain/leg split is REVERTED to the single-knob
    // selection (owner decree). The adapter still builds the core args in
    // leg+overlay form; the dedicated family-leg option the v4.21 decree
    // promised LANDED in v4.31 (see the leg line below).
    final selection = config.selectedProtocol;
    final overlay = selection.isTor || selection.isPsiphon ? selection : null;
    // v4.32 — a SMART candidate PINNS the plain tile (legOverride); the
    // walk's every mode/port/arg decision then reads the candidate.
    final overridden = legOverride != null && overlay == null;
    // v4.31 — the WARP leg under a family mode is the OWNER'S choice now
    // (round 7: «انتخاب پروتکل هسته ایتر برای حالت های ترکیبی اور وارپ»;
    // v4.21 deferred exactly this). Default stays the v4.19 fixed
    // WireGuard leg; protocolArgs still forces MASQUE where the core
    // refuses UDP-to-WARP legs on the TCP-only reverse modes.
    // v4.31c — the leg is PER FAMILY (owner round 8: «قسمت پایه حالت های
    // ترکیبی باید توی زیرمجموعه تنطیمات تور و سایفون قرار بگیره»): the
    // tor family reads torLegProtocol, the psiphon family its own.
    final leg = overridden
        ? legOverride
        : overlay == null
        ? selection
        : AetherArguments.legProtocolId(
            overlay.isTor
                ? config.coreSettings.torLegProtocol
                : config.coreSettings.psiphonLegProtocol,
          );
    final modeId = AetherArguments.effectiveMode(leg, overlay);
    final mode = TransportModes.byId(modeId);
    final tunnel = config.connectionMode == ConnectionMode.tunnel;
    _activeMode = config.connectionMode;
    _activePort = mode.socksEndpoint.port + portOffset;

    // v4.36 — the honest Windows desktop limit (documented, not hidden):
    // the `-only` family modes (tor-only / psiphon-only) dial the internet
    // DIRECTLY — no WARP carrier to ride on — and zeptun's Windows routing
    // cannot exempt the app's own unmarked sockets from the TUN default
    // route the way Android's VpnService exempts the app uid (and Linux the
    // exclude_uid rule does): the tunnel would loop back into itself. The
    // walk fails BEFORE starting anything; the same family keeps working
    // through those cores in proxy mode, and every other mode (plain WARP
    // legs + the chain families, whose inner legs ride the WARP carrier)
    // tunnels fine on Windows.
    if (tunnel &&
        Platform.isWindows &&
        (overlay == ProtocolId.torOnly || overlay == ProtocolId.psiphonOnly)) {
      fail(
        'platformLimit',
        'the whole-device tunnel for this family needs a direct internet '
        'leg the Windows routing cannot exempt yet — use proxy mode for it',
      );
      return false;
    }

    // v4.21 — bind-race guard: after a previous session, wait until its
    // SOCKS port actually refuses connections before the new coreStart
    // (the old job's abort is asynchronous on the Rust runtime).
    if (hadPreviousSession) {
      await _waitForPortFree(gen, _activePort);
      if (_stale(gen)) return false;
    }

    // --- 1. VPN permission (tunnel mode only) — asked BEFORE any core work
    // so a denial wastes no registration. The store is in `starting`.
    if (tunnel && !await _ensureVpnPermission(gen)) {
      if (_stale(gen)) return false; // cancelled mid-dialog — cancel owns the end
      if (!_disconnecting) {
        fail('vpnPermissionDenied', 'the VPN permission was not granted');
      } else {
        _emitState(VpnState.disconnected);
      }
      return false;
    }
    if (_stale(gen)) return false;

    // v4.34 — the SMART tour's SHORT window: the clock starts AFTER the
    // permission round-trip (a user dialog is not the candidate's fault)
    // and bounds the tunnel-up + listener wait + end-to-end probe alike.
    final DateTime? windowEnd = attemptWindow == null
        ? null
        : DateTime.now().add(attemptWindow);

    // --- 1b. v4.20 (tunnel mode): the VpnService comes up FIRST, before the
    // core work. A foreground-service start is only legal while the app is
    // visible — the old order (core → up-to-120 s listener wait → startVpn)
    // raced the user backgrounding/locking the screen mid-walk and died
    // with ForegroundServiceStartNotAllowedException (owner: «اپ هنوز هم در
    // حالت تونل مشکل داره و وصل نمیشه»). zeptun tolerates a not-yet-serving
    // SOCKS target exactly like the core tolerates early clients (the
    // greeting is held), so bringing the TUN up early is safe — it is the
    // standard "connecting…" state every VPN app shows.
    if (tunnel) {
      // v4.26 — the walk holds its completer in a LOCAL: a concurrent
      // disconnect completes/nulls the FIELD, and the old `_tunnelUp!`
      // re-read crashed the walk with a null-check TypeError that raced
      // the cancel's terminal state.
      final tunnelUp = Completer<bool>();
      _tunnelUp = tunnelUp;
      _tunnelDownReason = null;
      _tunnelAlive = false;
      _tunnelSession++; // v4.21 — events from older sessions are dropped
      _tornDownTunnelSession = null; // v4.26 — this session is live
      try {
        await _channel.invokeMethod<void>('startVpn', {
          'port': _activePort,
          'session': _tunnelSession,
          // v4.31 — the mode's UDP capability: every tor/psiphon family
          // mode is TCP-only (the core's socks listener ACCEPTS the UDP
          // ASSOCIATE and then silently drops every non-DNS datagram), so
          // zeptun is configured with `udp = "disabled"` — it then
          // answers the device's UDP flows with ICMP port-unreachable
          // (apps fall back to TCP immediately) instead of blackholing
          // them (owner round 7: the psiphon tunnel «به مقدار دیتا رد و
          // بدل میشه و بعد دویاره دیتایی رد نمیشه» while the same port's
          // proxy worked).
          'tcpOnly': mode.tcpOnly,
          // v4.38 — the psiphon TUNNEL data-path root cause (owner round
          // 13 addendum: proxy works, tunnel shows Connected but exchanges
          // no data, in every version). The psiphon family's SOCKS target
          // (1821 relay → psiphon's local proxy, or 1819 handed to psiphon
          // in -only mode) is goptlib — psiphon/common/goptlib/socks.go
          // `socksFlushReadBuffer` treats ANY byte buffered after a SOCKS
          // message as a fatal error and closes the connection. zeptun's
          // desktop/mobile defaults pipeline the handshake (greeting+
          // request in one write; pooled connections always) and attach
          // optimistic data to the request — every TCP flow of the tunnel
          // died right there, while the walk's own probe speaks strictly
          // sequential SOCKS5 and passed. The fix: `pipeline = false` +
          // `optimistic_data = false` in the zeptun TOML for exactly the
          // modes whose listener terminates on goptlib (psiphonChain +
          // psiphonOnly). The tor family (1820/1819 served by aether's own
          // sequential socks.rs) and every plain WARP leg are untouched —
          // evidence: scripts/psiphon_socks_pipeline_check.py (byte-level
          // replay of both sides) + LINUX_RUNTIME_AND_TUNNEL_FIX_REPORT.md.
          'socksStrict':
              overlay == ProtocolId.psiphonChain ||
              overlay == ProtocolId.psiphonOnly,
        });
      } on PlatformException catch (e) {
        if (!_stale(gen)) {
          await _hardCleanup();
          fail('vpnStartFailed', '${e.code}: ${e.message}');
        }
        return false;
      } on MissingPluginException {
        if (!_stale(gen)) {
          await _hardCleanup();
          fail(
            'platformBridgeMissing',
            'the aethone/engine platform channel is not available in this build',
          );
        }
        return false;
      }
      if (_stale(gen)) return false; // cancelled mid-start — straggler-safe (Kotlin gate)
      final up = await tunnelUp.future.timeout(_tunnelUpWaitBudget, onTimeout: () {
        return false;
      });
      _tunnelUp = null;
      _tunnelAlive = up;
      if (!up) {
        if (_stale(gen)) return false; // cancelled mid-tunnel (#3)
        await _hardCleanup();
        fail(
          'tunnelStartFailed',
          _tunnelDownReason ?? 'zeptun did not come up',
        );
        return false;
      }
      if (_stale(gen)) return false;
    }

    // --- 2. Aether in-process (embedded core, architecture B+).
    if (_stale(gen)) return false; // a cancel must never hear `connecting`
    _emitState(VpnState.connecting);

    // v4.21 — PROCESS-ENVIRONMENT HYGIENE (the engineClosed fix). The
    // in-process core's CLI parser only ever SETS `AETHER_*` variables
    // (cli.rs), so without this cleanup session N+1 inherited session N's
    // mode — e.g. the core's own reverse-mode leftovers AETHER_UPSTREAM +
    // AETHER_MASQUE_HTTP2 pointing at a dead carrier — and died during
    // startup (owner: «بعد از خروج از اپ … دیگه اپ وصل نمیشه … ارورش هم
    // اینه: engineClosed»). Clear the whole inventory first; the fresh
    // argument list re-sets exactly what this mode needs.
    clearAetherEnvironment();

    // v4.22 — the tor family's log verbosity is ENV-ONLY in the pinned
    // core (AETHER_TOR_LOG, cli.rs L432): injected AFTER the inventory
    // cleanup above, exactly like the fresh arg list re-sets its selects.
    if (overlay != null &&
        overlay.isTor &&
        config.coreSettings.torLog != TorLogLevel.info) {
      setAetherEnvVar('AETHER_TOR_LOG', config.coreSettings.torLog.name);
    }
    // v4.31 — the family TIMEOUTS are env-only too (cli.rs L423-428):
    //  * tor: the plain-direct budget (AETHER_TOR_DIRECT_SECS, default
    //    75) and the per-bridge budget (AETHER_TOR_BRIDGE_SECS, 360) —
    //    owner round 7's «تنظیمات بیشتر»;
    //  * psiphon: the ready budget (AETHER_PSIPHON_READY_SECS, 180) — the
    //    walk's own budget widens with it (see readyBudget) so the app
    //    never fails a psiphon the core itself is still given time to
    //    bring up.
    if (overlay != null && overlay.isTor) {
      if (config.coreSettings.torDirectSecs != 75) {
        setAetherEnvVar(
          'AETHER_TOR_DIRECT_SECS',
          '${config.coreSettings.torDirectSecs}',
        );
      }
      if (config.coreSettings.torBridgeSecs != 360) {
        setAetherEnvVar(
          'AETHER_TOR_BRIDGE_SECS',
          '${config.coreSettings.torBridgeSecs}',
        );
      }
    }
    if (overlay != null && overlay.isPsiphon) {
      if (config.coreSettings.psiphonReadySecs != 180) {
        setAetherEnvVar(
          'AETHER_PSIPHON_READY_SECS',
          '${config.coreSettings.psiphonReadySecs}',
        );
      }
    }

    final core = _core =
        _coreFactory == null ? AetherCore.open() : _coreFactory();
    final paths = await _paths();
    // v4.34 — the SMART tour's variant settings (masque HTTP/2 vs HTTP/3)
    // replace the user's own for THIS attempt only.
    final effectiveCore = coreOverride ?? config.coreSettings;
    // v4.26 — CRITICAL ordering: everything from here to coreStart below
    // is SYNCHRONOUS (no await), so a cancel can never land between this
    // staleness check and the job spawn — a walk that goes stale after the
    // check but before coreStart would start a core that no cleanup ever
    // cancels (the job id lands in the field only AFTER the spawn).
    if (_stale(gen)) return false;
    _jobId = core.coreStart(
      AetherArguments.build(
        protocol: leg,
        chain: overlay,
        countryCode: _resolveCountryPick(modeId, config),
        scanSpeed: config.scanSpeed,
        core: effectiveCore,
        filesDir: paths.filesDir,
        nativeLibraryDir: paths.nativeLibraryDir,
        lyrebirdPath: paths.lyrebirdPath,
        psiphonPath: paths.psiphonPath,
      ),
    );
    // v4.26 — record the job id on the PROCESS side (Kotlin companion):
    // the Rust registry is process-scoped, so a RECREATED isolate can adopt
    // this id on resync and actually cancel the core on disconnect (the
    // orphaned-core bug: «باید اپ رو کلا بندی تا اتصال تونل قطع بشه»).
    await _recordCoreJob();
    if (_stale(gen)) return false;

    // --- 2b. v4.19 (#7): proxy mode has no VpnService to hold the process,
    // so swiping the app away used to kill the in-process core. A tiny
    // foreground service (CoreHoldService) pins the process for the session
    // and is torn down on disconnect. The tunnel mode already has
    // AethoneVpnService in the foreground.
    if (!tunnel) {
      try {
        await _channel.invokeMethod<void>(
          'startCoreHold',
          {'port': _activePort},
        );
      } on PlatformException {
        // Hold failed — proxy still works while the app is foregrounded;
        // the honest resync on the next start reports the truth.
      } on MissingPluginException {
        // no platform (tests) — nothing to hold
      }
      if (_stale(gen)) return false;
    }

    // --- 3. Wait for the SOCKS listener of the SELECTED mode (no fallback,
    // no guessing — prompt §12-الحاقیه). v4.19 (#2): while waiting, the
    // walk FOLLOWS the core — a job that exits on its own fails the walk
    // immediately with the core's own error (the core is the authority,
    // owner: «اپ باید تابع هسته ایتر باشه و ناموفق بودن اتصال رو از هسته
    // ایتر بگیره و منتظر اتصال هسته ایتر باشه»), and a user cancel aborts
    // the wait right away (#3).
    final ready = await _waitForListenerFollowingCore(
      gen,
      _activePort,
      timeout: _remainingUntil(windowEnd) ?? _listenerBudget,
    );
    // v4.26 — a stale walk (cancelled or superseded by a newer connect)
    // stays SILENT from here on: the cancel owns the terminal state, and a
    // newer walk owns every success/failure of the CURRENT engines. The
    // zombie used to keep polling, "succeed" against the NEXT session's
    // listener, emit a premature Connected, and on its own timeout run a
    // _hardCleanup that KILLED the next session's service and job.
    if (_stale(gen)) return false;
    if (!ready) {
      await _hardCleanup();
      if (_coreFailureDuringStart != null) {
        fail('coreExited', _coreFailureDuringStart!);
      } else {
        fail(
          'engineStartTimeout',
          'the core did not serve 127.0.0.1:$_activePort within '
          '$_listenerBudget'
          '${_probeLastErrorKind == null ? '' : ' — last attempt: $_probeLastErrorKind'}',
        );
      }
      return false;
    }
    _coreFailureDuringStart = null;

    // --- 4. End-to-end probe with RETRIES — the ONLY path to Connected
    // (§6.6). v4.20: a single 20 s attempt failed every mode whose inner
    // protocol legitimately bootstraps slower than that (Psiphon up to 180 s,
    // Tor 75 s direct + up to 360 s over bridges) because aether binds the
    // listeners BEFORE the data path exists. The loop retries the probe
    // within the mode's own budget while still FOLLOWING the core — a core
    // that dies fails the walk immediately with its own error.
    final probe = await _probeUntilReadyFollowingCore(
      gen,
      _activePort,
      budget: _remainingUntil(windowEnd) ??
          readyBudget(modeId, core: config.coreSettings),
      deadline: windowEnd,
    );
    if (_stale(gen)) return false; // cancelled during the probe (#3)
    if (probe == null) {
      await _hardCleanup();
      if (_coreFailureDuringStart != null) {
        fail('coreExited', _coreFailureDuringStart!);
      } else {
        fail(
          'endToEndProbeFailed',
          'the ${mode.label} data path did not answer through '
          '127.0.0.1:$_activePort within ${readyBudget(modeId).inSeconds} s '
          '(the chained protocol can legitimately take tens of seconds to '
          'bootstrap)'
          '${_probeLastErrorKind == null ? '' : ' — last attempt: $_probeLastErrorKind'}',
        );
      }
      return false;
    }
    // v4.20 — the probe only ever tests the LOCAL SOCKS listener; a tunnel
    // leg that died between 'up' and here must never be papered over with
    // a fake Connected.
    if (tunnel && !_tunnelAlive) {
      await _hardCleanup();
      fail(
        'tunnelDiedDuringWalk',
        _tunnelDownReason ?? 'the VPN service went down mid-connection',
      );
      return false;
    }

    // v4.37 — requirement D («فقط پس از عبور موفق ترافیک واقعی از مسیر
    // مورد انتظار، وضعیت Connected اعلام شود»): on the Linux desktop the
    // tunnel is helper-backed, and the helper can prove the DATA PATH
    // itself — it runs as uid 0, which the uid-exclusion rule does NOT
    // cover, so its probe genuinely traverses TUN → zeptun → SOCKS5 → the
    // aether core → the internet. A tunnel whose rules are wrong, whose
    // zeptun relay is dead or whose DNS delegation broke fails HERE,
    // honestly, instead of showing «Connected» over a black hole (the
    // owner's «با اینکه متصله ولی دیتا رد و بدل نمیکنه»).
    // The SMART tour's measurement walks are exempt (they tear down after
    // their probe; the WINNER's own full walk runs this gate — and the
    // candidate window must not absorb a data-path round trip).
    if (tunnel && !smartMeasure && _isLinuxDesktopEngine) {
      try {
        final verdict = await _channel
            .invokeMethod<Map<Object?, Object?>>('verifyTunnelPath')
            .timeout(const Duration(seconds: 45));
        final attempted = verdict?['attempted'] == true;
        final verified = verdict?['verified'] == true;
        final detail = (verdict?['detail'] as String?) ?? '';
        if (!attempted) {
          // The tunnel came up through the direct (root) path — the local
          // SOCKS probe remains the gate there (the app's own uid is
          // excluded from the TUN, an in-process probe could never pass).
          _debugLog('tunnel path verify skipped: $detail');
        } else if (!verified) {
          await _hardCleanup();
          fail(
            'tunnelDataPathFailed',
            'the tunnel was established but real traffic did not pass '
            'through it — $detail',
          );
          return false;
        } else {
          _debugLog('tunnel path verified through the TUN ($detail)');
        }
      } on MissingPluginException {
        // An older runner without the method — the walk degrades to the
        // local-probe gate (never silently: logged for the diagnostics).
        _debugLog('tunnel path verify unavailable on this runner');
      } catch (e) {
        _debugLog('tunnel path verify errored: $e');
      }
    }
    _emit(statsEvent(probe));

    // v4.34 — the SMART tour's measurement attempt stops HERE: the walk
    // proved the candidate connects inside its window and measured its
    // ping; the tour tears the session down and moves on. No Connected
    // emission, no ticker — the user sees ONE Connected (the winner's).
    if (onProbePing != null) {
      onProbePing(probe.pingMs);
    }
    if (smartMeasure) {
      return true;
    }
    _emitState(VpnState.connected);

    // v4.34 — the session-scoped retry counters start clean.
    _exitResolveTries = 0;
    _degradedTicks = 0;

    // v4.31 — a pseudo-country exit (loc=T1 — the Tor network, no flag,
    // no name; owner round 7 «اسمش رو هم T1 نوشته بود»): resolve the REAL
    // country from the exit relay's own directory record (Onionoo, by the
    // exit IP, fetched through the live tunnel) once the session is up.
    // Unresolved stays honestly unknown — never a fake flag.
    if (probe.countryIsPseudo && probe.exitIp != null) {
      unawaited(_resolveExitCountry(gen, _activePort, probe.exitIp!));
    }

    // v4.28 — harvest the psiphon egress regions the core reported during
    // the walk (the network's own `AvailableEgressRegions` notice lands in
    // the captured core log). Fire-and-forget both times: the wheel gets
    // the fresh set whenever the read completes, walk or no walk.
    unawaited(_harvestPsiphonEgressRegions());

    // --- 5. Steady state: stats + health (§6 health probe ⇒ reconnecting).
    _startTicker(gen);
    return true;
  }

  /// v4.19 (#2) — the core's last words when it died during the listener
  /// wait ("connection failure comes FROM the core").
  String? _coreFailureDuringStart;

  /// v4.37 — the classified last error of the end-to-end probe attempts
  /// (requirement 2.5: the raw `SocketException: Connection reset by peer,
  /// address = 127.0.0.1` the owner saw must become a DIAGNOSTIC line, not
  /// a swallowed mystery). Set by the probe loops, read by the walk's
  /// failure screens.
  String? _probeLastErrorKind;

  /// The classifier for [TunnelProbe] failures: keeps the OS wording but
  /// names WHAT it means for the walk — a reset on 127.0.0.1 is the core
  /// (or a previous session's listener) closing the socket mid-handshake.
  static String classifyProbeError(Object error) {
    if (error is SocketException) {
      final msg = error.osError?.message ?? error.message;
      if (msg.contains('Connection reset by peer')) {
        return 'the local connection to the core (127.0.0.1) was RESET '
            'mid-handshake — the core exited or closed its listener just as '
            'the probe arrived (the core’s own exit reason, when it has '
            'one, is quoted separately)';
      }
      if (msg.contains('Connection refused')) {
        return 'the core is not accepting connections on 127.0.0.1 yet '
            '(connection refused)';
      }
      return 'local socket error: $msg';
    }
    if (error is TimeoutException) {
      return 'the core accepted the connection but never answered the '
          'probe within the attempt timeout';
    }
    return error.toString();
  }

  /// The walk's diagnostics channel (flutter run console + release logs via
  /// the platform capture when the platform chooses to forward it).
  void _debugLog(String line) => debugPrint('aethone/engine: $line');

  /// v4.21 — the honest reason a done job ended: a NORMAL stop carries
  /// `result.state` ("closed"/"stopped"), a FAILED core carries
  /// `result.error` (ffi.rs `error_value` — the JSON object the old code
  /// misread as "state: null", swallowing the core's own words: owner
  /// device test «ارورش هم اینه: engineClosed / the core exited on its own
  /// (state: null)» — the REAL reason was in the very same reply).
  static String describeJobOutcome(Map<Object?, Object?> body) {
    final result = body['result'];
    if (result is Map) {
      final inner = result['state'];
      if (inner is String) {
        return inner == 'stopped'
            ? 'the core was stopped (state: $inner)'
            : 'the core exited on its own (state: $inner)';
      }
      final error = result['error'];
      if (error is String && error.isNotEmpty) {
        return 'the core failed: $error';
      }
    }
    return 'the core exited on its own (state: null)';
  }

  /// v4.21 — bind-race guard: waits until [port] no longer accepts SOCKS
  /// connections (the previous job's abort releasing its listener),
  /// bounded to [_portFreeBudget]. A refusal/error means the port is free.
  /// v4.26 — generation-aware: a superseded walk stops waiting.
  Future<void> _waitForPortFree(int gen, int port) async {
    final deadline = DateTime.now().add(_portFreeBudget);
    while (DateTime.now().isBefore(deadline)) {
      if (_stale(gen)) return;
      try {
        if (!await TunnelProbe.isListenerReady(port)) return;
      } catch (_) {
        return; // refused — already free
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// v4.21 — per-family location pick (owner device-test round 3:
  /// «اپ باید انتخاب لوکیشن سایفون و تور رو یادش بمونه» + «برای سایفون
  /// و تور به انتخاب خودکار هم باید بزاریم»):
  ///  * psiphon family → the psiphon pick ('auto' = the core's own
  ///    egress choice — no flag); psiphon-exit modes map to
  ///    --psiphon-region, psiphonReverse to --exit-loc (warp exit);
  ///  * tor family → the tor pick for torReverse (--exit-loc — the exit
  ///    IS a WARP colo); torOnly/torChain get NO pin — the pinned arti
  ///    has no exit-country control (CLI_REFERENCE: AETHER_TOR_COUNTRY is
  ///    the BridgeDB request country, not an exit pin). The pick stays a
  ///    remembered display anchor there;
  ///  * everything else → the plain wheel pick (null = no pin).
  String? _resolveCountryPick(ProtocolId modeId, EngineConfigSource config) {
    switch (modeId) {
      case ProtocolId.psiphonChain:
      case ProtocolId.psiphonOnly:
      case ProtocolId.psiphonReverse:
        return _nonAuto(config.psiphonLocation);
      case ProtocolId.torReverse:
        return _nonAuto(config.torLocation);
      case ProtocolId.torChain:
      case ProtocolId.torOnly:
        return null; // no core pin exists — never a fake flag
      default:
        return config.selectedCountryCode;
    }
  }

  static String? _nonAuto(String pick) =>
      pick == LocationWheelPolicy.autoCode ? null : pick;

  /// v4.34 — the time left until the SMART window's deadline (null when
  /// no window is set, or a floor of 1 s so a nearly-spent window still
  /// gives the stage one honest poll instead of a zero-duration timeout).
  Duration? _remainingUntil(DateTime? deadline) {
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) return const Duration(seconds: 1);
    return left;
  }

  /// v4.20 — one core-liveness poll. Returns the core's own error when the
  /// job has ended (done/failed/poll-threw), null while it runs. Shared by
  /// the listener wait and the probe-retry loop.
  String? _pollCoreOnce() {
    final jobId = _jobId;
    final core = _core;
    if (core == null || jobId == null) return null;
    try {
      final poll = core.jobPoll(jobId);
      if (poll.body['state'] == 'done') {
        return poll.error ?? describeJobOutcome(poll.body);
      }
      if (!poll.ok) {
        return poll.error;
      }
    } on AetherFfiException catch (e) {
      return e.message ?? e.code;
    }
    return null;
  }

  /// The listener wait of the v4.19 walk: polls the listener AND the core's
  /// job liveness. Returns true when the listener is up; when the core
  /// exits first, records its own error in [_coreFailureDuringStart] and
  /// returns false. Aborts on cancel (#3) — v4.26: via the generation, so
  /// the abort is permanent (the old flag reset let the walk resume).
  Future<bool> _waitForListenerFollowingCore(
    int gen,
    int port, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_stale(gen)) return false;
      if (await TunnelProbe.isListenerReady(port)) return !_stale(gen);
      // Core liveness — the core owns the truth about its own failure.
      final failure = _pollCoreOnce();
      if (failure != null) {
        _coreFailureDuringStart = failure;
        return false;
      }
      await Future<void>.delayed(_coreHealthInterval);
    }
    return false;
  }

  /// v4.31 — the shared probe→stats mapping: a GeoIP PSEUDO-country
  /// (loc=T1 — the Tor network; A1/A2/O1) is stripped to null instead of
  /// reaching the store, where it would show as the raw name «T1» with no
  /// flag (owner round 7). The real country for a tor exit is resolved
  /// afterwards from the exit relay's directory data (Onionoo by IP —
  /// [_resolveExitCountry]) and lands as [EngineExitCountryResolved].
  static EngineStatsUpdated statsEvent(
    TunnelProbeResult result, {
    int? downBytes,
    int? upBytes,
  }) => EngineStatsUpdated(
    pingMs: result.pingMs,
    downBytes: downBytes ?? 0,
    upBytes: upBytes ?? 0,
    exitCountryCode: result.countryIsPseudo ? null : result.exitCountryCode,
  );

  /// v4.31 — resolves the REAL country behind a pseudo-country exit: the
  /// trace only says `T1` (the Tor network), but its `ip=` names the exit
  /// relay, and Onionoo — the Tor network's own metrics API — answers
  /// `search=<ip>` with the relay's `country`. The fetch rides the live
  /// tunnel's own SOCKS listener (a direct fetch is blocked in exactly
  /// the markets this app serves). Fire-and-forget by design: unresolved
  /// ⇒ no event, and a walk superseded meanwhile (gen moved) stays silent.
  Future<void> _resolveExitCountry(int gen, int port, String exitIp) async {
    final code = await EgressLocations.resolveTorExitCountry(
      socksPort: port,
      exitIp: exitIp,
    );
    if (code == null || _stale(gen)) return;
    _emit(EngineExitCountryResolved(code));
  }

  /// v4.20 — the end-to-end probe RETRY loop (the single-shot probe failed
  /// every slow-bootstrapping mode: chain listeners are bound before their
  /// inner protocol exists, so the first SOCKS greeting simply hangs until
  /// the 20 s probe timeout). Retries within [budget] while following the
  /// core: a job that dies fails the walk immediately with the core's own
  /// error; a cancel aborts at the next checkpoint. Returns the successful
  /// probe's raw result, or null (budget exhausted / core died / cancelled).
  /// v4.26 — a probe success that belongs to a NEWER session (this walk was
  /// superseded mid-probe and the new core's listener answered) is NOT this
  /// walk's success: return null and let the staleness check silence it.
  Future<TunnelProbeResult?> _probeUntilReadyFollowingCore(
    int gen,
    int port, {
    required Duration budget,
    DateTime? deadline,
  }) async {
    final hardEnd = deadline ?? DateTime.now().add(budget);
    while (true) {
      if (_stale(gen)) return null;
      // v4.34 — the SMART window bounds each ATTEMPT too: a 20 s probe
      // timeout inside a 3 s remainder would blow the whole window on one
      // hung connect.
      final left = hardEnd.difference(DateTime.now());
      final attemptTimeout = deadline == null || left > _probeTimeout
          ? _probeTimeout
          : (left <= Duration.zero
                ? const Duration(milliseconds: 200)
                : left);
      try {
        final result = await TunnelProbe().trace(
          port: port,
          timeout: attemptTimeout,
        );
        if (_stale(gen)) return null;
        return result;
      } catch (e) {
        // v4.37 — keep the classified error for the failure screen: a
        // reset/refused on 127.0.0.1 names itself instead of surfacing as
        // an anonymous timeout after the budget runs out (the owner's
        // SocketException report).
        _probeLastErrorKind = classifyProbeError(e);
        // Probe failed — the core may have died; it owns the failure truth.
        final failure = _pollCoreOnce();
        if (failure != null) {
          _coreFailureDuringStart = failure;
          return null;
        }
        if (DateTime.now().isBefore(hardEnd)) {
          await Future<void>.delayed(_probeRetryInterval);
          continue;
        }
        return null; // budget exhausted — honest timeout, not a fake exit
      }
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;
    // v4.26 — the generation bump comes FIRST: every in-flight walk (and
    // the resume) is stale from this line on, permanently. The cancel owns
    // the terminal state; nothing the aborted walk does afterwards can
    // start/stop engines or emit progress. The old flag-based design reset
    // `_disconnecting` when THIS method finished — right when the walk's
    // next poll was due — so a cancelled walk RESUMED and kept running.
    ++_walkGeneration;
    _connecting = false; // no live walk remains after a cancel
    // Release anyone still waiting on connect-phase events.
    if (_tunnelUp != null && !_tunnelUp!.isCompleted) {
      _tunnelUp!.complete(false);
    }
    if (_permissionAnswer != null && !_permissionAnswer!.isCompleted) {
      _permissionAnswer!.complete(false);
    }
    await _hardCleanup();
    if (!_controller.isClosed) {
      _emitState(VpnState.disconnected);
    }
    _disconnecting = false;
  }

  // ---- helpers -------------------------------------------------------------

  void _emit(EngineEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void _emitState(VpnState state) =>
      _emit(EngineStateChanged(state));

  void _emitFail(String code, String? message) {
    // v4.28 — even a failed psiphon walk may have already received the
    // network's egress-region notice (it fires before establishment); a
    // failed connect must not lose the freshest real list we have.
    unawaited(_harvestPsiphonEgressRegions());
    _emit(EngineStateChanged(VpnState.failed, errorCode: code, message: message));
  }

  /// v4.28 — reads the captured core log and extracts the LAST
  /// `[*] psiphon can leave from: …` line (the pinned core's rendering of
  /// the Psiphon network's `AvailableEgressRegions` notice — one per
  /// session, psiphon.rs note()). Found ⇒ emit [EngineEgressRegions] +
  /// cache it. Never throws: a missing bridge/parse miss is a no-op (the
  /// wheel keeps the seed / the last cached set).
  Future<void> _harvestPsiphonEgressRegions() async {
    if (_egressHarvestBusy) return; // one read in flight is enough
    _egressHarvestBusy = true;
    try {
      final snapshot = await _coreLog.read(tailBytes: 96 * 1024);
      final regions = EgressLocations.parsePsiphonEgressRegions(
        snapshot.text,
      );
      if (regions == null || regions.isEmpty) return;
      await EgressLocations.savePsiphonEgress(regions);
      _emit(EngineEgressRegions(regions));
    } catch (_) {
      // no platform bridge (tests) / read failure — nothing to harvest
    } finally {
      _egressHarvestBusy = false;
    }
  }

  /// Guards [_harvestPsiphonEgressRegions] against overlapping reads
  /// (connected-emission + a failed-walk emission can race).
  bool _egressHarvestBusy = false;

  /// v4.28 — the captured-core-log reader the egress harvest tails.
  final CoreLogReader _coreLog = CoreLogReader();

  Future<_PlatformPaths> _paths() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('paths');
    if (raw == null) {
      throw const AetherFfiException('pathsMissing', 'paths returned null');
    }
    return _PlatformPaths(
      filesDir: raw['filesDir'] as String? ?? '',
      nativeLibraryDir: raw['nativeLibraryDir'] as String? ?? '',
      lyrebirdPath: raw['lyrebirdPath'] as String?,
      psiphonPath: raw['psiphonPath'] as String?,
    );
  }

  /// Asks the platform whether the VPN consent is needed; when it is, waits
  /// for the user's answer (surfaced as `waitingForPermissions` first).
  /// v4.26 — generation-aware: a cancel during the dialog aborts the wait,
  /// and a walk that was superseded reports nothing.
  Future<bool> _ensureVpnPermission(int gen) async {
    final Map<Object?, Object?> answer;
    try {
      answer =
          await _channel.invokeMethod<Map<Object?, Object?>>('prepareVpn') ??
          const {};
    } on MissingPluginException {
      if (!_stale(gen)) {
        _emitFail(
          'platformBridgeMissing',
          'the aethone/engine platform channel is not available in this build',
        );
      }
      return false;
    }
    if (_stale(gen)) return false;
    if (answer['needsPermission'] != true) return true;

    _emitState(VpnState.waitingForPermissions);
    final permissionAnswer = Completer<bool>();
    _permissionAnswer = permissionAnswer;
    final granted = await permissionAnswer.future.timeout(
      _permissionBudget,
      onTimeout: () => false,
    );
    _permissionAnswer = null;
    return granted && !_stale(gen);
  }

  void _startTicker(int gen) {
    _ticker?.cancel();
    _tickerGeneration = gen;
    _ticker = Timer.periodic(_statsInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    // v4.26 — the tick belongs to its walk's generation (a cancelled or
    // superseded session's ticker dies with it) and never re-enters (a
    // 20 s probe inside a 5 s interval used to stack up to four
    // concurrent probes on one core).
    final gen = _tickerGeneration;
    if (gen == null || _stale(gen) || _disconnecting || _ticking) return;
    _ticking = true;
    try {
      await _tickInner();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tickInner() async {
    final core = _core;
    final jobId = _jobId;

    // 1. Core liveness (when a job id is known — spawned this lifetime OR
    //    adopted from the process-durable store after an isolate restart,
    //    v4.26: a resumed session now watches its core too).
    if (core != null && jobId != null) {
      try {
        final poll = core.jobPoll(jobId);
        final state = poll.body['state'];
        if (state == 'done') {
          final result = poll.body['result'];
          final inner = result is Map ? result['state'] : null;
          final normal = inner is String;
          await _onEngineDied(
            normal && inner == 'stopped' ? 'engineStopped' : 'engineClosed',
            normal
                ? 'the core exited on its own (state: $inner)'
                : describeJobOutcome(poll.body),
          );
          return;
        }
        if (!poll.ok) {
          await _onEngineDied('engineFailed', poll.error);
          return;
        }
      } on AetherFfiException {
        await _onEngineDied('enginePollFailed', 'job poll threw');
        return;
      }
    }

    // 2. Real stats: zeptun counters (tunnel mode) + a fresh end-to-end
    //    probe for ping/exit-country.
    int? rxBytes;
    int? txBytes;
    if (_activeMode == ConnectionMode.tunnel) {
      try {
        final counters =
            await _channel.invokeMethod<Map<Object?, Object?>>(
              'zeptunCounters',
            ) ??
            const {};
        rxBytes = (counters['rxBytes'] as num?)?.toInt();
        txBytes = (counters['txBytes'] as num?)?.toInt();
      } on PlatformException {
        // The service may be mid-stop; stats are best-effort, the health
        // probe below is the authority.
      }
    }
    try {
      final result = await TunnelProbe().trace(
        port: _activePort,
        timeout: _probeTimeout,
      );
      _probeStrikes = 0;
      _degradedTicks = 0;
      // v4.31 — the tick strips pseudo-countries (loc=T1) to null so it
      // can never overwrite the resolved real exit with the raw «T1».
      _emit(
        statsEvent(
          result,
          downBytes:
              (txBytes ?? 0) < 0
                  ? 0
                  : txBytes ?? 0, // TUN tx = into the device = download
          upBytes:
              (rxBytes ?? 0) < 0 ? 0 : rxBytes ?? 0, // TUN rx = upload
        ),
      );
      // v4.34 — the walk-time Tor exit-country fetch races the circuit
      // build and often loses («تور مکان اتصال رو … انتخاب خودکار نشون
      // میده در صورتی که لوکیشن هلند هست»): every pseudo-country report
      // is one more retry, spread a tick apart, until the real country
      // lands (EngineExitCountryResolved) or the budget runs out.
      if (result.countryIsPseudo &&
          result.exitIp != null &&
          _exitResolveTries < _exitResolveMaxTries) {
        _exitResolveTries++;
        unawaited(
          _resolveExitCountry(_tickerGeneration!, _activePort, result.exitIp!),
        );
      }
    } catch (_) {
      // v4.34 — GRADED health (owner round 10: «روی حالت تور اپ میره روی
      // اتصال مجدد ولی اتصال برقراره و دیتا داره جا به جا میشه»): a tor
      // circuit can simply be slower than the 20 s trace while REAL
      // traffic flows, so a trace failure alone must not flip the app to
      // «در حال اتصال مجدد»:
      //  * the SOCKS listener REFUSES → the tunnel is truly down — the
      //    old 2-strike rule (fast, decisive);
      //  * the listener still ANSWERS → DEGRADED, not dead: the strike
      //    counters reset (no reconnecting flap) and a separate
      //    minute-long continuous-degradation budget decides instead.
      var listenerAlive = false;
      try {
        listenerAlive = await TunnelProbe.isListenerReady(_activePort);
      } catch (_) {
        listenerAlive = false;
      }
      if (!listenerAlive) {
        _probeStrikes++;
        _degradedTicks = 0;
        if (_probeStrikes >= 2) {
          _probeStrikes = 0;
          _emit(const EngineHealthProbeFailed());
        }
      } else {
        _probeStrikes = 0;
        _degradedTicks++;
        if (_degradedTicks >= _degradedTicksBudget) {
          _degradedTicks = 0;
          _emit(const EngineHealthProbeFailed());
        }
      }
    }
  }

  /// The core died while we believed we were connected: stop faking, tear
  /// everything down, report failed (any → failed is legal, §8).
  Future<void> _onEngineDied(String code, String? message) async {
    // v4.26 — a disconnect already in flight owns the terminal state (and
    // its own cleanup); a concurrent death probe must not flip the UI to
    // `failed` right after the user asked to disconnect.
    if (_disconnecting) return;
    _ticker?.cancel();
    _ticker = null;
    _tickerGeneration = null;
    _jobId = null;
    await _clearCoreJob();
    if (_activeMode == ConnectionMode.tunnel) {
      _tornDownTunnelSession = _tunnelSession;
      try {
        await _channel.invokeMethod<void>('stopVpn');
      } on PlatformException {
        // already down — nothing else to do
      }
    } else {
      // v4.19 (#7): release the proxy hold too — a dead core must not keep
      // the process pinned.
      try {
        await _channel.invokeMethod<void>('stopCoreHold');
      } on PlatformException {
        // already down
      }
    }
    _emitFail(code, message);
  }

  /// Full teardown: zeptun (via the service) + the core-hold service (proxy)
  /// + aether job. Safe to call in any state, twice, or when nothing is
  /// running. v4.21: the cancel grace grew from 1 s to [_cancelGrace] — the
  /// registry entry is only freed after the job actually reached `done`
  /// (or the grace ran out), so a slow abort can no longer leak a live job
  /// with bound listeners into the "disconnected" state.
  Future<void> _hardCleanup() async {
    _ticker?.cancel();
    _ticker = null;
    _tickerGeneration = null;
    if (_tunnelUp != null && !_tunnelUp!.isCompleted) {
      _tunnelUp!.complete(false);
    }
    _tunnelUp = null;
    if (_permissionAnswer != null && !_permissionAnswer!.isCompleted) {
      _permissionAnswer!.complete(false);
    }
    _permissionAnswer = null;
    if (_activeMode == ConnectionMode.tunnel) {
      // v4.26 — mark the session WE are stopping: the service's
      // asynchronous onDestroy emits `down: destroy` whenever the system
      // processes the stop, and that late event must never surface as a
      // failure after a clean disconnect.
      _tornDownTunnelSession = _tunnelSession;
      try {
        await _channel.invokeMethod<void>('stopVpn');
      } on PlatformException {
        // already stopped
      } on MissingPluginException {
        // no platform (tests) — nothing to stop
      }
    } else {
      // v4.19 (#7): proxy mode — release the process hold so an idle app
      // costs nothing in the background.
      try {
        await _channel.invokeMethod<void>('stopCoreHold');
      } on PlatformException {
        // already stopped
      } on MissingPluginException {
        // no platform (tests)
      }
    }
    final jobId = _jobId;
    final core = _core;
    _jobId = null;
    if (jobId != null && core != null) {
      try {
        core.jobCancel(jobId);
        // Cooperative cancel: give the runtime the grace to run the abort
        // cascade (TaskGuard drops → chain children killed → listeners
        // released), then free the registry entry either way (free cancels
        // again by contract).
        final deadline = DateTime.now().add(_cancelGrace);
        while (DateTime.now().isBefore(deadline)) {
          final poll = core.jobPoll(jobId);
          if (poll.body['state'] == 'done') break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        core.jobFree(jobId);
      } on AetherFfiException {
        // job already gone
      }
    }
    // v4.26 — the durable job id dies with the session (a later isolate
    // must not adopt a cancelled core).
    await _clearCoreJob();
  }

  // ---- durable job id (v4.26 — isolate-restart hardening) ------------------

  /// Records the live job id on the PROCESS side (the Kotlin companion
  /// outlives the Dart isolate). Best-effort: an older platform build
  /// simply keeps none, and this lifetime's in-memory id still works.
  Future<void> _recordCoreJob() async {
    final id = _jobId;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('setCoreJob', {'job': id});
    } on PlatformException {
      // older platform — ignore
    } on MissingPluginException {
      // no platform (tests) — ignore
    }
  }

  /// Clears the process-side job id (the job is cancelled/dead).
  Future<void> _clearCoreJob() async {
    try {
      await _channel.invokeMethod<void>('clearCoreJob');
    } on PlatformException {
      // older platform — ignore
    } on MissingPluginException {
      // no platform (tests) — ignore
    }
  }

  /// Adopts the process-side job id after an isolate restart. The Rust job
  /// registry is process-scoped: a core the DEAD isolate spawned is still
  /// running (listener bound, WARP session up) while the fresh adapter had
  /// no id — a disconnect then cancelled NOTHING, the orphan kept the SOCKS
  /// port bound and the NEXT connect died on «address already in use»
  /// until the app was force-closed (owner round 4: «باید اپ رو کلا بندی
  /// تا اتصال تونل قطع بشه»). Only called once a LIVE listener proved the
  /// core really is alive (a restarted process has an empty registry).
  Future<void> _adoptDurableJob() async {
    if (_jobId != null) return;
    try {
      final reply =
          await _channel.invokeMethod<Map<Object?, Object?>>('getCoreJob');
      final id = (reply?['job'] as num?)?.toInt();
      if (id == null || id <= 0) return;
      _jobId = id;
      // The core handle: tests inject a factory; production re-opens the
      // (process-global) library. A failure here keeps the id adopted —
      // the next connect's port-free wait still honors the live listener.
      _core ??= _coreFactory == null ? AetherCore.open() : _coreFactory();
    } on PlatformException {
      // older platform — nothing to adopt
    } on MissingPluginException {
      // no platform (tests) — nothing to adopt
    } on AetherFfiException {
      // no embedded library in this build — keep the id, drop the handle
    }
  }

  // ---- platform → Dart -----------------------------------------------------

  Future<void> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onTunnelEvent':
        final args = (call.arguments as Map?)?.cast<Object?, Object?>();
        // v4.21 — session filter: events from a service instance of an
        // OLDER tunnel session are dropped. A stale instance being torn
        // down after a quick reconnect used to deliver a late
        // `down/destroy` that failed the NEW walk (owner device-test
        // «در حالت تونل … tunnelStartFailed / destroy»). Events without a
        // session stamp (older platform builds) stay accepted.
        final session = args?['session'];
        if (session is int && session != _tunnelSession) return;
        final event = args?['event'] as String?;
        switch (event) {
          case 'up':
            _tunnelAlive = true;
            if (_tunnelUp != null && !_tunnelUp!.isCompleted) {
              _tunnelUp!.complete(true);
            }
          case 'down':
          case 'revoked':
            // v4.20 — keep the platform's own reason (establish-failed,
            // start-threw:<Ex>, destroy…) for the failed screen, and track
            // the leg's liveness for the walk's post-probe honesty check.
            _tunnelAlive = false;
            _tunnelDownReason = (args?['reason'] as String?) ?? event;
            if (_tunnelUp != null && !_tunnelUp!.isCompleted) {
              _tunnelUp!.complete(false);
            }
            // v4.26 — a teardown WE initiated (user disconnect / walk
            // cleanup / engine death): the service's onDestroy fires
            // whenever the system processes the stop — often AFTER the
            // disconnect already finished. That expected event must never
            // surface as a failure; the disconnect owns the terminal state
            // (owner round 4: a clean disconnect used to flip the UI to
            // `failed(tunnelDown: destroy)` a moment later).
            if (session is int && session == _tornDownTunnelSession) {
              break;
            }
            // A tunnel that goes down while connected is surfaced
            // immediately instead of waiting for the next health probe.
            if (!_connecting && !_disconnecting) {
              _ticker?.cancel();
              _ticker = null;
              _tickerGeneration = null;
              _jobId = null;
              _emitFail(
                event == 'revoked' ? 'tunnelRevoked' : 'tunnelDown',
                event == 'revoked'
                    ? 'the VPN was revoked (system UI or another VPN took over)'
                    : (_tunnelDownReason ?? 'the VPN service went down'),
              );
            }
          case 'permission':
            if (_permissionAnswer != null && !_permissionAnswer!.isCompleted) {
              _permissionAnswer!.complete(args?['granted'] == true);
            }
        }
      default:
        // v4.40 — the desktop window/tray events (no payload; the bridge
        // owns the decision logic). Unknown methods stay an error.
        if (call.method == 'onWindowCloseRequested') {
          onWindowCloseRequested?.call();
          return;
        }
        if (call.method == 'onTrayToggleConnection') {
          onTrayToggleConnection?.call();
          return;
        }
        throw MissingPluginException(
          'unknown aethone/engine method: ${call.method}',
        );
    }
  }

  /// If the Flutter engine was restarted while a foreground service kept
  /// the session alive, resume the honest state instead of showing
  /// `disconnected` while the device is actually tunnelled/proxied.
  /// v4.19 (#7): BOTH holders are recognized — AethoneVpnService (tunnel)
  /// and CoreHoldService (proxy) — so re-entering the app after swiping it
  /// away shows the TRUE state (owner: «وقتی وارد اپ میشم مجدد میره رو حالت
  /// اتصال مجدد»). Proxy resume relies on the in-process core still
  /// listening on the held port (same process — CoreHoldService kept it
  /// alive); if the listener is gone the session is honestly dead.
  ///
  /// v4.26 hardening (owner round 4 — the «تونل فعاله» complaints after
  /// reopening the app):
  ///  * the resume runs under the WALK GENERATION — any user action
  ///    supersedes it (the old code could emit its starting/connected walk
  ///    INTO a user-initiated one and fail the machine with
  ///    illegalTransition, or stop a JUST-STARTED service mid-walk);
  ///  * `_activeMode`/`_activePort` are set BEFORE the (up to 20 s) probe —
  ///    a disconnect during the probe used to stop the WRONG holder (the
  ///    default `proxy` → stopCoreHold) and leave the TUNNEL RUNNING;
  ///  * the durable job id is adopted so the resumed session's disconnect
  ///    actually cancels the core (see [_adoptDurableJob]).
  Future<void> _resyncAfterRestart({bool force = false}) async {
    // v4.36 — a REAL desktop app (its runner sets the
    // AETHONE_DESKTOP_ENGINE=1 env flag before the engine starts) answers
    // the same `aethone/engine` surface, so the honest resume runs there
    // too. The TEST hosts never set the flag, keeping the v4.26
    // resume-window suite's semantics exactly as shipped. Android untouched.
    final desktop =
        (Platform.isLinux || Platform.isWindows) &&
        Platform.environment['AETHONE_DESKTOP_ENGINE'] == '1';
    if (!Platform.isAndroid && !desktop && !force) return;
    // v4.21 — never race a user-initiated walk: bind() can fire while an
    // activity recreation spins up a fresh engine, and a zombie probe here
    // used to stop the LIVE session's VPN service mid-walk.
    if (_connecting || _disconnecting) return;
    final gen = _walkGeneration; // v4.26 — the resume lives under this gen
    try {
      final status =
          await _channel.invokeMethod<Map<Object?, Object?>>('vpnStatus') ??
          const {};
      if (_stale(gen)) return; // a user action superseded the resync
      if (status['running'] == true) {
        final port = (status['port'] as num?)?.toInt() ?? 1819;
        // v4.26 — the holder identity is known BEFORE the probe: a
        // disconnect during the probe must stop the RIGHT service.
        _activePort = port;
        _activeMode = ConnectionMode.tunnel;
        if (!await TunnelProbe.isListenerReady(port)) {
          if (_stale(gen)) return;
          // Service alive but the core is gone — stop the zombie service; the
          // user reconnects through the normal flow.
          await _channel.invokeMethod<void>('stopVpn');
          await _clearCoreJob();
          return;
        }
        if (_stale(gen)) return;
        await _adoptDurableJob();
        await _resumeSession(gen, port, ConnectionMode.tunnel);
        return;
      }
      // Proxy mode: the core-hold service keeps the process (and the
      // in-process core) alive after the app was swiped away.
      final hold =
          await _channel.invokeMethod<Map<Object?, Object?>>('coreHoldStatus') ??
          const {};
      if (_stale(gen)) return;
      if (hold['running'] != true) return;
      final port = (hold['port'] as num?)?.toInt() ?? 1819;
      _activePort = port;
      _activeMode = ConnectionMode.proxy;
      if (!await TunnelProbe.isListenerReady(port)) {
        if (_stale(gen)) return;
        // Process alive but the core is gone — release the hold; the user
        // reconnects through the normal flow.
        await _channel.invokeMethod<void>('stopCoreHold');
        await _clearCoreJob();
        return;
      }
      if (_stale(gen)) return;
      await _adoptDurableJob();
      await _resumeSession(gen, port, ConnectionMode.proxy);
    } on PlatformException {
      // platform not ready yet — the next connect() will sort it out
    } on SocketException {
      // probe failed — treat as not connected
    }
  }

  /// The shared resume walk (legal per §8: starting → connecting →
  /// connected) once a live listener on [port] was proven. v4.26 —
  /// generation-guarded (a user action supersedes the resume) and a FAILED
  /// resume probe tears the zombie session down instead of leaving a
  /// half-alive service for the next connect to fight.
  Future<void> _resumeSession(int gen, int port, ConnectionMode mode) async {
    _activePort = port;
    _activeMode = mode;
    try {
      final result = await TunnelProbe().trace(
        port: port,
        timeout: _probeTimeout,
      );
      if (_stale(gen)) return;
      _emitState(VpnState.starting);
      _emitState(VpnState.connecting);
      _emit(statsEvent(result));
      _emitState(VpnState.connected);
      // v4.31 — same pseudo-country resolution as the fresh walk (a Tor
      // exit answers loc=T1; the real country comes from Onionoo by IP).
      if (result.countryIsPseudo && result.exitIp != null) {
        unawaited(_resolveExitCountry(gen, port, result.exitIp!));
      }
      _startTicker(gen);
    } catch (_) {
      if (_stale(gen)) return;
      // The session is a zombie (listener up, data path dead) — stop it so
      // the user's next connect starts clean instead of losing the bind
      // race against a listener nothing serves.
      await _hardCleanup();
    }
  }

  /// v4.26 — test seam for [_resyncAfterRestart] (the platform gate keeps
  /// it inert on the desktop VM; tests drive it with [force]).
  @visibleForTesting
  Future<void> debugResync() => _resyncAfterRestart(force: true);

  @visibleForTesting
  Future<void> debugTick() => _tick();
}

class _PlatformPaths {
  const _PlatformPaths({
    required this.filesDir,
    required this.nativeLibraryDir,
    this.lyrebirdPath,
    this.psiphonPath,
  });

  final String filesDir;
  final String nativeLibraryDir;

  /// v4.36 — optional platform-resolved child-core paths (null on Android:
  /// the Kotlin channel answers only the two legacy fields, so the Android
  /// arg strings stay exactly as before).
  final String? lyrebirdPath;
  final String? psiphonPath;
}

/// v4.34 — a connected candidate of the SMART tour: which tile ran, which
/// per-variant settings it ran with, the measured quality (best ping of
/// the phase, ms) and where in the tour it landed (the tie-breaker).
class _SmartConnector {
  const _SmartConnector({
    required this.candidate,
    required this.settings,
    required this.qualityMs,
    required this.tourIndex,
  });

  final ProtocolId candidate;
  final CoreSettings? settings;
  final int qualityMs;
  final int tourIndex;
}
