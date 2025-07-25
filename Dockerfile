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

# Install rclone
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cd rclone-*-linux-amd64 && \
    cp rclone /usr/bin/ && \
    chown root:root /usr/bin/rclone && \
    chmod 755 /usr/bin/rclone && \
    cd .. && \
    rm -rf rclone-*

# Create necessary directories
RUN mkdir -p /backup/volumes /backup/compose-stacks /logs /scripts

# Copy scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Set working directory
WORKDIR /backup

# Default command
CMD ["/scripts/start.sh"]