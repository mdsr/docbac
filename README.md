# Docker Backup Solution

A comprehensive Docker Compose solution for automatically backing up Docker volumes and compose stack directories to Google Drive using rclone.

## Features

- **Automatic Discovery**: Discovers and backs up all Docker volumes on the host
- **Graceful Backup**: Supports stopping/starting containers during backup for data consistency
- **Compose Stacks Backup**: Backs up directories containing docker-compose.yaml files and related configurations
- **Scheduled Backups**: Configurable cron-based scheduling
- **Retention Management**: Configurable number of backups to retain
- **Google Drive Integration**: Uses rclone for reliable cloud storage
- **Logging**: Comprehensive logging with configurable levels
- **Manual Backup**: Support for on-demand backups
- **Restore Functionality**: Scripts for restoring backups when needed

## Quick Start

### 1. Setup Directory Structure

```bash
mkdir docker-backup-solution
cd docker-backup-solution
mkdir -p scripts logs rclone-config
```

### 2. Create Configuration Files

Copy all the provided files to their respective locations:
- `docker-compose.yml` (main directory)
- `Dockerfile` (main directory)  
- `.env` (main directory)
- `scripts/start.sh`
- `scripts/backup.sh`
- `scripts/manual-backup.sh`
- `scripts/restore.sh`

### 3. Configure rclone for Google Drive

First, build the container:
```bash
docker compose build
```

Configure rclone interactively:
```bash
docker compose run --rm backup-service rclone config
```

Follow these steps:
1. Choose `n` for new remote
2. Name it `gdrive` (or update the `GDRIVE_REMOTE_NAME` in `.env`)
3. Choose Google Drive (type `drive`)
4. Leave client_id and client_secret blank (press Enter)
5. Choose full access scope (`1`)
6. Leave root_folder_id blank
7. Leave service_account_file blank
8. Choose `n` for advanced config
9. Choose `y` for auto config
10. Complete the browser authentication
11. Choose `n` for team drive
12. Confirm with `y`
13. Choose `q` to quit

### 4. Configure Containers for Graceful Backup (Optional)

Add labels to containers that need graceful backup in their docker-compose.yml:

```yaml
services:
  database:
    image: postgres:15
    labels:
      # Enable graceful backup
      - "backup.graceful=true"
      # Method: stop (default), pause, or command
      - "backup.graceful.method=stop"
      # Optional: custom timeout
      - "backup.graceful.timeout=60"
    volumes:
      - db_data:/var/lib/postgresql/data
```

See `examples/docker-compose-with-graceful.yml` for more examples.

### 5. Update Configuration

Edit the `.env` file to match your setup:

```env
# Required: Update this path to your docker compose stacks directory
COMPOSE_STACKS_DIR=/path/to/your/docker-stacks

# Optional: Customize other settings
BACKUP_SCHEDULE=0 2 * * *  # Daily at 2 AM
MAX_BACKUPS=7
GDRIVE_BACKUP_PATH=/docker-backups
TIMEZONE=America/New_York
```

### 6. Start the Backup Service

```bash
docker compose up -d
```

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_SCHEDULE` | `0 2 * * *` | Cron schedule for automatic backups |
| `MAX_BACKUPS` | `7` | Number of backups to retain |
| `GDRIVE_REMOTE_NAME` | `gdrive` | Name of the rclone remote |
| `GDRIVE_BACKUP_PATH` | `/docker-backups` | Path on Google Drive for backups |
| `COMPOSE_STACKS_DIR` | `/opt/docker-stacks` | Local directory containing compose stacks |
| `BACKUP_PREFIX` | `backup` | Prefix for backup filenames |
| `TIMEZONE` | `UTC` | Timezone for scheduling and logs |
| `LOG_LEVEL` | `INFO` | Logging level (DEBUG, INFO, WARN, ERROR) |
| `GRACEFUL_BACKUP_LABEL` | `backup.graceful` | Label to identify containers needing graceful backup |
| `GRACEFUL_STOP_TIMEOUT` | `30` | Timeout in seconds for graceful container stops |
| `ENABLE_GRACEFUL_BACKUP` | `true` | Enable/disable graceful backup feature |

### Cron Schedule Examples

- Daily at 2 AM: `0 2 * * *`
- Every 6 hours: `0 */6 * * *`
- Weekly on Sunday at 3 AM: `0 3 * * 0`
- Every 15 minutes: `*/15 * * * *`

## Usage

### Monitor Logs
```bash
docker compose logs -f backup-service
```

### Manual Backup
```bash
docker compose exec backup-service /scripts/manual-backup.sh
```

### List Available Backups
```bash
# List volume backups
docker compose exec backup-service /scripts/restore.sh volumes

# List compose stack backups
docker compose exec backup-service /scripts/restore.sh compose-stacks
```

### Restore from Backup
```bash
# Restore volumes
docker compose exec backup-service /scripts/restore.sh volumes backup_volumes_20231225_120000.tar.gz

