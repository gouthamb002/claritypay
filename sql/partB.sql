-- B1 — Identity clusters. (Core)
-- 
-- Graph Construction Notes:
-- Edges are built strictly on deterministic, high-entropy fields (tax_id, email, fingerprints).
-- We deliberately exclude low-entropy fields (like dob or region) to prevent massive false-positive 
-- super-clusters. 
--
-- Traversal Notes:
-- We use a Recursive CTE with a comma-delimited path tracker (visited_path) to prevent cycles. 
-- A depth cap of 10 is included as an absolute failsafe against runaway queries.
-- For every node, the final component_id is assigned as the MIN(root_uid) that was able to reach it.
WITH node_identifiers AS (
    -- EMAILS
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
    -- TAX IDs
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
    UNION ALL
    -- CARDS
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid,
        'card' AS id_type,
        card_fingerprint AS id_value
    FROM payment_instruments
    WHERE instrument_type = 'card'
        AND card_fingerprint IS NOT NULL
        AND card_fingerprint != ''
    UNION ALL
    SELECT 'merchant' AS node_type,
        merchant_id AS node_id,
        'm_' || merchant_id AS node_uid,
        'card' AS id_type,
        business_card_fingerprint AS id_value
    FROM merchants
    WHERE business_card_fingerprint IS NOT NULL
        AND business_card_fingerprint != ''
    UNION ALL
    -- BANK ACCOUNTS
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid,
        'bank' AS id_type,
        bank_account_fingerprint AS id_value
    FROM payment_instruments
    WHERE instrument_type = 'bank'
        AND bank_account_fingerprint IS NOT NULL
        AND bank_account_fingerprint != ''
),
edges AS (
    -- Build an undirected edge list by self-joining the identifiers
    SELECT DISTINCT a.node_type AS source_type,
        a.node_id AS source_id,
        a.node_uid AS source_uid,
        b.node_type AS target_type,
        b.node_id AS target_id,
        b.node_uid AS target_uid
    FROM node_identifiers a
        JOIN node_identifiers b ON a.id_type = b.id_type
        AND a.id_value = b.id_value
    WHERE a.node_uid != b.node_uid
),
initial_nodes AS (
    -- We need to include EVERY node, even isolated ones with no edges.
    SELECT 'customer' AS node_type,
        customer_id AS node_id,
        'c_' || customer_id AS node_uid
    FROM customers
    UNION ALL
    SELECT 'merchant' AS node_type,
        merchant_id AS node_id,
        'm_' || merchant_id AS node_uid
    FROM merchants
),
graph_traversal AS (
    -- Anchor Member: Start a traversal from every single node
    SELECT node_uid AS root_uid,
        node_type,
        node_id,
        node_uid AS current_uid,
        ',' || node_uid || ',' AS visited_path,
        0 AS depth
    FROM initial_nodes
    UNION ALL
    -- Recursive Member: Hop to connected neighbors
    SELECT gt.root_uid,
        e.target_type AS node_type,
        e.target_id AS node_id,
        e.target_uid AS current_uid,
        gt.visited_path || e.target_uid || ',' AS visited_path,
        gt.depth + 1 AS depth
    FROM graph_traversal gt
        JOIN edges e ON gt.current_uid = e.source_uid
    WHERE gt.depth < 10
        AND INSTR(gt.visited_path, ',' || e.target_uid || ',') = 0
) -- Because a single connected component can be explored starting from ANY of its nodes,
-- every node in a component will be reached by the exact same set of roots.
-- Therefore, MIN(root_uid) will be identical for every node in the same component.
SELECT node_type,
    node_id,
    MIN(root_uid) AS component_id
FROM graph_traversal
GROUP BY node_type,
    node_id
ORDER BY component_id,
    node_type,
    node_id;


