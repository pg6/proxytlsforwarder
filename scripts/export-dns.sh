#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"

usage() {
    echo "Usage: $0 <server-ip>"
    echo "  server-ip: The IP address of your redirect server"
    echo ""
    echo "Generates a CSV file with DNS A records needed for all domains."
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

SERVER_IP="$1"

# Basic IP validation
if ! [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format: $SERVER_IP" >&2
    exit 1
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "No domains configured yet."
    exit 0
fi

OUTPUT_FILE="$PROJECT_DIR/data/dns-records.csv"

{
    echo "domain,record_type,value"
    tail -n +2 "$CSV_FILE" | while IFS=, read -r domain target; do
        [[ -z "$domain" ]] && continue
        echo "${domain},A,${SERVER_IP}"
    done
} > "$OUTPUT_FILE"

echo "DNS records exported to: $OUTPUT_FILE"
echo ""
echo "Configure these A records with your DNS provider:"
echo "---"
cat "$OUTPUT_FILE"
