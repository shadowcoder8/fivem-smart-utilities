-- Inventory Management Utilities
Inventory = {}

-- Check if player has required items (QBCore/ox_inventory compatible)
function Inventory.HasRequiredItems(src, requiredItems)
    if not src or not requiredItems then
        Logger.Error("HasRequiredItems: Invalid parameters")
        return false
    end
    
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        Logger.Error("HasRequiredItems: Player not found for source: " .. src)
        return false
    end
    
    -- Check if ox_inventory is available
    if GetResourceState('ox_inventory') == 'started' then
        return Inventory.CheckItemsOxInventory(src, requiredItems)
    end
    
    -- Default to QBCore inventory
    return Inventory.CheckItemsQBCore(Player, requiredItems)
end

-- QBCore inventory check
function Inventory.CheckItemsQBCore(Player, requiredItems)
    for _, item in ipairs(requiredItems) do
        local itemName = item.name or item
        local requiredCount = item.count or 1
        
        local playerItem = Player.Functions.GetItemByName(itemName)
        if not playerItem or playerItem.amount < requiredCount then
            Logger.Debug("Player missing item: " .. itemName .. " (required: " .. requiredCount .. ")")
            return false
        end
    end
    return true
end

-- ox_inventory check
function Inventory.CheckItemsOxInventory(src, requiredItems)
    for _, item in ipairs(requiredItems) do
        local itemName = item.name or item
        local requiredCount = item.count or 1
        
        local itemCount = exports.ox_inventory:GetItemCount(src, itemName)
        if itemCount < requiredCount then
            Logger.Debug("Player missing item: " .. itemName .. " (required: " .. requiredCount .. ", has: " .. itemCount .. ")")
            return false
        end
    end
    return true
end

-- Remove items from player inventory
function Inventory.RemoveItems(src, items)
    if not src or not items then
        Logger.Error("RemoveItems: Invalid parameters")
        return false
    end
    
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        Logger.Error("RemoveItems: Player not found for source: " .. src)
        return false
    end
    
    -- Check if ox_inventory is available
    if GetResourceState('ox_inventory') == 'started' then
        return Inventory.RemoveItemsOxInventory(src, items)
    end
    
    -- Default to QBCore inventory
    return Inventory.RemoveItemsQBCore(Player, items)
end

-- QBCore item removal
function Inventory.RemoveItemsQBCore(Player, items)
    -- First check if player has all items
    if not Inventory.CheckItemsQBCore(Player, items) then
        return false
    end
    
    -- Remove items
    for _, item in ipairs(items) do
        local itemName = item.name or item
        local removeCount = item.count or 1
        
        local success = Player.Functions.RemoveItem(itemName, removeCount)
        if not success then
            Logger.Error("Failed to remove item: " .. itemName)
            return false
        end
    end
    
    return true
end

-- ox_inventory item removal
function Inventory.RemoveItemsOxInventory(src, items)
    -- First check if player has all items
    if not Inventory.CheckItemsOxInventory(src, items) then
        return false
    end
    
    -- Remove items
    for _, item in ipairs(items) do
        local itemName = item.name or item
        local removeCount = item.count or 1
        
        local success = exports.ox_inventory:RemoveItem(src, itemName, removeCount)
        if not success then
            Logger.Error("Failed to remove item: " .. itemName)
            return false
        end
    end
    
    return true
end

-- Add items to player inventory
function Inventory.AddItems(src, items)
    if not src or not items then
        Logger.Error("AddItems: Invalid parameters")
        return false
    end
    
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        Logger.Error("AddItems: Player not found for source: " .. src)
        return false
    end
    
    -- Check if ox_inventory is available
    if GetResourceState('ox_inventory') == 'started' then
        return Inventory.AddItemsOxInventory(src, items)
    end
    
    -- Default to QBCore inventory
    return Inventory.AddItemsQBCore(Player, items)
end

-- QBCore item addition
function Inventory.AddItemsQBCore(Player, items)
    for _, item in ipairs(items) do
        local itemName = item.name or item
        local addCount = item.count or 1
        local info = item.info or {}
        
        local success = Player.Functions.AddItem(itemName, addCount, false, info)
        if not success then
            Logger.Error("Failed to add item: " .. itemName)
            return false
        end
    end
    
    return true
end

-- ox_inventory item addition
function Inventory.AddItemsOxInventory(src, items)
    for _, item in ipairs(items) do
        local itemName = item.name or item
        local addCount = item.count or 1
        local metadata = item.metadata or {}
        
        local success = exports.ox_inventory:AddItem(src, itemName, addCount, metadata)
        if not success then
            Logger.Error("Failed to add item: " .. itemName)
            return false
        end
    end
    
    return true
end

-- Check if player has specific job
function Inventory.HasJob(src, allowedJobs)
    if not src or not allowedJobs then
        return false
    end
    
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData.job then
        return false
    end
    
    local playerJob = Player.PlayerData.job.name
    
    if type(allowedJobs) == "string" then
        return playerJob == allowedJobs
    elseif type(allowedJobs) == "table" then
        for _, job in ipairs(allowedJobs) do
            if playerJob == job then
                return true
            end
        end
    end
    
    return false
end

-- Get player's current job
function Inventory.GetPlayerJob(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData.job then
        return nil
    end
    
    return Player.PlayerData.job.name
end

Logger.Info("Inventory utilities initialized")