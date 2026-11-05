/// The settings sub-page control vocabulary (v4.22) — every control is
/// drawn from the app's own design language (dark cards, the pill family,
/// IRANYekanX, the accent green) with NO Material-widget look-alikes: the
/// toggle is a hand-drawn AnimatedContainer pill, the option chips are the
/// protocol page's segment style, the fields sit on the deeper #0C120F
/// like the descriptions popup.
///
/// Every row carries its own RTL directionality: the pages' LTR-locked
/// frames place the cards, the Persian content inside flows naturally
/// (icon/label at the visual RIGHT, the control at the visual LEFT).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_assets.dart';
import '../../core/design_tokens.dart';
import '../../core/motion.dart';

/// A small secondary caption (option descriptions, section notes).
class SettingInfoText extends StatelessWidget {
  const SettingInfoText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFamily: 'IRANYekanX',
          fontWeight: FontWeight.w400,
          fontSize: 11,
          height: 1.7,
          color: AethColors.textSecondary,
        ),
      ),
    );
  }
}

/// A label line (12 w600 white) over its control — used above fields and
/// pill groups inside a card.
class SettingLabel extends StatelessWidget {
  const SettingLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFamily: 'IRANYekanX',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: AethColors.textPrimary,
        ),
      ),
    );
  }
}

/// A toggle row: icon (accent) + title/description at the visual RIGHT,
/// the hand-drawn switch at the visual LEFT. Nothing Material — the track
/// is an AnimatedContainer pill, the knob a white circle.
class SettingToggleRow extends StatelessWidget {
  const SettingToggleRow({
    super.key,
    this.icon,
    required this.title,
    this.description,
    required this.value,
    required this.onChanged,
    this.keyId,
  });

