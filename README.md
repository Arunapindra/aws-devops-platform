# AWS DevOps Platform

A production-grade DevOps platform demonstrating Infrastructure as Code, GitOps, CI/CD pipelines, and Kubernetes platform engineering on AWS.

> **New here?** Start with our **[Getting Started Guide](docs/GETTING-STARTED.md)** -- it walks you through setting up the entire project locally in about 15 minutes, no AWS account required.

---

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started Guide](docs/GETTING-STARTED.md) | Prerequisites, install commands, step-by-step local setup |
| [Architecture Deep Dive](docs/ARCHITECTURE.md) | Terraform modules, CI/CD pipelines, GitOps, OIDC/IRSA, design decisions |
| [Troubleshooting Guide](docs/TROUBLESHOOTING.md) | Common issues with symptoms, causes, and exact fix commands |

---

## What You'll Learn

This project demonstrates real-world SRE and DevOps skills used in production environments:

| Skill | What This Project Teaches |
|-------|---------------------------|
| **Infrastructure as Code** | Modular Terraform with remote state, environment separation, and provider version pinning |
| **Kubernetes Operations** | Deployments, HPA, PDB, NetworkPolicies, Pod Security Standards, health probes |
| **GitOps** | ArgoCD application definitions, auto-sync vs. manual sync, RBAC, self-healing |
| **CI/CD Pipelines** | Multi-stage GitHub Actions with linting, security scanning, building, and canary deployments |
| **Container Security** | Non-root containers, read-only filesystems, capability drops, seccomp profiles, image scanning |
| **Cloud Networking** | VPC design with public/private subnets, NAT Gateways, flow logs, security groups |
| **Secrets Management** | OIDC authentication (no static credentials), IRSA for pod-level IAM, KMS encryption |
| **Deployment Strategies** | Canary deployments (10% -> 50% -> 100%) with automated rollback |
| **Observability** | Prometheus annotations, structured logging, CloudWatch integration |
| **Environment Management** | Dev/staging/prod with different resource allocations, security postures, and deployment gates |

---

## Architecture

```
+------------------------------------------------------------------+
|                        GitHub Actions                              |
|  +----------+  +----------+  +----------+  +---------------+      |
|  |  CI/Lint  |  | Security |  |  Build   |  |  Terraform    |      |
|  |  & Test   |  |  Scans   |  |  & Push  |  |  Plan/Apply   |      |
|  +----+------+  +----+-----+  +----+-----+  +-------+-------+      |
+-------+--------------+-------------+------------------+-------------+
        |              |            |                 |
        v              v            v                 v
+---------------+  +--------+  +--------+  +------------------+
|   ArgoCD      |  | Trivy  |  |  ECR   |  |   AWS Infra      |
|  (GitOps)     |  |Checkov |  |        |  |  +------------+  |
|               |  |Gitleaks|  |        |  |  |    VPC     |  |
|  +---------+  |  +--------+  +---+----+  |  +------------+  |
|  |   Dev   |  |                  |       |  |    EKS     |  |
|  +---------+  |                  |       |  +------------+  |
|  | Staging |<-+------------------+       |  |    ECR     |  |
|  +---------+  |                          |  +------------+  |
|  |  Prod   |  |                          |                  |
|  +---------+  |                          |                  |
+-------+-------+                          +------------------+
        |
        v
+------------------------------------------+
|           Kubernetes (EKS)               |
|  +----------+ +----------+ +----------+  |
|  |  Helm    | | Network  | |   HPA    |  |
|  |  Charts  | | Policies | |  & PDB   |  |
|  +----------+ +----------+ +----------+  |
|  |   RBAC   | | Ingress  | | Service  |  |
|  |          | |  (ALB)   | | Accounts |  |
|  +----------+ +----------+ +----------+  |
+------------------------------------------+
```

---

## Project Structure

