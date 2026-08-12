---
name: review-checklist
description: Self-learning review checklist for medik8s/system-tests. Learns from new merged PRs then checks current code against all known patterns. Use before submitting PRs to catch known review patterns early.
---

# PR Review Checklist

## Metadata

- **Last scanned merged_at:** 2026-08-05T17:40:20Z
- **Total rules:** 60
- **Source:** 256 review comments from 37 merged PRs (initial), auto-updated from PRs #61, #62, #70, #72
- **Reviewers:** ugreener (124), gamado (75), razo7 (55), maximunited (26), clobrano (7)
- **Data file:** `docs/system-tests-reviews-complete.json` (for reference only, not a runtime dependency)

## How It Works

Every `/review-checklist` invocation runs two steps automatically:

1. **LEARN** -- fetch newly merged PRs since last scan, update rules
2. **REVIEW** -- check all changed files against ALL rules

## Learn Algorithm

1. Read "Last scanned merged_at" timestamp from the Metadata section above
2. Fetch merged PRs since then:
```bash
GH_TOKEN=$(cat <github-token-path>)  # resolve path from config `tokens.github`
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/medik8s/system-tests/pulls?state=closed&per_page=50&sort=created&direction=desc"
```
3. Filter to PRs where `merged_at` is not null AND `merged_at` > last scanned timestamp. This uses GitHub's UTC server clock (the `Z` suffix), so it works regardless of local timezone and catches PRs that merge out of PR-number order.
4. For each new merged PR, fetch reviewer comments:
```bash
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/medik8s/system-tests/pulls/{N}/comments?per_page=100"
```
5. Filter out bots (`coderabbitai[bot]`, `qodo-*`, `openshift-ci*`) and the PR author
6. For each reviewer comment:
   - Read ALL rules below
   - Does an existing rule cover this pattern? --> Add the PR number to that rule's PR refs
   - No existing rule matches? --> Create a new rule: next R-XX ID, description, bad/good code from the comment's diff context and the merged file, severity, PR ref
7. Update "Last scanned merged_at" in Metadata to the latest `merged_at` timestamp from the processed PRs (UTC, from GitHub API -- same clock as the filter in step 3)
8. Edit this SKILL.md file with any changes

If no new merged PRs exist since last scan, skip silently and proceed to Review.

**IMPORTANT:** Always run the actual curl command above -- never rely on cached results from a previous session. The "Last scanned" PR number in Metadata is the only source of truth for what has been processed.

## Review Algorithm

1. Get changed files:
```bash
git diff --name-only main...HEAD
# or: git diff --name-only origin/main...HEAD
```
2. Read each changed file fully
3. Check **ALL** rules below against each file -- no skipping based on category
4. For each violation found, report:
   - Rule ID and short description
   - Severity (Critical/Major/Minor)
   - File and approximate location
   - The "Bad" pattern found
   - The "Good" pattern to use instead
5. Summary: total violations grouped by severity

---

## Rules

Rules are grouped by topic for readability. **ALL rules are checked every time** regardless of grouping.

### Cleanup & Teardown

#### R-01: DeferCleanup before Create
**Check:** `DeferCleanup` (or cleanup registration) must be registered BEFORE the resource `Create` call, not after. If Create succeeds but a later step panics, cleanup never runs.
**Bad:**
```go
Expect(APIClient.Create(ctx, obj)).To(Succeed())
DeferCleanup(func() { APIClient.Delete(ctx, obj) })
```
**Good:**
```go
DeferCleanup(func() { /* delete obj */ })
Expect(APIClient.Create(ctx, obj)).To(Succeed())
```
**Note:** PR #52 reviewer (ugreener) observed that registering DeferCleanup BEFORE Create causes unnecessary cleanup attempts when Create fails. The FAR pattern registers cleanup AFTER a successful Create. Both patterns are in use -- prefer AFTER Create for simple resources (pods), BEFORE Create for resources with complex side effects.
**Severity:** Critical
**PRs:** #10, #11, #26, #31, #32, #33, #34, #39, #52

#### R-02: Wrap Delete in Eventually
**Check:** Any `APIClient.Delete()` in `AfterAll`, `DeferCleanup`, or cleanup functions must be wrapped in `Eventually` with a timeout. Bare Delete fails permanently on transient API errors.
**Bad:**
```go
deleteErr := APIClient.Delete(ctx, obj)
```
**Good:**
```go
Eventually(func() error {
    err := APIClient.Delete(ctx, obj)
    if k8serrors.IsNotFound(err) { return nil }
    return err
}, timeout, interval).Should(Succeed())
```
**Severity:** Critical
**PRs:** #11, #17, #26, #27, #28, #29, #31, #32, #33, #34

#### R-03: Pre-cleanup stale resources
**Check:** Before creating a test resource, delete any stale instance from a previous interrupted run. Prevents `AlreadyExists` failures on retry.
**Bad:**
```go
// No pre-cleanup -- jumps straight to Create
Expect(APIClient.Create(ctx, newSBRC)).To(Succeed())
```
**Good:**
```go
// Delete stale, wait for NotFound, then create
stale := buildSBRC(testName, map[string]interface{}{})
_ = APIClient.Delete(ctx, stale)
Eventually(func() bool {
    return k8serrors.IsNotFound(APIClient.Get(ctx, ...))
}, timeout, interval).Should(BeTrue())
Expect(APIClient.Create(ctx, newSBRC)).To(Succeed())
```
**Severity:** Critical
**PRs:** #26, #28, #32, #34, #52

#### R-04: Wait for DaemonSet GC after owner delete
**Check:** After deleting an SBRC/NHC, poll with Eventually until the owned DaemonSet returns NotFound before proceeding. Leftover DaemonSets with watchdog locks cause EBUSY crash-loops.
**Bad:**
```go
Expect(APIClient.Delete(ctx, sbrc)).To(Succeed())
// Immediately proceed without waiting for DS cleanup
```
**Good:**
```go
Expect(APIClient.Delete(ctx, sbrc)).To(Succeed())
Eventually(func() bool {
    _, err := ds.Pull(APIClient, dsName, ns)
    return k8serrors.IsNotFound(err)
}, timeout, interval).Should(BeTrue())
```
**Severity:** Critical
**PRs:** #10, #11, #13, #26, #28, #32, #33, #34, #39

