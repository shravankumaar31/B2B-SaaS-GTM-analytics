# Decisions Log

A running log of judgment calls made while building this project, and the
reasoning behind each.

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

## 6. Migrated from Salesforce Starter Suite trial to Developer Edition

**Finding:** The Salesforce org used for Phase 2 turned out to be a
**Starter Suite trial** (30-day trial, simplified UI, no native Reports
tab in the main nav, restrictive default Stage/Forecast Category
picklist configuration) rather than the free, permanent **Developer
Edition** the project plan called for. This wasn't obvious until well
into report-building, when the trial's default Stage picklist and
inactive-value forecast mapping (see #5 above) caused confusing report
results.

**Decision:** Signed up for a proper Salesforce Developer Edition org
and rebuilt the CRM layer there: recreated the two custom fields
(`Product__c`, `Sales_Agent__c`), re-imported the same 85 Accounts via
the Data Import Wizard, and re-imported Opportunities using
**dataloader.io** (web-based) instead of the desktop Data Loader used
previously.

**Why dataloader.io instead of desktop Data Loader again:** the desktop
app required a Java runtime install and had a persistent window
rendering bug on this machine (its SWT-based window opened off-screen
and had to be forced back into view via AppleScript). dataloader.io also
has a genuinely simpler workflow for this use case: its "Lookup via"
field mapping resolves an `Account Name` text column directly to the
correct `AccountId` for the *current* org at import time, which meant
we could reuse the original `sfdc_opportunities_import.csv` (plain text
Account Name) directly, with no need to first export Account IDs and
merge them in a separate script.

**File impact:** `sfdc_opportunities_import_with_ids.csv` and its
generator `merge_account_ids.py` were built for the desktop Data
Loader's ID-based Insert requirement. That output file is now stale
(the Account IDs it contains belong to the retired Starter Suite org)
and was removed from the repo. `merge_account_ids.py` itself is kept as
reference code, since the ID-merge approach is still valid and worth
showing, but it is not part of the current import pipeline.

**Result:** All Salesforce-side artifacts (Accounts, Opportunities,
custom fields, reports, dashboard) now live in a permanent Developer
Edition org rather than an expiring trial.

---

## 7. Reverted from Developer Edition back to Starter Suite (storage cap)

**Finding:** Immediately after migrating to Developer Edition (see #6),
the Opportunities Insert via dataloader.io failed partway through with
3,175 errors, all reading `"ERROR: storage limit exceeded"`. Checking
Setup → Storage Usage revealed the org's Data Storage limit is a fixed
**5.0 MB**, already at 174% (8.7 MB) after only 4,231 partial
Opportunity records. Salesforce charges a flat ~2KB of storage per
record regardless of field count -- confirmed by the math (8.3 MB /
4,231 Opportunities ≈ 1.96 KB/record; 196 KB / 98 Accounts ≈ 2 KB/record).
At that rate, a 5MB free Developer Edition org can hold roughly
2,300-2,400 Opportunities maximum -- nowhere near the full 7,375-row
dataset. This is a hard, well-documented platform ceiling on the free
tier, not a configuration mistake.

**Decision:** Reverted to the original Salesforce Starter Suite trial
org rather than permanently scoping the CRM layer down to a ~2,000-row
sample on Developer Edition. Starter Suite had already successfully
held the complete 7,375-row Opportunities import (proven in the
original Phase 2 pass) with zero storage errors, and already had all 4
reports built plus a dashboard in progress.

**Reasoning:** The tradeoff came down to Starter Suite's 30-day trial
window versus Developer Edition's permanent-but-tiny storage cap. For a
portfolio project, what an interviewer actually references is the
GitHub repo, documentation, and screenshots -- not live login access to
a Salesforce org, which isn't something you'd share credentials for
anyway. Rebuilding all 4 reports and the dashboard a second time on a
necessarily incomplete, artificially-sampled dataset was a worse
tradeoff than simply capturing screenshots from the already-complete
Starter Suite build before its trial period ends.

**Result:** Returned to the Starter Suite org with the full,
already-validated 7,375-row Opportunities dataset and all 4 reports
intact. Screenshots and documentation captured throughout this project
remain valid regardless of the trial's eventual expiration.

**Note on `sfdc_opportunities_import_with_ids.csv`:** this file was
removed in decision #6 because its Account IDs belonged to the
Developer Edition org and were stale there. Since this reversal returns
to the original Starter Suite org -- the same org those IDs were
exported from -- the file is valid again and was restored to the repo.

---

## 8. SQL validation layer independently confirms all prior findings

**What was done:** built `sql/02_validation.sql`, a set of 9 queries
against the raw Postgres schema covering: row count reconciliation,
orphan-account detection (both directions -- blank accounts, and
accounts that don't match between tables), the GTXPro/GTX Pro product
name mismatch, a full null audit by deal stage, duplicate checks on
`opportunity_id` and on account names (case-insensitive), and a
referential integrity check tying `subscriptions` back to genuine Won
opportunities.

**Result:** every query returned exactly the expected result --
including the two known data quality issues (1,425 orphan pipeline
rows, the GTXPro naming split), which were independently reproduced via
SQL rather than just carried over from the earlier Python/Salesforce
work. All duplicate, referential integrity, and near-duplicate checks
came back clean (0 rows). This confirms the raw Postgres layer is a
faithful, fully reconciled copy of the source data, and that the two
known issues are the only data quality problems in the dataset -- not
symptoms of a broader problem that only Python or Salesforce happened
to catch.

---

## 9. Stage funnel tie-break bug, and a conversion-rate metric this dataset can't support

**Finding 1 (bug):** the first version of the stage conversion funnel
query gave Won and Lost the same `stage_order` value (both = 3), since
they're both "final" stages. This created a tie inside the `LAG()`
window function's `ORDER BY`, and Postgres does not guarantee row order
for ties without an explicit tiebreaker -- so the "percent of previous
stage" computed for Won and Lost was based on an arbitrary, undefined
ordering between them, not a meaningful comparison. Fixed by giving
every stage a distinct `stage_order` (1-4) so the window function's
ordering is fully deterministic.

**Finding 2 (data limitation, not a bug):** even after fixing the tie,
attempting to compute "% of Engaging deals that became Won" produced
266.7% -- a mathematically impossible conversion rate, since a rate can
never exceed 100%. Root cause: `sales_pipeline` records only each
deal's current/final stage, not a history of stage transitions over
time. Won and Lost are cumulative totals across the dataset's entire
history; Engaging is a point-in-time snapshot of deals currently
sitting in that stage. Dividing one by the other compares two
fundamentally different kinds of counts and produces a number that
looks like a percentage but isn't one.

**Decision:** removed the Engaging-to-Won/Lost "conversion rate" query
entirely rather than report a number that looks precise but is not
actually valid. Kept the overall win rate (Won / (Won + Lost), both
cumulative totals -- a genuinely apples-to-apples comparison) as the
one defensible closed-outcome metric this dataset supports.

**Why this matters:** this is a distinction worth being able to explain
clearly -- a true stage-to-stage funnel conversion rate requires
tracking individual deals as they move through stages over time (cohort
analysis), which this dataset's structure doesn't provide. Recognizing
when a data structure can't support a metric, rather than forcing a
calculation that produces a technically-computed-but-meaningless
number, is exactly the kind of judgment call that separates a junior
analyst running queries from a senior one interpreting them correctly.

---
