import 'dart:math' as math;

import '../data/session.dart';
import '../ml/models.dart';

class DayTotals {
  DayTotals(this.day);

  final DateTime day;
  double walkingSeconds = 0;
  double freezingSeconds = 0;
  int episodes = 0;
  int walks = 0;

  double get frozenShare => walkingSeconds == 0 ? 0 : math.min(1, freezingSeconds / walkingSeconds);
}

class ProfileResult {
  const ProfileResult({
    required this.cluster,
    required this.clusterCount,
    required this.confidence,
    required this.agreement,
    required this.sessionsUsed,
    required this.severity,
    required this.band,
    required this.stats,
  });

  final int cluster;
  final int clusterCount;
  final double confidence;

  /// Share of individual walks that fall in the same pattern as the overall profile.
  final double agreement;
  final int sessionsUsed;

  /// 0–100 severity estimate: proximity to the more-affected cluster centre
  /// blended with the observed freezing burden.
  final double severity;
  final String band;
  final ClusterStats? stats;
}

/// Aggregations behind the Insights screen.
class Insights {
  Insights(List<Session> sessions, {DateTime? now})
      : sessions = [...sessions]..sort((a, b) => a.start.compareTo(b.start)),
        now = now ?? DateTime.now();

  final List<Session> sessions;
  final DateTime now;

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  bool get isEmpty => sessions.isEmpty;

  List<DayTotals> lastDays([int count = 7]) {
    final today = dayOf(now);
    final days = [for (var i = count - 1; i >= 0; i--) DayTotals(today.subtract(Duration(days: i)))];
    for (final s in sessions) {
      final index = days.indexWhere((d) => d.day == dayOf(s.start));
      if (index < 0) continue;
      days[index]
        ..walkingSeconds += s.walkingSeconds
        ..freezingSeconds += s.freezingSeconds
        ..episodes += s.episodes.length
        ..walks += 1;
    }
    return days;
  }

  DayTotals get today => lastDays(1).single;

  /// Freeze episodes by clock hour.
  List<int> episodesByHour() {
    final counts = List.filled(24, 0);
    for (final s in sessions) {
      for (final e in s.episodes) {
        counts[s.start.add(Duration(milliseconds: (e.start * 1000).round())).hour]++;
      }
    }
    return counts;
  }

  double _shareBetween(DateTime from, DateTime to) {
    var walking = 0.0, freezing = 0.0;
    for (final s in sessions.where((s) => !s.start.isBefore(from) && s.start.isBefore(to))) {
      walking += s.walkingSeconds;
      freezing += s.freezingSeconds;
    }
    return walking < 60 ? double.nan : freezing / walking;
  }

  /// Time frozen (share of on-feet time) this week and the week before.
  ({double thisWeek, double lastWeek}) weekComparison() {
    final end = dayOf(now).add(const Duration(days: 1));
    final mid = end.subtract(const Duration(days: 7));
    return (thisWeek: _shareBetween(mid, end), lastWeek: _shareBetween(mid.subtract(const Duration(days: 7)), mid));
  }

  double get totalWalkingSeconds => sessions.fold(0.0, (a, s) => a + s.walkingSeconds);
  double get totalFreezingSeconds => sessions.fold(0.0, (a, s) => a + s.freezingSeconds);
  int get totalEpisodes => sessions.fold(0, (a, s) => a + s.episodes.length);

  ({double? median, double withinFive, int cued}) cueResponse() {
    final values = [for (final s in sessions) for (final e in s.episodes) if (e.recoveryAfterCue != null) e.recoveryAfterCue!]..sort();
    if (values.isEmpty) return (median: null, withinFive: 0, cued: 0);
    return (
      median: values[values.length ~/ 2],
      withinFive: values.where((v) => v <= 5).length / values.length,
      cued: values.length,
    );
  }

  /// Share of episodes by length: short (<3 s), medium (3–10 s), long (>10 s).
  List<int> episodeLengths() {
    final buckets = [0, 0, 0];
    for (final s in sessions) {
      for (final e in s.episodes) {
        buckets[e.duration < 3 ? 0 : e.duration <= 10 ? 1 : 2]++;
      }
    }
    return buckets;
  }

  ProfileResult? profile(GaitProfileModel model) {
    final summaries = [for (final s in sessions) if (s.profileSummary.isNotEmpty) s.profileSummary];
    final overall = model.assign(summaries);
    if (overall == null) return null;
    final perWalk = [for (final s in summaries) model.assign([s])!.cluster];

    // Continuous severity estimate (0–100): 60% proximity to the more-affected
    // cluster centre, 40% observed freezing burden.
    var proximity = overall.cluster == 0 ? 1.0 : 0.0;
    if (model.clusterCount == 2 && overall.distances.fold(0.0, (a, b) => a + b) > 0) {
      // The cluster with the higher mean UPDRS-III (on) is the more-affected one.
      final affected = model.clusterStats.length == 2
          ? (model.clusterStats[0].updrsOn >= model.clusterStats[1].updrsOn ? 0 : 1)
          : 0;
      proximity = overall.distances[1 - affected] / (overall.distances[affected] + overall.distances[1 - affected]);
    }
    final walking = totalWalkingSeconds;
    final burden = walking < 60 ? 0.0 : math.min(1, totalFreezingSeconds / walking / 0.4);
    final severity = 100 * (0.6 * proximity + 0.4 * burden);
    final band = severity < 35 ? 'Mild' : severity < 65 ? 'Moderate' : 'High';

    return ProfileResult(
      cluster: overall.cluster,
      clusterCount: model.clusterCount,
      confidence: overall.confidence,
      agreement: perWalk.where((c) => c == overall.cluster).length / perWalk.length,
      sessionsUsed: summaries.length,
      severity: severity,
      band: band,
      stats: overall.cluster < model.clusterStats.length ? model.clusterStats[overall.cluster] : null,
    );
  }
}

String formatDuration(double seconds, {bool short = false}) {
  final s = seconds.round();
  if (s < 60) return short ? '${s}s' : '$s sec';
  final m = s ~/ 60, rest = s % 60;
  if (m < 60) {
    if (short) return m < 10 && rest > 0 ? '${m}m ${rest}s' : '${m}m';
    return rest == 0 ? '$m min' : '$m min $rest sec';
  }
  final h = m ~/ 60;
  return '${h}h ${m % 60}m';
}

/// Position within a walk, e.g. `1:02`.
String formatClock(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String formatPercent(double share) => share.isNaN ? '–' : '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%';
