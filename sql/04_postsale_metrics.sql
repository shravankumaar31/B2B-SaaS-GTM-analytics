-- ============================================================
-- 04_postsale_metrics.sql
-- Post-sale / subscription metrics against raw.subscriptions.
-- Each section is standalone -- run one block at a time.
--
-- Cross-check: generate_postsale.py's own console output already
-- gave us the answer key for the headline metrics (section 1 and
-- 2 below). If your SQL results don't match these, something is
-- wrong -- these aren't estimates, they're the exact expected
-- values from the same underlying data:
--   Total starting ARR:  $10,005,534.00
--   Total renewal ARR:   $9,332,402.21
--   GRR:  89.4%
--   NRR:  93.3%
--   Logo churn rate: 9.1%
-- ============================================================


-- ------------------------------------------------------------
-- 1. Gross Revenue Retention (GRR) and Net Revenue Retention (NRR)
--
-- GRR excludes expansion -- a customer that expands can only ever
-- contribute 100% of their starting ARR toward GRR, never more.
-- LEAST(renewal_arr, starting_arr) caps each row at its starting
-- value before summing, which is what "excluding expansion" means
-- in practice. NRR uses the uncapped renewal_arr, so expansion
-- revenue pulls the ratio above 100% when it's strong enough to
-- outweigh churn and contraction.
-- ------------------------------------------------------------
SELECT
    SUM(starting_arr) AS total_starting_arr,
    SUM(renewal_arr) AS total_renewal_arr,
    ROUND(100.0 * SUM(LEAST(renewal_arr, starting_arr)) / SUM(starting_arr), 1) AS grr_pct,
    ROUND(100.0 * SUM(renewal_arr) / SUM(starting_arr), 1) AS nrr_pct
FROM raw.subscriptions;


-- ------------------------------------------------------------
-- 2. Logo churn rate
-- Percentage of subscriptions (accounts up for renewal) that
-- churned entirely (renewal_arr = 0).
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') AS churned_count,
    COUNT(*) AS total_subscriptions,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') / COUNT(*),
        1
    ) AS logo_churn_pct
FROM raw.subscriptions;


-- ------------------------------------------------------------
-- 3. Expansion rate and expansion ARR by product
-- Expansion rate = expanded accounts / all renewed accounts
-- (renewed = anything that didn't churn -- flat, expanded, or
-- contracted all count as "renewed" in the traditional sense).
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE renewal_outcome = 'Expansion') AS expanded_count,
    COUNT(*) FILTER (WHERE renewal_outcome != 'Churned') AS renewed_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Expansion')
        / NULLIF(COUNT(*) FILTER (WHERE renewal_outcome != 'Churned'), 0),
        1
    ) AS expansion_rate_pct
FROM raw.subscriptions;

-- Expansion ARR generated, by product (the incremental ARR above
-- each account's starting value, summed across only the accounts
-- that expanded)
SELECT
    product,
    COUNT(*) AS expanded_accounts,
    SUM(renewal_arr - starting_arr) AS expansion_arr_generated
FROM raw.subscriptions
WHERE renewal_outcome = 'Expansion'
GROUP BY product
ORDER BY expansion_arr_generated DESC;


-- ------------------------------------------------------------
-- 4a. Churn signal: churn rate by sector (via accounts join)
-- ------------------------------------------------------------
SELECT
    a.sector,
    COUNT(*) FILTER (WHERE s.renewal_outcome = 'Churned') AS churned,
    COUNT(*) AS total,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.renewal_outcome = 'Churned') / COUNT(*),
        1
    ) AS churn_rate_pct
FROM raw.subscriptions s
JOIN raw.accounts a ON s.account = a.account
GROUP BY a.sector
ORDER BY churn_rate_pct DESC;


-- ------------------------------------------------------------
-- 4b. Churn signal: churn rate by deal size quartile
-- NTILE(4) splits subscriptions into 4 equal-sized buckets by
-- starting_arr, from smallest (quartile 1) to largest (quartile
-- 4). This answers: "do small deals churn more than large ones?"
-- -- a genuinely interesting question for a renewals/CS team.
-- ------------------------------------------------------------
WITH sized AS (
    SELECT
        subscription_id,
        starting_arr,
        renewal_outcome,
        NTILE(4) OVER (ORDER BY starting_arr) AS size_quartile
    FROM raw.subscriptions
)
SELECT
    size_quartile,
    MIN(starting_arr) AS min_arr_in_quartile,
    MAX(starting_arr) AS max_arr_in_quartile,
    COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') AS churned,
    COUNT(*) AS total,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') / COUNT(*),
        1
    ) AS churn_rate_pct
FROM sized
GROUP BY size_quartile
ORDER BY size_quartile;


-- ------------------------------------------------------------
-- 4c. Churn signal: churn rate by the sales agent who sold the
-- original deal -- a genuinely sensitive but important question:
-- do some reps' deals churn more than others', even if their win
-- rate looks fine on paper? (Top 15 by subscription volume, to
-- keep the result readable.)
-- ------------------------------------------------------------
SELECT
    sales_agent,
    COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') AS churned,
    COUNT(*) AS total_subscriptions,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') / COUNT(*),
        1
    ) AS churn_rate_pct
FROM raw.subscriptions
GROUP BY sales_agent
ORDER BY total_subscriptions DESC
LIMIT 15;
