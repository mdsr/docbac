# Docbac - Docker Backup Solution

A comprehensive Docker Compose solution for automatically backing up Docker volumes and compose stack directories to Google Drive using rclone.

## Features

- **Multi-Server Support**: Organizes backups by server/hostname with configurable server names
- **Intelligent Volume Naming**: Uses meaningful names based on Docker Compose project and service info
- **Automatic Discovery**: Discovers and backs up all Docker volumes on the host
- **Graceful Backup**: Supports stopping/starting containers during backup for data consistency
- **Compose Stacks Backup**: Backs up directories containing docker-compose.yaml files and related configurations
- **Scheduled Backups**: Configurable cron-based scheduling
- **Retention Management**: Configurable number of backups to retain per server
- **Google Drive Integration**: Uses rclone for reliable cloud storage
- **Volume Metadata**: Includes volume manifests with project/service information for easier restoration
- **Logging**: Comprehensive logging with configurable levels
- **Manual Backup**: Support for on-demand backups
- **Cross-Server Restore**: Scripts for restoring backups from any server

## Quick Start

### 1. Setup Directory Structure

```bash
mkdir docbac
cd docbac
mkdir -p scripts logs rclone-config examples
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
docker compose run --rm docbac-service rclone config
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
| `MAX_BACKUPS` | `7` | Number of backups to retain per server |
| `GDRIVE_REMOTE_NAME` | `gdrive` | Name of the rclone remote |
| `GDRIVE_BACKUP_PATH` | `/docker-backups` | Path on Google Drive for backups |
| `SERVER_NAME` | hostname | Server identifier for organizing backups |
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
docker compose logs -f docbac-service
```

### Manual Backup
```bash
docker compose exec docbac-service /scripts/manual-backup.sh
```

### List Available Backups
```bash
# List volume backups for current server
docker compose exec docbac-service /scripts/restore.sh volumes

# List volume backups for specific server
docker compose exec docbac-service /scripts/restore.sh volumes "" server1

# List compose stack backups
docker compose exec docbac-service /scripts/restore.sh compose-stacks

# List all available servers
docker compose exec docbac-service /scripts/restore.sh servers
```

### View Volume Information
```bash
# List volumes with meaningful names
docker compose exec docbac-service /scripts/get-volume-info.sh list

# Get detailed volume information in JSON
docker compose exec docbac-service /scripts/get-volume-info.sh json

# Get info for specific volume
docker compose exec docbac-service /scripts/get-volume-info.sh volume <volume_name>
```

### Restore from Backup
```bash
# Restore volumes from current server
docker compose exec docbac-service /scripts/restore.sh volumes backup_volumes_server1_20231225_120000.tar.gz

# Restore volumes from specific server
docker compose exec docbac-service /scripts/restore.sh volumes backup_volumes_server2_20231225_120000.tar.gz server2

# Restore compose stacks
docker compose exec docbac-service /scripts/restore.sh compose-stacks backup_compose-stacks_server1_20231225_120000.tar.gz
```

### Test rclone Connection
```bash
docker compose exec docbac-service rclone lsd gdrive:
```

### List Containers with Graceful Backup
```bash
docker compose exec docbac-service /scripts/graceful-backup.sh list
```

### Test Graceful Backup Process
```bash
# Stop graceful containers
docker compose exec docbac-service /scripts/graceful-backup.sh stop

# Start graceful containers
docker compose exec docbac-service /scripts/graceful-backup.sh start
```

### Check Architecture Compatibility
```bash
docker compose exec docbac-service /scripts/check-arch.sh
```

## Multi-Server Setup

Docbac is designed to handle backups from multiple servers efficiently:

### Server Organization

Backups are organized on Google Drive by server:
```
/docker-backups/
├── server1/
│   ├── volumes/
│   │   ├── backup_volumes_server1_20231225_120000.tar.gz
│   │   └── backup_volumes_server1_20231224_120000.tar.gz
│   └── compose-stacks/
│       └── backup_compose-stacks_server1_20231225_120000.tar.gz
├── server2/
│   ├── volumes/
│   │   └── backup_volumes_server2_20231225_120000.tar.gz
│   └── compose-stacks/
└── production-db/
    └── volumes/
        └── backup_volumes_production-db_20231225_120000.tar.gz
```

