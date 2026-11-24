/// v6 — THE LOGIN LOOP VIDEO («صفحه ورود»): the owner's own 6-second
/// app-icon mockup, playing INFINITELY at the top of the new first-run
/// login («قسمت بالا یک ویدیو … به صورت بی نهایت نمایش داده میشه»).
///
/// The poster frame (frame 0 of the loop, committed as `poster.png`)
/// paints INSTANTLY while the player warms up — and stays forever
/// wherever the codec or the platform channel is unavailable (the widget
/// tests, hosts without the plugin): the flow never blocks, never flashes
/// an empty band, and the loop fades in over its own first frame when
/// ready, so the seam is invisible.
library;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_assets.dart';
import '../../core/motion.dart';

class LoginLoopVideo extends StatefulWidget {
  const LoginLoopVideo({super.key});

  @override
  State<LoginLoopVideo> createState() => _LoginLoopVideoState();
}

class _LoginLoopVideoState extends State<LoginLoopVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.asset(AppAssets.loginVideo);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // The infinite loop — muted, autoplaying, forever.
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      // No codec / no platform channel (the widget-test host): the poster
      // stays — silently, with nothing thrown out of the tree.
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final fade = motionDuration(
      MotionScope.of(context),
      MotionDurations.state,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Frame 0 of the loop — the exact frame the video returns to, so
        // the poster-to-video seam is a single crossfade, never a jump.
        Image.asset(
          AppAssets.loginPoster,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
        if (_ready && controller != null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: fade,
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: VideoPlayer(controller),
          ),
      ],
    );
  }
}

