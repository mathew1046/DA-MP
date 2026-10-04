# Models used in StepCue

This document describes the two models that run on-device in the StepCue app:
the **binary freezing-of-gait (FoG) detector** and the **patient-level K-means
gait-profile model**, plus the evaluation protocol, datasets, and how the work
relates to the reference paper (Sri-iesaranusorn et al., 2025,
*Scientific Reports*, DOI 10.1038/s41598-025-22751-3).

---

## 1. Training data

**Source:** TLVMC Parkinson's Freezing of Gait Prediction dataset
(Kaggle competition `tlvmc-parkinsons-freezing-gait-prediction`), `tdcsfog`
subset — laboratory FoG-provoking tasks recorded with a tri-axial
accelerometer taped to the **lower back**.

| Property | Value |
|---|---|
| Recordings used | 506 |
| Subjects | 60 people with Parkinson's disease |
| Raw samples | 3,385,465 (~7.3 h at 128 Hz) |
| Sampling rate | 128 Hz |
| Axes | AccV (vertical), AccML (medio-lateral), AccAP (antero-posterior) |
| Medication state | 321 recordings on-medication, 185 off-medication |
| Task types | 3 standardized walking tasks (~170 recordings each) |
| Subject ages | 51–94 years |
| Years since diagnosis | 1–23 |
| UPDRS-III (on) | 15–79; (off) 15–91 |
| NFOG-Q (freezing questionnaire) | 0–26 |

**Labels:** every accelerometer sample is annotated by clinicians (video
review) as `StartHesitation`, `Turn`, `Walking`, or none. The union of the
three event types is the binary FoG label: **12.1 %** of samples and **15.9 %**
of extracted windows are positive. Clinical variables (UPDRS-III, NFOG-Q,
age, disease duration) are used only for evaluation and post-hoc analysis —
never as model inputs.

**Windowing:** overlapping windows of 256 samples (2.0 s) with a 128-sample
hop (1.0 s stride) → **25,689 windows**. A window is positive if its centre
sample falls inside a FoG annotation.

**Splitting:** all evaluation is **subject-grouped** — windows from one
person never cross train/validation boundaries, because overlapping windows
from the same gait are strongly correlated. Two protocols are used:

- 5-fold `StratifiedGroupKFold` cross-validation for model selection and
  threshold tuning, and
- a fixed held-out test set of **12 subjects (20 %)** never touched during
  training: `02bc69, 231c3b, 312788, 31d269, 7688c1, 7fcee9, bc3908,
  c7fee4, c8e721, d8836b, e9fc55, f62eec`.

---

## 2. Feature extraction (shared by both models)

Each 2 s window → **51 features**, computed identically in Python
(training) and Dart (on-device), verified by a parity fixture to ~1e-6.

Per axis (AccV, AccML, AccAP) and for the 3-D magnitude (4 signals × 12):

- mean, std, min, max, IQR, RMS
- jerk RMS (RMS of the first difference × fs)
- dominant frequency (strongest non-DC FFT bin after Hann windowing)
- locomotor-band power 0.5–3 Hz (log1p)
- freeze-band power 3–8 Hz (log1p)
- freeze index: log(freeze-band / locomotor-band) — the classic FoG
  spectral feature of Bächlin et al. (2010)
- spectral entropy of the normalised power spectrum

Plus 3 cross-axis Pearson correlations (V–ML, V–AP, ML–AP) = 48 + 3 = **51**.

For live phone input, raw accelerometer samples are first resampled to
128 Hz by linear interpolation on the timestamp stream.

---

## 3. Model 1 — Binary FoG detector

### Architecture

`GradientBoostingClassifier` (scikit-learn), exported to JSON and
re-implemented in Dart (tree traversal + logistic link — no Python runtime
on the phone).

| Parameter | Value |
|---|---|
| Estimators | 150 |
| Max depth | 3 |
| Learning rate | 0.08 |
| Subsample | 0.8 |
| Random state | 42 |
| Class weighting | sample weights, positive class ×~5.3 ((1−p)/p ≈ 0.841/0.159) |
| Init | log-odds of the class prior (scikit-learn default) |
| Decision threshold | **0.686** — argmax F1 on out-of-fold probabilities from grouped 5-fold CV |
| Exported size | ~100 KB JSON (150 trees: children, split feature, split threshold, leaf value) |

