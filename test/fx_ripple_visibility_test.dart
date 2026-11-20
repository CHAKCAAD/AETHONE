import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/core/fx/tap_ripple.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/core/motion_widgets.dart';

/// Round-2 regression — the owner's report: «Ripple Effect … روی نما ۲
/// دکمهٔ اتصال هنوز اعمال نشده». The v4.43 tests only asserted that the
/// field ATTACHED and SETTLED — a burst that rendered nothing at all
/// passed them. These tests count the burst's actual PIXELS through the
/// production composition (PressSpring → TapRipple), for the first tap
/// AND for a tap after an idle pause (the clock-restart path).
void main() {
  Future<int> ringPixels(WidgetTester tester, Key boundaryKey) async {
    var count = 0;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        final r = bytes.getUint8(i);
        final g = bytes.getUint8(i + 1);
        final b = bytes.getUint8(i + 2);
        // Ring red (0xEA2323) + the landing flash, over the dark child.
        if (r > 70 && r > g + 30 && r > b + 30) count++;
      }
    });
    return count;
  }

  testWidgets('every tap paints a visible burst — including after idle',
      (tester) async {
    const boundaryKey = ValueKey('ripple-boundary');
    final controller = TapRippleController();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0E14),
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: PressSpring(
                style: MotionStyle.standard,
                onTap: () => taps++,
                onPointerDown: controller.tapAt,
                child: SizedBox(
                  width: 236,
                  height: 236,
                  child: TapRipple(
                    controller: controller,
                    color: const Color(0xFFEA2323),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutCubic,
                    baseRadius: 108.17 / 2,
                    maxScale: 2.2,
                    child: Container(
                      color: const Color(0xFF101820),
                      width: 108,
                      height: 108,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Baseline: the dark child alone — no red family pixels.
    final before = await ringPixels(tester, boundaryKey);
    expect(before, lessThan(20), reason: 'idle field paints nothing');

    // TAP 1 — through the real gesture path (the pointer-down hook).
    await tester.tap(find.byType(PressSpring), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 90));
    final tap1 = await ringPixels(tester, boundaryKey);
    expect(tap1, greaterThan(150),
        reason: 'the first burst must be clearly visible');

    // Run the burst out completely — the field goes idle (house rule).
    for (var i = 0; i < 60 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(seconds: 1));
    final idle = await ringPixels(tester, boundaryKey);
    expect(idle, lessThan(20), reason: 'the field is idle again');

    // TAP 2 — AFTER the idle pause (the clock-restart path: birth times
    // recorded on a previous timeline must still render immediately).
    await tester.tap(find.byType(PressSpring), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 90));
    final tap2 = await ringPixels(tester, boundaryKey);
    expect(tap2, greaterThan(150),
        reason: 'a tap after idle must burst just as visibly');

    for (var i = 0; i < 60 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(taps, 2, reason: 'both taps fired their actions');
    expect(controller.isAttached, isTrue);

    // Sanity artifact for the evidence folder (best-effort).
    try {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('/tmp/ui_shots').create(recursive: true);
        await File('/tmp/ui_shots/ripple_idle.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    } catch (_) {}
  });

  testWidgets('the OFF gate (Duration.zero) paints nothing at all',
      (tester) async {
    const boundaryKey = ValueKey('ripple-boundary-off');
    final controller = TapRippleController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0E14),
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: TapRipple(
                controller: controller,
                color: const Color(0xFFEA2323),
                duration: Duration.zero,
                child: Container(
                  color: const Color(0xFF101820),
                  width: 108,
                  height: 108,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    controller.tapAt(const Offset(54, 54));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final pixels = await ringPixels(tester, boundaryKey);
    expect(pixels, lessThan(20), reason: 'OFF never paints a ring');
  });
}
