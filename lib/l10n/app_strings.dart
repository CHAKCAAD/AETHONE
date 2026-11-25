/// UI strings — minimal hand-rolled l10n for UI step 1 (home screen).
///
/// fa strings are taken VERBATIM from the reference screens (غیرفعال / متصل /
/// آفلاین / پروتکل). en/ru/zh are natural translations; tk is a FIRST-CLASS
/// table since v4.42 (the v4.41 "fall back to en" mapping was the bug that
/// killed the whole Turkmen table — see app.dart's tk seam).
///
/// This is a deliberate stopgap: the full gen-l10n pipeline (5 locales, .arb
/// files, untranslated-key policy) lands with the onboarding/settings step,
/// where CI verifies codegen. Replacing this class is mechanical.
library;

import 'package:flutter/widgets.dart';

import '../connection/core_settings.dart';
import '../core/app_assets.dart';

class AppStrings {
  const AppStrings._(this._v);

  final Map<String, String> _v;

  String get offline => _v['offline']!;
  String get statusDisconnected => _v['statusDisconnected']!;

  /// v6 (owner round 23) — LOOK 1's own disconnected label (the new CSS
  /// spells «غیرفعال» on the three-layer 140×38 chip; look 2 keeps the
  /// «قــطــع!» of its own frame).
  String get statusIdle => _v['statusIdle']!;
  String get statusConnected => _v['statusConnected']!;
  String get statusConnecting => _v['statusConnecting']!;
  String get statusReconnecting => _v['statusReconnecting']!;
  String get statusFailed => _v['statusFailed']!;

  // v1.0.2 motion overhaul — the three states the pill used to fold into
  // their neighbours now carry their own words in every language.
  String get statusStarting => _v['statusStarting']!;
  String get statusWaitingPermissions => _v['statusWaitingPermissions']!;
  String get statusDisconnecting => _v['statusDisconnecting']!;
  String get protocol => _v['protocol']!;
  String get settingsComingNext => _v['settingsComingNext']!;
  String get speedTestComingNext => _v['speedTestComingNext']!;
  String get protocolSheetComingNext => _v['protocolSheetComingNext']!;

  // ---- v4.16 protocol sheet (fa verbatim from the design frame
  // «صفحه شناور انتخاب پروتکل صفحه اصلی.jpg» + descriptions from the
  // phase-1 report §11) ----
  String get sheetHeadingMode => _v['sheetHeadingMode']!;
  String get modeTunnel => _v['modeTunnel']!;
  String get modeProxy => _v['modeProxy']!;
  String get sheetHeadingScanSpeed => _v['sheetHeadingScanSpeed']!;

  /// v4.17 — the full protocol-selection PAGE's top-bar title (the page
  /// replaces the v4.16 floating sheet; the title mirrors the settings
  /// page's «تنظیمات» slot).
  String get protocolPageTitle => _v['protocolPageTitle']!;
  /// «اتوماتیک» — the sheet's tile label for AUTO (the home card keeps
  /// «اتو / اسمارت»; this is the design frame's own wording).
  String get protoAutoSheet => _v['protoAutoSheet']!;

  /// «تور اور وارپ» — Tor over Warp (TOW): the AETHER leg carries the
  /// tunnel, Tor rides on top; the exit IP is a Tor node (round 24:
  /// «t o w تور اور وارپ هست»).
  String get protoTorOverWarp => _v['protoTorOverWarp']!;

  /// «وارپ اور تور» — Warp over Tor (WOT): Tor carries the tunnel, the
  /// AETHER/WARP leg rides on top; the exit IP is a WARP colo (round
  /// 24: «w o t وارپ اور تور هست»).
  String get protoWarpOverTor => _v['protoWarpOverTor']!;

  /// «سایفون اور وارپ» — Psiphon over Warp (POW): the AETHER leg carries
  /// the tunnel, Psiphon rides on top; the exit IP is a Psiphon node
  /// (round 24: «p o w سایفون اور وارپ هست»).
  String get protoPsiphonOverWarp => _v['protoPsiphonOverWarp']!;

  /// «وارپ اور سایفون» — Warp over Psiphon (WOP): Psiphon carries the
  /// tunnel, the AETHER/WARP leg rides on top; the exit IP is a WARP
  /// colo (round 24: «w o p وارپ اور سایفون هست»).
  String get protoWarpOverPsiphon => _v['protoWarpOverPsiphon']!;

  // ---- Settings main page (step 2; fa values verbatim from the design) ----
  String get settingsTitle => _v['settingsTitle']!;
  String get settingsRouting => _v['settingsRouting']!;
  String get settingsRoutingSub => _v['settingsRoutingSub']!;
  String get settingsGeneral => _v['settingsGeneral']!;
  String get settingsGeneralSub => _v['settingsGeneralSub']!;
  String get settingsConnection => _v['settingsConnection']!;
  String get settingsConnectionSub => _v['settingsConnectionSub']!;
  String get settingsLanguage => _v['settingsLanguage']!;
  String get settingsLanguageSub => _v['settingsLanguageSub']!;
  String get settingsAppearance => _v['settingsAppearance']!;
  String get settingsAppearanceSub => _v['settingsAppearanceSub']!;
  String get settingsSecurity => _v['settingsSecurity']!;
  String get settingsSecuritySub => _v['settingsSecuritySub']!;
  String get settingsPsiphon => _v['settingsPsiphon']!;
  String get settingsTor => _v['settingsTor']!;
  String get settingsLantern => _v['settingsLantern']!;
  String get lanternLocationDesc => _v['lanternLocationDesc']!;
  String get lanternLocationEmpty => _v['lanternLocationEmpty']!;
  String get secLanternTimings => _v['secLanternTimings']!;
  String get lanternConnectSecsLabel => _v['lanternConnectSecsLabel']!;
  String get lanternTimingsDesc => _v['lanternTimingsDesc']!;
  String get secLanternTunnel => _v['secLanternTunnel']!;
  String get lanternUdpLabel => _v['lanternUdpLabel']!;
  String get lanternUdpDesc => _v['lanternUdpDesc']!;
  String get lanternStrictLabel => _v['lanternStrictLabel']!;
  String get lanternStrictDesc => _v['lanternStrictDesc']!;
  String get lanternTelegramLabel => _v['lanternTelegramLabel']!;
  String get lanternTelegramDesc => _v['lanternTelegramDesc']!;
  String get lanternTelegramFailed => _v['lanternTelegramFailed']!;
  String get telegramProxyDesc => _v['telegramProxyDesc']!;
  String get secTelegram => _v['secTelegram']!;
  String get secScanSpeed => _v['secScanSpeed']!;
  String get scanTurbo => _v['scanTurbo']!;
  String get scanBalanced => _v['scanBalanced']!;
  String get scanThorough => _v['scanThorough']!;
  String get scanVerified => _v['scanVerified']!;
  String get scanIronclad => _v['scanIronclad']!;
  String get scanTurboDesc => _v['scanTurboDesc']!;
  String get scanBalancedDesc => _v['scanBalancedDesc']!;
  String get scanThoroughDesc => _v['scanThoroughDesc']!;
  String get scanVerifiedDesc => _v['scanVerifiedDesc']!;
  String get scanIroncladDesc => _v['scanIroncladDesc']!;
  String get lanternAndroidOnly => _v['lanternAndroidOnly']!;
  String get settingsPillSub => _v['settingsPillSub']!;
  String get settingsAdvancedStatus => _v['settingsAdvancedStatus']!;
  String get settingsRoutingArea => _v['settingsRoutingArea']!;
  String get settingsMainServer => _v['settingsMainServer']!;
  String get settingsSubpageComingNext => _v['settingsSubpageComingNext']!;

  /// Routing-region value shown on the status card — the design renders
  /// the LATIN country name («Iran»), so this stays Latin in every locale.
  String routingRegionName(String? code) => switch (code) {
        'ir' => 'Iran',
        'tm' => 'Turkmenistan',
        'ru' => 'Russia',
        'cn' => 'China',
        _ => 'None',
      };

  /// "146 ms" style. DOWN/UP/MB stay Latin (part of the visual design).
  String pingMs(int ms) => '$ms ms';

  /// v4.20 — the mode's local SOCKS port note in the descriptions popup
  /// (digits stay Latin, like the ping/counter labels).
  String protocolPortNote(int port) => _v['portNote']! .replaceAll('@p', '$port');

  /// v4.20 — the failed-state caption + details sheet.
  String get failureCodeLabel => _v['failureCodeLabel']!;

  // ---- v2.1.0 — the home widget deck («برای صفحه اصلی چندتا ویجت
  // خلاقانه اضافه کن»): the three cards' labels. ----
  String get homeWidgetTimer => _v['homeWidgetTimer']!;
  String get homeWidgetPing => _v['homeWidgetPing']!;
  String get homeWidgetData => _v['homeWidgetData']!;
  String get failureDetailsTitle => _v['failureDetailsTitle']!;
  String get failureDetailsCopy => _v['failureDetailsCopy']!;

  /// v4.21 — the core-log diagnostics page (owner: «چطوره اون بخش متن خطا
  /// لاگ کل هسته هارو هم بده تا بهتر بتونیم دیباگ کنیم»).
  String get coreLogTitle => _v['coreLogTitle']!;
  String get coreLogOpen => _v['coreLogOpen']!;
  String get coreLogCopy => _v['coreLogCopy']!;
  String get coreLogClear => _v['coreLogClear']!;
  String get coreLogCopied => _v['coreLogCopied']!;
  String get coreLogEmpty => _v['coreLogEmpty']!;
  String coreLogSize(int bytes) =>
      _v['coreLogSize']!.replaceAll('@b', '$bytes');

  // ---- v4.22 settings sub-pages (owner round: «تنظیمات جزیی» — every
  // page real, no placeholder sheets; fa is the design language) ----
  String get subCoreTitle => _v['subCoreTitle']!;
  String get expertMode => _v['expertMode']!;
  String get expertModeDesc => _v['expertModeDesc']!;
  String get appliesNextConnect => _v['appliesNextConnect']!;

  // fragment
  String get secFragment => _v['secFragment']!;
  String get fragOff => _v['fragOff']!;
  String get fragStandard => _v['fragStandard']!;
  String get fragBalanced => _v['fragBalanced']!;
  String get fragAggressive => _v['fragAggressive']!;
  String get fragCustom => _v['fragCustom']!;
  String get fragOffDesc => _v['fragOffDesc']!;
  String get fragStandardDesc => _v['fragStandardDesc']!;
  String get fragBalancedDesc => _v['fragBalancedDesc']!;
  String get fragAggressiveDesc => _v['fragAggressiveDesc']!;
  String get fragCustomDesc => _v['fragCustomDesc']!;
  String get fragSizeLabel => _v['fragSizeLabel']!;
  String get fragDelayLabel => _v['fragDelayLabel']!;
  String get fragSizeHint => _v['fragSizeHint']!;
  String get fragDelayHint => _v['fragDelayHint']!;

  // TLS
  String get secTls => _v['secTls']!;
  String get tlsCustom => _v['tlsCustom']!;
  String get tlsCustomDesc => _v['tlsCustomDesc']!;
  String get tlsDisableGrease => _v['tlsDisableGrease']!;
  String get tlsDisableGreaseDesc => _v['tlsDisableGreaseDesc']!;
  String get tlsGreaseSigalgs => _v['tlsGreaseSigalgs']!;
  String get tlsGreaseSigalgsDesc => _v['tlsGreaseSigalgsDesc']!;
  String get tlsEchGrease => _v['tlsEchGrease']!;
  String get tlsEchGreaseDesc => _v['tlsEchGreaseDesc']!;
  String get tlsSessionTicket => _v['tlsSessionTicket']!;
  String get tlsSessionTicketDesc => _v['tlsSessionTicketDesc']!;
  String get tlsOcsp => _v['tlsOcsp']!;
  String get tlsOcspDesc => _v['tlsOcspDesc']!;
  String get tlsSct => _v['tlsSct']!;
  String get tlsSctDesc => _v['tlsSctDesc']!;
  String get tlsExtPerm => _v['tlsExtPerm']!;
  String get tlsExtPermDesc => _v['tlsExtPermDesc']!;
  String get tlsVerify => _v['tlsVerify']!;
  String get tlsVerifyDesc => _v['tlsVerifyDesc']!;
  String get tlsGroups => _v['tlsGroups']!;
  String get tlsGroupsHint => _v['tlsGroupsHint']!;
  String get tlsKeyShares => _v['tlsKeyShares']!;
  String get tlsKeySharesHint => _v['tlsKeySharesHint']!;
  String get tlsCiphers12 => _v['tlsCiphers12']!;
  String get tlsCiphers12Hint => _v['tlsCiphers12Hint']!;
  String get tlsCiphers13 => _v['tlsCiphers13']!;
  String get tlsCiphers13Hint => _v['tlsCiphers13Hint']!;
  String get masqueSni => _v['masqueSni']!;
  String get masqueSniHint => _v['masqueSniHint']!;

  // transport
  String get secTransport => _v['secTransport']!;
  String get h2Transport => _v['h2Transport']!;
  String get h2TransportDesc => _v['h2TransportDesc']!;
  String get quicV2 => _v['quicV2']!;
  String get quicV2Desc => _v['quicV2Desc']!;

  // engine
  String get secEngine => _v['secEngine']!;
  String get noizeLabel => _v['noizeLabel']!;
  String get noizeDesc => _v['noizeDesc']!;
  String get noizeDefault => _v['noizeDefault']!;
  String get noizeOff => _v['noizeOff']!;
  String get noizeLight => _v['noizeLight']!;
  String get noizeFirewall => _v['noizeFirewall']!;
  String get noizeBalanced => _v['noizeBalanced']!;
  String get noizeGfw => _v['noizeGfw']!;
  String get noizeAggressive => _v['noizeAggressive']!;
  String get perfLabel => _v['perfLabel']!;
  String get perfAuto => _v['perfAuto']!;
  String get perfLow => _v['perfLow']!;
  String get perfMedium => _v['perfMedium']!;
  String get perfHigh => _v['perfHigh']!;
  String get logLevelLabel => _v['logLevelLabel']!;
  String get logInfo => _v['logInfo']!;
  String get logDebug => _v['logDebug']!;
  String get logTrace => _v['logTrace']!;
  String get keepaliveLabel => _v['keepaliveLabel']!;

  // routing page
  String get secRoutes => _v['secRoutes']!;
  String get routeBlockLabel => _v['routeBlockLabel']!;
  String get routeBlockHint => _v['routeBlockHint']!;
  String get routeDirectLabel => _v['routeDirectLabel']!;
  String get routeDirectHint => _v['routeDirectHint']!;
  String get routesDesc => _v['routesDesc']!;
  String get routingNone => _v['routingNone']!;

  // connection page
  String get secProtocolMode => _v['secProtocolMode']!;
  String get protoModeSmart => _v['protoModeSmart']!;
  String get smartNote => _v['smartNote']!;

  /// v4.32 — the SMART attempt line («اسمارت: ماسک (۱ از ۵)») — the
  /// explicit, observable fallback chain (SMART_AUTO_SPEC §7.2).
  String smartAttemptLabel(String name, int attempt, int total) =>
      _v['smartAttemptLabel']!
          .replaceAll('{name}', name)
          .replaceAll('{i}', '$attempt')
          .replaceAll('{n}', '$total');

  /// v4.34 — the SMART MEASUREMENT line («سنجش کیفیت ماسک …») — the
  /// tour's quality phase over a candidate that already connected
  /// (owner round 10: measure every connector, then pick the best).
  String smartMeasuringLabel(String name) =>
      _v['smartMeasuringLabel']!.replaceAll('{name}', name);
  String get coreRowDesc => _v['coreRowDesc']!;

  // general page
  String get secAbout => _v['secAbout']!;
  String get appVersionLabel => _v['appVersionLabel']!;

  /// v4.35 — the beta-stage value the version row shows (owner round 11:
  /// «نسخه برنامه رو بنویس آزمایشی» — the real number stays in
  /// pubspec/app_meta for the tests).
  String get betaStage => _v['betaStage']!;
  String get telegramRow => _v['telegramRow']!;
  String get githubRow => _v['githubRow']!;

  /// v1.0.0 (round 18) — the Instagram link row (the About card).
  String get instagramRow => _v['instagramRow']!;
  String get secNotifications => _v['secNotifications']!;
  String get notificationsComing => _v['notificationsComing']!;

  /// v4.41 (round 17, item 12) — the notifications section's row + value.
  String get notificationsRow => _v['notificationsRow']!;
  String get notificationsOn => _v['notificationsOn']!;

  /// v4.41 (round 17, item 3) — the routing-area profile description.
  String get routingAreaDesc => _v['routingAreaDesc']!;

  /// v4.41 (round 17, item 4) — the per-app tunneling section.
  String get tunnelApps => _v['tunnelApps']!;
  String get tunnelAppsModeAll => _v['tunnelAppsModeAll']!;
  String get tunnelAppsModeAllow => _v['tunnelAppsModeAllow']!;
  String get tunnelAppsModeDisallow => _v['tunnelAppsModeDisallow']!;
  String get tunnelAppsDesc => _v['tunnelAppsDesc']!;
  String get tunnelAppsLoading => _v['tunnelAppsLoading']!;

  // ---- v1.1.0 hybrid per-tunnel routing ----
  String get hybridRouting => _v['hybridRouting']!;
  String get hybridRoutingOpen => _v['hybridRoutingOpen']!;
  String get hybridRoutingDesc => _v['hybridRoutingDesc']!;
  String get hybridRoutes => _v['hybridRoutes']!;
  String get hybridDefaultRoute => _v['hybridDefaultRoute']!;
  String get hybridDefaultNote => _v['hybridDefaultNote']!;
  String get hybridApps => _v['hybridApps']!;
  String get hybridDomains => _v['hybridDomains']!;
  String get hybridIps => _v['hybridIps']!;
  String get hybridAddApps => _v['hybridAddApps']!;
  String get hybridAddDomain => _v['hybridAddDomain']!;
  String get hybridAddIp => _v['hybridAddIp']!;
  String get hybridDomainHint => _v['hybridDomainHint']!;
  String get hybridIpHint => _v['hybridIpHint']!;
  String get hybridSearchApps => _v['hybridSearchApps']!;
  String get hybridErrEmpty => _v['hybridErrEmpty']!;
  String get hybridErrInvalid => _v['hybridErrInvalid']!;
  String get hybridErrDuplicate => _v['hybridErrDuplicate']!;
  String get hybridConflict => _v['hybridConflict']!;
  String get hybridEmpty => _v['hybridEmpty']!;
  String get hybridInvalidTunnel => _v['hybridInvalidTunnel']!;
  String get hybridEngineRejected => _v['hybridEngineRejected']!;
  String get hybridRuleOff => _v['hybridRuleOff']!;
  String get hybridSave => _v['hybridSave']!;
  String get hybridAppliedNext => _v['hybridAppliedNext']!;
  String get hybridApplyFailed => _v['hybridApplyFailed']!;
  String get hybridNotRouted => _v['hybridNotRouted']!;
  String get hybridStatusLive => _v['hybridStatusLive']!;
  String get hybridAppUnsupported => _v['hybridAppUnsupported']!;
  String get hybridWildcardNote => _v['hybridWildcardNote']!;
  String get hybridPriority => _v['hybridPriority']!;
  String get hybridLimits => _v['hybridLimits']!;
  String get hybridPickTunnel => _v['hybridPickTunnel']!;
  String get hybridFlows => _v['hybridFlows']!;
  String get tunnelAppsLoadFailed => _v['tunnelAppsLoadFailed']!;

  // v4.40 — the desktop close behavior (owner round 15)
  String get secCloseBehavior => _v['secCloseBehavior']!;
  String get closeBehaviorAsk => _v['closeBehaviorAsk']!;
  String get closeBehaviorTray => _v['closeBehaviorTray']!;
  String get closeBehaviorClose => _v['closeBehaviorClose']!;
  String get closeBehaviorDesc => _v['closeBehaviorDesc']!;
  String get closeDialogTitle => _v['closeDialogTitle']!;
  String get closeDialogBody => _v['closeDialogBody']!;
  String get closeDialogToTray => _v['closeDialogToTray']!;
  String get closeDialogFullClose => _v['closeDialogFullClose']!;
  String get closeDialogRemember => _v['closeDialogRemember']!;
  String get closeDialogCancel => _v['closeDialogCancel']!;

