-- Performance Optimization Utilities
Performance = {}

-- Movement tracking for optimized zone checks
local lastPlayerPosition = vector3(0, 0, 0)
local movementThreshold = 5.0
local lastMovementCheck = 0
local movementCheckInterval = 500 -- Check movement every 500ms

-- Zone check optimization
local zoneCheckCache = {}
local cacheTimeout = 2000 -- Cache results for 2 seconds

-- Check if player has moved significantly
function Performance.HasPlayerMoved()
    local currentTime = GetGameTimer()
    if (currentTime - lastMovementCheck) < movementCheckInterval then
        return false -- Don't check too frequently
    end
    
    lastMovementCheck = currentTime
    local currentPos = GetEntityCoords(PlayerPedId())
    local distance = #(currentPos - lastPlayerPosition)
    
    if distance > movementThreshold then
        lastPlayerPosition = currentPos
        return true
    end
    
    return false
end

-- Optimized zone distance check with caching
function Performance.CheckZoneDistance(zoneId, zoneCoords, radius, playerCoords)
    local currentTime = GetGameTimer()
    local cacheKey = zoneId .. "_" .. math.floor(playerCoords.x) .. "_" .. math.floor(playerCoords.y)
    
    -- Check cache first
    if zoneCheckCache[cacheKey] and (currentTime - zoneCheckCache[cacheKey].time) < cacheTimeout then
        return zoneCheckCache[cacheKey].result
    end
    
    -- Calculate distance
    local distance = #(playerCoords - zoneCoords)
    local isInRange = distance <= radius
    
    -- Cache result
    zoneCheckCache[cacheKey] = {
        result = isInRange,
        time = currentTime
    }
    
    return isInRange
end

-- Clean up old cache entries
function Performance.CleanupCache()
    local currentTime = GetGameTimer()
    for key, data in pairs(zoneCheckCache) do
        if (currentTime - data.time) > (cacheTimeout * 2) then
            zoneCheckCache[key] = nil
        end
    end
end

-- Optimized thread management
local activeThreads = {}

function Performance.CreateOptimizedThread(name, func, baseWait)
    if activeThreads[name] then
        Logger.Warn("Thread " .. name .. " already exists")
        return
    end
    
    activeThreads[name] = true
    
    Citizen.CreateThread(function()
        while activeThreads[name] do
            local startTime = GetGameTimer()
            
            -- Execute the function
            local success, error = pcall(func)
            if not success then
                Logger.Error("Thread " .. name .. " error: " .. tostring(error))
            end
            
            -- Dynamic wait based on execution time
            local executionTime = GetGameTimer() - startTime
            local waitTime = math.max(baseWait or 100, executionTime * 2)
            
            Citizen.Wait(waitTime)
        end
        
        Logger.Debug("Thread " .. name .. " stopped")
    end)
end

function Performance.StopThread(name)
    activeThreads[name] = nil
end

function Performance.StopAllThreads()
    for name, _ in pairs(activeThreads) do
        activeThreads[name] = nil
    end
end

-- Batch processing utility
local batchQueue = {}
local batchTimer = nil
local batchDelay = 1000 -- Process batches every 1 second

function Performance.AddToBatch(category, data)
    if not batchQueue[category] then
        batchQueue[category] = {}
    end
    
    table.insert(batchQueue[category], data)
    
    -- Start batch timer if not already running
    if not batchTimer then
        batchTimer = SetTimeout(batchDelay, function()
            Performance.ProcessBatches()
            batchTimer = nil
        end)
    end
end

function Performance.ProcessBatches()
    for category, items in pairs(batchQueue) do
        if #items > 0 then
            -- Process batch based on category
            if category == "zone_updates" then
                -- Batch zone updates
                TriggerServerEvent("smartutilities:server:batchZoneUpdates", items)
            elseif category == "particle_cleanup" then
                -- Batch particle cleanup
                for _, particleHandle in ipairs(items) do
                    if DoesParticleFxLoopedExist(particleHandle) then
                        StopParticleFxLooped(particleHandle, false)
                        RemoveParticleFx(particleHandle, false)
                    end
                end
            end
            
            -- Clear processed items
            batchQueue[category] = {}
        end
    end
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    Performance.StopAllThreads()
    Performance.ProcessBatches() -- Process any remaining batches
    
    if batchTimer then
        ClearTimeout(batchTimer)
    end
end)

-- Periodic cache cleanup
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(30000) -- Clean up every 30 seconds
        Performance.CleanupCache()
    end
end)

Logger.Info("Performance utilities initialized")