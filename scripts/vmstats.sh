#!/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
OUT=/home/thomasserver/ical/www/vms.json
IF=wlp40s0
INT=2

hum()  { awk -v b="$1" 'BEGIN{ if(b>=1073741824) printf "%.1f GB", b/1073741824; else if(b>=1048576) printf "%.1f MB", b/1048576; else printf "%.0f KB", b/1024 }'; }
rate() { awk -v b="$1" -v i="$INT" 'BEGIN{ r=b/i; if(r>=1048576) printf "%.1f MB/s", r/1048576; else printf "%.0f KB/s", r/1024 }'; }
dom()  { virsh domstats --state --cpu-total --balloon --vcpu --interface "$1" 2>/dev/null; }
val()  { awk -F= -v k="$2" '{ gsub(/^[ \t]+/, "", $1) } $1 == k { print $2; exit }' <<< "$1"; }
netsum() { awk -F= -v d="$2" '{ gsub(/^[ \t]+/, "", $1) } $1 ~ ("^net\\.[0-9]+\\." d "\\.bytes$") { s += $2 } END { printf "%.0f", s }' <<< "$1"; }
hostnet() { sed 's/:/ /' /proc/net/dev | awk -v i="$IF" '$1 == i { print $2, $10 }'; }

vmjson() {
  local s1="$1" s2="$2" state t1 t2 vc cpu rss max rx tx
  state=$(val "$s2" state.state)
  if [ "$state" != "1" ]; then
    printf '{"state":"Off","cpu":"-","mem":"-","net":"-"}'; return
  fi
  t1=$(val "$s1" cpu.time); t2=$(val "$s2" cpu.time); vc=$(val "$s2" vcpu.current)
  cpu=$(awk -v a="${t1:-0}" -v b="${t2:-0}" -v v="${vc:-1}" -v i="$INT" 'BEGIN{ if(v<1) v=1; printf "%.0f%%", (b-a)/(i*1e9*v)*100 }')
  av=$(val "$s2" balloon.available); us=$(val "$s2" balloon.usable)
  if [ -n "$av" ] && [ -n "$us" ]; then rss=$((av - us)); else rss=""; fi
  max=$(val "$s2" balloon.maximum)
  rx=$(netsum "$s2" rx); tx=$(netsum "$s2" tx)
  printf '{"state":"Running","cpu":"%s","mem":"%s / %s","net":"%s / %s"}' \
    "$cpu" "$([ -n "$rss" ] && hum $(( rss * 1024 )) || echo n/a)" "$(hum $(( ${max:-0} * 1024 )))" "$(hum "$rx")" "$(hum "$tx")"
}

read rx1 tx1 < <(hostnet)
g1=$(dom game-servers); o1=$(dom opnsense-firewall)
sleep $INT
read rx2 tx2 < <(hostnet)
g2=$(dom game-servers); o2=$(dom opnsense-firewall)

down=$(rate $(( rx2 - rx1 ))); up=$(rate $(( tx2 - tx1 )))
load=$(cut -d' ' -f1 /proc/loadavg)
wifi=$(iw dev "$IF" link 2>/dev/null | awk '/signal:/ { print $2 " dBm" }'); [ -z "$wifi" ] && wifi="n/a"

TMP=$(mktemp "$(dirname "$OUT")/.vms.XXXXXX")
printf '{"host":{"down":"%s","up":"%s","load":"%s","wifi":"%s"},"game_servers":%s,"opnsense":%s}\n' \
  "$down" "$up" "$load" "$wifi" "$(vmjson "$g1" "$g2")" "$(vmjson "$o1" "$o2")" > "$TMP"
chmod 644 "$TMP"
mv "$TMP" "$OUT"
