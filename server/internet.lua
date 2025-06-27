local QBCore = exports['qb-core']:GetCoreObject()

-- Helper function to get player's properties (placeholder)
-- In a real scenario, this would integrate with your housing script.
-- For now, it might return a list of properties the player is associated with,
-- or we might assume properties are identified by a unique ID that the player knows or owns.
local function getPlayerProperties(playerId)
    -- Example: Fetch properties owned by the player's citizenid
    -- This is highly dependent on your housing system.
    -- For demonstration, let's assume we have a table `player_houses`
    -- with `citizenid` and `property_id` (or house name/label).
    -- If you pass property IDs directly from client that player owns, this function might not be needed here.
    -- For this example, let's assume the client NUI will be populated based on properties the player owns.
    local citizenid = QBCore.Functions.GetPlayer(playerId).PlayerData.citizenid
    local properties = {}
    --[[
    local result = MySQL.Sync.fetchAll("SELECT property_id, property_address FROM player_properties WHERE citizenid = ?", {citizenid})
    if result then
        for _, v in ipairs(result) do
            table.insert(properties, { propertyId = v.property_id, address = v.property_address })
        end
    end
    -- For testing, let's add some mock properties if the above is not set up
    if #properties == 0 then
        properties = {
            { propertyId = "dev_property_1", address = "123 Dev Street" },
            { propertyId = "dev_property_2", address = "456 Coder Avenue" }
        }
    end
    --]]
    -- Simplified: Assuming property IDs are managed and known by the client/player for now.
    -- The NUI will receive a list of property IDs the player has some association with.
    -- For this system, we care more about the *internet status* of those properties.
    -- So, the client will request data for specific properties, or we fetch all known to the player.
    -- Let's assume for now the client will manage which properties it's interested in or the housing script provides this.

    -- We will fetch internet status for properties the player *could* manage.
    -- For now, this function will just be a placeholder. The actual property list might come from a housing script.
    -- Let's assume we have a way to get these property identifiers.
    -- For the NUI, we will construct a list of properties the player owns.
    -- This will be a simplified version for now.
    local exampleProperties = {
        { propertyId = QBCore.Functions.GetPlayer(playerId).PlayerData.citizenid .. "_home1", address = "My Primary Residence" },
        { propertyId = "shared_apt_complex_a_unit_101", address = "Apartment 101A" }
    }
    -- In a real setup, you'd query a database table linking players to properties they own or rent.
    return exampleProperties
end

-- Fetch internet data for all of a player's properties
RegisterNetEvent("smartutils:server:getInternetData", function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local ownedProperties = getPlayerProperties(src) -- Get list of property IDs player owns/manages
    local propertiesData = {}

    if #ownedProperties > 0 then
        for _, propInfo in ipairs(ownedProperties) do
            local propertyId = propInfo.propertyId
            -- Fetch internet status for each property
            local result = MySQL.Sync.fetchAll("SELECT property_id, upgrade_tier, is_router_installed FROM player_internet WHERE citizenid = ? AND property_id = ?", {
                citizenid, propertyId
            })

            if result and result[1] then
                table.insert(propertiesData, {
                    propertyId = result[1].property_id,
                    address = propInfo.address, -- Get address from housing script data
                    currentTier = result[1].upgrade_tier or 'None',
                    isRouterInstalled = tonumber(result[1].is_router_installed) == 1,
                    isSubscribed = true -- If there's an entry, they are subscribed
                })
            else
                -- Not subscribed or no entry yet for this property
                table.insert(propertiesData, {
                    propertyId = propertyId,
                    address = propInfo.address,
                    currentTier = 'None',
                    isRouterInstalled = false,
                    isSubscribed = false
                })
            end
        end
    end
    TriggerClientEvent("smartutils:client:showInternetNUI", src, propertiesData)
end)

