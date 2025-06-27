-- Shared Objects & Framework
QBCore = nil
ESX = nil
PlayerJob = nil -- Store player's job

-- Global state
TabletOpen = false

-- Initialize Logger
-- Logger is loaded as a shared script, so it should be available.
-- We call Initialize() once QBCore/ESX object is confirmed or config is known to be loaded.
Citizen.CreateThread(function()
    if Config.Framework == 'qb-core' then
        QBCore = exports['qb-core']:GetCoreObject()
        if QBCore then
            Logger.Initialize() -- Initialize logger now that Config is definitely loaded
            Logger.Info("QBCore object loaded on client.")
            -- Get initial job
            local player = QBCore.Functions.GetPlayerData()
            if player then PlayerJob = player.job.name end
        else
            Logger.Error("QBCore object failed to load on client.")
        end
    elseif Config.Framework == 'esx' then
        -- ESX loading
        local status, esxSharedObject = pcall(function() return exports.esx:getSharedObject() end)
        if status and esxSharedObject then
            ESX = esxSharedObject
            Logger.Initialize()
            Logger.Info("ESX Shared Object loaded on client.")
            -- TODO: Get initial job for ESX if needed for client side checks
        else
            Logger.Error("ESX Shared Object failed to load on client.")
            -- Attempt to load ESX object if not immediately available (older ESX versions)
            Citizen.CreateThread(function()
                while ESX == nil do
                    TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
                    Citizen.Wait(100)
                end
                if ESX then
                    Logger.Initialize()
                    Logger.Info("ESX Shared Object loaded on client (delayed).")
                     -- TODO: Get initial job for ESX
                else
                    Logger.Error("ESX Shared Object still not loaded after delay.")
                end
            end)
        end
    else
        Logger.Initialize()
        Logger.Warn("No framework specified or framework not recognized. Some features might not work.")
    end
end)


-- NUI Tablet Control
RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    if Config.Framework == 'qb-core' then
        QBCore = exports['qb-core']:GetCoreObject() -- Ensure it's loaded
        local player = QBCore.Functions.GetPlayerData()
        if player then PlayerJob = player.job.name end
        Logger.Info("Player loaded, QBCore confirmed.")
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate')
AddEventHandler('QBCore:Client:OnJobUpdate', function(job)
    if Config.Framework == 'qb-core' then
        PlayerJob = job.name
        Logger.Debug("Player job updated to: " .. PlayerJob)
    end
end)

-- ESX Job update (if applicable)
RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    if Config.Framework == 'esx' then
        PlayerJob = job.name
        Logger.Debug("Player job updated to: " .. PlayerJob)
    end
end)

-- Open/Close Tablet
function OpenTablet()
    if TabletOpen then return end
    -- Permission Check (basic example, refine with IsAdmin from config if needed server-side first)
    if Config.Tablet.AdminOnly then
        -- This check ideally should be confirmed server-side before opening.
        -- For now, a client-side check or rely on server to not send data if not admin.
        -- A robust way: TriggerServerEvent('smartutilities:requestOpenTablet'), server checks perms, then triggers client event to open.
        Logger.Info("Tablet is admin only. Implement server-side permission check before sending NUI_SHOW.")
        -- For now, let's assume if Config.Tablet.AdminOnly is true, we need a server check.
        -- This is a placeholder for a proper permission check.
        -- For simplicity in this stage, we'll allow it if client thinks it's admin only, but this is not secure.
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ type = "NUI_SHOW" })
    TabletOpen = true
    Logger.Debug("Tablet opened.")

    -- TODO: Send initial data to NUI (e.g., current status of utilities)
    -- TriggerServerEvent('smartutilities:getInitialNUIData')
end

function CloseTablet()
    if not TabletOpen then return end
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "NUI_HIDE" })
    TabletOpen = false
    Logger.Debug("Tablet closed.")
end

-- Register command and key for tablet
RegisterCommand(Config.Tablet.Command, function()
    if Config.Tablet.AdminOnly then
        -- Ask server if we have permission
        TriggerServerEvent('smartutilities:requestTabletOpenPermission')
    else
        OpenTablet()
    end
end, false) -- false = not restricted command

