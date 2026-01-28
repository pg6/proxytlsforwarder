#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"

usage() {
    echo "Usage: $0 <domain> <target>"
    echo "  domain: Source domain (e.g., oldsite.com)"
    echo "  target: Destination domain (e.g., newsite.com)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

DOMAIN="$1"
TARGET="$2"

# Basic domain validation (alphanumeric, hyphens, dots)
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN" >&2
    exit 1
fi

if ! [[ "$TARGET" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid target format: $TARGET" >&2
    exit 1
fi

# Check for duplicates
if grep -q "^${DOMAIN}," "$CSV_FILE" 2>/dev/null; then
    echo "Error: Domain '$DOMAIN' already exists in CSV" >&2
    exit 1
fi

# Append to CSV
echo "${DOMAIN},${TARGET}" >> "$CSV_FILE"
echo "Added: $DOMAIN -> $TARGET"

# Regenerate config and reload
"$SCRIPT_DIR/generate-config.sh"
"$SCRIPT_DIR/reload.sh"
