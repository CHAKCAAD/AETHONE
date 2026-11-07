/// «تنظیمات عمومی» — the general sub-page. v4.40 (owner round 15: «قسمت
/// تنطیمات عمومی واقعا تنطیمات زیادی رو ارایه نمیکنه. باید یه سری
/// تنطیمات به این بخش اضافه کنیم»): the page now carries REAL settings —
/// the desktop close behavior (the ask-dialog's remembered pick, the
/// round-15 decree), the login auto-start, and the reset-to-defaults —
/// beside the standing version row. The v4.35 About card (beta window:
/// the version row only) stays as shipped.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../connection/connection_state.dart';
import '../../../connection/connection_store.dart';
import '../../../connection/desktop_window.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  static bool get _isDesktop => Platform.isLinux || Platform.isWindows;

  bool _autoStart = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _readAutoStart();
    }
  }

  Future<void> _readAutoStart() async {
    try {
      final status = await const MethodChannelProxy().autoStartStatus();
      if (mounted) {
        setState(() => _autoStart = status);
      }
    } catch (_) {
      // the honest fallback: the toggle stays off and a flip retries the
      // write
    }
  }

  Future<void> _writeAutoStart(bool enabled) async {
    try {
      await const MethodChannelProxy().setAutoStart(enabled);
      if (mounted) {
        setState(() => _autoStart = enabled);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).autoStartFailed}: $e')),
        );
      }
    }
  }

  Future<void> _confirmReset() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _ResetConfirmDialog(strings: strings),
    );
    if (confirmed != true) return;
    widget.store.resetToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SubPageFrame(
      store: widget.store,
      title: strings.settingsGeneral,
      children: () => [
        // ---- Section: about the app ----
        SubSectionHeading(
          icon: AppAssets.iconInformationCircle,
          title: strings.secAbout,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingNavRow(
                keyId: 'app-version',
                icon: AppAssets.iconSetting,
                title: strings.appVersionLabel,
                // v4.35 — the beta window shows the stage, not the number.
                trailingValue: strings.betaStage,
                chevron: false,
                onTap: () {}, // a value row — not a navigation target
              ),
            ],
          ),
        ),

        // ---- Section: the desktop close behavior (owner round 15) ----
        if (_isDesktop) ...[
          SizedBox(height: 24 * s),
          SubSectionHeading(
            icon: AppAssets.iconCloseCircle,
            title: strings.secCloseBehavior,
          ),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingPills<CloseBehavior>(
                  keyId: 'close-behavior',
                  options: [
                    (CloseBehavior.ask, strings.closeBehaviorAsk),
                    (CloseBehavior.tray, strings.closeBehaviorTray),
                    (CloseBehavior.close, strings.closeBehaviorClose),
                  ],
                  selected: widget.store.closeBehavior,
                  onSelect: widget.store.setCloseBehavior,
                ),
                const SubSectionDivider(),
                SettingInfoText(strings.closeBehaviorDesc),
              ],
            ),
          ),
        ],

        // ---- Section: the login auto-start (desktop) ----
        if (_isDesktop) ...[
          SizedBox(height: 24 * s),
          SubSectionHeading(
            icon: AppAssets.iconActivity4,
            title: strings.secAutoStart,
          ),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: SettingToggleRow(
              keyId: 'auto-start',
              icon: AppAssets.iconShieldStar,
              title: strings.autoStartTitle,
              description: strings.autoStartDesc,
              value: _autoStart,
              onChanged: _writeAutoStart,
            ),
          ),
        ],

        // ---- Section: reset to defaults ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconRedo,
          title: strings.secReset,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingNavRow(
            keyId: 'reset-settings',
            icon: AppAssets.iconRedo,
            title: strings.resetTitle,
            description: strings.resetDesc,
            onTap: _confirmReset,
          ),
        ),
      ],
    );
  }
}

/// The thin channel proxy for the two auto-start methods (kept here so the
/// page reads as UI; the window bridge owns the other channel traffic).
class MethodChannelProxy {
  const MethodChannelProxy();

  Future<bool> autoStartStatus() async =>
      await DesktopWindowChannel.invokeBool('autoStartStatus', 'enabled');

  Future<void> setAutoStart(bool enabled) async =>
      await DesktopWindowChannel.invokeVoid('setAutoStart', {'enabled': enabled});
}

/// The reset confirm — the app's own dialog language (matches the close
/// ask-dialog of the round-15 decree).
class _ResetConfirmDialog extends StatelessWidget {
  const _ResetConfirmDialog({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
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
                strings.resetTitle,
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
                strings.resetConfirmBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w400,
                  fontSize: 12 * s,
                  color: AethColors.textSecondary,
                ),
              ),
              SizedBox(height: 18 * s),
              GestureDetector(
                key: const ValueKey('reset-confirm-yes'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(true),
                child: Container(
                  height: 44 * s,
                  decoration: BoxDecoration(
                    color: AethColors.statusDisconnected,
                    borderRadius: BorderRadius.circular(14 * s),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    strings.resetConfirmYes,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w700,
                      fontSize: 13 * s,
                      color: AethColors.onPillDisconnected,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12 * s),
              GestureDetector(
                key: const ValueKey('reset-confirm-no'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(false),
                child: Container(
                  height: 44 * s,
                  decoration: BoxDecoration(
                    color: AethColors.sheetDescCard,
                    borderRadius: BorderRadius.circular(14 * s),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    strings.closeDialogCancel,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w700,
                      fontSize: 13 * s,
                      color: AethColors.textPrimary,
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
