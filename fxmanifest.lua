fx_version 'cerulean'
game 'gta5'

author 'Google Jules AI'
description 'FiveM Smart City Utilities System'
version '1.0.0'

lua54 'yes'

shared_scripts {
    'config.lua',
    'utils/logger.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Assuming oxmysql is installed and this is the correct path
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'images/*' -- If you have images for the UI
}

-- Optional: exports for other resources to use
exports {
  'DoesPlayerHaveInternet' -- Client-side: Checks if the player's current internet service is active
}

server_exports {
  'IsPowerZoneBlackout',
  'GetPowerZoneStatus',
  'IsInternetHubDown',
  'GetInternetHubStatus',
  'HasPropertyInternetService',
  'GetPropertyInternetServiceDetails'
  -- Add other server exports here if needed, e.g., for water levels, trash info etc.
}

dependencies {
    'oxmysql' -- Ensure oxmysql is started before this resource
}
