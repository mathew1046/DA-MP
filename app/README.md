# StepCue

Flutter app for people with Parkinson's freezing of gait (FoG). It reads the phone's accelerometer, detects freezes on-device, plays a rhythmic vibration/visual cue, and turns each walk into plain-language insights.

## Screens

- **Today** – today's totals, one large *Start a walk* button, *Play walking rhythm*, last walk.
- **Walk** – status in large type (Standing still / Walking well / Freeze detected), timer, freeze count, live movement trace, manual rhythm, *Finish walk*. The screen turns soft red and the rhythm starts automatically during a detected freeze.
- **Walk detail** – duration, time on feet, freezes, % time frozen, longest freeze, steps per minute, step-rhythm variation, recovery after cue; movement timeline with shaded freezes; model likelihood vs. alert threshold; per-freeze list; for recorded data, agreement with clinician labels.
- **Insights** – week-over-week comparison, last-7-days chart, freezes by time of day, time frozen and step rate per walk, freeze-length breakdown, cue response, K-means movement pattern, all walks.
- **Settings** – vibration / on-screen pulse, rhythm speed and length, alert sensitivity, phone sensor vs. practice mode, wearing guide, sample data, delete data, detector performance.

## How detection works

1. Accelerometer samples are resampled to 128 Hz (phone upright at waist/lower back: AccV = −y, AccML = x, AccAP = z).
2. Every second, a 2-second window yields 51 time/frequency features (identical to `ml/export_mobile_models.py`).
3. A 150-tree gradient-boosting model (`assets/fog_detector.json`) scores the window. Two consecutive windows above threshold open a freeze; two below close it.
4. Each walk is summarised (median/IQR of features) and assigned to the patient-profile K-means model (`assets/gait_profile_kmeans.json`). Patterns describe movement style, not disease severity.

Held-out performance (12 unseen people): balanced accuracy 0.71, F1 0.47, average precision 0.50. The app is a research prototype — it detects freezes as they happen; it does not predict them in advance, grade severity, or detect falls.

## Run

```bash
flutter pub get
flutter test                 # model parity, engine and screen tests
flutter run                  # Android/iOS device; Linux desktop works in Practice mode
flutter build apk --release
```

`test/screens_test.dart` writes screenshots to `build/screenshots/`.

Regenerate model assets from the project root (Conda `base`):

```bash
conda run -n base python ml/export_mobile_models.py
```

Practice mode and sample walks use real recordings from held-out patients in the Kaggle *Parkinson's Freezing of Gait Prediction* tDCS-FoG data (`assets/demo/`).
