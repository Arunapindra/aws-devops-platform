# Contributing to AWS DevOps Platform

Thank you for your interest in contributing! This guide will help you get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/<your-username>/aws-devops-platform.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Set up the local environment: `make local-setup`
5. Make your changes
6. Run tests: `make test`
7. Submit a Pull Request

## Development Setup

See [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) for complete local setup instructions.

**Quick start:**
```bash
./scripts/setup-local.sh
make helm-lint
make terraform-validate
```

## Code Standards

### Terraform
- Run `terraform fmt` before committing
- Add Terratest tests for new modules in `modules/<name>/tests/`
- Use consistent variable naming (snake_case)
- Always include `variables.tf` and `outputs.tf` for modules
- Tag all resources with `project`, `environment`, and `managed_by`

### Helm Charts
- Run `helm lint` before committing
- Include test values in `ci/test-values.yaml`
- Use `_helpers.tpl` for shared template logic
- Follow Kubernetes security best practices (non-root, read-only fs, drop capabilities)

### Kubernetes Manifests
- Use Kustomize for environment overlays
- Always set resource requests and limits
- Include health checks (liveness + readiness probes)
- Add network policies for namespace isolation

### CI/CD
- All workflow changes must be tested with `act` locally
- Security scanning must pass (Trivy, Checkov, tfsec)

## Commit Messages

Use conventional commit format:
```
feat: add new EKS node group for GPU workloads
fix: correct IAM policy for ECR cross-account access
docs: update architecture diagram with new VPC layout
refactor: simplify Helm chart template logic
test: add Terratest for ECR module
ci: add tfsec scanning to CI pipeline
```

## Pull Request Process

1. Ensure all CI checks pass
2. Update documentation for any changed behavior
3. Add/update tests
4. Request review from at least one maintainer
5. Squash commits before merging

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
