#!/bin/bash

# CI/CD Framework Backup System
# Comprehensive backup solution for databases, configurations, and persistent data

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/cicd-backup.log"
CONFIG_FILE="${SCRIPT_DIR}/backup.conf"

# Default values
BACKUP_TYPE=""
BACKUP_DIR="/backup"
RETENTION_DAYS=30
COMPRESSION=true
ENCRYPTION=false
ENCRYPTION_KEY=""
NAMESPACE=""
DATABASE_TYPE=""
S3_BUCKET=""
NOTIFICATION_WEBHOOK=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
            echo -e "${BLUE}[DEBUG]${NC} $message"
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Error handling
error_exit() {
    log ERROR "$1"
    send_notification "FAILED" "$1"
    exit 1
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

CI/CD Framework Backup System

OPTIONS:
    -t, --type TYPE            Backup type (database|kubernetes|files|full)
    -d, --backup-dir DIR       Backup directory (default: /backup)
    -n, --namespace NS         Kubernetes namespace for k8s backups
    --database-type TYPE       Database type (postgres|mysql|redis)
    --retention-days DAYS      Retention period in days (default: 30)
    --no-compression          Disable compression
    --encrypt                 Enable encryption
    --encryption-key KEY      Encryption key file path
    --s3-bucket BUCKET        S3 bucket for remote backup
    --webhook URL             Notification webhook URL
    -h, --help                Show this help message

EXAMPLES:
    $0 -t database --database-type postgres -n production
    $0 -t kubernetes -n production --s3-bucket my-backups
    $0 -t full --encrypt --encryption-key /etc/backup.key

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -d|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --database-type)
                DATABASE_TYPE="$2"
                shift 2
                ;;
            --retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --no-compression)
                COMPRESSION=false
                shift
                ;;
            --encrypt)
                ENCRYPTION=true
                shift
                ;;
            --encryption-key)
                ENCRYPTION_KEY="$2"
                shift 2
                ;;
            --s3-bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            --webhook)
                NOTIFICATION_WEBHOOK="$2"
                shift 2
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

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log INFO "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log INFO "Validating prerequisites..."
    
    # Check backup directory
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log INFO "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Check required tools based on backup type
    case $BACKUP_TYPE in
        database)
            case $DATABASE_TYPE in
                postgres)
                    command -v pg_dump >/dev/null || error_exit "pg_dump not found"
                    ;;
                mysql)
                    command -v mysqldump >/dev/null || error_exit "mysqldump not found"
                    ;;
                redis)
                    command -v redis-cli >/dev/null || error_exit "redis-cli not found"
                    ;;
                *)
                    error_exit "Unsupported database type: $DATABASE_TYPE"
                    ;;
            esac
            ;;
        kubernetes)
            command -v kubectl >/dev/null || error_exit "kubectl not found"
            ;;
    esac
    
    # Check compression tools
    if [[ "$COMPRESSION" == "true" ]]; then
        command -v gzip >/dev/null || error_exit "gzip not found"
    fi
    
    # Check encryption tools
    if [[ "$ENCRYPTION" == "true" ]]; then
        command -v gpg >/dev/null || error_exit "gpg not found"
        if [[ -z "$ENCRYPTION_KEY" ]]; then
            error_exit "Encryption key must be specified when encryption is enabled"
        fi
    fi
    
    # Check S3 tools
    if [[ -n "$S3_BUCKET" ]]; then
        command -v aws >/dev/null || error_exit "aws cli not found"
    fi
}

