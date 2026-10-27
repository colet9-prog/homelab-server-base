#!/bin/bash
IFACE="wlp40s0"
OUTFILE="/var/lib/node_exporter/textfile/wifi.prom"
TMPFILE="${OUTFILE}.tmp"

LINK=$(iw dev "$IFACE" link)
SIGNAL=$(echo "$LINK" | grep -oP 'signal:\s*-?\K[0-9]+')
RX_BITRATE=$(echo "$LINK" | grep -oP 'RX:.*rx bitrate:\s*\K[0-9.]+' || echo "$LINK" | grep -oP 'rx bitrate:\s*\K[0-9.]+')
TX_BITRATE=$(echo "$LINK" | grep -oP 'tx bitrate:\s*\K[0-9.]+')
FREQ=$(echo "$LINK" | grep -oP 'freq:\s*\K[0-9.]+')

{
  echo "# HELP wifi_signal_dbm Wi-Fi signal strength in dBm (negative value, stored positive)"
  echo "# TYPE wifi_signal_dbm gauge"
  echo "wifi_signal_dbm{iface=\"$IFACE\"} -${SIGNAL:-0}"
  echo "# HELP wifi_rx_bitrate_mbps Current RX bitrate in Mbit/s"
  echo "# TYPE wifi_rx_bitrate_mbps gauge"
  echo "wifi_rx_bitrate_mbps{iface=\"$IFACE\"} ${RX_BITRATE:-0}"
  echo "# HELP wifi_tx_bitrate_mbps Current TX bitrate in Mbit/s"
  echo "# TYPE wifi_tx_bitrate_mbps gauge"
  echo "wifi_tx_bitrate_mbps{iface=\"$IFACE\"} ${TX_BITRATE:-0}"
  echo "# HELP wifi_freq_mhz Current connected frequency in MHz"
  echo "# TYPE wifi_freq_mhz gauge"
  echo "wifi_freq_mhz{iface=\"$IFACE\"} ${FREQ:-0}"
} > "$TMPFILE"

mv "$TMPFILE" "$OUTFILE"
