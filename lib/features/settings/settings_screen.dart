/// The Settings main page — v1.1.0 «control center» redesign (owner:
/// «صفحه اصلی تنظیمات و سایر قسمت های تنظیمات رو با زبان طراحی صفحه ورود
/// و صفحات اصلی اپ بازطراحی کن ... فقط میخوام کاربر راحت تر و بهتر به
/// تنظیمات دسترسی داشته باشه»).
///
/// The login's vocabulary carries the page:
///   * the HERO card is the login sheet — its top edge carries the same
///     centre notch, and the notch holds the login step indicator re-read
///     as the connection's three phases (off · connecting · on: the active
///     phase is the wide pill, in the state's own color);
///   * under it the login step composition — the rounded icon box (the
///     selected protocol's own logo), the centred title and a one-line
///     summary — and three QUICK controls (Kill Switch, connection mode,
///     theme) that change the setting in place, no page to open;
///   * a SEARCH field that finds any setting by name and opens its page;
///   * the CATEGORIES as one grouped list — each row a login icon box, the
///     title and a LIVE summary of what is set (no more guessing behind a
///     tile). Connection + security and look + language are merged pages;
///   * the protocol family (Psiphon / Tor / Lantern / Aether core) as a
///     2×2 grid with each one's live exit location, and the support block
///     (core log, the two core repositories, the version) at the bottom.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_state.dart';
import '../../connection/connection_store.dart';
import '../../connection/core_log.dart';
import '../../connection/transport_modes.dart';
import '../../core/app_assets.dart';
import '../../core/app_theme.dart';
import '../../core/country_names.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../core/motion_widgets.dart';
import '../../l10n/app_strings.dart';
import '../shared/theme_toggle_tile.dart';
import 'appearance_page.dart';
import 'connection_page.dart';
import 'core_page.dart';
import 'general_page.dart';
import 'lantern_page.dart';
import 'psiphon_page.dart';
import 'routing_page.dart';
import 'subpage_frame.dart';
import 'tor_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  ConnectionStore get store => widget.store;

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _open(Widget page) {
    _searchFocus.unfocus();
    Navigator.of(context).push(
      aethPageRoute<void>(
        style: store.effectiveMotionStyle(context),
        builder: (_) => page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final style = store.effectiveMotionStyle(context);
    return AnimatedBuilder(
      animation: Listenable.merge([store, _query]),
      builder: (context, _) {
        final strings = AppStrings.of(context);
        final searching = _query.text.trim().isNotEmpty;
        final blocks = <Widget>[
          _SettingsTopBar(
            store: store,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          SizedBox(height: 20 * s),
          _SearchField(controller: _query, focusNode: _searchFocus),
          SizedBox(height: 22 * s),
          if (searching)
            _SearchResults(
              entries: _searchIndex(strings),
              query: _query.text,
              onOpen: (e) => _open(e.builder()),
            )
          else ...[
            _SectionTitle(strings.settingsCategories),
            SizedBox(height: 10 * s),
            _CategoryList(store: store, onOpen: _open),
            SizedBox(height: 24 * s),
            _SectionTitle(strings.settingsProtocolsSection),
            SizedBox(height: 10 * s),
            _ProtocolGrid(store: store, onOpen: _open),
          ],
          SizedBox(height: 30 * s),
        ];
        return Scaffold(
          backgroundColor: AethColors.bgScreen,
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _searchFocus.unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(
                  horizontal: AethGeometry.pageHPadding * s,
                ),
                child: MotionScope(
                  style: style,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: AethGeometry.topSafeExtraGap * s),
                      for (var i = 0; i < blocks.length; i++)
                        motionCascade(context, style, i.clamp(0, 8), blocks[i]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Every setting a person may look for, by the words its page uses.
  List<_SearchEntry> _searchIndex(AppStrings t) {
    Widget conn() => ConnectionSettingsPage(store: store);
    Widget routing() => RoutingSettingsPage(store: store);
    Widget look() => AppearanceSettingsPage(store: store);
    Widget general() => GeneralSettingsPage(store: store);
    Widget core() => CoreSettingsPage(store: store);
    Widget psiphon() => PsiphonSettingsPage(store: store);
    Widget tor() => TorSettingsPage(store: store);
    Widget lantern() => LanternSettingsPage(store: store);
    final cs = t.settingsConnSecTitle;
    final rt = t.settingsRouting;
    final lk = t.settingsLookLangTitle;
    final gn = t.settingsGeneral;
    const cr = 'Aether Core';
    return [
      _SearchEntry(t.secKillSwitch, cs, AppAssets.iconOff, conn),
      _SearchEntry(t.sheetHeadingMode, cs, AppAssets.iconPassword1, conn),
      _SearchEntry(t.secIpVersion, cr, AppAssets.iconWebsite, core),
      _SearchEntry(t.secUpstream, cr, AppAssets.iconArrowSwapHorizontal, core),
      _SearchEntry(t.settingsRoutingArea, rt, AppAssets.iconRedo, routing),
      _SearchEntry(
        t.hybridRouting,
        rt,
        AppAssets.iconArrowSwapHorizontal,
        routing,
      ),
      _SearchEntry(t.secRoutes, rt, AppAssets.iconRedo, routing),
      _SearchEntry(t.tunnelApps, rt, AppAssets.iconCategory, routing),
      _SearchEntry(t.secThemeMode, lk, AppAssets.iconMoon, look),
      _SearchEntry(t.secHomeLook, lk, AppAssets.iconHome1, look),
      _SearchEntry(t.secMotion, lk, AppAssets.iconActivity4, look),
      _SearchEntry(t.animationsOffTitle, lk, AppAssets.iconCloseCircle, look),
      _SearchEntry(t.secPatterns, lk, AppAssets.iconPalette, look),
      _SearchEntry(t.secAppLanguage, lk, AppAssets.iconWebsite, look),
      _SearchEntry(t.secAbout, gn, AppAssets.iconInformationCircle, general),
      _SearchEntry(t.secNotifications, gn, AppAssets.iconNotification, general),
      _SearchEntry(t.secCloseBehavior, gn, AppAssets.iconClose, general),
      _SearchEntry(t.secAutoStart, gn, AppAssets.iconOff, general),
      _SearchEntry(t.secReset, gn, AppAssets.iconRedo, general),
      _SearchEntry(t.secFragment, cr, AppAssets.iconCrop1, core),
      _SearchEntry(t.secTransport, cr, AppAssets.iconArrowSwapHorizontal, core),
      _SearchEntry(t.secScanSpeed, cr, AppAssets.iconScan1, core),
      _SearchEntry(t.secTls, cr, AppAssets.iconShieldTick, core),
      _SearchEntry(t.echLabel, cr, AppAssets.iconShieldStar, core),
      _SearchEntry(t.expertMode, cr, AppAssets.iconSetting, core),
      _SearchEntry(
        t.settingsPsiphon,
        t.settingsProtocolsSection,
        AppAssets.protocolPsiphonLogo,
        psiphon,
        tinted: false,
      ),
      _SearchEntry(
        t.secFronting,
        t.settingsPsiphon,
        AppAssets.iconDiscovery1,
        psiphon,
      ),
      _SearchEntry(
        t.settingsTor,
        t.settingsProtocolsSection,
        AppAssets.protocolTorLogo,
        tor,
        tinted: false,
      ),
      _SearchEntry(t.secTorBridges, t.settingsTor, AppAssets.iconShuffle1, tor),
      _SearchEntry(
        t.settingsLantern,
        t.settingsProtocolsSection,
        AppAssets.protocolLanternLogo(light: AethThemeSync.light),
        lantern,
        tinted: false,
      ),
      _SearchEntry(
        t.coreLogTitle,
        gn,
        AppAssets.iconInformationCircle,
        () => CoreLogPage(style: store.effectiveMotionStyle(context)),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Shared text helpers
// ---------------------------------------------------------------------------

TextStyle _yekan(double size, FontWeight w, Color c, {double? height}) =>
    TextStyle(
      fontFamily: 'IRANYekanX',
      fontWeight: w,
      fontSize: size,
      height: height,
      color: c,
    );

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: appContentDirection(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6 * s),
        child: Row(
          children: [
            // The login indicator's ACTIVE pill as the section mark.
            Container(
              width: 18 * s,
              height: 6 * s,
              decoration: BoxDecoration(
                color: AethColors.accentConnected,
                borderRadius: BorderRadius.circular(3 * s),
              ),
            ),
            SizedBox(width: 8 * s),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _yekan(14 * s, FontWeight.w700, AethColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar: theme toggle · «تنظیمات» · back chevron — unchanged positions.
// ---------------------------------------------------------------------------

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.onBack, required this.store});

  final VoidCallback onBack;
  final ConnectionStore store;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.topTileSize * s;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: tile,
        child: Row(
          children: [
            ThemeToggleTile(
              store: store,
              size: tile,
              iconSize: AethGeometry.topTileIcon * s,
              tileKey: const ValueKey('settings-theme-toggle'),
            ),
            const Spacer(),
            Text(
              strings.settingsTitle,
              style: _yekan(17 * s, FontWeight.w700, AethColors.textPrimary),
            ),
            const Spacer(),
            Semantics(
              label: 'Back',
              button: true,
              child: GestureDetector(
                key: const ValueKey('settings-back'),
                behavior: HitTestBehavior.opaque,
                onTap: onBack,
                child: Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: AethColors.topTile,
                    borderRadius: BorderRadius.circular(
                      AethGeometry.topTileRadius * s,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AethColors.tileShadow,
                        offset: const Offset(0, 4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    AppAssets.iconRight2,
                    width: AethGeometry.topTileIcon * s,
                    height: AethGeometry.topTileIcon * s,
                    colorFilter: ColorFilter.mode(
                      AethColors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

class _SearchEntry {
  const _SearchEntry(
    this.title,
    this.section,
    this.icon,
    this.builder, {
    this.tinted = true,
  });

  final String title;
  final String section;
  final String icon;
  final Widget Function() builder;
  final bool tinted;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final hasText = controller.text.isNotEmpty;
    return Directionality(
      textDirection: appContentDirection(context),
      child: Container(
        height: 52 * s,
        padding: EdgeInsets.symmetric(horizontal: 14 * s),
        decoration: BoxDecoration(
          color: AethColors.cardDark,
          borderRadius: BorderRadius.circular(18 * s),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              AppAssets.iconSearch,
              width: 20 * s,
              height: 20 * s,
              colorFilter: ColorFilter.mode(
                AethColors.textSecondary,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              child: TextField(
                key: const ValueKey('settings-search'),
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                cursorColor: AethColors.accentConnected,
                style: _yekan(14 * s, FontWeight.w400, AethColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: t.settingsSearchHint,
                  hintStyle: _yekan(
                    14 * s,
                    FontWeight.w300,
                    AethColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (hasText)
              Semantics(
                button: true,
                label: 'Clear',
                child: GestureDetector(
                  key: const ValueKey('settings-search-clear'),
                  behavior: HitTestBehavior.opaque,
                  onTap: controller.clear,
                  child: Padding(
                    padding: EdgeInsets.all(8 * s),
                    child: SvgPicture.asset(
                      AppAssets.iconCloseCircle,
                      width: 20 * s,
                      height: 20 * s,
                      colorFilter: ColorFilter.mode(
                        AethColors.textSecondary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.entries,
    required this.query,
    required this.onOpen,
  });

  final List<_SearchEntry> entries;
  final String query;
  final ValueChanged<_SearchEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final q = query.trim().toLowerCase();
    final hits = entries
        .where(
          (e) =>
              e.title.toLowerCase().contains(q) ||
              e.section.toLowerCase().contains(q),
        )
        .toList();
    if (hits.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 28 * s),
        child: Column(
          children: [
            SettingsIconBox(
              asset: AppAssets.iconSearch,
              size: 56 * s,
              glyph: 26 * s,
              color: AethColors.cardDark,
              glyphColor: AethColors.textSecondary,
            ),
            SizedBox(height: 12 * s),
            Text(
              t.settingsSearchEmpty,
              key: const ValueKey('settings-search-empty'),
              textAlign: TextAlign.center,
              textDirection: appContentDirection(context),
              style: _yekan(13 * s, FontWeight.w400, AethColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return _GroupCard(
      children: [
        for (final e in hits)
          _ListRow(
            keyId: 'settings-hit-${e.title}',
            icon: e.icon,
            tinted: e.tinted,
            title: e.title,
            summary: e.section,
            onTap: () => onOpen(e),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Grouped list primitives
// ---------------------------------------------------------------------------

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 6 * s),
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius: BorderRadius.circular(22 * s),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Directionality(
                textDirection: appContentDirection(context),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 70 * s,
                    end: 16 * s,
                  ),
                  child: Container(height: 1, color: AethColors.sheetSubtile),
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.keyId,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
    this.tinted = true,
  });

  final String keyId;
  final String icon;
  final String title;
  final String summary;
  final VoidCallback onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final rtl = appContentDirection(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: '$title, $summary',
      child: GestureDetector(
        key: ValueKey(keyId),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AethHaptics.tap();
          onTap();
        },
        child: Directionality(
          textDirection: appContentDirection(context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 10 * s),
            child: Row(
              children: [
                SettingsIconBox(
                  asset: icon,
                  size: 44 * s,
                  glyph: tinted ? 22 * s : 28 * s,
                  tinted: tinted,
                ),
                SizedBox(width: 14 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _yekan(
                          15 * s,
                          FontWeight.w600,
                          AethColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2 * s),
                      AnimatedValueText(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textStyle: _yekan(
                          12 * s,
                          FontWeight.w400,
                          AethColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * s),
                SvgPicture.asset(
                  rtl ? AppAssets.iconLeft2 : AppAssets.iconRight2,
                  width: 18 * s,
                  height: 18 * s,
                  colorFilter: ColorFilter.mode(
                    AethColors.textSecondary,
                    BlendMode.srcIn,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Categories — one grouped list with LIVE summaries.
// ---------------------------------------------------------------------------

String _langName(AppStrings t, String? code) => switch (code) {
  null => t.langSystem,
  'fa' => 'فارسی',
  'en' => 'English',
  'ru' => 'Русский',
  'zh' => '中文',
  'tk' => 'Türkmen',
  _ => code,
};

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.store, required this.onOpen});

  final ConnectionStore store;
  final ValueChanged<Widget> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final mode = store.connectionMode == ConnectionMode.tunnel
        ? t.modeTunnel
        : t.modeProxy;
    final rules = store.hybridRules.values
        .expand((l) => l)
        .where((r) => r.enabled)
        .length;
    final theme = switch (store.themePick) {
      AethThemePick.night => t.themePickNight,
      AethThemePick.light => t.themePickLight,
      AethThemePick.auto => t.themePickAuto,
    };
    return _GroupCard(
      children: [
        _ListRow(
          keyId: 'settings-cat-connection',
          icon: AppAssets.iconLock1,
          title: t.settingsConnSecTitle,
          summary:
              '$mode • Kill Switch ${store.killSwitch ? t.settingsOn : t.settingsOff}',
          onTap: () => onOpen(ConnectionSettingsPage(store: store)),
        ),
        _ListRow(
          keyId: 'settings-cat-routing',
          icon: AppAssets.iconRedo,
          title: t.settingsRouting,
          summary: [
            store.routingRegion == null
                ? t.routingNone
                : countryName(
                        store.routingRegion,
                        locale: Localizations.localeOf(context).languageCode,
                      ) ??
                      t.routingRegionName(store.routingRegion),
            if (rules > 0) '${t.hybridRouting}: ${t.settingsRulesCount(rules)}',
          ].join(' • '),
          onTap: () => onOpen(RoutingSettingsPage(store: store)),
        ),
        _ListRow(
          keyId: 'settings-cat-look',
          icon: AppAssets.iconPalette,
          title: t.settingsLookLangTitle,
          summary: '$theme • ${_langName(t, store.appLocale)}',
          onTap: () => onOpen(AppearanceSettingsPage(store: store)),
        ),
        _ListRow(
          keyId: 'settings-cat-general',
          icon: AppAssets.iconFilter5,
          title: t.settingsGeneral,
          summary: t.settingsAboutSub,
          onTap: () => onOpen(GeneralSettingsPage(store: store)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Protocols & core — a 2×2 grid with each family's live exit location.
// ---------------------------------------------------------------------------

class _ProtocolGrid extends StatelessWidget {
  const _ProtocolGrid({required this.store, required this.onOpen});

  final ConnectionStore store;
  final ValueChanged<Widget> onOpen;

  String _exit(BuildContext context, String code) {
    final t = AppStrings.of(context);
    if (code == LocationWheelPolicy.autoCode) return t.settingsExitAuto;
    return countryName(
          code,
          locale: Localizations.localeOf(context).languageCode,
        ) ??
        code.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    Widget tile(
      String keyId,
      String logo,
      bool tinted,
      String title,
      String sub,
      Widget Function() page,
    ) => Expanded(
      child: _ProtocolTile(
        keyId: keyId,
        logo: logo,
        tinted: tinted,
        title: title,
        subtitle: sub,
        onTap: () => onOpen(page()),
      ),
    );
    return Directionality(
      textDirection: appContentDirection(context),
      child: Column(
        children: [
          Row(
            children: [
              tile(
                'settings-proto-psiphon',
                AppAssets.protocolPsiphonLogo,
                false,
                t.settingsPsiphon,
                _exit(context, store.psiphonLocation),
                () => PsiphonSettingsPage(store: store),
              ),
              SizedBox(width: 10 * s),
              tile(
                'settings-proto-tor',
                AppAssets.protocolTorLogo,
                false,
                t.settingsTor,
                _exit(context, store.torLocation),
                () => TorSettingsPage(store: store),
              ),
            ],
          ),
          SizedBox(height: 10 * s),
          Row(
            children: [
              tile(
                'settings-proto-lantern',
                AppAssets.protocolLanternLogo(light: AethThemeSync.light),
                false,
                t.settingsLantern,
                _exit(context, store.lanternLocation),
                () => LanternSettingsPage(store: store),
              ),
              SizedBox(width: 10 * s),
              tile(
                'settings-proto-core',
                // v1.1.0 — the app's own green mark (owner round).
                AppAssets.brandMark,
                false,
                'Aether Core',
                t.settingsCoreSub,
                () => CoreSettingsPage(store: store),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtocolTile extends StatelessWidget {
  const _ProtocolTile({
    required this.keyId,
    required this.logo,
    required this.tinted,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String keyId;
  final String logo;
  final bool tinted;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: GestureDetector(
        key: ValueKey(keyId),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AethHaptics.tap();
          onTap();
        },
        child: Container(
          height: 74 * s,
          padding: EdgeInsets.symmetric(horizontal: 12 * s),
          decoration: BoxDecoration(
            color: AethColors.cardDark,
            borderRadius: BorderRadius.circular(22 * s),
          ),
          child: Row(
            children: [
              SettingsIconBox(
                asset: logo,
                size: 44 * s,
                glyph: tinted ? 22 * s : 28 * s,
                tinted: tinted,
              ),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _yekan(
                        14 * s,
                        FontWeight.w600,
                        AethColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2 * s),
                    AnimatedValueText(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textStyle: _yekan(
                        11.5 * s,
                        FontWeight.w400,
                        AethColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// v4.21 — the core diagnostics page (unchanged behaviour).
// ---------------------------------------------------------------------------

/// The full-screen core log viewer: tails the capture every 2 s while
/// open, supports copy (share sheet is out of scope — Clipboard + a toast
/// is honest) and clear.
class CoreLogPage extends StatefulWidget {
  const CoreLogPage({super.key, this.style = MotionStyle.standard});

  /// v4.25 — the effective motion style (the page's own controls).
  /// v5.3 — the pattern params (showPatterns/connected/alive) are retired:
  /// the page carries no patterns any more (the owner's home + speed-page
  /// only rule).
  final MotionStyle style;

  @override
  State<CoreLogPage> createState() => _CoreLogPageState();
}

class _CoreLogPageState extends State<CoreLogPage> {
  final CoreLogReader _reader = CoreLogReader();
  CoreLogSnapshot _snapshot = const CoreLogSnapshot(text: '', totalBytes: 0);
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final snapshot = await _reader.read();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await _reader.clear();
    await _refresh();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _snapshot.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).coreLogCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Directionality(
      // v1.0.2 — the content follows the app's own locale.
      textDirection: appContentDirection(context),
      child: Scaffold(
        backgroundColor: AethColors.bgScreen,
        // v5.3 — NO patterns here (the owner: home + speed test only).
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Column(
                children: [
                  // Header row: back · title · copy · clear
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('core-log-back'),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: SvgPicture.asset(
                            AppAssets.iconRight2,
                            width: 22,
                            height: 22,
                            colorFilter: ColorFilter.mode(
                              AethColors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            strings.coreLogTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'IRANYekanX',
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AethColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('core-log-copy'),
                          tooltip: strings.coreLogCopy,
                          onPressed: _snapshot.isEmpty ? null : _copy,
                          icon: SvgPicture.asset(
                            AppAssets.iconSend,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              _snapshot.isEmpty
                                  ? AethColors.textSecondary
                                  : AethColors.accentConnected,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('core-log-clear'),
                          tooltip: strings.coreLogClear,
                          onPressed: _snapshot.isEmpty ? null : _clear,
                          icon: SvgPicture.asset(
                            AppAssets.iconClose,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              _snapshot.isEmpty
                                  ? AethColors.textSecondary
                                  : AethColors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        strings.coreLogSize(_snapshot.totalBytes),
                        style: TextStyle(
                          fontFamily: 'IRANYekanX',
                          fontWeight: FontWeight.w400,
                          fontSize: 11,
                          color: AethColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      key: const ValueKey('core-log-body'),
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: AethColors.cardDark,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      // v1.0.2 — the loading->content swap crossfades and
                      // the spinner obeys the kill-switch (a STATIC ring
                      // with animations off — was an always-spinning
                      // CircularProgressIndicator, the audit's finding).
                      child: AnimatedSwitcher(
                        duration: motionDuration(
                          widget.style,
                          MotionDurations.quick,
                        ),
                        child: _loading
                            ? Center(
                                key: const ValueKey('core-log-loading'),
                                child: widget.style == MotionStyle.off
                                    ? Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AethColors.accentConnected,
                                            width: 4,
                                          ),
                                        ),
                                      )
                                    : const CircularProgressIndicator(
                                        color: AethColors.accentConnected,
                                      ),
                              )
                            : _snapshot.isEmpty
                            ? Center(
                                child: Text(
                                  strings.coreLogEmpty,
                                  style: TextStyle(
                                    fontFamily: 'IRANYekanX',
                                    fontWeight: FontWeight.w400,
                                    fontSize: 13,
                                    color: AethColors.textSecondary,
                                  ),
                                ),
                              )
                            : Scrollbar(
                                key: const ValueKey('core-log-content'),
                                child: SingleChildScrollView(
                                  // The core's own lines are LTR (English +
                                  // timestamps); one line per log record.
                                  child: Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: SelectionArea(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          _snapshot.text,
                                          key: const ValueKey('core-log-text'),
                                          style: TextStyle(
                                            fontFamily: 'IRANYekanX',
                                            fontWeight: FontWeight.w400,
                                            fontSize: 11,
                                            height: 1.5,
                                            color: AethColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
