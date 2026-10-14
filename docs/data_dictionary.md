# Data dictionary and data-quality notes

Source: NHS England, *A&E Attendances and Emergency Admissions* monthly statistics (one CSV per month) and the *System Mapping* file (providers to ICBs and regions). Every row is a count for one organisation in one month. There is no patient-level data.

## Table `stg_ae_monthly` (one row per organisation per month)

| Column | Meaning |
|---|---|
| `period_date` | First day of the reporting month, parsed from the file's `Period` value (e.g. `MSitAE-APRIL-2026`). |
| `org_code` | ODS organisation code, upper case. |
| `parent_org` | NHS England region as published (trailing spaces removed). |
| `org_name` | Organisation name as published. |
| `att_type1`, `att_type2`, `att_other` | A&E attendances by department type. Type 1 = major, consultant-led 24-hour A&E. Type 2 = single-specialty A&E (for example eye or dental). Other = walk-in centres, minor injury units and urgent treatment centres. |
| `att_booked_*` | Attendances that were booked appointments, same three department types. |
| `over4_*` | Attendances that took longer than 4 hours (from arrival to admission, transfer or discharge), same six groups. |
| `dta_4_to_12h`, `dta_12h_plus` | Patients who waited 4 to 12 hours, or over 12 hours, from decision to admit (DTA) to being admitted. |
| `emerg_adm_type1`, `emerg_adm_type2`, `emerg_adm_other` | Emergency admissions that came through A&E, by department type. |
| `other_emerg_adm` | Other emergency admissions (not through A&E). |
| `source_file` | The CSV the row came from. |

The department-type descriptions summarise NHS England's standard definitions. Check them against NHS England's own guidance before quoting them in the final write-up.

## Other tables

- `stg_ae_monthly_total`: the `TOTAL` row from each CSV, kept apart so it is never added to the organisation rows.
- `stg_icb_mapping`: provider code to ICB code, ICB name and region name.
- `stg_load_log`: one row per file loaded, with whether the organisation rows added up to the file's TOTAL row.

## Data-quality notes found in the April 2026 file

1. **The file ends with a `TOTAL` row.** Left in, it would double every sum. The loader stores it separately.
2. **Organisation rows add up exactly to that TOTAL row** for all 18 measures, which is used as a built-in check on every load.
3. **`Parent Org` has inconsistent trailing spaces** (for example `NHS ENGLAND MIDLANDS ` against `NHS ENGLAND LONDON`). Trimmed on load.
4. **Column headings are not consistently worded** (for example "Other A&E Department" and "Other Department", and "4-12 hs"). The loader accepts known spellings and stops with a clear error on any heading it does not recognise.
5. **Organisation codes are a mix of 3-character codes (mostly NHS trusts) and 5 or 6-character codes** (walk-in centres, GP-led sites, community providers). Many of the 5 and 6-character providers report no Type 1 activity, so trust-level comparisons should be made on Type 1 where appropriate.
6. **Organisation names can change** (for example a site renamed in April 2026). Code is the key; names are descriptive.
7. **Mapping file:** one provider code appears twice with identical details (`NNFA7`) and one code differs only in case from the monthly data (`NTV0b` against `NTV0B`). The loader ignores the identical duplicate and upper-cases codes before joining.
