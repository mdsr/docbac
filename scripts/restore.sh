#!/bin/bash

# Restore script for recovering backups from Google Drive

set -e

LOG_FILE="/logs/restore.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RESTORE: $1" | tee -a $LOG_FILE
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [volumes|compose-stacks] [backup_filename]"
    echo ""
    echo "Examples:"
    echo "  $0 volumes                    # List available volume backups"
    echo "  $0 compose-stacks            # List available compose stack backups"
    echo "  $0 volumes backup_volumes_20231225_120000.tar.gz    # Restore specific volume backup"
    echo "  $0 compose-stacks backup_compose-stacks_20231225_120000.tar.gz  # Restore specific compose backup"
    exit 1
}

# Function to list available backups
list_backups() {
    local backup_type=$1
    log "Available $backup_type backups:"
    rclone lsf "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/${backup_type}/" --format "tsp" | sort -k2 -nr
}

# Function to restore volumes
restore_volumes() {
    local backup_file=$1
    local temp_dir="/tmp/restore_volumes"
    
    log "Restoring volumes from: $backup_file"
    
    # Download backup
    log "Downloading backup file..."
    rclone copy "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/volumes/$backup_file" /tmp/
    
    # Extract backup
    log "Extracting backup..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    tar -xzf "/tmp/$backup_file" -C "$temp_dir"
    
    # Restore each volume
    for volume_dir in "$temp_dir"/*; do
        if [ -d "$volume_dir" ]; then
            volume_name=$(basename "$volume_dir")
            log "Restoring volume: $volume_name"
            
            # Create volume if it doesn't exist
            docker volume create "$volume_name" >/dev/null 2>&1 || true
            
            # Copy data to volume
            docker run --rm \
                -v "$volume_name":/target \
                -v "$volume_dir":/source:ro \
                alpine:3.18 \
                sh -c "rm -rf /target/* && cp -a /source/. /target/"
                
            log "Restored volume: $volume_name"
        fi
    done
    
    # Cleanup
    rm -rf "$temp_dir" "/tmp/$backup_file"
    log "Volume restore completed"
}

# Function to restore compose stacks
restore_compose_stacks() {
    local backup_file=$1
    local restore_dir="/tmp/restore_compose"
    
    log "Restoring compose stacks from: $backup_file"
    log "WARNING: This will overwrite existing files in $COMPOSE_STACKS_DIR"
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled"
        exit 0
    fi
    
    # Download backup
    log "Downloading backup file..."
    rclone copy "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/compose-stacks/$backup_file" /tmp/
    
    # Extract backup
    log "Extracting backup..."
    rm -rf "$restore_dir"
    mkdir -p "$restore_dir"
    tar -xzf "/tmp/$backup_file" -C "$restore_dir"
    
    # Restore files
    log "Restoring compose stacks to: $COMPOSE_STACKS_DIR"
    mkdir -p "$COMPOSE_STACKS_DIR"
    cp -a "$restore_dir/." "$COMPOSE_STACKS_DIR/"
    
    # Cleanup
    rm -rf "$restore_dir" "/tmp/$backup_file"
    log "Compose stacks restore completed"
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        show_usage
    fi
    
    local backup_type=$1
    local backup_file=$2
    
    case $backup_type in
        "volumes")
            if [ -z "$backup_file" ]; then
                list_backups "volumes"
            else
                restore_volumes "$backup_file"
            fi
            ;;
        "compose-stacks")
            if [ -z "$backup_file" ]; then
                list_backups "compose-stacks"
            else
                restore_compose_stacks "$backup_file"
            fi
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function
main "$@"