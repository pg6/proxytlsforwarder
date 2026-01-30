#!/bin/bash

# Simple Hetzner DNS API Test (no jq required)
# Usage: ./test_hetzner_dns_simple.sh YOUR_API_TOKEN

if [ -z "$1" ]; then
    echo "Error: No API token provided"
    echo "Usage: $0 YOUR_HETZNER_DNS_API_TOKEN"
    exit 1
fi

API_TOKEN="$1"
BASE_URL="https://dns.hetzner.com/api/v1"

echo "========================================"
echo "Hetzner DNS API Token Test"
echo "========================================"
echo ""

# Test 1: List zones
echo "Test 1: Listing DNS Zones..."
echo ""
curl -s -H "Authorization: Bearer ${API_TOKEN}" "${BASE_URL}/zones" | python3 -m json.tool
echo ""

# Test 2: Get all records (if you have zones)
echo "Test 2: Listing All DNS Records..."
echo ""
curl -s -H "Authorization: Bearer ${API_TOKEN}" "${BASE_URL}/records" | python3 -m json.tool
echo ""

echo "========================================"
echo "Test completed!"
echo "========================================"
