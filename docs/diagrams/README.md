# Architecture Diagrams

This directory contains Mermaid diagram sources for the AWS DevOps Platform.

## Viewing

- **GitHub**: Click any `.mmd` file — GitHub renders Mermaid natively
- **VS Code**: Install the [Mermaid Preview](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid) extension
- **CLI**: `npx -p @mermaid-js/mermaid-cli mmdc -i infrastructure.mmd -o infrastructure.png`

## Diagrams

| File | Description |
|------|-------------|
| `infrastructure.mmd` | AWS infrastructure layout (VPC, EKS, ECR) |
| `cicd-flow.mmd` | CI/CD pipeline flow from commit to deployment |
