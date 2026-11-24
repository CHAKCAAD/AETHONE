/// v4.45/v4.46 — regression tests for the protocol-selection BOTTOM SHEET
/// (the owner's redesign, pixel-faithful to «انتخاب پروتکل.jpg» + the
/// owner's own Figma CSS): the home protocol card slides a flutterfx-style
/// sheet up over the scaling home, the 2×6 grid of 159×67 tiles carries the
/// standing green gradient + 4px ring on the selected protocol, a tap
/// commits IMMEDIATELY and auto-closes, and a drag (or the barrier) closes
/// it too. The retired v4.17 full PAGE (segments, family cards, Firefox
/// card) is gone with its tokens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethone/app.dart';
import 'package:aethone/core/app_assets.dart' show ProtocolId;
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/connection/connection_store.dart';
import 'package:aethone/connection/engine.dart';
import 'package:aethone/core/design_tokens.dart';
import 'package:aethone/features/home/home_screen.dart';
import 'package:aethone/features/home/protocol_sheet/protocol_sheet.dart';
import 'package:aethone/features/shared/protocol_glyph.dart';
import 'package:aethone/l10n/app_strings.dart';

class ScriptedEngine extends EngineAdapter {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast();
  @override
  Stream<EngineEvent> get events => _controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void bind(EngineConfigSource config) {} // scripted — config never read
}

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

Future<void> _openSheet(WidgetTester tester, ConnectionStore store) async {
  await tester.pumpWidget(_booth(HomeScreen(store: store)));
  await tester.pumpAndSettle();
  // The home protocol card names the SELECTED protocol — the v4.19 cold
  // default is WIREGUARD, and a previous pick in the same store renames
  // the card, so the tap rides the live label.
  final label = AppStrings.forLocale('fa').protocolName(
    store.smartDisplayProtocol,
  );
  await tester.tap(find.text(label).first);
  await tester.pump();
  await tester.pumpAndSettle(); // the flutterfx entrance (scale + slide)
}

Future<void> _tapAndAutoClose(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump(); // the selection frame (commit is immediate)
  await tester.pump(const Duration(milliseconds: 320)); // the green hold
  await tester.pumpAndSettle(); // the reverse slide
}

