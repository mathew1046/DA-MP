import 'package:flutter/material.dart';

import '../app.dart';
import '../engine/cue.dart';
import '../engine/monitor.dart';
import '../engine/sources.dart';
import '../engine/walk_controller.dart';
import '../insights/insights.dart';
import 'session_screen.dart';
import 'theme.dart';

class WalkScreen extends StatefulWidget {
  const WalkScreen({super.key, required this.source});

  final MotionSource source;

  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

class _WalkScreenState extends State<WalkScreen> {
  WalkController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final scope = AppScope.of(context);
      _controller = WalkController(
        store: scope.store,
        detector: scope.detector,
        profileModel: scope.profileModel,
        source: widget.source,
        monitor: BackgroundMonitor(),
      )..start();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    final session = await _controller!.finish();
    if (!mounted) return;
    if (session == null) {
      navigator.pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Walk was too short to save.')));
      return;
    }
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => SessionScreen(session: session, justFinished: true)));
  }

  Future<void> _confirmFinish() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish this walk?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep walking')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (ok == true) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmFinish();
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, controller.cue]),
        builder: (context, _) {
          final (title, subtitle, color) = switch (controller.status) {
            WalkStatus.starting => ('Getting ready', 'Start walking when you are ready.', Palette.still),
            WalkStatus.still => ('Standing still', 'Start walking when you are ready.', Palette.still),
            WalkStatus.walking => ('Walking well', 'Keep going at your own pace.', Palette.accent),
            WalkStatus.freezing => ('Freeze detected', 'Shift your weight and step with the rhythm.', Palette.freeze),
            WalkStatus.sensorError => ('Motion sensor unavailable', 'Use practice mode in Settings on this device.', Palette.freeze),
          };
          final cueing = controller.cue.active;
          final elapsed = controller.elapsed;
          final time =
              '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

          return Scaffold(
            backgroundColor: controller.status == WalkStatus.freezing ? Palette.freezeSoft : Palette.paper,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(time, style: theme.textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        const Spacer(),
                        if (controller.source.kind == 'demo')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(border: Border.all(color: Palette.line), borderRadius: BorderRadius.circular(20)),
                            child: Text('Practice', style: theme.textTheme.labelMedium?.copyWith(color: Palette.muted)),
                          ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 220,
                      child: controller.settings.visualCue || !cueing
                          ? RhythmPulse(cue: controller.cue, color: color, idle: !cueing)
                          : Icon(Icons.vibration, size: 96, color: color),
                    ),
                    const SizedBox(height: 32),
                    Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(color: color)),
                    const SizedBox(height: 8),
                    Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: Palette.muted)),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(child: _Figure(label: 'Freezes', value: '${controller.freezeCount}')),
                        Expanded(child: _Figure(label: 'On your feet', value: formatDuration(controller.walkingSeconds, short: true))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(height: 44, child: _LiveTrace(values: controller.recentIntensity.toList(), color: color)),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 72,
                      child: OutlinedButton.icon(
                        onPressed: cueing ? controller.cue.stop : controller.cueNow,
                        icon: Icon(cueing ? Icons.stop : Icons.graphic_eq, size: 26),
                        label: Text(cueing ? 'Stop rhythm' : 'Play rhythm'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: FilledButton(
                        onPressed: _confirmFinish,
                        style: FilledButton.styleFrom(backgroundColor: Palette.ink),
                        child: const Text('Finish walk', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Palette.muted)),
        ],
      );
}

/// Pulsing disc that beats with the cue; breathes slowly when idle.
class RhythmPulse extends StatefulWidget {
  const RhythmPulse({super.key, required this.cue, required this.color, this.idle = false});

  final CueController cue;
  final Color color;
  final bool idle;

  @override
  State<RhythmPulse> createState() => _RhythmPulseState();
}

class _RhythmPulseState extends State<RhythmPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  int _lastBeat = 0;

  @override
  void initState() {
    super.initState();
    widget.cue.addListener(_onCue);
  }

  void _onCue() {
    if (widget.cue.beat != _lastBeat) {
      _lastBeat = widget.cue.beat;
      _beat.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.cue.removeListener(_onCue);
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _beat,
        builder: (context, _) {
          final v = widget.idle ? 0.0 : Curves.easeOut.transform(1 - _beat.value);
          return LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest.shortestSide;
            return Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size * (0.72 + 0.28 * v),
                    height: size * (0.72 + 0.28 * v),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.10 + 0.12 * v)),
                  ),
                  Container(
                    width: size * 0.46,
                    height: size * 0.46,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: widget.idle ? 0.35 : 0.9)),
                  ),
                ],
              ),
            );
          });
        },
      );
}

class _LiveTrace extends StatelessWidget {
  const _LiveTrace({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _TracePainter(values, color), size: Size.infinite);
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = Palette.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), base);
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b).clamp(1.0, 6.0);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (60 - values.length + i) / 59;
      final y = size.height - size.height * (values[i] / maxV).clamp(0.0, 1.0);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TracePainter old) => true;
}
