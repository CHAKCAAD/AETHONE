/// «تنظیمات هستهٔ Aether» — the fine-grained core sub-page (v4.22, the
/// owner's «تنظیمات جزیی» round). The page every user sees: the Iran
/// fragment profiles, the transport switches, the core log level. The
/// expert toggle reveals the TLS fingerprint panel and the engine panel
/// (owner: «تنظیمات باید برای کاربر عادی و کاربر حرفه‌ای مناسب باشه»).
///
/// Every control folds into the pinned core's CLI surface through
/// [AetherArguments.coreArgs] — nothing here is decorative: a value equal
/// to the core's default passes NOTHING, exactly as before.
library;

import 'package:flutter/material.dart';

import '../../../connection/connection_store.dart';
import '../../../connection/core_settings.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_strings.dart';
import 'settings_controls.dart';
import 'subpage_frame.dart';

class CoreSettingsPage extends StatelessWidget {
  const CoreSettingsPage({super.key, required this.store});

  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final core = store.coreSettings;

    // The selected fragment preset's description line.
    final fragDesc = switch (core.fragmentPreset) {
      FragmentPreset.off => strings.fragOffDesc,
      FragmentPreset.standard => strings.fragStandardDesc,
      FragmentPreset.balanced => strings.fragBalancedDesc,
      FragmentPreset.aggressive => strings.fragAggressiveDesc,
      FragmentPreset.custom => strings.fragCustomDesc,
    };

    return SubPageFrame(
      store: store,
      title: strings.subCoreTitle,
      children: () => [
        // ---- Section: TLS fragmentation (the owner's headline) ----
        SubSectionHeading(
          icon: AppAssets.iconCrop1,
          title: strings.secFragment,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingPills<FragmentPreset>(
                keyId: 'fragment',
                options: [
                  (FragmentPreset.off, strings.fragOff),
                  (FragmentPreset.standard, strings.fragStandard),
                  (FragmentPreset.balanced, strings.fragBalanced),
                  (FragmentPreset.aggressive, strings.fragAggressive),
                  (FragmentPreset.custom, strings.fragCustom),
                ],
                selected: core.fragmentPreset,
                onSelect: (v) =>
                    store.updateCore((c) => c.fragmentPreset = v),
              ),
              const SubSectionDivider(),
              SettingInfoText(fragDesc),
              if (core.fragmentPreset == FragmentPreset.custom) ...[
                const SubSectionDivider(),
                SettingField(
                  keyId: 'frag-size',
                  label: strings.fragSizeLabel,
                  hint: strings.fragSizeHint,
                  initial: core.fragmentSize,
                  onChanged: (v) =>
                      store.updateCore((c) => c.fragmentSize = v.trim()),
                ),
                const SubSectionDivider(),
                SettingField(
                  keyId: 'frag-delay',
                  label: strings.fragDelayLabel,
                  hint: strings.fragDelayHint,
                  initial: core.fragmentDelay,
                  onChanged: (v) =>
                      store.updateCore((c) => c.fragmentDelay = v.trim()),
                ),
              ],
            ],
          ),
        ),

