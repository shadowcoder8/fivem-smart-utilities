Config = Config or {}

Config.TrashZones = {
    EnableDebug = true, -- Set to true to draw markers or zones for debugging

    -- Public Bins: Smaller trash collection points
    PublicBins = {
        {
            name = "Legion Square Bin 1",
            coords = vector3(205.78, -948.32, 30.69),
            radius = 1.5, -- Interaction radius
            type = "bin", -- For specific interaction logic or prop
            capacity = 50, -- Max trash units this bin can hold (conceptual)
            currentLoad = 0 -- Initial load (can be managed dynamically)
        },
        {
            name = "Vespucci Beach Bin 1",
            coords = vector3(-1205.8, -1463.5, 4.45),
            radius = 1.5,
            type = "bin",
            capacity = 50,
            currentLoad = 0
        },
        -- Add more public bins here
    },

    -- Dumpsters: Larger trash collection points
    Dumpsters = {
        {
            name = "Downtown Alley Dumpster",
            coords = vector3(135.11, -1709.71, 29.29),
            radius = 2.5, -- Larger interaction radius
            -- For box zones, you might define center, length, width, heading
            -- Example for qb-target or PolyZone box:
            -- type = "box",
            -- length = 3.0,
            -- width = 1.5,
            -- heading = 90.0,
            -- minZ = 28.0,
            -- maxZ = 31.0,
            type = "dumpster",
            capacity = 200, -- Max trash units
            currentLoad = 0
        },
        {
            name = "Industrial Area Dumpster",
            coords = vector3(899.75, -1918.04, 31.2),
            radius = 3.0,
            type = "dumpster",
            capacity = 250,
            currentLoad = 0
        },
        -- Add more dumpsters here
    },

    -- Trash Depot: Where collected trash is processed and paid out
    Depot = {
        name = "La Puerta Trash Depot",
        -- This could be a larger area, defined by a polygon or a larger radius
        -- For simplicity, a point for drop-off interaction
        dropOffCoords = vector3(728.9, -1638.0, 29.01), -- Point where players dump collected trash
        dropOffRadius = 5.0, -- Interaction radius for dumping

        -- For PolyZone, you might define a polygon for the entire depot area
        -- zone = {
        --     vector2(700.0, -1650.0),
        --     vector2(750.0, -1650.0),
        --     vector2(750.0, -1620.0),
        --     vector2(700.0, -1620.0),
        -- },
        -- minZ = 28.0,
        -- maxZ = 35.0,

        payoutPerUnit = 0.5, -- Money paid per unit of trash (e.g., per kg)

        -- Job related settings (if applicable)
        jobVehicles = { -- Vehicles that can be spawned or are allowed for trash collection
            { model = "trash", label = "Trashmaster" },
            -- { model = "mule", label = "Mule (Small Collection)"}
        },
        jobVehicleSpawnPoint = vector4(718.05, -1631.66, 28.99, 180.0), -- Coords and heading for spawning job vehicle
        startJobCoords = vector3(725.61, -1620.2, 29.01), -- Coords to start/end trash job
        startJobRadius = 3.0
    }
}

-- Settings for the trash collection job/activity
Config.TrashCollection = {
    MaxCarryWeight = 100, -- Max trash player can carry before needing to unload (e.g., in kg)
    CollectionTime = 2000, -- Time in ms to collect from a bin/dumpster (used with qb-taskbar)
    FineForIllegalDumping = 250, -- Fine amount
    IllegalDumpCooldown = 30000, -- Cooldown in ms before player can be fined again for illegal dumping
    MinTrashToDump = 10 -- Minimum amount of trash player must have to dump at depot
}

-- You might want to add specific props for bins/dumpsters if they are not already on the map
-- Config.TrashProps = {
--    bin = "prop_bin_07a",
--    dumpster = "prop_dumpster_01a",
-- }

-- If using PolyZone, ensure it's loaded.
-- Example of how these zones might be used with PolyZone:
-- CreateZone("trash_depot_area", Config.TrashZones.Depot.zone, Config.TrashZones.Depot.minZ, Config.TrashZones.Depot.maxZ)
-- Then check if player is inside using IsPointInPolyzone("trash_depot_area", playerCoords)

print("SmartUtils: Trash zone configuration loaded.")

-- Note: The 'currentLoad' for bins/dumpsters would ideally be persisted or dynamically managed
-- on the server if you want their fill state to be consistent across players and server restarts.
-- For this initial implementation, it's a client-side conceptual value or reset on script start.
-- A more advanced system would have the server track and sync these.
