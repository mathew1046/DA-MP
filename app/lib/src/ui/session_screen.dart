import 'package:flutter/material.dart';

import '../app.dart';
import '../data/session.dart';
import '../insights/insights.dart';
import 'charts.dart';
import 'theme.dart';
import 'widgets.dart';

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.session, this.justFinished = false});

  final Session session;
  final bool justFinished;

  String _headline() {
    final n = session.episodes.length;
    final walked = formatDuration(session.walkingSeconds);
    if (n == 0) return 'You were on your feet for $walked with no freezes detected.';
    final freezes = n == 1 ? 'one freeze was' : '$n freezes were';
    return 'You were on your feet for $walked and $freezes detected. '
        'The longest lasted ${formatDuration(session.longestEpisode)}.';
  }

  ({double recall, double precision})? _agreement() {
    final labelled = session.windows.where((w) => w.annotatedFog != null).toList();
    if (labelled.isEmpty || !labelled.any((w) => w.annotatedFog!)) return null;
    final truePos = labelled.where((w) => w.annotatedFog! && w.freezing).length;
    final marked = labelled.where((w) => w.annotatedFog!).length;
    final flagged = labelled.where((w) => w.freezing).length;
    return (recall: truePos / marked, precision: flagged == 0 ? 0 : truePos / flagged);
  }

  Future<void> _delete(BuildContext context) async {
    final store = AppScope.of(context).store;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this walk?'),
        content: const Text('Its measurements will be removed from your insights.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Palette.freeze),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.deleteSession(session.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detector = AppScope.of(context).detector;
    final threshold = (detector.threshold + AppScope.of(context).store.settings.thresholdShift).clamp(0.3, 0.95);
    final cadence = session.medianCadence;
    final steadiness = session.cadenceVariability;
    final recovery = session.medianRecoveryAfterCue;
    final agreement = _agreement();

    return Scaffold(
      appBar: AppBar(
        title: Text('${relativeDay(session.start)}, ${clockTime(session.start)}'),
        automaticallyImplyLeading: !justFinished,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (justFinished) ...[
              Text('Walk saved', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
            ],
            Text(_headline(), style: theme.textTheme.bodyLarge),
            if (session.isRecorded) ...[
              const SizedBox(height: 8),
              const Note('Recorded data from the Kaggle tDCS-FoG study — not your own walk.'),
            ],
            const SizedBox(height: 20),
            Panel(
              child: StatGrid(stats: [
                Stat(label: 'Duration', value: formatDuration(session.durationSeconds, short: true)),
                Stat(label: 'On your feet', value: formatDuration(session.walkingSeconds, short: true)),
                Stat(
                  label: session.episodes.length == 1 ? 'Freeze' : 'Freezes',
                  value: '${session.episodes.length}',
                  color: session.episodes.isEmpty ? null : Palette.freeze,
                ),
                Stat(label: 'Time frozen', value: formatPercent(session.frozenShare)),
                Stat(label: 'Longest freeze', value: session.episodes.isEmpty ? '–' : formatDuration(session.longestEpisode, short: true)),
                Stat(label: 'Steps per minute', value: cadence == null ? '–' : cadence.round().toString()),
                Stat(label: 'Step rhythm variation', value: steadiness == null ? '–' : '${steadiness.toStringAsFixed(0)}%'),
                Stat(label: 'Back to walking after cue', value: recovery == null ? '–' : formatDuration(recovery, short: true)),
              ]),
            ),
            const SizedBox(height: 16),
            Section(
              title: 'Movement',
              caption: 'Second-by-second movement; shaded areas are detected freezes.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MovementTimeline(session: session),
                  const SizedBox(height: 10),
                  const Legend(items: [(Palette.accent, 'Movement (m/s²)'), (Palette.freezeSoft, 'Freeze')]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Section(
              title: 'Freeze likelihood',
              caption: 'Model estimate per moment; a freeze counts above the dashed line.',
              child: LikelihoodChart(session: session, threshold: threshold),
            ),
            if (agreement != null) ...[
              const SizedBox(height: 16),
              Section(
                title: 'Compared with clinicians',
                caption: 'Clinician video annotations vs app alerts.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AgreementStrip(session: session),
                    const SizedBox(height: 18),
                    StatGrid(stats: [
                      Stat(label: 'Marked freezing detected', value: formatPercent(agreement.recall)),
                      Stat(label: 'Alerts confirmed', value: formatPercent(agreement.precision)),
                    ]),
                  ],
                ),
              ),
            ],
            if (session.episodes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Section(
                title: 'Each freeze',
                child: Column(
                  children: [
                    for (final (i, e) in session.episodes.indexed) ...[
                      if (i > 0) const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(child: Text('At ${formatClock(e.start)}', style: theme.textTheme.bodyLarge)),
                          Text(formatDuration(e.duration, short: true), style: theme.textTheme.titleMedium),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 130,
                            child: Text(
                              e.recoveryAfterCue == null
                                  ? 'No cue'
                                  : 'walking ${formatDuration(e.recoveryAfterCue!, short: true)} after cue',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(color: Palette.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (justFinished)
              SizedBox(height: 72, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')))
            else
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Palette.freeze),
                onPressed: () => _delete(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete this walk'),
              ),
          ],
        ),
      ),
    );
  }
}
