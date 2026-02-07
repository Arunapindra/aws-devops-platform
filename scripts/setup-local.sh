#!/usr/bin/env bash
###############################################################################
# setup-local.sh - Local Development Environment Setup
#
# Sets up a complete local Kubernetes development environment with:
#   - Minikube cluster with proper resource allocation
#   - ArgoCD installation and configuration
#   - Application deployment via Helm
#
# Usage:
#   ./scripts/setup-local.sh [--skip-minikube] [--skip-argocd] [--help]
#
# Prerequisites:
#   docker, kubectl, minikube, helm, terraform, argocd (CLI)
###############################################################################
set -euo pipefail

#------------------------------------------------------------------------------
# Color definitions for readable output
#------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#------------------------------------------------------------------------------
# Configuration (override via environment variables)
#------------------------------------------------------------------------------
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"
MINIKUBE_DISK="${MINIKUBE_DISK:-40g}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"
MINIKUBE_K8S_VERSION="${MINIKUBE_K8S_VERSION:-v1.29.2}"
ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="dev"
APP_NAME="aws-devops-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Feature flags
SKIP_MINIKUBE=false
SKIP_ARGOCD=false

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

usage() {
    echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-minikube    Skip Minikube cluster creation (use existing cluster)"
    echo "  --skip-argocd      Skip ArgoCD installation"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  MINIKUBE_CPUS       CPU count for Minikube (default: 4)"
    echo "  MINIKUBE_MEMORY     Memory in MB for Minikube (default: 8192)"
    echo "  MINIKUBE_DISK       Disk size for Minikube (default: 40g)"
    echo "  MINIKUBE_DRIVER     Minikube driver (default: docker)"
    echo "  MINIKUBE_K8S_VERSION  Kubernetes version (default: v1.29.2)"
    exit 0
}

#------------------------------------------------------------------------------
# Parse command-line arguments
#------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-minikube) SKIP_MINIKUBE=true; shift ;;
        --skip-argocd)   SKIP_ARGOCD=true; shift ;;
        --help|-h)       usage ;;
        *)               log_error "Unknown option: $1"; usage ;;
    esac
done

#------------------------------------------------------------------------------
# Step 1: Check all prerequisites are installed
#------------------------------------------------------------------------------
log_header "Checking Prerequisites"

REQUIRED_TOOLS=(docker kubectl minikube helm terraform argocd)
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        VERSION=$("$tool" version --short 2>/dev/null || "$tool" version 2>/dev/null | head -1 || echo "installed")
        log_success "${tool}: ${VERSION}"
    else
        log_error "${tool}: NOT FOUND"
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    log_error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Install on macOS with Homebrew:"
    echo "  brew install ${MISSING_TOOLS[*]}"
    echo ""
    echo "Or visit each tool's installation docs for your platform."
    exit 1
fi

# Check that Docker daemon is running
if ! docker info &>/dev/null; then
    log_error "Docker daemon is not running. Please start Docker Desktop."
    exit 1
fi
log_success "Docker daemon is running"

log_success "All prerequisites satisfied"

#------------------------------------------------------------------------------
# Step 2: Start Minikube cluster with proper resources
#------------------------------------------------------------------------------
if [ "$SKIP_MINIKUBE" = false ]; then
    log_header "Starting Minikube Cluster"

    # Check if Minikube is already running
    if minikube status &>/dev/null; then
        log_warn "Minikube is already running"
        read -rp "Delete and recreate? (y/N) " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            log_info "Deleting existing Minikube cluster..."
            minikube delete
        else
            log_info "Using existing Minikube cluster"
        fi
    fi

    # Start Minikube if not running
    if ! minikube status &>/dev/null; then
        log_info "Starting Minikube..."
        log_info "  CPUs:       ${MINIKUBE_CPUS}"
        log_info "  Memory:     ${MINIKUBE_MEMORY}MB"
        log_info "  Disk:       ${MINIKUBE_DISK}"
        log_info "  Driver:     ${MINIKUBE_DRIVER}"
        log_info "  Kubernetes: ${MINIKUBE_K8S_VERSION}"
        echo ""

        minikube start \
            --cpus="${MINIKUBE_CPUS}" \
            --memory="${MINIKUBE_MEMORY}" \
            --disk-size="${MINIKUBE_DISK}" \
            --driver="${MINIKUBE_DRIVER}" \
            --kubernetes-version="${MINIKUBE_K8S_VERSION}" \
            --addons=ingress,metrics-server,dashboard

        log_success "Minikube cluster started successfully"
    fi

    # Verify cluster is accessible
    log_info "Verifying cluster connectivity..."
    kubectl cluster-info
    kubectl get nodes
    log_success "Cluster is accessible"
