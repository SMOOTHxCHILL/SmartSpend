"""
Exports labeled training data from the SmartSpend on-device SQLite database.

Only transactions whose resolved merchant has category_source = 'user_corrected'
are exported. MCC-inferred ('default') categories are heuristic guesses, not
verified ground truth, so they're excluded from training data -- otherwise the
model would learn from its own (or the seed table's) unverified guesses.

Usage:
    python export_labeled_data.py --db smartspend_debug.db --out labeled_transactions.csv

Get the db file off the device first, e.g.:
    adb shell run-as <your.package.name> cat /data/data/<your.package.name>/databases/smartspend.db > smartspend_debug.db
"""

import argparse
import sqlite3
import csv
import sys


QUERY = """
    SELECT
        pt.id,
        pt.amount,
        pt.type,
        pt.raw_merchant,
        pt.transaction_date,
        m.canonical_name AS merchant_name,
        m.category AS category,
        m.mcc AS mcc
    FROM parsed_transactions pt
    JOIN merchants m ON pt.merchant_id = m.id
    WHERE m.category_source = 'user_corrected'
      AND pt.transaction_date IS NOT NULL
    ORDER BY pt.transaction_date ASC
"""


def export(db_path: str, out_path: str) -> int:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    rows = conn.execute(QUERY).fetchall()
    conn.close()

    if not rows:
        print(
            "No user_corrected transactions found. "
            "Correct a few more transactions on-device before exporting.",
            file=sys.stderr,
        )
        return 0

    fieldnames = [
        "id", "amount", "type", "raw_merchant",
        "transaction_date", "merchant_name", "category", "mcc",
    ]

    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row[k] for k in fieldnames})

    return len(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True, help="Path to the pulled smartspend.db file")
    parser.add_argument("--out", default="labeled_transactions.csv", help="Output CSV path")
    args = parser.parse_args()

    count = export(args.db, args.out)
    print(f"Exported {count} labeled transactions to {args.out}")

    # Quick per-category breakdown so you can see if any category is too
    # thin to train on yet.
    if count > 0:
        import collections
        with open(args.out, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            counts = collections.Counter(row["category"] for row in reader)
        print("\nPer-category counts:")
        for category, n in sorted(counts.items(), key=lambda x: -x[1]):
            print(f"  {category}: {n}")
