import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/session.dart';
import '../insights/insights.dart';
import 'theme.dart';
import 'widgets.dart';

const _axisStyle = TextStyle(fontSize: 13, color: Palette.muted);

FlGridData _grid(double? interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => const FlLine(color: Palette.line, strokeWidth: 1),
    );

AxisTitles _hidden() => const AxisTitles(sideTitles: SideTitles(showTitles: false));

AxisTitles _axis(String Function(double) label, {double? interval, double reserved = 28}) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: interval,
        reservedSize: reserved,
        getTitlesWidget: (value, meta) {
          if (value != meta.min && value != meta.max && interval != null && (value / interval - (value / interval).round()).abs() > 1e-6) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(meta: meta, child: Text(label(value), style: _axisStyle));
        },
      ),
    );

double _niceStep(double maxValue, {int ticks = 3}) {
  if (maxValue <= 0) return 1;
  final raw = maxValue / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (raw <= m * magnitude) return m * magnitude;
  }
  return 10 * magnitude;
}

String _clock(double seconds) {
  final s = seconds.round();
  return s < 60 ? '${s}s' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Movement intensity across a walk with detected freezes shaded.
class MovementTimeline extends StatelessWidget {
  const MovementTimeline({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final points = session.windows;
    if (points.length < 2) return const Note('Not enough data to draw this walk.');
    final maxX = math.max(session.durationSeconds, points.last.t + 2);
    final maxY = math.max(1.5, points.map((p) => p.intensity).reduce(math.max) * 1.1);
    final yStep = _niceStep(maxY);
    return AspectRatio(
      aspectRatio: 1.9,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: 0,
          maxY: (maxY / yStep).ceil() * yStep,
          gridData: _grid(yStep),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          rangeAnnotations: RangeAnnotations(
            verticalRangeAnnotations: [
              for (final e in session.episodes) VerticalRangeAnnotation(x1: e.start, x2: e.end, color: Palette.freezeSoft),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: _hidden(),
            rightTitles: _hidden(),
            leftTitles: _axis((v) => v.toStringAsFixed(v < 2 ? 1 : 0), interval: yStep, reserved: 34),
            bottomTitles: _axis(_clock, interval: _niceStep(maxX, ticks: 4)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in points) FlSpot(p.t + 1, p.intensity)],
              isCurved: true,
              curveSmoothness: 0.2,
              color: Palette.accent,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Model probability per window with the alert threshold.
class LikelihoodChart extends StatelessWidget {
  const LikelihoodChart({super.key, required this.session, required this.threshold});

  final Session session;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final points = session.windows;
    if (points.length < 2) return const SizedBox.shrink();
    final maxX = math.max(session.durationSeconds, points.last.t + 2);
    return AspectRatio(
      aspectRatio: 2.4,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: 0,
          maxY: 1,
          gridData: _grid(0.5),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: threshold, color: Palette.freeze, strokeWidth: 1.2, dashArray: [6, 4]),
          ]),
          titlesData: FlTitlesData(
            topTitles: _hidden(),
            rightTitles: _hidden(),
            leftTitles: _axis((v) => '${(v * 100).round()}%', interval: 0.5, reserved: 44),
            bottomTitles: _axis(_clock, interval: _niceStep(maxX, ticks: 4)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in points) FlSpot(p.t + 1, p.probability)],
              color: Palette.ink,
              barWidth: 1.6,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two aligned strips comparing detected freezes with expert labels.
class AgreementStrip extends StatelessWidget {
  const AgreementStrip({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _strip(context, 'Detected by the app', (w) => w.freezing),
          const SizedBox(height: 10),
          _strip(context, 'Marked by clinicians', (w) => w.annotatedFog ?? false),
        ],
      );

  Widget _strip(BuildContext context, String label, bool Function(WindowPoint) on) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Palette.muted)),
          const SizedBox(height: 4),
          SizedBox(
            height: 14,
            child: CustomPaint(size: Size.infinite, painter: _StripPainter([for (final w in session.windows) on(w)])),
          ),
        ],
      );
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.flags);

  final List<bool> flags;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.accentSoft);
    final w = size.width / math.max(1, flags.length);
    final paint = Paint()..color = Palette.freeze;
    for (var i = 0; i < flags.length; i++) {
      if (flags[i]) canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.5, size.height), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.flags != flags;
}

/// Minutes on feet and minutes frozen for each of the last days.
class WeekChart extends StatelessWidget {
  const WeekChart({super.key, required this.days});

