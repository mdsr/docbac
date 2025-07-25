FROM alpine:3.18

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    tar \
    gzip \
    jq \
    coreutils \
    dcron \
    tzdata \
    ca-certificates

# Install rclone with architecture detection
RUN ARCH=$(uname -m) && \
    case $ARCH in \
        x86_64) RCLONE_ARCH="amd64" ;; \
        aarch64) RCLONE_ARCH="arm64" ;; \
        armv7l) RCLONE_ARCH="arm" ;; \
        armv6l) RCLONE_ARCH="arm" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    echo "Detected architecture: $ARCH, downloading rclone for: $RCLONE_ARCH" && \
    curl -O https://downloads.rclone.org/rclone-current-linux-${RCLONE_ARCH}.zip && \
    unzip rclone-current-linux-${RCLONE_ARCH}.zip && \
    cd rclone-*-linux-${RCLONE_ARCH} && \
    cp rclone /usr/bin/ && \
    chown root:root /usr/bin/rclone && \
    chmod 755 /usr/bin/rclone && \
    cd .. && \
    rm -rf rclone-* && \
    rclone version

# Create necessary directories
RUN mkdir -p /backup/volumes /backup/compose-stacks /logs /scripts

# Copy scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Set working directory
WORKDIR /backup

# Default command
CMD ["/scripts/start.sh"]