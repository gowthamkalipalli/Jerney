# Jerney Kubernetes Deployment Troubleshooting Guide

## Overview
This document explains the critical issues encountered during the initial Kubernetes deployment of Jerney on GKE, the root causes, and the solutions applied.

---

## Issue 1: Docker Registry Secret - "Illegal Base64 Data" Error

### Error Symptoms
```
NAME                           READY   STATUS                                RESTARTS
jerney-frontend-dc57789b-7czzw 0/1     illegal base64 data at input byte 23  0
jerney-frontend-dc57789b-tzr2k 0/1     illegal base64 data at input byte 23  0
```

### Root Cause
The `dockerhub-secret` Secret was created with an **invalid/corrupted base64-encoded `.dockercfg`** value:

```yaml
# BROKEN - This is what was in the manifest
type: kubernetes.io/dockercfg
data:
  .dockercfg: eyJodWIuZG9ja2VyLmNvbSI6eyJhdXRoIjoiWTNKbGNuWmxjaTluYjI5bmJHVXVZMkY6IiwiZW1haWwiOiIifX0=
```

When decoded, this produced:
```json
{"hub.docker.com":{"auth":"Y3JsbGNuWmxjaTluYjI5bmJHVXVZMkY:","email":""}}
```

**Problems:**
- Missing actual Docker credentials (username:password)
- Incomplete auth token
- Wrong Docker registry hostname (`hub.docker.com` instead of `docker.io`)

### Why Pods Failed
Kubernetes tried to use this Secret to authenticate with Docker Hub and pull the images:
- `gowthamk4/jerney-backend:75da1da`
- `gowthamk4/jerney-frontend:75da1da`

Without valid credentials, image pulls failed with base64 decode errors.

### Solution Applied

**Step 1: Delete the invalid Secret**
```bash
kubectl delete secret dockerhub-secret -n jerney
```
> Note: Secrets cannot be updated in-place if the `type` field changes. Deletion was required.

**Step 2: Create a proper Docker Registry Secret**
```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=docker.io \
  --docker-username=gowthamk4 \
  --docker-password=Docker@2108 \
  --docker-email=gowthamkalipalli@gmail.com \
  --namespace=jerney
```

This command automatically:
- Generates the correct `.dockerconfigjson` type (not `.dockercfg`)
- Base64-encodes your credentials properly
- Creates a valid authentication token for Docker Hub

**Step 3: Restart Deployments to Trigger New Image Pulls**
```bash
kubectl rollout restart deployment/jerney-backend -n jerney
kubectl rollout restart deployment/jerney-frontend -n jerney
```

### Prevention Tips
- Use `kubectl create secret docker-registry` instead of manually base64-encoding
- Store Docker credentials in a secure secrets manager (not in manifests)
- Never hardcode credentials in YAML files
- For production, use:
  - **GCP**: Workload Identity or Service Accounts
  - **Private registries**: Consider using pull-through cache or artifact registries

---

## Issue 2: Database Pod Stuck in "Pending" State

### Error Symptoms
```
NAME              READY  STATUS    RESTARTS  AGE
jerney-db-55878847ff-w7k8g  0/1    Pending   0         11m
```

### Root Cause
The PersistentVolumeClaim (PVC) failed to provision storage:

```
Warning  ProvisioningFailed  84s
Volume provisioning failed with infeasible error.
rpc error: code = InvalidArgument desc = CreateVolume failed to create regional disk: 
failed to insert regional disk: unknown Insert disk error: 
googleapi: Error 400: Invalid value for field 'resource.sizeGb': '10'. 
Disk size cannot be smaller than 200 GB.
```

**The Problem:**
The manifest requested `10Gi` of storage:
```yaml
spec:
  resources:
    requests:
      storage: 10Gi
  storageClassName: jerney-gcp-sc-v2
```

But the StorageClass was configured for **GCP regional persistent disks** with a **200GB minimum**:
```yaml
parameters:
  type: pd-standard
  replication-type: regional-pd  # <-- Regional disks have 200GB minimum
```

### Why GCP Has This Limit
- **Regional disks**: Replicated across zones for high availability
- **Google's requirement**: Minimum 200GB for regional replication infrastructure
- **Standard disks**: Local zone disks allow smaller sizes (1GB minimum)

### Solution Applied

**Changed PVC storage from 10Gi to 200Gi** (line 74):

```yaml
# BEFORE (broken)
spec:
  resources:
    requests:
      storage: 10Gi

# AFTER (fixed)
spec:
  resources:
    requests:
      storage: 200Gi
```

**Steps to recover:**
```bash
# Delete the failed PVC
kubectl delete pvc jerney-db-pvc -n jerney

# Apply the corrected manifest
kubectl apply -f k8s/jerney.yaml

# Monitor provisioning (takes 1-2 minutes on GCP)
kubectl get pvc -n jerney -w
```

### Why This Fixed the Issue
1. GCP CSI provisioner re-evaluated the claim
2. 200GB meets the regional disk minimum
3. Provisioning succeeded
4. Database pod transitioned from `Pending` → `Running`
5. Backend init containers could complete their database readiness check

### Alternative Solutions

**Option A: Use Standard Zone Disks (Smaller Size)**
```yaml
storageClassName: standard-rwo  # Use GKE's default
# Allows 1GB minimum size
```
**Tradeoff**: No cross-zone replication, less durable but smaller and cheaper.

