-- RemoteTerminalData.lua
-- Client-side shared data layer for the Remote Terminal mod.
-- Both the walk-up terminal UI and the handheld remote UI use this
-- module to query the server, aggregate items, and manage cold storage.
--
-- Uses sendClientCommand/sendServerCommand to communicate with the
-- server's RemoteTerminalNetwork module.

require "ISUI/ISScrollingListBox"
require "ISUI/ISMouseDrag"
require "ISUI/ISInventoryPane"
require "RemoteTerminal/RemoteTerminal"

RemoteTerminalData = RemoteTerminalData or {}

-- ============================================================================
-- Network State Cache
-- ============================================================================

RemoteTerminalData._stateCache = {}
RemoteTerminalData._pendingRequests = {}
RemoteTerminalData.AUTO_REFRESH_INTERVAL = 30 -- seconds

-- ============================================================================
-- Server Communication
-- ============================================================================

--- Request the network state for a given packer IP from the server.
--- The response comes asynchronously via OnServerCommand.
--- @param ip string The packer IP to query.
--- @param callback function Called with (state|nil, errorMsg|nil) when response arrives.
function RemoteTerminalData.requestNetworkState(ip, callback)
    ip = RemoteTerminal.normalizeIP(ip)
    if not ip then
        if callback then callback(nil, "Invalid IP address") end
        return
    end

    -- Check cache (valid for AUTO_REFRESH_INTERVAL seconds)
    local cached = RemoteTerminalData._stateCache[ip]
    if cached and (os.time() - cached.time) < RemoteTerminalData.AUTO_REFRESH_INTERVAL then
        if callback then callback(cached.state, nil) end
        return
    end

    -- Register callback
    if callback then
        RemoteTerminalData._pendingRequests[ip] = RemoteTerminalData._pendingRequests[ip] or {}
        table.insert(RemoteTerminalData._pendingRequests[ip], callback)
    end

    sendClientCommand(RemoteTerminal.COMMAND_MODULE, "requestNetworkState", { ip = ip })
end

--- Request transfer of items from network to player.
--- @param ip string Packer IP.
--- @param fullType string Item fullType to take.
--- @param count number How many (-1 = all).
--- @param callback function Called with (result) on response.
function RemoteTerminalData.requestTransfer(ip, fullType, count, callback)
    ip = RemoteTerminal.normalizeIP(ip)
    if not ip then
        if callback then callback({ transferred = 0 }) end
        return
    end

    if callback then
        RemoteTerminalData._pendingRequests["transfer_" .. ip .. "_" .. fullType] = { callback }
    end

    sendClientCommand(RemoteTerminal.COMMAND_MODULE, "requestTransfer", {
        ip = ip,
        fullType = fullType,
        count = count,
    })
end

--- Request store of items from player inventory to network.
--- @param ip string Packer IP.
--- @param fullType string Item fullType to store.
--- @param count number How many.
--- @param callback function Called with (result) on response.
function RemoteTerminalData.requestStore(ip, fullType, count, callback)
    ip = RemoteTerminal.normalizeIP(ip)
    if not ip then
        if callback then callback({ stored = 0 }) end
        return
    end

    if callback then
        RemoteTerminalData._pendingRequests["store_" .. ip .. "_" .. fullType] = { callback }
    end

    sendClientCommand(RemoteTerminal.COMMAND_MODULE, "requestStore", {
        ip = ip,
        fullType = fullType,
        count = count or 1,
    })
end

--- Request linking a container to a terminal.
--- @param terminalCode string Terminal code.
--- @param x number Container X.
--- @param y number Container Y.
--- @param z number Container Z.
--- @param callback function Called with (result) on response.
function RemoteTerminalData.requestLinkContainer(terminalCode, x, y, z, callback)
    if callback then
        RemoteTerminalData._pendingRequests["link_" .. terminalCode] = { callback }
    end

    sendClientCommand(RemoteTerminal.COMMAND_MODULE, "requestLinkContainer", {
        terminalCode = terminalCode,
        x = x,
        y = y,
        z = z,
    })
end

-- ============================================================================
-- Server Response Handler
-- ============================================================================

