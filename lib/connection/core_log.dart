/// Core-log access (v4.21 — owner device-test round 3: «چطوره اون بخش متن
/// خطا لاگ کل هسته هارو هم بده تا بهتر بتونیم دیباگ کنیم»).
///
/// The Kotlin layer redirects the PROCESS stderr (fd 1 + fd 2) into
/// `filesDir/logs/core-log.txt` at activity start — the embedded Rust core
/// (aether) and the zeptun JNI both log to stderr, so their full startup
/// and error lines land in that ONE file. This reader tails it through the
/// `aethone/engine` MethodChannel:
///  * `readCoreLog`  → the LAST [tailBytes] of the file (plus its size);
///  * `clearCoreLog` → truncates it.
///
/// On a platform without the bridge (tests/desktop) both calls fail
/// honestly and the page shows the empty state — never a fabricated log.
library;

import 'dart:async';

import 'package:flutter/services.dart';

class CoreLogSnapshot {
  const CoreLogSnapshot({required this.text, required this.totalBytes});

  /// The tailed text (may be empty).
  final String text;

  /// The full size of the capture file on disk.
  final int totalBytes;

  bool get isEmpty => text.trim().isEmpty;
}

class CoreLogReader {
  CoreLogReader();

  static const MethodChannel _channel = MethodChannel('aethone/engine');

  /// Reads the last [tailBytes] bytes of the captured core log.
  Future<CoreLogSnapshot> read({int tailBytes = 64 * 1024}) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'readCoreLog',
        {'tail': tailBytes},
      );
      if (raw == null) return const CoreLogSnapshot(text: '', totalBytes: 0);
      return CoreLogSnapshot(
        text: raw['text'] as String? ?? '',
        totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return const CoreLogSnapshot(text: '', totalBytes: 0);
    } on MissingPluginException {
      return const CoreLogSnapshot(text: '', totalBytes: 0);
    }
  }

  /// Truncates the capture file.
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearCoreLog');
    } on PlatformException {
      // nothing to clear / no bridge
    } on MissingPluginException {
      // tests/desktop
    }
  }
}
