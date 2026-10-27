# systemd

Copy to /etc/systemd/system/, then `sudo systemctl daemon-reload` and enable what you need.

- homelab-host-firewall.service: loads nftables/homelab-host-input.nft at boot
- pihole-compose.service: starts Pi-hole after the Tailscale IP exists (Pi-hole's own restart policy is "no" for this reason)
- slskd-port-sync.service / .timer: see scripts/README.md
- wifi-metrics.service / .timer: see scripts/README.md
