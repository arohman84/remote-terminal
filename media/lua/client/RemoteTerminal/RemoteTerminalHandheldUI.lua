-- RemoteTerminalHandheldUI.lua
-- Handheld remote terminal window — opened by right-clicking the
-- crafted Remote Terminal item in inventory.
--
-- Features: IP entry, connect/disconnect, battery bar, two-panel
-- item list with transfer buttons. Always queries the server via
-- RemoteTerminalData (never local scanning). Battery drains on
-- transfers; device closes at 0%.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISTextBox"
require "ISUI/ISMouseDrag"
require "ISUI/ISInventoryPane"
require "TimedActions/ISInventoryTransferAction"
require "RemoteTerminal/RemoteTerminal"
require "RemoteTerminal/RemoteTerminalData"
require "RemoteTerminal/RemoteTerminalItemList"

RemoteTerminalHandheldUI = RemoteTerminalHandheldUI or {}

-- ============================================================================
-- Window Class
-- ============================================================================
RemoteTerminalHandheldWindow = ISCollapsableWindow:derive("RemoteTerminalHandheldWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local WINDOW_WIDTH = 1000
local WINDOW_HEIGHT = 620
local LEFT_PANEL_WIDTH = 760
local RIGHT_PANEL_WIDTH = 210
local BUTTON_HEIGHT = 28

function RemoteTerminalHandheldWindow:new(x, y, deviceItem, playerObj)
    local o = ISCollapsableWindow:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.deviceItem = deviceItem
    o.playerObj = playerObj
    o.networkState = nil
    o.connectedIP = nil
    o.autoRefreshTimer = 0
    o.isTransferring = false

    -- Read stored IP from device item modData
    o.storedIP = deviceItem and deviceItem:getModData().DevicePackerIP or ""

    o:setTitle("Remote Terminal — Handheld Device")
    o:setResizable(false)

    local colors = RemoteTerminal.Colors
    o:setBackgroundRGBA(colors.window.r, colors.window.g, colors.window.b, colors.window.a)

    o:buildUI()

    return o
end

function RemoteTerminalHandheldWindow:buildUI()
    local colors = RemoteTerminal.Colors
    local top = 30
    local leftMargin = 8

    -- ========================================================================
    -- TOP BAR — IP Entry + Connect + Battery
    -- ========================================================================
    local barY = top

    -- Packer IP entry
    self.ipEntry = ISTextEntryBox:new("", leftMargin, barY, 180, 22)
    self.ipEntry:initialise()
    self.ipEntry:instantiate()
    self.ipEntry.tooltip = "Packer IP address"
    self.ipEntry:setText(self.storedIP or "")
    self:addChild(self.ipEntry)
    RemoteTerminalData.applyInputStyle(self.ipEntry)

    local btnX = leftMargin + 188

    -- Connect button
    self.connectBtn = ISButton:new(btnX, barY, 90, 22, "Connect", self,
        function() self:onConnect() end)
    self.connectBtn:initialise()
    self.connectBtn:instantiate()
    self.connectBtn.internal = "CONNECT"
    self:addChild(self.connectBtn)
    RemoteTerminalData.applyButtonStyle(self.connectBtn, "take", false)

    btnX = btnX + 96

    -- Disconnect button
    self.disconnectBtn = ISButton:new(btnX, barY, 90, 22, "Disconnect", self,
        function() self:onDisconnect() end)
    self.disconnectBtn:initialise()
    self.disconnectBtn:instantiate()
    self.disconnectBtn.internal = "DISCONNECT"
    self:addChild(self.disconnectBtn)
    RemoteTerminalData.applyButtonStyle(self.disconnectBtn, "danger", false)

    btnX = btnX + 96

    -- Status label
    self.statusLabel = ISLabel:new(btnX, barY + 4, 20, "Not connected", 1, 1, 1, 1, UIFont.Small)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)

    -- Battery bar (right side of top bar)
    local batteryX = WINDOW_WIDTH - 160
    self.batteryLabel = ISLabel:new(batteryX, barY + 4, 20, "Battery: 100%", 1, 1, 1, 1, UIFont.Small)
    self.batteryLabel:initialise()
    self:addChild(self.batteryLabel)

    -- ========================================================================
    -- LEFT PANEL — Item List
    -- ========================================================================
    local listY = barY + 32
    local listX = leftMargin
    local listW = LEFT_PANEL_WIDTH
    local listH = WINDOW_HEIGHT - listY - 10

    self.itemList = RemoteTerminalItemList:new(listX, listY, listW, listH)
    self.itemList:instantiate()
    self:addChild(self.itemList)
    RemoteTerminalData.applyListStyle(self.itemList)

    -- Search entry (above item list, right of IP bar)
    local searchY = barY
    local searchX = listX + listW - 210
    self.searchEntry = ISTextEntryBox:new("", searchX, searchY, 200, 20)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry.tooltip = "Search items..."
    self.searchEntry.onTextChange = function()
        if self.itemList then
            self.itemList:setSearchText(self.searchEntry:getText())
        end
    end
    self:addChild(self.searchEntry)
    RemoteTerminalData.applyInputStyle(self.searchEntry)

    -- ========================================================================
    -- RIGHT PANEL — Info + Action Buttons
    -- ========================================================================
    local rightX = listX + listW + 10
    local btnW = RIGHT_PANEL_WIDTH
    local btnY = listY + 30

    -- Network info
    self.netInfoLabel = ISLabel:new(rightX, btnY - 20, 20, "No network data", 1, 1, 1, 1, UIFont.Small)
    self.netInfoLabel:initialise()
    self:addChild(self.netInfoLabel)
    btnY = btnY + 10

    -- Transfer buttons
    local function makeActionButton(label, internal, kind, yOff, callback)
        local btn = ISButton:new(rightX, btnY + yOff, btnW, BUTTON_HEIGHT, label, self, callback)
        btn:initialise()
        btn:instantiate()
        btn.internal = internal
        self:addChild(btn)
        RemoteTerminalData.applyButtonStyle(btn, kind)
        return btn
    end

    makeActionButton("Take One", "TAKE_ONE", "take", 0, function() self:takeItems("one") end)
    makeActionButton("Take Half", "TAKE_HALF", "take", BUTTON_HEIGHT + 4, function() self:takeItems("half") end)
    makeActionButton("Take All", "TAKE_ALL", "take", (BUTTON_HEIGHT + 4) * 2, function() self:takeItems("all") end)

    btnY = btnY + (BUTTON_HEIGHT + 4) * 3 + 16

    makeActionButton("Store Selected", "STORE_SELECTED", "store", 0, function() self:storeSelected() end)
    makeActionButton("Store All", "STORE_ALL", "store", BUTTON_HEIGHT + 4, function() self:storeAll() end)

    btnY = btnY + (BUTTON_HEIGHT + 4) * 2 + 16

    makeActionButton("Refresh", "REFRESH", "config", 0, function() self:refreshState() end)

    -- View tabs at bottom of right panel
    local tabY = WINDOW_HEIGHT - BUTTON_HEIGHT - 30
    local tabW = (btnW - 12) / 4

    local function makeTabButton(name, mode, tabIdx)
        local btn = ISButton:new(rightX + (tabW + 4) * tabIdx, tabY, tabW, 22, name, self,
            function()
                self.itemList:setViewMode(mode)
                self:_updateTabStyles()
            end)
        btn:initialise()
        btn:instantiate()
        btn.internal = mode
        self:addChild(btn)
        RemoteTerminalData.applyButtonStyle(btn, "neutral", false)
        return btn
    end

    self.nameTabBtn = makeTabButton("Name", RemoteTerminalItemList.VIEW_NAME, 0)
    self.categoryTabBtn = makeTabButton("Cat", RemoteTerminalItemList.VIEW_CATEGORY, 1)
    self.fridgeTabBtn = makeTabButton("Fridge", RemoteTerminalItemList.VIEW_FRIDGE, 2)
    self.freezerTabBtn = makeTabButton("Freezer", RemoteTerminalItemList.VIEW_FREEZER, 3)

    self:_updateTabStyles()
