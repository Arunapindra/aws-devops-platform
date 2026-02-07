#!/usr/bin/env bash
###############################################################################
# deploy.sh - Deployment Helper Script
#
# Deploys the aws-devops-platform to a specified environment by running
# Terraform infrastructure provisioning and Kubernetes application deployment.
#
# Usage:
#   ./scripts/deploy.sh <environment> [OPTIONS]
#
# Arguments:
#   environment    Target environment: dev, staging, or prod
#
# Options:
#   --dry-run      Show what would be done without making changes
#   --skip-tf      Skip Terraform infrastructure deployment
#   --skip-k8s     Skip Kubernetes application deployment
#   --auto-approve Skip all confirmation prompts (use with caution)
#   --help, -h     Show this help message
#
# Examples:
#   ./scripts/deploy.sh dev
#   ./scripts/deploy.sh staging --dry-run
#   ./scripts/deploy.sh prod --skip-tf --auto-approve
###############################################################################
set -euo pipefail

#------------------------------------------------------------------------------
# Color definitions
#------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALID_ENVS=("dev" "staging" "prod")
APP_NAME="aws-devops-platform"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Flags
DRY_RUN=false
SKIP_TF=false
SKIP_K8S=false
AUTO_APPROVE=false
ENVIRONMENT=""

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }
log_dry_run() { echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $*"; }

usage() {
    echo -e "${BOLD}Usage:${NC} $0 <environment> [OPTIONS]"
    echo ""
    echo -e "${BOLD}Arguments:${NC}"
    echo "  environment         Target: dev, staging, or prod"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --dry-run           Show what would be done without making changes"
    echo "  --skip-tf           Skip Terraform infrastructure deployment"
    echo "  --skip-k8s          Skip Kubernetes application deployment"
    echo "  --auto-approve      Skip confirmation prompts"
    echo "  --help, -h          Show this help message"
    echo ""
    echo -e "${BOLD}Environment Variables:${NC}"
    echo "  AWS_REGION          AWS region (default: us-east-1)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 dev                       # Full deploy to dev"
    echo "  $0 staging --dry-run         # Dry-run staging deployment"
    echo "  $0 prod --auto-approve       # Deploy to prod without prompts"
    echo "  $0 dev --skip-tf             # Only deploy K8s (skip Terraform)"
    exit 0
}

# Validate that the environment argument is one of the allowed values
validate_environment() {
    local env="$1"
    for valid in "${VALID_ENVS[@]}"; do
        if [[ "$env" == "$valid" ]]; then
            return 0
        fi
    done
    log_error "Invalid environment: '${env}'"
    log_error "Valid environments: ${VALID_ENVS[*]}"
    exit 1
}

# Prompt for confirmation unless --auto-approve is set
confirm() {
    if [ "$AUTO_APPROVE" = true ]; then
        return 0
    fi
    local message="$1"
    read -rp "$(echo -e "${YELLOW}${message} (y/N): ${NC}")" answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_info "Aborted by user"
        exit 0
    fi
}

#------------------------------------------------------------------------------
# Parse arguments
#------------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    log_error "Environment argument is required"
    echo ""
    usage
fi

# First positional argument is the environment
ENVIRONMENT="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)      DRY_RUN=true; shift ;;
        --skip-tf)      SKIP_TF=true; shift ;;
        --skip-k8s)     SKIP_K8S=true; shift ;;
        --auto-approve) AUTO_APPROVE=true; shift ;;
        --help|-h)      usage ;;
        *)              log_error "Unknown option: $1"; usage ;;
    esac
done

validate_environment "$ENVIRONMENT"

#------------------------------------------------------------------------------
# Display deployment plan
#------------------------------------------------------------------------------
log_header "Deployment Plan"

echo -e "  ${BOLD}Environment:${NC}  ${ENVIRONMENT}"
echo -e "  ${BOLD}Region:${NC}       ${AWS_REGION}"
echo -e "  ${BOLD}Dry Run:${NC}      ${DRY_RUN}"
echo -e "  ${BOLD}Terraform:${NC}    $([ "$SKIP_TF" = true ] && echo "SKIP" || echo "YES")"
echo -e "  ${BOLD}Kubernetes:${NC}   $([ "$SKIP_K8S" = true ] && echo "SKIP" || echo "YES")"
echo ""

# Extra warning for production
if [ "$ENVIRONMENT" = "prod" ]; then
    echo -e "  ${RED}${BOLD}*** WARNING: Deploying to PRODUCTION! ***${NC}"
    echo ""
fi

confirm "Proceed with deployment to ${ENVIRONMENT}?"

