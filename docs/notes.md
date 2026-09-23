THOMASHOMESERV — QUICK REFERENCE GUIDE (V5)
(lean version — see homelab-network-topology.txt V2 for full detail)


1. HARDWARE & ROLE

    Hostname: thomashomeserv
    OS: Ubuntu 26.04.1 LTS (CORRECTED — previously documented as 24.04 LTS; confirmed
        via `hostnamectl`. Kernel 7.0.0-31-generic)
    Motherboard: MSI B450 Tomahawk Max (MS-7C02), BIOS/firmware v3.70, dated 2020-06-09
        (~6.3 years old — worth a BIOS update check, especially relevant to the RAM
        speed issue below)
    CPU: AMD Ryzen 5 3600X, 6-core/12-thread, boost enabled, max ~4.4GHz. Idle-ish temps
        under light load: Tctl 56.1°C, Tccd1 54.0°C
    RAM: 24GiB installed — CORRECTED from previously documented 32GB (4x8GB). Confirmed
        via `dmidecode -t memory`: only 3x8GB DIMMs populated (DIMM 0/Channel A, DIMM
        0/Channel B, DIMM 1/Channel A), 4th slot (DIMM 1/Channel B) empty/no module.
        Also: the two populated sticks have MISMATCHED part numbers
        (F4-3600C16-8GVKC vs F4-3600C18-8GVK) and are running at 2133 MT/s — well
        below their rated speed (JEDEC default, not XMP/DOCP). Matches the original
        ServPlans concern about RAM speed not matching listing. Worth deciding whether
        to: (a) source a matching 4th stick and reach 32GB, (b) enable XMP/DOCP in BIOS
        to get proper rated speed, or both.
    GPU: EVGA GeForce GT710 2GB, running the open-source `nouveau` driver (not
        proprietary nvidia), idle temp ~25°C. Cannot meaningfully hardware-transcode
        video (confirmed via Jellyfin Direct Play testing — see section 3)
    Role: KVM/libvirt hypervisor host + Docker host (NPM, monitoring stack, Jellyfin,
        Samba, and now also Pi-hole — see section 3 note)
    Wired NIC: enp34s0 (onboard Realtek RTL8111/8168/8211/8411) — down/unplugged, no
        Ethernet run planned (server is upstairs). NOTE: leaving this NIC down is
        currently causing two boot-time issues — see section 8.
    Wi-Fi NIC: wlp40s0 — CORRECTED: this is an Intel Wireless 7265 (Dual Band
        Wireless-AC), NOT a "TP-Link card" as previously documented. Confirmed via
        `lspci` (Intel Corporation Wireless 7265, iwlwifi driver). Forced to 5GHz band
        (see section 6).
    IP forwarding: enabled (net.ipv4.ip_forward=1, net.ipv6.conf.all.forwarding=1) —
        required for Tailscale exit node + subnet routing


2. NETWORK ACCESS

    Home LAN (Wi-Fi, wlp40s0)
        IP: 192.168.4.80/22
        Broadcast: 192.168.7.255
        Subnet: 192.168.4.0/22 (gateway 192.168.4.1)
        SSID: "Wu-Tang LAN" — router band-steers 2.4GHz and 5GHz under one SSID name
        Default route present twice (static metric 600 + DHCP metric 1024) — harmless
        redundancy, static route wins

    Tailscale (remote access, no port-forwarding needed)
        Hostname: thomashomeserv
        Tailscale IP: 100.64.113.70
        Advertised as an exit node (replaced thomasPi in this role — Pi's Wi-Fi was
        unreliable)
        Reach it from anywhere on the tailnet via this IP (or hostname, once MagicDNS
        is confirmed working)

    SSH
        ssh thomasserver@192.168.4.80        (on home LAN)
        ssh thomasserver@100.64.113.70        (via Tailscale, from anywhere)


