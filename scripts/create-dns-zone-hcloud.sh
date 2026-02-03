#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

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

BIND_IP="${BIND_IP:-}"

usage() {
    echo "Usage: $0 <domain>"
    echo ""
    echo "Creates DNS zone on Hetzner Cloud with A records for @ and * pointing to BIND_IP"
    echo ""
    echo "Environment variables (from .env):"
    echo "  BIND_IP  - Required: IP address for A records"
    echo ""
    echo "Example:"
    echo "  $0 example.com"
    exit 1
}

# Validate requirements
if [[ -z "$BIND_IP" ]]; then
    echo "Error: BIND_IP not set in environment" >&2
    exit 1
fi

# Validate BIND_IP is not 0.0.0.0
if [[ "$BIND_IP" == "0.0.0.0" ]]; then
    echo "Error: BIND_IP cannot be 0.0.0.0 for DNS records" >&2
    echo "Please set a specific IP address in your .env file" >&2
    exit 1
fi

if [[ $# -ne 1 ]]; then
    usage
fi

DOMAIN="$1"

# Basic domain validation
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN" >&2
    exit 1
fi

# Check if hcloud CLI is available
if ! command -v hcloud &> /dev/null; then
    echo "Error: hcloud CLI not found" >&2
    echo "Install from: https://github.com/hetznercloud/cli" >&2
    exit 1
fi

echo "Creating DNS zone for $DOMAIN with IP $BIND_IP..."

# Create zone
echo "Creating zone..."
hcloud zone create --name "$DOMAIN" || {
    echo "Warning: Zone may already exist, continuing..." >&2
}

# Create A records
echo "Creating A record for @ (root) -> $BIND_IP"
hcloud zone rrset create --type A --name "@" --record "$BIND_IP" "$DOMAIN" || {
    echo "Warning: Record may already exist" >&2
}

echo "Creating A record for * (wildcard) -> $BIND_IP"
hcloud zone rrset create --type A --name "*" --record "$BIND_IP" "$DOMAIN" || {
    echo "Warning: Record may already exist" >&2
}

echo "Done: $DOMAIN configured with A records pointing to $BIND_IP"
