import 'dart:math' as math;
import 'dart:typed_data';

/// Window feature extraction. Mirrors `signal_features`/`window_features` in
/// `ml/export_mobile_models.py` so the exported model sees identical inputs.
class FeatureExtractor {
  FeatureExtractor({this.samplingRate = 128});

  final double samplingRate;
  static const signalNames = ['AccV', 'AccML', 'AccAP'];

  /// [window] holds rows of (AccV, AccML, AccAP) in m/s².
  Map<String, double> extract(List<List<double>> window) {
    final n = window.length;
    final columns = List.generate(3, (c) => Float64List.fromList([for (final row in window) row[c]]));
    final magnitude = Float64List(n);
    for (var i = 0; i < n; i++) {
      final r = window[i];
      magnitude[i] = math.sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]);
    }
    final features = <String, double>{};
    for (var c = 0; c < 3; c++) {
      features.addAll(_signal(columns[c], signalNames[c]));
    }
    features.addAll(_signal(magnitude, 'Magnitude'));
    features['corr_V_ML'] = _corr(columns[0], columns[1]);
    features['corr_V_AP'] = _corr(columns[0], columns[2]);
    features['corr_ML_AP'] = _corr(columns[1], columns[2]);
    return features;
  }

  Map<String, double> _signal(Float64List values, String prefix) {
    final n = values.length;
    final mean = _mean(values);
    var sq = 0.0, minV = double.infinity, maxV = double.negativeInfinity, rmsAcc = 0.0;
    for (final v in values) {
      sq += (v - mean) * (v - mean);
      rmsAcc += v * v;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    var jerk = 0.0;
    for (var i = 1; i < n; i++) {
      final d = (values[i] - values[i - 1]) * samplingRate;
      jerk += d * d;
    }

    final re = Float64List(n), im = Float64List(n);
    for (var i = 0; i < n; i++) {
      final w = n > 1 ? 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)) : 1.0;
      re[i] = (values[i] - mean) * w;
    }
    _fft(re, im);
    final bins = n ~/ 2 + 1;
    final power = Float64List(bins);
    var total = 0.0, locomotor = 0.0, freeze = 0.0, best = -1.0, dominant = 0.0;
    for (var k = 0; k < bins; k++) {
      final p = re[k] * re[k] + im[k] * im[k];
      final f = k * samplingRate / n;
      power[k] = p;
      total += p;
      if (f >= 0.5 && f < 3.0) locomotor += p;
      if (f >= 3.0 && f <= 8.0) freeze += p;
      final candidate = k == 0 ? 0.0 : p;
      if (candidate > best) {
        best = candidate;
        dominant = f;
      }
    }
    var entropy = 0.0;
    for (final p in power) {
      final q = p / (total + 1e-12);
      entropy -= q * math.log(q + 1e-12);
    }
    final sorted = Float64List.fromList(values)..sort();
    return {
      '${prefix}_mean': mean,
      '${prefix}_std': math.sqrt(sq / n),
      '${prefix}_min': minV,
      '${prefix}_max': maxV,
      '${prefix}_iqr': quantile(sorted, 0.75) - quantile(sorted, 0.25),
      '${prefix}_rms': math.sqrt(rmsAcc / n),
      '${prefix}_jerk_rms': n > 1 ? math.sqrt(jerk / (n - 1)) : 0.0,
      '${prefix}_dominant_hz': dominant,
      '${prefix}_locomotor_power': math.log(1 + locomotor),
      '${prefix}_freeze_power': math.log(1 + freeze),
      '${prefix}_freeze_index': math.log((freeze + 1e-9) / (locomotor + 1e-9)),
      '${prefix}_spectral_entropy': entropy,
    };
  }

  static double _mean(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  static double _corr(Float64List a, Float64List b) {
    final ma = _mean(a), mb = _mean(b);
    var num = 0.0, da = 0.0, db = 0.0;
    for (var i = 0; i < a.length; i++) {
      final x = a[i] - ma, y = b[i] - mb;
      num += x * y;
      da += x * x;
      db += y * y;
    }
    final denom = math.sqrt(da * db);
    return denom == 0 ? 0.0 : num / denom;
  }

  /// Linear-interpolated quantile of an ascending [sorted] list (numpy default).
  static double quantile(List<double> sorted, double q) {
    if (sorted.isEmpty) return double.nan;
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor();
    final hi = math.min(lo + 1, sorted.length - 1);
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  /// In-place complex FFT; radix-2 when possible, direct DFT otherwise.
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    if (n & (n - 1) != 0) {
      final r = Float64List.fromList(re), i0 = Float64List.fromList(im);
      for (var k = 0; k < n; k++) {
        var sr = 0.0, si = 0.0;
        for (var t = 0; t < n; t++) {
          final a = -2 * math.pi * k * t / n;
          sr += r[t] * math.cos(a) - i0[t] * math.sin(a);
          si += r[t] * math.sin(a) + i0[t] * math.cos(a);
        }
        re[k] = sr;
        im[k] = si;
      }
      return;
    }
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wr = math.cos(angle), wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final ar = re[i + k + len ~/ 2] * cr - im[i + k + len ~/ 2] * ci;
          final ai = re[i + k + len ~/ 2] * ci + im[i + k + len ~/ 2] * cr;
          re[i + k + len ~/ 2] = re[i + k] - ar;
          im[i + k + len ~/ 2] = im[i + k] - ai;
          re[i + k] += ar;
          im[i + k] += ai;
          final nr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = nr;
        }
      }
    }
  }
}
