/// v4.17 — THE PROTOCOL SELECTION PAGE, promoted from the v4.16 floating
/// sheet to a full page «مثل صفحه اصلی تنظیمات» (owner round #6): the same
/// settings-page chrome around the «انتخاب پروتکل» title. v4.19 (owner
/// device test #10): the two chrome tiles SWAPPED SLOTS — the BACK chevron
/// and the INFO tile (i → Telegram channel) exchanged places («جای دکمه
/// برگشت رو با دکمه ای که آیکون تعجب داره و آدرس کانال تلگرام عملکردشه
/// جابه جا کن»). The chrome Row runs under the app's RTL directionality:
/// the FIRST Row child renders on the visual RIGHT.
///
/// The v4.16 pixel work survives verbatim (design frames «صفحه شناور انتخاب
/// پروتکل صفحه اصلی.jpg» 402×874 + «صفحه شناور توضیحات پروتکل ها.jpg»); the
/// section geometry is re-anchored to the page (AethGeometry `proto*`
/// tokens) and every v4.17 owner defect report is folded in:
///
///  * YELLOW UNDERLINES FIXED: the v4.16 sheet route built a raw Stack with
///    NO Material ancestor — Flutter deliberately paints a double yellow
///    underline under every text without one (the v4.16 capture QA
///    mis-read it as a raster artifact; the owner then reported it from the
///    device). The page sits on a Scaffold/Material — gone.
///  * LIVE BINDING: the page listens to [ConnectionStore] — «حالت اتصال»
///    segments and «سرعت اسکن» pills now apply visually the moment they are
///    tapped, INDEPENDENT of protocol selection (the v4.16 sheet only
///    rebuilt when a protocol tap's setState ran).
///  * Headings: «پروتکل» badge = Swap 1.svg, «سرعت اسکن» badge = Scan 1.svg,
///    «حالت اتصال» keeps Password 1.svg; badges 20 → 26 and the text moved
///    next to its icon (gap 26 → 12).
///  * Tiles/family cards: radius 16 → 21 (the settings cards' corners);
///    family cards breathe (h 116, subtile gaps 20, vertically centred);
///    ماسک/وایرگارد glyph boxes match the other tiles (28).
///  * ⓘ badges: 15 px visual + a 32 px invisible hit box (easy tap, same
///    structure).
///  * Descriptions popup: deep 94% scrim so the text reads on the dark
///    card, and the × close grows Ø22 → Ø30.
///  * ENTRANCE/EXIT kept: the route fade + the internal block cascade
///    (staggered slide-up) ride the same route timeline; the exit retraces
///    the cascade on pop. Selecting a protocol still pulses and AUTO-POPS
///    back to the home page (owner v4.16 decree).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../connection/connection_state.dart';
import '../../../connection/connection_store.dart';
import '../../../connection/transport_modes.dart';
import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';
import '../../../core/motion.dart';
import '../../../l10n/app_strings.dart';
import '../widgets/pattern_sides.dart';
import '../widgets/top_bar.dart';

