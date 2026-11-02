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
