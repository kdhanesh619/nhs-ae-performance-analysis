-- 03_clean_validate.sql
-- Data-quality checks on the loaded A&E data (Step 4: clean and validate).
-- Run each query on its own (click inside it, then Cmd+Enter in DBeaver).
-- For each check, note the result in docs/data_quality_log.md.

-- 1. Missing values: how many NULLs are there in each measure, per month?
--    A column that is NULL for a whole month usually means a heading was not recognised.
SELECT period_date,
       COUNT(*)                                                 AS org_rows,
       COUNT(*) FILTER (WHERE att_type1 IS NULL)                AS null_att_type1,
       COUNT(*) FILTER (WHERE att_booked_type1 IS NULL)         AS null_att_booked_type1,
       COUNT(*) FILTER (WHERE over4_type1 IS NULL)              AS null_over4_type1,
       COUNT(*) FILTER (WHERE over4_booked_type1 IS NULL)       AS null_over4_booked_type1,
       COUNT(*) FILTER (WHERE emerg_adm_type1 IS NULL)          AS null_emerg_adm_type1,
       COUNT(*) FILTER (WHERE dta_12h_plus IS NULL)             AS null_dta_12h_plus
FROM stg_ae_monthly
GROUP BY period_date
ORDER BY period_date;

-- 2. Impossible values: negative counts, or more breaches than attendances.
--    Expect no rows. Any row returned needs a decision: fix, exclude, or document.
SELECT period_date, org_code, org_name,
       att_type1, over4_type1, att_type2, over4_type2, att_other, over4_other
FROM stg_ae_monthly
WHERE LEAST(att_type1, att_type2, att_other, over4_type1, over4_type2, over4_other,
            att_booked_type1, att_booked_type2, att_booked_other,
            over4_booked_type1, over4_booked_type2, over4_booked_other,
            dta_4_to_12h, dta_12h_plus, emerg_adm_type1, emerg_adm_type2,
            emerg_adm_other, other_emerg_adm) < 0
   OR over4_type1 > att_type1 + COALESCE(att_booked_type1, 0)
   OR over4_type2 > att_type2 + COALESCE(att_booked_type2, 0)
   OR over4_other > att_other + COALESCE(att_booked_other, 0)
ORDER BY period_date, org_code;

-- 3. Organisations that appear or disappear between consecutive months.
--    Joins each month to the month before it. Mergers, closures and new services show up here.
WITH months AS (
    SELECT DISTINCT period_date FROM stg_ae_monthly
),
pairs AS (
    SELECT m.period_date,
           (SELECT MAX(p.period_date) FROM months p WHERE p.period_date < m.period_date) AS prev_period
    FROM months m
)
SELECT p.period_date,
       'new in this month' AS change,
       cur.org_code, cur.org_name
FROM pairs p
JOIN stg_ae_monthly cur ON cur.period_date = p.period_date
LEFT JOIN stg_ae_monthly prev ON prev.period_date = p.prev_period AND prev.org_code = cur.org_code
WHERE p.prev_period IS NOT NULL AND prev.org_code IS NULL
UNION ALL
SELECT p.period_date,
       'missing from this month',
       prev.org_code, prev.org_name
FROM pairs p
JOIN stg_ae_monthly prev ON prev.period_date = p.prev_period
LEFT JOIN stg_ae_monthly cur ON cur.period_date = p.period_date AND cur.org_code = prev.org_code
WHERE p.prev_period IS NOT NULL AND cur.org_code IS NULL
ORDER BY period_date, change, org_code;

-- 4. Organisations whose name changes across months (code is the key, names are descriptive).
SELECT org_code,
       COUNT(DISTINCT org_name)                    AS names_used,
       STRING_AGG(DISTINCT org_name, '  |  ')      AS names
FROM stg_ae_monthly
GROUP BY org_code
HAVING COUNT(DISTINCT org_name) > 1
ORDER BY org_code;

-- 5. Organisations that report no Type 1 (major A&E) activity at all in any month.
--    These are mostly walk-in centres and community services, so trust league tables should use Type 1.
SELECT org_code, MAX(org_name) AS org_name,
       SUM(COALESCE(att_type1, 0) + COALESCE(att_booked_type1, 0)) AS type1_attendances_all_months
FROM stg_ae_monthly
GROUP BY org_code
HAVING SUM(COALESCE(att_type1, 0) + COALESCE(att_booked_type1, 0)) = 0
ORDER BY org_code;

-- 6. Large month-on-month swings in a trust's Type 1 attendances (possible data errors or mergers).
--    Shows changes of more than 30% for organisations with at least 1,000 Type 1 attendances.
WITH t AS (
    SELECT period_date, org_code, MAX(org_name) AS org_name,
           SUM(COALESCE(att_type1, 0) + COALESCE(att_booked_type1, 0)) AS att1
    FROM stg_ae_monthly
    GROUP BY period_date, org_code
),
c AS (
    SELECT *, LAG(att1) OVER (PARTITION BY org_code ORDER BY period_date) AS prev_att1
    FROM t
)
SELECT period_date, org_code, org_name, prev_att1, att1,
       ROUND(100.0 * (att1 - prev_att1) / prev_att1, 1) AS pct_change
FROM c
WHERE prev_att1 >= 1000
  AND ABS(att1 - prev_att1) > 0.30 * prev_att1
ORDER BY ABS(att1 - prev_att1) DESC;
