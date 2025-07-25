#!/bin/bash

# Script to get detailed volume information including stack/project names

set -e

# Function to get volume information with stack/project context
get_volume_info() {
    local volume=$1
    local volume_info="{}"
    
    # Get basic volume info
    local volume_labels=$(docker volume inspect "$volume" --format '{{json .Labels}}' 2>/dev/null || echo '{}')
    local created=$(docker volume inspect "$volume" --format '{{.CreatedAt}}' 2>/dev/null || echo 'unknown')
    
    # Extract compose project and service info from labels
    local project_name=$(echo "$volume_labels" | jq -r '."com.docker.compose.project" // empty' 2>/dev/null || echo '')
    local service_name=$(echo "$volume_labels" | jq -r '."com.docker.compose.service" // empty' 2>/dev/null || echo '')
    local volume_name=$(echo "$volume_labels" | jq -r '."com.docker.compose.volume" // empty' 2>/dev/null || echo '')
    
    # Find containers using this volume
    local containers=$(docker ps -a --filter "volume=$volume" --format "{{.Names}}" 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo '')
    
    # Generate a meaningful name based on available information
    local meaningful_name=""
    if [ -n "$project_name" ] && [ -n "$volume_name" ]; then
        meaningful_name="${project_name}_${volume_name}"
    elif [ -n "$project_name" ] && [ -n "$service_name" ]; then
        meaningful_name="${project_name}_${service_name}"
    elif [ -n "$project_name" ]; then
        meaningful_name="${project_name}_volume"
    elif [ -n "$containers" ]; then
        # Use the first container name if available
        local first_container=$(echo "$containers" | cut -d',' -f1)
        meaningful_name="${first_container}_volume"
    else
        # Fallback to a shortened volume hash
        meaningful_name="vol_$(echo "$volume" | cut -c1-12)"
    fi
    
    # Create volume info JSON
    volume_info=$(jq -n \
        --arg volume "$volume" \
        --arg meaningful_name "$meaningful_name" \
        --arg project "$project_name" \
        --arg service "$service_name" \
        --arg volume_label "$volume_name" \
        --arg containers "$containers" \
        --arg created "$created" \
        --argjson labels "$volume_labels" \
        '{
            volume: $volume,
            meaningful_name: $meaningful_name,
            project: $project,
            service: $service,
            volume_label: $volume_label,
            containers: $containers,
            created: $created,
            labels: $labels
        }')
    
    echo "$volume_info"
}

# Function to get all volumes with their info
get_all_volumes_info() {
    local volumes=$(docker volume ls -q 2>/dev/null || echo '')
    local volumes_array="[]"
    
    if [ -n "$volumes" ]; then
        for volume in $volumes; do
            local volume_info=$(get_volume_info "$volume")
            volumes_array=$(echo "$volumes_array" | jq --argjson item "$volume_info" '. += [$item]')
        done
    fi
    
    echo "$volumes_array"
}

# Main function
main() {
    case "${1:-}" in
        "list")
            get_all_volumes_info | jq -r '.[] | "\(.meaningful_name) (\(.volume)) - Project: \(.project // "none") - Containers: \(.containers // "none")"'
            ;;
        "json")
            get_all_volumes_info
            ;;
        "volume")
            if [ -z "$2" ]; then
                echo "Usage: $0 volume <volume_name>"
                exit 1
            fi
            get_volume_info "$2"
            ;;
        *)
            echo "Usage: $0 {list|json|volume <name>}"
            echo "  list   - Human readable list of volumes"
            echo "  json   - JSON output of all volume information"
            echo "  volume - Get info for specific volume"
            exit 1
            ;;
    esac
}

main "$@"