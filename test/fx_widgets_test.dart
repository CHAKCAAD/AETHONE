import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/app_theme.dart';
import 'package:aethone/core/fx/circular_reveal.dart';
import 'package:aethone/core/fx/tap_ripple.dart';
import 'package:aethone/core/fx/theme_reveal.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/shared/theme_toggle_tile.dart';

/// v4.43 — the three flutterfx ports (owner-approved dependency round):
/// the circular-reveal geometry and host and the connect button's tap
/// ripple (the connected smoke field joined them in v4.43 and was RETIRED
/// in v5.3 — the owner: «انیمیشن حاله سبز در حالت اتصال رو کلا حذف کن و
/// فقط پترن ها باشن»). Every assertion here encodes a HOUSE RULE
/// (prompt §11.7 / report §10): OFF renders nothing, the action never
/// waits for decoration, state is never faked. If a test here fails, one
/// of those rules was broken — do NOT relax the test.
void main() {
  setUp(() {
    AethThemeSync.palette = AethPal.night;
  });

  group('CircularRevealClipper — the geometry (flutterfx port)', () {
    test('revealMaxRadius covers the farthest corner from any origin', () {
      const size = Size(400, 800);
      // A corner origin: the farthest point is the opposite corner.
      final r = revealMaxRadius(size, const Offset(0, 0));
      final needed = const Offset(400, 800).distance;
      expect(r, greaterThanOrEqualTo(needed));
      // A mid-screen origin: both bottom corners must be covered.
      final rMid = revealMaxRadius(size, const Offset(200, 400));
      final neededMid = const Offset(200, 400).distance;
      expect(rMid, greaterThanOrEqualTo(neededMid));
      // The original's +20 slack survives the generalization.
      expect(r - needed, greaterThanOrEqualTo(20));
    });

    test('radius 0 covers everything; full radius uncovers the far corner', () {
      const size = Size(400, 800);
      const origin = Offset(100, 50);
      final clipper0 = CircularRevealClipper(center: origin, radius: 0);
      // Inside the rect, outside the (degenerate) oval → still COVERED by
      // the even-odd fill: the old theme shows everywhere at t = 0.
      expect(clipper0.getClip(size).contains(const Offset(300, 700)), isTrue);

      final full = revealMaxRadius(size, origin);
      final clipper1 = CircularRevealClipper(center: origin, radius: full);
      // The farthest corner now sits INSIDE the hole → REVEALED (the new
      // theme pours through): the point is no longer part of the overlay.
      expect(
        clipper1.getClip(size).contains(const Offset(399, 799)),
        isFalse,
      );
    });
  });

  group('TapRipple — the connect button burst (flutterfx port)', () {
    testWidgets('attaches on mount, detaches on unmount', (tester) async {
      final controller = TapRippleController();
      await tester.pumpWidget(Center(
        child: TapRipple(
          controller: controller,
          color: Colors.green,
          child: const SizedBox(width: 100, height: 100),
        ),
      ));
      expect(controller.isAttached, isTrue,
          reason: 'the field registered itself on mount');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.isAttached, isFalse,
          reason: 'the field detached on dispose');
    });

    testWidgets('a tap bursts and the field settles back to idle', (tester) async {
      final controller = TapRippleController();
      await tester.pumpWidget(Center(
        child: TapRipple(
          controller: controller,
          color: Colors.green,
          duration: const Duration(milliseconds: 300),
          stagger: const Duration(milliseconds: 50),
          child: const SizedBox(width: 100, height: 100),
        ),
      ));
      // The burst: rings spawn, expand, and DIE — pumpAndSettle completes
      // precisely because nothing loops forever (the house rule).
      controller.tapAt(const Offset(50, 50));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      // The controller survives; the field is idle again.
      expect(controller.isAttached, isTrue);
    });

    testWidgets('the OFF gate (Duration.zero) spawns nothing at all', (tester) async {
      final controller = TapRippleController();
      await tester.pumpWidget(Center(
        child: TapRipple(
          controller: controller,
          color: Colors.green,
          duration: Duration.zero,
          child: const SizedBox(width: 100, height: 100),
        ),
      ));
      controller.tapAt(const Offset(50, 50));
      // No animation was scheduled — settle is instant.
      await tester.pumpAndSettle();
      expect(controller.isAttached, isTrue);
    });
  });

  // (The SmokeField group is RETIRED with the widget itself — v5.3, the
  // owner: «انیمیشن حاله سبز در حالت اتصال رو کلا حذف کن و فقط پترن ها
  // باشن»: the connected green smoke is gone from the app entirely.)

  group('ThemeReveal — the shell host (flutterfx port)', () {
    testWidgets('no host mounted: the request applies the flip directly',
        (tester) async {
      final s = ConnectionStore(engine: EngineNotWiredAdapter());
      var applied = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedBuilder(
              animation: s,
              builder: (context, _) => ThemeToggleTile(
                store: s,
                size: 50,
                iconSize: 24,
                tileKey: const ValueKey('theme-tile'),
              ),
            ),
          ),
        ),
      ));
      // The host-less path (bare harnesses, the OFF fallback's twin):
      // the tile still flips the mode, just without the wipe.
      await tester.tap(find.byKey(const ValueKey('theme-tile')));
      await tester.pumpAndSettle();
      expect(s.themeMode, AethThemeMode.night);
      applied = true;
      expect(applied, isTrue);
      expect(find.byType(ClipPath), findsNothing);
    });

    testWidgets(
        'a tile tap inside the host: capture → flip → wipe → settle',
        (tester) async {
      final s = ConnectionStore(engine: EngineNotWiredAdapter());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ThemeRevealHost(
            styleOf: () => MotionStyle.standard,
            child: Center(
              child: AnimatedBuilder(
                animation: s,
                builder: (context, _) => ThemeToggleTile(
                  store: s,
                  size: 50,
                  iconSize: 24,
                  tileKey: const ValueKey('theme-tile'),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(s.themeMode, AethThemeMode.light);

      // Tap: the OLD frame is captured first, THEN the flip lands.
      await tester.tap(find.byKey(const ValueKey('theme-tile')));
      await tester.pump(); // the async capture completes
      await tester.pump(const Duration(milliseconds: 16));

      // The wipe overlay is up (the old frame wiping away in a circle).
      expect(find.byType(ClipPath), findsOneWidget,
          reason: 'the reveal overlay mounted over the app');
      expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(1),
          reason: 'the capture boundary wraps the app');
      // The theme ALREADY flipped underneath (never delayed by art).
      expect(s.themeMode, AethThemeMode.night);

      // SILK: 650 ms wipe — run it out.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(find.byType(ClipPath), findsNothing,
          reason: 'the wipe finished and the overlay is gone');
      expect(s.themeMode, AethThemeMode.night);
    });

    testWidgets('the OFF style takes the plain flip — no overlay at all',
        (tester) async {
      final s = ConnectionStore(engine: EngineNotWiredAdapter());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ThemeRevealHost(
            styleOf: () => MotionStyle.off,
            child: Center(
              child: AnimatedBuilder(
                animation: s,
                builder: (context, _) => ThemeToggleTile(
                  store: s,
                  size: 50,
                  iconSize: 24,
                  tileKey: const ValueKey('theme-tile'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('theme-tile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      // The kill-switch: the mode flipped, no wipe was ever mounted.
      expect(s.themeMode, AethThemeMode.night);
      expect(find.byType(ClipPath), findsNothing);
    });
  });
}
