---
name: migrate-snr-test
description: Migrate SNR E2E tests from Python (ocp-edge-auto) to Go (medik8s/system-tests). Covers the full flow from Jira planning through PR creation.
user_invocable: true
---

# Migrate SNR Test Skill

Migrate SNR E2E tests from the Python ocp-edge-auto framework to Go in medik8s/system-tests.

## Flow

### Plan
1. Identify the relevant Jira ticket(s) under RHWA-836 epic. Check if a sub-task exists for the tests being migrated. If not, suggest creating one and linking it properly.

### Prep
2. Pull latest main in `repos/system-tests` and latest in the Python source repo (ask user for location if not known)
3. Create a feature branch with a meaningful name (e.g. `feat/snr-phase2.1b-config-lifecycle`)
4. Read the Python source tests from `<python-source>/edge_tests/management/cluster_life_cycle/` -- read the **full implementation**:
   - The test method body (what it verifies)
   - **Every helper function** the test calls (e.g. `stop_kubelet_on_node` uses SSH, not `oc debug`)
   - The class `teardown_method` (recovery logic not in the Polarion plan)
   - The Polarion test plan describes WHAT to verify; Python shows HOW. Follow both.

### Learn from history
5. Read all merged and open PRs in the repo -- review comments that led to code fixes. Extract patterns and standards to follow. Do not limit to our own PRs -- read all of them.

### Implement
6. Write the Go test file following patterns learned from step 5
7. Add any new constants/vars to `snrparams/`
8. Update `helpers.go` if shared helpers are needed

### Verify
9. Run lint and build checks. Ensure Go 1.26+ and golangci-lint are in PATH.
   ```bash
   export PATH=/usr/local/go/bin:$HOME/go/bin:$PATH
   gofmt -l tests/snr-operator/
   make lint    # runs golangci-lint with repo's config -- catches unlambda, varnamelen, etc.
   go build ./tests/snr-operator/...
   ```
10. Fix any issues found
11. Run code review skills:
    - `/simplify` -- review for reuse, quality, efficiency
    - `/github:code-review` -- comprehensive AI-powered code review
12. **GATE -- do not skip:** Run tests on a real cluster and confirm they pass. Use `/run-system-tests` skill. If no cluster is available, ask the user which cluster to use. Do NOT proceed to Ship until tests pass.

### Ship
13. Commit to branch, push to `gamado` fork
14. Create PR with description, Polarion ID hyperlinks (resolve Polarion base URL from config `urls.polarion`), and test plan
15. Look up the correct Jira ticket, update it with the PR link, move to "In Review"

### Post-PR
16. Check for reviewer comments, address feedback

## Key references

- Python source: ask user for ocp-edge-auto location (typically `edge_tests/management/cluster_life_cycle/`)
- Go target: `repos/system-tests/tests/snr-operator/`
- SNR params: `repos/system-tests/tests/snr-operator/internal/snrparams/`
- Jira epic: RHWA-836
- SNR story: RHWA-1073
- Git remote for push: `gamado`
- GitHub API: use curl with token from config `tokens.github` (not gh CLI)
- Jira API: use REST with token from config `tokens.jira`

## Coding patterns from merged PR reviews

Extracted from reviewer comments (ugreener, razo7) that led to code fixes across all merged PRs.
**Last PR analyzed: #29 (merged 2026-06-24), plus review feedback from PR #39.**
On future runs, only query PRs merged after #29.

### Naming & structure
- Use `Context` wrappers around `It` blocks for better Ginkgo output grouping
- `Ordered` is only needed when `BeforeAll` exists or tests depend on execution order
- Go naming convention: initialisms stay uppercase (`SBRCSplitBrainTestName` not `SBRCsplitBrainTestName`)
- Constants that are only used in one test file can stay file-scoped; shared ones go in `snrparams`

### Cleanup & lifecycle
- `DeferCleanup` must be registered **before** the resource is created, so cleanup runs even if Create fails
- All deletes in `AfterAll`/`DeferCleanup` must be wrapped in `Eventually` -- API server may be briefly unreachable after node reboots
- If `Create` might unexpectedly succeed (e.g. testing rejection), guard with `if err == nil { deferDeleteCR(cr) }`
- After deleting a resource, wait with `Eventually` + `IsNotFound` before recreating -- async finalizers can race

### Assertions
- Use `MatchError(ContainSubstring(...))` not `Expect(err.Error())` -- the latter panics on nil with `ContinueOnFailure`
- Use typed constants (`corev1.NodeReady`, `corev1.PodRunning`) not raw strings (`"Ready"`, `"Running"`)
- When asserting multiple error substrings, collect mismatches into a slice and fail once with a consolidated message
- Stale snapshots: don't reuse a fetched object across multiple `It` blocks -- re-fetch inside `Eventually`
- Never silently discard errors from API calls (e.g. `result, _ := pod.List(...)`) -- use `Expect(err).ToNot(HaveOccurred())` in Ginkgo contexts, or propagate the error. A silently-empty result causes downstream checks to vacuously pass

### Pod & DaemonSet checks
- Pod name limit is 63 chars (RFC 1123 DNS label), not 253 (DNS subdomain)
- `filterRunningPods` should also check container-level readiness -- `Phase == Running` doesn't mean containers are ready
- When listing DS pods, use the label selector from `snrparams.DaemonSetPodLabelSelector`, not namespace-wide queries

### Labels & documentation
- Every `It` block needs granular labels: `TierAcceptance`/`TierSmoke`, `DisruptionNonDestructive`, `PlatformAny`, `FrequencyWeekly`/`FrequencyPresubmit`, `ComponentController`/`ComponentDaemonSet`
- `reportxml.ID` must be unique per test -- duplicate Polarion IDs cause one result to overwrite another
- README must document new tests with Polarion hyperlinks

### Misc
- Doc comments must match actual function behavior (don't describe old API contracts after refactoring)
- `nsenter` commands should use `--` delimiter to separate nsenter flags from the target command
- Shell commands in containers: avoid unnecessary `sh -c` wrappers when calling a single binary
- Don't hardcode port numbers or template names inline -- use constants from `snrparams`
- `strings.Fields` already handles all whitespace splitting including newlines -- no need for outer newline split + inner Fields

## Important

- Always ask before posting GitHub reviews or comments
- Check other reviewers' open comments before drafting reviews
- Use `--` (double hyphen) instead of em dash character
- Do not mention other PR numbers in review comments on others' PRs
