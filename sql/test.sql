-- Insert a mock customer
INSERT INTO customers (
        customer_id,
        signup_at,
        region,
        risk_band,
        credit_limit_usd,
        status,
        tax_id,
        dob,
        email,
        is_confirmed_fraud
    )
VALUES (
        9999,
        '2026-07-10',
        'US',
        'low',
        5000.00,
        'active',
        '123-45-6789',
        '1990-01-01',
        'test@test.com',
        0
    );
-- Update their credit limit
UPDATE customers
SET credit_limit_usd = 6000.00
WHERE customer_id = 9999;
SELECT *
FROM pii_audit_log;
DELETE FROM customers
WHERE customer_id = 9999;