# Domain Redirect Server

A Docker-based Caddy web server that handles 301 redirects with automatic Let's Encrypt certificates via Hetzner DNS.

## Features

- Automatic HTTPS via Let's Encrypt (DNS-01 challenge)
- Hetzner DNS integration for certificate automation
- Zero-downtime configuration reloads
- Simple CSV-based domain management
- Shell scripts for adding/removing domains
- No weekly rate limit concerns (DNS-01 allows bulk issuance)

## Prerequisites

- Docker and Docker Compose
- Hetzner DNS account with API token
- Domains using Hetzner nameservers

## Hetzner DNS Setup

### 1. Create Hetzner DNS Account

1. Go to [dns.hetzner.com](https://dns.hetzner.com)
2. Log in with your Hetzner account (or create one)

### 2. Add Your Domains

For each domain:

1. Click **Add new zone**
2. Enter the domain name
3. Note the Hetzner nameservers provided:
   - `hydrogen.ns.hetzner.com`
   - `oxygen.ns.hetzner.com`
   - `helium.ns.hetzner.de`
4. Update nameservers at your registrar to point to Hetzner

### 3. Create API Token

1. Go to [dns.hetzner.com/settings/api-token](https://dns.hetzner.com/settings/api-token)
2. Click **Create access token**
3. Give it a name (e.g., "caddy-redirect-server")
4. Copy the token immediately (shown only once)

### 4. Add DNS A Record

For each domain, add an A record pointing to your server:

- **Name:** `@` (or leave blank)
- **Type:** A
- **Value:** Your server's IP address

## Quick Start

### 1. Configure Environment

Create a `.env` file:

```bash
cat > .env << 'EOF'
ACME_EMAIL=your-email@example.com
HETZNER_API_TOKEN=your-hetzner-api-token
EOF
```

### 2. Add Your Domains

```bash
./scripts/add-domain.sh oldsite.com newsite.com
```

This adds a redirect: `https://oldsite.com/*` → `https://newsite.com/*`

### 3. Build and Start

```bash
docker-compose up -d --build
```

The first build takes a few minutes (compiles Caddy with Hetzner plugin).

### 4. Verify

```bash
curl -I https://oldsite.com
# Should return: HTTP/2 301, Location: https://newsite.com/
```

## Usage

### Adding a Domain

```bash
./scripts/add-domain.sh <source-domain> <target-domain>
```

Example:
```bash
./scripts/add-domain.sh legacy.example.com modern.example.com
```

### Removing a Domain

```bash
./scripts/remove-domain.sh <domain>
```

Example:
```bash
./scripts/remove-domain.sh legacy.example.com
```

### Listing All Domains

```bash
./scripts/list-domains.sh
```

Filter by target:
```bash
./scripts/list-domains.sh --target newsite.com
```

### Checking Certificate Status

```bash
./scripts/status.sh
```

Shows which domains have valid certificates and their expiry dates.

### Exporting DNS Records

```bash
./scripts/export-dns.sh <server-ip>
```

Generates a CSV file with all required DNS A records.

## Bulk Import

For adding many domains at once, edit `data/domains.csv` directly:

```csv
domain,target
oldsite1.com,newsite.com
oldsite2.org,newsite.com
legacy.example.net,modern.example.com
```

Then regenerate and reload:

```bash
./scripts/generate-config.sh
./scripts/reload.sh
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `ACME_EMAIL` | Email for Let's Encrypt notifications | Yes |
| `HETZNER_API_TOKEN` | Hetzner DNS API token | Yes |

### Example .env File

```bash
ACME_EMAIL=admin@example.com
HETZNER_API_TOKEN=abc123your-token-here
```

## File Structure

```
proxyforwardtls/
├── Dockerfile              # Builds Caddy with Hetzner DNS plugin
├── docker-compose.yml      # Docker service configuration
├── .env                    # Environment variables (create this)
├── config/
│   └── Caddyfile           # Generated - do not edit manually
├── data/
│   ├── domains.csv         # Source of truth for redirects
│   └── dns-records.csv     # Generated DNS records for reference
└── scripts/
    ├── add-domain.sh       # Add a redirect
    ├── remove-domain.sh    # Remove a redirect
    ├── list-domains.sh     # List all domains
    ├── status.sh           # Check certificate status
    ├── export-dns.sh       # Generate DNS records CSV
    ├── generate-config.sh  # Rebuild Caddyfile from CSV
    └── reload.sh           # Reload Caddy configuration
```

## How DNS-01 Challenge Works

1. Caddy requests a certificate from Let's Encrypt
2. Let's Encrypt provides a challenge token
3. Caddy uses the Hetzner API to create a TXT record: `_acme-challenge.yourdomain.com`
4. Let's Encrypt verifies the TXT record
5. Certificate is issued
6. Caddy removes the TXT record

**Advantages over HTTP-01:**
- No need for port 80 to be accessible during issuance
- Higher rate limits (can issue all 400 certs quickly)
- Works even before DNS A records are configured

## Troubleshooting

### Certificate Not Issued

1. Verify Hetzner API token is correct:
   ```bash
   curl -H "Auth-API-Token: $HETZNER_API_TOKEN" \
     https://dns.hetzner.com/api/v1/zones
   ```

2. Check domain is using Hetzner nameservers:
   ```bash
   dig NS yourdomain.com
   ```

3. Check Caddy logs:
   ```bash
   docker-compose logs caddy
   ```

### Build Fails

Ensure Docker has internet access to download the Hetzner DNS plugin:
```bash
docker-compose build --no-cache
```

### Container Won't Start

Validate the Caddyfile:
```bash
docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile
```

### Reload Fails

Check if the container is running:
```bash
docker-compose ps
```

Restart if needed:
```bash
docker-compose restart
```
