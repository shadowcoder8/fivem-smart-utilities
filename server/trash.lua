local QBCore = exports['qb-core']:GetCoreObject()

-- Ensure Config is loaded, especially for payout and fine amounts
-- Config might be loaded via fxmanifest shared_script or loaded explicitly here if needed.
-- Assuming Config.TrashZones and Config.TrashCollection are available.
Citizen.CreateThread(function()
    while Config == nil or Config.TrashZones == nil or Config.TrashCollection == nil do
        Citizen.Wait(1000)
        if Config and Config.TrashZones and Config.TrashCollection then
            print("Trash Config successfully accessed on server.")
        else
            print("Waiting for Trash Config on server...")
        end
    end
    if not Config or not Config.TrashZones or not Config.TrashCollection then
        print("ERROR: Trash Config not available on server. Trash script might not function correctly.")
    end
end)

local function logTrashActivity(citizenid, actionType, amountCollected, fineAmount)
    MySQL.Async.execute(
        "INSERT INTO trash_log (citizenid, action_type, amount_collected, fine_amount) VALUES (?, ?, ?, ?)",
        {citizenid, actionType, amountCollected or 0, fineAmount or 0.00},
        function(affectedRows)
            if affectedRows > 0 then
                -- print("Trash activity logged for " .. citizenid)
            else
                print("Failed to log trash activity for " .. citizenid)
            end
        end
    )
end

-- Event for when player dumps trash at the depot
RegisterNetEvent("smartutils:server:dumpTrashAtDepot", function(amountCollected)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then
        Logger.Error("smartutils:server:dumpTrashAtDepot - Player not found for source: " .. src)
        return
    end
    
    -- Rate limiting check
    local canProceed, limitError = RateLimiter.CheckLimit(src, "smartutils:server:dumpTrashAtDepot")
    if not canProceed then
        Player.Functions.Notify(limitError, "error")
        Logger.Warn("Rate limit exceeded for player " .. Player.PlayerData.citizenid .. " on dumpTrashAtDepot")
        return
    end
    
    -- Validate input
    local isValid, errorMsg = Validation.ValidateAmount(amountCollected, 1, 1000)
    if not isValid then
        Player.Functions.Notify("Invalid trash amount: " .. errorMsg, "error")
        Logger.Warn("Player " .. Player.PlayerData.citizenid .. " sent invalid trash amount: " .. tostring(amountCollected))
        return
    end

    if not Config or not Config.TrashZones or not Config.TrashZones.Depot or not Config.TrashCollection then
        Player.Functions.Notify("Server configuration error for trash system. Please contact an admin.", "error")
        print("ERROR: Trash Config not loaded or incomplete on server for dumpTrashAtDepot.")
        return
    end

    local payoutPerUnit = Config.TrashZones.Depot.payoutPerUnit or 0.5
    local minTrashToDump = Config.TrashCollection.MinTrashToDump or 10

    if amountCollected < minTrashToDump then
        Player.Functions.Notify("You need at least " .. minTrashToDump .. "kg of trash to dump.", "error")
        return
    end

    local payoutAmount = amountCollected * payoutPerUnit

    if payoutAmount > 0 then
        Player.Functions.AddMoney("cash", math.floor(payoutAmount), "trash-collection-payout") -- Ensure it's an integer if using 'cash'
        Player.Functions.Notify("You received $" .. math.floor(payoutAmount) .. " for " .. amountCollected .. "kg of trash.", "success")
        logTrashActivity(Player.PlayerData.citizenid, "collected_depot", amountCollected, 0)
    else
        Player.Functions.Notify("No payout for this amount of trash.", "warning")
    end
    -- Potentially trigger job-related rewards or stats updates here
end)

-- Event for when player dumps trash illegally
RegisterNetEvent("smartutils:server:illegalDumpTrash", function(amountDumped, dumpLocation)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then
        Logger.Error("smartutils:server:illegalDumpTrash - Player not found for source: " .. src)
        return
    end
    
    -- Validate inputs
    local isValidAmount, amountError = Validation.ValidateAmount(amountDumped, 1, 1000)
    if not isValidAmount then
        Player.Functions.Notify("Invalid trash amount: " .. amountError, "error")
        Logger.Warn("Player " .. Player.PlayerData.citizenid .. " sent invalid trash amount: " .. tostring(amountDumped))
        return
    end
    
    local isValidCoords, coordsError = Validation.ValidateCoords(dumpLocation)
    if not isValidCoords then
        Player.Functions.Notify("Invalid dump location: " .. coordsError, "error")
        Logger.Warn("Player " .. Player.PlayerData.citizenid .. " sent invalid dump coordinates")
        return
    end

    if not Config or not Config.TrashCollection then
        Player.Functions.Notify("Server configuration error for trash system. Please contact an admin.", "error")
        print("ERROR: Trash Config not loaded or incomplete on server for illegalDumpTrash.")
        return
    end

    local fineAmount = Config.TrashCollection.FineForIllegalDumping or 250

    -- It's good practice to remove money from bank, as player might not have cash
    local playerMoney = Player.Functions.GetMoney('bank')
    if playerMoney >= fineAmount then
        Player.Functions.RemoveMoney("bank", fineAmount, "illegal-trash-dumping-fine")
        Player.Functions.Notify("You have been fined $" .. fineAmount .. " for illegal dumping!", "error", 7500)
    else
        -- Player doesn't have enough in bank, try cash, or issue a warrant/debt.
        local playerCash = Player.Functions.GetMoney('cash')
        if playerCash >= fineAmount then
            Player.Functions.RemoveMoney("cash", fineAmount, "illegal-trash-dumping-fine")
            Player.Functions.Notify("You have been fined $" .. fineAmount .. " (paid from cash) for illegal dumping!", "error", 7500)
        else
            Player.Functions.Notify("You have been fined $" .. fineAmount .. " for illegal dumping, but you don't have enough money. A warrant may be issued.", "error", 10000)
            -- TODO: Integrate with a wanted system or debt system here if available.
            -- exports['qb-policealerts']:AddOffense(Player.PlayerData.citizenid, "Illegal Dumping", fineAmount)
        end
    end

    logTrashActivity(Player.PlayerData.citizenid, "dumped_illegal", amountDumped, fineAmount)

    -- Notify authorities (placeholder, could be a police alert system)
    local message = ("Illegal trash dumping reported by %s (%s) at coords X: %.2f, Y: %.2f, Z: %.2f. Amount: %dkg."):format(Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname, Player.PlayerData.citizenid, dumpLocation.x, dumpLocation.y, dumpLocation.z, amountDumped)

    -- Example: Trigger a dispatch for police job
    -- TriggerClientEvent('police:client:sendPoliceAlert', -1, {
    --     code = "10-52", -- Example code for dumping/littering
    --     description = message,
    --     location = dumpLocation,
    --     priority = 3 -- Low to medium priority
    -- })
    print("SERVER LOG: " .. message) -- Log to server console for now

    -- You could also trigger a global notification or a specific job alert
    -- TriggerClientEvent('QBCore:Notify', -1, message, 'error', 10000) -- Notify all players (maybe too spammy)
end)

-- TODO:
-- - Server-side management of bin/dumpster fill levels if desired for persistence and sync.
--   This would involve storing their state in a table or database and updating clients.
-- - Integration with a job system for specific trash collector job roles, vehicle spawning, etc.
-- - More advanced fine system (e.g., escalating fines, warrants).
-- - Integration with dispatch/alert systems for illegal dumping.

print("SmartUtils: Server-side Trash script loaded.")
