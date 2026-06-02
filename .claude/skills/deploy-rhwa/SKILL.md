---
name: deploy-rhwa
description: Use when deploying RHWA (Workload Availability) operators on an OCP cluster using a pre-production IIB from Konflux. Covers CatalogSource, IDMS extraction from IIB, MCP rollout, subscriptions, and verification.
---

# Deploy RHWA Operators on OCP

## Overview

Deploy all RHWA operators (NHC, SNR, FAR, MDR, NMO, SBR) on an OpenShift cluster using a pre-production IIB (Index Image Bundle) from Konflux. The IIB contains all operator catalogs; an IDMS mirrors pre-production images from `quay.io/redhat-user-workloads/rhwa-tenant/` since `registry.redhat.io` images don't exist until GA.

## When to Use

- Deploying RHWA for QE testing with a staged IIB
- Setting up a new cluster for RHWA validation
- Upgrading RHWA to a new IIB build

## Prerequisites

- `oc` access to the target cluster (or SSH access to a host with `oc`)
- Cluster must reach `registry-proxy.engineering.redhat.com` (RH VPN) or use `brew.registry.redhat.io` as fallback
- Cluster must reach `quay.io/redhat-user-workloads/rhwa-tenant/`

## Step 1: Find the Latest IIB

Check the build location doc: https://docs.google.com/document/d/1c5xFWKs_NabZYWBwebhzp7-8hzNWDcp9tQsvqG0vfWI/edit

Look for the most recent entry under **IIBs and Snapshot** for your target OCP version. The IIB format is:

```
registry-proxy.engineering.redhat.com/rh-osbs/iib:<NUMBER>
```

If cluster lacks RH VPN connectivity, use `brew.registry.redhat.io/rh-osbs/iib:<NUMBER>` instead.

## Step 2: Create CatalogSource

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: rhwa-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: registry-proxy.engineering.redhat.com/rh-osbs/iib:<NUMBER>
```

Apply and verify the pod is running:

```bash
oc apply -f catalogsource.yaml
oc get pods -n openshift-marketplace | grep rhwa
```

Wait for `connectionState: READY`:

```bash
oc get catalogsource rhwa-catalog -n openshift-marketplace -o yaml | grep lastObservedState
```

## Step 3: Extract IDMS Mappings from IIB

The IIB contains catalog YAML files with the exact `registry.redhat.io` image references. Extract them to build the IDMS:

```bash
# List RHWA packages in the IIB
podman run --rm --entrypoint='' <IIB_IMAGE> ls /configs/ | grep -E 'self-node|node-health|fence-agents|machine-deletion|node-maintenance|storage-based'

# Extract registry.redhat.io source names per operator
for pkg in self-node-remediation node-healthcheck-operator fence-agents-remediation \
           machine-deletion-remediation node-maintenance-operator storage-based-remediation; do
  echo "=== $pkg ==="
  podman run --rm --entrypoint='' <IIB_IMAGE> \
    grep -o 'registry.redhat.io/workload-availability/[^@"]*' /configs/$pkg/catalog.yaml | sort -u
done
```

This outputs the exact `registry.redhat.io` source names needed for the IDMS.

## Step 4: Build and Apply IDMS

Map each `registry.redhat.io` source to its `quay.io/redhat-user-workloads/rhwa-tenant/` mirror. The mirror repo names follow the pattern on quay.io under the `redhat-user-workloads` org (search for `rhwa-tenant`).

### Mapping Convention

| registry.redhat.io source | quay.io mirror |
|---|---|
| `workload-availability/<name>-rhel9-operator` | `rhwa-tenant/<app>/<abbrev>-operator-<version>` |
| `workload-availability/<name>-operator-bundle` | `rhwa-tenant/<app>/<abbrev>-bundle-<version>` |

### Example IDMS (RHWA 4.22-0)

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

Apply:

```bash
oc apply -f idms.yaml
```

**IMPORTANT:** IDMS triggers a MachineConfig rollout — nodes reboot one by one.

## Step 5: Wait for MCP Rollout

Monitor until all nodes are updated:

```bash
oc get mcp
```

Wait for `UPDATED=True`, `UPDATING=False`, `READYMACHINECOUNT` equals `MACHINECOUNT`.

## Step 6: Create Subscriptions

First create the namespace and OperatorGroup:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-workload-availability
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-workload-availability
  namespace: openshift-workload-availability
spec: {}
```

