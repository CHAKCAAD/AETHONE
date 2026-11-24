/// v6 — THE LOGIN STEP BODIES («صفحه ورود», the owner's five committed
/// frames ورود1..ورود5, 402×874 @3× — every value measured on them):
///
///  * the WELCOME and DONE steps carry the frames' centred title (19/w500
///    #141C16 at y 574) over the justified description block (256 wide,
///    15/w300, 20 line-height, at y 635);
///
///  * the LANGUAGE step is the five flag circles — us/tm/ir on the top
///    row (centres 120/201/282), ru/cn below (159/244) — and the ROUTING
///    step the four (tm/ir at 161/242, ru/cn at 157/242). The owner's
///    selection rule rides every option: «گزینه هایی که انتخاب میشن رنگی
///    هستن اما گزینه هایی که حالت انتخاب ندارند سیاه و سفید هستند» —
///    SELECTED renders the full-color flag face, UNSELECTED the baked
///    grayscale one (the frames' own soft grays);
///
///  * the LOOK step («ضاهر برنامه») is the two home previews: the look-2
///    GLOW composition (the frame's «Group 45» at the 0.75 scale — 120/99
///    r43/32 green rings + the 81 r27 gradient core with the white Off
///    glyph) at x 120, and the look-1 HERO logo artwork (3.svg, ink
///    91×101) at x 272 — gray when unselected, the standing green
///    gradient when picked;
///
///  * every block enters with the app's own cascade (the recipe's rise/
///    curve/zoom, the onboarding flavor's boosted rise), replayed on each
///    step change — «جابه جایی بین مراحل باید انیمیشن ایجاد کنه».
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';

// ---------------------------------------------------------------------------
// The staggered entrance every step body shares.
// ---------------------------------------------------------------------------

/// One block of a step body's cascade: rises, fades and (per the ambient
/// style's recipe) zooms in on its own slice of a one-shot timeline —
/// [motionCascade]'s choreography re-cut for a step change (no route
/// involved), with the onboarding flavor's boosted rise.
class _StepBlock extends StatefulWidget {
  const _StepBlock({required this.index, required this.child});

  /// The cascade slot (0 = the title, then each content row).
  final int index;
  final Widget child;

  @override
  State<_StepBlock> createState() => _StepBlockState();
}

class _StepBlockState extends State<_StepBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  bool _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    final style = MotionScope.of(context);
    _c.duration = motionDuration(style, 560);
    if (style == MotionStyle.off) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MotionScope.of(context);
    if (style == MotionStyle.off || _c.isCompleted) return widget.child;
    final r = style.recipe;
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final start = (widget.index * 0.11).clamp(0.0, 0.45);
        final end = math.min(1.0, start + 0.55);
        final t =
            r.blockCurve.transform(Interval(start, end).transform(_c.value));
        if (t >= 0.999) return child!;
        Widget node = child!;
        // EntranceFlavor.onboarding's rise boost (recipe rise ×1.3 + 6).
        if (r.blockRise > 0) {
          node = Transform.translate(
            offset: Offset(0, (1 - t) * (r.blockRise * 1.3 + 6) * s),
            child: node,
          );
        }
        if (r.blockScaleFrom < 1) {
          node = Transform.scale(
            scale: r.blockScaleFrom + (1 - r.blockScaleFrom) * t,
            child: node,
          );
        }
        return Opacity(opacity: t, child: node);
      },
      child: widget.child,
    );
  }
}

