#!/bin/bash

# Architecture detection and verification script

echo "=== Architecture Information ==="
echo "Host architecture: $(uname -m)"
echo "Host kernel: $(uname -r)"
echo "Host OS: $(uname -s)"

if command -v docker >/dev/null 2>&1; then
    echo "Docker version: $(docker --version)"
    echo "Docker architecture: $(docker version --format '{{.Server.Arch}}' 2>/dev/null || echo 'N/A')"
fi

echo ""
echo "=== Container Architecture Check ==="
ARCH=$(uname -m)
case $ARCH in
    x86_64) 
        RCLONE_ARCH="amd64"
        echo "Detected x86_64 - will use amd64 rclone"
        ;;
    aarch64) 
        RCLONE_ARCH="arm64"
        echo "Detected aarch64 - will use arm64 rclone"
        ;;
    armv7l) 
        RCLONE_ARCH="arm"
        echo "Detected armv7l - will use arm rclone"
        ;;
    armv6l) 
        RCLONE_ARCH="arm"
        echo "Detected armv6l - will use arm rclone"
        ;;
    *) 
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Target rclone architecture: $RCLONE_ARCH"

echo ""
echo "=== Testing rclone binary ==="
if command -v rclone >/dev/null 2>&1; then
    echo "rclone is available"
    echo "rclone version: $(rclone version 2>/dev/null || echo 'Failed to get version')"
else
    echo "rclone is not available in PATH"
fi