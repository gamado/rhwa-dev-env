---
name: run-rhwa-tests
description: Use when running RHWA QE automation tests (ocp-edge-auto) on an OCP cluster. Covers environment setup, config file generation, Python venv, and pytest execution for SNR, NHC, FAR, MDR, NMO, SBR test suites.
---

# Run RHWA QE Tests (ocp-edge-auto)

## Overview

Run the RHWA QE automation suite (ocp-edge-auto) against an OpenShift cluster. Tests validate operator deployment, functionality, and remediation behavior for all RHWA operators.

## When to Use

- Validating RHWA operator deployment on a cluster
- Running regression/sanity tests after operator install or upgrade
- Verifying specific operator behavior (SNR, NHC, FAR, MDR, NMO, SBR)

## Prerequisites

- SSH access to the cluster host (resolve hostname from config `clusters.<name>.host`)
- RHWA operators deployed in `openshift-workload-availability` namespace (use `deploy-rhwa` skill)
- ocp-edge-auto zip file (download URL from config `urls.gitlab_qe`)
- Python 3.9+ and `virtualenv` on the cluster host

## Step 1: Copy Test Framework to Cluster Host

```bash
# Extract locally
unzip <path-to-ocp-edge-auto-zip> -d /tmp/

# Copy to cluster host (resolve host from config)
scp -r /tmp/ocp-edge-auto-master root@<host>:/root/ocp-edge-auto
```

## Step 2: Create vms_definitions.json

Extract BMC details from the cluster's BareMetalHost resources:

```bash
# Get BMC info for all nodes
oc get bmh -n openshift-machine-api -o jsonpath='{range .items[*]}{.metadata.name} bmc={.spec.bmc.address} mac={.spec.bootMACAddress} secret={.spec.bmc.credentialsName}{"\n"}{end}'

# Get BMC credentials (usually admin/password for virtual BMC)
oc get secret master-0-bmc-secret -n openshift-machine-api -o jsonpath='{.data.username}' | base64 -d
oc get secret master-0-bmc-secret -n openshift-machine-api -o jsonpath='{.data.password}' | base64 -d
```

Create `/root/vms_definitions.json` with one entry per node:

```json
{
  "master-0": {
    "bmc_type": "redfish-virtualmedia",
    "bmc_user": "admin",
    "bmc_pass": "password",
    "bmc_v4address": "<registry-host>:8000",
    "bmc_v6address": "<registry-host>:8000",
    "mac_address": "<boot-mac>",
    "baremetal_mac_address": ["<boot-mac>"],
    "node_role": "master"
  }
}
```

The `bmc_v4address` should be `host:port` extracted from the BMC address URL (not the full redfish URL).

## Step 3: Copy install-config.yaml

```bash
cp <kubeconfig-dir>/install-config.yaml /root/install-config.yaml
```

## Step 4: Set Up Python Environment

```bash
cd /root/ocp-edge-auto
virtualenv .venv
. .venv/bin/activate
pip install -r requirements.txt
pip install netifaces  # missing from requirements.txt
```

## Step 5: Export Environment Variables

```bash
export KUBECONFIG=<kubeconfig-path>  # resolve from config
export ASSISTED_INSTALLER=false
export SNO=false
export ENVIRONMENT=Virtual  # or "Baremetal" for real BM
export OCP_EDGE_AUTO_PATH=$(pwd)
```

## Step 6: Run Tests

### Verification Test (run this first)

```bash
pytest edge_tests/management/cluster_life_cycle/test_snr_cli.py::TestPostDeploymentSnr::test_snr_resources_are_installed_and_running -v
```

### Test Suites

| Suite | Command | Requires |
|-------|---------|----------|
| SNR (with MHC) | `pytest --stringinput="mhc" edge_tests/management/cluster_life_cycle/test_snr_cli.py` | SNR |
| SNR (standalone) | `pytest edge_tests/management/cluster_life_cycle/test_only_snr_cli.py` | SNR |
| SNR scale | `pytest edge_tests/management/cluster_life_cycle/test_snr_scale.py` | SNR |
| NHC + SNR | `pytest --stringinput="nhc" edge_tests/management/cluster_life_cycle/test_snr_cli.py` | NHC, SNR |
| NHC | `pytest edge_tests/management/cluster_life_cycle/test_nhc_cli.py` | NHC, SNR |
| NMO | `pytest edge_tests/management/cluster_life_cycle/test_nmo_cli.py` | NMO (SNR for 1 TC) |
| FAR | `pytest edge_tests/management/cluster_life_cycle/test_far_cli.py` | FAR |
| MDR | `pytest edge_tests/management/cluster_life_cycle/test_mdr_cli.py` | MDR |
| Node Lease | `pytest edge_tests/management/cluster_life_cycle/test_node_lease.py` | NHC, SNR |
| Ext Remediation | `pytest edge_tests/management/cluster_life_cycle/test_external_remediation_template.py` | NHC |

### Saving Test Results

By default results only go to stdout. Use `--junitxml` to persist results:

```bash
# Single suite with saved results
RESULTS_DIR="/root/test-results/$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"
pytest edge_tests/management/cluster_life_cycle/test_snr_cli.py \
    --junitxml="$RESULTS_DIR/snr.xml" \
    -v 2>&1 | tee "$RESULTS_DIR/snr.log"
```

### Running All Suites

Use the `run-all-rhwa-tests.sh` script to run every suite sequentially with results saved:

```bash
cd /root/ocp-edge-auto

# Run in foreground
./run-all-rhwa-tests.sh

# Run in background (survives SSH disconnect)
nohup ./run-all-rhwa-tests.sh > /root/test-results/run-all.log 2>&1 &
```

The script creates a timestamped directory under `/root/test-results/` with:
- `summary.log` — pass/fail status for each suite
- `<suite>.xml` — JUnit XML results per suite
- `<suite>.log` — full stdout/stderr per suite

To check progress while running in background:

```bash
tail -f /root/test-results/run-all.log
```

**Note:** These tests involve node reboots and remediation — a full run of all suites can take several hours.

### Useful pytest Flags

| Flag | Purpose |
|------|---------|
| `-v` | Verbose output (pass/fail per test) |
| `-s` | Show stdout/stderr (live logs) |
| `-x` | Stop after first failure |
| `-m sanity` | Run only sanity-marked tests |
| `-m regression` | Run only regression-marked tests |
| `--debug-mode` | Stop on failure, skip teardown |
| `--junitxml=FILE` | Save results as JUnit XML |

## Common Issues

| Problem | Fix |
|---------|-----|
| `ModuleNotFoundError: netifaces` | `pip install netifaces` (missing from requirements.txt) |
| `SNRC not found` / tests look in wrong namespace | Operators must be in `openshift-workload-availability`, not `openshift-operators`. Reinstall with correct namespace + OperatorGroup |
| SNR daemonset pods `Pending` (port conflict) | Old SNR pods in `openshift-operators` hold host ports. Delete old daemonset: `oc delete daemonset self-node-remediation-ds -n openshift-operators` |
| `installer-X-master-Y found in Failed state` | Known deployment issue, harmless warning — tests handle it |
| Test timeout waiting for pods | Check pods are actually Running: `oc get pods -n openshift-workload-availability` |
| `install-config.yaml not found` | Must exist at `/root/install-config.yaml` on the cluster host |

## Quick Reference

All RHWA tests expect operators in the `openshift-workload-availability` namespace. The framework reads config from `$HOME/vms_definitions.json` and `$HOME/install-config.yaml` on the cluster host.