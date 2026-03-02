# Operational Considerations for Multi-Tenant PostgreSQL

## Purpose

This project primarily demonstrates SECURITY isolation for multi-tenant PostgreSQL:
- database-per-tenant
- role-per-tenant
- dedicated schema-per-tenant
- hardened privileges

Operationally, multi-tenancy introduces shared resource risks even when security isolation is correct.

This document captures the operational realities of running Postgres in multi-tenant mode and the mitigations we expect in production (e.g., AWS RDS).

---

## Core Principle

Security isolation does not imply performance isolation.

All tenants share:
- CPU / memory / IOPS
- WAL throughput
- background workers (autovacuum, checkpointer, etc.)
- connection limits and internal memory structures
- storage and checkpoint behavior

A single “noisy tenant” can degrade all tenants without ever violating access controls.

---

## Primary Operational Risks and Mitigations

### 1. Connection Exhaustion (Shared Blast Radius)

Risk:
- A tenant opens too many connections (or leaks them), starving others.

Mitigations:
- Per-tenant role connection limits (CONNECTION LIMIT)
- External pooling (pgBouncer) using transaction pooling where possible
- App-level connection pool caps
- Alerting on DBConnections growth and saturation

Project guardrails:
- Each tenant role sets a CONNECTION LIMIT.
- Test suite validates that exceeding the per-role limit fails.

---

### 2. Runaway Queries and Unbounded Latency

Risk:
- A tenant issues expensive queries, or an application bug triggers long-running statements.

Mitigations:
- Per-role statement timeouts (statement_timeout)
- lock_timeout to avoid waiting forever on locks
- idle_in_transaction_session_timeout to prevent “idle in transaction” session leaks
- query monitoring and slow query logging (RDS logs + CloudWatch + SIEM)

Project guardrails:
- Each tenant role sets statement_timeout (and optionally lock/idle timeouts).
- Test suite validates a long `pg_sleep()` query is terminated.

---

### 3. Lock Contention and Transaction Hygiene

Risk:
- Long transactions block VACUUM/DDL and increase bloat, causing rising latency for everyone.

Mitigations:
- idle_in_transaction_session_timeout
- enforce short transactions at the application layer
- monitor locks (pg_locks) and long transactions (pg_stat_activity)
- routine maintenance policies

Project notes:
- We include recommended role-level timeouts.
- Full lock/bloat tuning is environment-specific and is documented as a production expectation.

---

### 4. Autovacuum, Bloat, and Storage Growth

Risk:
- High churn tables bloat; autovacuum can fall behind; shared storage grows and performance degrades.

Mitigations:
- Track dead tuples / autovacuum progress
- Per-tenant table design guidance (indexes, churn patterns)
- Scaling decisions: storage, IOPS, instance class

Project notes:
- This project is not a performance benchmark.
- Production requires monitoring and capacity planning.

---

### 5. Backups and Snapshots are Multi-Tenant Objects

Risk:
- A snapshot contains all tenants’ data; access to snapshots is highly sensitive.

Mitigations:
- Strict IAM controls for snapshot operations
- KMS key policies limiting who can use keys
- Audit snapshot actions centrally
- Consider per-tenant logical exports if contractual/mission needs demand it

Project notes:
- Multi-tenant backup handling is a key IL4 operational concern; enforce via platform IAM.

---

## Recommended Monitoring Signals (AWS RDS)

Minimum signals to alert on:
- DBConnections (approaching max / pool limits)
- CPUUtilization
- FreeableMemory
- FreeStorageSpace
- Read/Write latency and IOPS saturation
- Deadlocks
- Replication lag (if applicable)
- Long-running queries (pg_stat_activity)
- Autovacuum lag / bloat indicators

Log sources:
- RDS PostgreSQL logs (to CloudWatch Logs)
- pgAudit logs (SQL-level auditing and denied actions)
- Application logs (connection pool and query timing)

---

## Project-Implemented Guardrails (Local + Portable)

This repo implements and/or validates:
- Per-tenant CONNECTION LIMIT
- Per-tenant statement_timeout
- Negative tests validating those controls

Future enhancements:
- Provide a pgBouncer example docker-compose profile
- Add “noisy neighbor” load simulations (optional)
- Provide Terraform modules for RDS + parameter groups + alarms

---

## When NOT to Use This Model

This model is not a fit when:

1. Tenants require strong performance isolation
   - If one tenant cannot be allowed to impact another’s latency at all,
     use separate RDS instances (or separate clusters) per tenant.

2. Tenants have materially different compliance requirements
   - If one tenant requires different logging, retention, encryption keys, patch cadence,
     or operational controls, isolate them at the instance/cluster boundary.

3. Tenants require independent backup/restore and RPO/RTO guarantees
   - Multi-tenant snapshots are shared objects.
   - If per-tenant restore independence is mandatory, consider separate instances.

4. The expected workload is highly variable / spiky / unpredictable
   - Multi-tenant works best when tenants are well-behaved or governed.
   - If you cannot enforce pool limits and timeouts, multi-tenant will be fragile.

5. The team cannot staff the operational rigor
   - Multi-tenant requires monitoring, guardrails, and disciplined change management.
   - Without those, cost savings may be erased by incident cost.

---

## Summary

Multi-tenant PostgreSQL can be secure and cost-effective, but it must be paired with:
- guardrails (connection limits, timeouts)
- monitoring and alerting
- disciplined operational practices

This repository’s goal is to provide a repeatable baseline for those controls and the evidence (tests + docs) to support platform adoption in regulated environments.