RegisterKeyMapping(Config.Tablet.Command, "Open Utilities Tablet", "keyboard", Config.Tablet.Key)

-- Event from server to actually open the tablet (after permission check)
RegisterNetEvent('smartutilities:client:openTablet')
AddEventHandler('smartutilities:client:openTablet', function()
    OpenTablet()
end)


-- NUI Message Handlers
RegisterNUICallback('NUI_READY', function(data, cb)
    Logger.Info("NUI is ready. Requesting initial data.")
    TriggerServerEvent('smartutilities:nui:getInitialData')
    cb('ok')
end)

RegisterNUICallback('NUI_CLOSE', function(data, cb)
    CloseTablet()
    cb('ok')
end)

-- Handle ESC key to close tablet
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100) -- Reduced frequency for better performance
        if TabletOpen and IsControlJustReleased(0, 322) and Config.Tablet.CloseOnEscape then -- 322 is ESC key for Windows, might need adjustment for Linux
            CloseTablet()
        end
    end
end)

-- Placeholder for receiving data updates from server to pass to NUI
RegisterNetEvent('smartutilities:client:updateNUIData')
AddEventHandler('smartutilities:client:updateNUIData', function(dataType, data)
    if TabletOpen then
        SendNUIMessage({
            type = "UPDATE_DATA",
            dataType = dataType, -- e.g., "power_status", "water_levels"
            payload = data
        })
        Logger.Debug("Sent data update to NUI: " .. dataType)
    end
end)


-- Power Module Client Logic
local affectedStreetLights = {} -- Store streetlights affected by blackouts { entity = entity, originalState = originalState }
local isNight = false

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000) -- Check every 5 seconds
        local currentHour = GetClockHours()
        isNight = (currentHour >= 20 or currentHour < 7) -- Define night time for street lights
    end
end)

RegisterNetEvent('smartutilities:client:powerBlackoutEffect')
AddEventHandler('smartutilities:client:powerBlackoutEffect', function(zoneId, isBlackout, zoneCoords, zoneRadius, affectedEntityTypes)
    Logger.Info("Received power status for zone " .. zoneId .. ": Blackout = " .. tostring(isBlackout) .. " Coords: " .. json.encode(zoneCoords) .. " Radius: " .. zoneRadius)

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    if not zoneCoords or not zoneRadius then
        Logger.Warn("Zone coords or radius missing for power effect: " .. zoneId)
        return
    end

    local distanceToZoneCenter = #(playerCoords - zoneCoords)

    -- Only apply street light effects if player is somewhat close to the zone or within it.
    -- This is a simple distance check; PolyZone checks would be more accurate for zone boundaries.
    if distanceToZoneCenter < zoneRadius + 200.0 then -- Apply if within radius + buffer
        if affectedEntityTypes.streetLights then
            Logger.Debug("Processing street lights for zone " .. zoneId .. ", Blackout: " .. tostring(isBlackout))
            ProcessStreetLights(zoneId, isBlackout, zoneCoords, zoneRadius)
        end
        -- TODO: Add effects for ATMs, specific buildings if client-side control is needed.
    end

    -- Traffic light control (Example integration with qb-trafficlights or similar)
    if affectedEntityTypes.trafficLights and Config.Power.TrafficLightControllingResource then
        local resource = GetResourceState(Config.Power.TrafficLightControllingResource)
        if resource == "started" then
            -- This export name is hypothetical. You'd need to check the actual traffic light script.
            exports[Config.Power.TrafficLightControllingResource]:SetZonePowerStatus(zoneId, not isBlackout)
            Logger.Debug("Notified " .. Config.Power.TrafficLightControllingResource .. " about power change in " .. zoneId)
        else
            Logger.Warn(Config.Power.TrafficLightControllingResource .. " not started. Cannot control traffic lights for zone " .. zoneId)
        end
    end
end)

