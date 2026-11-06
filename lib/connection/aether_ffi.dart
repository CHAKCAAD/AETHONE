/// dart:ffi binding to the embedded Aether core (`libaether.so`) — the
/// architecture-B+ seam of prompt §3: the Rust core runs IN-PROCESS, driven
/// through its stable C API (`aether/src/ffi.rs` at the frozen pin).
///
/// Contract (verified at the pinned source, ffi.rs):
///  * `aether_core_start(args_json)` — args is a JSON array of CLI strings;
///    returns `{"ok":true,"job":<id>}`. The job runs on Aether's own tokio
///    runtime threads (never blocks the caller).
///  * `aether_job_poll(id)` — `{"ok":true,"state":"running"}` or
///    `{"state":"done","result":{"state":"closed"|"stopped"}}` or
///    `{"ok":false,"error":"…"}` for a failed core.
///  * `aether_job_cancel(id)` / `aether_job_free(id)` — cancellation is
///    cooperative; `free` also removes the job from the registry.
///  * every returned `char*` is malloc'd by Rust and MUST be released with
///    `aether_string_free`.
///
/// Rules carried over from the prompt: events are TYPED (the poll results are
/// parsed into plain maps here, never raw log lines); secrets never appear in
/// events or logs.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _VersionC = Pointer<Uint8> Function();
typedef _VersionDart = Pointer<Uint8> Function();
typedef _StringInC = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _StringInDart = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _JobC = Pointer<Uint8> Function(Uint64);
typedef _JobDart = Pointer<Uint8> Function(int);
typedef _StringFreeC = Void Function(Pointer<Uint8>);
typedef _StringFreeDart = void Function(Pointer<Uint8>);

/// Thrown when `libaether.so` cannot be opened (debug builds without the
/// packaged native libraries) or the C API answers nonsense.
class AetherFfiException implements Exception {
  const AetherFfiException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() =>
      'AetherFfiException($code${message == null ? '' : ': $message'})';
}

/// One parsed reply of the C API (`{"ok":…}` JSON object).
class AetherReply {
  AetherReply(this.ok, this.body);

  final bool ok;

  /// The reply fields minus the `ok` marker (e.g. `{"job": 3}`).
  final Map<String, Object?> body;

  String? get error => body['error'] as String?;
}

/// Injectable view of the embedded core — production opens [AetherCore];
/// tests substitute a fake (the real .so only exists on a device).
abstract class AetherCoreApi {
  int coreStart(List<String> args);
  AetherReply jobPoll(int id);
  bool jobCancel(int id);
  bool jobFree(int id);
}

/// Thin, honest wrapper around the four calls the app needs. No state beyond
/// the open library handle; one Aether core per process (prompt: «در هر فرایند
/// فقط یک موتور zeptun اجرا شود» — same discipline for Aether).
class AetherCore implements AetherCoreApi {
  AetherCore._(this._lib);

  final DynamicLibrary _lib;

  static AetherCore? _instance;

  /// The embedded core's file name on THIS platform (v4.36 desktop round):
  /// Android and Linux both load `libaether.so` (the Android name stays
  /// byte-identical — the desktop change must never disturb it); Windows
  /// cdylibs are named `aether.dll` by cargo.
  static String get _libraryName =>
      Platform.isWindows ? 'aether.dll' : 'libaether.so';

  /// Opens (or returns the already-open) embedded core. Throws
  /// [AetherFfiException] with code `libraryMissing` when the cdylib is
  /// not packaged in this build.
  static AetherCore open() {
    final existing = _instance;
    if (existing != null) return existing;
    final name = _libraryName;
    final DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open(name);
    } catch (e) {
      throw AetherFfiException(
        'libraryMissing',
        '$name could not be opened (is the native core packaged in '
        'this build?): $e',
      );
    }
    return _instance = AetherCore._(lib);
  }

  /// `aether_version()` → `{"version": "2.4.0"}`.
  String version() {
    final reply = _call(() {
      final fn =
          _lib
              .lookupFunction<_VersionC, _VersionDart>('aether_version')
              .call();
      return fn;
    });
    return (reply.body['version'] as String?) ?? 'unknown';
  }

  /// `aether_core_start(args)` → the spawned job id.
  ///
  /// The arguments are the exact CLI flags of the pinned core (see
  /// docs/CLI_REFERENCE.md); the platform adapter builds them from the user's
  /// configuration.
  @override
  int coreStart(List<String> args) {
    final reply = _call(() {
      final payload = _toNative(jsonEncode(args));
      try {
        return _lib
            .lookupFunction<_StringInC, _StringInDart>('aether_core_start')
            .call(payload);
      } finally {
        malloc.free(payload);
      }
    });
    final job = reply.body['job'];
    if (reply.ok && job is int && job > 0) return job;
    throw AetherFfiException(
      'coreStartFailed',
      reply.error ?? 'the core did not return a job id',
    );
  }

  /// `aether_job_poll(id)` — `state` is `running` or `done`; a done job
  /// carries `result` (`{"state":"closed"|"stopped"}`) or an error.
  @override
  AetherReply jobPoll(int id) => _call(() => _jobCall('aether_job_poll', id));

  /// `aether_job_cancel(id)` — cooperative cancel for the running core.
  @override
  bool jobCancel(int id) => _jobBool('aether_job_cancel', id);

  /// `aether_job_free(id)` — cancels AND removes the job from the registry.
  @override
  bool jobFree(int id) => _jobBool('aether_job_free', id);

  // ---- internals -----------------------------------------------------------

  Pointer<Uint8> _jobCall(String symbol, int id) =>
      _lib.lookupFunction<_JobC, _JobDart>(symbol).call(id);

  bool _jobBool(String symbol, int id) {
    final reply = _call(() => _jobCall(symbol, id));
    return reply.ok;
  }

  AetherReply _call(Pointer<Uint8> Function() invoke) {
    final raw = invoke();
    if (raw == nullptr) {
      throw const AetherFfiException('nullReply', 'the core returned null');
    }
    try {
      final text = _fromNative(raw);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        final ok = decoded['ok'] == true;
        final body = Map<String, Object?>.from(decoded)..remove('ok');
        return AetherReply(ok, body);
      }
      throw AetherFfiException('badReply', 'not a json object: $text');
    } on FormatException catch (e) {
      throw AetherFfiException('badReply', e.message);
    } finally {
      _stringFree(raw);
    }
  }

  void _stringFree(Pointer<Uint8> raw) {
    _lib
        .lookupFunction<_StringFreeC, _StringFreeDart>('aether_string_free')
        .call(raw);
  }

  static Pointer<Uint8> _toNative(String text) {
    final units = utf8.encode(text);
    final ptr = malloc<Uint8>(units.length + 1);
    final view = ptr.asTypedList(units.length + 1)
      ..setRange(0, units.length, units)
      ..[units.length] = 0;
    assert(view.last == 0, 'the C string must be NUL-terminated');
    return ptr;
  }

  /// Manual NUL-terminated UTF-8 decode — keeps this binding dependency-free
  /// (package:ffi is not otherwise needed by the app).
  static String _fromNative(Pointer<Uint8> raw) {
    var len = 0;
    while (raw[len] != 0) {
      len++;
    }
    return utf8.decode(raw.asTypedList(len));
  }

  /// Debug aid: printable version for device logs (never secrets).
  @override
  String toString() => 'AetherCore(${kReleaseMode ? "release" : "debug"})';
}
