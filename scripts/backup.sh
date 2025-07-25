#!/bin/bash

set -e

# Configuration
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backup"
VOLUMES_BACKUP_DIR="$BACKUP_DIR/volumes"
COMPOSE_BACKUP_DIR="$BACKUP_DIR/compose-stacks"
LOG_FILE="/logs/backup.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to create timestamped backup
create_backup() {
    local backup_type=$1
    local source_dir=$2
    local backup_name="${BACKUP_PREFIX}_${backup_type}_${BACKUP_DATE}.tar.gz"
    local backup_path="/tmp/$backup_name"
    
    log "Creating $backup_type backup: $backup_name"
    
    if [ -d "$source_dir" ] && [ "$(ls -A $source_dir 2>/dev/null)" ]; then
        tar -czf "$backup_path" -C "$source_dir" .
        
        # Upload to Google Drive
        log "Uploading $backup_name to Google Drive..."
        if rclone copy "$backup_path" "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/${backup_type}/"; then
            log "Successfully uploaded $backup_name"
            rm -f "$backup_path"
        else
            log "ERROR: Failed to upload $backup_name"
            rm -f "$backup_path"
            return 1
        fi
    else
        log "WARNING: No data found in $source_dir, skipping $backup_type backup"
    fi
}

# Function to discover and backup Docker volumes
backup_docker_volumes() {
    log "Starting Docker volumes backup..."
    
    # Stop graceful containers before volume backup
    log "Preparing containers for graceful backup..."
    if ! /scripts/graceful-backup.sh stop; then
        log "WARNING: Some containers failed graceful preparation, continuing with backup"
    fi
    
    # Clean up previous volume backups
    rm -rf "$VOLUMES_BACKUP_DIR"
    mkdir -p "$VOLUMES_BACKUP_DIR"
    
    # Get list of all Docker volumes
    volumes=$(docker volume ls -q)
    
    if [ -z "$volumes" ]; then
        log "No Docker volumes found"
        return 0
    fi
    
    log "Found Docker volumes: $(echo $volumes | tr '\n' ' ')"
    
    # Backup each volume
    for volume in $volumes; do
        log "Backing up Docker volume: $volume"
        volume_path="/var/lib/docker/volumes/$volume/_data"
        backup_volume_path="$VOLUMES_BACKUP_DIR/$volume"
        
        if [ -d "$volume_path" ]; then
            mkdir -p "$backup_volume_path"
            cp -a "$volume_path/." "$backup_volume_path/" 2>/dev/null || {
                log "WARNING: Could not backup volume $volume (may be in use)"
                continue
            }
            log "Successfully backed up volume: $volume"
        else
            log "WARNING: Volume path not found: $volume_path"
        fi
    done
    
    # Create compressed backup of all volumes
    create_backup "volumes" "$VOLUMES_BACKUP_DIR"
    
    # Start graceful containers after volume backup
    log "Restoring containers after graceful backup..."
    if ! /scripts/graceful-backup.sh start; then
        log "WARNING: Some containers failed to restart after backup"
    fi
}

# Function to backup compose stacks directory
backup_compose_stacks() {
    log "Starting compose stacks backup..."
    
    if [ ! -d "$COMPOSE_STACKS_DIR" ]; then
        log "WARNING: Compose stacks directory not found: $COMPOSE_STACKS_DIR"
        return 0
    fi
    
    # Clean up previous compose backups
    rm -rf "$COMPOSE_BACKUP_DIR"
    mkdir -p "$COMPOSE_BACKUP_DIR"
    
    # Copy compose stacks directory
    log "Copying compose stacks from: $COMPOSE_STACKS_DIR"
    cp -a "$COMPOSE_STACKS_DIR/." "$COMPOSE_BACKUP_DIR/"
    
    # Create compressed backup
    create_backup "compose-stacks" "$COMPOSE_BACKUP_DIR"
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (keeping last $MAX_BACKUPS)..."
    
    for backup_type in "volumes" "compose-stacks"; do
        log "Cleaning up old $backup_type backups..."
        
        # List files, sort by modification time (newest first), skip the first MAX_BACKUPS, then delete the rest
        rclone lsf "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/${backup_type}/" --format "tsp" | \
        sort -k2 -nr | \
        tail -n +$((MAX_BACKUPS + 1)) | \
        cut -d' ' -f3- | \
        while IFS= read -r file; do
            if [ -n "$file" ]; then
                log "Deleting old backup: $file"
                rclone delete "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/${backup_type}/$file"
            fi
        done
    done
}

# Function to send notification (optional)
send_notification() {
    local status=$1
    local message=$2
    
    # You can implement notification logic here (email, webhook, etc.)
    log "NOTIFICATION: $status - $message"
}

# Main backup process
main() {
    log "========================================"
    log "Starting backup process..."
    log "========================================"
    
    local start_time=$(date +%s)
    local success=true
    
    # Create backup directories
    mkdir -p "$VOLUMES_BACKUP_DIR" "$COMPOSE_BACKUP_DIR"
    
    # Backup Docker volumes
    if ! backup_docker_volumes; then
        log "ERROR: Docker volumes backup failed"
        success=false
    fi
    
    # Backup compose stacks
    if ! backup_compose_stacks; then
        log "ERROR: Compose stacks backup failed"
        success=false
    fi
    
    # Cleanup old backups
    if [ "$success" = true ]; then
        cleanup_old_backups
    fi
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Clean up temporary directories
    rm -rf "$VOLUMES_BACKUP_DIR" "$COMPOSE_BACKUP_DIR"
    
    if [ "$success" = true ]; then
        log "========================================"
        log "Backup completed successfully in ${duration} seconds"
        log "========================================"
        send_notification "SUCCESS" "Backup completed in ${duration} seconds"
    else
        log "========================================"
        log "Backup completed with errors in ${duration} seconds"
        log "========================================"
        send_notification "ERROR" "Backup completed with errors"
        exit 1
    fi
}

# Run main function
main "$@"