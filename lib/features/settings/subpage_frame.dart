/// The shared frame of every settings SUB-page (v4.22 — owner round:
/// «تنظیمات جزیی»). One visual language with the settings main page and
/// the protocol page, all of it the app's own vocabulary:
///
///  * the HOME screen's edge patterns behind (same position, same
///    connected/disconnected state), gated by the appearance switch;
///  * the fixed chrome the owner decreed for every page («دکمه برگشت و
///    دکمه علامت تعجب هم که دکمه های ثابت همه صفحه ها باید باشن»):
///    v4.34 — that exclamation tile is now the NIGHT ⇄ LIGHT theme switch
///    (owner round 10) at the visual LEFT, the title centered, the back
///    chevron tile at the visual RIGHT — the settings page's own
///    arrangement;
///  * the entrance/exit cascade: every block slides up 22 px + fades on
///    its own slice of the ROUTE timeline (the settings page's recipe,
///    v4.17 — «به صفحه و کارت ها انیمیشن ورود و خروج اضافه کن»);
///  * sections: a right-aligned heading (icon + title, the settings
///    family look) over one dark card (r21) with #1A261C hairlines
///    between rows — the descriptions-popup's divider vocabulary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../shared/theme_toggle_tile.dart';

/// The Telegram channel — the info tile's destination on every page.
Future<void> openTelegramChannel() async {
  final uri = Uri.parse('https://t.me/AETHONE');
  // External browser/app — never an in-app webview (same as home).
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The block-cascade entrance the settings pages share — the per-style
/// v4.25 recipe (each mode's own rise/zoom/curve/stagger; OFF = no-op).
/// With no route (bare-harness pumps) the child renders untouched.
Widget subpageEnter(
  BuildContext context,
  MotionStyle style,
  int block,
  Widget child, {
  EntranceFlavor flavor = EntranceFlavor.standard,
}) {
  return motionCascade(context, style, block, child, flavor: flavor);
}

/// One sub-page: [title] in the chrome, [children] as the cascading body
/// blocks (block 0 = the top bar, blocks 1..n = the children in order).
///
/// [children] is a BUILDER, re-invoked on every store notification: the
/// pages read their section values (store fields, CoreSettings) INSIDE
/// the closure, so a preference change rebuilds the page body — the
/// conditional sections (custom fields, expert panels) appear and vanish
/// live (the v4.17 protocol-page LIVE-BINDING lesson).
class SubPageFrame extends StatelessWidget {
  const SubPageFrame({
    super.key,
    required this.store,
    required this.title,
    required this.children,
    this.icon,
    this.iconTinted = true,
    this.subtitle,
  });

  final ConnectionStore store;
  final String title;

  /// v1.1.0 (settings redesign) — the login-style page header: the glyph
  /// sits in the login's rounded icon box, the title and a one-line
  /// summary centred under it (the «صفحه ورود» step composition). When
  /// set, the top bar keeps only its two tiles; null keeps the old bar.
  final String? icon;

  /// false renders [icon] with its own colors (protocol logos).
  final bool iconTinted;
  final String? subtitle;
  final List<Widget> Function() children;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // v4.25 — the effective style (the master kill-switch clamps to OFF);
    // every block cascade AND the small controls inside the cards read it.
    final style = store.effectiveMotionStyle(context);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        backgroundColor: AethColors.bgScreen,
        // v5.3 (the owner: «پترن های سمت راست و چپ فقط باید در صفحه اصلی و
        // صفحه تست سرعت نمایش داده بشن و در سایر صفحه ها نباید نمایش داده
        // شوند») — the sub-pages carry NO patterns (and no smoke) any more.
        body: Stack(
          fit: StackFit.expand,
          children: [
            // LTR-locked geometry (the settings-page precedent): the
            // chrome rows land on the frame's measured positions while
            // Persian text inside keeps its natural bidi direction.
            SafeArea(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AethGeometry.pageHPadding * s,
                    ),
                    child: MotionScope(
                      style: style,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: AethGeometry.topSafeExtraGap * s),
                          subpageEnter(
                            context,
                            style,
                            0,
                            _SubPageTopBar(
                              title: icon == null ? title : '',
                              store: store,
                              onBack: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                          if (icon != null) ...[
                            SizedBox(height: 6 * s),
                            subpageEnter(
                              context,
                              style,
                              0,
                              SubPageHeader(
                                icon: icon!,
                                iconTinted: iconTinted,
                                title: title,
                                subtitle: subtitle,
                              ),
                            ),
                            SizedBox(height: 26 * s),
                          ] else
                            SizedBox(height: 22 * s),
                          // v1.0.2 — the body column resizes SOFTLY when a
                          // conditional section (export panel, bridge/ECH
                          // fields, per-app router rows) appears or folds:
                          // the style's own sectionResizeMs through the
                          // scope (OFF = instant, the audit's jump fix).
                          AnimatedSize(
                            duration: Duration(
                              milliseconds: MotionScope.of(context)
                                  .recipe
                                  .sectionResizeMs,
                            ),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: Builder(
                              builder: (context) {
                                final blocks = children();
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0; i < blocks.length; i++)
                                      subpageEnter(
                                        context,
                                        style,
                                        i + 1,
                                        blocks[i],
                                      ),
                                    SizedBox(height: 30 * s),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
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

/// The settings-page chrome: theme-toggle tile visual LEFT · title
/// centered · back chevron tile visual RIGHT (v4.34 — the exclamation /
/// info tile became the night ⇄ light switch).
class _SubPageTopBar extends StatelessWidget {
  const _SubPageTopBar({
    required this.title,
    required this.store,
    required this.onBack,
  });

  final String title;
  final ConnectionStore store;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.topTileSize * s;
    return SizedBox(
      height: tile,
      child: Row(
        children: [
          ThemeToggleTile(
            store: store,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            tileKey: const ValueKey('subpage-info'),
          ),
          // v4.22 device lesson: long page titles («تنظیمات هستهٔ Aether»)
          // overflowed the 336 px row at 17 px — the title now rides an
          // Expanded + FittedBox scale-down (the server-pills recipe), so
          // the FULL title always stays visible, centered like the
          // settings page's own «تنظیمات».
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textDirection: appContentDirection(context),
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w700,
                    fontSize: 17 * s,
                    color: AethColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          _TopTile(
            key: const ValueKey('subpage-back'),
            asset: AppAssets.iconRight2,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
        ],
      ),
    );
  }
}

/// The owner «Rectangle 9» tile — identical to the settings/home bars.
class _TopTile extends StatelessWidget {
  const _TopTile({
    super.key,
    required this.asset,
    required this.size,
    required this.iconSize,
    required this.semanticLabel,
    this.onTap,
  });

  final String asset;
  final double size;
  final double iconSize;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AethColors.topTile,
            borderRadius: BorderRadius.circular(AethGeometry.topTileRadius * s),
            // v4.35 (owner round 11, item 1): NO shadow in light mode —
            // the color rides the palette (night rgba(0,0,0,0.25) 0 4 4 /
            // light transparent) and fades with the 420 ms mode tween.
            boxShadow: [
              BoxShadow(
                color: AethColors.tileShadow,
                offset: const Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A right-aligned section heading — the settings family look (icon 20
/// white to the visual RIGHT of the title, hugging the page inset).
/// v4.22 device lesson: long titles (e.g. «مسیرهای مستقیم و مسدود»)
/// overflow the row at 15 px — the text rides a FittedBox scale-down
/// (the server-pills recipe), so the FULL title always stays visible.
/// v1.1.0 (settings redesign) — the login step composition re-used as a
/// page header: the rounded icon box (login 44/r16, here 56/r18 on the
/// card surface), the centred title (login 19/w500) and a short summary.
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconTinted = true,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final bool iconTinted;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final dir = appContentDirection(context);
    return Column(
      children: [
        SettingsIconBox(
          asset: icon,
          size: 56 * s,
          glyph: 28 * s,
          tinted: iconTinted,
          color: AethColors.cardDark,
        ),
        SizedBox(height: 14 * s),
        Text(
          title,
          textAlign: TextAlign.center,
          textDirection: dir,
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w600,
            fontSize: AethGeometry.loginTitleSize * s,
            color: AethColors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: 6 * s),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            textDirection: dir,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w300,
              fontSize: 13 * s,
              height: 1.5,
              color: AethColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// The login's rounded icon box (44×44 r16 in «صفحه ورود») as a shared
/// settings primitive: an SVG glyph centred on a soft tile. Tinted glyphs
/// take the accent green; [tinted] false keeps a logo's own colors.
class SettingsIconBox extends StatelessWidget {
  const SettingsIconBox({
    super.key,
    required this.asset,
    required this.size,
    required this.glyph,
    this.tinted = true,
    this.color,
    this.glyphColor,
  });

  final String asset;
  final double size;
  final double glyph;
  final bool tinted;
  final Color? color;
  final Color? glyphColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? AethColors.bgScreen,
        borderRadius: BorderRadius.circular(size * 16 / 44),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        asset,
        width: glyph,
        height: glyph,
        fit: BoxFit.contain,
        colorFilter: tinted
            ? ColorFilter.mode(
                glyphColor ?? AethColors.accentConnected,
                BlendMode.srcIn,
              )
            : null,
      ),
    );
  }
}

/// A section heading — v1.1.0: a small icon box + the title, aligned to
/// the reading START of the app's language (was pinned to the visual
/// right in every locale).
class SubSectionHeading extends StatelessWidget {
  const SubSectionHeading({super.key, required this.icon, required this.title});

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: appContentDirection(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4 * s),
        child: Row(
          children: [
            SettingsIconBox(
              asset: icon,
              size: 28 * s,
              glyph: 16 * s,
              color: AethColors.cardDark,
              glyphColor: AethColors.textPrimary,
            ),
            SizedBox(width: 10 * s),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w700,
                    fontSize: 14 * s,
                    color: AethColors.textPrimary,
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

class SubSectionCard extends StatelessWidget {
  const SubSectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Container(
      decoration: BoxDecoration(
        color: AethColors.cardDark,
        borderRadius: BorderRadius.circular(22 * s),
      ),
      padding: padding ?? EdgeInsets.all(16 * s),
      child: child,
    );
  }
}

class SubSectionDivider extends StatelessWidget {
  const SubSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * s),
      child: Container(height: 1, color: AethColors.sheetSubtile),
    );
  }
}

/// The vertical rhythm between a heading and its card, and between
/// sections — the settings page's own gaps.
class SubSectionGap extends StatelessWidget {
  const SubSectionGap.headingToCard({super.key})
    : size = AethGeometry.settingsHeadingGapToCards;
  const SubSectionGap.cardToHeading({super.key})
    : size = AethGeometry.settingsHeading2GapToServer;
  const SubSectionGap.betweenRows({super.key}) : size = 12;

  final double size;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SizedBox(height: size * s);
  }
}
