fx_version 'cerulean'
game 'gta5'

author 'Google Jules AI'
description 'FiveM Smart City Utilities System'
version '1.1.0' -- Incremented version

lua54 'yes'

shared_scripts {
    '@qb-core/shared/locale.lua', -- Common QBCore locale
    'config.lua',
    'config/trash_zones.lua', -- Added
    'utils/logger.lua'
}

client_scripts {
    'client.lua',
    'client/internet.lua', -- Added
    'client/trash.lua'     -- Added
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'server/internet.lua', -- Added
    'server/trash.lua'     -- Added
}

ui_page 'html/internet.html' -- Updated to internet.html as the primary UI

files {
    -- Existing files (assuming still needed or for other modules)
    'html/index.html',
    'html/style.css',
    'html/script.js',

    -- New files for Internet NUI
    'html/internet.html',
    'html/internet.css',
    'html/internet.js',

    'images/*' -- If you have images for the UI
}

-- Optional: exports for other resources to use
exports {
  'DoesPlayerHaveInternet' -- Client-side: Checks if the player's current internet service is active
  -- Add any new client exports if needed
}

server_exports {
  'IsPowerZoneBlackout',
  'GetPowerZoneStatus',
  'IsInternetHubDown',
  'GetInternetHubStatus',
  'HasPropertyInternetService',
  'GetPropertyInternetServiceDetails'
  -- Add any new server exports if needed
}

dependencies {
    'oxmysql', -- Ensure oxmysql is started before this resource
    'qb-core'  -- Added QBCore dependency
}

-- Ensure this resource starts after essential QBCore resources if not handled by qb-core dependency itself
-- ensure 'qb-target'
-- ensure 'qb-taskbar'
-- etc.
-- These are often better handled by server startup CFG order or explicit dependencies in qb-core if it loads them.

-- Define SQL file for database migrations (if framework supports it, e.g. Grapeshot/RedM frameworks)
-- For QBCore, SQL is typically handled manually or via qb-core's startup.
-- If using a framework that auto-runs SQL:
-- install_sql 'migrations/update_schema.sql'
-- For QBCore, ensure 'update_schema.sql' is in qb-core/shared/sql or run manually.
