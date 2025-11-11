# Pterodactyl Eggs

This repository collects panel-ready Pterodactyl eggs, helper scripts, and reference documentation. Keep it cloned to track revisions between releases and to audit the install scripts before importing them into production panels. Some eggs reference external containers, such as `ghcr.io/newskin01/arch-fs25server:latest` from https://github.com/Newskin01/arch-fs25server, so review upstream changelogs when pinning versions.

## What's Included
- `farming_simulator_25/` - Farming Simulator 25 egg, Arch-based bootstrap scripts, and an install helper tailored for license-bound media uploads.

Additional eggs follow the same layout: each game folder ships its egg JSON, install script source, and a concise README.

## Quick Start
1. Clone or download this repository.
2. Import the desired egg JSON into Pterodactyl (Admin > Nests > Eggs > Import).
3. Provision a server with the imported egg, assign allocations, and upload any required media noted in the game README.

Install scripts are self-contained and run directly inside `/home/container`, so no external downloads are required after import.

## Contribution Guidelines
1. Open an issue or discussion outlining the new egg or fix.
2. Follow the directory convention (`<game>/egg-*.json`, `install.sh`, README).
3. Validate your changes (JSON import, shellcheck, game-specific sanity tests).
4. Submit a pull request for review.

## Help
If you run into issues, open an issue with your panel version, Wings build, and egg commit hash (`git rev-parse --short HEAD`). That context makes reproducing bugs much faster.
