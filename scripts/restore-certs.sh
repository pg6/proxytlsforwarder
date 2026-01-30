#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CADDY_DATA="$PROJECT_DIR/caddy_data"
BACKUP_DIR="$PROJECT_DIR/backups"

usage() {
    echo "Usage: $0 [options] [backup_file]"
    echo ""
    echo "Arguments:"
    echo "  backup_file         Path to backup archive (default: latest in ./backups)"
    echo ""
    echo "Options:"
    echo "  -l, --list          List available backups"
    echo "  -f, --force         Overwrite existing certificates without prompting"
    echo "  -h, --help          Show this help"
    exit 0
}

list_backups() {
    echo "Available backups:"
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -name "caddy_certs_*.tar.gz" -type f | sort -r | while read -r backup; do
            local size
            size=$(du -h "$backup" | cut -f1)
            local date
            date=$(basename "$backup" | sed 's/caddy_certs_//' | sed 's/\.tar\.gz//' | sed 's/_/ /')
            echo "  $backup ($size) - $date"
        done
    else
        echo "  No backups found"
    fi
}

FORCE=false
LIST_ONLY=false
BACKUP_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

# List mode
if [[ "$LIST_ONLY" == "true" ]]; then
    list_backups
    exit 0
fi

# Find backup file
if [[ -z "$BACKUP_FILE" ]]; then
    # Use latest backup
    if [[ -d "$BACKUP_DIR" ]]; then
        BACKUP_FILE=$(find "$BACKUP_DIR" -name "caddy_certs_*.tar.gz" -type f | sort -r | head -n1)
    fi

    if [[ -z "$BACKUP_FILE" ]]; then
        echo "Error: No backup file specified and no backups found in $BACKUP_DIR" >&2
        echo "Run with --list to see available backups" >&2
        exit 1
    fi
    echo "Using latest backup: $BACKUP_FILE"
fi

# Verify backup file exists
if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Error: Backup file not found: $BACKUP_FILE" >&2
    exit 1
fi

# Check if certificates already exist
CERTS_DIR="$CADDY_DATA/caddy/certificates"
if [[ -d "$CERTS_DIR" ]] && [[ "$(ls -A "$CERTS_DIR" 2>/dev/null)" ]]; then
    if [[ "$FORCE" != "true" ]]; then
        echo "Warning: Existing certificates found at $CERTS_DIR"
        read -rp "Overwrite? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted"
            exit 1
        fi
    fi
fi

# Create caddy_data directory if needed
mkdir -p "$CADDY_DATA"

# Extract backup
echo "Restoring certificates from $BACKUP_FILE..."
tar -xzf "$BACKUP_FILE" -C "$CADDY_DATA"

echo "Certificates restored to $CADDY_DATA"

# List restored certificates
echo ""
echo "Restored certificates:"
find "$CERTS_DIR" -name "*.crt" 2>/dev/null | while read -r cert; do
    echo "  $(basename "$(dirname "$cert")")"
done

echo ""
echo "Restart Caddy to use the restored certificates:"
echo "  docker compose restart caddy"