#------------------------------------------------------------------------------
# Step 1: Terraform infrastructure deployment
#------------------------------------------------------------------------------
if [ "$SKIP_TF" = false ]; then
    log_header "Terraform Deployment (${ENVIRONMENT})"

    TF_DIR="${PROJECT_ROOT}/terraform/environments/${ENVIRONMENT}"

    if [ ! -d "$TF_DIR" ]; then
        log_error "Terraform directory not found: ${TF_DIR}"
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log_dry_run "cd ${TF_DIR}"
        log_dry_run "terraform init"
        log_dry_run "terraform plan -out=tfplan"
        log_dry_run "terraform apply tfplan"
    else
        log_info "Initializing Terraform..."
        cd "$TF_DIR"
        terraform init

        log_info "Creating Terraform plan..."
        terraform plan -out=tfplan

        if [ "$ENVIRONMENT" = "prod" ]; then
            confirm "Apply Terraform changes to PRODUCTION?"
        fi

        log_info "Applying Terraform changes..."
        terraform apply tfplan

        # Clean up the plan file
        rm -f tfplan

        log_success "Terraform deployment complete for ${ENVIRONMENT}"
    fi
else
    log_info "Skipping Terraform deployment (--skip-tf)"
fi

#------------------------------------------------------------------------------
# Step 2: Kubernetes application deployment
#------------------------------------------------------------------------------
if [ "$SKIP_K8S" = false ]; then
    log_header "Kubernetes Deployment (${ENVIRONMENT})"

    KUSTOMIZE_DIR="${PROJECT_ROOT}/kubernetes/overlays/${ENVIRONMENT}"
    HELM_DIR="${PROJECT_ROOT}/helm-charts/app"

    if [ "$DRY_RUN" = true ]; then
        if [ -d "$KUSTOMIZE_DIR" ]; then
            log_dry_run "kubectl apply -k ${KUSTOMIZE_DIR}"
        fi
        if [ -d "$HELM_DIR" ]; then
            log_dry_run "helm upgrade --install ${APP_NAME} ${HELM_DIR} -n ${ENVIRONMENT}"
        fi
    else
        # Update kubeconfig for EKS (if on AWS)
        log_info "Updating kubeconfig for EKS cluster..."
        aws eks update-kubeconfig \
            --name "${APP_NAME}-${ENVIRONMENT}" \
            --region "${AWS_REGION}" 2>/dev/null || \
            log_warn "Could not update kubeconfig for EKS. Using current context."

        # Apply Kustomize overlays if they exist
        if [ -d "$KUSTOMIZE_DIR" ]; then
            log_info "Applying Kustomize manifests from ${KUSTOMIZE_DIR}..."
            kubectl apply -k "$KUSTOMIZE_DIR"
            log_success "Kustomize manifests applied"
        else
            log_warn "Kustomize overlay not found at ${KUSTOMIZE_DIR}"
        fi

        # Deploy via Helm chart if it exists
        if [ -d "$HELM_DIR" ] && [ -f "${HELM_DIR}/Chart.yaml" ]; then
            log_info "Deploying via Helm chart..."
            # Try environment-specific values file first, fall back to defaults
            if [ -f "${HELM_DIR}/values-${ENVIRONMENT}.yaml" ]; then
                helm upgrade --install "${APP_NAME}" "$HELM_DIR" \
                    --namespace "${ENVIRONMENT}" \
                    --create-namespace \
                    -f "${HELM_DIR}/values-${ENVIRONMENT}.yaml" \
                    --wait --timeout 300s
            else
                helm upgrade --install "${APP_NAME}" "$HELM_DIR" \
                    --namespace "${ENVIRONMENT}" \
                    --create-namespace \
                    --wait --timeout 300s
            fi
            log_success "Helm deployment complete"
        fi

        # Wait for the deployment to roll out
        log_info "Waiting for deployment rollout to complete..."
        kubectl rollout status "deployment/${APP_NAME}" \
            -n "${ENVIRONMENT}" \
            --timeout=300s 2>/dev/null || \
            log_warn "Rollout status check timed out or deployment not found"

        log_success "Kubernetes deployment complete for ${ENVIRONMENT}"
    fi
else
    log_info "Skipping Kubernetes deployment (--skip-k8s)"
fi

#------------------------------------------------------------------------------
# Deployment summary
#------------------------------------------------------------------------------
log_header "Deployment Summary"

if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}This was a dry run. No changes were made.${NC}"
    echo ""
    echo -e "  Remove ${CYAN}--dry-run${NC} to execute the deployment."
else
    echo -e "  ${BOLD}Environment:${NC}  ${ENVIRONMENT}"
    echo -e "  ${BOLD}Status:${NC}       ${GREEN}Successfully Deployed${NC}"
    echo ""

    if [ "$SKIP_K8S" = false ]; then
        echo -e "${BOLD}Verify your deployment:${NC}"
        echo -e "  kubectl get pods -n ${ENVIRONMENT}"
        echo -e "  kubectl get svc -n ${ENVIRONMENT}"
        echo -e "  kubectl logs -f deployment/${APP_NAME} -n ${ENVIRONMENT}"
    fi
fi

echo ""
log_success "Done!"
