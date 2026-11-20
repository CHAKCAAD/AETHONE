import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';
import 'package:aethone/features/home/widgets/glow_pill.dart';
import 'custom_widget_slot.dart';

const _bg = Color(0xFF080D0A), _panel = Color(0xFF111914), _raised = Color(0xFF18231C);
const _line = Color(0xFF2A3A30), _muted = Color(0xFF91A095), _green = Color(0xFF1AD995);

enum _Target { connectControl, connectButton, connectShake, stateHalo, customWidget }
enum _CurveKind { linear, easeOutCubic, easeInOutCubic, easeOutBack, easeOutQuint, elastic, bounce, bezier, spring }

class _Frame {
  const _Frame(this.id, this.at, this.opacity, this.scale, this.x, this.y, this.rotation, this.blur);
  final int id;
  final double at, opacity, scale, x, y, rotation, blur;
  _Frame copyWith({double? at, double? opacity, double? scale, double? x, double? y, double? rotation, double? blur}) =>
      _Frame(id, at ?? this.at, opacity ?? this.opacity, scale ?? this.scale, x ?? this.x, y ?? this.y,
        rotation ?? this.rotation, blur ?? this.blur);
  Map<String, dynamic> toJson() => {'id': id, 'at': at, 'opacity': opacity, 'scale': scale, 'x': x, 'y': y, 'rotation': rotation, 'blur': blur};
  factory _Frame.fromJson(Map<String, dynamic> j) => _Frame(
    (j['id'] as num?)?.toInt() ?? 0, (j['at'] as num?)?.toDouble() ?? 0,
    (j['opacity'] as num?)?.toDouble() ?? 1, (j['scale'] as num?)?.toDouble() ?? 1,
    (j['x'] as num?)?.toDouble() ?? 0, (j['y'] as num?)?.toDouble() ?? 0,
    (j['rotation'] as num?)?.toDouble() ?? 0, (j['blur'] as num?)?.toDouble() ?? 0,
  );
}

class _Sample {
  const _Sample(this.opacity, this.scale, this.x, this.y, this.rotation, this.blur);
  final double opacity, scale, x, y, rotation, blur;
}

class _SpringCurve extends Curve {
  const _SpringCurve(this.ms, this.mass, this.stiffness, this.damping);
  final int ms;
  final double mass, stiffness, damping;
  @override
  double transformInternal(double t) => SpringSimulation(
    SpringDescription(mass: mass, stiffness: stiffness, damping: damping), 0, 1, 0,
  ).x(t * ms / 1000);
}

class MotionStudioScreen extends StatefulWidget {
  const MotionStudioScreen({super.key});
  @override
  State<MotionStudioScreen> createState() => _MotionStudioScreenState();
}