  final List<DayTotals> days;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = days.map((d) => d.walkingSeconds / 60).fold(0.0, math.max);
    final step = _niceStep(math.max(maxMinutes, 1));
    final top = math.max(step, (maxMinutes / step).ceil() * step);
    return AspectRatio(
      aspectRatio: 1.7,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          gridData: _grid(step),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          alignment: BarChartAlignment.spaceAround,
          titlesData: FlTitlesData(
            topTitles: _hidden(),
            rightTitles: _hidden(),
            leftTitles: _axis((v) => v.toStringAsFixed(step < 1 ? 1 : 0), interval: step, reserved: 34),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(shortWeekday(days[value.toInt()].day), style: _axisStyle),
                ),
              ),
            ),
          ),
          barGroups: [
            for (final (i, d) in days.indexed)
              BarChartGroupData(
                x: i,
                barsSpace: 3,
                barRods: [
                  BarChartRodData(
                    toY: d.walkingSeconds / 60,
                    width: 12,
                    color: Palette.accent,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  BarChartRodData(
                    toY: d.freezingSeconds / 60,
                    width: 12,
                    color: Palette.freeze,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Freeze episodes per two-hour block of the day.
class HourChart extends StatelessWidget {
  const HourChart({super.key, required this.byHour});

  final List<int> byHour;

  static List<int> blocks(List<int> byHour) => [for (var b = 0; b < 12; b++) byHour[2 * b] + byHour[2 * b + 1]];

  @override
  Widget build(BuildContext context) {
    final counts = blocks(byHour);
    final maxCount = counts.reduce(math.max).toDouble();
    final step = _niceStep(math.max(maxCount, 2), ticks: 2).ceilToDouble();
    return AspectRatio(
      aspectRatio: 2.0,
      child: BarChart(
        BarChartData(
          maxY: math.max(step, (maxCount / step).ceil() * step),
          gridData: _grid(step),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: _hidden(),
            rightTitles: _hidden(),
            leftTitles: _axis((v) => v.toStringAsFixed(0), interval: step, reserved: 28),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final hour = value.toInt() * 2;
                  if (hour % 6 != 0) return const SizedBox.shrink();
                  final label = hour == 0 ? '12am' : hour < 12 ? '${hour}am' : hour == 12 ? '12pm' : '${hour - 12}pm';
                  return SideTitleWidget(meta: meta, child: Text(label, style: _axisStyle));
                },
              ),
            ),
          ),
          barGroups: [
            for (final (i, c) in counts.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: c.toDouble(),
                  width: 14,
                  color: c == 0 ? Palette.line : Palette.freeze,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Simple per-walk trend line (e.g. steps per minute, % time frozen).
class WalkTrend extends StatelessWidget {
  const WalkTrend({super.key, required this.values, required this.format, this.color = Palette.accent});

  final List<double?> values;
  final String Function(double) format;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = [for (final (i, v) in values.indexed) if (v != null) FlSpot(i.toDouble() + 1, v)];
    if (spots.length < 2) return const Note('Trends appear after two or more walks.');
    final maxY = spots.map((s) => s.y).reduce(math.max);
    final minY = spots.map((s) => s.y).reduce(math.min);
    final pad = math.max((maxY - minY) * 0.25, maxY.abs() * 0.05 + 0.01);
    final step = _niceStep(maxY - minY + 2 * pad);
    final lo = math.max(0.0, ((minY - pad) / step).floor() * step);
    final hi = ((maxY + pad) / step).ceil() * step;
    return AspectRatio(
      aspectRatio: 2.2,
      child: LineChart(
        LineChartData(
          minX: 1,
          maxX: values.length.toDouble(),
          minY: lo,
          maxY: hi,
          gridData: _grid(step),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: _hidden(),
            rightTitles: _hidden(),
            leftTitles: _axis(format, interval: step, reserved: 44),
            bottomTitles: _axis((v) => 'Walk ${v.toInt()}', interval: math.max(1, (values.length / 4).ceilToDouble()), reserved: 28),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: color,
              barWidth: 2,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(radius: 3.5, color: Palette.surface, strokeColor: color, strokeWidth: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal proportion bars, e.g. freeze lengths.
class ProportionBars extends StatelessWidget {
  const ProportionBars({super.key, required this.items});

  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0, (a, e) => a + e.$2);
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final (label, count) in items) ...[
          Row(
            children: [
              SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodyMedium)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : count / total,
                    minHeight: 14,
                    color: Palette.freeze,
                    backgroundColor: Palette.line,
                  ),
                ),
              ),
              SizedBox(width: 44, child: Text('$count', textAlign: TextAlign.right, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
