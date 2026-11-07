/// v4.40 — the DESKTOP window/tray bridge (owner round 15).
///
/// The owner's decree, verbatim: «وقتی روی دکمه ضربدر کلیک میشه برنامه باید
/// یک پنجره نمایش بده و از کاربر بپرسه که میخواد برنامه کلا بسته بشه یا
/// اینکه بره تو تری سیستم و کامل بسته نشه، یه گزینه هم باید باشه که کاربر
/// بتونه تیک بزنه که آیا این انتخابش دفعه بعد هم اعمال بشه مستقیم یا اینکه
/// دوباره پرسیده بشه». The native runners route WM_CLOSE / delete-event into
/// Dart (`onWindowCloseRequested`); this bridge owns the DECISION:
///
///  * a REMEMBERED pick ([ConnectionStore.closeBehavior], written by the
///    dialog's checkbox or the general-settings row) applies directly;
///  * otherwise the ask-dialog — built in the app's own design language
///    (the dark/light card, IRANYekanX, the accent buttons) so it rides the
///    theme and the RTL direction exactly like every other surface;
///  * the answer lands back in the runner as window.quit (the real exit —
///    the kill-on-close job object reaps every engine) or window.hide (the
///    tray icon, the tunnel and every engine keep running).
///
/// The tray menu's «قطع و وصل اتصال» entry arrives here too
/// (`onTrayToggleConnection`): the connection state machine lives in the
/// store, so the bridge just toggles it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../l10n/app_strings.dart';
import 'connection_state.dart';
import 'connection_store.dart';
import 'platform_engine_adapter.dart';

/// The root navigator key — the app shell installs it on MaterialApp; the
/// close-dialog needs a context that survives every route.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Small typed helpers over the shared `aethone/engine` channel for the
/// settings pages (auto-start status/write) — the same channel the bridge
/// and the platform adapter use; multiple instances are fine.
abstract final class DesktopWindowChannel {
  static const MethodChannel _channel = MethodChannel('aethone/engine');

  static Future<bool> invokeBool(String method, String boolKey) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(method);
      return raw?[boolKey] == true;
    } on MissingPluginException {
      return false; // a test host — the honest default
    }
  }

  static Future<void> invokeVoid(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // a test host — nothing to do
    }
  }
}

class DesktopWindowBridge {
  DesktopWindowBridge(this._store);

  final ConnectionStore _store;

  static const MethodChannel _channel = MethodChannel('aethone/engine');

  /// One dialog at a time (a second close click while the dialog is up is a
  /// no-op — the window is still there under the barrier).
  bool _dialogOpen = false;

  bool get _isDesktop => Platform.isLinux || Platform.isWindows;

  /// Wires the platform hooks. Call once after the store is constructed and
  /// the persistence restored (main()); on Android the events never fire and
  /// the hooks stay dead — safe to call unconditionally.
  void bind() {
    if (!_isDesktop) return;
    PlatformEngineAdapter.onWindowCloseRequested = _onCloseRequested;
    PlatformEngineAdapter.onTrayToggleConnection = _onTrayToggle;
  }

  Future<void> _onCloseRequested() async {
    if (_dialogOpen) return;
    switch (_store.closeBehavior) {
      case CloseBehavior.close:
        await _quit();
      case CloseBehavior.tray:
        await _hide();
      case CloseBehavior.ask:
        await _ask();
    }
  }

