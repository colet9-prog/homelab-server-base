THOMASHOMESERV — QUICK REFERENCE GUIDE
(lean version — see homelab-network-topology.txt for full detail)


1. HARDWARE & ROLE

    Hostname: thomashomeserv
    OS: Ubuntu Server 24.04 LTS
    Role: KVM/libvirt hypervisor host + Docker host (NPM + monitoring stack — see note in section 3)
    Wired NIC: enp34s0 (onboard Realtek RTL8111/8168/8211/8411) — not using
    Wi-Fi NIC: wlp40s0 (TP-Link card + antennas) — ACTIVE
    IP forwarding: enabled (net.ipv4.ip_forward=1, net.ipv6.conf.all.forwarding=1) — required for Tailscale exit node + subnet routing


2. NETWORK ACCESS

    Home LAN (Wi-Fi, wlp40s0)
        IP: 192.168.4.80/22
        Broadcast: 192.168.7.255
        Subnet: 192.168.4.0/22 (gateway 192.168.4.1)

    Tailscale (remote access, no port-forwarding needed)
        Hostname: thomashomeserv
        Tailscale IP: 100.64.113.70
        Advertised as an exit node (replaced thomasPi in this role — Pi's Wi-Fi was unreliable)
        Reach it from anywhere on the tailnet via this IP (or hostname, once MagicDNS is confirmed working)

    SSH
        ssh thomasserver@192.168.4.80        (on home LAN)
        ssh thomasserver@100.64.113.70        (via Tailscale, from anywhere)


3. DOCKER — ON THOMASHOMESERV ITSELF

    NOTE: Minecraft and Project Zomboid do NOT run directly on thomashomeserv — they run
    inside the game-servers VM (see section 4). Only NPM runs as a container directly on
    the host.

    Nginx Proxy Manager (migrated here from thomasPi)
        Container: npm-app
        Image: jc21/nginx-proxy-manager:2.15.1
        Location: ~/npm (docker-compose.yml, ./data, ./letsencrypt)
        Ports: 80, 81 (admin UI), 443
        Admin UI: http://192.168.4.80:81
        Proxy hosts configured (all *.100.64.113.70.nip.io):
            cloud   -> 192.168.4.71:8080  (FileBrowser, on thomasPi)
            dns     -> 192.168.4.71:8053  (Pi-hole, on thomasPi)
            monitor -> 192.168.4.71:8090  (Beszel, on thomasPi)
            opnsense -> https://192.168.100.1:443 (OPNsense web UI — see section 4)
            grafana  -> http://192.168.4.80:3000 (Grafana, on thomashomeserv itself)
        NOTE: all proxy hosts are set to "Publicly Accessible" (no auth layer) — fine for
        services with their own logins, but the opnsense host in particular is a higher-
        value target and has no additional auth in front of it. Worth revisiting.

    Monitoring Stack (Prometheus + Grafana)
        Location: ~/monitoring (docker-compose.yml, prometheus.yml, ./prometheus-data, ./grafana-data)
        Containers:
            prometheus       -> prom/prometheus:latest, host port 9091 (NOT 9090 — Cockpit
                                 already owns 9090 on this box)
            grafana          -> grafana/grafana:latest, host port 3000
            node-exporter    -> prom/node-exporter:latest, network_mode: host (host system metrics)
            libvirt-exporter -> ghcr.io/inovex/prometheus-libvirt-exporter:v2.5.0, port 9177
                                 (per-VM CPU/mem/disk/network stats for opnsense-firewall and
                                 game-servers, via the libvirt socket)
        NOTE: prometheus-data and grafana-data folders must be chown'd to match each image's
        internal UID (65534 for Prometheus, 472 for Grafana) or the containers crash-loop on
        permission errors — bind-mounted folders default to your own user's ownership.
        Access: http://192.168.4.80:3000 (Grafana), also proxied via NPM (see above)


4. VIRTUAL MACHINES (KVM/libvirt)

    game-servers
        Hostname inside VM: thomashomegame
        Autostart: enabled (was disabled — fixed after it didn't survive a host reboot)
        Runs Docker containers:
            Minecraft (Java) — container: minecraft-server, image: itzg/minecraft-server,
                port 25565/tcp, connect via 192.168.4.80:25565
            Project Zomboid — container: pz-server, image: skytuna/zomboid:latest,
                ports 16261-16262/udp, connect via 192.168.4.80:16261
                IMPORTANT: docker-compose.yml volumes must use the ABSOLUTE path
                /home/thomasserver/pz-data, not ~/pz-data — sudo expands ~ to /root,
                silently mounting the wrong folder

    opnsense-firewall
        2 vCPU, 4GB RAM
        WAN -> default bridge (virbr0, 192.168.122.0/24 NAT out through host's Wi-Fi)
        LAN -> opn-lan bridge (virbr10, 192.168.100.0/24)
            Host bridge IP: 192.168.100.254 (NOT .1 — that's OPNsense's own LAN gateway IP;
            these must not match, causes intermittent unreachability)
        GAMES -> opn-games bridge (virbr11, 192.168.110.0/24), gateway 192.168.110.1
        Access:
            - SSH tunnel (ssh -L 8443:192.168.100.1:443 thomasserver@192.168.4.80,
              then https://localhost:8443) — always works, no extra config needed
            - Also reachable via NPM: https://opnsense.100.64.113.70.nip.io
              (requires OPNsense's own Alternate Hostnames list to include this domain,
              and NPM's proxy host to use a matching self-signed cert with Force SSL —
              otherwise DNS Rebind Protection / CSRF checks will block it)

    Useful commands:
        sudo virsh list --all                 -> list all VMs
        sudo virsh start <vm-name>             -> start a VM
        sudo virsh shutdown <vm-name>          -> graceful shutdown
        sudo virsh dominfo <vm-name>           -> specs/status
        sudo virsh autostart <vm-name>         -> enable autostart on boot
        sudo virsh net-list --all              -> list libvirt networks
        sudo virsh net-edit <network-name>     -> edit a network's XML (e.g. IP conflicts)
        NOTE: after editing a network's XML and running net-destroy/net-start, running
        VMs do NOT auto-reattach — a graceful virsh reboot isn't enough either; use
        virsh destroy + virsh start (hard power cycle) to force reattachment.


5. OPEN ITEMS / TO DO

Phase 3 — Networking & Segmentation
  - GAMES segment (opn-games/virbr11): CONFIRMED via testing — game-servers VM's only
    interface is opn-games (no default/direct bridge). Path: host iptables DNAT (0.0.0.0
    -> 192.168.122.24) -> OPNsense NAT port forward (WAN 25565/tcp and 16261-16262/udp ->
    192.168.110.10) -> GAMES firewall rules -> game-servers VM. Both services tested
    working end-to-end through this path.
  - Build out remaining zones: Management, "Victim" network, "Attacker" network
  - Practice firewall rule writing between zones
  - Wireshark packet captures across segments
  - Benefit: keeps game servers (exposed to friends) isolated from personal devices/lab
    if either is compromised

Phase 4 — Blue Team / Defensive
  - Suricata or Zeek (network IDS)
  - Wazuh or ELK/Elastic Stack (SIEM, log aggregation, dashboards) — pull in logs from
    the Pi's services and game servers too
  - Alternative: Security Onion (all-in-one, strong resume line)
  - Practice detection engineering: write a rule, generate matching traffic, confirm
    alert fires

Phase 5 — Red Team / Offensive
  - Kali Linux VM as attack box
  - Vulnerable targets: Metasploitable2, DVWA, VulnHub/TryHackMe-style boxes
  - Keep isolated on an internal-only network, never bridged to home LAN or game
    server zone
  - Document each exercise for portfolio material

Phase 6 — Honeypot / Threat Intel
  - T-Pot (all-in-one honeypot platform) or Cowrie (SSH/Telnet honeypot)
  - Analyze captured attack traffic/log data
  - Feed honeypot logs into the SIEM: capture -> log -> alert -> analyze

Phase 7 — Extras / Nice-to-haves
  - Vaultwarden (centralize password management across Pi + new server)
  - Uptime Kuma (monitor uptime across both boxes, including game servers)
  - Backup strategy: snapshot VMs/containers to bulk HDD or offsite
  - Power monitoring (smart plug or Kill-A-Watt) to check real-world draw against
    electric bill goals
  - Reverse proxy: DONE — Nginx Proxy Manager migrated from thomasPi to thomashomeserv
  - Decide on auth layer for the opnsense NPM proxy host (currently unauthenticated)