  /// Optional leading glyph (the expert TLS rows run icon-less).
  final String? icon;
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional [ValueKey] id for widget tests.
  final String? keyId;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          // Optional leading glyph (icon-less for the dense expert rows).
          if (icon != null) ...[
            _IconGlyph(asset: icon!, size: 20 * s),
            SizedBox(width: 10 * s),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w600,
                    fontSize: 13 * s,
                    color: AethColors.textPrimary,
                  ),
                ),
                if (description != null) ...[
                  SizedBox(height: 3 * s),
                  Text(
                    description!,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w400,
                      fontSize: 10 * s,
                      height: 1.6,
                      color: AethColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 10 * s),
          _CustomSwitch(
            key: keyId == null ? null : ValueKey('toggle-$keyId'),
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The hand-drawn switch — 46×26 track r13, 20 white knob; ON fills the
/// track with the accent green (the connected colour). v4.25 — the snap
/// follows the ambient motion style ([MotionScope]): SPRING flicks in
/// 140 ms with an overshoot, TIDE flows in 320 ms, BLINK blinks at
/// 90 ms, OFF lands instantly.
class _CustomSwitch extends StatelessWidget {
  const _CustomSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const track = Size(46, 26);
    final recipe = MotionScope.of(context).recipe;
    final duration = Duration(milliseconds: recipe.controlMs);
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: duration,
          curve: recipe.controlCurve,
          width: track.width,
          height: track.height,
          decoration: BoxDecoration(
            color: value ? AethColors.accentConnected : AethColors.sheetDescCard,
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: duration,
            curve: recipe.controlCurve,
            // RTL row: the knob travels toward the visual LEFT when on.
            alignment: value ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AethColors.textPrimary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An option-chip group (the protocol page's segment style): a Wrap of
/// pills, the selected one accent-filled. White text on both states —
/// the measured rule from the mode segments.
class SettingPills<T> extends StatelessWidget {
  const SettingPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.keyId,
  });

  /// (value, label) in display order (first = visual RIGHT in the RTL
  /// wrap).
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;

  /// Optional [ValueKey] id prefix for widget tests.
  final String? keyId;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    // v4.25 — the highlight snap follows the ambient motion style.
    final recipe = MotionScope.of(context).recipe;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        spacing: 8 * s,
        runSpacing: 8 * s,
        children: [
          for (final (v, label) in options)
            GestureDetector(
              key: keyId == null ? null : ValueKey('pill-$keyId-$label'),
              onTap: () => onSelect(v),
              child: AnimatedContainer(
                duration: Duration(milliseconds: recipe.controlMs),
                curve: recipe.controlCurve,
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * s,
                  vertical: 9 * s,
                ),
                decoration: BoxDecoration(
                  color: v == selected
                      ? AethColors.accentConnected
                      : AethColors.sheetDescCard,
                  borderRadius: BorderRadius.circular(14 * s),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight:
                        v == selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13 * s,
                    color: AethColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A text field under its label — the deeper #0C120F like the
/// descriptions popup; no Material underline anywhere.
class SettingField extends StatefulWidget {
  const SettingField({
    super.key,
    required this.label,
    required this.hint,
    required this.initial,
    required this.onChanged,
    this.keyId,
    this.maxLines = 1,
  });

  final String label;
  final String hint;
  final String initial;
  final ValueChanged<String> onChanged;
  final String? keyId;
  final int maxLines;

  @override
  State<SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<SettingField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w600,
              fontSize: 12 * s,
              color: AethColors.textPrimary,
            ),
          ),
          SizedBox(height: 8 * s),
          TextField(
            key: widget.keyId == null ? null : ValueKey('field-${widget.keyId}'),
            controller: _controller,
            onChanged: widget.onChanged,
            maxLines: widget.maxLines,
            keyboardType: TextInputType.text,
            style: TextStyle(
              fontFamily: 'IRANYekanX',
              fontWeight: FontWeight.w400,
              fontSize: 12 * s,
              color: AethColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w400,
                fontSize: 12 * s,
                color: AethColors.textSecondary,
              ),
              filled: true,
              fillColor: AethColors.sheetDescCard,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12 * s,
                vertical: 10 * s,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12 * s),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12 * s),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12 * s),
                borderSide: const BorderSide(color: AethColors.accentConnected),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A stepper row (numeric knob): icon + label at the visual RIGHT, the
/// −/value/+ cluster at the visual LEFT. LATIN digits only.
class SettingStepperRow extends StatelessWidget {
  const SettingStepperRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.keyId,
  });

  final String icon;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? keyId;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          _IconGlyph(asset: icon, size: 20 * s),
          SizedBox(width: 10 * s),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w600,
                fontSize: 13 * s,
                color: AethColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 10 * s),
          _StepButton(
            key: ValueKey('step-minus-${keyId ?? label}'),
            asset: AppAssets.iconMinus,
            enabled: value > min,
            onTap: () => onChanged(value - 1),
          ),
          SizedBox(width: 12 * s),
          SizedBox(
            width: 40 * s,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'IRANYekanX',
                fontWeight: FontWeight.w700,
                fontSize: 14 * s,
                color: AethColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 12 * s),
          _StepButton(
            key: ValueKey('step-plus-${keyId ?? label}'),
            asset: AppAssets.iconAdd,
            enabled: value < max,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.asset,
    required this.enabled,
    required this.onTap,
  });

  final String asset;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AethColors.sheetDescCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: _IconGlyph(
              asset: asset,
              size: 16,
              color: enabled
                  ? AethColors.textPrimary
                  : AethColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A navigation / information row: icon + title (+ optional description
/// or trailing value) at the visual RIGHT, a LEFT-pointing chevron (the
/// mirror sibling of the back chevron — “deeper” in this RTL app) at the
/// visual LEFT. [onTap == null] renders the plain value variant.
class SettingNavRow extends StatelessWidget {
  const SettingNavRow({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.trailingValue,
    required this.onTap,
    this.keyId,
    this.chevron = true,
  });

  final String icon;
  final String title;
  final String? description;
  final String? trailingValue;
  final VoidCallback onTap;
  final String? keyId;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        key: keyId == null ? null : ValueKey('nav-$keyId'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            _IconGlyph(asset: icon, size: 20 * s, color: AethColors.accentConnected),
            SizedBox(width: 10 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'IRANYekanX',
                      fontWeight: FontWeight.w600,
                      fontSize: 13 * s,
                      color: AethColors.textPrimary,
                    ),
                  ),
                  if (description != null) ...[
                    SizedBox(height: 3 * s),
                    Text(
                      description!,
                      style: TextStyle(
                        fontFamily: 'IRANYekanX',
                        fontWeight: FontWeight.w400,
                        fontSize: 10 * s,
                        height: 1.6,
                        color: AethColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 10 * s),
            if (trailingValue != null)
              Flexible(
                child: Text(
                  trailingValue!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'IRANYekanX',
                    fontWeight: FontWeight.w400,
                    fontSize: 12 * s,
                    color: AethColors.textSecondary,
                  ),
                ),
              )
            else if (chevron)
              _IconGlyph(
                asset: AppAssets.iconLeft2,
                size: 16 * s,
                color: AethColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

/// A linear icon glyph from the app's own pack.
class _IconGlyph extends StatelessWidget {
  const _IconGlyph({required this.asset, required this.size, this.color});

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Pre-rendered PNGs render through Image.asset; vectors through
    // flutter_svg (AppAssets.isRasterAsset decides — same rule as flags).
    return SvgGlyph(
      asset: asset,
      size: size,
      color: color ?? AethColors.textPrimary,
    );
  }
}

/// Renders an SVG icon tinted [color] (srcIn blend — the app's standard
/// icon treatment).
class SvgGlyph extends StatelessWidget {
  const SvgGlyph({super.key, required this.asset, required this.size, this.color});

  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? AethColors.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }
}

/// The family-pages flag strip: a horizontally scrolling row of flag
/// tiles (AUTO first — the placeholder globe), the selected one ringed
/// accent green and grown, exactly like the home wheel's selected flag.
class FlagPickStrip extends StatelessWidget {
  const FlagPickStrip({
    super.key,
    required this.codes,
    required this.selected,
    required this.onSelect,
  });

  /// Display order: 'auto' first (the caller supplies it), then the codes.
  final List<String> codes;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Directionality(
      textDirection: TextDirection.rtl, // first tile at the visual RIGHT
      child: SizedBox(
        height: 72 * s,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: codes.length,
          separatorBuilder: (_, _) => SizedBox(width: 10 * s),
          itemBuilder: (context, i) {
            final code = codes[i];
            final isSel = code == selected;
            // v4.25 — the selection ring snaps in the ambient style.
            final recipe = MotionScope.of(context).recipe;
            // v4.30 — the home wheel's EXACT flag look (owner round 6:
            // «از همون پرچم کشور ها که در صفحه اصلی استفاده کردیم باید
            // در تنظیمات هم استفاده کنیم با همون ظاهر و همون میزان گردی
            // گوشه ها»): the same 24 %-of-size corner radius and the same
            // cover crop as the wheel's _FlagItem; the selection ring
            // FOLLOWS the flag's rounding (radius + the 3 px padding)
            // instead of the old flat 12.
            final size =
                (isSel
                    ? AethGeometry.flagSizeSelected
                    : AethGeometry.flagSize) *
                s;
            final flagRadius = BorderRadius.circular(size * 0.24);
            return GestureDetector(
              key: ValueKey('flag-pick-$code'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(code),
              child: Center(
                child: AnimatedContainer(
                  duration: Duration(milliseconds: recipe.controlMs),
                  curve: recipe.controlCurve,
                  padding: EdgeInsets.all(3 * s),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size * 0.24 + 3 * s),
                    border: Border.all(
                      width: 2,
                      color: isSel
                          ? AethColors.accentConnected
                          : Colors.transparent,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: flagRadius,
                    child: Image.asset(
                      AppAssets.flag(code),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
