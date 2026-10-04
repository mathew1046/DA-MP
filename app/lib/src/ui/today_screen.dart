import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/settings.dart';
import '../engine/cue.dart';
import '../engine/sources.dart';
import '../insights/insights.dart';
import 'placement_screen.dart';
import 'session_screen.dart';
import 'theme.dart';
import 'walk_screen.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.onOpenInsights});

  final VoidCallback onOpenInsights;

  String _greeting(DateTime now) => now.hour < 12
      ? 'Good morning'
      : now.hour < 17
          ? 'Good afternoon'
          : 'Good evening';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final insights = Insights(store.sessions, now: now);
    final today = insights.today;
    final last = store.sessions.isEmpty ? null : store.sessions.first;
    final practice = store.settings.sensorMode == SensorMode.recording;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text(longDate(now), style: theme.textTheme.bodyMedium?.copyWith(color: Palette.muted)),
        const SizedBox(height: 4),
        Text(_greeting(now), style: theme.textTheme.headlineMedium),
        const SizedBox(height: 24),
        Panel(
          child: today.walks == 0
              ? Text('No walks yet today.', style: theme.textTheme.bodyLarge?.copyWith(color: Palette.muted))
              : Row(
                  children: [
                    Expanded(child: Stat(label: 'On your feet', value: formatDuration(today.walkingSeconds, short: true))),
                    Expanded(
                      child: Stat(
                        label: today.episodes == 1 ? 'Freeze' : 'Freezes',
                        value: '${today.episodes}',
                        color: today.episodes > 0 ? Palette.freeze : null,
                      ),
                    ),
                    Expanded(child: Stat(label: 'Time frozen', value: formatPercent(today.frozenShare))),
                  ],
                ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 96,
          child: FilledButton.icon(
            onPressed: () => startWalk(context),
            icon: const Icon(Icons.directions_walk, size: 32),
            label: const Text('Start a walk', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 72,
          child: OutlinedButton.icon(
            onPressed: () => showRhythmSheet(context),
            icon: const Icon(Icons.graphic_eq, size: 26),
            label: const Text('Play walking rhythm'),
          ),
        ),
        const SizedBox(height: 10),
        Note(practice
            ? 'Practice mode: replays recorded sensor data (Settings).'
            : 'Wear the phone upright at your waist or lower back.'),
        if (last != null) ...[
          const SizedBox(height: 32),
          Text('Last walk', style: theme.textTheme.titleMedium?.copyWith(color: Palette.muted)),
          const SizedBox(height: 10),
          Panel(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(session: last))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${relativeDay(last.start)}, ${clockTime(last.start)}', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${formatDuration(last.durationSeconds)} · '
                        '${last.episodes.length} ${last.episodes.length == 1 ? 'freeze' : 'freezes'}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Palette.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Palette.muted),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onOpenInsights, child: const Text('See all insights')),
          ),
        ],
      ],
    );
  }
}

Future<void> startWalk(BuildContext context) async {
  final scope = AppScope.of(context);
  final store = scope.store;
  final navigator = Navigator.of(context);
  if (!store.settings.placementSeen) {
    final ok = await navigator.push<bool>(MaterialPageRoute(builder: (_) => const PlacementScreen(firstTime: true)));
    if (ok != true) return;
    await store.updateSettings(store.settings.copyWith(placementSeen: true));
  }
  final MotionSource source;
  if (store.settings.sensorMode == SensorMode.recording) {
    final catalogue = await RecordingInfo.catalogue();
    final pick = catalogue[math.Random().nextInt(catalogue.length)];
    source = RecordingMotionSource(await Recording.load(pick.file));
  } else {
    source = PhoneMotionSource();
  }
  await navigator.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => WalkScreen(source: source)));
}

Future<void> showRhythmSheet(BuildContext context) {
  final settings = AppScope.of(context).store.settings;
  final cue = CueController();
  cue.start(bpm: settings.rhythmBpm, vibrate: settings.vibrationCue, maxSeconds: 20);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Palette.surface,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Step with the beat', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text('${settings.rhythmBpm} beats per minute', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Palette.muted)),
          const SizedBox(height: 28),
          SizedBox(height: 150, child: RhythmPulse(cue: cue, color: Palette.accent)),
          const SizedBox(height: 28),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Stop')),
        ],
      ),
    ),
  ).whenComplete(cue.dispose);
}
