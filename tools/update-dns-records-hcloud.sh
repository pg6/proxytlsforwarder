#!/bin/bash
set -euo pipefail

OLD_IP="65.108.24.25"
NEW_IP="178.104.217.162"

if ! command -v hcloud &>/dev/null; then
    echo "Error: hcloud CLI not found" >&2
    exit 1
fi

echo "Scanning all zones for A records pointing to $OLD_IP..."
echo ""

updated=0
skipped=0

while read -r zone_id zone_name _rest; do
    [[ -z "$zone_name" ]] && continue

    # Get all A records for this zone that match the old IP
    matching_names=()
    while read -r rrset_name _type rrset_value; do
        if [[ "$rrset_value" == "$OLD_IP" ]]; then
            matching_names+=("$rrset_name")
        fi
    done < <(hcloud zone rrset list -o noheader --type A "$zone_name" 2>/dev/null || true)

    if [[ ${#matching_names[@]} -eq 0 ]]; then
        echo "  SKIP  $zone_name (no records pointing to $OLD_IP)"
        skipped=$((skipped + 1))
        continue
    fi

    for name in "${matching_names[@]}"; do
        echo -n "  UPDATE $zone_name $name A $OLD_IP -> $NEW_IP ... "
        if hcloud zone rrset set-records --record "$NEW_IP" "$zone_name" "$name" A; then
            echo "OK"
            updated=$((updated + 1))
        else
            echo "FAILED"
        fi
    done

done < <(hcloud zone list -o noheader 2>/dev/null | awk '{print $1, $2}')

echo ""
echo "Done. Updated: $updated record(s), skipped: $skipped zone(s)."