local function handleServerResponse(moduleName, commandName, args)
    if moduleName ~= RemoteTerminal.COMMAND_MODULE then return end

    if commandName == "networkState" then
        local state = args
        local ip = state and state.ip
        if ip then
            RemoteTerminalData._stateCache[ip] = {
                state = state,
                time = os.time(),
            }
            local callbacks = RemoteTerminalData._pendingRequests[ip]
            if callbacks then
                for _, cb in ipairs(callbacks) do
                    cb(state, nil)
                end
                RemoteTerminalData._pendingRequests[ip] = nil
            end
        end

    elseif commandName == "networkError" then
        local msg = args and args.message or "Unknown error"
        -- Notify any pending requests that might be waiting
        for _, callbacks in pairs(RemoteTerminalData._pendingRequests) do
            for _, cb in ipairs(callbacks) do
                cb(nil, msg)
            end
        end
        RemoteTerminalData._pendingRequests = {}

    elseif commandName == "transferResult" then
        local fullType = args and args.fullType
        local transferred = args and args.transferred or 0
        -- Find pending transfer callback
        for key, callbacks in pairs(RemoteTerminalData._pendingRequests) do
            if string.find(key, "^transfer_") then
                for _, cb in ipairs(callbacks) do
                    cb({ fullType = fullType, transferred = transferred })
                end
                RemoteTerminalData._pendingRequests[key] = nil
            end
        end
        -- Invalidate cache so next request gets fresh data
        for ip, _ in pairs(RemoteTerminalData._stateCache) do
            RemoteTerminalData._stateCache[ip] = nil
        end

    elseif commandName == "storeResult" then
        local fullType = args and args.fullType
        local stored = args and args.stored or 0
        for key, callbacks in pairs(RemoteTerminalData._pendingRequests) do
            if string.find(key, "^store_") then
                for _, cb in ipairs(callbacks) do
                    cb({ fullType = fullType, stored = stored })
                end
                RemoteTerminalData._pendingRequests[key] = nil
            end
        end
        -- Invalidate cache
        for ip, _ in pairs(RemoteTerminalData._stateCache) do
            RemoteTerminalData._stateCache[ip] = nil
        end

    elseif commandName == "linkResult" then
        local terminalCode = args and args.terminalCode
        local ok = args and args.ok
        local callbacks = RemoteTerminalData._pendingRequests["link_" .. terminalCode]
        if callbacks then
            for _, cb in ipairs(callbacks) do
                cb({ terminalCode = terminalCode, ok = ok })
            end
            RemoteTerminalData._pendingRequests["link_" .. terminalCode] = nil
        end
    end
end

Events.OnServerCommand.Add(handleServerResponse)

-- ============================================================================
-- Item Aggregation Helpers
-- ============================================================================

--- Get the display category name for an item (with localization fallback).
--- @param item InventoryItem
--- @return string Category display name.
function RemoteTerminalData.getItemCategoryName(item)
    local category = item and item:getDisplayCategory()
    if not category or category == "" then
        category = item and item:getCategory()
    end
    if not category or category == "" then
        return "Other"
    end
    local key = "IGUI_ItemCat_" .. category
    local text = getText(key)
    if text and text ~= key then
        return text
    end
    return category
end

--- Detect the cold storage type of a container.
--- @param container ItemContainer
--- @return string|nil "freezer", "fridge", or nil
function RemoteTerminalData.getContainerColdType(container)
    if not container then return nil end
    local ctype = container:getType()
    if not ctype then return nil end
    local lower = string.lower(ctype)
    if string.find(lower, "freezer") then return "freezer" end
    if string.find(lower, "fridge") or string.find(lower, "refrigerator") then return "fridge" end
    return nil
end

--- Check if a food item should be prioritized for freezing.
--- @param item Food
--- @return boolean
function RemoteTerminalData.shouldFreezeFood(item)
    if not item or not instanceof(item, "Food") then return false end
    local ok, frozen = pcall(function() return item:isFrozen() end)
    if ok and frozen then return true end
    local okMax, offAgeMax = pcall(function() return item:getOffAgeMax() end)
    if okMax and offAgeMax and offAgeMax > 0 and offAgeMax <= 7 then
        return true
    end
    return false
end

