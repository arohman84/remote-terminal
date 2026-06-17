-- RemoteTerminalTerminalUI.lua
-- Walk-up terminal window — opened by right-clicking a world-placed
-- Remote Terminal object. Matches the original WarehouseTerminal UX:
-- two-panel layout with item list on the left and transfer/configure
-- buttons on the right.
--
-- Uses RemoteTerminalData for server communication and
-- RemoteTerminalItemList for the shared item list component.

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

RemoteTerminalTerminalUI = RemoteTerminalTerminalUI or {}

-- ============================================================================
-- Window Class
-- ============================================================================
RemoteTerminalWindow = ISCollapsableWindow:derive("RemoteTerminalWindow")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local WINDOW_WIDTH = 1000
local WINDOW_HEIGHT = 600
local LEFT_PANEL_WIDTH = 760
local RIGHT_PANEL_WIDTH = 210
local BUTTON_HEIGHT = 28

function RemoteTerminalWindow:new(x, y, terminalObject, playerObj)
    local o = ISCollapsableWindow:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.terminalObject = terminalObject
    o.playerObj = playerObj
    o.networkState = nil
    o.connectedIP = nil
    o.autoRefreshTimer = 0
    o.isTransferring = false

    -- Read terminal metadata
    local modData = terminalObject and terminalObject:getModData()
    o.terminalCode = modData and modData.RemoteTerminalCode or "??????"
    o.packerIP = modData and modData.RemotePackerIP or ""

    o:setTitle("Remote Terminal — " .. o.terminalCode)
    o:setResizable(false)

    -- Colors
    local colors = RemoteTerminal.Colors
    o:setBackgroundRGBA(colors.window.r, colors.window.g, colors.window.b, colors.window.a)

    o:buildUI()
    o:connect()

    return o
end

