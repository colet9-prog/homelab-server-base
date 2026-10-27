#!/bin/bash
set -u
CONF=/home/thomasserver/slskd/app/slskd.yml
exec 9>/run/slskd-port-sync.lock
flock -n 9 || exit 0
docker inspect -f '{{.State.Health.Status}}' gluetun 2>/dev/null | grep -qx healthy || exit 0
NEW=$(docker exec gluetun cat /tmp/gluetun/forwarded_port 2>/dev/null | tr -d '[:space:]')
case "$NEW" in ''|*[!0-9]*) exit 0;; esac
[ "$NEW" -ge 1024 ] && [ "$NEW" -le 65535 ] || exit 0
[ -f "$CONF" ] || exit 0
CUR=$(grep -E '^[[:space:]]*listen_port:' "$CONF" | grep -oE '[0-9]+' | head -1)
case "$CUR" in ''|*[!0-9]*) echo "listen_port not found in $CONF" >&2; exit 1;; esac
[ "$NEW" = "$CUR" ] && exit 0
TMP=$(mktemp)
sed -E "s/^([[:space:]]*listen_port:[[:space:]]*)[0-9]+/\1$NEW/" "$CONF" > "$TMP"
grep -qE "^[[:space:]]*listen_port:[[:space:]]*$NEW\$" "$TMP" || { rm -f "$TMP"; echo "edit verification failed" >&2; exit 1; }
cat "$TMP" > "$CONF"; rm -f "$TMP"
echo "listen_port $CUR -> $NEW, restarting slskd"
docker restart slskd