#### R-05: Don't strip finalizers in cleanup
**Check:** Do not remove finalizers to bypass operator cleanup logic. This can leave nodes cordoned, DaemonSets orphaned. Use plain Delete and wait.
**Severity:** Major
**PRs:** #27, #29, #31, #33, #34

#### R-06: iptables cleanup: use semicolon not &&
**Check:** iptables rule deletion commands must use `;` between deletions, not `&&`. If the first `-D` fails (rule already removed), `&&` short-circuits and remaining rules stay.
**Bad:**
```bash
iptables -D INPUT -j DROP && iptables -D OUTPUT -j DROP
```
**Good:**
```bash
iptables -D INPUT -j DROP ; iptables -D OUTPUT -j DROP
```
**Severity:** Critical
**PRs:** #27, #29, #31, #32, #33, #34

### Pod Validation

#### R-07: DNS 63-character label limit
**Check:** Pod names must conform to RFC 1123 DNS **label** limit of 63 characters, NOT the DNS subdomain limit of 253. Truncate at 63 and trim trailing dashes.
**Bad:**
```go
podName := fmt.Sprintf("sbr-split-brain-injector-%s-%s", nodeName, testID)
// Can exceed 63 chars with long node names
```
**Good:**
```go
podName := safePodName(fmt.Sprintf("sbr-injector-%s-%s", nodeName, testID))
// safePodName truncates to 63 chars and trims trailing dashes/dots
```
**Severity:** Major
**PRs:** #29, #32, #33, #34

#### R-08: Check container Ready, not just pod Phase
**Check:** `filterRunningPods` must check container-level readiness (`ContainerStatuses[].Ready == true`), not just `Phase == Running`. CrashLoopBackOff pods have Phase=Running.
**Bad:**
```go
if pod.Object.Status.Phase == corev1.PodRunning {
    running = append(running, pod)
}
```
**Good:**
```go
if pod.Object.Status.Phase == corev1.PodRunning {
    allReady := true
    for _, cs := range pod.Object.Status.ContainerStatuses {
        if !cs.Ready { allReady = false; break }
    }
    if allReady { running = append(running, pod) }
}
```
**Severity:** Major
**PRs:** #9, #11, #20, #35, #37, #38, #43

#### R-09: Use label selectors, not name-prefix filtering
**Check:** Use label selectors in `pod.List` calls, not `strings.HasPrefix(pod.Name, ...)`. Name-prefix matching can pick up unrelated pods.
**Bad:**
```go
for _, p := range pods {
    if strings.HasPrefix(p.Definition.Name, "sbr-agent-") { ... }
}
```
**Good:**
```go
pods, err := pod.List(client, ns, metav1.ListOptions{
    LabelSelector: "app=sbr-agent",
})
```
**Severity:** Major
**PRs:** #10, #13, #18, #26, #33

### Error Handling

#### R-10: Never discard errors from any function call
**Check:** Never use `_, err :=` and ignore the result, or `pods, _ := pod.List(...)`. An error causes an empty result, making subsequent assertions vacuously pass. This applies to ALL function calls that return errors -- not just Kubernetes API calls. Helper functions (e.g., `helpers.RunOnNode`), exec calls, and utility functions all count. Even when an error is "expected" (e.g., SSH connection drops during reboot), the error must be captured, inspected, and either asserted or logged -- never silently discarded with `_`.
**Bad:**
```go
pods, _ := pod.List(client, ns, listOpts)
Expect(len(pods)).To(Equal(3))

// Also bad: discarding error from helper function
helpers.RunOnNode(ctx, nodeName, timeout, "systemctl", "reboot")
// RunOnNode returns (string, error) but error is silently lost
```
**Good:**
```go
pods, err := pod.List(client, ns, listOpts)
Expect(err).ToNot(HaveOccurred())
Expect(len(pods)).To(Equal(3))

// Good: capture and handle expected errors explicitly
_, err := helpers.RunOnNode(ctx, nodeName, timeout, "systemctl", "reboot")
// Reboot drops the connection, so a specific error is expected
if err != nil && !isConnectionDropError(err) {
    Expect(err).ToNot(HaveOccurred(), "unexpected error during reboot of %s", nodeName)
}
```
**Severity:** Major
**PRs:** #15, #17, #34, #39, #62

#### R-11: Distinguish IsNotFound from transient errors / fail closed
**Check:** When checking if a resource exists, distinguish `IsNotFound` (genuine absence) from transient API errors. Functions like `isCRDInstalled` must fail closed: return `false` for ALL errors (not just NotFound). Unknown errors must not be treated as "CRD installed" -- that fails open and causes misleading test runs.

**Also applies inside Eventually/Consistently blocks:** When polling for resource absence (e.g., "wait until CR is gone"), use `func() (bool, error)` not `func() bool`. Returning `false` for all errors inside `func() bool` silently retries transient errors (RBAC failures, network timeouts, API overload) until the Eventually timeout, masking the real problem. The `(bool, error)` signature causes Eventually to fail immediately on unexpected errors.
**Bad:**
```go
_, err := client.Get(ctx, key, obj)
if err != nil { return false } // treats ALL errors as "not found"

// Also bad: inside Eventually, masks transient errors as "still exists"
Eventually(func() bool {
    err := APIClient.Get(ctx, client.ObjectKey{Name: name}, obj)
    return k8serrors.IsNotFound(err) // RBAC error? Network timeout? All treated as "not gone yet"
}).Should(BeTrue())
```
**Good:**
```go
_, err := client.Get(ctx, key, obj)
if k8serrors.IsNotFound(err) { return false }
if err != nil { log.Warn("unexpected error"); return false } // fail closed

// Good: inside Eventually, fail fast on unexpected errors
Eventually(func() (bool, error) {
    err := APIClient.Get(ctx, client.ObjectKey{Name: name}, obj)
    if k8serrors.IsNotFound(err) { return true, nil }
    if err != nil { return false, err } // fail fast
    return false, nil // still exists
}).Should(BeTrue())
```
**Severity:** Major
**PRs:** #29, #33, #34, #39, #72

