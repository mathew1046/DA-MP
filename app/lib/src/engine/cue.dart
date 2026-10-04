import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Rhythmic cue: a short pulse on every beat, through the phone's vibration
/// motor and/or an on-screen pulse.
class CueController extends ChangeNotifier {
  Timer? _beatTimer, _stopTimer;
  int _beat = 0;
  bool? _hasVibrator;
  bool _vibrate = true;

  bool get active => _beatTimer != null;

  /// Increments on every beat; the UI animates a pulse from it.
  int get beat => _beat;

  Future<void> start({required int bpm, required bool vibrate, required int maxSeconds}) async {
    stop();
    _vibrate = vibrate;
    if (vibrate) {
      try {
        _hasVibrator ??= await Vibration.hasVibrator();
      } catch (_) {
        _hasVibrator = false;
      }
    }
    final interval = Duration(milliseconds: (60000 / bpm).round());
    _pulse();
    _beatTimer = Timer.periodic(interval, (_) => _pulse());
    _stopTimer = Timer(Duration(seconds: maxSeconds), stop);
    notifyListeners();
  }

  void _pulse() {
    _beat++;
    if (_vibrate) {
      if (_hasVibrator == true) {
        Vibration.vibrate(duration: 110).catchError((_) {});
      } else {
        HapticFeedback.heavyImpact();
      }
    }
    notifyListeners();
  }

  void stop() {
    final wasActive = active;
    _beatTimer?.cancel();
    _stopTimer?.cancel();
    _beatTimer = null;
    _stopTimer = null;
    if (wasActive) {
      if (_hasVibrator == true) Vibration.cancel().catchError((_) {});
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
