# Decisions Log

A running log of judgment calls made while building this project, and the
reasoning behind each. Kept transparent rather than buried, since these are
exactly the kind of tradeoffs worth being able to explain in an interview.

---

## 1. Opportunities with no Account assigned (1,425 rows)

**Finding:** 1,425 of 8,800 opportunities in the raw `sales_pipeline.csv`
have a blank `account` field — 1,088 in the "Engaging" stage and 337 in
"Prospecting." Every "Won" and "Lost" deal has an account; the gap is
fully isolated to open, unresolved pipeline. Likely explanation: reps
logging early-stage activity before formally attaching an account.

**Decision:** Excluded these 1,425 rows from the Salesforce import, but
kept all 8,800 rows in the Postgres/SQL layer.

**Reasoning:** Salesforce's reporting model is built around the Account
object — pipeline-by-account views, forecast rollups, account hierarchy
reports all depend on a meaningful Account relationship. An Opportunity
with no Account would either fail import or sit as a confusing orphan
record. But these 1,425 rows are still real pipeline activity, and
dropping them from funnel/win-rate/velocity analysis would understate
actual pipeline volume. Keeping the full dataset in SQL preserves
analytical accuracy while keeping the CRM layer clean and meaningful.

**Result:** Salesforce reflects 7,375 account-attached opportunities.
SQL and all downstream pipeline metrics reflect the full 8,800.

---

## 2. Product name inconsistency: "GTXPro" vs "GTX Pro"

**Finding:** `sales_pipeline.csv` uses the value `GTXPro` (no space) for
1,480 rows. `products.csv` and the Salesforce Product picklist both use
`GTX Pro` (with a space) — and `GTX Pro` does not appear anywhere in the
raw pipeline data at all. This isn't a handful of stray typos; it's a
systematic naming difference between two source files for the same
product.

**Decision:** Normalized `GTXPro` → `GTX Pro` at the point both
`generate_postsale.py` and `generate_salesforce_import.py` first read
`sales_pipeline.csv`, so every downstream file (subscriptions table,
Salesforce import, and later the SQL/Tableau layer) is consistent.

**Reasoning:** Left unfixed, this would have caused two problems: every
one of the 1,480 rows would fail Salesforce's Product picklist
validation on import, and any product-level analysis (retention by
product, bookings by product) would incorrectly treat "GTXPro" and
"GTX Pro" as two different products, splitting what should be one
product's numbers in half.

**Result:** All product-level reporting across every layer of this
project now correctly groups under the 7 canonical product names.

---

## 5. Forecast Category mapping was broken by default (Salesforce org config)

**Finding:** After building the Forecast Category Rollup report, every
open Opportunity was grouping under "Closed" instead of Pipeline or
Commit -- clearly wrong, since none of those deals were actually closed.
Investigating Setup → Object Manager → Opportunity → Stage field
revealed the root cause: this Starter Suite trial org ships with a
default 6-stage picklist (Qualify, Meet & Present, Propose, Negotiate,
Closed Won, Closed Lost) that has nothing to do with the Maven dataset's
stage names. Our imported Opportunities use `Prospecting` and
`Negotiation/Review` -- values that existed in the org only as
**inactive** picklist entries, both hardcoded to Forecast Category =
"Closed" as an artifact of being deactivated. Salesforce's API still
accepts inactive picklist values on record insert, so the 7,375-row
Data Loader import succeeded silently with no error, masking the
problem until a report was actually built on top of it.

**Decision:** Activated `Prospecting` and `Negotiation/Review` in the
Stage picklist and assigned them correct forecast mappings:
Prospecting → Pipeline (10% probability), Negotiation/Review → Commit
(60% probability). Left the org's unused default stages (Qualify, Meet
& Present, Propose, Negotiate) untouched and inactive-irrelevant, since
zero records reference them and deactivating them further serves no
purpose.

**Reasoning:** This is a good example of a data quality issue that
doesn't surface until you build a report on top of the data -- the
import itself showed 100% success. Worth noting for anyone reviewing
this project: always validate reporting logic against a real report or
dashboard, not just import success counts.

**Result:** Forecast Category Rollup report now correctly shows 664 open
Opportunities split into Pipeline (163) and Commit (501), matching the
expected stage distribution.

---

## 3. Other typo normalizations (minor)

- `accounts.sector`: `"technolgy"` → `"technology"`
- `accounts.office_location`: `"Philipines"` → `"Philippines"`,
  `"Korea"` → `"Korea, Republic of"` (required to match Salesforce's
  State/Country picklist value; caused one failed row on first import
  attempt, resolved by adding this mapping)

---

## 4. Placeholder values for incomplete open pipeline

**Finding:** Salesforce requires every Opportunity to have a Close Date.
2,089 rows (500 Prospecting with no dates at all, 1,589 Engaging with an
engage_date but no close_date) don't have one in the source data, since
they're still open. Similarly, `close_value` is only populated for
closed deals, leaving 2,089 rows with no Amount.

**Decision:**
- Close Date: `engage_date + 90 days` where engage_date exists,
  otherwise `today + 90 days`.
- Amount: the product's list `sales_price` from `products.csv`, as an
  estimated deal value.

**Reasoning:** Both are reasonable, documented placeholders rather than
leaving required fields blank or guessing arbitrarily. The 90-day
horizon reflects a typical sales cycle assumption; using list price as
the estimated Amount for open deals is a standard sales-ops convention
when an actual negotiated value isn't yet known.
