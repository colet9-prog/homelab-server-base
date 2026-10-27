# scripts

Installed on the server under /usr/local/sbin (or /usr/local/bin for wifi-metrics.sh).
The matching systemd units are in ../systemd.

- slskd-port-sync.sh: reads Proton's forwarded port from gluetun and updates slskd's listen_port, restarting slskd only when it changed. Run every minute by slskd-port-sync.timer.
- wait-for-tailscale-ip.sh: blocks (up to 90s) until tailscale0 has the server's Tailscale IP. Pi-hole binds that IP, so pihole-compose.service waits for it.
- wifi-metrics.sh: writes Wi-Fi signal and bitrate as a Prometheus textfile for node-exporter. Every 30s via wifi-metrics.timer.
- vmstats.sh: samples the two VMs and the host's Wi-Fi throughput into a small JSON file that the Homepage dashboard reads. Runs from cron every minute.