3. DOCKER — ON THOMASHOMESERV ITSELF

    Confirmed running containers (via `docker ps -a`):
        node-exporter      — prom/node-exporter:latest, host networking
        jellyfin           — jellyfin/jellyfin:latest, 192.168.4.80:8096->8096
        pihole              — pihole/pihole:latest, DNS on :53 (both LAN IP and
                              Tailscale IP), web UI 192.168.4.80:8081->80
                              *** NEW/NOTABLE: Pi-hole is now ALSO running directly on
                              thomashomeserv, in addition to the existing instance on
                              thomasPi (192.168.4.71:8053). Not yet clear whether this
                              is a deliberate second instance, a migration in progress,
                              or a leftover test deployment — worth deciding which one
                              is authoritative and pointing DHCP/clients accordingly to
                              avoid split-brain DNS blocking. ***
        uptime-kuma         — louislam/uptime-kuma:2, 0.0.0.0:3001
        prometheus          — prom/prometheus:latest, 0.0.0.0:9091->9090
        grafana             — grafana/grafana:latest, 0.0.0.0:3000
        libvirt-exporter    — ghcr.io/inovex/prometheus-libvirt-exporter:v2.5.0, :9177
        npm-app             — jc21/nginx-proxy-manager:2.15.1, :80/:81/:443

    Restart behavior / Pi-hole boot ordering (IMPLEMENTED AND REBOOT-VALIDATED 2026-09-23)
        All non-Pi-hole containers use restart policy `unless-stopped`.
        Pi-hole uses restart policy `"no"` intentionally because it binds DNS to the
        specific Tailscale address 100.64.113.70:53. Docker can start before that
        address exists, which caused a failed post-reboot binding (`cannot assign
        requested address`). Pi-hole startup is therefore owned by systemd:
            Unit: /etc/systemd/system/pihole-compose.service (enabled; active/exited)
            Working directory: /home/thomasserver/pihole
            Wait script: /usr/local/sbin/wait-for-tailscale-ip.sh
            Behavior: waits up to 90 seconds for 100.64.113.70 on tailscale0, then
                      runs `docker compose up -d`.
        Verified after reboot: Pi-hole started successfully, became healthy, bound
        192.168.4.80:53 and 100.64.113.70:53 over TCP/UDP, exposed its UI at
        192.168.4.80:8081, and answered DNS queries through both addresses.
        Compose note: quote the policy exactly as `restart: "no"` (unquoted YAML `no`
        may be interpreted as a Boolean).

    Docker networks (one bridge per compose project, confirmed via `docker network ls`
    + `ip a`):
        jellyfin_default    (br-ffcfd71949cd)  172.22.0.0/16
        monitoring_default  (br-0d3c6559213f)  172.19.0.0/16
        npm_default         (br-7ffa61220a44)  172.18.0.0/16
        pihole_default      (br-8da586916e3f)  172.20.0.0/16
        uptime-kuma_default (br-776625e9ce27)  172.21.0.0/16
        docker0 (default bridge)               172.17.0.0/16 — unused/down

    Docker cleanup opportunity: `docker system df` shows 10.01GB of images with 9.29GB
    (92%) reclaimable, and 2 anonymous local volumes totaling 7.26GB, 100% reclaimable
    (not attached to any running container). Worth running `docker image prune -a` and
    `docker volume prune` after confirming those volumes aren't needed.

    Nginx Proxy Manager (migrated here from thomasPi)
        Container: npm-app
        Location: ~/npm (docker-compose.yml, ./data, ./letsencrypt)
        Admin UI: http://192.168.4.80:81
        Proxy hosts configured (all *.100.64.113.70.nip.io):
            cloud   -> 192.168.4.71:8080  (FileBrowser, on thomasPi)
            dns     -> 192.168.4.71:8053  (Pi-hole, on thomasPi)
            monitor -> 192.168.4.71:8090  (Beszel, on thomasPi)
            opnsense -> https://192.168.100.1:443 (OPNsense web UI — see section 4)
            grafana  -> http://192.168.4.80:3000 (Grafana, on thomashomeserv itself)
        NOTE: all proxy hosts are set to "Publicly Accessible" (no auth layer) — fine
        for services with their own logins, but the opnsense host in particular is a
        higher-value target and has no additional auth in front of it. Worth revisiting.

    Jellyfin (media server)
        Library: on the WD Blue 1TB HDD — see section 5 for the confirmed mount path
        (corrects an earlier discrepancy)
        Client tested: Roku app, confirmed Direct Play (no CPU transcoding) for tested
        content — GT710 GPU cannot meaningfully hardware-transcode, so keeping files
        client-compatible for Direct Play matters on this box
        NOTE: not yet added as an NPM proxy host — currently accessed directly by
        IP:port (192.168.4.80:8096)

    Samba
        smbd running directly on the host (systemd service, not containerized) —
        confirmed active via `systemctl list-units`

    Monitoring Stack (Prometheus + Grafana)
        Location: ~/monitoring (docker-compose.yml, prometheus.yml, ./prometheus-data,
        ./grafana-data)
        node-exporter runs with `network_mode: host`; textfile collector enabled (see
        below) for custom Wi-Fi metrics
        prometheus mapped to host port 9091 (container's internal 9090 — Cockpit
        already owns 9090 on this box)
        NOTE: prometheus-data and grafana-data folders must be chown'd to match each
        image's internal UID (65534 for Prometheus, 472 for Grafana) or the containers
        crash-loop on permission errors — bind-mounted folders default to your own
        user's ownership.
        Access: http://192.168.4.80:3000 (Grafana), also proxied via NPM (see above)

        Custom Wi-Fi metrics (added to diagnose streaming buffering):
            Script: /usr/local/bin/wifi-metrics.sh — parses `iw dev wlp40s0 link`
            every 30s via a systemd timer, writes Prometheus textfile-format metrics to
            /var/lib/node_exporter/textfile_collector/wifi.prom
            Metrics exposed: wifi_signal_dbm, wifi_rx_bitrate_mbps,
            wifi_tx_bitrate_mbps, wifi_freq_mhz (all labeled iface="wlp40s0")
            Systemd units: wifi-metrics.service (oneshot) + wifi-metrics.timer
            (OnUnitActiveSec=30s)
            Grafana panels added to the existing "Node Exporter Full" dashboard

    Uptime Kuma (uptime/latency monitoring — separate from the Prometheus stack)
        Monitoring thomashomeserv via ICMP ping to 192.168.4.80, 60s interval
        Covers latency/uptime history; does NOT capture Wi-Fi signal/link-rate data
        (that gap is what the custom textfile-collector metrics above fill)

    Performance Co-Pilot (pmcd, pmie, pmlogger, pmproxy) — CONFIRMED RUNNING, not
    previously documented. A separate host-level metrics/logging suite alongside
    Prometheus/Grafana. Not currently wired into Grafana or otherwise actively used —
    worth deciding whether to keep, configure properly, or disable to reduce overhead.


