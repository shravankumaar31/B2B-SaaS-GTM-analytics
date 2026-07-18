-- ============================================================
-- 05_analytics_views.sql
-- Builds the analytics schema: cleaned, reusable views sitting
-- on top of the raw schema. This is the "semantic layer" -- the
-- point of this separation is that Tableau (and anyone else
-- querying this database) connects to these views, not the raw
-- tables directly, so cleaning logic lives in exactly one place
-- rather than being copy-pasted into every downstream query or
-- every Tableau calculated field.
--
-- Cleaning applied here (see docs/decisions.md for the full
-- reasoning behind each):
--   - product name: "GTXPro" -> "GTX Pro"
--   - accounts.sector: "technolgy" -> "technology"
--   - accounts.office_location: "Philipines" -> "Philippines"
--   - open deals (Prospecting/Engaging) get an estimated value
--     from the product's list price, since close_value is NULL
--     for all open deals in the raw source data
-- ============================================================


-- ------------------------------------------------------------
-- analytics.vw_pipeline_summary
-- One row per opportunity, cleaned and enriched with agent/team
-- and account/sector context. This is the main fact table for
-- any pipeline, funnel, or bookings visualization in Tableau.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.vw_pipeline_summary AS
SELECT
    sp.opportunity_id,
    sp.account,
    CASE WHEN sp.product = 'GTXPro' THEN 'GTX Pro' ELSE sp.product END AS product,
    sp.deal_stage,
    CASE sp.deal_stage
        WHEN 'Prospecting' THEN 'Pipeline'
        WHEN 'Engaging' THEN 'Commit'
        WHEN 'Won' THEN 'Closed'
        WHEN 'Lost' THEN 'Omitted'
    END AS forecast_category,
    sp.engage_date,
    sp.close_date,
    sp.close_value,
    COALESCE(sp.close_value, p.sales_price) AS estimated_value,
    (sp.close_date - sp.engage_date) AS sales_cycle_days,
    sp.sales_agent,
    st.manager,
    st.regional_office,
    CASE a.sector WHEN 'technolgy' THEN 'technology' ELSE a.sector END AS sector,
    CASE a.office_location WHEN 'Philipines' THEN 'Philippines' ELSE a.office_location END AS office_location,
    a.revenue AS account_revenue_millions,
    a.employees AS account_employees
FROM raw.sales_pipeline sp
LEFT JOIN raw.products p
    ON CASE WHEN sp.product = 'GTXPro' THEN 'GTX Pro' ELSE sp.product END = p.product
LEFT JOIN raw.sales_teams st ON sp.sales_agent = st.sales_agent
LEFT JOIN raw.accounts a ON sp.account = a.account;


-- ------------------------------------------------------------
-- analytics.vw_agent_scorecard
-- One row per sales agent: win rate, cycle time, bookings, and a
-- rank so Tableau can build a leaderboard without recalculating
-- anything -- matches Phase 2's Salesforce "Win Rate by Sales
-- Agent" report, so the SQL and CRM layers tell the same story.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.vw_agent_scorecard AS
SELECT
    sp.sales_agent,
    st.manager,
    st.regional_office,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won_deals,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Lost') AS lost_deals,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sp.deal_stage = 'Won')
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won', 'Lost')), 0),
        1
    ) AS win_rate_pct,
    ROUND(AVG(sp.close_date - sp.engage_date) FILTER (WHERE sp.deal_stage = 'Won'), 1) AS avg_cycle_days,
    SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') AS total_bookings,
    RANK() OVER (ORDER BY SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') DESC NULLS LAST) AS bookings_rank
FROM raw.sales_pipeline sp
LEFT JOIN raw.sales_teams st ON sp.sales_agent = st.sales_agent
GROUP BY sp.sales_agent, st.manager, st.regional_office;


-- ------------------------------------------------------------
-- analytics.vw_retention_summary
-- One row per product, with retention/expansion/churn metrics,
-- plus an overall total row (product = 'ALL PRODUCTS') for the
-- headline company-wide numbers in one convenient place.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.vw_retention_summary AS
SELECT
    CASE WHEN product = 'GTXPro' THEN 'GTX Pro' ELSE product END AS product,
    COUNT(*) AS total_subscriptions,
    SUM(starting_arr) AS total_starting_arr,
    SUM(renewal_arr) AS total_renewal_arr,
    ROUND(100.0 * SUM(LEAST(renewal_arr, starting_arr)) / NULLIF(SUM(starting_arr), 0), 1) AS grr_pct,
    ROUND(100.0 * SUM(renewal_arr) / NULLIF(SUM(starting_arr), 0), 1) AS nrr_pct,
    COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') AS churned_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') / COUNT(*), 1) AS logo_churn_pct,
    COUNT(*) FILTER (WHERE renewal_outcome = 'Expansion') AS expanded_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Expansion')
        / NULLIF(COUNT(*) FILTER (WHERE renewal_outcome != 'Churned'), 0),
        1
    ) AS expansion_rate_pct
FROM raw.subscriptions
GROUP BY CASE WHEN product = 'GTXPro' THEN 'GTX Pro' ELSE product END

UNION ALL

SELECT
    'ALL PRODUCTS' AS product,
    COUNT(*) AS total_subscriptions,
    SUM(starting_arr) AS total_starting_arr,
    SUM(renewal_arr) AS total_renewal_arr,
    ROUND(100.0 * SUM(LEAST(renewal_arr, starting_arr)) / NULLIF(SUM(starting_arr), 0), 1) AS grr_pct,
    ROUND(100.0 * SUM(renewal_arr) / NULLIF(SUM(starting_arr), 0), 1) AS nrr_pct,
    COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') AS churned_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Churned') / COUNT(*), 1) AS logo_churn_pct,
    COUNT(*) FILTER (WHERE renewal_outcome = 'Expansion') AS expanded_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE renewal_outcome = 'Expansion')
        / NULLIF(COUNT(*) FILTER (WHERE renewal_outcome != 'Churned'), 0),
        1
    ) AS expansion_rate_pct
FROM raw.subscriptions;


-- ------------------------------------------------------------
-- Quick verification queries -- run these after creating the
-- views above to confirm they work and match known totals.
-- ------------------------------------------------------------

-- Should return 8,800 rows (matches raw.sales_pipeline exactly,
-- since this view doesn't filter anything, only cleans/enriches)
SELECT COUNT(*) FROM analytics.vw_pipeline_summary;

-- Should show 7 distinct products, none of them "GTXPro"
SELECT DISTINCT product FROM analytics.vw_pipeline_summary ORDER BY product;

-- Should show the same GRR 89.4% / NRR 93.3% / churn 9.1% we
-- already validated, on the 'ALL PRODUCTS' row
SELECT * FROM analytics.vw_retention_summary WHERE product = 'ALL PRODUCTS';
