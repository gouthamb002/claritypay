# ClarityPay — Data and Visualization Engineering Assignment

## Overview

This assignment reflects the work of our Risk and Analytics team: deriving
reliable answers from a transactional ledger and an identity graph that isn't
handed to you pre-built, and presenting those answers clearly. You will be
assessed on correctness, command of advanced SQL (window functions, gaps-and-
islands, recursive CTEs), graph reasoning, code quality, and the clarity of
your written reasoning — including the judgment calls you make and document
along the way.

- Database: SQLite (a ready-built `data/claritypay.db` ships with the
  assignment; it can also be rebuilt from the CSVs).
- Visualization: Python, using Plotly and NetworkX.
- Format: **timed-hybrid**. Budget roughly **2–3 hours** for the **(Core)**
  items. The **(Stretch)** items are untimed — take the time you need, or skip
  them; they exist to distinguish stronger submissions, not to be a second
  pass/fail bar.

The assignment is tiered. Items marked **(Core)** establish the baseline and
should be completed first. Items marked **(Stretch)** are more demanding.
A smaller number of correct, well-documented answers is preferred over a
larger number of incomplete ones.

## Scope and Assumptions

Real datasets are imperfect and requirements are rarely exhaustive. Where this
brief is silent or ambiguous, you are expected to make reasonable, defensible
assumptions and proceed rather than wait for clarification. Each assumption
must be:

1. stated explicitly in `NOTES.md` (and, where relevant, in a comment beside
   the query it affects);
2. internally consistent across your submission; and
3. justifiable on business or data-quality grounds.

We evaluate the quality of your reasoning, not your ability to guess an
unstated intent. A sound assumption, clearly documented, is always
acceptable. This applies with particular force to Part B: how you decide what
constitutes an identity link is a judgment call we are explicitly assessing,
not a detail to reverse-engineer.

## Background

ClarityPay is a Buy-Now-Pay-Later (BNPL) provider. A customer completes a
purchase at a merchant; ClarityPay settles with the merchant immediately and
the customer repays ClarityPay in scheduled installments (for example
`pay_in_4` or `pay_monthly_12`). Every scheduled payment is recorded as a row
in the installment ledger.

Separately, ClarityPay's risk function is interested in whether accounts —
customers or merchants — are secretly the same underlying party operating
under different records. Two accounts sharing a tax ID, an email address, or
a card/bank fingerprint is one kind of evidence of this; how much weight that
evidence deserves, and which shared attributes are strong enough to act on,
is left to your judgment. This kind of self-dealing is a real BNPL risk
pattern: a merchant that is effectively lending to itself will look fine on
paper until its self-funded orders mature and start missing payments.

This assignment covers three domains: repayment analytics over time (Part A),
an identity graph you construct from raw columns (Part B), and a
visualization and governance layer over both (Part C).

## Setup

1. Open the shipped database directly:

   ```bash
   sqlite3 data/claritypay.db
   ```

   Or rebuild it from the CSVs:

   ```bash
   cd data
   sqlite3 claritypay.db < schema.sql
   ```

2. Review `DATA_DICTIONARY.md` for the full table and column reference,
   including the identity-graph framing and the maturation rule. Note in
   particular:
   - Dates are ISO **`TEXT`**, not native `DATE`/`DATETIME` — use `date()` and
     `julianday()` rather than numeric or date-typed operators.
   - Booleans are stored as **`0`/`1`** integers.
   - Unpaid installments have `paid_date = ''` (empty string, not `NULL`) and
     `paid_amount_usd` unset — the CSV loader imports blanks that way.
   - Treat **`TODAY = 2026-07-01`** as "now" for any aging or delinquency
     calculation, and remember the **30-day maturation lag** between a plan's
     `created_at` and its first installment's `due_date`.
   - `schema.sql` ships with **no secondary indexes** — that is deliberate
     (see Part C4).

Sanity check after loading:

```sql
SELECT 'merchants' AS "table", count(*) AS n FROM merchants
UNION ALL SELECT 'customers', count(*) FROM customers
UNION ALL SELECT 'payment_instruments', count(*) FROM payment_instruments
UNION ALL SELECT 'plans', count(*) FROM plans
UNION ALL SELECT 'installments', count(*) FROM installments;
-- expected: 61 / 3100 / 4027 / 6982 / 35871  (sums to 50,041)
```

---

## Part A — Repayment Analytics Over Time

