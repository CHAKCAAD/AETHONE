/// «تنظیمات اتصال» — the connection sub-page (v4.22): the connection mode
/// (تونل/پروکسی — the same segment look the protocol page uses), the
/// protocol mode (AUTO/SMART — the status card's own source; SMART stays
/// an honest not-yet-in-the-core note), and the entry row into the Aether
/// core page (the owner's fragment/TLS layer).
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/connection_state.dart';
import '../../../connection/core_settings.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'core_page.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class ConnectionSettingsPage extends StatelessWidget {
  const ConnectionSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final core = store.coreSettings;
    return SubPageFrame(
      store: store,
      title: strings.settingsConnection,
      children: () => [
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

        // ---- Section: protocol mode (AUTO / SMART) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secProtocolMode,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingPills<bool>(
                keyId: 'proto-mode',
                options: [
                  (false, strings.protoAutoSheet),
                  (true, strings.protoModeSmart),
                ],
                selected: store.protocolModeSmart,
                onSelect: store.setProtocolModeSmart,
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.smartNote),
            ],
          ),
        ),

        // ---- Section: the Aether core protocol under the family modes
        // (v4.31 — owner round 7: «انتخاب پروتکل هسته ایتر برای حالت های
        // ترکیبی اور وارپ و …»; the option the v4.21 decree deferred) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconSwap1,
          title: strings.secAetherLeg,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingLabel(strings.aetherLegLabel),
              const SizedBox(height: 10),
              SettingPills<AetherLegProtocol>(
                keyId: 'aether-leg',
                options: [
                  // The same order + labels as the protocol page's own
                  // tiles (strings.aetherLegName reuses their names).
                  (AetherLegProtocol.wireguard, strings.aetherLegName(
                      AetherLegProtocol.wireguard)),
                  (AetherLegProtocol.masque, strings.aetherLegName(
                      AetherLegProtocol.masque)),
                  (AetherLegProtocol.gool, strings.aetherLegName(
                      AetherLegProtocol.gool)),
                  (AetherLegProtocol.goolClassic, strings.aetherLegName(
                      AetherLegProtocol.goolClassic)),
                  (AetherLegProtocol.mim, strings.aetherLegName(
                      AetherLegProtocol.mim)),
                ],
                selected: core.aetherLegProtocol,
                onSelect: (v) =>
                    store.updateCore((c) => c.aetherLegProtocol = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.aetherLegDesc),
            ],
          ),
        ),

        // ---- Section: IP version (v4.31) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconWebsite,
          title: strings.secIpVersion,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingPills<IpVersion>(
                keyId: 'ip-version',
                options: [
                  (IpVersion.v4, strings.ipV4),
                  (IpVersion.v6, strings.ipV6),
                  (IpVersion.dual, strings.ipDual),
                ],
                selected: core.ipVersion,
                onSelect: (v) => store.updateCore((c) => c.ipVersion = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.ipVersionDesc),
            ],
          ),
        ),

        // ---- Section: upstream proxy (v4.31) ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconArrowSwapHorizontal,
          title: strings.secUpstream,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingField(
                keyId: 'upstream',
                label: strings.upstreamLabel,
                hint: strings.upstreamHint,
                initial: core.upstreamProxy,
                onChanged: (v) =>
                    store.updateCore((c) => c.upstreamProxy = v.trim()),
              ),
              const SubSectionDivider(),
              SettingInfoText(strings.upstreamDesc),
            ],
          ),
        ),

        // ---- The Aether core entry row ----
        SizedBox(height: 24 * s),
        SubSectionCard(
          child: SettingNavRow(
            keyId: 'core-entry',
            icon: AppAssets.iconShieldTick,
            title: strings.subCoreTitle,
            description: strings.coreRowDesc,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CoreSettingsPage(store: store),
              ),
            ),
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
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            height: h,
            decoration: BoxDecoration(
              color: isSel ? AethColors.accentConnected : AethColors.sheetDescCard,
              borderRadius: BorderRadius.circular(r),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoSegmentTextSize * s,
                color: AethColors.textPrimary, // white on BOTH (measured)
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
