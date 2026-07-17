-- ============================================================
-- 03_presale_metrics.sql
-- Core pre-sale pipeline metrics against the raw schema.
-- Each section is a standalone query -- run them one at a time
-- in pgAdmin's Query Tool (highlight the block, then execute).
-- ============================================================


-- ------------------------------------------------------------
-- 1a. Win rate: overall
-- Win rate = Won / (Won + Lost). Open deals (Prospecting,
-- Negotiation/Review) are excluded from the denominator since
-- they haven't reached a final outcome yet.
-- ------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE deal_stage = 'Won') AS won,
    COUNT(*) FILTER (WHERE deal_stage = 'Lost') AS lost,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won', 'Lost')), 0),
        1
    ) AS win_rate_pct
FROM raw.sales_pipeline;


-- ------------------------------------------------------------
-- 1b. Win rate by product
-- ------------------------------------------------------------
SELECT
    product,
    COUNT(*) FILTER (WHERE deal_stage = 'Won') AS won,
    COUNT(*) FILTER (WHERE deal_stage = 'Lost') AS lost,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won', 'Lost')), 0),
        1
    ) AS win_rate_pct
FROM raw.sales_pipeline
GROUP BY product
ORDER BY win_rate_pct DESC;


-- ------------------------------------------------------------
-- 1c. Win rate by sales agent
-- ------------------------------------------------------------
SELECT
    sales_agent,
    COUNT(*) FILTER (WHERE deal_stage = 'Won') AS won,
    COUNT(*) FILTER (WHERE deal_stage = 'Lost') AS lost,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won', 'Lost')), 0),
        1
    ) AS win_rate_pct
FROM raw.sales_pipeline
GROUP BY sales_agent
ORDER BY win_rate_pct DESC;


-- ------------------------------------------------------------
-- 1d. Win rate by manager (requires joining to sales_teams to
-- go from agent -> manager)
-- ------------------------------------------------------------
SELECT
    st.manager,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Lost') AS lost,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won', 'Lost')), 0),
        1
    ) AS win_rate_pct
FROM raw.sales_pipeline sp
JOIN raw.sales_teams st ON sp.sales_agent = st.sales_agent
GROUP BY st.manager
ORDER BY win_rate_pct DESC;


-- ------------------------------------------------------------
-- 1e. Win rate by regional office
-- ------------------------------------------------------------
SELECT
    st.regional_office,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Lost') AS lost,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won', 'Lost')), 0),
        1
    ) AS win_rate_pct
FROM raw.sales_pipeline sp
JOIN raw.sales_teams st ON sp.sales_agent = st.sales_agent
GROUP BY st.regional_office
ORDER BY win_rate_pct DESC;


-- ------------------------------------------------------------
-- 2. Average sales cycle (close_date - engage_date), in days,
-- for Won deals only -- by product and by agent
-- ------------------------------------------------------------
SELECT
    product,
    ROUND(AVG(close_date - engage_date), 1) AS avg_cycle_days,
    COUNT(*) AS won_deals
FROM raw.sales_pipeline
WHERE deal_stage = 'Won'
GROUP BY product
ORDER BY avg_cycle_days;

SELECT
    sales_agent,
    ROUND(AVG(close_date - engage_date), 1) AS avg_cycle_days,
    COUNT(*) AS won_deals
FROM raw.sales_pipeline
WHERE deal_stage = 'Won'
GROUP BY sales_agent
ORDER BY avg_cycle_days;


-- ------------------------------------------------------------
-- 3. Pipeline velocity
-- Formula: (open opportunities x win rate x avg deal size) / avg sales cycle days
-- Built as a CTE stack so every input is visible and auditable.
-- ------------------------------------------------------------
WITH win_rate AS (
    SELECT
        COUNT(*) FILTER (WHERE deal_stage = 'Won')::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE deal_stage IN ('Won', 'Lost')), 0) AS rate
    FROM raw.sales_pipeline
),
avg_deal_size AS (
    SELECT AVG(close_value) AS avg_value
    FROM raw.sales_pipeline
    WHERE deal_stage = 'Won'
),
avg_cycle AS (
    SELECT AVG(close_date - engage_date) AS avg_days
    FROM raw.sales_pipeline
    WHERE deal_stage = 'Won'
),
open_pipeline AS (
    SELECT COUNT(*) AS open_count
    FROM raw.sales_pipeline
    WHERE deal_stage IN ('Prospecting', 'Engaging')
)
SELECT
    op.open_count,
    ROUND(wr.rate, 4) AS win_rate,
    ROUND(ads.avg_value, 2) AS avg_deal_size,
    ROUND(ac.avg_days, 1) AS avg_cycle_days,
    ROUND(
        (op.open_count * wr.rate * ads.avg_value) / NULLIF(ac.avg_days, 0),
        2
    ) AS pipeline_velocity_per_day
FROM open_pipeline op, win_rate wr, avg_deal_size ads, avg_cycle ac;


