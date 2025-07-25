#!/bin/bash

# Graceful backup management script
# Handles stopping and starting containers that require graceful backup

set -e

LOG_FILE="/logs/backup.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GRACEFUL: $1" | tee -a $LOG_FILE
}

# Function to get containers that need graceful backup
get_graceful_containers() {
    local label_filter="label=${GRACEFUL_BACKUP_LABEL}=true"
    docker ps --filter="$label_filter" --format "{{.Names}}" 2>/dev/null || true
}

# Function to get container info including compose project
get_container_info() {
    local container_name=$1
    docker inspect "$container_name" --format '{{json .}}' 2>/dev/null || echo "{}"
}

# Function to check if container is part of compose stack
is_compose_container() {
    local container_name=$1
    local info=$(get_container_info "$container_name")
    echo "$info" | jq -r '.Config.Labels["com.docker.compose.project"] // empty' 2>/dev/null
}

# Function to get compose service name
get_compose_service() {
    local container_name=$1
    local info=$(get_container_info "$container_name")
    echo "$info" | jq -r '.Config.Labels["com.docker.compose.service"] // empty' 2>/dev/null
}

# Function to get compose working directory
get_compose_working_dir() {
    local container_name=$1
    local info=$(get_container_info "$container_name")
    echo "$info" | jq -r '.Config.Labels["com.docker.compose.project.working_dir"] // empty' 2>/dev/null
}

# Function to get graceful backup configuration from container labels
get_graceful_config() {
    local container_name=$1
    local info=$(get_container_info "$container_name")
    
    # Get backup method (stop, pause, or custom command)
    local method=$(echo "$info" | jq -r '.Config.Labels["backup.graceful.method"] // "stop"' 2>/dev/null)
    
    # Get custom pre-backup command if specified
    local pre_cmd=$(echo "$info" | jq -r '.Config.Labels["backup.graceful.pre-command"] // empty' 2>/dev/null)
    
    # Get custom post-backup command if specified  
    local post_cmd=$(echo "$info" | jq -r '.Config.Labels["backup.graceful.post-command"] // empty' 2>/dev/null)
    
    # Get timeout override
    local timeout=$(echo "$info" | jq -r '.Config.Labels["backup.graceful.timeout"] // env.GRACEFUL_STOP_TIMEOUT' 2>/dev/null)
    if [ "$timeout" = "env.GRACEFUL_STOP_TIMEOUT" ]; then
        timeout=$GRACEFUL_STOP_TIMEOUT
    fi
    
    echo "$method|$pre_cmd|$post_cmd|$timeout"
}

# Function to execute pre-backup actions
execute_pre_backup() {
    local container_name=$1
    local config=$2
    
    local method=$(echo "$config" | cut -d'|' -f1)
    local pre_cmd=$(echo "$config" | cut -d'|' -f2)
    local timeout=$(echo "$config" | cut -d'|' -f4)
    
    log "Executing pre-backup for container: $container_name (method: $method)"
    
    # Execute custom pre-command if specified
    if [ -n "$pre_cmd" ] && [ "$pre_cmd" != "empty" ]; then
        log "Executing pre-backup command: $pre_cmd"
        if ! docker exec "$container_name" sh -c "$pre_cmd" 2>/dev/null; then
            log "WARNING: Pre-backup command failed for $container_name"
        fi
    fi
    
    case "$method" in
        "stop")
            log "Stopping container: $container_name"
            if ! docker stop --time="$timeout" "$container_name" 2>/dev/null; then
                log "ERROR: Failed to stop container $container_name"
                return 1
            fi
            ;;
        "pause")
            log "Pausing container: $container_name"
            if ! docker pause "$container_name" 2>/dev/null; then
                log "ERROR: Failed to pause container $container_name"
                return 1
            fi
            ;;
        "command")
            log "Using custom command method for: $container_name"
            # Custom commands are handled via pre_cmd above
            ;;
        *)
            log "WARNING: Unknown graceful backup method '$method' for $container_name, using stop"
            if ! docker stop --time="$timeout" "$container_name" 2>/dev/null; then
                log "ERROR: Failed to stop container $container_name"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Function to execute post-backup actions
execute_post_backup() {
    local container_name=$1
    local config=$2
    local was_running=$3
    
    local method=$(echo "$config" | cut -d'|' -f1)
    local post_cmd=$(echo "$config" | cut -d'|' -f3)
    
    log "Executing post-backup for container: $container_name"
    
    # Restore container state if it was running
    if [ "$was_running" = "true" ]; then
        case "$method" in
            "stop")
                log "Starting container: $container_name"
                if ! docker start "$container_name" 2>/dev/null; then
                    log "ERROR: Failed to start container $container_name"
                    return 1
                fi
                ;;
            "pause")
                log "Unpausing container: $container_name"
                if ! docker unpause "$container_name" 2>/dev/null; then
                    log "ERROR: Failed to unpause container $container_name"
                    return 1
                fi
                ;;
            "command")
                log "Container $container_name using custom command method, no automatic restart"
                ;;
        esac
    fi
    
    # Execute custom post-command if specified
    if [ -n "$post_cmd" ] && [ "$post_cmd" != "empty" ]; then
        log "Executing post-backup command: $post_cmd"
        # Wait a moment for container to be ready
        sleep 2
        if ! docker exec "$container_name" sh -c "$post_cmd" 2>/dev/null; then
            log "WARNING: Post-backup command failed for $container_name"
        fi
    fi
    
    return 0
}