```
aws-devops-platform/
+-- terraform/                    # Infrastructure as Code
|   +-- modules/
|   |   +-- vpc/                  # VPC with public/private subnets, NAT GW, flow logs
|   |   +-- eks/                  # EKS cluster with OIDC, IRSA, managed node groups
|   |   +-- ecr/                  # ECR repositories with KMS, scanning, lifecycle
|   +-- environments/
|       +-- dev/                  # Dev: t3.medium, single NAT, SPOT nodes
|       +-- staging/              # Staging: m5.large, KMS encryption, IMMUTABLE tags
|       +-- prod/                 # Prod: m5.xlarge, multi-AZ NAT, SOC2 tags
+-- helm-charts/
|   +-- app/                      # Application Helm chart
|       +-- templates/
|       |   +-- deployment.yaml   # Rolling updates, anti-affinity, probes
|       |   +-- hpa.yaml          # CPU/memory autoscaling with stabilization
|       |   +-- networkpolicy.yaml# Ingress/egress traffic rules
|       |   +-- pdb.yaml          # Pod Disruption Budget (minAvailable: 1)
|       |   +-- service.yaml      # ClusterIP on port 80
|       |   +-- serviceaccount.yaml # IRSA-ready ServiceAccount
|       |   +-- ingress.yaml      # ALB ingress (disabled by default)
|       +-- values.yaml
+-- kubernetes/
|   +-- base/                     # Kustomize base: namespace, deployment, service, configmap
|   +-- overlays/                 # Environment-specific patches
|       +-- dev/                  # 1 replica, debug logs, 50m CPU
|       +-- staging/              # 2 replicas, info logs
|       +-- prod/                 # 3 replicas, warn logs, 250m CPU, 1Gi memory
+-- argocd/
|   +-- applications/             # ArgoCD Application CRDs (dev/staging/prod)
|   +-- projects/                 # ArgoCD Project with RBAC roles
+-- .github/workflows/
|   +-- ci.yaml                   # PR: lint, test, security scan, build
|   +-- cd-dev.yaml               # Auto-deploy to dev on develop branch merge
|   +-- cd-prod.yaml              # Canary deployment (10%->50%->100%) on version tags
|   +-- terraform.yaml            # Terraform plan (PR) / apply (merge) with env gates
|   +-- scheduled-security.yaml   # Nightly Trivy + Checkov scans, auto-create GitHub issues
+-- scripts/
|   +-- setup-local.sh            # Local Minikube + ArgoCD + Helm setup
|   +-- deploy.sh                 # Deployment helper (Terraform + K8s, any env)
|   +-- cleanup.sh                # Resource teardown (Minikube, Docker, Terraform)
+-- docs/
    +-- GETTING-STARTED.md        # Beginner-friendly setup guide
    +-- ARCHITECTURE.md           # Technical architecture deep dive
    +-- TROUBLESHOOTING.md        # Common issues and fixes
```

---

## Quick Start

### Local Development (Minikube)

**Prerequisites:** Docker, kubectl, minikube, helm, terraform, argocd CLI. See the [Getting Started Guide](docs/GETTING-STARTED.md) for exact install commands.

**Option A: Automated setup (recommended)**

```bash
git clone https://github.com/<your-username>/aws-devops-platform.git
cd aws-devops-platform

chmod +x scripts/setup-local.sh
./scripts/setup-local.sh
```

Expected output:
```
=== Checking Prerequisites ===
[OK] docker: Docker version 25.0.3
[OK] kubectl: v1.29.2
[OK] minikube: v1.32.0
[OK] helm: v3.14.2
[OK] terraform: Terraform v1.7.4
[OK] argocd: v2.10.1
[OK] Docker daemon is running
[OK] All prerequisites satisfied

=== Starting Minikube Cluster ===
[INFO] Starting Minikube...
...
[OK] Minikube cluster started successfully

=== Installing ArgoCD ===
[OK] ArgoCD installed successfully

=== Deploying Application ===
[OK] Application deployed via Helm

=== Setup Complete - Access Information ===
...
[OK] Local development environment is ready!
```

**Option B: Manual step-by-step**

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/aws-devops-platform.git
cd aws-devops-platform

# 2. Start Minikube
minikube start --cpus=4 --memory=8192 --disk-size=40g \
  --driver=docker --kubernetes-version=v1.29.2 \
  --addons=ingress,metrics-server,dashboard

# 3. Verify cluster
kubectl get nodes
# Expected: minikube   Ready   control-plane   ...   v1.29.2

# 4. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# 5. Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
# Save this password. Username is "admin".

# 6. Access ArgoCD UI (in a new terminal)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080

# 7. Deploy the application
kubectl create namespace dev
helm upgrade --install aws-devops-platform ./helm-charts/app \
  --namespace dev \
  --set image.repository=nginx \
  --set image.tag=latest

# 8. Verify pods are running
kubectl get pods -n dev
# Expected: aws-devops-platform-...   1/1   Running   0   ...
```

### AWS Deployment

```bash
# 1. Configure AWS credentials
export AWS_PROFILE=your-profile

# 2. Deploy infrastructure
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# 3. Configure kubectl for EKS
aws eks update-kubeconfig --name aws-devops-platform-dev --region us-east-1

