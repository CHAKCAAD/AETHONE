import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';
import 'package:aethone/features/home/widgets/glow_pill.dart';

import 'code_generator.dart';
import 'custom_widget_slot.dart';
import 'motion_studio_screen.dart';

const bg = Color(0xFF090E0B);
const panel = Color(0xFF101812);
const raised = Color(0xFF151F18);
const line = Color(0xFF26362B);
const muted = Color(0xFF91A095);
const green = Color(0xFF1AD995);
const red = Color(0xFFEA4545);

class MotionPlaygroundApp extends StatelessWidget {
  const MotionPlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AETHONE Motion Playground',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(
            primary: green,
            secondary: green,
            surface: panel,
          ),
          fontFamily: 'IRANYekanX',
        ),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: MotionStudioScreen(),
        ),
      );
}

class MotionPlaygroundScreen extends StatefulWidget {
  const MotionPlaygroundScreen({super.key});

  @override
  State<MotionPlaygroundScreen> createState() =>
      _MotionPlaygroundScreenState();
}

class _MotionPlaygroundScreenState extends State<MotionPlaygroundScreen> {
  PlaygroundTarget target = PlaygroundTarget.connectControl;
  MotionStyle style = MotionStyle.standard;
  VpnState state = VpnState.disconnected;
  MotionEffect effect = MotionEffect.fadeScale;
  CurvePreset curve = CurvePreset.easeOutBack;
  int duration = 520;
  double strength = 0.72;
  int replay = 0;
  bool showCode = true;

  final widgetExpression = TextEditingController(text: 'const YourCard()');

  @override
  void dispose() {
    widgetExpression.dispose();
    super.dispose();
  }

  String get output => generateMotionCode(
        target: target,
        style: style,
        state: state,
        durationMs: duration,
        curve: curve,
        effect: effect,
        strength: strength,
        widgetExpression: widgetExpression.text,
      );

  void chooseState(VpnState value) => setState(() {
        state = value;
        replay++;
      });

  void nextState() => chooseState(switch (state) {
        VpnState.disconnected => VpnState.starting,
        VpnState.starting || VpnState.waitingForPermissions =>
          VpnState.connecting,
        VpnState.connecting || VpnState.reconnecting => VpnState.connected,
        VpnState.connected => VpnState.disconnecting,
        VpnState.disconnecting => VpnState.disconnected,
        VpnState.failed => VpnState.starting,
      });

  Future<void> copyCode() async {
    await Clipboard.setData(ClipboardData(text: output));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کد Dart کپی شد')),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 1050
            ? _desktop()
            : _compact(),
      );