4. VIRTUAL MACHINES (KVM/libvirt)

    game-servers
        Hostname inside VM: thomashomegame
        Confirmed specs (via `virsh dumpxml`): 8GB RAM (8388608 KiB), 2 vCPU, single
        disk (qcow2, /var/lib/libvirt/images/game-servers.qcow2), single NIC on
        opn-games (virbr11) only — no default/direct bridge attachment
        VNC console on 127.0.0.1:5901 (localhost only, not exposed)
        Autostart: enabled (was disabled — fixed after it didn't survive a host reboot)
        Runs Docker containers:
            Minecraft (Java) — container: minecraft-server, image: itzg/minecraft-server,
                port 25565/tcp, connect via 192.168.4.80:25565
            Project Zomboid — container: pz-server, image: skytuna/zomboid:latest,
                ports 16261-16262/udp, connect via 192.168.4.80:16261
                IMPORTANT: docker-compose.yml volumes must use the ABSOLUTE path
                /home/thomasserver/pz-data, not ~/pz-data — sudo expands ~ to /root,
                silently mounting the wrong folder
            PZ backup: cron job confirmed —
                0 3 * * * /home/thomasserver/pz-server/backup-pz.sh (daily at 3am,
                logs to /home/thomasserver/pz-server/backups/backup.log)

    opnsense-firewall
        Confirmed specs (via `virsh dumpxml`): 2 vCPU, 4GB RAM (4194304 KiB), FreeBSD
        13.2-based, single qcow2 disk (/var/lib/libvirt/images/opnsense-target.qcow2)
        VNC console on 127.0.0.1:5900 (localhost only)
        WAN -> default bridge (virbr0, 192.168.122.0/24 NAT out through host's Wi-Fi),
            MAC 52:54:00:89:c1:c6
        LAN -> opn-lan bridge (virbr10, 192.168.100.0/24), MAC 52:54:00:9b:f2:eb
            Host bridge IP: 192.168.100.254 (NOT .1 — that's OPNsense's own LAN gateway
            IP; these must not match, causes intermittent unreachability)
        GAMES -> opn-games bridge (virbr11, 192.168.110.0/24), gateway 192.168.110.1,
            MAC 52:54:00:a3:6a:fb
            NOTE: opn-games (virbr11) itself has NO host-side IP address assigned
            (confirmed via `virsh net-dumpxml` and `ip a`) — unlike opn-lan/virbr10,
            which has 192.168.100.254. This is expected since the host doesn't need L3
            reachability into the games segment the way it does for the lab segment.
        Access:
            - SSH tunnel (ssh -L 8443:192.168.100.1:443 thomasserver@192.168.4.80,
              then https://localhost:8443) — always works, no extra config needed
            - Also reachable via NPM: https://opnsense.100.64.113.70.nip.io

    Useful commands:
        sudo virsh list --all                 -> list all VMs
        sudo virsh start <vm-name>             -> start a VM
        sudo virsh shutdown <vm-name>          -> graceful shutdown
        sudo virsh dominfo <vm-name>           -> specs/status
        sudo virsh dumpxml <vm-name>           -> full XML config (NICs, disks, etc.)
        sudo virsh domblklist <vm-name>        -> disk file mappings per VM
        sudo virsh autostart <vm-name>         -> enable autostart on boot
        sudo virsh net-list --all              -> list libvirt networks
        sudo virsh net-dumpxml --network <name> -> full network/bridge XML config
        sudo virsh net-edit <network-name>     -> edit a network's XML (e.g. IP conflicts)
        NOTE: after editing a network's XML and running net-destroy/net-start, running
        VMs do NOT auto-reattach — a graceful virsh reboot isn't enough either; use
        virsh destroy + virsh start (hard power cycle) to force reattachment.


5. STORAGE

    Boot/OS drive: /dev/sdb — 128GB Fanxiang S101, GPT with EFI (sdb1, FAT32,
        /boot/efi), /boot (sdb2, ext4), and LVM (sdb3 -> ubuntu-vg/ubuntu-lv, ext4,
        mounted at /, 115G total, currently 60% used)

    Media HDD: /dev/sda — 1TB WDC WD10EZEX-22R (the WD Blue), single ext4 partition
        (sda1), UUID aecff732-3641-4b7e-a208-30aaf0bc40dd, mounted BY UUID in
        /etc/fstab — confirmed persistent across reboots, 916G total, 12% used.
        *** MOUNT PATH CORRECTION: confirmed via `lsblk -f`, `cat /etc/fstab`, and
        `df -h` that this drive is mounted at /mnt/hdd, NOT /mnt/data/media as
        previously documented. Update Jellyfin library path references accordingly if
        anything still points at the old path. ***

    SMART baseline: CAPTURED 2026-09-22 — see wd-blue-smart-baseline-20260922.txt.
        Overall health: PASSED. Reallocated_Sector_Ct=0, Current_Pending_Sector=0,
        Offline_Uncorrectable=0, SMART error log empty, temperature 28°C. The drive has
        36,079 power-on hours (~4.1 years) and UDMA_CRC_Error_Count=10; treat that CRC
        count as a baseline and investigate only if it increases. No SMART self-tests
        logged yet. Recommended test cadence: short test monthly, extended test during
        an idle maintenance window (reported duration ~119 minutes).


6. WI-FI — DIAGNOSIS & CURRENT STATE (Sept 2026)

    Symptom: intermittent Jellyfin streaming buffering (Roku client) on high-bitrate
    files (e.g. 3840x1600 remuxes)

    Root cause #1 — wrong band: wlp40s0 was auto-associating with the router's 2.4GHz
    radio (BSSID ending ...33:A6) instead of 5GHz (...33:A7); both broadcast under the
    same "Wu-Tang LAN" SSID (band-steering). This capped the link at ~58 Mbit/s.
        Fix: sudo nmcli connection modify "Wu-Tang LAN" 802-11-wireless.band a
             sudo nmcli connection down "Wu-Tang LAN" && sudo nmcli connection up "Wu-Tang LAN"
        Result: connects at 5200MHz/channel 40, 130-260 Mbit/s link rate
        Optional stronger pin: sudo nmcli connection modify "Wu-Tang LAN" \
             802-11-wireless.bssid 40:47:5E:79:33:A7   (forces the exact 5GHz radio)

    Root cause #2 — weak signal at range: after switching to 5GHz, signal measured
    around -72 to -74 dBm (5GHz has shorter range/worse wall penetration than 2.4GHz).
    Server was positioned between a wall and a couch.
        Fix: physically moved the server forward, away from the wall — resolved
        remaining lag. No Ethernet run is possible (server is upstairs).

    Root cause #3 (informational, not a real problem) — periodic signal spikes:
    wifi_signal_dbm graph shows a repeating square-wave pattern (baseline ~-72/-73,
    spiking to ~-66 every few minutes). Diagnosed via:
        journalctl -u NetworkManager | grep -i "scan"
    Found: wpa_supplicant bgscan config = 'simple:30:-65:300' — background-scans every
    30s when signal is below -65 dBm, backing off to every 300s once above threshold.
    Since baseline sits below -65 dBm, the radio is almost always in the aggressive
    30s scan mode, and each scan briefly disturbs the signal reading. NOT currently
    causing playback issues — flagged as informational only.

    Local RF environment on channel 40/5200MHz: a hidden/unnamed network sharing the
    same channel was observed at -52 to -63 dBm — a real co-channel neighbor, not
    investigated further since it isn't currently causing problems.


7. WI-FI FIREWALL / NETWORKING NOTES

    Host firewall: IMPLEMENTED AND REBOOT-VALIDATED 2026-09-23. UFW remains not
    installed; do not enable it or overwrite the existing Docker/libvirt/Tailscale
    iptables-nft compatibility tables. Instead, a dedicated nftables table protects
    host-bound traffic while deliberately leaving FORWARD traffic unchanged.

        Persistent rule file: /etc/nftables-homelab-host.nft
        Boot loader: homelab-host-firewall.service (enabled; active/exited after reboot)
        Custom table: inet homelab_host
        Scope: INPUT hook only, priority filter, policy drop (IPv4 + IPv6)
        LAN allowlist: 192.168.4.0/22 to TCP 22,80,81,443,139,445,3000,3001,
                       8081,8096,9091,9100,9177; TCP/UDP 53
        Tailscale: all traffic arriving on tailscale0 accepted; UDP/41641 accepted
                    for Tailscale transport
        Other required allowances: loopback; established/related traffic; ICMP and
                    required ICMPv6; Wi-Fi DHCP client traffic; libvirt DHCP traffic
                    on virbr0/virbr10/virbr11.
        Result: unsolicited host-bound IPv4/IPv6 traffic, including direct traffic to
                the server's public IPv6 address, is dropped unless explicitly allowed.
        Deliberately NOT changed: FORWARD policy/chains, Docker-managed rules,
                libvirt-managed rules, Tailscale-managed rules, OPNsense NAT, or game
                forwarding. Docker, VMs, OPNsense, game services, and Tailscale were
                verified functional through reboot.

    Operational rules: never run `nft flush ruleset`; do not manually modify the ip,
    ip6, or nat tables marked as iptables-nft-managed; do not enable a generic
    nftables.service configuration that flushes/replaces the global ruleset. To inspect:
        sudo nft list table inet homelab_host
        sudo systemctl status homelab-host-firewall.service --no-pager

    Confirmed game-server DNAT path (matches documented plan): host iptables FORWARD
    chain ACCEPTs tcp dpt:25565 and udp dpts:16261:16262 destined for 192.168.122.24
    (OPNsense's WAN-side IP on virbr0) — from there OPNsense's own NAT/firewall rules
    hand off to the GAMES segment.


8. OPEN ITEMS / TO DO

System audit findings (from `journalctl -p err -b`, Sept 22 boot) — new, not
previously tracked:
  - amd_pstate CPU frequency-scaling driver failed to register at boot
    ("min_freq(0) or max_freq(0)... failed to register with return -19") — CPU is
    likely falling back to a different cpufreq governor (e.g. acpi-cpufreq) rather
    than amd_pstate. Worth checking `cpupower frequency-info` and whether a BIOS
    update (firmware is from 2020) resolves it.
  - dnsmasq.service previously failed to start on the unused enp34s0 interface.
    STATUS: cleared on the 2026-09-23 reboot (`systemctl --failed` returned zero units).
    Keep this under observation; no change was required during the firewall work.
  - iperf3.service failed at startup ("Failed to determine c[redentials]...", "Failed
    at step USER") — leftover from the manual iperf3 testing session; the systemd
    service has a broken user/permissions config and isn't currently functional. Safe
    to `systemctl disable iperf3` if not needed as a standing service (iperf3 can
    still be run manually/on-demand without the service).
  - systemd-networkd-wait-online timed out multiple times at boot — likely tied to
    enp34s0 sitting down/unconfigured while networkd waits for all interfaces to come
    up. Consider marking enp34s0 as optional in networkd config to stop delaying boot.
  - AMD-Vi (IOMMU) "INVALID_DEVICE_REQUEST" events logged at boot — common/generally
    benign on some AMD boards with IOMMU enabled; not currently linked to any known
    functional problem, noted for awareness only.

Storage / backups
  - SMART baseline: DONE 2026-09-22 — continue periodic short/extended tests and track
    any increase in UDMA_CRC_Error_Count (baseline 10).
  - No backup strategy yet for the Jellyfin media library or VM images/configs
  - Docker image/volume cleanup available: 9.29GB reclaimable images, 7.26GB
    reclaimable anonymous volumes

Infrastructure
  - Resolve the duplicate Pi-hole situation: instances now exist on both thomasPi
    (192.168.4.71:8053) and thomashomeserv (192.168.4.80:8081, port 53) — decide which
    is authoritative and update DHCP/NPM proxy accordingly
  - Host firewall: DONE — persistent host-only nftables INPUT policy implemented and
    reboot-validated; continue narrowing service bindings and later reduce the LAN
    allowlist as ports become unnecessary.
  - RAM: decide on 4th DIMM + speed mismatch (see section 1)

Phase 3 — Networking & Segmentation
  - GAMES segment (opn-games/virbr11): CONFIRMED working end-to-end for both
    Minecraft and PZ traffic
  - Build out remaining zones: Management, "Victim" network, "Attacker" network
  - Practice firewall rule writing between zones
  - Wireshark packet captures across segments

Phase 4 — Blue Team / Defensive
  - Suricata or Zeek (network IDS)
  - Wazuh or ELK/Elastic Stack (SIEM, log aggregation, dashboards)
  - Alternative: Security Onion
  - Practice detection engineering

Phase 5 — Red Team / Offensive
  - Kali Linux VM as attack box
  - Vulnerable targets: Metasploitable2, DVWA, VulnHub/TryHackMe-style boxes
  - Keep isolated on an internal-only network
  - Document each exercise for portfolio material

Phase 6 — Honeypot / Threat Intel
  - T-Pot or Cowrie
  - Feed honeypot logs into the SIEM

Phase 7 — Extras / Nice-to-haves
  - Vaultwarden (centralize password management across Pi + new server)
  - Uptime Kuma: DONE — still worth extending to game servers and thomasPi's services
  - Power monitoring (smart plug or Kill-A-Watt)
  - Reverse proxy: DONE — NPM migrated from thomasPi to thomashomeserv
  - Decide on auth layer for the opnsense NPM proxy host (currently unauthenticated)
  - Add Jellyfin as an NPM proxy host (currently direct IP:port access only)
  - *arr stack (Sonarr/Radarr/Prowlarr) discussed for automating Jellyfin library
    fill — not yet built
  - Performance Co-Pilot (pmcd/pmie/pmlogger) is running but not wired into any
    dashboard — decide whether to configure, integrate, or disable
