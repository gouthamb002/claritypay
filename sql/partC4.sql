-- C4 — Scalability (Stretch)
-- 1. DROP INDEXES (To ensure we see the unindexed plan first on every run)
DROP INDEX IF EXISTS idx_customers_email;
DROP INDEX IF EXISTS idx_merchants_email;
DROP INDEX IF EXISTS idx_customers_tax_id;
DROP INDEX IF EXISTS idx_merchants_tax_id;
DROP INDEX IF EXISTS idx_pi_card;
DROP INDEX IF EXISTS idx_merchants_card;
DROP INDEX IF EXISTS idx_installments_plan_id;
DROP INDEX IF EXISTS idx_plans_customer_id;
DROP INDEX IF EXISTS idx_plans_merchant_id;
-- 2. EXPLAIN QUERY PLAN BEFORE INDEXING
-- We analyze the heavy identity linkage query (edge generation) from Part B.
EXPLAIN QUERY PLAN WITH node_identifiers AS (
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid,
        'email' AS id_type,
        email AS id_value
    FROM customers
    WHERE email IS NOT NULL
        AND email != ''
    UNION ALL
    SELECT 'merchant' AS node_type,
        merchant_id AS node_id,
        'm_' || merchant_id AS node_uid,
        'email' AS id_type,
        owner_email AS id_value
    FROM merchants
    WHERE owner_email IS NOT NULL
        AND owner_email != ''
    UNION ALL
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid,
        'tax_id' AS id_type,
        tax_id AS id_value
    FROM customers
    WHERE tax_id IS NOT NULL
        AND tax_id != ''
    UNION ALL
    SELECT 'merchant' AS node_type,
        merchant_id AS node_id,
        'm_' || merchant_id AS node_uid,
        'tax_id' AS id_type,
        owner_tax_id AS id_value
    FROM merchants
    WHERE owner_tax_id IS NOT NULL
        AND owner_tax_id != ''
),
edges AS (
    SELECT DISTINCT a.node_uid AS source_uid,
        b.node_uid AS target_uid
    FROM node_identifiers a
        JOIN node_identifiers b ON a.id_type = b.id_type
        AND a.id_value = b.id_value
    WHERE a.node_uid != b.node_uid
)
SELECT *
FROM edges;
-- 3. ADDING INDEXES
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_merchants_email ON merchants(owner_email);
CREATE INDEX idx_customers_tax_id ON customers(tax_id);
CREATE INDEX idx_merchants_tax_id ON merchants(owner_tax_id);
CREATE INDEX idx_pi_card ON payment_instruments(card_fingerprint);
CREATE INDEX idx_merchants_card ON merchants(business_card_fingerprint);
CREATE INDEX idx_installments_plan_id ON installments(plan_id, due_date);
CREATE INDEX idx_plans_customer_id ON plans(customer_id);
CREATE INDEX idx_plans_merchant_id ON plans(merchant_id);
-- 4. EXPLAIN QUERY PLAN AFTER INDEXING
EXPLAIN QUERY PLAN WITH node_identifiers AS (
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid,
        'email' AS id_type,
        email AS id_value
    FROM customers
    WHERE email IS NOT NULL
        AND email != ''
    UNION ALL
    SELECT 'merchant' AS node_type,
        merchant_id AS node_id,
        'm_' || merchant_id AS node_uid,
        'email' AS id_type,
        owner_email AS id_value
    FROM merchants
    WHERE owner_email IS NOT NULL
        AND owner_email != ''
    UNION ALL
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid,
        'tax_id' AS id_type,
        tax_id AS id_value
    FROM customers
    WHERE tax_id IS NOT NULL
        AND tax_id != ''
    UNION ALL
    SELECT 'merchant' AS node_type,
        merchant_id AS node_id,
        'm_' || merchant_id AS node_uid,
        'tax_id' AS id_type,
        owner_tax_id AS id_value
    FROM merchants
    WHERE owner_tax_id IS NOT NULL
        AND owner_tax_id != ''
),
edges AS (
    SELECT DISTINCT a.node_uid AS source_uid,
        b.node_uid AS target_uid
    FROM node_identifiers a
        JOIN node_identifiers b ON a.id_type = b.id_type
        AND a.id_value = b.id_value
    WHERE a.node_uid != b.node_uid
)
SELECT *
FROM edges;
-- 5. QUERY REWRITE
--
-- NAIVE APPROACH: In Part A (Vintage Curves), our initial approach joined the `plans` table 
-- directly to the `installments` table *before* grouping. This is naive because it explodes 
-- the number of rows (1 plan -> N installments) and drags all the `plans` columns through 
-- the join, eating up memory during the aggregation phase.
--
-- EFFICIENT REWRITE: Instead, we should pre-aggregate the `installments` table down to exactly
-- one row per `plan_id` BEFORE joining it to the `plans` table.
WITH plan_aggregates AS (
    -- Group down to 1 row per plan first
    SELECT plan_id,
        SUM(
            CASE
                WHEN due_date <= '2026-07-01' THEN 1
                ELSE 0
            END
        ) AS matured_count,
        SUM(
            CASE
                WHEN due_date <= '2026-07-01'
                AND status IN ('late', 'missed', 'written_off') THEN 1
                ELSE 0
            END
        ) AS defaulted_count
    FROM installments
    GROUP BY plan_id
)
SELECT DATE(p.created_at, 'start of month') AS cohort_month,
    COUNT(p.plan_id) AS total_plans,
    SUM(pa.matured_count) AS total_matured_installments,
    SUM(pa.defaulted_count) AS total_matured_defaulted,
    ROUND(
        CAST(SUM(pa.defaulted_count) AS REAL) / NULLIF(SUM(pa.matured_count), 0),
        4
    ) AS seasoned_delinquency_rate
FROM plans p
    JOIN plan_aggregates pa ON p.plan_id = pa.plan_id
GROUP BY cohort_month
ORDER BY cohort_month;