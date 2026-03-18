#!/bin/bash
set -euo pipefail

BIND_IP="65.108.24.25"
CURL_TIMEOUT=10

usage() {
    echo "Usage: $0 <domain-csv-file>"
    echo ""
    echo "Analyzes domains from a semicolon-separated CSV (first column = domain)."
    echo "Skips the header row. Writes results to <input>_analysis.csv"
    echo ""
    echo "Output columns: domain,resolved_ip,status,notes"
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

# Derive output filename
BASENAME="${INPUT_FILE%.*}"
OUTPUT_FILE="${BASENAME}_analysis.csv"

echo "domain,resolved_ip,status,notes" > "$OUTPUT_FILE"

resolve_ip() {
    local domain="$1"
    dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' | tail -1
}

# Check HTTP response: returns "REDIRECT|<url>" or "STATIC" or error string
check_http() {
    local url="$1"
    local response
    response=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' \
        --max-time "$CURL_TIMEOUT" --connect-timeout "$CURL_TIMEOUT" \
        -H "User-Agent: Mozilla/5.0" \
        "$url" 2>/dev/null) || {
        echo "CANT_REACH_HTTPD"
        return
    }

    local code redirect_url
    code=$(echo "$response" | awk '{print $1}')
    redirect_url=$(echo "$response" | awk '{print $2}')

    case "$code" in
        301|302|303|307|308)
            echo "REDIRECT|${redirect_url}"
            ;;
        200)
            echo "STATIC"
            ;;
        000)
            echo "CANT_REACH_HTTPD"
            ;;
        *)
            echo "HTTP_${code}"
            ;;
    esac
}

check_cert() {
    local domain="$1"
    local result
    result=$(echo | openssl s_client -servername "$domain" -connect "${BIND_IP}:443" \
        -verify_return_error 2>/dev/null) || {
        echo "CONF_INVALID"
        return
    }

    if echo "$result" | grep -q "Verify return code: 0"; then
        echo "CONF_VALID"
    else
        echo "CONF_INVALID"
    fi
}

# Normalize a redirect URL for comparison: strip scheme, trailing slash, www prefix
normalize_url() {
    local url="$1"
    url="${url#http://}"
    url="${url#https://}"
    url="${url#www.}"
    url="${url%/}"
    echo "$url"
}

# Check if a redirect target is just the same domain with/without www or scheme change
is_self_redirect() {
    local domain="$1"
    local redirect_url="$2"
    local norm_redirect
    norm_redirect=$(normalize_url "$redirect_url")
    local norm_bare
    norm_bare=$(normalize_url "$domain")
    local norm_www
    norm_www=$(normalize_url "www.${domain}")

    if [[ "$norm_redirect" == "$norm_bare" || "$norm_redirect" == "$norm_www" ]]; then
        return 0
    fi
    return 1
}

process_domain() {
    local domain="$1"
    local ip status notes

    # Resolve IP
    ip=$(resolve_ip "$domain")
    if [[ -z "$ip" ]]; then
        echo "${domain},,CANT_RESOLVE_IP,"
        return
    fi

    # If domain already points to our IP, check cert instead of HTTP
    if [[ "$ip" == "$BIND_IP" ]]; then
        local cert_status
        cert_status=$(check_cert "$domain")
        echo "${domain},${ip},${cert_status},"
        return
    fi

    # Check both bare and www
    local bare_result www_result
    bare_result=$(check_http "http://${domain}")
    www_result=$(check_http "http://www.${domain}")

    local bare_type bare_url www_type www_url
    bare_type="${bare_result%%|*}"
    bare_url="${bare_result#*|}"
    www_type="${www_result%%|*}"
    www_url="${www_result#*|}"

    # If bare_type has no pipe, bare_url == bare_type (no redirect URL)
    if [[ "$bare_type" == "$bare_url" ]]; then bare_url=""; fi
    if [[ "$www_type" == "$www_url" ]]; then www_url=""; fi

    # Both unreachable
    if [[ "$bare_type" == "CANT_REACH_HTTPD" && "$www_type" == "CANT_REACH_HTTPD" ]]; then
        echo "${domain},${ip},CANT_REACH_HTTPD,"
        return
    fi

    # Both static
    if [[ "$bare_type" == "STATIC" && "$www_type" == "STATIC" ]]; then
        echo "${domain},${ip},STATIC,"
        return
    fi

    # Both redirect to the same place
    if [[ "$bare_type" == "REDIRECT" && "$www_type" == "REDIRECT" ]]; then
        local norm_bare_url norm_www_url
        norm_bare_url=$(normalize_url "$bare_url")
        norm_www_url=$(normalize_url "$www_url")

        if [[ "$norm_bare_url" == "$norm_www_url" ]]; then
            echo "${domain},${ip},REDIRECT,${bare_url}"
            return
        fi

        # Different redirect targets — but check if they're just self-referencing (bare->www or www->bare)
        if is_self_redirect "$domain" "$bare_url" && is_self_redirect "$domain" "$www_url"; then
            echo "${domain},${ip},REDIRECT,${bare_url}"
            return
        fi

        echo "${domain},${ip},MANUAL_CHECK,bare->${bare_url} www->${www_url}"
        return
    fi

    # One redirects, one serves content
    if [[ "$bare_type" == "REDIRECT" && "$www_type" == "STATIC" ]]; then
        if is_self_redirect "$domain" "$bare_url"; then
            echo "${domain},${ip},STATIC,bare redirects to ${bare_url}"
            return
        fi
        echo "${domain},${ip},MANUAL_CHECK,bare->${bare_url} www->STATIC"
        return
    fi

    if [[ "$bare_type" == "STATIC" && "$www_type" == "REDIRECT" ]]; then
        if is_self_redirect "$domain" "$www_url"; then
            echo "${domain},${ip},STATIC,www redirects to ${www_url}"
            return
        fi
        echo "${domain},${ip},MANUAL_CHECK,bare->STATIC www->${www_url}"
        return
    fi

    # One redirects, other unreachable
    if [[ "$bare_type" == "REDIRECT" ]]; then
        echo "${domain},${ip},REDIRECT,${bare_url} (www: ${www_type})"
        return
    fi
    if [[ "$www_type" == "REDIRECT" ]]; then
        echo "${domain},${ip},REDIRECT,${www_url} (bare: ${bare_type})"
        return
    fi

    # One static, other unreachable
    if [[ "$bare_type" == "STATIC" ]]; then
        echo "${domain},${ip},STATIC,www: ${www_type}"
        return
    fi
    if [[ "$www_type" == "STATIC" ]]; then
        echo "${domain},${ip},STATIC,bare: ${bare_type}"
        return
    fi

    # Anything else
    echo "${domain},${ip},MANUAL_CHECK,bare: ${bare_type} www: ${www_type}"
}

# Process domains — skip header row
total=$(tail -n +2 "$INPUT_FILE" | grep -c '[^[:space:]]' || true)
count=0

while IFS=';' read -r domain rest; do
    [[ -z "$domain" ]] && continue

    count=$((count + 1))
    echo -ne "\r[${count}/${total}] ${domain}                    " >&2

    result=$(process_domain "$domain")
    echo "$result" >> "$OUTPUT_FILE"
done < <(tail -n +2 "$INPUT_FILE")

echo -e "\r[${count}/${total}] Done.                              " >&2
echo "Results written to: $OUTPUT_FILE" >&2
