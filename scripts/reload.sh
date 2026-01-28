#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q '^redirect-server$'; then
    echo "Warning: Container 'redirect-server' is not running. Config generated but not reloaded."
    exit 0
fi

# Reload Caddy config (zero-downtime)
docker exec redirect-server caddy reload --config /etc/caddy/Caddyfile

echo "Caddy configuration reloaded successfully"
