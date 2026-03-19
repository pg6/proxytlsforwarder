#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <analysis-csv-file>"
    echo ""
    echo "Pretty-prints the output of check-domain-status.sh with color coding."
    echo "Sorted by status (errors first), then alphabetically by domain."
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

INPUT_FILE="$1"
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: file not found: $INPUT_FILE" >&2
    exit 1
fi

# Colors — using bright variants for readability in both light and dark terminals
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# Status priority for sorting (lower = shown first)
status_priority() {
    case "$1" in
        CONF_INVALID)    echo "1" ;;
        CANT_RESOLVE_IP) echo "2" ;;
        CANT_REACH_HTTPD) echo "3" ;;
        MANUAL_CHECK)    echo "4" ;;
        HTTP_*)          echo "5" ;;
        SEDO)            echo "6" ;;
        REDIRECT)        echo "7" ;;
        STATIC)          echo "8" ;;
        CONF_VALID)      echo "9" ;;
        *)               echo "5" ;;
    esac
}

status_color() {
    case "$1" in
        CONF_VALID)      echo "$GREEN" ;;
        CONF_INVALID)    echo "$RED" ;;
        CANT_RESOLVE_IP) echo "$RED" ;;
        CANT_REACH_HTTPD) echo "$RED" ;;
        MANUAL_CHECK)    echo "$YELLOW" ;;
        REDIRECT)        echo "$BLUE" ;;
        STATIC)          echo "$MAGENTA" ;;
        SEDO)            echo "$YELLOW" ;;
        HTTP_*)          echo "$YELLOW" ;;
        *)               echo "$RESET" ;;
    esac
}

# Build sorted intermediate file, then display and count in one pass
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

# Skip header, build sortable lines: priority|status|domain|ip|notes
while IFS=',' read -r domain ip status notes; do
    [[ "$domain" == "domain" ]] && continue
    [[ -z "$domain" ]] && continue
    pri=$(status_priority "$status")
    echo "${pri}|${status}|${domain}|${ip}|${notes}"
done < "$INPUT_FILE" | sort -t'|' -k1,1n -k3,3 > "$TMPFILE"

# Display rows
total=0
while IFS='|' read -r _pri status domain ip notes; do
    color=$(status_color "$status")
    notes_str=""
    if [[ -n "$notes" ]]; then
        notes_str="${DIM} ${notes}${RESET}"
    fi
    printf "  ${color}%-16s${RESET} %-40s ${DIM}%-16s${RESET}%b\n" \
        "$status" "$domain" "$ip" "$notes_str"
    total=$((total + 1))
done < "$TMPFILE"

# Summary from the sorted file
echo ""
echo -e "${BOLD}Summary:${RESET} ${total} domains"
awk -F'|' '{print $2}' "$TMPFILE" | sort | uniq -c | sort -rn | while read -r count status; do
    color=$(status_color "$status")
    printf "  ${color}%-16s${RESET} %d\n" "$status" "$count"
done
