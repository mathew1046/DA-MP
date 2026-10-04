import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stepcue/src/data/session.dart';
import 'package:stepcue/src/engine/analysis.dart';
import 'package:stepcue/src/engine/sources.dart';
import 'package:stepcue/src/insights/insights.dart';
import 'package:stepcue/src/ml/models.dart';

Recording loadRecording(String path) {
  final lines = File(path).readAsLinesSync().skip(1).where((l) => l.isNotEmpty);
  final rows = <List<double>>[];
  final labels = <bool>[];
  for (final line in lines) {
    final p = line.split(',');
    rows.add([double.parse(p[0]), double.parse(p[1]), double.parse(p[2])]);
    labels.add(p[3].trim() == '1');
  }
  return Recording(rows, labels);
}

void main() {
  final detector = FogDetector.fromJson(File('assets/fog_detector.json').readAsStringSync());
  final profileModel = GaitProfileModel.fromJson(File('assets/gait_profile_kmeans.json').readAsStringSync());

  Session analyse(String file, {double rateScale = 1}) {
    final engine = AnalysisEngine(
      detector: detector,
      profileModel: profileModel,
      onFreezeStart: (e, detectedAt) => e.cueStart = detectedAt,
    );
    final recording = loadRecording(file);
    if (rateScale == 1) {
      recording.feed(engine.addSample);
    } else {
      // Simulate a phone sampling at a different, slightly jittery rate.
      final rnd = math.Random(1);
      final rate = Recording.rate * rateScale;
      for (var t = 0.0; t < recording.seconds - 0.02; t += (1 / rate) * (0.9 + 0.2 * rnd.nextDouble())) {
        final i = (t * Recording.rate).floor();
        final r = recording.rows[i];
        engine.addSample(t, r[0], r[1], r[2], annotatedFog: recording.labels[i]);
      }
    }
    return engine.finish(id: 'test', start: DateTime(2026, 10, 4, 9), source: 'sample');
  }

  test('detects freezes in a recording with long expert-marked freezing', () {
    final session = analyse('assets/demo/walk_6.csv');
    expect(session.windows.length, greaterThan(70));
    expect(session.episodes, isNotEmpty);
    final labelled = session.windows.where((w) => w.annotatedFog == true).length;
    final found = session.windows.where((w) => w.annotatedFog == true && w.freezing).length;
    expect(found / labelled, greaterThan(0.5));
    expect(session.episodes.every((e) => e.cueStart != null && e.cueStart! >= e.start), isTrue);
  });

  test('raises few alerts on a recording without freezing', () {
    final session = analyse('assets/demo/walk_1.csv');
    expect(session.frozenShare, lessThan(0.25));
    expect(session.medianCadence, isNotNull);
  });

  test('resampling keeps results close for irregular, slower phone sampling', () {
    final reference = analyse('assets/demo/walk_6.csv');
    final resampled = analyse('assets/demo/walk_6.csv', rateScale: 0.8);
    expect((resampled.freezingSeconds - reference.freezingSeconds).abs(), lessThan(reference.freezingSeconds * 0.35 + 3));
  });

  test('session JSON round-trips and feeds insights', () {
    final session = analyse('assets/demo/walk_5.csv');
    final restored = Session.fromJson(session.toJson());
    expect(restored.episodes.length, session.episodes.length);
    expect(restored.profileSummary.length, 102);

    final insights = Insights([restored], now: DateTime(2026, 10, 4, 20));
    expect(insights.today.walks, 1);
    expect(insights.lastDays(), hasLength(7));
    expect(insights.profile(profileModel), isNotNull);
  });

  test('cadence estimate recovers a synthetic step rhythm', () {
    const fs = 128.0;
    final signal = [for (var i = 0; i < 256; i++) -9.8 + 1.5 * math.sin(2 * math.pi * 1.8 * i / fs)];
    expect(AnalysisEngine.estimateCadence(signal, fs)!, closeTo(108, 4));
  });
}
