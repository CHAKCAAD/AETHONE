/// «تنظیمات اتصال» — the connection sub-page: the connection mode
/// (تونل/پروکسی — the same segment look the protocol page uses) and the
/// entry row into the Aether core page (the owner's fragment/TLS layer).
///
/// v4.40 (owner round 15: «صمت حالت پروتکل در تنظیمات اتصال برنامه رو
/// کلا حذف کن») — the AUTO/SMART protocol-mode section is GONE from this
/// page (and from the wizard's step 4): the setting no longer has any
/// picker; the engine keeps its persisted value.
///
/// v4.31c — the family-leg section MOVED OUT (owner round 8: «قسمت پایه
/// حالت های ترکیبی باید توی زیرمجموعه تنطیمات تور و سایفون قرار بگیره»):
/// the base of the combined modes lives on the TOR and PSIPHON pages now,
/// one pick per family — where the modes it configures actually live.
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/connection_state.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';
import '../../core/motion.dart';

class ConnectionSettingsPage extends StatelessWidget {
  const ConnectionSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SubPageFrame(
      store: store,
      title: strings.settingsConnSecTitle,
      icon: AppAssets.iconLock1,
      subtitle: strings.settingsConnSecSub,
      children: () => [
        // v1.1.0 (settings redesign) — the security page folds in here:
        // Kill Switch is a connection decision, one tap from the mode.
        SubSectionHeading(
          icon: AppAssets.iconSecuritySafe,
          title: strings.secKillSwitch,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingToggleRow(
            keyId: 'kill-switch',
            icon: AppAssets.iconOff,
            title: strings.secKillSwitch,
            description: strings.killSwitchDesc,
            value: store.killSwitch,
            onChanged: store.setKillSwitch,
          ),
        ),
        SizedBox(height: 24 * s),
        // ---- Section: connection mode (تونل/پروکسی) ----
        SubSectionHeading(
          icon: AppAssets.iconPassword1,
          title: strings.sheetHeadingMode,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: _ModeSegmentsRow(
            selected: store.connectionMode,
            onSelect: store.setConnectionMode,
          ),
        ),
      ],
    );
  }
}

/// The تونل/پروکسی segments — the protocol page's own segment look
/// (h35 r14 gap21, selected = accent fill + WHITE text on both, dark
/// unselected), so the SAME setting reads the same on both pages.
class _ModeSegmentsRow extends StatelessWidget {
  const _ModeSegmentsRow({required this.selected, required this.onSelect});

  final ConnectionMode selected;
  final ValueChanged<ConnectionMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final h = AethGeometry.protoSegmentH * s;
    final r = AethGeometry.protoSegmentRadius * s;

    Widget segment(ConnectionMode mode, String label) {
      final isSel = selected == mode;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('conn-mode-${mode.name}'),
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            // v1.0.2 — the segment follows the ambient style (was 260 ms).
            duration: Duration(
              milliseconds: MotionScope.of(context).recipe.controlMs,
            ),
            curve: MotionScope.of(context).recipe.controlCurve,
            height: h,
            decoration: BoxDecoration(
              color: isSel
                  ? AethColors.accentConnected
                  : AethColors.sheetDescCard,
              borderRadius: BorderRadius.circular(r),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoSegmentTextSize * s,
                color: isSel ? AethColors.onCoreDark : AethColors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl, // تونل first = visual RIGHT
      child: Row(
        children: [
          segment(ConnectionMode.tunnel, strings.modeTunnel),
          SizedBox(width: AethGeometry.protoSegmentGap * s),
          segment(ConnectionMode.proxy, strings.modeProxy),
        ],
      ),
    );
  }
}
