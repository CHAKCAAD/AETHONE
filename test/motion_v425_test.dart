/// v4.25 «انیمیشن‌های اختصاصی» — the motion-system round's own tests:
///
///  1. the five styles are five DISTINCT personalities (each recipe field
///     that defines a feel differs pairwise; OFF is the identity);
///  2. the master kill-switch: `animationsEnabled = false` clamps the
///     effective style to OFF instantly while the picked style stays
///     remembered;
///  3. the persistence round-trip carries the new knob + the fourth
///     style (minimal);
///  4. ONE pattern composition: home, the settings main page and a
///     settings sub-page render the background pattern at IDENTICAL
///     rects (the owner's decree — «مکانش دقیقا مثل صفحه اصلی باشه»);
///  5. the OFF route is an instant cut (Duration.zero).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/connection/settings_persistence.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/widgets/pattern_sides.dart';
import 'package:aethone/features/settings/appearance_page.dart';
import 'package:aethone/features/settings/settings_screen.dart';
import 'package:aethone/features/speedtest/speed_test_page.dart';

Widget _booth(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      supportedLocales: AethoneApp.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

Future<void> _useReferenceSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

ConnectionStore makeStore() =>
    ConnectionStore(engine: EngineNotWiredAdapter());

void main() {
  group('v4.25 — five recipes, five personalities', () {
    test('the style-defining recipe fields differ pairwise', () {
      const styles = MotionStyle.values;
      // Every field that defines a style's FEEL must separate the five
      // personalities: two styles sharing all of these would be the same
      // animation at different speeds — exactly what the owner replaced.
      final feelFields = <String, Map<MotionStyle, Object>>{
        'blockRise': {
          for (final s in styles) s: s.recipe.blockRise,
        },
        'blockScaleFrom': {
          for (final s in styles) s: s.recipe.blockScaleFrom,
        },
        'staggerStep': {
          for (final s in styles) s: s.recipe.staggerStep,
        },
        'pageSlide': {
          for (final s in styles) s: s.recipe.pageSlide,
        },
        'swayPeriodMs': {
          for (final s in styles) s: s.recipe.swayPeriodMs,
        },
        'swayAmpRef': {
          for (final s in styles) s: s.recipe.swayAmpRef,
        },
        'controlMs': {
          for (final s in styles) s: s.recipe.controlMs,
        },
      };
      // For every PAIR of styles, at least one feel field separates them.
      for (var i = 0; i < styles.length; i++) {
        for (var j = i + 1; j < styles.length; j++) {
          final a = styles[i], b = styles[j];
          final separated = feelFields.values
              .any((field) => field[a] != field[b]);
          expect(
            separated,
            isTrue,
            reason:
                '$a and $b must differ in at least one feel field — '
                'each style is its own animation, not a speed knob',
          );
        }
      }
    });

    test('the owner-approved SILK baseline is kept verbatim', () {
      final r = MotionStyle.standard.recipe;
      expect(r.blockRise, 22); // the v4.17 cascade rise
      expect(r.blockScaleFrom, 1.0); // no zoom on the baseline
      expect(r.pageSlide, const Offset(0, 0.03)); // the v4.17 route slide
      expect(r.swayPeriodMs, 6500); // the v4.17 pattern drift
      expect(r.swayAmpRef, 7);
      expect(r.controlMs, 200); // the v4.22 control snap
      expect(r.heroBreathMs, 2600); // the v4.12 hero pulse
      expect(r.rippleMs, 3900); // the v4.15 aurora ripple
    });

    test('OFF is the identity recipe (the kill-switch state)', () {
      final r = MotionStyle.off.recipe;
      expect(r.blockRise, 0);
      expect(r.blockScaleFrom, 1.0);
      expect(r.pageSlide, Offset.zero);
      expect(r.pageScaleFrom, 1.0);
      expect(r.swayAmpRef, 0); // patterns never drift
      expect(r.swayBreathFloor, 1.0); // no luminance breath
      expect(r.controlMs, 0); // controls land instantly
      expect(r.heroBreathAmp, 0); // the hero never pulses
      expect(MotionStyle.off.durationMultiplier, 0.0);
      expect(motionDuration(MotionStyle.off, 400), Duration.zero);
    });

    test('the personalities land on their designed values', () {
      // TIDE — long, flowing, deep.
      final tide = MotionStyle.smooth.recipe;
      expect(tide.blockRise, 34);
      expect(tide.blockScaleFrom, 0.965);
      expect(tide.pageSlide, Offset.zero); // the zoom-dissolve: no slide
      expect(tide.pageScaleFrom, 0.965);
      expect(tide.swayPeriodMs, 9500);
      expect(tide.swayAmpRef, 11);
      // SPRING — snappy, overshooting.
      final spring = MotionStyle.dynamic.recipe;
      expect(spring.blockRise, 12);
      expect(spring.blockScaleFrom, 0.90);
      expect(spring.pageSlide, const Offset(0, 0.055));
      expect(spring.controlMs, 140);
      // BLINK — pure quick fades.
      final blink = MotionStyle.minimal.recipe;
      expect(blink.blockRise, 0);
      expect(blink.blockScaleFrom, 1.0);
      expect(blink.pageSlide, Offset.zero);
    });

    testWidgets('motionCascade is a no-op for OFF and for route-less harnesses',
        (tester) async {
      await _useReferenceSurface(tester);
      const child = SizedBox(key: Key('the-child'));
      await tester.pumpWidget(
        _booth(
          Builder(
            builder: (context) => Column(
              children: [
                motionCascade(context, MotionStyle.off, 2, child),
                motionCascade(
                  context,
                  MotionStyle.standard,
                  2,
                  const SizedBox(key: Key('bare-child')),
                ),
              ],
            ),
          ),
        ),
      );
      // OFF passes the child through untouched; a bare harness (no route)
      // renders the child directly.
      expect(find.byKey(const Key('the-child')), findsOneWidget);
      expect(find.byKey(const Key('bare-child')), findsOneWidget);
    });

    test('the OFF route is an instant cut', () {
      final route = aethPageRoute<void>(
        style: MotionStyle.off,
        builder: (_) => const SizedBox(),
      );
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      // SILK keeps the owner-approved 380/320 ms pairing.
      final silk = aethPageRoute<void>(
        style: MotionStyle.standard,
        builder: (_) => const SizedBox(),
      );
      expect(silk.transitionDuration, const Duration(milliseconds: 380));
      expect(silk.reverseTransitionDuration,
          const Duration(milliseconds: 320));
    });
  });

  group('v4.25 — the master kill-switch', () {
    testWidgets('a disabled app clamps to OFF; the pick stays remembered',
        (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      store.animationStyle = MotionStyle.dynamic; // the owner's pick
      late BuildContext captured;
      await tester.pumpWidget(
        _booth(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      // Enabled: the pick flows through.
      expect(store.effectiveMotionStyle(captured), MotionStyle.dynamic);

      // Flip the switch — every surface reads OFF instantly…
      store.setAnimationsEnabled(false);
      expect(store.animationsEnabled, isFalse);
      expect(store.effectiveMotionStyle(captured), MotionStyle.off);
      // …even the OS reduce-motion clamp path is irrelevant now.
      // …but the PICK is still remembered (flipping back restores it).
      expect(store.animationStyle, MotionStyle.dynamic);

      store.setAnimationsEnabled(true);
      expect(store.effectiveMotionStyle(captured), MotionStyle.dynamic);
    });

    testWidgets('the appearance page commits the fourth style and the switch',
        (tester) async {
      await _useReferenceSurface(tester);
      final store = makeStore();
      await tester.pumpWidget(_booth(AppearanceSettingsPage(store: store)));
      await tester.pumpAndSettle();

      // The fourth style pill (حداقلی) commits.
      await tester.tap(find.text('حداقلی'));
      await tester.pumpAndSettle();
      expect(store.animationStyle, MotionStyle.minimal);
      expect(store.animationsEnabled, isTrue);

      // The kill-switch row: ON = animations disabled.
      await tester.tap(find.byKey(const ValueKey('toggle-animations-off')));
      await tester.pumpAndSettle();
      expect(store.animationsEnabled, isFalse);

      // Flipping it back re-enables without touching the pick.
      await tester.tap(find.byKey(const ValueKey('toggle-animations-off')));
      await tester.pumpAndSettle();
      expect(store.animationsEnabled, isTrue);
      expect(store.animationStyle, MotionStyle.minimal);
    });

    testWidgets('the persistence round-trips the knob and the style',
        (tester) async {
      final first = makeStore();
      first.animationStyle = MotionStyle.minimal;
      first.animationsEnabled = false;

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final persistence = SettingsPersistence();
      await persistence.restore(first);
      await persistence.save(first);

      final second = makeStore();
      final restore = SettingsPersistence();
      await restore.restore(second);
      expect(second.animationStyle, MotionStyle.minimal);
      expect(second.animationsEnabled, isFalse);

      // The key name is stable (never rename a persisted key).
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('aethone.settings.animationsEnabled'),
        isFalse,
      );
    });
  });

  group('v4.25 — ONE pattern composition (the owner decree)', () {
    /// Real-async window: the pattern PNGs decode through the real image
    /// pipeline, which fake-async pumps alone never complete (the
    /// ui_screenshot_test recipe).
    Future<void> settleImages(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The pattern art rects measured on the 402×874 reference surface.
    List<Rect> patternRects(WidgetTester tester) {
      final scope = find.byType(PatternSides);
      expect(scope, findsOneWidget);
      final images = find.descendant(
        of: scope,
        matching: find.byType(Image),
      );
      expect(images, findsNWidgets(2));
      final rects = tester
          .widgetList(images)
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList()
        ..sort((a, b) => a.left.compareTo(b.left));
      // Both canvases must have actually laid out (decoded + sized) —
      // a zero-sized rect would quietly void the comparison below.
      // v5: the new artworks render at their OWN design scale — the LEFT
      // canvas 178 wide, the RIGHT 198 (44 % / 49 % of the 402 frame).
      expect(rects.first.width, closeTo(178, 0.5));
      expect(rects.last.width, closeTo(198, 0.5));
      for (final r in rects) {
        expect(r.height, greaterThan(400));
      }
      return rects;
    }

    testWidgets(
        'v5.3 — the patterns live on the HOME and SPEED-TEST pages ONLY; '
        'the settings pages carry none (the owner\'s new decree)',
        (tester) async {
      await _useReferenceSurface(tester);

      // --- HOME: the one composition, at the mockup-measured placement ---
      final homeStore = makeStore();
      await tester.pumpWidget(_booth(HomeScreen(store: homeStore)));
      await settleImages(tester);
      final homeRects = patternRects(tester);
      // --- HOME: look 1's OWN placement (round 23's thirds RE-CUT,
      // round 24: «پترن سمت راست رو کمی پایین تر بیار و پترن سمت چپ رو
      // کمی بالاتر ببر در حدی که هر دو از وسط صفحه فاصله کمی داشته
      // باشن») — each art's INK CENTRE rides only a LITTLE off the
      // middle: the LEFT art slightly BELOW (58 %), the RIGHT art
      // slightly ABOVE (42 %). The look-2 mockup band (27% / 48.5%)
      // stays the SPEED-TEST page's placement below. ---
      const h = AethGeometry.refHeight * 1.0;
      final left = homeRects.first;
      final leftArtMidPx = (AethGeometry.patternLeftArtTopRow +
              AethGeometry.patternLeftArtRows / 2) /
          1593 *
          left.height;
      expect(
        left.top + leftArtMidPx,
        closeTo(AethGeometry.patternLeftAnchorLookOne * h, 0.5),
      );
      final right = homeRects.last;
      final rightArtMidPx = (AethGeometry.patternRightArtTopRow +
              AethGeometry.patternRightArtBottomRow) /
          2 /
          1848 *
          right.height;
      expect(
        right.top + rightArtMidPx,
        closeTo(AethGeometry.patternRightAnchorLookOne * h, 0.5),
      );

      // --- THE SPEED-TEST PAGE: the composition's other home (v4.33's
      // «از پترن‌های صفحه اصلی برای پس زمینه این صفحه استفاده کن») —
      // it keeps the committed LOOK-2 placement (27% / 48.5%); v6 gave the
      // home's LOOK 1 its own thirds placement, so the two pages no longer
      // share rects — the speed page keeps the mockup band. ---
      final speedStore = makeStore();
      await tester.pumpWidget(_booth(
        SpeedTestPage(store: speedStore, style: MotionStyle.standard),
      ));
      await settleImages(tester);
      final speedRects = patternRects(tester);
      final speedLeft = speedRects.first;
      final speedLeftArtMidPx = (AethGeometry.patternLeftArtTopRow +
              AethGeometry.patternLeftArtRows / 2) /
          1593 *
          speedLeft.height;
      expect(
        speedLeft.top + speedLeftArtMidPx,
        closeTo(AethGeometry.patternLeftAnchor * h, 0.5),
        reason: 'the speed page keeps the v5 mockup band (the LEFT art\'s '
            'centre at 27 %)',
      );
      final speedRight = speedRects.last;
      final speedRightArtBottomPx =
          AethGeometry.patternRightArtBottomRow / 1848 * speedRight.height;
      expect(
        speedRight.top + speedRightArtBottomPx,
        closeTo(AethGeometry.patternRightAnchor * h, 0.5),
        reason: 'the RIGHT art\'s ink bottom stays at 48.5 %',
      );

      // --- THE SETTINGS MAIN PAGE + A SUB-PAGE: NO patterns at all ---
      // v5.3 (the owner: «پترن های سمت راست و چپ فقط باید در صفحه اصلی و
      // صفحه تست سرعت نمایش داده بشن و در سایر صفحه ها نباید نمایش داده
      // شوند») — the v4.21/v4.25 every-page decree is retired.
      final settingsStore = makeStore();
      await tester.pumpWidget(_booth(SettingsScreen(store: settingsStore)));
      await settleImages(tester);
      expect(find.byType(PatternSides), findsNothing,
          reason: 'the settings main page carries no patterns');

      final subStore = makeStore();
      await tester.pumpWidget(_booth(AppearanceSettingsPage(store: subStore)));
      await settleImages(tester);
      expect(find.byType(PatternSides), findsNothing,
          reason: 'the settings sub-pages carry no patterns');
    });
  });
}