  Widget _desktop() => Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(width: 210, child: _sidebar()),
              const VerticalDivider(width: 1, color: line),
              Expanded(
                child: Column(
                  children: [
                    _header(),
                    const Divider(height: 1, color: line),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: _preview()),
                                if (showCode)
                                  SizedBox(height: 230, child: _codePanel()),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 1, color: line),
                          SizedBox(
                            width: 300,
                            child: SingleChildScrollView(child: _inspector()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _compact() => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              const Divider(height: 1, color: line),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SizedBox(height: 370, child: _preview()),
                      const SizedBox(height: 12),
                      _inspector(),
                      const SizedBox(height: 12),
                      if (showCode) SizedBox(height: 310, child: _codePanel()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _sidebar() => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Text('A', style: TextStyle(
                  color: green, fontSize: 29, fontWeight: FontWeight.w900,
                )),
                SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AETHONE', style: TextStyle(
                      fontWeight: FontWeight.w900, letterSpacing: 1.3,
                    )),
                    Text('MOTION LAB', style: TextStyle(
                      color: muted, fontSize: 9, letterSpacing: 1.7,
                    )),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _Label('کامپوننت‌ها'),
            const SizedBox(height: 8),
            for (final item in PlaygroundTarget.values)
              _navItem(
                item.label,
                target == item,
                () => setState(() {
                  target = item;
                  replay++;
                }),
              ),
            const SizedBox(height: 24),
            const _Label('شخصیت حرکتی'),
            const SizedBox(height: 8),
            for (final item in MotionStyle.values)
              _navItem(
                styleName(item),
                style == item,
                () => setState(() {
                  style = item;
                  replay++;
                }),
              ),
            const Spacer(),
            const _Notice(
              text: 'محیط توسعه است؛ هیچ VPN یا عملیات شبکه‌ای اجرا نمی‌شود.',
            ),
          ],
        ),
      );

  Widget _navItem(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0x221AD995) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0x664ADBA7) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.circle_outlined,
                  color: selected ? green : muted,
                  size: 15,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : muted,
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _header() => SizedBox(
        height: 62,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Motion Playground', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                    )),
                    Text('پیش‌نمایش و خروجی کد Dart',
                        style: TextStyle(color: muted, fontSize: 10)),
                  ],
                ),
              ),
              _Pill(styleName(style)),
              IconButton(
                tooltip: 'Replay',
                onPressed: () => setState(() => replay++),
                icon: const Icon(Icons.replay_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Code panel',
                onPressed: () => setState(() => showCode = !showCode),
                icon: Icon(showCode ? Icons.code : Icons.code_off, size: 19),
              ),
            ],
          ),
        ),
      );

  Widget _preview() => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text('پیش‌نمایش زنده',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text('LIVE PREVIEW',
                    style: TextStyle(color: green, fontSize: 9)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C130E),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: line),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(
                      painter: _GridPainter(),
                    )),
                    Center(
                      child: Builder(
                        builder: (context) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(size: const Size(402, 874)),
                          child: _previewChild(),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _Pill(stateName(state)),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Text(
                        target == PlaygroundTarget.customWidget
                            ? 'SAMPLE WIDGET'
                            : 'REAL AETHONE WIDGET',
                        style: const TextStyle(color: muted, fontSize: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _previewChild() {
    switch (target) {
      case PlaygroundTarget.connectControl:
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConnectHalo(state: state, style: style, size: 280),
              ConnectShake(
                state: state,
                style: style,
                child: ConnectButtonGlow(
                  connected: state == VpnState.connected,
                  state: state,
                  style: style,
                  duration: motionDuration(style, MotionDurations.state),
                  curve: style.curve,
                  onTap: nextState,
                ),
              ),
            ],
          ),
        );
      case PlaygroundTarget.stateHalo:
        final accent = state == VpnState.connected ? green : red;
        return SizedBox.square(
          dimension: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConnectHalo(state: state, style: style, size: 280),
              Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF101A14),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.4),
                ),
                child: const Text('A', style: TextStyle(
                  color: green, fontSize: 38, fontWeight: FontWeight.w800,
                )),
              ),
            ],
          ),
        );
      case PlaygroundTarget.customWidget:
        return TweenAnimationBuilder<double>(
          key: ValueKey<int>(replay),
          tween: Tween<double>(begin: 0, end: 1),
          duration: Duration(milliseconds: duration),
          curve: curveValue(curve),
          builder: (context, t, child) =>
              _applyEffect(t, child ?? const SizedBox.shrink()),
          child: _sampleCard(),
        );
    }
  }

  Widget _applyEffect(double t, Widget child) {
    final scale = 1 - strength * 0.18 + strength * 0.18 * t;
    switch (effect) {
      case MotionEffect.fade:
        return Opacity(opacity: t, child: child);
      case MotionEffect.scale:
        return Transform.scale(
          scale: 1 - strength * 0.20 + strength * 0.20 * t,
          child: child,
        );
      case MotionEffect.slide:
        return Transform.translate(
          offset: Offset(0, (1 - t) * strength * 34),
          child: child,
        );
      case MotionEffect.rotate:
        return Transform.rotate(
          angle: (1 - t) * strength * 0.28,
          child: child,
        );
      case MotionEffect.blur:
        final sigma = (1 - t) * strength * 8;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
      case MotionEffect.fadeScale:
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: scale, child: child),
        );
    }
  }

  Widget _sampleCard() => buildCustomWidgetPreview();

  Widget _inspector() => Container(
        color: panel,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('تنظیمات انیمیشن',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 14),
            _field('کامپوننت'),
            _dropdown<PlaygroundTarget>(
              target,
              PlaygroundTarget.values,
              (v) => v.label,
              (v) => setState(() { target = v; replay++; }),
            ),
            const SizedBox(height: 10),
            _field('شخصیت حرکتی'),
            _dropdown<MotionStyle>(
              style,
              MotionStyle.values,
              styleName,
              (v) => setState(() { style = v; replay++; }),
            ),
            const SizedBox(height: 10),
            _field('وضعیت نمایشی'),
            _dropdown<VpnState>(
              state,
              VpnState.values,
              stateName,
              chooseState,
            ),
            if (target == PlaygroundTarget.customWidget) ...[
              const SizedBox(height: 14),
              const Divider(color: line),
              const SizedBox(height: 10),
              _field('نوع افکت'),
              _dropdown<MotionEffect>(
                effect,
                MotionEffect.values,
                (v) => v.label,
                (v) => setState(() { effect = v; replay++; }),
              ),
              const SizedBox(height: 12),
              _slider(
                'مدت زمان',
                duration.toDouble(),
                120,
                1800,
                duration.toString() + ' ms',
                (v) => setState(() { duration = v.round(); replay++; }),
              ),
              _field('Curve'),
              _dropdown<CurvePreset>(
                curve,
                CurvePreset.values,
                (v) => v.label,
                (v) => setState(() { curve = v; replay++; }),
              ),
              const SizedBox(height: 10),
              _slider(
                'شدت افکت',
                strength,
                0,
                1,
                (strength * 100).round().toString() + '%',
                (v) => setState(() { strength = v; replay++; }),
              ),
              _field('Widget expression برای کد خروجی'),
              TextField(
                controller: widgetExpression,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: green, fontFamily: 'monospace', fontSize: 11,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              const Text(
                'برای پیش‌نمایش Widget واقعی، فایل custom_widget_slot.dart را به کلاس خودت متصل کن. عبارت همین فیلد هم در کد خروجی استفاده می‌شود؛ کد Dart دلخواه در زمان اجرا اجرا نمی‌شود.',
                style: TextStyle(color: muted, fontSize: 9, height: 1.5),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(color: line),
            const SizedBox(height: 8),
            const Text('پارامترهای Recipe',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            _recipeValues(),
            const SizedBox(height: 12),
            const _Notice(
              text: 'تنظیمات ذخیره‌شده و رفتار VPN دست‌نخورده می‌مانند.',
            ),
          ],
        ),
      );

  Widget _recipeValues() {
    final r = style.recipe;
    final values = <(String, String)>[
      ('Block rise', r.blockRise.round().toString() + ' px'),
      ('Connect march', r.connectMarchMs.toString() + ' ms'),
      ('Reconnect seek', r.connectSeekMs.toString() + ' ms'),
      ('Hold breath', r.connectHoldMs.toString() + ' ms'),
      ('Press scale', r.pressScale.toStringAsFixed(2)),
      ('Spring', r.pressStiffness.round().toString() + ' / ' +
          r.pressDamping.round().toString()),
      ('Section resize', r.sectionResizeMs.toString() + ' ms'),
      ('Dial', r.dialMs.toString() + ' ms'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in values)
          SizedBox(
            width: 116,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: raised,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$1,
                      style: const TextStyle(color: muted, fontSize: 8)),
                  const SizedBox(height: 3),
                  Text(item.$2,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _codePanel() => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0C120E),
          border: Border(top: BorderSide(color: line)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.code, color: green, size: 17),
                    const SizedBox(width: 7),
                    const Text('DART OUTPUT',
                        style: TextStyle(fontSize: 10, letterSpacing: 1)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: copyCode,
                      icon: const Icon(Icons.copy, size: 13),
                      label: const Text('کپی کد'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: line),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.5,
                      color: Color(0xFFC7D8CC),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _field(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(color: muted, fontSize: 10)),
      );

  Widget _dropdown<T>(
    T value,
    List<T> values,
    String Function(T) label,
    ValueChanged<T> onChanged,
  ) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: raised,
        style: const TextStyle(color: Colors.white, fontSize: 10),
        decoration: const InputDecoration(
          filled: true,
          fillColor: raised,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: line),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: line),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        items: [
          for (final item in values)
            DropdownMenuItem<T>(
              value: item,
              child: Text(label(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String valueLabel,
    ValueChanged<double> onChanged,
  ) =>
      Column(
        children: [
          Row(
            children: [
              Expanded(child: _field(label)),
              Text(valueLabel,
                  style: const TextStyle(color: green, fontSize: 10)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: 28,
            onChanged: onChanged,
          ),
        ],
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(
        color: muted, fontSize: 9, fontWeight: FontWeight.w800,
      ));
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x221AD995),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x554ADBA7)),
        ),
        child: Text(text, style: const TextStyle(
          color: green, fontSize: 9, fontWeight: FontWeight.w800,
        )),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x141AD995),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x3323D99A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: green, size: 14),
            const SizedBox(width: 7),
            Expanded(child: Text(text, style: const TextStyle(
              color: muted, fontSize: 9, height: 1.5,
            ))),
          ],
        ),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line.withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    const step = 26.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final center = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..color = line.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke;
    for (final radius in [90.0, 145.0, 205.0]) {
      canvas.drawCircle(center, radius, ring);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String styleName(MotionStyle style) => switch (style) {
      MotionStyle.standard => 'SILK',
      MotionStyle.smooth => 'TIDE',
      MotionStyle.dynamic => 'SPRING',
      MotionStyle.minimal => 'BLINK',
      MotionStyle.off => 'OFF',
    };

String stateName(VpnState state) => switch (state) {
      VpnState.disconnected => 'قطع‌شده',
      VpnState.starting => 'در حال شروع',
      VpnState.waitingForPermissions => 'در انتظار مجوز',
      VpnState.connecting => 'در حال اتصال',
      VpnState.connected => 'متصل',
      VpnState.reconnecting => 'اتصال مجدد',
      VpnState.disconnecting => 'در حال قطع',
      VpnState.failed => 'خطا',
    };

Curve curveValue(CurvePreset curve) => switch (curve) {
      CurvePreset.easeOutCubic => Curves.easeOutCubic,
      CurvePreset.easeOutBack => Curves.easeOutBack,
      CurvePreset.easeInOutCubic => Curves.easeInOutCubic,
      CurvePreset.easeOutQuint => Curves.easeOutQuint,
      CurvePreset.elasticOut => Curves.elasticOut,
      CurvePreset.linear => Curves.linear,
    };
