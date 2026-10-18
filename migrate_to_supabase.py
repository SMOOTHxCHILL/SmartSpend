import os
import sqlite3
from datetime import datetime, timezone

import psycopg


SQLITE_PATH = "training/smartspend_debug.db"
SUPABASE_DB_URL = os.environ.get("SUPABASE_DB_URL")

if not SUPABASE_DB_URL:
    raise RuntimeError("SUPABASE_DB_URL environment variable is missing.")


def unix_ms_to_datetime(value):
    if value is None:
        return None

    return datetime.fromtimestamp(
        value / 1000,
        tz=timezone.utc,
    )


print("Opening SQLite database...")

sqlite_conn = sqlite3.connect(SQLITE_PATH)
sqlite_conn.row_factory = sqlite3.Row

print("Connecting to Supabase PostgreSQL...")

pg_conn = psycopg.connect(SUPABASE_DB_URL)

try:
    with pg_conn.cursor() as cur:

        # --------------------------------------------
        # 1. Merchants
        # --------------------------------------------
        print("Migrating merchants...")

        merchants = sqlite_conn.execute("""
            SELECT
                id,
                canonical_name,
                category,
                category_source,
                mcc,
                created_at,
                updated_at
            FROM merchants
            ORDER BY id
        """).fetchall()

        for row in merchants:
            cur.execute("""
                INSERT INTO merchants (
                    id,
                    canonical_name,
                    category,
                    category_source,
                    mcc,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO NOTHING
            """, (
                row["id"],
                row["canonical_name"],
                row["category"],
                row["category_source"],
                row["mcc"],
                unix_ms_to_datetime(row["created_at"]),
                unix_ms_to_datetime(row["updated_at"]),
            ))

        print(f"  Merchants: {len(merchants)}")

        # --------------------------------------------
        # 2. Raw SMS
        # --------------------------------------------
        print("Migrating raw SMS...")

        raw_sms = sqlite_conn.execute("""
            SELECT
                id,
                sender,
                body,
                received_at,
                sms_hash
            FROM raw_sms
            ORDER BY id
        """).fetchall()

        for row in raw_sms:
            cur.execute("""
                INSERT INTO raw_sms (
                    id,
                    sender,
                    body,
                    received_at,
                    sms_hash
                )
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (id) DO NOTHING
            """, (
                row["id"],
                row["sender"],
                row["body"],
                unix_ms_to_datetime(row["received_at"]),
                row["sms_hash"],
            ))

        print(f"  Raw SMS: {len(raw_sms)}")

        # --------------------------------------------
        # 3. Transactions
        # --------------------------------------------
        print("Migrating transactions...")

        transactions = sqlite_conn.execute("""
            SELECT
                id,
                raw_sms_id,
                bank,
                amount,
                type,
                raw_merchant,
                transaction_date,
                confidence,
                dedup_hash,
                created_at,
                merchant_id
            FROM parsed_transactions
            ORDER BY id
        """).fetchall()

        for row in transactions:
            cur.execute("""
                INSERT INTO transactions (
                    id,
                    raw_sms_id,
                    bank,
                    amount,
                    type,
                    raw_merchant,
                    transaction_date,
                    confidence,
                    dedup_hash,
                    created_at,
                    merchant_id
                )
                VALUES (
                    %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (id) DO NOTHING
            """, (
                row["id"],
                row["raw_sms_id"],
                row["bank"],
                row["amount"],
                row["type"],
                row["raw_merchant"],
                unix_ms_to_datetime(row["transaction_date"]),
                row["confidence"],
                row["dedup_hash"],
                unix_ms_to_datetime(row["created_at"]),
                row["merchant_id"],
            ))

        print(f"  Transactions: {len(transactions)}")

        # --------------------------------------------
        # 4. Merchant aliases
        # --------------------------------------------
        print("Migrating merchant aliases...")

        aliases = sqlite_conn.execute("""
            SELECT
                id,
                merchant_id,
                alias_text
            FROM merchant_aliases
            ORDER BY id
        """).fetchall()

        for row in aliases:
            cur.execute("""
                INSERT INTO merchant_aliases (
                    id,
                    merchant_id,
                    alias_text
                )
                VALUES (%s, %s, %s)
                ON CONFLICT (id) DO NOTHING
            """, (
                row["id"],
                row["merchant_id"],
                row["alias_text"],
            ))

        print(f"  Merchant aliases: {len(aliases)}")

    pg_conn.commit()

    print()
    print("Migration completed successfully.")

finally:
    sqlite_conn.close()
    pg_conn.close()