function RemoteTerminalWindow:buildUI()
    local colors = RemoteTerminal.Colors
    local top = 30
    local leftMargin = 8

    -- ========================================================================
    -- LEFT PANEL — Item List
    -- ========================================================================
    local listX = leftMargin
    local listY = top + 24
    local listW = LEFT_PANEL_WIDTH
    local listH = WINDOW_HEIGHT - listY - 10

    self.itemList = RemoteTerminalItemList:new(listX, listY, listW, listH)
    self.itemList:instantiate()
    self:addChild(self.itemList)
    RemoteTerminalData.applyListStyle(self.itemList)

    -- Search entry (above item list)
    local searchY = top
    self.searchEntry = ISTextEntryBox:new("", listX, searchY, 200, 20)
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

    -- View tab buttons
    local tabY = searchY
    local tabX = listX + 210
    local tabW = 80
    local tabH = 20

    local function makeTabButton(name, mode)
        local btn = ISButton:new(tabX, tabY, tabW, tabH, name, self,
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

    self.nameTabBtn = makeTabButton("Name", RemoteTerminalItemList.VIEW_NAME)
    tabX = tabX + tabW + 4
    self.categoryTabBtn = makeTabButton("Category", RemoteTerminalItemList.VIEW_CATEGORY)
    tabX = tabX + tabW + 4
    self.fridgeTabBtn = makeTabButton("Fridge", RemoteTerminalItemList.VIEW_FRIDGE)
    tabX = tabX + tabW + 4
    self.freezerTabBtn = makeTabButton("Freezer", RemoteTerminalItemList.VIEW_FREEZER)

    self:_updateTabStyles()

    -- ========================================================================
    -- RIGHT PANEL — Info + Action Buttons
    -- ========================================================================
    local rightX = listX + listW + 10
    local btnW = RIGHT_PANEL_WIDTH
    local btnY = top + 50

    -- Packer IP display
    self.ipLabel = ISLabel:new(rightX, btnY, 20, "Packer: " .. (self.packerIP or "Not set"), 1, 1, 1, 1, UIFont.Small)
    self.ipLabel:initialise()
    self:addChild(self.ipLabel)
    btnY = btnY + 24

    -- Status
    self.statusLabel = ISLabel:new(rightX, btnY, 20, "Connecting...", 1, 1, 1, 1, UIFont.Small)
    self.statusLabel:initialise()
    self:addChild(self.statusLabel)
    btnY = btnY + 40

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

    makeActionButton("Refresh", "REFRESH", "config", 0, function() self:connect() end)

    btnY = btnY + BUTTON_HEIGHT + 8

    -- Packer IP entry (to change)
    self.ipEntry = ISTextEntryBox:new("", rightX, btnY, btnW, 20)
    self.ipEntry:initialise()
    self.ipEntry:instantiate()
    self.ipEntry.tooltip = "Set new Packer IP"
    self.ipEntry:setText(self.packerIP or "")
    self:addChild(self.ipEntry)
    RemoteTerminalData.applyInputStyle(self.ipEntry)

    makeActionButton("Set Packer IP", "SET_IP", "config", 24, function() self:setPackerIP() end)

    btnY = btnY + BUTTON_HEIGHT + 30 + 10

    -- PIN button
    local pinLabel = "PIN: "
    local modData = self.terminalObject and self.terminalObject:getModData()
    if modData and modData.RemoteTerminalPIN then
        pinLabel = pinLabel .. "****"
    else
        pinLabel = pinLabel .. "(none)"
    end
    self.pinLabel = ISLabel:new(rightX, btnY, 20, pinLabel, 1, 1, 1, 1, UIFont.Small)
    self.pinLabel:initialise()
    self:addChild(self.pinLabel)

    makeActionButton("Set Terminal PIN", "SET_PIN", "config", 20, function() self:setTerminalPIN() end)

    btnY = btnY + BUTTON_HEIGHT + 30 + 10

    -- Link Container button (only works when player is near terminal)
    makeActionButton("Link Container", "LINK_CONT", "config", 0, function() self:linkContainer() end)

    -- Refresh connected containers count
    self.containerCountLabel = ISLabel:new(rightX, btnY + BUTTON_HEIGHT + 8, 20,
        "Use Link Container\nto add storage.", 1, 1, 1, 1, UIFont.Small)
    self.containerCountLabel:initialise()
    self:addChild(self.containerCountLabel)
end

function RemoteTerminalWindow:_updateTabStyles()
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
-- Connection & Data
-- ============================================================================

function RemoteTerminalWindow:connect()
    self.statusLabel:setName("Connecting...")

    RemoteTerminalData.requestNetworkState(self.packerIP, function(state, err)
        if state then
            self.networkState = state
            self.statusLabel:setName("Connected — " .. tostring(#state.items) .. " types, "
                .. tostring(state.terminals and #state.terminals or 0) .. " terminals")
            self.itemList:setEntries(state.items or {})

            -- Update container count
            local totalContainers = 0
            if state.terminals then
                for _, t in ipairs(state.terminals) do
                    totalContainers = totalContainers + (t.containerCount or 0)
                end
            end
            self.containerCountLabel:setName(totalContainers .. " linked containers")

            -- Enable auto-refresh
            self.autoRefreshTimer = RemoteTerminalData.AUTO_REFRESH_INTERVAL
        else
            self.statusLabel:setName("Error: " .. tostring(err or "Failed to connect"))
        end
    end)
end

function RemoteTerminalWindow:setPackerIP()
    local newIP = RemoteTerminal.normalizeIP(self.ipEntry:getText())
    if not newIP then
        self.statusLabel:setName("Invalid IP format")
        return
    end

    self.packerIP = newIP
    self.ipLabel:setName("Packer: " .. newIP)

    -- Save to terminal modData
    if self.terminalObject then
        self.terminalObject:getModData().RemotePackerIP = newIP
        self.terminalObject:transmitModData()
    end

    self:connect()
end

function RemoteTerminalWindow:setTerminalPIN()
    local modData = self.terminalObject and self.terminalObject:getModData()
    local currentPIN = modData and modData.RemoteTerminalPIN or ""

    local modal = ISTextBox:new(
        0, 0, 360, 150,
        "Set Terminal PIN (" .. (currentPIN ~= "" and "****" or "none") .. ")",
        "", nil,
        function(_target, button)
            if button.internal ~= "OK" then return end
            local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
            local pin = RemoteTerminal.normalizePIN(text, true)
            if pin then
                modData.RemoteTerminalPIN = (pin ~= "" and pin or nil)
                self.terminalObject:transmitModData()
                self.pinLabel:setName("PIN: " .. (pin ~= "" and "****" or "(none)"))
            end
        end,
        self.playerObj:getPlayerNum()
    )
    modal.maxChars = 4
    modal:initialise()
    modal:setOnlyNumbers(true)
    modal:addToUIManager()
end

function RemoteTerminalWindow:linkContainer()
    -- Find the nearest container object the player is looking at
    -- Simple implementation: link whatever container the player is standing near
    local playerSquare = self.playerObj:getCurrentSquare()
    if not playerSquare then
        self.statusLabel:setName("Cannot determine your position")
        return
    end

    local px, py, pz = playerSquare:getX(), playerSquare:getY(), playerSquare:getZ()
    local cell = getCell()
    if not cell then return end

    -- Search nearby squares for containers
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local ok, objects = pcall(function() return sq:getObjects() end)
                if ok and objects then
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if obj and obj:getContainer() and obj ~= self.terminalObject then
                            -- Link this container
                            RemoteTerminalData.requestLinkContainer(
                                self.terminalCode,
                                sq:getX(), sq:getY(), sq:getZ(),
                                function(result)
                                    if result.ok then
                                        self.statusLabel:setName("Container linked! Refresh to see items.")
                                    else
                                        self.statusLabel:setName("Link failed")
                                    end
                                end
                            )
                            return
                        end
                    end
                end
            end
        end
    end

    self.statusLabel:setName("No container found nearby")
end

-- ============================================================================
-- Item Transfers
-- ============================================================================

function RemoteTerminalWindow:takeItems(mode)
    if self.isTransferring then return end
    local selected = self.itemList:getSelectedEntries()
    if #selected == 0 then
        self.statusLabel:setName("Select items first")
        return
    end

    self.isTransferring = true
    local ip = self.packerIP

    for _, entry in ipairs(selected) do
        local count = entry.count
        if mode == "one" then count = 1
        elseif mode == "half" then count = math.max(1, math.floor(entry.count / 2))
        end

        RemoteTerminalData.requestTransfer(ip, entry.fullType, count, function(result)
            -- After all transfers, refresh
            self.isTransferring = false
            self:connect()
        end)
    end
end

function RemoteTerminalWindow:storeSelected()
    if self.isTransferring then return end

    -- Store items matching the selected types from player inventory
    local selected = self.itemList:getSelectedEntries()
    if #selected == 0 then return end

    self.isTransferring = true
    local ip = self.packerIP
    local stored = 0

    for _, entry in ipairs(selected) do
        local playerCount = RemoteTerminalData.countPlayerItems(self.playerObj, entry.fullType)
        if playerCount > 0 then
            RemoteTerminalData.requestStore(ip, entry.fullType, playerCount, function(result)
                stored = stored + (result.stored or 0)
            end)
        end
    end

    self.isTransferring = false
    self:connect()
end

function RemoteTerminalWindow:storeAll()
    -- Store ALL items from player inventory that exist in the network
    if self.isTransferring then return end
    if not self.networkState or not self.networkState.items then return end

    self.isTransferring = true
    local ip = self.packerIP

    for _, entry in ipairs(self.networkState.items) do
        local playerCount = RemoteTerminalData.countPlayerItems(self.playerObj, entry.fullType)
        if playerCount > 0 then
            RemoteTerminalData.requestStore(ip, entry.fullType, playerCount)
        end
    end

    self.isTransferring = false
    self:connect()
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function RemoteTerminalWindow:update()
    ISCollapsableWindow.update(self)

    -- Auto-refresh
    if self.autoRefreshTimer and self.autoRefreshTimer > 0 then
        self.autoRefreshTimer = self.autoRefreshTimer - 1
        if self.autoRefreshTimer <= 0 then
            self:connect()
        end
    end
end

function RemoteTerminalWindow:close()
    ISCollapsableWindow.close(self)
    self:setVisible(false)
    self:removeFromUIManager()
end

-- ============================================================================
-- Open from world object
-- ============================================================================

--- Open the terminal window by right-clicking a world-placed Remote Terminal.
--- @param terminalObject IsoObject The terminal world object.
--- @param playerObj IsoPlayer The player.
function RemoteTerminalTerminalUI.openTerminal(terminalObject, playerObj)
    if not terminalObject or not RemoteTerminal.isTerminalObject(terminalObject) then
        return
    end

    -- PIN check
    local modData = terminalObject:getModData()
    local terminalPIN = modData and modData.RemoteTerminalPIN

    if terminalPIN and terminalPIN ~= "" then
        -- Prompt for PIN
        local modal = ISTextBox:new(
            0, 0, 360, 150,
            "Enter Terminal PIN",
            "", nil,
            function(_target, button)
                if button.internal ~= "OK" then return end
                local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
                if RemoteTerminal.normalizePIN(text, false) == terminalPIN then
                    -- PIN correct, open window
                    local wx = (getCore():getScreenWidth() - WINDOW_WIDTH) / 2
                    local wy = (getCore():getScreenHeight() - WINDOW_HEIGHT) / 2
                    local window = RemoteTerminalWindow:new(wx, wy, terminalObject, playerObj)
                    window:addToUIManager()
                    window:setVisible(true)
                else
                    if playerObj and playerObj.Say then
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

    -- No PIN set — open directly
    local wx = (getCore():getScreenWidth() - WINDOW_WIDTH) / 2
    local wy = (getCore():getScreenHeight() - WINDOW_HEIGHT) / 2
    local window = RemoteTerminalWindow:new(wx, wy, terminalObject, playerObj)
    window:addToUIManager()
    window:setVisible(true)
end

-- ============================================================================
-- Context Menu Hook
-- ============================================================================

local function onFillWorldObjectContextMenu(player, context, worldObjects, test)
    if not worldObjects or #worldObjects == 0 then return end
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    -- Only show for single-object right-click
    local terminalObj = nil
    for _, obj in ipairs(worldObjects) do
        if RemoteTerminal.isTerminalObject(obj) then
            terminalObj = obj
            break
        end
    end
    if not terminalObj then return end

    context:addOption("Open Remote Terminal", terminalObj, function()
        RemoteTerminalTerminalUI.openTerminal(terminalObj, playerObj)
    end)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