  // v4.40 — the login auto-start (general settings)
  String get secAutoStart => _v['secAutoStart']!;
  String get autoStartTitle => _v['autoStartTitle']!;
  String get autoStartDesc => _v['autoStartDesc']!;
  String get autoStartFailed => _v['autoStartFailed']!;

  // v4.40 — the reset-to-defaults (general settings)
  String get secReset => _v['secReset']!;
  String get resetTitle => _v['resetTitle']!;
  String get resetDesc => _v['resetDesc']!;
  String get resetConfirmBody => _v['resetConfirmBody']!;
  String get resetConfirmYes => _v['resetConfirmYes']!;

  // language page
  String get secAppLanguage => _v['secAppLanguage']!;
  String get langSystem => _v['langSystem']!;
  String get langDesc => _v['langDesc']!;

  // appearance page
  String get secHomeLook => _v['secHomeLook']!;
  String get lookOne => _v['lookOne']!;
  String get lookTwo => _v['lookTwo']!;

  // v4.40 — the display mode (night / light / AUTO — owner round 15)
  String get secThemeMode => _v['secThemeMode']!;
  String get themePickNight => _v['themePickNight']!;
  String get themePickLight => _v['themePickLight']!;
  String get themePickAuto => _v['themePickAuto']!;
  String get themeAutoNote => _v['themeAutoNote']!;
  String get secMotion => _v['secMotion']!;
  String get motionStandard => _v['motionStandard']!;
  String get motionSmooth => _v['motionSmooth']!;
  String get motionDynamic => _v['motionDynamic']!;

  /// v4.25 — the fourth style pill + the master kill-switch row.
  String get motionMinimal => _v['motionMinimal']!;
  String get animationsOffTitle => _v['animationsOffTitle']!;
  String get animationsOffDesc => _v['animationsOffDesc']!;
  String get secPatterns => _v['secPatterns']!;
  String get showPatterns => _v['showPatterns']!;
  String get showPatternsDesc => _v['showPatternsDesc']!;

  // security page
  String get secKillSwitch => _v['secKillSwitch']!;
  String get killSwitchDesc => _v['killSwitchDesc']!;
  String get secDiagnostics => _v['secDiagnostics']!;

  // psiphon page
  String get secExitLocation => _v['secExitLocation']!;
  String get psiphonLocationDesc => _v['psiphonLocationDesc']!;
  String get secFronting => _v['secFronting']!;
  String get frontingModeLabel => _v['frontingModeLabel']!;
  String get frontingAuto => _v['frontingAuto']!;
  String get frontingCdn => _v['frontingCdn']!;
  String get frontingDirect => _v['frontingDirect']!;
  String get frontingAutoDesc => _v['frontingAutoDesc']!;
  String get frontingCdnDesc => _v['frontingCdnDesc']!;
  String get frontingDirectDesc => _v['frontingDirectDesc']!;
  String get cdnSniLabel => _v['cdnSniLabel']!;
  String get cdnSniHint => _v['cdnSniHint']!;
  String get cdnIpsLabel => _v['cdnIpsLabel']!;
  String get cdnIpsHint => _v['cdnIpsHint']!;




  // 1.8.0 — the arman-pattern round: the DIRECT email+password sign-in
  // (the form tab) and its granular failure texts.


  // 1.8.0 — the DNS test's path labels (through the tunnel vs direct).



  // tor page
  String get torLocationDesc => _v['torLocationDesc']!;
  String get secTorBridges => _v['secTorBridges']!;
  String get bridgesLabel => _v['bridgesLabel']!;
  String get bridgesAuto => _v['bridgesAuto']!;
  String get bridgesOff => _v['bridgesOff']!;
  String get bridgesAutoDesc => _v['bridgesAutoDesc']!;
  String get bridgesOffDesc => _v['bridgesOffDesc']!;
  String get torLogLevelLabel => _v['torLogLevelLabel']!;

  // ---- v4.31 — the round-7 settings expansion (manual bridges, tor
  // budgets, psiphon sets/entries/budget, the family leg protocol, the
  // dial layer, ECH) ----
  String get bridgesCustom => _v['bridgesCustom']!;
  String get bridgesCustomDesc => _v['bridgesCustomDesc']!;
  String get torBridgeLinesLabel => _v['torBridgeLinesLabel']!;
  String get torBridgeLinesHint => _v['torBridgeLinesHint']!;
  String get secTorTimings => _v['secTorTimings']!;
  String get torDirectSecsLabel => _v['torDirectSecsLabel']!;
  String get torBridgeSecsLabel => _v['torBridgeSecsLabel']!;
  String get torTimingsDesc => _v['torTimingsDesc']!;
  String get cdnSetsLabel => _v['cdnSetsLabel']!;
  String get cdnSetsHint => _v['cdnSetsHint']!;
  String get cdnSetsDesc => _v['cdnSetsDesc']!;
  String get secPsiphonTimings => _v['secPsiphonTimings']!;
  String get psiphonReadyLabel => _v['psiphonReadyLabel']!;
  String get psiphonReadyDesc => _v['psiphonReadyDesc']!;
  String get serverEntriesLabel => _v['serverEntriesLabel']!;
  String get serverEntriesHint => _v['serverEntriesHint']!;
  String get serverEntriesDesc => _v['serverEntriesDesc']!;
  String get secFamilyLeg => _v['secFamilyLeg']!;
  String get aetherLegLabel => _v['aetherLegLabel']!;
  String get torLegDesc => _v['torLegDesc']!;
  String get psiphonLegDesc => _v['psiphonLegDesc']!;
  String get secIpVersion => _v['secIpVersion']!;
  String get ipV4 => _v['ipV4']!;
  String get ipV6 => _v['ipV6']!;
  String get ipDual => _v['ipDual']!;
  String get ipVersionDesc => _v['ipVersionDesc']!;
  String get secUpstream => _v['secUpstream']!;
  String get upstreamLabel => _v['upstreamLabel']!;
  String get upstreamHint => _v['upstreamHint']!;
  String get upstreamDesc => _v['upstreamDesc']!;
  String get echLabel => _v['echLabel']!;
  String get echOff => _v['echOff']!;
  String get echAuto => _v['echAuto']!;
  String get echManual => _v['echManual']!;
  String get echOffDesc => _v['echOffDesc']!;
  String get echAutoDesc => _v['echAutoDesc']!;
  String get echManualDesc => _v['echManualDesc']!;
  String get echKeyLabel => _v['echKeyLabel']!;
  String get echKeyHint => _v['echKeyHint']!;
  String get echDnsLabel => _v['echDnsLabel']!;
  String get echDnsHint => _v['echDnsHint']!;
  String get echDomainLabel => _v['echDomainLabel']!;
  String get echDomainHint => _v['echDomainHint']!;

  /// The family-leg pills reuse the protocol tiles' own labels
  /// («ماسک / وایرگارد / …») — the same protocol reads the same everywhere.
  /// (Named aetherLegName — aetherLegLabel is the section card's label.)
  String aetherLegName(AetherLegProtocol leg) => switch (leg) {
    AetherLegProtocol.masque => _v['protoMasque']!,
    AetherLegProtocol.wireguard => _v['protoWireguard']!,
    AetherLegProtocol.gool => _v['protoGool']!,
    AetherLegProtocol.goolClassic => _v['protoGoolClassic']!,
    AetherLegProtocol.mim => _v['protoMim']!,
  };

  // ---- v6 login («صفحه ورود» — fa VERBATIM from the owner's five frames
  // (ورود1..ورود5), transcribed off 3× crops) ----
  /// «برای ماجراجویی آماده‌ای؟» — the welcome step's title.
  String get loginWelcomeTitle => _v['loginWelcomeTitle']!;

  /// «زبان برنامه» — the language step's title.
  String get loginLanguageTitle => _v['loginLanguageTitle']!;

  /// «منطقه مسیریابی» — the routing step's title.
  String get loginRoutingTitle => _v['loginRoutingTitle']!;

  /// «ضاهر برنامه» — the look step's title (the frame's own spelling of
  /// ظاهر, kept verbatim per the pixel-faithful rule).
  String get loginLookTitle => _v['loginLookTitle']!;

  /// «اتمام راه اندازی!» — the done step's title.
  String get loginDoneTitle => _v['loginDoneTitle']!;

  /// The welcome step's description (the ورود1 block).
  String get loginWelcomeDesc => _v['loginWelcomeDesc']!;

  /// The done step's description (the ورود5 block).
  String get loginDoneDesc => _v['loginDoneDesc']!;

  /// «بعدی» — the forward pill.
  String get loginNext => _v['loginNext']!;

  /// «قبلی» — the back pill.
  String get loginPrev => _v['loginPrev']!;

  /// «بریم!» — the last step's pill.
  String get loginGo => _v['loginGo']!;

  /// The language pages' own-name option for Turkmen (Turkmençe).
  String get langTurkmen => _v['langTurkmen']!;

  // ---- v4.24 speed test («صفحه تست سرعت») — fa VERBATIM from the three
  // committed frames; the Latin card labels (Ping:/Jiter:/DOWN:/UP:) and
  // the «Mbs»/«...» slots stay page constants like the bottom panel's
  // DOWN:/UP: (identical in every locale on the frames). ----
  /// «تست سرعت» — the page's title row.
  String get speedTestTitle => _v['speedTestTitle']!;

  /// «پینگ» — the phase label while the ping phase runs.
  String get speedPhasePing => _v['speedPhasePing']!;

  /// «دانلود» — the phase label on the running frame.
  String get speedPhaseDownload => _v['speedPhaseDownload']!;

  /// «آپلود» — the upload phase label (the frames only carry دانلود; this
  /// completes the pair).
  String get speedPhaseUpload => _v['speedPhaseUpload']!;

  /// «شروع» — the idle button label.
  String get speedStart => _v['speedStart']!;

  /// «شروع شده...» — the running button label (frame verbatim).
  String get speedStarted => _v['speedStarted']!;

  /// «شروع دوباره» — the done button label.
  String get speedRestart => _v['speedRestart']!;

  /// The SELECTED protocol's display name for the protocol card — the
  /// reference frames show the protocol's own name (e.g. «وارپ»), not the
  /// generic word «پروتکل» (owner prompt §«دکمه انتخاب پروتکل»: هر پروتکلی
  /// که انتخاب شد لوگو آن در دکمه انتخاب پروتکل نمایش داده میشود).
  ///
  /// Round 24 — the four combined modes carry their FULL names (the
  /// owner's decree: «نام بعضی پروتکل ها … با سایر بخش های اپ هماهنگش
  /// کن» + the TOW/WOT/POW/WOP definitions): the card can now tell
  /// «تور اور وارپ» from «وارپ اور تور» — the plain «تور»/«سایفون» stay
  /// for the ONLY modes.
  String protocolName(ProtocolId id) {
    final key = switch (id) {
      ProtocolId.auto => 'protoAuto',
      ProtocolId.masque => 'protoMasque',
      ProtocolId.wireguard => 'protoWireguard',
      ProtocolId.gool => 'protoGool',
      ProtocolId.goolClassic => 'protoGoolClassic',
      ProtocolId.mim => 'protoMim',
      ProtocolId.torChain => 'protoTorOverWarp',
      ProtocolId.torReverse => 'protoWarpOverTor',
      ProtocolId.torOnly => 'protoTor',
      ProtocolId.psiphonChain => 'protoPsiphonOverWarp',
      ProtocolId.psiphonReverse => 'protoWarpOverPsiphon',
      ProtocolId.psiphonOnly => 'protoPsiphon',
      ProtocolId.lantern => 'protoLantern',
    };
    return _v[key] ?? _v['protoMasque']!;
  }

