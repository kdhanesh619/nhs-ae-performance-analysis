SELECT period_date, source_file, rows_loaded, sums_match_total_row
FROM stg_load_log;

SELECT m.org_code, m.org_name
FROM stg_ae_monthly m
LEFT JOIN stg_icb_mapping x ON x.org_code = m.org_code
WHERE x.org_code IS NULL;

SELECT period_date,
       ROUND(100.0 * (1 - SUM(COALESCE(over4_type1,0) + COALESCE(over4_type2,0) + COALESCE(over4_other,0)
                            + COALESCE(over4_booked_type1,0) + COALESCE(over4_booked_type2,0) + COALESCE(over4_booked_other,0))::numeric
                        / NULLIF(SUM(COALESCE(att_type1,0) + COALESCE(att_type2,0) + COALESCE(att_other,0)
                                   + COALESCE(att_booked_type1,0) + COALESCE(att_booked_type2,0) + COALESCE(att_booked_other,0)), 0)), 2)
         AS pct_within_4h_all_types
FROM stg_ae_monthly
GROUP BY period_date;

SELECT period_date, COUNT(*) AS orgs
FROM stg_ae_monthly
GROUP BY period_date
ORDER BY period_date;

SELECT period_date, source_file, rows_loaded, sums_match_total_row
FROM stg_load_log
ORDER BY period_date;

SELECT period_date, source_file, rows_loaded, total_row_found, sums_match_total_row
FROM stg_load_log
ORDER BY period_date;

SELECT * FROM stg_ae_monthly WHERE org_code = 'TOTAL';

SELECT period_date,
       SUM(COALESCE(att_type1,0) + COALESCE(att_type2,0) + COALESCE(att_other,0)
         + COALESCE(att_booked_type1,0) + COALESCE(att_booked_type2,0) + COALESCE(att_booked_other,0)) AS attendances_all_types,
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