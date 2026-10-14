-- 02_validate.sql
-- Checks to run after loading. Run each query on its own (select it, then Cmd+Enter in DBeaver).

-- 1. What was loaded, and did each file's organisation rows add up to its own TOTAL row?
SELECT period_date, source_file, rows_loaded, total_row_found, sums_match_total_row, notes, loaded_at
FROM stg_load_log
ORDER BY loaded_at DESC;

-- 2. Rows and distinct organisations per month.
SELECT period_date,
       COUNT(*)                   AS rows,
       COUNT(DISTINCT org_code)   AS organisations,
       COUNT(*) FILTER (WHERE LENGTH(org_code) = 3) AS three_char_codes   -- mostly NHS trusts
FROM stg_ae_monthly
GROUP BY period_date
ORDER BY period_date;

-- 3. Independent check against each file's TOTAL row.
--    total_abs_difference must be 0. Anything else means a row was lost or counted twice.
WITH s AS (
    SELECT period_date,
           SUM(att_type1) att_type1, SUM(att_type2) att_type2, SUM(att_other) att_other,
           SUM(att_booked_type1) att_booked_type1, SUM(att_booked_type2) att_booked_type2,
           SUM(att_booked_other) att_booked_other,
           SUM(over4_type1) over4_type1, SUM(over4_type2) over4_type2, SUM(over4_other) over4_other,
           SUM(over4_booked_type1) over4_booked_type1, SUM(over4_booked_type2) over4_booked_type2,
           SUM(over4_booked_other) over4_booked_other,
           SUM(dta_4_to_12h) dta_4_to_12h, SUM(dta_12h_plus) dta_12h_plus,
           SUM(emerg_adm_type1) emerg_adm_type1, SUM(emerg_adm_type2) emerg_adm_type2,
           SUM(emerg_adm_other) emerg_adm_other, SUM(other_emerg_adm) other_emerg_adm
    FROM stg_ae_monthly
    GROUP BY period_date
)
SELECT s.period_date,
       ABS(COALESCE(s.att_type1,0) - COALESCE(t.att_type1,0))
     + ABS(COALESCE(s.att_type2,0) - COALESCE(t.att_type2,0))
     + ABS(COALESCE(s.att_other,0) - COALESCE(t.att_other,0))
     + ABS(COALESCE(s.att_booked_type1,0) - COALESCE(t.att_booked_type1,0))
     + ABS(COALESCE(s.att_booked_type2,0) - COALESCE(t.att_booked_type2,0))
     + ABS(COALESCE(s.att_booked_other,0) - COALESCE(t.att_booked_other,0))
     + ABS(COALESCE(s.over4_type1,0) - COALESCE(t.over4_type1,0))
     + ABS(COALESCE(s.over4_type2,0) - COALESCE(t.over4_type2,0))
     + ABS(COALESCE(s.over4_other,0) - COALESCE(t.over4_other,0))
     + ABS(COALESCE(s.over4_booked_type1,0) - COALESCE(t.over4_booked_type1,0))
     + ABS(COALESCE(s.over4_booked_type2,0) - COALESCE(t.over4_booked_type2,0))
     + ABS(COALESCE(s.over4_booked_other,0) - COALESCE(t.over4_booked_other,0))
     + ABS(COALESCE(s.dta_4_to_12h,0) - COALESCE(t.dta_4_to_12h,0))
     + ABS(COALESCE(s.dta_12h_plus,0) - COALESCE(t.dta_12h_plus,0))
     + ABS(COALESCE(s.emerg_adm_type1,0) - COALESCE(t.emerg_adm_type1,0))
     + ABS(COALESCE(s.emerg_adm_type2,0) - COALESCE(t.emerg_adm_type2,0))
     + ABS(COALESCE(s.emerg_adm_other,0) - COALESCE(t.emerg_adm_other,0))
     + ABS(COALESCE(s.other_emerg_adm,0) - COALESCE(t.other_emerg_adm,0)) AS total_abs_difference
FROM s
LEFT JOIN stg_ae_monthly_total t USING (period_date)
ORDER BY s.period_date;

-- 4. Organisations in the monthly data that have no ICB / region in the mapping file.
SELECT m.org_code, m.org_name, COUNT(*) AS months_present
FROM stg_ae_monthly m
LEFT JOIN stg_icb_mapping x ON x.org_code = m.org_code
WHERE x.org_code IS NULL
GROUP BY m.org_code, m.org_name
ORDER BY m.org_code;

-- 5. Headline 4-hour performance by month, calculated from the organisation rows.
--    Check it against NHS England's published figures (see the statistical commentary PDF).
--    All types = Type 1 + Type 2 + other A&E, including booked appointments.
SELECT period_date,
       SUM(COALESCE(att_type1,0) + COALESCE(att_type2,0) + COALESCE(att_other,0)
         + COALESCE(att_booked_type1,0) + COALESCE(att_booked_type2,0) + COALESCE(att_booked_other,0)) AS attendances_all_types,
       SUM(COALESCE(over4_type1,0) + COALESCE(over4_type2,0) + COALESCE(over4_other,0)
         + COALESCE(over4_booked_type1,0) + COALESCE(over4_booked_type2,0) + COALESCE(over4_booked_other,0)) AS over_4h_all_types,
       ROUND(100.0 * (1 - SUM(COALESCE(over4_type1,0) + COALESCE(over4_type2,0) + COALESCE(over4_other,0)
                            + COALESCE(over4_booked_type1,0) + COALESCE(over4_booked_type2,0) + COALESCE(over4_booked_other,0))::numeric
                        / NULLIF(SUM(COALESCE(att_type1,0) + COALESCE(att_type2,0) + COALESCE(att_other,0)
                                   + COALESCE(att_booked_type1,0) + COALESCE(att_booked_type2,0) + COALESCE(att_booked_other,0)), 0)), 2)
         AS pct_within_4h_all_types,
       ROUND(100.0 * (1 - SUM(COALESCE(over4_type1,0) + COALESCE(over4_booked_type1,0))::numeric
                        / NULLIF(SUM(COALESCE(att_type1,0) + COALESCE(att_booked_type1,0)), 0)), 2)
         AS pct_within_4h_type1
FROM stg_ae_monthly
GROUP BY period_date
ORDER BY period_date;
