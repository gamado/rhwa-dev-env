# Prow CI Investigation

Investigate Prow CI job failures (or verify passing runs) for medik8s/system-tests PRs.

## Usage

```
/prow-investigate <PR-number> [job-name]
```

### Arguments

- **PR-number** (required): The PR number in medik8s/system-tests (e.g. `59`)
- **job-name** (optional): Prow job name suffix. Default: `4.22-konflux-e2e-nhc-aws`
  - Other jobs: `4.22-konflux-e2e-snr-aws`, `4.22-konflux-e2e-far-aws`, etc.
  - Use `all` to check all jobs for the PR

### Examples

```
/prow-investigate 59                              → investigate NHC job for PR 59
/prow-investigate 59 4.22-konflux-e2e-snr-aws     → investigate SNR job for PR 59
/prow-investigate 59 all                           → check all jobs for PR 59
```

## Implementation

### Step 1: Get PR and CI status

```bash
GH_TOKEN=$(cat <github-token-path>)  # resolve path from config `tokens.github`

# Get PR details (head SHA, branch, status)
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/medik8s/system-tests/pulls/<PR>"

# Get CI statuses for the head commit
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/medik8s/system-tests/commits/<HEAD_SHA>/statuses?per_page=100"
```

Present a summary table of all CI jobs:

```
| Job | Status | Time |
|-----|--------|------|
| ci/prow/4.22-konflux-e2e-nhc-aws | success/failure/pending | 2026-07-30T17:42:10Z |
| CodeRabbit | success | ... |
| tide | pending (needs approved, lgtm) | ... |
```

If the target job is still `pending`, report that and stop. If `success` or `failure`, proceed.

### Step 2: Find the Prow job ID

Extract the Prow job ID from the `target_url` in the status. The URL format is:
```
https://prow.ci.openshift.org/view/gs/test-platform-results/pr-logs/pull/medik8s_system-tests/<PR>/pull-ci-medik8s-system-tests-main-<JOB_NAME>/<JOB_ID>
```

The GCS base path is:
```
test-platform-results/pr-logs/pull/medik8s_system-tests/<PR>/pull-ci-medik8s-system-tests-main-<JOB_NAME>/<JOB_ID>
```

### Step 3: Fetch test output

The test output lives at a specific GCS path. Try these in order:

```bash
# Primary: e2e-test step build log (has the actual ginkgo output)
curl -sL --compressed \
  "https://storage.googleapis.com/<GCS_BASE>/artifacts/e2e-<OPERATOR>-aws/e2e-test/build-log.txt"

# Fallback: top-level build log (ci-operator log, may have embedded test output on failure)
curl -sL --compressed \
  "https://storage.googleapis.com/<GCS_BASE>/build-log.txt"
```

Where `<OPERATOR>` is derived from the job name:
- `4.22-konflux-e2e-nhc-aws` -> `nhc`
- `4.22-konflux-e2e-snr-aws` -> `snr`
- `4.22-konflux-e2e-far-aws` -> `far`
- etc.

**IMPORTANT**: The top-level `build-log.txt` does NOT contain test output on success -- only `ci-operator` step logs. Always try the `e2e-test/build-log.txt` path first.

If the e2e-test log is not found (job still running or artifacts not uploaded), list the artifact directory:
```bash
curl -sL "https://gcsweb-ci.apps.ci.l2s4.p1.openshiftapps.com/gcs/<GCS_BASE>/artifacts/e2e-<OPERATOR>-aws/" \
  | grep -oP 'href="(/gcs/[^"]*)"'
```

### Step 4: Parse test results

From the test output, extract:

1. **Ginkgo command line** -- check for `-vv` flag (verbose output)
2. **SSH infrastructure** -- look for `findSSHKey:` and `findSSHBastion:` lines
3. **Test summary line**: `Ran N of M Specs in X seconds`
4. **Result line**: `SUCCESS! -- N Passed | N Failed | N Pending | N Skipped`

Present results table:

