---
name: check-cluster
description: Quick health check of an OCP cluster. Shows nodes, cluster version, cluster operators, RHWA operator status (CSVs, pods), and any issues. Supports local kubeconfig, remote clusters via SSH, or explicit kubeconfig path.
---

# Check Cluster Health

## Usage

```
/check-cluster [target]
```

### Arguments

- **target** (optional): Which cluster to check. Default: use current `KUBECONFIG`.
  - Omitted or `local` — use `KUBECONFIG` env var
  - Path to kubeconfig — e.g. `/tmp/aws-kubeconfig`
  - `<cluster-alias>` — check a configured cluster via SSH (resolve from config)

### Examples

```
/check-cluster                     → check cluster using current KUBECONFIG
/check-cluster /tmp/aws-kubeconfig → check AWS cluster
/check-cluster srv-16              → check srv-16 cluster via SSH (resolved from config)
/check-cluster edge119             → check edge119 cluster via SSH (resolved from config)
```

## Implementation

### Step 1: Determine access method

Based on target argument:

| Target | Access method | Kubeconfig |
|--------|--------------|------------|
| `local` / omitted | Direct `oc` | `$KUBECONFIG` or `~/.kube/config` |
| `/path/to/kubeconfig` | Direct `oc` with `KUBECONFIG=<path>` | As specified |
| `<cluster-alias>` | SSH: `ssh root@<host>` (resolve host from config `clusters.<alias>.host`) | Resolve from config `clusters.<alias>.kubeconfig` |

### Step 2: Run health checks

Execute these commands on the target (either locally or via SSH):

```bash
export KUBECONFIG=<path>

echo "=== NODES ==="
oc get nodes -o wide

echo "=== CLUSTER VERSION ==="
oc get clusterversion

echo "=== FAILING CLUSTER OPERATORS ==="
oc get co | grep -v 'True.*False.*False'
# If only header line returned, all operators are healthy

echo "=== RHWA CSVs ==="
oc get csv -n openshift-workload-availability 2>/dev/null || echo "RHWA namespace not found"

echo "=== RHWA PODS ==="
oc get pods -n openshift-workload-availability 2>/dev/null || echo "No RHWA pods"

echo "=== NON-RUNNING PODS ==="
oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | head -20
```

### Step 3: Report summary

Present results in a clean summary table:

```
| Component | Status |
|-----------|--------|
| Nodes     | 3m + 3w, all Ready |
| OCP       | 4.22 nightly, Available |
| Operators | 35/35 healthy |
| SNR       | v0.13.0, Succeeded, 2 controller + 4 DS pods |
| FAR       | v0.8.0, Succeeded, 2 pods |
| ...       | ... |
```

Flag any issues:
- Nodes not Ready
- ClusterVersion not Available or Progressing
- Cluster operators Degraded or not Available
- CSVs not in Succeeded phase
- Pods in CrashLoopBackOff, ImagePullBackOff, or Error state
- RHWA namespace not found (operators not deployed)

## Known Clusters

Read cluster definitions from `.claude/local/config.yaml` (see CLAUDE.md "Config Resolution").
Each cluster entry has: `host`, `arch`, `kubeconfig`, and optionally `auth` and `password`.

For AWS (Cluster Bot) clusters, use the kubeconfig path directly instead of an alias.
