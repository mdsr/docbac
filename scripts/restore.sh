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
    echo "Usage: $0 [volumes|compose-stacks] [backup_filename] [server_name]"
    echo ""
    echo "Examples:"
    echo "  $0 volumes                                    # List available volume backups for current server"
    echo "  $0 volumes \"\" server1                        # List available volume backups for server1"
    echo "  $0 compose-stacks                            # List available compose stack backups for current server"
    echo "  $0 volumes backup_volumes_server1_20231225_120000.tar.gz    # Restore specific volume backup"
    echo "  $0 volumes backup_volumes_server1_20231225_120000.tar.gz server1  # Restore from specific server"
    exit 1
}

# Function to list available backups
list_backups() {
    local backup_type=$1
    local server_name=${2:-${SERVER_NAME:-$(hostname)}}
    
    log "Available $backup_type backups for server: $server_name"
    local backup_path="${GDRIVE_BACKUP_PATH}/${server_name}/${backup_type}/"
    
    if ! rclone lsd "${GDRIVE_REMOTE_NAME}:${backup_path}" >/dev/null 2>&1; then
        log "No backup directory found for server: $server_name"
        log "Available servers:"
        rclone lsd "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/" | awk '{print $5}' | grep -v "^$" || echo "  No servers found"
        return 1
    fi
    
    rclone lsf "${GDRIVE_REMOTE_NAME}:${backup_path}" --format "tsp" | sort -k2 -nr || {
        log "No backups found for $backup_type on server: $server_name"
    }
}

# Function to restore volumes
restore_volumes() {
    local backup_file=$1
    local server_name=${2:-${SERVER_NAME:-$(hostname)}}
    local temp_dir="/tmp/restore_volumes"
    
    log "Restoring volumes from: $backup_file (server: $server_name)"
    
    # Download backup
    log "Downloading backup file..."
    local backup_path="${GDRIVE_BACKUP_PATH}/${server_name}/volumes/$backup_file"
    rclone copy "${GDRIVE_REMOTE_NAME}:${backup_path}" /tmp/
    
    # Extract backup
    log "Extracting backup..."
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    tar -xzf "/tmp/$backup_file" -C "$temp_dir"
    
    # Check for volume manifest
    local manifest_file="$temp_dir/volume_manifest.json"
    if [ -f "$manifest_file" ]; then
        log "Found volume manifest, using meaningful names for restoration"
        
        # Restore each volume using manifest information
        jq -r '.[] | "\(.meaningful_name)|\(.volume)|\(.project // "")|\(.containers // "")"' "$manifest_file" | while IFS='|' read -r meaningful_name original_volume project containers; do
            local volume_dir="$temp_dir/$meaningful_name"
            
            if [ -d "$volume_dir" ]; then
                log "Restoring volume: $meaningful_name -> $original_volume (Project: ${project:-none})"
                
                # Create volume if it doesn't exist
                docker volume create "$original_volume" >/dev/null 2>&1 || true
                
                # Copy data to volume
                docker run --rm \
                    -v "$original_volume":/target \
                    -v "$volume_dir":/source:ro \
                    alpine:3.18 \
                    sh -c "rm -rf /target/* /target/.* 2>/dev/null || true; cp -a /source/. /target/ 2>/dev/null || true"
                    
                log "Restored volume: $meaningful_name -> $original_volume"
            else
                log "WARNING: Volume directory not found: $meaningful_name"
            fi
        done
    else
        log "No volume manifest found, using directory names for restoration"
        
        # Restore each volume directory
        for volume_dir in "$temp_dir"/*; do
            if [ -d "$volume_dir" ]; then
                local volume_name=$(basename "$volume_dir")
                log "Restoring volume: $volume_name"
                
                # Create volume if it doesn't exist
                docker volume create "$volume_name" >/dev/null 2>&1 || true
                
                # Copy data to volume
                docker run --rm \
                    -v "$volume_name":/target \
                    -v "$volume_dir":/source:ro \
                    alpine:3.18 \
                    sh -c "rm -rf /target/* /target/.* 2>/dev/null || true; cp -a /source/. /target/ 2>/dev/null || true"
                    
                log "Restored volume: $volume_name"
            fi
        done
    fi
    
    # Cleanup
    rm -rf "$temp_dir" "/tmp/$backup_file"
    log "Volume restore completed"
}

# Function to restore compose stacks
restore_compose_stacks() {
    local backup_file=$1
    local server_name=${2:-${SERVER_NAME:-$(hostname)}}
    local restore_dir="/tmp/restore_compose"
    
    log "Restoring compose stacks from: $backup_file (server: $server_name)"
    log "WARNING: This will overwrite existing files in $COMPOSE_STACKS_DIR"
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled"
        exit 0
    fi
    
    # Download backup
    log "Downloading backup file..."
    local backup_path="${GDRIVE_BACKUP_PATH}/${server_name}/compose-stacks/$backup_file"
    rclone copy "${GDRIVE_REMOTE_NAME}:${backup_path}" /tmp/
    
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
} =~ ^[Yy]$ ]]; then
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
    local server_name=$3
    
    case $backup_type in
        "volumes")
            if [ -z "$backup_file" ]; then
                list_backups "volumes" "$server_name"
            else
                restore_volumes "$backup_file" "$server_name"
            fi
            ;;
        "compose-stacks")
            if [ -z "$backup_file" ]; then
                list_backups "compose-stacks" "$server_name"
            else
                restore_compose_stacks "$backup_file" "$server_name"
            fi
            ;;
        "servers")
            log "Available servers:"
            rclone lsd "${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH}/" | awk '{if($5!="") print "  - " $5}' || echo "  No servers found"
            ;;
        *)
            show_usage
            ;;
    esac
}

# Run main function
main "$@"