#### R-12: Expect(err.Error()) panics when err is nil
**Check:** `Expect(err.Error())` panics with `ContinueOnFailure` when `err` is nil. Use `Expect(err).To(MatchError(...))` instead.
**Bad:**
```go
Expect(err).To(HaveOccurred())
Expect(err.Error()).To(ContainSubstring("unsupported"))
```
**Good:**
```go
Expect(err).To(MatchError(ContainSubstring("unsupported")))
```
**Severity:** Major
**PRs:** #17

### Resource Lifecycle

#### R-13: Re-pull resources inside Eventually blocks
**Check:** Don't use a snapshot from `BeforeAll` for status checks in `Eventually`. Re-fetch the resource inside the polling function.
**Bad:**
```go
// deployment fetched once in BeforeAll
Eventually(func() int32 {
    return deployment.Object.Status.ReadyReplicas // STALE
}).Should(Equal(int32(2)))
```
**Good:**
```go
Eventually(func() (int32, error) {
    fresh, err := deployment.Pull(client)
    if err != nil { return 0, err }
    return fresh.Object.Status.ReadyReplicas, nil
}).Should(Equal(int32(2)))
```
**Severity:** Major
**PRs:** #11, #13, #26, #32, #33

#### R-14: Track generation for DaemonSet rollouts
**Check:** When verifying DaemonSet rollout after a patch, capture `Generation` BEFORE the patch. Then assert `ObservedGeneration >= Generation` and `NumberReady > 0`.
**Bad:**
```go
// Only checks NumberReady > 0 -- could pass with pre-patch pods
Eventually(func() int32 {
    return ds.Object.Status.NumberReady
}).Should(BeNumerically(">", 0))
```
**Good:**
```go
prePatchGen := ds.Object.Generation
// ... apply patch ...
Eventually(func() bool {
    fresh, _ := ds.Pull(client)
    return fresh.Object.Status.ObservedGeneration >= prePatchGen &&
           fresh.Object.Status.NumberReady > 0
}).Should(BeTrue())
```
**Severity:** Major
**PRs:** #28, #39

#### R-15: Use Consistently for negative assertions
**Check:** Use `Consistently` (not single-shot `Expect`) for "should NOT happen" checks. Single-shot checks have a race window.
**Bad:**
```go
list, _ := client.List(ctx, ...)
Expect(len(list.Items)).To(BeZero()) // single-shot race
```
**Good:**
```go
baseline := len(currentList.Items)
Consistently(func() int {
    list, _ := client.List(ctx, ...)
    return len(list.Items)
}, duration, interval).Should(Equal(baseline))
```
**Severity:** Major
**PRs:** #10, #17, #28, #31, #32, #33

#### R-16: Use MergePatch to avoid resource version conflicts
**Check:** Use `MergePatch` for node operations (uncordoning, label changes) instead of `Get+Update`. Node objects are updated frequently by kubelet -- resource version conflicts are common.
**Severity:** Major
**PRs:** #28, #31

### Security Context

#### R-17: Validate all 7 security context assertions
**Check:** Operator pod security validation must check all 7 fields: `runAsNonRoot(pod)`, `runAsNonRoot(container)`, `runAsUser!=0`, `allowPrivilegeEscalation=false`, `readOnlyRootFilesystem=true`, `capabilities.drop=[ALL]`, `seccompProfile=RuntimeDefault`. Treat `nil` as failure for `AllowPrivilegeEscalation` and `Capabilities`.
**Severity:** Major
**PRs:** #11, #34, #35, #37, #38, #43

### Test Design

#### R-18: ContinueOnFailure with single It is a no-op
**Check:** `ContinueOnFailure` on a `Describe` with a single `It` block provides no benefit and introduces nil-pointer risk if Expect fails.
**Severity:** Minor
**PRs:** #10, #17, #28, #29

#### R-19: Use Ginkgo Skip(), not silent if
**Check:** Use `ginkgo.Skip()` for topology-specific test exclusions (SNO, non-ODF), not plain `if`. Skip makes the omission visible in JUnit/Polarion reports.
**Bad:**
```go
if isSNO {
    return // silently skips -- invisible in reports
}
```
**Good:**
```go
if isSNO {
    Skip("Skipping: requires multi-node cluster")
}
```
**Severity:** Major
**PRs:** #13, #26, #27, #28, #29, #34, #39

#### R-20: Operator dependency checks -- Describe-level AND per-It
**Check:** Each `Describe` block that depends on an operator must include its own `BeforeAll` readiness check. When tests are run via Ginkgo label filtering, other Describe blocks' BeforeAll does not execute.

**Additionally:** Trace the operator dependencies of EACH individual `It` block, not just the Describe. A Describe may check that operator A (e.g., NHC) is installed, but an individual It block inside it may use a template/CRD from operator B (e.g., SNRT from SNR). That It block must check `isBCRDInstalled()` and `Skip()` if absent. Without this, running on a cluster without operator B produces a confusing assertion failure instead of a clean skip.
**Bad:**
```go
Describe("NHC Negative", Label(labels.OperatorNHC), func() {
    BeforeAll(func() {
        // Only checks NHC is installed
        nhcDep, err := deployment.Pull(APIClient, nhcparams.OperatorDeploymentName, ...)
        Expect(err).ToNot(HaveOccurred())
    })
    It("OCP-71184 -- missing namespace in SNRT-based NHC", func() {
        // USES SelfNodeRemediationTemplate but never checks if SNR is installed!
        // Fails with "NHC should become Enabled" instead of Skip
    })
})
```
**Good:**
```go
It("OCP-71184 -- missing namespace in SNRT-based NHC", func() {
    if !isSNRCRDInstalled(ctx) {
        Skip("SelfNodeRemediation CRD not found -- OCP-71184 requires SNRT")
    }
    // ... test using SNRT
})
```
**Severity:** Major
**PRs:** #17, #26, #70, #72

