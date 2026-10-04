enum Sensitivity { fewer, balanced, more }

enum SensorMode { phone, recording }

class AppSettings {
  const AppSettings({
    this.rhythmBpm = 100,
    this.vibrationCue = true,
    this.visualCue = true,
    this.sensitivity = Sensitivity.balanced,
    this.sensorMode = SensorMode.phone,
    this.maxCueSeconds = 15,
    this.placementSeen = false,
    this.backgroundMonitor = false,
  });

  final int rhythmBpm;
  final bool vibrationCue;
  final bool visualCue;
  final Sensitivity sensitivity;
  final SensorMode sensorMode;
  final int maxCueSeconds;
  final bool placementSeen;

  /// Keep detecting freezes while the app is minimized (foreground service).
  final bool backgroundMonitor;

  /// Shift applied to the model's validated threshold.
  double get thresholdShift => switch (sensitivity) {
        Sensitivity.fewer => 0.08,
        Sensitivity.balanced => 0.0,
        Sensitivity.more => -0.12,
      };

  AppSettings copyWith({
    int? rhythmBpm,
    bool? vibrationCue,
    bool? visualCue,
    Sensitivity? sensitivity,
    SensorMode? sensorMode,
    int? maxCueSeconds,
    bool? placementSeen,
    bool? backgroundMonitor,
  }) =>
      AppSettings(
        rhythmBpm: rhythmBpm ?? this.rhythmBpm,
        vibrationCue: vibrationCue ?? this.vibrationCue,
        visualCue: visualCue ?? this.visualCue,
        sensitivity: sensitivity ?? this.sensitivity,
        sensorMode: sensorMode ?? this.sensorMode,
        maxCueSeconds: maxCueSeconds ?? this.maxCueSeconds,
        placementSeen: placementSeen ?? this.placementSeen,
        backgroundMonitor: backgroundMonitor ?? this.backgroundMonitor,
      );

  Map<String, dynamic> toJson() => {
        'bpm': rhythmBpm,
        'vibration': vibrationCue,
        'visual': visualCue,
        'sensitivity': sensitivity.name,
        'mode': sensorMode.name,
        'maxCue': maxCueSeconds,
        'placementSeen': placementSeen,
        'background': backgroundMonitor,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        rhythmBpm: (j['bpm'] as num?)?.toInt() ?? 100,
        vibrationCue: j['vibration'] as bool? ?? true,
        visualCue: j['visual'] as bool? ?? true,
        sensitivity: Sensitivity.values.asNameMap()[j['sensitivity']] ?? Sensitivity.balanced,
        sensorMode: SensorMode.values.asNameMap()[j['mode']] ?? SensorMode.phone,
        maxCueSeconds: (j['maxCue'] as num?)?.toInt() ?? 15,
        placementSeen: j['placementSeen'] as bool? ?? false,
        backgroundMonitor: j['background'] as bool? ?? false,
      );
}
