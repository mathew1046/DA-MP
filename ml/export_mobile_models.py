"""Train a compact FoG detector and export it, plus the patient-profile K-means model, for the Flutter app."""

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import average_precision_score, balanced_accuracy_score, f1_score, precision_recall_curve
from sklearn.model_selection import StratifiedGroupKFold

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "data" / "processed"
RAW = ROOT / "data" / "raw"
ASSETS = ROOT / "app" / "assets"
FIXTURES = ROOT / "app" / "test" / "fixtures"
FS = 128
WINDOW = 256
SIGNALS = ["AccV", "AccML", "AccAP"]
EVENTS = ["StartHesitation", "Turn", "Walking"]
META = {"Id", "Subject", "Medication", "window_start_s", "target"}
SEED = 42


def signal_features(values, prefix):
    values = np.asarray(values, dtype=np.float64)
    centered = values - values.mean()
    power = np.abs(np.fft.rfft(centered * np.hanning(len(centered)))) ** 2
    freqs = np.fft.rfftfreq(len(centered), d=1 / FS)
    positive = power.copy()
    positive[0] = 0
    locomotor = power[(freqs >= 0.5) & (freqs < 3.0)].sum()
    freeze = power[(freqs >= 3.0) & (freqs <= 8.0)].sum()
    probabilities = power / (power.sum() + 1e-12)
    q25, q75 = np.quantile(values, [0.25, 0.75])
    return {
        f"{prefix}_mean": values.mean(),
        f"{prefix}_std": values.std(),
        f"{prefix}_min": values.min(),
        f"{prefix}_max": values.max(),
        f"{prefix}_iqr": q75 - q25,
        f"{prefix}_rms": np.sqrt(np.mean(values**2)),
        f"{prefix}_jerk_rms": np.sqrt(np.mean((np.diff(values) * FS) ** 2)),
        f"{prefix}_dominant_hz": freqs[np.argmax(positive)],
        f"{prefix}_locomotor_power": np.log1p(locomotor),
        f"{prefix}_freeze_power": np.log1p(freeze),
        f"{prefix}_freeze_index": np.log((freeze + 1e-9) / (locomotor + 1e-9)),
        f"{prefix}_spectral_entropy": -(probabilities * np.log(probabilities + 1e-12)).sum(),
    }


def window_features(window):
    features = {}
    for index, column in enumerate(SIGNALS):
        features.update(signal_features(window[:, index], column))
    features.update(signal_features(np.linalg.norm(window, axis=1), "Magnitude"))
    corr = np.nan_to_num(np.corrcoef(window, rowvar=False), nan=0.0)
    features.update({"corr_V_ML": corr[0, 1], "corr_V_AP": corr[0, 2], "corr_ML_AP": corr[1, 2]})
    return features


