#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"

if [[ ! -f "$CSV_FILE" ]]; then
    echo "No domains configured yet."
    exit 0
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q '^redirect-server$'; then
    echo "Warning: Container 'redirect-server' is not running. Cannot check certificate status."
    echo ""
fi

echo "Certificate Status"
echo "=================="
printf "%-40s %-15s %s\n" "DOMAIN" "STATUS" "EXPIRES"
echo "---"

tail -n +2 "$CSV_FILE" | while IFS=, read -r domain target; do
    [[ -z "$domain" ]] && continue

    # Try to get certificate info
    CERT_INFO=$(echo | timeout 5 openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "")

    if [[ -n "$CERT_INFO" ]]; then
        EXPIRY=$(echo "$CERT_INFO" | grep 'notAfter=' | cut -d= -f2)
        printf "%-40s %-15s %s\n" "$domain" "VALID" "$EXPIRY"
    else
        printf "%-40s %-15s %s\n" "$domain" "PENDING" "-"
    fi
done

echo ""
echo "Summary:"
TOTAL=$(tail -n +2 "$CSV_FILE" | grep -v '^$' | wc -l | xargs)
echo "  Total domains: $TOTAL"
