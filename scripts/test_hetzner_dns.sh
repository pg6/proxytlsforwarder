#!/bin/bash

# Hetzner DNS API Test Script
# This script tests your Hetzner DNS API token and displays your DNS configuration

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if API token is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No API token provided${NC}"
    echo "Usage: $0 YOUR_HETZNER_DNS_API_TOKEN"
    exit 1
fi

API_TOKEN="$1"
BASE_URL="https://dns.hetzner.com/api/v1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Hetzner DNS API Token Test${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Test 1: Validate token by listing zones
echo -e "${YELLOW}Test 1: Validating API Token...${NC}"
ZONES_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${API_TOKEN}" "${BASE_URL}/zones")
HTTP_CODE=$(echo "$ZONES_RESPONSE" | tail -n1)
ZONES_DATA=$(echo "$ZONES_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Token is valid!${NC}\n"
else
    echo -e "${RED}✗ Token validation failed (HTTP $HTTP_CODE)${NC}"
    echo -e "${RED}Response: $ZONES_DATA${NC}"
    exit 1
fi

# Test 2: Display zones
echo -e "${YELLOW}Test 2: Listing DNS Zones...${NC}"
ZONE_COUNT=$(echo "$ZONES_DATA" | jq -r '.zones | length' 2>/dev/null)

if [ -z "$ZONE_COUNT" ] || [ "$ZONE_COUNT" = "null" ]; then
    echo -e "${RED}✗ Failed to parse zones data${NC}"
    echo "Raw response: $ZONES_DATA"
    exit 1
fi

echo -e "${GREEN}✓ Found $ZONE_COUNT zone(s)${NC}\n"

if [ "$ZONE_COUNT" -gt 0 ]; then
    echo -e "${BLUE}Zone Details:${NC}"
    echo "$ZONES_DATA" | jq -r '.zones[] | "  ID: \(.id)\n  Name: \(.name)\n  TTL: \(.ttl)\n  Records: \(.records_count)\n  Status: \(.status)\n  Created: \(.created)\n  Modified: \(.modified)\n  ---"'
    echo ""
    
    # Test 3: Get records for each zone
    echo -e "${YELLOW}Test 3: Listing DNS Records...${NC}"
    
    ZONE_IDS=$(echo "$ZONES_DATA" | jq -r '.zones[].id')
    
    for ZONE_ID in $ZONE_IDS; do
        ZONE_NAME=$(echo "$ZONES_DATA" | jq -r ".zones[] | select(.id==\"$ZONE_ID\") | .name")
        echo -e "${BLUE}Records for zone: ${ZONE_NAME}${NC}"
        
        RECORDS_RESPONSE=$(curl -s -H "Authorization: Bearer ${API_TOKEN}" "${BASE_URL}/records?zone_id=${ZONE_ID}")
        
        RECORD_COUNT=$(echo "$RECORDS_RESPONSE" | jq -r '.records | length' 2>/dev/null)
        
        if [ "$RECORD_COUNT" -gt 0 ]; then
            echo "$RECORDS_RESPONSE" | jq -r '.records[] | "  [\(.type)] \(.name) → \(.value) (TTL: \(.ttl))"'
        else
            echo "  No records found"
        fi
        echo ""
    done
else
    echo -e "${YELLOW}No DNS zones configured yet${NC}\n"
fi

# Test 4: Check API rate limits (if available in headers)
echo -e "${YELLOW}Test 4: Checking API Information...${NC}"
FULL_RESPONSE=$(curl -s -i -H "Authorization: Bearer ${API_TOKEN}" "${BASE_URL}/zones")

RATE_LIMIT=$(echo "$FULL_RESPONSE" | grep -i "x-ratelimit-limit:" | cut -d' ' -f2 | tr -d '\r')
RATE_REMAINING=$(echo "$FULL_RESPONSE" | grep -i "x-ratelimit-remaining:" | cut -d' ' -f2 | tr -d '\r')

if [ -n "$RATE_LIMIT" ]; then
    echo -e "${GREEN}✓ Rate Limit: $RATE_LIMIT requests${NC}"
    echo -e "${GREEN}✓ Remaining: $RATE_REMAINING requests${NC}"
else
    echo -e "${YELLOW}Rate limit information not available in response${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}All tests completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