        // ---- Section: transport ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconArrowSwapHorizontal,
          title: strings.secTransport,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingToggleRow(
                keyId: 'h2-transport',
                icon: AppAssets.iconSwap1,
                title: strings.h2Transport,
                description: strings.h2TransportDesc,
                value: core.h2Transport,
                onChanged: (v) =>
                    store.updateCore((c) => c.h2Transport = v),
              ),
              const SubSectionDivider(),
              SettingToggleRow(
                keyId: 'quic-v2',
                icon: AppAssets.iconShuffle1,
                title: strings.quicV2,
                description: strings.quicV2Desc,
                value: core.quicV2,
                onChanged: (v) => store.updateCore((c) => c.quicV2 = v),
              ),
              const SubSectionDivider(),
              SettingField(
                keyId: 'dns',
                label: strings.dnsLabel,
                hint: strings.dnsHint,
                initial: core.dns,
                onChanged: (v) =>
                    store.updateCore((c) => c.dns = v.trim()),
              ),
            ],
          ),
        ),

        // ---- Section: core log level ----
        SizedBox(height: 24 * s),
        SubSectionHeading(
          icon: AppAssets.iconActivity4,
          title: strings.logLevelLabel,
        ),
        const SubSectionGap.headingToCard(),
        SubSectionCard(
          child: SettingPills<CoreLogLevel>(
            keyId: 'log-level',
            options: [
              (CoreLogLevel.info, strings.logInfo),
              (CoreLogLevel.debug, strings.logDebug),
              (CoreLogLevel.trace, strings.logTrace),
            ],
            selected: core.logLevel,
            onSelect: (v) => store.updateCore((c) => c.logLevel = v),
          ),
        ),

        // ---- The expert toggle (persisted UI-only state).
        SizedBox(height: 24 * s),
        SubSectionCard(
          child: SettingToggleRow(
            keyId: 'expert',
            icon: AppAssets.iconSetting,
            title: strings.expertMode,
            description: strings.expertModeDesc,
            value: core.expertRevealed,
            onChanged: (v) =>
                store.updateCore((c) => c.expertRevealed = v),
          ),
        ),

        // ---- Expert-only panels ----
        if (core.expertRevealed) ...[
          SizedBox(height: 24 * s),
          SubSectionHeading(
            icon: AppAssets.iconShieldTick,
            title: strings.secTls,
          ),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: _buildTlsPanel(context, strings, s, core),
          ),
          // v4.31 — ECH (encrypted SNI): its own expert card, on the layer
          // it actually lives on (the MASQUE handshakes + the WARP API
          // calls), not under the fingerprint switches.
          SizedBox(height: 24 * s),
          SubSectionHeading(
            icon: AppAssets.iconLock1,
            title: strings.echLabel,
          ),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: _buildEchPanel(context, strings, s, core),
          ),
          SizedBox(height: 24 * s),
          SubSectionHeading(
            icon: AppAssets.iconGraphUp,
            title: strings.secEngine,
          ),
          const SubSectionGap.headingToCard(),
          SubSectionCard(
            child: _buildEnginePanel(context, strings, s, core),
          ),
        ],

        SizedBox(height: 16 * s),
        SettingInfoText(strings.appliesNextConnect),
      ],
    );
  }

  /// The TLS fingerprint panel — the customize switch first, then (when
  /// on) the eight fingerprint rows and the five expert fields.
  Widget _buildTlsPanel(
    BuildContext context,
    AppStrings strings,
    double s,
    CoreSettings core,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingToggleRow(
          keyId: 'tls-custom',
          icon: AppAssets.iconShieldTick,
          title: strings.tlsCustom,
          description: strings.tlsCustomDesc,
          value: core.tlsCustom,
          onChanged: (v) => store.updateCore((c) => c.tlsCustom = v),
        ),
        if (core.tlsCustom) ...[
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-grease',
            title: strings.tlsDisableGrease,
            description: strings.tlsDisableGreaseDesc,
            value: core.disableGrease,
            onChanged: (v) => store.updateCore((c) => c.disableGrease = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-sigalgs',
            title: strings.tlsGreaseSigalgs,
            description: strings.tlsGreaseSigalgsDesc,
            value: core.greaseSigalgs,
            onChanged: (v) => store.updateCore((c) => c.greaseSigalgs = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-ech-grease',
            title: strings.tlsEchGrease,
            description: strings.tlsEchGreaseDesc,
            value: core.echGrease,
            onChanged: (v) => store.updateCore((c) => c.echGrease = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-session-ticket',
            title: strings.tlsSessionTicket,
            description: strings.tlsSessionTicketDesc,
            value: core.sessionTicket,
            onChanged: (v) => store.updateCore((c) => c.sessionTicket = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-ocsp',
            title: strings.tlsOcsp,
            description: strings.tlsOcspDesc,
            value: core.ocsp,
            onChanged: (v) => store.updateCore((c) => c.ocsp = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-sct',
            title: strings.tlsSct,
            description: strings.tlsSctDesc,
            value: core.sct,
            onChanged: (v) => store.updateCore((c) => c.sct = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-ext-perm',
            title: strings.tlsExtPerm,
            description: strings.tlsExtPermDesc,
            value: core.extPermutation,
            onChanged: (v) => store.updateCore((c) => c.extPermutation = v),
          ),
          const SubSectionDivider(),
          SettingToggleRow(
            keyId: 'tls-verify',
            title: strings.tlsVerify,
            description: strings.tlsVerifyDesc,
            value: core.tlsVerify,
            onChanged: (v) => store.updateCore((c) => c.tlsVerify = v),
          ),
          const SubSectionDivider(),
          SettingField(
            keyId: 'tls-groups',
            label: strings.tlsGroups,
            hint: strings.tlsGroupsHint,
            initial: core.tlsGroups,
            onChanged: (v) => store.updateCore((c) => c.tlsGroups = v.trim()),
          ),
          const SubSectionDivider(),
          SettingField(
            keyId: 'tls-key-shares',
            label: strings.tlsKeyShares,
            hint: strings.tlsKeySharesHint,
            initial: core.keyShares,
            onChanged: (v) => store.updateCore((c) => c.keyShares = v.trim()),
          ),
          const SubSectionDivider(),
          SettingField(
            keyId: 'tls-ciphers12',
            label: strings.tlsCiphers12,
            hint: strings.tlsCiphers12Hint,
            initial: core.ciphers12,
            onChanged: (v) => store.updateCore((c) => c.ciphers12 = v.trim()),
          ),
          const SubSectionDivider(),
          SettingField(
            keyId: 'tls-ciphers13',
            label: strings.tlsCiphers13,
            hint: strings.tlsCiphers13Hint,
            initial: core.ciphers13,
            onChanged: (v) => store.updateCore((c) => c.ciphers13 = v.trim()),
          ),
          const SubSectionDivider(),
          SettingField(
            keyId: 'masque-sni',
            label: strings.masqueSni,
            hint: strings.masqueSniHint,
            initial: core.masqueSni,
            onChanged: (v) => store.updateCore((c) => c.masqueSni = v.trim()),
          ),
        ],
      ],
    );
  }

  /// v4.31 — the ECH panel (encrypted SNI, `--ech auto|base64` +
  /// `--ech-dns` / `--ech-domain`): pills first, then the mode's own
  /// fields. Independent of the fingerprint switches above — ECH is its
  /// own layer on the MASQUE handshakes and the WARP API calls.
  Widget _buildEchPanel(
    BuildContext context,
    AppStrings strings,
    double s,
    CoreSettings core,
  ) {
    final echDesc = switch (core.echMode) {
      EchMode.off => strings.echOffDesc,
      EchMode.auto => strings.echAutoDesc,
      EchMode.manual => strings.echManualDesc,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingLabel(strings.echLabel),
        const SizedBox(height: 10),
        SettingPills<EchMode>(
          keyId: 'ech-mode',
          options: [
            (EchMode.off, strings.echOff),
            (EchMode.auto, strings.echAuto),
            (EchMode.manual, strings.echManual),
          ],
          selected: core.echMode,
          onSelect: (v) => store.updateCore((c) => c.echMode = v),
        ),
        const SubSectionDivider(),
        SettingInfoText(echDesc),
        if (core.echMode == EchMode.manual) ...[
          const SubSectionDivider(),
          SettingField(
            keyId: 'ech-key',
            label: strings.echKeyLabel,
            hint: strings.echKeyHint,
            initial: core.echKey,
            onChanged: (v) => store.updateCore((c) => c.echKey = v.trim()),
          ),
        ],
        if (core.echMode != EchMode.off) ...[
          const SubSectionDivider(),
          SettingField(
            keyId: 'ech-dns',
            label: strings.echDnsLabel,
            hint: strings.echDnsHint,
            initial: core.echDns,
            onChanged: (v) => store.updateCore((c) => c.echDns = v.trim()),
          ),
          const SubSectionDivider(),
          SettingField(
            keyId: 'ech-domain',
            label: strings.echDomainLabel,
            hint: strings.echDomainHint,
            initial: core.echDomain,
            onChanged: (v) => store.updateCore((c) => c.echDomain = v.trim()),
          ),
        ],
      ],
    );
  }

  /// The engine panel: noize, perf, keepalive.
  Widget _buildEnginePanel(
    BuildContext context,
    AppStrings strings,
    double s,
    CoreSettings core,
  ) {
    final noizeDescShown = strings.noizeDesc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingLabel(strings.noizeLabel),
        const SizedBox(height: 10),
        SettingPills<NoizeProfile>(
          keyId: 'noize',
          options: [
            (NoizeProfile.defaultValue, strings.noizeDefault),
            (NoizeProfile.off, strings.noizeOff),
            (NoizeProfile.light, strings.noizeLight),
            (NoizeProfile.firewall, strings.noizeFirewall),
            (NoizeProfile.balanced, strings.noizeBalanced),
            (NoizeProfile.gfw, strings.noizeGfw),
            (NoizeProfile.aggressive, strings.noizeAggressive),
          ],
          selected: core.noize,
          onSelect: (v) => store.updateCore((c) => c.noize = v),
        ),
        const SubSectionDivider(),
        SettingInfoText(noizeDescShown),
        const SubSectionDivider(),
        SettingLabel(strings.perfLabel),
        const SizedBox(height: 10),
        SettingPills<PerfProfile>(
          keyId: 'perf',
          options: [
            (PerfProfile.auto, strings.perfAuto),
            (PerfProfile.low, strings.perfLow),
            (PerfProfile.medium, strings.perfMedium),
            (PerfProfile.high, strings.perfHigh),
          ],
          selected: core.perf,
          onSelect: (v) => store.updateCore((c) => c.perf = v),
        ),
        const SubSectionDivider(),
        SettingStepperRow(
          keyId: 'keepalive',
          icon: AppAssets.iconWatch1,
          label: strings.keepaliveLabel,
          value: core.keepalive,
          min: 1,
          max: 120,
          onChanged: (v) => store.updateCore((c) => c.keepalive = v),
        ),
      ],
    );
  }
}
