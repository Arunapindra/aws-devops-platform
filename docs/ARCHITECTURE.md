# Architecture Deep Dive

This document provides a comprehensive technical overview of the aws-devops-platform architecture, covering infrastructure, Kubernetes workloads, GitOps, and CI/CD pipelines.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Terraform Infrastructure Modules](#2-terraform-infrastructure-modules)
3. [Environment Strategy](#3-environment-strategy)
4. [Kubernetes Architecture](#4-kubernetes-architecture)
5. [ArgoCD GitOps Architecture](#5-argocd-gitops-architecture)
6. [CI/CD Pipeline Architecture](#6-cicd-pipeline-architecture)
7. [OIDC/IRSA Authentication](#7-oidcirsa-authentication)
8. [Design Decisions and Trade-offs](#8-design-decisions-and-trade-offs)

---

## 1. High-Level Architecture

```
+------------------------------------------------------------------+
|                         Developer Workflow                        |
|                                                                  |
|   git push ──> GitHub PR ──> CI Pipeline ──> Merge ──> CD        |
+----------|-------------------------------------------------------|
           |                                                       |
           v                                                       v
+---------------------+    +---------------------------------------+
|   GitHub Actions    |    |         ArgoCD (GitOps)                |
|                     |    |                                       |
| +-------+ +------+ |    |  +-----+  +-------+  +------+        |
| | Lint  | |Trivy | |    |  | Dev |  |Staging|  | Prod |        |
| |       | |      | |    |  |auto |  |manual |  |manual|        |
| +---+---+ +--+---+ |    |  +--+--+  +---+---+  +--+---+        |
|     |        |      |    |     |         |         |             |
| +---+--------+---+  |    +-----|---------|---------|-------------+
| | Build & Push   |  |          |         |         |
| | to ECR         |  |          v         v         v
| +-------+--------+  |    +----------------------------------+
|         |            |    |     Kubernetes (EKS / Minikube)   |
+---------+------------+    |                                  |
          |                 |  +----------+  +-----------+     |
          v                 |  |Deployment|  |  Service  |     |
+---------+--------+        |  | (Pods)   |  | ClusterIP |     |
|    Amazon ECR    |        |  +----------+  +-----------+     |
|  +----+ +-----+  |        |  +----------+  +-----------+     |
|  |api | |front|  |        |  |   HPA    |  |    PDB    |     |
|  +----+ +-----+  |        |  +----------+  +-----------+     |
|  +------+        |        |  +----------+  +-----------+     |
|  |worker|        |        |  | NetPolicy|  | Ingress   |     |
|  +------+        |        |  +----------+  +-----------+     |
+------------------+        +----------------------------------+
                                       |
          +----------------------------+
          |
          v
+-----------------------------------------------------+
|                  AWS Infrastructure                  |
|  (Provisioned by Terraform)                          |
|                                                      |
|  +--------+    +--------+    +--------+              |
|  |  VPC   |    |  EKS   |    |  ECR   |              |
|  |        |    |        |    |        |              |
|  |3 AZs   |    |OIDC    |    |KMS     |              |
|  |Public + |    |IRSA    |    |Scanning|              |
|  |Private  |    |Managed |    |Lifecycle|             |
|  |Subnets  |    |Nodes   |    |Policies|             |
|  |NAT GW   |    |Logging |    |        |             |
|  |Flow Logs|    |Encrypt |    |        |             |
|  +--------+    +--------+    +--------+              |
+-----------------------------------------------------+
```

### Data Flow Summary

1. **Developer** pushes code to GitHub.
2. **GitHub Actions CI** runs linting, security scans, and builds a Docker image.
3. The image is pushed to **Amazon ECR**.
4. **GitHub Actions CD** updates the Kustomize image tag in the GitOps repository.
5. **ArgoCD** detects the Git change and syncs the new manifests to the **Kubernetes cluster**.
6. The **Kubernetes cluster** runs on **Amazon EKS**, which is provisioned by **Terraform**.

---

## 2. Terraform Infrastructure Modules

All infrastructure is defined as code in `terraform/` using a modular architecture. Each module is self-contained with its own `main.tf`, `variables.tf`, and `outputs.tf`.

### 2.1 VPC Module (`terraform/modules/vpc/`)

Creates a production-ready Virtual Private Cloud.

```
                        VPC (10.x.0.0/16)
                              |
          +-------------------+-------------------+
          |                   |                   |
      AZ us-east-1a      AZ us-east-1b      AZ us-east-1c
      |         |         |         |         |         |
   Public    Private   Public    Private   Public    Private
   Subnet   Subnet    Subnet   Subnet    Subnet   Subnet
      |         |         |         |         |         |
      +----+----+         +----+----+         +----+----+
           |                   |                   |
        NAT GW             NAT GW*            NAT GW*
           |                   |                   |
      Internet GW ─────────────────────── Internet
      (Shared)

  * In dev: single NAT GW shared across AZs (cost saving)
  * In prod: one NAT GW per AZ (high availability)
```

**Key features:**

| Feature | Description |
|---------|-------------|
| **3 Availability Zones** | Automatically selects 3 AZs from the region for high availability |
| **Public Subnets** | CIDR blocks carved from the VPC CIDR using `cidrsubnet()` at indices 0-2 |
| **Private Subnets** | CIDR blocks at indices 3-5; worker nodes and pods run here |
| **NAT Gateway** | Allows private subnet resources to reach the internet; configurable as single (dev) or per-AZ (prod) |
| **VPC Flow Logs** | Captures all traffic metadata and sends to CloudWatch Logs; configurable retention (14 days dev, 90 days prod) |
| **Default SG Lockdown** | The default security group is restricted to deny all traffic, forcing explicit security group creation |
| **Kubernetes Tags** | Subnets are tagged with `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` for the AWS Load Balancer Controller |

**Key variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the VPC |
| `enable_nat_gateway` | `true` | Whether to create NAT Gateways |
| `single_nat_gateway` | `true` | Use one NAT GW (dev) vs. one per AZ (prod) |
| `enable_flow_logs` | `true` | Enable VPC Flow Logs |
| `flow_log_retention_days` | `30` | CloudWatch log retention |

---

### 2.2 EKS Module (`terraform/modules/eks/`)

Creates a managed Kubernetes cluster with IRSA support.

```
+-------------------------------------------------------+
|                    EKS Cluster                         |
|                                                       |
|  Control Plane (AWS Managed)                          |
|  +--------------------------------------------------+|
|  | API Server | etcd | Scheduler | Controller Mgr   ||
|  | Logging: api, audit, authenticator, ...           ||
|  | Encryption: KMS (secrets at rest, prod/staging)   ||
|  +--------------------------------------------------+|
|                                                       |
|  OIDC Provider ──> IAM ──> IRSA (pod-level IAM)     |
|                                                       |
|  Managed Node Groups:                                 |
|  +-----------------+  +-----------------+             |
|  | general         |  | spot / compute  |             |
|  | t3.medium (dev) |  | t3.medium+large |             |
|  | m5.xlarge (prod)|  | c5.xlarge (prod)|             |
|  | 2-4 nodes (dev) |  | 0-3 nodes (dev) |             |
|  | 3-10 nodes(prod)|  | 2-8 nodes (prod)|             |
|  +-----------------+  +-----------------+             |
|                                                       |
|  Security Groups:                                     |
|  +------------------+  +------------------+           |
|  | Cluster SG       |  | Node SG          |           |
|  | - Egress: all    |  | - Egress: all    |           |
|  | - Ingress: nodes |  | - Ingress: self  |           |
|  |   on port 443    |  | - Ingress: ctrl  |           |
|  +------------------+  |   ports 1025-65535|           |
|                         +------------------+           |
+-------------------------------------------------------+
```

**Key features:**

| Feature | Description |
|---------|-------------|
| **OIDC Provider** | Created from the EKS cluster identity issuer; enables IRSA |
| **IRSA** | IAM Roles for Service Accounts -- pods assume IAM roles without static credentials |
| **Managed Node Groups** | AWS manages node provisioning, patching, and draining; supports ON_DEMAND and SPOT |
| **Cluster Logging** | Control plane logs sent to CloudWatch: api, audit, authenticator (dev); adds controllerManager, scheduler (prod) |
| **Secrets Encryption** | KMS key encrypts Kubernetes secrets at rest (staging and prod only) |
| **aws-auth ConfigMap** | Automatically maps the node IAM role to Kubernetes RBAC groups |
| **Rolling Updates** | Node groups configured with `max_unavailable_percentage: 25` |
| **Custom Security Groups** | Separate SGs for control plane and nodes with least-privilege rules |

**Key variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `kubernetes_version` | `1.29` | EKS Kubernetes version |
| `cluster_endpoint_private_access` | `true` | Enable private API endpoint |
| `cluster_endpoint_public_access` | `true` | Enable public API endpoint |
| `cluster_enabled_log_types` | `["api", "audit", "authenticator"]` | Control plane log types |
| `cluster_encryption_key_arn` | `""` | KMS key for secrets encryption (empty = no encryption) |
| `node_groups` | Map of group configs | Instance types, scaling, capacity type, labels, taints |

---

### 2.3 ECR Module (`terraform/modules/ecr/`)

Creates container image repositories with security and lifecycle management.

**Key features:**

| Feature | Description |
|---------|-------------|
| **KMS Encryption** | Optional customer-managed KMS key for image encryption at rest (enabled in staging/prod) |
| **Image Scanning** | `scan_on_push: true` -- every pushed image is automatically scanned for vulnerabilities |
| **Lifecycle Policies** | Two rules: (1) Keep last N tagged images (prefixes: v, release, main, develop); (2) Expire untagged images after 7 days |
| **Tag Mutability** | MUTABLE in dev (convenient for iteration), IMMUTABLE in staging/prod (ensures traceability) |
| **Force Delete** | Enabled in dev (can delete repos with images), disabled in staging/prod (safety) |
| **Multiple Repositories** | Creates repos for `api`, `frontend`, and `worker` services |

**Key variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `repository_names` | `["api", "frontend", "worker"]` | List of ECR repos to create |
| `image_tag_mutability` | `MUTABLE` | Tag immutability setting |
| `scan_on_push` | `true` | Enable vulnerability scanning on push |
| `max_image_count` | `30` | Maximum tagged images to retain |
| `create_kms_key` | `false` | Whether to create a KMS key for encryption |

---

## 3. Environment Strategy

The project defines three environments with progressively stricter security and higher availability.

### Resource Comparison

| Attribute | Dev | Staging | Prod |
|-----------|-----|---------|------|
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| **NAT Gateway** | Single (shared) | Single (shared) | Per-AZ (3 total) |
| **Flow Log Retention** | 14 days | 30 days | 90 days |
| **Node Instance Types** | t3.medium | m5.large, m5.xlarge | m5.xlarge, m5.2xlarge + c5.xlarge, c5.2xlarge |
| **Node Groups** | general (1-4) + spot (0-3) | general (2-6) | general (3-10) + compute (2-8) |
| **Node Capacity** | ON_DEMAND + SPOT | ON_DEMAND | ON_DEMAND only |
| **Disk Size** | 30 GB | 50 GB | 100 GB |
| **EKS Log Types** | api, audit, authenticator | All 5 types | All 5 types |
| **Log Retention** | 14 days | 30 days | 90 days |
| **Secrets Encryption** | No | Yes (KMS) | Yes (KMS, 30-day deletion window) |
| **ECR Tag Mutability** | MUTABLE | IMMUTABLE | IMMUTABLE |
| **ECR KMS Encryption** | No | Yes | Yes |
| **ECR Force Delete** | Yes | No | No |
| **ECR Max Images** | 15 | 20 | 30 |
| **Additional Tags** | None | None | `Compliance = "soc2"` |

### Security Differences

| Security Feature | Dev | Staging | Prod |
|-----------------|-----|---------|------|
| KMS encryption for secrets | No | Yes | Yes (longer deletion window) |
| KMS encryption for ECR | No | Yes | Yes |
| Immutable image tags | No | Yes | Yes |
| SPOT instances allowed | Yes | No | No |
| Force delete repositories | Yes | No | No |
| Compliance tags | No | No | SOC2 |
| Full control plane logging | No (3 types) | Yes (5 types) | Yes (5 types) |

### Terraform State Management

Each environment stores its state in a separate key in the same S3 bucket:

```
S3 Bucket: aws-devops-platform-terraform-state
  +-- environments/dev/terraform.tfstate
  +-- environments/staging/terraform.tfstate
  +-- environments/prod/terraform.tfstate

DynamoDB Table: aws-devops-platform-terraform-locks
  (provides state locking to prevent concurrent modifications)
```

---

## 4. Kubernetes Architecture

### 4.1 Kustomize Base + Overlays Pattern

```
kubernetes/
  base/                          <-- Shared resources
    kustomization.yaml           <-- Declares all base resources
    namespace.yaml               <-- Namespace with Pod Security Standards
    deployments/app.yaml         <-- Deployment with security contexts
    services/app.yaml            <-- ClusterIP Service
    configmaps/app.yaml          <-- Application configuration
  overlays/
    dev/                         <-- Dev customizations
      kustomization.yaml         <-- Patches: 1 replica, debug logging, lower resources
    staging/                     <-- Staging customizations
      kustomization.yaml         <-- Patches: 2 replicas, staging APP_ENV
    prod/                        <-- Prod customizations
      kustomization.yaml         <-- Patches: 3 replicas, warn logging, higher resources
```

**How it works:**

1. The **base** defines the canonical version of each resource.
2. Each **overlay** references the base via `resources: [../../base]`.
3. Overlays apply **JSON patches** to modify specific fields (replicas, resources, config values).
4. Each overlay sets a unique **namespace** (`devops-platform-dev`, `-staging`, `-prod`) and **namePrefix** (`dev-`, `staging-`, `prod-`).
5. ArgoCD points to the overlay directory and runs `kustomize build` to generate the final manifests.

### 4.2 Helm Chart Architecture

The Helm chart (`helm-charts/app/`) provides a parameterized deployment with production best practices.

```
helm-charts/app/
  Chart.yaml                     <-- Chart metadata (name, version, appVersion)
  values.yaml                    <-- Default configuration values
  templates/
    _helpers.tpl                 <-- Template helper functions (names, labels, selectors)
    deployment.yaml              <-- Application Deployment
    service.yaml                 <-- ClusterIP Service
    hpa.yaml                     <-- HorizontalPodAutoscaler
    pdb.yaml                     <-- PodDisruptionBudget
    networkpolicy.yaml           <-- NetworkPolicy
    serviceaccount.yaml          <-- ServiceAccount (with IRSA support)
    ingress.yaml                 <-- Ingress (disabled by default)
```

**Deployment features:**
- **Rolling update strategy:** `maxSurge: 1`, `maxUnavailable: 0` -- zero-downtime deployments
- **Pod anti-affinity:** Prefers scheduling pods on different nodes for resilience
- **Three probe types:** startup (30 attempts), liveness (every 20s), readiness (every 10s)
- **ConfigMap injection:** Environment variables loaded via `envFrom`
- **Downward API:** POD_NAME and POD_NAMESPACE injected as environment variables
- **Prometheus annotations:** Scrape metrics from port 8080 at /metrics
- **Temporary directory:** `/tmp` mounted as emptyDir for read-only root filesystem

**HPA features:**
- Scales on both CPU (70%) and memory (80%)
- Scale-up stabilization: 60 seconds, max 50% increase per minute
- Scale-down stabilization: 300 seconds, max 25% decrease per 2 minutes
- This prevents flapping during transient load spikes

### 4.3 Security Features

The project implements defense-in-depth security at the Kubernetes layer:

```
Namespace Level:
  pod-security.kubernetes.io/enforce: restricted
  pod-security.kubernetes.io/audit: restricted
  pod-security.kubernetes.io/warn: restricted

Pod Level:
  runAsNonRoot: true              <-- Cannot run as root user
  runAsUser: 1000                 <-- Explicit non-root UID
  runAsGroup: 1000                <-- Explicit non-root GID
  fsGroup: 1000                   <-- File system group
  seccompProfile: RuntimeDefault  <-- Linux syscall filtering

Container Level:
  allowPrivilegeEscalation: false <-- Cannot gain more privileges
  readOnlyRootFilesystem: true    <-- Filesystem is read-only
  capabilities.drop: ["ALL"]      <-- All Linux capabilities removed

Network Level:
  NetworkPolicy:
    Ingress: Only from ingress-nginx and monitoring namespaces on port 8080
    Egress: DNS (port 53 to kube-system), HTTPS (port 443)
```

---

## 5. ArgoCD GitOps Architecture

### 5.1 Project Definition

The ArgoCD Project (`argocd/projects/devops-platform.yaml`) defines the security boundary:

```
AppProject: devops-platform
  |
  +-- Source Repos: https://github.com/*/aws-devops-platform.git
  |
  +-- Allowed Destinations:
  |     - devops-platform-dev
  |     - devops-platform-staging
  |     - devops-platform-prod
  |
  +-- Cluster Resource Whitelist:
  |     - Namespace
  |     - ClusterRole
  |     - ClusterRoleBinding
  |
  +-- Roles:
        +-- developer: read all, sync dev only
        +-- admin: full access to all environments
```

### 5.2 Application Sync Strategies

```
                         Git Repository
                              |
              +---------------+---------------+
              |                               |
         develop branch                  main branch
              |                               |
              v                          +----+----+
      +-------+--------+                |         |
      | devops-platform |                v         v
      |     -dev        |        staging app   prod app
      |                 |        (manual)      (manual)
      | AUTO SYNC       |
      | - prune: true   |
      | - selfHeal: true|
      | - retry: 5x     |
      +-----------------+
```

**Dev Application:**
- Source: `develop` branch, path: `kubernetes/overlays/dev`
- Automated sync with pruning and self-healing
- `ApplyOutOfSyncOnly`: Only syncs resources that have actually changed
- `ignoreDifferences` on `/spec/replicas` to avoid fighting with HPA

**Staging Application:**
- Source: `main` branch, path: `kubernetes/overlays/staging`
- Manual sync required
- Slack notifications on sync success and failure
- `PruneLast`: Deletes removed resources after all other syncs complete

**Production Application:**
- Source: `main` branch, path: `kubernetes/overlays/prod`
- Manual sync required
- Slack notifications on sync success and failure
- PagerDuty alerts on health degradation
- `RespectIgnoreDifferences`: Preserves manual overrides (e.g., HPA-managed replicas)
- Sync wave annotation (`argocd.argoproj.io/sync-wave: "10"`) for ordered deployments
- Longer retry backoff (30s initial, up to 10 minutes)

### 5.3 Sync Waves and Hooks

ArgoCD supports ordering resource creation using sync waves. Lower numbers sync first:

```
Wave -1: Namespaces, CRDs
Wave  0: ConfigMaps, Secrets, ServiceAccounts (default)
Wave  5: Deployments, Services
Wave 10: Ingress, HPA, PDB
```

The production application is annotated with `sync-wave: "10"`, meaning it syncs after lower-priority resources are ready.

---

## 6. CI/CD Pipeline Architecture

### 6.1 CI Pipeline (`ci.yaml`)

Triggered on pull requests to `main` or `develop`.

```
Pull Request Opened/Updated
         |
         v
+--------+---------+--------+---------+
|                  |                   |
v                  v                   v
lint-and-test    security-scan      unit-tests
|                  |                   |
| Hadolint         | Trivy FS         | pytest
| terraform fmt    | Trivy Config     | coverage
| TFLint           | Checkov (IaC)    |
| terraform validate| Gitleaks        |
| Helm lint        | (secrets)        |
| yamllint         |                  |
|                  |                  |
+--------+---------+                  |
         |                            |
         v                            |
       build                          |
         |                            |
         | Docker Buildx              |
         | Multi-stage build          |
         | Push to ECR (develop only) |
         | Trivy image scan           |
         | SBOM generation            |
         +----------------------------+
         |
         v
   PR Comments with results
```

**Key design decisions:**
- **Concurrency:** `cancel-in-progress: true` -- if a new commit is pushed to the same PR, the previous run is cancelled
- **OIDC authentication:** No static AWS credentials; uses GitHub's OIDC provider to assume an IAM role
- **Conditional push:** Docker images are only pushed to ECR when the target branch is `develop`
- **SBOM + Provenance:** Build includes Software Bill of Materials and provenance attestation
- **PR comments:** Results are posted as sticky comments on the PR for visibility

### 6.2 CD Dev Pipeline (`cd-dev.yaml`)

Triggered on push to the `develop` branch (i.e., when a PR is merged).

```
Push to develop
       |
       v
  build-and-push
       |
       | Build Docker image
       | Push to ECR with tags:
       |   - <commit-sha>
       |   - develop-latest
       |
       v
  update-gitops
       |
       | Checkout GitOps repo
       | kustomize edit set image
       | Commit and push
       |
       v
  (ArgoCD auto-syncs)
       |
       v
  smoke-tests
       |
       | Wait 60s for ArgoCD
       | kubectl rollout status
       | HTTP health check (10 retries)
       |
       v
  notify (Slack)
       |
       | Success or failure message
```

### 6.3 CD Prod Pipeline (`cd-prod.yaml`)

Triggered on version tags (`v*`). Implements canary deployment.

```
Push tag v1.2.3
       |
       v
  promote-image
       |
       | GitHub Environment: production (requires approval)
       | Copy staging-latest -> v1.2.3, prod-latest in ECR
       |
       v
  canary-deploy
       |
       +---> Phase 1: 10% traffic
       |       | Update kustomize image
       |       | Wait for canary pods
       |       | 20 health checks over 40s
       |       | Fail if error rate > 10%
       |
       +---> Phase 2: 50% traffic
       |       | Scale canary replicas to 3
       |       | 50 health checks over 50s
       |       | Fail if error rate > 5%
       |
       +---> Phase 3: 100% traffic
               | Update main deployment image
               | kubectl rollout status (600s timeout)
       |
       v
  integration-tests
       |
       | Test /health, /ready, /metrics endpoints
       |
       v
  notify (Slack + PagerDuty on failure)

  rollback (runs only if canary-deploy or integration-tests fail)
       |
       | kubectl rollout undo
       | Scale down canary to 0
       | PagerDuty critical alert
```

**Canary deployment thresholds:**
- At 10% traffic: Allow up to 10% error rate
- At 50% traffic: Allow up to 5% error rate
- If either threshold is exceeded, the pipeline triggers automatic rollback

### 6.4 Terraform Pipeline (`terraform.yaml`)

```
terraform/ files changed
       |
       +---> On PR: Plan
       |       |
       |       v
       |   detect-changes
       |       | Finds which environments changed (dev, staging, prod)
       |       |
       |       v
       |   plan (matrix: changed environments)
       |       | terraform init (with S3 backend)
       |       | terraform validate
       |       | terraform plan -out=tfplan
       |       | Post plan as PR comment
       |       | Upload plan artifact
       |
       +---> On Merge to main: Apply
               |
               v
           apply-dev (auto, GitHub Environment: dev)
               |
               v
           apply-staging (after dev, GitHub Environment: staging)
               |
               v
           apply-prod (after staging, GitHub Environment: production)
```

**Key features:**
- **Change detection:** Only plans/applies environments whose files actually changed
- **Environment gates:** Each apply step requires GitHub Environment approval
- **Sequential promotion:** Dev -> Staging -> Prod (staging waits for dev, prod waits for staging)
- **Matrix strategy:** Plans run in parallel for all changed environments

### 6.5 Scheduled Security Scanning (`scheduled-security.yaml`)

```
Daily at 2:00 AM UTC (cron: '0 2 * * *')
       |
       +---> scan-ecr-images
       |       | Pull last 5 images from ECR
       |       | Trivy scan each for CRITICAL/HIGH
       |       | Upload report as artifact (90 day retention)
       |
       +---> scan-codebase
               | Trivy filesystem scan
               | Trivy config scan (Terraform)
               | Checkov IaC scan
               | Parse results with github-script
               | Create GitHub Issue if vulnerabilities found
               |   Title: "Security Scan: YYYY-MM-DD - X Critical, Y High"
               |   Labels: security, automated-scan
```

---

## 7. OIDC/IRSA Authentication

### GitHub Actions OIDC with AWS

This project uses OIDC (OpenID Connect) instead of static AWS credentials for GitHub Actions authentication.

```
+----------------+         +------------------+        +-----------+
|  GitHub Actions |  (1)   | AWS IAM OIDC     |  (3)  | AWS STS   |
|  Workflow       |------->| Identity Provider |------>|           |
|                 |        |                   |       |           |
| JWT Token:      |  (2)   | Trust Policy:     |  (4)  | Temporary |
| - repo: ...     |<-------| - Audience: STS   |<------| Credentials|
| - ref: ...      |        | - Subject: repo/* |       | (15 min)  |
| - workflow: ... |        +------------------+        +-----------+
+----------------+                                          |
                                                           (5)
                                                            v
                                                     +-----------+
                                                     | AWS APIs  |
                                                     | ECR, EKS, |
                                                     | S3, etc.  |
                                                     +-----------+
```

**How it works:**

1. GitHub Actions generates a short-lived JWT token containing claims about the repository, branch, and workflow.
2. The workflow uses `aws-actions/configure-aws-credentials` to present this token to AWS.
3. AWS IAM validates the token against the registered OIDC provider and checks the trust policy conditions (repo name, branch).
4. AWS STS issues temporary credentials (valid for the session duration, typically 15 minutes).
5. The workflow uses these temporary credentials to interact with AWS services.

**Benefits over static credentials:**
- No long-lived secrets to rotate
- Credentials are scoped to the specific workflow run
- Trust policy can restrict access by repository, branch, and environment

### Kubernetes IRSA (IAM Roles for Service Accounts)

IRSA extends the OIDC pattern to Kubernetes pods, allowing them to assume IAM roles without node-level credentials.

```
+------------------+      +-------------------+      +-----------+
|  Kubernetes Pod  |      | EKS OIDC Provider |      | AWS IAM   |
|                  |      |                   |      |           |
| ServiceAccount:  | (1)  | Issues JWT with:  | (3)  | IAM Role  |
|   annotations:   |----->| - sa name         |----->| Trust:    |
|   eks.amazonaws  |      | - sa namespace    |      | - OIDC    |
|   .com/role-arn  | (2)  | - audience: sts   | (4)  |   provider|
|   = arn:aws:iam  |<-----|                   |<-----| - SA name |
|   :ROLE          |      +-------------------+      | - SA ns   |
+------------------+                                  +-----------+
        |                                                   |
        | (5) STS:AssumeRoleWithWebIdentity                |
        +---------------------------------------------------+
        |
        v
  +------------+
  | AWS APIs   |
  | (scoped to |
  | IAM role)  |
  +------------+
```

**How it works:**

1. The pod's ServiceAccount is annotated with `eks.amazonaws.com/role-arn`.
2. EKS mutating webhook injects a projected service account token into the pod.
3. The token is a JWT signed by the EKS OIDC provider.
4. The IAM role's trust policy validates the token's issuer, audience, and subject (ServiceAccount name + namespace).
5. The AWS SDK in the pod calls `STS:AssumeRoleWithWebIdentity` to get temporary credentials.

**In this project:** The Helm chart's `serviceAccount.annotations` field supports setting `eks.amazonaws.com/role-arn` to enable IRSA for any deployed pod.

---

## 8. Design Decisions and Trade-offs

### Kustomize vs. Helm -- Why Both?

This project uses **both** Kustomize and Helm, which is intentional:

- **Helm** is used for the application deployment because it provides powerful templating, lifecycle management (`helm upgrade`, `helm rollback`), and a package management model with versioned releases.
- **Kustomize** is used for the GitOps workflow because ArgoCD natively understands Kustomize, and the base/overlay pattern clearly shows what differs between environments without template syntax.

In a production setup, you would typically choose one for application deployment. This project demonstrates both to serve as a learning reference.

### Single Repo vs. GitOps Repo

The CI/CD pipeline references a separate `aws-devops-platform-gitops` repository for storing Kustomize manifests. This is a common pattern that separates application code changes from deployment configuration changes. The benefit is that ArgoCD only needs to watch the GitOps repo, and the CI/CD pipeline is responsible for promoting images by updating the Kustomize image tag.

### NAT Gateway Strategy

- **Dev uses a single NAT Gateway** to save costs (~$32/month per NAT GW). If the AZ hosting the NAT GW fails, private subnet resources in other AZs lose internet access. This is acceptable for dev.
- **Prod uses one NAT GW per AZ** for high availability. If one AZ fails, the other AZs continue to function independently.

### SPOT Instances in Dev Only

Dev uses SPOT instances for the `batch` node group to reduce costs by up to 90%. SPOT instances can be reclaimed by AWS with 2 minutes notice, so they are only used for non-critical workloads. Staging and prod use ON_DEMAND exclusively for reliability.

### Image Tag Mutability

- **Dev: MUTABLE** -- Allows overwriting tags like `develop-latest` for rapid iteration.
- **Staging/Prod: IMMUTABLE** -- Once a tag is pushed, it cannot be overwritten. This ensures that a given tag always refers to the same image, which is critical for audit trails and rollback reliability.

### Canary Deployment vs. Blue/Green

This project uses **canary deployments** for production (10% -> 50% -> 100%) rather than blue/green. The trade-off:

- **Canary** detects issues with real production traffic at low blast radius, but is more complex to implement and requires careful health check thresholds.
- **Blue/Green** provides instant rollback by switching traffic, but requires 2x the infrastructure during deployment.

### Pod Security Standards: Restricted

The namespace enforces the `restricted` Pod Security Standard, which is the most secure level. This means:
- Containers must run as non-root
- Containers cannot use privileged mode
- Containers cannot use host networking, ports, or PID
- Containers must drop all capabilities
- Containers must have a seccomp profile

This eliminates entire classes of security vulnerabilities but requires the application image to be built to run as a non-root user.
