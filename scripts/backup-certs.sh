#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CADDY_DATA="$PROJECT_DIR/caddy_data"
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_DIR/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="caddy_certs_${TIMESTAMP}.tar.gz"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -o, --output DIR    Output directory (default: ./backups)"
    echo "  -n, --name NAME     Backup filename (default: caddy_certs_TIMESTAMP.tar.gz)"
    echo "  -h, --help          Show this help"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -n|--name)
            BACKUP_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Check if caddy_data exists
if [[ ! -d "$CADDY_DATA" ]]; then
    echo "Error: Caddy data directory not found at $CADDY_DATA" >&2
    echo "Has Caddy been started and obtained certificates?" >&2
    exit 1
fi

# Check if certificates directory exists
CERTS_DIR="$CADDY_DATA/caddy/certificates"
if [[ ! -d "$CERTS_DIR" ]]; then
    echo "Error: No certificates found at $CERTS_DIR" >&2
    echo "Caddy may not have obtained any certificates yet." >&2
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
echo "Creating backup of certificates..."

tar -czf "$BACKUP_PATH" -C "$CADDY_DATA" caddy/certificates caddy/ocsp 2>/dev/null || \
tar -czf "$BACKUP_PATH" -C "$CADDY_DATA" caddy/certificates

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)

echo "Backup created: $BACKUP_PATH ($BACKUP_SIZE)"

# List what was backed up
echo ""
echo "Backed up certificates:"
tar -tzf "$BACKUP_PATH" | grep -E '\.crt$|\.key$' | sed 's/^/  /'

# Cleanup old backups (keep last 10)
if [[ -d "$BACKUP_DIR" ]]; then
    BACKUP_COUNT=$(find "$BACKUP_DIR" -name "caddy_certs_*.tar.gz" -type f | wc -l)
    if [[ "$BACKUP_COUNT" -gt 10 ]]; then
        echo ""
        echo "Cleaning up old backups (keeping last 10)..."
        find "$BACKUP_DIR" -name "caddy_certs_*.tar.gz" -type f | sort | head -n -10 | xargs rm -f
    fi
fi
