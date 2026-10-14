-- 01_schema.sql
-- Staging tables for the NHS England monthly A&E data.
-- Safe to run more than once (CREATE TABLE IF NOT EXISTS).
-- The loader script (scripts/load_ae_data.py) runs this file automatically.

-- One row per organisation per month, exactly as published, with tidy column names.
CREATE TABLE IF NOT EXISTS stg_ae_monthly (
    period_date                   date    NOT NULL,   -- first day of the reporting month
    org_code                      text    NOT NULL,   -- ODS code, upper case, trimmed
    parent_org                    text,               -- NHS England region as published, trimmed
    org_name                      text,
    -- A&E attendances
    att_type1                     integer,
    att_type2                     integer,
    att_other                     integer,            -- Type 3 / other A&E departments
    att_booked_type1              integer,
    att_booked_type2              integer,
    att_booked_other              integer,
    -- Attendances that took longer than 4 hours
    over4_type1                   integer,
    over4_type2                   integer,
    over4_other                   integer,
    over4_booked_type1            integer,
    over4_booked_type2            integer,
    over4_booked_other            integer,
    -- Waits from decision to admit (DTA) to admission
    dta_4_to_12h                  integer,
    dta_12h_plus                  integer,
    -- Emergency admissions
    emerg_adm_type1               integer,
    emerg_adm_type2               integer,
    emerg_adm_other               integer,
    other_emerg_adm               integer,            -- emergency admissions not via A&E
    source_file                   text    NOT NULL,
    loaded_at                     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (period_date, org_code)
);

-- The TOTAL row from each file, kept separately so we can check our sums against it.
-- It must never be mixed into stg_ae_monthly, or every total would be counted twice.
CREATE TABLE IF NOT EXISTS stg_ae_monthly_total (
    period_date                   date    PRIMARY KEY,
    att_type1                     integer,
    att_type2                     integer,
    att_other                     integer,
    att_booked_type1              integer,
    att_booked_type2              integer,
    att_booked_other              integer,
    over4_type1                   integer,
    over4_type2                   integer,
    over4_other                   integer,
    over4_booked_type1            integer,
    over4_booked_type2            integer,
    over4_booked_other            integer,
    dta_4_to_12h                  integer,
    dta_12h_plus                  integer,
    emerg_adm_type1               integer,
    emerg_adm_type2               integer,
    emerg_adm_other               integer,
    other_emerg_adm               integer,
    source_file                   text    NOT NULL,
    loaded_at                     timestamptz NOT NULL DEFAULT now()
);

-- Provider to ICB (Integrated Care Board) and region, from NHS England's System Mapping file.
CREATE TABLE IF NOT EXISTS stg_icb_mapping (
    org_code                      text    PRIMARY KEY, -- upper case, trimmed
    org_name                      text,
    icb_code                      text,
    icb_name                      text,
    region_name                   text,
    source_file                   text    NOT NULL,
    loaded_at                     timestamptz NOT NULL DEFAULT now()
);

-- One row per file loaded, so every load is traceable.
CREATE TABLE IF NOT EXISTS stg_load_log (
    log_id                        bigserial PRIMARY KEY,
    source_file                   text    NOT NULL,
    period_date                   date,
    rows_loaded                   integer,
    total_row_found               boolean,
    sums_match_total_row          boolean,            -- do the org rows add up to the TOTAL row?
    notes                         text,
    loaded_at                     timestamptz NOT NULL DEFAULT now()
);