  static const Map<String, Map<String, String>> _table = {
    'fa': {
      'offline': 'آفلاین',
      // v5 («نمای 2»): the owner's own pill labels — tatweel-stretched
      // exactly as the committed CSS spells them («قــطــع!»).
      'statusDisconnected': 'قــطــع!',
      'statusIdle': 'غیرفعال',
      'statusConnected': 'مــتـصـل',
      'statusConnecting': 'در حال اتصال',
      'statusReconnecting': 'اتصال مجدد',
      'statusFailed': 'خطا',
      'statusStarting': 'در حال شروع',
      'statusWaitingPermissions': 'در انتظار مجوز',
      'statusDisconnecting': 'در حال قطع',
      'protocol': 'پروتکل',
      'settingsComingNext': 'تنظیمات — در گام بعدی پیاده‌سازی می‌شود',
      'speedTestComingNext': 'تست سرعت — در گام بعدی پیاده‌سازی می‌شود',
      'protocolSheetComingNext':
          'انتخاب پروتکل — در گام بعدی پیاده‌سازی می‌شود',
      // ---- v4.16 protocol sheet: fa VERBATIM from the design frame + the
      // phase-1 report §11 descriptions (the owner's own words). The
      // wireguard/gool/goolClassic/mim lines are evidence-locked to the
      // transport-mode table (report table 11: WARP exit on the main
      // listener) — no invented behaviour.
      'sheetHeadingMode': 'حالت اتصال',
      'modeTunnel': 'تونل',
      'modeProxy': 'پروکسی',
      'sheetHeadingScanSpeed': 'سرعت اسکن',
      'protocolPageTitle': 'انتخاب پروتکل',
      'protoAutoSheet': 'اتوماتیک',
      'protoAuto': 'اتو / اسمارت',
      'protoMasque': 'ماسک',
      'protoWireguard': 'وایرگارد',
      'protoGool': 'گول',
      'protoGoolClassic': 'گول کلاسیک',
      'protoMim': 'میم',
      'protoTor': 'تور',
      'protoPsiphon': 'سایفون',
      // Round 24 — the combined modes' full names (the owner's decree:
      // «t o w تور اور وارپ هست …»), evidence-locked to the backend
      // wiring (torChain = AETHER_TOR=chain = Tor over Warp, etc.).
      'protoTorOverWarp': 'تور اور وارپ',
      'protoWarpOverTor': 'وارپ اور تور',
      'protoPsiphonOverWarp': 'سایفون اور وارپ',
      'protoWarpOverPsiphon': 'وارپ اور سایفون',
      'protoLantern': 'لنترن',
      // ---- settings main page (fa verbatim from the design frame; the
      // v4.15 renames are the owner's own words — settings round #5/#8:
      // «متن تنظیمات تور و تنظیمات سایفون به تور و سایفون تغیر کند»,
      // «متن (وضعیت پیشرفته) باید به وضعیت پیکربندی تغیر پیدا کند»,
      // «متن آدرس سرور اصلی باید به آدرس هسته ها تغیر پیدا کند») ----
      'settingsTitle': 'تنظیمات',
      'settingsRouting': 'مسیریابی‌ها',
      'settingsRoutingSub': 'مسیرهای مستقیم',
      'settingsGeneral': 'تنظیمات عمومی',
      'settingsGeneralSub': 'تنظیمات اعلان و رویداد',
      'settingsConnection': 'تنظیمات اتصال',
      'settingsConnectionSub': 'تنظیمات اتصال و پروتکل',
      'settingsLanguage': 'تنظیمات زبان',
      'settingsLanguageSub': 'انتخاب زبان برنامه',
      'settingsAppearance': 'تنظیمات ظاهری',
      'settingsAppearanceSub': 'شخصی‌سازی ظاهر برنامه',
      'settingsSecurity': 'تنظیمات امنیت',
      'settingsSecuritySub': 'امنیت و حریم خصوصی',
      'settingsPsiphon': 'سایفون',
      'settingsTor': 'تور',
      'settingsLantern': 'لنترن',
      'lanternLocationDesc': 'فقط کشورهایی که سرورهای خودِ لنترن ارائه می‌دهند؛ «خودکار» یعنی سریع‌ترین سرور به انتخاب خودِ هسته. در حالت متصل، تغییر بلافاصله اعمال می‌شود',
      'lanternLocationEmpty': 'فهرست کشورها بعد از اولین اتصال لنترن از سرورهای خودش دریافت می‌شود',
      'secLanternTimings': 'زمان اتصال لنترن',
      'lanternConnectSecsLabel': 'مهلت اتصال (ثانیه)',
      'lanternTimingsDesc': 'پیش‌فرض ۱۸۰ ثانیه: دریافت تنظیمات لنترن و رسیدن به سرور. در شبکه‌های کند بیشتر بگذارید',
      'secLanternTunnel': 'تونل',
      'lanternUdpLabel': 'عبور UDP',
      'lanternUdpDesc': 'خاموش: برنامه‌ها فوراً به TCP برمی‌گردند (برای برنامه‌هایی که روی «در حال اتصال» می‌مانند)',
      'lanternStrictLabel': 'دست‌دهی سازگار',
      'lanternStrictDesc': 'اتصال ساکس به لنترن مرحله‌به‌مرحله انجام می‌شود؛ پایدارتر برای تلگرام و اتصال‌های طولانی',
      'lanternTelegramLabel': 'پروکسی تلگرام',
      'lanternTelegramDesc': 'یک لمس: پروکسی SOCKS لنترن (127.0.0.1:1822) در تلگرام تنظیم می‌شود',
      'lanternTelegramFailed': 'تلگرام روی این دستگاه پیدا نشد',
      'telegramProxyDesc': 'یک لمس: پروکسی SOCKS همین پروتکل ({addr}) در تلگرام تنظیم می‌شود؛ تا وقتی متصل هستید کار می‌کند',
      'secTelegram': 'تلگرام',
      'secScanSpeed': 'سرعت اسکن',
      'scanTurbo': 'توربو',
      'scanBalanced': 'متعادل',
      'scanThorough': 'کامل',
      'scanVerified': 'تأییدشده',
      'scanIronclad': 'سخت‌گیرانه',
      'scanTurboDesc': 'سریع‌ترین اسکن: نمونهٔ کمتر و خروج با اولین آی‌پی سالم (پیش‌فرض)',
      'scanBalancedDesc': 'نمونه‌برداری بیشتر در چند موج؛ کندتر از توربو ولی در شبکه‌های فیلترشده مطمئن‌تر',
      'scanThoroughDesc': 'اسکن گسترده‌تر برای شبکه‌های سخت؛ زمان اتصال بیشتر می‌شود',
      'scanVerifiedDesc': 'اسکن عمیق‌تر و کم‌ردتر (حالت stealth هسته)؛ کندتر از کامل',
      'scanIroncladDesc': 'عمیق‌ترین و کندترین اسکن: هر آی‌پی با یک درخواست HTTP واقعی آزموده می‌شود',
      'lanternAndroidOnly': 'لنترن در این نسخه فقط روی اندروید در دسترس است',
      'settingsPillSub': 'انتخاب لوکیشن و ...',
      'settingsAdvancedStatus': 'وضعیت پیکربندی',
      'settingsRoutingArea': 'منطقهٔ مسیریابی',
      'settingsMainServer': 'آدرس هسته ها',
      'settingsSubpageComingNext':
          'این بخش — در گام بعدی پیاده‌سازی می‌شود',
      // ---- v4.20 failure visibility + desc-popup port notes ----
      'failureCodeLabel': 'کد خطا',
      // v2.1.0 — the home widget deck.
      'homeWidgetTimer': 'مدت اتصال',
      'homeWidgetPing': 'تأخیر',
      'homeWidgetData': 'داده جلسه',
      'failureDetailsTitle': 'جزئیات خطا',
      'failureDetailsCopy': 'کپی اطلاعات خطا',
      'portNote': 'پورت محلی SOCKS: @p',
      // ---- v4.21 core-log diagnostics ----
      'coreLogTitle': 'لاگ هسته‌ها',
      'coreLogOpen': 'مشاهده',
      'coreLogCopy': 'کپی لاگ',
      'coreLogClear': 'پاک کردن',
      'coreLogCopied': 'لاگ کپی شد',
      'coreLogEmpty': 'لاگی ثبت نشده است — متصل شوید',
      'coreLogSize': 'حجم لاگ: @b بایت',
      // ---- v4.22 settings sub-pages ----
      'subCoreTitle': 'تنظیمات هستهٔ Aether',
      'expertMode': 'حالت حرفه‌ای',
      'expertModeDesc': 'نمایش تنظیمات پیشرفتهٔ هسته برای کاربران حرفه‌ای',
      'appliesNextConnect': 'تغییرات از اتصالِ بعدی اعمال می‌شود',
      'secFragment': 'فرگمنت TLS',
      'fragOff': 'خاموش',
      'fragStandard': 'استاندارد',
      'fragBalanced': 'متعادل',
      'fragAggressive': 'تهاجمی',
      'fragCustom': 'سفارشی',
      'fragOffDesc': 'ClientHello یکپارچه ارسال می‌شود (پیش‌فرض هسته)',
      'fragStandardDesc': 'پیش‌فرض خود هسته — برش 8-16 بایتی با وقفهٔ 2-10 میلی‌ثانیه',
      'fragBalancedDesc': 'برش 40-100 بایتی با وقفهٔ 10-20 میلی‌ثانیه — مناسب اکثر شبکه‌های ایران',
      'fragAggressiveDesc': 'برش ریز 1-3 بایتی با وقفهٔ 1-3 میلی‌ثانیه — برای سخت‌ترین فیلترها',
      'fragCustomDesc': 'اندازه و وقفه را خودتان تعیین کنید',
      'fragSizeLabel': 'اندازهٔ برش (بایت)',
      'fragDelayLabel': 'وقفهٔ بین برش‌ها (میلی‌ثانیه)',
      'fragSizeHint': 'مثلاً 40-100',
      'fragDelayHint': 'مثلاً 10-20',
      'secTls': 'TLS و اثرانگشت',
      'tlsCustom': 'شخصی‌سازی TLS',
      'tlsCustomDesc': 'بدون فعال‌سازی، اثرانگشت خود هسته (شبیه کروم) اعمال می‌شود',
      'tlsDisableGrease': 'حذف مقادیر GREASE',
      'tlsDisableGreaseDesc': 'حذف مقادیر GREASE از رمزها، گروه‌ها و افزونه‌ها (RFC 8701)',
      'tlsGreaseSigalgs': 'GREASE در الگوریتم‌های امضا',
      'tlsGreaseSigalgsDesc': 'قرار دادن مقدار GREASE در ابتدای signature_algorithms مثل کروم',
      'tlsEchGrease': 'GREASE برای ECH',
      'tlsEchGreaseDesc': 'ارسال افزونهٔ ECH ساختگی وقتی کلید ECH ارائه نمی‌شود',
      'tlsSessionTicket': 'Session Ticket',
      'tlsSessionTicketDesc': 'درخواست session_ticket مثل کروم',
      'tlsOcsp': 'OCSP Stapling',
      'tlsOcspDesc': 'درخواست status_request مثل کروم',
      'tlsSct': 'SCT',
      'tlsSctDesc': 'درخواست signed_certificate_timestamps مثل کروم',
      'tlsExtPerm': 'جایگشت افزونه‌ها',
      'tlsExtPermDesc': 'تغییر ترتیب افزونه‌ها در هر handshake — خاموش کردن آن ترتیب ثابت BoringSSL را اعمال می‌کند',
      'tlsVerify': 'تأیید گواهی دروازهٔ MASQUE',
      'tlsVerifyDesc': 'گواهی MASQUE با پین‌های خود هسته بررسی می‌شود (پیش‌فرض: خاموش)',
      'tlsGroups': 'گروه‌های TLS',
      'tlsGroupsHint': 'مثلاً P-256:X25519:P-384',
      'tlsKeyShares': 'Key Shares',
      'tlsKeySharesHint': 'مثلاً X25519:P-256',
      'tlsCiphers12': 'رمزنگارهای TLS 1.2',
      'tlsCiphers12Hint': 'با : جدا شود — مثلاً ECDHE-RSA-AES128-GCM-SHA256',
      'tlsCiphers13': 'رمزنگارهای TLS 1.3',
      'tlsCiphers13Hint': 'مثلاً TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256',
      'masqueSni': 'SNI دستی MASQUE',
      'masqueSniHint': 'مثلاً www.cloudflare.com',
      'secTransport': 'انتقال',
      'h2Transport': 'انتقال روی HTTP/2 (TCP)',
      'h2TransportDesc': 'انتقال MASQUE روی HTTP/2 (TCP) — پیش‌فرض جدید اپ؛ برای شبکه‌هایی که UDP را می‌بندند',
      'quicV2': 'مذاکرهٔ QUIC v2',
      'quicV2Desc': 'بازکردن مسیر HTTP/3 روی شبکه‌هایی که QUIC v1 را می‌بندند',
      'secEngine': 'موتور',
      'noizeLabel': 'پروفایل اغتشاش (Noize)',
      'noizeDesc': 'پیش‌فرض جدید اپ: متعادل؛ برای شبکه‌های سخت‌گیر GFW یا تهاجمی را امتحان کنید',
      'noizeDefault': 'پیش‌فرض هسته',
      'noizeOff': 'خاموش',
      'noizeLight': 'سبک',
      'noizeFirewall': 'فایروال',
      'noizeBalanced': 'متعادل',
      'noizeGfw': 'GFW',
      'noizeAggressive': 'تهاجمی',
      'perfLabel': 'پروفایل منابع',
      'perfAuto': 'خودکار',
      'perfLow': 'کم',
      'perfMedium': 'متوسط',
      'perfHigh': 'زیاد',
      'logLevelLabel': 'سطح لاگ هسته',
      'logInfo': 'اطلاعات',
      'logDebug': 'دیباگ',
      'logTrace': 'تریس',
      'keepaliveLabel': 'وقفهٔ Keepalive وایرگارد (ثانیه)',
      'secRoutes': 'مسیرهای مستقیم و مسدود',
      'routeBlockLabel': 'دامنه‌های همیشه مسدود',
      'routeBlockHint': 'با کاما یا خط جدید جدا شود — مثلاً ads.example.com',
      'routeDirectLabel': 'دامنه‌های همیشه مستقیم (بیرون از تونل)',
      'routeDirectHint': 'مثلاً bank.example.com',
      'routesDesc': 'پیشوند full: فقط همان نام دقیق، keyword: هر نامی که شامل آن باشد؛ بدون پیشوند، دامنه و همهٔ زیردامنه‌هایش',
      'routingNone': 'هیچ‌کدام',
      'routingAreaDesc': 'ترافیک کشور انتخاب‌شده (دامنه‌ها و آی‌پی‌های خودش) مستقیم و بدون تونل می‌رود؛ بقیهٔ ترافیک از تونل عبور می‌کند.',
      'tunnelApps': 'برنامه‌های تونل',
      'tunnelAppsModeAll': 'همهٔ برنامه‌ها',
      'tunnelAppsModeAllow': 'فقط برنامه‌های انتخاب‌شده',
      'tunnelAppsModeDisallow': 'به‌جز برنامه‌های انتخاب‌شده',
      'tunnelAppsDesc': 'انتخاب کنید کدام برنامه‌ها از تونل عبور کنند؛ فقط در حالت اتصال «تونل» روی اندروید اعمال می‌شود و از اتصال بعدی مؤثر است.',
      'tunnelAppsLoading': 'در حال دریافت فهرست برنامه‌ها…',
      'tunnelAppsLoadFailed': 'فهرست برنامه‌ها در دسترس نیست',
      'hybridRouting': "مسیریابی ترکیبی",
      'hybridRoutingOpen': "مدیریت قوانین مسیر",
      'hybridRoutingDesc': "در این پروتکل ترکیبی تعیین کنید ترافیک هر برنامه، دامنه یا IP از کدام تونل عبور کند.",
      'hybridRoutes': "مسیرهای این پروتکل",
      'hybridDefaultRoute': "پیش‌فرض",
      'hybridDefaultNote': "ترافیکی که قانونی ندارد مثل قبل از مسیر پیش‌فرض {route} عبور می‌کند.",
      'hybridApps': "مسیر برنامه‌ها",
      'hybridDomains': "مسیر دامنه‌ها",
      'hybridIps': "مسیر IP",
      'hybridAddApps': "افزودن برنامه",
      'hybridAddDomain': "افزودن دامنه",
      'hybridAddIp': "افزودن IP",
      'hybridDomainHint': "example.com یا *.example.com",
      'hybridIpHint': "1.1.1.1 یا 192.168.1.0/24 یا 2606:4700::/32",
      'hybridSearchApps': "جست‌وجوی برنامه‌ها",
      'hybridErrEmpty': "چیزی وارد نشده",
      'hybridErrInvalid': "ورودی معتبر نیست",
      'hybridErrDuplicate': "این مورد قبلاً ثبت شده",
      'hybridConflict': "با {rules} روی تونل دیگری هم‌پوشانی دارد؛ قانون دقیق‌تر اعمال می‌شود.",
      'hybridEmpty': "هنوز قانونی ثبت نشده",
      'hybridInvalidTunnel': "این مسیر در این پروتکل وجود ندارد؛ ترافیکش مسدود می‌شود تا قانون را اصلاح کنید",
      'hybridEngineRejected': "موتور این قانون را نپذیرفت",
      'hybridRuleOff': "غیرفعال",
      'hybridSave': "ذخیره",
      'hybridAppliedNext': "از اتصال تونل بعدی با همین پروتکل اعمال می‌شود",
      'hybridApplyFailed': "موتور نتوانست قوانین را اعمال کند ({error})",
      'hybridNotRouted': "این اتصال بدون مسیریابی ترکیبی شروع شده؛ یک بار دوباره وصل شوید",
      'hybridStatusLive': "در موتور فعال است: {n} قانون",
      'hybridAppUnsupported': "مسیریابی برنامه‌ها به اندروید ۱۰ یا بالاتر نیاز دارد",
      'hybridWildcardNote': "example.com فقط خود همین دامنه را می‌گیرد؛ *.example.com فقط زیردامنه‌ها (مثل www.example.com) را، نه خود example.com.",
      'hybridPriority': "اولویت: برنامه ← دامنهٔ دقیق ← دامنهٔ wildcard (دقیق‌ترین) ← IP/CIDR (کوچک‌ترین محدوده) ← مسیر پیش‌فرض. قانون برنامه بر قوانین دامنه و IP همان برنامه مقدم است.",
      'hybridLimits': "محدودیت‌ها: دامنه از DNS خود تونل تشخیص داده می‌شود؛ برنامه‌هایی که DNS رمزگذاری‌شدهٔ خودشان (DoH/DoT) را دارند یا مستقیم به IP وصل می‌شوند فقط با قانون برنامه یا IP مسیریابی می‌شوند. قوانین IP فقط روی اتصال‌های مستقیم به IP اعمال می‌شوند. اگر تونل انتخاب‌شده در دسترس نباشد، ترافیک آن قانون مسدود می‌شود و هرگز مستقیم نمی‌رود. در این پروتکل‌ها UDP (به‌جز DNS) منتقل نمی‌شود. فقط در حالت «تونل» روی اندروید.",
      'hybridPickTunnel': "مسیر",
      'hybridFlows': "{n} اتصال",
      'secProtocolMode': 'حالت پروتکل',
      'protoModeSmart': 'اسمارت',
      'smartNote': 'در حالت اسمارت، خود اپ به‌جای پیش‌فرض هسته پروتکل را انتخاب می‌کند: نامزدها (ماسک، وایرگارد، گول، میم، گول کلاسیک) به ترتیب موفقیت و تأخیر اندازه‌گیری‌شدهٔ قبلی امتحان می‌شوند تا یکی وصل شود. ترتیب تلاش‌ها در صفحهٔ اصلی نمایش داده می‌شود، تأخیر اندازه‌گیری‌شده یادآوری می‌شود و انتخاب دستی شما هرگز بازنویسی نمی‌شود. فقط روی کاشی «اتوماتیک» فعال است.',
      'smartAttemptLabel': 'اسمارت: {name} ({i} از {n})',
      'smartMeasuringLabel': 'سنجش کیفیت {name} …',
      'coreRowDesc': 'فرگمنت، TLS، انتقال و موتور',
      'secAbout': 'دربارهٔ برنامه',
      'appVersionLabel': 'نسخهٔ برنامه',
      'betaStage': 'آزمایشی',
      'telegramRow': 'کانال تلگرام',
      'githubRow': 'مخزن گیت‌هاب',
      'instagramRow': 'اینستاگرام',
      'secNotifications': 'اعلان و رویداد',
      'notificationsComing': 'اعلان اندروید هنگام اتصال نمایش داده می‌شود و دکمهٔ «قطع اتصال» همان‌جا در دسترس است؛ در دسکتاپ از منوی آیکون سینی سیستم قطع و وصل کنید.',
      'notificationsRow': 'اعلان اتصال',
      'notificationsOn': 'روشن',
      'secCloseBehavior': 'رفتار دکمهٔ بستن',
      'closeBehaviorAsk': 'پرسیدن',
      'closeBehaviorTray': 'رفتن به سینی',
      'closeBehaviorClose': 'بستن کامل',
      'closeBehaviorDesc': 'انتخاب می‌کند که با کلیک روی ضربدر چه اتفاقی بیفتد: هر بار پرسیده شود، مستقیم برنامه به سینی سیستم برود یا کلا بسته شود.',
      'closeDialogTitle': 'بستن برنامه',
      'closeDialogBody': 'می‌خواهید برنامه کلا بسته شود یا در سینی سیستم باقی بماند و اتصال ادامه پیدا کند؟',
      'closeDialogToTray': 'رفتن به سینی سیستم',
      'closeDialogFullClose': 'بستن کامل برنامه',
      'closeDialogRemember': 'انتخاب من دفعهٔ بعد هم مستقیم اعمال شود',
      'closeDialogCancel': 'انصراف',
      'secAutoStart': 'شروع خودکار',
      'autoStartTitle': 'اجرا با روشن شدن سیستم',
      'autoStartDesc': 'برنامه هنگام ورود به سیستم به‌صورت خودکار اجرا شود.',
      'autoStartFailed': 'ثبت شروع خودکار ممکن نشد',
      'secReset': 'بازنشانی',
      'resetTitle': 'بازنشانی تنظیمات',
      'resetDesc': 'برگرداندن همهٔ تنظیمات به حالت پیش‌فرض کارخانه.',
      'resetConfirmBody': 'همهٔ تنظیمات به حالت اولیه برمی‌گردد. این کار قابل بازگشت نیست.',
      'resetConfirmYes': 'بازنشانی شود',
      'secThemeMode': 'حالت نمایش',
      'themePickNight': 'نایت',
      'themePickLight': 'لایت',
      'themePickAuto': 'خودکار',
      'themeAutoNote': 'در حالت خودکار از ساعت ۶ صبح تا ۶ عصر حالت لایت و از ساعت ۶ عصر تا ۶ صبح حالت نایت فعال است.',
      'secAppLanguage': 'زبان برنامه',
      'langSystem': 'همراه سیستم',
      'langDesc': 'زبان رابط کاربری — پیش‌فرض فارسی',
      'secHomeLook': 'نمای صفحهٔ اصلی',
      'lookOne': 'نمای ۱',
      'lookTwo': 'نمای ۲',
      'secMotion': 'انیمیشن',
      'motionStandard': 'استاندارد',
      'motionSmooth': 'نرم',
      'motionDynamic': 'پویا',
      'motionMinimal': 'حداقلی',
      'animationsOffTitle': 'خاموش کردن همهٔ انیمیشن‌ها',
      'animationsOffDesc': 'همهٔ انیمیشن‌های برنامه فوراً متوقف می‌شوند',
      'secPatterns': 'الگوهای پس‌زمینه',
      'showPatterns': 'نمایش الگوهای پس‌زمینه',
      'showPatternsDesc': 'الگوهای سبز/قرمز دو طرف همهٔ صفحات',
      'secKillSwitch': 'Kill Switch',
      'killSwitchDesc': 'جلوگیری از نشت ترافیک هنگام قطع اتصال — یکپارچه‌سازی کامل با سیستم‌عامل در گام بعدی',
      'secDiagnostics': 'تشخیص خطا',
      'secExitLocation': 'لوکیشن خروجی',
      'psiphonLocationDesc': 'برای حالت‌های سایفون‌خروج اعمال می‌شود؛ «خودکار» یعنی انتخاب خودِ هسته',
      'secFronting': 'فرانتینگ CDN',
      'frontingModeLabel': 'نحوهٔ فرانتینگ',
      'frontingAuto': 'خودکار',
      'frontingAutoDesc': 'هسته خودش انتخاب می‌کند (پیش‌فرض)',
      'frontingCdn': 'فقط CDN',
      'frontingCdnDesc': 'فقط از طریق CDN های مِک — برای شبکه‌هایی که بقیهٔ مسیرها را می‌بندند',
      'frontingDirect': 'مستقیم',
      'frontingDirectDesc': 'بدون فرانتینگ',
      'cdnSniLabel': 'SNI سرورهای CDN',
      'cdnSniHint': 'با کاما جدا شود — مثلاً cdn.example.com',
      'cdnIpsLabel': 'آدرس‌های CDN',
      'cdnIpsHint': 'مثلاً 104.16.0.1,104.16.1.1',
      'torLocationDesc': 'انتخاب شما ذخیره و در صفحهٔ اصلی نمایش داده می‌شود؛ هستهٔ Tor خروجی را از میان گره‌های موجود انتخاب می‌کند',
      'secTorBridges': 'پل‌های Tor',
      'bridgesLabel': 'سیاست پل‌ها',
      'bridgesAuto': 'خودکار',
      'bridgesAutoDesc': 'هسته خودش از bridgedb پل می‌گیرد و پل‌های مناسب را می‌آزماید',
      'bridgesOff': 'بدون پل',
      'bridgesOffDesc': 'پل‌ها خاموش می‌شوند (فقط برای شبکه‌های بدون فیلتر Tor)',
      'torLogLevelLabel': 'سطح لاگ Tor',
      // v4.31 — the round-7 settings expansion.
      'bridgesCustom': 'دستی',
      'bridgesCustomDesc': 'خط‌های پل خودتان را وارد کنید؛ هسته به‌جای پل‌های گرفته‌شده از bridgedb از همین‌ها استفاده می‌کند',
      'torBridgeLinesLabel': 'خط‌های پل',
      'torBridgeLinesHint': 'هر پل در یک خط — مثلاً obfs4 1.2.3.4:443 CERT=… iat-mode=0',
      'secTorTimings': 'زمان‌های اتصال تور',
      'torDirectSecsLabel': 'مهلت اتصال مستقیم (ثانیه)',
      'torBridgeSecsLabel': 'مهلت هر پل (ثانیه)',
      'torTimingsDesc': 'پیش‌فرض هسته: ۷۵ ثانیه اتصال مستقیم و ۳۶۰ ثانیه برای هر پل. در شبکه‌های کند می‌توانید بیشتر بگذارید',
      'cdnSetsLabel': 'مجموعه‌های فرانتینگ',
      'cdnSetsHint': 'با کاما جدا شود — مثلاً psiphon-akamai,vercel (خالی = همه)',
      'cdnSetsDesc': 'کدام فهرست‌های لبهٔ داخلی سایفون برای فرانتینگ CDN استفاده شوند',
      'secPsiphonTimings': 'زمان آماده‌سازی',
      'psiphonReadyLabel': 'مهلت آماده‌سازی سایفون (ثانیه)',
      'psiphonReadyDesc': 'پیش‌فرض هسته ۱۸۰ ثانیه است؛ در شبکه‌های کند بیشترش کنید — بودجهٔ خود اپ هم هماهنگ با آن باز می‌شود',
      'serverEntriesLabel': 'ورودی‌های سرور',
      'serverEntriesHint': 'متن JSON ورودی‌های سرور از کلاینت رسمی سایفون',
      'serverEntriesDesc': 'خالی یعنی کشف خودکار داخلی سایفون',
      'secFamilyLeg': 'پایهٔ حالت‌های ترکیبی',
      'aetherLegLabel': 'پایهٔ حالت‌های ترکیبی',
      'torLegDesc': 'در حالت‌های ترکیبی تور (زنجیره و معکوس)، تونل Aether زیرین با این پروتکل برقرار می‌شود. در حالت معکوس، پایه‌های نیازمند UDP خودکار به ماسک تغییر می‌کنند (محدودیت خود هسته)',
      'psiphonLegDesc': 'در حالت‌های ترکیبی سایفون (زنجیره و معکوس)، تونل Aether زیرین با این پروتکل برقرار می‌شود. در حالت معکوس، پایه‌های نیازمند UDP خودکار به ماسک تغییر می‌کنند (محدودیت خود هسته)',
      'secIpVersion': 'نسخهٔ IP',
      'ipV4': 'IPv4',
      'ipV6': 'IPv6',
      'ipDual': 'دوگانه',
      'ipVersionDesc': 'برخی اپراتورها IPv6 را سالم حمل نمی‌کنند؛ IPv4 پیش‌فرضِ خود هسته است',
      'secUpstream': 'پروکسی بالادست',
      'upstreamLabel': 'آدرس پروکسی (اختیاری)',
      'upstreamHint': 'socks5://127.0.0.1:1080',
      'upstreamDesc': 'فقط برای پروتکل‌های سادهٔ Aether؛ ترافیک هسته از این پروکسی عبور می‌کند. خالی = خاموش',
      'echLabel': 'ECH (رمزنگاری SNI)',
      'echOff': 'خاموش',
      'echAuto': 'خودکار',
      'echManual': 'دستی',
      'echOffDesc': 'SNI مثل حالت عادی ارسال می‌شود',
      'echAutoDesc': 'کلید ECH به‌صورت خودکار از DNS خوانده می‌شود و نام سرور رمزنگاری‌شده ارسال می‌شود',
      'echManualDesc': 'کلید ECH را دستی (base64) وارد می‌کنید',
      'echKeyLabel': 'کلید ECH (base64)',
      'echKeyHint': 'مثلاً AEDW…',
      'echDnsLabel': 'DNS یابندهٔ کلید',
      'echDnsHint': 'مثلاً https://1.1.1.1/dns-query',
      'echDomainLabel': 'دامنهٔ کلید (اختیاری)',
      'echDomainHint': 'پیش‌فرض: cloudflare-ech.com',
      // v6 login — verbatim from the «صفحه ورود» frames (ورود1..ورود5).
      'loginWelcomeTitle': 'برای ماجراجویی آماده‌ای؟',
      'loginLanguageTitle': 'زبان برنامه',
      'loginRoutingTitle': 'منطقه مسیریابی',
      'loginLookTitle': 'ضاهر برنامه',
      'loginDoneTitle': 'اتمام راه اندازی!',
      'loginWelcomeDesc':
          'در چند قدم ساده، با امکانات AETHONE آشنا شو، حالت اتصال و پروتکل موردنظرت رو انتخاب کن و تنظیمات رو مطابق نیازت شخصی‌سازی کن. ماجراجویی تو برای تجربه‌ای منعطف‌تر از اتصال و کشف مسیرهای مختلف ارتباطی، از همین‌جا شروع می‌شه!',
      'loginDoneDesc':
          'همه‌چیز برای شروع آماده‌ست! تنظیمات اولیه رو پشت سر گذاشتی و حالا می‌تونی وارد دنیای AETHONE بشی. به صفحه اصلی برو، اتصال دلخواهت رو برقرار کن و ماجراجویی خودت رو با تجربه‌ای تازه از ارتباط آزادتر آغاز کن!',
      'loginNext': 'بعدی',
      'loginPrev': 'قبلی',
      'loginGo': 'بریم!',
      'langTurkmen': 'Türkmençe',
      'speedTestTitle': 'تست سرعت',
      'speedPhasePing': 'پینگ',
      'speedPhaseDownload': 'دانلود',
      'speedPhaseUpload': 'آپلود',
      'speedStart': 'شروع',
      'speedStarted': 'شروع شده...',
      'speedRestart': 'شروع دوباره',
    },
    'en': {
      'offline': 'Offline',
      'statusDisconnected': 'Offline!',
      'statusIdle': 'Inactive',
      'statusConnected': 'Connected',
      'statusConnecting': 'Connecting',
      'statusReconnecting': 'Reconnecting',
      'statusFailed': 'Error',
      'statusStarting': 'Starting',
      'statusWaitingPermissions': 'Waiting for permissions',
      'statusDisconnecting': 'Disconnecting',
      'protocol': 'Protocol',
      'settingsComingNext': 'Settings — coming in the next step',
      'speedTestComingNext': 'Speed Test — coming in the next step',
      'protocolSheetComingNext':
          'Protocol selection — coming in the next step',
      // ---- v4.16 protocol sheet (translations of the fa verbatim frame +
      // the phase-1 report §11 descriptions) ----
      'sheetHeadingMode': 'Connection mode',
      'modeTunnel': 'Tunnel',
      'modeProxy': 'Proxy',
      'sheetHeadingScanSpeed': 'Scan speed',
      'protocolPageTitle': 'Select protocol',
      'protoAutoSheet': 'Auto',
      'protoAuto': 'AUTO / SMART',
      'protoMasque': 'MASQUE',
      'protoWireguard': 'WIREGUARD',
      'protoGool': 'GOOL',
      'protoGoolClassic': 'GOOL CLASSIC',
      'protoMim': 'MIM',
      'protoTor': 'TOR',
      'protoPsiphon': 'PSIPHON',
      'protoTorOverWarp': 'TOR OVER WARP',
      'protoWarpOverTor': 'WARP OVER TOR',
      'protoPsiphonOverWarp': 'PSIPHON OVER WARP',
      'protoWarpOverPsiphon': 'WARP OVER PSIPHON',
      'protoLantern': 'LANTERN',
      'settingsTitle': 'Settings',
      'settingsRouting': 'Routing',
      'settingsRoutingSub': 'Direct routes',
      'settingsGeneral': 'General',
      'settingsGeneralSub': 'Notifications & events',
      'settingsConnection': 'Connection',
      'settingsConnectionSub': 'Connection & protocol',
      'settingsLanguage': 'Language',
      'settingsLanguageSub': 'Choose the app language',
      'settingsAppearance': 'Appearance',
      'settingsAppearanceSub': 'Personalize the app',
      'settingsSecurity': 'Security',
      'settingsSecuritySub': 'Security & privacy',
      'settingsPsiphon': 'Psiphon',
      'settingsTor': 'Tor',
      'settingsLantern': 'Lantern',
      'lanternLocationDesc': 'Only the countries Lantern’s own servers offer; Auto means the core’s fastest server. While connected, a change applies at once',
      'lanternLocationEmpty': 'The country list arrives from Lantern’s own servers after the first Lantern connection',
      'secLanternTimings': 'Lantern connection budget',
      'lanternConnectSecsLabel': 'Connect budget (seconds)',
      'lanternTimingsDesc': 'Default 180 s: fetching Lantern’s config and reaching a server. Raise it on slow networks',
      'secLanternTunnel': 'Tunnel',
      'lanternUdpLabel': 'UDP pass-through',
      'lanternUdpDesc': 'Off: apps fall back to TCP at once (for apps stuck on “connecting”)',
      'lanternStrictLabel': 'Compatible handshake',
      'lanternStrictDesc': 'The SOCKS hand-off to Lantern runs step by step; steadier for Telegram and long-lived connections',
      'lanternTelegramLabel': 'Telegram proxy',
      'lanternTelegramDesc': 'One tap: sets Lantern’s SOCKS proxy (127.0.0.1:1822) in Telegram',
      'lanternTelegramFailed': 'Telegram isn’t installed on this device',
      'telegramProxyDesc': 'One tap: sets this protocol’s SOCKS proxy ({addr}) in Telegram; works while you’re connected',
      'secTelegram': 'Telegram',
      'secScanSpeed': 'Scan speed',
      'scanTurbo': 'Turbo',
      'scanBalanced': 'Balanced',
      'scanThorough': 'Thorough',
      'scanVerified': 'Verified',
      'scanIronclad': 'Ironclad',
      'scanTurboDesc': 'Fastest scan: fewer samples, exits on the first healthy IP (default)',
      'scanBalancedDesc': 'More samples over several waves; slower than turbo but steadier on filtered networks',
      'scanThoroughDesc': 'A wider scan for hard networks; connecting takes longer',
      'scanVerifiedDesc': 'A deeper, quieter scan (the core’s stealth mode); slower than thorough',
      'scanIroncladDesc': 'The deepest, slowest scan: every IP is tested with a real HTTP request',
      'lanternAndroidOnly': 'Lantern is only available on Android in this version',
      'settingsPillSub': 'Location & more …',
      'settingsAdvancedStatus': 'Configuration status',
      'settingsRoutingArea': 'Routing region',
      'settingsMainServer': 'Core addresses',
      'settingsSubpageComingNext': 'This section — coming in the next step',
      // ---- v4.20 failure visibility + desc-popup port notes ----
      'failureCodeLabel': 'Error code',
      // v2.1.0 — the home widget deck.
      'homeWidgetTimer': 'Session',
      'homeWidgetPing': 'Latency',
      'homeWidgetData': 'Session data',
      'failureDetailsTitle': 'Error details',
      'failureDetailsCopy': 'Copy error details',
      'portNote': 'Local SOCKS port: @p',
      // ---- v4.21 core-log diagnostics ----
      'coreLogTitle': 'Core logs',
      'coreLogOpen': 'View',
      'coreLogCopy': 'Copy log',
      'coreLogClear': 'Clear',
      'coreLogCopied': 'Log copied',
      'coreLogEmpty': 'No log recorded yet — connect first',
      'coreLogSize': 'Log size: @b bytes',
      // ---- v4.22 settings sub-pages ----
      'subCoreTitle': 'Aether core settings',
      'expertMode': 'Expert mode',
      'expertModeDesc': 'Show the advanced core settings for expert users',
      'appliesNextConnect': 'Changes apply from the next connect',
      'secFragment': 'TLS fragmentation',
      'fragOff': 'Off',
      'fragStandard': 'Standard',
      'fragBalanced': 'Balanced',
      'fragAggressive': 'Aggressive',
      'fragCustom': 'Custom',
      'fragOffDesc': 'The ClientHello goes out whole (the core default)',
      'fragStandardDesc': "The core's own default — 8-16 byte shards, 2-10 ms delay",
      'fragBalancedDesc': '40-100 byte shards with a 10-20 ms delay — fits most Iranian networks',
      'fragAggressiveDesc': 'Tiny 1-3 byte shards with a 1-3 ms delay — for the strictest filters',
      'fragCustomDesc': 'Set the size and delay yourself',
      'fragSizeLabel': 'Shard size (bytes)',
      'fragDelayLabel': 'Delay between shards (ms)',
      'fragSizeHint': 'e.g. 40-100',
      'fragDelayHint': 'e.g. 10-20',
      'secTls': 'TLS & fingerprint',
      'tlsCustom': 'Customize TLS',
      'tlsCustomDesc': 'Off: the core fingerprint (Chrome-like) applies',
      'tlsDisableGrease': 'Drop GREASE values',
      'tlsDisableGreaseDesc': 'Leave out the RFC 8701 GREASE values (as Chrome does)',
      'tlsGreaseSigalgs': 'GREASE in signature algorithms',
      'tlsGreaseSigalgsDesc': 'Put a GREASE value first among the sigalgs, as Chrome does',
      'tlsEchGrease': 'GREASE for ECH',
      'tlsEchGreaseDesc': 'Send a GREASE ECH extension when no ECH key is offered',
      'tlsSessionTicket': 'Session Ticket',
      'tlsSessionTicketDesc': 'Ask for session_ticket, as Chrome does',
      'tlsOcsp': 'OCSP Stapling',
      'tlsOcspDesc': 'Ask for status_request, as Chrome does',
      'tlsSct': 'SCT',
      'tlsSctDesc': 'Ask for signed_certificate_timestamps, as Chrome does',
      'tlsExtPerm': 'Extension permutation',
      'tlsExtPermDesc': 'Reorder the extensions on each handshake — off keeps BoringSSL’s fixed order',
      'tlsVerify': 'Verify the MASQUE gateway certificate',
      'tlsVerifyDesc': 'Hold the certificate to the core’s own pins (default: off)',
      'tlsGroups': 'TLS groups',
      'tlsGroupsHint': 'e.g. P-256:X25519:P-384',
      'tlsKeyShares': 'Key shares',
      'tlsKeySharesHint': 'e.g. X25519:P-256',
      'tlsCiphers12': 'TLS 1.2 cipher suites',
      'tlsCiphers12Hint': 'colon-separated — e.g. ECDHE-RSA-AES128-GCM-SHA256',
      'tlsCiphers13': 'TLS 1.3 cipher suites',
      'tlsCiphers13Hint': 'e.g. TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256',
      'masqueSni': 'Manual MASQUE SNI',
      'masqueSniHint': 'e.g. www.cloudflare.com',
      'secTransport': 'Transport',
      'h2Transport': 'HTTP/2 (TCP) transport',
      'h2TransportDesc': 'MASQUE over HTTP/2 (TCP) — the new app default; for networks that block UDP',
      'quicV2': 'QUIC v2 negotiation',
      'quicV2Desc': 'Opens a path for HTTP/3 where QUIC v1 is blocked',
      'secEngine': 'Engine',
      'noizeLabel': 'Obfuscation profile (Noize)',
      'noizeDesc': 'New app default: Balanced; try GFW or Aggressive on strict networks',
      'noizeDefault': 'Core default',
      'noizeOff': 'Off',
      'noizeLight': 'Light',
      'noizeFirewall': 'Firewall',
      'noizeBalanced': 'Balanced',
      'noizeGfw': 'GFW',
      'noizeAggressive': 'Aggressive',
      'perfLabel': 'Resource profile',
      'perfAuto': 'Auto',
      'perfLow': 'Low',
      'perfMedium': 'Medium',
      'perfHigh': 'High',
      'logLevelLabel': 'Core log level',
      'logInfo': 'Info',
      'logDebug': 'Debug',
      'logTrace': 'Trace',
      'keepaliveLabel': 'WireGuard keepalive interval (s)',
      'secRoutes': 'Direct & blocked routes',
      'routeBlockLabel': 'Always-blocked domains',
      'routeBlockHint': 'comma or newline separated — e.g. ads.example.com',
      'routeDirectLabel': 'Always-direct domains (outside the tunnel)',
      'routeDirectHint': 'e.g. bank.example.com',
      'routesDesc': 'full: that exact name only, keyword: any name containing it; bare entries cover the domain and every subdomain',
      'routingNone': 'None',
      'routingAreaDesc': "The selected country's own traffic (its domains and IP ranges) goes direct, bypassing the tunnel; everything else keeps tunneling.",
      'tunnelApps': 'Tunnel apps',
      'tunnelAppsModeAll': 'All apps',
      'tunnelAppsModeAllow': 'Only selected apps',
      'tunnelAppsModeDisallow': 'Except selected apps',
      'tunnelAppsDesc': 'Choose which apps go through the tunnel; applies in tunnel mode on Android, from the next connect.',
      'tunnelAppsLoading': 'Loading the app list…',
      'tunnelAppsLoadFailed': 'The app list is unavailable',
      'hybridRouting': "Hybrid routing",
      'hybridRoutingOpen': "Manage routing rules",
      'hybridRoutingDesc': "Choose which tunnel of this hybrid protocol each app, domain or IP uses.",
      'hybridRoutes': "Routes of this protocol",
      'hybridDefaultRoute': "default",
      'hybridDefaultNote': "Traffic without a rule keeps the default route {route}, exactly as before.",
      'hybridApps': "App routes",
      'hybridDomains': "Domain routes",
      'hybridIps': "IP routes",
      'hybridAddApps': "Add apps",
      'hybridAddDomain': "Add domain",
      'hybridAddIp': "Add IP",
      'hybridDomainHint': "example.com or *.example.com",
      'hybridIpHint': "1.1.1.1, 192.168.1.0/24 or 2606:4700::/32",
      'hybridSearchApps': "Search apps",
      'hybridErrEmpty': "Nothing entered",
      'hybridErrInvalid': "Not a valid entry",
      'hybridErrDuplicate': "Already added",
      'hybridConflict': "Overlaps {rules} on another tunnel; the more specific rule wins.",
      'hybridEmpty': "No rules yet",
      'hybridInvalidTunnel': "This route does not exist in this protocol; its traffic is blocked until you fix the rule",
      'hybridEngineRejected': "The engine refused this rule",
      'hybridRuleOff': "Off",
      'hybridSave': "Save",
      'hybridAppliedNext': "Applies from the next tunnel connect with this protocol",
      'hybridApplyFailed': "The engine could not apply the rules ({error})",
      'hybridNotRouted': "This connection started without hybrid routing; reconnect once",
      'hybridStatusLive': "Active in the engine: {n} rules",
      'hybridAppUnsupported': "App routing needs Android 10 or newer",
      'hybridWildcardNote': "example.com matches only that exact name; *.example.com matches its subdomains (like www.example.com), not example.com itself.",
      'hybridPriority': "Priority: app → exact domain → wildcard domain (most specific) → IP/CIDR (smallest range) → default route. An app rule beats domain and IP rules for that app.",
      'hybridLimits': "Limits: domains are recognised from the tunnel's own DNS; apps with their own encrypted DNS (DoH/DoT) or that connect straight to an IP are routed only by app or IP rules. IP rules apply only to direct-to-IP connections. If the chosen tunnel is down, that rule's traffic is blocked — it never goes direct. UDP (except DNS) is not carried in these protocols. Tunnel mode on Android only.",
      'hybridPickTunnel': "Route",
      'hybridFlows': "{n} connections",
      'secProtocolMode': 'Protocol mode',
      'protoModeSmart': 'SMART',
      'smartNote': 'In SMART mode the app itself picks the protocol instead of the core default: the candidates (masque, wireguard, gool, mim, gool-classic) are tried in the order of their measured success and latency until one connects. The attempt chain is shown on the home screen, the measured latency is remembered, and your manual pick is never rewritten. Active only with the AUTO tile.',
      'smartAttemptLabel': 'SMART: {name} ({i} of {n})',
      'smartMeasuringLabel': 'Measuring {name} quality…',
      'coreRowDesc': 'Fragmentation, TLS, transport and engine',
      'secAbout': 'About the app',
      'appVersionLabel': 'App version',
      'betaStage': 'Beta',
      'telegramRow': 'Telegram channel',
      'githubRow': 'GitHub repository',
      'instagramRow': 'Instagram',
      'secNotifications': 'Notifications & events',
      'notificationsComing':
          "While connected, Android's notification carries a Disconnect action right on it; on the desktop the system-tray menu toggles the connection.",
      'notificationsRow': 'Connection notification',
      'notificationsOn': 'On',
      'secCloseBehavior': 'Close-button behavior',
      'closeBehaviorAsk': 'Ask every time',
      'closeBehaviorTray': 'Go to tray',
      'closeBehaviorClose': 'Close fully',
      'closeBehaviorDesc': 'Chooses what the close button does: ask each time, hide straight to the system tray, or close the app completely.',
      'closeDialogTitle': 'Closing AETHONE',
      'closeDialogBody': 'Should the app close completely, or stay in the system tray with the connection running?',
      'closeDialogToTray': 'Go to system tray',
      'closeDialogFullClose': 'Close completely',
      'closeDialogRemember': 'Remember my choice for next time',
      'closeDialogCancel': 'Cancel',
      'secAutoStart': 'Auto-start',
      'autoStartTitle': 'Launch at sign-in',
      'autoStartDesc': 'Start AETHONE automatically when you sign in to the system.',
      'autoStartFailed': 'Could not register the auto-start',
      'secReset': 'Reset',
      'resetTitle': 'Reset settings',
      'resetDesc': 'Return every setting to its factory default.',
      'resetConfirmBody': 'All settings return to their defaults. This cannot be undone.',
      'resetConfirmYes': 'Reset now',
      'secThemeMode': 'Display mode',
      'themePickNight': 'Night',
      'themePickLight': 'Light',
      'themePickAuto': 'Auto',
      'themeAutoNote': 'Auto: light from 6 AM to 6 PM, night from 6 PM to 6 AM.',
      'secAppLanguage': 'App language',
      'langSystem': 'Follow system',
      'langDesc': 'The interface language — Persian by default',
      'secHomeLook': 'Home screen look',
      'lookOne': 'Look 1',
      'lookTwo': 'Look 2',
      'secMotion': 'Animation',
      'motionStandard': 'Standard',
      'motionSmooth': 'Smooth',
      'motionDynamic': 'Dynamic',
      'motionMinimal': 'Minimal',
      'animationsOffTitle': 'Turn off all animations',
      'animationsOffDesc': 'Stops every animation in the app instantly',
      'secPatterns': 'Background patterns',
      'showPatterns': 'Show background patterns',
      'showPatternsDesc': 'The green/red patterns on every page',
      'secKillSwitch': 'Kill Switch',
      'killSwitchDesc': 'Stops traffic leaking when the connection drops — full OS integration lands in the next step',
      'secDiagnostics': 'Diagnostics',
      'secExitLocation': 'Exit location',
      'psiphonLocationDesc': 'Applies to the psiphon-exit modes; Auto means the core’s own choice',
      'secFronting': 'CDN fronting',
      'frontingModeLabel': 'Fronting mode',
      'frontingAuto': 'Auto',
      'frontingAutoDesc': 'The core picks (default)',
      'frontingCdn': 'CDN only',
      'frontingCdnDesc': 'Front only through meek CDNs — for networks that block the rest',
      'frontingDirect': 'Direct',
      'frontingDirectDesc': 'No fronting',
      'cdnSniLabel': 'CDN edge server names (SNI)',
      'cdnSniHint': 'comma-separated — e.g. cdn.example.com',
      'cdnIpsLabel': 'CDN edge addresses',
      'cdnIpsHint': 'e.g. 104.16.0.1,104.16.1.1',
      'torLocationDesc': 'Your pick is remembered and shown on the home screen; the Tor core picks the exit from the available relays',
      'secTorBridges': 'Tor bridges',
      'bridgesLabel': 'Bridge policy',
      'bridgesAuto': 'Auto',
      'bridgesAutoDesc': 'The core fetches bridges from bridgedb and tries the suitable ones',
      'bridgesOff': 'No bridges',
      'bridgesOffDesc': 'Bridges off (only for networks that do not filter Tor)',
      'torLogLevelLabel': 'Tor log level',
      // v4.31 — the round-7 settings expansion.
      'bridgesCustom': 'Manual',
      'bridgesCustomDesc': 'Enter your own bridge lines; the core uses them instead of the ones fetched from bridgedb',
      'torBridgeLinesLabel': 'Bridge lines',
      'torBridgeLinesHint': 'one bridge per line — e.g. obfs4 1.2.3.4:443 CERT=… iat-mode=0',
      'secTorTimings': 'Tor connection budgets',
      'torDirectSecsLabel': 'Direct attempt budget (seconds)',
      'torBridgeSecsLabel': 'Per-bridge budget (seconds)',
      'torTimingsDesc': 'Core defaults: 75 s direct and 360 s per bridge. Raise them on slow networks',
      'cdnSetsLabel': 'Fronting sets',
      'cdnSetsHint': 'comma-separated — e.g. psiphon-akamai,vercel (empty = all)',
      'cdnSetsDesc': 'Which built-in psiphon edge lists the CDN fronting uses',
      'secPsiphonTimings': 'Ready budget',
      'psiphonReadyLabel': 'Psiphon ready budget (seconds)',
      'psiphonReadyDesc': 'The core default is 180 s; raise it on slow networks — the app walk budget widens with it',
      'serverEntriesLabel': 'Server entries',
      'serverEntriesHint': 'the server-entries JSON from the official psiphon client',
      'serverEntriesDesc': 'Empty means the built-in psiphon discovery',
      'secFamilyLeg': 'Base of the combined modes',
      'aetherLegLabel': 'Base of the combined modes',
      'torLegDesc': 'In the combined tor modes (chain and reverse) the underlying Aether tunnel runs this protocol. On the reverse mode the UDP-needing legs map to MASQUE automatically (a core limit)',
      'psiphonLegDesc': 'In the combined psiphon modes (chain and reverse) the underlying Aether tunnel runs this protocol. On the reverse mode the UDP-needing legs map to MASQUE automatically (a core limit)',
      'secIpVersion': 'IP version',
      'ipV4': 'IPv4',
      'ipV6': 'IPv6',
      'ipDual': 'Dual',
      'ipVersionDesc': "Some carriers carry broken IPv6; IPv4 is the core's own default",
      'secUpstream': 'Upstream proxy',
      'upstreamLabel': 'Proxy address (optional)',
      'upstreamHint': 'socks5://127.0.0.1:1080',
      'upstreamDesc': 'Plain Aether modes only; the core dials through this proxy. Empty = off',
      'echLabel': 'ECH (encrypted SNI)',
      'echOff': 'Off',
      'echAuto': 'Auto',
      'echManual': 'Manual',
      'echOffDesc': 'The SNI is sent as usual',
      'echAutoDesc': 'The ECH key is looked up over DNS and the server name travels encrypted',
      'echManualDesc': 'You provide the base64 ECH key yourself',
      'echKeyLabel': 'ECH key (base64)',
      'echKeyHint': 'e.g. AEDW…',
      'echDnsLabel': 'Key-lookup DNS',
      'echDnsHint': 'e.g. https://1.1.1.1/dns-query',
      'echDomainLabel': 'Key domain (optional)',
      'echDomainHint': 'default: cloudflare-ech.com',
      // v6 login.
      'loginWelcomeTitle': 'Ready for an adventure?',
      'loginLanguageTitle': 'App language',
      'loginRoutingTitle': 'Routing region',
      'loginLookTitle': 'App appearance',
      'loginDoneTitle': 'Setup complete!',
      'loginWelcomeDesc':
          "In a few simple steps, get to know AETHONE's features — pick your connection mode and protocol, and personalize the settings to your needs. Your journey toward a more flexible connection and new routes starts right here!",
      'loginDoneDesc':
          "Everything's ready to start! You've finished the initial setup and can now step into the world of AETHONE. Head to the home screen, establish the connection you want, and begin your adventure with a fresher experience of freer communication!",
      'loginNext': 'Next',
      'loginPrev': 'Back',
      'loginGo': "Let's go!",
      'langTurkmen': 'Türkmençe',
      'speedTestTitle': 'Speed Test',
      'speedPhasePing': 'Ping',
      'speedPhaseDownload': 'Download',
      'speedPhaseUpload': 'Upload',
      'speedStart': 'Start',
      'speedStarted': 'Started...',
      'speedRestart': 'Start again',
    },
    'ru': {
      'offline': 'Офлайн',
      'statusDisconnected': 'Оффлайн!',
      'statusIdle': 'Неактивно',
      'statusConnected': 'Подключено',
      'statusConnecting': 'Подключение',
      'statusReconnecting': 'Переподключение',
      'statusFailed': 'Ошибка',
      'statusStarting': 'Запуск',
      'statusWaitingPermissions': 'Ожидание разрешений',
      'statusDisconnecting': 'Отключение',
      'protocol': 'Протокол',
      'settingsComingNext': 'Настройки — на следующем шаге',
      'speedTestComingNext': 'Тест скорости — на следующем шаге',
      'protocolSheetComingNext': 'Выбор протокола — на следующем шаге',
      // ---- v4.16 protocol sheet ----
      'sheetHeadingMode': 'Режим подключения',
      'modeTunnel': 'Туннель',
      'modeProxy': 'Прокси',
      'sheetHeadingScanSpeed': 'Скорость сканирования',
      'protocolPageTitle': 'Выбор протокола',
      'protoAutoSheet': 'Авто',
      'protoAuto': 'АВТО / УМНЫЙ',
      'protoMasque': 'MASQUE',
      'protoWireguard': 'WIREGUARD',
      'protoGool': 'GOOL',
      'protoGoolClassic': 'GOOL CLASSIC',
      'protoMim': 'MIM',
      'protoTor': 'TOR',
      'protoPsiphon': 'PSIPHON',
      'protoTorOverWarp': 'TOR OVER WARP',
      'protoWarpOverTor': 'WARP OVER TOR',
      'protoPsiphonOverWarp': 'PSIPHON OVER WARP',
      'protoWarpOverPsiphon': 'WARP OVER PSIPHON',
      'protoLantern': 'LANTERN',
      'settingsTitle': 'Настройки',
      'settingsRouting': 'Маршрутизация',
      'settingsRoutingSub': 'Прямые маршруты',
      'settingsGeneral': 'Общие',
      'settingsGeneralSub': 'Уведомления и события',
      'settingsConnection': 'Подключение',
      'settingsConnectionSub': 'Подключение и протокол',
      'settingsLanguage': 'Язык',
      'settingsLanguageSub': 'Выбор языка приложения',
      'settingsAppearance': 'Оформление',
      'settingsAppearanceSub': 'Персонализация приложения',
      'settingsSecurity': 'Безопасность',
      'settingsSecuritySub': 'Безопасность и приватность',
      'settingsPsiphon': 'Psiphon',
      'settingsTor': 'Tor',
      'settingsLantern': 'Lantern',
      'lanternLocationDesc': 'Только страны, которые предлагают серверы самого Lantern; «Авто» — самый быстрый сервер по выбору ядра. При подключении изменение применяется сразу',
      'lanternLocationEmpty': 'Список стран придёт с серверов Lantern после первого подключения',
      'secLanternTimings': 'Лимит подключения Lantern',
      'lanternConnectSecsLabel': 'Лимит подключения (секунды)',
      'lanternTimingsDesc': 'По умолчанию 180 с: загрузка конфигурации Lantern и выход на сервер. Увеличьте в медленных сетях',
      'secLanternTunnel': 'Туннель',
      'lanternUdpLabel': 'Пропуск UDP',
      'lanternUdpDesc': 'Выкл.: приложения сразу переходят на TCP (для зависших на «подключении»)',
      'lanternStrictLabel': 'Совместимое рукопожатие',
      'lanternStrictDesc': 'SOCKS-подключение к Lantern идёт пошагово; стабильнее для Telegram и долгих соединений',
      'lanternTelegramLabel': 'Прокси Telegram',
      'lanternTelegramDesc': 'Одно касание: SOCKS-прокси Lantern (127.0.0.1:1822) в Telegram',
      'lanternTelegramFailed': 'Telegram не установлен на этом устройстве',
      'telegramProxyDesc': 'Одно касание: SOCKS-прокси этого протокола ({addr}) в Telegram; работает, пока есть подключение',
      'secTelegram': 'Telegram',
      'secScanSpeed': 'Скорость сканирования',
      'scanTurbo': 'Турбо',
      'scanBalanced': 'Баланс',
      'scanThorough': 'Полное',
      'scanVerified': 'Проверенное',
      'scanIronclad': 'Строгое',
      'scanTurboDesc': 'Самое быстрое: меньше проб, выход на первом рабочем IP (по умолчанию)',
      'scanBalancedDesc': 'Больше проб в несколько волн; медленнее турбо, но надёжнее в фильтруемых сетях',
      'scanThoroughDesc': 'Широкое сканирование для сложных сетей; подключение дольше',
      'scanVerifiedDesc': 'Более глубокое и незаметное сканирование (режим stealth ядра)',
      'scanIroncladDesc': 'Самое глубокое и медленное: каждый IP проверяется реальным HTTP-запросом',
      'lanternAndroidOnly': 'В этой версии Lantern доступен только на Android',
      'settingsPillSub': 'Локация и другое …',
      'settingsAdvancedStatus': 'Статус конфигурации',
      'settingsRoutingArea': 'Регион маршрутизации',
      'settingsMainServer': 'Адреса ядер',
      'settingsSubpageComingNext': 'Этот раздел — на следующем шаге',
      'failureCodeLabel': 'Код ошибки',
      // v2.1.0 — the home widget deck.
      'homeWidgetTimer': 'Сессия',
      'homeWidgetPing': 'Задержка',
      'homeWidgetData': 'Данные сессии',
      'failureDetailsTitle': 'Детали ошибки',
      'failureDetailsCopy': 'Копировать детали ошибки',
      'portNote': 'Локальный порт SOCKS: @p',
      // ---- v4.21 core-log diagnostics ----
      'coreLogTitle': 'Логи ядер',
      'coreLogOpen': 'Открыть',
      'coreLogCopy': 'Копировать лог',
      'coreLogClear': 'Очистить',
      'coreLogCopied': 'Лог скопирован',
      'coreLogEmpty': 'Лог пока пуст — сначала подключитесь',
      'coreLogSize': 'Размер лога: @b байт',
      // ---- v4.22 settings sub-pages ----
      'subCoreTitle': 'Настройки ядра Aether',
      'expertMode': 'Экспертный режим',
      'expertModeDesc': 'Показать расширенные настройки ядра для профессионалов',
      'appliesNextConnect': 'Изменения применятся со следующего подключения',
      'secFragment': 'Фрагментация TLS',
      'fragOff': 'Выкл.',
      'fragStandard': 'Стандартная',
      'fragBalanced': 'Сбалансированная',
      'fragAggressive': 'Агрессивная',
      'fragCustom': 'Своя',
      'fragOffDesc': 'ClientHello отправляется целиком (по умолчанию ядра)',
      'fragStandardDesc': 'Собственное умолчание ядра — куски 8-16 байт, пауза 2-10 мс',
      'fragBalancedDesc': 'Куски 40-100 байт с паузой 10-20 мс — подходит большинству иранских сетей',
      'fragAggressiveDesc': 'Мелкие куски 1-3 байта с паузой 1-3 мс — для строжайших фильтров',
      'fragCustomDesc': 'Задайте размер и паузу вручную',
      'fragSizeLabel': 'Размер куска (байт)',
      'fragDelayLabel': 'Пауза между кусками (мс)',
      'fragSizeHint': 'напр. 40-100',
      'fragDelayHint': 'напр. 10-20',
      'secTls': 'TLS и отпечаток',
      'tlsCustom': 'Настроить TLS',
      'tlsCustomDesc': 'Выкл.: действует отпечаток ядра (как у Chrome)',
      'tlsDisableGrease': 'Убрать значения GREASE',
      'tlsDisableGreaseDesc': 'Не отправлять значения GREASE (RFC 8701)',
      'tlsGreaseSigalgs': 'GREASE в алгоритмах подписи',
      'tlsGreaseSigalgsDesc': 'GREASE-значение первым в signature_algorithms, как у Chrome',
      'tlsEchGrease': 'GREASE для ECH',
      'tlsEchGreaseDesc': 'Отправлять GREASE-расширение ECH, когда ключ ECH не предлагается',
      'tlsSessionTicket': 'Session Ticket',
      'tlsSessionTicketDesc': 'Запрашивать session_ticket, как Chrome',
      'tlsOcsp': 'OCSP Stapling',
      'tlsOcspDesc': 'Запрашивать status_request, как Chrome',
      'tlsSct': 'SCT',
      'tlsSctDesc': 'Запрашивать signed_certificate_timestamps, как Chrome',
      'tlsExtPerm': 'Перестановка расширений',
      'tlsExtPermDesc': 'Менять порядок расширений при каждом handshake — выкл. держит фиксированный порядок BoringSSL',
      'tlsVerify': 'Проверять сертификат шлюза MASQUE',
      'tlsVerifyDesc': 'Сверять сертификат с пинами ядра (по умолчанию: выкл.)',
      'tlsGroups': 'Группы TLS',
      'tlsGroupsHint': 'напр. P-256:X25519:P-384',
      'tlsKeyShares': 'Key shares',
      'tlsKeySharesHint': 'напр. X25519:P-256',
      'tlsCiphers12': 'Шифры TLS 1.2',
      'tlsCiphers12Hint': 'через двоеточие — напр. ECDHE-RSA-AES128-GCM-SHA256',
      'tlsCiphers13': 'Шифры TLS 1.3',
      'tlsCiphers13Hint': 'напр. TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256',
      'masqueSni': 'Ручной SNI MASQUE',
      'masqueSniHint': 'напр. www.cloudflare.com',
      'secTransport': 'Транспорт',
      'h2Transport': 'Транспорт HTTP/2 (TCP)',
      'h2TransportDesc': 'MASQUE по HTTP/2 (TCP) — новый стандарт приложения; для сетей, блокирующих UDP',
      'quicV2': 'Согласование QUIC v2',
      'quicV2Desc': 'Открывает путь для HTTP/3 там, где QUIC v1 заблокирован',
      'secEngine': 'Движок',
      'noizeLabel': 'Профиль обфускации (Noize)',
      'noizeDesc': 'Новый стандарт приложения: Balanced; на строгих сетях попробуйте GFW или Aggressive',
      'noizeDefault': 'Как в ядре',
      'noizeOff': 'Выкл.',
      'noizeLight': 'Лёгкий',
      'noizeFirewall': 'Firewall',
      'noizeBalanced': 'Сбалансированный',
      'noizeGfw': 'GFW',
      'noizeAggressive': 'Агрессивный',
      'perfLabel': 'Профиль ресурсов',
      'perfAuto': 'Авто',
      'perfLow': 'Низкий',
      'perfMedium': 'Средний',
      'perfHigh': 'Высокий',
      'logLevelLabel': 'Уровень логов ядра',
      'logInfo': 'Инфо',
      'logDebug': 'Отладка',
      'logTrace': 'Трассировка',
      'keepaliveLabel': 'Интервал keepalive WireGuard (с)',
      'secRoutes': 'Прямые и заблокированные маршруты',
      'routeBlockLabel': 'Всегда блокируемые домены',
      'routeBlockHint': 'через запятую или с новой строки — напр. ads.example.com',
      'routeDirectLabel': 'Всегда прямые домены (мимо туннеля)',
      'routeDirectHint': 'напр. bank.example.com',
      'routesDesc': 'full: только точное имя, keyword: любое имя с этим словом; без префикса — домен и все поддомены',
      'routingNone': 'Нет',
      'routingAreaDesc': 'Трафик выбранной страны (её домены и IP-диапазоны) идёт напрямую, минуя туннель; всё остальное — через туннель.',
      'tunnelApps': 'Приложения туннеля',
      'tunnelAppsModeAll': 'Все приложения',
      'tunnelAppsModeAllow': 'Только выбранные',
      'tunnelAppsModeDisallow': 'Кроме выбранных',
      'tunnelAppsDesc': 'Выберите, какие приложения проходят через туннель; действует в режиме туннеля на Android, начиная со следующего подключения.',
      'tunnelAppsLoading': 'Загрузка списка приложений…',
      'tunnelAppsLoadFailed': 'Список приложений недоступен',
      'hybridRouting': "Гибридная маршрутизация",
      'hybridRoutingOpen': "Правила маршрутов",
      'hybridRoutingDesc': "Выберите, через какой туннель этого гибридного протокола идёт каждое приложение, домен или IP.",
      'hybridRoutes': "Маршруты протокола",
      'hybridDefaultRoute': "по умолчанию",
      'hybridDefaultNote': "Трафик без правила идёт по маршруту по умолчанию {route}, как и раньше.",
      'hybridApps': "Приложения",
      'hybridDomains': "Домены",
      'hybridIps': "IP-адреса",
      'hybridAddApps': "Добавить приложения",
      'hybridAddDomain': "Добавить домен",
      'hybridAddIp': "Добавить IP",
      'hybridDomainHint': "example.com или *.example.com",
      'hybridIpHint': "1.1.1.1, 192.168.1.0/24 или 2606:4700::/32",
      'hybridSearchApps': "Поиск приложений",
      'hybridErrEmpty': "Ничего не введено",
      'hybridErrInvalid': "Неверное значение",
      'hybridErrDuplicate': "Уже добавлено",
      'hybridConflict': "Пересекается с {rules} на другом туннеле; действует более точное правило.",
      'hybridEmpty': "Правил пока нет",
      'hybridInvalidTunnel': "Этого маршрута нет в протоколе; трафик блокируется, пока правило не исправлено",
      'hybridEngineRejected': "Движок отклонил правило",
      'hybridRuleOff': "Выкл.",
      'hybridSave': "Сохранить",
      'hybridAppliedNext': "Применится при следующем подключении туннеля с этим протоколом",
      'hybridApplyFailed': "Движок не смог применить правила ({error})",
      'hybridNotRouted': "Подключение начато без гибридной маршрутизации; переподключитесь",
      'hybridStatusLive': "Активно в движке: {n}",
      'hybridAppUnsupported': "Маршрутизация приложений требует Android 10+",
      'hybridWildcardNote': "example.com — только это имя; *.example.com — только поддомены (www.example.com), но не сам example.com.",
      'hybridPriority': "Приоритет: приложение → точный домен → wildcard (самый точный) → IP/CIDR (самый узкий) → маршрут по умолчанию.",
      'hybridLimits': "Ограничения: домены определяются по DNS туннеля; приложения со своим шифрованным DNS (DoH/DoT) или прямым подключением к IP маршрутизируются только правилами приложений или IP. Правила IP действуют только для прямых подключений к IP. Если выбранный туннель недоступен, трафик правила блокируется и никогда не идёт напрямую. UDP (кроме DNS) не передаётся. Только режим туннеля на Android.",
      'hybridPickTunnel': "Маршрут",
      'hybridFlows': "{n} соединений",
      'secProtocolMode': 'Режим протокола',
      'protoModeSmart': 'СМАРТ',
      'smartNote': 'В режиме SMART приложение само выбирает протокол вместо значения ядра по умолчанию: кандидаты (masque, wireguard, gool, mim, gool-classic) пробуются в порядке измеренных успехов и задержек, пока один не подключится. Цепочка попыток видна на главном экране, измеренная задержка запоминается, а ваш ручной выбор никогда не перезаписывается. Активен только с плиткой AUTO.',
      'smartAttemptLabel': 'SMART: {name} ({i} из {n})',
      'smartMeasuringLabel': 'Замер качества {name}…',
      'coreRowDesc': 'Фрагментация, TLS, транспорт и движок',
      'secAbout': 'О приложении',
      'appVersionLabel': 'Версия приложения',
      'betaStage': 'Бета-версия',
      'telegramRow': 'Канал Telegram',
      'githubRow': 'Репозиторий GitHub',
      'instagramRow': 'Instagram',
      'secNotifications': 'Уведомления и события',
      'notificationsComing': 'Во время подключения уведомление Android несёт действие «Отключить» прямо в себе; на десктопе соединением управляет меню значка в трее.',
      'notificationsRow': 'Уведомление о подключении',
      'notificationsOn': 'Вкл',
      'secCloseBehavior': 'Поведение кнопки закрытия',
      'closeBehaviorAsk': 'Спрашивать',
      'closeBehaviorTray': 'В трей',
      'closeBehaviorClose': 'Закрыть полностью',
      'closeBehaviorDesc': 'Что делает кнопка закрытия: спрашивать каждый раз, сразу свернуть в системный трей или полностью закрыть приложение.',
      'closeDialogTitle': 'Закрытие AETHONE',
      'closeDialogBody': 'Закрыть приложение полностью или оставить в системном трее с работающим подключением?',
      'closeDialogToTray': 'Свернуть в системный трей',
      'closeDialogFullClose': 'Закрыть полностью',
      'closeDialogRemember': 'Запомнить мой выбор на будущее',
      'closeDialogCancel': 'Отмена',
      'secAutoStart': 'Автозапуск',
      'autoStartTitle': 'Запускать при входе в систему',
      'autoStartDesc': 'AETHONE запускается автоматически при входе в систему.',
      'autoStartFailed': 'Не удалось зарегистрировать автозапуск',
      'secReset': 'Сброс',
      'resetTitle': 'Сброс настроек',
      'resetDesc': 'Вернуть все настройки к заводским значениям.',
      'resetConfirmBody': 'Все настройки вернутся к значениям по умолчанию. Действие необратимо.',
      'resetConfirmYes': 'Сбросить',
      'secThemeMode': 'Режим оформления',
      'themePickNight': 'Ночной',
      'themePickLight': 'Светлый',
      'themePickAuto': 'Авто',
      'themeAutoNote': 'Авто: светлый с 6:00 до 18:00, ночной с 18:00 до 6:00.',
      'secAppLanguage': 'Язык приложения',
      'langSystem': 'Как в системе',
      'langDesc': 'Язык интерфейса — по умолчанию персидский',
      'secHomeLook': 'Вид главного экрана',
      'lookOne': 'Вид 1',
      'lookTwo': 'Вид 2',
      'secMotion': 'Анимация',
      'motionStandard': 'Стандартная',
      'motionSmooth': 'Плавная',
      'motionDynamic': 'Динамичная',
      'motionMinimal': 'Минимальная',
      'animationsOffTitle': 'Отключить все анимации',
      'animationsOffDesc': 'Мгновенно останавливает все анимации приложения',
      'secPatterns': 'Фоновые узоры',
      'showPatterns': 'Показывать фоновые узоры',
      'showPatternsDesc': 'Зелёные/красные узоры по краям всех страниц',
      'secKillSwitch': 'Kill Switch',
      'killSwitchDesc': 'Не пропускает трафик при разрыве — полная интеграция с ОС в следующем шаге',
      'secDiagnostics': 'Диагностика',
      'secExitLocation': 'Локация выхода',
      'psiphonLocationDesc': 'Действует в режимах выхода через Psiphon; «Авто» — выбор самого ядра',
      'secFronting': 'CDN-фронтинг',
      'frontingModeLabel': 'Режим фронтинга',
      'frontingAuto': 'Авто',
      'frontingAutoDesc': 'Ядро выбирает само (по умолчанию)',
      'frontingCdn': 'Только CDN',
      'frontingCdnDesc': 'Фронтить только через meek-CDN — для сетей, блокирующих остальное',
      'frontingDirect': 'Напрямую',
      'frontingDirectDesc': 'Без фронтинга',
      'cdnSniLabel': 'SNI серверов CDN',
      'cdnSniHint': 'через запятую — напр. cdn.example.com',
      'cdnIpsLabel': 'Адреса CDN',
      'cdnIpsHint': 'напр. 104.16.0.1,104.16.1.1',
      'torLocationDesc': 'Выбор запоминается и показывается на главном экране; ядро Tor выбирает выход из доступных узлов',
      'secTorBridges': 'Мосты Tor',
      'bridgesLabel': 'Политика мостов',
      'bridgesAuto': 'Авто',
      'bridgesAutoDesc': 'Ядро получает мосты из bridgedb и пробует подходящие',
      'bridgesOff': 'Без мостов',
      'bridgesOffDesc': 'Мосты выключены (для сетей без фильтрации Tor)',
      'torLogLevelLabel': 'Уровень логов Tor',
      // v4.31 — the round-7 settings expansion.
      'bridgesCustom': 'Вручную',
      'bridgesCustomDesc': 'Введите свои строки мостов; ядро использует их вместо полученных от bridgedb',
      'torBridgeLinesLabel': 'Строки мостов',
      'torBridgeLinesHint': 'один мост на строку — напр. obfs4 1.2.3.4:443 CERT=… iat-mode=0',
      'secTorTimings': 'Лимиты подключения Tor',
      'torDirectSecsLabel': 'Лимит прямой попытки (сек)',
      'torBridgeSecsLabel': 'Лимит на мост (сек)',
      'torTimingsDesc': 'По умолчанию ядра: 75 с напрямую и 360 с на мост. Увеличьте в медленных сетях',
      'cdnSetsLabel': 'Наборы фронтинга',
      'cdnSetsHint': 'через запятую — напр. psiphon-akamai,vercel (пусто = все)',
      'cdnSetsDesc': 'Какие встроенные списки рёбер psiphon использует CDN-фронтинг',
      'secPsiphonTimings': 'Лимит готовности',
      'psiphonReadyLabel': 'Лимит готовности psiphon (сек)',
      'psiphonReadyDesc': 'По умолчанию ядра 180 с; увеличьте в медленных сетях — бюджет самого приложения расширяется вместе с ним',
      'serverEntriesLabel': 'Записи серверов',
      'serverEntriesHint': 'JSON записей серверов из официального клиента psiphon',
      'serverEntriesDesc': 'Пусто — встроенное обнаружение psiphon',
      'secFamilyLeg': 'Основа комбинированных режимов',
      'aetherLegLabel': 'Основа комбинированных режимов',
      'torLegDesc': 'В комбинированных режимах tor (цепочка и обратный) туннель Aether работает по этому протоколу. В обратном режиме ветки с UDP автоматически переходят на MASQUE (ограничение ядра)',
      'psiphonLegDesc': 'В комбинированных режимах psiphon (цепочка и обратный) туннель Aether работает по этому протоколу. В обратном режиме ветки с UDP автоматически переходят на MASQUE (ограничение ядра)',
      'secIpVersion': 'Версия IP',
      'ipV4': 'IPv4',
      'ipV6': 'IPv6',
      'ipDual': 'Обе',
      'ipVersionDesc': 'У некоторых операторов IPv6 сломан; IPv4 — значение ядра по умолчанию',
      'secUpstream': 'Вышестоящий прокси',
      'upstreamLabel': 'Адрес прокси (необязательно)',
      'upstreamHint': 'socks5://127.0.0.1:1080',
      'upstreamDesc': 'Только для обычных режимов Aether; ядро ходит через этот прокси. Пусто = выкл',
      'echLabel': 'ECH (шифрование SNI)',
      'echOff': 'Выкл',
      'echAuto': 'Авто',
      'echManual': 'Вручную',
      'echOffDesc': 'SNI отправляется как обычно',
      'echAutoDesc': 'Ключ ECH ищется через DNS, имя сервера уходит зашифрованным',
      'echManualDesc': 'Вы указываете base64-ключ ECH сами',
      'echKeyLabel': 'Ключ ECH (base64)',
      'echKeyHint': 'напр. AEDW…',
      'echDnsLabel': 'DNS для поиска ключа',
      'echDnsHint': 'напр. https://1.1.1.1/dns-query',
      'echDomainLabel': 'Домен ключа (необязательно)',
      'echDomainHint': 'по умолчанию: cloudflare-ech.com',
      // v6 login.
      'loginWelcomeTitle': 'Готовы к приключению?',
      'loginLanguageTitle': 'Язык приложения',
      'loginRoutingTitle': 'Регион маршрутизации',
      'loginLookTitle': 'Внешний вид приложения',
      'loginDoneTitle': 'Настройка завершена!',
      'loginWelcomeDesc':
          'За несколько простых шагов познакомьтесь с возможностями AETHONE: выберите режим подключения и протокол и настройте всё под себя. Ваше приключение — более гибкое подключение и поиск новых маршрутов — начинается прямо здесь!',
      'loginDoneDesc':
          'Всё готово к старту! Первоначальная настройка позади — добро пожаловать в мир AETHONE. Откройте главный экран, установите нужное подключение и начните своё приключение с новым ощущением свободной связи!',
      'loginNext': 'Далее',
      'loginPrev': 'Назад',
      'loginGo': 'Поехали!',
      'langTurkmen': 'Türkmençe',
      'speedTestTitle': 'Тест скорости',
      'speedPhasePing': 'Пинг',
      'speedPhaseDownload': 'Загрузка',
      'speedPhaseUpload': 'Отдача',
      'speedStart': 'Старт',
      'speedStarted': 'Начато...',
      'speedRestart': 'Начать заново',
    },
    'zh': {
      'offline': '离线',
      'statusDisconnected': '未连接!',
      'statusIdle': '未连接',
      'statusConnected': '已连接',
      'statusConnecting': '连接中',
      'statusReconnecting': '重新连接',
      'statusFailed': '错误',
      'statusStarting': '正在启动',
      'statusWaitingPermissions': '等待权限',
      'statusDisconnecting': '正在断开',
      'protocol': '协议',
      'settingsComingNext': '设置 — 将在下一步实现',
      'speedTestComingNext': '速度测试 — 将在下一步实现',
      'protocolSheetComingNext': '协议选择 — 将在下一步实现',
      // ---- v4.16 protocol sheet ----
      'sheetHeadingMode': '连接模式',
      'modeTunnel': '隧道',
      'modeProxy': '代理',
      'sheetHeadingScanSpeed': '扫描速度',
      'protocolPageTitle': '选择协议',
      'protoAutoSheet': '自动',
      'protoAuto': '自动 / 智能',
      'protoMasque': 'MASQUE',
      'protoWireguard': 'WIREGUARD',
      'protoGool': 'GOOL',
      'protoGoolClassic': 'GOOL CLASSIC',
      'protoMim': 'MIM',
      'protoTor': 'TOR',
      'protoPsiphon': 'PSIPHON',
      'protoTorOverWarp': 'TOR OVER WARP',
      'protoWarpOverTor': 'WARP OVER TOR',
      'protoPsiphonOverWarp': 'PSIPHON OVER WARP',
      'protoWarpOverPsiphon': 'WARP OVER PSIPHON',
      'protoLantern': 'LANTERN',
      'settingsTitle': '设置',
      'settingsRouting': '路由规则',
      'settingsRoutingSub': '直连路由',
      'settingsGeneral': '常规设置',
      'settingsGeneralSub': '通知与事件',
      'settingsConnection': '连接设置',
      'settingsConnectionSub': '连接与协议',
      'settingsLanguage': '语言设置',
      'settingsLanguageSub': '选择应用语言',
      'settingsAppearance': '外观设置',
      'settingsAppearanceSub': '个性化应用外观',
      'settingsSecurity': '安全设置',
      'settingsSecuritySub': '安全与隐私',
      'settingsPsiphon': 'Psiphon',
      'settingsTor': 'Tor',
      'settingsLantern': 'Lantern',
      'lanternLocationDesc': '仅显示 Lantern 自身服务器提供的国家；「自动」即内核选择最快的服务器。已连接时更改会立即生效',
      'lanternLocationEmpty': '首次连接 Lantern 后，国家列表将从其服务器获取',
      'secLanternTimings': 'Lantern 连接时限',
      'lanternConnectSecsLabel': '连接时限（秒）',
      'lanternTimingsDesc': '默认 180 秒：获取 Lantern 配置并连上服务器。慢速网络可调大',
      'secLanternTunnel': '隧道',
      'lanternUdpLabel': 'UDP 透传',
      'lanternUdpDesc': '关闭：应用立即回退到 TCP（适用于卡在“连接中”的应用）',
      'lanternStrictLabel': '兼容握手',
      'lanternStrictDesc': '逐步完成到 Lantern 的 SOCKS 握手；对 Telegram 和长连接更稳定',
      'lanternTelegramLabel': 'Telegram 代理',
      'lanternTelegramDesc': '一键在 Telegram 中设置 Lantern 的 SOCKS 代理（127.0.0.1:1822）',
      'lanternTelegramFailed': '此设备未安装 Telegram',
      'telegramProxyDesc': '一键：在 Telegram 中设置此协议的 SOCKS 代理（{addr}），连接期间有效',
      'secTelegram': 'Telegram',
      'secScanSpeed': '扫描速度',
      'scanTurbo': '极速',
      'scanBalanced': '均衡',
      'scanThorough': '全面',
      'scanVerified': '已验证',
      'scanIronclad': '严格',
      'scanTurboDesc': '最快的扫描：样本更少，找到第一个可用 IP 即退出（默认）',
      'scanBalancedDesc': '分多轮采样更多；比极速慢，但在受过滤的网络中更稳定',
      'scanThoroughDesc': '针对困难网络的更广扫描；连接时间更长',
      'scanVerifiedDesc': '更深入、更隐蔽的扫描（内核的 stealth 模式）',
      'scanIroncladDesc': '最深入也最慢：每个 IP 都用真实 HTTP 请求测试',
      'lanternAndroidOnly': '此版本中 Lantern 仅在 Android 上可用',
      'settingsPillSub': '位置等 …',
      'settingsAdvancedStatus': '配置状态',
      'settingsRoutingArea': '路由区域',
      'settingsMainServer': '内核地址',
      'settingsSubpageComingNext': '此部分 — 将在下一步实现',
      'failureCodeLabel': '错误代码',
      // v2.1.0 — the home widget deck.
      'homeWidgetTimer': '会话',
      'homeWidgetPing': '延迟',
      'homeWidgetData': '会话数据',
      'failureDetailsTitle': '错误详情',
      'failureDetailsCopy': '复制错误详情',
      'portNote': '本地 SOCKS 端口：@p',
      // ---- v4.21 core-log diagnostics ----
      'coreLogTitle': '核心日志',
      'coreLogOpen': '查看',
      'coreLogCopy': '复制日志',
      'coreLogClear': '清空',
      'coreLogCopied': '日志已复制',
      'coreLogEmpty': '暂无日志 — 请先连接',
      'coreLogSize': '日志大小：@b 字节',
      // ---- v4.22 settings sub-pages ----
      'subCoreTitle': 'Aether 内核设置',
      'expertMode': '专家模式',
      'expertModeDesc': '为专业用户显示内核高级设置',
      'appliesNextConnect': '更改自下次连接起生效',
      'secFragment': 'TLS 分片',
      'fragOff': '关闭',
      'fragStandard': '标准',
      'fragBalanced': '均衡',
      'fragAggressive': '激进',
      'fragCustom': '自定义',
      'fragOffDesc': 'ClientHello 完整发送（内核默认）',
      'fragStandardDesc': '内核自带默认 — 8-16 字节分片，间隔 2-10 毫秒',
      'fragBalancedDesc': '40-100 字节分片，间隔 10-20 毫秒 — 适合伊朗大多数网络',
      'fragAggressiveDesc': '1-3 字节微片，间隔 1-3 毫秒 — 面向最严苛的过滤',
      'fragCustomDesc': '自行设定分片大小与间隔',
      'fragSizeLabel': '分片大小（字节）',
      'fragDelayLabel': '分片间隔（毫秒）',
      'fragSizeHint': '如 40-100',
      'fragDelayHint': '如 10-20',
      'secTls': 'TLS 与指纹',
      'tlsCustom': '自定义 TLS',
      'tlsCustomDesc': '关闭时应用内核指纹（模拟 Chrome）',
      'tlsDisableGrease': '去掉 GREASE 值',
      'tlsDisableGreaseDesc': '不发送 RFC 8701 的 GREASE 值',
      'tlsGreaseSigalgs': '签名算法中的 GREASE',
      'tlsGreaseSigalgsDesc': '在 signature_algorithms 开头放入 GREASE 值，如同 Chrome',
      'tlsEchGrease': 'ECH 的 GREASE',
      'tlsEchGreaseDesc': '未提供 ECH 密钥时发送 GREASE ECH 扩展',
      'tlsSessionTicket': 'Session Ticket',
      'tlsSessionTicketDesc': '请求 session_ticket，如同 Chrome',
      'tlsOcsp': 'OCSP Stapling',
      'tlsOcspDesc': '请求 status_request，如同 Chrome',
      'tlsSct': 'SCT',
      'tlsSctDesc': '请求 signed_certificate_timestamps，如同 Chrome',
      'tlsExtPerm': '扩展置换',
      'tlsExtPermDesc': '每次握手重排扩展顺序 — 关闭时保持 BoringSSL 固定顺序',
      'tlsVerify': '校验 MASQUE 网关证书',
      'tlsVerifyDesc': '用内核自带的固定证书校验（默认：关闭）',
      'tlsGroups': 'TLS groups',
      'tlsGroupsHint': '如 P-256:X25519:P-384',
      'tlsKeyShares': 'Key shares',
      'tlsKeySharesHint': '如 X25519:P-256',
      'tlsCiphers12': 'TLS 1.2 密码套件',
      'tlsCiphers12Hint': '冒号分隔 — 如 ECDHE-RSA-AES128-GCM-SHA256',
      'tlsCiphers13': 'TLS 1.3 密码套件',
      'tlsCiphers13Hint': '如 TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256',
      'masqueSni': '手动 MASQUE SNI',
      'masqueSniHint': '如 www.cloudflare.com',
      'secTransport': '传输',
      'h2Transport': 'HTTP/2（TCP）传输',
      'h2TransportDesc': 'MASQUE 走 HTTP/2（TCP）— 应用新默认；适合封锁 UDP 的网络',
      'quicV2': 'QUIC v2 协商',
      'quicV2Desc': '在封锁 QUIC v1 的网络上打开 HTTP/3 通路',
      'secEngine': '引擎',
      'noizeLabel': '混淆配置（Noize）',
      'noizeDesc': '应用新默认：均衡（balanced）；严格网络可试 GFW 或激进',
      'noizeDefault': '内核默认',
      'noizeOff': '关闭',
      'noizeLight': '轻度',
      'noizeFirewall': 'Firewall',
      'noizeBalanced': '均衡',
      'noizeGfw': 'GFW',
      'noizeAggressive': '激进',
      'perfLabel': '资源档位',
      'perfAuto': '自动',
      'perfLow': '低',
      'perfMedium': '中',
      'perfHigh': '高',
      'logLevelLabel': '内核日志级别',
      'logInfo': '信息',
      'logDebug': '调试',
      'logTrace': '跟踪',
      'keepaliveLabel': 'WireGuard keepalive 间隔（秒）',
      'secRoutes': '直连与封锁路由',
      'routeBlockLabel': '始终封锁的域名',
      'routeBlockHint': '逗号或换行分隔 — 如 ads.example.com',
      'routeDirectLabel': '始终直连的域名（绕过隧道）',
      'routeDirectHint': '如 bank.example.com',
      'routesDesc': 'full: 仅精确名称，keyword: 包含该词的任意名称；无前缀则覆盖该域名及其全部子域名',
      'routingNone': '无',
      'routingAreaDesc': '所选国家自身的流量（其域名与 IP 段）绕过隧道直连；其余流量仍走隧道。',
      'tunnelApps': '隧道应用',
      'tunnelAppsModeAll': '所有应用',
      'tunnelAppsModeAllow': '仅选中的应用',
      'tunnelAppsModeDisallow': '排除选中的应用',
      'tunnelAppsDesc': '选择哪些应用通过隧道；仅在 Android 的隧道模式下生效，自下次连接起应用。',
      'tunnelAppsLoading': '正在获取应用列表…',
      'tunnelAppsLoadFailed': '应用列表不可用',
      'hybridRouting': "混合路由",
      'hybridRoutingOpen': "管理路由规则",
      'hybridRoutingDesc': "为此混合协议选择每个应用、域名或 IP 使用哪条隧道。",
      'hybridRoutes': "此协议的路由",
      'hybridDefaultRoute': "默认",
      'hybridDefaultNote': "没有规则的流量照旧走默认路由 {route}。",
      'hybridApps': "应用路由",
      'hybridDomains': "域名路由",
      'hybridIps': "IP 路由",
      'hybridAddApps': "添加应用",
      'hybridAddDomain': "添加域名",
      'hybridAddIp': "添加 IP",
      'hybridDomainHint': "example.com 或 *.example.com",
      'hybridIpHint': "1.1.1.1、192.168.1.0/24 或 2606:4700::/32",
      'hybridSearchApps': "搜索应用",
      'hybridErrEmpty': "未输入内容",
      'hybridErrInvalid': "输入无效",
      'hybridErrDuplicate': "已存在",
      'hybridConflict': "与另一隧道上的 {rules} 重叠；更具体的规则优先。",
      'hybridEmpty': "暂无规则",
      'hybridInvalidTunnel': "此协议中没有该路由；在修正规则前其流量将被阻止",
      'hybridEngineRejected': "引擎拒绝了此规则",
      'hybridRuleOff': "已关闭",
      'hybridSave': "保存",
      'hybridAppliedNext': "将在下次以此协议连接隧道时生效",
      'hybridApplyFailed': "引擎无法应用规则（{error}）",
      'hybridNotRouted': "本次连接未启用混合路由；请重新连接一次",
      'hybridStatusLive': "引擎中生效：{n} 条规则",
      'hybridAppUnsupported': "应用路由需要 Android 10 或更高版本",
      'hybridWildcardNote': "example.com 只匹配该名称本身；*.example.com 只匹配子域名（如 www.example.com），不含 example.com 本身。",
      'hybridPriority': "优先级：应用 → 精确域名 → 通配域名（最具体）→ IP/CIDR（最小范围）→ 默认路由。",
      'hybridLimits': "限制：域名通过隧道自身的 DNS 识别；使用自带加密 DNS（DoH/DoT）或直连 IP 的应用只能按应用或 IP 规则路由。IP 规则仅作用于直连 IP 的连接。所选隧道不可用时，该规则的流量会被阻止，绝不直连。这些协议不传输 UDP（DNS 除外）。仅限 Android 隧道模式。",
      'hybridPickTunnel': "路由",
      'hybridFlows': "{n} 个连接",
      'secProtocolMode': '协议模式',
      'protoModeSmart': '智能',
      'smartNote': '在 SMART 模式下，应用自行选择协议而非内核默认值：候选协议（masque、wireguard、gool、mim、gool-classic）按既往实测成功率与延迟依次尝试，直到其中一个连通。尝试链路会在主屏幕显示，实测延迟会被记住，您的手动选择永不被改写。仅在选中 AUTO 卡时生效。',
      'smartAttemptLabel': 'SMART：{name}（第 {i}/{n} 次）',
      'smartMeasuringLabel': '正在测量 {name} 质量…',
      'coreRowDesc': '分片、TLS、传输与引擎',
      'secAbout': '关于应用',
      'appVersionLabel': '应用版本',
      'betaStage': '测试版',
      'telegramRow': 'Telegram 频道',
      'githubRow': 'GitHub 仓库',
      'instagramRow': 'Instagram',
      'secNotifications': '通知与事件',
      'notificationsComing': '连接时，Android 通知栏内即带有「断开连接」按钮；桌面端可通过系统托盘菜单切换连接。',
      'notificationsRow': '连接通知',
      'notificationsOn': '开启',
      'secCloseBehavior': '关闭按钮行为',
      'closeBehaviorAsk': '每次询问',
      'closeBehaviorTray': '最小化到托盘',
      'closeBehaviorClose': '完全关闭',
      'closeBehaviorDesc': '决定点击关闭按钮时的行为：每次询问、直接最小化到系统托盘，或完全关闭程序。',
      'closeDialogTitle': '关闭 AETHONE',
      'closeDialogBody': '要完全关闭程序，还是保留在系统托盘中并保持连接？',
      'closeDialogToTray': '最小化到系统托盘',
      'closeDialogFullClose': '完全关闭程序',
      'closeDialogRemember': '记住我的选择，下次直接执行',
      'closeDialogCancel': '取消',
      'secAutoStart': '自动启动',
      'autoStartTitle': '随系统登录启动',
      'autoStartDesc': '登录系统时自动运行 AETHONE。',
      'autoStartFailed': '无法注册自动启动',
      'secReset': '重置',
      'resetTitle': '重置设置',
      'resetDesc': '将所有设置恢复为出厂默认值。',
      'resetConfirmBody': '所有设置将恢复默认值，此操作无法撤销。',
      'resetConfirmYes': '立即重置',
      'secThemeMode': '显示模式',
      'themePickNight': '夜间',
      'themePickLight': '浅色',
      'themePickAuto': '自动',
      'themeAutoNote': '自动：早 6 点至晚 6 点使用浅色模式，晚 6 点至次日早 6 点使用夜间模式。',
      'secAppLanguage': '应用语言',
      'langSystem': '跟随系统',
      'langDesc': '界面语言 — 默认波斯语',
      'secHomeLook': '主屏样式',
      'lookOne': '样式一',
      'lookTwo': '样式二',
      'secMotion': '动画',
      'motionStandard': '标准',
      'motionSmooth': '柔和',
      'motionDynamic': '动感',
      'motionMinimal': '极简',
      'animationsOffTitle': '关闭所有动画',
      'animationsOffDesc': '立即停止应用中的所有动画',
      'secPatterns': '背景花纹',
      'showPatterns': '显示背景花纹',
      'showPatternsDesc': '所有页面两侧的绿/红花纹',
      'secKillSwitch': 'Kill Switch',
      'killSwitchDesc': '断线时防止流量泄漏 — 与操作系统的完整集成在下一步实现',
      'secDiagnostics': '诊断',
      'secExitLocation': '出口位置',
      'psiphonLocationDesc': '作用于 Psiphon 出口模式；「自动」即内核自行选择',
      'secFronting': 'CDN 前置',
      'frontingModeLabel': '前置方式',
      'frontingAuto': '自动',
      'frontingAutoDesc': '内核自行选择（默认）',
      'frontingCdn': '仅 CDN',
      'frontingCdnDesc': '仅通过 meek CDN 前置 — 适合封锁其余路径的网络',
      'frontingDirect': '直连',
      'frontingDirectDesc': '不使用前置',
      'cdnSniLabel': 'CDN 服务器名称（SNI）',
      'cdnSniHint': '逗号分隔 — 如 cdn.example.com',
      'cdnIpsLabel': 'CDN 地址',
      'cdnIpsHint': '如 104.16.0.1,104.16.1.1',
      'torLocationDesc': '你的选择会被记住并显示在主屏；Tor 内核从可用节点中选择出口',
      'secTorBridges': 'Tor 网桥',
      'bridgesLabel': '网桥策略',
      'bridgesAuto': '自动',
      'bridgesAutoDesc': '内核从 bridgedb 获取网桥并尝试合适的',
      'bridgesOff': '无网桥',
      'bridgesOffDesc': '关闭网桥（仅适合不封锁 Tor 的网络）',
      'torLogLevelLabel': 'Tor 日志级别',
      // v4.31 — the round-7 settings expansion.
      'bridgesCustom': '手动',
      'bridgesCustomDesc': '输入你自己的网桥行；内核将用它们代替从 bridgedb 获取的网桥',
      'torBridgeLinesLabel': '网桥行',
      'torBridgeLinesHint': '每行一个网桥 — 例如 obfs4 1.2.3.4:443 CERT=… iat-mode=0',
      'secTorTimings': 'Tor 连接时限',
      'torDirectSecsLabel': '直连尝试时限（秒）',
      'torBridgeSecsLabel': '单个网桥时限（秒）',
      'torTimingsDesc': '内核默认：直连 75 秒、每个网桥 360 秒。慢速网络可调大',
      'cdnSetsLabel': '前端托管集合',
      'cdnSetsHint': '逗号分隔 — 例如 psiphon-akamai,vercel（留空 = 全部）',
      'cdnSetsDesc': 'CDN 前端托管使用 psiphon 内置的哪些边缘列表',
      'secPsiphonTimings': '就绪时限',
      'psiphonReadyLabel': 'Psiphon 就绪时限（秒）',
      'psiphonReadyDesc': '内核默认 180 秒；慢速网络可调大 — 应用自身的等待预算也会随之放宽',
      'serverEntriesLabel': '服务器条目',
      'serverEntriesHint': '来自 psiphon 官方客户端的服务器条目 JSON',
      'serverEntriesDesc': '留空表示使用 psiphon 内置发现',
      'secFamilyLeg': '组合模式的底层',
      'aetherLegLabel': '组合模式的底层',
      'torLegDesc': '在 Tor 组合模式（链式与反向）中，底层 Aether 隧道使用此协议。反向模式下需要 UDP 的分支会自动映射为 MASQUE（内核自身的限制）',
      'psiphonLegDesc': '在 Psiphon 组合模式（链式与反向）中，底层 Aether 隧道使用此协议。反向模式下需要 UDP 的分支会自动映射为 MASQUE（内核自身的限制）',
      'secIpVersion': 'IP 版本',
      'ipV4': 'IPv4',
      'ipV6': 'IPv6',
      'ipDual': '双栈',
      'ipVersionDesc': '部分运营商的 IPv6 有问题；IPv4 是内核自身的默认值',
      'secUpstream': '上游代理',
      'upstreamLabel': '代理地址（可选）',
      'upstreamHint': 'socks5://127.0.0.1:1080',
      'upstreamDesc': '仅适用于普通 Aether 模式；内核经由该代理拨号。留空 = 关闭',
      'echLabel': 'ECH（加密 SNI）',
      'echOff': '关闭',
      'echAuto': '自动',
      'echManual': '手动',
      'echOffDesc': 'SNI 按常规方式发送',
      'echAutoDesc': '通过 DNS 查询 ECH 密钥，服务器名以加密方式发送',
      'echManualDesc': '你自行提供 base64 的 ECH 密钥',
      'echKeyLabel': 'ECH 密钥（base64）',
      'echKeyHint': '例如 AEDW…',
      'echDnsLabel': '查找密钥的 DNS',
      'echDnsHint': '例如 https://1.1.1.1/dns-query',
      'echDomainLabel': '密钥域名（可选）',
      'echDomainHint': '默认：cloudflare-ech.com',
      // v6 login.
      'loginWelcomeTitle': '准备好开始冒险了吗？',
      'loginLanguageTitle': '应用语言',
      'loginRoutingTitle': '路由区域',
      'loginLookTitle': '应用外观',
      'loginDoneTitle': '初始设置完成！',
      'loginWelcomeDesc':
          '只需几个简单步骤，即可熟悉 AETHONE 的各项功能：选择连接模式与协议，并按需个性化设置。你通往更灵活的连接、探索不同通路的冒险，就从这里开始！',
      'loginDoneDesc':
          '一切已准备就绪！初始设置已经完成，现在即可进入 AETHONE 的世界。前往主界面，建立你想要的连接，以更自由的通信体验开启你的冒险吧！',
      'loginNext': '下一步',
      'loginPrev': '上一步',
      'loginGo': '出发！',
      'langTurkmen': 'Türkmençe',
      'speedTestTitle': '速度测试',
      'speedPhasePing': 'Ping',
      'speedPhaseDownload': '下载',
      'speedPhaseUpload': '上传',
      'speedStart': '开始',
      'speedStarted': '已开始...',
      'speedRestart': '重新开始',
    },

    // v4.41 (owner round 17, item 5): the COMPLETE Turkmen table —
    // «زبان ترکمنی که همین الان هم میبینم هیچ ترجمه ای براش در نظر گرفته
    // نشده». Same key parity as fa/en/ru/zh; the Material-locale mapping
    // stays 'en' (flutter_localizations ships no tk) while AppStrings
    // resolves tk natively now.
    'tk': {
      'offline': 'Oflaýn',
      'statusDisconnected': 'Offline!',
      'statusIdle': 'Işlemeýär',
      'statusConnected': 'Berkidildi',
      'statusConnecting': 'Birikdirilýär',
      'statusReconnecting': 'Täzeden birikdirilýär',
      'statusFailed': 'Ýalňyşlyk',
      'statusStarting': 'Başlanýar',
      'statusWaitingPermissions': 'Rugsat garaşýar',
      'statusDisconnecting': 'Aýrylýar',
      'protocol': 'Protokol',
      'settingsComingNext': 'Sazlamalar — indiki ädimde',
      'speedTestComingNext': 'Tizlik testi — indiki ädimde',
      'protocolSheetComingNext': 'Protokol saýlawy — indiki ädimde',
      // ---- v4.16 protocol sheet ----
      'sheetHeadingMode': 'Birikme režimi',
      'modeTunnel': 'Tunel',
      'modeProxy': 'Proksi',
      'sheetHeadingScanSpeed': 'Skan tizligi',
      'protocolPageTitle': 'Protokol saýlaň',
      'protoAutoSheet': 'Awtomatiki',
      'protoAuto': 'AUTO / SMART',
      'protoMasque': 'MASQUE',
      'protoWireguard': 'WIREGUARD',
      'protoGool': 'GOOL',
      'protoGoolClassic': 'GOOL CLASSIC',
      'protoMim': 'MIM',
      'protoTor': 'TOR',
      'protoPsiphon': 'PSIPHON',
      'protoTorOverWarp': 'TOR OVER WARP',
      'protoWarpOverTor': 'WARP OVER TOR',
      'protoPsiphonOverWarp': 'PSIPHON OVER WARP',
      'protoWarpOverPsiphon': 'WARP OVER PSIPHON',
      'protoLantern': 'LANTERN',
      'settingsTitle': 'Sazlamalar',
      'settingsRouting': 'Marşrutizasiýa',
      'settingsRoutingSub': 'Göni marşrutlar',
      'settingsGeneral': 'Umumy',
      'settingsGeneralSub': 'Bildirişler we wakalar',
      'settingsConnection': 'Birikme',
      'settingsConnectionSub': 'Birikme we protokol',
      'settingsLanguage': 'Dil',
      'settingsLanguageSub': 'Programma dilini saýlaň',
      'settingsAppearance': 'Daşky görnüş',
      'settingsAppearanceSub': 'Programmany özleşdiriň',
      'settingsSecurity': 'Howpsuzlyk',
      'settingsSecuritySub': 'Howpsuzlyk we gizlinlik',
      'settingsPsiphon': 'Psiphon',
      'settingsTor': 'Tor',
      'settingsLantern': 'Lantern',
      'lanternLocationDesc': 'Diňe Lantern-iň öz serwerleriniň hödürleýän ýurtlary; Awtomatiki — çekirdegiň iň çalt serweri. Birikende üýtgeşme derrew ulanylýar',
      'lanternLocationEmpty': 'Ýurtlaryň sanawy ilkinji Lantern birikmesinden soň öz serwerlerinden gelýär',
      'secLanternTimings': 'Lantern birikme möhleti',
      'lanternConnectSecsLabel': 'Birikme möhleti (sekunt)',
      'lanternTimingsDesc': 'Default 180 s: Lantern sazlamalaryny almak we serwere ýetmek. Ýuwaş ulaglarda artdyryň',
      'secLanternTunnel': 'Tunel',
      'lanternUdpLabel': 'UDP geçirmek',
      'lanternUdpDesc': 'Öçük: programmalar derrew TCP-a geçýär («birikýär» ýagdaýynda galýanlar üçin)',
      'lanternStrictLabel': 'Laýyk el gysyşmak',
      'lanternStrictDesc': 'Lantern-e SOCKS birikmesi ädimme-ädim edilýär; Telegram we uzak birikmeler üçin durnuklyrak',
      'lanternTelegramLabel': 'Telegram proksi',
      'lanternTelegramDesc': 'Bir basyş: Lantern-iň SOCKS proksisi (127.0.0.1:1822) Telegram-da sazlanýar',
      'lanternTelegramFailed': 'Bu enjamda Telegram ýok',
      'telegramProxyDesc': 'Bir basyş: bu protokolyň SOCKS proksisi ({addr}) Telegramda sazlanýar; birikme wagtynda işleýär',
      'secTelegram': 'Telegram',
      'secScanSpeed': 'Gözleg tizligi',
      'scanTurbo': 'Turbo',
      'scanBalanced': 'Deňagramly',
      'scanThorough': 'Doly',
      'scanVerified': 'Barlanan',
      'scanIronclad': 'Berk',
      'scanTurboDesc': 'Iň çalt gözleg: az nusga, ilkinji sagdyn IP-de çykýar (adaty)',
      'scanBalancedDesc': 'Birnäçe tolkunda köp nusga; turbodan haýal, emma süzgüçli torlarda ygtybarly',
      'scanThoroughDesc': 'Kyn torlar üçin giň gözleg; birikmek uzaga çekýär',
      'scanVerifiedDesc': 'Has çuň we ýaşyryn gözleg (ýadronyň stealth tertibi)',
      'scanIroncladDesc': 'Iň çuň we haýal: her IP hakyky HTTP haýyşy bilen barlanýar',
      'lanternAndroidOnly': 'Bu wersiýada Lantern diňe Android-da elýeterli',
      'settingsPillSub': 'Ýerleşýän ýer we başgalar …',
      'settingsAdvancedStatus': 'Konfigurasiýa ýagdaýy',
      'settingsRoutingArea': 'Marşrutizasiýa sebiti',
      'settingsMainServer': 'Çekirdek salgylary',
      'settingsSubpageComingNext': 'Bu bölek — indiki ädimde',
      // ---- v4.20 failure visibility ----
      'failureCodeLabel': 'Ýalňyşlyk kody',
      // v2.1.0 — the home widget deck.
      'homeWidgetTimer': 'Sessiýa',
      'homeWidgetPing': 'Gijikme',
      'homeWidgetData': 'Sessiýa maglumaty',
      'failureDetailsTitle': 'Ýalňyşlygyň jikme-jigi',
      'failureDetailsCopy': 'Ýalňyşlyk jikme-jiklerini göçür',
      'portNote': 'Ýerli SOCKS porty: @p',
      // ---- v4.21 core-log diagnostics ----
      'coreLogTitle': 'Çekirdek loglary',
      'coreLogOpen': 'Gör',
      'coreLogCopy': 'Logy göçür',
      'coreLogClear': 'Arassala',
      'coreLogCopied': 'Log göçürildi',
      'coreLogEmpty': 'Heniz log ýok — ilki birikdiriň',
      'coreLogSize': 'Logyň ululygy: @b baýt',
      // ---- v4.22 settings sub-pages ----
      'subCoreTitle': 'Aether çekirdeginiň sazlamalary',
      'expertMode': 'Ekspert režimi',
      'expertModeDesc': 'Ekspert ulanyjylar üçin ýokary derejeli çekirdek sazlamalaryny görkezýär',
      'appliesNextConnect': 'Üýtgeşmeler indiki birikmeden güýje girer',
      'secFragment': 'TLS bölünmegi',
      'fragOff': 'Öçürilen',
      'fragStandard': 'Standart',
      'fragBalanced': 'Denzag',
      'fragAggressive': 'Agresiw',
      'fragCustom': 'Özbaşdak',
      'fragOffDesc': 'ClientHello bütinleýin ugradylýar (çekirdegiň öz defaulty)',
      'fragStandardDesc': "Çekirdegiň öz defaulty — 8-16 baýt bölekler, 2-10 ms gepikme",
      'fragBalancedDesc': '40-100 baýt bölekler, 10-20 ms gepikme — köp Eýran ulaglaryna laýyk',
      'fragAggressiveDesc': '1-3 baýt kiçi bölekler, 1-3 ms gepikme — iň gysga süzgüçler üçin',
      'fragCustomDesc': 'Ululygy we gepikmäni özüňiz kesgitläň',
      'fragSizeLabel': 'Bölegiň ululygy (baýt)',
      'fragDelayLabel': 'Bölekleriň arasyndaky gepikme (ms)',
      'fragSizeHint': 'm. 40-100',
      'fragDelayHint': 'm. 10-20',
      'secTls': 'TLS we barmak yzy',
      'tlsCustom': 'TLS-i özleşdirmek',
      'tlsCustomDesc': 'Öçürilen: çekirdegiň barmak yzy (Chrome-meňzeş) ulanylýar',
      'tlsDisableGrease': 'GREASE bahalaryny aýyr',
      'tlsDisableGreaseDesc': 'RFC 8701 GREASE bahalaryny goýber (Chrome eden ýaly)',
      'tlsGreaseSigalgs': 'Imza algoritmlerinde GREASE',
      'tlsGreaseSigalgsDesc': 'Sigalgs-iň iň öňünde GREASE bahasyny goý (Chrome eden ýaly)',
      'tlsEchGrease': 'ECH üçin GREASE',
      'tlsEchGreaseDesc': 'ECH açary hödürlenmedik wagty GREASE ECH uzaltmasyny iber',
      'tlsSessionTicket': 'Sessiýa bileti',
      'tlsSessionTicketDesc': 'Chrome eden ýaly session_ticket isleg et',
      'tlsOcsp': 'OCSP Stapling',
      'tlsOcspDesc': 'Chrome eden ýaly status_request isleg et',
      'tlsSct': 'SCT',
      'tlsSctDesc': 'Chrome eden ýaly signed_certificate_timestamps isleg et',
      'tlsExtPerm': 'Uzaltmalaryň ýerini çalşmak',
      'tlsExtPermDesc': 'Her gol çekilende uzaltmalaryň tertibini çalşyr — öçürilende BoringSSL-iň berlen tertibi galýar',
      'tlsVerify': 'MASQUE derwezesiniň şahadatnamasyny barla',
      'tlsVerifyDesc': 'Şahadatnamany çekirdegiň öz pinlerine gabat getir (default: öçürilen)',
      'tlsGroups': 'TLS toparlary',
      'tlsGroupsHint': 'm. P-256:X25519:P-384',
      'tlsKeyShares': 'Açar paýlary',
      'tlsKeySharesHint': 'm. X25519:P-256',
      'tlsCiphers12': 'TLS 1.2 şifr toplumlary',
      'tlsCiphers12Hint': 'iki nokat bilen aýrylan — m. ECDHE-RSA-AES128-GCM-SHA256',
      'tlsCiphers13': 'TLS 1.3 şifr toplumlary',
      'tlsCiphers13Hint': 'm. TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256',
      'masqueSni': 'Ellik MASQUE SNI',
      'masqueSniHint': 'm. www.cloudflare.com',
      'secTransport': 'Ulag',
      'h2Transport': 'HTTP/2 (TCP) ulagy',
      'h2TransportDesc': 'MASQUE HTTP/2 (TCP) üstünden — programmanyň täze defaulty; UDP-i bloklaýan ulaglar üçin',
      'quicV2': 'QUIC v2 ylalaşygy',
      'quicV2Desc': 'QUIC v1 bloklanan ýerde HTTP/3 üçin ýol açýar',
      'secEngine': 'Motor',
      'noizeLabel': 'Gizleniş profili (Noize)',
      'noizeDesc': 'Programmanyň täze defaulty: Denzag; gysga ulaglarda GFW ýa-da Agresiw-i synap görüň',
      'noizeDefault': 'Çekirdegiň defaulty',
      'noizeOff': 'Öçürilen',
      'noizeLight': 'Ýeňil',
      'noizeFirewall': 'Faýrwol',
      'noizeBalanced': 'Denzag',
      'noizeGfw': 'GFW',
      'noizeAggressive': 'Agresiw',
      'perfLabel': 'Serişkeleriň profili',
      'perfAuto': 'Awtomatiki',
      'perfLow': 'Pes',
      'perfMedium': 'Orta',
      'perfHigh': 'Ýokary',
      'logLevelLabel': 'Çekirdek logyň derejesi',
      'logInfo': 'Maglumat',
      'logDebug': 'Dibag',
      'logTrace': 'Tres',
      'keepaliveLabel': 'WireGuard keepalive aralygy (s)',
      'secRoutes': 'Göni we bloklanan marşrutlar',
      'routeBlockLabel': 'Hemişe bloklanýan domenler',
      'routeBlockHint': 'vergül ýa-da täze setir bilen aýrylan — m. ads.example.com',
      'routeDirectLabel': 'Hemişe göni (tuneliň daşynda) domenler',
      'routeDirectHint': 'm. bank.example.com',
      'routesDesc': 'full: diňe şol takyk at; keyword: içinde ol söz bolan islendik at; prefikssiz ýazgy domeni we onuň ähli subdomenlerini öz içine alýar',
      'routingNone': 'Hiç biri',
      'routingAreaDesc':
          'Saýlanan ýurduň öz trafigi (onuň domenleri we IP aralyklary) tuneliň daşyndan göni gidýär; galan trafik tunelden geçýär.',
      'tunnelApps': 'Tunel programmalary',
      'tunnelAppsModeAll': 'Ähli programmalary',
      'tunnelAppsModeAllow': 'Diňe saýlananlary',
      'tunnelAppsModeDisallow': 'Saýlananlardan başgasyny',
      'tunnelAppsDesc':
          'Näme programmalaryň tunelden geçýändigini saýlaň; diňe Android-iň tunel režiminde, indiki birikmeden güýje girer.',
      'tunnelAppsLoading': 'Programma sanawy alnýar…',
      'tunnelAppsLoadFailed': 'Programma sanawy elýeterli däl',
      'hybridRouting': "Gibrid ugrukdyryş",
      'hybridRoutingOpen': "Ugur düzgünleri",
      'hybridRoutingDesc': "Bu gibrid protokolyň haýsy tuneli her programma, domen ýa-da IP üçin ulanylýandygyny saýlaň.",
      'hybridRoutes': "Protokolyň ugurlary",
      'hybridDefaultRoute': "esasy",
      'hybridDefaultNote': "Düzgüni bolmadyk traffik öňküsi ýaly esasy {route} ugry bilen geçýär.",
      'hybridApps': "Programma ugurlary",
      'hybridDomains': "Domen ugurlary",
      'hybridIps': "IP ugurlary",
      'hybridAddApps': "Programma goş",
      'hybridAddDomain': "Domen goş",
      'hybridAddIp': "IP goş",
      'hybridDomainHint': "example.com ýa-da *.example.com",
      'hybridIpHint': "1.1.1.1, 192.168.1.0/24 ýa-da 2606:4700::/32",
      'hybridSearchApps': "Programmalary gözle",
      'hybridErrEmpty': "Hiç zat girizilmedi",
      'hybridErrInvalid': "Nädogry giriş",
      'hybridErrDuplicate': "Eýýäm goşuldy",
      'hybridConflict': "Başga tuneldäki {rules} bilen kesişýär; has takyk düzgün ulanylýar.",
      'hybridEmpty': "Entek düzgün ýok",
      'hybridInvalidTunnel': "Bu ugur protokolda ýok; düzgün düzedilýänçä traffik petiklenýär",
      'hybridEngineRejected': "Hereketlendiriji düzgüni kabul etmedi",
      'hybridRuleOff': "Öçük",
      'hybridSave': "Ýatda sakla",
      'hybridAppliedNext': "Şu protokol bilen indiki tunel birikmesinden ulanylýar",
      'hybridApplyFailed': "Hereketlendiriji düzgünleri ulanyp bilmedi ({error})",
      'hybridNotRouted': "Bu birikme gibrid ugrukdyryşsyz başlady; bir gezek täzeden birikiň",
      'hybridStatusLive': "Hereketlendirijide işjeň: {n} düzgün",
      'hybridAppUnsupported': "Programma ugrukdyryşy Android 10 ýa-da täzesini talap edýär",
      'hybridWildcardNote': "example.com diňe şol ady; *.example.com diňe subdomenleri (www.example.com) tutýar, example.com-yň özüni däl.",
      'hybridPriority': "Ileri tutma: programma → takyk domen → wildcard → IP/CIDR → esasy ugur.",
      'hybridLimits': "Çäkler: domenler tuneliň öz DNS-i arkaly tanalýar; öz şifrlenen DNS-i (DoH/DoT) bar ýa-da göni IP-ä birikýän programmalar diňe programma ýa-da IP düzgünleri bilen ugrukdyrylýar. Saýlanan tunel elýeterli bolmasa, düzgüniň traffigi petiklenýär we hiç haçan göni gitmeýär. Bu protokollarda UDP (DNS-den başga) geçirilmeýär. Diňe Android-da tunel tertibi.",
      'hybridPickTunnel': "Ugur",
      'hybridFlows': "{n} birikme",
      'secProtocolMode': 'Protokol režimi',
      'protoModeSmart': 'SMART',
      'smartNote':
          'SMART režiminde protokoly çekirdegiň defaultyň ýerine programmanyň özi saýlaýar: namzetler (masque, wireguard, gool, mim, gool-classic) ölçelen üstünlige we gepikmä görä, biri birikýänça synanylýar. Synanyşyklaryň yzy esasy ekranda görkezilýär, ölçelen gepikme ýatda saklanýar we eliňiz bilen eden saýlawyňyz hiç haçan täzeden ýazylmaýar. Diňe «Awtomatiki» plitkasynda işjeň.',
      'smartAttemptLabel': 'SMART: {name} ({i}/{n})',
      'smartMeasuringLabel': '{name} häsiýeti ölçenilýär…',
      'coreRowDesc': 'Bölünmek, TLS, ulag we motor',
      'secAbout': 'Programma barada',
      'appVersionLabel': 'Wersiýasy',
      'betaStage': 'Beta',
      'telegramRow': 'Telegram kanaly',
      'githubRow': 'GitHub repozitoriýasy',
      'instagramRow': 'Instagram',
      'secNotifications': 'Bildirişler we wakalar',
      'notificationsComing': 'Birikdirilen wagty Android-iň bildirişinda «Birikmegi kes» düwmesi bar; iş stolynda sistema treý menyusy birikmäni dolandyrýar.',
      'notificationsRow': 'Birikme bildirişi',
      'notificationsOn': 'Açyk',
      'secCloseBehavior': 'Ýapma düwmesiniň hereketi',
      'closeBehaviorAsk': 'Her gezek sora',
      'closeBehaviorTray': 'Sistema treýine git',
      'closeBehaviorClose': 'Doly ýap',
      'closeBehaviorDesc': 'Ýapma düwmesiniň näme edýänini saýlaýar: her gezek sora, göni sistema treýine gizle ýa-da programmany doly ýap.',
      'closeDialogTitle': 'AETHONE ýapylýar',
      'closeDialogBody': 'Programma doly ýapylsyn ýa-da birikme işläp, sistema treýinde galsyn?',
      'closeDialogToTray': 'Sistema treýine git',
      'closeDialogFullClose': 'Doly ýap',
      'closeDialogRemember': 'Saýlawymy indiki gezek üçin hem ýatda sakla',
      'closeDialogCancel': 'Ýatyr',
      'secAutoStart': 'Awtomatiki başlama',
      'autoStartTitle': 'Ulgama girende açylsyn',
      'autoStartDesc': 'Sistemä gireniňizde AETHONE awtomatiki açylýar.',
      'autoStartFailed': 'Awtomatiki başlama ýazdyrylmady',
      'secReset': 'Yza gaýtarmak',
      'resetTitle': 'Sazlamalary yza gaýtarmak',
      'resetDesc': 'Ähli sazlamalary öndürilik defaultuna gaýtar.',
      'resetConfirmBody': 'Ähli sazlamalar defaulta gaýdýar. Muny yza gaýtaryp bolmaýar.',
      'resetConfirmYes': 'Häzir yza gaýtaryl',
      'secThemeMode': 'Görnüş režimi',
      'themePickNight': 'Gije',
      'themePickLight': 'Ýagty',
      'themePickAuto': 'Awtomatiki',
      'themeAutoNote': 'Awtomatiki: ir 06:00-dan agşam 18:00-a çenli ýagty, agşam 18:00-dan ir 06:00-a çenli gije režimi.',
      'secAppLanguage': 'Programma dili',
      'langSystem': 'Sistemany yzla',
      'langDesc': 'Interfeýs dili — defaultda pars dili',
      'secHomeLook': 'Esasy ekranyň görnüşi',
      'lookOne': 'Görnüş 1',
      'lookTwo': 'Görnüş 2',
      'secMotion': 'Animasiýa',
      'motionStandard': 'Standart',
      'motionSmooth': 'Ýumşak',
      'motionDynamic': 'Dinamiki',
      'motionMinimal': 'Minimal',
      'animationsOffTitle': 'Ähli animasiýalary öçür',
      'animationsOffDesc': 'Programmadaky ähli animasiýalary derrew bes edýär',
      'secPatterns': 'Fon naýşlary',
      'showPatterns': 'Fon naýşlaryny görkez',
      'showPatternsDesc': 'Her sahypadaky ýaşyl/gyzyl naýşlar',
      'secKillSwitch': 'Kill Switch',
      'killSwitchDesc': 'Birikme ýykylanda trafigiň sizmegini bes edýär — ulgam bilen doly birleşdiriş indiki ädimde',
      'secDiagnostics': 'Diagnostika',
      'secExitLocation': 'Çykyş ýeri',
      'psiphonLocationDesc': 'Psiphon-çykyş režimlerine degişlidir; Awtomatiki — çekirdegiň öz saýlawy',
      'secFronting': 'CDN fronting',
      'frontingModeLabel': 'Fronting režimi',
      'frontingAuto': 'Awtomatiki',
      'frontingAutoDesc': 'Çekirdek saýlaýar (default)',
      'frontingCdn': 'Diňe CDN',
      'frontingCdnDesc': 'Diňe meek CDN-lar arkaly — galanlaryny bloklaýan ulaglar üçin',
      'frontingDirect': 'Göni',
      'frontingDirectDesc': 'Fronting ýok',
      'cdnSniLabel': 'CDN gyra serwerleriniň atlary (SNI)',
      'cdnSniHint': 'vergül bilen aýrylan — m. cdn.example.com',
      'cdnIpsLabel': 'CDN gyra salgylary',
      'cdnIpsHint': 'm. 104.16.0.1,104.16.1.1',
      'torLocationDesc': 'Saýlawyňyz ýatda saklanýar we esasy ekranda görkezilýär; Tor çekirdegi elýeterli releýlerden çykyşy özi saýlaýar',
      'secTorBridges': 'Tor köprüleri',
      'bridgesLabel': 'Köprü syýasaty',
      'bridgesAuto': 'Awtomatiki',
      'bridgesAutoDesc': 'Çekirdek köprüleri bridgedb-den alýar we laýyklaryny synaýar',
      'bridgesOff': 'Köprüsiz',
      'bridgesOffDesc': 'Köprüler öçürilen (diňe Tor-y süzmeýän ulaglar üçin)',
      'torLogLevelLabel': 'Tor logyň derejesi',
      // v4.31 — the round-7 settings expansion.
      'bridgesCustom': 'Ellik',
      'bridgesCustomDesc': 'Öz köprü setirleriňizi giriziň; çekirdek bridgedb-den alnanlaryň ýerine şolary ulanýar',
      'torBridgeLinesLabel': 'Köprü setirleri',
      'torBridgeLinesHint': 'her setire bir köprü — m. obfs4 1.2.3.4:443 CERT=… iat-mode=0',
      'secTorTimings': 'Tor birikme möhletleri',
      'torDirectSecsLabel': 'Göni synanyşygyň möhleti (sekunt)',
      'torBridgeSecsLabel': 'Her köprüniň möhleti (sekunt)',
      'torTimingsDesc': 'Çekirdek defaultlary: göni 75 s, her köprü 360 s. Ýuwşak ulaglarda artdyryň',
      'cdnSetsLabel': 'Fronting toplumlary',
      'cdnSetsHint': 'vergül bilen aýrylan — m. psiphon-akamai,vercel (boş = ählisi)',
      'cdnSetsDesc': 'CDN fronting nähili göni psiphon gyra sanawlaryny ulanýar',
      'secPsiphonTimings': 'Taýýynlyk möhleti',
      'psiphonReadyLabel': 'Psiphonyň taýýynlyk möhleti (sekunt)',
      'psiphonReadyDesc': 'Çekirdek defaulty 180 s; ýuwşak ulaglarda artdyryň — ädimligiň möhleti hem şoňa görä giňelýär',
      'serverEntriesLabel': 'Serwer ýazgylary',
      'serverEntriesHint': 'resmi psiphon müşderisinden serwer-ýazgylarynyň JSON-y',
      'serverEntriesDesc': 'Boş = göni psiphon tapylşygy',
      'secFamilyLeg': 'Birleşdirilen režimleriň esasy',
      'aetherLegLabel': 'Birleşdirilen režimleriň esasy',
      'torLegDesc': 'Birleşdirilen tor režimlerinde (zelze we ters) aşaky Aether tuneli şu protokoly ulanýar. Ters režimde UDP isleg edýän protokollar awtomatiki MASQUE-e geçirilýär (çekirdegiň çäklenmesi)',
      'psiphonLegDesc': 'Birleşdirilen psiphon režimlerinde (zelze we ters) aşaky Aether tuneli şu protokoly ulanýar. Ters režimde UDP isleg edýän protokollar awtomatiki MASQUE-e geçirilýär (çekirdegiň çäklenmesi)',
      'secIpVersion': 'IP wersiýasy',
      'ipV4': 'IPv4',
      'ipV6': 'IPv6',
      'ipDual': 'Ikilen',
      'ipVersionDesc': 'Käbir ulaglar döwük IPv6 berýär; IPv4 — çekirdegiň öz defaulty',
      'secUpstream': 'Ýokary akym proksisi',
      'upstreamLabel': 'Proksi salgysy (hökmany däl)',
      'upstreamHint': 'socks5://127.0.0.1:1080',
      'upstreamDesc': 'Diňe adaty Aether režimleri; çekirdek şu proksi arkaly birikýär. Boş = öçürilen',
      'echLabel': 'ECH (şifrlenen SNI)',
      'echOff': 'Öçürilen',
      'echAuto': 'Awtomatiki',
      'echManual': 'Ellik',
      'echOffDesc': 'SNI adaty ýaly ugradylýar',
      'echAutoDesc': 'ECH açary DNS arkaly gözlenilýär we serweriň ady şifrlenip ugradylýar',
      'echManualDesc': 'Base64 ECH açaryny özüňiz berýärsiňiz',
      'echKeyLabel': 'ECH açary (base64)',
      'echKeyHint': 'm. AEDW…',
      'echDnsLabel': 'Açary gözleýän DNS',
      'echDnsHint': 'm. https://1.1.1.1/dns-query',
      'echDomainLabel': 'Açar domeni (hökmany däl)',
      'echDomainHint': 'default: cloudflare-ech.com',
      // v6 login.
      'loginWelcomeTitle': 'Serüäne taýynmy?',
      'loginLanguageTitle': 'Programma dili',
      'loginRoutingTitle': 'Marşrutlaşdyryş sebiti',
      'loginLookTitle': 'Programma görnüşi',
      'loginDoneTitle': 'Sazlama tamamlandy!',
      'loginWelcomeDesc':
          'Birnäçe ýönekeý ädimde AETHONE-yň mümkinçilikleri bilen tanyş: birikdiriş režimiňizi we islegen protokolyňyzy saýlaň, sazlamalary öz islegleriňize görä sazyň. Has çeýel birikdirişe we dürli aragatnaşyk ýollaryna ýol açýan serüwiňiz şu ýerde başlanýar!',
      'loginDoneDesc':
          'Başlamak üçin hemme zat taýyn! Ilkinji sazlamalary üstünlikli tamamlaň we indi AETHONE-yň dünýäsine girebilirsiňiz. Esasy ekrana gaýdyň, islegen birikdirişiňizi goşaň we erkin aragatnaşygyň täze tejribesi bilen öz serüwiňizi başlaň!',
      'loginNext': 'Indiki',
      'loginPrev': 'Yza',
      'loginGo': 'Gidel!',
      'langTurkmen': 'Türkmençe',
      'speedTestTitle': 'Tizlik testi',
      'speedPhasePing': 'Ping',
      'speedPhaseDownload': 'Ýüklenme',
      'speedPhaseUpload': 'Ýüklemek',
      'speedStart': 'Başla',
      'speedStarted': 'Başlandy...',
      'speedRestart': 'Täzeden başla',
    },  };

  /// Resolves strings for the ambient locale; `fa` is the design language
  /// and the fallback for unmapped locales (e.g. tk for now).
  static AppStrings of(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    return forLocale(locale?.languageCode);
  }

  static AppStrings forLocale(String? languageCode) {
    final map = _table[languageCode ?? 'fa'] ?? _table['en']!;
    return AppStrings._(map);
  }
}
