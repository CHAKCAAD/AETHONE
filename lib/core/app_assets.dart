/// Typed asset manifest — single source of truth for every design asset the
/// UI uses. Paths point INTO the committed `design/` package (single source of
/// truth, no duplication). File and folder names are used EXACTLY as committed
/// (owner rule: never rename). See `test/app_assets_test.dart` — it fails CI
/// if any referenced file is missing.
library;

/// Protocol identifiers — the 11 transport modes of the evidence table
/// (phase-1 report table 11) plus the AUTO/SMART selector.
enum ProtocolId {
  auto,
  masque,
  wireguard,
  gool,
  goolClassic,
  mim,
  torChain,
  torReverse,
  torOnly,
  psiphonChain,
  psiphonReverse,
  psiphonOnly,
}

extension ProtocolIdX on ProtocolId {
  /// Tor/Psiphon families replace the flag carousel with protocol selection
  /// (owner: the top area acts as the protocol selector in these modes).
  bool get isTor =>
      this == ProtocolId.torChain ||
      this == ProtocolId.torReverse ||
      this == ProtocolId.torOnly;

  bool get isPsiphon =>
      this == ProtocolId.psiphonChain ||
      this == ProtocolId.psiphonReverse ||
      this == ProtocolId.psiphonOnly;
}

abstract final class AppAssets {
  static const String _icons = 'design/آیکون های اپ';
  static const String _protocols = 'design/آیکون پروتکل ها';
  static const String _patterns = 'design/patterns_png';
  static const String _logo = 'design/آیکون اپ';
  static const String _flags = 'design/flags_png';
  static const String _protoPng = 'design/proto_icons_png';

  // --- app logo: 1 = green (connected artwork, rotated), 2 = gradient
  // facets (the brand mark behind the wordmark — v4.11, defect #14),
  // 3 = clean white (tintable — used for BOTH hero states with the
  // owner's rotation animation).
  static const String appLogoConnected = '$_logo/1.svg';
  static const String brandMark = '$_logo/2.svg';
  static const String appLogoNeutralWhite = '$_logo/3.svg';

  // --- background patterns (red when disconnected, green when connected).
  // v4.10: pre-rendered PNGs (headless Chromium, filters intact) — the raw
  // SVGs carry feGaussianBlur which flutter_svg cannot rasterize (the
  // blurred edge circles rendered SOLID on device — the "giant blobs").
  static const String patternDisconnectedLeft = '$_patterns/pattern_disconnected_left.png';
  static const String patternDisconnectedRight = '$_patterns/pattern_disconnected_right.png';
  static const String patternConnectedLeft = '$_patterns/pattern_connected_left.png';
  static const String patternConnectedRight = '$_patterns/pattern_connected_right.png';

  // --- linear icon set (subset actually used; owner forbids other icon
  // sources — no Material icons, no emoji, no online images).
  static const String iconShieldTick = '$_icons/Shield Tick.svg';
  static const String iconShieldCross = '$_icons/Shield Cross.svg';
  static const String iconGraphDown = '$_icons/Graph Down.svg';
  static const String iconGraphUp = '$_icons/Graph Up.svg';
  static const String iconDownload = '$_icons/Download.svg';
  static const String iconUpload = '$_icons/Upload.svg';
  static const String iconSetting = '$_icons/Setting.svg';
  static const String iconInformationCircle = '$_icons/Information Circle.svg';
  static const String iconMap = '$_icons/Map.svg';
  static const String iconSend = '$_icons/Send 1.svg';

  // --- owner-mandated assets for the connect/speed/chevron surfaces
  // (v4.11 defect reports #2/#4/#12):
  static const String iconOff = '$_icons/Off.svg';
  static const String iconActivity4 = '$_icons/Activity 4.svg';
  static const String iconRight2 = '$_icons/Right 2.svg';

  // --- step 2 (settings main page): pixel-matched against the design
  // frame — the six card icons, the status-card icons, the section
  // heading icon, and the owner's GitHub logo for the server cards.
  // The routing / Kill-Switch / routing-area cards all use the set's
  // single curved arrow (Redo) — 9× zoom verification against the frame.
  static const String iconRedo = '$_icons/Redo.svg';
  static const String iconFilter5 = '$_icons/Filter 5.svg';
  static const String iconLock1 = '$_icons/Lock 1.svg';
  static const String iconWebsite = '$_icons/Website.svg';
  static const String iconPalette = '$_icons/Palette.svg';
  static const String iconShieldStar = '$_icons/Shield Star.svg';
  static const String iconScan1 = '$_icons/Scan 1.svg';
  static const String iconMenuHamburger = '$_icons/Menu Hamburger.svg';
  static const String logoGithub = 'design/صفحه تنظیمات/لوگو گیت هاب.svg';

