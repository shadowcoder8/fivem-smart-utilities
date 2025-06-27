# FiveM Smart Utilities System

The FiveM Smart Utilities System is a comprehensive script designed to add immersive utility management (Power, Water, Internet, Trash) to your FiveM server, primarily integrating with the QBCore framework.

## Features (Overview)

*   **Power Grid Management:** Simulate power outages, manage power plants, and affect city lighting.
*   **Water System:** Control water availability, with potential for shortages or contamination events.
*   **Internet Services:** Allow players to subscribe to internet plans for their properties, upgrade tiers, and require technician router installation.
*   **Trash & Sanitation:** Implement a trash collection system with public bins, dumpsters, a depot for payouts, and fines for illegal dumping.

## Installation

1.  **Download:** Download the `smartutils` resource.
2.  **Dependencies:** Ensure you have the following dependencies installed and started *before* `smartutils`:
    *   `oxmysql` (or your preferred MySQL wrapper, adjust `fxmanifest.lua` accordingly)
    *   `qb-core`
    *   `qb-target` (Recommended for object interactions)
    *   `qb-taskbar` (Used for progress bars)
    *   (Any housing script you wish to integrate with for property data)
3.  **Database:**
    *   Import the SQL file(s) located in the `migrations/` directory into your server's database. The initial setup and any updates (like `migrations/update_schema.sql` for version 1.1.0+) are found here.
4.  **Configuration:**
    *   Review and customize `config.lua` for general settings.
    *   For the Trash module, configure zones and parameters in `config/trash_zones.lua`.
5.  **Server CFG:** Add `ensure smartutils` to your `server.cfg` file, ensuring it's placed after its dependencies.
6.  **Technician Jobs:**
    *   For the Internet module's router installation, ensure the job names listed in `client/internet.lua` (e.g., `isp_technician`, `mechanic`) match jobs in your `qb-core/shared/jobs.lua`.
    *   Consider creating a dedicated "Sanitation Worker" job for the Trash module, though it can also be used as a general player activity.

## Modules

### Internet Module

Players can manage their internet subscriptions for properties they own or have access to.

**Features:**

*   **Subscription:** Players can subscribe to different internet tiers (e.g., Basic, Premium, Ultra) via the NUI.
*   **Upgrades:** Existing subscriptions can be upgraded to higher tiers.
*   **Router Installation:**
    *   A new subscription requires a router to be installed at the property.
    *   Players with a designated technician job (configurable in `client/internet.lua`, e.g., `isp_technician`) can use the `/installinternet [propertyId]` command when near the property.
    *   The command places a router prop and simulates installation using an animation and taskbar.
    *   The router's position is saved per property.
*   **NUI Dashboard (`/openinternetmenu`):**
    *   Lists properties associated with the player.
    *   Shows current subscription status and tier.
    *   Provides options to subscribe or upgrade.
    *   Indicates if router installation is pending.

**Configuration:**

*   Internet tiers and technician jobs are primarily configured within `client/internet.lua` and `server/internet.lua` (e.g., tier details, job names).
*   Ensure your housing script provides a way to identify `propertyId` which is used by this module. The current implementation uses a placeholder `getPlayerProperties` function in `server/internet.lua` that needs to be adapted to your specific housing system to correctly list player properties in the NUI.

### Trash & Sanitation Module

This module introduces a system for trash collection and disposal.

**Features:**

*   **Trash Zones:**
    *   **Public Bins & Dumpsters:** Players can collect trash from these designated zones. Zone locations, types, and capacities are defined in `config/trash_zones.lua`.
    *   **Trash Depot:** A central location where players bring collected trash for payment.
*   **Trash Collection:**
    *   Players interact with bins/dumpsters (default: `E` key when nearby) to collect trash.
    *   Collected trash adds to the player's `currentTrashLoad`.
    *   `qb-taskbar` is used to simulate collection time.
*   **Dumping Trash:**
    *   Use the `/dumptrash` command or press `G` (default) when at the depot's drop-off zone.
    *   Payouts are based on the amount of trash and the `payoutPerUnit` rate in `config/trash_zones.lua`.
*   **Illegal Dumping:**
    *   Using `/dumptrash` outside of the designated depot zone results in a fine.
    *   The fine amount is configurable in `config/trash_zones.lua`.
    *   Illegal dumping activity is logged and can trigger alerts (placeholder for police/dispatch integration).
*   **Player Capacity:** Players have a maximum trash carrying capacity (`Config.TrashCollection.MaxCarryWeight`).
*   **Logging:** Trash collection and fines are logged in the `trash_log` database table.

**Configuration (`config/trash_zones.lua`):**

*   `Config.TrashZones.EnableDebug`: Set to `true` to draw visual markers for all defined zones in-game (useful for setup).
*   `Config.TrashZones.PublicBins`: Define coordinates, radius, type, and capacity for public trash bins.
*   `Config.TrashZones.Dumpsters`: Define larger dumpsters similarly.
*   `Config.TrashZones.Depot`:
    *   `dropOffCoords` & `dropOffRadius`: Area for legal trash dumping.
    *   `payoutPerUnit`: Monetary reward per unit of trash.
    *   `startJobCoords`, `jobVehicles`, `jobVehicleSpawnPoint`: Placeholders/examples for integrating with a formal job system.
*   `Config.TrashCollection`:
    *   `MaxCarryWeight`: Max trash a player can carry.
    *   `CollectionTime`: Duration for the taskbar when collecting.
    *   `FineForIllegalDumping`: Penalty amount.
    *   `IllegalDumpCooldown`: Time before another fine can be issued.
    *   `MinTrashToDump`: Minimum amount required to dump at the depot.

**Commands:**

*   `/openinternetmenu`: Opens the Internet Service Management NUI.
*   `/installinternet [propertyId]`: (Technician Job Only) Installs an internet router at the specified property.
*   `/dumptrash`: Dumps collected trash. Behavior depends on whether the player is at the depot or not.

## Future Enhancements / TODO

*   Full integration with specific housing scripts for property data.
*   Server-side synchronization of bin/dumpster fill levels.
*   NUI for the Trash module (e.g., displaying current load, nearby bin status).
*   Deeper job system integration for both Internet Technicians and Sanitation Workers (e.g., assigned tasks, vehicle management, clocking in/out).
*   Visual feedback for bin status (e.g., prop changes when full).
*   Animations for collecting and dumping trash.

## Troubleshooting

*   **NUI Not Opening:** Ensure `ui_page` in `fxmanifest.lua` is correct and the HTML/JS/CSS files are listed under `files`. Check for client-side errors (F8 console).
*   **Commands Not Working:** Verify the commands are registered correctly in client/server scripts and there are no conflicting commands.
*   **Database Errors:** Ensure `oxmysql` is running and the SQL files have been imported correctly. Check `player_internet` and `trash_log` table structures.
*   **Incorrect Payouts/Fines:** Double-check values in `config/trash_zones.lua`.
*   **Performance:** Monitor resmon values. If high, check for inefficient loops or frequent events.

This README provides a basic guide. Further customization and integration may be required depending on your specific server setup and other resources in use.
test
