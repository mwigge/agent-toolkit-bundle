# Migration Runbook: [MIGRATION_NAME]

**Date**: YYYY-MM-DD
**Author**: [NAME]
**Ticket**: <PROJ>-[N]
**Engine**: PostgreSQL / MySQL / SQLite

---

## Summary

Brief description of the schema change and its purpose.

## Risk Assessment

| Factor | Value |
|--------|-------|
| Tables affected | [list] |
| Estimated rows | [count] |
| Downtime required | None / Brief / Extended |
| Rollback complexity | Low / Medium / High |
| Replication lag risk | Low / Medium / High |

## Pre-Flight Checks

- [ ] Migration tested on staging with production-size data
- [ ] Rollback script tested on staging
- [ ] Backfill batch size tuned (target < 1s per batch)
- [ ] Monitoring dashboards open (replication lag, lock waits, CPU)
- [ ] Off-peak window confirmed
- [ ] Team notified

## Phase 1: Expand

```sql
-- Add new column/table (non-breaking)
-- TODO: paste DDL here
```

**Verification:**
```sql
-- Confirm new column/table exists
-- TODO: paste verification query
```

## Phase 2: Migrate (Backfill)

```sql
-- Backfill in batches
-- TODO: paste backfill script
```

**Monitoring during backfill:**
- Replication lag: must stay below [N] seconds
- Lock wait time: must stay below [N] ms
- Batch timing: target [N] ms per batch

**Verification:**
```sql
-- Confirm all rows backfilled
SELECT COUNT(*) FROM target_table WHERE new_col IS NULL;
-- Expected: 0
```

## Phase 3: Contract

Only execute after code is deployed reading from the new column/table.

```sql
-- Drop old column/table
-- TODO: paste DDL here
```

**Verification:**
```sql
-- Confirm old column/table removed
-- TODO: paste verification query
```

## Rollback Procedure

### Phase 1 Rollback (Expand)
```sql
-- Drop the new column/table
-- TODO: paste rollback DDL
```

### Phase 2 Rollback (Migrate)
```sql
-- Old column still exists; redeploy code using old column
-- No DDL rollback needed
```

### Phase 3 Rollback (Contract)
```sql
-- Requires restore from backup — this phase is irreversible
-- Ensure Phase 2 verification passed before entering Phase 3
```

## Post-Migration

- [ ] Run `ANALYZE` on affected tables
- [ ] Verify query plans have not regressed
- [ ] Check application error rates for 30 minutes
- [ ] Update schema documentation
- [ ] Archive this runbook in version control