# Function to check if container is running
is_container_running() {
    local container_name=$1
    local state=$(docker inspect "$container_name" --format '{{.State.Running}}' 2>/dev/null || echo "false")
    echo "$state"
}

# Function to handle compose stack graceful backup
handle_compose_stack() {
    local container_name=$1
    local config=$2
    local was_running=$3
    local action=$4  # "pre" or "post"
    
    local project=$(is_compose_container "$container_name")
    local service=$(get_compose_service "$container_name")
    local working_dir=$(get_compose_working_dir "$container_name")
    
    if [ -n "$project" ] && [ -n "$service" ]; then
        log "Handling compose stack - Project: $project, Service: $service"
        
        local compose_cmd="docker compose"
        if [ -n "$working_dir" ] && [ -d "$working_dir" ]; then
            compose_cmd="cd '$working_dir' && docker compose"
        fi
        
        if [ "$action" = "pre" ]; then
            case "$(echo "$config" | cut -d'|' -f1)" in
                "stop")
                    log "Stopping compose service: $project/$service"
                    eval "$compose_cmd stop $service" 2>/dev/null || {
                        log "WARNING: Failed to stop compose service, trying container stop"
                        return 1
                    }
                    ;;
            esac
        elif [ "$action" = "post" ] && [ "$was_running" = "true" ]; then
            case "$(echo "$config" | cut -d'|' -f1)" in
                "stop")
                    log "Starting compose service: $project/$service"
                    eval "$compose_cmd start $service" 2>/dev/null || {
                        log "WARNING: Failed to start compose service, trying container start"
                        return 1
                    }
                    ;;
            esac
        fi
        return 0
    fi
    return 1
}

# Main function to stop graceful containers
stop_graceful_containers() {
    if [ "$ENABLE_GRACEFUL_BACKUP" != "true" ]; then
        log "Graceful backup is disabled"
        return 0
    fi
    
    local containers=$(get_graceful_containers)
    
    if [ -z "$containers" ]; then
        log "No containers found with graceful backup label: $GRACEFUL_BACKUP_LABEL=true"
        return 0
    fi
    
    log "Found containers requiring graceful backup: $(echo $containers | tr '\n' ' ')"
    
    # Store container states and configs
    > /tmp/graceful_containers_state
    
    local failed_containers=""
    
    for container in $containers; do
        if ! docker inspect "$container" >/dev/null 2>&1; then
            log "WARNING: Container $container not found, skipping"
            continue
        fi
        
        local was_running=$(is_container_running "$container")
        local config=$(get_graceful_config "$container")
        
        # Store state for restoration
        echo "$container|$config|$was_running" >> /tmp/graceful_containers_state
        
        log "Processing container: $container (running: $was_running)"
        
        # Try compose stack handling first, then fallback to direct container handling
        if ! handle_compose_stack "$container" "$config" "$was_running" "pre"; then
            if ! execute_pre_backup "$container" "$config"; then
                failed_containers="$failed_containers $container"
                log "ERROR: Failed to prepare container $container for backup"
            fi
        fi
    done
    
    if [ -n "$failed_containers" ]; then
        log "WARNING: Some containers failed graceful preparation:$failed_containers"
        return 1
    fi
    
    log "All graceful containers prepared for backup"
    return 0
}

# Main function to start graceful containers
start_graceful_containers() {
    if [ "$ENABLE_GRACEFUL_BACKUP" != "true" ]; then
        return 0
    fi
    
    if [ ! -f /tmp/graceful_containers_state ]; then
        log "No graceful containers state file found"
        return 0
    fi
    
    local failed_containers=""
    
    while IFS='|' read -r container config was_running; do
        if [ -z "$container" ]; then
            continue
        fi
        
        log "Restoring container: $container (was_running: $was_running)"
        
        # Try compose stack handling first, then fallback to direct container handling
        if ! handle_compose_stack "$container" "$config" "$was_running" "post"; then
            if ! execute_post_backup "$container" "$config" "$was_running"; then
                failed_containers="$failed_containers $container"
                log "ERROR: Failed to restore container $container after backup"
            fi
        fi
    done < /tmp/graceful_containers_state
    
    # Cleanup state file
    rm -f /tmp/graceful_containers_state
    
    if [ -n "$failed_containers" ]; then
        log "WARNING: Some containers failed restoration:$failed_containers"
        return 1
    fi
    
    log "All graceful containers restored"
    return 0
}

# Handle command line arguments
case "${1:-}" in
    "stop")
        stop_graceful_containers
        ;;
    "start")
        start_graceful_containers
        ;;
    "list")
        containers=$(get_graceful_containers)
        if [ -n "$containers" ]; then
            log "Containers with graceful backup enabled:"
            for container in $containers; do
                config=$(get_graceful_config "$container")
                running=$(is_container_running "$container")
                method=$(echo "$config" | cut -d'|' -f1)
                log "  - $container (method: $method, running: $running)"
            done
        else
            log "No containers found with graceful backup label: $GRACEFUL_BACKUP_LABEL=true"
        fi
        ;;
    *)
        echo "Usage: $0 {stop|start|list}"
        echo "  stop  - Prepare containers for backup"
        echo "  start - Restore containers after backup"
        echo "  list  - List containers with graceful backup enabled"
        exit 1
        ;;
esac