Then install all operators in `openshift-workload-availability` namespace using the `stable` channel:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: self-node-remediation
  namespace: openshift-workload-availability
spec:
  channel: stable
  name: self-node-remediation
  source: rhwa-catalog
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: node-healthcheck-operator
  namespace: openshift-workload-availability
spec:
  channel: stable
  name: node-healthcheck-operator
  source: rhwa-catalog
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: fence-agents-remediation
  namespace: openshift-workload-availability
spec:
  channel: stable
  name: fence-agents-remediation
  source: rhwa-catalog
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: machine-deletion-remediation
  namespace: openshift-workload-availability
spec:
  channel: stable
  name: machine-deletion-remediation
  source: rhwa-catalog
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: node-maintenance-operator
  namespace: openshift-workload-availability
spec:
  channel: stable
  name: node-maintenance-operator
  source: rhwa-catalog
  sourceNamespace: openshift-marketplace
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: storage-based-remediation
  namespace: openshift-workload-availability
spec:
  channel: stable
  name: storage-based-remediation
  source: rhwa-catalog
  sourceNamespace: openshift-marketplace
```

## Step 7: Verify Deployment

```bash
# All CSVs should show Succeeded
oc get csv -n openshift-workload-availability

# All operator pods should be Running
oc get pods -n openshift-workload-availability

# Verify versions match the build doc
oc get csv -n openshift-workload-availability -o custom-columns='NAME:.metadata.name,VERSION:.spec.version'

# Verify CatalogSource image matches expected IIB
oc get catalogsource rhwa-catalog -n openshift-marketplace -o jsonpath='{.spec.image}'
```

## Quick Reference

| Component | Package Name | RHWA 4.22-0 Version |
|-----------|-------------|---------------------|
| Node Health Check | `node-healthcheck-operator` | v0.12.0 |
| Self Node Remediation | `self-node-remediation` | v0.13.0 |
| Fence Agents Remediation | `fence-agents-remediation` | v0.8.0 |
| Machine Deletion Remediation | `machine-deletion-remediation` | v0.7.0 |
| Node Maintenance Operator | `node-maintenance-operator` | v5.7.0 |
| Storage Based Remediation | `storage-based-remediation` | v0.3.0 |

## Common Issues

| Problem | Fix |
|---------|-----|
| CatalogSource pod has ImagePullBackOff | Cluster can't reach `registry-proxy`. Use `brew.registry.redhat.io` instead |
| Operator install fails with ImagePullBackOff | IDMS not applied correctly or missing a mapping. Check `oc get idms` |
| Nodes not rebooting after IDMS | Check `oc get mcp` — may already be rolled out if a previous IDMS existed |
| `oc get packagemanifest` shows duplicates | Same operator in multiple catalogs (rhwa-catalog + Red Hat Operators). Subscription `source` field ensures the correct one is used |

## References

- Testing team tutorial: https://docs.google.com/document/d/1E-arB0rzqZzWzI-T5EaKPdEtNRqZjv-xS-BWUB8-Ink/edit
- Build location doc: https://docs.google.com/document/d/1c5xFWKs_NabZYWBwebhzp7-8hzNWDcp9tQsvqG0vfWI/edit
- Quay repos: https://quay.io/organization/redhat-user-workloads (search `rhwa-tenant`)
- QE automation: https://gitlab.cee.redhat.com/ocp-edge-qe/ocp-edge-auto/