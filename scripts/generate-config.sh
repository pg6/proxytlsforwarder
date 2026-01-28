#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/data/domains.csv"
CADDYFILE="$PROJECT_DIR/config/Caddyfile"

# Get email from environment or use default
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"

if [[ ! -f "$CSV_FILE" ]]; then
    echo "Error: domains.csv not found at $CSV_FILE" >&2
    exit 1
fi

# Generate Caddyfile
{
    cat <<'EOF'
{
    email {$ACME_EMAIL}
}

(hetzner_tls) {
    tls {
        dns hetzner {$HETZNER_API_TOKEN}
    }
}

EOF

    # Skip header line and process each domain
    tail -n +2 "$CSV_FILE" | while IFS=, read -r domain target; do
        # Skip empty lines
        [[ -z "$domain" ]] && continue

        # Trim whitespace
        domain=$(echo "$domain" | xargs)
        target=$(echo "$target" | xargs)

        # Skip if either field is empty after trimming
        [[ -z "$domain" || -z "$target" ]] && continue

        cat <<EOF
${domain} {
    import hetzner_tls
    redir https://${target}{uri} 301
}

EOF
    done
} > "$CADDYFILE"

echo "Generated Caddyfile at $CADDYFILE"
