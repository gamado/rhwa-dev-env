# RHWA Remediation Test Coverage Report

Generated: 2026-07-22

## Summary

| Operator | Remediation Tests | Status | PR |
|----------|-------------------|--------|----|
| SNR | 5 | Merged | #52 |
| MDR | 1 | Merged | #53 |
| SBR | 8 (Maxim) + 5 (stashed) | Partial | stashed on feat/sbr-standalone-remediation |
| NHC | 5 | In progress | feat/nhc-remediation-trigger |
| FAR | 6 (Udi) | Merged | #49 |
| NMO | 0 | Not started | -- |

## SNR -- Self Node Remediation (PR #52, merged)

| # | Polarion | Test | File |
|---|----------|------|------|
| 1 | OCP-52416 | Worker kubelet stop via NHC | worker_remediation.go |
| 2 | OCP-50772 | ResourceDeletion strategy + workload eviction | worker_remediation.go |
| 3 | OCP-61594 | OutOfServiceTaint strategy + workload eviction | worker_remediation.go |
| 4 | OCP-55059 | Master kubelet stop via NHC | master_remediation.go |
| 5 | OCP-56069 | Simultaneous master + worker kubelet stop | master_remediation.go |

## MDR -- Machine Deletion Remediation (PR #53, merged)

| # | Polarion | Test | File |
|---|----------|------|------|
| 1 | OCP-66138 | NHC-triggered Machine deletion + condition transitions | mdr_remediation.go |

## SBR -- Storage Based Remediation

### Existing (Maxim's work, merged)

| # | Polarion | Test | File | Type |
|---|----------|------|------|------|
| 1 | OCP-88876 | detectOnlyMode suppression | detect_only.go | Remediation |
| 2 | OCP-88737 | SBR CR lifecycle (finalizer) | remediation.go | Remediation |
| 3 | OCP-88738 | Node hang: kernel panic + NHC fencing | node_hang.go | Remediation |
| 4 | OCP-88879 | NHC detects storage failure, triggers fencing | nhc_integration.go | Remediation |
| 5 | OCP-88877 | Split-brain: only isolated node fenced | split_brain.go | Remediation |
| 6 | OCP-88880 | Total storage I/O loss: watchdog fires | storage_loss_watchdog.go | Remediation |
| 7 | OCP-89200 | Write-only storage loss: fence-message-read | storage_loss_write_only.go | Remediation |
| 8 | OCP-88735 | Transient storage failure: self-healing | transient_storage.go | Remediation |

### Stashed (RHWA-1051, needs ODF/NFS cluster)

| # | Polarion | Test | Status |
|---|----------|------|--------|
| 1 | OCP-88738 | Standalone SBR CR remediation | Code ready, reviewed |
| 2 | OCP-88877 | Active controller node remediation | Code ready |
| 3 | OCP-TBD-SBR-1 | NoExecute taint during remediation | Code ready |
| 4 | OCP-TBD-SBR-2 | Workload eviction from fenced node | Code ready |
| 5 | OCP-TBD-SBR-3 | Controller pod handover | Code ready |

Branch: `feat/sbr-standalone-remediation` (stashed, skip-tested on AWS without ODF)

## NHC -- Node Health Check (RHWA-1243, in progress)

| # | Polarion | Test | File |
|---|----------|------|------|
| 1 | OCP-56938 | Selector editing (observed nodes drop) | nhc_remediation_trigger.go |
| 2 | OCP-56600 | Editing/deletion blocked during remediation | nhc_remediation_trigger.go |
| 3 | OCP-69711 | Old default NHC CR name handling | nhc_remediation_trigger.go |
| 4 | OCP-66814 | Only one NHC CR remediates at a time | nhc_remediation_trigger.go |
| 5 | OCP-71171 | Non-remediating NHC CR deletion allowed | nhc_remediation_trigger.go |

Branch: `feat/nhc-remediation-trigger` (code complete, reviewed, not yet tested on cluster)

## FAR -- Fence Agents Remediation (PR #49, Udi, merged)

| # | Polarion | Test | File |
|---|----------|------|------|
| 1 | OCP-66026 | AWS fence agent remediation | far_destructive.go |
| 2 | OCP-65960 | NoSchedule taint during fencing | far_destructive.go |
| 3 | OCP-67015 | Out-of-service taint applied | far_destructive.go |
| 4 | OCP-66228 | Workload pod deletion during fencing | far_destructive.go |
| 5 | OCP-70636 | Controller pod handover | far_destructive.go |
| 6 | OCP-67014 | Leader node fencing | far_destructive.go |

## NMO -- Node Maintenance Operator

No remediation tests (NMO handles maintenance mode, not remediation). Lifecycle tests tracked in RHWA-1250, RHWA-1252.

## Remaining Jira Tickets

| Jira | Operator | Description | Status |
|------|----------|-------------|--------|
| RHWA-1051 | SBR | Standalone remediation (5 tests) | Stashed, needs ODF/NFS |
| RHWA-1243 | NHC | Remediation trigger (5 tests) | In progress |
| RHWA-1245 | NHC | Escalation chain (7 tests) | Not started |
| RHWA-1348 | MDR | Standalone MDR without NHC | Not started |
| RHWA-1250 | NMO | Maintenance lifecycle (4 tests) | Not started |
| RHWA-1252 | NMO | Pod eviction + SNR interop (5 tests) | Not started |
