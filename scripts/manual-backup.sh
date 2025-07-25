#!/bin/bash

# Manual backup script for immediate execution
# This script can be run manually without waiting for the scheduled backup

set -e

LOG_FILE="/logs/manual-backup.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] MANUAL: $1" | tee -a $LOG_FILE
}

log "Starting manual backup..."

# Run the backup script
/scripts/backup.sh

log "Manual backup completed"