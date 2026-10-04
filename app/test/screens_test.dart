import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepcue/src/app.dart';
import 'package:stepcue/src/data/settings.dart';
import 'package:stepcue/src/data/store.dart';
import 'package:stepcue/src/engine/sources.dart';
import 'package:stepcue/src/engine/walk_controller.dart';
import 'package:stepcue/src/ml/models.dart';
import 'package:stepcue/src/ui/session_screen.dart';
import 'package:stepcue/src/ui/walk_screen.dart';

import 'engine_test.dart' show loadRecording;

/// Feeds a fixed slice of a recording as soon as the walk starts.
class _InstantSource implements MotionSource {
  _InstantSource(this.recording, this.seconds);

  final Recording recording;
  final double seconds;

  @override
  String get kind => 'demo';

  @override
  Future<void> start(SampleSink sink) async {
    final n = (seconds * Recording.rate).round();
    for (var i = 0; i < n; i++) {
      final r = recording.rows[i];
      sink(i / Recording.rate, r[0], r[1], r[2], annotatedFog: recording.labels[i]);
    }
  }

  @override
  Future<void> stop() async {}
}

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter'}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold', 'Roboto-Light']) {
    final file = File('$dir/$f.ttf');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await roboto.load();
  final icons = File('$dir/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

void main() {
  final shots = Directory('build/screenshots')..createSync(recursive: true);
  final boundaryKey = GlobalKey();

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 500));
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${shots.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('main screens render with sample data', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    addTearDown(tester.view.reset);

    final detector = FogDetector.fromJson(File('assets/fog_detector.json').readAsStringSync());
    final profileModel = GaitProfileModel.fromJson(File('assets/gait_profile_kmeans.json').readAsStringSync());
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('stepcue'));
    final store = (await tester.runAsync(() => AppStore.open(directory: tmp)))!;
    await tester.runAsync(() => store.updateSettings(store.settings.copyWith(placementSeen: true, sensorMode: SensorMode.recording)));

    Widget app() => RepaintBoundary(
          key: boundaryKey,
          child: StepCueApp(store: store, detector: detector, profileModel: profileModel),
        );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Start a walk'), findsOneWidget);
    await shoot(tester, '01_today_empty');

    final sessions = (await tester.runAsync(() => buildSampleHistory(
          detector: detector,
          profileModel: profileModel,
          thresholdShift: 0,
          now: DateTime.now(),
        )))!;
    await tester.runAsync(() => store.addSessions(sessions));
    await tester.pumpAndSettle();
    await shoot(tester, '02_today');

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(412 * 2, 3900 * 2);
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('Gait severity'), findsOneWidget);
    await shoot(tester, '03_insights');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(412 * 2, 1900 * 2);
    await tester.pumpAndSettle();
    await shoot(tester, '04_settings');

    final withFreezes = store.sessions.firstWhere((s) => s.episodes.length > 2);
    tester.view.physicalSize = const Size(412 * 2, 2300 * 2);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => SessionScreen(session: withFreezes)));
    await tester.pumpAndSettle();
    expect(find.text('Compared with clinicians'), findsOneWidget);
    await shoot(tester, '05_session');
    nav.pop();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    final recording = (await tester.runAsync(() async => loadRecording('assets/demo/walk_6.csv')))!;
    nav.push(MaterialPageRoute(builder: (_) => WalkScreen(source: _InstantSource(recording, 16))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await shoot(tester, '06_walk_freeze');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
