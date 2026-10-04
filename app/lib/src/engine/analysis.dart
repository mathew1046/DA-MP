import 'dart:math' as math;

import '../data/session.dart';
import '../ml/features.dart';
import '../ml/models.dart';

/// Streaming analysis: resamples raw accelerometer samples to the model's rate,
/// scores overlapping 2-second windows and groups positive windows into
/// freeze episodes.
class AnalysisEngine {
  AnalysisEngine({
    required this.detector,
    required this.profileModel,
    double thresholdShift = 0,
    this.onWindow,
    this.onFreezeStart,
    this.onFreezeEnd,
  })  : threshold = (detector.threshold + thresholdShift).clamp(0.3, 0.95),
        _extractor = FeatureExtractor(samplingRate: detector.samplingRate);

  final FogDetector detector;
  final GaitProfileModel profileModel;
  final double threshold;
  final void Function(WindowPoint point)? onWindow;

  /// Called with the stream time (seconds) at which the freeze was confirmed.
  final void Function(FogEpisode episode, double detectedAt)? onFreezeStart;
  final void Function(FogEpisode episode)? onFreezeEnd;

  /// Consecutive positive windows required to open an episode.
  static const confirmWindows = 2;

  /// Consecutive negative windows required to close an episode.
  static const releaseWindows = 2;

  /// Minimum movement (SD of acceleration magnitude, m/s²) to count as on-feet activity.
  static const activityThreshold = 0.45;

  final FeatureExtractor _extractor;
  final List<WindowPoint> windows = [];
  final List<FogEpisode> episodes = [];
  final List<Map<String, double>> _featureHistory = [];

  final List<List<double>> _buffer = [];
  final List<bool?> _truth = [];
  int _emitted = 0;
  int _sinceHop = 0;
  double? _t0, _lastT;
  List<double>? _last;
  bool? _lastTruth;
  int _hot = 0, _cold = 0;
  double? _firstHotT;
  FogEpisode? _open;

  double get _dt => 1 / detector.samplingRate;
  double get streamSeconds => _emitted * _dt;
  bool get isFreezing => _open != null;

  /// Adds one raw sample. [t] is in seconds on any monotonic clock.
  void addSample(double t, double v, double ml, double ap, {bool? annotatedFog}) {
    _t0 ??= t;
    final rel = t - _t0!;
    final current = [v, ml, ap];
    if (_last == null) {
      _push(current, annotatedFog);
      _last = current;
      _lastT = rel;
      _lastTruth = annotatedFog;
      return;
    }
    if (rel <= _lastT!) return;
    while (_emitted * _dt <= rel) {
      final g = _emitted * _dt;
      final f = (g - _lastT!) / (rel - _lastT!);
      _push([for (var i = 0; i < 3; i++) _last![i] + (current[i] - _last![i]) * f], f < 0.5 ? _lastTruth : annotatedFog);
    }
    _last = current;
    _lastT = rel;
    _lastTruth = annotatedFog;
  }

  void _push(List<double> row, bool? truth) {
    _buffer.add(row);
    _truth.add(truth);
    _emitted++;
    _sinceHop++;
    if (_buffer.length > detector.windowSamples) {
      _buffer.removeAt(0);
      _truth.removeAt(0);
    }
    if (_buffer.length == detector.windowSamples && _sinceHop >= detector.hopSamples) {
      _sinceHop = 0;
      _analyse();
    }
  }

  void _analyse() {
    final n = detector.windowSamples;
    final t = (_emitted - n) * _dt;
    final features = _extractor.extract(_buffer);
    final p = detector.probability(features);
    final intensity = features['Magnitude_std'] ?? 0;
    final cadence = estimateCadence(_buffer.map((r) => r[0]).toList(), detector.samplingRate);
    final labelled = _truth.whereType<bool>().toList();
    final hot = p >= threshold;
    _featureHistory.add(features);

    if (hot) {
      _hot++;
      _cold = 0;
      _firstHotT ??= t;
      if (_open == null && _hot >= confirmWindows) {
        _open = FogEpisode(start: _firstHotT! + 0.5, end: t + 1.5);
        episodes.add(_open!);
        onFreezeStart?.call(_open!, t + n * _dt);
      } else if (_open != null) {
        _open!.end = t + 1.5;
      }
    } else {
      _cold++;
      _hot = 0;
      _firstHotT = null;
      if (_open != null && _cold >= releaseWindows) {
        final closed = _open!;
        _open = null;
        onFreezeEnd?.call(closed);
      }
    }

    final point = WindowPoint(
      t: t,
      probability: p,
      freezing: _open != null,
      walking: intensity >= activityThreshold && cadence != null,
      intensity: intensity,
      cadence: cadence,
      annotatedFog: labelled.isEmpty ? null : labelled.where((x) => x).length * 2 >= labelled.length,
    );
    windows.add(point);
    onWindow?.call(point);
  }

  /// Ends the stream and builds a persisted session.
  Session finish({required String id, required DateTime start, required String source, int cues = 0, int manualCues = 0}) {
    if (_open != null) {
      final closed = _open!;
      _open = null;
      onFreezeEnd?.call(closed);
    }
    return Session(
      id: id,
      start: start,
      durationSeconds: streamSeconds,
      source: source,
      windows: List.of(windows),
      episodes: List.of(episodes),
      profileSummary: _featureHistory.isEmpty ? {} : profileModel.sessionSummary(_featureHistory),
      cueCount: cues,
      manualCueCount: manualCues,
    );
  }

  /// Step rate from the autocorrelation peak of vertical acceleration
  /// (step periods 0.33–1.0 s, i.e. 60–180 steps/min). Returns null when no
  /// clear rhythm is present.
  static double? estimateCadence(List<double> vertical, double fs) {
    final n = vertical.length;
    final mean = vertical.reduce((a, b) => a + b) / n;
    final x = [for (final v in vertical) v - mean];
    final energy = x.fold(0.0, (a, v) => a + v * v);
    if (energy < 1e-6) return null;
    final minLag = (0.33 * fs).round(), maxLag = math.min((1.0 * fs).round(), n - 1);
    var bestLag = -1;
    var best = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var s = 0.0;
      for (var i = 0; i + lag < n; i++) {
        s += x[i] * x[i + lag];
      }
      final r = s / energy * n / (n - lag);
      if (r > best) {
        best = r;
        bestLag = lag;
      }
    }
    return best >= 0.3 && bestLag > 0 ? 60 * fs / bestLag : null;
  }
}
