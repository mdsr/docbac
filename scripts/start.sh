#!/bin/bash

set -e

# Set timezone
if [ -n "$TIMEZONE" ]; then
    cp /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    echo $TIMEZONE > /etc/timezone
fi

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /logs/backup.log
}

# Validate rclone configuration
if [ ! -f /root/.config/rclone/rclone.conf ]; then
    log "ERROR: rclone configuration not found. Please configure rclone first."
    log "Run: docker compose exec backup-service rclone config"
    exit 1
fi

# Test Google Drive connection
log "Testing Google Drive connection..."
if ! rclone lsd ${GDRIVE_REMOTE_NAME}: > /dev/null 2>&1; then
    log "ERROR: Cannot connect to Google Drive. Please check your rclone configuration."
    exit 1
fi
log "Google Drive connection successful"

# Ensure backup directory exists on Google Drive
rclone mkdir ${GDRIVE_REMOTE_NAME}:${GDRIVE_BACKUP_PATH} 2>/dev/null || true

# Setup cron job
log "Setting up backup schedule: $BACKUP_SCHEDULE"
echo "$BACKUP_SCHEDULE /scripts/backup.sh" > /tmp/crontab
crontab /tmp/crontab

# Start cron daemon
crond -f -d 8 &

# Keep container running and show logs
log "Backup service started. Schedule: $BACKUP_SCHEDULE"
log "Monitoring logs..."

# Follow the log file
tail -f /logs/backup.log