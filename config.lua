Config = {}

Config.Framework = 'qb-core' -- 'qb-core' or 'esx' - For framework specific functions like notifications

Config.Debug = true -- Enable debug logging

-- NUI Tablet Config
Config.Tablet = {
    Command = "utilities", -- Command to open the tablet
    Key = "F6", -- Key to open the tablet (uses FiveM Key Mapping https://docs.fivem.net/docs/game-references/input-mapper-parameter-ids/keyboard/)
    CloseOnEscape = true, -- Close tablet with ESC key
    AdminOnly = false, -- Restrict tablet access to admins only (requires admin group check)
    AdminGroups = {"admin", "mod"} -- Admin groups that can access restricted parts or all of tablet
}

-- Power Module
Config.Power = {
    Enabled = true,
    Zones = {
        ['Downtown'] = {
            label = "Downtown Power Grid",
            coords = vector3(130.55, -750.62, 45.74), -- Example: Near a known substation area
            radius = 700.0,
            isBlackout = false, -- Initial state, will be managed by server.lua state
            canBeSabotaged = true,
            repairCost = 5000,
            sabotageDifficulty = 5, -- Example: 1-10 scale for minigame
            affectedEntities = {
                trafficLights = true, -- Will try to integrate with qb-trafficlights or similar
                atms = true,
                streetLights = true, -- Generic, actual control might be complex
                buildings = {} -- list specific building identifiers if needed
            }
        },
        ['Rockford'] = {
            label = "Rockford Hills Power Station",
            coords = vector3(-550.25, 60.70, 55.90), -- Example: Near another substation
            radius = 600.0,
            isBlackout = false,
            canBeSabotaged = true,
            repairCost = 4500,
            sabotageDifficulty = 4,
            affectedEntities = { trafficLights = true, atms = true, streetLights = true }
        },
        ['SandyShores'] = {
            label = "Sandy Shores Substation",
            coords = vector3(1750.10, 3700.50, 35.15), -- Example
            radius = 800.0,
            isBlackout = false,
            canBeSabotaged = true,
            repairCost = 3000,
            sabotageDifficulty = 3,
            affectedEntities = { trafficLights = false, atms = true, streetLights = true } -- Sandy might not have controlled traffic lights
        }
    },
    GlobalBlackoutCommand = "forceglobalblackout", -- Admin command
    ZoneBlackoutCommand = "forcezoneblackout", -- Admin command: /forcezoneblackout <zoneName> <duration_optional_seconds>
    RepairCommand = "repairpower", -- Admin command: /repairpower zoneName
    Sabotage = {
        Enabled = true,
        Cooldown = 3600, -- Seconds between sabotage attempts on the same substation
        PoliceAlert = true, -- Alert police if sabotage is attempted/successful
        RequiredItems = { -- Items needed to attempt sabotage (item name, count)
            -- {name = "advanced_hacking_kit", count = 1},
            -- {name = "thermite_charge", count = 1}
        },
        MinPoliceOnline = 2,
    },
    BlackoutDuration = {min = 300, max = 900}, -- seconds
    RepairTime = {min = 180, max = 420}, -- seconds for player-initiated repairs (if implemented)
    AutoRepairTime = {min = 600, max = 1200}, -- seconds for automatic repairs if no player intervenes
    TrafficLightControllingResource = "qb-trafficlights", -- Name of the resource that controls traffic lights, if any
    Notifications = {
        PowerOutage = "Power outage in ~r~{zone}~s~!",
        PowerRestored = "Power restored in ~g~{zone}~s~.",
        SabotageAttempt = "A sabotage attempt is underway at the ~y~{zone}~s~ substation!",
        SabotageSuccess = "The ~y~{zone}~s~ substation has been sabotaged!",
    }
}

-- Water Module
Config.Water = {
    Enabled = true,
    Sources = {
        ['LandActReservoir'] = {
            label = "Land Act Reservoir",
            coords = vector3(-393.0, 2976.0, 12.0), -- Actual reservoir location
            capacity = 5000000, -- Liters
            currentLevel = 4000000, -- Liters (initial state, managed by server)
            refillRatePerTick = 500, -- Liters per server tick (e.g., every 5 mins)
            alertThreshold = 0.25, -- Alert when level drops below 25%
            canHaveLeaksNearby = true, -- Can leaks spawn associated with this source's area?
            leakSpawnRadius = 1500.0 -- Radius around coords where leaks might occur related to this source
        },
        ['VinewoodHillsReservoir'] = {
            label = "Vinewood Hills Water Tower",
            coords = vector3(-1475.0, -50.0, 55.0), -- A water tower example
            capacity = 1000000,
            currentLevel = 800000,
            refillRatePerTick = 200,
            alertThreshold = 0.30,
            canHaveLeaksNearby = true,
            leakSpawnRadius = 1000.0
        }
    },
    TickInterval = 300000, -- How often server-side water ticks occur (e.g., consumption, refills, leak checks) in ms (300000 = 5 minutes)
    LeakChancePerTick = 0.05, -- 5% chance of a new leak occurring somewhere on the map per tick (if below max leaks)
    MaxActiveLeaks = 5, -- Max number of concurrent water leaks on the map
    LeakLocationRadius = 50.0, -- Radius around a leak's coords where effects/interactions occur
    LeakRepairTime = {min = 120, max = 240}, -- Seconds for a player to repair a leak (minigame duration or fixed time)
    LeakAutoDespawnTime = {min = 3600, max = 7200}, -- Seconds for a leak to despawn if not fixed (1-2 hours)
    RepairLeakCommand = "repairwaterleak", -- Admin command: /repairwaterleak <leakId or 'all'>
    PuddleEffect = {
        Enabled = true,
        ParticleDict = "core", -- "core" is a common one, but might need specific testing
        ParticleName = "ent_amb_water_spout", -- Example particle, "ent_amb_water_leak_lg" is also good
        Scale = 1.5
    },
    WaterTheft = {
        Enabled = true, -- Feature toggle for water theft mechanics
        PoliceAlert = true,
        RequiredItems = { -- Items for water theft
            -- {name = "water_pump", count = 1},
            -- {name = "empty_water_tanker", count = 1}
        },
        MinPoliceOnline = 1,
    },
    Billing = {
        Enabled = true,
        CycleDays = 7, -- Billing cycle in in-game days
        PricePerUnit = 0.05, -- Price per liter or defined unit
        PropertyBased = true -- Link bills to properties (requires integration with housing script)
    },
    Notifications = {
        NewLeak = "A water leak has been detected near ~b~{location}~s~!",
        LeakRepaired = "The water leak near ~g~{location}~s~ has been repaired.",
        WaterTheftAttempt = "An attempt to steal water is in progress at ~b~{location}~s~!",
        LowWaterWarning = "Water levels at ~y~{source}~s~ are critically low!"
    }
}

-- Internet Module
Config.Internet = {
    Enabled = true,
    Hubs = {
        ['LS_MainExchange'] = {
            label = "Los Santos Main Exchange",
            coords = vector3(-188.0, -580.0, 35.0), -- Example location (near a FIB building or similar)
            maxConnections = 5000, -- Max properties/users this hub can service
            isDown = false, -- Initial state, managed by server
            canBeHacked = true,
            hackingDifficulty = 7, -- Example: 1-10 scale
            repairCost = 10000
        },
        ['PaletoBayHub'] = {
            label = "Paleto Bay Regional Hub",
            coords = vector3(-250.0, 6200.0, 32.0), -- Example
            maxConnections = 500,
            isDown = false,
            canBeHacked = true,
            hackingDifficulty = 5,
            repairCost = 3000
        }
    },
    TickInterval = 450000, -- How often server-side internet ticks occur (e.g., check hub status) in ms (450000 = 7.5 minutes)
    ServiceTiers = {
        basic = {label = "Basic ADSL", speed = "25/5 Mbps", price = 75, installTime = 300, dataCapGB = 100 }, -- installTime in seconds
        standard = {label = "Standard Cable", speed = "100/20 Mbps", price = 120, installTime = 450, dataCapGB = 500 },
        premium = {label = "Premium Fiber", speed = "500/100 Mbps", price = 200, installTime = 600, dataCapGB = 0 }, -- 0 for unlimited
        business = {label = "Business Fiber", speed = "1000/500 Mbps", price = 350, installTime = 900, dataCapGB = 0 }
    },
    PlayerSubscriptionDBTable = "player_internet_subscriptions", -- DB table name for storing player subscriptions
    InstallationJob = {
        Enabled = true, -- Set to true to require a job for installations
        JobName = "technician", -- Example job name, ensure this job exists in your framework
        RequiredItems = { -- Items consumed by technician for installation
            -- {name = "modem_item", count = 1},
            -- {name = "fiber_cable_roll", count = 1}
        }
    },
    Hacking = {
        Enabled = true,
        PoliceAlert = true,
        RequiredItems = {
            -- {name = "advanced_hacking_device", count = 1}
        },
        MinPoliceOnline = 2,
        Cooldown = 7200, -- Cooldown for hacking a hub
        OutageDuration = {min = 300, max = 900} -- How long internet stays down after successful hack
    },
    AffectedServices = { -- Services that require internet
        CCTV = true,
        ATMs = true, -- Some ATMs might require internet
        BankTransactions = true,
        StockMarket = true -- If you have a stock market script
    },
    Notifications = {
        InternetDown = "Internet service is down in ~r~{area}~s~ due to an outage at ~y~{hub}~s~.",
        InternetRestored = "Internet service has been restored in ~g~{area}~s~.",
        InstallRequest = "A request for internet installation has been submitted for your property.",
        InstallComplete = "Internet ~b~{tier}~s~ has been successfully installed at your property."
    }
}

-- Trash & Sanitation Module
Config.Trash = {
    Enabled = true,
    TickInterval = 600000, -- How often server-side trash ticks occur (e.g., check bin fullness, schedule) in ms (600000 = 10 minutes)
    CollectionJob = {
        Enabled = true,
        JobName = "sanitation",
        VehicleModel = "trash",
        PayPerBag = 5,          -- Payment for collecting a small trash bag prop
        PayPerPublicBin = 20,   -- Payment for emptying a public bin
        PayPerLargeDumpster = 50, -- Payment for emptying a large dumpster (e.g. at businesses)
        WeightBonus = 0.05,      -- Extra $ per simulated Kg of trash
        InteractionRadius = 2.5, -- Radius to interact with trash bags/bins
        TrashBagItem = "trash_bag_filled", -- Item given/checked when collecting bags (if using items)
        MaxCarryableBags = 5,     -- If players carry bags as items before depositing in truck
    },
    IllegalDumping = {
        Enabled = true,
        FineAmount = 500,
        PoliceAlert = true,
        ReportCommand = "reportdumping",
        CleanupTime = {min = 1800, max = 3600}, -- Seconds for dumped trash (props) to despawn if not cleaned by players
        DumpableItems = { -- List of item names that are considered illegal dumping if dropped (requires inventory integration)
            "trash_bag_filled", "rottenflesh_item", "broken_tv_item"
            -- These are example item names. Your inventory script would trigger an event when items are dropped.
        },
        MinItemsToFine = 2, -- Minimum number of dumpable items dropped at once to trigger fine/alert
    },
    PublicBins = { -- Define specific, interactable public trash bin locations
        -- Bins will have unique IDs generated based on their coordinates or a defined ID.
        -- State (currentLoad) will be managed server-side.
        { id = "bin_legionsquare_1", coords = vector3(205.0, -945.0, 30.0), capacity = 100, heading = 90.0, model = `prop_bin_07a` },
        { id = "bin_vespucci_beach_1", coords = vector3(-1700.0, -1050.0, 2.5), capacity = 150, heading = 0.0, model = `prop_bin_08a` },
        -- Add more bins here
    },
    LargeDumpsters = { -- Similar to public bins, but larger capacity, different pay
        { id = "dumpster_burgershot_1", coords = vector3(300.0, -900.0, 29.5), capacity = 500, heading = 180.0, model = `prop_dumpster_01a`},
    },
    CollectionSchedule = {
        Enabled = false, -- If true, server will periodically "empty" bins if no player job activity
        IntervalHours = 12,
    },
    Notifications = {
        DumpingDetected = "Illegal dumping detected near ~y~{location}~s~! A fine of ${amount} has been issued.",
        CollectionShiftStart = "The sanitation department is starting its collection rounds.",
        BinFull = "A public trash bin at ~y~{location}~s~ is full and needs collection!",
        TrashCollected = "You collected trash and earned ${amount}.",
        VehicleFull = "Your sanitation vehicle is full. Please empty it at the depot."
    },
    DepotLocation = vector3(720.0, -1600.0, 29.0) -- Example location for sanitation depot to empty trucks
}

-- Admin Commands Configuration (permissions handled by your admin script, e.g., qb-adminmenu)
Config.Admin = {
    ForceBlackout = { Command = "forceblackout", Group = "admin" }, -- /forceblackout <zoneName> [duration_seconds]
    RepairPower = { Command = "repairpower", Group = "admin" }, -- /repairpower <zoneName>
    ForceWaterLeak = { Command = "forcewaterleak", Group = "admin" }, -- /forcewaterleak <sourceName or random> [duration_seconds]
    RepairWaterLeak = { Command = "repairwaterleak", Group = "admin" }, -- /repairwaterleak <leakId>
    ForceInternetOutage = { Command = "forceinternetoutage", Group = "admin" }, -- /forceinternetoutage <hubName> [duration_seconds]
    RepairInternet = { Command = "repairinternet", Group = "admin" }, -- /repairinternet <hubName>
    SpawnTrash = { Command = "spawntrash", Group = "admin" }, -- /spawntrash <amount> [location_coords_json_optional]
    ClearAllTrash = { Command = "clearalltrash", Group = "admin" }
}

-- Function to be called for notifications, adaptable to QB or ESX
-- Ensure your framework (QBCore/ESX) is correctly identified in Config.Framework
function ShowNotification(message, messageType, duration)
    if Config.Framework == 'qb-core' and QBCore and QBCore.Functions and QBCore.Functions.Notify then
        QBCore.Functions.Notify(message, messageType or "primary", duration or 5000)
    elseif Config.Framework == 'esx' and ESX and ESX.ShowNotification then
        ESX.ShowNotification(message, messageType or "info", duration or 5000) -- ESX types might be 'info', 'error', 'success'
    else
        -- Fallback for standalone or if framework functions are not found
        print(("[SmartUtilities] NOTIFICATION: %s (Type: %s, Duration: %s ms)"):format(message, messageType or 'N/A', duration or 'N/A'))
        -- For client-side, you could use a native FiveM notification as a fallback:
        -- if IsDuplicityVersion() then -- Check if client side
        --    SetNotificationTextEntry("STRING")
        --    AddTextComponentString(message)
        --    DrawNotification(false, true)
        -- end
    end
end

-- Function to check if player has required items (client-side or server-side via trigger)
-- This is a placeholder; you'll need to implement item checking based on your inventory script.
function HasRequiredItems(source, items)
    if not source or not items then return false end
    if type(items) == "table" and #items == 0 then return true end -- No items required
    
    -- Convert single item to table format
    if type(items) == "string" then
        items = {{name = items, count = 1}}
    elseif items.name then
        items = {items}
    end
    
    if Config.Framework == 'qb-core' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        
        for _, itemInfo in ipairs(items) do
            local itemName = itemInfo.name or itemInfo
            local itemCount = itemInfo.count or 1
            
            -- Check player inventory
            local hasItem = false
            local currentAmount = 0
            
            if Player.PlayerData.items then
                for _, item in pairs(Player.PlayerData.items) do
                    if item and item.name == itemName then
                        currentAmount = currentAmount + (item.amount or 0)
                    end
                end
            end
            
            if currentAmount >= itemCount then
                hasItem = true
            end
            
            if not hasItem then
                ShowNotification(source, "You are missing required items: " .. itemName .. " (x" .. itemCount .. ")", "error")
                return false
            end
        end
        return true
        
    elseif Config.Framework == 'esx' then
        local ESX = exports.esx:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(source)
        if not xPlayer then return false end
        
        for _, itemInfo in ipairs(items) do
            local itemName = itemInfo.name or itemInfo
            local itemCount = itemInfo.count or 1
            local item = xPlayer.getInventoryItem(itemName)
            
            if not item or item.count < itemCount then
                ShowNotification(source, "You are missing required items: " .. itemName .. " (x" .. itemCount .. ")", "error")
                return false
            end
        end
        return true
        
    elseif GetResourceState('ox_inventory') == 'started' then
        -- ox_inventory support
        for _, itemInfo in ipairs(items) do
            local itemName = itemInfo.name or itemInfo
            local itemCount = itemInfo.count or 1
            local count = exports.ox_inventory:GetItemCount(source, itemName)
            
            if count < itemCount then
                ShowNotification(source, "You are missing required items: " .. itemName .. " (x" .. itemCount .. ")", "error")
                return false
            end
        end
        return true
    else
        Logger.Warn("No supported inventory system found for item checking")
        return true -- Default to true if no system available
    end
end

-- Function to remove items (server-side)
function RemovePlayerItems(source, items)
    if not items or #items == 0 then return true end

    if Config.Framework == 'qb-core' and QBCore and QBCore.Functions then
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player then return false end
        for _, itemInfo in ipairs(items) do
            Player.Functions.RemoveItem(itemInfo.name, itemInfo.count)
        end
        return true
    elseif Config.Framework == 'esx' then
        -- ESX item removal logic here
        -- local xPlayer = ESX.GetPlayerFromId(source)
        -- for _, itemInfo in ipairs(items) do
        --    xPlayer.removeInventoryItem(itemInfo.name, itemInfo.count)
        -- end
        return true
    end
    print("[SmartUtilities] Warning: Item removal not implemented for the current framework.")
    return false
end

-- Placeholder for job check
function HasJob(source, jobName)
    if not jobName then return true end -- No specific job required

    if Config.Framework == 'qb-core' and QBCore and QBCore.Functions then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player.PlayerData.job.name == jobName
    elseif Config.Framework == 'esx' then
        -- local xPlayer = ESX.GetPlayerFromId(source)
        -- return xPlayer.job.name == jobName
        return false -- Placeholder
    end
    return false -- Default to false if no job system found
end

-- Placeholder for admin group check (server-side)
function IsAdmin(source, groups)
    if not Config.Tablet.AdminOnly and (not groups or #groups == 0) then return true end -- Not admin only or no specific groups defined

    local targetGroups = groups or Config.Tablet.AdminGroups
    if Config.Framework == 'qb-core' and QBCore and QBCore.Functions then
        local Player = QBCore.Functions.GetPlayer(source)
        -- QBCore permission check logic (e.g., Player.PlayerData.job.name == 'police' and Player.PlayerData.job.grade.level >= someLevel)
        -- Or more commonly, using ACE permissions if your admin script sets them up.
        -- This example assumes a simple group check from player metadata if available, or ACEs.
        for _, groupName in ipairs(targetGroups) do
            if IsPlayerAceAllowed(source, "command." .. groupName) or Player.PlayerData.job.name == groupName then -- Example ACE check
                 return true
            end
        end
        -- A more direct QBCore group check might involve checking Player.PlayerData.metadata['permission'] or similar,
        -- depending on how your server handles permissions.
        -- For simplicity, often people check job name for roles like 'admin' or 'police'.
        -- If you use qb-adminmenu, it often relies on ACE perms like "command.add_principal".
        -- A common way to check for general admin perms:
        if IsPlayerAceAllowed(source, "command") then -- General command ACE
            -- You might want more specific ACEs like "smartutilities.admin"
            -- For now, let's assume if they have any admin group from the list via job or a direct ACE perm.
            -- Example: if Player.Functions.IsAdmin() -- if such a helper exists in your QBCore.
        end

    elseif Config.Framework == 'esx' then
        -- ESX permission check (e.g., xPlayer.getGroup())
        -- local xPlayer = ESX.GetPlayerFromId(source)
        -- local playerGroup = xPlayer.getGroup()
        -- for _, groupName in ipairs(targetGroups) do
        --    if playerGroup == groupName then
        --        return true
        --    end
        -- end
        return false -- Placeholder
    end
    -- Fallback if no framework specific check, or if you want a simple ACE check.
    -- This requires you to set up ACEs like: add_ace group.admin smartutilities.admin allow
    for _, groupName in ipairs(targetGroups) do
        if IsPlayerAceAllowed(source, "smartutilities." .. groupName) then
            return true
        end
    end

    ShowNotification(source, "You do not have permission to do this.", "error")
    return false
end

-- Returns the QBCore shared object if available
function GetQBCore()
    if Config.Framework == 'qb-core' then
        return exports['qb-core']:GetCoreObject()
    end
    return nil
end

-- On script start, try to get QBCore object if configured
if Config.Framework == 'qb-core' then
    QBCore = exports['qb-core']:GetCoreObject()
    if QBCore then
        print("[SmartUtilities] QBCore object loaded.")
    else
        print("[SmartUtilities] ERROR: QBCore object failed to load. Ensure qb-core is started and exports GetCoreObject.")
    end
end

-- ESX shared object (usually just ESX = nil on server, then triggered from client or use server callback)
-- For server-side ESX, you typically use ESX.GetPlayerFromId(source) after an event.
-- ESX = nil
-- TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end) -- This is more for client side.
-- Server-side, you'd typically include ESX server files or ensure it's loaded.

print("[SmartUtilities] Configuration loaded. Debug: " .. tostring(Config.Debug))
print("[SmartUtilities] Framework: " .. Config.Framework)
