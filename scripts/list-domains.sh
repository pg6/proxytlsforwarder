#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"

usage() {
    echo "Usage: $0 [--target <filter>]"
    echo "  --target <filter>: Only show domains redirecting to this target"
    exit 1
}

TARGET_FILTER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            TARGET_FILTER="$2"
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

if [[ ! -f "$CSV_FILE" ]]; then
    echo "No domains configured yet."
    exit 0
fi

# Count domains
TOTAL=$(tail -n +2 "$CSV_FILE" | grep -v '^$' | wc -l | xargs)

echo "Configured domains: $TOTAL"
echo "---"
printf "%-40s %s\n" "DOMAIN" "TARGET"
echo "---"

tail -n +2 "$CSV_FILE" | while IFS=, read -r domain target; do
    [[ -z "$domain" ]] && continue

    if [[ -n "$TARGET_FILTER" ]]; then
        if [[ "$target" == "$TARGET_FILTER" ]]; then
            printf "%-40s %s\n" "$domain" "$target"
        fi
    else
        printf "%-40s %s\n" "$domain" "$target"
    fi
done
