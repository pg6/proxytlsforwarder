#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"

usage() {
    echo "Usage: $0 <domain>"
    echo "  domain: Domain to remove (e.g., oldsite.com)"
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

DOMAIN="$1"

if ! grep -q "^${DOMAIN}," "$CSV_FILE" 2>/dev/null; then
    echo "Error: Domain '$DOMAIN' not found in CSV" >&2
    exit 1
fi

# Create temp file and remove the domain
TEMP_FILE=$(mktemp)
grep -v "^${DOMAIN}," "$CSV_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$CSV_FILE"

echo "Removed: $DOMAIN"

# Regenerate config and reload
"$SCRIPT_DIR/generate-config.sh"
"$SCRIPT_DIR/reload.sh"
