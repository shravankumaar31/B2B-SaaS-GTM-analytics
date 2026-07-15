"""
merge_account_ids.py

Merges the real Salesforce Account IDs (exported via Data Loader) into
the Opportunities import file, replacing the plain-text "Account Name"
column with a proper "AccountId" column. Data Loader's Insert action
needs the actual 18-character Salesforce ID to link each Opportunity to
its Account -- it does not resolve names automatically the way the
Data Import Wizard did for Accounts.

Inputs:
    ~/Desktop/accounts_export.csv                          (from Data Loader Export)
    data/processed/salesforce/sfdc_opportunities_import.csv (from generate_salesforce_import.py)

Output:
    data/processed/salesforce/sfdc_opportunities_import_with_ids.csv
"""

import pandas as pd
from pathlib import Path

ACCOUNTS_EXPORT = Path.home() / "Desktop" / "accounts_export.csv"
OPPS_INPUT = Path("data/processed/salesforce/sfdc_opportunities_import.csv")
OPPS_OUTPUT = Path("data/processed/salesforce/sfdc_opportunities_import_with_ids.csv")


def main():
    if not ACCOUNTS_EXPORT.exists():
        raise FileNotFoundError(
            f"Could not find {ACCOUNTS_EXPORT}. "
            f"Check the exact filename Data Loader saved on your Desktop."
        )
    if not OPPS_INPUT.exists():
        raise FileNotFoundError(
            f"Could not find {OPPS_INPUT}. Run generate_salesforce_import.py first."
        )

    accounts = pd.read_csv(ACCOUNTS_EXPORT)
    opps = pd.read_csv(OPPS_INPUT)

    print(f"Accounts export: {len(accounts)} rows")
    print(f"Opportunities import: {len(opps)} rows")

    # Merge on account name. Left join so we can see anything that
    # fails to match (which would indicate a name mismatch worth
    # investigating rather than silently dropping rows).
    merged = opps.merge(
        accounts,
        left_on="Account Name",
        right_on="Name",
        how="left",
        indicator=True,
    )

    unmatched = merged[merged["_merge"] == "left_only"]
    matched = merged[merged["_merge"] == "both"]

    print(f"\nMatched:   {len(matched)}")
    print(f"Unmatched: {len(unmatched)}")

    if len(unmatched) > 0:
        print("\n--- WARNING: unmatched Account Names (sample) ---")
        print(unmatched["Account Name"].drop_duplicates().head(10).to_string(index=False))
        print(
            "\nThese rows will be DROPPED from the output. Investigate before "
            "proceeding if this count is unexpectedly high -- it likely means "
            "an account name doesn't exactly match between the two files "
            "(extra whitespace, punctuation, or a typo)."
        )

    # Build final output: drop the text Account Name / Name columns,
    # keep the real Salesforce Id renamed to AccountId.
    final = matched.drop(columns=["Account Name", "Name", "_merge"])
    final = final.rename(columns={"Id": "AccountId"})

    # Reorder so AccountId sits near the front, matching typical Data
    # Loader mapping conventions (cosmetic, but easier to review).
    cols = ["Opportunity Name", "AccountId"] + [
        c for c in final.columns if c not in ("Opportunity Name", "AccountId")
    ]
    final = final[cols]

    final.to_csv(OPPS_OUTPUT, index=False)
    print(f"\nWrote {len(final)} rows to {OPPS_OUTPUT}")
    print("This file is ready for Data Loader's Insert action on the Opportunity object.")


if __name__ == "__main__":
    main()
