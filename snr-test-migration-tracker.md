# SNR Test Migration Tracker — Python (ocp-edge-auto) → Go

## Context

Tracking all 24 SNR tests from the Python ocp-edge-auto framework for migration to a new Go implementation. Priority is based on current pass/fail status — tests that pass consistently are migrated first as proven reference implementations.

**Test results from:**
- **x86 (edge119):** IIB 1147821, 3-master compact (0 workers), OCP 4.22 nightly, May 28 2026
- **ARM64 (nvd-srv-16):** IIB 1151696, 3m+3w, OCP 4.22 nightly arm64, June 3 2026

## Priority Scheme

| Priority | Criteria |
|----------|----------|
| **P1** | Passed on both x86 and ARM — migrate first as proven reference |
| **P2** | Passed on x86 only, or simple verification tests |
| **P3** | Failed due to known reasons (env/infra), likely pass after fix |
| **P4** | Needs special infra (KVM suspend, scale workers), or permanently skipped |

---

## test_snr_cli.py

### TestPostDeploymentSnr — Post-install verification (6 tests)

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 1 | test_snr_resources_are_installed_and_running | OCP-54205 | SNRC config exists, DS pods on every node, controller-manager ready | Passed | Passed | **Passed** | **P1** |
| 2 | test_snr_only_automatic_remediation_template_exists | OCP-71010 | Only "Automatic" SNRT exists; ResourceDeletion/NodeDeletion must not | Passed | Passed | **Passed** | **P1** |
| 3 | test_snr_annotations | OCP-52136 | CSV annotations: valid-subscription, support, repo URL, maintainers | Passed | Passed | **Passed** | **P1** |
| 4 | test_snr_metadata | OCP-70705 | CSV metadata: infrastructure annotations, suggested-namespace, replaces field | Passed | Passed | **Passed** | **P1** |
| 5 | test_snr_must_gather | OCP-50774 | Runs RHWA must-gather, verifies SNR data files collected | Passed | Xfailed | Xfailed (ARM) | P2 |
| 6 | test_snr_description_of_safeTimeToAssumeNodeRebootedSeconds | OCP-60824 | CRD description text for safeTimeToAssumeNodeRebootedSeconds | Passed | Skipped | Partial | P2 |

### TestHealthDetectionForWorkersUsingSnr — Worker remediation (3 tests)

| # | Test | Polarion | What it validates | x86 (mhc) | x86 (nhc) | ARM | Status | Priority |
|---|------|----------|-------------------|-----------|-----------|-----|--------|----------|
| 7 | test_snr_with_stop_kubelet_for_worker | OCP-52417 / OCP-52416 | Stop kubelet on worker → MHC/NHC detects → SNR remediates → node reboots → recovers | Failed | Not run | Not run | Failed | P3 |
| 8 | test_remediation_strategy_resource_deletion | OCP-50772 | NHC-only: ResourceDeletion strategy — app pod rescheduled after remediation | Skipped (mhc) | Not run | Not run | Not run | P3 |
| 9 | test_remediation_strategy_out_of_service_taint | OCP-61594 | NHC-only: OutOfServiceTaint strategy — app pod rescheduled after remediation | Skipped (mhc) | Not run | Not run | Not run | P3 |

### TestHealthDetectionForControlPlanesUsingSnr — Master remediation (2 tests)

| # | Test | Polarion | What it validates | x86 (mhc) | x86 (nhc) | ARM | Status | Priority |
|---|------|----------|-------------------|-----------|-----------|-----|--------|----------|
| 10 | test_snr_with_stop_kubelet_for_master | OCP-55058 / OCP-55059 | Stop kubelet on master → MHC/NHC detects → SNR remediates with NoExecute taints → master reboots | Failed | Not run | Not run | Failed | P3 |
| 11 | test_snr_with_stop_kubelet_for_master_and_worker | OCP-56069 | NHC-only: Stop kubelet on master AND worker simultaneously → both remediated | Skipped (mhc) | Not run | Not run | Not run | P3 |

