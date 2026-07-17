"""
load_raw_data.py

Loads the 5 source CSVs into the raw schema of the gtm_analytics
Postgres database, exactly as they exist on disk (no cleaning applied
here -- that happens later when we build the analytics schema).

Requires: psycopg2-binary, pandas (already installed in venv)
"""

import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from pathlib import Path

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "gtm_analytics",
    "user": "shravankumaar",   # matches your Mac username / Postgres.app default role
}

RAW_DIR = Path("data/raw")
PROCESSED_DIR = Path("data/processed")

# Each entry: (csv_path, table_name, list_of_columns_in_table_order)
LOAD_PLAN = [
    (
        RAW_DIR / "accounts.csv",
        "raw.accounts",
        ["account", "sector", "year_established", "revenue", "employees",
         "office_location", "subsidiary_of"],
    ),
    (
        RAW_DIR / "products.csv",
        "raw.products",
        ["product", "series", "sales_price"],
    ),
    (
        RAW_DIR / "sales_teams.csv",
        "raw.sales_teams",
        ["sales_agent", "manager", "regional_office"],
    ),
    (
        RAW_DIR / "sales_pipeline.csv",
        "raw.sales_pipeline",
        ["opportunity_id", "sales_agent", "product", "account", "deal_stage",
         "engage_date", "close_date", "close_value"],
    ),
    (
        PROCESSED_DIR / "subscriptions.csv",
        "raw.subscriptions",
        ["subscription_id", "opportunity_id", "account", "product", "sales_agent",
         "start_date", "renewal_date", "starting_arr", "renewal_outcome", "renewal_arr"],
    ),
]


# Columns that must land in Postgres as INTEGER, not float, even if a row
# is missing a value. Pandas' nullable "Int64" dtype (capital I) allows
# NA values while keeping non-null values as real integers rather than
# silently upcasting the whole column to float64.
INTEGER_COLUMNS_BY_TABLE = {
    "raw.accounts": ["year_established", "employees"],
}


def load_table(conn, csv_path, table_name, columns):
    if not csv_path.exists():
        raise FileNotFoundError(f"Missing input file: {csv_path}")

    df = pd.read_csv(csv_path)

    for int_col in INTEGER_COLUMNS_BY_TABLE.get(table_name, []):
        if int_col in df.columns:
            df[int_col] = df[int_col].astype("Int64")

    # Keep only the expected columns, in the right order. Convert NaN to None
    # per-cell so psycopg2 writes real SQL NULLs. (Note: df.where(notnull, None)
    # does NOT reliably work here -- pandas coerces None back to NaN for
    # numeric-dtype columns, so we convert explicitly per value instead.)
    # Also convert numpy scalar types (int64, float64) to native Python
    # types via .item(), since psycopg2 cannot adapt numpy types directly.
    df = df[columns]

    def clean_value(v):
        if pd.isna(v):
            return None
        if hasattr(v, "item"):
            return v.item()
        return v

    records = [
        tuple(clean_value(v) for v in row)
        for row in df.itertuples(index=False, name=None)
    ]

    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE TABLE {table_name} CASCADE;")
        col_list = ", ".join(columns)
        query = f"INSERT INTO {table_name} ({col_list}) VALUES %s"
        execute_values(cur, query, records)
    conn.commit()

    print(f"Loaded {len(records)} rows into {table_name}")


def main():
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        for csv_path, table_name, columns in LOAD_PLAN:
            load_table(conn, csv_path, table_name, columns)

        print("\n--- Row count verification ---")
        with conn.cursor() as cur:
            for _, table_name, _ in LOAD_PLAN:
                cur.execute(f"SELECT COUNT(*) FROM {table_name};")
                count = cur.fetchone()[0]
                print(f"{table_name}: {count} rows")
    finally:
        conn.close()

    print("\nDone.")


if __name__ == "__main__":
    main()
