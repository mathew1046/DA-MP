import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/session.dart';
import '../data/settings.dart';
import '../data/store.dart';
import '../ml/models.dart';
import 'analysis.dart';
import 'cue.dart';
import 'monitor.dart';
import 'sources.dart';

enum WalkStatus { starting, still, walking, freezing, sensorError }

/// Runs one monitored walk: motion source → analysis → cue → saved session.
class WalkController extends ChangeNotifier {
  WalkController({
    required this.store,
    required FogDetector detector,
    required GaitProfileModel profileModel,
    required this.source,
    this.monitor,
  }) : settings = store.settings {
    _engine = AnalysisEngine(
      detector: detector,
      profileModel: profileModel,
      thresholdShift: settings.thresholdShift,
      onWindow: _onWindow,
      onFreezeStart: _onFreezeStart,
      onFreezeEnd: _onFreezeEnd,
    );
  }

  final AppStore store;
  final MotionSource source;
  final AppSettings settings;
  final CueController cue = CueController();

  /// Keeps detection alive while the app is minimized; null disables it.
  final BackgroundMonitor? monitor;
  late final AnalysisEngine _engine;
  final DateTime startedAt = DateTime.now();
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;

  WalkStatus status = WalkStatus.starting;
  double probability = 0;
  int cues = 0;
  int manualCues = 0;
  bool _finished = false;

  /// Recent movement intensity for the small live trace (last 60 s).
  final Queue<double> recentIntensity = Queue();

  Duration get elapsed => _clock.elapsed;
  int get freezeCount => _engine.episodes.length;
  double get walkingSeconds => _engine.windows.where((w) => w.walking || w.freezing).length.toDouble();

  Future<void> start() async {
    _clock.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    if (source is PhoneMotionSource) {
      (source as PhoneMotionSource).onError = (_) {
        status = WalkStatus.sensorError;
        notifyListeners();
      };
    }
    await source.start(_engine.addSample);
    if (settings.backgroundMonitor && source is PhoneMotionSource && monitor != null) {
      unawaited(monitor!.start());
    }
    // Keep the screen on; never let this delay or break monitoring.
    unawaited(WakelockPlus.enable().catchError((_) {}));
  }

  void _onWindow(WindowPoint point) {
    probability = point.probability;
    recentIntensity.add(point.intensity);
    while (recentIntensity.length > 60) {
      recentIntensity.removeFirst();
    }
    status = point.freezing
        ? WalkStatus.freezing
        : point.walking
            ? WalkStatus.walking
            : WalkStatus.still;
    notifyListeners();
  }

  void _onFreezeStart(FogEpisode episode, double detectedAt) {
    episode.cueStart = detectedAt;
    cues++;
    if (settings.vibrationCue || settings.visualCue) {
      cue.start(bpm: settings.rhythmBpm, vibrate: settings.vibrationCue, maxSeconds: settings.maxCueSeconds);
    }
    unawaited(monitor?.update('Freeze detected — rhythm cue playing') ?? Future.value());
  }

  void _onFreezeEnd(FogEpisode episode) {
    cue.stop();
    unawaited(monitor?.update('Monitoring for freezes') ?? Future.value());
  }

  /// Patient-initiated rhythm, e.g. before a doorway or a turn.
  void cueNow() {
    manualCues++;
    cue.start(bpm: settings.rhythmBpm, vibrate: settings.vibrationCue, maxSeconds: math.min(10, settings.maxCueSeconds));
    notifyListeners();
  }

  Future<Session?> finish() async {
    if (_finished) return null;
    _finished = true;
    _ticker?.cancel();
    _clock.stop();
    cue.stop();
    await source.stop();
    unawaited(monitor?.stop() ?? Future.value());
    unawaited(WakelockPlus.disable().catchError((_) {}));
    final session = _engine.finish(
      id: startedAt.microsecondsSinceEpoch.toString(),
      start: startedAt,
      source: source.kind,
      cues: cues,
      manualCues: manualCues,
    );
    if (session.durationSeconds < 10) return null;
    await store.addSessions([session]);
    return session;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    cue.dispose();
    if (!_finished) {
      source.stop();
      unawaited(monitor?.stop() ?? Future.value());
    }
    super.dispose();
  }
}

/// Builds labelled history from the bundled recordings so insights can be
/// explored before the phone has collected real walks.
Future<List<Session>> buildSampleHistory({
  required FogDetector detector,
  required GaitProfileModel profileModel,
  required double thresholdShift,
  DateTime? now,
}) async {
  final catalogue = await RecordingInfo.catalogue();
  final today = now ?? DateTime.now();
  const slots = [(6, 9, 10), (5, 18, 40), (4, 11, 5), (3, 16, 20), (1, 10, 30), (0, 8, 15)];
  final sessions = <Session>[];
  for (var i = 0; i < catalogue.length; i++) {
    final recording = await Recording.load(catalogue[i].file);
    final (daysAgo, hour, minute) = slots[i % slots.length];
    final day = today.subtract(Duration(days: daysAgo));
    final start = DateTime(day.year, day.month, day.day, hour, minute);
    final engine = AnalysisEngine(
      detector: detector,
      profileModel: profileModel,
      thresholdShift: thresholdShift,
      onFreezeStart: (episode, detectedAt) => episode.cueStart = detectedAt,
    );
    recording.feed(engine.addSample);
    sessions.add(engine.finish(
      id: 'sample-$i-${start.millisecondsSinceEpoch}',
      start: start,
      source: 'sample',
      cues: engine.episodes.length,
    ));
  }
  return sessions;
}