-- B2 — One merchant's collusion cluster. (Stretch)
--
-- Target Merchant Selection:
--   We selected Merchant 51 (Bright House) because:
--     1. It was ranked #1 in seasoned default rate (30.00%) from A4.
--     2. It resides in the largest connected identity component in the graph (9 total nodes).
--
-- Concentration Threshold:
--   We define a concentration threshold of >= 50.0% (0.50). 
--   This filters for customers whose transaction volume is heavily focused on this single merchant.
--
WITH node_identifiers AS (
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'email' AS id_type, email AS id_value
    FROM customers WHERE email IS NOT NULL AND email != ''
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid, 'email' AS id_type, owner_email AS id_value
    FROM merchants WHERE owner_email IS NOT NULL AND owner_email != ''
    UNION ALL
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'tax_id' AS id_type, tax_id AS id_value
    FROM customers WHERE tax_id IS NOT NULL AND tax_id != ''
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid, 'tax_id' AS id_type, owner_tax_id AS id_value
    FROM merchants WHERE owner_tax_id IS NOT NULL AND owner_tax_id != ''
    UNION ALL
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'card' AS id_type, card_fingerprint AS id_value
    FROM payment_instruments WHERE instrument_type = 'card' AND card_fingerprint IS NOT NULL AND card_fingerprint != ''
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid, 'card' AS id_type, business_card_fingerprint AS id_value
    FROM merchants WHERE business_card_fingerprint IS NOT NULL AND business_card_fingerprint != ''
    UNION ALL
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'bank' AS id_type, bank_account_fingerprint AS id_value
    FROM payment_instruments WHERE instrument_type = 'bank' AND bank_account_fingerprint IS NOT NULL AND bank_account_fingerprint != ''
),
edges AS (
    SELECT DISTINCT
        a.node_uid AS source_uid,
        b.node_uid AS target_uid
    FROM node_identifiers a
    JOIN node_identifiers b 
        ON a.id_type = b.id_type AND a.id_value = b.id_value
    WHERE a.node_uid != b.node_uid
),
initial_nodes AS (
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid FROM customers
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid FROM merchants
),
graph_traversal AS (
    SELECT node_uid AS root_uid, node_uid AS current_uid, ',' || node_uid || ',' AS visited_path, 0 AS depth
    FROM initial_nodes
    UNION ALL
    SELECT gt.root_uid, e.target_uid AS current_uid, gt.visited_path || e.target_uid || ',' AS visited_path, gt.depth + 1 AS depth
    FROM graph_traversal gt
    JOIN edges e ON gt.current_uid = e.source_uid
    WHERE gt.depth < 10 AND INSTR(gt.visited_path, ',' || e.target_uid || ',') = 0
),
components AS (
    SELECT node_uid, MIN(root_uid) AS component_id
    FROM (SELECT DISTINCT current_uid AS node_uid, root_uid FROM graph_traversal) gt
    GROUP BY 1
),
bright_house_component AS (
    -- Find the component_id dynamically for Merchant 51 (Bright House)
    SELECT component_id 
    FROM components 
    WHERE node_uid = 'm_51'
),
cluster_customers AS (
    -- Select the customers in that component
    SELECT i.node_id AS customer_id, c.component_id
    FROM components c
    JOIN initial_nodes i ON c.node_uid = i.node_uid
    JOIN bright_house_component bhc ON c.component_id = bhc.component_id
    WHERE c.node_uid LIKE 'c_%'
),
customer_orders AS (
    -- Calculate order concentration for these customers
    SELECT 
        p.customer_id,
        COUNT(p.plan_id) AS total_plans,
        SUM(CASE WHEN p.merchant_id = 51 THEN 1 ELSE 0 END) AS plans_at_bright_house,
        CAST(SUM(CASE WHEN p.merchant_id = 51 THEN 1 ELSE 0 END) AS REAL) / COUNT(p.plan_id) AS order_concentration
    FROM plans p
    GROUP BY p.customer_id
),
customer_defaults AS (
    -- Calculate seasoned default rates for these customers
    SELECT 
        p.customer_id,
        SUM(CASE WHEN i.due_date <= '2026-07-01' THEN 1 ELSE 0 END) AS matured_installments,
        SUM(CASE WHEN i.due_date <= '2026-07-01' AND i.status IN ('late', 'missed', 'written_off') THEN 1 ELSE 0 END) AS matured_defaults,
        CAST(SUM(CASE WHEN i.due_date <= '2026-07-01' AND i.status IN ('late', 'missed', 'written_off') THEN 1 ELSE 0 END) AS REAL) / 
            NULLIF(SUM(CASE WHEN i.due_date <= '2026-07-01' THEN 1 ELSE 0 END), 0) AS seasoned_default_rate
    FROM plans p
    JOIN installments i ON p.plan_id = i.plan_id
    GROUP BY p.customer_id
)
SELECT 
    cc.customer_id,
    cc.component_id,
    co.total_plans,
    co.plans_at_bright_house,
    ROUND(co.order_concentration, 4) AS order_concentration,
    COALESCE(cd.matured_installments, 0) AS matured_installments,
    COALESCE(cd.matured_defaults, 0) AS matured_defaults,
    ROUND(COALESCE(cd.seasoned_default_rate, 0.0), 4) AS seasoned_default_rate