**Option B: Use pd-ssd with Smaller Size**
```yaml
parameters:
  type: pd-ssd
  replication-type: regional-pd
# Still 200GB minimum for regional
```
**Tradeoff**: Faster but more expensive.

**Option C: Accept the 200GB Regional Disk**
```yaml
storage: 200Gi  # Current solution
```
**Benefits**: High availability, resilient to zone failures.

---

## Issue 3: Backend Init Containers Waiting (Init:0/1)

### Error Symptoms
```
NAME                          READY  STATUS     RESTARTS
jerney-backend-595767f5c8-dzz5h  0/1  Init:0/1   0
jerney-backend-595767f5c8-s5lb2  0/1  Init:0/1   0
```

### Root Cause
Backend pods use an **init container** to wait for the database to be ready:

```yaml
initContainers:
  - name: wait-for-db
    image: busybox:1.36
    command:
      - sh
      - -c
      - |
        echo "Waiting for jerney-db:5432..."
        until nc -z jerney-db 5432; do
          echo "DB not ready, retrying in 3s..."
          sleep 3
        done
        echo "DB is ready!"
```

**Why it stayed in Init:0/1:**
- The init container tries to connect to `jerney-db:5432`
- But the Database pod was stuck in `Pending` state
- So the port was never open
- Init container kept retrying forever

This is a **cascading failure**:
```
Database Pending 
    ↓
PVC not provisioned (10Gi < 200Gi minimum)
    ↓
Init container can't connect to DB
    ↓
Backend pods stuck waiting for init
```

### Solution
By fixing the PVC issue (Issue #2), the database pod started successfully, allowing:
1. Database port 5432 to open
2. Init container health check to pass
3. Main backend container to start
4. Application to become `Ready`

### Diagram: Dependency Chain
```
Frontend Service (NodePort)
    ↓ calls
Backend Service (ClusterIP)
    ↓ waits for (init container)
Database Service (ClusterIP)
    ↓ needs
PersistentVolume (200Gi GCP Regional Disk)
```

---

## Post-Resolution Verification

### Check All Pods Are Running
```bash
$ kubectl get pods -n jerney
NAME                              READY   STATUS    RESTARTS   AGE
jerney-backend-684c56f98d-zxdcw   1/1     Running   0          2m
jerney-backend-684c56f98d-abc12   1/1     Running   0          2m
jerney-db-55878847ff-w7k8g        1/1     Running   0          3m
jerney-frontend-556bf95d48-xzd46  1/1     Running   0          2m
jerney-frontend-556bf95d48-def34  1/1     Running   0          2m
```

### Verify Database Connectivity
```bash
# Check database readiness from a backend pod
kubectl logs jerney-backend-684c56f98d-zxdcw -n jerney | head -20

# Expected: "DB is ready!" from init container logs
```

### Test Frontend Service
```bash
# Get the NodePort
kubectl get svc jerney-frontend -n jerney
# Example output: NodePort: 31234/TCP

# Access via node IP (from your machine or bastion)
curl http://<GKE_NODE_IP>:31234
```

### Monitor Storage Usage
```bash
kubectl get pvc -n jerney
# Shows 200Gi allocated and available

# Check actual usage inside the pod
kubectl exec -it jerney-db-55878847ff-w7k8g -n jerney -- df -h /var/lib/postgresql/data
```

---

## Best Practices for Future Deployments

### 1. **Secrets Management**
- Never hardcode credentials in manifests
- Use Kubernetes Secrets for sensitive data
- For production: Use external secret managers (Vault, GCP Secret Manager)
- Use RBAC to limit who can access secrets

### 2. **Storage Planning**
- Research cloud provider storage limits before deployment
- Test storage class provisioning in dev environment first
- Document storage requirements in comments
- Use descriptive names for storage classes

### 3. **Resource Dependencies**
- Use init containers to ensure proper startup order
- Add probes (liveness, readiness) for health checks
- Document pod startup dependencies in comments
- Consider using Job/Hooks for one-time setup tasks

### 4. **Image Management**
- Use specific image tags (not `latest`)
- Store images in private registries with proper authentication
- Test image pulls locally before deploying
- Automate image building and pushing

### 5. **Manifest Structure**
- Validate YAML syntax before applying (`kubectl apply --dry-run`)
- Use tools like `kubeval` or `kube-score` for linting
- Version control all manifests with comments explaining decisions
- Test manifests in staging before production

### 6. **Monitoring & Debugging**
- Check pod events: `kubectl describe pod <pod-name> -n jerney`
- View pod logs: `kubectl logs <pod-name> -n jerney`
- Use port-forward for testing: `kubectl port-forward svc/jerney-backend 5000:5000 -n jerney`
- Set up centralized logging (ELK, Cloud Logging) for production

---

## Related Resources

- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- [GCP Persistent Disk Types](https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

---

## Summary Table

| Issue | Error | Root Cause | Fix |
|-------|-------|-----------|-----|
| Docker Auth | `illegal base64 data at input byte 23` | Invalid base64-encoded `.dockercfg` secret | Recreate secret using `kubectl create secret docker-registry` |
| PVC Provisioning | `Disk size cannot be smaller than 200 GB` | 10Gi requested vs 200Gi GCP minimum for regional disks | Increased storage request to 200Gi |
| Init Container | `Init:0/1` stuck | Database pod pending due to PVC issue | Fixed by resolving PVC provisioning |

---

**Last Updated:** 2026-06-30  
**Status:** ✅ All issues resolved  
**Environment:** GKE (Autopilot compatible)
