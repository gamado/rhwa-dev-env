---
name: migrate-test
description: Migrate E2E tests from Python (ocp-edge-auto) to Go (medik8s/system-tests). Generic for any RHWA operator (SNR, NHC, FAR, MDR, NMO, SBR). Covers Jira planning through verified CI.
user_invocable: true
---

# Migrate Test Skill

Migrate RHWA E2E tests from the Python ocp-edge-auto framework to Go in medik8s/system-tests.

## Usage

```
/migrate-test <operator> [polarion-ids...]
```

### Arguments

- **operator** (required): Target operator -- `snr`, `nhc`, `far`, `mdr`, `nmo`, `sbr`
- **polarion-ids** (optional): Space-separated Polarion IDs to migrate (e.g. `56600 69711 66814`)
  - If omitted, look up the Jira ticket for the operator to find the full scope

### Examples

```
/migrate-test nhc 56600 69711 66814 71171 56938
/migrate-test snr                                  → reads Jira for scope
/migrate-test far 12345 12346
```

## Flow

### Phase 1: Scope (from Jira)

1. **Read the Jira ticket** for the migration. Known epics:
   - SNR: RHWA-836 (story RHWA-1073)
   - NHC: RHWA-1243
   - Check Jira MCP or REST API for sub-tasks with Polarion IDs
   ```bash
   # Fetch Jira ticket details
   curl -s -H "Authorization: Bearer $(cat ~/.jira-token)" \
     "https://api.atlassian.com/ex/jira/2b9e35e3/rest/api/3/issue/RHWA-XXXX"
   ```

2. **Update Jira to "In Progress"** -- transition the ticket and add a comment:
   ```
   Starting migration of <operator> tests: <list of Polarion IDs>
   Reading Python reference implementation from ocp-edge-auto.
   ```

3. **List Polarion IDs** to migrate. For each ID, record:
   - Test name from Polarion
   - Python test method name (search for the ID in ocp-edge-auto)
   - Whether it's destructive (stops kubelet, reboots nodes) or non-destructive

### Phase 2: Read Python (CRITICAL -- do not skip)

3. **For each Polarion ID**, find and read the FULL Python implementation:

   ```bash
   grep -rn "<POLARION_ID>" /home/kni/git/ocp-edge-auto/edge_tests/
   ```

4. **Read the test method body** -- what it verifies, in what order

5. **Read EVERY helper function** the test calls. Follow the import chain:
   - `stop_kubelet_on_node` -> `invoke_ssh_on_the_node` -> paramiko SSH (NOT oc debug)
   - `start_kubelet_on_node` -> SSH + `daemon-reload`
   - `verify_remediation_finished` -> `await_all_nodes_ready` + `await_snr_deleted` + NHC phase check
   - `apply_nhc_external_remediation_resources` -> YAML-based CRD/RBAC setup

   Common helpers live in:
   - `/home/kni/git/ocp-edge-auto/edge_infra/ocp/utils/nodes.py` -- kubelet ops, node status
   - `/home/kni/git/ocp-edge-auto/edge_infra/ocp/utils/ssh.py` -- SSH mechanism
   - `/home/kni/git/ocp-edge-auto/edge_infra/ocp/utils/node_health_checks.py` -- NHC/SNR helpers

6. **Read the class `teardown_method`** -- recovery logic not in the Polarion plan but essential for cluster stability

7. **Produce a comparison table** for each test before writing code:

   ```
   | Step | Python | Go (planned) | Notes |
   |------|--------|--------------|-------|
   | Stop kubelet | SSH (paramiko) | StopKubeletSSH | Match |
   | Start kubelet | SSH + daemon-reload | StartKubeletSSH | Match |
   | Verify SNR not created | await timeout | Consistently 30s | Equivalent |
   ```

   Flag any gaps. The Polarion plan describes WHAT to verify; Python shows HOW.

### Phase 3: Learn from history

8. **Run `/review-checklist`** to load the latest review rules from merged PRs

9. **Read existing test files** for the target operator to follow established patterns:
   ```
   repos/system-tests/tests/<operator>-operator/tests/
   repos/system-tests/tests/<operator>-operator/internal/<operator>params/
   ```

### Phase 4: Implement

10. **Create feature branch**:
    ```bash
    git checkout -b feat/<operator>-<description>
    ```

