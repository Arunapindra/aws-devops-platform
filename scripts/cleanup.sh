#!/usr/bin/env bash
###############################################################################
# cleanup.sh - Resource Cleanup Script
#
# Destroys and cleans up all resources created by the aws-devops-platform
# project. Handles Terraform infrastructure teardown, Minikube cluster
# deletion, and Docker image cleanup.
#
# Usage:
#   ./scripts/cleanup.sh [OPTIONS]
#
# Options:
#   --all           Clean everything (Terraform + Minikube + Docker)
#   --terraform     Destroy Terraform resources only
#   --minikube      Delete Minikube cluster only
#   --docker        Clean Docker images only
#   --force         Skip all confirmation prompts
#   --help, -h      Show this help message
#
# Examples:
#   ./scripts/cleanup.sh --all
#   ./scripts/cleanup.sh --minikube --docker
#   ./scripts/cleanup.sh --all --force
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
APP_NAME="aws-devops-platform"

# Flags
CLEAN_TERRAFORM=false
CLEAN_MINIKUBE=false
CLEAN_DOCKER=false
FORCE=false

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
    echo -e "${BOLD}Options:${NC}"
    echo "  --all           Clean everything (Terraform + Minikube + Docker)"
    echo "  --terraform     Destroy Terraform resources only"
    echo "  --minikube      Delete Minikube cluster only"
    echo "  --docker        Clean Docker images only"
    echo "  --force         Skip all confirmation prompts"
    echo "  --help, -h      Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 --all                # Clean everything with prompts"
    echo "  $0 --minikube --docker  # Clean only Minikube and Docker"
    echo "  $0 --all --force        # Clean everything without prompts"
    exit 0
}

# Prompt for confirmation unless --force is set
# Returns 0 if confirmed, 1 if declined
confirm() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    local message="$1"
    read -rp "$(echo -e "${YELLOW}${message} (y/N): ${NC}")" answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

#------------------------------------------------------------------------------
# Parse arguments
#------------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    log_error "At least one option is required"
    echo ""
    usage
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)       CLEAN_TERRAFORM=true; CLEAN_MINIKUBE=true; CLEAN_DOCKER=true; shift ;;
        --terraform) CLEAN_TERRAFORM=true; shift ;;
        --minikube)  CLEAN_MINIKUBE=true; shift ;;
        --docker)    CLEAN_DOCKER=true; shift ;;
        --force)     FORCE=true; shift ;;
        --help|-h)   usage ;;
        *)           log_error "Unknown option: $1"; usage ;;
    esac
done

#------------------------------------------------------------------------------
# Display cleanup plan
#------------------------------------------------------------------------------
log_header "Cleanup Plan"

echo -e "  ${BOLD}Terraform:${NC}  $([ "$CLEAN_TERRAFORM" = true ] && echo "${RED}DESTROY${NC}" || echo "Skip")"
echo -e "  ${BOLD}Minikube:${NC}   $([ "$CLEAN_MINIKUBE" = true ] && echo "${RED}DELETE${NC}" || echo "Skip")"
echo -e "  ${BOLD}Docker:${NC}     $([ "$CLEAN_DOCKER" = true ] && echo "${RED}CLEAN${NC}" || echo "Skip")"
echo ""

echo -e "${RED}${BOLD}WARNING: This action is DESTRUCTIVE and cannot be undone!${NC}"
echo ""

if ! confirm "Proceed with cleanup?"; then
    log_info "Cleanup cancelled"
    exit 0
fi

