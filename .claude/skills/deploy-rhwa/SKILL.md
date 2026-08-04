---
name: deploy-rhwa
description: Deploy RHWA operators on an OCP cluster. Supports deploying all or specific operators (snr, far, nhc, mdr, nmo, sbr) from either a pre-production IIB or the GA redhat-operators catalog.
---

# Deploy RHWA Operators on OCP

## Usage

```
/deploy-rhwa [operators] [source]
```

### Arguments

- **operators** (optional): Comma-separated list of operators to deploy. Default: `all`
  - Valid values: `snr`, `far`, `nhc`, `mdr`, `nmo`, `sbr`, `all`
  - Examples: `snr,far` or `snr` or `all`

- **source** (optional): Where to install from. Default: `ga`
  - `ga` — install from `redhat-operators` catalog (GA versions, works from any cluster)
  - `iib <number>` — install from a pre-production IIB (requires VPN/lab network access)
  - If just a number is given, treat it as IIB number: `/deploy-rhwa all 1151696`

### Examples

```
/deploy-rhwa                        → deploy all operators from GA catalog
/deploy-rhwa snr,far                → deploy only SNR and FAR from GA catalog
/deploy-rhwa snr,far ga             → same as above (explicit)
/deploy-rhwa all iib 1151696        → deploy all operators from IIB 1151696
/deploy-rhwa snr iib 1151696        → deploy only SNR from IIB 1151696
/deploy-rhwa snr,far,nhc 1151696    → deploy SNR, FAR, NHC from IIB
```

## Operator Package Reference

| Abbreviation | Package Name | RHWA 4.22-0 Version |
|---|---|---|
| `snr` | `self-node-remediation` | v0.13.0 |
| `nhc` | `node-healthcheck-operator` | v0.12.0 |
| `far` | `fence-agents-remediation` | v0.8.0 |
| `mdr` | `machine-deletion-remediation` | v0.7.0 |
| `nmo` | `node-maintenance-operator` | v5.7.0 |
| `sbr` | `storage-based-remediation` | v0.3.0 |

## Prerequisites

- `KUBECONFIG` set or `oc` access to the target cluster
- For IIB source: cluster must reach the IIB registry (resolve from config `registries.iib` and `registries.iib_fallback`)
- For GA source: cluster must reach `registry.redhat.io` (public, works from AWS/anywhere)

## Implementation Steps

### Step 1: Parse arguments

Map abbreviations to package names:

| Abbrev | Package name |
|--------|-------------|
| snr | self-node-remediation |
| nhc | node-healthcheck-operator |
| far | fence-agents-remediation |
| mdr | machine-deletion-remediation |
| nmo | node-maintenance-operator |
| sbr | storage-based-remediation |

If `all` is specified (or no operators argument), use all 6.

Determine the catalog source name and image:
- GA mode: `source: redhat-operators`, `sourceNamespace: openshift-marketplace` (no CatalogSource creation needed)
- IIB mode: `source: rhwa-catalog`, create CatalogSource with the IIB image

### Step 2: Create namespace and OperatorGroup (if not exists)

```bash
oc create namespace openshift-workload-availability 2>/dev/null || true
```

```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-workload-availability
  namespace: openshift-workload-availability
spec: {}
```

Check if OperatorGroup already exists before creating:

```bash
oc get operatorgroup -n openshift-workload-availability 2>/dev/null || oc apply -f operatorgroup.yaml
```

### Step 3: Create CatalogSource (IIB mode only)

Only for IIB source. Skip this step for GA mode.

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: rhwa-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: <iib-registry>/iib:<NUMBER>  # resolve registry from config `registries.iib`
  displayName: RHWA IIB
  publisher: Red Hat
```

Wait for catalog pod to be ready:

```bash
oc wait --for=condition=Ready pod -l olm.catalogSource=rhwa-catalog -n openshift-marketplace --timeout=120s
```

If the pod has `ImagePullBackOff`, try the fallback registry from config `registries.iib_fallback`.

### Step 4: Extract and apply IDMS (IIB mode only)

Only for IIB source. Skip for GA mode (GA images are on registry.redhat.io which is public).

The IIB contains catalog YAML files with `registry.redhat.io` image references that don't exist yet (pre-GA). Extract and map them:

```bash
for pkg in self-node-remediation node-healthcheck-operator fence-agents-remediation \
           machine-deletion-remediation node-maintenance-operator storage-based-remediation; do
  podman run --rm --entrypoint='' <IIB_IMAGE> \
    grep -o 'registry.redhat.io/workload-availability/[^@"]*' /configs/$pkg/catalog.yaml | sort -u
