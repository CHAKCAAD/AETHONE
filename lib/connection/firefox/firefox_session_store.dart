/// Firefox session storage — the Keystore-backed secret store.
///
/// Security contract (docs/FIREFOX_VPN_SECURITY.md; phase-1 decree):
///  * session tokens are NEVER stored in plain files, SharedPreferences,
///    argv, environment, or logs;
///  * at rest they live ONLY in `<filesDir>/firefox/session.vault` as
///    Android-Keystore-encrypted bytes (AES/GCM, key inside
///    AndroidKeyStore, never exportable);
///  * the plaintext pair exists only (a) in memory right after decrypt,
///    (b) on the engine's private stdin pipe during a connect;
///  * [clear] is the logout-grade wipe (file + in-memory copy).
///
/// Phase 1 sources of the pair: the controlled injection (the developer
/// puts a session into the store through the debug path — Phase 2 adds
/// the real FxA login flow). Unit tests use the fake codec (plaintext
/// data in tests is explicitly allowed; LIVE-connection claims with fake
/// data are not).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'firefox_protocol.dart';

/// Encrypts/decrypts the vault bytes. Production: Android Keystore
/// AES/GCM through the `aethone/engine` MethodChannel. Tests: identity
/// codec (never used for real sessions).
abstract class FirefoxSecretCodec {
  Future<List<int>> encrypt(List<int> plaintext);
  Future<List<int>> decrypt(List<int> ciphertext);
}

/// The platform (Android Keystore) codec.
class KeystoreSecretCodec implements FirefoxSecretCodec {
  static const MethodChannel _channel = MethodChannel('aethone/engine');

  @override
  Future<List<int>> encrypt(List<int> plaintext) async {
    final blob = await _channel.invokeMethod<Uint8List>(
      'firefoxEncrypt',
      {'plaintext': Uint8List.fromList(plaintext)},
    );
    return blob?.toList() ?? const [];
  }

  @override
  Future<List<int>> decrypt(List<int> ciphertext) async {
    final blob = await _channel.invokeMethod<Uint8List>(
      'firefoxDecrypt',
      {'ciphertext': Uint8List.fromList(ciphertext)},
    );
    return blob?.toList() ?? const [];
  }
}

/// The session vault.
class FirefoxSessionStore {
  FirefoxSessionStore({required this.vaultPath, this.codec});

  /// e.g. `<filesDir>/firefox/session.vault`.
  final String vaultPath;

  final FirefoxSecretCodec? codec;

  FirefoxSessionAuth? _memory;

  /// Loads the stored pair (memory → vault). null = no session stored;
  /// a corrupt/undecryptable vault is treated as ABSENT (and wiped) —
  /// a Keystore key reset (new install, cleared credentials) must not
  /// brick the engine selection.
  Future<FirefoxSessionAuth?> load() async {
    final mem = _memory;
    if (mem != null) return mem;
    final secretCodec = codec ?? _platformCodec();
    if (secretCodec == null) return null;
    try {
      final raw = await File(vaultPath).readAsBytes();
      if (raw.isEmpty) return null;
      final plain = await secretCodec.decrypt(raw);
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is Map<String, dynamic>) {
        final auth = FirefoxSessionAuth.fromJson(decoded);
        if (auth.accessToken.isEmpty) return null;
        _memory = auth;
        return auth;
      }
      return null;
    } catch (_) {
      await clear(); // undecryptable — wipe honestly
      return null;
    }
  }

  /// Persists the pair (encrypted, atomic replace).
  Future<void> save(FirefoxSessionAuth auth) async {
    _memory = auth;
    final secretCodec = codec ?? _platformCodec();
    if (secretCodec == null) {
      return; // tests without a platform: memory only
    }
    try {
      final plain = utf8.encode(jsonEncode(auth.toJson()));
      final cipher = await secretCodec.encrypt(plain);
      final file = File(vaultPath);
      await file.parent.create(recursive: true);
      final tmp = File('$vaultPath.tmp');
      await tmp.writeAsBytes(cipher, flush: true);
      await tmp.rename(vaultPath);
    } catch (_) {
      // The engine keeps running on the in-memory pair; the next refresh
      // retries the persist. Never crash the session over storage.
    }
  }

  /// Logout-grade wipe: vault file + in-memory copy.
  Future<void> clear() async {
    _memory = null;
    try {
      final file = File(vaultPath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // already gone
    }
  }

  /// The production codec; null where no platform exists (tests, host).
  static FirefoxSecretCodec? _platformCodec() {
    if (Platform.isAndroid) return KeystoreSecretCodec();
    return null;
  }
}

/// The controlled injection for phase-1 testing: writes a session through
/// the SAME encrypted store a real login will use (Phase 2). NOT a login
/// flow; the injected pair must be a REAL session the owner controls —
/// never fake data presented as a live connection.
class FirefoxSessionInjector {
  FirefoxSessionInjector(this._store);

  final FirefoxSessionStore _store;

  Future<void> inject(FirefoxSessionAuth auth) => _store.save(auth);
}