# Restore compose stacks
docker compose exec backup-service /scripts/restore.sh compose-stacks backup_compose-stacks_20231225_120000.tar.gz
```

### Test rclone Connection
```bash
docker compose exec backup-service rclone lsd gdrive:
```

### List Containers with Graceful Backup
```bash
docker compose exec backup-service /scripts/graceful-backup.sh list
```

### Test Graceful Backup Process
```bash
# Stop graceful containers
docker compose exec backup-service /scripts/graceful-backup.sh stop

# Start graceful containers
docker compose exec backup-service /scripts/graceful-backup.sh start
```

## Graceful Backup Configuration

The solution supports graceful backup for containers that require consistent data states. Configure containers using Docker labels:

### Basic Configuration

```yaml
services:
  myservice:
    image: myapp:latest
    labels:
      - "backup.graceful=true"  # Enable graceful backup
    volumes:
      - mydata:/app/data
```

### Advanced Configuration

```yaml
services:
  database:
    image: postgres:15
    labels:
      # Enable graceful backup
      - "backup.graceful=true"
      
      # Backup method: stop (default), pause, or command
      - "backup.graceful.method=stop"
      
      # Custom timeout for stopping (seconds)
      - "backup.graceful.timeout=60"
      
      # Custom pre-backup command (executed before stopping)
      - "backup.graceful.pre-command=pg_dump mydb > /backup/dump.sql"
      
      # Custom post-backup command (executed after starting)
      - "backup.graceful.post-command=echo 'Backup completed' >> /var/log/backup.log"
```

### Graceful Backup Methods

1. **stop** (default): Stops the container completely before backup
2. **pause**: Pauses the container (faster, keeps in memory)
3. **command**: Uses custom commands only, no automatic stop/start

### Examples by Service Type

**Database Services:**
```yaml
postgres:
  labels:
    - "backup.graceful=true"
    - "backup.graceful.method=stop"
    - "backup.graceful.timeout=60"
```

**Cache Services:**
```yaml
redis:
  labels:
    - "backup.graceful=true"
    - "backup.graceful.method=pause"  # Faster for cache services
```

**Application Services:**
```yaml
webapp:
  labels:
    - "backup.graceful=true"
    - "backup.graceful.method=command"
    - "backup.graceful.pre-command=curl -X POST http://localhost/api/flush"
```

## File Structure

The solution creates the following structure on Google Drive:

```
/docker-backups/
├── volumes/
│   ├── backup_volumes_20231225_120000.tar.gz
│   ├── backup_volumes_20231224_120000.tar.gz
│   └── ...
└── compose-stacks/
    ├── backup_compose-stacks_20231225_120000.tar.gz
    ├── backup_compose-stacks_20231224_120000.tar.gz
    └── ...
```

## Local Directory Structure

```
docker-backup-solution/
├── docker-compose.yml
├── Dockerfile
├── .env
├── scripts/
│   ├── start.sh
│   ├── backup.sh
│   ├── graceful-backup.sh
│   ├── manual-backup.sh
│   └── restore.sh
├── rclone-config/
│   └── rclone.conf
└── logs/
    ├── backup.log
    ├── manual-backup.log
    └── restore.log
```

## Troubleshooting

### Common Issues

1. **rclone configuration not found**
   - Run the rclone config command as shown in setup
   - Ensure the config file is created in `./rclone-config/`

2. **Cannot connect to Google Drive**
   - Check your internet connection
   - Verify rclone configuration with `docker compose exec backup-service rclone lsd gdrive:`
   - Re-run rclone config if needed

3. **Permission denied accessing Docker volumes**
   - Ensure the container has access to `/var/run/docker.sock`
   - Check that `/var/lib/docker/volumes` is properly mounted

4. **Compose stacks directory not found**
   - Update `COMPOSE_STACKS_DIR` in `.env` to the correct path
   - Ensure the directory exists and is accessible

### Debugging

Enable debug logging:
```bash
# Add to .env
LOG_LEVEL=DEBUG
```

Check logs:
```bash
docker compose logs backup-service
tail -f logs/backup.log
```

### Backup Verification

Verify backup contents:
```bash
# Download and inspect a backup
docker compose exec backup-service rclone copy gdrive:/docker-backups/volumes/backup_volumes_20231225_120000.tar.gz /tmp/
docker compose exec backup-service tar -tzf /tmp/backup_volumes_20231225_120000.tar.gz | head -20
```

## Security Considerations

- The container requires access to the Docker socket for volume discovery
- rclone configuration contains Google Drive credentials - keep the config directory secure
- Consider using a dedicated Google account for backups
- Regularly rotate Google Drive API credentials

## Contributing

Feel free to customize the scripts for your specific needs:
- Add notification integrations (email, Slack, etc.)
- Implement different cloud storage backends
- Add backup encryption
- Extend logging and monitoring