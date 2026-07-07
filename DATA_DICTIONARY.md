# ClarityPay — Data Dictionary

Five tables, SQLite. `customers` and `merchants` are both business entities
**and**, together, the node set of an identity graph you will construct
yourself — there is no pre-built edge table. `plans` and `installments` carry
the repayment ledger; `payment_instruments` carries the funding instruments a
customer has on file.

```
merchants ──< plans >── customers ──< payment_instruments
                 │
                 └──< installments

identity graph = customers ∪ merchants
edge iff shared high-entropy id (tax_id / email / card_fingerprint)
```

> **PII is synthetic.** Every name, tax ID, date of birth, email address, and
> card/bank fingerprint in this dataset is fabricated for the exercise. None
> of it corresponds to a real person or business. Treat it as production-shaped
> PII for the purposes of Part C (masking, governance, audit), but there is no
> real privacy exposure in handling it.

## Row counts (shipped dump)

| table | rows |
|---|---:|
| `merchants` | 61 |
| `customers` | 3,100 |
| `payment_instruments` | 4,027 |
| `plans` | 6,982 |
| `installments` | 35,871 |
| **TOTAL** | **50,041** |

## Calendar

- Dates are stored as ISO **`TEXT`** (`YYYY-MM-DD`), not SQLite's native
  `DATE`/`DATETIME` types — use `date()`, `julianday()`, or string comparison
  as appropriate, not numeric operators.
- Treat **`TODAY = 2026-07-01`** as "now" for any aging, overdue, or
  delinquency calculation.
- **Maturation rule:** a plan's first installment is due **30 days** after
  `plans.created_at` (subsequent installments follow the product's cadence
  from there — see `plans.product_type` below). A plan that was created
  recently will therefore show few or no installments as `due` yet, even if
  it will eventually be a poor performer. Any delinquency metric that does
  not account for this will systematically favor young plans/merchants over
  mature ones — this matters for Part A and Part B.

---

## `merchants`

| column | type | notes |
|---|---|---|
| `merchant_id` | int PK | |
| `name` | text | display name |
| `category` | text | e.g. Fashion, Electronics, Travel, Home, Beauty, Fitness, Grocery |
| `region` | text | NA / EU / APAC / LATAM |
| `mdr_bps` | int | merchant discount rate (ClarityPay's revenue per order), basis points |
| `onboarded_at` | text (ISO date) | |
| `owner_tax_id` | text | synthetic PII / identity attribute |
| `owner_dob` | text (ISO date) | synthetic PII / identity attribute |
| `owner_email` | text | synthetic PII / identity attribute |
| `business_card_fingerprint` | text | synthetic PII / identity attribute |

## `customers` (identity-graph nodes)

| column | type | notes |
|---|---|---|
| `customer_id` | int PK | |
| `signup_at` | text (ISO date) | account creation |
| `region` | text | NA / EU / APAC / LATAM |
| `risk_band` | text | A (best) … E (worst) |
| `credit_limit_usd` | real | |
| `status` | text | account status |
| `tax_id` | text | synthetic PII / identity attribute |
| `dob` | text (ISO date) | synthetic PII / identity attribute |
| `email` | text | synthetic PII / identity attribute |
| `is_confirmed_fraud` | int | 0 / 1 |

## `payment_instruments`

| column | type | notes |
|---|---|---|
| `instrument_id` | int PK | |
| `customer_id` | int FK → `customers` | |
| `instrument_type` | text | `card` or `bank` |
| `card_fingerprint` | text, nullable | tokenized PAN; populated when `instrument_type = 'card'` |
| `bank_account_fingerprint` | text, nullable | tokenized bank account; populated when `instrument_type = 'bank'` |
| `added_at` | text (ISO date) | |

A customer may have more than one instrument. Fingerprints are the
high-entropy identity attribute you'll join through when linking a customer
to a merchant's `business_card_fingerprint` (or to another customer sharing
the same instrument).

## `plans` (one BNPL order)

| column | type | notes |
|---|---|---|
| `plan_id` | int PK | |
| `customer_id` | int FK → `customers` | |
| `merchant_id` | int FK → `merchants` | |
| `product_type` | text | e.g. `pay_in_4`, `pay_in_3`, `pay_monthly_6`, `pay_monthly_12` |
| `num_installments` | int | matches the product's schedule |
| `order_amount_usd` | real | principal |
| `total_repayable_usd` | real | principal + interest (equals principal for 0-APR products) |
| `apr_bps` | int | 0 for the pay-in-N products; non-zero for the monthly products |
| `created_at` | text (ISO date) | order date — the maturation clock starts here |
| `status` | text | plan-level status |

## `installments` (repayment ledger)

| column | type | notes |
|---|---|---|
| `installment_id` | int PK | |
| `plan_id` | int FK → `plans` | |
| `installment_no` | int | 1 … `num_installments` |
| `due_date` | text (ISO date) | |
| `amount_due_usd` | real | |
| `paid_date` | text, nullable | **empty string `''`, not SQL `NULL`, means unpaid** — the CSV loader imports blanks as `''` |
| `paid_amount_usd` | real, nullable | same convention: unpaid rows have no value here |
| `late_fee_usd` | real | charged on late/missed/written-off installments |
| `status` | text | e.g. `scheduled` (not yet due), `paid`, `late`, `missed`, `written_off` |

---

## The identity graph

`customers` and `merchants` are two disjoint sets of nodes in a single
identity graph. There is no `account_links` table — you build the edges
yourself from the columns above.

**Two nodes are linked when they share a high-entropy identifier**: a
`tax_id`, an `email`, or a card/bank `fingerprint` (a customer's
`payment_instruments.card_fingerprint` / `bank_account_fingerprint`, or a
merchant's `business_card_fingerprint`). A customer-to-merchant edge and a
customer-to-customer edge are both formed the same way — by an exact match on
one of these attributes.

Every person and business in this dataset also has a `dob` (`customers.dob`
or `merchants.owner_dob`) recorded as PII, alongside the identifiers above.
Whether — and how — date of birth should factor into your identity-linking
logic is a judgment call for you to make and document, not something this
dictionary prescribes. Different attributes carry different entropy and
different collision risk at this population size; part of the exercise is
recognizing which of a candidate identifier's properties make it suitable (or
unsuitable) for declaring two accounts "the same underlying party."

There is no separate weighting or distance metric shipped with the data (no
analogue of a `link_distance` column) — an edge either exists, because two
nodes share an identifier, or it doesn't. Any notion of "stronger" or
"weaker" evidence across multiple shared attributes is something you would
define and justify yourself.
