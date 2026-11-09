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

  /// PHASE-1 (firefox-vpn, private branch): the Firefox VPN engine — a
  /// DEDICATED communication engine (Go child process `libfirefoxvpn.so`,
  /// local SOCKS5 on 127.0.0.1:1822), NOT an aether overlay: no aether
  /// core runs for this mode. The protocol tile/UI presentation is
  /// Phase 2's scope; the engine wiring lives in
  /// lib/connection/firefox/ + the adapter's firefox branch.
  firefoxOnly,
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

  /// PHASE-1 (firefox-vpn): the dedicated Firefox VPN engine mode.
  bool get isFirefox => this == ProtocolId.firefoxOnly;
}

abstract final class AppAssets {
  static const String _icons = 'design/آیکون های اپ';
  static const String _protocols = 'design/آیکون پروتکل ها';
  static const String _patterns = 'design/patterns_png';
  static const String _logo = 'design/آیکون اپ';
  static const String _flags = 'design/flags_png';

  // --- app logo: 1 = green (connected artwork, rotated), 3 = clean white
  // (tintable — used for BOTH hero states with the owner's rotation
  // animation). 2 = the retired silver-gradient facets (superseded by the
  // owner's round-11 mark below; the file stays committed untouched).
  //
  // v4.35 (owner round 11, item 3: «لوگوی زیرش در هر دو حالت باید رنگ سبز
  // داشته باشه که فایل svg اون رو میزارم برات») — the mark behind the
  // wordmark is the owner's own «آیکون بالای اپ» artwork: the same facet
  // composition on a #1AD995→transparent GREEN gradient, committed under
  // its owner-given name. It renders with its OWN colors in BOTH modes
  // (theme-independent by construction — green at night AND in light).
  static const String appLogoConnected = '$_logo/1.svg';
  static const String brandMark = '$_logo/آیکون بالای اپ.svg';
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

  /// v4.41 (round 17, item 4) — the per-app tunneling section's heading
  /// (the launchable-apps grid) + the selected-row check.
  static const String iconCategory = '$_icons/Category.svg';
  static const String iconTick = '$_icons/Tick.svg';

  /// v4.41 (round 17, item 12) — the notifications section's heading (the
  /// owner's icon-set glyph).
  static const String iconNotification = '$_icons/Notification 1.svg';
  static const String iconSend = '$_icons/Send 1.svg';

  /// v1.0.0 (round 18) — the About-card link rows' glyphs, the owner's
  /// own picks: «برای تلگرام از آیکون: Send 3 استفاده کن و برای
  /// اینستاگرام از Instagram.svg استفاده کن که توی پوشه آیکون های اپ
  /// هست». The repo row rides the committed GitHub logo (logoGithub).
  static const String iconSend3 = '$_icons/Send 3.svg';
  static const String iconInstagram = '$_icons/Instagram.svg';

  // --- v4.34 light mode (owner round 10): the theme-toggle icons the
  // owner named — «آیکون با نام Sun 1 برای حالت لایت و آیکون با نام Moon
  // برای حالت نایت مود که هردو در پوشه آیکون های اپ موجود هستند».
  static const String iconSun1 = '$_icons/Sun 1.svg';
  static const String iconMoon = '$_icons/Moon.svg';

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

  // --- v4.16 protocol sheet: the two heading badges measured on the sheet
  // frame — «حالت اتصال» carries the key-in-frame glyph (Password 1.svg —
  // pixel-verified identical on both headings).
  // v4.17 — owner: «آیکون پروتکل باید Swap 1.svg» and «آیکون سرعت اسکن باید
  // Scan 1.svg» — the protocol heading swaps to [iconSwap1] (both on the
  // protocol page and on the settings status card) and the scan-speed
  // heading takes [iconScan1] (already declared).
  static const String iconPassword1 = '$_icons/Password 1.svg';
  static const String iconSwap1 = '$_icons/Swap 1.svg';

  // v4.16 descriptions popup: the × close glyph (the set's own Close.svg).
  static const String iconClose = '$_icons/Close.svg';

