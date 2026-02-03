#!/bin/bash
set -euo pipefail

# Ensure UTF-8 locale for proper IDN handling
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

usage() {
    echo "Usage: $0 <domain-list-file>"
    echo "  domain-list-file: Text file with one domain per line"
    echo ""
    echo "Creates three CSV files in /data directory:"
    echo "  check_domains.csv  - Domains with forwarding (domain,target)"
    echo "  check_timeout.csv  - Domains that timeout (domain only)"
    echo "  check_addzones.csv - All domains to add DNS zones for (domain only)"
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

DOMAIN_FILE="$1"

if [[ ! -f "$DOMAIN_FILE" ]]; then
    echo "Error: File not found: $DOMAIN_FILE" >&2
    exit 1
fi

# Define output files in /data directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
CHECK_DOMAINS_CSV="$DATA_DIR/check_domains.csv"
CHECK_TIMEOUT_CSV="$DATA_DIR/check_timeout.csv"
CHECK_ADDZONES_CSV="$DATA_DIR/check_addzones.csv"

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Initialize/clear output files
> "$CHECK_DOMAINS_CSV"
> "$CHECK_TIMEOUT_CSV"
> "$CHECK_ADDZONES_CSV"

# Extract domain from URL
extract_domain() {
    local url="$1"
    # Remove protocol
    url="${url#http://}"
    url="${url#https://}"
    # Remove path and trailing slashes
    url="${url%%/*}"
    # Remove port if present
    url="${url%%:*}"
    echo "$url"
}

# Convert domain to Punycode (IDN) format
# e.g., münchen.de -> xn--mnchen-3ya.de
to_punycode() {
    local domain="$1"

    # Skip if already in Punycode format
    if [[ "$domain" =~ xn-- ]]; then
        echo "$domain"
        return 0
    fi

    # Skip if domain contains only ASCII characters
    if [[ "$domain" =~ ^[[:ascii:]]+$ ]]; then
        echo "$domain"
        return 0
    fi

    # Convert using idn2 with explicit UTF-8 handling
    if command -v idn2 &> /dev/null; then
        local result
        result=$(printf "%s" "$domain" | idn2 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "$result"
        else
            echo "$domain"
        fi
    elif command -v idn &> /dev/null; then
        local result
        result=$(printf "%s" "$domain" | idn 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "$result"
        else
            echo "$domain"
        fi
    else
        echo "$domain"
    fi
}

# Extract base domain (without subdomain)
# e.g., www.example.com -> example.com
#       sub.example.com -> example.com
#       example.com -> example.com
extract_base_domain() {
    local domain="$1"
    # Split by dots and take last two parts
    # This handles most common cases but not all TLDs (e.g., .co.uk)
    echo "$domain" | awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}'
}

# Check if domain redirects and extract target
check_domain() {
    local domain="$1"
    # Convert to Punycode if needed
    domain=$(to_punycode "$domain")
    local url="http://${domain}"

    # Use curl to follow redirects and get final URL and HTTP status
    # -L: follow redirects
    # -s: silent mode
    # -I: HEAD request only
    # -w: write out format
    # --max-time: timeout after 4 seconds
    # --max-redirs: follow max 10 redirects
    local response
    response=$(curl -L -s -I -o /dev/null -w '%{url_effective}|%{http_code}' --max-time 4 --max-redirs 10 "$url" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        # Could not connect or timeout
        echo "${domain}" >> "$CHECK_TIMEOUT_CSV"
        echo "${domain}" >> "$CHECK_ADDZONES_CSV"
        return 1
    fi

    # Split response into URL and HTTP code
    local final_url="${response%|*}"
    local http_code="${response##*|}"

    # Check if HTTP code indicates failure (000 = no response, 4xx/5xx = errors)
    if [[ "$http_code" == "000" ]]; then
        echo "${domain}" >> "$CHECK_TIMEOUT_CSV"
        echo "${domain}" >> "$CHECK_ADDZONES_CSV"
        return 1
    fi

    # Extract domains and convert to Punycode
    local original_domain
    local final_domain
    original_domain=$(to_punycode "$(extract_domain "$url")")
    final_domain=$(to_punycode "$(extract_domain "$final_url")")

    # Check if it's a redirect (domains are different)
    if [[ "$original_domain" != "$final_domain" ]]; then
        # Extract base domains to check if it's same-domain redirect
        local original_base
        local final_base
        original_base=$(extract_base_domain "$original_domain")
        final_base=$(extract_base_domain "$final_domain")

        # If base domains are the same (e.g., example.com -> www.example.com), dismiss silently
        if [[ "$original_base" == "$final_base" ]]; then
            return 1
        fi

        # It's a redirect to a different domain - write to CSV files
        echo "${original_domain},${final_domain}" >> "$CHECK_DOMAINS_CSV"
        echo "${original_domain}" >> "$CHECK_ADDZONES_CSV"
        return 0
    fi

    # Not a redirect - dismiss silently
    return 1
}

# Process each domain in the file
while IFS= read -r domain || [[ -n "$domain" ]]; do
    # Skip empty lines
    [[ -z "$domain" ]] && continue

    # Trim whitespace
    domain=$(echo "$domain" | xargs)

    # Skip empty lines after trimming
    [[ -z "$domain" ]] && continue

    # Skip comments
    [[ "$domain" =~ ^# ]] && continue

    # Check domain and output if it redirects
    check_domain "$domain" || true
done < "$DOMAIN_FILE"

# Output summary
echo "Results written to:"
echo "  Forwarding domains: $CHECK_DOMAINS_CSV ($(wc -l < "$CHECK_DOMAINS_CSV" | xargs) entries)"
echo "  Timeout domains:    $CHECK_TIMEOUT_CSV ($(wc -l < "$CHECK_TIMEOUT_CSV" | xargs) entries)"
echo "  Add DNS zones:      $CHECK_ADDZONES_CSV ($(wc -l < "$CHECK_ADDZONES_CSV" | xargs) entries)"
