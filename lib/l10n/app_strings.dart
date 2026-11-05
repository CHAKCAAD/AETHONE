/// UI strings — minimal hand-rolled l10n for UI step 1 (home screen).
///
/// fa strings are taken VERBATIM from the reference screens (غیرفعال / متصل /
/// آفلاین / پروتکل). en/ru/zh are natural translations; tk falls back to en
/// until native Turkmen review (honest gap, tracked for the onboarding step).
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
  String get statusConnected => _v['statusConnected']!;
  String get statusConnecting => _v['statusConnecting']!;
  String get statusReconnecting => _v['statusReconnecting']!;
  String get statusFailed => _v['statusFailed']!;
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
  String get dnsLabel => _v['dnsLabel']!;
  String get dnsHint => _v['dnsHint']!;

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
  String get secNotifications => _v['secNotifications']!;
  String get notificationsComing => _v['notificationsComing']!;

  // language page
  String get secAppLanguage => _v['secAppLanguage']!;
  String get langSystem => _v['langSystem']!;
  String get langDesc => _v['langDesc']!;

  // appearance page
  String get secHomeLook => _v['secHomeLook']!;
  String get lookOne => _v['lookOne']!;
  String get lookTwo => _v['lookTwo']!;
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

  // ---- v4.23 onboarding («صفحه شروع» — fa VERBATIM from the four wizard
  // frames + «لودینگ اسکن», transcribed off 3–5× crops) ----
  /// «زبان برنامه چی باشه؟»
  String get obLanguageTitle => _v['obLanguageTitle']!;

  /// «ترافیک کدوم کشور مستقیم باشه؟»
  String get obRoutingTitle => _v['obRoutingTitle']!;

  /// «ضاهر دکمه اتصال چجوری باشه؟» — the frame's own spelling of ظاهر
  /// (kept verbatim per the pixel-faithful rule; one-line change if the
  /// owner prefers the dictionary spelling).
  String get obLookTitle => _v['obLookTitle']!;

  /// «ادامه بده» — the CTA of steps 1–3.
  String get obContinue => _v['obContinue']!;

  /// «برو بریم!» — the CTA of step 4.
  String get obFinish => _v['obFinish']!;

  /// «پروتکل اتوماتیک میخوای؟» — the step-4 section heading.
  String get obProtocolHeading => _v['obProtocolHeading']!;

  /// «دستی» — the manual option card's label («اتوماتیک» reuses
  /// [protoAutoSheet]).
  String get obManualLabel => _v['obManualLabel']!;

  /// The «اتوماتیک» card body (3 lines on the frame).
  String get obAutoDesc => _v['obAutoDesc']!;

  /// The «دستی» card body (3 lines on the frame).
  String get obManualDesc => _v['obManualDesc']!;

  /// «در حال پیدا کردن بهترین راه» — the scanning modal's title.
  String get obLoading => _v['obLoading']!;

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
  String protocolName(ProtocolId id) {
    final key = switch (id) {
      ProtocolId.auto => 'protoAuto',
      ProtocolId.masque => 'protoMasque',
      ProtocolId.wireguard => 'protoWireguard',
      ProtocolId.gool => 'protoGool',
      ProtocolId.goolClassic => 'protoGoolClassic',
      ProtocolId.mim => 'protoMim',
      ProtocolId.torChain ||
      ProtocolId.torReverse ||
      ProtocolId.torOnly =>
        'protoTor',
      ProtocolId.psiphonChain ||
      ProtocolId.psiphonReverse ||
      ProtocolId.psiphonOnly =>
        'protoPsiphon',
    };
    return _v[key] ?? _v['protoMasque']!;
  }

  static const Map<String, Map<String, String>> _table = {
    'fa': {
      'offline': 'آفلاین',
      'statusDisconnected': 'غیرفعال',
      'statusConnected': 'متصل',
      'statusConnecting': 'در حال اتصال',
      'statusReconnecting': 'اتصال مجدد',
      'statusFailed': 'خطا',
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
      'settingsPillSub': 'انتخاب لوکیشن و ...',
      'settingsAdvancedStatus': 'وضعیت پیکربندی',
      'settingsRoutingArea': 'منطقهٔ مسیریابی',
      'settingsMainServer': 'آدرس هسته ها',
      'settingsSubpageComingNext':
          'این بخش — در گام بعدی پیاده‌سازی می‌شود',
      // ---- v4.20 failure visibility + desc-popup port notes ----
      'failureCodeLabel': 'کد خطا',
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
      'dnsLabel': 'DNS داخل تونل',
      'dnsHint': 'با کاما جدا شود — مثلاً 1.1.1.1,1.0.0.1',
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
      'secNotifications': 'اعلان و رویداد',
      'notificationsComing': 'اعلان‌های وضعیت اتصال همراه یکپارچه‌سازی سیستم‌عامل اضافه می‌شود',
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
      // v4.23 onboarding — verbatim from the «صفحه شروع» frames.
      'obLanguageTitle': 'زبان برنامه چی باشه؟',
      'obRoutingTitle': 'ترافیک کدوم کشور مستقیم باشه؟',
      'obLookTitle': 'ضاهر دکمه اتصال چجوری باشه؟',
      'obContinue': 'ادامه بده',
      'obFinish': 'برو بریم!',
      'obProtocolHeading': 'پروتکل اتوماتیک میخوای؟',
      'obManualLabel': 'دستی',
      'obAutoDesc':
          'برنامه به‌صورت خودکار روش‌های اتصال پشتیبانی‌شده را بررسی می‌کند و بر اساس موفقیت اتصال، سرعت و پایداری شبکه، مناسب‌ترین گزینه را انتخاب می‌کند.',
      'obManualDesc':
          'بعد از ورود به صفحه اصلی برنامه میتونی از لیست پروتکل ها به صورت دستی پروتکل مورد نظرت رو انتخاب کنی. برنامه 5 پروتکل اصلی و 6 پروتکل غیراصلی داره.',
      'obLoading': 'در حال پیدا کردن بهترین راه',
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
      'statusDisconnected': 'Inactive',
      'statusConnected': 'Connected',
      'statusConnecting': 'Connecting',
      'statusReconnecting': 'Reconnecting',
      'statusFailed': 'Error',
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
      'settingsPillSub': 'Location & more …',
      'settingsAdvancedStatus': 'Configuration status',
      'settingsRoutingArea': 'Routing region',
      'settingsMainServer': 'Core addresses',
      'settingsSubpageComingNext': 'This section — coming in the next step',
      // ---- v4.20 failure visibility + desc-popup port notes ----
      'failureCodeLabel': 'Error code',
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
      'dnsLabel': 'DNS inside the tunnel',
      'dnsHint': 'comma-separated — e.g. 1.1.1.1,1.0.0.1',
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
      'secNotifications': 'Notifications & events',
      'notificationsComing': 'Connection notifications land with the OS integration step',
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
      // v4.23 onboarding.
      'obLanguageTitle': 'What should the app language be?',
      'obRoutingTitle': "Which country's traffic should go direct?",
      'obLookTitle': 'How should the connect button look?',
      'obContinue': 'Continue',
      'obFinish': "Let's go!",
      'obProtocolHeading': 'Want the automatic protocol?',
      'obManualLabel': 'Manual',
      'obAutoDesc':
          'The app automatically checks the supported connection methods and picks the most suitable one based on connection success, speed and network stability.',
      'obManualDesc':
          'Once you reach the home screen you can pick your protocol by hand from the list. The app ships 5 main and 6 secondary protocols.',
      'obLoading': 'Finding the best route',
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
      'statusDisconnected': 'Отключено',
      'statusConnected': 'Подключено',
      'statusConnecting': 'Подключение',
      'statusReconnecting': 'Переподключение',
      'statusFailed': 'Ошибка',
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
      'settingsPillSub': 'Локация и другое …',
      'settingsAdvancedStatus': 'Статус конфигурации',
      'settingsRoutingArea': 'Регион маршрутизации',
      'settingsMainServer': 'Адреса ядер',
      'settingsSubpageComingNext': 'Этот раздел — на следующем шаге',
      'failureCodeLabel': 'Код ошибки',
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
      'dnsLabel': 'DNS внутри туннеля',
      'dnsHint': 'через запятую — напр. 1.1.1.1,1.0.0.1',
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
      'secNotifications': 'Уведомления и события',
      'notificationsComing': 'Уведомления о подключении появятся вместе с интеграцией с ОС',
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
      // v4.23 onboarding.
      'obLanguageTitle': 'Какой язык приложения?',
      'obRoutingTitle': 'Трафик какой страны идёт напрямую?',
      'obLookTitle': 'Каким должен быть вид кнопки подключения?',
      'obContinue': 'Продолжить',
      'obFinish': 'Поехали!',
      'obProtocolHeading': 'Автоматический протокол?',
      'obManualLabel': 'Вручную',
      'obAutoDesc':
          'Программа автоматически проверяет поддерживаемые способы подключения и выбирает самый подходящий — по успешности подключения, скорости и стабильности сети.',
      'obManualDesc':
          'Попав на главный экран, вы сможете выбрать протокол вручную из списка. В программе 5 основных и 6 дополнительных протоколов.',
      'obLoading': 'Ищем лучший маршрут',
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
      'statusDisconnected': '未连接',
      'statusConnected': '已连接',
      'statusConnecting': '连接中',
      'statusReconnecting': '重新连接',
      'statusFailed': '错误',
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
      'settingsPillSub': '位置等 …',
      'settingsAdvancedStatus': '配置状态',
      'settingsRoutingArea': '路由区域',
      'settingsMainServer': '内核地址',
      'settingsSubpageComingNext': '此部分 — 将在下一步实现',
      'failureCodeLabel': '错误代码',
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
      'dnsLabel': '隧道内 DNS',
      'dnsHint': '逗号分隔 — 如 1.1.1.1,1.0.0.1',
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
      'secNotifications': '通知与事件',
      'notificationsComing': '连接通知将随系统集成步骤加入',
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
      // v4.23 onboarding.
      'obLanguageTitle': '程序用什么语言？',
      'obRoutingTitle': '哪个国家的流量直连？',
      'obLookTitle': '连接按钮长什么样？',
      'obContinue': '继续',
      'obFinish': '出发！',
      'obProtocolHeading': '要自动选择协议吗？',
      'obManualLabel': '手动',
      'obAutoDesc':
          '程序会自动检测支持的连接方式，并根据连接成功率、速度与网络稳定性选择最合适的一个。',
      'obManualDesc':
          '进入主界面后，你可以从列表中手动选择协议。程序内置 5 个主要协议和 6 个次要协议。',
      'obLoading': '正在寻找最佳路线',
      'langTurkmen': 'Türkmençe',
      'speedTestTitle': '速度测试',
      'speedPhasePing': 'Ping',
      'speedPhaseDownload': '下载',
      'speedPhaseUpload': '上传',
      'speedStart': '开始',
      'speedStarted': '已开始...',
      'speedRestart': '重新开始',
    },
    // tk: pending native review — falls back to English (documented gap).
  };

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
