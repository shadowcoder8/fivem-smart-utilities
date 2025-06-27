-- Shared Objects & Framework
QBCore = nil
ESX = nil

-- Initialize Logger (shared script, should be available)
Citizen.CreateThread(function()
    -- Ensure Config is loaded (it's a shared script, should be parsed before server.lua)
    while not Config or not next(Config) do
        print("[SmartUtilities] Server waiting for Config to be loaded...")
        Citizen.Wait(100)
    end
    Logger.Initialize() -- Initialize logger now that Config is definitely loaded
    Logger.Info("SmartUtilities Server Script Starting...")

    if Config.Framework == 'qb-core' then
        QBCore = exports['qb-core']:GetCoreObject()
        if QBCore then
            Logger.Info("QBCore object loaded on server.")
            -- Register QBCore specific events or load data if needed
        else
            Logger.Error("QBCore object failed to load on server. Ensure qb-core is started and exports GetCoreObject.")
        end
    elseif Config.Framework == 'esx' then
        -- ESX server-side setup
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        if ESX then
            Logger.Info("ESX Shared Object potentially loaded on server.")
            -- ESX often relies on player-specific objects (xPlayer) obtained via events.
        else
            Logger.Warn("ESX Shared Object not immediately available on server. Will try to get it via events for players.")
        end
    else
        Logger.Warn("No framework specified or framework not recognized. Some server-side features might be limited.")
    end

    -- Initialize Database (oxmysql)
    if exports.oxmysql then
        Logger.Info("oxmysql is available.")
        -- TODO: Create database tables if they don't exist for player_internet_subscriptions etc.
        -- Internet.CreatePlayerSubscriptionsTable()
    else
        Logger.Error("oxmysql is not available. Database features will be disabled.")
    end

    InitializeModules()
end)

-- Function to initialize all utility modules
function InitializeModules()
    Logger.Info("Initializing utility modules...")
    if Config.Power.Enabled then Power.Initialize() end
    if Config.Water.Enabled then Water.Initialize() end
    if Config.Internet.Enabled then Internet.Initialize() end
    if Config.Trash.Enabled then Trash.Initialize() end
    Logger.Info("Utility modules initialization sequence complete.")
end

-- NUI Data Handling
RegisterNetEvent('smartutilities:nui:getInitialData', function()
    local src = source
    Logger.Debug("Client " .. src .. " requested initial NUI data.")

    local powerStatus = {}
    if Config.Power.Enabled then
        powerStatus = Power.GetStatusForAllZones()
    end
    local waterStatus = {}
    if Config.Water.Enabled then
        waterStatus = Water.GetStatusForAll()
    end
    local internetData = { hubs = {}, userService = nil, playerProperties = {}, subscriptions = {}, pendingInstallations = {} }
    if Config.Internet.Enabled then
        internetData.hubs = Internet.GetStatusForAllHubs()
        internetData.userService = Internet.GetUserSubscriptionStatus(src) -- This is context-dependent, might need a primary property
        -- For NUI, we need all subscriptions and properties for this player
        -- This part requires integration with a housing script (e.g., qb-houses)
        -- Mocking playerProperties for now, server needs to populate this.
        internetData.playerProperties = {} -- Example: { {property_id = 'prop1', label = 'House 1'}, ... }
                                         -- This should be fetched using something like exports['qb-houses']:GetOwnedHouses(QBCore.Functions.GetPlayer(src).PlayerData.citizenid)
        internetData.subscriptions = Internet.PlayerSubscriptions -- Send all cached subs for this player to filter on NUI side, or filter here by citizenid.
        internetData.pendingInstallations = Internet.PendingInstallations
    end
    local trashStatus = {}
    if Config.Trash.Enabled then
        trashStatus = Trash.GetStatusForAll()
    end

    local initialData = {
        isAdmin = IsAdmin(src),
        config = {
            Power = { Zones = Config.Power.Zones },
            Water = { Sources = Config.Water.Sources },
            Internet = { ServiceTiers = Config.Internet.ServiceTiers, Hubs = Config.Internet.Hubs },
            Trash = { PublicBins = Config.Trash.PublicBins, LargeDumpsters = Config.Trash.LargeDumpsters }
        },
        power = powerStatus,
        water = waterStatus,
        internet = internetData,
        trash = trashStatus
    }
    TriggerClientEvent('smartutilities:client:updateNUIData', src, "initial_load", initialData)
    Logger.Debug("Sent initial NUI data to client " .. src .. ": " .. json.encode(initialData))
end)

RegisterNetEvent('smartutilities:requestTabletOpenPermission', function()
    local src = source
    if Config.Tablet.AdminOnly then
        if IsAdmin(src) then
            TriggerClientEvent('smartutilities:client:openTablet', src)
            Logger.Info("Admin " .. GetPlayerName(src) .. " (" .. src .. ") granted tablet access.")
        else
            ShowNotification(src, "You do not have permission to open the Utilities Tablet.", "error")
            Logger.Warn("Player " .. GetPlayerName(src) .. " (" .. src .. ") denied tablet access (Admin Only).")
        end
    else
        TriggerClientEvent('smartutilities:client:openTablet', src)
        Logger.Info("Player " .. GetPlayerName(src) .. " (" .. src .. ") granted tablet access (Public).")
    end
end)

function BroadcastNUIDataUpdate(dataType, data)
    TriggerClientEvent('smartutilities:client:updateNUIData', -1, dataType, data)
    Logger.Debug("Broadcasted NUI data update: " .. dataType)
end

-- Power Module (existing code...)
Power = {}
Power.ZonesState = {}
function Power.Initialize()
    Logger.Info("Power Module Initializing (Server)...")
    if not Config.Power or not Config.Power.Enabled then Logger.Warn("Power module is disabled in config.") return end
    for zoneId, zoneConfig in pairs(Config.Power.Zones) do
        Power.ZonesState[zoneId] = {
            label = zoneConfig.label, isBlackout = zoneConfig.isBlackout or false, autoRepairTimer = nil,
            sabotageCooldownTimer = nil, lastSabotageAttempt = 0, config = zoneConfig
        }
    end
    Power.StartPowerCheckTimers()
    Logger.Info("Power Module Initialized. "..(#Config.Power.Zones or 0).." zones loaded.")
end
function Power.LoadZoneStateFromDB(zoneId) end
function Power.SaveZoneStateToDB(zoneId) end
function Power.SetZoneBlackoutState(zoneId, isBlackout, initiatedBy)
    local zoneState = Power.ZonesState[zoneId]
    if not zoneState then Logger.Warn("SetZoneBlackoutState: Zone " .. zoneId .. " not found.") return false end
    if zoneState.isBlackout == isBlackout then return false end
    zoneState.isBlackout = isBlackout
    Logger.Info("Power zone " .. zoneId .. " is now " .. (isBlackout and "IN BLACKOUT" or "ONLINE") .. (initiatedBy and (" (By: "..initiatedBy..")") or ""))
    if zoneState.autoRepairTimer then KillTimer(zoneState.autoRepairTimer) zoneState.autoRepairTimer = nil end
    if isBlackout then
        Power.ScheduleAutoRepair(zoneId)
        TriggerClientEvent('smartutilities:client:powerBlackoutEffect', -1, zoneId, true, zoneState.config.coords, zoneState.config.radius, zoneState.config.affectedEntities)
        ShowNotification(-1, string.format(Config.Power.Notifications.PowerOutage, zoneState.label or zoneId), "error", 7000)
    else
        TriggerClientEvent('smartutilities:client:powerBlackoutEffect', -1, zoneId, false, zoneState.config.coords, zoneState.config.radius, zoneState.config.affectedEntities)
        ShowNotification(-1, string.format(Config.Power.Notifications.PowerRestored, zoneState.label or zoneId), "success", 7000)
    end
    Power.SaveZoneStateToDB(zoneId)
    Power.BroadcastPowerStatusUpdate(zoneId)
    return true
end
function Power.ScheduleAutoRepair(zoneId)
    local zoneState = Power.ZonesState[zoneId]
    if not zoneState or not zoneState.isBlackout then return end
    local repairTime = math.random(Config.Power.AutoRepairTime.min, Config.Power.AutoRepairTime.max) * 1000
    if zoneState.autoRepairTimer then KillTimer(zoneState.autoRepairTimer) end
    zoneState.autoRepairTimer = SetTimeout(repairTime, function()
        Power.SetZoneBlackoutState(zoneId, false, "AutoRepairSystem")
        zoneState.autoRepairTimer = nil
    end)
end
function Power.ForceBlackout(source, zoneId, durationSeconds)
    local zoneState = Power.ZonesState[zoneId]
    if not zoneState then ShowNotification(source, "Error: Power zone '" .. zoneId .. "' not found.", "error") return end
    Power.SetZoneBlackoutState(zoneId, true, GetPlayerName(source) or "Admin")
    ShowNotification(source, "Forced blackout for zone: " .. (zoneState.label or zoneId), "success")
    if durationSeconds and durationSeconds > 0 then
        if zoneState.autoRepairTimer then KillTimer(zoneState.autoRepairTimer) end
        zoneState.autoRepairTimer = SetTimeout(durationSeconds * 1000, function()
            Power.SetZoneBlackoutState(zoneId, false, "TimedAction")
            zoneState.autoRepairTimer = nil
        end)
    end
end
function Power.RepairPowerZone(source, zoneId)
    local zoneState = Power.ZonesState[zoneId]
    if not zoneState then ShowNotification(source, "Error: Power zone '" .. zoneId .. "' not found.", "error") return end
    if not zoneState.isBlackout then ShowNotification(source, (zoneState.label or zoneId) .. " is already online.", "info") return end
    Power.SetZoneBlackoutState(zoneId, false, GetPlayerName(source) or "AdminRepair")
    ShowNotification(source, "Repaired power for zone: " .. (zoneState.label or zoneId), "success")
end
function Power.AttemptSabotage(source, zoneId)
    local zoneState = Power.ZonesState[zoneId]; local player = QBCore.Functions.GetPlayer(source)
    if not zoneState or not zoneState.config.canBeSabotaged then ShowNotification(source, "This zone cannot be sabotaged.", "error") return end
    if zoneState.isBlackout then ShowNotification(source, (zoneState.label or zoneId) .. " is already blacked out.", "info") return end
    if Config.Power.Sabotage.MinPoliceOnline and #QBCore.Functions.GetPlayersByJob('police') < Config.Power.Sabotage.MinPoliceOnline then ShowNotification(source, "Not enough police.", "error") return end
    local currentTime = GetGameTimer()
    if zoneState.lastSabotageAttempt and (currentTime - zoneState.lastSabotageAttempt) < (Config.Power.Sabotage.Cooldown * 1000) then
        ShowNotification(source, "Substation recently targeted. Try later.", "error") return
    end
    if not HasRequiredItems(source, Config.Power.Sabotage.RequiredItems) then return end
    ShowNotification(source, "Tampering with substation...", "info", 10000)
    SetTimeout(15000, function()
        if not GetPlayerName(source) or zoneState.isBlackout then return end
        if RemovePlayerItems(source, Config.Power.Sabotage.RequiredItems) then
            Power.SetZoneBlackoutState(zoneId, true, "Sabotage by " .. GetPlayerName(source))
            ShowNotification(source, "Sabotage successful! " .. (zoneState.label or zoneId) .. " offline.", "success")
            zoneState.lastSabotageAttempt = GetGameTimer()
            if Config.Power.Sabotage.PoliceAlert then TriggerEvent("police:server:policeAlert", string.format(Config.Power.Notifications.SabotageSuccess, zoneState.label or zoneId)) end
        else ShowNotification(source, "Failed to use items for sabotage.", "error") end
    end)
end
function Power.GetStatusForAllZones()
    local status = {}
    for zoneId, state in pairs(Power.ZonesState) do
        status[zoneId] = {label = state.label, isBlackout = state.isBlackout, canBeSabotaged = state.config.canBeSabotaged}
    end
    return status
end
function Power.BroadcastPowerStatusUpdate(zoneId)
    local zoneData = Power.ZonesState[zoneId]
    if zoneData then BroadcastNUIDataUpdate("power_status", {[zoneId] = {label = zoneData.label, isBlackout = zoneData.isBlackout, canBeSabotaged = zoneData.config.canBeSabotaged}}) end
end
function Power.BroadcastAllPowerStatus() BroadcastNUIDataUpdate("power_status", Power.GetStatusForAllZones()) end
function Power.StartPowerCheckTimers()
    SetInterval(300000, function()
        for zoneId, _ in pairs(Power.ZonesState) do Power.SaveZoneStateToDB(zoneId) end
    end)
end
exports('IsPowerZoneBlackout', function(zoneId) if Power.ZonesState[zoneId] then return Power.ZonesState[zoneId].isBlackout end return false end)
exports('GetPowerZoneStatus', function(zoneId) if Power.ZonesState[zoneId] then return { isBlackout = Power.ZonesState[zoneId].isBlackout, label = Power.ZonesState[zoneId].label } end return nil end)
function Power.GetZoneNames() local names = {} for id, zData in pairs(Config.Power.Zones) do table.insert(names, zData.label or id) end return names end


-- Water Module (existing code...)
Water = {}
Water.SourcesState = {}
Water.ActiveLeaks = {}
local nextLeakId = 1
function Water.Initialize()
    Logger.Info("Water Module Initializing (Server)...")
    if not Config.Water or not Config.Water.Enabled then Logger.Warn("Water module is disabled.") return end
    for sourceId, sourceConfig in pairs(Config.Water.Sources) do
        Water.SourcesState[sourceId] = { label = sourceConfig.label, currentLevel = sourceConfig.currentLevel, capacity = sourceConfig.capacity, alertThreshold = sourceConfig.alertThreshold, config = sourceConfig }
    end
    SetInterval(Config.Water.TickInterval or 300000, Water.ProcessTick)
    Logger.Info("Water Module Initialized. "..(#Config.Water.Sources or 0).." sources. Tick: "..(Config.Water.TickInterval or 300000)/1000 .."s")
end
function Water.ProcessTick()
    Logger.Debug("Water Module: Processing tick...")
    for sourceId, state in pairs(Water.SourcesState) do
        if state.config.refillRatePerTick and state.currentLevel < state.capacity then
            state.currentLevel = math.min(state.capacity, state.currentLevel + state.config.refillRatePerTick)
        end
    end
    if #Water.ActiveLeaks < Config.Water.MaxActiveLeaks and math.random() < Config.Water.LeakChancePerTick then
        Water.SpawnRandomLeak()
    end
    Water.BroadcastAllWaterStatus()
end
function Water.SpawnRandomLeak(sourceIdForLeak)
    local leakId = "leak_" .. nextLeakId; nextLeakId = nextLeakId + 1
    local randomX, randomY = math.random(-2000, 2000), math.random(-2000, 3000)
    local associatedSourceId = sourceIdForLeak
    if not associatedSourceId and next(Config.Water.Sources) ~= nil then
        local sourceKeys = {}; for k, v in pairs(Config.Water.Sources) do if v.canHaveLeaksNearby then table.insert(sourceKeys, k) end end
        if #sourceKeys > 0 then associatedSourceId = sourceKeys[math.random(#sourceKeys)] end
    end
    if associatedSourceId and Water.SourcesState[associatedSourceId] and Water.SourcesState[associatedSourceId].config.leakSpawnRadius then
        local sourceConf = Water.SourcesState[associatedSourceId].config; local angle = math.random()*2*math.pi; local radius = math.random()*sourceConf.leakSpawnRadius
        randomX = sourceConf.coords.x + math.cos(angle)*radius; randomY = sourceConf.coords.y + math.sin(angle)*radius
    end
    local foundZ, groundZ = GetGroundZFor_3dCoord(randomX, randomY, 100.0, false); if not foundZ then groundZ = 30.0 end
    local leakCoords = vector3(randomX, randomY, groundZ)
    local despawnTime = math.random(Config.Water.LeakAutoDespawnTime.min, Config.Water.LeakAutoDespawnTime.max) * 1000
    local despawnTimer = SetTimeout(despawnTime, function() Water.RemoveLeak(leakId, "AutoDespawn") end)
    Water.ActiveLeaks[leakId] = { id = leakId, coords = leakCoords, spawnedTime = GetGameTimer(), autoDespawnTimer = despawnTimer, sourceId = associatedSourceId, locationDescription = "near " .. (associatedSourceId and Water.SourcesState[associatedSourceId].label or "unknown area") }
    Logger.Info("New water leak: " .. leakId .. " at " .. json.encode(leakCoords))
    ShowNotification(-1, string.format(Config.Water.Notifications.NewLeak, Water.ActiveLeaks[leakId].locationDescription), "warning", 10000)
    TriggerClientEvent('smartutilities:client:waterLeakEffect', -1, leakId, leakCoords, true)
    Water.BroadcastWaterLeakUpdate(leakId, true); return leakId
end
function Water.RemoveLeak(leakId, reason)
    local leak = Water.ActiveLeaks[leakId]
    if leak then
        if leak.autoDespawnTimer then KillTimer(leak.autoDespawnTimer) end
        Water.ActiveLeaks[leakId] = nil; Logger.Info("Water leak " .. leakId .. " removed. Reason: " .. (reason or "Repaired"))
        TriggerClientEvent('smartutilities:client:waterLeakEffect', -1, leakId, leak.coords, false)
        ShowNotification(-1, string.format(Config.Water.Notifications.LeakRepaired, leak.locationDescription), "success")
        Water.BroadcastWaterLeakUpdate(leakId, false)
    end
end
function Water.ForceLeak(sourceAdmin, sourceIdForLeak)
    if #Water.ActiveLeaks >= Config.Water.MaxActiveLeaks then ShowNotification(sourceAdmin, "Max active leaks reached.", "error") return end
    local newLeakId = Water.SpawnRandomLeak(sourceIdForLeak)
    if newLeakId then ShowNotification(sourceAdmin, "Forced new water leak: " .. newLeakId, "success")
    else ShowNotification(sourceAdmin, "Failed to force new water leak.", "error") end
end
function Water.RepairLeak(sourceAdmin, leakIdToRepair)
    if leakIdToRepair == 'all' then
        local count = 0; for id, _ in pairs(Water.ActiveLeaks) do Water.RemoveLeak(id, "AdminClearAll"); count = count + 1 end
        ShowNotification(sourceAdmin, "Cleared all (" .. count .. ") water leaks.", "success")
        return
    end
    if Water.ActiveLeaks[leakIdToRepair] then Water.RemoveLeak(leakIdToRepair, "AdminRepair"); ShowNotification(sourceAdmin, "Repaired water leak: " .. leakIdToRepair, "success")
    else ShowNotification(sourceAdmin, "Leak ID '" .. leakIdToRepair .. "' not found.", "error") end
end
function Water.GetStatusForAll()
    local status = { sources = {}, leaks = {} }
    for id, state in pairs(Water.SourcesState) do status.sources[id] = { label = state.label, currentLevel = state.currentLevel, capacity = state.capacity, alertThreshold = state.alertThreshold, percentage = (state.currentLevel / state.capacity) * 100 } end
    for id, leakData in pairs(Water.ActiveLeaks) do table.insert(status.leaks, { id = id, coords = leakData.coords, locationDescription = leakData.locationDescription, spawnedTime = leakData.spawnedTime }) end
    return status
end
function Water.BroadcastWaterLeakUpdate(leakId, isLeaking)
    local leakData = Water.ActiveLeaks[leakId]; local dataToSend
    if isLeaking and leakData then dataToSend = { id = leakId, coords = leakData.coords, locationDescription = leakData.locationDescription, spawnedTime = leakData.spawnedTime, isLeaking = true }
    else dataToSend = { id = leakId, isLeaking = false } end
    BroadcastNUIDataUpdate("water_leak_update", dataToSend)
end
function Water.BroadcastAllWaterStatus() BroadcastNUIDataUpdate("water_status", Water.GetStatusForAll()) end

Internet.HubsState = {} -- { hubId = { label, isDown, autoRepairTimer, lastHackAttempt, currentConnections, config = {} } }
Internet.PlayerSubscriptions = {} -- { [property_id] = { citizenid, property_id, provider (hubId), speed_tier (tierId), is_active, last_payment } }
Internet.PendingInstallations = {} -- { [property_id] = { ticket_id, type, property_id, citizenid, description (tierLabel), status } }

function Internet.Initialize()
    Logger.Info("Internet Module Initializing (Server)...")
    if not Config.Internet or not Config.Internet.Enabled then
        Logger.Warn("Internet module is disabled in config.")
        return
    end

    Internet.CreateTables() -- Create DB tables

    for hubId, hubConfig in pairs(Config.Internet.Hubs) do
        Internet.HubsState[hubId] = {
            label = hubConfig.label, isDown = hubConfig.isDown or false, autoRepairTimer = nil,
            lastHackAttempt = 0, currentConnections = 0, config = hubConfig
        }
        -- TODO: Load persistent hub state (isDown, currentConnections) from a separate internet_hubs table if needed
        Logger.Debug("Initialized internet hub: " .. hubId)
    end

    Internet.LoadAllPlayerSubscriptions() -- Loads subscriptions and updates hub counts
    Internet.LoadPendingInstallations() -- Loads pending job tickets

    SetInterval(Config.Internet.TickInterval or 450000, Internet.ProcessTick)
    Logger.Info("Internet Module Initialized. "..(#Config.Internet.Hubs or 0).." hubs loaded. Tick: "..(Config.Internet.TickInterval or 450000)/1000 .."s")
end

function Internet.ProcessTick()
    Logger.Debug("Internet Module: Processing tick...")
    -- TODO: Implement billing logic: iterate PlayerSubscriptions, check nextBillDate, attempt payment, deactivate if failed.
    Internet.BroadcastAllInternetStatus()
end

function Internet.SetHubStatus(hubId, isDown, initiatedBy)
    local hubState = Internet.HubsState[hubId]
    if not hubState then Logger.Warn("SetHubStatus: Hub " .. hubId .. " not found.") return false end
    if hubState.isDown == isDown then return false end

    hubState.isDown = isDown
    Logger.Info("Internet Hub " .. hubId .. " is now " .. (isDown and "DOWN" : "ONLINE") .. (initiatedBy and (" (By: "..initiatedBy..")") or ""))
    if hubState.autoRepairTimer then KillTimer(hubState.autoRepairTimer); hubState.autoRepairTimer = nil end

    if isDown then
        local outageDuration = math.random(Config.Internet.Hacking.OutageDuration.min, Config.Internet.Hacking.OutageDuration.max) * 1000
        hubState.autoRepairTimer = SetTimeout(outageDuration, function() Internet.SetHubStatus(hubId, false, "AutoRepairSystem") end)
        ShowNotification(-1, string.format(Config.Internet.Notifications.InternetDown, hubState.label, hubState.label), "error", 7000)
        TriggerClientEvent('smartutilities:client:internetStatusChanged', -1, hubId, true, "Hub " .. hubState.label .. " is down.")
    else
        ShowNotification(-1, string.format(Config.Internet.Notifications.InternetRestored, hubState.label, hubState.label), "success", 7000)
        TriggerClientEvent('smartutilities:client:internetStatusChanged', -1, hubId, false, "Hub " .. hubState.label .. " is back online.")
    end
    -- TODO: Internet.SaveHubStateToDB(hubId)
    Internet.BroadcastInternetHubStatusUpdate(hubId)
    -- Notify all players with subscriptions on this hub
    for propId, sub in pairs(Internet.PlayerSubscriptions) do
        if sub.provider == hubId then
            local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(sub.citizenid)
            if targetPlayer then Internet.BroadcastUserInternetStatus(targetPlayer.PlayerData.source) end
        end
    end
    return true
end

function Internet.ForceOutage(source, hubId, durationSeconds)
    local hubState = Internet.HubsState[hubId]
    if not hubState then ShowNotification(source, "Error: Hub '" .. hubId .. "' not found.", "error") return end
    Internet.SetHubStatus(hubId, true, GetPlayerName(source) or "Admin")
    ShowNotification(source, "Forced outage for Hub: " .. (hubState.label or hubId), "success")
    if durationSeconds and durationSeconds > 0 then
        if hubState.autoRepairTimer then KillTimer(hubState.autoRepairTimer) end
        hubState.autoRepairTimer = SetTimeout(durationSeconds * 1000, function() Internet.SetHubStatus(hubId, false, "TimedAdminAction") end)
    end
end

function Internet.RepairHub(source, hubId)
    local hubState = Internet.HubsState[hubId]
    if not hubState then ShowNotification(source, "Error: Hub '" .. hubId .. "' not found.", "error") return end
    if not hubState.isDown then ShowNotification(source, (hubState.label or hubId) .. " is already online.", "info") return end
    Internet.SetHubStatus(hubId, false, GetPlayerName(source) or "AdminRepair")
end

function Internet.AttemptHack(source, hubId)
    local hubState = Internet.HubsState[hubId]
    if not hubState or not hubState.config.canBeHacked then ShowNotification(source, "This hub cannot be hacked.", "error") return end
    if hubState.isDown then ShowNotification(source, (hubState.label or hubId) .. " is already down.", "info") return end
    if Config.Internet.Hacking.MinPoliceOnline > 0 and #QBCore.Functions.GetPlayersByJob('police') < Config.Internet.Hacking.MinPoliceOnline then ShowNotification(source, "Not enough police.", "error") return end
    local currentTime = GetGameTimer()
    if hubState.lastHackAttempt and (currentTime - hubState.lastHackAttempt) < (Config.Internet.Hacking.Cooldown * 1000) then
        ShowNotification(source, "Hub recently targeted. Try later.", "error") return
    end
    if not HasRequiredItems(source, Config.Internet.Hacking.RequiredItems) then return end

    ShowNotification(source, "Attempting to breach hub security...", "info", 15000)
    TriggerClientEvent('smartutilities:client:startInternetHackMinigame', source, hubId, hubState.config.hackingDifficulty or 5)
end

RegisterNetEvent('smartutilities:server:finishInternetHack', function(hubId, success)
    local src = source
    local hubState = Internet.HubsState[hubId]
    if not hubState or hubState.isDown or not GetPlayerName(src) then return end

    if success then
        if RemovePlayerItems(src, Config.Internet.Hacking.RequiredItems) then
            Internet.SetHubStatus(hubId, true, "Hack by " .. GetPlayerName(src))
            ShowNotification(src, "Hack successful! " .. (hubState.label or hubId) .. " offline.", "success")
            hubState.lastHackAttempt = GetGameTimer()
            if Config.Internet.Hacking.PoliceAlert then TriggerEvent("police:server:policeAlert", "Internet hub "..(hubState.label or hubId).." compromised!") end
        else ShowNotification(src, "Failed to use items for hacking (already used/removed?).", "error") end
    else
        ShowNotification(src, "Hacking attempt on "..(hubState.label or hubId).." failed.", "error")
    end
end)

function Internet.RequestInstallation(source, tierId, propertyId)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end
    if not Config.Internet.ServiceTiers[tierId] then ShowNotification(source, "Invalid internet tier.", "error") return end
    if not propertyId then ShowNotification(source, "Property ID is required for installation.", "error") return end

    if Internet.PlayerSubscriptions[propertyId] and Internet.PlayerSubscriptions[propertyId].is_active then
        ShowNotification(source, "An internet service is already active for this property.", "error")
        return
    end
    if Internet.PendingInstallations[propertyId] and Internet.PendingInstallations[propertyId].status == 'open' then
        ShowNotification(source, "An installation is already pending for this property.", "info")
        return
    end

    local tierInfo = Config.Internet.ServiceTiers[tierId]

    if player.Functions.RemoveMoney("bank", tierInfo.price, "internet-installation-fee") then
        if Config.Internet.InstallationJob.Enabled then
            local ticketDesc = "Install " .. tierInfo.label .. " at property: " .. propertyId
            exports.oxmysql.insert(
                "INSERT INTO job_tickets (type, property_id, citizenid, description, status) VALUES (?, ?, ?, ?, ?)",
                {'internet_install', propertyId, player.PlayerData.citizenid, ticketDesc, 'open'},
                function(insertId)
                    if insertId then
                        Internet.PendingInstallations[propertyId] = {ticket_id = insertId, type='internet_install', property_id=propertyId, citizenid=player.PlayerData.citizenid, description=ticketDesc, status='open'}
                        ShowNotification(source, "Installation for "..tierInfo.label.." requested. A technician will complete it. Ticket ID: "..insertId, "success")
                        Logger.Info("Internet install ("..tierInfo.label..") for property " .. propertyId .. " (Ticket: "..insertId..") needs technician.")
                        -- TODO: Notify online technicians
                        -- Example: TriggerClientEvent('smartutilities:notifyTechnicians', -1, "New internet installation ticket: "..insertId)
                    else
                        ShowNotification(source, "Failed to create installation ticket. Refunding.", "error")
                        player.Functions.AddMoney("bank", tierInfo.price, "internet-install-refund")
                    end
                end
            )
        else
            local nearestHubId = Internet.GetNearestAvailableHub(player.PlayerData.coords)
            if not nearestHubId then
                ShowNotification(source, "No available internet hubs to connect to. Refunding.", "error")
                player.Functions.AddMoney("bank", tierInfo.price, "internet-install-refund")
                return
            end
            Internet.CompleteInstallation(propertyId, player.PlayerData.citizenid, tierId, nearestHubId, source)
        end
    else
        ShowNotification(source, "Not enough money for " .. tierInfo.label, "error")
    end
end

function Internet.CompleteInstallation(propertyId, citizenId, tierId, hubId, installerSource)
    local tierInfo = Config.Internet.ServiceTiers[tierId]
    local subData = {
        citizenid = citizenId, property_id = propertyId, provider = hubId, speed_tier = tierId,
        is_active = true, last_payment = os.time()
    }
    Internet.PlayerSubscriptions[propertyId] = subData

    if Internet.HubsState[hubId] then
        Internet.HubsState[hubId].currentConnections = (Internet.HubsState[hubId].currentConnections or 0) + 1
        -- TODO: Internet.SaveHubStateToDB(hubId)
    end
    Internet.SavePlayerSubscription(propertyId, subData)

    if Internet.PendingInstallations[propertyId] then -- Close ticket if it was a job
        exports.oxmysql.update("UPDATE job_tickets SET status = 'closed' WHERE ticket_id = ?", {Internet.PendingInstallations[propertyId].ticket_id})
        Internet.PendingInstallations[propertyId] = nil
    end

    local targetPlayer = QBCore.Functions.GetPlayerByCitizenId(citizenId)
    local targetSource = targetPlayer and targetPlayer.PlayerData.source or installerSource

    ShowNotification(targetSource, tierInfo.label .. " has been installed at property " .. propertyId .. "!", "success")
    Logger.Info(tierInfo.label .. " installed for property " .. propertyId .. " (Citizen: "..citizenId..") by " .. (installerSource and GetPlayerName(installerSource) or "System"))
    Internet.BroadcastUserInternetStatus(targetSource)
    Internet.BroadcastInternetHubStatusUpdate(hubId)
end

function Internet.InstallCommand(source, args)
    local technician = QBCore.Functions.GetPlayer(source)
    if not technician or not HasJob(source, Config.Internet.InstallationJob.JobName) then
        ShowNotification(source, "You are not authorized for this.", "error")
        return
    end
    local propertyId = args[1]
    if not propertyId then ShowNotification(source, "Usage: /installinternet <property_id>", "error") return end

    local ticket = Internet.PendingInstallations[propertyId]
    if not ticket or ticket.status ~= 'open' then
        ShowNotification(source, "No open installation ticket found for property: " .. propertyId, "error")
        return
    end

    -- TODO: Check if technician has Config.Internet.InstallationJob.RequiredItems
    -- if not RemovePlayerItems(source, Config.Internet.InstallationJob.RequiredItems) then ShowNotification(source, "Missing required tools.", "error") return end

    local tierId = Config.Internet.ServiceTiers[string.lower(string.match(ticket.description, "Install (%S+)"))] and string.lower(string.match(ticket.description, "Install (%S+)")) or nil
    -- This parsing of tierId from description is fragile. Better to store tierId in ticket.
    -- For now, let's assume description is "Install Basic ADSL at property..." and we extract "Basic ADSL" then map it back.
    -- A better way: store tierId directly in the job_tickets.description or a dedicated column.
    local parsedTierKey = nil
    for key, tierCfg in pairs(Config.Internet.ServiceTiers) do
        if string.find(string.lower(ticket.description), string.lower(tierCfg.label)) then
            parsedTierKey = key
            break
        end
    end

    if not parsedTierKey then
        ShowNotification(source, "Could not determine service tier from ticket: "..ticket.description, "error")
        Logger.Error("Failed to parse tier from ticket: " .. ticket.ticket_id)
        return
    end

    local nearestHubId = Internet.GetNearestAvailableHub(technician.PlayerData.coords) -- Or use property coords if available
    if not nearestHubId then ShowNotification(source, "No available internet hubs for connection.", "error") return end

    Internet.CompleteInstallation(propertyId, ticket.citizenid, parsedTierKey, nearestHubId, source)
end


function Internet.GetNearestAvailableHub(coords)
    local closestHubId = nil; local minDist = -1
    for hubId, hubState in pairs(Internet.HubsState) do
        if not hubState.isDown and hubState.currentConnections < hubState.config.maxConnections then
            local dist = #(vector3(coords.x, coords.y, coords.z) - hubState.config.coords)
            if minDist == -1 or dist < minDist then minDist = dist; closestHubId = hubId end
        end
    end
    return closestHubId
end

function Internet.GetHubIdByName(name)
    for id, hubData in pairs(Config.Internet.Hubs) do
        if string.lower(id) == string.lower(name) or (hubData.label and string.lower(hubData.label) == string.lower(name)) then return id end
    end
    return nil
end

function Internet.GetStatusForAllHubs()
    local status = {}; for hubId, state in pairs(Internet.HubsState) do status[hubId] = {label=state.label,isDown=state.isDown,canBeHacked=state.config.canBeHacked,cc=state.currentConnections,mc=state.config.maxConnections} end; return status
end

function Internet.GetUserSubscriptionStatus(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return nil end

    -- Attempt to get current property the player is in, if property system provides such export
    local currentPropertyId = nil
    -- Example: if exports['qb-houses'] and exports['qb-houses'].GetCurrentHouse then currentPropertyId = exports['qb-houses']:GetCurrentHouse() end
    -- If no current property, or if we want to show all their subscriptions, iterate.
    -- For a single active service status (e.g. for DoesPlayerHaveInternet), we need a primary property or a way to determine context.
    -- For NUI, we'd list all subscriptions linked to their citizenid.

    -- This example focuses on a specific property if provided, otherwise defaults to citizenid as key (which needs to change for property-based)
    -- For now, this function is more for NUI display of a known subscription.
    -- The actual "is my current location's internet active" check should use smartutils:getInternetStatus(propertyId) callback.

    local propertyIdToCheck = player.PlayerData.citizenid -- Placeholder - this needs to be the property context

    -- To list ALL properties for NUI:
    -- local ownedHouses = exports['qb-houses']:GetOwnedHouses(player.PlayerData.citizenid) -- Hypothetical
    -- For each house in ownedHouses, check Internet.PlayerSubscriptions[house.id]

    local sub = Internet.PlayerSubscriptions[propertyIdToCheck] -- This should be propertyId
    if sub and sub.is_active then
        local hubState = Internet.HubsState[sub.provider]
        local isActive = not (hubState and hubState.isDown or false)
        return {tierId=sub.speed_tier, tierLabel=Config.Internet.ServiceTiers[sub.speed_tier].label, speed=Config.Internet.ServiceTiers[sub.speed_tier].speed, installDate=sub.last_payment, hubId=sub.provider, isServiceActive = isActive, propertyId = sub.property_id }
    end
    return nil
end

function Internet.BroadcastInternetHubStatusUpdate(hubId)
    local hubData = Internet.HubsState[hubId]
    if hubData then BroadcastNUIDataUpdate("internet_hub_status", { [hubId] = { label=hubData.label,isDown=hubData.isDown,cc=hubData.currentConnections,mc=hubData.config.maxConnections }}) end
end
function Internet.BroadcastAllInternetStatus()
    local data = { hubs = Internet.GetStatusForAllHubs() }
    BroadcastNUIDataUpdate("internet_status", data)
end
function Internet.BroadcastUserInternetStatus(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end
    -- This needs to be more nuanced. Which property's status to send?
    -- For now, let's assume it sends status for *a* property, or a general "you have a plan"
    -- The NUI on load will get all relevant property statuses.
    -- This broadcast is for when a specific player's active subscription status changes.
    local subDataForNUI = Internet.GetUserSubscriptionStatus(source) -- This needs refinement for property context
    TriggerClientEvent('smartutilities:client:updateNUIData', source, "internet_user_service", subDataForNUI)
    TriggerClientEvent('smartutilities:client:updateUserInternetService', source, subDataForNUI) -- also trigger the client var update
end

function Internet.CreateTables()
    if not exports.oxmysql then Logger.Error("oxmysql not found, cannot create Internet tables."); return end
    exports.oxmysql.execute([[
        CREATE TABLE IF NOT EXISTS `player_internet` (
            `citizenid` VARCHAR(64) DEFAULT NULL,
            `property_id` VARCHAR(64) NOT NULL,
            `provider` VARCHAR(32) DEFAULT NULL,
            `speed_tier` VARCHAR(32) DEFAULT NULL,
            `is_active` BOOLEAN DEFAULT FALSE,
            `last_payment` BIGINT DEFAULT 0,
            PRIMARY KEY (`property_id`)
        );
    ]], {})
    exports.oxmysql.execute([[
        CREATE TABLE IF NOT EXISTS `job_tickets` (
            `ticket_id` INT AUTO_INCREMENT PRIMARY KEY,
            `type` VARCHAR(32) DEFAULT NULL,
            `property_id` VARCHAR(64) DEFAULT NULL,
            `citizenid` VARCHAR(64) DEFAULT NULL,
            `description` TEXT DEFAULT NULL,
            `status` VARCHAR(16) DEFAULT 'open',
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ]], {})
    Logger.Info("Checked/Created 'player_internet' and 'job_tickets' tables.")
end

function Internet.SavePlayerSubscription(propertyId, data)
    if not exports.oxmysql or not data then return end
    exports.oxmysql.execute(
        "INSERT INTO `player_internet` (property_id, citizenid, provider, speed_tier, is_active, last_payment) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE citizenid = VALUES(citizenid), provider = VALUES(provider), speed_tier = VALUES(speed_tier), is_active = VALUES(is_active), last_payment = VALUES(last_payment)",
        {propertyId, data.citizenid, data.provider, data.speed_tier, data.is_active, data.last_payment}
    )
end

function Internet.LoadAllPlayerSubscriptions()
    if not exports.oxmysql then return end
    exports.oxmysql.query("SELECT * FROM `player_internet`", {}, function(results)
        if results then
            Internet.PlayerSubscriptions = {} -- Clear cache before loading
            local hubConnectionCounts = {}
            for _, result in ipairs(results) do
                Internet.PlayerSubscriptions[result.property_id] = result
                if result.is_active and result.provider and Internet.HubsState[result.provider] then
                    hubConnectionCounts[result.provider] = (hubConnectionCounts[result.provider] or 0) + 1
                end
            end
            for hubId, count in pairs(hubConnectionCounts) do
                if Internet.HubsState[hubId] then Internet.HubsState[hubId].currentConnections = count end
            end
            Logger.Info("Loaded " .. #results .. " player internet subscriptions from DB.")
            Internet.BroadcastAllInternetStatus()
        end
    end)
end

function Internet.LoadPendingInstallations()
    if not exports.oxmysql then return end
    exports.oxmysql.query("SELECT * FROM `job_tickets` WHERE `type` = 'internet_install' AND `status` = 'open'", {}, function(results)
        if results then
            Internet.PendingInstallations = {} -- Clear cache
            for _, result in ipairs(results) do
                Internet.PendingInstallations[result.property_id] = result
            end
            Logger.Info("Loaded " .. #results .. " pending internet installation tickets.")
        end
    end)
end

-- Server callback for client to get internet status for a property
RegisterServerEvent('smartutils:cb:getInternetStatus')
AddEventHandler('smartutils:cb:getInternetStatus', function(propertyId, cb)
    local sub = Internet.PlayerSubscriptions[propertyId]
    local status = { propertyId = propertyId, hasSubscription = false, isActive = false, tierLabel = nil, hubDown = true }
    if sub and sub.is_active then
        status.hasSubscription = true
        status.tierLabel = Config.Internet.ServiceTiers[sub.speed_tier].label
        local hubState = Internet.HubsState[sub.provider]
        status.hubDown = (hubState and hubState.isDown) or false
        status.isActive = not status.hubDown
        -- Could also check power to the hub here if power zones cover hub locations
    end
    cb(status)
end)

exports('IsInternetHubDown', function(hubId)
    if Internet.HubsState[hubId] then
        return Internet.HubsState[hubId].isDown
    end
    Logger.Warn("IsInternetHubDown: Hub ID '"..tostring(hubId).."' not found.")
    return true -- Default to true (down) if unknown, to be safe for dependent systems
end)

exports('GetInternetHubStatus', function(hubId)
    if Internet.HubsState[hubId] then
        local hub = Internet.HubsState[hubId]
        return { label = hub.label, isDown = hub.isDown, currentConnections = hub.currentConnections, maxConnections = hub.config.maxConnections }
    end
    Logger.Warn("GetInternetHubStatus: Hub ID '"..tostring(hubId).."' not found.")
    return nil
end)

exports('HasPropertyInternetService', function(propertyId)
    local sub = Internet.PlayerSubscriptions[propertyId]
    return sub and sub.is_active or false
end)

exports('GetPropertyInternetServiceDetails', function(propertyId)
    local sub = Internet.PlayerSubscriptions[propertyId]
    if sub and sub.is_active then
        local hubState = Internet.HubsState[sub.provider]
        local hubIsDown = (hubState and hubState.isDown) or false -- Assume hub down if not found
        return {
            property_id = sub.property_id,
            citizenid = sub.citizenid,
            tierId = sub.speed_tier,
            tierLabel = Config.Internet.ServiceTiers[sub.speed_tier].label,
            speed = Config.Internet.ServiceTiers[sub.speed_tier].speed,
            providerHubId = sub.provider,
            isServiceCurrentlyActive = not hubIsDown, -- True service status depends on hub
            hubStatus = hubState and { label = hubState.label, isDown = hubState.isDown } or { label = "Unknown Hub", isDown = true }
        }
    end
    return nil
end)


-- Trash Module Server Logic
Trash = {}
Trash.PublicBinStates = {} -- { binId = { config = {}, currentLoad = 0, lastCollected = 0 } }
Trash.DumpsterStates = {} -- { dumpsterId = { config = {}, currentLoad = 0, lastCollected = 0 } }
Trash.ActiveIllegalDumps = {} -- { dumpId = { coords, items = {}, spawnedTime, despawnTimer } }
local nextDumpId = 1

function Trash.Initialize()
    Logger.Info("Trash Module Initializing (Server)...")
    if not Config.Trash or not Config.Trash.Enabled then
        Logger.Warn("Trash module is disabled in config.")
        return
    end

    -- Initialize Public Bins
    for _, binConfig in ipairs(Config.Trash.PublicBins) do
        local binId = binConfig.id or ("bin@"..math.floor(binConfig.coords.x)..","..math.floor(binConfig.coords.y))
        Trash.PublicBinStates[binId] = {
            id = binId, config = binConfig, currentLoad = 0, -- TODO: Load from DB if persistent
            lastCollected = 0 -- Store os.time()
        }
        Logger.Debug("Initialized public trash bin: " .. binId)
    end
    -- Initialize Large Dumpsters
    for _, dumpsterConfig in ipairs(Config.Trash.LargeDumpsters or {}) do
        local dumpsterId = dumpsterConfig.id or ("dumpster@"..math.floor(dumpsterConfig.coords.x)..","..math.floor(dumpsterConfig.coords.y))
        Trash.DumpsterStates[dumpsterId] = {
            id = dumpsterId, config = dumpsterConfig, currentLoad = 0, -- TODO: Load from DB
            lastCollected = 0
        }
        Logger.Debug("Initialized large dumpster: " .. dumpsterId)
    end

    -- TODO: Load active illegal dump sites from DB
    SetInterval(Config.Trash.TickInterval or 600000, Trash.ProcessTick)
    Logger.Info("Trash Module Initialized. Bins: " .. tablelength(Trash.PublicBinStates) .. ", Dumpsters: " .. tablelength(Trash.DumpsterStates))
end

function Trash.ProcessTick()
    Logger.Debug("Trash Module: Processing tick...")
    local currentTime = os.time()
    -- Automated Collection Schedule (if enabled)
    if Config.Trash.CollectionSchedule.Enabled then
        for binId, state in pairs(Trash.PublicBinStates) do
            if currentTime - (state.lastCollected or 0) > (Config.Trash.CollectionSchedule.IntervalHours * 3600) then
                state.currentLoad = 0
                state.lastCollected = currentTime
                Logger.Debug("Automated collection for public bin: " .. binId)
                -- TODO: Broadcast bin status update
            end
        end
         for dumpsterId, state in pairs(Trash.DumpsterStates) do
            if currentTime - (state.lastCollected or 0) > (Config.Trash.CollectionSchedule.IntervalHours * 3600) then
                state.currentLoad = 0
                state.lastCollected = currentTime
                Logger.Debug("Automated collection for dumpster: " .. dumpsterId)
                -- TODO: Broadcast dumpster status update
            end
        end
    end
    -- TODO: Other periodic checks if needed
    Trash.BroadcastAllTrashStatus()
end

-- Called by player with sanitation job when interacting with a public bin
function Trash.CollectFromPublicBin(source, binId)
    local player = QBCore.Functions.GetPlayer(source)
    if not player or not HasJob(source, Config.Trash.CollectionJob.JobName) then
        ShowNotification(source, "You are not on sanitation duty.", "error") return false
    end
    local binState = Trash.PublicBinStates[binId]
    if not binState then ShowNotification(source, "This trash bin does not exist.", "error") return false end
    if binState.currentLoad == 0 then ShowNotification(source, "This bin is empty.", "info") return false end

    local amountCollected = binState.currentLoad
    local pay = Config.Trash.CollectionJob.PayPerPublicBin + (amountCollected * (Config.Trash.CollectionJob.WeightBonus or 0.05))
    player.Functions.AddMoney("cash", pay, "sanitation-job-collection")

    binState.currentLoad = 0
    binState.lastCollected = os.time()
    ShowNotification(source, string.format(Config.Trash.Notifications.TrashCollected, pay), "success")
    Logger.Info("Player " .. GetPlayerName(source) .. " collected " .. amountCollected .. "kg from bin " .. binId .. " for $" .. pay)
    -- TODO: Add to vehicle capacity, check if vehicle full
    Trash.BroadcastBinStatusUpdate(binId)
    return true
end
-- Similar function for Trash.CollectFromLargeDumpster

function Trash.HandleIllegalDumping(source, itemCoords, droppedItems) -- droppedItems = { {name="itemName", count=1}, ... }
    if not Config.Trash.IllegalDumping.Enabled then return end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end

    local dumpableItemCount = 0
    for _, itemData in ipairs(droppedItems) do
        for _, allowedDumpItem in ipairs(Config.Trash.IllegalDumping.DumpableItems) do
            if itemData.name == allowedDumpItem then
                dumpableItemCount = dumpableItemCount + (itemData.count or 1)
                break
            end
        end
    end

    if dumpableItemCount >= Config.Trash.IllegalDumping.MinItemsToFine then
        player.Functions.RemoveMoney("bank", Config.Trash.IllegalDumping.FineAmount, "illegal-dumping-fine")
        ShowNotification(source, string.format(Config.Trash.Notifications.DumpingDetected, "your location", Config.Trash.IllegalDumping.FineAmount), "error")
        Logger.Info("Player " .. GetPlayerName(source) .. " fined $" .. Config.Trash.IllegalDumping.FineAmount .. " for illegal dumping.")
        if Config.Trash.IllegalDumping.PoliceAlert then
            TriggerEvent("police:server:policeAlert", "Illegal dumping reported near coordinates: " .. json.encode(itemCoords))
        end
        -- Create a persistent dump site if needed (e.g. spawn props client-side)
        Trash.CreateIllegalDumpSite(itemCoords, droppedItems)
    end
end
-- This requires an event from your inventory when a player drops items.
-- Example: RegisterNetEvent('myInventory:itemDropped', function(itemName, count, coords) Trash.HandleIllegalDumping(source, coords, {{name=itemName, count=count}}) end)


function Trash.CreateIllegalDumpSite(coords, items)
    local dumpId = "dump_" .. nextDumpId; nextDumpId = nextDumpId + 1
    local despawnTime = math.random(Config.Trash.IllegalDumping.CleanupTime.min, Config.Trash.IllegalDumping.CleanupTime.max) * 1000
    local despawnTimer = SetTimeout(despawnTime, function() Trash.RemoveIllegalDumpSite(dumpId, "AutoDespawn") end)
    Trash.ActiveIllegalDumps[dumpId] = { id = dumpId, coords = coords, items = items, spawnedTime = GetGameTimer(), despawnTimer = despawnTimer }
    Logger.Info("Illegal dump site created: " .. dumpId .. " at " .. json.encode(coords))
    -- TODO: Trigger client event to spawn visual trash props at coords
    -- TriggerClientEvent('smartutilities:client:spawnDumpProps', -1, dumpId, coords, items)
    Trash.BroadcastIllegalDumpUpdate(dumpId, true)
end

function Trash.RemoveIllegalDumpSite(dumpId, reason)
    local dump = Trash.ActiveIllegalDumps[dumpId]
    if dump then
        if dump.despawnTimer then KillTimer(dump.despawnTimer) end
        Trash.ActiveIllegalDumps[dumpId] = nil
        Logger.Info("Illegal dump site " .. dumpId .. " removed. Reason: " .. (reason or "CleanedUp"))
        -- TODO: Trigger client event to remove visual trash props
        -- TriggerClientEvent('smartutilities:client:removeDumpProps', -1, dumpId)
        Trash.BroadcastIllegalDumpUpdate(dumpId, false)
    end
end

function Trash.GetStatusForAll()
    local status = { public_bins = {}, large_dumpsters = {}, illegal_dumps = {} }
    for id, state in pairs(Trash.PublicBinStates) do status.public_bins[id] = { id=id, label=state.config.label, load=state.currentLoad, capacity=state.config.capacity, coords=state.config.coords } end
    for id, state in pairs(Trash.DumpsterStates) do status.large_dumpsters[id] = { id=id, label=state.config.label, load=state.currentLoad, capacity=state.config.capacity, coords=state.config.coords } end
    for id, dumpData in pairs(Trash.ActiveIllegalDumps) do table.insert(status.illegal_dumps, {id=id, coords=dumpData.coords, items=dumpData.items}) end
    return status
end

function Trash.BroadcastBinStatusUpdate(binId) -- Can be used for dumpsters too if structure is similar
    local state = Trash.PublicBinStates[binId] or Trash.DumpsterStates[binId]
    if state then BroadcastNUIDataUpdate("trash_bin_status", {[state.id] = {load=state.currentLoad, capacity=state.config.capacity}}) end
end
function Trash.BroadcastIllegalDumpUpdate(dumpId, isActive)
     BroadcastNUIDataUpdate("trash_illegal_dump_update", {id=dumpId, isActive=isActive, coords = isActive and Trash.ActiveIllegalDumps[dumpId].coords or nil})
end
function Trash.BroadcastAllTrashStatus() BroadcastNUIDataUpdate("trash_status", Trash.GetStatusForAll()) end

function tablelength(T) local count = 0; for _ in pairs(T) do count = count + 1 end return count end


-- Admin Commands Registration
Citizen.CreateThread(function()
    while not QBCore do Citizen.Wait(100) end

    QBCore.Commands.Add(Config.Admin.ForceBlackout.Command, "Force blackout.", {{name="zone", help="Zone ID"},{name="duration",help="Duration (s)"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.ForceBlackout.Group})then return end local z=a[1] local d=tonumber(a[2]) if not z then ShowNotification(s,"Usage: /"..Config.Admin.ForceBlackout.Command.." <zone> [duration]","error")return end local tZ=nil;for i,zd in pairs(Config.Power.Zones)do if string.lower(i)==string.lower(z)or(zd.label and string.lower(zd.label)==string.lower(z))then tZ=i;break;end;end;if not tZ then ShowNotification(s,"Zone '"..z.."' not found.","error")return end Power.ForceBlackout(s,tZ,d) end, Config.Admin.ForceBlackout.Group)
    QBCore.Commands.Add(Config.Admin.RepairPower.Command, "Repair power zone.", {{name="zone", help="Zone ID"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.RepairPower.Group})then return end local z=a[1] if not z then ShowNotification(s,"Usage: /"..Config.Admin.RepairPower.Command.." <zone>","error")return end local tZ=nil;for i,zd in pairs(Config.Power.Zones)do if string.lower(i)==string.lower(z)or(zd.label and string.lower(zd.label)==string.lower(z))then tZ=i;break;end;end;if not tZ then ShowNotification(s,"Zone '"..z.."' not found.","error")return end Power.RepairPowerZone(s,tZ) end, Config.Admin.RepairPower.Group)
    QBCore.Commands.Add(Config.Admin.ForceWaterLeak.Command, "Force water leak.", {{name="source",help="Source ID (optional)"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.ForceWaterLeak.Group})then return end local srcN=a[1] local tS=nil;if srcN then for i,sd in pairs(Config.Water.Sources)do if string.lower(i)==string.lower(srcN)or(sd.label and string.lower(sd.label)==string.lower(srcN))then tS=i;break;end;end;if not tS then ShowNotification(s,"Source '"..srcN.."' not found.","error")return end;end;Water.ForceLeak(s,tS) end, Config.Admin.ForceWaterLeak.Group)
    QBCore.Commands.Add(Config.Admin.RepairWaterLeak.Command, "Repair water leak(s).", {{name="leakid", help="'all' or leak ID"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.RepairWaterLeak.Group})then return end local lId=a[1] if not lId then ShowNotification(s,"Usage: /"..Config.Admin.RepairWaterLeak.Command.." <leakId|'all'>","error")return end Water.RepairLeak(s,lId) end, Config.Admin.RepairWaterLeak.Group)
    QBCore.Commands.Add(Config.Admin.ForceInternetOutage.Command, "Force internet hub outage.", {{name="hub", help="Hub ID"},{name="duration",help="Duration (s)"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.ForceInternetOutage.Group})then return end local hN=a[1] local d=tonumber(a[2]) if not hN then ShowNotification(s,"Usage: /"..Config.Admin.ForceInternetOutage.Command.." <hub> [duration]","error")return end local tH=Internet.GetHubIdByName(hN); if not tH then ShowNotification(s,"Hub '"..hN.."' not found.","error")return end Internet.ForceOutage(s,tH,d) end, Config.Admin.ForceInternetOutage.Group)
    QBCore.Commands.Add(Config.Admin.RepairInternet.Command, "Repair internet hub.", {{name="hub", help="Hub ID"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.RepairInternet.Group})then return end local hN=a[1] if not hN then ShowNotification(s,"Usage: /"..Config.Admin.RepairInternet.Command.." <hub>","error")return end local tH=Internet.GetHubIdByName(hN); if not tH then ShowNotification(s,"Hub '"..hN.."' not found.","error")return end Internet.RepairHub(s,tH) end, Config.Admin.RepairInternet.Group)
    RegisterCommand("installinternet", Internet.InstallCommand, true)
    QBCore.Commands.Add(Config.Admin.SpawnTrash.Command, "Spawn an illegal dump site (Admin).", {{name="items", help="Optional: Item names, comma-sep (e.g., trash_bag_filled,broken_tv)"}}, true, function(s,a) if not IsAdmin(s,{Config.Admin.SpawnTrash.Group})then return end local player = QBCore.Functions.GetPlayer(s) local itemsToDump = {}; if a[1] then for _,itemName in ipairs(string.split(a[1],",")) do table.insert(itemsToDump, {name=string.trim(itemName), count=1}) end else table.insert(itemsToDump, {name="trash_bag_filled", count=math.random(2,4)}) end Trash.CreateIllegalDumpSite(GetEntityCoords(player.PlayerData.ped), itemsToDump); ShowNotification(s,"Spawned illegal dump site.", "success") end, Config.Admin.SpawnTrash.Group)
    QBCore.Commands.Add(Config.Admin.ClearAllTrash.Command, "Clear all illegal dump sites (Admin).", {}, true, function(s,a) if not IsAdmin(s,{Config.Admin.ClearAllTrash.Group})then return end local count=0; for id,_ in pairs(Trash.ActiveIllegalDumps)do Trash.RemoveIllegalDumpSite(id, "AdminClearAll"); count=count+1; end ShowNotification(s,"Cleared "..count.." illegal dump sites.", "success") end, Config.Admin.ClearAllTrash.Group)

    RegisterNetEvent('smartutilities:admin:forceBlackout', function(data) local s=source; if not IsAdmin(s,{Config.Admin.ForceBlackout.Group})then return end if data and data.zoneId then Power.ForceBlackout(s,data.zoneId,nil)end end)
    RegisterNetEvent('smartutilities:admin:repairPowerZone', function(data) local s=source; if not IsAdmin(s,{Config.Admin.RepairPower.Group})then return end if data and data.zoneId then Power.RepairPowerZone(s,data.zoneId)end end)
    RegisterNetEvent('smartutilities:admin:forceWaterLeak', function(data) local s=source; if not IsAdmin(s,{Config.Admin.ForceWaterLeak.Group})then return end Water.ForceLeak(s, data and data.sourceId or nil) end)
    RegisterNetEvent('smartutilities:admin:forceInternetOutage', function(data) local s=source; if not IsAdmin(s,{Config.Admin.ForceInternetOutage.Group})then return end if data and data.hubId then Internet.ForceOutage(s,data.hubId,nil)end end)
    RegisterNetEvent('smartutilities:admin:spawnTrash', function() local s=source; if not IsAdmin(s, {Config.Admin.SpawnTrash.Group}) then return end local player = QBCore.Functions.GetPlayer(s); Trash.CreateIllegalDumpSite(GetEntityCoords(player.PlayerData.ped), {{name="trash_bag_filled", count=math.random(2,3)}}); ShowNotification(s, "Spawned random trash pile.", "success") end)

    RegisterNetEvent('smartutilities:user:requestInternetInstall', function(data)
        local src = source
        if data and data.tierId and data.propertyId then
            Internet.RequestInstallation(src, data.tierId, data.propertyId)
        else
            ShowNotification(src, "Missing tier or property ID for internet installation request.", "error")
        end
    end)

    -- Event from inventory when player drops items (HYPOTHETICAL - needs actual inventory event)
    -- RegisterNetEvent('qb-inventory:itemDropped', function(itemName, amount, itemData, dropCoords)
    --    if Config.Trash.Enabled and Config.Trash.IllegalDumping.Enabled then
    --        local isDumpable = false
    --        for _, dumpable in ipairs(Config.Trash.IllegalDumping.DumpableItems) do
    --            if itemName == dumpable then isDumpable = true; break; end
    --        end
    --        if isDumpable then
    --            Trash.HandleIllegalDumping(source, dropCoords, {{name = itemName, count = amount}})
    --        end
    --    end
    -- end)

    -- Event for player collecting trash from a public bin
    RegisterNetEvent('smartutilities:server:collectPublicTrashBin', function(binId)
        Trash.CollectFromPublicBin(source, binId)
    end)
end)

Logger.Info("SmartUtilities Server Script Loaded. Waiting for framework and DB initialization.")

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        Logger.Info("SmartUtilities resource stopping. Performing cleanup and saving data...")
        for zoneId, _ in pairs(Power.ZonesState or {}) do Power.SaveZoneStateToDB(zoneId) end
        -- for sourceId, _ in pairs(Water.SourcesState or {}) do Water.SaveSourceStateToDB(sourceId) end
        for hubId, _ in pairs(Internet.HubsState or {}) do
            -- Internet.SaveHubStateToDB(hubId) -- Placeholder for saving hub operational state
        end
        -- No need to explicitly save all subscriptions here if they are saved on change.
        Logger.Info("Cleanup complete (actual data saving for hubs/sources/etc. is mostly placeholder). Goodbye!")
    end
end)