#### R-21: Assert target node does NOT exist before using CR name
**Check:** Non-destructive tests using `CR.metadata.name` as target node name must assert the node does NOT exist first. A cluster with a matching node name would trigger real fencing.
**Severity:** Major
**PRs:** #12, #16, #17, #28, #32, #34

#### R-22: Deterministic selection with sort
**Check:** `candidates[0]` depends on Kubernetes API list ordering, which is not guaranteed stable. Use `sort.Strings(candidates)` before selection.
**Severity:** Minor
**PRs:** #29

### Naming & Constants

#### R-23: Use named constants from *params packages / extract repeated literals
**Check:** Use constants from `sbrparams`, `snrparams`, `farparams`, `medik8sparams` instead of hardcoded strings and durations. Use existing variables (e.g., `operatorNs`) instead of re-declaring. Use typed constants like `corev1.NodeReady` instead of raw strings `"Ready"`.

**Additionally:** Any string literal or status/reason value that appears 3 or more times in a file (or 2+ times across files) MUST be extracted to a named constant in the appropriate `*params/const.go`. This includes error reason strings, annotation keys, label values, phase names, and condition types -- not just CR names and timeouts.
**Bad:**
```go
// "RemediationTemplateNotFound" appears 4 times in the file
Expect(reason).To(ContainSubstring("RemediationTemplateNotFound"))
// ... 3 more identical occurrences
```
**Good:**
```go
// In nhcparams/const.go:
NHCReasonTemplateNotFound = "RemediationTemplateNotFound"

// In test file:
Expect(reason).To(ContainSubstring(nhcparams.NHCReasonTemplateNotFound))
```
**Severity:** Minor
**PRs:** #8, #16, #17, #20, #26, #28, #29, #33, #34, #43, #70

#### R-24: No hardcoded durations -- use named constants
**Check:** Use `medik8sparams.DefaultTimeout` (300s) for `Eventually` timeouts, not hardcoded `30*time.Second` or other values. This rule applies to ALL duration values, not just `Eventually` timeouts -- including timeouts passed to helper functions (`helpers.RunOnNode(ctx, node, 2*time.Minute, ...)`), `time.Sleep` calls, and any other place a duration appears. If all other timeouts in a file use `*params` constants, a hardcoded `2*time.Minute` sticks out and should be a constant too.
**Bad:**
```go
Eventually(..., 30*time.Second, 5*time.Second)

// Also bad: hardcoded timeout in helper call when all other timeouts use constants
helpers.RunOnNode(ctx, nodeName, 2*time.Minute, "systemctl", "reboot")
```
**Good:**
```go
Eventually(..., medik8sparams.DefaultTimeout, sbrparams.DefaultPollInterval)

// Good: named constant in *params/const.go
helpers.RunOnNode(ctx, nodeName, nmoparams.RunOnNodeTimeout, "systemctl", "reboot")
```
**Severity:** Minor
**PRs:** #13, #16, #18, #28, #29, #31, #34, #39, #62

#### R-25: Remove unused constants
**Check:** Remove constants defined but never referenced. Dead code creates drift risk if operator values change.
**Severity:** Minor
**PRs:** #16, #28, #32, #34

#### R-26: No em dash characters
**Check:** Use `--` (double hyphen) instead of em dash character (U+2014). Project convention.
**Severity:** Minor
**PRs:** #29

### Labels & CI

#### R-27: Granular Ginkgo labels -- required on every It, deduplicated to Describe
**Check:** Every `It` block must have: `labels.TierSmoke` (or TierAcceptance), `labels.DisruptionNonDestructive` (or Destructive), `labels.PlatformAny`, `labels.Frequency*`, component labels, AND operator labels (`labels.OperatorSNR`, `labels.OperatorFAR`, etc.).

**Additionally:** When ALL It blocks within a Describe/Context share identical labels (e.g., all have `DisruptionNonDestructive, FrequencyWeekly`), those shared labels MUST be moved to the Describe/Context-level `Label()` call and removed from each It. This ensures any future test added inherits them automatically and avoids redundant repetition. Check sibling Describe blocks in the same package for established patterns.
**Bad:**
```go
Describe("NHC Negative", Label(labels.OperatorNHC), func() {
    It("test 1", Label(labels.DisruptionNonDestructive, labels.FrequencyWeekly, ...), ...)
    It("test 2", Label(labels.DisruptionNonDestructive, labels.FrequencyWeekly, ...), ...)
    It("test 3", Label(labels.DisruptionNonDestructive, labels.FrequencyWeekly, ...), ...)
    // Same labels repeated on every It
})
```
**Good:**
```go
Describe("NHC Negative",
    Label(labels.OperatorNHC, labels.DisruptionNonDestructive, labels.FrequencyWeekly),
    func() {
    It("test 1", Label(labels.TierSmoke, ...), ...) // only It-specific labels
    It("test 2", Label(labels.TierAcceptance, ...), ...)
})
```
**Severity:** Minor
**PRs:** #13, #17, #19, #37, #43, #70

#### R-28: reportxml.ID for Polarion tracking
**Check:** Every `It` block with a Polarion test case must have `reportxml.ID("NNNNN")`. Do NOT reuse IDs across different It blocks -- duplicates cause one result to overwrite the other.
**Severity:** Minor
**PRs:** #11, #17, #19, #25, #32, #44

### Code Duplication

#### R-29: Extract shared helpers / eliminate all duplication
**Check:** Common functions (`filterRunningPods`, `fetchActiveCSV`, `filterPodsByDeployment`, security context validation) must live in `tests/internal/helpers/`, not be copy-pasted per operator.

**This rule covers THREE forms of duplication, all of which must be checked:**

1. **Cross-file duplication:** The same function appears in two operator directories. Extract to `tests/internal/helpers/`.

