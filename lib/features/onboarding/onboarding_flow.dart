/// v4.23 — THE FIRST-RUN WIZARD («صفحه شروع»), pixel-faithful to the four
/// design frames + «لودینگ اسکن» (402×874, every value measured on the
/// sources — see the `ob*` tokens in AethGeometry/AethColors):
///
///  * chrome per frame: the AETHONE lockup (brand mark 38 behind a 17px
///    wordmark), a 4-segment stepper (70×7 bars + 22px step glyphs, the
///    ACTIVE step in accent, the rest in [AethColors.stepDim]), a question
///    heading (20 w700 white + a 22 glyph at the page's right inset) and
///    the full-width green CTA pill (white label + the white Left-2
///    chevron at the visual left — RTL forward);
///
///  * the MAIN-PAGE edge patterns behind every step (owner: «برای پترن
///    های این صفحات هم از همون پترن صفحه اصلی استفاده کن») — the home
///    composition, the GREEN artwork variant the frames carry, at the
///    low opacity the frames show (≈24%);
///
///  * steps slide horizontally through an AnimatedSwitcher (RTL forward =
///    from the visual left), system BACK walks to the previous step;
///
///  * «برو بریم!» starts the scanning state: the step-4 page stays behind
///    BLURRED (the frame's backdrop) with the centered dark modal — brand
///    mark 38 + «در حال پیدا کردن بهترین راه» — for ~3 s, then the wizard
///    commits ([ConnectionStore.completeOnboarding]) and hands over to
///    the home screen.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../connection/connection_store.dart';
import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';
import '../../l10n/app_strings.dart';
import '../home/home_screen.dart';
import '../home/widgets/pattern_sides.dart';
import 'onboarding_steps.dart';