#------------------------------------------------------------------------------
# Step 1: Destroy Terraform resources (reverse order: prod -> staging -> dev)
#------------------------------------------------------------------------------
if [ "$CLEAN_TERRAFORM" = true ]; then
    log_header "Destroying Terraform Resources"

    for env in prod staging dev; do
        TF_DIR="${PROJECT_ROOT}/terraform/environments/${env}"

        if [ ! -d "$TF_DIR" ]; then
            log_warn "Terraform directory not found for '${env}', skipping..."
            continue
        fi

        if confirm "Destroy Terraform resources for '${env}'?"; then
            log_info "Destroying ${env} environment..."
            cd "$TF_DIR"

            # Initialize Terraform (needed to access the state)
            terraform init 2>/dev/null || {
                log_warn "Terraform init failed for ${env}. State may not be configured."
                continue
            }

            # Destroy all resources
            terraform destroy -auto-approve 2>/dev/null || {
                log_warn "Terraform destroy encountered errors for ${env}"
                log_warn "Some resources may need manual cleanup"
            }

            log_success "Terraform resources destroyed for ${env}"
        else
            log_info "Skipping ${env}"
        fi
    done

    # Clean up Terraform local files
    log_info "Cleaning Terraform cache and state files..."
    find "${PROJECT_ROOT}/terraform" -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    find "${PROJECT_ROOT}/terraform" -name "*.tfstate" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}/terraform" -name "*.tfstate.backup" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}/terraform" -name ".terraform.lock.hcl" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}/terraform" -name "tfplan" -delete 2>/dev/null || true
    log_success "Terraform cache files cleaned"
fi

#------------------------------------------------------------------------------
# Step 2: Delete Minikube cluster
#------------------------------------------------------------------------------
if [ "$CLEAN_MINIKUBE" = true ]; then
    log_header "Deleting Minikube Cluster"

    if ! command -v minikube &>/dev/null; then
        log_warn "minikube command not found, skipping..."
    elif minikube status &>/dev/null; then
        log_info "Stopping and deleting Minikube cluster..."
        minikube delete --all --purge
        log_success "Minikube cluster deleted and purged"
    else
        log_info "Minikube is not currently running"
        # Still try to clean up any leftover profiles
        minikube delete --all --purge 2>/dev/null || true
        log_success "Minikube cleanup complete"
    fi
fi

#------------------------------------------------------------------------------
# Step 3: Clean Docker images and build cache
#------------------------------------------------------------------------------
if [ "$CLEAN_DOCKER" = true ]; then
    log_header "Cleaning Docker Images"

    if ! command -v docker &>/dev/null; then
        log_warn "docker command not found, skipping..."
    elif ! docker info &>/dev/null; then
        log_warn "Docker daemon is not running, skipping..."
    else
        # Remove project-specific images
        log_info "Removing ${APP_NAME} Docker images..."
        IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | \
            grep -E "${APP_NAME}|aws-devops" || true)

        if [ -n "$IMAGES" ]; then
            echo "$IMAGES" | xargs docker rmi -f 2>/dev/null || true
            log_success "Project images removed"
        else
            log_info "No project-specific images found"
        fi

        # Remove dangling (untagged) images
        log_info "Removing dangling images..."
        docker image prune -f 2>/dev/null || true

        # Optionally remove build cache
        if confirm "Remove Docker build cache? (frees disk space)"; then
            log_info "Removing Docker build cache..."
            docker builder prune -f 2>/dev/null || true
            log_success "Docker build cache removed"
        fi

        log_success "Docker cleanup complete"
    fi
fi

#------------------------------------------------------------------------------
# Cleanup summary
#------------------------------------------------------------------------------
log_header "Cleanup Summary"

echo -e "  ${BOLD}Terraform:${NC}  $([ "$CLEAN_TERRAFORM" = true ] && echo "${GREEN}Destroyed${NC}" || echo "Skipped")"
echo -e "  ${BOLD}Minikube:${NC}   $([ "$CLEAN_MINIKUBE" = true ] && echo "${GREEN}Deleted${NC}" || echo "Skipped")"
echo -e "  ${BOLD}Docker:${NC}     $([ "$CLEAN_DOCKER" = true ] && echo "${GREEN}Cleaned${NC}" || echo "Skipped")"
echo ""

log_success "Cleanup complete!"
