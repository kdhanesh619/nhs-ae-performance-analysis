-- 04_clean_view.sql
-- A clean, analysis-ready view on top of the staging tables.
-- Run the whole script once (Alt+X in DBeaver, "Execute script"). It is safe to re-run.
--
-- What the view does:
--   * replaces NULL counts with 0 so sums are safe
--   * adds totals across department types (all types, and Type 1 on its own)
--   * adds the 4-hour performance percentage for each organisation and month
--   * joins the ICB and region from the mapping file (organisations with no mapping stay in, with NULLs)
--
-- Definitions (same as 02_validate.sql, and the figure that matched NHS England's April 2026 number):
--   attendances all types = Type 1 + Type 2 + other A&E, including booked appointments
--   within 4 hours %      = 100 * (1 - breaches / attendances)

CREATE OR REPLACE VIEW v_ae_monthly AS
SELECT
    m.period_date,
    m.org_code,
    m.org_name,
    m.parent_org                                              AS nhse_region_parent,
    x.icb_code,
    x.icb_name,
    x.region_name,

    COALESCE(m.att_type1, 0) + COALESCE(m.att_booked_type1, 0)   AS att_type1_all,
    COALESCE(m.att_type2, 0) + COALESCE(m.att_booked_type2, 0)   AS att_type2_all,
    COALESCE(m.att_other, 0) + COALESCE(m.att_booked_other, 0)   AS att_other_all,

    COALESCE(m.over4_type1, 0) + COALESCE(m.over4_booked_type1, 0) AS over4_type1_all,
    COALESCE(m.over4_type2, 0) + COALESCE(m.over4_booked_type2, 0) AS over4_type2_all,
    COALESCE(m.over4_other, 0) + COALESCE(m.over4_booked_other, 0) AS over4_other_all,

    COALESCE(m.att_type1, 0) + COALESCE(m.att_booked_type1, 0)
      + COALESCE(m.att_type2, 0) + COALESCE(m.att_booked_type2, 0)
      + COALESCE(m.att_other, 0) + COALESCE(m.att_booked_other, 0)   AS att_all_types,

    COALESCE(m.over4_type1, 0) + COALESCE(m.over4_booked_type1, 0)
      + COALESCE(m.over4_type2, 0) + COALESCE(m.over4_booked_type2, 0)
      + COALESCE(m.over4_other, 0) + COALESCE(m.over4_booked_other, 0) AS over4_all_types,

    COALESCE(m.dta_4_to_12h, 0)       AS dta_4_to_12h,
    COALESCE(m.dta_12h_plus, 0)       AS dta_12h_plus,
    COALESCE(m.emerg_adm_type1, 0)    AS emerg_adm_type1,
    COALESCE(m.emerg_adm_type2, 0)    AS emerg_adm_type2,
    COALESCE(m.emerg_adm_other, 0)    AS emerg_adm_other,
    COALESCE(m.other_emerg_adm, 0)    AS other_emerg_adm,

    -- 4-hour performance; NULL (not 0) when the organisation had no attendances
    ROUND(100.0 * (1 - (COALESCE(m.over4_type1, 0) + COALESCE(m.over4_booked_type1, 0)
                      + COALESCE(m.over4_type2, 0) + COALESCE(m.over4_booked_type2, 0)
                      + COALESCE(m.over4_other, 0) + COALESCE(m.over4_booked_other, 0))::numeric
                      / NULLIF(COALESCE(m.att_type1, 0) + COALESCE(m.att_booked_type1, 0)
                             + COALESCE(m.att_type2, 0) + COALESCE(m.att_booked_type2, 0)
                             + COALESCE(m.att_other, 0) + COALESCE(m.att_booked_other, 0), 0)), 2)
        AS pct_within_4h_all_types,

    ROUND(100.0 * (1 - (COALESCE(m.over4_type1, 0) + COALESCE(m.over4_booked_type1, 0))::numeric
                      / NULLIF(COALESCE(m.att_type1, 0) + COALESCE(m.att_booked_type1, 0), 0)), 2)
        AS pct_within_4h_type1,

    -- true for organisations that run a major (Type 1) A&E that month
    (COALESCE(m.att_type1, 0) + COALESCE(m.att_booked_type1, 0)) > 0 AS has_type1
FROM stg_ae_monthly m
LEFT JOIN stg_icb_mapping x ON x.org_code = m.org_code;

-- Check: this must reproduce the headline figures (April 2026 should be 76.91 and 63.83).
-- SELECT period_date,
--        ROUND(100.0 * (1 - SUM(over4_all_types)::numeric / NULLIF(SUM(att_all_types), 0)), 2) AS pct_all,
--        ROUND(100.0 * (1 - SUM(over4_type1_all)::numeric / NULLIF(SUM(att_type1_all), 0)), 2) AS pct_type1
-- FROM v_ae_monthly GROUP BY period_date ORDER BY period_date;
