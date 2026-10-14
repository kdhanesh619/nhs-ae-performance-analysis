#!/usr/bin/env python3
"""
Load NHS England monthly A&E CSV files, and the provider-to-ICB mapping file,
into PostgreSQL staging tables.

What it does
  1. Runs sql/01_schema.sql (creates the staging tables if they do not exist).
  2. Loads every CSV in data/raw into stg_ae_monthly. The TOTAL row at the bottom
     of each file goes to stg_ae_monthly_total, never into the main table.
  3. Checks that the organisation rows add up to the TOTAL row, per month.
  4. Loads the newest mapping file in data/reference into stg_icb_mapping.

Safe to run again: each month is replaced, not duplicated.

Usage (from the project root, with the virtual environment active)
    python scripts/load_ae_data.py
    python scripts/load_ae_data.py --dbname nhs_ae --user your_mac_username

Needs:  pip install psycopg2-binary xlrd
"""
import argparse
import csv
import getpass
import os
import re
import sys
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values

ROOT = Path(__file__).resolve().parent.parent

MONTHS = {name: i for i, name in enumerate(
    ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST",
     "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"], start=1)}

# Database column -> accepted CSV headers (compared in lower case, spaces collapsed).
# NHS England is not fully consistent in its wording, so a few spellings are accepted.
MEASURES = {
    "att_type1": ["a&e attendances type 1"],
    "att_type2": ["a&e attendances type 2"],
    "att_other": ["a&e attendances other a&e department", "a&e attendances other department"],
    "att_booked_type1": ["a&e attendances booked appointments type 1"],
    "att_booked_type2": ["a&e attendances booked appointments type 2"],
    "att_booked_other": ["a&e attendances booked appointments other department",
                         "a&e attendances booked appointments other a&e department"],
    "over4_type1": ["attendances over 4hrs type 1"],
    "over4_type2": ["attendances over 4hrs type 2"],
    "over4_other": ["attendances over 4hrs other department",
                    "attendances over 4hrs other a&e department"],
    "over4_booked_type1": ["attendances over 4hrs booked appointments type 1"],
    "over4_booked_type2": ["attendances over 4hrs booked appointments type 2"],
    "over4_booked_other": ["attendances over 4hrs booked appointments other department",
                           "attendances over 4hrs booked appointments other a&e department"],
    "dta_4_to_12h": ["patients who have waited 4-12 hs from dta to admission",
                     "patients who have waited 4-12 hrs from dta to admission"],
    "dta_12h_plus": ["patients who have waited 12+ hrs from dta to admission"],
    "emerg_adm_type1": ["emergency admissions via a&e - type 1"],
    "emerg_adm_type2": ["emergency admissions via a&e - type 2"],
    "emerg_adm_other": ["emergency admissions via a&e - other a&e department",
                        "emergency admissions via a&e - other department"],
    "other_emerg_adm": ["other emergency admissions"],
}
ID_HEADERS = {"period": "period", "org code": "org_code",
              "parent org": "parent_org", "org name": "org_name"}

HEADER_TO_COLUMN = dict(ID_HEADERS)
for column, names in MEASURES.items():
    for name in names:
        HEADER_TO_COLUMN[name] = column

MEASURE_COLUMNS = list(MEASURES)
MONTHLY_COLUMNS = ["period_date", "org_code", "parent_org", "org_name"] + MEASURE_COLUMNS + ["source_file"]
TOTAL_COLUMNS = ["period_date"] + MEASURE_COLUMNS + ["source_file"]


def norm(text):
    return re.sub(r"\s+", " ", text.strip().lower())


def to_int(text):
    text = (text or "").strip().replace(",", "")
    if text in ("", "-"):
        return None
    return int(float(text))


def parse_period(label):
    """'MSitAE-APRIL-2026' -> date(2026, 4, 1)."""
    from datetime import date
    match = re.match(r"^MSitAE-([A-Za-z]+)-(\d{4})$", label.strip())
    if not match or match.group(1).upper() not in MONTHS:
        raise ValueError(f"Cannot read the month from Period value '{label}'")
    return date(int(match.group(2)), MONTHS[match.group(1).upper()], 1)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        return path.read_text(encoding="cp1252")


