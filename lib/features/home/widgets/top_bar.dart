/// Home top bar: settings icon (START side — visual right in RTL), the
/// AETHONE wordmark centered, info icon (END side — visual left in RTL).
///
/// Behavior (owner text): settings icon → Settings; info icon → Telegram
/// channel t.me/AETHONE. The reference image shows an "i" (Information
/// Circle) icon — pending decision D1 we keep the reference icon and wire it
/// to the Telegram link (option A: honors both the image and the text).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_assets.dart';
import '../../../core/design_tokens.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, required this.onSettings});

  final VoidCallback onSettings;

  static const String telegramChannelUrl = 'https://t.me/AETHONE';

  Future<void> _openTelegram() async {
    final uri = Uri.parse(telegramChannelUrl);
    // External browser/app — never an in-app webview.
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Opening failed (no handler). Honest no-op; diagnostics page (later
      // step) will surface such errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.sizeOf(context).width / AethGeometry.refWidth;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AethGeometry.pageHPadding * s),
      child: SizedBox(
        height: 44 * s,
        child: Row(
          children: [
            _TopBarIcon(
              asset: AppAssets.iconSetting,
              semanticLabel: 'Settings',
              onTap: onSettings,
            ),
            const Spacer(),
            // Wordmark — white Bold ~21px with letterSpacing; a small green
            // 3D diamond (the app mark rotated 45°) sits BEHIND the T–H
            // letters, exactly like the reference top bar (green pixels
            // x 183–218 of the 402-wide frame).
            _Wordmark(scale: s),
            const Spacer(),
            _TopBarIcon(
              asset: AppAssets.iconInformationCircle,
              semanticLabel: 'Telegram channel',
              onTap: _openTelegram,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({
    required this.asset,
    required this.semanticLabel,
    this.onTap,
  });

  final String asset;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: IconButton(
        onPressed: onTap,
        icon: SvgPicture.asset(
          asset,
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(
            AethColors.textPrimary,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

/// The AETHONE wordmark: white text with the green extruded diamond mark
/// behind the T–H (drawn in the set's linear style — custom drawing in the
/// icon set's style is allowed per design decision D7).
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final fontSize = 21 * scale;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Green diamond ≈ behind the T–H (≈47% across the wordmark).
        Transform.translate(
          offset: Offset(-fontSize * 1.05, 0),
          child: CustomPaint(
            size: Size.square(fontSize * 1.35),
            painter: _GreenDiamondPainter(),
          ),
        ),
        Text(
          'AETHONE',
          style: TextStyle(
            fontFamily: 'IRANYekanX',
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            letterSpacing: 2.5 * scale,
            color: AethColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Extruded diamond: bright green top face fading to deep green — the same
/// mark geometry as the hero logo (3.svg) rotated 45°.
class _GreenDiamondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    final top = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1AD995), Color(0xFF0A4F33)],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(path, top);
    // Subtle depth edge (bottom-right half a touch darker).
    final edge = Paint()
      ..color = const Color(0xFF0A4F33).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, edge);
  }

  @override
  bool shouldRepaint(_GreenDiamondPainter oldDelegate) => false;
}
