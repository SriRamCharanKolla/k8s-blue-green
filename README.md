# Kubernetes Blue/Green Deployment Strategy (`k8s-blue-green`)

This repository demonstrates a production-grade **Blue/Green Zero-Downtime Deployment Strategy** on Kubernetes. It features live traffic routing, isolated preview testing, instant rollbacks, and safe resource retirement.

---

## 🏗️ Architecture & Traffic Flow

```mermaid
graph TD
    subgraph "Public Internet / End Users"
        LIVE_USERS["Live User Traffic"]
        QA_USERS["QA / Automated Tests"]
    end

    subgraph "Kubernetes Services (L4 Load Balancer & ClusterIP)"
        MAIN_SVC["Service: nginx<br/>(type: LoadBalancer)<br/><b>selector: version: blue</b>"]
        PREV_SVC["Service: nginx-preview<br/>(type: ClusterIP)<br/><b>selector: version: green</b>"]
    end

    subgraph "Deployments (Isolated Environments)"
        BLUE_DEP["Deployment: nginx-blue<br/>(Replicas: 4, Image: v0.0.1)<br/>labels: version: blue"]
        GREEN_DEP["Deployment: nginx-green<br/>(Replicas: 4, Image: v0.0.2)<br/>labels: version: green"]
    end

    LIVE_USERS -->|Port 80 (Production)| MAIN_SVC
    QA_USERS -->|Port 80 (Validation)| PREV_SVC

    MAIN_SVC -->|Live Route| BLUE_DEP
    PREV_SVC -.->|Preview Route| GREEN_DEP

    classDef active fill:#2b82c9,stroke:#1b4f72,stroke-width:2px,color:#fff;
    classDef preview fill:#27ae60,stroke:#196f3d,stroke-width:2px,color:#fff;
    class BLUE_DEP,MAIN_SVC active;
    class GREEN_DEP,PREV_SVC preview;
```

---

## 📁 Repository Manifest Matrix

