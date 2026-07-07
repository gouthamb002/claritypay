# ClarityPay — Data & Risk Engineering Take-Home

Welcome, and thanks for your interest in ClarityPay. This repository contains a
take-home exercise drawn from the real work of our Risk & Analytics team.

## Start here

1. Read **[`ASSIGNMENT.md`](ASSIGNMENT.md)** — the brief and the tasks.
2. Read **[`DATA_DICTIONARY.md`](DATA_DICTIONARY.md)** — the table and column reference.
3. Load the data and begin.

## Setup

The dataset ships as a ready-to-use **SQLite** database plus the raw CSVs.

```bash
# Option A — use the shipped database directly:
sqlite3 data/claritypay.db

# Option B — rebuild it from the CSVs:
cd data && sqlite3 claritypay.db < schema.sql
```

Sanity check after loading:

```sql
SELECT 'merchants' AS t, count(*) FROM merchants
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'payment_instruments', count(*) FROM payment_instruments
UNION ALL SELECT 'plans', count(*) FROM plans
UNION ALL SELECT 'installments', count(*) FROM installments;
-- expected: 61 / 3100 / 4027 / 6982 / 35871
```

For the Python visualization layer:

```bash
cd python && pip install -r requirements.txt   # or: uv pip install -r requirements.txt
```

> **Note:** All personal data in this dataset is **synthetic** — generated, never
> real. There is no real PII here.

## What to submit

Place your work in the provided skeleton and fill in the deliverable docs:

```
sql/            partA.sql, partB.sql
python/         your visualization / data-access code
figures/        exported HTML or PNG of your charts
NOTES.md        assumptions, one trade-off, what you'd do with more time
APPROACH.md     a short note/slides walking through your detection approach
                as a flowchart (see the assignment)
RISK_MEMO.md    your auditable risk write-up (see the assignment)
GOVERNANCE.md   your access-control + audit design (see the assignment)
AI_USAGE.md     how you used AI tools, if at all
```

Submit a link to a Git repository or a compressed archive. Good luck.