Inference: `raw = init_log_odds + Σ learning_rate·leaf(x)` over the 150
trees, then `p = 1/(1+e^−raw)`. Trees compare float32 inputs, matching
scikit-learn exactly.

### Why this model

Three class-balanced candidates were compared under grouped CV on the full
model (notebook evaluation):

| Candidate | CV F1 | CV balanced acc | CV avg precision |
|---|---|---|---|
| **Balanced histogram boosting** | **0.594 ± 0.060** | 0.773 | 0.659 |
| Balanced extra trees | 0.572 ± 0.108 | 0.725 | 0.666 |
| Balanced logistic regression | 0.519 ± 0.063 | 0.753 | 0.568 |

The compact 150-tree gradient booster was chosen for the app because it
serializes small, runs in microseconds per window in pure Dart, and matches
the larger model's held-out accuracy.

### On-device episode logic (not learned — deterministic)

- Window score ≥ threshold for **2 consecutive windows** (≈1.5 s) → a FoG
  **episode opens** and the rhythm cue fires.
- Score < threshold for 2 consecutive windows → episode closes, cue stops.
- Sensitivity setting shifts the threshold (Fewer +0.08 / More −0.12,
  clamped to [0.30, 0.95]).
- "On your feet" = window movement SD ≥ 0.45 m/s² with an estimable cadence
  (autocorrelation of vertical accel, step periods 0.33–1.0 s ⇔ 60–180
  steps/min).

### Metrics

Grouped 5-fold CV (threshold tuning set): average precision **0.655**.

Held-out 12 unseen subjects:

| Metric | Compact app model | Larger reference model (hist. boosting) |
|---|---|---|
| F1 | 0.471 | 0.487 |
| Balanced accuracy | 0.710 | 0.743 |
| Average precision | 0.502 | 0.501 |

Honest reading: the detector generalises to unseen people at balanced
accuracy ~0.71 — useful for a research prototype with vibration feedback,
not clinical-grade. It **detects ongoing freezing**; it does not predict
future episodes or falls.

---

## 4. Model 2 — Patient-level K-means gait profile

### Pipeline

`session summaries → median aggregation → StandardScaler → PCA(16) →
KMeans(2)`, all serialized to JSON (scaler mean/scale, PCA mean/components,
cluster centres, per-cluster clinical stats) and re-implemented in Dart.

1. **Session profile:** for each walk, take the median and IQR of each of
   the 51 window features → 102 profile features.