### TestSnrConfigNegativeScenarios — Config edge cases (3 tests)

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 12 | test_non_default_snrc_creation | OCP-50961 | Creating a second (non-default) SNRC is rejected | Passed | Not run | Passed (x86) | P2 |
| 13 | test_snr_auto_detects_softdog_path | OCP-50770 | Invalid watchdog path → SNR auto-detects softdog and logs message | Passed | Not run | Passed (x86) | P2 |
| 14 | test_snrc_deletion_disables_snr | OCP-74298 | Delete SNRC → DS pods removed; manual SNR shows "config not found"; recreate SNRC → pods return | Passed | Not run | Passed (x86) | P2 |

### TestSnrNegativeScenarios — Invalid input handling (2 tests)

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 15 | test_invalid_values_in_snrc | OCP-47330 | SNRC with invalid string/duration values → specific validation errors | Passed | Not run | Passed (x86) | P2 |
| 16 | test_last_error_captured_in_snr | OCP-50583 | SNR with non-existent node name → lastError field populated | Passed | Not run | Passed (x86) | P2 |

---

## test_only_snr_cli.py

### TestApiCasesSnr — Standalone remediation via KVM suspend (2 tests)

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 17 | test_snr_standalone_by_stop_kubelet | OCP-55370 | Stop kubelet + suspend 2 masters → isolated master self-remediates | Skipped (ECOPROJECT-2875) | Not run | Skipped | P4 |
| 18 | test_snr_standalone_by_suspend_all_workers | OCP-56071 | Suspend all other masters + all workers → isolated master self-remediates via standalone SNR | Passed | Not run | Passed (x86) | P4 |

### TestSnrNegativeScenarios — Unsupported strategies (2 tests)

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 19 | test_create_snr_with_unsupported_strategy | OCP-60877 | SNR with NodeDeletion strategy → rejected with "Unsupported value" | Passed | Not run | Passed (x86) | P2 |
| 20 | test_create_snr_template_with_unsupported_strategy | OCP-60822 | SNRT with NodeDeletion strategy → rejected with "Unsupported value" | Passed | Not run | Passed (x86) | P2 |

### TestSnrProcessingCondition — Status condition validation (2 tests)

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 21 | test_snr_conditions_while_nhc_timed_out_annotation | OCP-60881 | SNR with nhc-timed-out annotation → Processing/Succeeded show "RemediationStoppedByNHC" | Passed | Not run | Passed (x86) | P2 |
| 22 | test_snr_conditions_with_non_existent_node_name | OCP-70584 | SNR with fake node name → conditions show "RemediationSkippedNodeNotFound" | Passed | Not run | Passed (x86) | P2 |

---

## test_snr_scale.py

| # | Test | Polarion | What it validates | x86 | ARM | Status | Priority |
|---|------|----------|-------------------|-----|-----|--------|----------|
| 23 | test_self_node_remediation_after_scale_down | OCP-50780 | Scale down (remove worker with SNR controller) → controller moves, DS pod removed. Requires 3+ workers | Skipped (no workers) | Not run | Skipped | P4 |
| 24 | test_self_node_remediation_after_scale_up | OCP-51155 | Scale up (add BMH back) → DS pod created on new node. Requires spare provisioned workers | Skipped (no workers) | Not run | Skipped | P4 |

---

---

## Migration Phases

### Phase 1 — Post-deployment verification (P1) `[x]`

Passed on both x86 and ARM. Pure API/object checks, no node disruption, ~2 min total. Establishes the Go test scaffold, client setup, and assertion patterns.

