-- RemoteTerminalContextMenu.lua
-- Right-click inventory context menu for the crafted Remote Terminal item.
-- Adds options: Open, Set/Change PIN, Recharge (near running generator).

require "ISUI/ISTextBox"
require "TimedActions/ISBaseTimedAction"
require "RemoteTerminal/RemoteTerminal"
require "RemoteTerminal/RemoteTerminalData"
require "RemoteTerminal/RemoteTerminalHandheldUI"

RemoteTerminalContextMenu = RemoteTerminalContextMenu or {}

-- ============================================================================
-- Timed Action: Recharge at a running generator
-- ============================================================================
RemoteTerminalRechargeAction = ISBaseTimedAction:derive("RemoteTerminalRechargeAction")

function RemoteTerminalRechargeAction:new(character, deviceItem)
    local o = ISBaseTimedAction:new(character)
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.deviceItem = deviceItem

    o.maxTime = 6000
    if SandboxVars and SandboxVars.RemoteTerminal then
        local sbTime = tonumber(SandboxVars.RemoteTerminal.RechargeTime)
        if sbTime and sbTime > 0 then
            o.maxTime = sbTime
        end
    end
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function RemoteTerminalRechargeAction:isValid()
    if not self.deviceItem then return false end
    local battery = self.deviceItem:getModData()[RemoteTerminal.BATTERY_KEY]
    local val = tonumber(battery)
    if val == nil then return false end
    return val < RemoteTerminal.BATTERY_MAX
end

function RemoteTerminalRechargeAction:perform()
    self.deviceItem:getModData()[RemoteTerminal.BATTERY_KEY] = nil -- clear = full charge
    if self.character and self.character.Say then
        self.character:Say("Remote Terminal fully charged")
    end
    ISBaseTimedAction.perform(self)
end

-- ============================================================================
-- Item Detection
-- ============================================================================

local function isDeviceItem(item)
    if not item then return false end
    if not instanceof(item, "InventoryItem") then return false end
    return item:getFullType() == "Base.RemoteTerminal"
end

local function collectActualItems(items)
    if not items then return {} end
    if instanceof(items, "InventoryItem") then return { items } end
    if ISInventoryPane and ISInventoryPane.getActualItems then
        local ok, result = pcall(ISInventoryPane.getActualItems, items)
        if ok and result then return result end
    end
    if type(items) == "table" then return items end
    return {}
end

-- ============================================================================
-- Find Running Generator (within 3 tiles)
-- ============================================================================
local function findNearbyRunningGenerator(playerObj)
    if not playerObj then return nil end
    local origin = playerObj:getSquare()
    if not origin then return nil end
    local cell = getCell()
    if not cell then return nil end

    local cx, cy = origin:getX(), origin:getY()
    for x = cx - 3, cx + 3 do
        for y = cy - 3, cy + 3 do
            for z = 0, 7 do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    for _, listName in ipairs({ "getObjects", "getSpecialObjects" }) do
                        local okL, list = pcall(function() return sq[listName](sq) end)
                        if okL and list then
                            for i = 0, list:size() - 1 do
                                local obj = list:get(i)
                                if obj and instanceof(obj, "IsoGenerator") then
                                    local okA, active = pcall(function() return obj:isActivated() end)
                                    if okA and active then
                                        return sq
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================================
-- Context Menu Hook
-- ============================================================================

local function addUseOption(player, context, items)
    local actualItems = collectActualItems(items)
    if not actualItems or #actualItems == 0 then return end

    local deviceItem = nil
    for _, item in ipairs(actualItems) do
        if isDeviceItem(item) then
            deviceItem = item
            break
        end
    end
    if not deviceItem then return end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    -- "Open Remote Terminal"
    context:addOption(
        "Open Remote Terminal",
        deviceItem,
        function()
            RemoteTerminalHandheldUI.openHandheld(deviceItem, playerObj)
        end
    )

    -- "Set Device PIN" / "Change Device PIN"
    local currentPIN = deviceItem:getModData().DevicePIN or ""
    local pinText = currentPIN ~= "" and "Change Device PIN" or "Set Device PIN"
    context:addOption(
        pinText,
        deviceItem,
        function()
            local title = (currentPIN ~= "" and "Change" or "Set") .. " Device PIN"
            if currentPIN ~= "" then
                title = title .. " (current: ****)"
            else
                title = title .. " (none)"
            end
            local modal = ISTextBox:new(
                0, 0, 360, 150,
                title, "", nil,
                function(_target, button)
                    if button.internal ~= "OK" then return end
                    local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
                    local pin = RemoteTerminal.normalizePIN(text, true)
                    if pin then
                        deviceItem:getModData().DevicePIN = (pin ~= "" and pin or nil)
                    end
                end,
                playerObj:getPlayerNum()
            )
            modal.maxChars = 4
            modal:initialise()
            modal:setOnlyNumbers(true)
            modal:addToUIManager()
        end
    )

    -- "Recharge" (only if battery < 100% and near running generator)
    local battery = deviceItem:getModData()[RemoteTerminal.BATTERY_KEY]
    local batteryVal = tonumber(battery)
    if batteryVal == nil then
        -- Full charge (no modData key = full)
        batteryVal = RemoteTerminal.BATTERY_MAX
    end
    if batteryVal < RemoteTerminal.BATTERY_MAX then
        local genSquare = findNearbyRunningGenerator(playerObj)
        if genSquare then
            local pct = math.floor(batteryVal / RemoteTerminal.BATTERY_MAX * 100)
            context:addOption(
                "Recharge Remote Terminal (" .. pct .. "%)",
                deviceItem,
                function()
                    ISTimedActionQueue.add(RemoteTerminalRechargeAction:new(playerObj, deviceItem))
                end
            )
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(addUseOption)
