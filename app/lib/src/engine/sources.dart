import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sensors_plus/sensors_plus.dart';

typedef SampleSink = void Function(double t, double v, double ml, double ap, {bool? annotatedFog});

abstract class MotionSource {
  Future<void> start(SampleSink sink);
  Future<void> stop();
  String get kind;
}

/// Live phone accelerometer. Assumes the phone is upright at the lower back or
/// waist (screen facing outward), matching the lower-back sensor of the
/// training data: AccV ≈ −y, AccML ≈ x, AccAP ≈ z.
class PhoneMotionSource implements MotionSource {
  StreamSubscription<AccelerometerEvent>? _sub;
  void Function(Object error)? onError;

  @override
  String get kind => 'phone';

  @override
  Future<void> start(SampleSink sink) async {
    _sub = accelerometerEventStream(samplingPeriod: const Duration(microseconds: 7812)).listen(
      (e) => sink(e.timestamp.microsecondsSinceEpoch / 1e6, -e.y, e.x, e.z),
      onError: (Object error) => onError?.call(error),
      cancelOnError: true,
    );
  }

  @override
  Future<void> stop() async => _sub?.cancel();
}

class RecordingInfo {
  const RecordingInfo({required this.file, required this.seconds, required this.medication, required this.annotatedShare});

  final String file;
  final double seconds;
  final String medication;
  final double annotatedShare;

  static Future<List<RecordingInfo>> catalogue() async {
    final list = jsonDecode(await rootBundle.loadString('assets/demo/catalogue.json')) as List;
    return [
      for (final e in list)
        RecordingInfo(
          file: e['file'] as String,
          seconds: (e['seconds'] as num).toDouble(),
          medication: e['medication'] as String,
          annotatedShare: (e['annotated_fog_fraction'] as num).toDouble(),
        ),
    ];
  }
}

/// A bundled Kaggle tDCS-FoG recording (128 Hz, lower-back sensor).
class Recording {
  Recording(this.rows, this.labels);

  final List<List<double>> rows;
  final List<bool> labels;
  static const rate = 128.0;

  double get seconds => rows.length / rate;

  static Future<Recording> load(String asset) async {
    final lines = const LineSplitter().convert(await rootBundle.loadString(asset));
    final rows = <List<double>>[];
    final labels = <bool>[];
    for (final line in lines.skip(1)) {
      final parts = line.split(',');
      if (parts.length < 4) continue;
      rows.add([double.parse(parts[0]), double.parse(parts[1]), double.parse(parts[2])]);
      labels.add(parts[3].trim() == '1');
    }
    return Recording(rows, labels);
  }

  /// Feeds the whole recording at once (used for sample history and tests).
  void feed(SampleSink sink) {
    for (var i = 0; i < rows.length; i++) {
      sink(i / rate, rows[i][0], rows[i][1], rows[i][2], annotatedFog: labels[i]);
    }
  }
}

/// Replays a recording in real time, looping until stopped.
class RecordingMotionSource implements MotionSource {
  RecordingMotionSource(this.recording);

  final Recording recording;
  Timer? _timer;
  final _clock = Stopwatch();
  int _sent = 0;

  @override
  String get kind => 'demo';

  @override
  Future<void> start(SampleSink sink) async {
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final due = (_clock.elapsedMicroseconds / 1e6 * Recording.rate).floor();
      while (_sent < due) {
        final i = _sent % recording.rows.length;
        final r = recording.rows[i];
        sink(_sent / Recording.rate, r[0], r[1], r[2], annotatedFog: recording.labels[i]);
        _sent++;
      }
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _clock.stop();
  }
}
