"""
export_analytics_views.py

Tableau Public does not support live database connections -- it only
accepts file-based sources (Excel, CSV, JSON, etc). This script
exports the 3 analytics views built in 05_analytics_views.sql to CSV
files that Tableau Public can import directly.

Outputs to data/processed/tableau/:
    vw_pipeline_summary.csv
    vw_agent_scorecard.csv
    vw_retention_summary.csv
"""

import pandas as pd
import psycopg2
from pathlib import Path

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "gtm_analytics",
    "user": "shravankumaar",
}

OUTPUT_DIR = Path("data/processed/tableau")

VIEWS_TO_EXPORT = [
    "vw_pipeline_summary",
    "vw_agent_scorecard",
    "vw_retention_summary",
]


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    conn = psycopg2.connect(**DB_CONFIG)

    try:
        for view_name in VIEWS_TO_EXPORT:
            df = pd.read_sql(f"SELECT * FROM analytics.{view_name};", conn)
            output_path = OUTPUT_DIR / f"{view_name}.csv"
            df.to_csv(output_path, index=False)
            print(f"Exported {len(df)} rows -> {output_path}")
    finally:
        conn.close()

    print("\nDone. These CSVs are ready to import into Tableau Public.")


if __name__ == "__main__":
    main()