-- Subscribe to internet service
RegisterNetEvent("smartutils:server:subscribeInternet", function(propertyId, tier)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid

    -- Rate limiting check
    local canProceed, limitError = RateLimiter.CheckLimit(src, "smartutils:server:subscribeInternet")
    if not canProceed then
        Player.Functions.Notify(limitError, "error")
        Logger.Warn("Rate limit exceeded for player " .. citizenid .. " on subscribeInternet")
        return
    end

    -- Validate inputs
    local isValidProperty, propertyError = Validation.ValidatePropertyId(propertyId)
    if not isValidProperty then
        Player.Functions.Notify("Invalid property ID: " .. propertyError, "error")
        return
    end
    
    local isValidTier, tierError = Validation.ValidateInternetTier(tier)
    if not isValidTier then
        Player.Functions.Notify("Invalid tier: " .. tierError, "error")
        return
    end

    -- Check if already subscribed (though UI should prevent this path if already subscribed)
    local existing = MySQL.Sync.fetchAll("SELECT id FROM player_internet WHERE citizenid = ? AND property_id = ?", {citizenid, propertyId})
    if existing and existing[1] then
        Player.Functions.Notify("You are already subscribed to internet at this property.", "warning")
        -- Optionally, update their tier if this path is hit due to a race condition or error
        -- MySQL.Async.execute("UPDATE player_internet SET upgrade_tier = ? WHERE citizenid = ? AND property_id = ?", {tier, citizenid, propertyId})
        return
    end

    -- TODO: Add cost for subscription if applicable, using Player.Functions.RemoveMoney
    -- local subscriptionCost = Config.InternetTiers[tier].cost
    -- if Player.PlayerData.money.cash < subscriptionCost then
    // Player.Functions.Notify("You don't have enough money to subscribe.", "error")
    -- return
    -- end
    -- Player.Functions.RemoveMoney('cash', subscriptionCost, "internet-subscription")

    MySQL.Async.execute(
        "INSERT INTO player_internet (citizenid, property_id, upgrade_tier, is_router_installed, router_pos_x, router_pos_y, router_pos_z) VALUES (?, ?, ?, ?, NULL, NULL, NULL) ON DUPLICATE KEY UPDATE upgrade_tier = VALUES(upgrade_tier)",
        {citizenid, propertyId, tier, 0}, -- is_router_installed defaults to 0 (false)
        function(affectedRows)
            if affectedRows > 0 then
                Player.Functions.Notify("Successfully subscribed to " .. tier .. " internet for property " .. propertyId .. ". A technician needs to install the router.", "success", 7500)
                TriggerClientEvent("smartutils:client:updateInternetPropertyData", src, {
                    propertyId = propertyId,
                    currentTier = tier,
                    isRouterInstalled = false,
                    isSubscribed = true
                    -- address will be preserved on client side or re-fetched if needed
                })
            else
                Player.Functions.Notify("Failed to subscribe. Please try again.", "error")
            end
        end
    )
end)

-- Upgrade internet tier
RegisterNetEvent("smartutils:server:upgradeInternetTier", function(propertyId, newTier)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid

    -- Rate limiting check
    local canProceed, limitError = RateLimiter.CheckLimit(src, "smartutils:server:upgradeInternetTier")
    if not canProceed then
        Player.Functions.Notify(limitError, "error")
        Logger.Warn("Rate limit exceeded for player " .. citizenid .. " on upgradeInternetTier")
        return
    end

    -- Validate inputs
    local isValidProperty, propertyError = Validation.ValidatePropertyId(propertyId)
    if not isValidProperty then
        Player.Functions.Notify("Invalid property ID: " .. propertyError, "error")
        return
    end
    
    local isValidTier, tierError = Validation.ValidateInternetTier(newTier)
    if not isValidTier then
        Player.Functions.Notify("Invalid tier: " .. tierError, "error")
        return
    end

    -- TODO: Add cost for upgrade, potentially pro-rated or difference
    -- local upgradeCost = Config.InternetTiers[newTier].upgradeCost
    -- if Player.PlayerData.money.cash < upgradeCost then
    -- Player.Functions.Notify("You don't have enough money to upgrade.", "error")
    -- return
    -- end
    -- Player.Functions.RemoveMoney('cash', upgradeCost, "internet-upgrade")

    MySQL.Async.execute(
        "UPDATE player_internet SET upgrade_tier = ? WHERE citizenid = ? AND property_id = ?",
        {newTier, citizenid, propertyId},
        function(affectedRows)
            if affectedRows > 0 then
                Player.Functions.Notify("Successfully upgraded internet to " .. newTier .. " for property " .. propertyId, "success")
                TriggerClientEvent("smartutils:client:updateInternetPropertyData", src, {
                    propertyId = propertyId,
                    currentTier = newTier,
                    isRouterInstalled = true, -- Assuming router must be installed to upgrade
                    isSubscribed = true
                })
            else
                Player.Functions.Notify("Failed to upgrade. Are you subscribed to this property?", "error")
            end
        end
    )
end)

