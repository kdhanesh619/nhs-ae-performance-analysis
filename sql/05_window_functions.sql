-- 05_window_functions.sql
-- Month-on-month change in England's 4-hour A&E performance (all types, May 2025 to April 2026).
-- LAG() looks at the previous month's value so each row can show the change in percentage points.
-- Result: lowest month January 2026 (72.45%), biggest monthly fall January 2026 (-1.39 points),
-- biggest monthly rise March 2026 (+3.05 points).

WITH monthly AS (
    SELECT period_date,
           ROUND(100.0 * (1 - SUM(over4_all_types)::numeric / NULLIF(SUM(att_all_types), 0)), 2) AS pct_all
    FROM v_ae_monthly
    GROUP BY period_date
)
SELECT period_date,
       pct_all,
       LAG(pct_all) OVER (ORDER BY period_date)                    AS prev_month,
       pct_all - LAG(pct_all) OVER (ORDER BY period_date)          AS change_in_points
FROM monthly
ORDER BY period_date;

