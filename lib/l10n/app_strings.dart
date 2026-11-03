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