  // --- v4.22 (owner round: «تنظیمات جزیی»): the settings sub-page icons —
  // every glyph from the app's own icon pack ONLY (owner: «از آیکون های
  // پوشه آیکون های اپ برای بخش تنظیمات استفاده کن و از آیکون دیگه ای
  // استفاده نکن»). Names the owner has not personally blessed yet are
  // stopgaps the owner swaps by editing THIS table (one-line change each,
  // owner: «اگه نمیدونستی چه آیکونی بزاری یه آیکون رندوم بزار بعدا توی
  // اصلاح میگم تغیرش بدی»):
  //   fragment (TLS shard)      -> Crop 1
  //   TLS / core handshake      -> Shield Tick (iconShieldTick above)
  //   H2/H3 transport switch    -> Arrow Swap Horizontal
  //   DNS                       -> Website (iconWebsite, globe glyph)
  //   log level / diagnostics   -> Activity 4 (iconActivity4 above)
  //   performance               -> Graph Up (iconGraphUp above)
  //   keepalive (WG)            -> Watch 1
  //   expert-section chevron    -> Down 1 / Up 1
  //   location (family pages)   -> Location
  //   tor bridges               -> Discovery 1
  //   psiphon cdn fronting      -> Shuffle 1
  //   kill-switch row           -> Off (iconOff above)
  //   stepper +/-               -> Add / Minus
  static const String iconCrop1 = '$_icons/Crop 1.svg';
  static const String iconArrowSwapHorizontal =
      '$_icons/Arrow Swap Horizontal.svg';
  static const String iconDown1 = '$_icons/Down 1.svg';
  static const String iconUp1 = '$_icons/Up 1.svg';
  static const String iconWatch1 = '$_icons/Watch 1.svg';
  static const String iconLocation = '$_icons/Location.svg';
  static const String iconDiscovery1 = '$_icons/Discovery 1.svg';
  static const String iconShuffle1 = '$_icons/Shuffle 1.svg';
  static const String iconAdd = '$_icons/Add.svg';
  static const String iconMinus = '$_icons/Minus.svg';

  // v4.22 — the settings sub-page set, second batch: the in-page nav
  // chevron (Left 2 = the mirror sibling of the back chevron Right 2;
  // in this RTL app a LEFT-pointing chevron reads “deeper”) and the
  // home-look section glyph.
  static const String iconLeft2 = '$_icons/Left 2.svg';
  static const String iconHome1 = '$_icons/Home 1.svg';

  // --- v4.23 onboarding («صفحه شروع»): every glyph pixel-matched against
  // the four wizard frames + the scanning frame (owner-swappable table —
  // names the owner has not blessed yet are one-line edits here):
  //   language step (globe)     -> Website (iconWebsite, the set's globe
  //                                 glyph — VLM-matched against Map.svg)
  //   routing step (curved arr) -> Redo (iconRedo, the routing family)
  //   look step (palette)       -> Palette (iconPalette)
  //   type step (sliders)       -> Setting (iconSetting)
  //   system-language tile      -> Setting (the gear glyph, dark-indigo
  //                                 [AethColors.tileGrayInk] tint)
  //   routing «none» tile       -> Close Circle (dark-indigo tint)
  //   check badge under the
  //     selected look preview   -> Tick Circle (dark on green)
  //   «اتوماتیک» card           -> Shield Star ([autoShieldAmber] on the
  //                                 green card, white on dark)
  //   «دستی» card               -> Shield 1 (the set's plain shield)
  //   CTA chevron               -> Left 2 (iconLeft2 above, white)
  static const String iconTickCircle = '$_icons/Tick Circle.svg';
  static const String iconCloseCircle = '$_icons/Close Circle.svg';
  static const String iconShield1 = '$_icons/Shield 1.svg';
  // (iconShieldStar already declared in the settings section above — the
  // v4.23 re-declaration was a duplicate_definition analyze error.)

