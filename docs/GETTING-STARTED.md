# Getting Started Guide

This guide walks you through setting up the **aws-devops-platform** project on your local machine from scratch. By the end, you will have a running Kubernetes cluster with ArgoCD and the application deployed locally -- no AWS account required.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Verify Your Tools](#2-verify-your-tools)
3. [Step-by-Step Local Setup](#3-step-by-step-local-setup)
4. [Understanding the Helm Chart](#4-understanding-the-helm-chart)
5. [Understanding Kustomize Overlays](#5-understanding-kustomize-overlays)
6. [How ArgoCD GitOps Sync Works](#6-how-argocd-gitops-sync-works)
7. [Stopping and Cleaning Up](#7-stopping-and-cleaning-up)
8. [What to Explore Next](#8-what-to-explore-next)

---

## 1. Prerequisites

You need the following tools installed on your machine. Below are exact install commands for macOS and Linux (Ubuntu/Debian).

### Docker Desktop

Docker Desktop provides the container runtime that Minikube uses as its driver.

**macOS (Homebrew):**
```bash
brew install --cask docker
```

**Linux (Ubuntu/Debian):**
```bash
# Install Docker Engine
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add your user to the docker group so you don't need sudo
sudo usermod -aG docker $USER
newgrp docker
```

**Minimum Resource Settings (Docker Desktop):**

Open Docker Desktop > Settings > Resources and configure:
- **CPUs:** 4 (minimum)
- **Memory:** 8 GB (minimum)
- **Disk image size:** 40 GB (recommended)

These resources are needed because Minikube, ArgoCD, and the application all run inside Docker containers on your machine.

---

### kubectl v1.29+

The Kubernetes command-line tool for interacting with clusters.

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

---

### Minikube v1.32+

Runs a single-node Kubernetes cluster locally inside Docker.

**macOS:**
```bash
brew install minikube
```

**Linux:**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
```

---

### Helm v3.14+

The Kubernetes package manager used for deploying the application chart.

**macOS:**
```bash
brew install helm
```

**Linux:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

### Terraform v1.5+

Infrastructure as Code tool used for provisioning AWS resources (for cloud deployments).

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Linux:**
```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

---

### ArgoCD CLI v2.10+

Command-line interface for ArgoCD, the GitOps continuous delivery tool.

**macOS:**
```bash
brew install argocd
```

**Linux:**
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

---

### Git

Version control system.

**macOS:**
```bash
brew install git
```

**Linux:**
```bash
sudo apt-get update && sudo apt-get install -y git
```

---

## 2. Verify Your Tools

Run each of the following commands to confirm everything is installed correctly. The exact version numbers may differ, but ensure they meet the minimum versions listed above.

```bash
docker --version
# Expected output (example): Docker version 25.0.3, build 4debf41

kubectl version --client
# Expected output (example): Client Version: v1.29.2

minikube version
# Expected output (example): minikube version: v1.32.0

helm version --short
# Expected output (example): v3.14.2+g5e30c27

terraform version
# Expected output (example): Terraform v1.7.4

argocd version --client
# Expected output (example): argocd: v2.10.1+...

git --version
# Expected output (example): git version 2.44.0
```

If any tool is missing or too old, revisit the install commands above. Also verify that Docker Desktop is running:

```bash
docker info
# Should display server information without errors.
# If you see "Cannot connect to the Docker daemon", start Docker Desktop first.
```

---

## 3. Step-by-Step Local Setup

### Step 1: Clone the Repository

```bash
git clone https://github.com/<your-username>/aws-devops-platform.git
cd aws-devops-platform
```

Expected output:
```
Cloning into 'aws-devops-platform'...
remote: Enumerating objects: ...
remote: Counting objects: 100% ...
Receiving objects: 100% ...
```

### Step 2: Start the Minikube Cluster

This creates a local Kubernetes cluster with enough resources for ArgoCD and the application.

```bash
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=40g \
  --driver=docker \
  --kubernetes-version=v1.29.2 \
  --addons=ingress,metrics-server,dashboard
```

Expected output:
```
* minikube v1.32.0 on Darwin ...
* Using the docker driver based on user configuration
* Starting control plane node minikube in cluster minikube
* Creating docker container (CPUs=4, Memory=8192MB, Disk=40000MB) ...
* Preparing Kubernetes v1.29.2 on Docker ...
* Verifying Kubernetes components...
  - Using image gcr.io/k8s-minikube/storage-provisioner:v5
  - Using image registry.k8s.io/ingress-nginx/controller:...
  - Using image registry.k8s.io/metrics-server/metrics-server:...
* Enabled addons: storage-provisioner, ingress, metrics-server, dashboard
* Done! kubectl is now configured to use "minikube" cluster
```

**Alternatively**, you can use the provided setup script which automates the next several steps:
```bash
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh
```

If you use the script, it handles Steps 2 through 7 automatically. The steps below explain what happens under the hood.

### Step 3: Verify the Cluster Is Running

```bash
kubectl cluster-info
```

Expected output:
```
Kubernetes control plane is running at https://127.0.0.1:xxxxx
CoreDNS is running at https://127.0.0.1:xxxxx/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

```bash
kubectl get nodes
```

Expected output:
```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   1m    v1.29.2
```

Make sure the STATUS is `Ready` before proceeding.

### Step 4: Install ArgoCD in the Cluster

Create the ArgoCD namespace and install the server components:

```bash
kubectl create namespace argocd
```

Expected output:
```
namespace/argocd created
```

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Expected output (truncated):
```
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io created
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io created
serviceaccount/argocd-application-controller created
...
deployment.apps/argocd-server created
```

Wait for ArgoCD to be fully ready (this typically takes 2-3 minutes):

```bash
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s
```

Expected output:
```
deployment.apps/argocd-server condition met
```

Also wait for the repo server:

```bash
kubectl wait --for=condition=available deployment/argocd-repo-server \
  -n argocd --timeout=300s
```

### Step 5: Get the ArgoCD Admin Password

The initial admin password is stored in a Kubernetes secret:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Expected output (your password will be different):
```
aB3cD4eFgHiJ
```

Save this password -- you will need it to log into the ArgoCD UI. The username is `admin`.

### Step 6: Port-Forward the ArgoCD UI

Open a **new terminal window** (this command runs in the foreground) and run:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Expected output:
```
Forwarding from 127.0.0.1:8080 -> 8443
Forwarding from [::1]:8080 -> 8443
```

Now open your browser and navigate to:

```
https://localhost:8080
```

Your browser will show a certificate warning because ArgoCD uses a self-signed certificate. Click "Advanced" and proceed. Log in with:
- **Username:** `admin`
- **Password:** (the password from Step 5)

### Step 7: Deploy the Application via Helm

In your **original terminal** (not the port-forward terminal), deploy the application:

```bash
kubectl create namespace dev
```

```bash
helm upgrade --install aws-devops-platform ./helm-charts/app \
  --namespace dev \
  --set image.repository=nginx \
  --set image.tag=latest \
  --set replicaCount=2 \
  --wait --timeout 300s
```

We use `nginx` as the image since we do not have a real application image locally. In a real deployment, this would point to your ECR repository.

Expected output:
```
Release "aws-devops-platform" does not exist. Installing it now.
NAME: aws-devops-platform
LAST DEPLOYED: ...
NAMESPACE: dev
STATUS: deployed
REVISION: 1
```

### Step 8: Deploy via Kustomize Overlays

Kustomize is an alternative deployment method used by ArgoCD. You can preview what it generates:

```bash
kubectl kustomize kubernetes/overlays/dev
```

This outputs the full YAML that would be applied. To actually deploy it:

```bash
kubectl apply -k kubernetes/overlays/dev
```

Expected output:
```
namespace/devops-platform-dev created
configmap/dev-devops-platform-app-config created
service/dev-devops-platform-app created
deployment.apps/dev-devops-platform-app created
```

### Step 9: Verify Everything Is Running

Check the Helm-deployed application:

```bash
kubectl get pods -n dev
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
aws-devops-platform-xxxxxxxx-xxxxx      1/1     Running   0          2m
aws-devops-platform-xxxxxxxx-yyyyy      1/1     Running   0          2m
```

Check the Kustomize-deployed application:

```bash
kubectl get pods -n devops-platform-dev
```

Check all services:

```bash
kubectl get svc -n dev
kubectl get svc -n devops-platform-dev
```

Check ArgoCD is healthy:

```bash
kubectl get pods -n argocd
```

Expected output (all pods should be `Running`):
```
NAME                                  READY   STATUS    RESTARTS   AGE
argocd-application-controller-0       1/1     Running   0          10m
argocd-dex-server-xxxxxxxxx-xxxxx     1/1     Running   0          10m
argocd-redis-xxxxxxxxx-xxxxx          1/1     Running   0          10m
argocd-repo-server-xxxxxxxxx-xxxxx    1/1     Running   0          10m
argocd-server-xxxxxxxxx-xxxxx         1/1     Running   0          10m
```

### Step 10: Access the Application

For the Helm-deployed app:

```bash
kubectl port-forward svc/aws-devops-platform-devops-platform-app -n dev 9090:80
```

Then open `http://localhost:9090` in your browser.

Alternatively, use Minikube's built-in service tunnel:

```bash
minikube service aws-devops-platform-devops-platform-app -n dev
```

This automatically opens your browser to the correct URL.

---

## 4. Understanding the Helm Chart

The Helm chart is located at `helm-charts/app/` and creates the following Kubernetes resources:

| Resource | File | Purpose |
|----------|------|---------|
| Deployment | `templates/deployment.yaml` | Runs the application pods with rolling update strategy |
| Service | `templates/service.yaml` | ClusterIP service exposing port 80 -> 8080 |
| HPA | `templates/hpa.yaml` | Auto-scales pods based on CPU (70%) and memory (80%) |
| PDB | `templates/pdb.yaml` | Guarantees at least 1 pod is always available during disruptions |
| NetworkPolicy | `templates/networkpolicy.yaml` | Restricts traffic to only allowed sources/destinations |
| ServiceAccount | `templates/serviceaccount.yaml` | Pod identity with IRSA annotation support |
| Ingress | `templates/ingress.yaml` | ALB ingress for external traffic (disabled by default) |

### Key `values.yaml` Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `replicaCount` | `2` | Number of pod replicas (ignored when HPA is enabled) |
| `image.repository` | ECR URL | Container image registry and name |
| `image.tag` | `""` | Image tag; defaults to the chart's `appVersion` if empty |
| `image.pullPolicy` | `IfNotPresent` | When to pull the image |
| `serviceAccount.create` | `true` | Whether to create a dedicated ServiceAccount |
| `serviceAccount.annotations` | `{}` | Add `eks.amazonaws.com/role-arn` for IRSA |
| `podSecurityContext.runAsNonRoot` | `true` | Prevents running containers as root |
| `securityContext.readOnlyRootFilesystem` | `true` | Makes the container filesystem read-only |
| `securityContext.capabilities.drop` | `["ALL"]` | Drops all Linux capabilities |
| `service.type` | `ClusterIP` | Service type; change to `LoadBalancer` or `NodePort` for external access |
| `service.port` | `80` | Port the Service listens on |
| `service.targetPort` | `8080` | Port the container listens on |
| `ingress.enabled` | `false` | Set to `true` to create an Ingress resource |
| `autoscaling.enabled` | `true` | Enables Horizontal Pod Autoscaler |
| `autoscaling.minReplicas` | `2` | Minimum number of replicas |
| `autoscaling.maxReplicas` | `10` | Maximum number of replicas |
| `autoscaling.targetCPUUtilizationPercentage` | `70` | CPU threshold to trigger scale-up |
| `resources.requests.cpu` | `100m` | CPU request per pod |
| `resources.requests.memory` | `128Mi` | Memory request per pod |
| `resources.limits.cpu` | `500m` | CPU limit per pod |
| `resources.limits.memory` | `512Mi` | Memory limit per pod |
| `networkPolicy.enabled` | `true` | Enables NetworkPolicy for pod traffic control |
| `podDisruptionBudget.enabled` | `true` | Enables PDB |
| `podDisruptionBudget.minAvailable` | `1` | Minimum pods that must stay available |
| `probes.liveness` | HTTP /healthz | Restarts pod if health check fails |
| `probes.readiness` | HTTP /readyz | Removes pod from traffic if not ready |
| `probes.startup` | HTTP /healthz | Gives the pod time to start up before liveness kicks in |

### Overriding Values

You can override any value at install time:

```bash
# Single values
helm upgrade --install myapp ./helm-charts/app \
  --set replicaCount=3 \
  --set image.tag=v1.2.3

# Using a values file
helm upgrade --install myapp ./helm-charts/app \
  -f my-custom-values.yaml
```

---

## 5. Understanding Kustomize Overlays

Kustomize uses a "base + overlays" pattern. The base defines the common resources, and each overlay customizes them for a specific environment.

### Base (`kubernetes/base/`)

Contains the core resources that all environments share:
- `namespace.yaml` -- Creates the `devops-platform` namespace with Pod Security Standards set to `restricted`
- `deployments/app.yaml` -- The Deployment with 2 replicas, security contexts, health probes
- `services/app.yaml` -- ClusterIP Service on port 80
- `configmaps/app.yaml` -- Application configuration (APP_ENV, LOG_LEVEL, etc.)

### Overlays

Each overlay patches the base for its environment:

| Overlay | Namespace | Replicas | CPU Request | Memory Request | CPU Limit | Memory Limit | LOG_LEVEL | APP_ENV |
|---------|-----------|----------|-------------|----------------|-----------|--------------|-----------|---------|
| **dev** | `devops-platform-dev` | 1 | 50m | 64Mi | 200m | 256Mi | debug | development |
| **staging** | `devops-platform-staging` | 2 | 100m (base) | 128Mi (base) | 500m (base) | 512Mi (base) | info (base) | staging |
| **prod** | `devops-platform-prod` | 3 | 250m | 256Mi | 1 CPU | 1Gi | warn | production |

To preview what an overlay generates without applying it:

```bash
# Preview dev overlay
kubectl kustomize kubernetes/overlays/dev

# Preview staging overlay
kubectl kustomize kubernetes/overlays/staging

# Preview prod overlay
kubectl kustomize kubernetes/overlays/prod
```

To apply an overlay:

```bash
kubectl apply -k kubernetes/overlays/dev
```

---

## 6. How ArgoCD GitOps Sync Works

ArgoCD watches your Git repository and automatically (or manually) syncs Kubernetes resources to match what is defined in Git. This project defines three ArgoCD Applications in `argocd/applications/`.

### Sync Strategy Per Environment

| Environment | Branch | Sync Mode | Auto-Prune | Self-Heal | Retry |
|-------------|--------|-----------|------------|-----------|-------|
| **dev** | `develop` | Automated | Yes | Yes | 5 attempts, exponential backoff |
| **staging** | `main` | Manual | No | No | 3 attempts |
| **prod** | `main` | Manual | No | No | 3 attempts, longer backoff |

**What this means in practice:**

- **Dev (auto-sync):** When you merge a PR into the `develop` branch, ArgoCD detects the change within ~3 minutes and automatically applies the new manifests from `kubernetes/overlays/dev`. If someone manually changes something in the cluster, ArgoCD will revert it back (self-heal).

- **Staging (manual sync):** Changes to the `main` branch show up as "OutOfSync" in the ArgoCD UI, but are NOT applied automatically. A team member must click "Sync" in the ArgoCD UI or run `argocd app sync devops-platform-staging` to deploy.

- **Production (manual sync):** Same as staging, but with additional safeguards: longer retry backoff (30s initial), `RespectIgnoreDifferences` option, and PagerDuty alerts configured for health degradation.

### RBAC and Project Configuration

The ArgoCD Project (`argocd/projects/devops-platform.yaml`) defines two roles:

- **developer** -- Can view all applications and sync only dev environments
- **admin** -- Full access to all environments including production

### Setting Up ArgoCD Applications Locally

To register the ArgoCD applications in your local cluster:

```bash
# Apply the project definition first
kubectl apply -f argocd/projects/devops-platform.yaml

# Then apply the application definitions
kubectl apply -f argocd/applications/dev.yaml
kubectl apply -f argocd/applications/staging.yaml
kubectl apply -f argocd/applications/prod.yaml
```

Note: These applications point to `https://github.com/example/aws-devops-platform.git`. You will need to edit the `repoURL` field in each file to match your actual repository URL.

---

## 7. Stopping and Cleaning Up

### Stop the cluster (preserves state)

```bash
minikube stop
```

The cluster can be restarted later with `minikube start` and all your deployments will still be there.

### Delete everything

Using the provided cleanup script:

```bash
chmod +x scripts/cleanup.sh

# Delete only the Minikube cluster
./scripts/cleanup.sh --minikube

# Delete Minikube and clean Docker images
./scripts/cleanup.sh --minikube --docker

# Delete everything (Minikube + Docker + Terraform state files)
./scripts/cleanup.sh --all

# Skip all confirmation prompts
./scripts/cleanup.sh --all --force
```

Or manually:

```bash
# Delete Minikube cluster entirely
minikube delete --all --purge

# Remove project Docker images
docker images | grep aws-devops | awk '{print $3}' | xargs docker rmi -f

# Clean up Docker build cache
docker builder prune -f

# Remove Terraform local files
find terraform/ -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null
find terraform/ -name "*.tfstate*" -delete 2>/dev/null
find terraform/ -name ".terraform.lock.hcl" -delete 2>/dev/null
```

### Remove Helm release without deleting the cluster

```bash
helm uninstall aws-devops-platform -n dev
```

### Remove Kustomize-deployed resources

```bash
kubectl delete -k kubernetes/overlays/dev
```

---

## 8. What to Explore Next

Now that you have the project running locally, here are recommended next steps:

| Topic | Document | What You Will Learn |
|-------|----------|---------------------|
| Architecture Deep Dive | [docs/ARCHITECTURE.md](ARCHITECTURE.md) | How the Terraform modules, CI/CD pipelines, and GitOps workflows are designed |
| Troubleshooting | [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and how to fix them |
| CI/CD Pipelines | `.github/workflows/` | How GitHub Actions handles linting, security scanning, building, and deploying |
| Terraform Modules | `terraform/modules/` | How VPC, EKS, and ECR infrastructure is codified |
| Helm Chart | `helm-charts/app/` | Modify `values.yaml` and run `helm template` to see generated YAML |
| Kustomize | `kubernetes/overlays/` | Try creating a new overlay for a custom environment |
| Scripts | `scripts/` | Read `deploy.sh` to understand the full deployment flow |

### Suggested Hands-On Exercises

1. **Modify the Helm chart:** Change `replicaCount` to 3 in `values.yaml` and run `helm upgrade`.
2. **Create a new Kustomize overlay:** Copy `kubernetes/overlays/dev/` to `kubernetes/overlays/sandbox/` and customize it.
3. **Explore ArgoCD:** Open the ArgoCD UI and examine how applications, sync status, and resource trees are displayed.
4. **Read the Terraform code:** Run `terraform validate` in `terraform/environments/dev/` (use `-backend=false` since you do not have an S3 backend locally).
5. **Inspect security settings:** Look at the `podSecurityContext` and `securityContext` in the Helm chart and the `pod-security.kubernetes.io` labels in the Kustomize namespace.
