#!/bin/bash

# CI/CD Framework Deployment Automation Script
# Comprehensive deployment script with rollback capabilities and health checks

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/cicd-deploy.log"
CONFIG_FILE="${SCRIPT_DIR}/deploy.conf"

# Default values
ENVIRONMENT=""
APPLICATION=""
VERSION=""
NAMESPACE=""
ROLLBACK_VERSION=""
DRY_RUN=false
VERBOSE=false
FORCE=false
TIMEOUT=600

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" >&2
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Error handling
error_exit() {
    log ERROR "$1"
    exit 1
}

# Cleanup function
cleanup() {
    log INFO "Cleaning up temporary files..."
    rm -f /tmp/deploy-*.tmp
}

# Trap for cleanup
trap cleanup EXIT

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

CI/CD Framework Deployment Script

OPTIONS:
    -e, --environment ENV       Target environment (dev/staging/prod)
    -a, --application APP       Application name
    -v, --version VERSION       Version to deploy
    -n, --namespace NAMESPACE   Kubernetes namespace
    -r, --rollback VERSION      Rollback to specific version
    -d, --dry-run              Perform dry run without actual deployment
    -f, --force                Force deployment without confirmations
    -t, --timeout SECONDS      Deployment timeout (default: 600)
    --verbose                  Enable verbose logging
    -h, --help                 Show this help message

EXAMPLES:
    $0 -e prod -a myapp -v 1.2.3 -n production
    $0 -e staging -a myapp -r 1.2.2
    $0 --dry-run -e dev -a myapp -v latest

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -a|--application)
                APPLICATION="$2"
                shift 2
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--rollback)
                ROLLBACK_VERSION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log INFO "Validating prerequisites..."
    
    # Check required tools
    local required_tools=("kubectl" "helm" "docker" "jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool '$tool' is not installed"
        fi
    done
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to Kubernetes cluster"
    fi
    
    # Validate parameters
    if [[ -z "$ENVIRONMENT" ]]; then
        error_exit "Environment must be specified"
    fi
    
    if [[ -z "$APPLICATION" ]]; then
        error_exit "Application must be specified"
    fi
    
    if [[ -z "$ROLLBACK_VERSION" && -z "$VERSION" ]]; then
        error_exit "Either version or rollback version must be specified"
    fi
    
    # Set default namespace if not provided
    if [[ -z "$NAMESPACE" ]]; then
        NAMESPACE="$APPLICATION-$ENVIRONMENT"
    fi
    
    log INFO "Prerequisites validated successfully"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log INFO "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log WARN "Configuration file not found: $CONFIG_FILE"
    fi
}

# Check deployment readiness
check_readiness() {
    log INFO "Checking deployment readiness..."
    
    # Check namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log INFO "Creating namespace: $NAMESPACE"
        if [[ "$DRY_RUN" == "false" ]]; then
            kubectl create namespace "$NAMESPACE"
        fi
    fi
    
    # Check if application is already deployed
    if kubectl get deployment "$APPLICATION" -n "$NAMESPACE" &> /dev/null; then
        local current_version
        current_version=$(kubectl get deployment "$APPLICATION" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.version}')
        log INFO "Current deployed version: $current_version"
        
        if [[ -z "$ROLLBACK_VERSION" && "$current_version" == "$VERSION" && "$FORCE" == "false" ]]; then
            log WARN "Version $VERSION is already deployed. Use --force to redeploy."
            exit 0
        fi
    fi
}

# Backup current deployment
backup_deployment() {
    log INFO "Creating backup of current deployment..."
    
    local backup_dir="/tmp/deployment-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    if kubectl get deployment "$APPLICATION" -n "$NAMESPACE" &> /dev/null; then
        kubectl get deployment "$APPLICATION" -n "$NAMESPACE" -o yaml > "$backup_dir/deployment.yaml"
        kubectl get service "$APPLICATION" -n "$NAMESPACE" -o yaml > "$backup_dir/service.yaml" 2>/dev/null || true
        kubectl get ingress "$APPLICATION" -n "$NAMESPACE" -o yaml > "$backup_dir/ingress.yaml" 2>/dev/null || true
        kubectl get configmap "$APPLICATION-config" -n "$NAMESPACE" -o yaml > "$backup_dir/configmap.yaml" 2>/dev/null || true
        
        log INFO "Backup created in: $backup_dir"
        echo "$backup_dir" > /tmp/last-backup-path
    fi
}

