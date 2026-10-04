import 'package:flutter/material.dart';

import 'theme.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

/// Section with a heading, optional explanatory line and content.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.caption, required this.child, this.trailing});

  final String title;
  final String? caption;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              ?trailing,
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: theme.textTheme.bodyMedium?.copyWith(color: Palette.muted)),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, this.color, this.large = false});

  final String label;
  final String value;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: (large ? theme.textTheme.headlineMedium : theme.textTheme.headlineSmall)?.copyWith(color: color ?? Palette.ink),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Palette.muted)),
      ],
    );
  }
}

/// Two-column grid of [Stat]s.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.stats});

  final List<Stat> stats;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 22,
            children: [for (final s in stats) SizedBox(width: width, child: s)],
          );
        },
      );
}

class Legend extends StatelessWidget {
  const Legend({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          for (final (color, label) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Palette.muted)),
              ],
            ),
        ],
      );
}

class Note extends StatelessWidget {
  const Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Palette.muted),
      );
}

String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String longDate(DateTime t) => '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]}';
String shortWeekday(DateTime t) => _weekdays[t.weekday - 1].substring(0, 3);

String relativeDay(DateTime t, {DateTime? now}) {
  final today = DateTime((now ?? DateTime.now()).year, (now ?? DateTime.now()).month, (now ?? DateTime.now()).day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return _weekdays[t.weekday - 1];
  return '${t.day} ${_months[t.month - 1].substring(0, 3)}';
}
