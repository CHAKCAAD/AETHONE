/// The «سرعت اسکن» (scan speed) pills — 5 increasing widths
/// 28/47/64/77/87, h36 r8 gap8, CENTERED. The widest (rightmost, level
/// 5) is the fastest scan depth.
///
/// PHASE-2 REBUILD (2026-11-09, the owner's decree): the section MOVED
/// from the ProtocolPage to Connection Settings — same control, same
/// geometry tokens ([AethGeometry.protoPill*]), same persisted value
/// ([ConnectionStore.scanSpeed], migrated untouched: a user's stored
/// level keeps applying). The widget is shared (not copied) so the two
/// surfaces can never drift apart if one is ever restyled.
library;

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

class ScanSpeedPills extends StatelessWidget {
  const ScanSpeedPills({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  /// The persisted scan level (1..5).
  final int selected;

  final ValueChanged<int> onSelect;

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

    // The design row is 335 logical px (5 pills + gaps); the settings
    // card's own insets are narrower than the protocol page's full-width
    // slot the section used to occupy — scaleDown preserves the pill
    // rhythm exactly and only shrinks when the card is tighter.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Directionality(
          // RTL with children 5→1: the FIRST child (the widest, level 5)
          // lands at the visual RIGHT — the frame's reading (87 selected,
          // then 77/64/47/28 toward the left).
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
                        // The settings family's in-card chip fill
                        // (SettingPills' own unselected color) so the
                        // pills read as members of the card; the
                        // SELECTED state stays the accent green (the
                        // page-wide selection grammar).
                        color: selected == level
                            ? AethColors.accentConnected
                            : AethColors.sheetDescCard,
                        borderRadius: BorderRadius.circular(r),
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
