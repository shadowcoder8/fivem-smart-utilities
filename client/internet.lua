local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData() -- Store player data

local isNuiOpen = false
local currentProperties = {} -- Cache properties to send to NUI

-- Configuration (can be moved to a config file)
local INSTALL_ANIM_DICT = "amb@world_human_wrench@male@base"
local INSTALL_ANIM_NAME = "base"
local INSTALL_DURATION = 5000 -- ms (5 seconds)
local ROUTER_PROP = `prop_router_01`
local TECHNICIAN_JOBS = { "mechanic", "isp_technician" } -- Example jobs that can install routers

-- Function to check if player has a technician job
local function HasTechnicianJob()
    if not PlayerData or not PlayerData.job or not PlayerData.job.name then
        return false
    end
    for _, jobName in ipairs(TECHNICIAN_JOBS) do
        if PlayerData.job.name == jobName then
            return true
        end
    end
    return false
end

-- Function to send data to NUI
local function SendNUIMessage(action, data)
    SendNUIMessage(action, data or {})
end

-- Open Internet NUI
RegisterCommand("openinternetmenu", function()
    if isNuiOpen then return end

    -- Request latest property and internet status from server before opening
    TriggerServerEvent("smartutils:server:getInternetData")
    -- The server will respond with "smartutils:client:showInternetNUI"
end, false)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)


RegisterNetEvent("smartutils:client:showInternetNUI", function(propertiesData)
    if isNuiOpen then return end

    currentProperties = propertiesData or {}
    SetNuiFocus(true, true)
    isNuiOpen = true
    SendNUIMessage("openInternetUI", { properties = currentProperties })
end)

-- NUI Callbacks
RegisterNUICallback("closeNUI", function(_, cb)
    SetNuiFocus(false, false)
    isNuiOpen = false
    cb({}) -- Acknowledge callback
end)

RegisterNUICallback("subscribe", function(data, cb)
    if data and data.propertyId and data.tier then
        TriggerServerEvent("smartutils:server:subscribeInternet", data.propertyId, data.tier)
        -- Optimistically update UI or wait for server confirmation
        QBCore.Functions.Notify("Subscription request sent for property " .. data.propertyId .. " to tier " .. data.tier, "primary")
    else
        QBCore.Functions.Notify("Invalid subscription data received.", "error")
    end
    cb({})
end)

RegisterNUICallback("upgradeTier", function(data, cb)
    if data and data.propertyId and data.newTier then
        TriggerServerEvent("smartutils:server:upgradeInternetTier", data.propertyId, data.newTier)
        QBCore.Functions.Notify("Upgrade request sent for property " .. data.propertyId .. " to tier " .. data.newTier, "primary")
    else
        QBCore.Functions.Notify("Invalid upgrade data received.", "error")
    end
    cb({})
end)

RegisterNUICallback("requestInstall", function(data, cb)
    if data and data.propertyId then
        QBCore.Functions.Notify("A technician from your Internet Service Provider has been notified to install the router at property: "..data.propertyId..".", "primary", 7500)
        -- Potentially, this could trigger an event for players with the 'isp_technician' job
        -- TriggerServerEvent("smartutils:server:logTechnicianRequest", data.propertyId)
    end
    cb({})
end)

-- Event to update NUI if data changes on server-side (e.g., after an upgrade)
RegisterNetEvent("smartutils:client:updateInternetPropertyData", function(propertyData)
    if not isNuiOpen then return end

    local found = false
    for i, prop in ipairs(currentProperties) do
        if prop.propertyId == propertyData.propertyId then
            currentProperties[i] = propertyData
            found = true
            break
        end
    end
    if not found then
        table.insert(currentProperties, propertyData)
    end
    SendNUIMessage("updatePropertyData", propertyData)
end)


-- /installinternet command
RegisterCommand("installinternet", function(source, args)
    if not HasTechnicianJob() then
        QBCore.Functions.Notify("You are not authorized to perform this action.", "error")
        return
    end

    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local propertyId = args[1] -- Expecting property ID as first argument

    if not propertyId then
        QBCore.Functions.Notify("Usage: /installinternet [propertyId]", "error")
        -- Try to get property nearby if using a housing script that supports it
        -- For simplicity, we'll require propertyId for now.
        -- Example: propertyId = exports['qb-housing']:GetCurrentProperty()
        -- if not propertyId then QBCore.Functions.Notify("You are not near any property.", "error") return end
        return
    end

    -- Check if router is already installed for this property (client-side check first, then server)
    TriggerServerEvent("smartutils:server:checkRouterStatus", propertyId, function(isInstalled)
        if isInstalled then
            QBCore.Functions.Notify("Router is already installed at this property.", "warning")
            return
        end

        QBCore.Functions.Notify("Starting router installation...", "primary")

        -- Animation and Taskbar
        RequestAnimDict(INSTALL_ANIM_DICT)
        while not HasAnimDictLoaded(INSTALL_ANIM_DICT) do Wait(100) end

        TaskPlayAnim(playerPed, INSTALL_ANIM_DICT, INSTALL_ANIM_NAME, 8.0, -8.0, -1, 1, 0, false, false, false)

        local success = exports['qb-taskbar']:taskBar(INSTALL_DURATION, "Installing Router...", false, true, false, false, nil, 5.0, playerPed)

        ClearPedTasks(playerPed)
        RemoveAnimDict(INSTALL_ANIM_DICT)

        if success then
            -- Router Placement: Place it slightly in front of the player or at a defined spot if property system provides it.
            -- For simplicity, placing it in front of where the technician is standing.
            -- A more robust solution would involve getting property entrance or predefined installation spots.
            local forwardVector = GetEntityForwardVector(playerPed)
            local routerCoords = coords + forwardVector * 1.0 + vector3(0.0, 0.0, 0.5) -- Adjust Z height as needed

            RequestModel(ROUTER_PROP)
            while not HasModelLoaded(ROUTER_PROP) do Wait(100) end

            local routerObject = CreateObject(ROUTER_PROP, routerCoords.x, routerCoords.y, routerCoords.z, true, true, false)
            PlaceObjectOnGroundProperly(routerObject)
            FreezeEntityPosition(routerObject, true)
            SetModelAsNoLongerNeeded(ROUTER_PROP)

            TriggerServerEvent("smartutils:server:confirmInstall", propertyId, routerCoords)
            QBCore.Functions.Notify("Router installed successfully at property " .. propertyId .. "!", "success")
        else
            QBCore.Functions.Notify("Router installation failed or was cancelled.", "error")
        end
    end)
end, false)

-- Clean up props on resource stop (basic example)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    -- A more robust system would involve tracking created props and deleting them.
    -- For routers, they are meant to be persistent per property based on DB.
    -- This is more for temporary props if any were used.
end)

-- Initial player data load
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

-- Update player data on job change
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobData)
    PlayerData.job = jobData
end)

-- Ensure NUI is closed if player logs out or crashes
AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    if isNuiOpen then
        SetNuiFocus(false, false)
        isNuiOpen = false
        SendNUIMessage("closeInternetUI", {}) -- Inform JS to clean up if needed
    end
end)

Citizen.CreateThread(function()
    PlayerData = QBCore.Functions.GetPlayerData()
    -- If PlayerData is not available immediately, wait for it
    while PlayerData == nil do
        Citizen.Wait(100)
        PlayerData = QBCore.Functions.GetPlayerData()
    end
    -- You can add any initial client-side setup here once player data is loaded
end)
print("SmartUtils: Client-side Internet script loaded.")
