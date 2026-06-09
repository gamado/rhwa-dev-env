# RHWA 4.22-0 Test Report — ARM64 (aarch64)

- **Cluster:** nvd-srv-16.nvidia.eng.rdu2.redhat.com
- **OCP:** 4.22.0-0.nightly-arm64-2026-06-02-080307
- **IIB:** registry-proxy.engineering.redhat.com/rh-osbs/iib:1151696
- **Topology:** 3 masters + 3 workers (libvirt VMs, virtual BMC via sushy-tools)
- **Date:** 2026-06-03
- **Test framework:** ocp-edge-auto (master branch)

---

## Summary

| Suite | Passed | Failed | Errors | Duration | Verdict           |
|-------|-------:|-------:|-------:|----------|-------------------|
| SNR   |      4 |      0 |      0 | 2 min    | PASS              |
| NMO   |     13 |      4 |      0 | 37 min   | FAIL — see below  |
| NHC   |      6 |      5 |      0 | 13 min   | FAIL — see below  |
| MDR   |      4 |      1 |      6 | 2h 7min  | FAIL — see below  |
| FAR   |     11 |     14 |      0 | 1h 14min | FAIL — see below  |
| SBR   |      — |      — |      — | —        | Skipped           |

---

## SNR — PASS

All 4 tests passed. 1 xfailed, 1 skipped. No ARM-specific issues.

---

## NMO — 13 passed, 4 failed

**1. `test_nmo_must_gather`** — ARM-SPECIFIC
- Must-gather image `node-healthcheck-must-gather-rhel9:v0.11.0` is amd64-only (no arm64 manifest)
- Test hardcodes old version v0.11.0 instead of deployed v0.12.0
- The v0.12.0 on quay.io does have arm64 builds

**2. `test_node_in_maintenance_after_reboot`** — Nightly infra issue
- Pods rescheduled to master nodes during drain
- Masters blocked image pulls due to `ClusterImagePolicy` (SignatureValidationFailed)
- Cluster readiness check failed due to pending pods

**3. `test_check_master_quorum`** — Nightly infra issue
- Same cascading failure as above

**4. `test_nmo_for_not_ready_node`** — Nightly infra issue
- Same cascading failure as above

---

## NHC — 6 passed, 5 failed

All 5 failures have the same root cause — **not ARM-specific**:

```
FileNotFound: No ssh private key file /root/.ssh/id_rsa found
```

NHC tests SSH into nodes to stop kubelet and simulate unhealthy nodes.

Failed tests:
1. `test_status_field_in_nhc`
2. `test_nhc_editing_during_remediation`
3. `test_nhc_with_zero_healthy_nodes`
4. `test_nhc_escalation_basic_functionality`
5. `test_nhc_with_custom_remediation_template`


---

## MDR — 4 passed, 1 failed, 6 errors

### 6 errors (setup failures) — Nightly infra issue

All caused by cluster readiness check failing due to pending pods
(same signature policy issue as NMO). These ran before the fix was applied.

- `test_mdr_resource_is_installed_and_running`
- `test_mdr_annotations`
- `test_mdr_metadata`
- `test_mdr_must_gather` (setup + teardown)
- `test_nhc_with_machine_deletion_remediation_template`

### 1 actual failure — Needs investigation

**`test_permanent_node_deletion_condition_in_mdr_with_control_plane_node_name`**
- Timed out waiting for `PermanentNodeDeletionExpected` condition
- MDR reported `RemediationCannotStartNoControllerOwner`
- The Machine object for master-2 may lack a controller owner reference

> **QE question:** Is this known to fail on baremetal/virtual x86 clusters?
> The `NoControllerOwner` condition may be expected for BM clusters.

---

## FAR — 11 passed, 14 failed

### SSH key issue (7 failures) — Setup issue

Same missing `/root/.ssh/id_rsa` as NHC:

1. `test_far_remediation_from_nhc`
2. `test_far_template_default_action`
3. `test_far_log_output`
4. `test_far_must_gather`
5. `test_far_remediation_standalone`
6. `test_far_remediation_standalone_on_active_controller_node`
7. `test_far_cr_default_action`

### Potentially ARM-specific (3 failures)

**`test_run_container_as_non_root`** — ARM?
- FAR container fails to run as non-root user

**`test_available_agents`** — ARM?
- Missing agents: `fence_aws, fence_azure_arm, fence_gce`
- ARM image may not include cloud fence agents

**`test_far_explicit_workload_deletion`** — ARM-SPECIFIC
- hello-openshift pod not found — same x86-only image issue as NMO

### Needs investigation (4 failures)

**`test_controller_replicas_one_worker_node_available`**
- FAR controller pods not ready after test scenario

**`test_far_support_NoExecute_taint`**
- Timed out waiting for NoExecute taint on worker-2

**`test_far_condition_status`**
- Timed out waiting for `FenceAgentActionSucceeded` condition

**`test_far_action_misconfiguration`**
- Admission webhook rejected the CR: `Forbidden`

> **QE question:** Are the 4 investigation-needed failures known on x86? The `test_available_agents` failure (missing cloud agents) may be ARM image packaging issue.

---

## ARM-Specific Findings

### 1. hello-openshift test image is x86-only

The test framework uses `registry.redhat.io/openshift4/ose-hello-openshift-rhel8`
for cluster readiness. This image is amd64-only — on arm64 it crashes with
`Exec format error`. Blocked test startup until timeout.

**Fix:** Replace with a multi-arch image.

### 2. must-gather image v0.11.0 has no arm64 support

Test hardcodes `node-healthcheck-must-gather-rhel9:v0.11.0` (amd64-only).
Current v0.12.0 on quay.io has arm64 builds.

**Fix:** Update test to read must-gather version from deployed CSV.

### 3. Nightly cluster signature policy

Not ARM-specific but affects ARM nightly testing:
- `ClusterImagePolicy` enforces signatures for `ocp-v4.0-art-dev` (unsigned on nightly)
- `99-master-permissive-policy` MC enforced GPG signatures for `registry.redhat.io` on masters only
- Both required workarounds to deploy and test RHWA

---

## Environment Notes

- RHWA operators deployed via IDMS mirrors (quay.io/redhat-user-workloads/rhwa-tenant)
- SSH key for node access was not configured (caused all NHC failures)
- Signature policy was fixed mid-run (NMO/MDR ran before fix; SNR ran after)
- All 17 operator pods were Running and healthy before testing started

---

## Recommended Re-run

After fixing setup issues, re-run for clean ARM validation:

1. Set up SSH keys for node access (`/root/.ssh/id_rsa`)
2. Scale CVO down and patch `ClusterImagePolicy` before tests
3. Re-run: NMO, MDR, NHC, FAR (SNR is clean)