function ProcessStreetLights(zoneId, isBlackout, zoneCoords, zoneRadius)
    if isBlackout then
        -- Turn off street lights in the area
        -- Finding all street lights in a radius can be performance intensive.
        -- A better approach might be to have predefined light entities or use a system that manages them.
        -- For simplicity, this example might not be exhaustive or super performant.
        -- This is a very basic example. Real street light control is complex.
        SetArtificialLightsState(true) -- This native is more about global state, not individual lights.
        Logger.Info("Simulating street lights OFF in zone " .. zoneId .. " due to blackout. (Actual individual light control is complex and placeholder here)")
        -- A more detailed implementation would iterate over known street light props/entities:
        -- For example, if you have a list of street light entities:
        -- For _, lightEntity in ipairs(GetStreetLightsInZone(zoneCoords, zoneRadius)) do
        --    if DoesEntityExist(lightEntity) then
        --        table.insert(affectedStreetLights, { entity = lightEntity, originalState = GetEntityState(lightEntity) }) -- Fictional GetEntityState
        --        SetEntityLights(lightEntity, false) -- Fictional native
        --        NetworkSetEntityInvisible(lightEntity, true) -- This is too aggressive, just an example
        --    end
        -- End
        -- For now, we'll just log it as a proper implementation requires a lot more infrastructure
        -- or integration with a dedicated street light script.
    else
        -- Turn on street lights in the area
        SetArtificialLightsState(false) -- Again, global state.
        Logger.Info("Simulating street lights ON in zone " .. zoneId .. " as power is restored.")
        -- Restore any lights we specifically turned off
        for i = #affectedStreetLights, 1, -1 do
            local lightData = affectedStreetLights[i]
            if DoesEntityExist(lightData.entity) then
                -- Restore lightData.originalState
                -- SetEntityLights(lightData.entity, true) -- Fictional
            end
            table.remove(affectedStreetLights, i)
        end
    end
end

-- Power sabotage minigame implementation
RegisterNetEvent('smartutilities:client:startPowerSabotageMinigame')
AddEventHandler('smartutilities:client:startPowerSabotageMinigame', function(zoneId, difficulty)
    Logger.Debug("Starting power sabotage minigame for zone: " .. zoneId .. " difficulty: " .. difficulty)
    QBCore.Functions.Notify("Initiating power grid sabotage...", "primary")
    
    Minigames.GetMinigameForAction("repair_electrical", difficulty or 3, function(success)
        if success then
            QBCore.Functions.Notify("Power grid successfully compromised!", "success")
            Logger.Info("Player successfully sabotaged power zone: " .. zoneId)
        else
            QBCore.Functions.Notify("Sabotage failed! Security systems detected the intrusion.", "error")
            Logger.Info("Player failed power sabotage on zone: " .. zoneId)
        end
        
        TriggerServerEvent('smartutilities:server:finishPowerSabotageMinigame', zoneId, success)
    end)
end)


-- Water Module Client Logic
local activeLeakParticles = {} -- { [leakId] = particleHandle }