# Database backup functions
backup_postgres() {
    local db_name="$1"
    local backup_file="$2"
    
    log INFO "Backing up PostgreSQL database: $db_name"
    
    # Get database connection info from Kubernetes secret
    local db_host=$(kubectl get secret postgres-credentials -n "$NAMESPACE" -o jsonpath='{.data.host}' | base64 -d)
    local db_user=$(kubectl get secret postgres-credentials -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 -d)
    local db_pass=$(kubectl get secret postgres-credentials -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
    
    PGPASSWORD="$db_pass" pg_dump -h "$db_host" -U "$db_user" -d "$db_name" \
        --verbose --clean --if-exists --create > "$backup_file"
    
    log INFO "PostgreSQL backup completed: $backup_file"
}

backup_mysql() {
    local db_name="$1"
    local backup_file="$2"
    
    log INFO "Backing up MySQL database: $db_name"
    
    # Get database connection info from Kubernetes secret
    local db_host=$(kubectl get secret mysql-credentials -n "$NAMESPACE" -o jsonpath='{.data.host}' | base64 -d)
    local db_user=$(kubectl get secret mysql-credentials -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 -d)
    local db_pass=$(kubectl get secret mysql-credentials -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
    
    mysqldump -h "$db_host" -u "$db_user" -p"$db_pass" \
        --single-transaction --routines --triggers "$db_name" > "$backup_file"
    
    log INFO "MySQL backup completed: $backup_file"
}

backup_redis() {
    local backup_file="$1"
    
    log INFO "Backing up Redis data"
    
    # Get Redis connection info
    local redis_host=$(kubectl get secret redis-credentials -n "$NAMESPACE" -o jsonpath='{.data.host}' | base64 -d)
    local redis_pass=$(kubectl get secret redis-credentials -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
    
    redis-cli -h "$redis_host" -a "$redis_pass" --rdb "$backup_file"
    
    log INFO "Redis backup completed: $backup_file"
}

# Kubernetes backup functions
backup_kubernetes() {
    local backup_dir="$1"
    
    log INFO "Backing up Kubernetes resources for namespace: $NAMESPACE"
    
    mkdir -p "$backup_dir/kubernetes"
    
    # Backup different resource types
    local resources=("deployments" "services" "configmaps" "secrets" "ingresses" "persistentvolumeclaims")
    
    for resource in "${resources[@]}"; do
        log INFO "Backing up $resource..."
        kubectl get "$resource" -n "$NAMESPACE" -o yaml > "$backup_dir/kubernetes/${resource}.yaml"
    done
    
    # Backup custom resources
    kubectl get crd -o name | while read crd; do
        local crd_name=$(echo "$crd" | cut -d'/' -f2)
        kubectl get "$crd_name" -n "$NAMESPACE" -o yaml > "$backup_dir/kubernetes/crd-${crd_name}.yaml" 2>/dev/null || true
    done
    
    log INFO "Kubernetes backup completed: $backup_dir/kubernetes"
}

# File system backup
backup_files() {
    local source_dir="$1"
    local backup_file="$2"
    
    log INFO "Backing up files from: $source_dir"
    
    if [[ "$COMPRESSION" == "true" ]]; then
        tar -czf "$backup_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
    else
        tar -cf "$backup_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")"
    fi
    
    log INFO "File backup completed: $backup_file"
}

# Encryption function
encrypt_file() {
    local file="$1"
    local encrypted_file="${file}.gpg"
    
    log INFO "Encrypting backup file: $file"
    
    gpg --cipher-algo AES256 --compress-algo 1 --symmetric \
        --passphrase-file "$ENCRYPTION_KEY" --output "$encrypted_file" "$file"
    
    # Remove unencrypted file
    rm "$file"
    
    echo "$encrypted_file"
}

# Upload to S3
upload_to_s3() {
    local file="$1"
    local s3_key="$2"
    
    log INFO "Uploading to S3: s3://$S3_BUCKET/$s3_key"
    
    aws s3 cp "$file" "s3://$S3_BUCKET/$s3_key" --storage-class STANDARD_IA
    
    log INFO "Upload completed: s3://$S3_BUCKET/$s3_key"
}

# Cleanup old backups
cleanup_old_backups() {
    log INFO "Cleaning up backups older than $RETENTION_DAYS days"
    
    # Local cleanup
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
    
    # S3 cleanup if configured
    if [[ -n "$S3_BUCKET" ]]; then
        local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d)
        aws s3api list-objects-v2 --bucket "$S3_BUCKET" --query "Contents[?LastModified<='$cutoff_date'].Key" --output text | \
        while read key; do
            if [[ -n "$key" ]]; then
                aws s3 rm "s3://$S3_BUCKET/$key"
                log INFO "Deleted old S3 backup: $key"
            fi
        done
    fi
}

# Send notification
send_notification() {
    local status="$1"
    local message="$2"
    
    if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
        local payload=$(cat <<EOF
{
    "text": "Backup $status",
    "attachments": [
        {
            "color": "$([[ "$status" == "SUCCESS" ]] && echo "good" || echo "danger")",
            "fields": [
                {"title": "Status", "value": "$status", "short": true},
                {"title": "Type", "value": "$BACKUP_TYPE", "short": true},
                {"title": "Namespace", "value": "$NAMESPACE", "short": true},
                {"title": "Message", "value": "$message", "short": false}
            ]
        }
    ]
}
EOF
        )
        
        curl -X POST -H 'Content-type: application/json' \
            --data "$payload" "$NOTIFICATION_WEBHOOK" || true
    fi
}

# Main backup function
perform_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="${BACKUP_TYPE}_${NAMESPACE}_${timestamp}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    case $BACKUP_TYPE in
        database)
            case $DATABASE_TYPE in
                postgres)
                    backup_postgres "appdb" "${backup_path}.sql"
                    ;;
                mysql)
                    backup_mysql "appdb" "${backup_path}.sql"
                    ;;
                redis)
                    backup_redis "${backup_path}.rdb"
                    ;;
            esac
            ;;
        kubernetes)
            backup_kubernetes "$backup_path"
            # Create archive
            if [[ "$COMPRESSION" == "true" ]]; then
                tar -czf "${backup_path}.tar.gz" -C "$BACKUP_DIR" "$(basename "$backup_path")"
                rm -rf "$backup_path"
                backup_path="${backup_path}.tar.gz"
            fi
            ;;
        files)
            backup_files "/app/data" "${backup_path}.tar.gz"
            ;;
        full)
            # Perform all backup types
            backup_kubernetes "${backup_path}/k8s"
            backup_postgres "appdb" "${backup_path}/postgres.sql"
            backup_redis "${backup_path}/redis.rdb"
            backup_files "/app/data" "${backup_path}/files.tar.gz"
            
            # Create final archive
            tar -czf "${backup_path}.tar.gz" -C "$BACKUP_DIR" "$(basename "$backup_path")"
            rm -rf "$backup_path"
            backup_path="${backup_path}.tar.gz"
            ;;
        *)
            error_exit "Unknown backup type: $BACKUP_TYPE"
            ;;
    esac
    
    # Encrypt if requested
    if [[ "$ENCRYPTION" == "true" ]]; then
        backup_path=$(encrypt_file "$backup_path")
    fi
    
    # Upload to S3 if configured
    if [[ -n "$S3_BUCKET" ]]; then
        local s3_key="cicd-backups/$(basename "$backup_path")"
        upload_to_s3 "$backup_path" "$s3_key"
    fi
    
    log INFO "Backup completed successfully: $backup_path"
    send_notification "SUCCESS" "Backup completed: $(basename "$backup_path")"
}

# Main function
main() {
    log INFO "Starting CI/CD backup process..."
    
    parse_args "$@"
    load_config
    validate_prerequisites
    
    if [[ -z "$BACKUP_TYPE" ]]; then
        error_exit "Backup type must be specified"
    fi
    
    perform_backup
    cleanup_old_backups
    
    log INFO "Backup process completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

