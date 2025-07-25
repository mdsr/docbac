#!/bin/bash

set -e

# Configuration
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/backup"
VOLUMES_BACKUP_DIR="$BACKUP_DIR/volumes"
COMPOSE_BACKUP_DIR="$BACKUP_DIR/compose-stacks"
LOG_FILE="/logs/backup.log"

# Server identification - use SERVER_NAME if set, otherwise hostname
if [ -n "$SERVER_NAME" ]; then
    CURRENT_SERVER="$SERVER_NAME"
else
    CURRENT_SERVER=$(hostname)
fi

# Update Google Drive paths to include server name
GDRIVE_SERVER_PATH="${GDRIVE_BACKUP_PATH}/${CURRENT_SERVER}"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to create timestamped backup
create_backup() {
    local backup_type=$1
    local source_dir=$2
    local backup_name="${BACKUP_PREFIX}_${backup_type}_${CURRENT_SERVER}_${BACKUP_DATE}.tar.gz"
    local backup_path="/tmp/$backup_name"
    
    log "Creating $backup_type backup: $backup_name"
    
    if [ -d "$source_dir" ] && [ "$(ls -A $source_dir 2>/dev/null)" ]; then
        tar -czf "$backup_path" -C "$source_dir" .
        
        # Upload to Google Drive (server-specific path)
        log "Uploading $backup_name to Google Drive at ${GDRIVE_SERVER_PATH}/${backup_type}/"
        if rclone copy "$backup_path" "${GDRIVE_REMOTE_NAME}:${GDRIVE_SERVER_PATH}/${backup_type}/"; then
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
    log "Starting Docker volumes backup for server: $CURRENT_SERVER"
    
    # Stop graceful containers before volume backup
    log "Preparing containers for graceful backup..."
    if ! /scripts/graceful-backup.sh stop; then
        log "WARNING: Some containers failed graceful preparation, continuing with backup"
    fi
    
    # Clean up previous volume backups
    rm -rf "$VOLUMES_BACKUP_DIR"
    mkdir -p "$VOLUMES_BACKUP_DIR"
    
    # Get detailed volume information
    log "Gathering volume information..."
    local volumes_info=$(/scripts/get-volume-info.sh json)
    local volume_count=$(echo "$volumes_info" | jq length)
    
    if [ "$volume_count" -eq 0 ]; then
        log "No Docker volumes found"
        return 0
    fi
    
    log "Found $volume_count Docker volumes"
    
    # Create volume manifest
    echo "$volumes_info" > "$VOLUMES_BACKUP_DIR/volume_manifest.json"
    
    # Backup each volume with meaningful names
    echo "$volumes_info" | jq -r '.[] | "\(.volume)|\(.meaningful_name)|\(.project // "")|\(.containers // "")"' | while IFS='|' read -r volume meaningful_name project containers; do
        log "Backing up volume: $volume as $meaningful_name (Project: ${project:-none})"
        
        local volume_path="/var/lib/docker/volumes/$volume/_data"
        local backup_volume_path="$VOLUMES_BACKUP_DIR/$meaningful_name"
        
        if [ -d "$volume_path" ]; then
            mkdir -p "$backup_volume_path"
            if cp -a "$volume_path/." "$backup_volume_path/" 2>/dev/null; then
                log "Successfully backed up volume: $volume as $meaningful_name"
                
                # Create volume metadata file
                echo "$volumes_info" | jq --arg vol "$volume" '.[] | select(.volume == $vol)' > "$backup_volume_path/.volume_info.json"
            else
                log "WARNING: Could not backup volume $volume (may be in use)"
                continue
            fi
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
    if cp -a "$COMPOSE_STACKS_DIR/." "$COMPOSE_BACKUP_DIR/" 2>/dev/null; then
        log "Successfully copied compose stacks"
    else
        log "ERROR: Failed to copy compose stacks directory"
        return 1
    fi
    
    # Create compressed backup
    create_backup "compose-stacks" "$COMPOSE_BACKUP_DIR"
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups for server $CURRENT_SERVER (keeping last $MAX_BACKUPS)..."
    
    for backup_type in "volumes" "compose-stacks"; do
        log "Cleaning up old $backup_type backups..."
        
        # Check if directory exists on Google Drive first
        if ! rclone lsd "${GDRIVE_REMOTE_NAME}:${GDRIVE_SERVER_PATH}/${backup_type}/" >/dev/null 2>&1; then
            log "Backup directory for $backup_type does not exist yet, skipping cleanup"
            continue
        fi
        
        # List files, sort by modification time (newest first), skip the first MAX_BACKUPS, then delete the rest
        local files_to_delete=$(rclone lsf "${GDRIVE_REMOTE_NAME}:${GDRIVE_SERVER_PATH}/${backup_type}/" --format "tsp" 2>/dev/null | \
        sort -k2 -nr | \
        tail -n +$((MAX_BACKUPS + 1)) | \
        cut -d' ' -f3-)
        
        if [ -n "$files_to_delete" ]; then
            echo "$files_to_delete" | while IFS= read -r file; do
                if [ -n "$file" ]; then
                    log "Deleting old backup: $file"
                    rclone delete "${GDRIVE_REMOTE_NAME}:${GDRIVE_SERVER_PATH}/${backup_type}/$file" 2>/dev/null || {
                        log "WARNING: Failed to delete $file"
                    }
                fi
            done
        else
            log "No old backups to clean up for $backup_type"
        fi
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
    log "Starting backup process for server: $CURRENT_SERVER"
    log "========================================"
    
    local start_time=$(date +%s)
    local success=true
    
    # Create backup directories (ensure they're writable)
    mkdir -p "$VOLUMES_BACKUP_DIR" "$COMPOSE_BACKUP_DIR"
    
    # Make sure directories are writable
    chmod 755 "$VOLUMES_BACKUP_DIR" "$COMPOSE_BACKUP_DIR" 2>/dev/null || true
    
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
    
    # Clean up temporary directories (with better error handling)
    log "Cleaning up temporary directories..."
    if [ -d "$VOLUMES_BACKUP_DIR" ]; then
        rm -rf "$VOLUMES_BACKUP_DIR" 2>/dev/null || {
            log "WARNING: Could not remove volumes backup directory (may be read-only)"
        }
    fi
    
    if [ -d "$COMPOSE_BACKUP_DIR" ]; then
        rm -rf "$COMPOSE_BACKUP_DIR" 2>/dev/null || {
            log "WARNING: Could not remove compose backup directory (may be read-only)"
        }
    fi
    
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