--- Check if a terminal accepts a given item based on its routing rules.
--- @param terminal table Terminal info from network state.
--- @param itemInfo table Item info (needs fullType, category).
--- @return boolean
function RemoteTerminalData.terminalAcceptsItem(terminal, itemInfo)
    if not terminal or not itemInfo then return true end

    local hasCategories = terminal.categories and #terminal.categories > 0
    local hasItems = terminal.items and #terminal.items > 0

    -- If no routing rules, accept everything
    if not hasCategories and not hasItems then return true end

    -- Check category filter
    if hasCategories then
        local itemCat = itemInfo.category or ""
        for _, cat in ipairs(terminal.categories) do
            if string.lower(cat) == string.lower(itemCat) then
                return true
            end
        end
    end

    -- Check item filter
    if hasItems then
        for _, it in ipairs(terminal.items) do
            if it == itemInfo.fullType then
                return true
            end
        end
    end

    -- If either filter is defined but item didn't match, reject
    return not hasCategories and not hasItems
end

-- ============================================================================
-- Player Inventory Helpers
-- ============================================================================

--- Count how many of a given fullType the player has in their inventory.
--- @param playerObj IsoPlayer
--- @param fullType string
--- @return number
function RemoteTerminalData.countPlayerItems(playerObj, fullType)
    if not playerObj or not fullType then return 0 end
    local inv = playerObj:getInventory()
    if not inv then return 0 end

    local count = 0
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item:getFullType() == fullType then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- UI Styling (shared by all RemoteTerminal windows)
-- ============================================================================

function RemoteTerminalData.applyInputStyle(entry)
    if not entry then return end
    local c = RemoteTerminal.Colors
    entry.backgroundColor = c.input
    entry.borderColor = c.inputBorder
end

function RemoteTerminalData.applyListStyle(list)
    if not list then return end
    local c = RemoteTerminal.Colors
    list.backgroundColor = c.list
    list.borderColor = c.border
    list.drawBorder = true
end

function RemoteTerminalData.applyButtonStyle(button, kind, active)
    if not button then return end
    local c = RemoteTerminal.Colors
    local base   = { r = 0.018, g = 0.052, b = 0.052, a = 0.90 }
    local over   = { r = 0.045, g = 0.145, b = 0.130, a = 1.00 }
    local border = { r = 0.18, g = 0.58, b = 0.54, a = 1.00 }
    local text   = c.text

    if kind == "take" then
        base   = { r = 0.030, g = 0.080, b = 0.120, a = 0.92 }
        over   = { r = 0.055, g = 0.150, b = 0.210, a = 1.00 }
        border = { r = 0.28, g = 0.62, b = 0.86, a = 1.00 }
    elseif kind == "store" then
        base   = { r = 0.025, g = 0.110, b = 0.080, a = 0.92 }
        over   = { r = 0.040, g = 0.180, b = 0.120, a = 1.00 }
        border = { r = 0.22, g = 0.78, b = 0.48, a = 1.00 }
    elseif kind == "config" then
        base   = { r = 0.095, g = 0.075, b = 0.030, a = 0.92 }
        over   = { r = 0.160, g = 0.120, b = 0.045, a = 1.00 }
        border = { r = 0.82, g = 0.62, b = 0.26, a = 1.00 }
    elseif kind == "danger" then
        base   = { r = 0.150, g = 0.035, b = 0.030, a = 0.92 }
        over   = { r = 0.240, g = 0.060, b = 0.050, a = 1.00 }
        border = { r = c.danger.r, g = c.danger.g, b = c.danger.b, a = 1.00 }
    elseif active then
        base   = { r = 0.025, g = 0.180, b = 0.145, a = 0.96 }
        over   = { r = 0.040, g = 0.240, b = 0.180, a = 1.00 }
        border = { r = 0.24, g = 0.86, b = 0.62, a = 1.00 }
    end

    button.backgroundColor = base
    button.backgroundColorMouseOver = over
    button.borderColor = border
    button.borderColorEnabled = border
    button.textColor = { r = text.r, g = text.g, b = text.b, a = text.a }
end

--- Draw text with ellipsis truncation if it exceeds maxWidth.
function RemoteTerminalData.drawClippedText(ui, text, x, y, maxWidth, r, g, b, a, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if maxWidth and getTextManager():MeasureStringX(font, text) > maxWidth then
        while getTextManager():MeasureStringX(font, text .. "...") > maxWidth and #text > 0 do
            text = string.sub(text, 1, -2)
        end
        text = text .. "..."
    end
    ui:drawText(text, x, y, r, g, b, a, font)
end
