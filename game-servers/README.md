# game-servers

These run inside the game-servers VM (192.168.110.10, GAMES zone behind OPNsense), not on the host.
Both are shut down for now (Project Zomboid since 2026-10-26, Minecraft since 2026-10-27).

- Stop Minecraft: `docker stop -t 60 minecraft-server` (it is not part of the pz compose project, so `compose down` does not touch it)
- Start it again: `docker start minecraft-server`
- A cron entry in the VM pings Uptime Kuma while pz-server is running (push URL not committed).
