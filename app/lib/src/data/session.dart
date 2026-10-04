import 'dart:math' as math;

/// One analysed 2-second window (computed every second).
class WindowPoint {
  const WindowPoint({
    required this.t,
    required this.probability,
    required this.freezing,
    required this.walking,
    required this.intensity,
    this.cadence,
    this.annotatedFog,
  });

  /// Window start, seconds from session start.
  final double t;
  final double probability;
  final bool freezing;
  final bool walking;

  /// Standard deviation of acceleration magnitude (m/s²).
  final double intensity;

  /// Estimated steps per minute while walking.
  final double? cadence;

  /// Expert label, only present for bundled sample recordings.
  final bool? annotatedFog;

  Map<String, dynamic> toJson() => {
        't': t,
        'p': double.parse(probability.toStringAsFixed(3)),
        'f': freezing,
        'w': walking,
        'i': double.parse(intensity.toStringAsFixed(3)),
        if (cadence != null) 'c': double.parse(cadence!.toStringAsFixed(1)),
        if (annotatedFog != null) 'a': annotatedFog,
      };

  factory WindowPoint.fromJson(Map<String, dynamic> j) => WindowPoint(
        t: (j['t'] as num).toDouble(),
        probability: (j['p'] as num).toDouble(),
        freezing: j['f'] as bool,
        walking: j['w'] as bool,
        intensity: (j['i'] as num).toDouble(),
        cadence: (j['c'] as num?)?.toDouble(),
        annotatedFog: j['a'] as bool?,
      );
}

class FogEpisode {
  FogEpisode({required this.start, required this.end, this.cueStart});

  final double start;
  double end;

  /// Seconds from session start at which a cue began, if one was given.
  double? cueStart;

  double get duration => end - start;
  double? get recoveryAfterCue => cueStart == null ? null : math.max(0, end - cueStart!);

  Map<String, dynamic> toJson() => {'s': start, 'e': end, if (cueStart != null) 'c': cueStart};

  factory FogEpisode.fromJson(Map<String, dynamic> j) => FogEpisode(
        start: (j['s'] as num).toDouble(),
        end: (j['e'] as num).toDouble(),
        cueStart: (j['c'] as num?)?.toDouble(),
      );
}

class Session {
  Session({
    required this.id,
    required this.start,
    required this.durationSeconds,
    required this.source,
    required this.windows,
    required this.episodes,
    required this.profileSummary,
    this.cueCount = 0,
    this.manualCueCount = 0,
  });

  final String id;
  final DateTime start;
  final double durationSeconds;

  /// `phone`, `demo` (live replay) or `sample` (pre-loaded history).
  final String source;
  final List<WindowPoint> windows;
  final List<FogEpisode> episodes;
  final Map<String, double> profileSummary;
  final int cueCount;
  final int manualCueCount;

  static const windowStepSeconds = 1.0;

  bool get isRecorded => source != 'phone';
  double get walkingSeconds => windows.where((w) => w.walking || w.freezing).length * windowStepSeconds;
  double get freezingSeconds => episodes.fold(0.0, (a, e) => a + e.duration);
  double get longestEpisode => episodes.isEmpty ? 0 : episodes.map((e) => e.duration).reduce(math.max);

  /// Share of on-feet time spent freezing (0–1).
  double get frozenShare {
    final active = math.max(walkingSeconds, freezingSeconds);
    return active == 0 ? 0 : math.min(1, freezingSeconds / active);
  }

  double? get medianCadence {
    final values = [for (final w in windows) if (w.walking && !w.freezing && w.cadence != null) w.cadence!]..sort();
    return values.isEmpty ? null : values[values.length ~/ 2];
  }

  /// Coefficient of variation of cadence (%), lower means steadier rhythm.
  double? get cadenceVariability {
    final values = [for (final w in windows) if (w.walking && !w.freezing && w.cadence != null) w.cadence!];
    if (values.length < 5) return null;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sd = math.sqrt(values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length);
    return mean == 0 ? null : 100 * sd / mean;
  }

  double? get medianRecoveryAfterCue {
    final values = [for (final e in episodes) if (e.recoveryAfterCue != null) e.recoveryAfterCue!]..sort();
    return values.isEmpty ? null : values[values.length ~/ 2];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'duration': durationSeconds,
        'source': source,
        'cues': cueCount,
        'manualCues': manualCueCount,
        'windows': [for (final w in windows) w.toJson()],
        'episodes': [for (final e in episodes) e.toJson()],
        'profile': profileSummary,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        durationSeconds: (j['duration'] as num).toDouble(),
        source: j['source'] as String,
        cueCount: (j['cues'] as num?)?.toInt() ?? 0,
        manualCueCount: (j['manualCues'] as num?)?.toInt() ?? 0,
        windows: [for (final w in j['windows'] as List) WindowPoint.fromJson(Map<String, dynamic>.from(w))],
        episodes: [for (final e in j['episodes'] as List) FogEpisode.fromJson(Map<String, dynamic>.from(e))],
        profileSummary: {
          for (final e in Map<String, dynamic>.from(j['profile'] as Map).entries) e.key: (e.value as num).toDouble(),
        },
      );
}
