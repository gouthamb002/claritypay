-- C1 — PII masking view. (Core)
--
-- View Definitions:
--   - masked_customers: Masks email, dob (to YYYY-01-01), and hashes tax_id using sha256.
--   - masked_merchants: Masks owner_email, owner_dob, and hashes owner_tax_id/business_card_fingerprint.
--   - masked_payment_instruments: Hashes card/bank account fingerprints.
--
-- Note on sha256():
--   Standard SQLite does not natively implement a sha256() function. We write the standard
--   SQL function call here, assuming the database driver (e.g., Python's sqlite3 client) 
--   registers this function on the connection before querying the views.
DROP VIEW IF EXISTS masked_customers;
CREATE VIEW masked_customers AS
SELECT customer_id,
    signup_at,
    region,
    risk_band,
    credit_limit_usd,
    status,
    -- Hash tax_id
    CASE
        WHEN tax_id IS NOT NULL
        AND tax_id != '' THEN sha256(tax_id)
        ELSE NULL
    END AS tax_id_hashed,
    -- Mask dob to YYYY-01-01
    CASE
        WHEN dob IS NOT NULL
        AND dob != '' THEN substr(dob, 1, 4) || '-01-01'
        ELSE NULL
    END AS dob_masked,
    -- Mask email to f***@domain.com
    CASE
        WHEN email IS NOT NULL
        AND email != '' THEN substr(email, 1, 1) || '***@' || substr(email, instr(email, '@') + 1)
        ELSE NULL
    END AS email_masked,
    is_confirmed_fraud
FROM customers;
DROP VIEW IF EXISTS masked_merchants;
CREATE VIEW masked_merchants AS
SELECT merchant_id,
    name,
    category,
    region,
    mdr_bps,
    onboarded_at,
    -- Hash owner_tax_id
    CASE
        WHEN owner_tax_id IS NOT NULL
        AND owner_tax_id != '' THEN sha256(owner_tax_id)
        ELSE NULL
    END AS owner_tax_id_hashed,
    -- Mask owner_dob to YYYY-01-01
    CASE
        WHEN owner_dob IS NOT NULL
        AND owner_dob != '' THEN substr(owner_dob, 1, 4) || '-01-01'
        ELSE NULL
    END AS owner_dob_masked,
    -- Mask owner_email to f***@domain.com
    CASE
        WHEN owner_email IS NOT NULL
        AND owner_email != '' THEN substr(owner_email, 1, 1) || '***@' || substr(owner_email, instr(owner_email, '@') + 1)
        ELSE NULL
    END AS owner_email_masked,
    -- Hash business_card_fingerprint
    CASE
        WHEN business_card_fingerprint IS NOT NULL
        AND business_card_fingerprint != '' THEN sha256(business_card_fingerprint)
        ELSE NULL
    END AS business_card_fingerprint_hashed
FROM merchants;
DROP VIEW IF EXISTS masked_payment_instruments;
CREATE VIEW masked_payment_instruments AS
SELECT instrument_id,
    customer_id,
    instrument_type,
    -- Hash card_fingerprint
    CASE
        WHEN card_fingerprint IS NOT NULL
        AND card_fingerprint != '' THEN sha256(card_fingerprint)
        ELSE NULL
    END AS card_fingerprint_hashed,
    -- Hash bank_account_fingerprint
    CASE
        WHEN bank_account_fingerprint IS NOT NULL
        AND bank_account_fingerprint != '' THEN sha256(bank_account_fingerprint)
        ELSE NULL
    END AS bank_account_fingerprint_hashed,
    added_at
FROM payment_instruments;


-- C2 — Access control and audit. (Core)
--
-- Audit log table to capture any write operation (INSERT, UPDATE, DELETE)
-- on tables containing raw PII (customers, merchants, payment_instruments).

DROP TABLE IF EXISTS pii_audit_log;
CREATE TABLE pii_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    action_timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    target_table TEXT NOT NULL,
    operation TEXT NOT NULL,
    actor TEXT NOT NULL DEFAULT 'sqlite_session_user'
);

-- Triggers for customers table
DROP TRIGGER IF EXISTS audit_customers_insert;
CREATE TRIGGER audit_customers_insert
AFTER INSERT ON customers
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('customers', 'INSERT');
END;

DROP TRIGGER IF EXISTS audit_customers_update;
CREATE TRIGGER audit_customers_update
AFTER UPDATE ON customers
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('customers', 'UPDATE');
END;

DROP TRIGGER IF EXISTS audit_customers_delete;
CREATE TRIGGER audit_customers_delete
AFTER DELETE ON customers
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('customers', 'DELETE');
END;

-- Triggers for merchants table
DROP TRIGGER IF EXISTS audit_merchants_insert;
CREATE TRIGGER audit_merchants_insert
AFTER INSERT ON merchants
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('merchants', 'INSERT');
END;

DROP TRIGGER IF EXISTS audit_merchants_update;
CREATE TRIGGER audit_merchants_update
AFTER UPDATE ON merchants
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('merchants', 'UPDATE');
END;

DROP TRIGGER IF EXISTS audit_merchants_delete;
CREATE TRIGGER audit_merchants_delete
AFTER DELETE ON merchants
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('merchants', 'DELETE');
END;

-- Triggers for payment_instruments table
DROP TRIGGER IF EXISTS audit_payment_instruments_insert;
CREATE TRIGGER audit_payment_instruments_insert
AFTER INSERT ON payment_instruments
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('payment_instruments', 'INSERT');
END;

DROP TRIGGER IF EXISTS audit_payment_instruments_update;
CREATE TRIGGER audit_payment_instruments_update
AFTER UPDATE ON payment_instruments
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('payment_instruments', 'UPDATE');
END;

DROP TRIGGER IF EXISTS audit_payment_instruments_delete;
CREATE TRIGGER audit_payment_instruments_delete
AFTER DELETE ON payment_instruments
BEGIN
    INSERT INTO pii_audit_log (target_table, operation)
    VALUES ('payment_instruments', 'DELETE');
END;