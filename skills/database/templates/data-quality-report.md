# Data Quality Audit Report

**Database**: [DATABASE_NAME]
**Date**: YYYY-MM-DD
**Auditor**: [NAME]
**Scope**: [tables/schemas audited]

---

## Executive Summary

[1-3 sentences: overall data quality status, critical findings count, recommended priority actions.]

## Findings

### Null Analysis

| Table | Column | Total Rows | Null Count | Null % | Severity | Expected? |
|-------|--------|-----------|------------|--------|----------|-----------|
| | | | | | | |

**Recommendations:**
- [ ] [Column] — backfill with [default], then add NOT NULL constraint
- [ ] [Column] — acceptable; document as intentionally nullable

### Duplicate Detection

| Table | Key Columns | Duplicate Groups | Total Duplicate Rows | Severity |
|-------|------------|-----------------|---------------------|----------|
| | | | | |

**Recommendations:**
- [ ] Deduplicate [table] using ROW_NUMBER (keep latest by [column])
- [ ] Add UNIQUE constraint on [columns] after cleanup

### Orphaned Records

| Child Table | FK Column | Parent Table | Orphan Count | Severity |
|-------------|-----------|-------------|-------------|----------|
| | | | | |

**Recommendations:**
- [ ] Delete orphaned rows in [table]
- [ ] Add FOREIGN KEY constraint with ON DELETE CASCADE/SET NULL

### Range Violations

| Table | Column | Constraint | Violation Count | Min Value | Max Value | Severity |
|-------|--------|-----------|----------------|-----------|-----------|----------|
| | | | | | | |

**Recommendations:**
- [ ] Fix invalid values in [column]
- [ ] Add CHECK constraint: `CHECK ([column] BETWEEN [min] AND [max])`

### Referential Integrity

| Relationship | Status | Issues |
|-------------|--------|--------|
| [parent] -> [child] | OK / BROKEN | [details] |

### Staleness

| Table | Last Insert/Update | Row Count | Status |
|-------|-------------------|-----------|--------|
| | | | Active / Stale / Abandoned |

---

## Severity Legend

| Level | Meaning | Action |
|-------|---------|--------|
| CRITICAL | Data corruption or loss risk | Fix immediately |
| HIGH | Constraint violations, broken FKs | Fix this sprint |
| MEDIUM | Unexpected nulls, duplicates | Schedule fix |
| LOW | Cosmetic, stale data | Track for next audit |

## Remediation Plan

| # | Finding | Severity | Owner | Target Date | Status |
|---|---------|----------|-------|-------------|--------|
| 1 | | | | | TODO |
| 2 | | | | | TODO |

## Appendix: Queries Used

```sql
-- Paste the exact queries used for reproducibility
```