RegisterNetEvent('smartutilities:client:waterLeakEffect')
AddEventHandler('smartutilities:client:waterLeakEffect', function(leakId, coords, isLeaking)
    Logger.Info("Water leak effect update for leak " .. leakId .. ": Leaking = " .. tostring(isLeaking) .. " at " .. json.encode(coords))

    if isLeaking and Config.Water.PuddleEffect.Enabled then
        if activeLeakParticles[leakId] then return end -- Already active

        RequestNamedPtfxAsset(Config.Water.PuddleEffect.ParticleDict)
        Citizen.CreateThread(function() -- Use a new thread to avoid blocking if asset loading is slow
            local attempts = 0
            while not HasNamedPtfxAssetLoaded(Config.Water.PuddleEffect.ParticleDict) and attempts < 100 do -- Max 5 seconds wait
                Citizen.Wait(50)
                attempts = attempts + 1
            end

            if HasNamedPtfxAssetLoaded(Config.Water.PuddleEffect.ParticleDict) then
                UseParticleFxAssetNextCall(Config.Water.PuddleEffect.ParticleDict)
                -- Ensure coords are numbers, not a table from JSON deserialization without proper conversion
                local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
                if not x or not y or not z then
                    Logger.Error("Invalid coordinates for water leak particle: " .. json.encode(coords))
                    return
                end

                -- Check if player is near before creating intensive effects
                local playerPed = PlayerPedId()
                local playerCoords = GetEntityCoords(playerPed)
                if #(playerCoords - vec3(x,y,z)) < (Config.Water.LeakLocationRadius + 100.0) then -- Only spawn if relatively close
                    local particleHandle = StartParticleFxLoopedAtCoord(
                        Config.Water.PuddleEffect.ParticleName,
                        x, y, z,
                        0.0, 0.0, 0.0, -- rotation
                        Config.Water.PuddleEffect.Scale,
                        false, false, false, false -- x,y,z axis, unknown1, unknown2
                    )
                    activeLeakParticles[leakId] = particleHandle
                    particleData[leakId] = {
                        handle = particleHandle,
                        coords = vec3(x, y, z),
                        lastCheck = GetGameTimer()
                    }
                    Logger.Debug("Started puddle particle effect for leak: " .. leakId .. " Handle: " .. particleHandle)
                else
                    Logger.Debug("Player too far from leak " .. leakId .. " to spawn particle effect.")
                end
            else
                Logger.Warn("Failed to load particle asset '" .. Config.Water.PuddleEffect.ParticleDict .. "' for water leak.")
            end
        end)
    else
        -- Stop particle effect for this leakId
        if activeLeakParticles[leakId] then
            local particleHandle = activeLeakParticles[leakId]
            if DoesParticleFxLoopedExist(particleHandle) then
                StopParticleFxLooped(particleHandle, false)
            end
            RemoveParticleFx(particleHandle, false) -- Ensure it's fully removed
            activeLeakParticles[leakId] = nil
            particleData[leakId] = nil -- Clean up stored data
            Logger.Debug("Stopped puddle particle effect for leak: " .. leakId .. " Handle: " .. particleHandle)
        end
    end
end)

-- Store particle data with coordinates for cleanup
local particleData = {} -- { [leakId] = { handle = handle, coords = coords, lastCheck = time } }

-- Clean up particles if player moves too far away from them (optimization)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(15000) -- Check every 15 seconds
        if next(activeLeakParticles) == nil then 
            Citizen.Wait(30000) -- If no particles, check much less often
            goto continue
        end

        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local currentTime = GetGameTimer()

        for leakId, particleHandle in pairs(activeLeakParticles) do
            local data = particleData[leakId]
            if data then
                -- Check if player is too far from particle (cleanup for performance)
                local distance = #(playerCoords - data.coords)
                if distance > 500.0 then -- 500 units away, clean up particle
                    if DoesParticleFxLoopedExist(particleHandle) then
                        StopParticleFxLooped(particleHandle, false)
                        RemoveParticleFx(particleHandle, false)
                    end
                    activeLeakParticles[leakId] = nil
                    particleData[leakId] = nil
                    Logger.Debug("Cleaned up distant particle for leak " .. leakId)
                end
            else
                -- No data stored, check if particle still exists
                if not DoesParticleFxLoopedExist(particleHandle) then
                    activeLeakParticles[leakId] = nil
                    Logger.Debug("Particle for leak " .. leakId .. " no longer exists, removed from tracking.")
                end
            end
        end
        
        ::continue::
    end
end)

-- Water repair minigame implementation
RegisterNetEvent('smartutilities:client:startWaterRepairMinigame')
AddEventHandler('smartutilities:client:startWaterRepairMinigame', function(leakId, difficulty)
    Logger.Debug("Starting water repair minigame for leak: " .. leakId .. " difficulty: " .. difficulty)
    QBCore.Functions.Notify("Beginning water leak repair...", "primary")
    
    Minigames.GetMinigameForAction("repair_mechanical", difficulty or 2, function(success)
        if success then
            QBCore.Functions.Notify("Water leak successfully repaired!", "success")
            Logger.Info("Player successfully repaired water leak: " .. leakId)
        else
            QBCore.Functions.Notify("Repair failed! The leak is still active.", "error")
            Logger.Info("Player failed to repair water leak: " .. leakId)
        end
        
        TriggerServerEvent('smartutilities:server:finishWaterRepair', leakId, success)
    end)
end)