2. **Intra-file duplication:** The same multi-line code block (3+ lines) appears 2 or more times within ONE file. This is the most commonly missed form. Look for identical `Eventually` blocks, identical assertion sequences, identical setup/teardown patterns within a single file. Extract to a local helper function.
**Bad:**
```go
// Block repeated 4 times in the same file:
Expect(waitForNHCPhase(ctx, nhcName, "Disabled", timeout)).To(Succeed())
Eventually(func(g Gomega) {
    reason, err := getNHCReason(ctx, nhcName)
    g.Expect(err).ToNot(HaveOccurred())
    g.Expect(reason).To(ContainSubstring("RemediationTemplateNotFound"))
}).WithPolling(interval).WithTimeout(timeout).Should(Succeed())
```
**Good:**
```go
// Extracted to a helper function:
verifyNHCDisabledWithReason(ctx, nhcName, nhcparams.NHCReasonTemplateNotFound, timeout)
```

3. **Near-duplicate / structural duplication:** Multiple functions have identical structure but differ only in one parameter (e.g., field name, type). Extract a generic parameterized function and make each original a one-line wrapper.
**Bad:**
```go
func getNHCPhase(ctx, name) (string, error)     { /* fetch NHC, extract status.phase */ }
func getNHCReason(ctx, name) (string, error)     { /* fetch NHC, extract status.reason */ }
func getNHCObservedNodes(ctx, name) (int64, error) { /* fetch NHC, extract status.observedNodes */ }
func getNHCHealthyNodes(ctx, name) (int64, error)  { /* fetch NHC, extract status.healthyNodes */ }
// 4 functions with identical structure, ~50 lines of duplication
```
**Good:**
```go
func getNHCStatusString(ctx, name, field string) (string, error) { /* generic */ }
func getNHCStatusInt64(ctx, name, field string) (int64, error) { /* generic */ }
func getNHCPhase(ctx, name) (string, error) { return getNHCStatusString(ctx, name, "phase") }
```
**Severity:** Minor
**PRs:** #9, #11, #17, #27, #28, #29, #32, #33, #34, #35, #37, #38, #52, #70, #72

### Established Patterns

#### R-30: Use csv.GetPhase() not .Object.Status.Phase
**Check:** Use the accessor method `csv.GetPhase()` instead of direct field access `csv.Object.Status.Phase`. Established pattern across all medik8s operators.
**Severity:** Minor
**PRs:** #13, #18

#### R-31: Check annotation values, not just keys
**Check:** Annotation/label checks should verify values are non-empty, not just that keys exist. `support: ""` should fail.
**Bad:**
```go
_, hasSupport := csv.Object.Annotations["support"]
Expect(hasSupport).To(BeTrue())
```
**Good:**
```go
support := strings.TrimSpace(csv.Object.Annotations["support"])
Expect(support).ToNot(BeEmpty())
```
**Severity:** Minor
**PRs:** #13, #17

### Assertions & Error Messages

#### R-32: Collect errors into slice, Fail with consolidated message
**Check:** Don't fail on the first missing annotation/label. Collect all mismatches into a slice, then `Fail()` once with a consolidated message showing all failures.
**Bad:**
```go
Expect(csv.Object.Annotations["support"]).ToNot(BeEmpty())
// Stops here if this fails -- never checks remaining annotations
Expect(csv.Object.Annotations["repository"]).ToNot(BeEmpty())
```
**Good:**
```go
var errs []string
for _, key := range requiredAnnotations {
    if val := csv.Object.Annotations[key]; val == "" {
        errs = append(errs, fmt.Sprintf("missing %s", key))
    }
}
if len(errs) > 0 { Fail(strings.Join(errs, "; ")) }
```
**Severity:** Minor
**PRs:** #13

#### R-33: Include LeaseList in ReporterCRDsToDump
**Check:** `ReporterCRDsToDump` must include `corev1.LeaseList` for leader election diagnostics when controller pods misbehave.
**Severity:** Minor
**PRs:** #13

#### R-34: By() labels must match what's being checked
**Check:** The string in `By("checking X")` must accurately describe what the subsequent assertions verify. Don't say "infrastructure annotations" if the check includes non-infrastructure annotations.
**Severity:** Minor
**PRs:** #13

#### R-35: Go naming conventions -- capitalize after initialisms
**Check:** Follow Go naming: capitalize the letter after an initialism. `SBRCsplitBrainTestName` should be `SBRCSplitBrainTestName`.
**Severity:** Minor
**PRs:** #29

#### R-36: Unique --focus strings per test
**Check:** Each test must have a unique `--focus` pattern for standalone execution. Two tests sharing the same focus string always run together, defeating isolation.
**Severity:** Minor
**PRs:** #17, #52

#### R-37: Use Context wrappers for Ginkgo grouping
**Check:** Related `It` blocks should be wrapped in `Context` for better Ginkgo output grouping and JUnit readability.
**Severity:** Minor
**PRs:** #17, #28, #52

### CI & Build Config

#### R-38: dnf clean all in Dockerfiles
**Check:** Use `dnf clean all`, not `dnf clean metadata packages`. The latter leaves `dbcache` and `expire-cache` behind, producing a larger image layer.
**Severity:** Minor
**PRs:** #19

#### R-39: Consistent indentation in shell scripts
**Check:** Standardize on 4-space indentation in shell scripts. Don't mix tabs and spaces within the same file.
**Severity:** Minor
**PRs:** #12, #25

#### R-40: Use .Object.Name not .Definition.Name for pod list results
**Check:** For pods returned by `pod.List`, use `.Object.Name` consistently. `.Definition.Name` works but is inconsistent with the rest of the codebase.
**Severity:** Minor
**PRs:** #26

#### R-41: Comments must match current code
**Check:** When refactoring, update comments and docstrings to match the new behavior. Stale comments describing old API contracts (e.g., "returns empty string" when it now returns error) are misleading. Also applies to stale test numbering references (e.g., "Test 11" when README says "Test 19").
**Severity:** Minor
**PRs:** #32, #34, #52

#### R-42: Diagnostic detail in ALL error paths
**Check:** Error messages and error returns must include enough context to diagnose what went wrong. This applies to ALL error paths, not just test assertions:

