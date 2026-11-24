/// v6 — THE FIRST-RUN LOGIN («صفحه ورود»), replacing the retired four-page
/// wizard wholesale (owner: «4 صفحه ورود اولیه داره که میخوام کلا از اپ
/// حذف بشن و صفحه ورود جدید جایگزینش بشه»), pixel-faithful to the five
/// committed frames ورود1..ورود5 (402×874 @3× — every value measured on
/// them; see the `login*` tokens in AethGeometry/AethColors):
///
///  * the TOP section is the owner's own 6-second video, looping
///    INFINITELY at the screen's top edge («به صورت بی نهایت نمایش داده
///    میشه» — [LoginLoopVideo]);
///
///  * the BOTTOM section is the white sheet ([LoginSheetPainter]): flat
///    top edge at y 468 with r27 corners and the centre NOTCH (109→293,
///    sinking to 492) through which the dark video shows behind the step
///    indicator;
///
///  * the step indicator — 5 marks in the notch: the ACTIVE step a
///    55-wide white pill, the rest 9-wide white-60% dots, 7 px apart.
///    Walking between steps MORPHS the row (the pill re-flow) — «جابه
///    جایی بین مراحل باید انیمیشن رو روی این قسمت ایجاد کنه»;
///
///  * under it, the per-step glyph tile (44×44 #F4F4F4 r16), the title
///    (19/w500), the step's body and the nav pills — every layer rides
///    the app's own motion vocabulary (direction-aware slide + the
///    cascade entrance, the ambient [MotionStyle] scaling it all);
///
///  * steps: welcome → language («زبان برنامه») → routing («منطقه
///    مسیریابی») → look («ضاهر برنامه») → done («اتمام راه اندازی!»),
///    every pick committing to the store LIVE, «بریم!» committing the
///    onboarding flag and handing the navigator to the home screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../home/home_screen.dart';
import 'login_steps.dart';
import 'login_video.dart';

/// The five login steps, in walking order.
enum LoginStep { welcome, language, routing, look, done }

