-- Rate Limiting Utility
RateLimiter = {}

-- Store rate limit data
local rateLimitData = {} -- { [playerId] = { [eventName] = { count = 0, lastReset = time } } }

-- Rate limit configuration
local RATE_LIMITS = {
    ['smartutils:server:subscribeInternet'] = { maxRequests = 5, windowMs = 60000 }, -- 5 requests per minute
    ['smartutils:server:upgradeInternetTier'] = { maxRequests = 3, windowMs = 60000 }, -- 3 requests per minute
    ['smartutils:server:dumpTrashAtDepot'] = { maxRequests = 10, windowMs = 60000 }, -- 10 requests per minute
    ['smartutils:server:illegalDumpTrash'] = { maxRequests = 5, windowMs = 60000 }, -- 5 requests per minute
    ['smartutils:server:confirmInstall'] = { maxRequests = 3, windowMs = 300000 }, -- 3 requests per 5 minutes
    ['smartutilities:server:finishInternetHack'] = { maxRequests = 5, windowMs = 300000 }, -- 5 requests per 5 minutes
}

-- Check if player is rate limited for a specific event
function RateLimiter.CheckLimit(playerId, eventName)
    if not playerId or not eventName then
        return false, "Invalid parameters"
    end
    
    local limit = RATE_LIMITS[eventName]
    if not limit then
        return true, nil -- No rate limit configured for this event
    end
    
    local currentTime = GetGameTimer()
    
    -- Initialize player data if not exists
    if not rateLimitData[playerId] then
        rateLimitData[playerId] = {}
    end
    
    -- Initialize event data if not exists
    if not rateLimitData[playerId][eventName] then
        rateLimitData[playerId][eventName] = {
            count = 0,
            lastReset = currentTime
        }
    end
    
    local eventData = rateLimitData[playerId][eventName]
    
    -- Reset counter if window has passed
    if (currentTime - eventData.lastReset) > limit.windowMs then
        eventData.count = 0
        eventData.lastReset = currentTime
    end
    
    -- Check if limit exceeded
    if eventData.count >= limit.maxRequests then
        local timeLeft = limit.windowMs - (currentTime - eventData.lastReset)
        return false, string.format("Rate limit exceeded. Try again in %d seconds.", math.ceil(timeLeft / 1000))
    end
    
    -- Increment counter
    eventData.count = eventData.count + 1
    return true, nil
end

-- Clean up old rate limit data (call periodically)
function RateLimiter.Cleanup()
    local currentTime = GetGameTimer()
    local cleanupThreshold = 600000 -- 10 minutes
    
    for playerId, playerData in pairs(rateLimitData) do
        for eventName, eventData in pairs(playerData) do
            if (currentTime - eventData.lastReset) > cleanupThreshold then
                playerData[eventName] = nil
            end
        end
        
        -- Remove player data if empty
        if next(playerData) == nil then
            rateLimitData[playerId] = nil
        end
    end
end

-- Periodic cleanup
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000) -- Clean up every 5 minutes
        RateLimiter.Cleanup()
    end
end)

Logger.Info("Rate limiter initialized")