Concepts assessed: common table expressions, window aggregates, `LAG`,
gaps-and-islands grouping, and window frames (`RANGE` / `GROUPS`).

Place your answers in `sql/partA.sql`, with each question identified by a
comment. Every query must execute without modification against the loaded
database.

**A1 — Vintage / seasoning curve. (Core)**
Group plans into monthly origination cohorts by `created_at`. For each
cohort, compute cumulative on-time or default performance as a function of
"months on book" since origination — a standard credit-risk vintage curve.
Required columns: `cohort_month, months_on_book, installments_due,
cumulative_default_rate` (define `cumulative_default_rate` precisely in a
comment, including which installment statuses you count as a default). Use
window functions rather than a self-join.

**A2 — Longest missed-payment streak (gaps and islands). (Core)**
For each plan, find the longest run of *consecutive* installments (by
`installment_no`) with status `late`, `missed`, or `written_off`. This is a
classic gaps-and-islands problem — do not solve it with a loop or a
procedural scan.
Required columns: `plan_id, longest_missed_streak, streak_start_installment_no,
streak_end_installment_no`. Plans with no missed installments should show a
streak of 0.

**A3 — Rolling collections. (Core)**
For each merchant, compute a rolling 30-day trailing total of amounts
actually collected (`paid_amount_usd` on paid installments), evaluated at
each `paid_date` that occurs. Use a window frame with `RANGE BETWEEN` (or, if
you frame it by row count instead of a date range, `GROUPS BETWEEN`) rather
than a self-join or a correlated subquery.
Required columns: `merchant_id, paid_date, collected_that_day,
rolling_30d_collected`. State in a comment which frame type you chose and
why.

**A4 — Seasoned vs. naive merchant delinquency ranking. (Stretch)**
Rank merchants by delinquency rate two ways: a **naive** rate over *all*
installments regardless of whether they've had time to come due, and a
**seasoned** rate restricted to installments that are actually past their
maturation window (using `TODAY` and the 30-day maturation lag from the
Data Dictionary). Return both rankings side by side and identify any merchant
whose rank changes materially between them.
Required columns: `merchant_id, name, naive_rate, naive_rank, seasoned_rate,
seasoned_rank, rank_delta`. In a comment, explain in a sentence or two why a
naive rate systematically favors merchants with a lot of *recent* orders,
independent of their actual repayment quality.

---

## Part B — Identity Graph and Collusion Detection

Concepts assessed: recursive CTEs, connected-component construction, cycle
prevention, and defensible scoring under ambiguity.

Place your answers in `sql/partB.sql`. Use a recursive CTE for B1 through B3.
SQLite has no native array type — accumulate a visited-node set as delimited
text (or an equivalent technique) for your cycle guard; do not hard-code hop
counts and do not emulate traversal with per-hop self-joins.

There is no pre-built edge table. You must derive the identity graph yourself
from `customers`, `merchants`, and `payment_instruments`, per the "shared
high-entropy identifier" framing in `DATA_DICTIONARY.md`. Which attributes
you treat as forming a valid edge — and which, if any, you deliberately
exclude — is part of what this section assesses. State and justify your
choice in `NOTES.md`.

**B1 — Identity clusters. (Core)**
Using your derived edge set, compute the connected components of the
identity graph over `customers ∪ merchants`. Use a recursive CTE that is
cycle-safe (a node cannot be revisited within a traversal) and depth-capped
(recursion terminates even if a component turns out to be large).
Required columns: `node_type` (`customer` or `merchant`), `node_id`,
`component_id`.

**B2 — One merchant's collusion cluster. (Stretch)**
Take the merchant your Part A4 seasoned-delinquency ranking (or your B1
component sizes) flags as the most anomalous, and assemble the full picture
for that merchant: its identity-graph component from B1, the subset of its
customers whose orders are unusually concentrated at that merchant relative
to their overall activity, and their seasoned repayment behavior from Part A.
Required output: a single query or small set of queries whose result set
identifies the customers you believe are self-dealing with that merchant,
plus the evidence (component membership, concentration, seasoned
delinquency) supporting each one. Document your merchant selection and your
concentration threshold in a comment.

