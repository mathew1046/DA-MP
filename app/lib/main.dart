import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/store.dart';
import 'src/ml/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = await Future.wait([AppStore.open(), FogDetector.load(), GaitProfileModel.load()]);
  runApp(StepCueApp(
    store: results[0] as AppStore,
    detector: results[1] as FogDetector,
    profileModel: results[2] as GaitProfileModel,
  ));
}
