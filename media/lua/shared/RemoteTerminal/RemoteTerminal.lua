-- RemoteTerminal.lua
-- Shared module bootstrap, constants, and utility functions for the
-- Remote Terminal mod.
--
-- This mod replaces chunk-radius scanning with a server-side global
-- data table (RemoteTerminal.Network) so players can access their
-- warehouse network from anywhere.

RemoteTerminal = RemoteTerminal or {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
RemoteTerminal.DEFAULT_RADIUS = 12
RemoteTerminal.MAX_RADIUS = 30
RemoteTerminal.PACKER_SCAN_RADIUS = 80
RemoteTerminal.PIN_PATTERN = "^%d%d%d%d$"
RemoteTerminal.TERMINAL_CODE_LENGTH = 6
RemoteTerminal.IP_SEGMENT_MIN = 10
RemoteTerminal.IP_SEGMENT_MAX = 199

-- Battery defaults (overridable via sandbox)
RemoteTerminal.BATTERY_MAX = 100
RemoteTerminal.BATTERY_DRAIN_PER_ITEM = 2.0
RemoteTerminal.BATTERY_KEY = "DeviceBattery"

-- Server command module name
RemoteTerminal.COMMAND_MODULE = "RemoteTerminal"

-- ---------------------------------------------------------------------------
-- IP Helpers
-- ---------------------------------------------------------------------------

--- Generate a random Packer IP address (like 192.168.x.x style).
--- Mirrors WarehouseTerminal_Balanced IP generation.
function RemoteTerminal.generatePackerIP()
    return tostring(RemoteTerminal.IP_SEGMENT_MIN + ZombRand(RemoteTerminal.IP_SEGMENT_MAX - RemoteTerminal.IP_SEGMENT_MIN + 1))
        .. "." .. tostring(ZombRand(256))
        .. "." .. tostring(ZombRand(256))
        .. "." .. tostring(RemoteTerminal.IP_SEGMENT_MIN + ZombRand(RemoteTerminal.IP_SEGMENT_MAX - RemoteTerminal.IP_SEGMENT_MIN + 1))
end

--- Normalize an IP string (trim whitespace, validate format).
--- Returns the normalized IP string or nil if invalid.
function RemoteTerminal.normalizeIP(value)
    value = tostring(value or ""):gsub("%s+", "")
    if value == "" then
        return nil
    end
    -- Basic IP format check: four segments of digits
    if not value:match("^%d+%.%d+%.%d+%.%d+$") then
        return nil
    end
    return value
end

-- ---------------------------------------------------------------------------
-- Terminal Code Helpers
-- ---------------------------------------------------------------------------

--- Generate a random 6-character alphanumeric terminal code.
--- Mirrors WarehouseTerminal_Balanced terminal code generation.
function RemoteTerminal.generateTerminalCode()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local code = ""
    for _ = 1, RemoteTerminal.TERMINAL_CODE_LENGTH do
        local index = ZombRand(string.len(chars)) + 1
        code = code .. string.sub(chars, index, index)
    end
    return code
end

--- Normalize a terminal code (uppercase, strip non-alphanumeric, max 12 chars).
function RemoteTerminal.normalizeTerminalCode(value)
    value = tostring(value or ""):upper():gsub("[^A-Z0-9]", "")
    if value == "" then
        return nil
    end
    return string.sub(value, 1, 12)
end

-- ---------------------------------------------------------------------------
-- PIN Helpers
-- ---------------------------------------------------------------------------

--- Validate and normalize a 4-digit PIN.
--- @param value string The raw PIN input.
--- @param allowEmpty boolean If true, empty string is valid (clears PIN).
--- @return string|nil The normalized 4-digit PIN, or nil if invalid.
function RemoteTerminal.normalizePIN(value, allowEmpty)
    value = tostring(value or ""):gsub("%s+", "")
    if value == "" and allowEmpty then
        return ""
    end
    if value:match(RemoteTerminal.PIN_PATTERN) then
        return value
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Radius Helpers
-- ---------------------------------------------------------------------------

--- Clamp a radius value to valid range [1, MAX_RADIUS].
function RemoteTerminal.clampRadius(value)
    value = tonumber(value) or RemoteTerminal.DEFAULT_RADIUS
    value = math.floor(value)
    if value < 1 then
        return 1
    end
    if value > RemoteTerminal.MAX_RADIUS then
        return RemoteTerminal.MAX_RADIUS
    end
    return value
end

-- ---------------------------------------------------------------------------
-- Object Detection Helpers (shared by client & server)
-- ---------------------------------------------------------------------------

--- Check if an object is a Remote Terminal network packer.
function RemoteTerminal.isPackerObject(object)
    return object and object:getModData() and object:getModData().RemotePacker == true
end

--- Check if an object is a Remote Terminal network terminal.
function RemoteTerminal.isTerminalObject(object)
    return object and object:getModData() and object:getModData().RemoteTerminalObj == true
end

-- ---------------------------------------------------------------------------
-- Sandbox Initialization
-- ---------------------------------------------------------------------------

--- Read sandbox settings once. Call this early in client and server init.
function RemoteTerminal.initSandbox()
    if RemoteTerminal._sandboxInitialized then
        return
    end
    RemoteTerminal._sandboxInitialized = true

    if SandboxVars and SandboxVars.RemoteTerminal then
        local sbMax = tonumber(SandboxVars.RemoteTerminal.BatteryMax)
        if sbMax and sbMax > 0 then
            RemoteTerminal.BATTERY_MAX = math.floor(sbMax)
        end
        local sbDrain = tonumber(SandboxVars.RemoteTerminal.BatteryDrainPerItem)
        if sbDrain and sbDrain > 0 then
            RemoteTerminal.BATTERY_DRAIN_PER_ITEM = sbDrain
        end
    end
end

-- ---------------------------------------------------------------------------
-- Color Scheme (shared by all client UIs)
-- ---------------------------------------------------------------------------
RemoteTerminal.Colors = {
    window      = { r = 0.015, g = 0.025, b = 0.026, a = 0.90 },
    border      = { r = 0.18, g = 0.58, b = 0.54, a = 1.00 },
    list        = { r = 0.012, g = 0.025, b = 0.026, a = 0.62 },
    input       = { r = 0.010, g = 0.035, b = 0.034, a = 0.82 },
    inputBorder = { r = 0.18, g = 0.58, b = 0.54, a = 1.00 },
    rowAlt      = { r = 0.025, g = 0.060, b = 0.060, a = 0.55 },
    rowSelected = { r = 0.030, g = 0.240, b = 0.205, a = 0.86 },
    rowBorder   = { r = 0.125, g = 0.350, b = 0.340, a = 0.55 },
    header      = { r = 0.025, g = 0.075, b = 0.073, a = 0.58 },
    text        = { r = 0.88, g = 0.95, b = 0.92, a = 1.00 },
    textDim     = { r = 0.56, g = 0.74, b = 0.72, a = 1.00 },
    accent      = { r = 0.22, g = 0.86, b = 0.62, a = 1.00 },
    cold        = { r = 0.42, g = 0.78, b = 1.00, a = 1.00 },
    amber       = { r = 0.95, g = 0.72, b = 0.28, a = 1.00 },
    danger      = { r = 0.82, g = 0.24, b = 0.22, a = 1.00 },
}
