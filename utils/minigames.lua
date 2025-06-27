-- Minigame Utilities for Smart Utilities
Minigames = {}

-- Simple skill check minigame
function Minigames.SkillCheck(difficulty, duration, callback)
    if not difficulty or not duration or not callback then
        Logger.Error("SkillCheck: Missing required parameters")
        return
    end
    
    -- Check if qb-skillbar is available
    if GetResourceState('qb-skillbar') == 'started' then
        local success = exports['qb-skillbar']:GetSkillbarObject()
        success.Start({
            duration = duration,
            pos = math.random(10, 30),
            width = math.max(10, 20 - difficulty),
        }, function()
            callback(true)
        end, function()
            callback(false)
        end)
        return
    end
    
    -- Check if ps-ui is available
    if GetResourceState('ps-ui') == 'started' then
        exports['ps-ui']:Circle(function(success)
            callback(success)
        end, math.max(2, difficulty), math.max(10, 20 - difficulty))
        return
    end
    
    -- Fallback to simple timer-based minigame
    Minigames.SimpleTimerGame(difficulty, duration, callback)
end

-- Simple timer-based minigame fallback
function Minigames.SimpleTimerGame(difficulty, duration, callback)
    local startTime = GetGameTimer()
    local targetTime = startTime + duration
    local successWindow = math.max(500, 2000 - (difficulty * 200)) -- Smaller window for higher difficulty
    local targetHitTime = startTime + math.random(duration * 0.3, duration * 0.7)
    
    local gameActive = true
    local success = false
    
    -- Display instructions
    QBCore.Functions.Notify("Press [E] when the bar is in the green zone!", "primary", duration + 1000)
    
    Citizen.CreateThread(function()
        while gameActive and GetGameTimer() < targetTime do
            Citizen.Wait(0)
            
            local currentTime = GetGameTimer()
            local progress = (currentTime - startTime) / duration
            
            -- Draw progress bar
            DrawRect(0.5, 0.8, 0.3, 0.05, 0, 0, 0, 150)
            DrawRect(0.35 + (progress * 0.3), 0.8, 0.01, 0.05, 255, 255, 255, 255)
            
            -- Draw success zone
            local successStart = (targetHitTime - startTime) / duration
            local successEnd = (targetHitTime + successWindow - startTime) / duration
            DrawRect(0.35 + (successStart * 0.3), 0.8, (successEnd - successStart) * 0.3, 0.05, 0, 255, 0, 100)
            
            -- Check for input
            if IsControlJustPressed(0, 38) then -- E key
                if currentTime >= targetHitTime and currentTime <= (targetHitTime + successWindow) then
                    success = true
                end
                gameActive = false
                break
            end
        end
        
        callback(success)
    end)
end

-- Hacking minigame for internet hubs
function Minigames.HackingGame(difficulty, callback)
    -- Check for available hacking minigames
    if GetResourceState('hacking') == 'started' then
        exports['hacking']:OpenHackingGame(difficulty, 5, 3, callback)
        return
    end
    
    if GetResourceState('ps-ui') == 'started' then
        exports['ps-ui']:Scrambler(function(success)
            callback(success)
        end, "numeric", 30, difficulty)
        return
    end
    
    -- Fallback to skill check
    Minigames.SkillCheck(difficulty, 5000, callback)
end

-- Repair minigame for utilities
function Minigames.RepairGame(repairType, difficulty, callback)
    local duration = 3000 + (difficulty * 1000) -- 3-8 seconds based on difficulty
    
    -- Check for thermite or other specialized minigames
    if repairType == "electrical" and GetResourceState('qb-thermite') == 'started' then
        exports['qb-thermite']:OpenThermiteGame(function(success)
            callback(success)
        end, difficulty, 10)
        return
    end
    
    -- Default to skill check
    Minigames.SkillCheck(difficulty, duration, callback)
end

-- Lock picking minigame for accessing restricted areas
function Minigames.LockpickGame(difficulty, callback)
    if GetResourceState('qb-lockpick') == 'started' then
        exports['qb-lockpick']:OpenLockpickGame(function(success)
            callback(success)
        end)
        return
    end
    
    if GetResourceState('ps-ui') == 'started' then
        exports['ps-ui']:Circle(function(success)
            callback(success)
        end, difficulty, 20)
        return
    end
    
    -- Fallback
    Minigames.SkillCheck(difficulty, 4000, callback)
end

-- Memory game for complex repairs
function Minigames.MemoryGame(difficulty, callback)
    if GetResourceState('ps-ui') == 'started' then
        exports['ps-ui']:Memory(function(success)
            callback(success)
        end, difficulty, 3)
        return
    end
    
    -- Fallback to multiple skill checks
    local checksRemaining = difficulty
    local allSuccess = true
    
    local function doNextCheck()
        if checksRemaining <= 0 then
            callback(allSuccess)
            return
        end
        
        Minigames.SkillCheck(2, 2000, function(success)
            if not success then
                allSuccess = false
            end
            checksRemaining = checksRemaining - 1
            
            if checksRemaining > 0 and allSuccess then
                Citizen.Wait(500) -- Brief pause between checks
                doNextCheck()
            else
                callback(allSuccess)
            end
        end)
    end
    
    doNextCheck()
end

-- Utility function to get appropriate minigame for action
function Minigames.GetMinigameForAction(actionType, difficulty, callback)
    if actionType == "hack" then
        Minigames.HackingGame(difficulty, callback)
    elseif actionType == "repair_electrical" then
        Minigames.RepairGame("electrical", difficulty, callback)
    elseif actionType == "repair_mechanical" then
        Minigames.RepairGame("mechanical", difficulty, callback)
    elseif actionType == "lockpick" then
        Minigames.LockpickGame(difficulty, callback)
    elseif actionType == "memory" then
        Minigames.MemoryGame(difficulty, callback)
    else
        -- Default skill check
        Minigames.SkillCheck(difficulty, 3000, callback)
    end
end

Logger.Info("Minigame utilities initialized")