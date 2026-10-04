import 'package:flutter/material.dart';

import '../app.dart';
import '../data/settings.dart';
import 'insights_screen.dart';
import 'placement_screen.dart';
import 'theme.dart';
import 'today_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final s = store.settings;
    final theme = Theme.of(context);
    final metrics = scope.detector.metrics;
    void update(AppSettings next) => store.updateSettings(next);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('Settings', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 20),
        Section(
          title: 'Rhythm cue',
          caption: 'Plays automatically when a freeze is detected.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SwitchRow(label: 'Vibration', value: s.vibrationCue, onChanged: (v) => update(s.copyWith(vibrationCue: v))),
              _SwitchRow(label: 'Pulse on screen', value: s.visualCue, onChanged: (v) => update(s.copyWith(visualCue: v))),
              const SizedBox(height: 16),
              Text('Speed', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 80, label: Text('Slow')),
                  ButtonSegment(value: 100, label: Text('Medium')),
                  ButtonSegment(value: 120, label: Text('Fast')),
                ],
                selected: {s.rhythmBpm},
                onSelectionChanged: (v) => update(s.copyWith(rhythmBpm: v.first)),
              ),
              const SizedBox(height: 16),
              Text('Length', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 10, label: Text('10 sec')),
                  ButtonSegment(value: 15, label: Text('15 sec')),
                  ButtonSegment(value: 20, label: Text('20 sec')),
                ],
                selected: {s.maxCueSeconds},
                onSelectionChanged: (v) => update(s.copyWith(maxCueSeconds: v.first)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => showRhythmSheet(context), child: const Text('Try the rhythm')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Freeze alerts',
          caption: 'Higher sensitivity catches more freezes, with more false alerts.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<Sensitivity>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Sensitivity.fewer, label: Text('Fewer')),
                  ButtonSegment(value: Sensitivity.balanced, label: Text('Balanced')),
                  ButtonSegment(value: Sensitivity.more, label: Text('More')),
                ],
                selected: {s.sensitivity},
                onSelectionChanged: (v) => update(s.copyWith(sensitivity: v.first)),
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                label: 'Monitor in background',
                value: s.backgroundMonitor,
                onChanged: (v) => update(s.copyWith(backgroundMonitor: v)),
              ),
              const Note('Shows a notification while detecting; vibration cues still work.'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Motion data',
          caption: 'Practice mode replays recorded walks.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<SensorMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SensorMode.phone, label: Text('This phone')),
                  ButtonSegment(value: SensorMode.recording, label: Text('Practice')),
                ],
                selected: {s.sensorMode},
                onSelectionChanged: (v) => update(s.copyWith(sensorMode: v.first)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlacementScreen())),
                child: const Text('How to wear your phone'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Your data',
          caption: 'Walks are stored only on this phone.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(onPressed: () => loadSampleHistory(context), child: const Text('Add sample walks')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => store.deleteWhere((x) => x.source == 'sample'),
                child: const Text('Remove sample walks'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Palette.freeze),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete all walks?'),
                      content: const Text('This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: Palette.freeze),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete all'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await store.deleteWhere((_) => true);
                },
                child: const Text('Delete all walks'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'About the detector',
          caption: 'Lower-back accelerometer model (Kaggle tDCS-FoG); ${metrics['held_out_subjects']} held-out subjects.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatGrid(stats: [
                Stat(label: 'Balanced accuracy', value: formatShare(metrics['held_out_balanced_accuracy'])),
                Stat(label: 'F1 score', value: (metrics['held_out_f1'] as num).toStringAsFixed(2)),
              ]),
              const SizedBox(height: 16),
              const Note('Research prototype — not for diagnosis, severity grading, or fall detection.'),
            ],
          ),
        ),
      ],
    );
  }
}

String formatShare(Object? v) => '${((v as num) * 100).round()}%';

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      );
}