end

function RemoteTerminalHandheldWindow:_updateTabStyles()
    local function styleTab(btn, mode)
        local active = self.itemList and self.itemList.viewMode == mode
        RemoteTerminalData.applyButtonStyle(btn, "neutral", active)
    end
    styleTab(self.nameTabBtn, RemoteTerminalItemList.VIEW_NAME)
    styleTab(self.categoryTabBtn, RemoteTerminalItemList.VIEW_CATEGORY)
    styleTab(self.fridgeTabBtn, RemoteTerminalItemList.VIEW_FRIDGE)
    styleTab(self.freezerTabBtn, RemoteTerminalItemList.VIEW_FREEZER)
end

-- ============================================================================
-- Battery Management
-- ============================================================================

function RemoteTerminalHandheldWindow:getDeviceBattery()
    if not self.deviceItem then return RemoteTerminal.BATTERY_MAX end
    local val = tonumber(self.deviceItem:getModData()[RemoteTerminal.BATTERY_KEY])
    if val == nil then return RemoteTerminal.BATTERY_MAX end
    return math.max(0, math.min(RemoteTerminal.BATTERY_MAX, val))
end

function RemoteTerminalHandheldWindow:setDeviceBattery(value)
    if not self.deviceItem then return end
    value = math.max(0, math.min(RemoteTerminal.BATTERY_MAX, math.floor(value or RemoteTerminal.BATTERY_MAX)))
    if value >= RemoteTerminal.BATTERY_MAX then
        self.deviceItem:getModData()[RemoteTerminal.BATTERY_KEY] = nil
    else
        self.deviceItem:getModData()[RemoteTerminal.BATTERY_KEY] = value
    end
