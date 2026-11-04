/// The shared frame of every settings SUB-page (v4.22 — owner round:
/// «تنظیمات جزیی»). One visual language with the settings main page and
/// the protocol page, all of it the app's own vocabulary:
///
///  * the HOME screen's edge patterns behind (same position, same
///    connected/disconnected state), gated by the appearance switch;
///  * the fixed chrome the owner decreed for every page («دکمه برگشت و
///    دکمه علامت تعجب هم که دکمه های ثابت همه صفحه ها باید باشن»):
///    the info tile (Telegram) at the visual LEFT, the title centered,
///    the back chevron tile at the visual RIGHT — the settings page's
///    own arrangement;
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
import '../home/widgets/pattern_sides.dart';

/// The Telegram channel — the info tile's destination on every page.
Future<void> openTelegramChannel() async {
  final uri = Uri.parse('https://t.me/AETHONE');
  // External browser/app — never an in-app webview (same as home).
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The block-cascade entrance the settings pages share. With no route
/// (bare-harness pumps) the child renders untouched.
Widget subpageEnter(BuildContext context, int block, Widget child) {
  final anim = ModalRoute.of(context)?.animation;
  if (anim == null) return child;
  return AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      final t = anim.value;
      final start = (block * 0.075).clamp(0.0, 0.45);
      final bt = Curves.easeOutCubic
          .transform(Interval(start, start + 0.55).transform(t));
      if (bt >= 0.999) return child;
      final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
      return Opacity(
        opacity: bt,
        child: Transform.translate(
          offset: Offset(0, (1 - bt) * 22 * s),
          child: child,
        ),
      );
    },
  );
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
  });

  final ConnectionStore store;
  final String title;
  final List<Widget> Function() children;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        backgroundColor: AethColors.bgScreen,
        body: Stack(
          children: [
            // The home patterns behind (v4.21 decree), gated by the
            // appearance switch (v4.22).
            if (store.showPatterns)
              Positioned.fill(
                child: PatternSides(
                  connected: store.isConnected,
                  style: store.animationStyle,
                  stage: PatternStage.home,
                ),
              ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: AethGeometry.topSafeExtraGap * s),
                        subpageEnter(
                          context,
                          0,
                          _SubPageTopBar(
                            title: title,
                            onInfo: openTelegramChannel,
                            onBack: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        SizedBox(height: 22 * s),
                        Builder(
                          builder: (context) {
                            final blocks = children();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < blocks.length; i++)
                                  subpageEnter(context, i + 1, blocks[i]),
                                SizedBox(height: 30 * s),
                              ],
                            );
                          },
                        ),
                      ],
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

/// The settings-page chrome: info tile (Telegram) visual LEFT · title
/// centered · back chevron tile visual RIGHT.
class _SubPageTopBar extends StatelessWidget {
  const _SubPageTopBar({
    required this.title,
    required this.onBack,
    required this.onInfo,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.topTileSize * s;
    return SizedBox(
      height: tile,
      child: Row(
        children: [
          _TopTile(
            key: const ValueKey('subpage-info'),
            asset: AppAssets.iconInformationCircle,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Telegram channel',
            onTap: onInfo,
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
                  textDirection: TextDirection.rtl,
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
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000), // rgba(0,0,0,0.25) 0 4 4
                offset: Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              asset,
              width: iconSize,
              height: iconSize,
              colorFilter: const ColorFilter.mode(
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
class SubSectionHeading extends StatelessWidget {
  const SubSectionHeading({super.key, required this.icon, required this.title});

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: AethGeometry.settingsHeadingSize * s,
                  color: AethColors.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(width: 8 * s),
          SvgPicture.asset(
            icon,
            width: AethGeometry.settingsHeadingIconSize * s,
            height: AethGeometry.settingsHeadingIconSize * s,
            colorFilter: const ColorFilter.mode(
              AethColors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
        ],
      ),
    );
  }
}

/// One section's dark card (r21, the settings family corners) with
/// internal padding; rows inside are separated by [SubSectionDivider].
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
        borderRadius: BorderRadius.circular(AethGeometry.settingsCardRadius * s),
      ),
      padding: padding ?? EdgeInsets.all(16 * s),
      child: child,
    );
  }
}

/// The hairline between rows (the descriptions-popup divider colour).
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