def parse_monthly_csv(path):
    """Return (period_date, org_rows, total_row_or_None, missing_columns)."""
    lines = read_text(path).splitlines()
    reader = csv.reader(lines)
    header = next(reader)
    mapped = [HEADER_TO_COLUMN.get(norm(h)) for h in header]
    unknown = [h for h, m in zip(header, mapped) if m is None]
    if unknown:
        raise ValueError("Unrecognised column(s): " + "; ".join(unknown))
    for needed in ("period", "org_code"):
        if needed not in mapped:
            raise ValueError(f"Required column '{needed}' is missing")
    missing = [c for c in MEASURE_COLUMNS if c not in mapped]

    org_rows, total_row, periods = [], None, set()
    for number, cells in enumerate(reader, start=2):
        if not any(c.strip() for c in cells):
            continue  # blank line
        record = dict(zip(mapped, cells))
        label = record["period"].strip()
        if label.upper() == "TOTAL":
            total_row = {c: to_int(record.get(c)) for c in MEASURE_COLUMNS}
            continue
        periods.add(label)
        row = {
            "org_code": record["org_code"].strip().upper(),
            "parent_org": (record.get("parent_org") or "").strip() or None,
            "org_name": (record.get("org_name") or "").strip() or None,
        }
        for c in MEASURE_COLUMNS:
            row[c] = to_int(record[c]) if c in record else None
        org_rows.append(row)

    if len(periods) != 1:
        raise ValueError(f"Expected one period in the file, found: {sorted(periods)}")
    codes = [r["org_code"] for r in org_rows]
    duplicates = sorted({c for c in codes if codes.count(c) > 1})
    if duplicates:
        raise ValueError("Duplicate organisation codes in file: " + ", ".join(duplicates))
    return parse_period(periods.pop()), org_rows, total_row, missing


def sums_match(org_rows, total_row):
    """Compare the sum of the organisation rows with the file's own TOTAL row."""
    if total_row is None:
        return None, "no TOTAL row in file"
    bad = []
    for c in MEASURE_COLUMNS:
        if total_row[c] is None:
            continue
        added = sum((r[c] or 0) for r in org_rows)
        if added != total_row[c]:
            bad.append(f"{c}: rows add to {added}, TOTAL row says {total_row[c]}")
    return (not bad), ("; ".join(bad) if bad else None)


def load_monthly_file(conn, path):
    period_date, org_rows, total_row, missing = parse_monthly_csv(path)
    matched, detail = sums_match(org_rows, total_row)
    notes = []
    if missing:
        notes.append("columns not in this file (stored as NULL): " + ", ".join(missing))
    if detail:
        notes.append(detail)

    with conn.cursor() as cur:
        cur.execute("DELETE FROM stg_ae_monthly WHERE period_date = %s", (period_date,))
        cur.execute("DELETE FROM stg_ae_monthly_total WHERE period_date = %s", (period_date,))
        execute_values(
            cur,
            f"INSERT INTO stg_ae_monthly ({', '.join(MONTHLY_COLUMNS)}) VALUES %s",
            [[period_date, r["org_code"], r["parent_org"], r["org_name"]]
             + [r[c] for c in MEASURE_COLUMNS] + [path.name] for r in org_rows],
        )
        if total_row is not None:
            execute_values(
                cur,
                f"INSERT INTO stg_ae_monthly_total ({', '.join(TOTAL_COLUMNS)}) VALUES %s",
                [[period_date] + [total_row[c] for c in MEASURE_COLUMNS] + [path.name]],
            )
        cur.execute(
            "INSERT INTO stg_load_log (source_file, period_date, rows_loaded, total_row_found, "
            "sums_match_total_row, notes) VALUES (%s, %s, %s, %s, %s, %s)",
            (path.name, period_date, len(org_rows), total_row is not None, matched,
             "; ".join(notes) or None),
        )
    conn.commit()
    return period_date, len(org_rows), matched, notes


def read_sheet_rows(path):
    """Return the first worksheet as a list of lists of strings (.xls or .xlsx)."""
    if path.suffix.lower() == ".xls":
        import xlrd
        sheet = xlrd.open_workbook(str(path)).sheet_by_index(0)
        return [[str(v).strip() for v in sheet.row_values(r)] for r in range(sheet.nrows)]
    import openpyxl  # only needed for .xlsx
    sheet = openpyxl.load_workbook(path, read_only=True, data_only=True).worksheets[0]
    return [["" if v is None else str(v).strip() for v in row] for row in sheet.iter_rows(values_only=True)]