def export_tree(tree):
    t = tree.tree_
    return {
        "left": t.children_left.tolist(),
        "right": t.children_right.tolist(),
        "feature": t.feature.tolist(),
        "threshold": [float(x) for x in t.threshold],
        "value": [float(v[0][0]) for v in t.value],
    }


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    FIXTURES.mkdir(parents=True, exist_ok=True)
    windows = pd.read_csv(PROCESSED / "tdcsfog_features_2s.csv", dtype={"Id": str, "Subject": str})
    features = [c for c in windows.columns if c not in META]
    X, y, groups = windows[features], (windows["target"] > 0).astype(int), windows["Subject"]
    held_out = set(json.loads((PROCESSED / "evaluation_metrics.json").read_text())["held_out_subjects"])
    train = ~groups.isin(held_out)

    params = dict(n_estimators=150, max_depth=3, learning_rate=0.08, subsample=0.8, random_state=SEED)
    weights = np.where(y[train] == 1, (1 - y[train].mean()) / y[train].mean(), 1.0)

    cv = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=SEED)
    oof = np.zeros(train.sum())
    Xt, yt, gt = X[train].reset_index(drop=True), y[train].reset_index(drop=True), groups[train].reset_index(drop=True)
    for fit_idx, val_idx in cv.split(Xt, yt, gt):
        model = GradientBoostingClassifier(**params)
        model.fit(Xt.iloc[fit_idx], yt.iloc[fit_idx], sample_weight=weights[fit_idx])
        oof[val_idx] = model.predict_proba(Xt.iloc[val_idx])[:, 1]
    precision, recall, thresholds = precision_recall_curve(yt, oof)
    f1 = 2 * precision[:-1] * recall[:-1] / (precision[:-1] + recall[:-1] + 1e-12)
    threshold = float(thresholds[np.argmax(f1)])

    evaluated = GradientBoostingClassifier(**params).fit(X[train], y[train], sample_weight=weights)
    held_prob = evaluated.predict_proba(X[~train])[:, 1]
    held_pred = held_prob >= threshold
    metrics = {
        "model": "GradientBoostingClassifier (150 trees, depth 3, class-weighted)",
        "threshold_from_grouped_cv": threshold,
        "cv_average_precision": float(average_precision_score(yt, oof)),
        "held_out_subjects": len(held_out),
        "held_out_f1": float(f1_score(y[~train], held_pred)),
        "held_out_balanced_accuracy": float(balanced_accuracy_score(y[~train], held_pred)),
        "held_out_average_precision": float(average_precision_score(y[~train], held_prob)),
    }
    print(json.dumps(metrics, indent=2))

    all_weights = np.where(y == 1, (1 - y.mean()) / y.mean(), 1.0)
    final = GradientBoostingClassifier(**params).fit(X, y, sample_weight=all_weights)
    init_prior = final.init_.class_prior_[1]
    detector = {
        "type": "gradient_boosting_binary",
        "sampling_rate_hz": FS,
        "window_samples": WINDOW,
        "hop_samples": WINDOW // 2,
        "feature_names": features,
        "init_log_odds": float(np.log(init_prior / (1 - init_prior))),
        "learning_rate": params["learning_rate"],
        "threshold": threshold,
        "metrics": metrics,
        "trees": [export_tree(est[0]) for est in final.estimators_],
    }
    (ASSETS / "fog_detector.json").write_text(json.dumps(detector, separators=(",", ":")))

    bundle = joblib.load(ROOT / "models" / "kmeans_subject_profile_model.joblib")
    pipe = bundle["pipeline"]
    scaler, pca, kmeans = pipe.named_steps["standardize"], pipe.named_steps["pca"], pipe.named_steps["kmeans"]
    subject_clusters = pd.read_csv(PROCESSED / "kmeans_subject_clusters.csv", dtype={"Subject": str})
    cluster_stats = [
        {
            "subjects": int((subject_clusters["cluster"] == k + 1).sum()),
            "updrs_on": float(subject_clusters.loc[subject_clusters["cluster"] == k + 1, "UPDRSIII_On"].mean()),
            "updrs_off": float(subject_clusters.loc[subject_clusters["cluster"] == k + 1, "UPDRSIII_Off"].mean()),
            "nfogq": float(subject_clusters.loc[subject_clusters["cluster"] == k + 1, "NFOGQ"].mean()),
            "fog_rate": float(subject_clusters.loc[subject_clusters["cluster"] == k + 1, "tDCS_FoG_window_rate"].mean()),
        }
        for k in range(len(kmeans.cluster_centers_))
    ]
    profile = {
        "type": "kmeans_subject_profile",
        "window_features": features,
        "profile_features": bundle["feature_columns"],
        "scaler_mean": scaler.mean_.tolist(),
        "scaler_scale": scaler.scale_.tolist(),
        "pca_mean": pca.mean_.tolist(),
        "pca_components": pca.components_.tolist(),
        "centers": kmeans.cluster_centers_.tolist(),
        "cluster_stats": cluster_stats,
        "note": bundle["interpretation"],
    }
    (ASSETS / "gait_profile_kmeans.json").write_text(json.dumps(profile, separators=(",", ":")))

    meta = pd.read_csv(RAW / "tdcsfog_metadata.csv", dtype={"Id": str, "Subject": str})
    held = meta[meta["Subject"].isin(held_out) & meta["Id"].map(lambda i: (RAW / f"{i}.csv").exists())]
    burden = {i: pd.read_csv(RAW / f"{i}.csv", usecols=EVENTS).any(axis=1).mean() for i in held["Id"]}
    ranked = sorted(burden, key=burden.get)
    picks = [ranked[int(q * (len(ranked) - 1))] for q in (0.15, 0.35, 0.55, 0.7, 0.85, 1.0)]
    demo_dir = ASSETS / "demo"
    demo_dir.mkdir(exist_ok=True)
    for old in demo_dir.glob("*.csv"):
        old.unlink()
    (ASSETS / "demo_walk.csv").unlink(missing_ok=True)
    catalogue = []
    for index, recording in enumerate(picks):
        frame = pd.read_csv(RAW / f"{recording}.csv")
        frame["FoG"] = frame[EVENTS].any(axis=1).astype(int)
        name = f"walk_{index + 1}.csv"
        frame[SIGNALS + ["FoG"]].round(3).to_csv(demo_dir / name, index=False)
        row = held[held["Id"] == recording].iloc[0]
        catalogue.append({"file": f"assets/demo/{name}", "recording": recording, "subject": row["Subject"],
                          "medication": row["Medication"], "seconds": round(len(frame) / FS, 1),
                          "annotated_fog_fraction": round(float(frame["FoG"].mean()), 4)})
    (demo_dir / "catalogue.json").write_text(json.dumps(catalogue, indent=2))
    print(json.dumps(catalogue, indent=2))
    demo = pd.read_csv(RAW / f"{picks[-1]}.csv")

    first_fog = int(np.flatnonzero(demo[EVENTS].any(axis=1).to_numpy())[0])
    signal = demo[SIGNALS].round(3).to_numpy()[first_fog:first_fog + WINDOW]
    fx = window_features(signal)
    vector = np.array([[fx[name] for name in features]])
    fixture = {
        "window": signal.tolist(),
        "features": {k: float(v) for k, v in fx.items()},
        "probability": float(final.predict_proba(pd.DataFrame(vector, columns=features))[0, 1]),
    }
    (FIXTURES / "parity.json").write_text(json.dumps(fixture))


def export_profile_fixture():
    profiles = pd.read_csv(PROCESSED / "kmeans_subject_sensor_profiles.csv", dtype={"Subject": str})
    clusters = pd.read_csv(PROCESSED / "kmeans_subject_clusters.csv", dtype={"Subject": str})
    rows = profiles.merge(clusters[["Subject", "cluster"]], on="Subject").head(12)
    fixture = [
        {"cluster": int(r["cluster"]) - 1, "profile": {c: float(r[c]) for c in profiles.columns if c != "Subject"}}
        for _, r in rows.iterrows()
    ]
    (FIXTURES / "profile_parity.json").write_text(json.dumps(fixture))


if __name__ == "__main__":
    main()
    export_profile_fixture()
