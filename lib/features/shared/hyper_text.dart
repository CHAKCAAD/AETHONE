/// HYPER TEXT — the flutterfx «fx_10_hyper_text» technique, rebuilt
/// natively for AETHONE (owner round 18: «روی متن قسمت نام کشور و قسمت
/// نمایش پینگ هم Hyper Text رو اعمال کن»).
///
/// Whenever the text CHANGES it decodes: characters resolve one by one in
/// the string's own order — for the Persian country names that is the
/// visual RIGHT edge first, the natural reading frontier — while the
/// not-yet-resolved positions show random glyphs drawn from the text's
/// own script (Persian letters for Persian text, Latin digits/letters for
/// the «146 ms» readout). Spaces and joiners always render verbatim.
///
/// The RESTING render is byte-identical to the plain [Text] it replaces
/// (same style, maxLines/softWrap/ellipsis, direction), so the location
/// header's pixel contract holds at rest; only the change is animated.
///
/// Style honesty (the app's #1 rule): [MotionStyle.off] renders the new
/// text instantly; every other style scales the decode off its own
/// recipe ([MotionRecipe.hyperTextMs]).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/motion.dart';

/// The Persian scramble pool — letters only, so a mid-decode country
/// name still shapes like connected Persian script.
const String _persianPool = 'ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی';

/// The Latin/digit pool for LTR readouts («146 ms»).
const String _latinPool = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

bool _isPersianScript(String s) =>
    s.runes.any((r) => r >= 0x0600 && r <= 0x06FF);

/// Spaces, the ZWNJ/ZWJ joiners and the bidi marks render verbatim —
/// scrambling them would break the shaping of the resolved half.
bool _isPreserved(int rune) =>
    rune == 0x20 || (rune >= 0x200B && rune <= 0x200F);

class HyperText extends StatefulWidget {
  const HyperText(
    this.text, {
    super.key,
    required this.style,
    this.textStyle,
    this.textDirection,
  });

  final String text;

  /// The ambient motion style — the decode tempo (and its OFF clamp).
  final MotionStyle style;

  final TextStyle? textStyle;
  final TextDirection? textDirection;

  @override
  State<HyperText> createState() => _HyperTextState();
}

class _HyperTextState extends State<HyperText> {
  final Random _random = Random();

  /// The run stamp: a newer change supersedes an in-flight decode (the
  /// old timer's completion is a full no-op — the same discipline as the
  /// wheel's spin epochs).
  int _run = 0;

  double _frontier = 0;
  Timer? _timer;
  String _display = '';

  @override
  void initState() {
    super.initState();
    // No animate-on-load: a freshly mounted slot renders RESOLVED — the
    // decode is a CHANGE animation (and every harness that pumps a fresh
    // tree keeps finding the plain text).
    _display = widget.text;
  }

  @override
  void didUpdateWidget(covariant HyperText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _run++;
    final run = _run;
    final target = widget.text;

    // OFF (accessibility) / empty targets land instantly.
    if (target.isEmpty || widget.style == MotionStyle.off) {
      _frontier = 0;
      _display = target;
      return;
    }

    final len = target.length;
    final ms = widget.style.recipe.hyperTextMs;
    // ~16 ms ticks (60 fps); the frontier advances so the whole decode
    // spans exactly `ms` regardless of length.
    final ticks = (ms ~/ 16).clamp(1, 600);
    final step = len / ticks;
    _frontier = 0;

    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_run != run) {
        timer.cancel();
        return;
      }
      if (_frontier < len) {
        setState(() {
          _frontier += step;
          _display = _scramble(target);
        });
      } else {
        timer.cancel();
        // The exact target — never a boundary artifact of the frontier.
        if (mounted) setState(() => _display = target);
      }
    });
  }

  String _scramble(String target) {
    final runes = target.runes.toList();
    final pool = _isPersianScript(target) ? _persianPool : _latinPool;
    final buffer = StringBuffer();
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (i < _frontier || _isPreserved(rune)) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write(pool[_random.nextInt(pool.length)]);
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _display,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textDirection: widget.textDirection,
      style: widget.textStyle,
    );
  }
}