1. **Test assertions:** Must identify specific pod and container names, not just counts. "not ready: pod-a container-x" is better than "expected 3, got 1".
2. **Helper function error returns:** Must wrap errors with context using `fmt.Errorf("operation on %s: %w", name, err)`. A bare `return "", err` from a helper function produces an opaque error when Eventually times out. The wrapping must identify WHICH resource (CR name, node name, field name) was being accessed.
**Bad:**
```go
func getNHCReason(ctx context.Context, name string) (string, error) {
    if err := APIClient.Get(ctx, key, obj); err != nil {
        return "", err // bare error -- which NHC? what operation?
    }
}
```
**Good:**
```go
func getNHCReason(ctx context.Context, name string) (string, error) {
    if err := APIClient.Get(ctx, key, obj); err != nil {
        return "", fmt.Errorf("getting NHC %s reason: %w", name, err)
    }
}
```
**Severity:** Major
**PRs:** #43, #70

#### R-43: nil vs empty map consistency
**Check:** Use `map[string]interface{}{}` (empty map), not `nil`, when calling helpers like `buildSBRC`. Consistent with all other call sites.
**Severity:** Minor
**PRs:** #26

#### R-44: Avoid unnecessary sh -c wrappers in ExecCommand
**Check:** Don't use `sh -c "test -c /dev/watchdog"` when you can call the binary directly. Shell wrappers add quoting complexity and failure modes.
**Severity:** Minor
**PRs:** #19

#### R-45: Don't shadow imported modules
**Check:** Don't assign to a variable name that shadows an imported package. `html = build_html(...)` shadows the `html` module.
**Severity:** Minor
**PRs:** #15

#### R-46: Validate inputs before exec
**Check:** Check for empty `nodeName` or `cmd` before calling `oc debug node/`. Empty nodeName produces confusing errors; empty cmd drops into an interactive shell that hangs.
**Severity:** Major
**PRs:** #23

#### R-47: Error match specificity
**Check:** Don't match broad substrings like `"EOF"` or `"timed out"` in error strings -- it catches unrelated errors. Use the specific error type or a more precise substring (e.g., `"oc debug on node X timed out"`).
**Severity:** Major
**PRs:** #23, #52

#### R-48: Keep Describe block names concise
**Check:** Ginkgo concatenates `Describe` + `It` names into the full test name for JUnit. Long Describe names hurt CI dashboard readability. Keep them under ~60 characters.
**Severity:** Minor
**PRs:** #32

#### R-49: README pass criteria must match actual test assertions
**Check:** Each test's README pass criteria must list every assertion the test code performs, and nothing it doesn't. Common omissions: `suggested-namespace` annotation, container existence check from `ValidateNonRootSecurityContext`, container readiness (not just pod phase), `CreationTimestamp` unchanged verification. Don't claim etcd health if the test doesn't check etcd.
**Bad:**
```markdown
- **Pass criteria**: All pods Running, count matches expected replicas
```
**Good:**
```markdown
- **Pass criteria**: All pods Running with all containers ready, count matches expected replica count (1)
```
**Severity:** Minor
**PRs:** #50, #51, #52

#### R-50: README annotation list must match code
**Check:** When the README lists specific annotation names in pass criteria, the list must match the actual `RequiredAnnotations` map in the `*params` package. Don't copy from another operator's README -- check the code.
**Severity:** Minor
**PRs:** #51

#### R-51: Disconnected-incompatible images in README Environment field
**Check:** If a test uses a container image from a public registry (e.g., `registry.k8s.io/pause:3.9`), the README Environment field must say "Connected" not "Connected or disconnected". Public registry images are not available on disconnected clusters unless explicitly mirrored.
**Bad:**
```markdown
- **Environment**: Connected or disconnected
```
when the test uses `registry.k8s.io/pause:3.9`
**Good:**
```markdown
- **Environment**: Connected (pause image needs registry.k8s.io)
```
**Severity:** Minor
**PRs:** #52

#### R-53: Migration code must match Python mechanism, not just logic
**Check:** When porting from Python to Go, the Go code must use the same underlying mechanism as the Python, not just produce the same visible result. Common mismatches:
- Python `del obj['key']` removes a field -- Go equivalent is JSON merge patch with `null`, NOT setting to `""` (empty string persists in the API server)
- Python `invoke_ssh_on_the_node` uses SSH -- Go must use SSH too (not `oc debug`) when kubelet is stopped
- Python `create_api_object` may do server-side apply -- Go `APIClient.Create` does create-only (different conflict behavior)
**Bad:**
```go
// Python uses: del nhc_cr['spec']['remediationTemplate']['namespace']
// Go WRONG: sets empty string instead of removing the field
patch := []byte(`{"spec":{"remediationTemplate":{"namespace":""}}}`)
```
**Good:**
```go
// Python uses: del nhc_cr['spec']['remediationTemplate']['namespace']
// Go CORRECT: null removes the key per RFC 7396
patch := []byte(`{"spec":{"remediationTemplate":{"namespace":null}}}`)
```
**Severity:** Critical
**PRs:** #59

#### R-54: No internal rule references in code comments
**Check:** Code comments must not reference internal review rule IDs (R-01, R-28, etc.) from the review-checklist skill. These IDs are meaningful only inside the skill file and opaque to anyone reading the code. Instead, explain the *reason* directly.
**Bad:**
```go
// Both kept in one It block to avoid duplicating reportxml.ID (R-28).
```
**Good:**
```go
// Both kept in one It block to avoid duplicating reportxml.ID --
// duplicate IDs cause one Polarion result to overwrite the other.
```
**Severity:** Minor
**PRs:** #59

#### R-52: Eventually in JustAfterEach stops remaining cleanup on timeout
**Check:** `Eventually().Should(Succeed())` in `JustAfterEach` calls `Fail()` on timeout, which panics and stops executing the rest of the cleanup. Subsequent cleanup steps (FART deletion, node recovery) are skipped, leaving the cluster in a dirty state. Use `wait.PollUntilContextTimeout` with warning logging instead.
**Bad:**
```go
JustAfterEach(func() {
    Eventually(func() error { return client.Delete(...) }).Should(Succeed())
    // These never run if Eventually above times out:
    cleanupTemplate(...)
    waitForNodeReady(...)
})
```
**Good:**
```go
JustAfterEach(func() {
    if waitErr := wait.PollUntilContextTimeout(...); waitErr != nil {
        GinkgoWriter.Printf("Warning: cleanup timed out: %v\n", waitErr)
    }
    // Always runs:
    cleanupTemplate(...)
    waitForNodeReady(...)
})
```
**Severity:** Critical
**PRs:** #49

