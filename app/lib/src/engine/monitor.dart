import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Drives the Android foreground service that keeps freeze detection alive
/// while the app is minimized. A no-op on other platforms and in tests.
class BackgroundMonitor {
  static const _channel = MethodChannel('stepcue/monitor');

  bool _active = false;
  bool get active => _active;
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _call(String method, [Map<String, dynamic>? args]) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // No native side (desktop, tests).
    } catch (_) {
      // Platform errors must never break monitoring.
    }
  }

  Future<void> start() async {
    if (!supported) return;
    await _call('start');
    _active = true;
  }

  Future<void> update(String text) async {
    if (_active) await _call('update', {'text': text});
  }

  Future<void> stop() async {
    await _call('stop');
    _active = false;
  }
}
