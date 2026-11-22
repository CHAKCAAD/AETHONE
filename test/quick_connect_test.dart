// v1.0.1 — the phone surfaces' quick-connect delegation (the home-screen
// widget's «اتصال» button and the QS tile): those surfaces launch
// MainActivity with the quick-connect extra, the activity parks the ask in
// its companion, and the shell PULLS it over the engine channel
// (`takeQuickConnect`) — routing it into the store's normal single-flight
// connect, exactly like the in-app button. The ask is consumed even when
// the wizard owns the first run (never left armed for a later resume).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethone/app.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';

/// Records connect() calls without running a walk.
class _RecordingEngine implements EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();

  int connects = 0;
  int disconnects = 0;

  @override
  void bind(EngineConfigSource config) {}

  @override
  Stream<EngineEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    connects++;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The shell pulls twice on a cold start (initState + the first resumed
  // tick); the mock answers "true" exactly ONCE, then false — the ask is
  // consumed by whoever pulls first.
  void mockChannel({required int truePulls}) {
    var served = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('aethone/engine'), (
          call,
        ) async {
          if (call.method == 'takeQuickConnect') {
            served++;
            return <String, Object?>{'connect': served <= truePulls};
          }
          if (call.method == 'widgetState') return null;
          throw MissingPluginException('unmocked: ${call.method}');
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('aethone/engine'), null);
  });

  testWidgets(
    'an armed quick-connect ask routes into the store connect (once)',
    (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final engine = _RecordingEngine();
      final store = ConnectionStore(engine: engine);
      store.onboardingComplete = true; // the shell owns the connect
      mockChannel(truePulls: 1);

      await tester.pumpWidget(AethoneApp(store: store));
      // The armed ask lands the home screen in `starting`, which plays the
      // repeating scan halo — bounded pumps, never pumpAndSettle (v4.11
      // discipline).
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.connects, 1,
          reason: 'the widget/tile ask must run the normal connect flow');
    },
  );

  testWidgets('a consumed ask behind the wizard never connects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = _RecordingEngine();
    final store = ConnectionStore(engine: engine);
    store.onboardingComplete = false; // the wizard owns the first run
    mockChannel(truePulls: 1);

    await tester.pumpWidget(AethoneApp(store: store));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(engine.connects, 0,
        reason: 'the wizard owns the first run — consumed, not armed');
  });

  testWidgets('no ask, no connect (the everyday cold start)', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final engine = _RecordingEngine();
    final store = ConnectionStore(engine: engine);
    store.onboardingComplete = true;
    mockChannel(truePulls: 0);

    await tester.pumpWidget(AethoneApp(store: store));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(engine.connects, 0);
  });
}