done
```

Apply IDMS mapping each `registry.redhat.io` source to its `quay.io/redhat-user-workloads/rhwa-tenant/` mirror. See the IDMS example in the appendix.

**IMPORTANT:** IDMS triggers a MachineConfig rollout — nodes reboot one by one. Wait for MCP:

```bash
oc get mcp
# Wait for UPDATED=True, UPDATING=False
```

### Step 5: Create Subscriptions

For each selected operator, create a Subscription:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: <package-name>
  namespace: openshift-workload-availability
spec:
  channel: stable
  installPlanApproval: Automatic
  name: <package-name>
  source: <catalog-source>        # "redhat-operators" for GA, "rhwa-catalog" for IIB
  sourceNamespace: openshift-marketplace
```

Only create Subscriptions for the selected operators, not all 6.

### Step 6: Wait and verify

Wait for CSVs to reach `Succeeded` phase:

```bash
# Wait up to 120s for pods to appear
sleep 30

# Check CSV status
oc get csv -n openshift-workload-availability

# Check pods
oc get pods -n openshift-workload-availability
```

All requested CSVs should show `Phase: Succeeded`. All pods should be `Running`.

Report the results in a summary table:

```
| Operator | Version | CSV Phase | Pods |
|----------|---------|-----------|------|
| SNR      | v0.13.0 | Succeeded | 2/2  |
| FAR      | v0.8.0  | Succeeded | 2/2  |
```

## Common Issues

| Problem | Fix |
|---------|-----|
| CatalogSource pod `ImagePullBackOff` | Cluster can't reach the IIB registry. Try `registries.iib_fallback` from config, or switch to `ga` source |
| Operator pod `ImagePullBackOff` (IIB mode) | IDMS not applied or missing a mapping. Check `oc get idms` |
| CSV stuck in `Installing` | Check operator pod logs: `oc logs -n openshift-workload-availability <pod>` |
| OperatorGroup conflict | Delete existing OperatorGroup: `oc delete og -n openshift-workload-availability --all` then recreate |
| GA catalog shows older version than IIB | Expected — GA catalog has released versions, IIB has pre-release |

## Appendix: IDMS Example (RHWA 4.22-0)

```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: rhwa-konflux-idms
spec:
  imageDigestMirrors:
    # SNR
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/self-node-remediation/snr-operator-0-13
      source: registry.redhat.io/workload-availability/self-node-remediation-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/self-node-remediation/snr-bundle-0-13
      source: registry.redhat.io/workload-availability/self-node-remediation-operator-bundle
    # NHC
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/node-healthcheck-operator/nhc-operator-0-12
      source: registry.redhat.io/workload-availability/node-healthcheck-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/node-healthcheck-operator/nhc-bundle-0-12
      source: registry.redhat.io/workload-availability/node-healthcheck-operator-bundle
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/node-healthcheck-operator/nhc-console-0-12
      source: registry.redhat.io/workload-availability/node-remediation-console-rhel9
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/node-healthcheck-operator/nhc-must-gather-0-12
      source: registry.redhat.io/workload-availability/node-healthcheck-must-gather-rhel9
    # FAR
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/fence-agents-remediation/far-operator-0-8
      source: registry.redhat.io/workload-availability/fence-agents-remediation-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/fence-agents-remediation/far-bundle-0-8
      source: registry.redhat.io/workload-availability/fence-agents-remediation-operator-bundle
    # MDR
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/machine-deletion-remediation/mdr-operator-0-7
      source: registry.redhat.io/workload-availability/machine-deletion-remediation-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/machine-deletion-remediation/mdr-bundle-0-7
      source: registry.redhat.io/workload-availability/machine-deletion-remediation-operator-bundle
    # NMO
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/node-maintenance-operator/nmo-operator-5-7
      source: registry.redhat.io/workload-availability/node-maintenance-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/node-maintenance-operator/nmo-bundle-5-7
      source: registry.redhat.io/workload-availability/node-maintenance-operator-bundle
    # SBR
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/storage-based-remediation/sbr-operator-0-3
      source: registry.redhat.io/workload-availability/storage-based-remediation-rhel9-operator
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/storage-based-remediation/sbr-agent-0-3
      source: registry.redhat.io/workload-availability/storage-based-remediation-agent-rhel9
    - mirrors:
        - quay.io/redhat-user-workloads/rhwa-tenant/storage-based-remediation/sbr-bundle-0-3
      source: registry.redhat.io/workload-availability/storage-based-remediation-operator-bundle
```

## References

- Build location doc: resolve from config `urls.build_doc`
- Testing team tutorial: resolve from config `urls.test_tutorial`
- Quay repos: https://quay.io/organization/redhat-user-workloads (search `rhwa-tenant`)
