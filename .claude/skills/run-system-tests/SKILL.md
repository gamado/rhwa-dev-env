---
name: run-system-tests
description: Run medik8s/system-tests Go E2E tests against an OCP cluster. Supports running specific operator tests (snr, far, sbr, nhc, nmo, mdr) with flexible cluster targeting (local kubeconfig, remote via SSH, or explicit path).
---

# Run System Tests

## Usage

```
/run-system-tests [operator] [cluster]
```

### Arguments

- **operator** (required): Which operator tests to run.
  - Valid values: `snr`, `far`, `sbr`, `nhc`, `nmo`, `mdr`, `all`
  - Maps to `ECO_TEST_FEATURES`: `snr` → `snr-operator`, `far` → `far-operator`, etc.

- **cluster** (optional): Which cluster to run against. Default: use current `KUBECONFIG`.
  - `local` or omitted — use `KUBECONFIG` env var or `~/.kube/config`
  - Path to kubeconfig — e.g. `/tmp/aws-kubeconfig`
  - `srv-16` — run remotely on nvd-srv-16 via SSH (for ARM64 testing)
  - `edge119` — use kubeconfig from edge119 (SSH to fetch if needed)

### Examples

```
/run-system-tests snr                          → run SNR tests with current KUBECONFIG
/run-system-tests far /tmp/aws-kubeconfig      → run FAR tests against AWS cluster
/run-system-tests snr srv-16                   → run SNR tests remotely on nvd-srv-16
/run-system-tests all /tmp/aws-kubeconfig      → run all operator tests against AWS
```

## Prerequisites

- Go 1.26+ installed (`/usr/local/go/bin` should be in PATH)
- system-tests repo cloned at `repos/system-tests/` (in rhwa-dev-env workspace)
- For remote execution (srv-16): `sshpass` installed, password `qum10net`
- For local execution: kubeconfig with cluster-admin access

## Operator to Feature Mapping

| Operator | ECO_TEST_FEATURES | ECO_TEST_LABELS |
|----------|-------------------|-----------------|
| `snr` | `snr-operator` | `snr` |
| `far` | `far-operator` | `far` |
| `sbr` | `sbr-operator` | `sbr` |
| `nhc` | `nhc-operator` | `nhc` |
| `nmo` | `nmo-operator` | `nmo` |
| `mdr` | `mdr-operator` | `mdr` |
| `all` | all of the above | (no filter) |

## Implementation Steps

### Step 1: Parse arguments and determine execution mode

Determine:
1. Which operator → set `ECO_TEST_FEATURES` value
2. Which cluster → set kubeconfig path or remote execution flag

### Step 2: Validate prerequisites

For local execution:
```bash
export PATH=/usr/local/go/bin:$PATH
go version  # must be 1.26+
```

Check kubeconfig works:
```bash
export KUBECONFIG=<path>
oc get nodes --no-headers | wc -l  # should return > 0
```

For remote (srv-16):
```bash
sshpass -p "qum10net" ssh root@nvd-srv-16.nvidia.eng.rdu2.redhat.com "go version"
```

### Step 3: Run tests

#### Local execution (any machine with Go + kubeconfig access)

```bash
export PATH=/usr/local/go/bin:$PATH
export KUBECONFIG=<path>
export ECO_TEST_FEATURES=<operator>-operator
cd repos/system-tests   # or /home/kni/git/rhwa-dev-env/repos/system-tests
make run-tests
```

For verbose output, add:
```bash
export ECO_TEST_VERBOSE=true
```

#### Remote execution (srv-16)

First sync latest test code to srv-16:
```bash
# Copy the specific operator test directory
sshpass -p "qum10net" scp -r repos/system-tests/tests/<operator>-operator/ \
  root@nvd-srv-16.nvidia.eng.rdu2.redhat.com:/home/kni/git/system-tests/tests/<operator>-operator/
```

Then run:
```bash
sshpass -p "qum10net" ssh root@nvd-srv-16.nvidia.eng.rdu2.redhat.com \
  "export PATH=/usr/local/go/bin:\$PATH && \
   export KUBECONFIG=/home/kni/clusterconfigs/auth/kubeconfig && \
   export ECO_TEST_FEATURES=<operator>-operator && \
   cd /home/kni/git/system-tests && \
   make run-tests"
```

### Step 4: Report results

Parse the output and report a summary:

```
| Operator | Tests | Passed | Failed | Skipped | Time |
|----------|-------|--------|--------|---------|------|
| SNR      | 4     | 4      | 0      | 0       | 4.5s |
```

If any tests failed, show the failure details (test name, error message, file:line).

### Step 5: Check for generated reports

After test execution, check for JUnit XML and report artifacts:

```bash
ls -la /tmp/reports/  # default report directory
```

## Known Cluster Targets

| Name | Hostname | Kubeconfig | Arch | Access |
|------|----------|-----------|------|--------|
| srv-16 | nvd-srv-16.nvidia.eng.rdu2.redhat.com | /home/kni/clusterconfigs/auth/kubeconfig | ARM64 | SSH only (run remotely) |
| edge119 | ocp-edge119.lab.eng.tlv2.redhat.com | /home/kni/clusterconfigs/auth/kubeconfig | x86 | SSH or direct from edge servers |
| AWS | varies | /tmp/aws-kubeconfig | x86 | Public API (works from anywhere) |

## Common Issues

| Problem | Fix |
|---------|-----|
| `go: not found` | Add to PATH: `export PATH=/usr/local/go/bin:$PATH` |
| `cannot find module ... -mod=vendor` | Run `go mod vendor` in system-tests dir |
| DNS error connecting to cluster | Cluster API not reachable from this machine. Use remote execution or SSH tunnel |
| `ginkgo: command not found` | Run `make install` first, or `make run-tests` will auto-download ginkgo |
| Tests timeout at 5 min | Operator deployment is not ready. Check `oc get csv -n openshift-workload-availability` |