2. **Patient profile:** median of the session profiles (training: all
   recordings of one subject; in-app: all the user's walks).
3. **Standardize** (z-scores) → **PCA to 16 components** → **K-means**,
   Euclidean distance to the nearest centre.

### Choosing k

Evaluated k ∈ {2…6} on 60 subject profiles with mean silhouette plus
bootstrap stability (pairwise ARI across resamples):

| k | Silhouette | Stability (ARI) |
|---|---|---|
| **2** | **0.265** | **1.000** |
| 3 | 0.264 | 0.970 |
| 4 | 0.146 | 0.836 |
| 5 | 0.127 | 0.695 |
| 6 | 0.124 | 0.628 |

→ **k = 2** selected: best silhouette and perfectly stable.

### Resulting clusters (60 subjects)

| | Cluster A (35 subjects) | Cluster B (25 subjects) |
|---|---|---|
| UPDRS-III (on) | **39.0** | 32.6 |
| UPDRS-III (off) | **46.6** | 39.4 |
| NFOG-Q | 18.7 | 17.7 |
| FoG-window rate | 0.161 | 0.146 |
| Age | 70.7 | 67.4 |
| Years since dx | 10.2 | 9.0 |

Cluster A is the more-affected group on every clinical measure. Kruskal–
Wallis tests (Benjamini–Hochberg adjusted): UPDRS-III-on p = 0.030
unadjusted / **0.120 adjusted**; UPDRS-III-off 0.087/0.173; NFOG-Q
0.335/0.446; FoG rate 0.549. Direction is consistent but **not
statistically robust** — which is why the app shows a continuous
estimate, not a staging claim.

### Severity estimate shown in the app (demo)

`severity = 100 × (0.6·proximity + 0.4·burden)` where

- `proximity = d(B) / (d(A) + d(B))` — how close the patient's profile sits
  to Cluster A's centre vs B's in PCA space (1 = exactly on the
  more-affected centre), and
- `burden = min(observed frozen share / 0.4, 1)` — the app's own measured
  FoG burden, normalised.

Bands: <35 Mild · 35–65 Moderate · ≥65 High. It is a research/demo
estimate, explicitly labelled as such in-app — it is **not** a validated
clinical severity grade.

### Related analyses (same training run, not deployed)

- **Window-level K-means** (notebook 03): 51 window features → PCA(15) →
  K-means, k ∈ 2–8. Data-driven k = 2 (silhouette 0.383); paper-aligned
  k = 4 (silhouette 0.171) — NFOG-Q association p = 0.039, UPDRS-III n.s.
- **4-class FoG event-type model** (start hesitation / turning / walking
  freeze): balanced random forest, held-out macro-F1 0.332 — kept as a
  repository artifact, not shipped in the app.

---

## 5. What we referenced from Sri-iesaranusorn et al. (2025)

Paper: *"Parkinson's disease severity clustering based on gait activity
from mobile device"*, Scientific Reports — clusters gait cycles from the
mPower smartphone study (8,779 recordings, 1,957 participants) with
DTW-K-means, embeds them with an autoencoder + t-SNE, and finds 4 clusters
that correlate with self-reported MDS-UPDRS Parts I & II (most-severe
cluster: 2.43× balance/walking problems, 8.41× freezing).

**Directly adopted:**

- **The core framing** — unsupervised K-means on inertial gait data to find
  patient subgroups, validated **post-hoc** against clinical scores rather
  than trained on them (clinical variables never enter the clustering
  inputs).
- **Standardised gait units before clustering** — the paper extracts stride
  cycles and pads them to a uniform length (Algorithm 1, Q3 length); we use
  fixed 2 s windows + engineered features, which serves the same
  "equal-length input" role and is far cheaper on-device.
- **Dimensionality reduction before clustering/visualisation** — the paper
  uses autoencoder + t-SNE; we use PCA (16 components), the deployable
  linear equivalent that can be exported as a matrix.
- **Paper-aligned k = 4 comparison** — the paper identifies 4 gait
  clusters; we evaluated k = 4 alongside the data-driven selection and
  report it explicitly (silhouette 0.171 at window level) rather than
  assuming it.
- **Severity-cluster association testing** — the paper correlates clusters
  with MDS-UPDRS; we test UPDRS-III (on/off) and NFOG-Q with the same
  post-hoc group-comparison approach (Kruskal–Wallis + BH adjustment).
- **The conservative caveat** — the paper itself flags K-means variability
  as a limitation; our severity display is labelled an estimate for the
  same reason.

**Deliberate divergences:**

| Paper (mPower) | StepCue |
|---|---|
| Phone in pocket, free-living walking | Lower-back IMU, scripted FoG tasks |
| Stride segmentation + sequence padding | Fixed 2 s windows + 51 features |
| DTW K-means on raw stride shapes | Euclidean K-means on PCA'd feature profiles |
| Autoencoder + t-SNE embedding | PCA (linear, exportable, on-device) |
| Self-reported MDS-UPDRS I & II | Clinician-scored UPDRS-III & NFOG-Q |
| Unsupervised only | K-means profile **plus** supervised FoG detector |
| 4 clusters found | k = 2 supported by this dataset (k = 4 reported for comparison) |

## 6. Limitations carried into the app

- Detector held-out F1 ≈ 0.47 on unseen subjects; false alerts and misses
  occur — the UI states this.
- Trained on lower-back sensors in scripted tasks; phone-at-waist use is an
  approximation (placement guide in-app).
- The K-means split is real but its clinical separation is not
  statistically robust (adjusted p > 0.05) — the 0–100 score is a demo
  estimate, not a diagnosis or staging.
- Only ~7.3 h of data from 60 subjects; no real-world daily-living
  recordings.