  Future<void> _ask() async {
    final context = appNavigatorKey.currentContext;
    if (context == null) return; // no UI yet — the next click re-asks
    _dialogOpen = true;
    try {
      final result = await showDialog<_CloseDialogResult>(
        context: context,
        barrierColor: Colors.black54,
        builder: (dialogContext) => _CloseAskDialog(store: _store),
      );
      if (result == null) return; // dismissed — the window stays as is
      if (result.remember) {
        _store.setCloseBehavior(result.choice);
      }
      switch (result.choice) {
        case CloseBehavior.close:
          await _quit();
        case CloseBehavior.tray:
          await _hide();
        case CloseBehavior.ask:
          break; // unreachable — the dialog only answers close/tray
      }
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _hide() async {
    try {
      await _channel.invokeMethod<void>('window.hide');
    } on PlatformException catch (e) {
      // No tray on this session (the honest native answer) — the window
      // must not strand: quit instead.
      debugPrint('desktop-window: hide failed (${e.message}) — quitting');
      await _quit();
    } on MissingPluginException {
      // A test host — nothing to do.
    }
  }

  Future<void> _quit() async {
    try {
      await _channel.invokeMethod<void>('window.quit');
    } on MissingPluginException {
      // A test host — nothing to do.
    }
  }

  Future<void> _onTrayToggle() async {
    final state = _store.state;
    if (state == VpnState.disconnected || state == VpnState.failed) {
      await _store.connect();
    } else if (state == VpnState.connected ||
        state == VpnState.connecting ||
        state == VpnState.starting ||
        state == VpnState.reconnecting) {
      await _store.disconnect();
    }
    // disconnecting / waitingForPermissions: a transition is already in
    // flight — the store's single-flight guard owns it.
  }
}

class _CloseDialogResult {
  const _CloseDialogResult(this.choice, this.remember);
  final CloseBehavior choice;
  final bool remember;
}

/// The ask-dialog — the app's own design language: the card surface
/// ([AethColors.cardDark] on the 420 ms theme tween), IRANYekanX, the
/// accent-green «رفتن به سینی» and the red «بستن کامل» (the app's own
/// status colors), RTL like every page.
class _CloseAskDialog extends StatefulWidget {
  const _CloseAskDialog({required this.store});

  final ConnectionStore store;

  @override
  State<_CloseAskDialog> createState() => _CloseAskDialogState();
}

class _CloseAskDialogState extends State<_CloseAskDialog> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 326 * s,
          padding: EdgeInsets.all(20 * s),
          decoration: BoxDecoration(
            color: AethColors.cardDark,
            borderRadius: BorderRadius.circular(21 * s),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.closeDialogTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: 16 * s,
                  color: AethColors.textPrimary,
                ),
              ),
              SizedBox(height: 6 * s),
              Text(
                strings.closeDialogBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w400,
                  fontSize: 12 * s,
                  color: AethColors.textSecondary,
                ),
              ),
              SizedBox(height: 18 * s),
              _CloseDialogButton(
                label: strings.closeDialogToTray,
                background: AethColors.accentConnected,
                ink: AethColors.onPillConnected,
                keyId: 'close-dialog-tray',
                onTap: () => Navigator.of(context).pop(
                  _CloseDialogResult(CloseBehavior.tray, _remember),
                ),
              ),
              SizedBox(height: 12 * s),
              _CloseDialogButton(
                label: strings.closeDialogFullClose,
                background: AethColors.statusDisconnected,
                ink: AethColors.onPillDisconnected,
                keyId: 'close-dialog-quit',
                onTap: () => Navigator.of(context).pop(
                  _CloseDialogResult(CloseBehavior.close, _remember),
                ),
              ),
              SizedBox(height: 14 * s),
              // The remember checkbox («انتخابش دفعه بعد هم اعمال بشه
              // مستقیم») — UNCHECKED keeps asking every time.
              GestureDetector(
                key: const ValueKey('close-dialog-remember'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _remember = !_remember),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18 * s,
                      height: 18 * s,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _remember
                              ? AethColors.accentConnected
                              : AethColors.sheetDescCard,
                          borderRadius: BorderRadius.circular(5 * s),
                        ),
                        child: _remember
                            ? Icon(Icons.check,
                                size: 14 * s,
                                color: AethColors.onPillConnected)
                            : null,
                      ),
                    ),
                    SizedBox(width: 10 * s),
                    Expanded(
                      child: Text(
                        strings.closeDialogRemember,
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w400,
                          fontSize: 12 * s,
                          color: AethColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10 * s),
              GestureDetector(
                key: const ValueKey('close-dialog-cancel'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: Text(
                    strings.closeDialogCancel,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w400,
                      fontSize: 12 * s,
                      color: AethColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseDialogButton extends StatelessWidget {
  const _CloseDialogButton({
    required this.label,
    required this.background,
    required this.ink,
    required this.keyId,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color ink;
  final String keyId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      key: ValueKey(keyId),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44 * s,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14 * s),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w700,
            fontSize: 13 * s,
            color: ink,
          ),
        ),
      ),
    );
  }
}