-- Water meter installation minigame
RegisterNetEvent('smartutilities:client:startWaterMeterInstall')
AddEventHandler('smartutilities:client:startWaterMeterInstall', function(sourceId, difficulty)
    Logger.Debug("Starting water meter installation for source: " .. sourceId)
    QBCore.Functions.Notify("Installing water monitoring equipment...", "primary")
    
    Minigames.GetMinigameForAction("memory", difficulty or 3, function(success)
        if success then
            QBCore.Functions.Notify("Water meter installed successfully!", "success")
        else
            QBCore.Functions.Notify("Installation failed! Equipment may be damaged.", "error")
        end
        
        TriggerServerEvent('smartutilities:server:finishWaterMeterInstall', sourceId, success)
    end)
end)


-- Internet Module Client Logic
local IsUserInternetActive = true -- Assume active by default, updated by server

RegisterNetEvent('smartutilities:client:internetStatusChanged')
AddEventHandler('smartutilities:client:internetStatusChanged', function(hubId, isDown)
    -- This event is generic for a hub status change.
    -- The NUI will get more detailed updates directly (e.g. internet_user_service)
    Logger.Info("Internet Hub " .. hubId .. " status changed. Is Down: " .. tostring(isDown))
    -- If this specific hub affects the player, update their local internet status
    -- This requires the client to know which hub they are connected to, or for the server to send a specific player update.
    -- For now, NUI data 'internet_user_service' is the primary source for player's own status.
end)

-- Event to update the player's own internet service status specifically
RegisterNetEvent('smartutilities:client:updateUserInternetService')
AddEventHandler('smartutilities:client:updateUserInternetService', function(serviceStatus)
    if serviceStatus and serviceStatus.isServiceActive ~= nil then
        IsUserInternetActive = serviceStatus.isServiceActive
        Logger.Info("My Internet Service Active: " .. tostring(IsUserInternetActive) .. (serviceStatus.tierLabel and (" - Tier: " .. serviceStatus.tierLabel) or ""))
        -- TODO: Based on IsUserInternetActive, enable/disable features
        -- e.g., If !IsUserInternetActive then DisableBankAccess(), DisableCCTV(), etc.
        if not IsUserInternetActive then
            ShowClientNotification("Your internet connection is currently down!", "error")
        else
            ShowClientNotification("Your internet connection is active.", "success")
        end
    elseif serviceStatus == nil then -- No active service
        IsUserInternetActive = false
        Logger.Info("No active internet service for this player.")
        ShowClientNotification("You do not have an active internet plan.", "info")
    end
end)

function DoesPlayerHaveInternet()
    return IsUserInternetActive
end
exports('DoesPlayerHaveInternet', DoesPlayerHaveInternet)


-- Internet hacking minigame implementation
RegisterNetEvent('smartutilities:client:startInternetHackMinigame')
AddEventHandler('smartutilities:client:startInternetHackMinigame', function(hubId, difficulty)
    Logger.Debug("Starting internet hack minigame for hub: " .. hubId .. " difficulty: " .. difficulty)
    QBCore.Functions.Notify("Initiating hack on hub: " .. hubId, "primary")
    
    -- Start the hacking minigame
    Minigames.HackingGame(difficulty or 3, function(success)
        if success then
            QBCore.Functions.Notify("Hack successful! Hub compromised.", "success")
            Logger.Info("Player successfully hacked hub: " .. hubId)
        else
            QBCore.Functions.Notify("Hack failed! Security detected the intrusion.", "error")
            Logger.Info("Player failed to hack hub: " .. hubId)
        end
        
        TriggerServerEvent('smartutilities:server:finishInternetHack', hubId, success)
    end)
end)

-- TODO: Client-side logic for internet installation (technician job)
-- This would involve UI prompts, targeting, and potentially a minigame for the technician.


