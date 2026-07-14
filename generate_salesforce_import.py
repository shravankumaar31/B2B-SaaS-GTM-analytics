"""
generate_salesforce_import.py

Transforms the raw Maven CRM CSVs into two Salesforce Data Import Wizard
ready files:
    data/processed/salesforce/sfdc_accounts_import.csv
    data/processed/salesforce/sfdc_opportunities_import.csv

Import these in Salesforce in this order:
    1. sfdc_accounts_import.csv       (Setup -> Data Import Wizard -> Accounts)
    2. sfdc_opportunities_import.csv  (Setup -> Data Import Wizard -> Opportunities,
                                        matched to existing Accounts by name)

Documented assumptions (also written to docs/decisions.md):
    - accounts.revenue is in millions of USD per the data dictionary;
      multiplied by 1,000,000 for Salesforce's Annual Revenue field.
    - Known typos corrected: "technolgy" -> "technology" (sector),
      "Philipines" -> "Philippines" (office_location).
    - deal_stage mapped to Salesforce StageName:
          Prospecting -> Prospecting
          Engaging    -> Negotiation/Review
          Won         -> Closed Won
          Lost        -> Closed Lost
    - Salesforce requires a Close Date on every Opportunity. Rows missing
      close_date get a placeholder: engage_date + 90 days if engage_date
      exists, otherwise today + 90 days.
    - Salesforce requires an Amount for meaningful reporting. Rows missing
      close_value (i.e. still-open deals) get the product's list
      sales_price as an estimated deal value.
"""

import pandas as pd
from pathlib import Path
from datetime import datetime, timedelta

RAW_DIR = Path("data/raw")
OUT_DIR = Path("data/processed/salesforce")

STAGE_MAP = {
    "Prospecting": "Prospecting",
    "Engaging": "Negotiation/Review",
    "Won": "Closed Won",
    "Lost": "Closed Lost",
}

TYPO_FIXES_SECTOR = {"technolgy": "technology"}
TYPO_FIXES_COUNTRY = {"Philipines": "Philippines"}

PLACEHOLDER_HORIZON_DAYS = 90


def build_accounts_import():
    accounts = pd.read_csv(RAW_DIR / "accounts.csv")

    accounts["sector"] = accounts["sector"].replace(TYPO_FIXES_SECTOR)
    accounts["office_location"] = accounts["office_location"].replace(TYPO_FIXES_COUNTRY)

    out = pd.DataFrame({
        "Account Name": accounts["account"],
        "Industry": accounts["sector"],
        "Annual Revenue": (accounts["revenue"] * 1_000_000).round(2),
        "NumberOfEmployees": accounts["employees"],
        "BillingCountry": accounts["office_location"],
        "Description": accounts.apply(
            lambda r: f"Founded {r['year_established']}"
            + (f"; subsidiary of {r['subsidiary_of']}" if pd.notna(r["subsidiary_of"]) else ""),
            axis=1,
        ),
    })
    return out


def build_opportunities_import():
    pipeline = pd.read_csv(RAW_DIR / "sales_pipeline.csv", parse_dates=["engage_date", "close_date"])
    products = pd.read_csv(RAW_DIR / "products.csv")
    price_lookup = dict(zip(products["product"], products["sales_price"]))

    today = pd.Timestamp(datetime.today().date())

    def resolve_close_date(row):
        if pd.notna(row["close_date"]):
            return row["close_date"]
        if pd.notna(row["engage_date"]):
            return row["engage_date"] + timedelta(days=PLACEHOLDER_HORIZON_DAYS)
        return today + timedelta(days=PLACEHOLDER_HORIZON_DAYS)

    def resolve_amount(row):
        if pd.notna(row["close_value"]):
            return row["close_value"]
        return price_lookup.get(row["product"], 0)

    pipeline["resolved_close_date"] = pipeline.apply(resolve_close_date, axis=1)
    pipeline["resolved_amount"] = pipeline.apply(resolve_amount, axis=1)
    pipeline["resolved_stage"] = pipeline["deal_stage"].map(STAGE_MAP)

    out = pd.DataFrame({
        "Opportunity Name": pipeline["account"] + " - " + pipeline["product"],
        "Account Name": pipeline["account"],
        "Amount": pipeline["resolved_amount"].round(2),
        "Close Date": pipeline["resolved_close_date"].dt.strftime("%Y-%m-%d"),
        "Stage": pipeline["resolved_stage"],
        "Product": pipeline["product"],
        "Sales Agent": pipeline["sales_agent"],
        "Opportunity_ID__c": pipeline["opportunity_id"],  # keep source ID for reconciliation
    })
    return out, pipeline


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    accounts_out = build_accounts_import()
    accounts_path = OUT_DIR / "sfdc_accounts_import.csv"
    accounts_out.to_csv(accounts_path, index=False)
    print(f"Wrote {len(accounts_out)} accounts to {accounts_path}")

    opps_out, pipeline_full = build_opportunities_import()
    opps_path = OUT_DIR / "sfdc_opportunities_import.csv"
    opps_out.to_csv(opps_path, index=False)
    print(f"Wrote {len(opps_out)} opportunities to {opps_path}")

    print("\n--- Reconciliation check ---")
    print(f"Source sales_pipeline.csv row count: {len(pipeline_full)}")
    print(f"Opportunities import row count:      {len(opps_out)}")
    assert len(pipeline_full) == len(opps_out), "Row count mismatch! Investigate before importing."
    print("Row counts match. Safe to import.")

    print("\n--- Stage distribution in import file ---")
    print(opps_out["Stage"].value_counts())

    print("\n--- Placeholder close dates assigned ---")
    placeholder_count = pipeline_full["close_date"].isna().sum()
    print(f"{placeholder_count} rows received a placeholder Close Date (originally null)")

    print("\n--- Estimated amounts assigned (from product sales_price) ---")
    estimated_count = pipeline_full["close_value"].isna().sum()
    print(f"{estimated_count} rows received an estimated Amount (originally null close_value)")


if __name__ == "__main__":
    main()