```
| # | Test ID | Test Name | Verdict | Duration | Key Info |
|---|---------|-----------|---------|----------|----------|
| 1 | 56600   | block selector editing... | PASSED | 4m46s | SSH stop, webhook blocks verified |
| 2 | 69711   | old default CR name... | PASSED | 3m0s | SNR reboot, controller survived |
```

### Step 5: Detailed failure analysis (if any failures)

For each failed test, extract from the `-vv` output:

1. **Last successful STEP** before failure
2. **Failure message** (the `[FAILED]` block)
3. **Timeline** -- timestamps of each step to identify where time was spent
4. **Error type**:
   - Timeout (`timed out after Xs`) -- check which wait timed out and the timeout value
   - API error (`client rate limiter`, `forbidden`, `not found`)
   - Assertion failure (`Expected X to equal Y`)
   - SSH failure (`SSH to core@... failed`)
5. **NHC controller state** (logged on failure): pod phases, ready status, node placement

### Step 6: Flow verification (if passing with -vv)

For each passing test, trace the flow to verify correctness:

1. **SSH operations**: confirm `findSSHKey` and `findSSHBastion` resolved, and kubelet stop/start completed (check timestamps -- stop should be ~1s, not 5min)
2. **Remediation flow**: confirm NHC entered Remediating, SNR CR created/deleted, boot ID changed
3. **Webhook checks**: confirm error messages match expected patterns
4. **Recovery**: confirm node returned to Ready, NHC returned to Enabled
5. **Cleanup**: confirm JustAfterEach ran, safety net passed

Report as a per-test timeline table:

```
| Time | Step | Duration | Verified? |
|------|------|----------|-----------|
| 17:13:25 | Stop kubelet via SSH | ~1s | OK |
| 17:13:26 | Wait for Remediating | 1m50s | OK |
| ... | ... | ... | ... |
```

### Step 7: Infrastructure checks

Also report from the build log:

- **Cluster version**: from the `ipi-install-install` step
- **ssh-bastion step**: did it succeed? How long?
- **Operator install**: which operators were installed? (`medik8s-operator-subscribe` step)
- **Total job duration**: from `Ran for XhYmZs` line

## Common Failure Patterns

| Pattern | Root Cause | Fix |
|---------|-----------|-----|
| `timed out after 15m0s waiting for node X to become Ready` | Node didn't recover after SNR reboot within timeout | Check if SSH kubelet restart is in JustAfterEach; may need to increase NodeReadyTimeout |
| `oc debug on node X timed out after 5m0s` | oc debug used instead of SSH on Prow AWS | Switch to StopKubeletSSH |
| `unable to create the debug pod` | oc debug race condition with kubelet stopping | Switch to StopKubeletSSH |
| `no SSH private key found` | SSH key not mounted in CI pod | Check CLUSTER_PROFILE_DIR, verify ssh-bastion step ran |
| `SSH to core@X failed: connection refused` | ssh-bastion not deployed or security group issue | Verify ssh-bastion step succeeded |
| `client rate limiter Wait returned an error` | K8s client throttling during rapid polling | Increase poll interval or add backoff |
| `undefined: os` / compilation error | Rebase dropped imports when main modified same file | Re-add missing imports, rebuild |
| `not enough arguments in call to helpers.X` | Main added new parameters to shared helpers | Update call sites to match new signature |

## GCS Artifact Directory Structure

```
<GCS_BASE>/
  build-log.txt                          # ci-operator top-level log
  finished.json                          # {passed: true/false, timestamp, metadata}
  artifacts/
    e2e-<operator>-aws/
      e2e-test/
        build-log.txt                    # THE TEST OUTPUT (ginkgo -vv)
      ssh-bastion/
        build-log.txt                    # ssh-bastion deployment log
      medik8s-operator-subscribe/
        build-log.txt                    # operator install log
      gather-extra/
        artifacts/                       # must-gather artifacts
      ipi-install-install/
        build-log.txt                    # cluster install log
```