/// Pushes the protocol-selection page. The fade + internal cascade both
/// ride the route animation so entry, pop and system-back share one
/// timeline (the sheet's recipe, kept per the owner's «انیمیشن های فعلی رو
/// حذف نکن»).
PageRouteBuilder<void> protocolPageRoute({
  required ConnectionStore store,
  required MotionStyle style,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: motionDuration(style, 380),
    reverseTransitionDuration: motionDuration(style, 320),
    pageBuilder: (_, _, _) => ProtocolPage(store: store, style: style),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class ProtocolPage extends StatefulWidget {
  const ProtocolPage({
    super.key,
    required this.store,
    required this.style,
  });

  final ConnectionStore store;
  final MotionStyle style;

  @override
  State<ProtocolPage> createState() => _ProtocolPageState();
}

class _ProtocolPageState extends State<ProtocolPage> {
  /// The protocol whose ⓘ descriptions popup is open (a family id for the
  /// cards, the protocol itself for a tile).
  ProtocolId? _descFor;

  /// The protocol currently pulsing from a selection tap (auto-pop follows).
  ProtocolId? _pulseId;

  /// v4.21 — the single-knob plain-tile highlight: the committed protocol
  /// when it is a PLAIN tile, null when a family member is committed (the
  /// v4.20 "leg tile stays green under a family mode" double-highlight is
  /// exactly what the owner asked to remove).
  ProtocolId? get _plainHighlight {
    final p = widget.store.selectedProtocol;
    return p.isTor || p.isPsiphon ? null : p;
  }

  void _select(ProtocolId id) {
    if (!mounted) return;
    // v4.21 — SINGLE-KNOB selection, the v4.19 semantics restored (owner
    // device-test round 3: «حالت جدید که برای انتخاب پروتکل AETHER در حالت
    // اور وارپ ایجاد کردی از لحاظ تجربه کاربری جالب نیست لطفا به حالت قبل
    // برشگردون بعدا یک گزینه برای انتخاب پروتکل هسته AETHER در پروتکل های
    // اور وارپ اضافه میکنیم»): every tile and every family sub-tile commits
    // THE protocol — one green selection on the whole page. The WARP leg
    // under a family mode stays the fixed WireGuard default inside the
    // engine adapter until the promised dedicated option lands.
    final already = widget.store.selectedProtocol == id;
    setState(() => _pulseId = id);
    if (!already) widget.store.selectProtocol(id);
    // Owner v4.16: after choosing a protocol the user is returned to the
    // home page automatically. The 300 ms hold lets the green crossfade +
    // pulse land before the reverse slide.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _openDesc(ProtocolId id) => setState(() => _descFor = id);

  void _closeDesc() => setState(() => _descFor = null);

  Future<void> _openTelegram() async {
    final uri = Uri.parse(HomeTopBar.telegramChannelUrl);
    // External browser/app — never an in-app webview (same as settings).
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final routeAnim = ModalRoute.of(context)!.animation!;

    return PopScope(
      // The popup consumes BACK first; otherwise the route pops normally.
      canPop: _descFor == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _descFor != null) _closeDesc();
      },
      child: Scaffold(
        backgroundColor: AethColors.bgScreen,
        body: AnimatedBuilder(
          // v4.17: LIVE store binding — mode segments and scan pills apply
          // instantly, independent of protocol selection.
          animation: Listenable.merge([widget.store, routeAnim]),
          builder: (context, _) {
            final t = routeAnim.value;
            final s =
                MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
            return Stack(
              children: [
                // v4.21 — the owner's decree: the OTHER pages carry the
                // home screen's patterns, exactly the same, same position
                // («از پترن های صفحه اصلی برای سایر صفحات مثل انتخاب پروتکل
                // و تنطیمات استفاده کن دقیقا همونا با همون مکان»).
                Positioned.fill(
                  child: PatternSides(
                    connected: widget.store.isConnected,
                    style: widget.store.animationStyle,
                    stage: PatternStage.home,
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: AethGeometry.refHeight * s,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ---- top bar: info (Telegram) · title · back
                          _enter(
                            t,
                            0,
                            Positioned(
                              top: AethGeometry.topSafeExtraGap * s,
                              left: AethGeometry.pageHPadding * s,
                              right: AethGeometry.pageHPadding * s,
                              child: _PageTopBar(
                                onInfo: _openTelegram,
                                onBack: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                          // ---- «حالت اتصال» + the تونل/پروکسی segments
                          _enter(
                            t,
                            1,
                            Positioned(
                              top: AethGeometry.protoPageHeadingModeTop * s,
                              left: 0,
                              right: 0,
                              child: _SheetHeadingRow(
                                text: strings.sheetHeadingMode,
                                badge: AppAssets.iconPassword1,
                              ),
                            ),
                          ),
                          _enter(
                            t,
                            1,
                            Positioned(
                              top: AethGeometry.protoSegmentTop * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _ModeSegments(
                                selected: widget.store.connectionMode,
                                onSelect: widget.store.setConnectionMode,
                              ),
                            ),
                          ),
                          // ---- «پروتکل» + the 3+3 tiles + family cards
                          _enter(
                            t,
                            2,
                            Positioned(
                              top:
                                  AethGeometry.protoPageHeadingProtocolTop * s,
                              left: 0,
                              right: 0,
                              child: _SheetHeadingRow(
                                text: strings.protocol, // «پروتکل» verbatim
                                badge: AppAssets.iconSwap1,
                              ),
                            ),
                          ),
                          _enter(
                            t,
                            3,
                            Positioned(
                              top: AethGeometry.protoTileRow1Top * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _TileRow(
                                ids: const [
                                  ProtocolId.auto,
                                  ProtocolId.masque,
                                  ProtocolId.wireguard,
                                ],
                                labels: [
                                  strings.protoAutoSheet,
                                  strings.protocolName(ProtocolId.masque),
                                  strings.protocolName(ProtocolId.wireguard),
                                ],
                                // v4.21 — the single-knob highlight: a
                                // family selection means NO plain tile is
                                // active (the v4.20 double-green is gone).
                                selected: _plainHighlight,
                                pulse: _pulseId,
                                onSelect: _select,
                                onInfo: _openDesc,
                              ),
                            ),
                          ),
                          _enter(
                            t,
                            4,
                            Positioned(
                              top: AethGeometry.protoTileRow2Top * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _TileRow(
                                ids: const [
                                  ProtocolId.gool,
                                  ProtocolId.goolClassic,
                                  ProtocolId.mim,
                                ],
                                labels: [
                                  strings.protocolName(ProtocolId.gool),
                                  strings.protocolName(ProtocolId.goolClassic),
                                  strings.protocolName(ProtocolId.mim),
                                ],
                                // v4.21 — the single-knob highlight.
                                selected: _plainHighlight,
                                pulse: _pulseId,
                                onSelect: _select,
                                onInfo: _openDesc,
                              ),
                            ),
                          ),
                          _enter(
                            t,
                            5,
                            Positioned(
                              top: AethGeometry.protoCardTopPsiphon * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _FamilyCard(
                                family: const [
                                  ProtocolId.psiphonOnly,
                                  ProtocolId.psiphonChain,
                                  ProtocolId.psiphonReverse,
                                ],
                                label:
                                    strings.protocolName(ProtocolId.psiphonChain),
                                logoAsset: AppAssets.protocolPsiphonLogo,
                                // v4.21 — the single-knob selection: the
                                // card highlights only when one of ITS
                                // members is the committed protocol.
                                selected: widget.store.selectedProtocol,
                                pulse: _pulseId,
                                onSelect: _select,
                                onInfo: _openDesc,
                                infoId: ProtocolId.psiphonChain,
                              ),
                            ),
                          ),
                          _enter(
                            t,
                            6,
                            Positioned(
                              top: AethGeometry.protoCardTopTor * s,
                              left: AethGeometry.protoRightInset * s,
                              right: AethGeometry.protoRightInset * s,
                              child: _FamilyCard(
                                family: const [
                                  ProtocolId.torOnly,
                                  ProtocolId.torChain,
                                  ProtocolId.torReverse,
                                ],
                                label:
                                    strings.protocolName(ProtocolId.torChain),
                                logoAsset: AppAssets.protocolTorLogo,
                                // v4.21 — the single-knob selection.
                                selected: widget.store.selectedProtocol,
                                pulse: _pulseId,
                                onSelect: _select,
                                onInfo: _openDesc,
                                infoId: ProtocolId.torChain,
                              ),
                            ),
                          ),
                          // ---- «سرعت اسکن» + the 5 pills
                          _enter(
                            t,
                            7,
                            Positioned(
                              top: AethGeometry.protoPageHeadingScanTop * s,
                              left: 0,
                              right: 0,
                              child: _SheetHeadingRow(
                                text: strings.sheetHeadingScanSpeed,
                                badge: AppAssets.iconScan1,
                              ),
                            ),
                          ),
                          _enter(
                            t,
                            7,
                            Positioned(
                              top: AethGeometry.protoPillTop * s,
                              left: 0,
                              right: 0,
                              child: _ScanPills(
                                selected: widget.store.scanSpeed,
                                onSelect: widget.store.setScanSpeed,
                              ),
                            ),
                          ),
                          // ---- the ⓘ descriptions popup
                          if (_descFor != null)
                            _DescLayer(
                              forId: _descFor!,
                              onClose: _closeDesc,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The stagger wrapper (kept from the sheet — owner: «انیمیشن های فعلی رو
  /// حذف نکن»): block [i] slides up 22px + fades on its own slice of the
  /// route timeline (starts i*0.075, 0.55 wide, easeOutCubic). On reverse
  /// the same slices retrace — the page folds away gently.
  Widget _enter(double t, int block, Widget child) {
    final start = (block * 0.075).clamp(0.0, 0.45);
    final bt =
        Curves.easeOutCubic.transform(Interval(start, start + 0.55).transform(t));
    if (bt >= 0.999) return child;

    // The animation must live INSIDE the Positioned (ParentData rule:
    // Positioned has to stay a DIRECT Stack child), so a Positioned child
    // is unwrapped, animated, and re-wrapped with identical bounds.
    final pd = child is Positioned ? child : null;
    final inner = pd?.child ?? child;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final animated = Opacity(
      opacity: bt,
      child: Transform.translate(
        offset: Offset(0, (1 - bt) * 22 * s),
        child: inner,
      ),
    );
    if (pd == null) return animated;
    return Positioned(
      left: pd.left,
      top: pd.top,
      right: pd.right,
      bottom: pd.bottom,
      width: pd.width,
      height: pd.height,
      child: animated,
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — the settings page's own chrome around the title, «Rectangle 9»
// 50×50 tiles. v4.19: the owner swapped the tile slots. The Row runs under
// the app's RTL directionality — the FIRST child renders on the visual
// RIGHT: back first (visual RIGHT), info second (visual LEFT).
// ---------------------------------------------------------------------------

class _PageTopBar extends StatelessWidget {
  const _PageTopBar({required this.onInfo, required this.onBack});

  final VoidCallback onInfo;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final tile = AethGeometry.topTileSize * s;
    return SizedBox(
      height: tile,
      child: Row(
        children: [
          // FIRST child → visual RIGHT (RTL row): the back chevron tile
          // (owner v4.19: slots swapped with the info tile).
          _TileButton(
            key: const ValueKey('proto-page-back'),
            asset: AppAssets.iconRight2,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
          const Spacer(),
          Text(
            strings.protocolPageTitle,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w700,
              fontSize: 17 * s,
              color: AethColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Visual LEFT: the info tile (i → Telegram channel).
          _TileButton(
            key: const ValueKey('proto-page-info'),
            asset: AppAssets.iconInformationCircle,
            size: tile,
            iconSize: AethGeometry.topTileIcon * s,
            semanticLabel: 'Telegram channel',
            onTap: onInfo,
          ),
        ],
      ),
    );
  }
}

/// The owner «Rectangle 9» tile (50×50, #0F1510, r16, soft shadow) — the
/// exact same tile as the settings/home top bars.
class _TileButton extends StatelessWidget {
  const _TileButton({
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
            borderRadius:
                BorderRadius.circular(AethGeometry.topTileRadius * s),
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

// ---------------------------------------------------------------------------
// Section heading row: «TEXT … [badge]» — text 16 w700 white.
// v4.17 — the badge grows 20 → 26 and the text sits 12 (was 26) from it.
// ---------------------------------------------------------------------------

class _SheetHeadingRow extends StatelessWidget {
  const _SheetHeadingRow({required this.text, required this.badge});

  final String text;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // LTR-locked geometry (the settings-page precedent): the badge hugs the
    // visual RIGHT edge, the Persian text right-aligned to its left.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          const Spacer(),
          Padding(
            // Text right edge = [protoHeadingTextRightInset] from the screen
            // right (66 = badge 26 + gap 12 + inset 28).
            padding: EdgeInsets.only(
              right: AethGeometry.protoHeadingBadgeGap * s,
            ),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoHeadingTextSize * s,
                color: AethColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: AethGeometry.protoRightInset * s),
            child: SvgPicture.asset(
              badge,
              width: AethGeometry.protoBadgeSize * s,
              height: AethGeometry.protoBadgeSize * s,
              colorFilter: const ColorFilter.mode(
                AethColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// «حالت اتصال» segments: h35 r14 gap21; RTL order تونل (right/first) then
// پروکسی. Selected = #1AD995 fill, unselected = #0F1511; WHITE text on both
// (measured: «پروکسی» ink is white on the green segment).
// ---------------------------------------------------------------------------

class _ModeSegments extends StatelessWidget {
  const _ModeSegments({
    required this.selected,
    required this.onSelect,
  });

  final ConnectionMode selected;
  final void Function(ConnectionMode) onSelect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);
    final h = AethGeometry.protoSegmentH * s;
    final r = AethGeometry.protoSegmentRadius * s;

    Widget segment(ConnectionMode mode, String label) {
      final isSel = selected == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            height: h,
            decoration: BoxDecoration(
              color: isSel ? AethColors.accentConnected : AethColors.cardDark,
              borderRadius: BorderRadius.circular(r),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: AethGeometry.protoSegmentTextSize * s,
                color: AethColors.textPrimary, // white on BOTH (measured)
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          segment(ConnectionMode.tunnel, strings.modeTunnel),
          SizedBox(width: AethGeometry.protoSegmentGap * s),
          segment(ConnectionMode.proxy, strings.modeProxy),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Protocol tiles: r21 (v4.17 — the settings cards' corners); ⓘ 15×15 visual
// inside a 32×32 invisible hit box at the same corner; icon center at
// top+41; label 12 w500 at top+66. Unselected: #0F1511 + native icon colors
// (white / gold) + white label. Selected: #1AD995 + all-white glyph.
// ---------------------------------------------------------------------------

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.ids,
    required this.labels,
    required this.selected,
    required this.pulse,
    required this.onSelect,
    required this.onInfo,
  });

  final List<ProtocolId> ids;
  final List<String> labels;

  /// v4.21 — nullable: the single-knob highlight shows NO plain tile when
  /// a family member is committed.
  final ProtocolId? selected;
  final ProtocolId? pulse;
  final void Function(ProtocolId) onSelect;
  final void Function(ProtocolId) onInfo;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, // first child at the visual RIGHT
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < ids.length; i++)
            _ProtoTile(
              id: ids[i],
              label: labels[i],
              isSelected: selected == ids[i],
              pulsing: pulse == ids[i],
              onSelect: onSelect,
              onInfo: onInfo,
            ),
        ],
      ),
    );
  }
}

class _ProtoTile extends StatefulWidget {
  const _ProtoTile({
    required this.id,
    required this.label,
    required this.isSelected,
    required this.pulsing,
    required this.onSelect,
    required this.onInfo,
  });

  final ProtocolId id;
  final String label;
  final bool isSelected;
  final bool pulsing;
  final void Function(ProtocolId) onSelect;
  final void Function(ProtocolId) onInfo;

  /// The 32×32 hit box is centred on the 15×15 visual badge so the visual
  /// position never moves: visual centre (11+7.5, 9+7.5) = (18.5, 16.5)
  /// ⇒ hit-box top-left (18.5−16, 16.5−16) = (2.5, 0.5).
  static double get _infoHitLeft =>
      AethGeometry.protoInfoBadgeInset +
      AethGeometry.protoInfoBadgeSize / 2 -
      AethGeometry.protoInfoHit / 2;
  static double get _infoHitTop =>
      AethGeometry.protoInfoBadgeInset -
      2 +
      AethGeometry.protoInfoBadgeSize / 2 -
      AethGeometry.protoInfoHit / 2;

  @override
  State<_ProtoTile> createState() => _ProtoTileState();
}

class _ProtoTileState extends State<_ProtoTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    lowerBound: 0.97,
  );

  @override
  void didUpdateWidget(covariant _ProtoTile old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !old.pulsing) {
      _pulse.forward(); // 0.97 → 1.0 spring-ish settle
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final w = AethGeometry.protoTileW * s;
    final iconBox = _tileIconBox(widget.id);

    return SizedBox(
      width: w,
      height: AethGeometry.protoTileRow1H * s,
      child: ScaleTransition(
        scale: _pulse,
        child: GestureDetector(
          key: ValueKey('proto-tile-${widget.id.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(widget.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AethColors.accentConnected
                  : AethColors.cardDark,
              borderRadius:
                  BorderRadius.circular(AethGeometry.protoTileRadius * s),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ⓘ info badge — 15×15 visual at (11,9) inside a 32×32
                // invisible hit box (v4.17: the badge was hard to tap; the
                // visual position is unchanged, only the tap target grew).
                Positioned(
                  left: _ProtoTile._infoHitLeft * s,
                  top: _ProtoTile._infoHitTop * s,
                  width: AethGeometry.protoInfoHit * s,
                  height: AethGeometry.protoInfoHit * s,
                  child: _InfoBadge(onTap: () => widget.onInfo(widget.id)),
                ),
                // Icon — center at top+41 (measured cy 342 on row 1).
                Positioned(
                  left: 0,
                  right: 0,
                  top: (AethGeometry.protoTileIconCenter - iconBox / 2) * s,
                  child: Center(
                    child: _ProtocolGlyph(
                      id: widget.id,
                      box: iconBox,
                      white: widget.isSelected,
                    ),
                  ),
                ),
                // Label — 12 w5, center at top+66 (measured cy 368).
                Positioned(
                  left: 0,
                  right: 0,
                  top: (AethGeometry.protoTileLabelCenter - 6) * s,
                  child: Center(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w500,
                        fontSize: AethGeometry.protoTileLabelSize * s,
                        color: AethColors.textPrimary,
                      ),
                    ),
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

/// The ⓘ badge: 15×15 white Information Circle glyph + a generous opaque
/// tap area (the parent Positioned sizes the hit box).
class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: SvgPicture.asset(
          AppAssets.iconInformationCircle,
          width: AethGeometry.protoInfoBadgeSize * s,
          height: AethGeometry.protoInfoBadgeSize * s,
          colorFilter: const ColorFilter.mode(
            AethColors.textPrimary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

/// Per-protocol tile icon boxes, calibrated so the final GLYPH matches the
/// frame (each SVG carries its own ink ratio — the settings-page recipe).
/// v4.17 — owner: ماسک و وایرگارد «هم بزرگه هم اندازه سایر آیکون ها باید
/// باشن» — 38/37 → 28, the gool/gool-classic box.
double _tileIconBox(ProtocolId id) => switch (id) {
      ProtocolId.auto => 26,
      ProtocolId.masque => 28,
      ProtocolId.wireguard => 28,
      ProtocolId.gool => 28,
      ProtocolId.goolClassic => 28,
      ProtocolId.mim => 32,
      _ => 30, // families never render on the tile grid
    };

// ---------------------------------------------------------------------------
// One protocol glyph at a calibrated box. SVGs render in their NATIVE
// colors (white / #997A35 gold — exactly how the frame colours them);
// PNGs (psiphon/tor) are tinted white. `white` forces the all-white
// treatment the frame uses on the SELECTED (green) surface.
// ---------------------------------------------------------------------------

class _ProtocolGlyph extends StatelessWidget {
  const _ProtocolGlyph({
    required this.id,
    required this.box,
    this.white = false,
  });

  final ProtocolId id;
  final double box;
  final bool white;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final asset = AppAssets.protocolIcon(id);
    final isRaster = AppAssets.isRasterAsset(asset);
    final w = box * s;

    if (id == ProtocolId.auto) {
      // AUTO has no dedicated artwork (report §6.9): Shield Tick, gold —
      // the frame's gold shield.
      return SvgPicture.asset(
        AppAssets.iconShieldTick,
        width: w,
        height: w,
        colorFilter: ColorFilter.mode(
          white ? AethColors.textPrimary : AethColors.goldAccent,
          BlendMode.srcIn,
        ),
      );
    }
    if (isRaster) {
      return Image.asset(
        asset,
        width: w,
        height: w,
        fit: BoxFit.contain,
        color: white ? AethColors.textPrimary : Colors.white,
        colorBlendMode: BlendMode.srcIn,
      );
    }
    if (white) {
      return SvgPicture.asset(
        asset,
        width: w,
        height: w,
        colorFilter: const ColorFilter.mode(
          AethColors.textPrimary,
          BlendMode.srcIn,
        ),
      );
    }
    return SvgPicture.asset(asset, width: w, height: w);
  }
}

// ---------------------------------------------------------------------------
// Family cards (سایفون/تور): v4.17 breathing — h116 r21 #0F1511, subtiles
// 66×66 r14 #1A261C vertically centred (inset 25), gaps 20. Visual LEFT→
// RIGHT (the frame's own reading): [main logo+label] gap [plain=only] gap
// [Aether+∨=chain] gap [Aether+∧=reverse].
// ---------------------------------------------------------------------------

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.family,
    required this.label,
    required this.logoAsset,
    required this.selected,
    required this.pulse,
    required this.onSelect,
    required this.onInfo,
    required this.infoId,
  });

  /// Visual order [only, chain, reverse] — matches the frame's subtiles.
  final List<ProtocolId> family;
  final String label;
  final String logoAsset;

  /// v4.20 — the CHAIN overlay selection (null = no overlay active).
  final ProtocolId? selected;
  final ProtocolId? pulse;
  final void Function(ProtocolId) onSelect;
  final void Function(ProtocolId) onInfo;

  /// The id the ⓘ opens descriptions for (a family representative).
  final ProtocolId infoId;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final bool isPsiphon = family.first.isPsiphon;

    return SizedBox(
      key: ValueKey('proto-card-${family.first.isPsiphon ? 'psiphon' : 'tor'}'),
      height: AethGeometry.protoCardH * s,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AethColors.cardDark,
          borderRadius:
              BorderRadius.circular(AethGeometry.protoCardRadius * s),
        ),
        child: Directionality(
          // LTR by design: the main block sits at the visual LEFT, the
          // three subtiles to its right (frame-measured zone).
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              // ---- main block (logo center top+43, label 12 at top+80)
              SizedBox(
                width: AethGeometry.protoMainBlockW * s,
                child: Stack(
                  children: [
                    Positioned(
                      left: _ProtoTile._infoHitLeft * s,
                      top: _ProtoTile._infoHitTop * s,
                      width: AethGeometry.protoInfoHit * s,
                      height: AethGeometry.protoInfoHit * s,
                      child: _InfoBadge(onTap: () => onInfo(infoId)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (AethGeometry.protoMainLogoCenterY - 28) * s,
                      child: Center(
                        child: Image.asset(
                          logoAsset,
                          height: (isPsiphon ? 56 : 42) * s,
                          fit: BoxFit.contain,
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (AethGeometry.protoMainLabelCenterY - 6) * s,
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'IRANYekanX',
                            fontWeight: FontWeight.w500,
                            fontSize: AethGeometry.protoTileLabelSize * s,
                            color: AethColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // NO separator: the main zone + 3 subtiles + gaps exactly
              // fill the 346 card (95 + 3×66 + 2×20 + 13 inset).
              for (final id in family)
                Padding(
                  padding: EdgeInsets.only(
                    right:
                        id == family.last ? 0 : AethGeometry.protoSubtileGap * s,
                  ),
                  child: _SubTile(
                    id: id,
                    isPsiphon: isPsiphon,
                    isSelected: selected == id,
                    pulsing: pulse == id,
                    onSelect: onSelect,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTile extends StatefulWidget {
  const _SubTile({
    required this.id,
    required this.isPsiphon,
    required this.isSelected,
    required this.pulsing,
    required this.onSelect,
  });

  final ProtocolId id;
  final bool isPsiphon;
  final bool isSelected;
  final bool pulsing;
  final void Function(ProtocolId) onSelect;

  @override
  State<_SubTile> createState() => _SubTileState();
}

class _SubTileState extends State<_SubTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    lowerBound: 0.95,
  );

  @override
  void didUpdateWidget(covariant _SubTile old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !old.pulsing) _pulse.forward();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final chain = widget.id.isPsiphon
        ? widget.id == ProtocolId.psiphonChain
        : widget.id == ProtocolId.torChain;
    final reverse = widget.id.isPsiphon
        ? widget.id == ProtocolId.psiphonReverse
        : widget.id == ProtocolId.torReverse;

    return ScaleTransition(
      scale: _pulse,
      child: GestureDetector(
        key: ValueKey('proto-subtile-${widget.id.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(widget.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: AethGeometry.protoSubtile * s,
          height: AethGeometry.protoSubtile * s,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AethColors.accentConnected
                : AethColors.sheetSubtile,
            borderRadius:
                BorderRadius.circular(AethGeometry.protoSubtileRadius * s),
          ),
          child: Center(
            child: _StackGlyph(
              protocol: widget.id,
              chain: chain,
              reverse: reverse,
              white: widget.isSelected,
              scale: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The stack glyph language (frame-measured): plain = the protocol glyph
// alone; chain/reverse = [Aether logo ~18×19] +7 [chevron 14×6] +6
// [protocol glyph ~16×20]. The Aether mark is the app logo 3.svg (white)
// — pixel-matched to the frame's stack-top glyph. `scale` grows it for the
// descriptions popup (×1.45).
// ---------------------------------------------------------------------------

class _StackGlyph extends StatelessWidget {
  const _StackGlyph({
    required this.protocol,
    required this.chain,
    required this.reverse,
    this.white = false,
    this.scale = 1.0,
  });

  final ProtocolId protocol;
  final bool chain;
  final bool reverse;

  /// All-white treatment (selected surfaces — measured on the frame).
  final bool white;

  final double scale;

  // Canvas-honest layout. The family PNGs carry big transparent margins
  // (psiphon ink = 47%×64% of its 128-canvas; tor = 57%×86% of 42-box), so
  // the glyph BOX is larger than its ink. The LAYOUT gaps are compensated
  // so the VISUAL ink-to-ink gaps land on the frame's ~7 / ~6 and the
  // whole stack totals ≈59 ink-height inside the 66 box (measured):
  //   psiphon: box 31.2 (ink 14.6×20), gaps 6.7 / 0.4
  //   tor:     box 26.3 (ink 15×22.5), gaps 6.7 / 4.1
  // (aether canvas 20 ≈ its ink — only ~0.2 pad.)
  static const double _psiphonBox = 31.2;
  static const double _psiphonG1 = 6.7;
  static const double _psiphonG2 = 0.4;
  static const double _torBox = 26.3;
  static const double _torG1 = 6.7;
  static const double _torG2 = 4.1;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final isPsiphon = protocol.isPsiphon;
    final box = (isPsiphon ? _psiphonBox : _torBox) * scale;
    final glyph = _ProtocolGlyph(id: protocol, box: box, white: white);
    if (!chain && !reverse) return glyph; // plain = ONLY

    final k = s * scale;
    final aether = SvgPicture.asset(
      AppAssets.appLogoNeutralWhite,
      width: 20 * k,
      height: 20 * k,
    );
    final chevron = _StackChevron(
      up: reverse,
      width: 14 * k,
      height: 6 * k,
      color: white ? AethColors.textPrimary : Colors.white,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        aether,
        SizedBox(height: (isPsiphon ? _psiphonG1 : _torG1) * k),
        chevron,
        SizedBox(height: (isPsiphon ? _psiphonG2 : _torG2) * k),
        glyph,
      ],
    );
  }
}

/// The stack chevron — 14×6, 2px round-cap strokes (drawn once here in the
/// set's linear style; custom drawing precedent D7, documented).
class _StackChevron extends StatelessWidget {
  const _StackChevron({
    required this.up,
    required this.width,
    required this.height,
    required this.color,
  });

  final bool up;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _StackChevronPainter(up, color),
    );
  }
}

class _StackChevronPainter extends CustomPainter {
  _StackChevronPainter(this.up, this.color);

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.06, up ? h * 0.85 : h * 0.15)
      ..lineTo(w * 0.5, up ? h * 0.28 : h * 0.72)
      ..lineTo(w * 0.94, up ? h * 0.85 : h * 0.15);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StackChevronPainter old) =>
      old.up != up || old.color != color;
}

// ---------------------------------------------------------------------------
// «سرعت اسکن» pills: 5 increasing widths 28/47/64/77/87, h36 r8 gap8,
// CENTERED (the row spans x33..367). The widest (rightmost) is selected in
// the frame.
// ---------------------------------------------------------------------------

class _ScanPills extends StatelessWidget {
  const _ScanPills({required this.selected, required this.onSelect});

  final int selected;
  final void Function(int) onSelect;

  static const List<double> _w = [
    AethGeometry.protoPillW1,
    AethGeometry.protoPillW2,
    AethGeometry.protoPillW3,
    AethGeometry.protoPillW4,
    AethGeometry.protoPillW5,
  ];

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final h = AethGeometry.protoPillH * s;
    final r = AethGeometry.protoPillRadius * s;

    return Center(
      child: Directionality(
        // RTL with children 5→1: the FIRST child (the widest, level 5)
        // lands at the visual RIGHT — the frame's reading (87 selected at
        // x281..367, then 77/64/47/28 toward the left).
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var level = 5; level >= 1; level--)
              Padding(
                padding: EdgeInsets.only(
                  left: level == 1 ? 0 : AethGeometry.protoPillGap * s,
                ),
                child: GestureDetector(
                  key: ValueKey('proto-pill-$level'),
                  onTap: () => onSelect(level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    width: _w[level - 1] * s,
                    height: h,
                    decoration: BoxDecoration(
                      color: selected == level
                          ? AethColors.accentConnected
                          : AethColors.cardDark,
                      borderRadius: BorderRadius.circular(r),
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
// The ⓘ descriptions popup: × Ø30 at y206 (v4.17 — bigger, easy hit), the
// card r24 #0C120F over a 94% #0C120F scrim (v4.17 — «باید تیره باشه تا
// متنش قابل خوندن باشه»), blocks 14px/lh18 white + dividers #1A261C, icon
// column on the right (plain / Aether+∨ / Aether+∧ — the subtile language
// ×1.45).
// ---------------------------------------------------------------------------

class _DescLayer extends StatelessWidget {
  const _DescLayer({required this.forId, required this.onClose});

  final ProtocolId forId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final strings = AppStrings.of(context);

    final bool isFamily = forId.isPsiphon || forId.isTor;
    // v4.20 — every block carries its mode's LOCAL SOCKS PORT (evidence:
    // transport_modes.dart endpoints; cli.rs L23/L239/L282) so the owner
    // can see which port each mode actually serves on a device (owner
    // round 2: tested 1820 while the psiphon chain serves 1821).
    final blocks = <({String text, bool chain, bool reverse, int port})>[
      if (isFamily) ...[
        (
          text: forId.isPsiphon ? strings.descPsiphonOnly : strings.descTorOnly,
          chain: false,
          reverse: false,
          port: 1819,
        ),
        (
          text: forId.isPsiphon
              ? strings.descPsiphonChain
              : strings.descTorChain,
          chain: true,
          reverse: false,
          port: forId.isPsiphon ? 1821 : 1820,
        ),
        (
          text: forId.isPsiphon
              ? strings.descPsiphonReverse
              : strings.descTorReverse,
          chain: true,
          reverse: true,
          port: 1819,
        ),
      ] else
        (
          text: switch (forId) {
            ProtocolId.auto => strings.descAuto,
            ProtocolId.masque => strings.descMasque,
            ProtocolId.wireguard => strings.descWireguard,
            ProtocolId.gool => strings.descGool,
            ProtocolId.goolClassic => strings.descGoolClassic,
            ProtocolId.mim => strings.descMim,
            _ => strings.descMasque,
          },
          chain: false,
          reverse: false,
          port: 1819,
        ),
    ];
    assert(
      !isFamily ||
          blocks.every(
            (b) => b.port == TransportModes.byId(
              // The glyph language: reverse implies a stacked (chain) glyph
              // with an inverted chevron — derive the MODE reverse-first.
              forId.isPsiphon
                  ? (b.reverse
                        ? ProtocolId.psiphonReverse
                        : b.chain
                        ? ProtocolId.psiphonChain
                        : ProtocolId.psiphonOnly)
                  : (b.reverse
                        ? ProtocolId.torReverse
                        : b.chain
                        ? ProtocolId.torChain
                        : ProtocolId.torOnly),
            ).socksEndpoint.port,
          ),
      'desc-popup ports must mirror transport_modes.dart',
    );

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          if (t < 0.01) return const SizedBox.shrink();
          return Stack(
            children: [
              // Second scrim over the page (v4.17 — deepened to 94% so the
              // description text reads on the dark card).
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Opacity(
                    opacity: t,
                    child: const ColoredBox(
                      color: Color(0xF20C120F), // #0C120F @ 95%
                    ),
                  ),
                ),
              ),
              // × close — Ø30 thin white ring + the set's Close.svg
              Positioned(
                top: AethGeometry.protoDescCloseTop * s,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Container(
                      width: AethGeometry.protoDescCloseSize * s,
                      height: AethGeometry.protoDescCloseSize * s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AethColors.cardDark,
                        border: Border.all(
                          color: AethColors.textPrimary.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: SvgPicture.asset(
                        AppAssets.iconClose,
                        width: 13 * s,
                        height: 13 * s,
                        colorFilter: const ColorFilter.mode(
                          AethColors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // the card
              Positioned(
                top: AethGeometry.protoDescCardTop * s,
                left: AethGeometry.protoRightInset * s,
                right: AethGeometry.protoRightInset * s,
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.96 + 0.04 * t,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              ),
            ],
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AethColors.sheetDescCard,
            borderRadius:
                BorderRadius.circular(AethGeometry.protoDescCardRadius * s),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 32 * s,
                      vertical: 10 * s,
                    ),
                    child: Container(
                      height: 1,
                      color: AethColors.sheetSubtile,
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    32 * s, // left text pad (frame: text starts x≈60)
                    i == 0 ? 24 * s : 8 * s,
                    30 * s + 22 * s + 12 * s, // pad + icon column + gap
                    i == blocks.length - 1 ? 24 * s : 8 * s,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              blocks[i].text,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'IRANYekanX',
                                fontWeight: FontWeight.w400,
                                fontSize: AethGeometry.protoDescTextSize * s,
                                height: AethGeometry.protoDescTextHeight /
                                    AethGeometry.protoDescTextSize,
                                color: AethColors.textPrimary,
                              ),
                            ),
                            // v4.20 — the mode's local SOCKS port (honest
                            // label, Latin digits like the ping labels).
                            SizedBox(height: 4 * s),
                            Text(
                              strings.protocolPortNote(blocks[i].port),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: 'IRANYekanX',
                                fontWeight: FontWeight.w500,
                                fontSize:
                                    (AethGeometry.protoDescTextSize - 2) * s,
                                height: 1.3,
                                color: AethColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12 * s),
                      SizedBox(
                        width: 22 * s,
                        child: _StackGlyph(
                          protocol: forId,
                          chain: blocks[i].chain,
                          reverse: blocks[i].reverse,
                          scale: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