  // --- v4.15 (owner settings round #1/#7/#8): the three real set icons the
  // owner named for the settings page — «Security Safe.svg» for the
  // security card, «Menu Fries.svg» for the وضعیت پیکربندی heading,
  // «Situation 1.svg» for the آدرس هسته ها heading (the v4.14 stand-ins
  // Shield Star / Menu Hamburger / the drawn CrosshairIcon are retired
  // from the UI; the constants above stay for reference). [iconSend]
  // (Send 1.svg) gains its first real use: the status pill's connecting
  // icon (owner home round #6).
  static const String iconSecuritySafe = '$_icons/Security Safe.svg';
  static const String iconMenuFries = '$_icons/Menu Fries.svg';
  static const String iconSituation1 = '$_icons/Situation 1.svg';

  // --- protocol logos. Tor/Psiphon ship as pre-rendered PNGs (their SVGs
  // embed the artwork in hidden tracing layers + the real vector art,
  // which flutter_svg renders partially) — v4.10.
  static const String _protoMasque = '$_protocols/ماسک.svg';
  static const String _protoWireguard = '$_protocols/وایرگارد.svg';
  static const String _protoGool = '$_protocols/گول.svg';
  static const String _protoGoolClassic = '$_protocols/گول کلاسیک.svg';
  static const String _protoMim = '$_protocols/میم.svg';
  static const String _protoTor = '$_protoPng/تور.png';
  static const String _protoPsiphon = '$_protoPng/سایفون.png';

  /// Public protocol-logo paths (the settings Psiphon/Tor pills render the
  /// REAL logos with an accent-green tint).
  static const String protocolTorLogo = _protoTor;
  static const String protocolPsiphonLogo = _protoPsiphon;

  /// Logo for a transport mode. AUTO/SMART has NO dedicated SVG in the ZIP —
  /// pending design decision D-pending (report §6.9 suggests Shield Tick with
  /// gold accent); until decided it maps to Shield Tick (documented stopgap).
  static String protocolIcon(ProtocolId id) => switch (id) {
        ProtocolId.auto => iconShieldTick,
        ProtocolId.masque => _protoMasque,
        ProtocolId.wireguard => _protoWireguard,
        ProtocolId.gool => _protoGool,
        ProtocolId.goolClassic => _protoGoolClassic,
        ProtocolId.mim => _protoMim,
        ProtocolId.torChain => _protoTor,
        ProtocolId.torReverse => _protoTor,
        ProtocolId.torOnly => _protoTor,
        ProtocolId.psiphonChain => _protoPsiphon,
        ProtocolId.psiphonReverse => _protoPsiphon,
        ProtocolId.psiphonOnly => _protoPsiphon,
      };

  /// Country flag by ISO code (lowercase), e.g. `ir` → ir.png.
  /// v4.10: 265 of the 266 flag SVGs embed the artwork as a raster
  /// `<image>` inside a `<pattern>` — unsupported by flutter_svg (renders
  /// BLANK on device; only vector ir.svg worked). All flags are therefore
  /// shipped as pre-rendered 256×256 PNGs extracted from the owner's own
  /// embedded artwork (no redesign, byte-faithful to the SVG).
  static String flag(String code) => '$_flags/$code.png';

  /// True when the asset is a pre-rendered PNG (rendered via Image.asset);
  /// false for vector SVGs (rendered via flutter_svg).
  static bool isRasterAsset(String path) => path.endsWith('.png');

  /// All asset paths referenced above (used by the existence test).
  static List<String> get allReferenced => [
        appLogoConnected,
        appLogoNeutralWhite,
        patternDisconnectedLeft,
        patternDisconnectedRight,
        patternConnectedLeft,
        patternConnectedRight,
        iconShieldTick,
        iconShieldCross,
        iconGraphDown,
        iconGraphUp,
        iconDownload,
        iconUpload,
        iconSetting,
        iconInformationCircle,
        iconMap,
        iconSend,
        iconOff,
        iconActivity4,
        iconRight2,
        iconRedo,
        iconFilter5,
        iconLock1,
        iconWebsite,
        iconPalette,
        iconShieldStar,
        iconScan1,
        iconMenuHamburger,
        logoGithub,
        brandMark,
        iconSecuritySafe,
        iconMenuFries,
        iconSituation1,
        _protoMasque,
        _protoWireguard,
        _protoGool,
        _protoGoolClassic,
        _protoMim,
        _protoTor,
        _protoPsiphon,
        ...ProtocolId.values.map(protocolIcon),
        flag('ir'),
        flag('tm'),
        flag('ru'),
        flag('cn'),
        flag('de'),
        flag('us'),
      ];
}
