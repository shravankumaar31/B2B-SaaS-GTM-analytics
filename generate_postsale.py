"""
generate_postsale.py

Builds a synthetic "subscriptions" table from Won opportunities in the
Maven CRM Sales Opportunities dataset. This adds a post-sale layer
(renewals, expansion, churn) on top of a dataset that otherwise only
covers pre-sale pipeline activity.

Input:  data/raw/sales_pipeline.csv
Output: data/processed/subscriptions.csv

Renewal outcome split (reproducible via random.seed):
    70% flat renewal   -> renewal_arr = starting_arr
    15% expansion      -> renewal_arr = starting_arr * random(1.10 - 1.40)
    10% churn          -> renewal_arr = 0
    5%  contraction    -> renewal_arr = starting_arr * random(0.60 - 0.90)
"""

import pandas as pd
import random
from pathlib import Path
from datetime import timedelta

# ---------------------------------------------------------------
# Config
# ---------------------------------------------------------------
RAW_DIR = Path("data/raw")
PROCESSED_DIR = Path("data/processed")
INPUT_FILE = RAW_DIR / "sales_pipeline.csv"
OUTPUT_FILE = PROCESSED_DIR / "subscriptions.csv"

SEED = 42
SUBSCRIPTION_TERM_MONTHS = 12

# Renewal outcome probabilities (must sum to 1.0)
P_FLAT = 0.70
P_EXPAND = 0.15
P_CHURN = 0.10
P_CONTRACT = 0.05

EXPAND_MULTIPLIER_RANGE = (1.10, 1.40)
CONTRACT_MULTIPLIER_RANGE = (0.60, 0.90)


def add_months(date, months):
    """Add a whole number of months to a date without extra dependencies."""
    month = date.month - 1 + months
    year = date.year + month // 12
    month = month % 12 + 1
    day = min(date.day, 28)  # avoid day-overflow issues (e.g. Jan 31 + 1mo)
    return date.replace(year=year, month=month, day=day)


def assign_renewal_outcome(rng):
    """Pick a renewal outcome using the configured probability split."""
    roll = rng.random()
    if roll < P_FLAT:
        return "Renewed Flat", 1.0
    elif roll < P_FLAT + P_EXPAND:
        multiplier = rng.uniform(*EXPAND_MULTIPLIER_RANGE)
        return "Expansion", multiplier
    elif roll < P_FLAT + P_EXPAND + P_CHURN:
        return "Churned", 0.0
    else:
        multiplier = rng.uniform(*CONTRACT_MULTIPLIER_RANGE)
        return "Contraction", multiplier


def main():
    rng = random.Random(SEED)

    if not INPUT_FILE.exists():
        raise FileNotFoundError(
            f"Could not find {INPUT_FILE}. Run this script from the "
            f"project root (~/gtm-analytics), not from inside data/raw."
        )

    print(f"Reading {INPUT_FILE} ...")
    df = pd.read_csv(INPUT_FILE, parse_dates=["engage_date", "close_date"])

    won = df[df["deal_stage"] == "Won"].copy()
    print(f"Total opportunities: {len(df)}")
    print(f"Won opportunities:   {len(won)}")

    if len(won) == 0:
        raise ValueError(
            "No rows with deal_stage == 'Won' were found. "
            "Check the exact spelling/casing of deal_stage values with: "
            "df['deal_stage'].unique()"
        )

    # Drop any Won deals missing a close_date or close_value; can't build
    # a subscription without a start date and an ARR figure.
    before = len(won)
    won = won.dropna(subset=["close_date", "close_value"])
    dropped = before - len(won)
    if dropped:
        print(f"Dropped {dropped} Won rows missing close_date/close_value.")

    records = []
    for i, row in enumerate(won.itertuples(index=False), start=1):
        subscription_id = f"SUB-{i:05d}"
        start_date = row.close_date
        renewal_date = add_months(start_date, SUBSCRIPTION_TERM_MONTHS)
        starting_arr = round(float(row.close_value), 2)

        outcome, multiplier = assign_renewal_outcome(rng)
        renewal_arr = round(starting_arr * multiplier, 2)

        records.append({
            "subscription_id": subscription_id,
            "opportunity_id": row.opportunity_id,
            "account": row.account,
            "product": row.product,
            "sales_agent": row.sales_agent,
            "start_date": start_date.date(),
            "renewal_date": renewal_date.date(),
            "starting_arr": starting_arr,
            "renewal_outcome": outcome,
            "renewal_arr": renewal_arr,
        })

    out_df = pd.DataFrame(records)

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    out_df.to_csv(OUTPUT_FILE, index=False)
    print(f"\nWrote {len(out_df)} subscription records to {OUTPUT_FILE}")

    # ---------------------------------------------------------------
    # Quick validation summary - sanity check the numbers look realistic
    # ---------------------------------------------------------------
    print("\n--- Renewal outcome breakdown ---")
    print(out_df["renewal_outcome"].value_counts())
    print("\n--- Renewal outcome % ---")
    print((out_df["renewal_outcome"].value_counts(normalize=True) * 100).round(1))

    total_starting_arr = out_df["starting_arr"].sum()
    total_renewal_arr = out_df["renewal_arr"].sum()

    # GRR: renewal ARR capped at starting ARR (i.e., expansion doesn't count toward GRR)
    capped_renewal = out_df.apply(
        lambda r: min(r["renewal_arr"], r["starting_arr"]), axis=1
    )
    grr = capped_renewal.sum() / total_starting_arr * 100

    # NRR: all renewal ARR including expansion, relative to starting ARR
    nrr = total_renewal_arr / total_starting_arr * 100

    logo_churn = (out_df["renewal_outcome"] == "Churned").mean() * 100

    print(f"\n--- ARR-based metrics (sanity check) ---")
    print(f"Total starting ARR:  ${total_starting_arr:,.2f}")
    print(f"Total renewal ARR:   ${total_renewal_arr:,.2f}")
    print(f"Gross Revenue Retention (GRR): {grr:.1f}%")
    print(f"Net Revenue Retention (NRR):   {nrr:.1f}%")
    print(f"Logo churn rate:               {logo_churn:.1f}%")
    print("\nExpected ranges: GRR ~85-90%, NRR ~100-105%, logo churn ~8-12%")


if __name__ == "__main__":
    main()
