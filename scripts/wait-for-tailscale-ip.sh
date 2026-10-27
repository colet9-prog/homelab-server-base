#!/bin/sh
set -eu

TARGET_IP="100.64.113.70"
MAX_WAIT=90
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    if ip -4 addr show dev tailscale0 2>/dev/null | grep -q "inet ${TARGET_IP}/"; then
        exit 0
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

echo "Timed out waiting for ${TARGET_IP} on tailscale0" >&2
exit 1
