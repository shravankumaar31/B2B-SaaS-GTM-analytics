-- ============================================================
-- 02_validation.sql
-- Data validation queries against the raw schema.
--
-- Purpose: reconcile row counts, surface data quality issues,
-- and confirm (via SQL, independently of the earlier Python/
-- Salesforce work) the same findings already documented in
-- docs/decisions.md -- specifically the 1,425 orphan pipeline
-- rows with no account, and the "GTXPro" vs "GTX Pro" product
-- name inconsistency. Run each block separately and compare
-- results against the expected values noted in comments.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Row counts per table (sanity check against source CSVs)
-- Expected: accounts 85, products 7, sales_teams 35,
--           sales_pipeline 8800, subscriptions 4238
-- ------------------------------------------------------------
SELECT 'raw.accounts' AS table_name, COUNT(*) AS row_count FROM raw.accounts
UNION ALL
SELECT 'raw.products', COUNT(*) FROM raw.products
UNION ALL
SELECT 'raw.sales_teams', COUNT(*) FROM raw.sales_teams
UNION ALL
SELECT 'raw.sales_pipeline', COUNT(*) FROM raw.sales_pipeline
UNION ALL
SELECT 'raw.subscriptions', COUNT(*) FROM raw.subscriptions
ORDER BY table_name;


-- ------------------------------------------------------------
-- 2. Orphan check: pipeline rows with no matching account
-- Expected: 1,425 rows -- see docs/decisions.md #1. All Won
-- and Lost deals should have an account; the gap should be
-- fully isolated to Engaging (1,088) and Prospecting (337).
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS orphan_opportunities,
    deal_stage
FROM raw.sales_pipeline
WHERE account IS NULL
GROUP BY deal_stage
ORDER BY orphan_opportunities DESC;

-- Confirm zero orphans among Won/Lost specifically (sanity check
-- on the claim above -- this should return 0 rows)
SELECT *
FROM raw.sales_pipeline
WHERE account IS NULL
  AND deal_stage IN ('Won', 'Lost');


-- ------------------------------------------------------------
-- 3. Orphan check the other direction: accounts referenced in
-- pipeline that don't exist in the accounts table at all
-- (distinct from the NULL-account case above -- this checks for
-- a typo'd or missing account name rather than a blank one)
-- Expected: 0 rows, since sales_pipeline.account values were
-- generated from the same source as accounts.account
-- ------------------------------------------------------------
SELECT DISTINCT sp.account
FROM raw.sales_pipeline sp
LEFT JOIN raw.accounts a ON sp.account = a.account
WHERE sp.account IS NOT NULL
  AND a.account IS NULL;


-- ------------------------------------------------------------
-- 4. Product name inconsistency check
-- Expected: "GTXPro" appears ~1,480 times; "GTX Pro" (the
-- canonical name matching raw.products) does not appear in
-- sales_pipeline at all. See docs/decisions.md #2.
-- ------------------------------------------------------------
SELECT
    sp.product AS pipeline_product_name,
    COUNT(*) AS row_count,
    CASE WHEN p.product IS NULL THEN 'NOT IN products table' ELSE 'matches products table' END AS match_status
FROM raw.sales_pipeline sp
LEFT JOIN raw.products p ON sp.product = p.product
GROUP BY sp.product, p.product
ORDER BY row_count DESC;


-- ------------------------------------------------------------
-- 5. Null audit: engage_date / close_date / close_value by stage
-- Expected pattern: Prospecting missing all three (500 rows);
-- Engaging missing close_date/close_value but has engage_date
-- (1,589 rows); Won/Lost have zero nulls in any of these fields.
-- ------------------------------------------------------------
SELECT
    deal_stage,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE engage_date IS NULL) AS null_engage_date,
    COUNT(*) FILTER (WHERE close_date IS NULL) AS null_close_date,
    COUNT(*) FILTER (WHERE close_value IS NULL) AS null_close_value,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE close_date IS NULL) / NULLIF(COUNT(*), 0),
        1
    ) AS pct_null_close_date
FROM raw.sales_pipeline
GROUP BY deal_stage
ORDER BY deal_stage;


-- ------------------------------------------------------------
-- 6. Duplicate check on opportunity_id
-- Expected: 0 rows (opportunity_id is the primary key, so this
-- should be structurally impossible -- included anyway as a
-- defensive check, and as a reusable pattern for tables without
-- a primary key constraint)
-- ------------------------------------------------------------
SELECT
    opportunity_id,
    COUNT(*) AS occurrences
FROM raw.sales_pipeline
GROUP BY opportunity_id
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- 7. Duplicate check on account names (case-insensitive)
-- Expected: 0 rows. A soft check for near-duplicate accounts
-- that a straightforward exact-match join would miss.
-- ------------------------------------------------------------
SELECT
    LOWER(TRIM(account)) AS normalized_name,
    COUNT(*) AS occurrences,
    STRING_AGG(account, ', ') AS variants
FROM raw.accounts
GROUP BY LOWER(TRIM(account))
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- 8. Known text typos (confirms the two fixes documented in
-- docs/decisions.md #3 are needed at the SQL layer too, since
-- raw preserves the uncorrected source values)
-- ------------------------------------------------------------
SELECT sector, COUNT(*)
FROM raw.accounts
WHERE sector ILIKE 'technolg%'
GROUP BY sector;

SELECT office_location, COUNT(*)
FROM raw.accounts
WHERE office_location ILIKE 'philipines'
GROUP BY office_location;


-- ------------------------------------------------------------
-- 9. Subscriptions table sanity check: every subscription should
-- trace back to a real, Won opportunity. Expected: 0 rows.
-- ------------------------------------------------------------
SELECT s.subscription_id, s.opportunity_id
FROM raw.subscriptions s
LEFT JOIN raw.sales_pipeline sp
    ON s.opportunity_id = sp.opportunity_id
    AND sp.deal_stage = 'Won'
WHERE sp.opportunity_id IS NULL;