-- Check router status before installation attempt
RegisterNetEvent("smartutils:server:checkRouterStatus", function(propertyId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Validate input
    local isValid, errorMsg = Validation.ValidatePropertyId(propertyId)
    if not isValid then
        Player.Functions.Notify("Invalid property ID: " .. errorMsg, "error")
        return
    end
    
    -- Server-side validation that the requester is a technician
    local TECHNICIAN_JOBS_SERVER = { "mechanic", "isp_technician" }
    local hasPermission = false
    if Player.PlayerData.job and Player.PlayerData.job.name then
        for _, jobName in ipairs(TECHNICIAN_JOBS_SERVER) do
            if Player.PlayerData.job.name == jobName then
                hasPermission = true
                break
            end
        end
    end

    if not hasPermission then
        Player.Functions.Notify("You are not authorized to check router status.", "error")
        Logger.Warn("Player " .. Player.PlayerData.citizenid .. " attempted to check router status without technician job")
        return
    end

    local result = Validation.SafeExecute(function()
        return MySQL.Sync.fetchAll("SELECT is_router_installed, citizenid FROM player_internet WHERE property_id = ? ORDER BY id DESC LIMIT 1", {propertyId})
    end, "Failed to check router status for property: " .. propertyId)

    local isInstalled = false
    if result and result[1] then
        isInstalled = tonumber(result[1].is_router_installed) == 1
    end
    
    TriggerClientEvent("smartutils:client:routerStatusResponse", src, propertyId, isInstalled)
end)

-- Confirm router installation
RegisterNetEvent("smartutils:server:confirmInstall", function(propertyId, routerCoords)
    local src = source -- Technician's source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Rate limiting check
    local canProceed, limitError = RateLimiter.CheckLimit(src, "smartutils:server:confirmInstall")
    if not canProceed then
        Player.Functions.Notify(limitError, "error")
        Logger.Warn("Rate limit exceeded for player " .. Player.PlayerData.citizenid .. " on confirmInstall")
        return
    end

    -- Validate inputs
    local isValidProperty, propertyError = Validation.ValidatePropertyId(propertyId)
    if not isValidProperty then
        Player.Functions.Notify("Invalid property ID: " .. propertyError, "error")
        return
    end
    
    local isValidCoords, coordsError = Validation.ValidateCoords(routerCoords)
    if not isValidCoords then
        Player.Functions.Notify("Invalid coordinates: " .. coordsError, "error")
        return
    end

    -- Server-side validation that the installer is a technician
    local TECHNICIAN_JOBS_SERVER = { "mechanic", "isp_technician" }
    if not Inventory.HasJob(src, TECHNICIAN_JOBS_SERVER) then
        Player.Functions.Notify("You are not authorized to confirm installations.", "error")
        Logger.Warn(string.format("SECURITY: Player %s (CitizenID: %s) attempted to trigger confirmInstall without technician job.", Player.PlayerData.name or "Unknown", Player.PlayerData.citizenid))
        return
    end

    -- Check if technician has required tools
    if not Inventory.HasRequiredItems(src, Config.Internet.Installation.RequiredItems or {}) then
        Player.Functions.Notify("You don't have the required installation tools.", "error")
        return
    end

    -- Who is the subscription for? We need their citizenid.
    -- This is tricky. The technician installs for a property. We need to find who subscribed to that property.
    -- For now, we assume the technician is told which player's service they are installing, or propertyId is globally unique.
    -- Let's assume the propertyId is enough to find the unique subscription record.
    -- A more robust system might involve a job ID or the customer's citizenid.

    local result = MySQL.Sync.fetchAll("SELECT citizenid FROM player_internet WHERE property_id = ? AND is_router_installed = 0", {propertyId})
    if not result or not result[1] then
        Player.Functions.Notify("Could not find an active subscription awaiting installation for property: " .. propertyId, "error")
        return
    end
    local targetCitizenId = result[1].citizenid

    MySQL.Async.execute(
        "UPDATE player_internet SET is_router_installed = 1, router_pos_x = ?, router_pos_y = ?, router_pos_z = ? WHERE property_id = ? AND citizenid = ?",
        {routerCoords.x, routerCoords.y, routerCoords.z, propertyId, targetCitizenId},
        function(affectedRows)
            if affectedRows > 0 then
                Player.Functions.Notify("Router installation confirmed for property " .. propertyId, "success")
                local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenId)
                if targetPlayer then
                    targetPlayer.Functions.Notify("Your internet router has been installed at property " .. propertyId .. "!", "success")
                    -- Update target player's NUI if it's open
                    TriggerClientEvent("smartutils:client:updateInternetPropertyData", targetPlayer.PlayerData.source, {
                        propertyId = propertyId,
                        isRouterInstalled = true
                        -- other fields like tier and address are already known or will be updated if changed
                    })
                end
            else
                Player.Functions.Notify("Failed to update router installation status in database for " .. propertyId, "error")
            end
        end
    )
end)

-- Example: Log technician request (could be expanded for a dispatch system)
-- RegisterNetEvent("smartutils:server:logTechnicianRequest", function(propertyId)
--    local src = source
--    local Player = QBCore.Functions.GetPlayer(src)
--    print("Technician request logged for property: " .. propertyId .. " by player: " .. Player.PlayerData.citizenid)
--    -- Here you could alert players with the 'isp_technician' job
-- end)

print("SmartUtils: Server-side Internet script loaded.")