**Source:** `test_snr_cli.py` → `TestPostDeploymentSnr`
**PR:** [medik8s/system-tests#13](https://github.com/medik8s/system-tests/pull/13)
**Jira:** [RHWA-1074](https://redhat.atlassian.net/browse/RHWA-1074)

| # | Test | Polarion | What to implement | Progress |
|---|------|----------|-------------------|----------|
| 1 | test_snr_resources_are_installed_and_running | OCP-54205 | Get SNRC by name, verify DS pods on all nodes, verify controller-manager replicas | `[x]` |
| 2 | test_snr_only_automatic_remediation_template_exists | OCP-71010 | Get SNRT "Automatic", verify strategy field, assert ResourceDeletion/NodeDeletion don't exist | `[x]` |
| 3 | test_snr_annotations | OCP-52136 | Get SNR CSV, check annotations (valid-subscription, support, repo, maintainers) | `[x]` |
| 4 | test_snr_metadata | OCP-70705 | Get SNR CSV, check infrastructure annotations, suggested-namespace, replaces field | `[x]` |

**Done when:** All 4 tests pass on a deployed RHWA cluster (x86 and ARM).
**Status:** 4/4 passed on ARM64 (nvd-srv-16, IIB 1151696, SNR v0.13.0) and x86 (AWS Cluster Bot, GA catalog, SNR v0.12.1).

---

### Phase 2.1 — Config & negative scenarios from test_snr_cli.py (P2) `[x]`

Passed on x86 and ARM64. Config manipulation, CRD validation, and negative input tests. Split into 2 PRs: A (CRD/negative), B (config lifecycle). Must-gather (Test 5) moved out of scope for this ticket.

**Source:** `test_snr_cli.py` → `TestSnrConfigNegativeScenarios`, `TestSnrNegativeScenarios`
**PR (A):** [medik8s/system-tests#16](https://github.com/medik8s/system-tests/pull/16)
**PR (B):** [medik8s/system-tests#39](https://github.com/medik8s/system-tests/pull/39)
**Jira:** [RHWA-1075](https://redhat.atlassian.net/browse/RHWA-1075) (Closed)

| # | Test | Polarion | What to implement | Progress |
|---|------|----------|-------------------|----------|
| 6 | test_snr_description_of_safeTimeToAssumeNodeRebootedSeconds | OCP-60824 | Get SNR CRD, validate description text for safeTimeToAssumeNodeRebootedSeconds | `[x]` (PR A) |
| 12 | test_non_default_snrc_creation | OCP-50961 | Create second SNRC → expect rejection with specific error | `[x]` (PR A) |
| 13 | test_snr_auto_detects_softdog_path | OCP-50770 | Patch SNRC watchdog to invalid path → verify auto-detect log message | `[x]` (PR B) |
| 14 | test_snrc_deletion_disables_snr | OCP-74298 | Delete SNRC → DS pods removed; create manual SNR → "config not found"; recreate SNRC → pods return | `[x]` (PR B) |
| 15 | test_invalid_values_in_snrc | OCP-47330 | Create SNRC with invalid string/duration values → expect validation errors | `[x]` (PR A) |
| 16 | test_last_error_captured_in_snr | OCP-50583 | Create SNR with fake node name → verify lastError in status | `[x]` (PR A) |

**Done when:** All 6 tests pass on x86. ARM validation as stretch goal.
**Status:** 6/6 passed on ARM64 (nvd-srv-16, SNR v0.13.0) and x86 (AWS Cluster Bot, OCP 4.22, SNR v0.13.0 GA).

---

### Phase 2.2 — Negative & condition tests from test_only_snr_cli.py (P2) `[x]`

Passed on x86. Introduces the second source file — unsupported strategy rejection and SNR condition/status validation.

**Source:** `test_only_snr_cli.py` → `TestSnrNegativeScenarios`, `TestSnrProcessingCondition`
**PR:** [medik8s/system-tests#17](https://github.com/medik8s/system-tests/pull/17)
**Jira:** [RHWA-1076](https://redhat.atlassian.net/browse/RHWA-1076)

| # | Test | Polarion | What to implement | Progress |
|---|------|----------|-------------------|----------|
| 19 | test_create_snr_with_unsupported_strategy | OCP-60877 | Create SNR with NodeDeletion strategy → expect "Unsupported value" error | `[x]` |
| 20 | test_create_snr_template_with_unsupported_strategy | OCP-60822 | Create SNRT with NodeDeletion strategy → expect "Unsupported value" error | `[x]` |
| 21 | test_snr_conditions_while_nhc_timed_out_annotation | OCP-60881 | Create SNR with nhc-timed-out annotation → verify Processing/Succeeded conditions + stop log | `[x]` |
| 22 | test_snr_conditions_with_non_existent_node_name | OCP-70584 | Create SNR with fake node name → verify Processing/Succeeded show "RemediationSkippedNodeNotFound" | `[x]` |

**Done when:** All 4 tests pass on x86.
**Status:** 4/4 passed on ARM64 (nvd-srv-16, SNR v0.13.0) and x86 (AWS Cluster Bot, SNR v0.12.1).

---

### Phase 3 — Remediation & must-gather tests (P3) `[ ]`

Must-gather plus kubelet-stop tests that trigger actual node reboots via MHC/NHC detection. Requires SSH access to nodes and longer timeouts (~15 min per remediation cycle).

**Source:** `test_snr_cli.py` → `TestPostDeploymentSnr` (must-gather), `TestHealthDetectionForWorkersUsingSnr`, `TestHealthDetectionForControlPlanesUsingSnr`
**Jira:** [RHWA-1077](https://redhat.atlassian.net/browse/RHWA-1077)

| # | Test | Polarion | What to implement | Progress |
|---|------|----------|-------------------|----------|
| 5 | test_snr_must_gather | OCP-50774 | Run RHWA must-gather, verify SNR data files in output | `[ ]` |
| 7 | test_snr_with_stop_kubelet_for_worker | OCP-52417 / OCP-52416 | Stop kubelet on worker → MHC/NHC detects → SNR remediates → node reboots → verify recovery | `[ ]` |
| 8 | test_remediation_strategy_resource_deletion | OCP-50772 | NHC + ResourceDeletion strategy: deploy app, stop kubelet → verify pod rescheduled | `[ ]` |
| 9 | test_remediation_strategy_out_of_service_taint | OCP-61594 | NHC + OutOfServiceTaint strategy: deploy app, stop kubelet → verify pod rescheduled | `[ ]` |
| 10 | test_snr_with_stop_kubelet_for_master | OCP-55058 / OCP-55059 | Stop kubelet on master → MHC/NHC detects → SNR with NoExecute taints → master reboots | `[ ]` |
| 11 | test_snr_with_stop_kubelet_for_master_and_worker | OCP-56069 | NHC-only: stop kubelet on master AND worker simultaneously → both remediated | `[ ]` |

**Done when:** All 6 tests pass on x86 with both mhc and nhc modes. ARM as stretch goal.

---

### Phase 4 — Standalone & scale tests (P4) `[ ]`

Requires special infrastructure: KVM suspend (hypervisor access) or MachineSet scaling (3+ workers). Low priority — migrate last.

**Source:** `test_only_snr_cli.py` → `TestApiCasesSnr`, `test_snr_scale.py`

| # | Test | Polarion | What to implement | Progress |
|---|------|----------|-------------------|----------|
| 17 | test_snr_standalone_by_stop_kubelet | OCP-55370 | Stop kubelet + suspend 2 masters → standalone self-remediation. Currently skipped (ECOPROJECT-2875) | `[ ]` |
| 18 | test_snr_standalone_by_suspend_all_workers | OCP-56071 | Suspend all masters + workers via KVM → isolated master self-remediates | `[ ]` |
| 23 | test_self_node_remediation_after_scale_down | OCP-50780 | Scale down cluster → SNR controller moves, DS pod removed from deleted node | `[ ]` |
| 24 | test_self_node_remediation_after_scale_up | OCP-51155 | Scale up cluster → DS pod created on new node | `[ ]` |

**Done when:** Pass on cluster with dedicated workers + hypervisor access.

---

## Phase Summary

| Phase | Tests | Source files | Status |
|-------|------:|-------------|--------|
| **Phase 1** | 4 | `test_snr_cli.py` | **Done** (PR #13) |
| **Phase 2.1** | 6 | `test_snr_cli.py` | **Done** (PR #16, #39) |
| **Phase 2.2** | 4 | `test_only_snr_cli.py` | **Done** (PR #17) |
| **Phase 3** | 5 | `test_snr_cli.py` | Not started |
| **Phase 4** | 4 | `test_only_snr_cli.py`, `test_snr_scale.py` | Not started |
| **Migrated** | **14** | | **14/24 (58%)** |
| **Remaining** | **10** | | must-gather (1) + remediation (5) + standalone/scale (4) |

## Notes

- **Phase 1** establishes the Go test scaffold, client setup, and assertion patterns — everything after builds on it.
- **Phase 2.1 before 2.2** keeps work in a single source file before introducing the second, reducing context switching.
- **Phase 3** is the core value of SNR testing (actual remediation) but needs stable infra and longer run times.
- **Phase 4** tests are environment-gated — skip unless the cluster has workers and hypervisor access.
- Source code: `~/git/ocp-edge-auto/edge_tests/management/cluster_life_cycle/`
