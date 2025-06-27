-- Input Validation Utilities
Validation = {}

-- Validate property ID format
function Validation.ValidatePropertyId(propertyId)
    if not propertyId or type(propertyId) ~= "string" then
        return false, "Property ID must be a string"
    end
    if #propertyId > 50 or #propertyId < 3 then
        return false, "Property ID must be between 3 and 50 characters"
    end
    if not string.match(propertyId, "^[a-zA-Z0-9_%-]+$") then
        return false, "Property ID contains invalid characters"
    end
    return true, nil
end

-- Validate coordinates
function Validation.ValidateCoords(coords)
    if not coords or type(coords) ~= "table" then
        return false, "Coordinates must be a table"
    end
    if not coords.x or not coords.y or not coords.z then
        return false, "Coordinates must have x, y, z values"
    end
    if type(coords.x) ~= "number" or type(coords.y) ~= "number" or type(coords.z) ~= "number" then
        return false, "Coordinate values must be numbers"
    end
    if math.abs(coords.x) > 10000 or math.abs(coords.y) > 10000 or math.abs(coords.z) > 2000 then
        return false, "Coordinates are out of valid range"
    end
    return true, nil
end

-- Validate internet tier
function Validation.ValidateInternetTier(tier)
    local validTiers = { "Basic", "Premium", "Ultra" }
    if not tier or type(tier) ~= "string" then
        return false, "Tier must be a string"
    end
    for _, validTier in ipairs(validTiers) do
        if tier == validTier then
            return true, nil
        end
    end
    return false, "Invalid tier specified"
end

-- Validate zone ID
function Validation.ValidateZoneId(zoneId)
    if not zoneId or type(zoneId) ~= "string" then
        return false, "Zone ID must be a string"
    end
    if #zoneId > 30 or #zoneId < 2 then
        return false, "Zone ID must be between 2 and 30 characters"
    end
    if not string.match(zoneId, "^[a-zA-Z0-9_%-]+$") then
        return false, "Zone ID contains invalid characters"
    end
    return true, nil
end

-- Validate numeric amount
function Validation.ValidateAmount(amount, min, max)
    if not amount or type(amount) ~= "number" then
        return false, "Amount must be a number"
    end
    if amount < (min or 0) or amount > (max or 999999) then
        return false, string.format("Amount must be between %d and %d", min or 0, max or 999999)
    end
    return true, nil
end

-- Sanitize string input
function Validation.SanitizeString(input, maxLength)
    if not input or type(input) ~= "string" then
        return nil
    end
    if #input > (maxLength or 255) then
        return string.sub(input, 1, maxLength or 255)
    end
    return input
end

-- Safe execution wrapper
function Validation.SafeExecute(func, errorMsg, ...)
    local success, result = pcall(func, ...)
    if not success then
        Logger.Error((errorMsg or "Function execution failed") .. ": " .. tostring(result))
        return nil, result
    end
    return result, nil
end

Logger.Info("Validation utilities loaded.")