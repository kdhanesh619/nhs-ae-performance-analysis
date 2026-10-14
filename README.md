# NHS England A&E Performance Analysis (SQL + Power BI)

> **Status: in progress** (started 14 October 2026). Sections marked TODO are filled in as the work is done. Nothing below the "Key findings" heading is written until the analysis exists.

## Why this project

Emergency departments in England are measured against a 4-hour standard: the share of patients who are admitted, transferred or discharged within 4 hours of arriving. This project uses NHS England's public monthly data to ask where performance is weakest, how it has moved over time, and what the pressure looks like by trust and region.

## Business questions

1. How has 4-hour performance changed month by month, and how far is it from the current NHS target? (TODO: state the target and cite the NHS England commentary.)
2. Which trusts and regions are consistently best and worst, and which have improved most over the period?
3. How does the number of emergency admissions relate to 4-hour breaches, and does this differ by department type?
4. How strong is the winter effect? Compare the same months across years.

## Data

- **Source:** NHS England, *A&E Attendances and Emergency Admissions* monthly statistics: https://www.england.nhs.uk/statistics/statistical-work-areas/ae-waiting-times-and-activity/
- **Files used:** the monthly A&E CSVs in `data/raw` (the months actually loaded are recorded in the `stg_load_log` table) and NHS England's System Mapping file in `data/reference`. See `docs/data_dictionary.md` for the columns and the data-quality notes.
- **Licence / attribution:** TODO (confirm the licence on the NHS England page and state it here).
- **Data is aggregated by trust. It contains no patient-level or personal information.**

## Approach

1. Load the raw monthly CSVs into PostgreSQL staging tables (one script, rerunnable).
2. Clean and validate: data types, missing values, duplicate rows, trusts that appear or disappear, and a check that totals add up.
3. Analyse in SQL using joins, CTEs and window functions (month-on-month change, rolling averages, ranking by trust).
4. Model as a star schema (a fact table for monthly activity and dimensions for trust, region and date).
5. Build the Power BI report with DAX measures, then publish screenshots here.

## Repository structure

```
data/raw/         original monthly CSV files, unchanged
data/reference/   mapping file (provider to ICB and region)
scripts/          load_ae_data.py, the rerunnable loader
sql/              numbered scripts: 01_schema.sql, 02_validate.sql, then the analysis scripts
powerbi/          the .pbix file and exported screenshots
docs/             data dictionary and data-quality notes
```

## How to run

You need PostgreSQL running locally (for example Postgres.app on a Mac) and an empty database called `nhs_ae`.

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python scripts/load_ae_data.py --dbname nhs_ae
```

The loader creates the staging tables (`sql/01_schema.sql`), loads every CSV in `data/raw`, loads the mapping file from `data/reference`, and reports whether each month's organisation rows add up to that file's own TOTAL row. It can be run again at any time. Then run the queries in `sql/02_validate.sql`.

By default it connects to `localhost:5432` as your operating-system username. Use `--user`, `--host` or `--port` to change that.

## Validation so far

- For April 2026, the 190 organisation rows add up exactly to the file's TOTAL row on all 18 measures.
- The 4-hour performance calculated from the organisation rows is 76.91% (all types) and 63.83% (Type 1). NHS England's [May 2026 statistical commentary](https://www.england.nhs.uk/statistics/wp-content/uploads/sites/2/2026/06/Statistical-commentary-May-2026-sDl1e.pdf) quotes April 2026 as 76.9% and 63.8%, so the calculation matches the published figures.

## Progress

| Step | Share of project | Status |
|---|---|---|
| 1. Scope and questions | 5% | Done |
| 2. Setup: PostgreSQL, repo | 5% | PostgreSQL and database done; confirm repo is pushed |
| 3. Load raw data | 10% | In progress (loader written and tested on April 2026; add more months) |
| 4. Clean and validate | 15% | TODO |
| 5. SQL analysis | 25% | TODO |
| 6. Star schema | 10% | TODO |
| 7. Power BI report | 20% | TODO |
| 8. README, findings, publish | 10% | TODO |

## Key findings

TODO (only after the analysis is complete).

## Limitations

TODO

## Author

Dhanesh Kanakaraj, MSc Data Science, University of Hertfordshire. [LinkedIn](https://www.linkedin.com/in/dhanesh-kanakaraj/)