  // --- v4.24 speed test («صفحه تست سرعت»): the stat-card glyphs. The ping
  // arcs and the DOWN/UP trend squares come from the app's own pack
  // (iconGraphDown/iconGraphUp are declared above; owner-swappable table,
  // the page's doc lists the mapping). Two glyphs are NOT in the pack and
  // are traced as vectors from the committed design frames themselves
  // (the patterns_png precedent — the design package is the source of
  // truth):
  //   jitter (drop + rain)  -> Drop Rain (design/speed_glyphs)
  //   badge + button core   -> Hex Wave (the brand hexagon+wave mark)
  static const String iconWifi = '$_icons/Wifi.svg';
  static const String _speedGlyphs = 'design/speed_glyphs';
  static const String iconDropRain = '$_speedGlyphs/Drop Rain.svg';
  static const String iconHexWave = '$_speedGlyphs/Hex Wave.svg';

  /// v4.33 (owner round 9) — the dial needle: the owner's own SVG «عقربه
  /// صفحه تست سرعت» (15×52, #1AD995→transparent gradient), committed under
  /// its owner-given name. It sweeps with the measured download speed.
  static const String speedNeedle = '$_speedGlyphs/عقربه صفحه تست سرعت.svg';

  // --- protocol logos. v4.40 (owner round 16) — THE OWNER'S OWN ICON
  // FILES, verbatim: «رنگ و شکل آیکون ها باید دقیقا همین فایل هایی باشه که
  // برات ارسال شده». Dark/light PAIRS (the owner's file names, «دارک» /
  // «لایت» suffixes): ماسک، میم، وایرگارد، گول. IDENTICAL in both modes
  // («هر دو حالت» — the owner's own naming): تور، سایفون، گول کلاسیک، and
  // the four combined-mode logos (no variant files were sent — one face for
  // both themes). The old v4.10/v4.35 tinting and shadow-rebuild rules are
  // RETIRED: these render with their OWN colors, no colorFilter ever.
  static const String _protoTorBoth = '$_protocols/تور هر دو حالت.svg';
  static const String _protoPsiphonBoth =
      '$_protocols/سایفون هر دو حالت.svg';
  static const String _protoGoolClassicBoth =
      '$_protocols/گول کلاسیک هردو حالت.svg';
  static const String _protoPsiphonOverWarp = '$_protocols/سایفون اور وارپ.svg';
  static const String _protoWarpOverPsiphon = '$_protocols/وارپ اور سایفون.svg';
  static const String _protoTorOverWarp = '$_protocols/تور اور وارپ.svg';
  static const String _protoWarpOverTor = '$_protocols/وارپ اور تور.svg';

  /// PHASE-2 REBUILD (2026-11-09): the OFFICIAL Firefox artwork the
  /// owner delivered (mozilla-vpn-seeklogo.svg), committed under the
  /// set's own single-face naming («هر دو حالت»). The mark is
  /// MONOCHROME (a single untinted path = default black), so it renders
  /// through the INK color on dark surfaces — the file's geometry is
  /// exact, only the ink adapts (see ProtocolGlyph's firefoxOnly rule).
  static const String _protoFirefoxBoth =
      '$_protocols/فایرفاکس هر دو حالت.svg';

  /// Public protocol-logo paths (the settings Psiphon/Tor pills render the
  /// REAL logos — v4.40: the owner's own «هر دو حالت» files, own colors).
  static const String protocolTorLogo = _protoTorBoth;
  static const String protocolPsiphonLogo = _protoPsiphonBoth;

  /// The OFFICIAL Firefox mark (the owner-delivered artwork,
  /// mozilla-vpn-seeklogo.svg) — the Firefox card/settings glyph.
  static const String protocolFirefoxLogo = _protoFirefoxBoth;

