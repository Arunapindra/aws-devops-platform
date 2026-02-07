# AWS DevOps Platform

A production-grade DevOps platform demonstrating Infrastructure as Code, GitOps, CI/CD pipelines, and Kubernetes platform engineering on AWS.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Actions                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐   │
│  │  CI/Lint  │  │ Security │  │  Build   │  │  Terraform    │   │
│  │  & Test   │  │  Scans   │  │  & Push  │  │  Plan/Apply   │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───────┬───────┘   │
└───────┼──────────────┼────────────┼─────────────────┼───────────┘
        │              │            │                 │
        ▼              ▼            ▼                 ▼
┌───────────────┐  ┌────────┐  ┌────────┐  ┌──────────────────┐
│   ArgoCD      │  │ Trivy  │  │  ECR   │  │   AWS Infra      │
│  (GitOps)     │  │Checkov │  │        │  │  ┌────────────┐  │
│               │  │Gitleaks│  │        │  │  │    VPC     │  │
│  ┌─────────┐  │  └────────┘  └───┬────┘  │  ├────────────┤  │
│  │   Dev   │  │                  │       │  │    EKS     │  │
│  ├─────────┤  │                  │       │  ├────────────┤  │
│  │ Staging │◄─┼──────────────────┘       │  │    ECR     │  │
│  ├─────────┤  │                          │  └────────────┘  │
│  │  Prod   │  │                          │                  │
│  └─────────┘  │                          │                  │
└───────┬───────┘                          └──────────────────┘
        │
        ▼
┌──────────────────────────────────────────┐
│           Kubernetes (EKS)               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │  Helm    │ │ Network  │ │   HPA    │ │
│  │  Charts  │ │ Policies │ │  & PDB   │ │
│  ├──────────┤ ├──────────┤ ├──────────┤ │
│  │   RBAC   │ │ Ingress  │ │ Service  │ │
│  │          │ │  (ALB)   │ │ Accounts │ │
│  └──────────┘ └──────────┘ └──────────┘ │
└──────────────────────────────────────────┘
```

## Project Structure

```
aws-devops-platform/
├── terraform/                    # Infrastructure as Code
│   ├── modules/
│   │   ├── vpc/                  # VPC with public/private subnets
│   │   ├── eks/                  # EKS cluster with managed node groups
│   │   └── ecr/                  # ECR repositories
│   └── environments/
│       ├── dev/                  # Development environment
│       ├── staging/              # Staging environment
│       └── prod/                 # Production environment
├── helm-charts/
│   └── app/                      # Application Helm chart
│       ├── templates/
│       │   ├── deployment.yaml   # Rolling updates, anti-affinity
│       │   ├── hpa.yaml          # Horizontal Pod Autoscaler
│       │   ├── networkpolicy.yaml# Network segmentation
│       │   └── pdb.yaml          # Pod Disruption Budget
│       └── values.yaml
├── kubernetes/
│   ├── base/                     # Kustomize base manifests
│   └── overlays/                 # Environment-specific overlays
│       ├── dev/
│       ├── staging/
│       └── prod/
├── argocd/
│   ├── applications/             # ArgoCD Application CRDs
│   └── projects/                 # ArgoCD Project definitions
├── .github/workflows/
│   ├── ci.yaml                   # Lint, test, security scan, build
│   ├── cd-dev.yaml               # Auto-deploy to dev
│   ├── cd-prod.yaml              # Gated deploy to production
│   ├── terraform.yaml            # Terraform plan/apply pipeline
│   └── scheduled-security.yaml   # Nightly vulnerability scans
└── scripts/
    ├── setup-local.sh            # Local Minikube setup
    ├── deploy.sh                 # Deployment helper
    └── cleanup.sh                # Resource cleanup
```

## Key Features

### Infrastructure as Code (Terraform)
- **Modular design**: Reusable VPC, EKS, and ECR modules
- **Multi-environment**: Separate configs for dev, staging, and prod
- **Remote state**: S3 backend with DynamoDB locking
- **Security**: VPC flow logs, EKS audit logging, ECR image scanning
- **IRSA**: IAM Roles for Service Accounts via OIDC

### GitOps (ArgoCD)
- **Declarative deployments**: All environments managed via Git
- **Auto-sync for dev**: Changes merged to develop auto-deploy
- **Manual gates for prod**: Require approval for production syncs
- **Self-healing**: ArgoCD detects and corrects drift
- **Sync waves**: Ordered deployment of resources

### CI/CD (GitHub Actions)
- **Comprehensive CI**: Linting, testing, security scanning on every PR
- **OIDC auth**: No static AWS credentials stored in GitHub
- **Multi-stage CD**: Dev (auto) → Staging (manual) → Prod (gated)
- **Canary deployments**: Progressive rollout for production
- **Security**: Trivy, Checkov, Gitleaks integrated in pipeline

### Kubernetes Platform
- **Helm charts**: Parameterized deployments with best practices
- **Security**: Non-root containers, NetworkPolicies, RBAC
- **Reliability**: HPA, PDB, pod anti-affinity, health probes
- **Kustomize overlays**: Environment-specific configurations

## Quick Start

### Local Development (Minikube)

```bash
# Prerequisites: docker, kubectl, minikube, helm, argocd CLI
./scripts/setup-local.sh

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Deploy the application
helm install app ./helm-charts/app -n default
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

# 3. Configure kubectl
aws eks update-kubeconfig --name devops-platform-dev --region us-east-1

# 4. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 5. Deploy applications via ArgoCD
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applications/dev.yaml
```

## Technologies

| Category | Tools |
|----------|-------|
| IaC | Terraform, Kustomize |
| Container Orchestration | Kubernetes (EKS) |
| GitOps | ArgoCD |
| CI/CD | GitHub Actions |
| Container Registry | Amazon ECR |
| Security | Trivy, Checkov, Gitleaks |
| Package Management | Helm |
| Cloud | AWS (VPC, EKS, ECR, IAM, S3, DynamoDB) |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