void main() {
  testWidgets(
    'the BOTTOM SHEET opens over the scaling home (panel + handle + '
    'barrier; the retired PAGE is gone)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);

      // The chrome: the panel, the drag handle, the dimming barrier.
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('proto-sheet-handle')), findsOneWidget);

      // v4.45-fixed — the panel rides its OWN palette slot (protoSheetBg),
      // never the home-card family: the improper merge once left the
      // panel the SAME color as its chips (cardDark #F4F4F4 in light),
      // and the whole grid read as one flat blob. Round 24 — the night
      // family is the HOME screen's own dark pair (#000000 panel / chips
      // #1C1C1C). The bare booth starts on the sync's own NIGHT default,
      // so the panel must be the night sheet #000000 — and must DIFFER
      // from the chip color either way.
      final panelWidget = tester.widget<Container>(
        find.byKey(const ValueKey('proto-sheet-panel')),
      );
      final panelColor =
          (panelWidget.decoration! as BoxDecoration).color as Color;
      expect(panelColor, AethColors.protoSheetBg);
      expect(panelColor, const Color(0xFF000000));
      expect(panelColor, isNot(AethColors.protoSheetChip));

      // Geometry (the view is 402×874 logical — 1:1 with the frame):
      // panel 402×565 anchored to the bottom (top = 874 − 565 = 309).
      final panel = tester.getRect(
        find.byKey(const ValueKey('proto-sheet-panel')),
      );
      expect(panel.left, closeTo(0, 0.5));
      expect(panel.width, closeTo(402, 1));
      expect(panel.top, closeTo(874 - AethGeometry.protoSheetH, 1));
      expect(panel.height, closeTo(AethGeometry.protoSheetH, 1));

      // The handle: 97×8, 17 below the panel's top edge, centred.
      final handle = tester.getRect(
        find.byKey(const ValueKey('proto-sheet-handle')),
      );
      expect(handle.width, closeTo(AethGeometry.protoSheetHandleW, 1));
      expect(handle.height, closeTo(AethGeometry.protoSheetHandleH, 0.5));
      expect(
        handle.top,
        closeTo(panel.top + AethGeometry.protoSheetHandleTop, 1),
      );
      expect(
        handle.center.dx,
        closeTo(201, 1),
        reason: 'horizontally centred on the 402 frame',
      );

      // The first row's top sits 53 below the panel's top edge (y355).
      final wg = tester.getRect(
        find.byKey(const ValueKey('proto-tile-wireguard')),
      );
      expect(
        wg.top,
        closeTo(panel.top + AethGeometry.protoSheetGridTop, 1),
      );
      expect(wg.height, closeTo(AethGeometry.protoSheetCardH, 1));
      expect(wg.width, closeTo(AethGeometry.protoSheetCardW, 1.5));

      // The barrier dims (flutterfx recipe, alpha 0.38 at full open).
      final barrier = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('proto-sheet-barrier')),
      );
      final barrierColor =
          (barrier.decoration as BoxDecoration).color as Color;
      expect(barrierColor.a, closeTo(0.38, 0.04));
    },
  );

  testWidgets(
    'all 12 protocols render in the frame\'s LTR grid order '
    '(wireguard LEFT · auto RIGHT)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);

      // Round 25 — the frame's OWN Latin labels are BACK (the owner:
      // «اسامی پروتکل ها در صفحه پروتکل رو به حالت قبل برگردون» — the
      // round-24 localized re-cut is retired; the app's localized names
      // keep riding the home card + settings). The finders are SCOPED
      // to the sheet panel so a future label can never collide with the
      // scaled home behind the barrier.
      Finder sheetText(String label) => find.descendant(
            of: find.byKey(const ValueKey('proto-sheet-panel')),
            matching: find.text(label),
          );
      for (final label in [
        'Wireguard', 'Auto', 'M I M', 'Masq', 'G Classic', 'Gool',
        'Tor', 'Psiphon', 'T O W', 'P O W', 'W O T', 'W O P',
      ]) {
        expect(sheetText(label), findsOneWidget, reason: label);
      }

      // LTR-locked reading (the grid never bidi-flips under the fa
      // locale): wireguard on the visual LEFT, auto on the RIGHT.
      final wg = tester.getCenter(sheetText('Wireguard'));
      final auto = tester.getCenter(sheetText('Auto'));
      expect(auto.dx, greaterThan(wg.dx));

      // Column order down the rows: mim below wireguard, masq below auto.
      expect(
        tester.getCenter(sheetText('M I M')).dy,
        greaterThan(wg.dy),
      );
      expect(
        tester.getCenter(sheetText('Masq')).dx,
        greaterThan(tester.getCenter(sheetText('M I M')).dx),
      );

      // The last row ends 25 above the panel's bottom (867 − 842).
      final panel = tester.getRect(
        find.byKey(const ValueKey('proto-sheet-panel')),
      );
      final lastRow = tester.getRect(
        find.byKey(const ValueKey('proto-tile-psiphonReverse')),
      );
      expect(
        panel.bottom - lastRow.bottom,
        closeTo(25, 2),
      );
    },
  );

  testWidgets(
    'the SELECTED tile carries the standing green gradient + the 4px '
    'rgba(26,217,149,0.4) ring; the others stay chip-grey', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);
      await tester.pump(const Duration(milliseconds: 300)); // crossfade lands

      BoxDecoration tileDecoration(ProtocolId id) {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey('proto-tile-${id.name}')),
            matching: find.byType(Container),
          ).first,
        );
        return container.decoration! as BoxDecoration;
      }

      // SELECTED (the line's cold default — MASQUE on the motion line,
      // v1.0.1): the green gradient core under the 4px translucent green
      // ring (owner CSS «Rectangle 13»).
      final selectedDec = tileDecoration(store.smartDisplayProtocol);
      expect(
        (selectedDec.gradient as LinearGradient).colors.first,
        AethColors.accentConnectedGradient.colors.first,
      );
      expect(
        (selectedDec.gradient as LinearGradient).colors.last,
        AethColors.accentConnectedGradient.colors.last,
      );
      final selectedRing = selectedDec.border as Border;
      expect(
        selectedRing.top.width,
        closeTo(AethGeometry.protoSheetCardBorder, 0.1),
      );
      expect(
        selectedRing.top.color.a * 255,
        closeTo(AethGeometry.protoSheetCardRingAlpha * 255, 6),
      );

      // UNSELECTED (auto — never the cold default on this line): the flat
      // chip fill, no visible ring.
      final autoDec = tileDecoration(ProtocolId.auto);
      expect(autoDec.gradient!.colors.first, AethColors.protoSheetChip);
      expect((autoDec.border as Border).top.color.a, 0);
    },
  );

  testWidgets(
    'a tile tap commits the protocol IMMEDIATELY and AUTO-CLOSES the '
    'sheet (the v4.16 decree, carried over)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);

      await tester.tap(find.byKey(const ValueKey('proto-tile-auto')));
      await tester.pump(); // the commit is synchronous with the frame
      expect(store.selectedProtocol, ProtocolId.auto);
      // The sheet content listens to the store — the green crossfade is
      // already running (independent of the close ride).
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 320)); // the hold
      await tester.pumpAndSettle(); // the reverse slide
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsNothing);
    },
  );

  testWidgets(
    'every one of the 12 tiles commits its own protocol (the flattened '
    'family modes are first-class)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);

      final expectations = <ProtocolId, ProtocolId>{
        // spot-check the combined modes (the old family subtiles).
        ProtocolId.psiphonChain: ProtocolId.psiphonChain,
        ProtocolId.torReverse: ProtocolId.torReverse,
        ProtocolId.goolClassic: ProtocolId.goolClassic,
      };
      for (final entry in expectations.entries) {
        await _tapAndAutoClose(
          tester,
          find.byKey(ValueKey('proto-tile-${entry.key.name}')),
        );
        expect(store.selectedProtocol, entry.value);
        // Selection alone NEVER claims a connection.
        expect(store.state, VpnState.disconnected);
        await _openSheet(tester, store); // re-open for the next pick
      }
    },
  );

  testWidgets(
    'the BARRIER tap closes the sheet; the drag-to-dismiss follows the '
    'finger (flutterfx handlers)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      final before = store.selectedProtocol;
      await _openSheet(tester, store);

      // Barrier tap (a point well above the panel, over the scaled home).
      await tester.tapAt(const Offset(201, 100));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsNothing);

      // Re-open (the card names the SELECTED protocol — the line's cold
      // default, MASQUE), then drag the panel down past halfway → it
      // dismisses.
      await tester.tap(
        find.text(
          AppStrings.forLocale('fa').protocolName(store.smartDisplayProtocol),
        ).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('proto-sheet-panel')),
        const Offset(0, 565 * 0.75),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsNothing);
      // A dismissal never commits anything on its own.
      expect(store.selectedProtocol, before);
    },
  );

  testWidgets(
    'v4.46 — the squat-viewport guard: a clamped sheet SCROLLS its grid '
    '(never overflowS)', (tester) async {
      // A squat viewport (402×500): the panel clamps to 0.92×500 = 460
      // and the grid rides a scroll view — nothing overflows, the last
      // row is reachable, and the sheet still opens and closes. The host
      // is pumped DIRECTLY with a placeholder mainContent: the motion
      // line's look-1 home legitimately needs more than 500px (its fixed
      // session stack under the hero) and that overflow is this test's
      // noise, not the sheet's guard.
      tester.view.physicalSize = const Size(402 * 3, 500 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final store = ConnectionStore(engine: ScriptedEngine());
      final controller = ProtocolSheetController();
      await tester.pumpWidget(_booth(ProtocolSheetHost(
        controller: controller,
        store: store,
        mainContent: const SizedBox.expand(),
      )));
      await tester.pumpAndSettle();
      controller.open();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'a clamped sheet must never overflow');
      await tester.tap(find.byKey(const ValueKey('proto-tile-gool')));
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();
      expect(store.selectedProtocol, ProtocolId.gool);
      expect(find.byKey(const ValueKey('proto-sheet-panel')), findsNothing);
    }
  );

  testWidgets(
    'v4.46 — the reference viewport keeps the FIXED grid (no scroll '
    'view — the whole panel stays drag-to-dismiss)', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('proto-sheet-panel')),
          matching: find.text('W O P'),
        ),
        findsOneWidget,
      ); // the last row is laid out
    },
  );

  testWidgets(
    'round 25 — the logos pack to the tile\'s LEFT edge (two aligned '
    'columns) and the per-tile calibrated heights are back', (tester) async {
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final store = ConnectionStore(engine: ScriptedEngine());
      await _openSheet(tester, store);

      // The glyph inside a tile (the view is 402 logical — s = 1).
      Finder glyph(ProtocolId id) => find.descendant(
            of: find.byKey(ValueKey('proto-tile-${id.name}')),
            matching: find.byType(ProtocolGlyph),
          );

      // The column anchors are derived from the tiles' OWN rects (the
      // grid rides Expanded slots, so the right column starts at 209.5,
      // not the frame's nominal 209): every glyph leads its column from
      // the tile's left edge + the round-25 pad (the 4px ring PAINTS
      // over the edge band; a BoxDecoration border never layout-insets
      // the child).
      final colLeft = tester
              .getRect(find.byKey(const ValueKey('proto-tile-wireguard')))
              .left +
          AethGeometry.protoSheetTilePadLeft;
      final colRight =
          tester.getRect(find.byKey(const ValueKey('proto-tile-auto'))).left +
              AethGeometry.protoSheetTilePadLeft;
      for (final id in [
        ProtocolId.wireguard,
        ProtocolId.mim,
        ProtocolId.goolClassic,
        ProtocolId.torOnly,
        ProtocolId.torChain,
        ProtocolId.torReverse,
      ]) {
        expect(tester.getTopLeft(glyph(id)).dx, closeTo(colLeft, 0.5),
            reason: '${id.name} leads the left column');
      }

      // RIGHT COLUMN — same rule, its own anchor.
      for (final id in [
        ProtocolId.auto,
        ProtocolId.masque,
        ProtocolId.gool,
        ProtocolId.psiphonOnly,
        ProtocolId.psiphonChain,
        ProtocolId.psiphonReverse,
      ]) {
        expect(tester.getTopLeft(glyph(id)).dx, closeTo(colRight, 0.5),
            reason: '${id.name} leads the right column');
      }
      expect(colRight, greaterThan(colLeft));

      // The per-tile calibrated heights are RESTORED (the round-24
      // uniform 24 ref-px box is retired): spot-check the extremes +
      // the frame's own values.
      expect(tester.getSize(glyph(ProtocolId.wireguard)).height,
          closeTo(19, 0.5));
      expect(tester.getSize(glyph(ProtocolId.auto)).height,
          closeTo(23, 0.5));
      expect(tester.getSize(glyph(ProtocolId.mim)).height,
          closeTo(28, 0.5));
      expect(tester.getSize(glyph(ProtocolId.psiphonOnly)).height,
          closeTo(34, 0.5));
      expect(tester.getSize(glyph(ProtocolId.psiphonReverse)).height,
          closeTo(31, 0.5));
    },
  );
}
