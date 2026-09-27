# Project instructions

- Use the Conda `base` environment.
- Run notebooks from the project root so relative paths resolve correctly.
- Execute the notebooks in order:
  - `conda run -n base jupyter nbconvert --to notebook --execute --inplace notebooks/01_data_exploration.ipynb --ExecutePreprocessor.timeout=1200`
  - `conda run -n base jupyter nbconvert --to notebook --execute --inplace notebooks/02_fog_model.ipynb --ExecutePreprocessor.timeout=3600`
  - `conda run -n base jupyter nbconvert --to notebook --execute --inplace notebooks/03_kmeans_gait_clustering.ipynb --ExecutePreprocessor.timeout=3600`
- Raw labeled tDCS FoG CSV files and Kaggle metadata are stored in `data/raw/`.
- Window features are cached in `data/processed/tdcsfog_features_2s.csv`.
- The app-focused model is `models/fog_binary_model_final.joblib`; event-type classification is available in `models/fog_event_model_final.joblib`.
- The data-driven and paper-aligned K-means artifacts are `models/kmeans_gait_clusters_selected.joblib` and `models/kmeans_gait_clusters_k4.joblib`.
- Evaluation must remain subject-grouped. Do not randomly split overlapping windows across train and test sets.