  /// Logo for a transport mode. AUTO/SMART has NO dedicated file in the
  /// owner's round-16 set — pending design decision D-pending (report §6.9
  /// suggests Shield Tick with gold accent); until decided it maps to Shield
  /// Tick (documented stopgap).
  ///
  /// v4.40 — THEME-AWARE: the four protocols the owner sent in TWO faces
  /// (ماسک/میم/وایرگارد/گول) pick the «لایت» file when [light] is true, the
  /// «دارک» file otherwise; tor/psiphon/gool-classic and the combined modes
  /// carry one face for both themes (the owner's own «هر دو حالت" naming).
  /// Colors and shapes are EXACTLY the owner's files — the caller never
  /// tints them (decree: «رنگ و شکل آیکون ها باید دقیقا همین فایل هایی باشه
  /// که برات ارسال شده»).
  static String protocolIcon(ProtocolId id, {required bool light}) =>
      switch (id) {
        ProtocolId.auto => iconShieldTick,
        ProtocolId.masque =>
          '$_protocols/ماسک ${light ? 'لایت' : 'دارک'}.svg',
        ProtocolId.wireguard =>
          '$_protocols/وایرگارد ${light ? 'لایت' : 'دارک'}.svg',
        ProtocolId.gool => '$_protocols/گول ${light ? 'لایت' : 'دارک'}.svg',
        ProtocolId.goolClassic => _protoGoolClassicBoth,
        ProtocolId.mim => '$_protocols/میم ${light ? 'لایت' : 'دارک'}.svg',
        ProtocolId.torChain => _protoTorOverWarp,
        ProtocolId.torReverse => _protoWarpOverTor,
        ProtocolId.torOnly => _protoTorBoth,
        ProtocolId.psiphonChain => _protoPsiphonOverWarp,
        ProtocolId.psiphonReverse => _protoWarpOverPsiphon,
        ProtocolId.psiphonOnly => _protoPsiphonBoth,
        // PHASE-2 REBUILD (2026-11-09): the owner's OFFICIAL Firefox
        // artwork (open item G2 closed) — the Shield-Tick stopgap is
        // retired. Monochrome mark: ProtocolGlyph carries the ink rule.
        ProtocolId.firefoxOnly => _protoFirefoxBoth,
      };

  /// Country flag by ISO code (lowercase), e.g. `ir` → ir.png.
  /// v4.10: 265 of the 266 flag SVGs embed the artwork as a raster
  /// `<image>` inside a `<pattern>` — unsupported by flutter_svg (renders
  /// BLANK on device; only vector ir.svg worked). All flags are therefore
  /// shipped as pre-rendered 256×256 PNGs extracted from the owner's own
  /// embedded artwork (no redesign, byte-faithful to the SVG).
  ///
  /// v4.41 (round 17): `flag('auto')` is the OWNER'S OWN artwork — the
  /// delivered «آیکون لوکیشن خودکار» tile (design/brand/auto-location.svg,
  /// the green rounded square with the white globe mark), rendered 256×256
  /// like every other flag. The v4.21 placeholder globe is retired.
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
        iconCategory,
        iconTick,
        iconNotification,
        iconSend,
        // v1.0.0 — the About-card link rows (Send 3 / Instagram).
        iconSend3,
        iconInstagram,
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
        iconPassword1,
        iconSwap1,
        iconClose,
        // v4.22 — the settings sub-page set (owner-swappable table above).
        iconCrop1,
        iconArrowSwapHorizontal,
        iconDown1,
        iconUp1,
        iconWatch1,
        iconLocation,
        iconDiscovery1,
        iconShuffle1,
        iconAdd,
        iconMinus,
        iconLeft2,
        iconHome1,
        // v4.23 — the onboarding set (owner-swappable table above).
        iconTickCircle,
        iconCloseCircle,
        iconShield1,
        iconShieldStar,
        // v4.34 — the theme-toggle pair.
        iconSun1,
        iconMoon,
        // v4.40 — the owner's round-16 protocol icons: every referenced
        // face of every protocol (both dark and light variants where the
        // owner sent a pair).
        _protoTorBoth,
        _protoPsiphonBoth,
        _protoGoolClassicBoth,
        ...ProtocolId.values.expand(
          (id) => [protocolIcon(id, light: true), protocolIcon(id, light: false)],
        ),
        flag('ir'),
        flag('tm'),
        flag('ru'),
        flag('cn'),
        flag('de'),
        flag('us'),
        // v4.21 — the AUTO placeholder globe (family location selectors).
        flag('auto'),
        // v4.24 — the speed-test stat-card glyphs.
        iconWifi,
        iconDropRain,
        iconHexWave,
        // v4.33 — the dial needle (the owner's own SVG).
        speedNeedle,
      ];
}