-- Helper for client-side notifications if QBCore/ESX not fully loaded or for standalone
function ShowClientNotification(message, type)
    if QBCore and QBCore.Functions.Notify then
        QBCore.Functions.Notify(message, type, 5000)
    elseif ESX and ESX.ShowNotification then
        ESX.ShowNotification(message, type)
    else
        SetNotificationTextEntry("STRING")
        AddTextComponentString(message)
        DrawNotification(false, true)
        PlaySoundFrontend(-1, "INFO", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end


-- Trash Module Client Logic
local nearbyTrashBins = {} -- Store bin entities if needed for interaction, or just use coords
local activeDumpSiteProps = {} -- { [dumpId] = {prop1, prop2, ...} }

Citizen.CreateThread(function()
    -- Periodically check for nearby trash bins if using target/interaction systems
    while true do
        Citizen.Wait(2000) -- Check every 2 seconds
        if not Config.Trash.Enabled then Citizen.Wait(30000); goto continue end

        local playerPed = PlayerPedId()
        local coords = GetEntityCoords(playerPed)
        nearbyTrashBins = {} -- Clear and repopulate

        for binId, binData in pairs(Config.Trash.PublicBins) do -- Iterate over Config, not server state for locations
            if #(coords - binData.coords) < (Config.Trash.CollectionJob.InteractionRadius + 5.0) then
                -- TODO: Use a targeting system (e.g., qb-target, ox_target) to show an interaction option
                -- For now, this just identifies nearby bins. Player might use a command /collecttrashwhilelookingatbin
                -- Or a key press when near a specific bin model.
                -- Example using qb-target (conceptual):
                -- exports['qb-target']:AddCircleZone("trashbin_"..binId, binData.coords, Config.Trash.CollectionJob.InteractionRadius, {
                --    name="trashbin_"..binId, debugPoly=Config.Debug, useZ=true,
                -- }, {
                --    options = {
                --        { event = "smartutilities:client:collectPublicTrash", icon = "fas fa-recycle", label = "Collect Trash", binId = binId, job = Config.Trash.CollectionJob.JobName },
                --    },
                --    distance = Config.Trash.CollectionJob.InteractionRadius
                -- })
                table.insert(nearbyTrashBins, {id = binId, coords = binData.coords, model = binData.model})
            else
                -- exports['qb-target']:RemoveZone("trashbin_"..binId)
            end
        end
        -- Similar loop for Config.Trash.LargeDumpsters

        ::continue::
    end
end)

RegisterNetEvent('smartutilities:client:collectPublicTrash', function(data)
    if not data or not data.binId then return end
    -- TODO: Add checks, e.g., if player is in a trash vehicle, has correct job.
    -- Server will do final validation.
    ShowClientNotification("Attempting to collect trash from bin: " .. data.binId, "info")
    TriggerServerEvent('smartutilities:server:collectPublicTrashBin', data.binId)
end)


-- Illegal Dumping Visuals (Placeholder)
RegisterNetEvent('smartutilities:client:spawnDumpProps')
AddEventHandler('smartutilities:client:spawnDumpProps', function(dumpId, dumpCoords, items)
    if activeDumpSiteProps[dumpId] then return end -- Already spawned
    Logger.Debug("Spawning illegal dump props for ID: " .. dumpId .. " at " .. json.encode(dumpCoords))
    activeDumpSiteProps[dumpId] = {}
    -- Example: Spawn a few generic trash bag props. A real system might vary props based on 'items'.
    local trashBagModel = `prop_cs_bin_01_lid` -- Using a lid as a placeholder for a small trash item/bag
    RequestModel(trashBagModel)
    Citizen.CreateThread(function()
        local attempts = 0
        while not HasModelLoaded(trashBagModel) and attempts < 100 do Citizen.Wait(50); attempts = attempts + 1 end
        if HasModelLoaded(trashBagModel) then
            for i = 1, math.min(#items, 3) do -- Spawn up to 3 props
                local randomOffset = vec3(math.random(-100,100)/100, math.random(-100,100)/100, 0.0)
                local spawnPos = dumpCoords + randomOffset
                local prop = CreateObject(trashBagModel, spawnPos.x, spawnPos.y, spawnPos.z, true, true, false)
                PlaceObjectOnGroundProperly(prop)
                SetEntityAsMissionEntity(prop, true, true) -- So it doesn't despawn easily
                table.insert(activeDumpSiteProps[dumpId], prop)
            end
        end
        SetModelAsNoLongerNeeded(trashBagModel)
    end)
end)

RegisterNetEvent('smartutilities:client:removeDumpProps')
AddEventHandler('smartutilities:client:removeDumpProps', function(dumpId)
    if activeDumpSiteProps[dumpId] then
        Logger.Debug("Removing illegal dump props for ID: " .. dumpId)
        for _, propHandle in ipairs(activeDumpSiteProps[dumpId]) do
            if DoesEntityExist(propHandle) then
                DeleteEntity(propHandle)
            end
        end
        activeDumpSiteProps[dumpId] = nil
    end
end)

-- Report Dumping Command (Client-side part if any, mostly server)
RegisterCommand(Config.Trash.IllegalDumping.ReportCommand, function(source, args, rawCommand)
    -- Client could send more precise coords or info if needed, or just trigger server event.
    TriggerServerEvent('smartutilities:server:reportIllegalDumping', GetEntityCoords(PlayerPedId()))
    ShowClientNotification("Illegal dumping reported. Authorities have been notified.", "success")
end, false)


Logger.Info("SmartUtilities Client Script Loaded.")

-- Example NUI interaction (sending a message from Lua to JS)
-- Citizen.CreateThread(function()
--     Citizen.Wait(10000) -- Wait 10 seconds
--     if TabletOpen then
--         SendNUIMessage({
--             type = "SHOW_NOTIFICATION",
--             message = "This is a test notification from client.lua!"
--         })
--     end
-- end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    Logger.Info("Cleaning up SmartUtilities client resources...")
    
    -- Clean up all active particles
    for leakId, particleHandle in pairs(activeLeakParticles) do
        if DoesParticleFxLoopedExist(particleHandle) then
            StopParticleFxLooped(particleHandle, false)
            RemoveParticleFx(particleHandle, false)
        end
    end
    activeLeakParticles = {}
    particleData = {}
    
    -- Close any open NUI
    if TabletOpen then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "closeTablet" })
        TabletOpen = false
    end
    
    Logger.Info("SmartUtilities client cleanup completed")
end)

