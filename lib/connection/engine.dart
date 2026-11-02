/// Engine boundary — the seam between the Flutter UI and the platform
/// service layer that will own Aether + zeptun (architecture B+, prompt §3/§7).
///
/// In UI step 1 NO platform layer exists yet, so the default adapter is
/// `EngineNotWiredAdapter`: it fails honestly with `engineNotWired` instead of
/// ever pretending to be connected. A clearly-gated preview adapter exists for
/// UI development only (never in release builds) — it animates the state
/// machine so every visual state can be built and golden-tested.
///
/// Rules carried over from the prompt:
///  * events are TYPED — the UI never parses log lines;
///  * `Connected` is only emitted after the end-to-end probe passes (§6.6);
///  * secrets never appear in events or logs.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_assets.dart';
import 'connection_state.dart';

/// Minimal `ProxyEndpoint` model (prompt §7): filled only from the real
/// listener configuration — never guessed.
class ProxyEndpoint {
  const ProxyEndpoint({
    required this.modeId,
    required this.host,
    required this.port,
    required this.supportsUdp,
    required this.isReady,
  });

  final ProtocolId modeId;
  final String host;
  final int port;
  final bool supportsUdp;
  final bool isReady;
}

/// Typed engine events (prompt §7 `onEngineEvent`).
sealed class EngineEvent {
  const EngineEvent();
}

/// A state change that is LEGAL per the machine — the adapter must respect
/// the transition table; the store enforces it.
class EngineStateChanged extends EngineEvent {
  const EngineStateChanged(this.state, {this.errorCode, this.message});
  final VpnState state;
  final String? errorCode;
  final String? message;
}

/// Periodic health probe failed ⇒ store downgrades to `reconnecting` (§6).
class EngineHealthProbeFailed extends EngineEvent {
  const EngineHealthProbeFailed();
}

class EngineEndpointChanged extends EngineEvent {
  const EngineEndpointChanged(this.endpoint);
  final ProxyEndpoint? endpoint;
}

/// Live counters (zeptun stats / ping through the tunnel). Only real values
/// are ever delivered here.
class EngineStatsUpdated extends EngineEvent {
  const EngineStatsUpdated({
    this.pingMs,
    this.downBytes = 0,
    this.upBytes = 0,
    this.exitCountryCode,
  });
  final int? pingMs;
  final int downBytes;
  final int upBytes;
  final String? exitCountryCode;
}

/// Structured log line (level + message; secrets already stripped upstream).
class EngineLogLine extends EngineEvent {
  const EngineLogLine(this.level, this.message);
  final String level;
  final String message;
}

/// The seam the UI talks to. The production implementation (M2) drives the
/// platform service (MethodChannel/FFI) that owns both engines.
///
/// Division of responsibility (UI step 1): the STORE owns user-intent
/// transitions (`starting`, `disconnecting`); adapters only report PROGRESS
/// (`waitingForPermissions`, `connecting`, `connected`, `disconnected`,
/// `failed`). This keeps the machine single-flight and retry-legal.
abstract class EngineAdapter {
  Stream<EngineEvent> get events;
  Future<void> connect();
  Future<void> disconnect();
}

/// Default adapter until the native service lands (M2): fails honestly.
class EngineNotWiredAdapter implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    _controller.add(
      const EngineStateChanged(
        VpnState.failed,
        errorCode: 'engineNotWired',
        message: 'Native engine layer is not wired yet (milestone M2).',
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _controller.add(const EngineStateChanged(VpnState.disconnected));
  }

  void dispose() => _controller.close();
}

/// PREVIEW-ONLY adapter (UI development / golden tests). Gated behind
/// `--dart-define=PREVIEW_MODE=true` AND never active in release builds.
/// It simulates the legal state walk so every visual state can be exercised;
/// it must NEVER ship enabled — see `PreviewEngineAdapter.allowed`.
class PreviewEngineAdapter implements EngineAdapter {
  PreviewEngineAdapter({
    // v4.11 (owner defect #10): the connecting walk must last long enough
    // for the scanning halo behind the central icon to be SEEN and for the
    // swipe gesture to feel like a real handshake (~2.6 s). Preview-only.
    this.stepDelay = const Duration(milliseconds: 2600),
    this.samplePingMs = 146,
    this.sampleExitCountry = 'ir',
  });

  final Duration stepDelay;
  final int samplePingMs;
  final String sampleExitCountry;

  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  static const bool requested = bool.fromEnvironment('PREVIEW_MODE');

  /// Preview simulation is allowed only in non-release builds with the
  /// explicit opt-in flag.
  static bool get allowed => requested && !kReleaseMode;

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    _emit(const EngineStateChanged(VpnState.connecting));
    await Future<void>.delayed(stepDelay);
    // End-to-end probe "passed" in preview — this is a SIMULATION, clearly
    // documented; production Connected only comes from the real probe.
    _emit(const EngineStateChanged(VpnState.connected));
    _emit(
      EngineStatsUpdated(
        pingMs: samplePingMs,
        exitCountryCode: sampleExitCountry,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    await Future<void>.delayed(stepDelay);
    _emit(const EngineStateChanged(VpnState.disconnected));
  }

  void _emit(EngineEvent e) => _controller.add(e);

  void dispose() => _controller.close();
}
