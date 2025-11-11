# Pterodactyl Eggs

This repository collects panel-ready [Pterodactyl](https://pterodactyl.io) eggs, helper scripts, and reference documentation for popular dedicated servers. Keep it cloned to track revisions between releases and to audit the install scripts before importing them into production panels. Some eggs reference external containers, such as `ghcr.io/newskin01/arch-fs25server:latest` from https://github.com/Newskin01/arch-fs25server, so review upstream changelogs when pinning versions.

## What's Included
- `farming_simulator_25/` - [Farming Simulator 25](https://www.farming-simulator.com) egg, Arch-based bootstrap scripts, and an install helper tailored for license-bound media uploads.

Additional eggs follow the same layout: each game folder ships its egg JSON, install script source, and a concise README.

## Quick Start
1. Clone or download this repository.
2. Import the desired egg JSON into [Pterodactyl](https://pterodactyl.io) (Admin > Nests > Eggs > Import).
3. Provision a server with the imported egg, assign allocations, and upload any required media noted in the game README.

Install scripts are self-contained and run directly inside `/home/container`, so no external downloads are required after import.

## Contribution Guidelines
1. Open an issue or discussion outlining the new egg or fix.
2. Follow the directory convention (`<game>/egg-*.json`, `install.sh`, README).
3. Validate your changes (JSON import, shellcheck, game-specific sanity tests).
4. Submit a pull request for review.

## Help
If you run into issues, open an issue with your panel version, Wings build, and egg commit hash (`git rev-parse --short HEAD`). That context makes reproducing bugs much faster.

## Resources
- Pterodactyl Project: https://pterodactyl.io
- Farming Simulator: https://www.farming-simulator.com
- GIANTS Software: https://www.giants-software.com
- Arch FS25 container source: https://github.com/Newskin01/arch-fs25server
- Prebuilt container image: `ghcr.io/newskin01/arch-fs25server:latest`

## Legal Disclaimer
This Docker container is not endorsed by, directly affiliated with, maintained, authorized, or sponsored by [GIANTS Software](https://www.giants-software.com) or the [Farming Simulator 25](https://www.farming-simulator.com) franchise. The Farming Simulator name and logo are © 2025 GIANTS Software, and the Farming Simulator 25 logo is © 2025 GIANTS Software.

## License
Unless noted otherwise inside a specific egg folder, all content in this repository is released under the MIT License (see [LICENSE](LICENSE)). Feel free to reuse or adapt the scripts for your own panels, but double-check any bundled third-party assets for their respective terms.
