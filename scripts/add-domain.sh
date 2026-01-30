#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"

# Load environment variables
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
elif [[ -f "$PROJECT_DIR/.env.prod" ]]; then
    set -a
    source "$PROJECT_DIR/.env.prod"
    set +a
fi

BIND_IP="${BIND_IP:-0.0.0.0}"
SKIP_DNS_CHECK="${SKIP_DNS_CHECK:-false}"

usage() {
    echo "Usage: $0 [options] <domain> <target>"
    echo "  domain: Source domain (e.g., oldsite.com)"
    echo "  target: Destination domain (e.g., newsite.com)"
    echo ""
    echo "Options:"
    echo "  --skip-dns    Skip DNS verification"
    exit 1
}

# Get the expected IP address for DNS verification
get_expected_ip() {
    local bind_ip="$1"

    # If BIND_IP is 0.0.0.0, try to determine public IP
    if [[ "$bind_ip" == "0.0.0.0" ]]; then
        # Try multiple services in case one is down
        local public_ip
        public_ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) ||
        public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) ||
        public_ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null) ||
        public_ip=""

        if [[ -z "$public_ip" ]]; then
            echo "Warning: Could not determine public IP" >&2
            return 1
        fi
        echo "$public_ip"
    else
        echo "$bind_ip"
    fi
}

# Verify DNS resolution for a domain
verify_dns() {
    local domain="$1"
    local expected_ip="$2"

    # Resolve domain A record
    local resolved_ip
    resolved_ip=$(dig +short A "$domain" 2>/dev/null | head -n1)

    if [[ -z "$resolved_ip" ]]; then
        echo "Error: Domain '$domain' does not resolve to any IP address" >&2
        return 1
    fi

    if [[ "$resolved_ip" != "$expected_ip" ]]; then
        echo "Error: Domain '$domain' resolves to $resolved_ip, expected $expected_ip" >&2
        echo "Hint: Update your DNS records or use --skip-dns to bypass this check" >&2
        return 1
    fi

    echo "DNS verified: $domain -> $resolved_ip"
    return 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-dns)
            SKIP_DNS_CHECK="true"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

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

# DNS verification
if [[ "$SKIP_DNS_CHECK" != "true" ]]; then
    expected_ip=$(get_expected_ip "$BIND_IP") || {
        echo "Warning: Skipping DNS verification (could not determine expected IP)" >&2
    }

    if [[ -n "${expected_ip:-}" ]]; then
        verify_dns "$DOMAIN" "$expected_ip" || exit 1
    fi
fi

# Append to CSV
echo "${DOMAIN},${TARGET}" >> "$CSV_FILE"
echo "Added: $DOMAIN -> $TARGET"

# Regenerate config and reload
"$SCRIPT_DIR/generate-config.sh"
"$SCRIPT_DIR/reload.sh"
