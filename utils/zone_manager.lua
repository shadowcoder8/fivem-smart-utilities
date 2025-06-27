-- Optimized Zone Management System
ZoneManager = {}

-- Zone tracking
local activeZones = {}
local playerZoneCache = {}
local lastPlayerPosition = vector3(0, 0, 0)
local lastZoneCheck = 0

-- Configuration
local ZONE_CHECK_INTERVAL = 1000 -- Check zones every 1 second
local MOVEMENT_THRESHOLD = 10.0 -- Only check if player moved more than 10 units
local CACHE_TIMEOUT = 5000 -- Cache results for 5 seconds

-- Register a zone for monitoring
function ZoneManager.RegisterZone(zoneId, zoneData)
    if not zoneId or not zoneData then
        Logger.Error("RegisterZone: Invalid parameters")
        return false
    end
    
    activeZones[zoneId] = {
        id = zoneId,
        coords = zoneData.coords,
        radius = zoneData.radius or 50.0,
        type = zoneData.type or "generic",
        callback = zoneData.callback,
        onEnter = zoneData.onEnter,
        onExit = zoneData.onExit,
        data = zoneData.data or {},
        lastCheck = 0,
        playerInside = false
    }
    
    Logger.Debug("Registered zone: " .. zoneId)
    return true
end

-- Unregister a zone
function ZoneManager.UnregisterZone(zoneId)
    if activeZones[zoneId] then
        activeZones[zoneId] = nil
        playerZoneCache[zoneId] = nil
        Logger.Debug("Unregistered zone: " .. zoneId)
        return true
    end
    return false
end

-- Check if player is in a specific zone
function ZoneManager.IsPlayerInZone(zoneId, playerCoords)
    local zone = activeZones[zoneId]
    if not zone then return false end
    
    playerCoords = playerCoords or GetEntityCoords(PlayerPedId())
    local distance = #(playerCoords - zone.coords)
    
    return distance <= zone.radius
end

-- Get all zones player is currently in
function ZoneManager.GetPlayerZones(playerCoords)
    playerCoords = playerCoords or GetEntityCoords(PlayerPedId())
    local zonesInside = {}
    
    for zoneId, zone in pairs(activeZones) do
        if ZoneManager.IsPlayerInZone(zoneId, playerCoords) then
            table.insert(zonesInside, {
                id = zoneId,
                zone = zone,
                distance = #(playerCoords - zone.coords)
            })
        end
    end
    
    -- Sort by distance (closest first)
    table.sort(zonesInside, function(a, b) return a.distance < b.distance end)
    
    return zonesInside
end

-- Optimized zone checking with movement detection
function ZoneManager.CheckZones()
    local currentTime = GetGameTimer()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    -- Check if player moved significantly
    local playerMoved = #(playerCoords - lastPlayerPosition) > MOVEMENT_THRESHOLD
    local timeElapsed = (currentTime - lastZoneCheck) > ZONE_CHECK_INTERVAL
    
    if not playerMoved and not timeElapsed then
        return -- Skip check if player hasn't moved and not enough time passed
    end
    
    lastPlayerPosition = playerCoords
    lastZoneCheck = currentTime
    
    -- Check each zone
    for zoneId, zone in pairs(activeZones) do
        local isInside = ZoneManager.IsPlayerInZone(zoneId, playerCoords)
        local wasInside = zone.playerInside
        
        -- Handle zone enter/exit
        if isInside and not wasInside then
            -- Player entered zone
            zone.playerInside = true
            if zone.onEnter then
                zone.onEnter(zoneId, zone.data)
            end
            Logger.Debug("Player entered zone: " .. zoneId)
            
        elseif not isInside and wasInside then
            -- Player exited zone
            zone.playerInside = false
            if zone.onExit then
                zone.onExit(zoneId, zone.data)
            end
            Logger.Debug("Player exited zone: " .. zoneId)
        end
        
        -- Update zone state
        zone.lastCheck = currentTime
        
        -- Call zone callback if player is inside
        if isInside and zone.callback then
            zone.callback(zoneId, zone.data, #(playerCoords - zone.coords))
        end
    end
end

-- Get closest zone of a specific type
function ZoneManager.GetClosestZone(zoneType, playerCoords)
    playerCoords = playerCoords or GetEntityCoords(PlayerPedId())
    local closestZone = nil
    local closestDistance = math.huge
    
    for zoneId, zone in pairs(activeZones) do
        if not zoneType or zone.type == zoneType then
            local distance = #(playerCoords - zone.coords)
            if distance < closestDistance then
                closestDistance = distance
                closestZone = {
                    id = zoneId,
                    zone = zone,
                    distance = distance
                }
            end
        end
    end
    
    return closestZone
end

-- Batch zone updates for performance
local zoneUpdateBatch = {}
local batchTimer = nil

function ZoneManager.BatchZoneUpdate(zoneId, updateData)
    zoneUpdateBatch[zoneId] = updateData
    
    if not batchTimer then
        batchTimer = SetTimeout(500, function() -- Process batch every 500ms
            ZoneManager.ProcessZoneUpdates()
            batchTimer = nil
        end)
    end
end

function ZoneManager.ProcessZoneUpdates()
    if next(zoneUpdateBatch) == nil then return end
    
    for zoneId, updateData in pairs(zoneUpdateBatch) do
        local zone = activeZones[zoneId]
        if zone then
            -- Apply updates
            for key, value in pairs(updateData) do
                if key ~= "id" then -- Don't allow ID changes
                    zone[key] = value
                end
            end
        end
    end
    
    -- Clear batch
    zoneUpdateBatch = {}
    Logger.Debug("Processed zone update batch")
end

-- Main zone checking thread
Citizen.CreateThread(function()
    while true do
        local startTime = GetGameTimer()
        
        ZoneManager.CheckZones()
        
        -- Dynamic wait based on zone count and execution time
        local executionTime = GetGameTimer() - startTime
        local zoneCount = 0
        for _ in pairs(activeZones) do zoneCount = zoneCount + 1 end
        
        local waitTime = math.max(500, math.min(2000, zoneCount * 50 + executionTime))
        Citizen.Wait(waitTime)
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    activeZones = {}
    playerZoneCache = {}
    
    if batchTimer then
        ClearTimeout(batchTimer)
    end
    
    Logger.Info("Zone manager cleaned up")
end)

-- Export functions
exports('RegisterZone', ZoneManager.RegisterZone)
exports('UnregisterZone', ZoneManager.UnregisterZone)
exports('IsPlayerInZone', ZoneManager.IsPlayerInZone)
exports('GetPlayerZones', ZoneManager.GetPlayerZones)
exports('GetClosestZone', ZoneManager.GetClosestZone)

Logger.Info("Zone manager initialized")