### Type Safety & Go Idioms

#### R-55: Use checked type assertions, not bare assertions
**Check:** Never use bare (unchecked) Go type assertions like `x.(map[string]interface{})` in test code. If the assertion fails at runtime, it panics with an unhelpful stack trace. Use the two-value form `val, ok := x.(Type)` with a Ginkgo assertion on `ok`, or extract a typed helper function that does checked assertions.

This is especially common when working with `unstructured.Unstructured` objects, where spec/status fields are `interface{}`.
**Bad:**
```go
spec := nhc.Object["spec"].(map[string]interface{})
conditions := spec["unhealthyConditions"].([]interface{})
cond := conditions[0].(map[string]interface{})
// Any of these panics if the structure doesn't match
```
**Good:**
```go
func nhcSpec(nhc *unstructured.Unstructured) map[string]interface{} {
    GinkgoHelper()
    spec, ok := nhc.Object["spec"].(map[string]interface{})
    Expect(ok).To(BeTrue(), "NHC object has no map spec")
    return spec
}
// Usage: spec := nhcSpec(nhc)
```
**General intent:** Any `.(Type)` in the diff without the `, ok` two-value form is a violation. This includes nested assertions inside loops and deeply chained accesses.
**Severity:** Major
**PRs:** #72

#### R-56: Match sibling Describe decorators for consistency
**Check:** When adding a new `Describe` block to a package that already has existing Describes, match the decorator list (Serial, Ordered, ContinueOnFailure, etc.) for consistency. Different decorator lists within the same package cause confusing behavior differences and signal that the author didn't review existing patterns.

Check sibling `*_test.go` or `*.go` files in the same package directory for established patterns.
**Bad:**
```go
// Existing Describe in nhc_remediation_trigger.go:
Describe("NHC Remediation", Serial, Ordered, ContinueOnFailure, ...)

// New Describe in nhc_negative_validation.go:
Describe("NHC Negative", Serial, Ordered, ...) // Missing ContinueOnFailure
```
**Good:**
```go
// Match the established pattern:
Describe("NHC Negative", Serial, Ordered, ContinueOnFailure, ...)
```
**Severity:** Minor
**PRs:** #72

### Documentation & Environment

#### R-57: Document required environment variables in README
**Check:** When adding a runtime requirement for an environment variable (especially `panic()` or `log.Fatal()` on missing env var), the variable must be documented in the relevant README's environment or prerequisites section. Runtime-only error messages are not discoverable by users reading setup docs. If the README already documents the variable, no change is needed -- but verify.
**Bad:**
```go
// Code panics if WORKLOAD_IMAGE is not set, but README doesn't mention it
panic("WORKLOAD_IMAGE env var is required")
```
**Good:**
```markdown
## Environment Variables
| Variable | Required | Description |
|---|---|---|
| `WORKLOAD_IMAGE` | Yes | Container image for test workload pods. In Prow CI... |
```
**Severity:** Minor
**PRs:** #61

### Namespace & Resource Isolation

#### R-58: Do not create test resources in the default namespace
**Check:** Tests must not create pods, ConfigMaps, or other resources in the `default` namespace. Use a dedicated test namespace (e.g., `medik8sparams.OperatorNs` or a test-specific namespace) to avoid collisions with other workloads, parallel test suites, or restrictive RBAC policies on the default namespace.
**Bad:**
```go
pod := &corev1.Pod{
    ObjectMeta: metav1.ObjectMeta{
        Name:      "test-workload",
        Namespace: "default", // or no namespace specified (defaults to "default")
    },
}
```
**Good:**
```go
pod := &corev1.Pod{
    ObjectMeta: metav1.ObjectMeta{
        Name:      "test-workload",
        Namespace: nmoparams.TestNamespace, // or medik8sparams.OperatorNs
    },
}
```
**Severity:** Minor
**PRs:** #62

### Migration & Coverage

#### R-59: Compare new test coverage against operator source e2e
**Check:** When writing system tests for an operator, compare the test coverage against the operator's OWN e2e test suite (usually in the operator's source repo, e.g., `node-maintenance-operator/test/e2e/`). Flag significant coverage gaps as review comments. Common gaps:

- **Webhook validation:** Duplicate CR rejection, immutable field patching
- **Kubernetes events:** Operator-emitted events (BeginMaintenance, SucceedMaintenance, RemovedMaintenance)
- **Taints and leases:** Operator-managed taints (e.g., `medik8s.io/drain` NoSchedule), maintenance lease creation/validation/cleanup
- **Drain behavior:** Workload drain/migration to other nodes, drain timeout handling
- **Status fields:** CR status transitions and status field validation

Not all source e2e tests need to be ported to system tests (some are unit-level), but the reviewer should document which source behaviors are intentionally omitted and why.
**Severity:** Minor
**PRs:** #62

#### R-60: Use GinkgoHelper() or WithOffset in helper assertion functions
**Check:** Helper functions that call `Expect()`, `Eventually()`, or other Ginkgo assertions directly must either call `GinkgoHelper()` at the top (Ginkgo v2+) or use `ExpectWithOffset(1, ...)` / `EventuallyWithOffset(1, ...)`. Without this, assertion failures report the file/line of the helper function, not the caller -- making it hard to identify which test failed.
**Bad:**
```go
func deleteAndWaitForResource(ctx context.Context, name string) {
    Expect(APIClient.Delete(ctx, obj)).To(Succeed())
    // Failure points here, not at the call site
    Eventually(func() bool {
        return k8serrors.IsNotFound(APIClient.Get(ctx, key, obj))
    }).Should(BeTrue())
}
```
**Good:**
```go
func deleteAndWaitForResource(ctx context.Context, name string) {
    GinkgoHelper() // All failures report at the caller's location
    Expect(APIClient.Delete(ctx, obj)).To(Succeed())
    Eventually(func() bool {
        return k8serrors.IsNotFound(APIClient.Get(ctx, key, obj))
    }).Should(BeTrue())
}
```
**Severity:** Minor
**PRs:** #62

