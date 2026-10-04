import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'session.dart';
import 'settings.dart';

/// Local, on-device persistence. Nothing leaves the phone.
class AppStore extends ChangeNotifier {
  AppStore._(this._dir);

  static Future<AppStore> open({Directory? directory}) async {
    final base = directory ?? Directory('${(await getApplicationDocumentsDirectory()).path}/stepcue');
    await base.create(recursive: true);
    final store = AppStore._(base);
    await store._load();
    return store;
  }

  final Directory _dir;
  final List<Session> _sessions = [];
  AppSettings _settings = const AppSettings();

  List<Session> get sessions => List.unmodifiable(_sessions);
  AppSettings get settings => _settings;

  File get _sessionsFile => File('${_dir.path}/sessions.json');
  File get _settingsFile => File('${_dir.path}/settings.json');

  Future<void> _load() async {
    if (await _settingsFile.exists()) {
      _settings = AppSettings.fromJson(jsonDecode(await _settingsFile.readAsString()));
    }
    if (await _sessionsFile.exists()) {
      final list = jsonDecode(await _sessionsFile.readAsString()) as List;
      _sessions
        ..clear()
        ..addAll(list.map((e) => Session.fromJson(Map<String, dynamic>.from(e))));
      _sort();
    }
  }

  void _sort() => _sessions.sort((a, b) => b.start.compareTo(a.start));

  Future<void> _saveSessions() => _sessionsFile.writeAsString(jsonEncode([for (final s in _sessions) s.toJson()]));

  Future<void> addSessions(Iterable<Session> sessions) async {
    _sessions.addAll(sessions);
    _sort();
    notifyListeners();
    await _saveSessions();
  }

  Future<void> deleteSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    notifyListeners();
    await _saveSessions();
  }

  Future<void> deleteWhere(bool Function(Session) test) async {
    _sessions.removeWhere(test);
    notifyListeners();
    await _saveSessions();
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }
}
