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

HETZNER_API_TOKEN="${HETZNER_API_TOKEN:-}"
BIND_IP="${BIND_IP:-}"
HETZNER_API="https://dns.hetzner.com/api/v1"

usage() {
    echo "Usage: $0 <domain> [domain2] [domain3] ..."
    echo ""
    echo "Creates DNS zones on Hetzner with A records for @ and * pointing to BIND_IP"
    echo ""
    echo "Environment variables (from .env):"
    echo "  HETZNER_API_TOKEN  - Required: Hetzner DNS API token"
    echo "  BIND_IP            - Required: IP address for A records"
    echo ""
    echo "Example:"
    echo "  $0 example.com example.org"
    exit 1
}

# Validate requirements
if [[ -z "$HETZNER_API_TOKEN" ]]; then
    echo "Error: HETZNER_API_TOKEN not set in environment" >&2
    exit 1
fi

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

if [[ $# -lt 1 ]]; then
    usage
fi

# Create a DNS zone
create_zone() {
    local domain="$1"

    echo "Creating zone for $domain..."

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$HETZNER_API/zones" \
        -H "Auth-API-Token: $HETZNER_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$domain\", \"ttl\": 3600}")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        local zone_id
        zone_id=$(echo "$body" | grep -o '"id":"[^"]*"' | head -n1 | cut -d'"' -f4)
        echo "  Zone created: $zone_id"
        echo "$zone_id"
        return 0
    elif [[ "$http_code" == "422" ]] && echo "$body" | grep -q "zone_exists"; then
        echo "  Zone already exists, fetching zone ID..."
        local zone_id
        zone_id=$(get_zone_id "$domain")
        if [[ -n "$zone_id" ]]; then
            echo "$zone_id"
            return 0
        fi
        return 1
    else
        echo "  Error creating zone: HTTP $http_code" >&2
        echo "  $body" >&2
        return 1
    fi
}

# Get zone ID by domain name
get_zone_id() {
    local domain="$1"

    local response
    response=$(curl -s "$HETZNER_API/zones?name=$domain" \
        -H "Auth-API-Token: $HETZNER_API_TOKEN")

    echo "$response" | grep -o '"id":"[^"]*"' | head -n1 | cut -d'"' -f4
}

# Create an A record
create_a_record() {
    local zone_id="$1"
    local name="$2"
    local ip="$3"

    local display_name="$name"
    [[ "$name" == "@" ]] && display_name="(root)"
    [[ "$name" == "*" ]] && display_name="(wildcard)"

    echo "  Creating A record: $display_name -> $ip"

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$HETZNER_API/records" \
        -H "Auth-API-Token: $HETZNER_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"zone_id\": \"$zone_id\", \"type\": \"A\", \"name\": \"$name\", \"value\": \"$ip\", \"ttl\": 3600}")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        echo "    Record created"
        return 0
    elif echo "$body" | grep -q "record_exists\|already exists"; then
        echo "    Record already exists"
        return 0
    else
        echo "    Error: HTTP $http_code" >&2
        echo "    $body" >&2
        return 1
    fi
}

# Process each domain
for domain in "$@"; do
    echo ""
    echo "=== Processing: $domain ==="

    # Basic domain validation
    if ! [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        echo "Error: Invalid domain format: $domain" >&2
        continue
    fi

    # Create zone and get zone ID
    zone_id=$(create_zone "$domain") || continue

    # Extract just the zone ID (last line of output)
    zone_id=$(echo "$zone_id" | tail -n1)

    if [[ -z "$zone_id" ]]; then
        echo "Error: Could not get zone ID for $domain" >&2
        continue
    fi

    # Create A records
    create_a_record "$zone_id" "@" "$BIND_IP" || true
    create_a_record "$zone_id" "*" "$BIND_IP" || true

    echo "  Done: $domain"
done

echo ""
echo "Finished processing all domains"
