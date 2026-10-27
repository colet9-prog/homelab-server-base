THOMASHOMESERV — QUICK REFERENCE (public copy, updated 2026-10-27)

This is the trimmed public version of my private notes. Passwords, keys, account names and
open security to-dos are left out on purpose. The compose files and firewall rules in this
repo are the real ones.


1. HARDWARE & ROLE

    Hostname: thomashomeserv
    OS: Ubuntu 26.04.1 LTS, kernel 7.0.0-38-generic
    Board: MSI B450 Tomahawk Max, BIOS v3.70 (2020-06-09)
    CPU: AMD Ryzen 5 3600X (6C/12T)
    RAM: 24GiB (3x8GB). The two populated sticks have mismatched part numbers and run at
        2133 MT/s (JEDEC default, not XMP). A 4th stick is on hand but the server would
        not boot with all four installed.
    GPU: EVGA GT710 2GB (nouveau). No useful hardware transcoding, so Jellyfin files need
        to be client-compatible for Direct Play.
    Network: Wi-Fi only (Intel 7265, wlp40s0, 192.168.4.80/22, static via NetworkManager,
        forced to the 5GHz band). The onboard Ethernet port is unused.
    Role: KVM/libvirt host + Docker host + Samba file server.
    The Raspberry Pi (thomasPi) was retired on 2026-09-27; everything runs here now.


2. NETWORK ACCESS

    LAN: 192.168.4.0/22, gateway 192.168.4.1
    Tailscale: server is an exit node, Tailscale IP 100.64.113.70, MagicDNS on
        (thomashomeserv.tail866efc.ts.net)
    SSH: ssh thomasserver@192.168.4.80 (LAN) or @100.64.113.70 (Tailscale)
    When another machine uses the server as exit node it needs
        --exit-node-allow-lan-access=true, or LAN traffic to the server goes through the
        tailnet and times out.


3. DOCKER (14 containers, one compose project per folder, bind mounts only)

    node-exporter      host networking, :9100
    prometheus         9091->9090
    grafana            :3000
    libvirt-exporter   :9177
    npm-app            Nginx Proxy Manager, :80 / :81 / :443
    jellyfin           192.168.4.80:8096
    pihole             DNS on the LAN and Tailscale IPs, web UI :8081. Restart policy is "no"
                       on purpose: it binds the Tailscale IP, so a systemd unit starts it
                       after Tailscale is up.
    uptime-kuma        :3001, phone alerts through ntfy
    vaultwarden        11001->80, served over HTTPS by NPM with a Tailscale-issued cert
    homepage           :3002, dashboard (with socket-proxy, a read-only Docker socket gateway)
    ical               :8099, small nginx that relays a calendar feed for the dashboard
    gluetun + slskd    Soulseek behind ProtonVPN, see section 4

    Compose files for all of these are in this repo, one folder each (plus game-servers/).


4. SLSKD (SOULSEEK) BEHIND PROTONVPN

    Goal: share the music library over Soulseek with all of that traffic leaving through
    ProtonVPN, so peers and the ISP never see the home IP.

    - gluetun is the ProtonVPN WireGuard client and firewall. slskd runs with
      network_mode "service:gluetun", so it has no network of its own. If gluetun stops,
      slskd has no network at all. That is the kill switch (tested).
    - Music is mounted read-only at /music. Downloads go to /mnt/hdd/slskd-downloads,
      outside the Jellyfin library.
    - The web UI is on port 5030 (LAN and Tailscale) and needs a login.
    - Nothing is forwarded on the home router. Proton's port forwarding gives a new port
      every time gluetun connects, so a small systemd timer checks it each minute and
      updates slskd's listen_port (restarting slskd only when it changed).
    - Secrets are not in the repo: the WireGuard key goes in .env (see .env.example) and
      slskd's own config in app/slskd.yml stays on the server.
    - Known gap: if gluetun alone is restarted, slskd keeps the old network attachment and
      goes dead. Fix: cd slskd && sudo docker compose up -d --force-recreate

    Tests done: exit IP differs from the home IP, no IPv6 leak, kill switch, a packet
    capture on the Wi-Fi interface saw no direct Soulseek traffic, and two reboots.


5. VIRTUAL MACHINES (libvirt, definitions in libvirt/)

    opnsense-firewall   2 vCPU / 4GB. WAN on the default NAT bridge (virbr0), LAN on opn-lan
                        (virbr10, 192.168.100.0/24), GAMES on opn-games (virbr11,
                        192.168.110.0/24). Autostart on. The host side of opn-lan is
                        192.168.100.254 because OPNsense itself is .1.
    game-servers        8GB / 2 vCPU, only on opn-games. Project Zomboid and Minecraft run
                        here in Docker. Both are shut down for now (PZ since 2026-10-26, Minecraft since 2026-10-27).
                        Friends connect to the host LAN IP, which is forwarded through the
                        host's FORWARD chain to OPNsense NAT, then to the VM.
    honeypot            abandoned 2026-10-26, VM is shut off with autostart disabled.

    After editing a libvirt network's XML and restarting it, running VMs do not reattach.
    Use virsh destroy + virsh start (a full power cycle).


6. STORAGE

    Boot: 128GB SATA SSD, LVM root, about 52% used.
    Media: 1TB WD Blue HDD mounted by UUID at /mnt/hdd, about 65% used (Jellyfin library,
    slskd downloads, doc archive). Shared over Samba to the Windows machines.
    SMART baseline in wd-blue-smart-baseline-20260922.txt, first short and extended
    self-tests passed.
    Backups: not built yet. Plan is restic to /mnt/hdd with a nightly timer, a tested
    restore, then an offsite copy.


7. HOST FIREWALL

    Dedicated nftables table "inet homelab_host", INPUT only, default drop. The rules are
    in nftables/homelab-host-input.nft and load at boot through homelab-host-firewall.service.
    It leaves FORWARD and the Docker, libvirt and Tailscale chains alone.
    Never run `nft flush ruleset`, and don't enable a generic nftables.service.
    Check it: sudo nft list table inet homelab_host


8. WI-FI NOTES

    The router band-steers 2.4GHz and 5GHz under one SSID and the card kept picking 2.4GHz
    (about 58 Mbit/s). Forcing the band fixed it:
        sudo nmcli connection modify "<ssid>" 802-11-wireless.band a
    A stall on 2026-10-04 (very slow SSH, gateway-down alert) was cleared by bringing the
    connection down and up. The link sits on a DFS channel; if stalls come back, pin the
    router's 5GHz channel to 36-48.


9. CHEAT SHEET

    Deploy or update a stack:   cd <folder> && sudo docker compose up -d
    Container logs:             sudo docker logs <name> --tail 40
    List containers:            sudo docker ps -a
    VM status:                  sudo virsh list --all
    Firewall:                   sudo nft list table inet homelab_host
    slskd status:               cd ~/slskd && sudo docker compose ps
    Proton forwarded port:      sudo docker exec gluetun cat /tmp/gluetun/forwarded_port
    Port sync log:              journalctl -u slskd-port-sync.service -n 10 --no-pager
    Rebuild slskd + gluetun:    cd ~/slskd && sudo docker compose up -d --force-recreate