**B3 — Ranked, auditable case file. (Stretch)**
Across all identity components with more than one customer (or a customer
and a merchant), compute a defensible severity score combining cluster size,
order concentration, and seasoned delinquency, and produce a ranked list —
the kind of flag list a fraud analyst could act on. Write up your top
findings, with the supporting evidence for each, in `RISK_MEMO.md`.
Required columns: `component_id, cluster_size, concentration_metric,
seasoned_delinquency_rate, severity_score, rank`. State your scoring formula
and its rationale in a comment and in `RISK_MEMO.md`.

---

## Part C — Regulated Data, Visualization, and Delivery

Place your SQL in `sql/`, notebook/script code in `python/`. A script or a
notebook is acceptable. Keep any credentials or file paths out of hard-coded
strings — use variables or a small configuration block. Parameters such as a
target merchant or customer must be variables, not values embedded in query
strings.

**C1 — PII masking view. (Core)**
Create a SQL view (or set of views) that exposes `customers`, `merchants`,
and `payment_instruments` data for analytics use **without ever surfacing
raw `tax_id`, `dob`, `email`, or fingerprint values**. Any join your masked
view needs across these attributes must be performed on the raw tables
underneath and never re-exposed; the view itself should only ever return
masked, tokenized, or hashed forms.

**C2 — Access control and audit. (Core)**
Build (a) the masked, analyst-facing view(s) from C1; (b) an audit-log table
populated by a **trigger** that records any write to a table containing raw
PII (actor, timestamp, table, and operation, at minimum); and (c) a short
`GOVERNANCE.md` describing an access-control design for this dataset in a
regulated setting — who should be able to see raw PII versus masked-only
data, how that would be enforced, and how the audit trail would be used.

**C3 — Visualization. (Core)**
Produce two pieces of output:
- A NetworkX rendering of an identity-graph cluster from Part B, with the
  merchant (or component) as a parameter you can swap — **no raw PII in node
  labels or figure text**, identifiers only.
- Plotly vintage curves from A1, with merchant as a filter/parameter.
Titles, axis labels, and hover text must make each figure self-explanatory.

**C4 — Scalability. (Stretch)**
Pick one heavier query from Part A or Part B, run `EXPLAIN QUERY PLAN`
against it on the unindexed schema, add one or more `CREATE INDEX`
statements that materially improve it, and show the before/after plan. Write
a short rewrite of a query you initially wrote naively into a more efficient
form, and a brief note on what would need to change (indexing strategy,
materialization, engine choice) to run this analysis at 50–100x the current
row counts.

---

## Deliverables

```
sql/partA.sql        A1 through A4, executable, commented by question
sql/partB.sql        B1 through B3, using recursive CTEs
python/              C1 through C3 (and C4) code that produces the figures
figures/             exported PNG or HTML of your charts
GOVERNANCE.md         access-control design (Part C2)
RISK_MEMO.md          ranked findings and evidence (Part B3)
NOTES.md              one page maximum: assumptions (including your
                     identity-link definition), one trade-off encountered,
                     and what you would do with additional time
APPROACH.md           a short note or a few slides that walk through your
                     collusion-detection approach as a flowchart/diagram
                     (Mermaid, an image, a PDF, or plain ASCII — your choice)
AI_USAGE.md           a short note on which AI tools, if any, you used and how
```

For `APPROACH.md`, we are looking for a clear, end-to-end picture of how your
detection works — from building the identity graph, through your concentration
and seasoned-delinquency measures, to the ranked cluster output and where a
human reviewer would step in. Aim for something a risk analyst who does not
read SQL could follow.

Submit a compressed archive or a link to a Git repository.

## Assessment Criteria

- SQL that executes without modification and handles edge cases correctly,
  including plans with no missed installments, the first row of a rolling
  window, division by zero, and installments that are not yet due.
- A defensible, clearly documented definition of what constitutes an
  identity link, and identity-graph queries that are cycle-safe and
  terminate.
- Recognition of the maturation effect on delinquency measurement and its
  consequences for merchant ranking.
- Figures that answer a clearly defined question, with no raw PII rendered
  anywhere in figures or logs.
- A masking/audit design in `GOVERNANCE.md` that would hold up under a real
  data-access review.
- `NOTES.md` and `RISK_MEMO.md` that demonstrate sound reasoning under
  ambiguity, not just working code.
- An `APPROACH.md` flowchart that communicates your detection pipeline clearly
  to a non-engineer and matches the queries you actually wrote.
- An honest `AI_USAGE.md`: we care that you can own and explain your
  submission, not whether you used AI.
