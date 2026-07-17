-- ============================================================
-- 01_schema.sql
-- Creates the raw and analytics schemas for the GTM Analytics
-- Postgres database, plus all raw source tables.
--
-- Design: the `raw` schema holds data exactly as it exists in
-- the source CSVs (including known typos like "technolgy" and
-- "Philipines" -- see docs/decisions.md). The `analytics` schema
-- (built in later scripts) applies the same cleaning logic used
-- in the Salesforce import, so both layers tell a consistent
-- story while raw preserves an honest source-of-truth copy.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;

-- ------------------------------------------------------------
-- raw.accounts
-- ------------------------------------------------------------
DROP TABLE IF EXISTS raw.accounts CASCADE;
CREATE TABLE raw.accounts (
    account             TEXT PRIMARY KEY,
    sector              TEXT,
    year_established    INTEGER,
    revenue             NUMERIC(12, 2),   -- in millions of USD per data dictionary
    employees           INTEGER,
    office_location     TEXT,
    subsidiary_of       TEXT
);

-- ------------------------------------------------------------
-- raw.products
-- ------------------------------------------------------------
DROP TABLE IF EXISTS raw.products CASCADE;
CREATE TABLE raw.products (
    product             TEXT PRIMARY KEY,
    series              TEXT,
    sales_price         NUMERIC(12, 2)
);

-- ------------------------------------------------------------
-- raw.sales_teams
-- ------------------------------------------------------------
DROP TABLE IF EXISTS raw.sales_teams CASCADE;
CREATE TABLE raw.sales_teams (
    sales_agent         TEXT PRIMARY KEY,
    manager             TEXT,
    regional_office     TEXT
);

-- ------------------------------------------------------------
-- raw.sales_pipeline
-- Note: account and product are intentionally NOT foreign keys
-- here -- the raw layer preserves the 1,425 rows with a null
-- account exactly as they exist in the source data, and the
-- "GTXPro" vs "GTX Pro" product name inconsistency (see
-- docs/decisions.md #1 and #2). Foreign keys are enforced in
-- the analytics layer instead, after cleaning.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS raw.sales_pipeline CASCADE;
CREATE TABLE raw.sales_pipeline (
    opportunity_id      TEXT PRIMARY KEY,
    sales_agent         TEXT,
    product             TEXT,
    account             TEXT,
    deal_stage          TEXT,
    engage_date         DATE,
    close_date          DATE,
    close_value         NUMERIC(12, 2)
);

-- ------------------------------------------------------------
-- raw.subscriptions
-- The synthesized post-sale table from generate_postsale.py
-- ------------------------------------------------------------
DROP TABLE IF EXISTS raw.subscriptions CASCADE;
CREATE TABLE raw.subscriptions (
    subscription_id     TEXT PRIMARY KEY,
    opportunity_id      TEXT,
    account             TEXT,
    product             TEXT,
    sales_agent         TEXT,
    start_date          DATE,
    renewal_date         DATE,
    starting_arr         NUMERIC(12, 2),
    renewal_outcome      TEXT,
    renewal_arr           NUMERIC(12, 2)
);

-- ------------------------------------------------------------
-- Helpful indexes for the raw layer (join/filter columns)
-- ------------------------------------------------------------
CREATE INDEX idx_raw_pipeline_account ON raw.sales_pipeline (account);
CREATE INDEX idx_raw_pipeline_product ON raw.sales_pipeline (product);
CREATE INDEX idx_raw_pipeline_agent ON raw.sales_pipeline (sales_agent);
CREATE INDEX idx_raw_pipeline_stage ON raw.sales_pipeline (deal_stage);
CREATE INDEX idx_raw_subscriptions_account ON raw.subscriptions (account);
CREATE INDEX idx_raw_subscriptions_product ON raw.subscriptions (product);
