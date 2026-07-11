-- A1 — Vintage / seasoning curve. (Core)
--
-- cumulative_default_rate:
--   (Cumulative count of installments in defaulted status up to months_on_book) / 
--   (Cumulative count of installments that have come due up to months_on_book)
--   for a given monthly cohort of plans.
--
--   An installment is considered "due" if its due_date is on or before TODAY (2026-07-01).
--   An installment is counted as a "default" if its status is 'late', 'missed', or 'written_off'.
WITH installment_months AS (
    SELECT strftime('%Y-%m', p.created_at) AS cohort_month,
        (
            (
                strftime('%Y', i.due_date) - strftime('%Y', p.created_at)
            ) * 12 + (
                strftime('%m', i.due_date) - strftime('%m', p.created_at)
            )
        ) AS months_on_book,
        i.status
    FROM plans p
        JOIN installments i ON p.plan_id = i.plan_id
    WHERE i.due_date <= '2026-07-01'
),
mob_aggregates AS (
    SELECT cohort_month,
        months_on_book,
        COUNT(*) AS due_at_mob,
        SUM(
            CASE
                WHEN status IN ('late', 'missed', 'written_off') THEN 1
                ELSE 0
            END
        ) AS default_at_mob
    FROM installment_months
    GROUP BY 1,
        2
)
SELECT cohort_month,
    months_on_book,
    SUM(due_at_mob) OVER (
        PARTITION BY cohort_month
        ORDER BY months_on_book ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS installments_due,
    ROUND(
        CAST(
            SUM(default_at_mob) OVER (
                PARTITION BY cohort_month
                ORDER BY months_on_book ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS REAL
        ) / SUM(due_at_mob) OVER (
            PARTITION BY cohort_month
            ORDER BY months_on_book ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        4
    ) AS cumulative_default_rate
FROM mob_aggregates
ORDER BY 1,
    2;
-- A2 — Longest missed-payment streak (gaps and islands). (Core)
--
-- In case of ties (multiple streaks with the same maximum length), we select the 
-- first occurring streak by ordering by start_no ASC in the ROW_NUMBER() window function.
-- For plans with no missed installments, the streak length is 0, and start/end numbers are NULL.
WITH missed_ranked AS (
    SELECT plan_id,
        installment_no,
        ROW_NUMBER() OVER (
            PARTITION BY plan_id
            ORDER BY installment_no
        ) AS seq_num
    FROM installments
    WHERE status IN ('late', 'missed', 'written_off')
),
streaks AS (
    SELECT plan_id,
        (installment_no - seq_num) AS streak_group,
        COUNT(*) AS streak_length,
        MIN(installment_no) AS start_no,
        MAX(installment_no) AS end_no
    FROM missed_ranked
    GROUP BY plan_id,
        (installment_no - seq_num)
),
ranked_streaks AS (
    SELECT plan_id,
        streak_length,
        start_no,
        end_no,
        ROW_NUMBER() OVER (
            PARTITION BY plan_id
            ORDER BY streak_length DESC,
                start_no ASC
        ) AS rnk
    FROM streaks
)
SELECT p.plan_id,
    COALESCE(rs.streak_length, 0) AS longest_missed_streak,
    rs.start_no AS streak_start_installment_no,
    rs.end_no AS streak_end_installment_no
FROM plans p
    LEFT JOIN ranked_streaks rs ON p.plan_id = rs.plan_id
    AND rs.rnk = 1
ORDER BY p.plan_id;
-- A3 — Rolling collections. (Core)
--
-- Frame Type Selection:
--   We choose a RANGE-based frame (RANGE BETWEEN 29 PRECEDING AND CURRENT ROW) instead of ROWS.
--   Why: ROWS would count a fixed number of rows. Since dates can have
--   gaps or multiple transactions, only RANGE can correctly calculate a sliding 30-day calendar 
--   window. We convert the paid_date string to Julian Day numbers to enable numerical 
--   range framing in SQLite.
WITH daily_collections AS (
    SELECT p.merchant_id,
        i.paid_date,
        SUM(i.paid_amount_usd) AS collected_that_day,
        julianday(i.paid_date) AS paid_day_num
    FROM plans p
        JOIN installments i ON p.plan_id = i.plan_id
    WHERE i.paid_date IS NOT NULL
        AND i.paid_date != ''
    GROUP BY 1,
        2
)
SELECT merchant_id,
    paid_date,
    collected_that_day,
    SUM(collected_that_day) OVER (
        PARTITION BY merchant_id
        ORDER BY paid_day_num RANGE BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30d_collected
FROM daily_collections
ORDER BY 1,
    2;
-- A4 — Seasoned vs. naive merchant delinquency ranking. (Stretch)
--
-- Why naive rate favors recent orders:
--   A naive delinquency rate counts all installments in the denominator, including those due in the future.
--   Because future installments have had no time to default, a high volume of recent plans artificially 
--   inflates the denominator and dilutes the measured risk, favoring fast-growing merchants.
--
WITH merchant_metrics AS (
SELECT m.merchant_id,
    m.name,
    -- Naive: Count defaults over all installments ever generated
    CAST(
        SUM(
            CASE
                WHEN i.status IN ('late', 'missed', 'written_off') THEN 1
                ELSE 0
            END
        ) AS REAL
    ) / NULLIF(COUNT(i.installment_id), 0) AS naive_rate,
    -- Seasoned: Count defaults over matured installments only (due on or before TODAY)
    CAST(
        SUM(
            CASE
                WHEN i.status IN ('late', 'missed', 'written_off') THEN 1
                ELSE 0
            END
        ) AS REAL
    ) / NULLIF(
        SUM(
            CASE
                WHEN i.due_date <= '2026-07-01' THEN 1
                ELSE 0
            END
        ),
        0
    ) AS seasoned_rate
FROM merchants m
    LEFT JOIN plans p ON m.merchant_id = p.merchant_id
    LEFT JOIN installments i ON p.plan_id = i.plan_id
GROUP BY 1,
    2
),
ranked_metrics AS (
    SELECT merchant_id,
        name,
        ROUND(COALESCE(naive_rate, 0.0), 4) AS naive_rate,
        RANK() OVER (
            ORDER BY COALESCE(naive_rate, 0.0) DESC
        ) AS naive_rank,
        ROUND(COALESCE(seasoned_rate, 0.0), 4) AS seasoned_rate,
        RANK() OVER (
            ORDER BY COALESCE(seasoned_rate, 0.0) DESC
        ) AS seasoned_rank
    FROM merchant_metrics
)
SELECT merchant_id,
    name,
    naive_rate,
    naive_rank,
    seasoned_rate,
    seasoned_rank,
    (naive_rank - seasoned_rank) AS rank_delta
FROM ranked_metrics
ORDER BY ABS(rank_delta) DESC,
    seasoned_rank ASC;