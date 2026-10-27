# homelab-server-base

Config for `thomashomeserv`, the Ubuntu box that runs my homelab: Docker services, the
host firewall, and the libvirt VM definitions. Network layout and segmentation live in
the `homelab-networking` repo.

| Folder | What's in it |
| --- | --- |
| `monitoring/` | Prometheus, Grafana, node-exporter, libvirt-exporter |
| `npm/` | Nginx Proxy Manager |
| `uptime-kuma/` | Uptime Kuma |
| `vaultwarden/` | Vaultwarden |
| `slskd/` | slskd (Soulseek) running behind gluetun / ProtonVPN |
| `jellyfin/` | Jellyfin |
| `pihole/` | Pi-hole (starts after Tailscale, see systemd/) |
| `homepage/` | Homepage dashboard + docker socket proxy, config files |
| `ical/` | Tiny nginx that serves a calendar feed and the VM stats JSON to Homepage |
| `game-servers/` | Compose files for the game-servers VM (both off for now) |
| `systemd/` | Units: host firewall, Pi-hole start order, slskd port sync, Wi-Fi metrics |
| `scripts/` | The scripts those units and cron run |
| `nftables/` | Host firewall rules (INPUT only, default drop) |
| `libvirt/` | VM and virtual network definitions |
| `docs/notes.md` | Quick reference, public version |

Secrets stay out of here. `.env`, certs, keys, and app data folders are in `.gitignore`;
`slskd/.env.example` shows what the WireGuard key file looks like.

Placeholders to fill in: `.env.example` files in slskd/, pihole/ and game-servers/, the API keys in homepage/config/services.yaml, and the calendar URL in ical/refresh.sh.