class LoginFlow extends StatefulWidget {
  const LoginFlow({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<LoginFlow> {
  int _step = 0;
  bool _forward = true;

  void _go(int target) {
    if (target == _step || target < 0 || target >= LoginStep.values.length) {
      return;
    }
    setState(() {
      _forward = target > _step;
      _step = target;
    });
  }

  void _advance() => _go(_step + 1);

  void _finish() {
    // Commit first (the debounced save persists the flag), then hand the
    // navigator to the real home route — the app's own route personality.
    widget.store.completeOnboarding();
    Navigator.of(context).pushReplacement(
      aethPageRoute<void>(
        style: widget.store.effectiveMotionStyle(context),
        builder: (_) => HomeScreen(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final style = store.effectiveMotionStyle(context);
    return PopScope(
      // BACK walks the login backwards; only the first step pops (leaves
      // the app).
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _go(_step - 1);
      },
      child: AnimatedBuilder(
        // LIVE binding: every login pick (language, routing region, look)
        // applies to the store the moment it is tapped.
        animation: store,
        builder: (context, _) {
          final strings = AppStrings.of(context);
          final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
          // The nav pills' anchor: the frame's y 795, lifted only if a
          // tall bottom inset (3-button bars) would crowd it.
          final mq = MediaQuery.of(context);
          final btnTop = math.min(
            AethGeometry.loginBtnTop * s,
            mq.size.height -
                mq.padding.bottom -
                AethGeometry.loginBtnH * s -
                8 * s,
          );
          return MotionScope(
            style: style,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              // The video band is dark — light status glyphs over it.
              value: SystemUiOverlayStyle.light,
              child: Scaffold(
                backgroundColor: AethColors.loginSheet,
                body: Directionality(
                  // LTR-locked geometry (the settings-page precedent):
                  // every frame position lands as measured while Persian
                  // text keeps its natural bidi direction.
                  textDirection: TextDirection.ltr,
                  child: Stack(
                    children: [
                      // ---- the top section: the infinite loop video ----
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: AethGeometry.loginVideoH * s,
                        child: const LoginLoopVideo(),
                      ),
                      // ---- the white sheet, notched around the video ----
                      Positioned(
                        top: AethGeometry.loginSheetTop * s,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: CustomPaint(
                          painter: _LoginSheetPainter(s: s),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      // ---- the step indicator, inside the notch ----
                      Positioned(
                        top: AethGeometry.loginIndicatorTop * s,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: LoginStepIndicator(active: _step),
                        ),
                      ),
                      // ---- the per-step glyph tile ----
                      Positioned(
                        top: AethGeometry.loginIconBoxTop * s,
                        left: 0,
                        right: 0,
                        child: Center(child: LoginIconBox(step: _step)),
                      ),
                      // ---- the step body (title + content), animated ----
                      Positioned.fill(child: _buildBody(strings, style)),
                      // ---- the nav pills ----
                      Positioned(
                        top: btnTop,
                        left: 0,
                        right: 0,
                        height: AethGeometry.loginBtnH * s,
                        child: _buildButtons(strings, style, s),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The step body: title + content as ONE unit, so a step change moves
  /// them together — a direction-aware slide (the reading direction's
  /// "next"), a fade and (per the ambient recipe) a soft zoom.
  Widget _buildBody(AppStrings strings, MotionStyle style) {
    final Widget body = switch (LoginStep.values[_step]) {
      LoginStep.welcome => LoginDescriptionBody(
          title: strings.loginWelcomeTitle,
          description: strings.loginWelcomeDesc,
        ),
      LoginStep.language => LoginLanguageBody(
          store: widget.store,
          title: strings.loginLanguageTitle,
        ),
      LoginStep.routing => LoginRoutingBody(
          store: widget.store,
          title: strings.loginRoutingTitle,
        ),
      LoginStep.look => LoginLookBody(
          store: widget.store,
          title: strings.loginLookTitle,
        ),
      LoginStep.done => LoginDescriptionBody(
          title: strings.loginDoneTitle,
          description: strings.loginDoneDesc,
        ),
    };
    final r = style.recipe;
    // Forward steps arrive FROM the reading direction's "next" — the
    // visual LEFT under Persian, the visual RIGHT under the LTR locales.
    final sign =
        appContentDirection(context) == TextDirection.rtl ? -1.0 : 1.0;
    final travel = r.blockRise > 0 ? 1.0 : 0.0;
    final dx = (_forward ? 0.08 : -0.08) * sign * travel;
    final curve = style == MotionStyle.off ? Curves.linear : r.blockCurve;
    return AnimatedSwitcher(
      duration: motionDuration(style, MotionDurations.page),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        Widget node = FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: anim.drive(
              Tween(begin: Offset(dx, 0), end: Offset.zero)
                  .chain(CurveTween(curve: curve)),
            ),
            child: child,
          ),
        );
        if (r.blockScaleFrom < 1) {
          node = ScaleTransition(
            scale: anim.drive(
              Tween(begin: r.blockScaleFrom, end: 1.0)
                  .chain(CurveTween(curve: curve)),
            ),
            child: node,
          );
        }
        return node;
      },
      child: KeyedSubtree(
        key: ValueKey('login-body-$_step'),
        child: body,
      ),
    );
  }

  /// The nav pills: the pair («قبلی» + «بعدی») on the middle steps, the
  /// single centred pill on the first («بعدی») and last («بریم!»).
  Widget _buildButtons(AppStrings strings, MotionStyle style, double s) {
    final Widget row;
    if (_step == 0) {
      row = LoginPillButton.single(
        keyId: 'login-next',
        label: strings.loginNext,
        onTap: _advance,
      );
    } else if (_step == LoginStep.values.length - 1) {
      row = LoginPillButton.single(
        keyId: 'login-go',
        label: strings.loginGo,
        onTap: _finish,
      );
    } else {
      // The PAIR spans the full zone width (the switcher's default
      // layout CENTRES its children — a full-width child keeps the
      // frame's own absolute pill positions: «قبلی» at x 33, «بعدی» at
      // x 213).
      row = SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.only(left: AethGeometry.loginBtnPrevLeft * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoginPillButton.leading(
                keyId: 'login-prev',
                label: strings.loginPrev,
                onTap: () => _go(_step - 1),
              ),
              SizedBox(
                width:
                    (AethGeometry.loginBtnNextLeft -
                        AethGeometry.loginBtnPrevLeft -
                        AethGeometry.loginBtnW) *
                        s,
              ),
              LoginPillButton.trailing(
                keyId: 'login-next',
                label: strings.loginNext,
                onTap: _advance,
              ),
            ],
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: motionDuration(style, MotionDurations.quick),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: anim.drive(
            Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey('login-btns-$_step'), child: row),
    );
  }
}

// ---------------------------------------------------------------------------
// The white sheet's painter — the r27 top corners + the centre notch.
// ---------------------------------------------------------------------------

/// The sheet: a plain white fill whose top edge rounds at the corners
/// (r27) and dips into the centre NOTCH — the slot (109→293, sinking to
/// y 492) through which the dark video shows behind the step indicator.
/// The two transitions are the frames' smooth S-curves (cubic control
/// points fitted to the per-column edge scan of all five frames).
class _LoginSheetPainter extends CustomPainter {
  const _LoginSheetPainter({required this.s});

  /// The width scale (screenWidth / 402) every reference value rides.
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // CANVAS coordinates: this painter's own top edge IS the sheet's flat
    // top (the widget is mounted AT y 468), so every y below is relative
    // to it — the notch floor sits 24 ref px in.
    final r = AethGeometry.loginSheetCorner * s;
    final depth =
        (AethGeometry.loginNotchBottom - AethGeometry.loginSheetTop) * s;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, r)
      // Top-left corner (r27 — the measured y(0)=495).
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(AethGeometry.loginNotchLeft * s, 0)
      // The notch's left S-curve: leaves the flat edge horizontally,
      // lands flat on the notch floor (fitted to the edge scan).
      ..cubicTo(
        135 * s,
        0,
        122 * s,
        depth,
        AethGeometry.loginNotchFlatLeft * s,
        depth,
      )
      ..lineTo(AethGeometry.loginNotchFlatRight * s, depth)
      // The right S-curve — the left one's mirror (the notch is centred).
      ..cubicTo(
        280 * s,
        depth,
        267 * s,
        0,
        AethGeometry.loginNotchRight * s,
        0,
      )
      ..lineTo(w - r, 0)
      // Top-right corner.
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = AethColors.loginSheet);
  }

  @override
  bool shouldRepaint(_LoginSheetPainter oldDelegate) => oldDelegate.s != s;
}

// ---------------------------------------------------------------------------
// The step indicator — the notch's own 5-mark row.
// ---------------------------------------------------------------------------

/// The 5-mark step row: the ACTIVE step renders the 55-wide fully-rounded
/// white pill, the rest the 9-wide white-60% dots, 7 px apart (the whole
/// row 119 wide, centred). Walking between steps MORPHS the row — each
/// mark's width tweens, so the pill visibly re-flows into its new slot.
class LoginStepIndicator extends StatelessWidget {
  const LoginStepIndicator({super.key, required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    final style = MotionScope.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final duration = motionDuration(style, MotionDurations.quick);
    final curve = style == MotionStyle.off ? Curves.linear : Curves.easeOutCubic;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < LoginStep.values.length; i++) ...[
          if (i > 0) SizedBox(width: AethGeometry.loginIndicatorGap * s),
          AnimatedContainer(
            duration: duration,
            curve: curve,
            width: (i == active
                    ? AethGeometry.loginIndicatorActiveW
                    : AethGeometry.loginIndicatorDotW) *
                s,
            height: AethGeometry.loginIndicatorH * s,
            decoration: BoxDecoration(
              color: i == active ? Colors.white : AethColors.loginDot,
              borderRadius: BorderRadius.circular(
                AethGeometry.loginIndicatorH * s / 2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The per-step glyph tile.
// ---------------------------------------------------------------------------

/// The 44×44 #F4F4F4 r16 tile with the step's glyph — Filter 1 (welcome/
/// done), the Website globe (language), Redo (routing), Palette (look) —
/// crossfading with a soft zoom on every step change.
class LoginIconBox extends StatelessWidget {
  const LoginIconBox({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final style = MotionScope.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final (asset, box) = switch (LoginStep.values[step]) {
      LoginStep.welcome => (AppAssets.iconFilter1, AethGeometry.loginGlyphFilter1),
      LoginStep.language => (
          AppAssets.iconWebsite,
          AethGeometry.loginGlyphWebsite
        ),
      LoginStep.routing => (AppAssets.iconRedo, AethGeometry.loginGlyphRedo),
      LoginStep.look => (AppAssets.iconPalette, AethGeometry.loginGlyphPalette),
      LoginStep.done => (AppAssets.iconFilter1, AethGeometry.loginGlyphFilter1),
    };
    return Container(
      key: const ValueKey('login-icon-box'),
      width: AethGeometry.loginIconBoxSize * s,
      height: AethGeometry.loginIconBoxSize * s,
      decoration: BoxDecoration(
        color: AethColors.loginBox,
        borderRadius: BorderRadius.circular(AethGeometry.loginIconBoxRadius * s),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: motionDuration(style, MotionDurations.quick),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.75, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: SvgPicture.asset(
            asset,
            key: ValueKey('login-glyph-$step'),
            width: box * s,
            height: box * s,
            colorFilter: const ColorFilter.mode(
              Color(0xFF000000),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The nav pills.
// ---------------------------------------------------------------------------

enum _PillVariant { single, leading, trailing }

/// One 156×44 r16 ghost pill: a horizontal #F4F4F4 alpha gradient —
/// symmetric for the centred single, solid-at-the-outer-edge for the
/// pair — carrying its 16/w400 label and the set's own chevron at the
/// pill's OUTER end («بعدی» + Right 2 pointing right, «قبلی» + Left 2).
class LoginPillButton extends StatefulWidget {
  const LoginPillButton.single({
    super.key,
    required this.keyId,
    required this.label,
    required this.onTap,
  }) : _variant = _PillVariant.single;

  const LoginPillButton.leading({
    super.key,
    required this.keyId,
    required this.label,
    required this.onTap,
  }) : _variant = _PillVariant.leading;

  const LoginPillButton.trailing({
    super.key,
    required this.keyId,
    required this.label,
    required this.onTap,
  }) : _variant = _PillVariant.trailing;

  final String keyId;
  final String label;
  final VoidCallback onTap;
  final _PillVariant _variant;

  @override
  State<LoginPillButton> createState() => _LoginPillButtonState();
}

class _LoginPillButtonState extends State<LoginPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final style = MotionScope.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    const ghost = Color(0x00F4F4F4);
    // The measured gradients: the pair's pills fade toward the CENTRE
    // (solid at their own outer edge), the single's is symmetric.
    final Gradient gradient = switch (widget._variant) {
      _PillVariant.single => const LinearGradient(
          colors: [ghost, AethColors.loginBox, ghost],
        ),
      _PillVariant.leading => const LinearGradient(
          colors: [AethColors.loginBox, ghost],
        ),
      _PillVariant.trailing => const LinearGradient(
          colors: [ghost, AethColors.loginBox],
        ),
    };
    final Widget label = Text(
      widget.label,
      textDirection: appContentDirection(context),
      style: TextStyle(
        fontFamily: 'IRANYekanX',
        fontWeight: FontWeight.w400,
        fontSize: AethGeometry.loginBtnTextSize * s,
        color: AethColors.loginInk,
      ),
    );
    Widget chevron(String asset) => SvgPicture.asset(
          asset,
          width: AethGeometry.loginBtnChevron * s,
          height: AethGeometry.loginBtnChevron * s,
          colorFilter: const ColorFilter.mode(
            AethColors.loginInk,
            BlendMode.srcIn,
          ),
        );
    // The chevron rides the pill's OUTER end (measured on the frames:
    // glyph centres x≈52.5/226/347); the box gaps below land the GLYPH
    // where the frames put it (the 26-px box carries its own air).
    final Widget content;
    switch (widget._variant) {
      case _PillVariant.single:
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [label, SizedBox(width: 3 * s), chevron(AppAssets.iconRight2)],
        );
      case _PillVariant.leading:
        content = Padding(
          padding: EdgeInsets.only(left: 7 * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chevron(AppAssets.iconLeft2),
              SizedBox(width: 8 * s),
              label,
            ],
          ),
        );
      case _PillVariant.trailing:
        content = Padding(
          padding: EdgeInsets.only(right: 9 * s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [label, SizedBox(width: 4 * s), chevron(AppAssets.iconRight2)],
          ),
        );
    }
    return Semantics(
      label: widget.label,
      button: true,
      child: GestureDetector(
        key: ValueKey(widget.keyId),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: motionDuration(style, MotionDurations.touch),
          curve: Curves.easeOut,
          child: Container(
            width: AethGeometry.loginBtnW * s,
            height: AethGeometry.loginBtnH * s,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AethGeometry.loginBtnRadius * s),
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