/// The four wizard steps, in wizard order (RTL: step 0 lands rightmost).
enum ObStep { language, routing, look, protocol }

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.store});

  final ConnectionStore store;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  ObStep _step = ObStep.language;
  bool _forward = true;
  bool _finishing = false;

  /// The branded wait on the scanning frame — long enough to read the
  /// modal, short enough to never annoy (nothing engine-side runs here;
  /// the real connect walk belongs to the home screen).
  static const Duration _scanDuration = Duration(milliseconds: 3000);

  void _go(ObStep target) {
    if (_finishing) return;
    setState(() {
      _forward = target.index > _step.index;
      _step = target;
    });
  }

  void _advance() {
    if (_step == ObStep.protocol) {
      _startFinishing();
    } else {
      _go(ObStep.values[_step.index + 1]);
    }
  }

  void _startFinishing() {
    if (_finishing) return;
    setState(() => _finishing = true);
    Future.delayed(_scanDuration, _finish);
  }

  void _finish() {
    if (!mounted) return;
    // Commit first (the debounced save persists the flag), then hand the
    // navigator over to the real home route.
    widget.store.completeOnboarding();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(store: widget.store),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final style = store.effectiveMotionStyle(context);
    return PopScope(
      // BACK walks the wizard backwards; only the first step pops (leaves
      // the app) and the scanning state swallows it entirely.
      canPop: _step == ObStep.language && !_finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finishing && _step != ObStep.language) {
          _go(ObStep.values[_step.index - 1]);
        }
      },
      child: AnimatedBuilder(
        // LIVE binding: every wizard pick (language, routing area, look,
        // mode, auto/manual, scan speed) applies to the store the moment
        // it is tapped — the v4.17 protocol-page lesson.
        animation: store,
        builder: (context, _) {
          final strings = AppStrings.of(context);
          final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
          final duration = motionDuration(style, MotionDurations.page);
          return Scaffold(
            backgroundColor: AethColors.bgScreen,
            body: Stack(
              children: [
                // The main-page patterns (owner decree), green variant at
                // the frames' low opacity, gated by the appearance switch.
                if (store.showPatterns)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: AethColors.obPatternOpacity,
                        child: PatternSides(
                          connected: true,
                          style: style,
                          stage: PatternStage.home,
                        ),
                      ),
                    ),
                  ),
                AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    // RTL forward: the incoming page slides in from the
                    // visual LEFT (the reading direction's "next").
                    final dx = (_forward ? -0.06 : 0.06) *
                        (MediaQuery.sizeOf(context).width /
                            AethGeometry.refWidth);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: anim.drive(
                          Tween(
                            begin: Offset(dx, 0),
                            end: Offset.zero,
                          ).chain(CurveTween(curve: Curves.easeOutCubic)),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: _buildStep(store, strings, s, style),
                ),
                if (_finishing)
                  Positioned.fill(
                    child: ObScanningLayer(store: store, style: style),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStep(
    ConnectionStore store,
    AppStrings strings,
    double s,
    MotionStyle style,
  ) {
    switch (_step) {
      case ObStep.language:
        return ObPage(
          key: const ValueKey('ob-step-language'),
          store: store,
          step: ObStep.language,
          style: style,
          ctaLabel: strings.obContinue,
          onCta: _advance,
          body: ObLanguageTiles(store: store),
          child: ObQuestionHeading(
            icon: AppAssets.iconWebsite,
            text: strings.obLanguageTitle,
          ),
        );
      case ObStep.routing:
        return ObPage(
          key: const ValueKey('ob-step-routing'),
          store: store,
          step: ObStep.routing,
          style: style,
          ctaLabel: strings.obContinue,
          onCta: _advance,
          body: ObRoutingTiles(store: store),
          child: ObQuestionHeading(
            icon: AppAssets.iconRedo,
            text: strings.obRoutingTitle,
          ),
        );
      case ObStep.look:
        return ObPage(
          key: const ValueKey('ob-step-look'),
          store: store,
          step: ObStep.look,
          style: style,
          ctaLabel: strings.obContinue,
          onCta: _advance,
          body: ObLookPreviews(store: store),
          child: ObQuestionHeading(
            icon: AppAssets.iconPalette,
            text: strings.obLookTitle,
          ),
        );
      case ObStep.protocol:
        return ObPage(
          key: const ValueKey('ob-step-protocol'),
          store: store,
          step: ObStep.protocol,
          style: style,
          ctaLabel: strings.obFinish,
          onCta: _startFinishing,
          flexCenter: false,
          child: ObProtocolSections(store: store),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// The shared page scaffold: lockup → stepper → [heading + body] → CTA.
// ---------------------------------------------------------------------------

/// One wizard page. Steps 1–3 float their heading+body block between the
/// stepper and the CTA with the frames' 179:223 spacer rhythm; step 4
/// scrolls its taller stack with fixed gaps.
class ObPage extends StatelessWidget {
  const ObPage({
    super.key,
    required this.store,
    required this.step,
    required this.style,
    required this.ctaLabel,
    required this.onCta,
    required this.child,
    this.body,
    this.flexCenter = true,
  });

  final ConnectionStore store;
  final ObStep step;
  final MotionStyle style;
  final String ctaLabel;
  final VoidCallback onCta;

  /// The question heading (steps 1–3) or the full section stack (step 4).
  final Widget child;

  /// The tiles/previews under the heading (steps 1–3 only).
  final Widget? body;
  final bool flexCenter;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SafeArea(
      child: Directionality(
        // LTR-locked geometry (the settings-page precedent): the chrome
        // lands on the frame's measured positions while Persian text
        // inside keeps its natural bidi direction.
        textDirection: TextDirection.ltr,
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: AethGeometry.pageHPadding * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: AethGeometry.topSafeExtraGap * s),
              const ObLockup(),
              SizedBox(height: AethGeometry.obLockupToStepper * s),
              ObStepper(active: step),
              if (flexCenter) ...[
                const Spacer(flex: AethGeometry.obFlexAbove),
                child,
                SizedBox(height: AethGeometry.obHeadingToTiles * s),
                body ?? const SizedBox.shrink(),
                const Spacer(flex: AethGeometry.obFlexBelow),
              ] else ...[
                Expanded(
                  child: SingleChildScrollView(child: child),
                ),
              ],
              ObCtaButton(label: ctaLabel, onTap: onCta),
              SizedBox(height: AethGeometry.obCtaToBottom * s),
            ],
          ),
        ),
      ),
    );
  }
}

/// The AETHONE lockup — the brand mark (آیکون اپ/2.svg, its own gradient
/// facets) centered BEHIND a 17px wordmark (the home top bar's recipe at
/// the wizard's larger size).
class ObLockup extends StatelessWidget {
  const ObLockup({super.key});

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return SizedBox(
      height: AethGeometry.brandMarkSize * s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SvgPicture.asset(
            AppAssets.brandMark,
            width: AethGeometry.brandMarkSize * s,
            height: AethGeometry.brandMarkSize * s,
            fit: BoxFit.contain,
          ),
          Text(
            'AETHONE',
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w700,
              fontSize: AethGeometry.obWordmarkSize * s,
              letterSpacing: AethGeometry.wordmarkLetterSpacing * s,
              color: AethColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 4-segment stepper: bars 70×7 with 19 gaps spanning the page inset,
/// 22px step glyphs centered under each bar. The ACTIVE step renders in
/// the accent, the rest in [AethColors.stepDim] (all four frames agree).
class ObStepper extends StatelessWidget {
  const ObStepper({super.key, required this.active});

  final ObStep active;

  /// The step glyphs, LTR slot order (step 0 is the RIGHTMOST slot):
  /// sliders (type) · palette (look) · redo (routing) · globe (language).
  static const List<String> _icons = [
    AppAssets.iconSetting,
    AppAssets.iconPalette,
    AppAssets.iconRedo,
    AppAssets.iconWebsite,
  ];

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    final barW = AethGeometry.obBarW * s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: barW,
                height: AethGeometry.obBarH * s,
                decoration: BoxDecoration(
                  color: i == 3 - active.index
                      ? AethColors.accentConnected
                      : AethColors.stepDim,
                  borderRadius:
                      BorderRadius.circular(AethGeometry.obBarH * s / 2),
                ),
              ),
          ],
        ),
        SizedBox(height: AethGeometry.obBarToIcon * s),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: barW,
                child: Center(
                  child: SvgPicture.asset(
                    _icons[i],
                    width: AethGeometry.obStepIcon * s,
                    height: AethGeometry.obStepIcon * s,
                    colorFilter: ColorFilter.mode(
                      i == 3 - active.index
                          ? AethColors.accentConnected
                          : AethColors.stepDim,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The question heading: 20 w700 white with the step's own 22px glyph at
/// the page's right inset, 8 gap — the frames' exact arrangement.
class ObQuestionHeading extends StatelessWidget {
  const ObQuestionHeading({super.key, required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          const Spacer(),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: AethGeometry.obHeadingSize * s,
                  color: AethColors.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(width: AethGeometry.obHeadingIconGap * s),
          SvgPicture.asset(
            icon,
            width: AethGeometry.obHeadingIcon * s,
            height: AethGeometry.obHeadingIcon * s,
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

/// The full-width green CTA pill: white 18 w700 label + the white Left-2
/// chevron 20 from the visual LEFT edge (RTL "forward"), soft green
/// shadow (the frames' under-glow).
class ObCtaButton extends StatelessWidget {
  const ObCtaButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        key: const ValueKey('ob-cta'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AethGeometry.obCtaH * s,
          decoration: BoxDecoration(
            color: AethColors.accentConnected,
            borderRadius: BorderRadius.circular(AethGeometry.obCtaRadius * s),
            boxShadow: [
              BoxShadow(
                color: AethColors.accentConnected.withValues(alpha: 0.30),
                offset: Offset(0, 4 * s),
                blurRadius: 14 * s,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                label,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'IRANYekanX',
                  fontWeight: FontWeight.w700,
                  fontSize: AethGeometry.obCtaTextSize * s,
                  color: AethColors.textPrimary,
                ),
              ),
              Positioned(
                left: AethGeometry.obCtaChevronInset * s,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SvgPicture.asset(
                    AppAssets.iconLeft2,
                    width: AethGeometry.obCtaChevron * s,
                    height: AethGeometry.obCtaChevron * s,
                    colorFilter: const ColorFilter.mode(
                      AethColors.textPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
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
// The scanning state («لودینگ اسکن»): the finished step-4 page stays
// behind, blurred + dimmed, with the centered dark modal on top.
// ---------------------------------------------------------------------------

class ObScanningLayer extends StatefulWidget {
  const ObScanningLayer({super.key, required this.store, required this.style});

  final ConnectionStore store;
  final MotionStyle style;

  @override
  State<ObScanningLayer> createState() => _ObScanningLayerState();
}

class _ObScanningLayerState extends State<ObScanningLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.style != MotionStyle.off) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return AbsorbPointer(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9 * s, sigmaY: 9 * s),
        child: Container(
          // The frames dim the backdrop mostly through the blur itself;
          // a whisper of black keeps the modal reading as the top layer.
          color: Colors.black.withValues(alpha: 0.12),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: motionDuration(widget.style, MotionDurations.quick),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
              ),
              child: Container(
                key: const ValueKey('ob-scanning-modal'),
                width: AethGeometry.obModalW * s,
                height: AethGeometry.obModalH * s,
                decoration: BoxDecoration(
                  color: AethColors.cardDark,
                  borderRadius:
                      BorderRadius.circular(AethGeometry.obModalRadius * s),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.05).animate(
                        CurvedAnimation(
                          parent: _pulse,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: SvgPicture.asset(
                        AppAssets.brandMark,
                        width: AethGeometry.obModalMark * s,
                        height: AethGeometry.obModalMark * s,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: AethGeometry.obModalGap * s),
                    Text(
                      strings.obLoading,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w600,
                        fontSize: AethGeometry.obModalTextSize * s,
                        color: AethColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
