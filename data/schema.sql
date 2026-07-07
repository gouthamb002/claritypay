-- ClarityPay v2 take-home schema (SQLite).
-- A ready-built data/claritypay.db ships with the assignment. To rebuild from
-- the CSVs instead, run from data/:  sqlite3 claritypay.db < schema.sql
DROP TABLE IF EXISTS installments;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS payment_instruments;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS merchants;

CREATE TABLE merchants (
    merchant_id   INTEGER PRIMARY KEY,
    name          TEXT NOT NULL,
    category      TEXT NOT NULL,
    region        TEXT NOT NULL,
    mdr_bps       INTEGER NOT NULL,
    onboarded_at  TEXT NOT NULL,          -- ISO date
    owner_tax_id  TEXT NOT NULL,          -- synthetic PII / identity attribute
    owner_dob     TEXT NOT NULL,          -- synthetic PII / identity attribute
    owner_email   TEXT NOT NULL,          -- synthetic PII / identity attribute
    business_card_fingerprint TEXT NOT NULL
);

CREATE TABLE customers (
    customer_id       INTEGER PRIMARY KEY,
    signup_at         TEXT NOT NULL,       -- ISO date
    region            TEXT NOT NULL,
    risk_band         TEXT NOT NULL,
    credit_limit_usd  REAL NOT NULL,
    status            TEXT NOT NULL,
    tax_id            TEXT NOT NULL,       -- synthetic PII / identity attribute
    dob               TEXT NOT NULL,       -- synthetic PII / identity attribute
    email             TEXT NOT NULL,       -- synthetic PII / identity attribute
    is_confirmed_fraud INTEGER NOT NULL    -- 0 / 1
);

CREATE TABLE payment_instruments (
    instrument_id             INTEGER PRIMARY KEY,
    customer_id               INTEGER NOT NULL REFERENCES customers(customer_id),
    instrument_type           TEXT NOT NULL,          -- 'card' | 'bank'
    card_fingerprint          TEXT,                    -- tokenized PAN (nullable)
    bank_account_fingerprint  TEXT,                    -- tokenized bank acct (nullable)
    added_at                  TEXT NOT NULL            -- ISO date
);

CREATE TABLE plans (
    plan_id             INTEGER PRIMARY KEY,
    customer_id         INTEGER NOT NULL REFERENCES customers(customer_id),
    merchant_id         INTEGER NOT NULL REFERENCES merchants(merchant_id),
    product_type        TEXT NOT NULL,
    num_installments    INTEGER NOT NULL,
    order_amount_usd    REAL NOT NULL,
    total_repayable_usd REAL NOT NULL,
    apr_bps             INTEGER NOT NULL,
    created_at          TEXT NOT NULL,               -- ISO date
    status              TEXT NOT NULL
);

CREATE TABLE installments (
    installment_id  INTEGER PRIMARY KEY,
    plan_id         INTEGER NOT NULL REFERENCES plans(plan_id),
    installment_no  INTEGER NOT NULL,
    due_date        TEXT NOT NULL,                   -- ISO date
    amount_due_usd  REAL NOT NULL,
    paid_date       TEXT,                            -- ISO date, nullable
    paid_amount_usd REAL,
    late_fee_usd    REAL NOT NULL,
    status          TEXT NOT NULL
);

-- Load the CSVs (sqlite3 CLI >= 3.32). Empty strings import as '' not NULL;
-- candidates should treat '' in paid_date/paid_amount as "unpaid".
.mode csv
.import --skip 1 merchants.csv merchants
.import --skip 1 customers.csv customers
.import --skip 1 payment_instruments.csv payment_instruments
.import --skip 1 plans.csv plans
.import --skip 1 installments.csv installments

-- Deliberately NO secondary indexes here: candidates add them in C4.
