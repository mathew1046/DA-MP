import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'features.dart';

class _Tree {
  _Tree(Map<String, dynamic> json)
      : left = Int32List.fromList(List<int>.from(json['left'])),
        right = Int32List.fromList(List<int>.from(json['right'])),
        feature = Int32List.fromList(List<int>.from(json['feature'])),
        threshold = Float64List.fromList([for (final t in json['threshold']) (t as num).toDouble()]),
        value = Float64List.fromList([for (final v in json['value']) (v as num).toDouble()]);

  final Int32List left, right, feature;
  final Float64List threshold, value;

  double predict(Float32List x) {
    var node = 0;
    while (left[node] != -1) {
      node = x[feature[node]] <= threshold[node] ? left[node] : right[node];
    }
    return value[node];
  }
}

/// Gradient-boosted FoG detector exported from scikit-learn.
class FogDetector {
  FogDetector._(Map<String, dynamic> json)
      : featureNames = List<String>.from(json['feature_names']),
        initLogOdds = (json['init_log_odds'] as num).toDouble(),
        learningRate = (json['learning_rate'] as num).toDouble(),
        threshold = (json['threshold'] as num).toDouble(),
        windowSamples = json['window_samples'] as int,
        hopSamples = json['hop_samples'] as int,
        samplingRate = (json['sampling_rate_hz'] as num).toDouble(),
        metrics = Map<String, dynamic>.from(json['metrics']),
        _trees = [for (final t in json['trees']) _Tree(Map<String, dynamic>.from(t))];

  factory FogDetector.fromJson(String source) => FogDetector._(jsonDecode(source));

  static Future<FogDetector> load() async =>
      FogDetector.fromJson(await rootBundle.loadString('assets/fog_detector.json'));

  final List<String> featureNames;
  final double initLogOdds, learningRate, threshold, samplingRate;
  final int windowSamples, hopSamples;
  final Map<String, dynamic> metrics;
  final List<_Tree> _trees;

  double probability(Map<String, double> features) {
    // scikit-learn trees compare float32 inputs.
    final x = Float32List.fromList([for (final name in featureNames) features[name] ?? 0.0]);
    var raw = initLogOdds;
    for (final tree in _trees) {
      raw += learningRate * tree.predict(x);
    }
    return 1 / (1 + math.exp(-raw));
  }
}

/// Clinical/context summary of one K-means cluster, computed on the 60
/// training subjects after fitting.
class ClusterStats {
  ClusterStats(Map<String, dynamic> json)
      : subjects = (json['subjects'] as num).toInt(),
        updrsOn = (json['updrs_on'] as num).toDouble(),
        updrsOff = (json['updrs_off'] as num).toDouble(),
        nfogq = (json['nfogq'] as num).toDouble(),
        fogRate = (json['fog_rate'] as num).toDouble();

  final int subjects;
  final double updrsOn, updrsOff, nfogq, fogRate;
}

/// Patient-level K-means gait profile (standardize → PCA → nearest centre).
class GaitProfileModel {
  GaitProfileModel._(Map<String, dynamic> json)
      : windowFeatures = List<String>.from(json['window_features']),
        profileFeatures = List<String>.from(json['profile_features']),
        clusterStats = [for (final s in json['cluster_stats'] ?? const []) ClusterStats(Map<String, dynamic>.from(s))],
        _mean = _vec(json['scaler_mean']),
        _scale = _vec(json['scaler_scale']),
        _pcaMean = _vec(json['pca_mean']),
        _components = [for (final row in json['pca_components']) _vec(row)],
        _centers = [for (final row in json['centers']) _vec(row)];

  factory GaitProfileModel.fromJson(String source) => GaitProfileModel._(jsonDecode(source));

  static Future<GaitProfileModel> load() async =>
      GaitProfileModel.fromJson(await rootBundle.loadString('assets/gait_profile_kmeans.json'));

  final List<String> windowFeatures, profileFeatures;
  final List<ClusterStats> clusterStats;
  final Float64List _mean, _scale, _pcaMean;
  final List<Float64List> _components, _centers;

  int get clusterCount => _centers.length;

  static Float64List _vec(dynamic list) => Float64List.fromList([for (final v in list) (v as num).toDouble()]);

  /// Per-session summary: median and IQR of each window feature.
  Map<String, double> sessionSummary(List<Map<String, double>> windows) {
    final summary = <String, double>{};
    for (final name in windowFeatures) {
      final values = [for (final w in windows) w[name] ?? 0.0]..sort();
      summary['${name}__median'] = FeatureExtractor.quantile(values, 0.5);
      summary['${name}__<lambda_0>'] = FeatureExtractor.quantile(values, 0.75) - FeatureExtractor.quantile(values, 0.25);
    }
    return summary;
  }

  /// Combines session summaries (median across sessions) and returns the
  /// zero-based cluster index, the distance margin and the distances to every
  /// centre (used for the continuous severity estimate).
  ({int cluster, double confidence, List<double> distances})? assign(List<Map<String, double>> sessionSummaries) {
    if (sessionSummaries.isEmpty) return null;
    final x = Float64List(profileFeatures.length);
    for (var i = 0; i < profileFeatures.length; i++) {
      final values = [for (final s in sessionSummaries) s[profileFeatures[i]] ?? 0.0]..sort();
      final scaled = (FeatureExtractor.quantile(values, 0.5) - _mean[i]) / (_scale[i] == 0 ? 1 : _scale[i]);
      x[i] = scaled - _pcaMean[i];
    }
    final z = [
      for (final component in _components)
        Iterable.generate(component.length, (i) => component[i] * x[i]).fold(0.0, (a, b) => a + b),
    ];
    final distances = [
      for (final c in _centers)
        math.sqrt(Iterable.generate(c.length, (i) => (c[i] - z[i]) * (c[i] - z[i])).fold(0.0, (a, b) => a + b)),
    ];
    final order = List.generate(distances.length, (i) => i)..sort((a, b) => distances[a].compareTo(distances[b]));
    final nearest = distances[order.first];
    final second = distances.length > 1 ? distances[order[1]] : nearest;
    return (cluster: order.first, confidence: second == 0 ? 0 : 1 - nearest / second, distances: distances);
  }
}