11. **Write Go tests** following these rules:
    - Match the Python kubelet stop/start mechanism (SSH or oc debug -- read the Python helpers to determine which)
    - If Python uses SSH: use `helpers.StopKubeletSSH` / `helpers.StartKubeletSSH`
    - `StartKubeletSSH` includes `daemon-reload` (matches Python's `start_kubelet_on_node`)
    - Use `MatchError(ContainSubstring(...))` not `Expect(err.Error())` (R-12)
    - Use `Consistently` for negative assertions (R-15)
    - Use `wait.PollUntilContextTimeout` in cleanup (not `Eventually` which panics on timeout in JustAfterEach) (R-52)
    - Pre-clean stale CRs in BeforeEach (R-03)
    - Every `It` block needs: `reportxml.ID`, granular labels, unique focus string
    - Match the Python flow step-for-step. If the Python does something the Go doesn't, that's a gap to fill

12. **Add constants** to `<operator>params/const.go`

13. **Update README** with new test entries (R-49):
    - Polarion hyperlink, description, operators, cluster, environment, standalone command, pass criteria
    - Pass criteria must list EVERY assertion the code performs

### Phase 5: Verify (incremental)

14. **Build and lint**:
    ```bash
    export PATH=/usr/local/go/bin:/home/kni/go/bin:$PATH
    go build ./tests/<operator>-operator/...
    go vet ./tests/<operator>-operator/...
    gofmt -l tests/<operator>-operator/
    ```

15. **Run on baremetal first** (srv-16 or edge cluster):
    - Skip other tests: run only the new test(s) by label filter
    - Check cluster health before AND after
    - Verify `-vv` output shows complete flow
    ```bash
    /run-system-tests srv-16 <operator> --label-filter="<polarion-id>"
    ```

16. **If tests are destructive**: run one test at a time first, then all together. Destructive tests reboot nodes -- verify the cluster recovers between tests.

17. **Run `/review-checklist`** on the changed files

### Phase 6: Ship

18. **Commit and push** to `gamado` fork:
    ```bash
    git push gamado feat/<operator>-<description>
    ```

19. **Create PR** with:
    - Title: `<operator>-operator: add <description> tests (RHWA-XXXX)`
    - Body: Polarion ID hyperlinks, test descriptions, test plan
    - Reference the Jira ticket

20. **Update Jira to "In Review"** -- add a comment with the PR link:
    ```
    PR created: https://github.com/medik8s/system-tests/pull/<N>
    Tests: <list of Polarion IDs>
    CI status: <passing/pending>
    ```

21. **Trigger CI** and verify with `/prow-investigate`:
    ```
    /prow-investigate <PR-number>
    ```

22. **Trace every test** in the `-vv` CI output:
    - Kubelet stop/start completed correctly (SSH or oc debug, matching Python)
    - Remediation flow: NHC Remediating -> SNR CR -> boot ID changed -> node Ready -> NHC Enabled
    - Webhook assertions: correct error messages
    - Cleanup: JustAfterEach ran, safety net passed

### Phase 7: Post-PR

23. Address reviewer comments (rbartal, mpryc, ugreener)
24. **After PR merges**, update Jira to "Done" with final comment:
    ```
    PR merged: https://github.com/medik8s/system-tests/pull/<N>
    Tests migrated: <list of Polarion IDs>
    CI: all passing on Prow AWS
    ```

## Key References

| Resource | Path / URL |
|----------|-----------|
| Python source | `/home/kni/git/ocp-edge-auto/edge_tests/management/cluster_life_cycle/` |
| Python helpers (nodes) | `/home/kni/git/ocp-edge-auto/edge_infra/ocp/utils/nodes.py` |
| Python helpers (SSH) | `/home/kni/git/ocp-edge-auto/edge_infra/ocp/utils/ssh.py` |
| Python helpers (NHC) | `/home/kni/git/ocp-edge-auto/edge_infra/ocp/utils/node_health_checks.py` |
| Go target | `repos/system-tests/tests/<operator>-operator/` |
| Shared Go helpers | `repos/system-tests/tests/internal/helpers/` |
| Git remote for push | `gamado` |
| GitHub API | `curl` with `~/.github-token` (not gh CLI) |
| Jira API | REST with `~/.jira-token`, CloudID `2b9e35e3` |
| Review checklist | `/review-checklist` |
| CI investigation | `/prow-investigate <PR>` |
| Cluster health | `/check-cluster srv-16` or `/check-cluster edge119` |

## Coding Patterns (from merged PR reviews)

### Kubelet operations
- **Match the Python reference implementation** for kubelet stop/start mechanism
- Python uses SSH (`invoke_ssh_on_the_node` via paramiko) -- use `helpers.StopKubeletSSH` / `helpers.StartKubeletSSH`
- Python uses `oc debug` -- use `helpers.StopKubelet` / `helpers.StartKubelet`
- SSH works on Prow AWS (via ssh-bastion proxy) and baremetal (direct)
- Note: `oc debug` can be unreliable on Prow AWS (5-minute timeouts). If the Python uses SSH, prefer SSH in Go too
- `StartKubeletSSH` includes `daemon-reload` after start (matches Python's `start_kubelet_on_node`)

### Cleanup & lifecycle
- `DeferCleanup` after Create for simple resources; before Create for resources with complex side effects
- All deletes in `AfterAll`/`DeferCleanup` must use `wait.PollUntilContextTimeout` with warning logging (not `Eventually` which panics on timeout in JustAfterEach)
- Pre-clean stale CRs in BeforeEach before creating new ones
- After deleting a resource, wait with `Eventually` + `IsNotFound` before recreating

### Assertions
- `MatchError(ContainSubstring(...))` not `Expect(err.Error())` -- nil-safe under ContinueOnFailure
- Typed constants (`corev1.NodeReady`) not raw strings (`"Ready"`)
- `Consistently` for "should NOT happen" checks (not single-shot Expect)
- Never discard errors from API calls (`result, _ := pod.List(...)`)

### Labels & documentation
- Every `It` block: `reportxml.ID`, `TierAcceptance`/`TierSmoke`, `DisruptionDestructive`/`NonDestructive`, `PlatformAny`, `FrequencyWeekly`/`FrequencyPresubmit`, component labels
- README pass criteria must list every assertion the code performs (R-49)
- Use `--` (double hyphen) not em dash

## Important

- Always ask before posting GitHub reviews or comments
- Always ask before committing or pushing
- Use `--` (double hyphen) instead of em dash character
- Do not mention other PR numbers in review comments on others' PRs