FROM cluster_customers cc
JOIN customer_orders co ON cc.customer_id = co.customer_id
LEFT JOIN customer_defaults cd ON cc.customer_id = cd.customer_id
WHERE co.order_concentration >= 0.50
ORDER BY order_concentration DESC, seasoned_default_rate DESC;


-- B3 — Ranked, auditable case file. (Stretch)
--
-- Severity Score Formula: (cluster_size * 10) + (concentration_metric * 100) + (seasoned_delinquency_rate * 100)
-- 
-- Rationale:
--   1. Size Multiplier (10x): Each additional synthetic identity in a cluster increases the risk linearly. 
--      A cluster of 9 entities adds 90 points, whereas a cluster of 2 adds 20 points.
--   2. Concentration (100x): Order concentration (percentage of cluster volume spent at cluster merchants) 
--      is a smoking gun for self-dealing. A 100% concentration rate adds a massive 100 points.
--   3. Delinquency (100x): The ultimate proof of fraud is not paying back the loans. A 100% seasoned 
--      default rate adds another 100 points.
--   
--   This creates a maximum theoretical score near 300 for massive, 100% concentrated, completely defaulted rings,
--   allowing a fraud analyst to easily sort and prioritize the worst offenders.
--
WITH node_identifiers AS (
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'email' AS id_type, email AS id_value
    FROM customers WHERE email IS NOT NULL AND email != ''
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid, 'email' AS id_type, owner_email AS id_value
    FROM merchants WHERE owner_email IS NOT NULL AND owner_email != ''
    UNION ALL
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'tax_id' AS id_type, tax_id AS id_value
    FROM customers WHERE tax_id IS NOT NULL AND tax_id != ''
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid, 'tax_id' AS id_type, owner_tax_id AS id_value
    FROM merchants WHERE owner_tax_id IS NOT NULL AND owner_tax_id != ''
    UNION ALL
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'card' AS id_type, card_fingerprint AS id_value
    FROM payment_instruments WHERE instrument_type = 'card' AND card_fingerprint IS NOT NULL AND card_fingerprint != ''
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid, 'card' AS id_type, business_card_fingerprint AS id_value
    FROM merchants WHERE business_card_fingerprint IS NOT NULL AND business_card_fingerprint != ''
    UNION ALL
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid, 'bank' AS id_type, bank_account_fingerprint AS id_value
    FROM payment_instruments WHERE instrument_type = 'bank' AND bank_account_fingerprint IS NOT NULL AND bank_account_fingerprint != ''
),
edges AS (
    SELECT DISTINCT
        a.node_uid AS source_uid,
        b.node_uid AS target_uid
    FROM node_identifiers a
    JOIN node_identifiers b 
        ON a.id_type = b.id_type AND a.id_value = b.id_value
    WHERE a.node_uid != b.node_uid
),
initial_nodes AS (
    SELECT 'customer' AS node_type, customer_id AS node_id, 'c_' || customer_id AS node_uid FROM customers
    UNION ALL
    SELECT 'merchant' AS node_type, merchant_id AS node_id, 'm_' || merchant_id AS node_uid FROM merchants
),
graph_traversal AS (
    SELECT node_uid AS root_uid, node_uid AS current_uid, ',' || node_uid || ',' AS visited_path, 0 AS depth
    FROM initial_nodes
    UNION ALL
    SELECT gt.root_uid, e.target_uid AS current_uid, gt.visited_path || e.target_uid || ',' AS visited_path, gt.depth + 1 AS depth
    FROM graph_traversal gt
    JOIN edges e ON gt.current_uid = e.source_uid
    WHERE gt.depth < 10 AND INSTR(gt.visited_path, ',' || e.target_uid || ',') = 0
),
components AS (
    SELECT node_uid, MIN(root_uid) AS component_id
    FROM (SELECT DISTINCT current_uid AS node_uid, root_uid FROM graph_traversal) gt
    GROUP BY 1
),
cluster_stats AS (
    SELECT component_id,
           COUNT(*) AS cluster_size,
           SUM(CASE WHEN node_uid LIKE 'm_%' THEN 1 ELSE 0 END) AS num_merchants,
           SUM(CASE WHEN node_uid LIKE 'c_%' THEN 1 ELSE 0 END) AS num_customers
    FROM components
    GROUP BY component_id
    HAVING COUNT(*) > 1 -- Only analyze multi-node clusters
),
cluster_customers AS (
    SELECT c.component_id, n.node_id AS customer_id
    FROM components c
    JOIN initial_nodes n ON c.node_uid = n.node_uid
    WHERE n.node_type = 'customer'
),
cluster_merchants AS (
    SELECT c.component_id, n.node_id AS merchant_id
    FROM components c
    JOIN initial_nodes n ON c.node_uid = n.node_uid
    WHERE n.node_type = 'merchant'
),
customer_plans AS (
    -- Get all plans made by customers in the cluster
    SELECT cc.component_id, p.customer_id, p.plan_id, p.merchant_id
    FROM cluster_customers cc
    JOIN plans p ON cc.customer_id = p.customer_id
),
concentration_metrics AS (
    -- Calculate intra-cluster order concentration: 
    -- What % of these customers' orders went to merchants inside the exact same cluster?
    SELECT 
        cp.component_id,
        CAST(SUM(CASE WHEN cm.merchant_id IS NOT NULL THEN 1 ELSE 0 END) AS REAL) / 
            NULLIF(COUNT(cp.plan_id), 0) AS intra_cluster_order_concentration
    FROM customer_plans cp
    LEFT JOIN cluster_merchants cm 
        ON cp.component_id = cm.component_id AND cp.merchant_id = cm.merchant_id
    GROUP BY cp.component_id
),
delinquency_metrics AS (
    -- Calculate the seasoned default rate for the entire cluster
    SELECT 
        cc.component_id,
        CAST(SUM(CASE WHEN i.due_date <= '2026-07-01' AND i.status IN ('late', 'missed', 'written_off') THEN 1 ELSE 0 END) AS REAL) /
            NULLIF(SUM(CASE WHEN i.due_date <= '2026-07-01' THEN 1 ELSE 0 END), 0) AS seasoned_default_rate
    FROM cluster_customers cc
    JOIN plans p ON cc.customer_id = p.customer_id
    JOIN installments i ON p.plan_id = i.plan_id
    GROUP BY cc.component_id
),
scored_clusters AS (
    SELECT cs.component_id,
           cs.cluster_size,
           ROUND(COALESCE(cm.intra_cluster_order_concentration, 0.0), 4) AS concentration_metric,
           ROUND(COALESCE(dm.seasoned_default_rate, 0.0), 4) AS seasoned_delinquency_rate,
           ROUND(
               (cs.cluster_size * 10) + 
               (COALESCE(cm.intra_cluster_order_concentration, 0.0) * 100) + 
               (COALESCE(dm.seasoned_default_rate, 0.0) * 100), 
           2) AS severity_score
    FROM cluster_stats cs
    LEFT JOIN concentration_metrics cm ON cs.component_id = cm.component_id
    LEFT JOIN delinquency_metrics dm ON cs.component_id = dm.component_id
)
SELECT 
    component_id,
    cluster_size,
    concentration_metric,
    seasoned_delinquency_rate,
    severity_score,
    RANK() OVER (ORDER BY severity_score DESC) AS rank
FROM scored_clusters
ORDER BY rank ASC;