---

## PR Process Reminders

These are not code rules but review workflow patterns:

- Run `gofmt -w` before committing
- Include Polarion links in PR description: `[OCP-XXXXX](<polarion-base-url>/workitem?id=OCP-XXXXX)` (resolve base URL from config `urls.polarion`)
- Reply to each review comment with "Fixed in <commit>" and reference the fix
- Before adding a new rule to this file: check if an existing rule already covers the same pattern -- merge, don't duplicate

## Pre-Commit Review Steps

**MANDATORY: Run ALL steps every time. Never skip any step regardless of change size.**
Present all findings in tables and let the user decide what to fix before making changes.

### Step 1: Launch 3 review agents in ONE message

**CRITICAL: Send exactly ONE message containing exactly 3 `Agent` tool calls.**
Do NOT launch agents one at a time. Do NOT run reviews inline with grep/bash.
One message, three Agent calls, all parallel. No exceptions.

Each agent runs in ISOLATION -- no session context, no awareness of the other agents
or who wrote the code. The prompt must be fully self-contained: repo path, branch name,
how to find changed files, what to check, and how to report. Every agent must be told
to be aggressive, suspicious, and assume the code has bugs.

**Agent A: Dynamic Learning Reviewer** -- `Agent(subagent_type="reviewer", run_in_background=true)`

This is the only agent that knows our learned rules from past PR reviews.

Prompt must be self-contained and include:
- Repository path and branch name
- How to find changed files: `git diff --name-only main...HEAD`
- LEARN instructions: fetch newly merged PRs since `<last-scanned-timestamp>` (from Metadata
  section above). Use `curl` with GitHub token at `~/.github-token`. For each new merged PR,
  fetch review comments, filter bots (`coderabbitai[bot]`, `qodo-*`, `openshift-ci*`), check
  if any comment introduces a pattern not covered by the rules. Report any new rules found.
- The full list of rules R-01 through R-XX (copy all rule IDs and their one-line descriptions
  into the prompt so the agent has them without needing to read this file)
- Instruction: go through EVERY rule as a general guideline. Scan the code for the INTENT
  behind each rule, not specific known patterns. Do not grep for examples from the rule --
  read the code and judge whether the rule's intent is violated.
- Read 2-3 sibling test files from the same operator directory for pattern comparison.
- Be aggressive: flag anything that looks wrong, don't give benefit of the doubt.
- Report format: Rule ID | Severity | File:Line | Issue | Recommendation

**Agent B: Code Analyzer** -- `Agent(subagent_type="code-analyzer", run_in_background=true)`

General-purpose aggressive code reviewer. No awareness of our learned rules.

Prompt must be self-contained and include:
- Repository path and branch name
- How to find changed files: `git diff --name-only main...HEAD`
- Read ALL changed files fully. Read 2-3 existing test files from the same operator
  directory (or sibling operator) for comparison.
- You are an aggressive code reviewer. Assume the code was written by an AI coding agent
  that makes mistakes. Assume the code has bugs until proven otherwise.
- Check: duplication (intra-file AND cross-file), naming conventions, unused code/constants,
  import hygiene, error handling completeness, codebase consistency (formatting, style,
  blank line patterns vs sibling files), hallucinated APIs (verify imports and function calls
  exist in the vendor directory), pattern drift (new code contradicting established codebase
  patterns), incomplete error handling, plausible-but-wrong logic, abandoned scaffolding.
- Report format: Category | Severity | File:Line | Issue | Recommendation

**Agent C: Adversarial Reviewer** -- `Agent(subagent_type="reviewer", run_in_background=true)`

General-purpose aggressive code reviewer. No awareness of our learned rules.
Independent from Agent B -- a second pair of eyes on the same code.

Prompt must be self-contained and include:
- Repository path and branch name
- How to find changed files: `git diff --name-only main...HEAD`
- Read ALL changed files fully. Read 2-3 existing test files from the same operator
  directory (or sibling operator) for comparison.
- You are an adversarial reviewer. Your job is to FIND PROBLEMS, not confirm the code
  is good. Assume the code was written by an AI agent that often produces plausible-but-wrong
  code. Assume previous reviewers missed critical issues.
- Check: correctness (does the code actually test what it claims?), error handling (every
  error path, including helpers), resource cleanup (what happens if a test panics mid-way?),
  assertion strength (are assertions testing the right thing?), race conditions, cross-file
  conflicts (shared CRDs, global state, CR name collisions with other test files), mechanism
  fidelity (if migrating from another language, does the Go code match the original mechanism?).
- Report format: Category | Severity | File:Line | Issue | Recommendation

### Step 2: Consolidate and present ALL findings

Wait for all 3 agents to complete. Present ALL findings from ALL agents -- do NOT
deduplicate or filter. Show which agent found each issue. If multiple agents found the
same issue, that strengthens the finding. Discuss every finding with the user.

Do NOT make changes until the user approves.

### Step 3: Build verification

After the user approves fixes (or if no fixes needed):
```bash
export PATH=/usr/local/go/bin:$HOME/go/bin:$PATH
go build ./...
go vet ./...
gofmt -l <changed-directories>
```
All three must pass clean.

### Step 4: README update

If the PR adds, removes, or modifies test specs (`It` blocks), the operator's `README.md`
must be updated to match. Each test entry needs: numbered heading with Polarion link,
description, Operators/Cluster/Environment/Standalone/Pass criteria fields.

### Step 5: CI test coverage

If the PR has a completed Prow CI run, run `/prow-investigate <PR>` and cross-reference:
- Extract all `reportxml.ID` values from changed Go files (the PR's Polarion IDs)
- Check each ID appears in the CI test results as **PASSED** (not SKIPPED or absent)
- If any PR test was **SKIPPED**: flag as **Critical** -- report which test, and the skip
  reason from the log
- If any PR test is **absent** from results: flag as **Critical** (test may not be wired
  into the ginkgo suite or label filter excluded it)
- A CI run where all existing tests pass but all NEW tests are skipped is a **false green**
  -- the PR's actual changes were never validated
