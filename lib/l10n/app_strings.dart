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
  String get descAuto => _v['descAuto']!;
  String get descMasque => _v['descMasque']!;
  String get descWireguard => _v['descWireguard']!;
  String get descGool => _v['descGool']!;
  String get descGoolClassic => _v['descGoolClassic']!;
  String get descMim => _v['descMim']!;
  String get descPsiphonChain => _v['descPsiphonChain']!;
  String get descPsiphonReverse => _v['descPsiphonReverse']!;
  String get descPsiphonOnly => _v['descPsiphonOnly']!;
  String get descTorChain => _v['descTorChain']!;
  String get descTorReverse => _v['descTorReverse']!;
  String get descTorOnly => _v['descTorOnly']!;

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
      'descAuto':
          'برنامه به‌صورت خودکار روش‌های اتصال پشتیبانی‌شده را بررسی می‌کند و بر اساس موفقیت اتصال، سرعت و پایداری شبکه، مناسب‌ترین گزینه را انتخاب می‌کند. در صورت بروز اختلال، برای برقراری مجدد اتصال تلاش می‌کند؛ بدون نیاز به انتخاب دستی پروتکل توسط شما.',
      'descMasque':
          'اتصال رمزگذاری‌شده از طریق ترافیک شبیه HTTPS. از HTTP/3 و HTTP/2 پشتیبانی می‌کند و برای شبکه‌هایی که ترافیک VPN را محدود می‌کنند طراحی شده است.',
      'descWireguard':
          'اتصال مستقیم از طریق پروتکل WireGuard روی هستهٔ Aether؛ IP خروجی متعلق به سرور خروجی WARP خواهد بود.',
      'descGool':
          'اتصال از طریق حالت Gool روی هستهٔ Aether؛ IP خروجی متعلق به سرور خروجی WARP خواهد بود.',
      'descGoolClassic':
          'اتصال از طریق حالت Gool کلاسیک روی هستهٔ Aether؛ IP خروجی متعلق به سرور خروجی WARP خواهد بود.',
      'descMim':
          'اتصال از طریق حالت Mim روی هستهٔ Aether؛ IP خروجی متعلق به سرور خروجی WARP خواهد بود.',
      'descPsiphonChain':
          'ابتدا تونل Aether برقرار می‌شود و سپس Psiphon از داخل آن به اینترنت متصل می‌شود. آدرس IP خروجی متعلق به سرور خروجی Psiphon خواهد بود.',
      'descPsiphonReverse':
          'ابتدا اتصال از طریق Psiphon برقرار می‌شود و سپس تونل Aether از داخل آن شکل می‌گیرد. این روش به Aether اجازه می‌دهد از مسیر خروجی Psiphon به شبکه متصل شود.',
      'descPsiphonOnly':
          'اتصال مستقیماً از طریق Psiphon برقرار می‌شود و از تونل Aether یا WARP استفاده نمی‌کند. مسیر خروجی اینترنت توسط Psiphon تأمین می‌شود.',
      'descTorChain':
          'ابتدا اتصال Aether برقرار می‌شود و سپس ترافیک از شبکهٔ Tor عبور می‌کند. آدرس IP خروجی متعلق به یک گره خروجی Tor خواهد بود.',
      'descTorReverse':
          'ابتدا اتصال به شبکهٔ Tor برقرار می‌شود و سپس تونل Aether از داخل آن ایجاد می‌شود. خروجی نهایی از طریق تونل Aether خواهد بود.',
      'descTorOnly':
          'اتصال مستقیماً از طریق شبکهٔ Tor برقرار می‌شود و از تونل Aether یا WARP استفاده نمی‌کند. آدرس IP خروجی متعلق به یک گره خروجی Tor است.',
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
      // ---- v4.16 protocol sheet (translations of the fa verbatim frame +
      // the phase-1 report §11 descriptions) ----
      'sheetHeadingMode': 'Connection mode',
      'modeTunnel': 'Tunnel',
      'modeProxy': 'Proxy',
      'sheetHeadingScanSpeed': 'Scan speed',
      'protocolPageTitle': 'Select protocol',
      'protoAutoSheet': 'Auto',
      'descAuto':
          'The app automatically probes the supported transport modes and picks the best one by connection success, speed and network stability. On disruption it keeps trying to re-establish the connection — no manual protocol choice needed.',
      'descMasque':
          'An encrypted connection over HTTPS-like traffic. Supports HTTP/3 and HTTP/2 and is designed for networks that restrict VPN traffic.',
      'descWireguard':
          'A direct connection over the WireGuard protocol on the Aether core; the exit IP belongs to a WARP exit server.',
      'descGool':
          'A connection over the Gool mode on the Aether core; the exit IP belongs to a WARP exit server.',
      'descGoolClassic':
          'A connection over the classic Gool mode on the Aether core; the exit IP belongs to a WARP exit server.',
      'descMim':
          'A connection over the Mim mode on the Aether core; the exit IP belongs to a WARP exit server.',
      'descPsiphonChain':
          'The Aether tunnel comes up first, then Psiphon connects to the internet from inside it. The exit IP address belongs to a Psiphon exit server.',
      'descPsiphonReverse':
          'Psiphon connects first, then the Aether tunnel is formed inside it. This lets Aether reach the network through the Psiphon exit path.',
      'descPsiphonOnly':
          'The connection is established directly through Psiphon and does not use the Aether tunnel or WARP. The internet exit path is provided by Psiphon.',
      'descTorChain':
          'Aether connects first, then the traffic passes through the Tor network. The exit IP address belongs to a Tor exit node.',
      'descTorReverse':
          'The connection to the Tor network comes up first, then the Aether tunnel is created inside it. The final exit goes through the Aether tunnel.',
      'descTorOnly':
          'The connection is established directly through the Tor network and does not use the Aether tunnel or WARP. The exit IP address belongs to a Tor exit node.',
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
      // ---- v4.16 protocol sheet ----
      'sheetHeadingMode': 'Режим подключения',
      'modeTunnel': 'Туннель',
      'modeProxy': 'Прокси',
      'sheetHeadingScanSpeed': 'Скорость сканирования',
      'protocolPageTitle': 'Выбор протокола',
      'protoAutoSheet': 'Авто',
      'descAuto':
          'Приложение автоматически проверяет поддерживаемые режимы подключения и выбирает лучший по успешности подключения, скорости и стабильности сети. При сбое оно само пытается восстановить связь — без ручного выбора протокола.',
      'descMasque':
          'Шифрованное подключение через трафик, похожий на HTTPS. Поддерживает HTTP/3 и HTTP/2 и предназначено для сетей, ограничивающих VPN-трафик.',
      'descWireguard':
          'Прямое подключение по протоколу WireGuard на ядре Aether; выходной IP принадлежит выходному серверу WARP.',
      'descGool':
          'Подключение через режим Gool на ядре Aether; выходной IP принадлежит выходному серверу WARP.',
      'descGoolClassic':
          'Подключение через классический режим Gool на ядре Aether; выходной IP принадлежит выходному серверу WARP.',
      'descMim':
          'Подключение через режим Mim на ядре Aether; выходной IP принадлежит выходному серверу WARP.',
      'descPsiphonChain':
          'Сначала поднимается туннель Aether, затем Psiphon подключается к интернету изнутри него. Выходной IP принадлежит выходному серверу Psiphon.',
      'descPsiphonReverse':
          'Сначала подключается Psiphon, затем внутри него строится туннель Aether. Это позволяет Aether выходить в сеть через маршрут Psiphon.',
      'descPsiphonOnly':
          'Подключение устанавливается напрямую через Psiphon и не использует туннель Aether или WARP. Выходной маршрут интернета обеспечивает Psiphon.',
      'descTorChain':
          'Сначала подключается Aether, затем трафик проходит через сеть Tor. Выходной IP принадлежит выходному узлу Tor.',
      'descTorReverse':
          'Сначала устанавливается соединение с сетью Tor, затем внутри него создаётся туннель Aether. Финальный выход — через туннель Aether.',
      'descTorOnly':
          'Подключение устанавливается напрямую через сеть Tor и не использует туннель Aether или WARP. Выходной IP принадлежит выходному узлу Tor.',
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
      // ---- v4.16 protocol sheet ----
      'sheetHeadingMode': '连接模式',
      'modeTunnel': '隧道',
      'modeProxy': '代理',
      'sheetHeadingScanSpeed': '扫描速度',
      'protocolPageTitle': '选择协议',
      'protoAutoSheet': '自动',
      'descAuto':
          '应用自动探测受支持的传输模式，并根据连接成功率、速度与网络稳定性选择最优方案。出现中断时会自动尝试恢复连接，无需手动选择协议。',
      'descMasque':
          '通过类似 HTTPS 的流量建立加密连接。支持 HTTP/3 与 HTTP/2，专为限制 VPN 流量的网络设计。',
      'descWireguard':
          '在 Aether 内核上通过 WireGuard 协议直连；出口 IP 属于 WARP 出口服务器。',
      'descGool': '在 Aether 内核上通过 Gool 模式连接；出口 IP 属于 WARP 出口服务器。',
      'descGoolClassic':
          '在 Aether 内核上通过经典 Gool 模式连接；出口 IP 属于 WARP 出口服务器。',
      'descMim':
          '在 Aether 内核上通过 Mim 模式连接；出口 IP 属于 WARP 出口服务器。',
      'descPsiphonChain':
          '首先建立 Aether 隧道，随后 Psiphon 从隧道内接入互联网。出口 IP 属于 Psiphon 出口服务器。',
      'descPsiphonReverse':
          '首先通过 Psiphon 建立连接，再在其内部构建 Aether 隧道。这使 Aether 能够经由 Psiphon 的出口路径接入网络。',
      'descPsiphonOnly':
          '直接通过 Psiphon 建立连接，不使用 Aether 隧道或 WARP。互联网出口路由由 Psiphon 提供。',
      'descTorChain':
          '首先建立 Aether 连接，随后流量经 Tor 网络传出。出口 IP 属于 Tor 出口节点。',
      'descTorReverse':
          '首先接入 Tor 网络，再在其内部创建 Aether 隧道。最终出口经由 Aether 隧道。',
      'descTorOnly':
          '直接通过 Tor 网络建立连接，不使用 Aether 隧道或 WARP。出口 IP 属于 Tor 出口节点。',
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