/// The shared title block — 19/w500 [AethColors.loginInk], centred at the
/// frames' y 574, following the app locale's own bidi direction.
class _LoginTitle extends StatelessWidget {
  const _LoginTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Text(
      text,
      textAlign: TextAlign.center,
      textDirection: appContentDirection(context),
      style: TextStyle(
        fontFamily: 'IRANYekanX',
        fontWeight: FontWeight.w500,
        fontSize: AethGeometry.loginTitleSize * s,
        color: AethColors.loginInk,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The welcome / done steps — the title over the justified description.
// ---------------------------------------------------------------------------

class LoginDescriptionBody extends StatelessWidget {
  const LoginDescriptionBody({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: AethGeometry.loginTitleTop * s,
          left: 0,
          right: 0,
          child: _StepBlock(index: 0, child: Center(child: _LoginTitle(title))),
        ),
        Positioned(
          top: AethGeometry.loginDescTop * s,
          left: 0,
          right: 0,
          child: _StepBlock(
            index: 1,
            child: Center(
              child: SizedBox(
                width: AethGeometry.loginDescW * s,
                child: Text(
                  description,
                  textAlign: TextAlign.justify,
                  textDirection: appContentDirection(context),
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w300,
                    fontSize: AethGeometry.loginDescSize * s,
                    height: AethGeometry.loginDescLineH,
                    color: AethColors.loginDescInk,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The flag circles — the owner's colored/gray selection rule.
// ---------------------------------------------------------------------------

/// One 48 px flag circle: the full-color face when selected, the baked
/// grayscale face when not (a soft crossfade + a one-shot scale bump on
/// the pick — «به حالت انتخاب گزینه ها دقت کن»).
class LoginFlagButton extends StatefulWidget {
  const LoginFlagButton({
    super.key,
    required this.keyId,
    required this.code,
    required this.selected,
    required this.onTap,
  });

  final String keyId;

  /// The flag ASSET code (e.g. `us` — the language it stands for is the
  /// caller's business, the key carries it).
  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<LoginFlagButton> createState() => _LoginFlagButtonState();
}

class _LoginFlagButtonState extends State<LoginFlagButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  MotionStyle? _style;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _style ??= MotionScope.of(context);
  }

  @override
  void didUpdateWidget(LoginFlagButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      final style = _style ?? MotionStyle.standard;
      _pulse.duration = motionDuration(style, 340);
      if (style != MotionStyle.off) _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style ?? MotionScope.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final size = AethGeometry.loginFlagSize * s;
    final fade = motionDuration(style, MotionDurations.quick);
    final curve = style == MotionStyle.off ? Curves.linear : Curves.easeOutCubic;
    return Semantics(
      label: widget.keyId,
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        key: ValueKey(widget.keyId),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AethHaptics.tap();
          widget.onTap();
        },
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final bump = 0.07 * math.sin(math.pi * _pulse.value);
              return bump == 0
                  ? child!
                  : Transform.scale(scale: 1 + bump, child: child!);
            },
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The B&W face (the frames' unselected state).
                  AnimatedOpacity(
                    duration: fade,
                    curve: curve,
                    opacity: widget.selected ? 0 : 1,
                    child: Image.asset(
                      AppAssets.loginFlagGray(widget.code),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                  // The colored face — selected = رنگی.
                  AnimatedOpacity(
                    duration: fade,
                    curve: curve,
                    opacity: widget.selected ? 1 : 0,
                    child: Image.asset(
                      AppAssets.flag(widget.code),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The language step's five circles — us/tm/ir (row 1, pitch 81), ru/cn
/// (row 2, pitch 85), bound LIVE to [ConnectionStore.appLocale] (the
/// fresh-install default is 'fa', applied at restore).
class LoginLanguageBody extends StatelessWidget {
  const LoginLanguageBody({super.key, required this.store, required this.title});

  final ConnectionStore store;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final current = store.appLocale ?? 'fa';
    LoginFlagButton flag(String code, String locale) => LoginFlagButton(
          keyId: 'login-lang-$locale',
          code: code,
          selected: current == locale,
          onTap: () => store.setAppLocale(locale),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: AethGeometry.loginTitleTop * s,
          left: 0,
          right: 0,
          child: _StepBlock(index: 0, child: Center(child: _LoginTitle(title))),
        ),
        Positioned(
          top: AethGeometry.loginLangRow1Top * s,
          left: 0,
          right: 0,
          child: _StepBlock(
            index: 1,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  flag('us', 'en'),
                  SizedBox(
                    width:
                        (AethGeometry.loginLangRow1Pitch -
                            AethGeometry.loginFlagSize) *
                        s,
                  ),
                  flag('tm', 'tk'),
                  SizedBox(
                    width:
                        (AethGeometry.loginLangRow1Pitch -
                            AethGeometry.loginFlagSize) *
                        s,
                  ),
                  flag('ir', 'fa'),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: AethGeometry.loginLangRow2Top * s,
          left: 0,
          right: 0,
          child: _StepBlock(
            index: 2,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  flag('ru', 'ru'),
                  SizedBox(
                    width:
                        (AethGeometry.loginLangRow2Pitch -
                            AethGeometry.loginFlagSize) *
                        s,
                  ),
                  flag('cn', 'zh'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The routing step's four circles — tm/ir (row 1), ru/cn (row 2) —
/// bound LIVE to [ConnectionStore.routingRegion] (the store's own
/// default is 'ir').
class LoginRoutingBody extends StatelessWidget {
  const LoginRoutingBody({super.key, required this.store, required this.title});

  final ConnectionStore store;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final current = store.routingRegion ?? 'ir';
    LoginFlagButton flag(String code) => LoginFlagButton(
          keyId: 'login-route-$code',
          code: code,
          selected: current == code,
          onTap: () => store.setRoutingRegion(code),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: AethGeometry.loginTitleTop * s,
          left: 0,
          right: 0,
          child: _StepBlock(index: 0, child: Center(child: _LoginTitle(title))),
        ),
        Positioned(
          top: AethGeometry.loginLangRow1Top * s,
          left: 0,
          right: 0,
          child: _StepBlock(
            index: 1,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  flag('tm'),
                  SizedBox(
                    width:
                        (AethGeometry.loginLangRow1Pitch -
                            AethGeometry.loginFlagSize) *
                        s,
                  ),
                  flag('ir'),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: AethGeometry.loginLangRow2Top * s,
          left: 0,
          right: 0,
          child: _StepBlock(
            index: 2,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  flag('ru'),
                  SizedBox(
                    width:
                        (AethGeometry.loginLangRow2Pitch -
                            AethGeometry.loginFlagSize) *
                        s,
                  ),
                  flag('cn'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The look step — the two home previews.
// ---------------------------------------------------------------------------

/// The frame's «Group 45» at the 0.75 scale: the three crisp squircles
/// (120 r43 rgba(47,248,177,.16) · 99 r32 rgba(47,248,177,.45) · 81.12
/// r27 the standing 180° green gradient) with the white Off glyph —
/// drawn from the ورود4 CSS itself so the preview never depends on the
/// live button's theme-tinted state machinery.
class _LoginGlowPreview extends StatelessWidget {
  const _LoginGlowPreview();

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final outer = AethGeometry.loginLookGroupSize * s;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: outer,
            height: outer,
            decoration: BoxDecoration(
              color: const Color(0x292FF8B1), // rgba(47,248,177,0.16)
              borderRadius: BorderRadius.circular(43 * s),
            ),
          ),
          Container(
            width: 99 * s,
            height: 99 * s,
            decoration: BoxDecoration(
              color: const Color(0x732FF8B1), // rgba(47,248,177,0.45)
              borderRadius: BorderRadius.circular(32 * s),
            ),
          ),
          Container(
            width: 81.12 * s,
            height: 81.12 * s,
            decoration: BoxDecoration(
              gradient: AethColors.accentConnectedGradient,
              borderRadius: BorderRadius.circular(27 * s),
            ),
          ),
          SvgPicture.asset(
            AppAssets.iconOff,
            width: 36 * s,
            height: 36 * s,
            colorFilter:
                const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn),
          ),
        ],
      ),
    );
  }
}

/// The look-1 preview — the hero's OWN artwork (3.svg, the two clean
/// white polygons): the standing green gradient shader when selected
/// (the connected hero's own recipe), the frames' flat #787878 when not.
class _LoginLogoMark extends StatelessWidget {
  const _LoginLogoMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final box = AethGeometry.loginLookGlyphBox * s;
    if (!selected) {
      return SvgPicture.asset(
        AppAssets.appLogoNeutralWhite,
        width: box,
        height: box,
        colorFilter: const ColorFilter.mode(
          AethColors.loginLookGray,
          BlendMode.srcIn,
        ),
      );
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: AethColors.greenStops,
      ).createShader(bounds),
      child: SvgPicture.asset(
        AppAssets.appLogoNeutralWhite,
        width: box,
        height: box,
      ),
    );
  }
}

/// The frames' plain luminance matrix — the unselected look-2 preview's
/// B&W face (the look-1 gray is a FLAT tint, per its frame's vectors).
const ColorFilter _loginGrayMatrix = ColorFilter.matrix(<double>[
  0.299, 0.587, 0.114, 0, 0,
  0.299, 0.587, 0.114, 0, 0,
  0.299, 0.587, 0.114, 0, 0,
  0, 0, 0, 1, 0,
]);

/// One look option zone: the preview centred in its 120-tall band, the
/// tap committing the pick, a one-shot scale bump landing it.
class _LoginLookOption extends StatefulWidget {
  const _LoginLookOption({
    required this.keyId,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String keyId;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_LoginLookOption> createState() => _LoginLookOptionState();
}

class _LoginLookOptionState extends State<_LoginLookOption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  MotionStyle? _style;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _style ??= MotionScope.of(context);
  }

  @override
  void didUpdateWidget(_LoginLookOption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      final style = _style ?? MotionStyle.standard;
      _pulse.duration = motionDuration(style, 340);
      if (style != MotionStyle.off) _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.keyId,
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        key: ValueKey(widget.keyId),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AethHaptics.tap();
          widget.onTap();
        },
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final bump = 0.06 * math.sin(math.pi * _pulse.value);
            return bump == 0
                ? child!
                : Transform.scale(scale: 1 + bump, child: child!);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// The look step («ضاهر برنامه»): the look-2 glow composition at x 120
/// and the look-1 hero artwork at x 272, both centred on y 684, bound
/// LIVE to [ConnectionStore.homeLook].
class LoginLookBody extends StatelessWidget {
  const LoginLookBody({super.key, required this.store, required this.title});

  final ConnectionStore store;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final zoneH = AethGeometry.loginLookGroupSize * s;
    final zoneTop = (AethGeometry.loginLookCenterY * s) - zoneH / 2;
    // The band spans the look-2 group's left edge (60) to the look-1
    // glyph box's right edge (272 + 51 = 323) — 263 wide on the frame.
    const rowLeft =
        (AethGeometry.loginLook2CenterX - AethGeometry.loginLookGroupSize / 2);
    const midGap = (AethGeometry.loginLook1CenterX -
        AethGeometry.loginLook2CenterX -
        AethGeometry.loginLookGroupSize / 2 -
        AethGeometry.loginLookGlyphBox / 2);
    const rowW = AethGeometry.loginLookGroupSize +
        midGap +
        AethGeometry.loginLookGlyphBox;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: AethGeometry.loginTitleTop * s,
          left: 0,
          right: 0,
          child: _StepBlock(index: 0, child: Center(child: _LoginTitle(title))),
        ),
        Positioned(
          top: zoneTop,
          left: rowLeft * s,
          width: rowW * s,
          height: zoneH,
          child: _StepBlock(
            index: 1,
            child: Row(
              children: [
                SizedBox(
                  width: AethGeometry.loginLookGroupSize * s,
                  child: Center(
                    child: _LoginLookOption(
                      keyId: 'login-look-two',
                      selected: store.homeLook == HomeLook.two,
                      onTap: () => store.setHomeLook(HomeLook.two),
                      child: store.homeLook == HomeLook.two
                          ? const _LoginGlowPreview()
                          : const ColorFiltered(
                              colorFilter: _loginGrayMatrix,
                              child: _LoginGlowPreview(),
                            ),
                    ),
                  ),
                ),
                SizedBox(width: midGap * s),
                SizedBox(
                  width: AethGeometry.loginLookGlyphBox * s,
                  child: Center(
                    child: _LoginLookOption(
                      keyId: 'login-look-one',
                      selected: store.homeLook == HomeLook.one,
                      onTap: () => store.setHomeLook(HomeLook.one),
                      child: _LoginLogoMark(
                        selected: store.homeLook == HomeLook.one,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
