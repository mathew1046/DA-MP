import 'package:flutter/material.dart';

import '../app.dart';
import '../engine/walk_controller.dart';
import '../insights/insights.dart';
import 'charts.dart';
import 'session_screen.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> loadSampleHistory(BuildContext context) async {
  final scope = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await scope.store.deleteWhere((s) => s.source == 'sample');
  final sessions = await buildSampleHistory(
    detector: scope.detector,
    profileModel: scope.profileModel,
    thresholdShift: scope.store.settings.thresholdShift,
  );
  await scope.store.addSessions(sessions);
  messenger.showSnackBar(SnackBar(content: Text('Added ${sessions.length} sample walks.')));
}

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  String _weekSentence(({double thisWeek, double lastWeek}) c) {
    if (c.thisWeek.isNaN) return 'Weekly comparison appears after a few walks.';
    final now = '${formatPercent(c.thisWeek)} of on-feet time frozen this week';
    if (c.lastWeek.isNaN) return '$now.';
    if (c.thisWeek < c.lastWeek * 0.85) return '$now, down from ${formatPercent(c.lastWeek)} last week.';
    if (c.thisWeek > c.lastWeek * 1.15) return '$now, up from ${formatPercent(c.lastWeek)} last week.';
    return '$now, similar to last week.';
  }

  String? _peakSentence(List<int> byHour) {
    final blocks = HourChart.blocks(byHour);
    final total = blocks.fold(0, (a, b) => a + b);
    if (total < 3) return null;
    var best = 0;
    for (var i = 1; i < blocks.length; i++) {
      if (blocks[i] > blocks[best]) best = i;
    }
    String h(int hour) => hour % 24 == 0 ? '12 am' : hour < 12 ? '$hour am' : hour == 12 ? '12 pm' : '${hour - 12} pm';
    return 'Freezes were most common between ${h(best * 2)} and ${h(best * 2 + 2)}.';
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final insights = Insights(scope.store.sessions);

    if (insights.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text('Insights', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text('Insights appear after your first walk.', style: theme.textTheme.bodyLarge?.copyWith(color: Palette.muted)),
          const SizedBox(height: 24),
          SizedBox(
            height: 64,
            child: OutlinedButton(onPressed: () => loadSampleHistory(context), child: const Text('Show sample walks')),
          ),
          const SizedBox(height: 8),
          const Note('Real recordings from the Kaggle Freezing of Gait dataset.'),
        ],
      );
    }

    final days = insights.lastDays();
    final comparison = insights.weekComparison();
    final byHour = insights.episodesByHour();
    final peak = _peakSentence(byHour);
    final cue = insights.cueResponse();
    final lengths = insights.episodeLengths();
    final profile = insights.profile(scope.profileModel);
    final chronological = insights.sessions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('Insights', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(_weekSentence(comparison), style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        Panel(
          child: Row(
            children: [
              Expanded(child: Stat(label: 'Walks', value: '${insights.sessions.length}')),
              Expanded(child: Stat(label: 'On your feet', value: formatDuration(insights.totalWalkingSeconds, short: true))),
              Expanded(child: Stat(label: 'Freezes', value: '${insights.totalEpisodes}', color: Palette.freeze)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Last 7 days',
          caption: 'Daily minutes on your feet vs frozen.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WeekChart(days: days),
              const SizedBox(height: 10),
              const Legend(items: [(Palette.accent, 'On your feet'), (Palette.freeze, 'Frozen')]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Time of day',
          caption: peak ?? 'Freezes per two-hour block.',
          child: HourChart(byHour: byHour),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Time frozen per walk',
          caption: 'Share of each walk spent frozen.',
          child: WalkTrend(
            values: [for (final s in chronological) s.walkingSeconds < 10 ? null : s.frozenShare * 100],
            format: (v) => '${v.round()}%',
            color: Palette.freeze,
          ),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Walking rhythm',
          caption: 'Median steps per minute per walk.',
          child: WalkTrend(values: [for (final s in chronological) s.medianCadence], format: (v) => v.round().toString()),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'How long freezes last',
          child: ProportionBars(items: [
            ('Under 3 sec', lengths[0]),
            ('3 to 10 sec', lengths[1]),
            ('Over 10 sec', lengths[2]),
          ]),
        ),
        const SizedBox(height: 16),
        Section(
          title: 'Rhythm cue',
          caption: 'Time from cue start to walking again.',
          child: cue.median == null
              ? const Note('No cued freezes yet.')
              : StatGrid(stats: [
                  Stat(label: 'Typical time to walk again', value: formatDuration(cue.median!, short: true)),
                  Stat(label: 'Walking again within 5 sec', value: formatPercent(cue.withinFive)),
                ]),
        ),
        if (profile != null) ...[
          const SizedBox(height: 16),
          Section(
            title: 'Gait severity',
            caption: 'K-means profile from ${profile.sessionsUsed} ${profile.sessionsUsed == 1 ? 'walk' : 'walks'}.',
            child: _PatternView(profile: profile),
          ),
        ],
        const SizedBox(height: 28),
        Text('All walks', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, s) in scope.store.sessions.indexed) ...[
                if (i > 0) const Divider(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  title: Text('${relativeDay(s.start)}, ${clockTime(s.start)}', style: theme.textTheme.titleMedium),
                  subtitle: Text(
                    '${formatDuration(s.durationSeconds)} · ${s.episodes.length} '
                    '${s.episodes.length == 1 ? 'freeze' : 'freezes'}${s.isRecorded ? ' · recorded' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Palette.muted),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Palette.muted),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(session: s))),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Note('StepCue is a research prototype, not a medical device.'),
      ],
    );
  }
}

class _PatternView extends StatelessWidget {
  const _PatternView({required this.profile});

  final ProfileResult profile;

  Color get _bandColor => switch (profile.band) {
        'Mild' => Palette.accent,
        'Moderate' => const Color(0xFFB07A2A),
        _ => Palette.freeze,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = profile.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(profile.severity.round().toString(), style: theme.textTheme.displayMedium?.copyWith(color: _bandColor)),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 10),
              child: Text('/ 100', style: theme.textTheme.bodyLarge?.copyWith(color: Palette.muted)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _bandColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(profile.band, style: theme.textTheme.titleMedium?.copyWith(color: _bandColor)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: profile.severity / 100,
            minHeight: 8,
            backgroundColor: Palette.line,
            valueColor: AlwaysStoppedAnimation(_bandColor),
          ),
        ),
        const SizedBox(height: 20),
        StatGrid(stats: [
          Stat(label: 'Pattern group', value: String.fromCharCode(65 + profile.cluster)),
          Stat(label: 'Walks matching', value: formatPercent(profile.agreement)),
          if (stats != null) ...[
            Stat(label: 'Group UPDRS-III (on)', value: stats.updrsOn.toStringAsFixed(1)),
            Stat(label: 'Group freeze rate', value: formatPercent(stats.fogRate)),
            Stat(label: 'Group NFOG-Q', value: stats.nfogq.toStringAsFixed(1)),
            Stat(label: 'People in group', value: '${stats.subjects}'),
          ],
        ]),
        const SizedBox(height: 12),
        const Note('Estimate from 60-subject K-means profiles and your observed freezing. Demo only — not a clinical rating.'),
      ],
    );
  }
}
