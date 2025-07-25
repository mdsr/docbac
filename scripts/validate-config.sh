#!/bin/bash

# Configuration validation script

set -e

LOG_FILE="/logs/validation.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] VALIDATE: $1" | tee -a $LOG_FILE
}

# Function to check if directory exists and is accessible
check_directory() {
    local dir_path=$1
    local dir_name=$2
    
    if [ -z "$dir_path" ]; then
        log "ERROR: $dir_name is not set"
        return 1
    fi
    
    if [ ! -d "$dir_path" ]; then
        log "ERROR: $dir_name directory does not exist: $dir_path"
        return 1
    fi
    
    if [ ! -r "$dir_path" ]; then
        log "ERROR: $dir_name directory is not readable: $dir_path"
        return 1
    fi
    
    log "✓ $dir_name directory is valid: $dir_path"
    return 0
}

# Function to validate rclone configuration
validate_rclone() {
    log "Validating rclone configuration..."
    
    if [ ! -f /root/.config/rclone/rclone.conf ]; then
        log "ERROR: rclone configuration file not found"
        log "Please run: docker compose run --rm docbac-service rclone config"
        return 1
    fi
    
    log "✓ rclone configuration file exists"
    
    # Test remote connection
    if ! rclone lsd "${GDRIVE_REMOTE_NAME}:" >/dev/null 2>&1; then
        log "ERROR: Cannot connect to Google Drive remote: ${GDRIVE_REMOTE_NAME}"
        log "Please check your rclone configuration"
        return 1
    fi
    
    log "✓ Google Drive connection successful"
    
    # Ensure backup directory exists
    rclone mkdir "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}" 2>/dev/null || true
    rclone mkdir "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/volumes" 2>/dev/null || true
    rclone mkdir "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/compose-stacks" 2>/dev/null || true
    
    log "✓ Google Drive backup directories created"
    return 0
}

# Function to validate Docker access
validate_docker() {
    log "Validating Docker access..."
    
    if ! docker ps >/dev/null 2>&1; then
        log "ERROR: Cannot access Docker daemon"
        log "Please ensure Docker socket is mounted: /var/run/docker.sock:/var/run/docker.sock:ro"
        return 1
    fi
    
    log "✓ Docker daemon access successful"
    
    # Check Docker volumes access
    if [ ! -d "/var/lib/docker/volumes" ]; then
        log "ERROR: Docker volumes directory not accessible"
        log "Please ensure volumes directory is mounted: /var/lib/docker/volumes:/var/lib/docker/volumes:ro"
        return 1
    fi
    
    log "✓ Docker volumes directory accessible"
    
    # List available volumes
    local volumes=$(docker volume ls -q 2>/dev/null || true)
    if [ -n "$volumes" ]; then
        log "✓ Found $(echo "$volumes" | wc -l) Docker volumes"
    else
        log "WARNING: No Docker volumes found on the system"
    fi
    
    return 0
}

# Function to validate graceful backup configuration
validate_graceful_backup() {
    log "Validating graceful backup configuration..."
    
    if [ "$ENABLE_GRACEFUL_BACKUP" != "true" ]; then
        log "INFO: Graceful backup is disabled"
        return 0
    fi
    
    local containers=$(docker ps --filter="label=${GRACEFUL_BACKUP_LABEL}=true" --format "{{.Names}}" 2>/dev/null || true)
    
    if [ -z "$containers" ]; then
        log "INFO: No containers found with graceful backup label: ${GRACEFUL_BACKUP_LABEL}=true"
    else
        log "✓ Found containers with graceful backup enabled: $(echo $containers | tr '\n' ' ')"
    fi
    
    return 0
}

# Function to validate environment variables
validate_environment() {
    log "Validating environment variables..."
    
    # Required variables
    local required_vars=(
        "GDRIVE_REMOTE_NAME"
        "GDRIVE_BACKUP_PATH"
        "BACKUP_PREFIX"
        "MAX_BACKUPS"
    )
    
    local missing_vars=""
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars="$missing_vars $var"
        fi
    done
    
    if [ -n "$missing_vars" ]; then
        log "ERROR: Missing required environment variables:$missing_vars"
        return 1
    fi
    
    log "✓ All required environment variables are set"
    
    # Validate MAX_BACKUPS is a number
    if ! [[ "$MAX_BACKUPS" =~ ^[0-9]+$ ]] || [ "$MAX_BACKUPS" -lt 1 ]; then
        log "ERROR: MAX_BACKUPS must be a positive integer, got: $MAX_BACKUPS"
        return 1
    fi
    
    log "✓ MAX_BACKUPS is valid: $MAX_BACKUPS"
    
    # Validate cron schedule format (basic check)
    if [ -n "$BACKUP_SCHEDULE" ]; then
        local cron_parts=$(echo "$BACKUP_SCHEDULE" | wc -w)
        if [ "$cron_parts" -ne 5 ]; then
            log "WARNING: BACKUP_SCHEDULE may not be valid cron format: $BACKUP_SCHEDULE"
        else
            log "✓ BACKUP_SCHEDULE format looks valid: $BACKUP_SCHEDULE"
        fi
    fi
    
    return 0
}

# Function to show configuration summary
show_configuration_summary() {
    log "=== Configuration Summary ==="
    log "Google Drive Remote: $GDRIVE_REMOTE_NAME"
    log "Backup Path: $GDRIVE_BACKUP_PATH"
    log "Compose Stacks Dir: $COMPOSE_STACKS_DIR"
    log "Max Backups: $MAX_BACKUPS"
    log "Backup Schedule: $BACKUP_SCHEDULE"
    log "Graceful Backup: $ENABLE_GRACEFUL_BACKUP"
    if [ "$ENABLE_GRACEFUL_BACKUP" = "true" ]; then
        log "Graceful Label: $GRACEFUL_BACKUP_LABEL"
        log "Graceful Timeout: $GRACEFUL_STOP_TIMEOUT"
    fi
    log "Log Level: $LOG_LEVEL"
    log "Timezone: $TIMEZONE"
    log "============================"
}

# Main validation function
main() {
    log "========================================"
    log "Starting configuration validation..."
    log "========================================"
    
    local validation_passed=true
    
    # Show configuration
    show_configuration_summary
    
    # Run validations
    if ! validate_environment; then
        validation_passed=false
    fi
    
    if ! validate_docker; then
        validation_passed=false
    fi
    
    if ! validate_rclone; then
        validation_passed=false
    fi
    
    # Optional validations
    validate_graceful_backup || true
    
    # Check compose stacks directory if set
    if [ -n "$COMPOSE_STACKS_DIR" ] && [ "$COMPOSE_STACKS_DIR" != "/opt/docker-stacks" ]; then
        check_directory "$COMPOSE_STACKS_DIR" "Compose stacks" || {
            log "WARNING: Compose stacks directory issues detected"
        }
    fi
    
    log "========================================"
    if [ "$validation_passed" = true ]; then
        log "✅ Configuration validation PASSED"
        log "Your backup system is ready to use!"
    else
        log "❌ Configuration validation FAILED"
        log "Please fix the errors above before running backups"
        exit 1
    fi
    log "========================================"
}

# Run main function
main "$@"