# 4. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 5. Deploy applications via ArgoCD
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applications/dev.yaml
```

---

## Local vs Cloud

This project is designed to work both locally (with Minikube) and on AWS (with EKS). Here is what works in each environment:

| Component | Local (Minikube) | AWS (EKS) |
|-----------|-----------------|-----------|
| Kubernetes cluster | Minikube single-node | EKS managed multi-node |
| Application deployment (Helm) | Works fully | Works fully |
| Application deployment (Kustomize) | Works fully | Works fully |
| ArgoCD | Works fully | Works fully |
| Terraform plan/validate | Works (`-backend=false`) | Works fully |
| Terraform apply | Not applicable (no AWS) | Works fully |
| ECR image push/pull | Not applicable | Works fully |
| CI/CD pipelines | View and study only | Works fully with secrets configured |
| Network Policies | Works (with Minikube CNI) | Works (with VPC CNI) |
| Ingress | Minikube ingress addon | AWS ALB Ingress Controller |
| HPA | Works (with metrics-server addon) | Works (with metrics-server) |
| IRSA | Not applicable | Works (requires OIDC provider) |

**Recommendation:** Start locally to understand the Kubernetes resources, then move to AWS when you are ready to test the full infrastructure pipeline.

---

## Technologies

| Category | Tools | Version |
|----------|-------|---------|
| Infrastructure as Code | Terraform | >= 1.5.0 |
| IaC Providers | AWS Provider | ~> 5.40 |
| Container Orchestration | Kubernetes (EKS) | 1.29 |
| GitOps | ArgoCD | >= 2.10 |
| CI/CD | GitHub Actions | - |
| Container Registry | Amazon ECR | - |
| Security Scanning | Trivy | 0.18+ |
| IaC Security | Checkov | v12+ |
| Secret Detection | Gitleaks | v2.3+ |
| Dockerfile Linting | Hadolint | v3.1+ |
| Terraform Linting | TFLint | v0.50+ |
| Package Management | Helm | >= 3.14 |
| Manifest Customization | Kustomize | Built into kubectl |
| Cloud | AWS (VPC, EKS, ECR, IAM, S3, DynamoDB, KMS, CloudWatch) | - |
| Container Runtime | Docker | >= 25.0 |
| Local Kubernetes | Minikube | >= 1.32 |

---

## Key Features

### Infrastructure as Code (Terraform)
- **Modular design**: Reusable VPC, EKS, and ECR modules with clear inputs/outputs
- **Multi-environment**: Separate configs for dev (cost-optimized), staging (prod-like), and prod (HA)
- **Remote state**: S3 backend with DynamoDB locking to prevent concurrent modifications
- **Security**: VPC flow logs, EKS audit logging, ECR image scanning, KMS encryption (staging/prod)
- **IRSA**: IAM Roles for Service Accounts via OIDC -- pods get their own IAM identity

### GitOps (ArgoCD)
- **Declarative deployments**: All environments managed via Git with Kustomize overlays
- **Auto-sync for dev**: Changes merged to `develop` branch auto-deploy within minutes
- **Manual gates for prod**: Require explicit sync approval for production
- **Self-healing**: ArgoCD detects and corrects drift in dev automatically
- **Sync waves**: Ordered deployment of resources (namespaces first, then apps)
- **RBAC**: Developer role (sync dev only) and admin role (full access)

### CI/CD (GitHub Actions)
- **Comprehensive CI**: Linting (Hadolint, TFLint, Helm, YAML), security scanning (Trivy, Checkov, Gitleaks), and unit tests on every PR
- **OIDC auth**: No static AWS credentials -- uses GitHub OIDC to assume IAM roles
- **Multi-stage CD**: Dev (auto on `develop` merge) -> Staging (manual) -> Prod (on version tag)
- **Canary deployments**: Progressive rollout (10% -> 50% -> 100%) with automated rollback on failure
- **Nightly security scans**: Scheduled Trivy and Checkov scans that create GitHub Issues for findings

### Kubernetes Platform
- **Helm charts**: Parameterized deployments with rolling updates, anti-affinity, three probe types
- **Security**: Non-root containers, read-only filesystem, dropped capabilities, NetworkPolicies, Pod Security Standards (restricted)
- **Reliability**: HPA (CPU + memory with stabilization), PDB (minAvailable: 1), pod anti-affinity
- **Kustomize overlays**: Environment-specific configurations (replicas, resources, log levels)

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please review the [Architecture Guide](docs/ARCHITECTURE.md) before making significant changes.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