# Deploy application
deploy_application() {
    local deploy_version="$1"
    log INFO "Deploying $APPLICATION version $deploy_version to $ENVIRONMENT environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would deploy version $deploy_version"
        return 0
    fi
    
    # Update deployment image
    kubectl set image deployment/"$APPLICATION" \
        "$APPLICATION"="$REGISTRY/$APPLICATION:$deploy_version" \
        -n "$NAMESPACE"
    
    # Update version label
    kubectl patch deployment "$APPLICATION" -n "$NAMESPACE" \
        -p '{"metadata":{"labels":{"version":"'$deploy_version'"}}}'
    
    # Wait for rollout to complete
    log INFO "Waiting for deployment to complete (timeout: ${TIMEOUT}s)..."
    if ! kubectl rollout status deployment/"$APPLICATION" -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
        error_exit "Deployment failed or timed out"
    fi
    
    log INFO "Deployment completed successfully"
}

# Health check
health_check() {
    log INFO "Performing health checks..."
    
    # Wait for pods to be ready
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local ready_pods
        ready_pods=$(kubectl get pods -n "$NAMESPACE" -l app="$APPLICATION" --field-selector=status.phase=Running -o json | jq '.items | length')
        local total_pods
        total_pods=$(kubectl get deployment "$APPLICATION" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        
        if [[ "$ready_pods" -eq "$total_pods" ]]; then
            log INFO "All pods are ready ($ready_pods/$total_pods)"
            break
        fi
        
        log DEBUG "Waiting for pods to be ready ($ready_pods/$total_pods) - attempt $attempt/$max_attempts"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error_exit "Health check failed: Not all pods are ready"
    fi
    
    # Application-specific health check
    if [[ -n "${HEALTH_CHECK_URL:-}" ]]; then
        log INFO "Checking application health endpoint..."
        local health_url="$HEALTH_CHECK_URL"
        
        for i in {1..10}; do
            if curl -f -s "$health_url" > /dev/null; then
                log INFO "Application health check passed"
                return 0
            fi
            log DEBUG "Health check attempt $i failed, retrying..."
            sleep 5
        done
        
        error_exit "Application health check failed"
    fi
}

# Rollback deployment
rollback_deployment() {
    local rollback_to="$1"
    log INFO "Rolling back to version $rollback_to..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would rollback to version $rollback_to"
        return 0
    fi
    
    # Perform rollback
    kubectl set image deployment/"$APPLICATION" \
        "$APPLICATION"="$REGISTRY/$APPLICATION:$rollback_to" \
        -n "$NAMESPACE"
    
    # Update version label
    kubectl patch deployment "$APPLICATION" -n "$NAMESPACE" \
        -p '{"metadata":{"labels":{"version":"'$rollback_to'"}}}'
    
    # Wait for rollback to complete
    if ! kubectl rollout status deployment/"$APPLICATION" -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
        error_exit "Rollback failed or timed out"
    fi
    
    log INFO "Rollback completed successfully"
}

# Send notifications
send_notifications() {
    local status="$1"
    local version="$2"
    
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        local color="good"
        local message="Deployment successful"
        
        if [[ "$status" != "success" ]]; then
            color="danger"
            message="Deployment failed"
        fi
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"title\": \"$message\",
                    \"fields\": [
                        {\"title\": \"Application\", \"value\": \"$APPLICATION\", \"short\": true},
                        {\"title\": \"Environment\", \"value\": \"$ENVIRONMENT\", \"short\": true},
                        {\"title\": \"Version\", \"value\": \"$version\", \"short\": true},
                        {\"title\": \"Namespace\", \"value\": \"$NAMESPACE\", \"short\": true}
                    ]
                }]
            }" \
            "$SLACK_WEBHOOK_URL" || log WARN "Failed to send Slack notification"
    fi
}

# Main deployment function
main() {
    log INFO "Starting CI/CD deployment process..."
    
    parse_args "$@"
    load_config
    validate_prerequisites
    check_readiness
    
    if [[ -n "$ROLLBACK_VERSION" ]]; then
        # Rollback scenario
        backup_deployment
        rollback_deployment "$ROLLBACK_VERSION"
        health_check
        send_notifications "success" "$ROLLBACK_VERSION"
        log INFO "Rollback to version $ROLLBACK_VERSION completed successfully"
    else
        # Normal deployment scenario
        backup_deployment
        deploy_application "$VERSION"
        health_check
        send_notifications "success" "$VERSION"
        log INFO "Deployment of version $VERSION completed successfully"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

