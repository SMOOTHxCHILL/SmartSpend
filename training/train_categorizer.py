"""
Trains the SmartSpend category classifier.

Deliberately does NOT use merchant_id as a feature. Category is stored at the
merchant level in the app's schema, so every transaction from a known
merchant already has a category via the resolver/graph -- using merchant_id
here would just let the model memorize that lookup table and report
misleadingly perfect accuracy while learning nothing that generalizes.

Instead this predicts category from signals available for a BRAND NEW,
never-before-seen merchant:
  - character n-grams of the merchant name (captures "SWIGGY*BLR123" ~
    "SWIGGY" style patterns without needing exact string matches)
  - amount / log(amount)
  - hour of day, day of week
  - transaction type (debit/credit)

That's the actual use case: the moment a new merchant appears and MCC
lookup + merchant graph haven't resolved it yet, this model gives a
same-session category guess instead of defaulting to 'Other'.

Usage:
    python train_categorizer.py --csv labeled_transactions.csv --out-dir model
"""

import argparse
import warnings
from datetime import datetime

import numpy as np
import pandas as pd
from scipy.sparse import hstack, csr_matrix
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import StratifiedKFold, cross_val_predict
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report
import lightgbm as lgb
import joblib
import os


def build_features(df: pd.DataFrame, vectorizer: TfidfVectorizer = None, fit: bool = True):
    if fit:
        vectorizer = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 5), max_features=300)
        text_features = vectorizer.fit_transform(df["merchant_name"].fillna(""))
    else:
        text_features = vectorizer.transform(df["merchant_name"].fillna(""))

    amount = df["amount"].astype(float).to_numpy()
    log_amount = np.log1p(amount)

    dt = pd.to_datetime(df["transaction_date"].astype("int64"), unit="ms")
    hour = dt.dt.hour.to_numpy()
    day_of_week = dt.dt.dayofweek.to_numpy()
    is_debit = (df["type"] == "debit").astype(int).to_numpy()

    numeric_features = np.column_stack([amount, log_amount, hour, day_of_week, is_debit])
    numeric_sparse = csr_matrix(numeric_features)

    features = hstack([text_features, numeric_sparse]).tocsr()
    return features, vectorizer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True, help="Path to labeled_transactions.csv from export step")
    parser.add_argument("--out-dir", default="model", help="Directory to save trained model artifacts")
    args = parser.parse_args()

    df = pd.read_csv(args.csv)

    if len(df) < 30:
        warnings.warn(
            f"Only {len(df)} labeled transactions found. This is very little data -- "
            "treat any metrics below as directional, not reliable. Keep correcting "
            "transactions and re-run once you have more, ideally 30+ per category."
        )

    class_counts = df["category"].value_counts()
    thin_classes = class_counts[class_counts < 2]
    if len(thin_classes) > 0:
        print(
            f"Dropping categories with fewer than 2 examples (can't cross-validate them): "
            f"{list(thin_classes.index)}"
        )
        df = df[~df["category"].isin(thin_classes.index)]

    if df["category"].nunique() < 2:
        raise SystemExit(
            "Need at least 2 categories with 2+ examples each to train. "
            "Correct a wider spread of transactions first."
        )

    label_encoder = LabelEncoder()
    y = label_encoder.fit_transform(df["category"])

    X, vectorizer = build_features(df, fit=True)

    min_class_count = df["category"].value_counts().min()
    n_splits = max(2, min(5, min_class_count))

    print(f"Training on {len(df)} examples, {df['category'].nunique()} categories, {n_splits}-fold CV")

    skf = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=42)

    base_model = lgb.LGBMClassifier(
        objective="multiclass",
        num_class=df["category"].nunique(),
        n_estimators=200,
        learning_rate=0.05,
        max_depth=6,
        min_child_samples=max(1, len(df) // 50),
        verbose=-1,
    )

    y_pred = cross_val_predict(base_model, X, y, cv=skf, method="predict")

    print("\nPer-category precision/recall (cross-validated):")
    print(
        classification_report(
            y, y_pred,
            labels=list(range(len(label_encoder.classes_))),
            target_names=label_encoder.classes_,
            zero_division=0,
        )
    )

    # Fit the final model on all available labeled data for export.
    final_model = lgb.LGBMClassifier(
        objective="multiclass",
        num_class=df["category"].nunique(),
        n_estimators=200,
        learning_rate=0.05,
        max_depth=6,
        min_child_samples=max(1, len(df) // 50),
        verbose=-1,
    )
    final_model.fit(X, y)

    os.makedirs(args.out_dir, exist_ok=True)
    joblib.dump(final_model, os.path.join(args.out_dir, "categorizer_lgbm.joblib"))
    joblib.dump(vectorizer, os.path.join(args.out_dir, "merchant_name_vectorizer.joblib"))
    joblib.dump(label_encoder, os.path.join(args.out_dir, "label_encoder.joblib"))

    print(f"\nSaved model artifacts to {args.out_dir}/")
    print("Next step (Phase 2, step 5): export categorizer_lgbm.joblib to ONNX for on-device inference.")


if __name__ == "__main__":
    main()