else
    log_info "Skipping Minikube setup (--skip-minikube)"
fi

#------------------------------------------------------------------------------
# Step 3: Install ArgoCD in local cluster
#------------------------------------------------------------------------------
if [ "$SKIP_ARGOCD" = false ]; then
    log_header "Installing ArgoCD"

    # Create ArgoCD namespace
    kubectl create namespace "${ARGOCD_NAMESPACE}" 2>/dev/null || \
        log_info "Namespace '${ARGOCD_NAMESPACE}' already exists"

    # Install ArgoCD using the stable manifests
    log_info "Deploying ArgoCD to namespace '${ARGOCD_NAMESPACE}'..."
    kubectl apply -n "${ARGOCD_NAMESPACE}" \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Wait for all ArgoCD components to be ready
    log_info "Waiting for ArgoCD server to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=available deployment/argocd-server \
        -n "${ARGOCD_NAMESPACE}" --timeout=300s

    kubectl wait --for=condition=available deployment/argocd-repo-server \
        -n "${ARGOCD_NAMESPACE}" --timeout=300s

    # Retrieve the initial admin password
    ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "<not yet available>")

    log_success "ArgoCD installed successfully"
else
    log_info "Skipping ArgoCD installation (--skip-argocd)"
fi

#------------------------------------------------------------------------------
# Step 4: Deploy application using Helm
#------------------------------------------------------------------------------
log_header "Deploying Application"

# Create application namespace
kubectl create namespace "${APP_NAMESPACE}" 2>/dev/null || \
    log_info "Namespace '${APP_NAMESPACE}' already exists"

# Deploy using Helm chart if it exists
HELM_CHART="${PROJECT_ROOT}/helm-charts/app"
if [ -d "${HELM_CHART}" ] && [ -f "${HELM_CHART}/Chart.yaml" ]; then
    log_info "Installing Helm chart from ${HELM_CHART}..."
    helm upgrade --install "${APP_NAME}" "${HELM_CHART}" \
        --namespace "${APP_NAMESPACE}" \
        --set image.tag=latest \
        --set replicaCount=2 \
        --wait --timeout 300s
    log_success "Application deployed via Helm"
else
    log_warn "Helm chart not found at ${HELM_CHART}"
    log_warn "You can deploy manually later with:"
    log_warn "  helm upgrade --install ${APP_NAME} ${HELM_CHART} -n ${APP_NAMESPACE}"
fi

#------------------------------------------------------------------------------
# Step 5: Print access URLs and useful commands
#------------------------------------------------------------------------------
log_header "Setup Complete - Access Information"

echo -e "${BOLD}Cluster:${NC}"
echo -e "  Context:    $(kubectl config current-context)"
echo -e "  Nodes:      $(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
echo ""

echo -e "${BOLD}Kubernetes Dashboard:${NC}"
echo -e "  Run:        ${CYAN}minikube dashboard${NC}"
echo ""

if [ "$SKIP_ARGOCD" = false ]; then
    echo -e "${BOLD}ArgoCD:${NC}"
    echo -e "  Port-fwd:   ${CYAN}kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443${NC}"
    echo -e "  URL:        https://localhost:8080"
    echo -e "  Username:   admin"
    echo -e "  Password:   ${ARGOCD_PASSWORD:-<run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d>}"
    echo ""
fi

echo -e "${BOLD}Application:${NC}"
echo -e "  Namespace:  ${APP_NAMESPACE}"
echo -e "  Service:    ${CYAN}minikube service ${APP_NAME} -n ${APP_NAMESPACE}${NC}"
echo ""

echo -e "${BOLD}Useful Commands:${NC}"
echo -e "  kubectl get pods -n ${APP_NAMESPACE}          # List app pods"
echo -e "  kubectl logs -f deploy/${APP_NAME} -n ${APP_NAMESPACE}  # Stream logs"
echo -e "  kubectl get all -n ${ARGOCD_NAMESPACE}         # ArgoCD resources"
echo -e "  minikube dashboard                             # Open K8s dashboard"
echo -e "  minikube stop                                  # Stop cluster"
echo -e "  minikube delete                                # Delete cluster"
echo ""

log_success "Local development environment is ready!"