end

function RemoteTerminalHandheldWindow:drainBattery(itemCount)
    local charge = self:getDeviceBattery()
    local drain = (itemCount or 1) * RemoteTerminal.BATTERY_DRAIN_PER_ITEM
    charge = charge - drain
    self:setDeviceBattery(charge)

    if charge <= 0 then
        self:close()
        if self.playerObj and self.playerObj.Say then
            self.playerObj:Say("Remote Terminal battery is dead.")
        end
    end

    return charge
end

function RemoteTerminalHandheldWindow:updateBatteryDisplay()
    local pct = math.floor(self:getDeviceBattery() / RemoteTerminal.BATTERY_MAX * 100)
    local colors = RemoteTerminal.Colors
    local r, g, b = colors.accent.r, colors.accent.g, colors.accent.b
    if pct <= 20 then
        r, g, b = colors.danger.r, colors.danger.g, colors.danger.b
    elseif pct <= 50 then
        r, g, b = colors.amber.r, colors.amber.g, colors.amber.b
    end

    self.batteryLabel:setName("Battery: " .. tostring(pct) .. "%")
    self.batteryLabel.r = r
    self.batteryLabel.g = g
    self.batteryLabel.b = b
end

-- ============================================================================
-- Connection
-- ============================================================================

function RemoteTerminalHandheldWindow:onConnect()
    -- Check battery
    if self:getDeviceBattery() <= 0 then
        self.statusLabel:setName("Battery dead — recharge at a generator")
        return
    end

    local ip = RemoteTerminal.normalizeIP(self.ipEntry:getText())
    if not ip then
        self.statusLabel:setName("Invalid IP address")
        return
    end

    self.connectedIP = ip
    self.statusLabel:setName("Connecting...")

    -- Save IP to device item
    if self.deviceItem then
        self.deviceItem:getModData().DevicePackerIP = ip
    end

    self:refreshState()
end

function RemoteTerminalHandheldWindow:onDisconnect()
    self.connectedIP = nil
    self.networkState = nil
    self.statusLabel:setName("Disconnected")
    self.netInfoLabel:setName("No network data")
    self.itemList:setEntries({})
    self.autoRefreshTimer = 0
end

