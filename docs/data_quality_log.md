# Data quality log

Checks run on the 12 months of NHS England A&E data loaded into PostgreSQL (May 2025 to April 2026), using `sql/03_clean_validate.sql`. Run on 21 October 2026.

Earlier validation (see `sql/02_validate.sql`): every month reconciles to its source file's TOTAL row, and the April 2026 4-hour performance (76.91%, all types) matches NHS England's published 76.9%.

| # | Check | Result | Decision |
|---|-------|--------|----------|
| 1 | Missing values (NULLs) per month | No NULLs in any checked measure in any month. Organisation rows per month: 200 (May 2025), 201 (Jun to Sep), 197 (Oct to Feb), 199 (Mar 2026), 190 (Apr 2026). | None needed. |
| 2 | Impossible values (negative counts, or more breaches than attendances including booked appointments) | No rows returned. | None needed. |
| 3 | Organisations appearing or disappearing between consecutive months | 20 changes, which fully explain the monthly counts above. Almost all are walk-in, urgent care or community providers. NNJ10 (Enderby Leisure Centre) and NNJ11 (Lutterworth Hospital) appear in March 2026 only. April 2026 has 9 fewer organisations than March. | Keep all organisations. Note that April 2026 is not strictly like-for-like with earlier months. Use Type 1 for trust-level comparisons. |
| 4 | Organisations whose name changes | 6 organisation codes have two names: A5D4Q, NNJ15, RA2, RRF, RWH, RWW. All are renames or wording changes. | Use `org_code` as the key. For display, use the name from the most recent month (not `MAX(org_name)`, which picks the alphabetically last name). |
| 5 | Organisations with no Type 1 (major A&E) activity in any month | 84 organisations, such as walk-in centres, urgent treatment centres, minor injuries units and community services. | Keep them in all-types totals. Filter on `has_type1` for trust-level comparisons. |
| 6 | Month-on-month swings of more than 30% in Type 1 attendances (organisations with at least 1,000 attendances) | One case: RQ3 Birmingham Women's and Children's NHS Foundation Trust, September 2025, 3,491 to 4,565 (+30.8%). Its 12-month series is smooth: attendances fall to a low in August 2025 and recover in September, which looks like a seasonal pattern and not a data error. | No action. Treated as genuine. |

## Notes for the analysis

- Headline 4-hour performance (all types, England) was highest in July 2025 (76.41%), lowest in January 2026 (72.45%), and recovered to 76.91% by April 2026.
- Type 1 (major A&E) performance is lower throughout (57.32% to 64.09%).
- At trust level, 4-hour performance appears to move the opposite way to attendance volume (for example RQ3: 95.56% in August 2025 with the lowest attendances, 71.29% in December 2025). This is an observation to examine further, not a tested conclusion.