class _MotionStudioScreenState extends State<MotionStudioScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  _Target _target = _Target.connectControl;
  _CurveKind _curve = _CurveKind.easeOutCubic;
  MotionStyle _style = MotionStyle.standard;
  VpnState _state = VpnState.disconnected;
  int _duration = 1200, _delay = 0, _nextId = 4, _selectedId = 2, _playToken = 0;
  double _speed = 1, _x1 = .22, _y1 = .75, _x2 = .36, _y2 = 1;
  double _mass = 1, _stiffness = 320, _damping = 24;
  bool _loop = false, _reverse = false, _reduceMotion = false, _showCode = true, _light = false, _playing = false;
  List<_Frame> _frames = const [
    _Frame(1, 0, 0, .82, 0, 38, -5, 10),
    _Frame(2, .55, .82, 1.04, 0, -4, 1.5, 1.5),
    _Frame(3, 1, 1, 1, 0, 0, 0, 0),
  ];
  List<Map<String, dynamic>> _presets = [];
  String? _presetName;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: _duration), value: 1);
    _controller.addStatusListener((s) {
      if (mounted && (s == AnimationStatus.completed || s == AnimationStatus.dismissed)) {
        setState(() => _playing = false);
      }
    });
    _loadPresets();
  }

  @override
  void dispose() { _playToken++; _controller.dispose(); super.dispose(); }

  _Frame get _selected => _frames.firstWhere((f) => f.id == _selectedId, orElse: () => _frames.first);

  Curve get _activeCurve => switch (_curve) {
    _CurveKind.linear => Curves.linear,
    _CurveKind.easeOutCubic => Curves.easeOutCubic,
    _CurveKind.easeInOutCubic => Curves.easeInOutCubic,
    _CurveKind.easeOutBack => Curves.easeOutBack,
    _CurveKind.easeOutQuint => Curves.easeOutQuint,
    _CurveKind.elastic => Curves.elasticOut,
    _CurveKind.bounce => Curves.bounceOut,
    _CurveKind.bezier => Cubic(_x1, _y1, _x2, _y2),
    _CurveKind.spring => _SpringCurve(_duration, _mass, _stiffness, _damping),
  };

  _Sample _sample(double progress) {
    final fs = [..._frames]..sort((a, b) => a.at.compareTo(b.at));
    final p = _activeCurve.transform(progress.clamp(0.0, 1.0).toDouble()).clamp(-.5, 1.5).toDouble();
    var a = fs.first, b = fs.last;
    if (p <= fs.first.at) { a = fs[0]; b = fs[1]; }
    else if (p >= fs.last.at) { a = fs[fs.length - 2]; b = fs.last; }
    else { for (var i = 0; i < fs.length - 1; i++) { if (p >= fs[i].at && p <= fs[i + 1].at) { a = fs[i]; b = fs[i + 1]; break; } } }
    final span = (b.at - a.at).abs() < .0001 ? 1.0 : b.at - a.at;
    final t = (p - a.at) / span;
    double mix(double x, double y) => x + (y - x) * t;
    return _Sample(mix(a.opacity, b.opacity).clamp(0.0, 1.0).toDouble(),
      mix(a.scale, b.scale).clamp(.1, 3.0).toDouble(), mix(a.x, b.x), mix(a.y, b.y),
      mix(a.rotation, b.rotation), mix(a.blur, b.blur).clamp(0.0, 40.0).toDouble());
  }

  void _scrub(double v) { _playToken++; _controller.stop(); setState(() { _playing = false; _controller.value = v.clamp(0.0, 1.0).toDouble(); }); }
  Future<void> _play() async {
    final token = ++_playToken; _controller.stop();
    if (_reduceMotion) { _scrub(1); return; }
    final ms = (_duration / _speed).round();
    _controller.duration = Duration(milliseconds: ms < 1 ? 1 : ms);
    _controller.value = 0; setState(() => _playing = true);
    if (_delay > 0) await Future<void>.delayed(Duration(milliseconds: _delay));
    if (!mounted || token != _playToken) return;
    if (_loop) { _controller.repeat(reverse: _reverse); }
    else { await _controller.forward(); if (mounted && token == _playToken) setState(() => _playing = false); }
  }
  void _pause() { _playToken++; _controller.stop(); setState(() => _playing = false); }

  void _edit(int id, _Frame Function(_Frame) change) {
    setState(() { _frames = _frames.map((f) => f.id == id ? change(f) : f).toList()..sort((a, b) => a.at.compareTo(b.at)); _selectedId = id; });
  }
  void _move(int id, double delta) {
    final i = _frames.indexWhere((f) => f.id == id);
    if (i <= 0 || i >= _frames.length - 1) return;
    final at = (_frames[i].at + delta).clamp(_frames[i - 1].at + .02, _frames[i + 1].at - .02).toDouble();
    _edit(id, (f) => f.copyWith(at: at)); _scrub(at);
  }
  void _addFrame() {
    final p = _controller.value;
    final near = _frames.reduce((a, b) => (a.at - p).abs() < (b.at - p).abs() ? a : b);
    if ((near.at - p).abs() < .025) { setState(() => _selectedId = near.id); return; }
    final s = _sample(p), id = _nextId++;
    setState(() { _frames = [..._frames, _Frame(id, p.clamp(.02, .98).toDouble(), s.opacity, s.scale, s.x, s.y, s.rotation, s.blur)]..sort((a, b) => a.at.compareTo(b.at)); _selectedId = id; });
  }
  void _removeFrame() {
    if (_frames.length < 3 || _selectedId == _frames.first.id || _selectedId == _frames.last.id) return;
    setState(() { _frames = _frames.where((f) => f.id != _selectedId).toList(); _selectedId = _frames.first.id; });
  }

  Map<String, dynamic> _spec() => {
    'version': 2, 'target': _target.name, 'curve': _curve.name, 'style': _style.name, 'state': _state.name,
    'duration': _duration, 'delay': _delay, 'speed': _speed, 'bezier': [_x1, _y1, _x2, _y2],
    'spring': [_mass, _stiffness, _damping], 'loop': _loop, 'reverse': _reverse, 'frames': _frames.map((f) => f.toJson()).toList(),
  };
  void _apply(Map<String, dynamic> j) {
    final bz = j['bezier'] as List<dynamic>?, sp = j['spring'] as List<dynamic>?, fs = j['frames'] as List<dynamic>?;
    setState(() {
      _target = _Target.values.firstWhere((v) => v.name == j['target'], orElse: () => _Target.connectControl);
      _curve = _CurveKind.values.firstWhere((v) => v.name == j['curve'], orElse: () => _CurveKind.easeOutCubic);
      _style = MotionStyle.values.firstWhere((v) => v.name == j['style'], orElse: () => MotionStyle.standard);
      _state = VpnState.values.firstWhere((v) => v.name == j['state'], orElse: () => VpnState.disconnected);
      _duration = (j['duration'] as num?)?.toInt() ?? 1200; _delay = (j['delay'] as num?)?.toInt() ?? 0; _speed = (j['speed'] as num?)?.toDouble() ?? 1;
      if (bz != null && bz.length == 4) { _x1 = (bz[0] as num).toDouble(); _y1 = (bz[1] as num).toDouble(); _x2 = (bz[2] as num).toDouble(); _y2 = (bz[3] as num).toDouble(); }
      if (sp != null && sp.length == 3) { _mass = (sp[0] as num).toDouble(); _stiffness = (sp[1] as num).toDouble(); _damping = (sp[2] as num).toDouble(); }
      _loop = j['loop'] == true; _reverse = j['reverse'] == true;
      if (fs != null && fs.length >= 2) { _frames = fs.whereType<Map<String, dynamic>>().map(_Frame.fromJson).toList()..sort((a, b) => a.at.compareTo(b.at)); _nextId = _frames.fold<int>(0, (m, f) => m > f.id ? m : f.id) + 1; _selectedId = _frames.first.id; }
      _controller.value = 0; _playing = false; _presetName = j['name'] as String?;
    });
  }
  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance(), rows = prefs.getStringList('aethone_motion_studio_presets_v2') ?? [];
      final list = <Map<String, dynamic>>[];
      for (final row in rows) { final j = jsonDecode(row); if (j is Map<String, dynamic>) list.add(j); }
      if (mounted) setState(() => _presets = list);
    } catch (_) {}
  }
  Future<void> _savePreset() async {
    final input = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      backgroundColor: _raised, title: const Text('ذخیره Preset'),
      content: TextField(controller: input, autofocus: true, decoration: const InputDecoration(hintText: 'مثلاً Spring Connect Intro')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(context, input.text.trim()), child: const Text('ذخیره'))],
    ));
    input.dispose(); if (name == null || name.isEmpty) return;
    final rows = [..._presets.where((p) => p['name'] != name), <String, dynamic>{..._spec(), 'name': name}];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('aethone_motion_studio_presets_v2', rows.map(jsonEncode).toList());
      if (mounted) { setState(() { _presets = rows; _presetName = name; }); _toast('Preset ذخیره شد'); }
    } catch (_) { _toast('ذخیره‌سازی مرورگر در دسترس نیست'); }
  }
  Future<void> _deletePreset() async {
    if (_presetName == null) return;
    final rows = _presets.where((p) => p['name'] != _presetName).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('aethone_motion_studio_presets_v2', rows.map(jsonEncode).toList());
    if (mounted) setState(() { _presets = rows; _presetName = null; });
  }
  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text)); if (mounted) _toast(message);
  }
  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String get _code {
    final rows = _frames.map((f) => '  AethoneMotionFrame(at: ' + f.at.toStringAsFixed(3) +
      ', opacity: ' + f.opacity.toStringAsFixed(3) + ', scale: ' + f.scale.toStringAsFixed(3) +
      ', x: ' + f.x.toStringAsFixed(2) + ', y: ' + f.y.toStringAsFixed(2) +
      ', rotation: ' + f.rotation.toStringAsFixed(2) + ', blur: ' + f.blur.toStringAsFixed(2) + '),').join('\n');
    final curve = switch (_curve) {
      _CurveKind.linear => 'Curves.linear', _CurveKind.easeOutCubic => 'Curves.easeOutCubic',
      _CurveKind.easeInOutCubic => 'Curves.easeInOutCubic', _CurveKind.easeOutBack => 'Curves.easeOutBack',
      _CurveKind.easeOutQuint => 'Curves.easeOutQuint', _CurveKind.elastic => 'Curves.elasticOut',
      _CurveKind.bounce => 'Curves.bounceOut',
      _CurveKind.bezier => 'Cubic(' + _x1.toStringAsFixed(3) + ', ' + _y1.toStringAsFixed(3) + ', ' + _x2.toStringAsFixed(3) + ', ' + _y2.toStringAsFixed(3) + ')',
      _CurveKind.spring => 'AethoneSpringCurve(durationSeconds: ' + (_duration / 1000).toStringAsFixed(3) + ', mass: ' + _mass.toStringAsFixed(2) + ', stiffness: ' + _stiffness.toStringAsFixed(1) + ', damping: ' + _damping.toStringAsFixed(1) + ')',
    };
    final springCode = _curve == _CurveKind.spring ? '''
class AethoneSpringCurve extends Curve {
  const AethoneSpringCurve({required this.durationSeconds, required this.mass, required this.stiffness, required this.damping});
  final double durationSeconds, mass, stiffness, damping;
  @override
  double transformInternal(double t) => SpringSimulation(SpringDescription(mass: mass, stiffness: stiffness, damping: damping), 0, 1, 0).x(t * durationSeconds);
}
''' : '';
    final style = _style.name, state = _state.name, duration = _duration;
    return '''
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:aethone/connection/connection_state.dart';
import 'package:aethone/core/motion.dart';
import 'package:aethone/features/home/widgets/connect_core.dart';
import 'package:aethone/features/home/widgets/glow_pill.dart';

// Generated by AETHONE Motion Studio 2.0.
class AethoneMotionFrame {
  const AethoneMotionFrame({required this.at, required this.opacity, required this.scale, required this.x, required this.y, required this.rotation, required this.blur});
  final double at, opacity, scale, x, y, rotation, blur;
}
$springCode
const aethoneMotionDuration = Duration(milliseconds: $duration);
const aethoneMotionCurve = $curve;
const aethoneMotionFrames = <AethoneMotionFrame>[
$rows
];

Widget buildAethoneMotionLayer({required Animation<double> progress, required Widget child}) =>
  AnimatedBuilder(animation: progress, child: child, builder: (context, kid) {
    final rawProgress = progress.value.clamp(0.0, 1.0).toDouble();
    final p = aethoneMotionCurve.transform(rawProgress).clamp(-0.5, 1.5).toDouble();
    final f = _sampleAethoneMotion(p);
    return Opacity(opacity: f.opacity.clamp(0.0, 1.0).toDouble(), child: ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: f.blur.clamp(0.0, 40.0).toDouble(), sigmaY: f.blur.clamp(0.0, 40.0).toDouble()),
      child: Transform.translate(offset: Offset(f.x, f.y), child: Transform.rotate(
        angle: f.rotation * 0.017453292519943295, child: Transform.scale(scale: f.scale, child: kid))),
    ));
  });

AethoneMotionFrame _sampleAethoneMotion(double p) {
  final fs = aethoneMotionFrames;
  var a = fs.first, b = fs.last;
  if (p <= fs.first.at) { a = fs[0]; b = fs[1]; }
  else if (p >= fs.last.at) { a = fs[fs.length - 2]; b = fs.last; }
  else { for (var i = 0; i < fs.length - 1; i++) { if (p >= fs[i].at && p <= fs[i + 1].at) { a = fs[i]; b = fs[i + 1]; break; } } }
  final span = (b.at - a.at).abs() < .0001 ? 1.0 : b.at - a.at;
  final t = (p - a.at) / span;
  double mix(double x, double y) => x + (y - x) * t;
  return AethoneMotionFrame(at: p, opacity: mix(a.opacity, b.opacity), scale: mix(a.scale, b.scale),
    x: mix(a.x, b.x), y: mix(a.y, b.y), rotation: mix(a.rotation, b.rotation), blur: mix(a.blur, b.blur));
}

Widget buildAnimatedAethoneConnectControl({required Animation<double> progress, required VoidCallback onTap}) {
  const style = MotionStyle.$style;
  const state = VpnState.$state;
  final child = SizedBox(width: 300, height: 300, child: Stack(alignment: Alignment.center, children: [
    ConnectHalo(state: state, style: style, size: 280),
    ConnectShake(state: state, style: style, child: ConnectButtonGlow(
      connected: state == VpnState.connected, state: state, style: style,
      duration: motionDuration(style, MotionDurations.state), curve: style.curve, onTap: onTap,
    )),
  ]));
  return buildAethoneMotionLayer(progress: progress, child: child);
}

// Create AnimationController(vsync: this, duration: aethoneMotionDuration)
// in the owning State and pass controller.view as progress. Halo and button
// retain their native state-driven choreography.
''';
  }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: _bg, body: SafeArea(child: Column(children: [
    Container(height: 64, padding: const EdgeInsets.symmetric(horizontal: 18), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Row(children: [
        const Text('A', style: TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 25)),
        const SizedBox(width: 10),
        const Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AETHONE MOTION STUDIO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)),
          Text('Timeline · Keyframes · Live Preview · Dart Export', style: TextStyle(color: _muted, fontSize: 9)),
        ])),
        const _Badge('V2.0'),
        IconButton(onPressed: () => setState(() => _showCode = !_showCode), icon: Icon(_showCode ? Icons.code_off : Icons.code)),
      ])),
    Expanded(child: LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 1120) return Row(children: [
        Expanded(flex: 7, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Expanded(child: _preview()),
          const SizedBox(height: 10), SizedBox(height: 260, child: _timeline()),
          if (_showCode) ...[const SizedBox(height: 10), SizedBox(height: 190, child: _codePanel())],
        ]))),
        const VerticalDivider(width: 1, color: _line),
        SizedBox(width: 370, child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: _inspector())),
      ]);
      return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
        SizedBox(height: 350, child: _preview()), const SizedBox(height: 12), _timeline(),
        const SizedBox(height: 12), _inspector(),
        if (_showCode) ...[const SizedBox(height: 12), SizedBox(height: 300, child: _codePanel())],
      ]));
    })),
  ])));

  Widget _preview() => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
    child: Column(children: [
      Row(children: [
        const Expanded(child: Text('پیش‌نمایش زنده', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
        _Badge(_playing ? 'PLAYING' : 'READY'),
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => _light = !_light), icon: Icon(_light ? Icons.dark_mode : Icons.light_mode, size: 17)),
      ]),
      const SizedBox(height: 8),
      Expanded(child: Container(width: double.infinity, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(
        color: _light ? const Color(0xFFE7EEE9) : const Color(0xFF0A120D), borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter(_light))),
          Center(child: AnimatedBuilder(animation: _controller, builder: (context, _) {
            final f = _sample(_controller.value);
            return Opacity(opacity: f.opacity, child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: f.blur, sigmaY: f.blur),
              child: Transform.translate(offset: Offset(f.x, f.y), child: Transform.rotate(
                angle: f.rotation * math.pi / 180, child: Transform.scale(scale: f.scale, child: _previewChild())))));
          })),
          Positioned(left: 10, bottom: 10, child: _Badge(_target == _Target.customWidget ? 'CUSTOM WIDGET' : 'AETHONE COMPONENT')),
          Positioned(right: 10, bottom: 10, child: _Badge((_controller.value * 100).round().toString() + '%')),
        ]),
      )),
      const SizedBox(height: 7),
      Row(children: [
        IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: _playing ? _pause : _play, icon: Icon(_playing ? Icons.pause : Icons.play_arrow)),
        IconButton(visualDensity: VisualDensity.compact, onPressed: _play, icon: const Icon(Icons.replay, size: 18)),
        Expanded(child: Slider(value: _controller.value.clamp(0.0, 1.0).toDouble(), onChanged: _scrub)),
        Text((_controller.value * _duration).round().toString() + ' ms', style: const TextStyle(color: _green, fontFamily: 'monospace', fontSize: 10)),
      ]),
    ]));

  Widget _previewChild() {
    switch (_target) {
      case _Target.connectControl:
        return SizedBox(width: 300, height: 300, child: Stack(alignment: Alignment.center, children: [
          ConnectHalo(state: _state, style: _style, size: 280),
          ConnectShake(state: _state, style: _style, child: ConnectButtonGlow(
            connected: _state == VpnState.connected, state: _state, style: _style,
            duration: motionDuration(_style, MotionDurations.state), curve: _style.curve,
            onTap: () => setState(() { _state = _nextState(_state); _controller.value = 0; }),
          )),
        ]));
      case _Target.connectButton:
        return SizedBox(width: 300, height: 300, child: Center(child: ConnectButtonGlow(
          connected: _state == VpnState.connected, state: _state, style: _style,
          duration: motionDuration(_style, MotionDurations.state), curve: _style.curve,
          onTap: () => setState(() { _state = _nextState(_state); _controller.value = 0; }),
        )));
      case _Target.connectShake:
        return SizedBox.square(dimension: 280, child: Center(child: ConnectShake(
          state: _state, style: _style,
          child: Container(width: 112, height: 112, alignment: Alignment.center,
            decoration: BoxDecoration(color: _raised, borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _green, width: 1.5),
              boxShadow: [BoxShadow(color: _green.withValues(alpha: .22), blurRadius: 24)]),
            child: const Icon(Icons.bolt_rounded, color: _green, size: 46)),
        )));
      case _Target.stateHalo:
        final accent = _state == VpnState.connected ? _green : const Color(0xFFEA4545);
        return SizedBox.square(dimension: 280, child: Stack(alignment: Alignment.center, children: [
          ConnectHalo(state: _state, style: _style, size: 280),
          Container(width: 92, height: 92, alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF101A14), shape: BoxShape.circle, border: Border.all(color: accent, width: 1.4)),
            child: const Text('A', style: TextStyle(color: _green, fontSize: 38, fontWeight: FontWeight.w800))),
        ]));
      case _Target.customWidget: return buildCustomWidgetPreview();
    }
  }

  VpnState _nextState(VpnState s) => switch (s) {
    VpnState.disconnected => VpnState.starting,
    VpnState.starting || VpnState.waitingForPermissions => VpnState.connecting,
    VpnState.connecting || VpnState.reconnecting => VpnState.connected,
    VpnState.connected => VpnState.disconnecting,
    VpnState.disconnecting => VpnState.disconnected,
    VpnState.failed => VpnState.starting,
  };

  Widget _timeline() => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('TIMELINE & KEYFRAMES', style: TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1))),
        Text(_frames.length.toString() + ' KEYFRAMES', style: const TextStyle(color: _muted, fontSize: 9)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'افزودن Keyframe', onPressed: _addFrame, icon: const Icon(Icons.add_circle_outline, size: 18)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'حذف Keyframe', onPressed: _removeFrame, icon: const Icon(Icons.delete_outline, size: 18)),
      ]),
      Expanded(child: SingleChildScrollView(child: Column(children: [
        _track('Opacity', _green), _track('Scale', const Color(0xFF6FB6FF)),
        _track('Position X', const Color(0xFFFFB86B)), _track('Position Y', const Color(0xFFFF8FAD)),
        _track('Rotation', const Color(0xFFB59AFF)), _track('Blur', const Color(0xFF7EDBCB)),
      ]))),
      Row(children: [
        const Text('PLAYHEAD', style: TextStyle(color: _muted, fontSize: 8)),
        Expanded(child: Text((_controller.value * 100).toStringAsFixed(1) + '%', style: const TextStyle(color: _green, fontSize: 9, fontFamily: 'monospace'))),
        Text('SELECTED #' + _selectedId.toString(), style: const TextStyle(color: _muted, fontSize: 8, fontFamily: 'monospace')),
      ]),
    ]));

  Widget _track(String title, Color color) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
    SizedBox(width: 76, child: Text(title, style: const TextStyle(color: _muted, fontSize: 9))),
    Expanded(child: LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth, usable = math.max(1.0, box.maxWidth - 12).toDouble();
      return SizedBox(height: 24, child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTapDown: (d) => _scrub((d.localPosition.dx / width).clamp(0.0, 1.0)))),
        Positioned(left: 0, right: 0, top: 10, child: Container(height: 2, color: _line)),
        for (final f in _frames) Positioned(left: (f.at * usable).clamp(0.0, usable), top: 4, child: GestureDetector(
          onTap: () { _scrub(f.at); setState(() => _selectedId = f.id); },
          onPanUpdate: (d) => _move(f.id, d.delta.dx / usable),
          child: Container(width: 12, height: 12, decoration: BoxDecoration(
            color: f.id == _selectedId ? color : _raised, border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(3),
            boxShadow: f.id == _selectedId ? [BoxShadow(color: color.withValues(alpha: .4), blurRadius: 8)] : null,
          )),
        )),
        Positioned(left: (_controller.value * usable).clamp(0.0, usable), top: 1, child: Container(width: 1.5, height: 20, color: Colors.white.withValues(alpha: .85))),
      ]));
    })),
  ]));

  Widget _inspector() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _section('SCENE'),
    _label('کامپوننت'),
    _dropdown<_Target>(_target, _Target.values, (v) => switch (v) {
      _Target.connectControl => 'ترکیب کامل اتصال', _Target.connectButton => 'ConnectButtonGlow', _Target.connectShake => 'ConnectShake', _Target.stateHalo => 'ConnectHalo', _Target.customWidget => 'Widget اختصاصی',
    }, (v) => setState(() => _target = v)),
    const SizedBox(height: 8), _label('وضعیت نمایشی'),
    _dropdown<VpnState>(_state, VpnState.values, _stateLabel, (v) => setState(() => _state = v)),
    const SizedBox(height: 8), _label('Motion personality اصلی'),
    _dropdown<MotionStyle>(_style, MotionStyle.values, _styleLabel, (v) => setState(() => _style = v)),
    const SizedBox(height: 14), _section('TIMING & PLAYBACK'),
    _slider('Duration', _duration.toDouble(), 120, 5000, _duration.toString() + ' ms', (v) => setState(() => _duration = v.round()), divisions: 48),
    _slider('Start delay', _delay.toDouble(), 0, 3000, _delay.toString() + ' ms', (v) => setState(() => _delay = v.round()), divisions: 30),
    _slider('Playback speed', _speed, .25, 2, _speed.toStringAsFixed(2) + 'x', (v) => setState(() => _speed = v), divisions: 35),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Loop', style: TextStyle(fontSize: 10)), value: _loop, onChanged: (v) => setState(() => _loop = v)),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Ping-pong / Reverse', style: TextStyle(fontSize: 10)), value: _reverse, onChanged: (v) => setState(() => _reverse = v)),
    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Reduce Motion test', style: TextStyle(fontSize: 10)), subtitle: const Text('حرکت سفارشی را به حالت نهایی می‌برد', style: TextStyle(fontSize: 8, color: _muted)), value: _reduceMotion, onChanged: (v) { setState(() => _reduceMotion = v); if (v) _scrub(1); }),
    const SizedBox(height: 12), _section('CURVE EDITOR'),
    _dropdown<_CurveKind>(_curve, _CurveKind.values, _curveLabel, (v) => setState(() => _curve = v)),
    if (_curve == _CurveKind.bezier) ...[
      const SizedBox(height: 8),
      _slider('P1 X', _x1, 0, 1, _x1.toStringAsFixed(2), (v) => setState(() => _x1 = v)),
      _slider('P1 Y', _y1, -.5, 1.5, _y1.toStringAsFixed(2), (v) => setState(() => _y1 = v)),
      _slider('P2 X', _x2, 0, 1, _x2.toStringAsFixed(2), (v) => setState(() => _x2 = v)),
      _slider('P2 Y', _y2, -.5, 1.5, _y2.toStringAsFixed(2), (v) => setState(() => _y2 = v)),
      SizedBox(height: 80, child: CustomPaint(painter: _BezierPainter(Cubic(_x1, _y1, _x2, _y2)), child: const SizedBox.expand())),
    ],
    if (_curve == _CurveKind.spring) ...[
      const SizedBox(height: 8),
      _slider('Mass', _mass, .2, 4, _mass.toStringAsFixed(2), (v) => setState(() => _mass = v)),
      _slider('Stiffness', _stiffness, 40, 900, _stiffness.round().toString(), (v) => setState(() => _stiffness = v)),
      _slider('Damping', _damping, 2, 90, _damping.round().toString(), (v) => setState(() => _damping = v)),
    ],
    const SizedBox(height: 14), _section('KEYFRAME PROPERTIES · #' + _selectedId.toString()),
    _slider('Opacity', _selected.opacity, 0, 1, _selected.opacity.toStringAsFixed(2), (v) => _edit(_selectedId, (f) => f.copyWith(opacity: v))),
    _slider('Scale', _selected.scale, .4, 1.8, _selected.scale.toStringAsFixed(2) + 'x', (v) => _edit(_selectedId, (f) => f.copyWith(scale: v))),
    _slider('Position X', _selected.x, -160, 160, _selected.x.round().toString() + ' px', (v) => _edit(_selectedId, (f) => f.copyWith(x: v))),
    _slider('Position Y', _selected.y, -160, 160, _selected.y.round().toString() + ' px', (v) => _edit(_selectedId, (f) => f.copyWith(y: v))),
    _slider('Rotation', _selected.rotation, -180, 180, _selected.rotation.round().toString() + '°', (v) => _edit(_selectedId, (f) => f.copyWith(rotation: v))),
    _slider('Blur', _selected.blur, 0, 32, _selected.blur.toStringAsFixed(1) + ' px', (v) => _edit(_selectedId, (f) => f.copyWith(blur: v))),
    const SizedBox(height: 14), _section('PRESETS & EXPORT'),
    _dropdown<String?>(_presetName, [null, ..._presets.map((p) => p['name'] as String)], (v) => v ?? 'انتخاب Preset', (v) {
      if (v == null) { setState(() => _presetName = null); } else { _apply(_presets.firstWhere((p) => p['name'] == v)); }
    }),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: _savePreset, icon: const Icon(Icons.bookmark_add_outlined, size: 15), label: const Text('ذخیره'))),
      const SizedBox(width: 7),
      Expanded(child: OutlinedButton.icon(onPressed: _presetName == null ? null : _deletePreset, icon: const Icon(Icons.delete_outline, size: 15), label: const Text('حذف'))),
    ]),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: FilledButton.icon(onPressed: () => _copy(_code, 'کد Dart کپی شد'), icon: const Icon(Icons.code, size: 15), label: const Text('کپی Dart'))),
      const SizedBox(width: 7),
      OutlinedButton.icon(onPressed: () => _copy(const JsonEncoder.withIndent('  ').convert(_spec()), 'JSON کپی شد'), icon: const Icon(Icons.data_object, size: 15), label: const Text('JSON')),
    ]),
    const SizedBox(height: 12),
    const _Note(text: 'این محیط فقط پیش‌نمایش طراحی است و هیچ عملیات VPN اجرا نمی‌کند. Transformهای Timeline روی کامپوننت واقعی اعمال می‌شوند؛ رفتار داخلی Halo و Spring اصلی AETHONE حفظ می‌شود.'),
  ]);

  Widget _section(String title) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
    Expanded(child: Text(title, style: const TextStyle(color: _green, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1))),
    Container(width: 40, height: 1, color: _line),
  ]));
  Widget _label(String title) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(title, style: const TextStyle(color: _muted, fontSize: 9)));
  Widget _dropdown<T>(T value, List<T> items, String Function(T) label, ValueChanged<T> onChange) => DropdownButtonFormField<T>(
    initialValue: value, isExpanded: true, dropdownColor: _raised, style: const TextStyle(color: Colors.white, fontSize: 10),
    decoration: const InputDecoration(filled: true, fillColor: _raised, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderSide: BorderSide(color: _line), borderRadius: BorderRadius.all(Radius.circular(9))),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: _line), borderRadius: BorderRadius.all(Radius.circular(9)))),
    items: [for (final v in items) DropdownMenuItem<T>(value: v, child: Text(label(v), overflow: TextOverflow.ellipsis))],
    onChanged: (v) { if (v != null) onChange(v); },
  );
  Widget _slider(String title, double value, double min, double max, String suffix, ValueChanged<double> change, {int? divisions}) =>
    Padding(padding: const EdgeInsets.only(bottom: 7), child: Column(children: [
      Row(children: [Expanded(child: _label(title)), Text(suffix, style: const TextStyle(color: _green, fontSize: 9, fontFamily: 'monospace'))]),
      Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, onChanged: change),
    ]));

  Widget _codePanel() => Container(decoration: BoxDecoration(color: const Color(0xFF0B120D), borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
    child: Column(children: [
      SizedBox(height: 38, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        const Icon(Icons.code, color: _green, size: 15), const SizedBox(width: 7), const Text('GENERATED DART', style: TextStyle(fontSize: 9, letterSpacing: 1)),
        const Spacer(), TextButton.icon(onPressed: () => _copy(_code, 'کد Dart کپی شد'), icon: const Icon(Icons.copy, size: 12), label: const Text('کپی')),
      ]))),
      const Divider(height: 1, color: _line),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(10), child: Directionality(textDirection: TextDirection.ltr,
        child: SelectableText(_code, style: const TextStyle(fontFamily: 'monospace', fontSize: 9, height: 1.45, color: Color(0xFFC7D8CC)))))),
    ]));

  String _stateLabel(VpnState s) => switch (s) {
    VpnState.disconnected => 'قطع‌شده', VpnState.starting => 'در حال شروع', VpnState.waitingForPermissions => 'در انتظار مجوز',
    VpnState.connecting => 'در حال اتصال', VpnState.connected => 'متصل', VpnState.reconnecting => 'اتصال مجدد',
    VpnState.disconnecting => 'در حال قطع', VpnState.failed => 'خطا',
  };
  String _styleLabel(MotionStyle s) => switch (s) {
    MotionStyle.standard => 'SILK · استاندارد', MotionStyle.smooth => 'TIDE · نرم', MotionStyle.dynamic => 'SPRING · پویا',
    MotionStyle.minimal => 'BLINK · حداقلی', MotionStyle.off => 'OFF · خاموش',
  };
  String _curveLabel(_CurveKind c) => switch (c) {
    _CurveKind.linear => 'Linear', _CurveKind.easeOutCubic => 'Ease Out Cubic', _CurveKind.easeInOutCubic => 'Ease In Out Cubic',
    _CurveKind.easeOutBack => 'Ease Out Back', _CurveKind.easeOutQuint => 'Ease Out Quint', _CurveKind.elastic => 'Ease Out Elastic',
    _CurveKind.bounce => 'Bounce Out', _CurveKind.bezier => 'Custom Cubic Bezier', _CurveKind.spring => 'Spring Simulation',
  };
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: const Color(0x221AD995), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x554AD995))),
    child: Text(text, style: const TextStyle(color: _green, fontSize: 8, fontWeight: FontWeight.w800)));
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0x141AD995), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x3323D99A))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, color: _green, size: 14), const SizedBox(width: 7),
      Expanded(child: Text(text, style: const TextStyle(color: _muted, fontSize: 8, height: 1.5))),
    ]));
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.light);
  final bool light;
  @override
  void paint(Canvas canvas, Size size) {
    final color = light ? const Color(0xFFB7C8BC) : _line.withValues(alpha: .42);
    final p = Paint()..color = color..strokeWidth = .6;
    for (var x = 0.0; x < size.width; x += 26) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), p); }
    for (var y = 0.0; y < size.height; y += 26) { canvas.drawLine(Offset(0, y), Offset(size.width, y), p); }
    final c = Offset(size.width / 2, size.height / 2);
    final ring = Paint()..color = color.withValues(alpha: .6)..style = PaintingStyle.stroke;
    for (final r in [90.0, 145.0, 205.0]) { canvas.drawCircle(c, r, ring); }
  }
  @override
  bool shouldRepaint(covariant _GridPainter old) => old.light != light;
}

class _BezierPainter extends CustomPainter {
  const _BezierPainter(this.curve);
  final Cubic curve;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final axis = Paint()..color = _line..strokeWidth = 1;
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.right, r.bottom), axis);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left, r.top), axis);
    final path = Path()..moveTo(r.left, r.bottom);
    for (var i = 1; i <= 60; i++) { final t = i / 60, v = curve.transform(t); path.lineTo(r.left + t * r.width, r.bottom - v * r.height); }
    canvas.drawPath(path, Paint()..color = _green..style = PaintingStyle.stroke..strokeWidth = 2);
    final points = [
      Offset(r.left + curve.a * r.width, r.bottom - curve.b * r.height),
      Offset(r.left + curve.c * r.width, r.bottom - curve.d * r.height),
    ];
    for (final p in points) { canvas.drawCircle(p, 4, Paint()..color = Colors.white); }
  }
  @override
  bool shouldRepaint(covariant _BezierPainter old) => old.curve != curve;
}
