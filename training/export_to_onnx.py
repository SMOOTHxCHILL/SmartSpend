"""
Step 5 export: converts the trained LightGBM model to ONNX for on-device
inference, and exports the TF-IDF vectorizer's vocabulary/IDF weights as JSON
so the same feature extraction can be reimplemented in Dart (ONNX mobile
runtimes don't support the text-tokenization ops needed to export the
vectorizer itself).

Also writes test_vectors.json: a set of known (input -> feature_vector)
pairs computed by the real Python pipeline. Use these to verify the Dart
feature extractor produces matching output BEFORE wiring it into the app --
a silent mismatch here would make the model quietly predict garbage with no
error thrown anywhere.

Usage:
    python export_to_onnx.py --model-dir model --out-dir model
"""

import argparse
import json
import numpy as np
import joblib
from onnxmltools import convert_lightgbm
from onnxmltools.convert.common.data_types import FloatTensorType


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", default="model")
    parser.add_argument("--out-dir", default="model")
    args = parser.parse_args()

    model = joblib.load(f"{args.model_dir}/categorizer_lgbm.joblib")
    vectorizer = joblib.load(f"{args.model_dir}/merchant_name_vectorizer.joblib")
    label_encoder = joblib.load(f"{args.model_dir}/label_encoder.joblib")

    n_text_features = len(vectorizer.get_feature_names_out())
    n_total_features = n_text_features + 5  # amount, log_amount, hour, day_of_week, is_debit

    # --- 1. ONNX export of the classifier ---
    initial_type = [('input', FloatTensorType([None, n_total_features]))]
    onnx_model = convert_lightgbm(model, initial_types=initial_type, target_opset=13)

    onnx_path = f"{args.out_dir}/categorizer.onnx"
    with open(onnx_path, "wb") as f:
        f.write(onnx_model.SerializeToString())
    print(f"Wrote {onnx_path}")

    # --- 2. Vectorizer weights as JSON (for the Dart port) ---
    vectorizer_json = {
        "vocabulary": {k: int(v) for k, v in vectorizer.vocabulary_.items()},
        "idf": vectorizer.idf_.tolist(),
        "ngram_range": list(vectorizer.ngram_range),
        "lowercase": vectorizer.lowercase,
        "norm": vectorizer.norm,
    }
    vec_path = f"{args.out_dir}/vectorizer.json"
    with open(vec_path, "w") as f:
        json.dump(vectorizer_json, f)
    print(f"Wrote {vec_path} ({len(vectorizer_json['vocabulary'])} vocab entries)")

    # --- 3. Label mapping ---
    label_path = f"{args.out_dir}/label_encoder.json"
    with open(label_path, "w") as f:
        json.dump({"classes": label_encoder.classes_.tolist()}, f)
    print(f"Wrote {label_path}: {label_encoder.classes_.tolist()}")

    # --- 4. Reference test vectors for verifying the Dart port ---
    test_cases = [
        {"merchant_name": "SWIGGY BLR", "amount": 350.0, "hour": 20, "day_of_week": 4, "is_debit": 1},
        {"merchant_name": "BIGBASKET COM", "amount": 1200.0, "hour": 10, "day_of_week": 1, "is_debit": 1},
        {"merchant_name": "AMAZON PAY", "amount": 2499.0, "hour": 15, "day_of_week": 6, "is_debit": 1},
        {"merchant_name": "APOLLO PHARMA", "amount": 480.0, "hour": 9, "day_of_week": 2, "is_debit": 1},
        {"merchant_name": "UNKNOWN NEW MERCHANT XYZ", "amount": 99.0, "hour": 12, "day_of_week": 0, "is_debit": 1},
    ]

    from scipy.sparse import hstack, csr_matrix
    import pandas as pd

    names = [c["merchant_name"] for c in test_cases]
    text_features = vectorizer.transform(names).toarray()

    output_cases = []
    for i, case in enumerate(test_cases):
        amount = case["amount"]
        log_amount = float(np.log1p(amount))
        numeric = [amount, log_amount, case["hour"], case["day_of_week"], case["is_debit"]]
        full_vector = text_features[i].tolist() + numeric

        pred_idx = int(model.predict(np.array([full_vector], dtype=np.float32))[0])
        pred_label = label_encoder.classes_[pred_idx]

        output_cases.append({
            "input": case,
            "feature_vector": full_vector,
            "expected_predicted_category": pred_label,
        })

    test_path = f"{args.out_dir}/test_vectors.json"
    with open(test_path, "w") as f:
        json.dump(output_cases, f, indent=2)
    print(f"Wrote {test_path} ({len(output_cases)} reference cases)")
    print("\nUse test_vectors.json to verify the Dart feature extractor before wiring it into the app.")


if __name__ == "__main__":
    main()