def load_mapping_file(conn, path):
    rows = read_sheet_rows(path)
    header_at = next((i for i, r in enumerate(rows)
                      if "code" in [norm(c) for c in r] and "icb code" in [norm(c) for c in r]), None)
    if header_at is None:
        raise ValueError("Could not find the header row (Code, Name, ICB Code, ICB Name, Region Name)")
    names = [norm(c) for c in rows[header_at]]
    index = {n: names.index(n) for n in ("code", "name", "icb code", "icb name", "region name")}

    seen, records, dropped = {}, [], 0
    for r in rows[header_at + 1:]:
        code = r[index["code"]].strip().upper() if len(r) > index["code"] else ""
        if not code:
            continue
        record = (code, r[index["name"]], r[index["icb code"]], r[index["icb name"]],
                  r[index["region name"]], path.name)
        if code in seen:
            if seen[code] != record:
                raise ValueError(f"Code {code} appears twice with different details")
            dropped += 1
            continue
        seen[code] = record
        records.append(record)

    with conn.cursor() as cur:
        cur.execute("TRUNCATE stg_icb_mapping")
        execute_values(
            cur,
            "INSERT INTO stg_icb_mapping (org_code, org_name, icb_code, icb_name, region_name, source_file) VALUES %s",
            records,
        )
    conn.commit()
    return len(records), dropped


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default=os.environ.get("PGHOST", "localhost"))
    parser.add_argument("--port", default=os.environ.get("PGPORT", "5432"))
    parser.add_argument("--dbname", default=os.environ.get("PGDATABASE", "nhs_ae"))
    parser.add_argument("--user", default=os.environ.get("PGUSER", getpass.getuser()))
    parser.add_argument("--raw-dir", default=str(ROOT / "data" / "raw"))
    parser.add_argument("--ref-dir", default=str(ROOT / "data" / "reference"))
    args = parser.parse_args()

    try:
        conn = psycopg2.connect(host=args.host, port=args.port, dbname=args.dbname, user=args.user)
    except psycopg2.OperationalError as error:
        sys.exit(f"Could not connect to PostgreSQL: {error}\n"
                 "Check that Postgres.app is open and running, and that --dbname / --user are right.")

    with conn.cursor() as cur:
        cur.execute((ROOT / "sql" / "01_schema.sql").read_text())
    conn.commit()
    print(f"Connected to database '{args.dbname}' as '{args.user}'. Tables are ready.\n")

    failures = 0
    csv_files = sorted(Path(args.raw_dir).glob("*.csv"))
    if not csv_files:
        print(f"No CSV files found in {args.raw_dir}")
    for path in csv_files:
        try:
            period, count, matched, notes = load_monthly_file(conn, path)
            status = "OK" if matched else ("CHECK" if matched is False else "NO TOTAL ROW")
            print(f"[{status:>12}] {path.name}: {period:%B %Y}, {count} organisations loaded")
            for note in notes:
                print(f"               note: {note}")
        except Exception as error:  # keep going with the other files
            conn.rollback()
            failures += 1
            print(f"[      FAILED] {path.name}: {error}")

    mapping_files = sorted(Path(args.ref_dir).glob("*.xls*"), key=lambda p: p.stat().st_mtime)
    if mapping_files:
        path = mapping_files[-1]
        try:
            count, dropped = load_mapping_file(conn, path)
            extra = f" ({dropped} identical duplicate row(s) ignored)" if dropped else ""
            print(f"\n[          OK] {path.name}: {count} provider-to-ICB rows loaded{extra}")
        except Exception as error:
            conn.rollback()
            failures += 1
            print(f"\n[      FAILED] {path.name}: {error}")
    else:
        print(f"\nNo mapping file (.xls or .xlsx) found in {args.ref_dir}")

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(DISTINCT period_date), COUNT(*) FROM stg_ae_monthly")
        months, rows = cur.fetchone()
    print(f"\nDatabase now holds {rows} organisation-month rows across {months} month(s).")
    conn.close()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
