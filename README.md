# StepCue — Parkinson's gait analytics & FoG-cueing app

Data-analytics microproject based on
[Sri-iesaranusorn et al. (2025), *"Parkinson's disease severity clustering based on gait activity from mobile device"*, Scientific Reports](https://doi.org/10.1038/s41598-025-22751-3).

The project has two parts:

1. **Analytics pipeline** — supervised freezing-of-gait (FoG) detection and
   unsupervised K-means gait profiling on the
   [TLVMC Parkinson's Freezing of Gait Prediction dataset](https://www.kaggle.com/competitions/tlvmc-parkinsons-freezing-gait-prediction)
   (`tdcsfog` subset: lower-back accelerometer, 60 subjects, clinician
   video-annotated freezes, UPDRS-III / NFOG-Q metadata).
2. **StepCue Flutter app** (`app/`) — runs both models fully on-device:
   real-time FoG detection with a rhythmic vibration cue, walk analytics,
   and a K-means gait-severity profile. Demo/practice mode replays real
   held-out recordings.

## Dataset

Not included in this repo (Kaggle terms). Download the `tdcsfog` training
recordings plus `subjects.csv`, `tdcsfog_metadata.csv`, `tasks.csv` and
`events.csv` from the
[competition data page](https://www.kaggle.com/competitions/tlvmc-parkinsons-freezing-gait-prediction/data)
into `data/raw/` (accept the competition rules first; the Python Kaggle API
works if the `kaggle` CLI is not installed).

Used here: 506 recordings, 60 subjects, ~7.3 h at 128 Hz
(`AccV`, `AccML`, `AccAP` at the lower back). Labels `StartHesitation`,
`Turn`, `Walking` → binary FoG target (15.9 % of windows positive).

## Pipeline

Jupyter notebooks in `notebooks/` (run in order, Conda `base`):

| Notebook | Output |
|---|---|
| `01_data_exploration` | recording/window summaries, label stats, plots |
| `02_fog_model` | binary FoG + 4-class event models, grouped-CV + 12-subject held-out eval |
| `03_kmeans_gait_clustering` | window-level K-means (k-selection, k=4 paper-aligned check, clinical tests) |
| `04_patient_profile_kmeans` | subject-level K-means profiles (deployed in the app) |

All splitting is **subject-grouped** — windows from one person never leak
across folds. Full model documentation: [`model.md`](model.md).

## Models

| Model | Type | Held-out performance |
|---|---|---|
| FoG detector (app) | 150-tree gradient boosting, JSON export | F1 0.47 · bal. acc 0.71 · AP 0.50 |
| FoG detector (reference) | balanced histogram boosting | F1 0.49 · bal. acc 0.74 · AP 0.50 |
| Event-type model | balanced random forest (4 classes) | macro-F1 0.33 |
| Gait profile | K-means k=2 on PCA(16) subject profiles | silhouette 0.27, ARI 1.0 |

Cluster A (35 subjects) vs B (25): UPDRS-III-on 39.0 vs 32.6, NFOG-Q 18.7
vs 17.7 — directionally consistent, not statistically robust, so the app's
0–100 "gait severity" score is labelled a demo estimate.

Trained `.joblib` artifacts are committed under `models/`. The compact
on-device exports live in `app/assets/*.json`; regenerate with:

```bash
conda run -n base python ml/export_mobile_models.py
```

## App

- **Detect** — accelerometer → resample 128 Hz → 51 features/2 s window →
  boosted-tree score → vibration/visual rhythm cue on confirmed freeze.
- **Track** — per-walk charts (movement, FoG probability, freeze episodes),
  weekly trends, time-of-day patterns, cue-response stats.
- **Profile** — per-walk feature summaries → nearest K-means centre →
  severity estimate + cluster clinical context.
- **Background** — optional Android foreground service keeps detecting with
  the screen off behind a persistent notification.

Installable APK:
[**app-release.apk** (latest release)](https://github.com/mathew1046/DA-MP/releases/latest).

```bash
cd app
flutter pub get
flutter test            # Python↔Dart parity + screen tests
flutter run             # or: flutter build apk --release
```

See [`app/README.md`](app/README.md) for the full feature list.
Android only for background monitoring (Core Motion can't stream in
background on iOS). Research prototype — not a medical device.

## Layout

```
app/            Flutter app (StepCue)
ml/             model export script → app assets + parity fixtures
models/         trained joblib artifacts
notebooks/      01–04 analysis pipeline (execute in order)
data/           raw (git-ignored) + processed summaries
research/       reference Kaggle solutions
model.md        detailed model documentation
```