-- ------------------------------------------------------------
-- 4. Stage distribution snapshot (not a true cohort funnel)
--
-- IMPORTANT MODELING NOTE: this dataset records only each deal's
-- current/final stage, not a history of stage transitions over
-- time. A true "funnel conversion rate" would require tracking a
-- cohort of deals as they move stage-to-stage (e.g. "of the
-- deals that entered Prospecting in January, how many reached
-- Engaging by February"). What follows is a snapshot comparison
-- of current stage populations, which is still useful, but is a
-- different metric and should not be described as a cohort
-- conversion rate.
--
-- Won and Lost are NOT sequential stages -- they are two
-- alternate terminal outcomes that both branch off of Engaging.
-- Comparing Won directly to Lost via LAG() (as an earlier version
-- of this query did) is not a meaningful relationship, and with
-- both sharing the same sort position, the window function's
-- "previous row" was undefined between them. Fixed here by
-- giving every stage a distinct order, and by presenting the
-- Engaging -> Won and Engaging -> Lost branch rates separately
-- instead of forcing a single linear chain across all 4 stages.
-- ------------------------------------------------------------
WITH funnel AS (
    SELECT
        deal_stage,
        CASE deal_stage
            WHEN 'Prospecting' THEN 1
            WHEN 'Engaging' THEN 2
            WHEN 'Won' THEN 3
            WHEN 'Lost' THEN 4
        END AS stage_order,
        COUNT(*) AS deal_count,
        SUM(close_value) AS total_value
    FROM raw.sales_pipeline
    GROUP BY deal_stage
)
SELECT
    deal_stage,
    deal_count,
    total_value,
    ROUND(
        100.0 * deal_count / LAG(deal_count) OVER (ORDER BY stage_order),
        1
    ) AS pct_of_previous_stage
FROM funnel
ORDER BY stage_order;

-- Branch conversion rates from Engaging specifically -- the
-- business-meaningful version of "what happens after Engaging"
SELECT
    (SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Engaging') AS engaging_count,
    (SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Won') AS won_count,
    (SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Lost') AS lost_count,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Won')
        / NULLIF((SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Engaging'), 0),
        1
    ) AS won_pct_of_engaging,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Lost')
        / NULLIF((SELECT COUNT(*) FROM raw.sales_pipeline WHERE deal_stage = 'Engaging'), 0),
        1
    ) AS lost_pct_of_engaging;


-- ------------------------------------------------------------
-- 5. Average deal size by product and by sector (via accounts)
-- ------------------------------------------------------------
SELECT
    sp.product,
    ROUND(AVG(sp.close_value), 2) AS avg_deal_size,
    COUNT(*) AS won_deals
FROM raw.sales_pipeline sp
WHERE sp.deal_stage = 'Won'
GROUP BY sp.product
ORDER BY avg_deal_size DESC;

SELECT
    a.sector,
    ROUND(AVG(sp.close_value), 2) AS avg_deal_size,
    COUNT(*) AS won_deals
FROM raw.sales_pipeline sp
JOIN raw.accounts a ON sp.account = a.account
WHERE sp.deal_stage = 'Won'
GROUP BY a.sector
ORDER BY avg_deal_size DESC;


-- ------------------------------------------------------------
-- 6. Monthly bookings trend (Won deals, by close month)
-- ------------------------------------------------------------
SELECT
    DATE_TRUNC('month', close_date)::DATE AS month,
    COUNT(*) AS deals_won,
    SUM(close_value) AS total_bookings
FROM raw.sales_pipeline
WHERE deal_stage = 'Won'
GROUP BY DATE_TRUNC('month', close_date)
ORDER BY month;


-- ------------------------------------------------------------
-- 7. AE productivity: bookings per agent per quarter, with a
-- rank so you can see who's #1 each quarter at a glance.
-- ------------------------------------------------------------
WITH quarterly_bookings AS (
    SELECT
        sales_agent,
        DATE_TRUNC('quarter', close_date)::DATE AS quarter,
        COUNT(*) AS deals_closed,
        SUM(close_value) AS bookings
    FROM raw.sales_pipeline
    WHERE deal_stage = 'Won'
    GROUP BY sales_agent, DATE_TRUNC('quarter', close_date)
)
SELECT
    quarter,
    sales_agent,
    deals_closed,
    bookings,
    RANK() OVER (PARTITION BY quarter ORDER BY bookings DESC) AS rank_in_quarter
FROM quarterly_bookings
ORDER BY quarter, rank_in_quarter;


-- ------------------------------------------------------------
-- 8. Forecast category snapshot with weighted pipeline
-- Mirrors the Salesforce forecast category mapping we set up in
-- Phase 2: Prospecting -> Pipeline (10% weight), Engaging /
-- Negotiation-Review -> Commit (60% weight). Weighted pipeline
-- estimates realistic expected revenue from open deals.
--
-- IMPORTANT: close_value is NULL for 100% of Prospecting and
-- Engaging rows (confirmed in 02_validation.sql query 5) -- these
-- are open deals with no negotiated value yet. Rather than sum a
-- column of nulls, this uses each product's list sales_price as
-- an estimated deal value via COALESCE, the same approach used
-- in generate_salesforce_import.py (see docs/decisions.md #4).
-- ------------------------------------------------------------
SELECT
    sp.deal_stage,
    CASE sp.deal_stage
        WHEN 'Prospecting' THEN 'Pipeline'
        WHEN 'Engaging' THEN 'Commit'
    END AS forecast_category,
    CASE sp.deal_stage
        WHEN 'Prospecting' THEN 0.10
        WHEN 'Engaging' THEN 0.60
    END AS category_weight,
    COUNT(*) AS open_deal_count,
    SUM(COALESCE(sp.close_value, p.sales_price)) AS estimated_value,
    ROUND(
        SUM(COALESCE(sp.close_value, p.sales_price)) * CASE sp.deal_stage
            WHEN 'Prospecting' THEN 0.10
            WHEN 'Engaging' THEN 0.60
        END,
        2
    ) AS weighted_pipeline
FROM raw.sales_pipeline sp
-- normalize "GTXPro" -> "GTX Pro" in the join so those rows aren't
-- silently dropped by the match (see docs/decisions.md #2)
JOIN raw.products p
    ON CASE WHEN sp.product = 'GTXPro' THEN 'GTX Pro' ELSE sp.product END = p.product
WHERE sp.deal_stage IN ('Prospecting', 'Engaging')
GROUP BY sp.deal_stage
ORDER BY sp.deal_stage;
