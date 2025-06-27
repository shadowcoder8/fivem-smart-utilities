local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()

local currentTrashLoad = 0
local onIllegalDumpCooldown = false

local nearbyBin = nil -- Stores the reference to the closest interactive bin/dumpster
local isNearDepotDropOff = false
local isNearJobStart = false

-- Performance optimization variables
local lastPlayerPos = vector3(0, 0, 0)
local lastZoneCheck = 0
local ZONE_CHECK_INTERVAL = 1000 -- Check zones every 1 second
local MOVEMENT_THRESHOLD = 5.0 -- Only check zones if player moved more than 5 units

local function DrawText3D(coords, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

local function GetCombinedTrashZones()
    local allZones = {}
    for _, zoneData in ipairs(Config.TrashZones.PublicBins) do
        table.insert(allZones, { data = zoneData, type = 'bin' })
    end
    for _, zoneData in ipairs(Config.TrashZones.Dumpsters) do
        table.insert(allZones, { data = zoneData, type = 'dumpster' })
    end
    return allZones
end

Citizen.CreateThread(function()
    PlayerData = QBCore.Functions.GetPlayerData()
    while PlayerData == nil do
        Citizen.Wait(100)
        PlayerData = QBCore.Functions.GetPlayerData()
    end

    -- Wait for config to be loaded (ensure it's accessible)
    while Config == nil or Config.TrashZones == nil do
        Citizen.Wait(100)
        if Config and Config.TrashZones then
            print("Trash Config successfully loaded on client.")
        else
            print("Waiting for Trash Config...")
        end
    end
    if not Config or not Config.TrashZones then
        print("ERROR: Trash Config not loaded. Trash script might not function correctly.")
        return
    end

    local allCollectionZones = GetCombinedTrashZones()

    while true do
        local currentTime = GetGameTimer()
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local playerMoved = #(playerCoords - lastPlayerPos) > MOVEMENT_THRESHOLD
        
        -- Only check zones if player moved or enough time has passed
        local shouldCheckZones = playerMoved or (currentTime - lastZoneCheck) > ZONE_CHECK_INTERVAL
        
        if shouldCheckZones then
            lastPlayerPos = playerCoords
            lastZoneCheck = currentTime
            
            local foundNearbyBin = false
            local foundNearDepot = false
            local foundNearJobStart = false

            -- Check near collection zones (bins/dumpsters)
            for _, zoneEntry in ipairs(allCollectionZones) do
                local zone = zoneEntry.data
                local dist = #(playerCoords - zone.coords)
                if dist < zone.radius + 2.0 then -- A bit larger radius for initial detection
                    if Config.TrashZones.EnableDebug then
                        DrawMarker(1, zone.coords.x, zone.coords.y, zone.coords.z - 0.9, 0, 0, 0, 0, 0, 0, zone.radius * 2, zone.radius * 2, 0.5, 0, 255, 0, 50, false, true, 2, nil, nil, false)
                    end
                    if dist < zone.radius then
                        nearbyBin = zone
                        foundNearbyBin = true
                        break -- Found the closest, no need to check others for now
                    end
                end
            end
            if not foundNearbyBin then
                nearbyBin = nil
            end

            -- Check near depot drop-off
            local depot = Config.TrashZones.Depot
            if depot and depot.dropOffCoords then
                local distToDepotDropOff = #(playerCoords - depot.dropOffCoords)
                if distToDepotDropOff < depot.dropOffRadius + 5.0 then -- Larger for debug
                     if Config.TrashZones.EnableDebug then
                        DrawMarker(1, depot.dropOffCoords.x, depot.dropOffCoords.y, depot.dropOffCoords.z - 0.9, 0, 0, 0, 0, 0, 0, depot.dropOffRadius * 2, depot.dropOffRadius * 2, 1.0, 255, 255, 0, 50, false, true, 2, nil, nil, false)
                    end
                    if distToDepotDropOff < depot.dropOffRadius then
                        isNearDepotDropOff = true
                        foundNearDepot = true
                    end
                end
            end
            if not foundNearDepot then
                isNearDepotDropOff = false
            end

            -- Check near job start point
            if depot and depot.startJobCoords then
                 local distToJobStart = #(playerCoords - depot.startJobCoords)
                 if distToJobStart < depot.startJobRadius + 2.0 then
                    if Config.TrashZones.EnableDebug then
                        DrawMarker(1, depot.startJobCoords.x, depot.startJobCoords.y, depot.startJobCoords.z - 0.9, 0, 0, 0, 0, 0, 0, depot.startJobRadius * 2, depot.startJobRadius * 2, 1.0, 0, 0, 255, 50, false, true, 2, nil, nil, false)
                    end
                    if distToJobStart < depot.startJobRadius then
                        isNearJobStart = true
                        foundNearJobStart = true
                    end
                end
            end
            if not foundNearJobStart then
                isNearJobStart = false
            end
        end

        -- UI Prompts (simple version) - Always show if near something
        if nearbyBin and (nearbyBin.currentLoad or 0) < nearbyBin.capacity then
            DrawText3D(nearbyBin.coords + vector3(0,0,1.0), "[E] Collect Trash (" .. (nearbyBin.currentLoad or 0) .. "/" .. nearbyBin.capacity .. " units)")
        elseif nearbyBin and (nearbyBin.currentLoad or 0) >= nearbyBin.capacity then
            DrawText3D(nearbyBin.coords + vector3(0,0,1.0), "This bin is full!")
        end

        if isNearDepotDropOff and currentTrashLoad > 0 then
            local depot = Config.TrashZones.Depot
            DrawText3D(depot.dropOffCoords + vector3(0,0,1.5), "[G] Dump Trash (" .. currentTrashLoad .. " units)")
        elseif isNearDepotDropOff and currentTrashLoad == 0 then
            local depot = Config.TrashZones.Depot
             DrawText3D(depot.dropOffCoords + vector3(0,0,1.5), "Trash Depot - Nothing to dump.")
        end

        if isNearJobStart then
            local depot = Config.TrashZones.Depot
            -- Placeholder for job interaction, e.g., start/end trash collector job
            DrawText3D(depot.startJobCoords + vector3(0,0,1.0), "[H] Sanitation Job Services")
        end

        -- Current trash load display (simple text on screen)
        if currentTrashLoad > 0 then
            SetTextFont(4)
            SetTextScale(0.45, 0.45)
            SetTextColour(255, 255, 255, 255)
            SetTextEntry("STRING")
            AddTextComponentString("Trash Load: " .. currentTrashLoad .. "/" .. Config.TrashCollection.MaxCarryWeight .. " kg")
            DrawText(0.9, 0.8) -- Position on screen (bottom right-ish)
        end

        -- Dynamic wait based on activity
        if nearbyBin or isNearDepotDropOff or isNearJobStart then
            Citizen.Wait(100) -- Fast updates when near interaction points
        else
            Citizen.Wait(1000) -- Slower updates when not near anything
        end
    end
end)

-- Interaction logic
Citizen.CreateThread(function()
    while true do
        -- Only check for key presses frequently if near an interaction point
        if nearbyBin or isNearDepotDropOff or isNearJobStart then
            Citizen.Wait(0) -- Check every frame for key presses when near interaction points
        else
            Citizen.Wait(200) -- Much less frequent when not near anything
        end

        if nearbyBin and IsControlJustPressed(0, 38) then -- Key E
            if (nearbyBin.currentLoad or 0) < nearbyBin.capacity then
                if currentTrashLoad < Config.TrashCollection.MaxCarryWeight then
                    QBCore.Functions.Notify("Collecting trash...", "primary", Config.TrashCollection.CollectionTime)
                    local success = exports['qb-taskbar']:taskBar(Config.TrashCollection.CollectionTime, "Collecting Trash", false, true, false, false, nil, 5.0, PlayerPedId())
                    if success then
                        local amountToCollect = math.random(5, 15) -- Collect a random amount
                        local actualCollected = 0

                        if (nearbyBin.currentLoad or 0) + amountToCollect > nearbyBin.capacity then
                            amountToCollect = nearbyBin.capacity - (nearbyBin.currentLoad or 0)
                        end

                        if currentTrashLoad + amountToCollect > Config.TrashCollection.MaxCarryWeight then
                           actualCollected = Config.TrashCollection.MaxCarryWeight - currentTrashLoad
                        else
                            actualCollected = amountToCollect
                        end

                        if actualCollected > 0 then
                            currentTrashLoad = currentTrashLoad + actualCollected
                            nearbyBin.currentLoad = (nearbyBin.currentLoad or 0) + actualCollected -- Update conceptual bin load
                            QBCore.Functions.Notify("Collected " .. actualCollected .. " units of trash. Current load: " .. currentTrashLoad .. "kg", "success")
                        else
                            QBCore.Functions.Notify("You can't carry more or the bin is empty!", "warning")
                        end
                    else
                        QBCore.Functions.Notify("Trash collection cancelled.", "error")
                    end
                else
                    QBCore.Functions.Notify("Your carry load is full! (" .. Config.TrashCollection.MaxCarryWeight .. "kg)", "warning")
                end
            else
                QBCore.Functions.Notify("This bin is full!", "warning")
            end
        end

        if isNearDepotDropOff and IsControlJustPressed(0, 47) then -- Key G
            HandleDumpTrash()
        end

        if isNearJobStart and IsControlJustPressed(0, 74) then -- Key H
            -- Placeholder for job interaction
            QBCore.Functions.Notify("Sanitation job menu would open here.", "inform")
            -- Example: TriggerServerEvent('qb-jobs:client:ToggleJobCenter', 'sanitation')
        end
    end
end)

function HandleDumpTrash()
    if currentTrashLoad <= 0 then
        QBCore.Functions.Notify("You have no trash to dump.", "warning")
        return
    end

    if currentTrashLoad < Config.TrashCollection.MinTrashToDump and isNearDepotDropOff then
         QBCore.Functions.Notify("You need at least " .. Config.TrashCollection.MinTrashToDump .. "kg of trash to dump at the depot.", "warning")
         return
    end

    if isNearDepotDropOff then
        -- Legal dumping at depot
        QBCore.Functions.Notify("Dumping " .. currentTrashLoad .. "kg of trash at the depot...", "primary")
        -- Simulate time or animation if desired
        local success = exports['qb-taskbar']:taskBar(2500, "Dumping Trash", false, true, false, false, nil, 5.0, PlayerPedId())
        if success then
            TriggerServerEvent("smartutils:server:dumpTrashAtDepot", currentTrashLoad)
            currentTrashLoad = 0
        else
            QBCore.Functions.Notify("Dumping cancelled.", "error")
        end
    else
        -- Illegal dumping
        if onIllegalDumpCooldown then
            QBCore.Functions.Notify("You were recently fined for illegal dumping. Wait a bit.", "warning")
            return
        end
        QBCore.Functions.Notify("You are dumping trash illegally!", "error", 5000)
        -- Placeholder effect for illegal dumping (e.g., camera shake, sound)
        ShakeGameplayCam("ROAD_VIBRATION", 0.3)
        PlaySoundFrontend(-1, "Bed_Shrink_Squeak", "HUD_MINI_GAME_SOUNDSET", true)

        TriggerServerEvent("smartutils:server:illegalDumpTrash", currentTrashLoad, GetEntityCoords(PlayerPedId()))
        currentTrashLoad = 0
        onIllegalDumpCooldown = true
        SetTimeout(Config.TrashCollection.IllegalDumpCooldown, function()
            onIllegalDumpCooldown = false
        end)
    end
end

RegisterCommand("dumptrash", HandleDumpTrash, false)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    currentTrashLoad = 0 -- Reset trash load on player load
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
    -- Potentially reset trash load or apply job-specific bonuses here
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    -- Clean up any markers or UI elements if necessary
end)

print("SmartUtils: Client-side Trash script loaded.")
-- TODO:
-- - Integrate qb-target for interactions instead of key press + DrawText3D.
-- - More sophisticated management of bin/dumpster currentLoad (server-side sync).
-- - Visual feedback for bin status (e.g., different prop model or texture).
-- - NUI for trash load/alerts if desired over simple text.
-- - Job system integration (vehicle spawning, specific job tasks).
-- - Refine debug drawing to be cleaner or use a library.
-- - Consider using PolyZone for more complex zone shapes.
-- - Add animations for collecting and dumping trash.
-- - Persist currentTrashLoad if player logs off with trash.
-- - Add checks for being in a vehicle when trying to collect from bins (should probably be on foot).