function RemoteTerminalHandheldWindow:refreshState()
    if not self.connectedIP then
        self.statusLabel:setName("Not connected")
        return
    end

    self.statusLabel:setName("Connecting...")

    RemoteTerminalData.requestNetworkState(self.connectedIP, function(state, err)
        if state then
            self.networkState = state
            self.statusLabel:setName("Connected — " .. tostring(#state.items) .. " types")
            self.netInfoLabel:setName("Packer: " .. tostring(state.ip)
                .. " | Terminals: " .. tostring(state.terminals and #state.terminals or 0))
            self.itemList:setEntries(state.items or {})
            self.autoRefreshTimer = RemoteTerminalData.AUTO_REFRESH_INTERVAL
        else
            self.statusLabel:setName("Error: " .. tostring(err or "Failed"))
        end
    end)
end

-- ============================================================================
-- Item Transfers
-- ============================================================================

function RemoteTerminalHandheldWindow:takeItems(mode)
    if self.isTransferring or not self.connectedIP then return end

    local selected = self.itemList:getSelectedEntries()
    if #selected == 0 then
        self.statusLabel:setName("Select items first")
        return
    end

    self.isTransferring = true

    for _, entry in ipairs(selected) do
        local count = entry.count
        if mode == "one" then count = 1
        elseif mode == "half" then count = math.max(1, math.floor(entry.count / 2))
        end

        self:drainBattery(count)

        RemoteTerminalData.requestTransfer(self.connectedIP, entry.fullType, count, function(result)
            self.statusLabel:setName("Transferred: " .. tostring(result.transferred or 0) .. " x " .. entry.displayName)
        end)
    end

    self.isTransferring = false
    -- Refresh after short delay
    self.autoRefreshTimer = 2
end

function RemoteTerminalHandheldWindow:storeSelected()
    if self.isTransferring or not self.connectedIP then return end

    local selected = self.itemList:getSelectedEntries()
    if #selected == 0 then return end

    self.isTransferring = true

    for _, entry in ipairs(selected) do
        local playerCount = RemoteTerminalData.countPlayerItems(self.playerObj, entry.fullType)
        if playerCount > 0 then
            self:drainBattery(playerCount)
            RemoteTerminalData.requestStore(self.connectedIP, entry.fullType, playerCount)
        end
    end

    self.isTransferring = false
    self.autoRefreshTimer = 2
end

function RemoteTerminalHandheldWindow:storeAll()
    if self.isTransferring or not self.connectedIP then return end
    if not self.networkState or not self.networkState.items then return end

    self.isTransferring = true

    for _, entry in ipairs(self.networkState.items) do
        local playerCount = RemoteTerminalData.countPlayerItems(self.playerObj, entry.fullType)
        if playerCount > 0 then
            self:drainBattery(playerCount)
            RemoteTerminalData.requestStore(self.connectedIP, entry.fullType, playerCount)
        end
    end

    self.isTransferring = false
    self.autoRefreshTimer = 2
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function RemoteTerminalHandheldWindow:update()
    ISCollapsableWindow.update(self)

    -- Auto-refresh
    if self.autoRefreshTimer and self.autoRefreshTimer > 0 then
        self.autoRefreshTimer = self.autoRefreshTimer - 1
        if self.autoRefreshTimer <= 0 then
            self:refreshState()
        end
    end

    -- Battery display
    self:updateBatteryDisplay()
end

function RemoteTerminalHandheldWindow:close()
    ISCollapsableWindow.close(self)
    self:setVisible(false)
    self:removeFromUIManager()
end

-- ============================================================================
-- Open from inventory item
-- ============================================================================

--- Open the handheld remote terminal window from the device item.
--- @param deviceItem InventoryItem The Remote Terminal item.
--- @param playerObj IsoPlayer The player.
function RemoteTerminalHandheldUI.openHandheld(deviceItem, playerObj)
    if not deviceItem or not playerObj then return end

    -- Check battery
    local battery = deviceItem:getModData()[RemoteTerminal.BATTERY_KEY]
    if battery and tonumber(battery) <= 0 then
        if playerObj.Say then
            playerObj:Say("Remote Terminal battery is dead. Recharge at a generator.")
        end
        return
    end

    -- PIN check
    local devicePIN = deviceItem:getModData().DevicePIN
    if devicePIN and devicePIN ~= "" then
        local modal = ISTextBox:new(
            0, 0, 360, 150,
            "Enter Device PIN",
            "", nil,
            function(_target, button)
                if button.internal ~= "OK" then return end
                local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
                if RemoteTerminal.normalizePIN(text, false) == devicePIN then
                    local wx = (getCore():getScreenWidth() - WINDOW_WIDTH) / 2
                    local wy = (getCore():getScreenHeight() - WINDOW_HEIGHT) / 2
                    local window = RemoteTerminalHandheldWindow:new(wx, wy, deviceItem, playerObj)
                    window:addToUIManager()
                    window:setVisible(true)
                else
                    if playerObj.Say then
                        playerObj:Say("Wrong PIN.")
                    end
                end
            end,
            playerObj:getPlayerNum()
        )
        modal.maxChars = 4
        modal:initialise()
        modal:setOnlyNumbers(true)
        modal:addToUIManager()
        return
    end

    -- No PIN — open directly
    local wx = (getCore():getScreenWidth() - WINDOW_WIDTH) / 2
    local wy = (getCore():getScreenHeight() - WINDOW_HEIGHT) / 2
    local window = RemoteTerminalHandheldWindow:new(wx, wy, deviceItem, playerObj)
    window:addToUIManager()
    window:setVisible(true)
end