### Configuration for Multiple Servers

On each server, configure the `SERVER_NAME` in `.env`:

**Server 1 (.env):**
```bash
SERVER_NAME=webserver-01
COMPOSE_STACKS_DIR=/opt/docker-apps
```

**Server 2 (.env):**
```bash
SERVER_NAME=database-server
COMPOSE_STACKS_DIR=/home/admin/docker-stacks
```

**Production (.env):**
```bash
SERVER_NAME=production-cluster
COMPOSE_STACKS_DIR=/srv/docker
```

If `SERVER_NAME` is not set, the system hostname is used automatically.

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
├── server1/
│   ├── volumes/
│   │   ├── backup_volumes_server1_20231225_120000.tar.gz
│   │   └── backup_volumes_server1_20231224_120000.tar.gz
│   └── compose-stacks/
│       ├── backup_compose-stacks_server1_20231225_120000.tar.gz
│       └── backup_compose-stacks_server1_20231224_120000.tar.gz
└── server2/
    ├── volumes/
    └── compose-stacks/
```

Each volume backup contains:
- Organized directories with meaningful names (e.g., `myapp_database` instead of hash)
- `volume_manifest.json` with metadata for intelligent restoration
- Individual `.volume_info.json` files per volume with detailed metadata

## Local Directory Structure

```
docbac/
├── docker-compose.yml
├── Dockerfile
├── .env
├── scripts/
│   ├── start.sh
│   ├── backup.sh
│   ├── graceful-backup.sh
│   ├── get-volume-info.sh
│   ├── manual-backup.sh
│   ├── restore.sh
│   ├── validate-config.sh
│   └── check-arch.sh
├── examples/
│   └── docker-compose-with-graceful.yml
├── rclone-config/
│   └── rclone.conf
└── logs/
    ├── backup.log
    ├── manual-backup.log
    └── restore.log
```

## Troubleshooting

### Common Issues

1. **"exec format error" when running rclone**
   - This indicates architecture mismatch
   - Run: `docker compose exec docbac-service /scripts/check-arch.sh`
   - Rebuild the container: `docker compose build --no-cache`
   - The Dockerfile now auto-detects architecture (amd64, arm64, arm)

2. **"Read-only file system" errors during cleanup**
   - These are warnings and don't affect backup functionality
   - Caused by Docker volume mount restrictions
   - The backup will still complete successfully

3. **"Directory not found" errors during cleanup**
   - Occurs when no previous backups exist for that type
   - This is normal for first-time runs
   - Subsequent runs won't show this error

4. **Wrong compose stacks directory path**
   - Update `COMPOSE_STACKS_DIR` in `.env` to the correct path
   - Use absolute paths (e.g., `/home/user/docker-projects`)
   - Leave empty or comment out if you don't have compose stacks to backup

5. **rclone configuration not found**
   - Run the rclone config command as shown in setup
   - Ensure the config file is created in `./rclone-config/`

   - Run the rclone config command as shown in setup
   - Ensure the config file is created in `./rclone-config/`

   - Run the rclone config command as shown in setup
   - Ensure the config file is created in `./rclone-config/`

6. **Cannot connect to Google Drive**
   - Check your internet connection
   - Verify rclone configuration with `docker compose exec backup-service rclone lsd gdrive:`
   - Re-run rclone config if needed

   - Check your internet connection
   - Verify rclone configuration with `docker compose exec docbac-service rclone lsd gdrive:`
   - Re-run rclone config if needed

   - Check your internet connection
   - Verify rclone configuration with `docker compose exec docbac-service rclone lsd gdrive:`
   - Re-run rclone config if needed

7. **Permission denied accessing Docker volumes**
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
docker compose logs docbac-service
tail -f logs/backup.log
```

### Backup Verification

Verify backup contents:
```bash
# Download and inspect a backup
docker compose exec docbac-service rclone copy gdrive:/docker-backups/volumes/backup_volumes_20231225_120000.tar.gz /tmp/
docker compose exec docbac-service tar -tzf /tmp/backup_volumes_20231225_120000.tar.gz | head -20
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