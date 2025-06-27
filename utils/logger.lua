Logger = {}
Logger.LogLevels = {
    NONE = 0,
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4
}

-- Set default log level here, can be overridden by Config.Debug or a specific LogLevel in Config
Logger.CurrentLogLevel = Logger.LogLevels.INFO

-- Function to initialize logger settings, typically called after Config is loaded
function Logger.Initialize()
    if Config and Config.Debug then
        Logger.CurrentLogLevel = Logger.LogLevels.DEBUG
    elseif Config and Config.LogLevel then -- Allow specifying a log level like "INFO", "DEBUG"
        local level = string.upper(Config.LogLevel)
        if Logger.LogLevels[level] then
            Logger.CurrentLogLevel = Logger.LogLevels[level]
        end
    end
    Logger.Info("Logger Initialized. Current Log Level: " .. Logger.GetLogLevelName(Logger.CurrentLogLevel))
end

function Logger.GetLogLevelName(levelValue)
    for name, value in pairs(Logger.LogLevels) do
        if value == levelValue then
            return name
        end
    end
    return "UNKNOWN"
end

function Logger.Log(level, message, ...)
    if level <= Logger.CurrentLogLevel then
        local formattedMessage = string.format(message, ...)
        local logLevelName = Logger.GetLogLevelName(level)
        local prefix = "[SmartUtilities][" .. logLevelName .. "]"

        if IsDuplicityVersion() then -- Client side
            print(("%s %s"):format(prefix, formattedMessage))
        else -- Server side
            print(("%s %s"):format(prefix, formattedMessage))
        end
    end
end

function Logger.Debug(message, ...)
    Logger.Log(Logger.LogLevels.DEBUG, message, ...)
end

function Logger.Info(message, ...)
    Logger.Log(Logger.LogLevels.INFO, message, ...)
end

function Logger.Warn(message, ...)
    Logger.Log(Logger.LogLevels.WARN, message, ...)
end

function Logger.Error(message, ...)
    Logger.Log(Logger.LogLevels.ERROR, message, ...)
end

-- Perform initial setup when script loads.
-- Note: Config might not be fully available when this shared script is first parsed.
-- Logger.Initialize() should be called explicitly from client.lua and server.lua after Config is confirmed loaded.
-- However, for immediate use (like logging that the logger itself loaded), a default level is set.

-- Example of calling Initialize after Config is ready:
-- In your client.lua or server.lua, after ensuring Config is loaded:
-- if Logger and Logger.Initialize then Logger.Initialize() end

-- For now, let's print a startup message with default level.
Logger.Log(Logger.LogLevels.INFO, "Logger script loaded. Call Logger.Initialize() after Config is available.")