| Manifest File | Kind | Version Label | Role / Purpose |
| :--- | :--- | :--- | :--- |
| [`Dockerfile`](file:///Users/sriramcharankolla/Desktop/DevOps/k8s-blue-green/Dockerfile) | `Dockerfile` | `0.0.2` | Builds sample container image serving versioned HTML (`v0.0.2`) |
| [`01-blue-deployment.yaml`](file:///Users/sriramcharankolla/Desktop/DevOps/k8s-blue-green/01-blue-deployment.yaml) | `Deployment` | `version: blue` | Active production deployment running `4` replicas of `joindevops/blue-green:0.0.1` |
| [`02-main.service.yaml`](file:///Users/sriramcharankolla/Desktop/DevOps/k8s-blue-green/02-main.service.yaml) | `Service` (`LoadBalancer`) | `selector: version: blue` | Production internet-facing LoadBalancer routing live traffic |
| [`03-green-deployment.yaml`](file:///Users/sriramcharankolla/Desktop/DevOps/k8s-blue-green/03-green-deployment.yaml) | `Deployment` | `version: green` | Staging / New release deployment running `4` replicas of `joindevops/blue-green:0.0.2` |
| [`04-preview-service.yaml`](file:///Users/sriramcharankolla/Desktop/DevOps/k8s-blue-green/04-preview-service.yaml) | `Service` (`ClusterIP`) | `selector: version: green` | Internal preview service used by QA / Smoke tests before cutting over traffic |

---

## 🔑 Core Concepts & Deployment Mechanics

### 1. Zero-Downtime Traffic Cutover
* Unlike **Rolling Updates** (which replace pods incrementally and run two versions simultaneously), **Blue/Green** maintains two complete, isolated environments.
* The cutover occurs by updating a single label selector on the production Service:
  ```yaml
  selector:
    version: green  # Changes target from Blue to Green instantly
  ```

### 2. Isolated Preview Validation
* The Green deployment is spun up with `4` replicas and validated using [`04-preview-service.yaml`](file:///Users/sriramcharankolla/Desktop/DevOps/k8s-blue-green/04-preview-service.yaml).
* Zero production users are impacted while functional, performance, and smoke tests run against the Green environment.

### 3. Instant Rollback
* If unforeseen errors occur in production after cutover, traffic is reverted to Blue in **sub-seconds** by switching the selector back to `version: blue`.

---

## 🚀 Step-by-Step Execution & Cutover Workflow

### Step 1: Deploy Active Blue Environment
```bash
# 1. Apply Blue Deployment and Main LoadBalancer Service:
kubectl apply -f 01-blue-deployment.yaml
kubectl apply -f 02-main.service.yaml

# 2. Verify Pods and LoadBalancer endpoint:
kubectl get pods -l project=roboshop,tier=frontend -o wide
kubectl get svc nginx
```

Test the live endpoint:
```bash
EXTERNAL_IP=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$EXTERNAL_IP
# Output: <h1>Hi, I am version 0.0.1</h1>
```

---

### Step 2: Deploy and Validate Green Preview
```bash
# 1. Apply Green Deployment and Preview Service:
kubectl apply -f 03-green-deployment.yaml
kubectl apply -f 04-preview-service.yaml

# 2. Verify both Blue and Green pods are active:
kubectl get pods -l project=roboshop,tier=frontend --show-labels

# 3. Port-forward or test preview service internally:
kubectl port-forward svc/nginx-preview 8080:80 &
curl http://localhost:8080
# Output: <h1>Hi, I am version 0.0.2</h1>
```

---

### Step 3: Execute Traffic Cutover (Blue ➔ Green)
Update the main service selector to route all live traffic to the Green pods:
```bash
# Patch the Service selector dynamically to version=green:
kubectl patch svc nginx -p '{"spec":{"selector":{"version":"green"}}}'

# Verify the live endpoint now returns version 0.0.2:
curl http://$EXTERNAL_IP
# Output: <h1>Hi, I am version 0.0.2</h1>
```

---

### Step 4: Instant Rollback (If needed)
If any anomaly is detected on Green, instantly switch traffic back to Blue:
```bash
kubectl patch svc nginx -p '{"spec":{"selector":{"version":"blue"}}}'

# Verify live endpoint returned to 0.0.1:
curl http://$EXTERNAL_IP
```

---

### Step 5: Decommission Old Environment (Post-Cutover)
Once Green has been stable in production for a designated bake period (e.g., 2 hours):
```bash
# 1. Delete preview service:
kubectl delete -f 04-preview-service.yaml

# 2. Scale down or delete old Blue deployment:
kubectl delete -f 01-blue-deployment.yaml
```

---

## 🛠️ Troubleshooting & Debugging Guide

### 1. `Service has no endpoints` (Traffic returns 503 / Connection Refused)
* **Cause:** The Service selector does not match all Pod labels.
* **Investigation:**
  ```bash
  # Check active endpoints linked to the Service:
  kubectl get endpoints nginx
  kubectl get endpoints nginx-preview

  # Compare Service selector with Pod labels:
  kubectl get svc nginx -o jsonpath='{.spec.selector}'
  kubectl get pods --show-labels
  ```
* **Fix:** Ensure all 4 labels (`project`, `tier`, `component`, `version`) match exactly between Pod and Service.

### 2. Pods Stuck in `Pending`
* **Cause:** Insufficient cluster CPU/memory to run both Blue (4 replicas) and Green (4 replicas) concurrently.
* **Fix:**
  ```bash
  kubectl describe pod -l version=green
  # Check node capacity or enable cluster autoscaler / add spot instances
  ```

---

## 🧹 Safe Teardown & Resource Cleanup

> [!WARNING]
> Deleting the `LoadBalancer` Service triggers AWS to asynchronously deprovision the underlying Elastic Load Balancer (ELB).

```bash
# 1. Delete Services (initiates ELB deprovisioning):
kubectl delete -f 02-main.service.yaml
kubectl delete -f 04-preview-service.yaml

# 2. Delete Deployments:
kubectl delete -f 01-blue-deployment.yaml
kubectl delete -f 03-green-deployment.yaml

# 3. Verify all resources are terminated:
kubectl get pods,svc -l project=roboshop
```
