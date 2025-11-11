# Farming Simulator 25 Egg

This egg packages the Arch-based `ghcr.io/newskin01/arch-fs25server:latest` container (source: https://github.com/Newskin01/arch-fs25server) with custom bootstrap scripts so [Farming Simulator 25](https://www.farming-simulator.com) can run cleanly on most [Pterodactyl](https://pterodactyl.io) panels. Import the JSON, upload your licensed media from [GIANTS Software](https://www.giants-software.com), and the server handles the rest.

## Highlights
- Media-aware startup that waits for `FarmingSimulator2025.exe` instead of crashing.
- Health log emits `FS25_HEALTHCHECK=PASS` for easy panel readiness detection.
- Cloudflare-friendly default ports and an opt-in web admin shortcut patcher.
- Bootstrap + install scripts live under `/home/container` for easy audit and customization.

## Requirements
- Pterodactyl 1.11+ with Wings running on an x86_64 host.
- Docker access to `ghcr.io/newskin01/arch-fs25server:latest` (or your overridden tag).
- 40 GB+ disk, 8 GB RAM, and a Farming Simulator 25 dedicated server license.
- Ability to upload installer media via the panel file manager or SFTP.
- A panel mount (Admin > Mounts) that binds `/var/lib/pterodactyl/mounts/fs25_config` to `/config` inside the container. Set `Read Only = false`, `User Mountable = true`, and use the same mount on every FS25 server so Giants configuration survives rebuilds.

## Repository Contents
| File | Purpose |
|------|---------|
| `egg-fs25-arch.json` | Importable egg definition referencing the bootstrap/start scripts. |
| `install.sh` | Source-friendly copy of the install script bundled inside the egg. |

## Quick Install
1. Download `farming_simulator_25/egg-fs25-arch.json`.
2. Pterodactyl panel (https://pterodactyl.io) > Admin > Nests > Eggs > Import Egg > upload the JSON.
3. Create a new server using the imported egg, pick an allocation, attach the `/config` mount (`/var/lib/pterodactyl/mounts/fs25_config` -> `/config`), and finish the wizard.
4. Start the server once so the install script lays down `/home/container/fs-data` and helper files.
5. Upload your `FarmingSimulator2025*.exe` installer (and optional DLC executables) into `/home/container/fs-data/installer` and `/home/container/fs-data/dlc`.
6. Restart the server; the bootstrap script detects the media and launches the Giants dedicated server UI automatically.

## Media Checklist
1. Download the official installer plus DLC from your GIANTS account.
2. Upload the base installer to `/home/container/fs-data/installer/`.
3. Upload DLC installers to `/home/container/fs-data/dlc/`.
4. Watch the console - once the files land, logs switch from `MEDIA PENDING` to `Installer detected` and the game boots.

## Key Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | `FS25 Server` | Writes the visible server name into `dedicatedServerConfig.xml`. |
| `SERVER_PORT` | `10823` | Primary gameplay port (TCP/UDP). |
| `WEB_PORT` | `8443` | Giants web admin UI; bootstrap patches shortcuts + config to match. |
| `WEB_SCHEME` | `http` | Switch to `https` if you terminate TLS elsewhere. |
| `AUTO_START_FS25` | `no` | `yes` auto-launches the dedicated server UI on boot. |
| `ENABLE_STARTUP_SCRIPTS` | `no` | `yes` runs user-provided scripts from `/home/container/scripts/startup.d`. |

All other fields visible in the egg follow Pterodactyl defaults, so feel free to extend them per deployment.

## Default Ports
| Purpose | Container Port |
|---------|----------------|
| Gameplay (TCP/UDP) | 10823 |
| Web admin | 8443 |

Expose 10823 as your primary allocation and forward 8443 through your proxy/CDN if you need browser access to the Giants panel.

## Support
Need help, runbooks, or a tweak for a different distro? Open an issue with your panel version, Wings build, and recent console logs so maintainers can reproduce the environment quickly.

## Additional Resources
- Farming Simulator franchise: https://www.farming-simulator.com
- GIANTS Software support: https://www.giants-software.com
- Pterodactyl documentation: https://pterodactyl.io
- Container source repository: https://github.com/Newskin01/arch-fs25server
- Container image registry: `ghcr.io/newskin01/arch-fs25server:latest`
