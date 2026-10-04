import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepcue/src/ml/features.dart';
import 'package:stepcue/src/ml/models.dart';

void main() {
  final detector = FogDetector.fromJson(File('assets/fog_detector.json').readAsStringSync());
  final profileModel = GaitProfileModel.fromJson(File('assets/gait_profile_kmeans.json').readAsStringSync());

  test('window features match the Python extractor', () {
    final fixture = jsonDecode(File('test/fixtures/parity.json').readAsStringSync());
    final window = [for (final row in fixture['window']) <double>[for (final v in row) (v as num).toDouble()]];
    final expected = Map<String, dynamic>.from(fixture['features']);
    final actual = FeatureExtractor().extract(window);

    expect(actual.keys.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      final want = (entry.value as num).toDouble();
      expect(actual[entry.key]!, closeTo(want, 1e-6 + want.abs() * 1e-6), reason: entry.key);
    }
  });

  test('detector probability matches scikit-learn', () {
    final fixture = jsonDecode(File('test/fixtures/parity.json').readAsStringSync());
    final features = {
      for (final e in Map<String, dynamic>.from(fixture['features']).entries) e.key: (e.value as num).toDouble(),
    };
    expect(detector.probability(features), closeTo((fixture['probability'] as num).toDouble(), 1e-4));
    expect(detector.featureNames, hasLength(51));
  });

  test('K-means profile assignment matches scikit-learn', () {
    final fixture = jsonDecode(File('test/fixtures/profile_parity.json').readAsStringSync()) as List;
    for (final item in fixture) {
      final profile = {
        for (final e in Map<String, dynamic>.from(item['profile']).entries) e.key: (e.value as num).toDouble(),
      };
      expect(profileModel.assign([profile])!.cluster, item['cluster']);
    }
  });

  test('quantile uses linear interpolation', () {
    expect(FeatureExtractor.quantile([1, 2, 3, 4], 0.25), closeTo(1.75, 1e-12));
    expect(FeatureExtractor.quantile([1, 2, 3, 4], 0.5), closeTo(2.5, 1e-12));
  });
}