-- Admin test event handlers
RegisterNetEvent('smartutilities:client:runTests')
AddEventHandler('smartutilities:client:runTests', function()
    QBCore.Functions.Notify("Running client-side performance tests...", "info")
    
    -- Test zone manager
    local testZone = {
        coords = GetEntityCoords(PlayerPedId()),
        radius = 50.0,
        type = "test",
        onEnter = function() 
            QBCore.Functions.Notify("Test zone entered", "success") 
        end,
        onExit = function() 
            QBCore.Functions.Notify("Test zone exited", "info") 
        end
    }
    
    ZoneManager.RegisterZone("test_zone", testZone)
    
    Citizen.Wait(2000)
    ZoneManager.UnregisterZone("test_zone")
    
    QBCore.Functions.Notify("Client tests completed", "success")
end)

RegisterNetEvent('smartutilities:client:forceCleanup')
AddEventHandler('smartutilities:client:forceCleanup', function()
    -- Force cleanup of all client resources
    for leakId, particleHandle in pairs(activeLeakParticles) do
        if DoesParticleFxLoopedExist(particleHandle) then
            StopParticleFxLooped(particleHandle, false)
            RemoveParticleFx(particleHandle, false)
        end
    end
    activeLeakParticles = {}
    particleData = {}
    
    Performance.CleanupCache()
    QBCore.Functions.Notify("Client cleanup completed", "success")
end)

-- Ensure config is loaded before anything major happens
Citizen.CreateThread(function()
    while not Config or not next(Config) do -- Wait until Config table is populated
        Logger.Debug("Waiting for Config to be loaded...")
        Citizen.Wait(500)
    end
    Logger.Info("Config confirmed loaded on client-side.")
    -- Now safe to run functions that depend on Config
end)
