-- RemoteTerminalNetwork.lua
-- Server-side global data table for the Remote Terminal mod.
-- This replaces chunk-radius scanning with a server-authoritative
-- global table that clients query via sendClientCommand/sendServerCommand.
--
-- The Network table stores all packer/terminal metadata and cached
-- inventory snapshots. It is persisted across save/load via ModData.

require "RemoteTerminal/RemoteTerminal"

RemoteTerminalNetwork = RemoteTerminalNetwork or {}

-- ============================================================================
-- Global Network Table
-- ============================================================================

--- Structure:
---   Network.packers[ip] = {
---     x, y, z,          -- world coordinates
---     pin,               -- optional 4-digit PIN (or nil)
---   }
---   Network.terminals[code] = {
---     packerIP,          -- linked packer IP
---     x, y, z,           -- world coordinates
---     pin,               -- optional 4-digit PIN (or nil)
---     radius,            -- scan radius (1-30)
---     linkedContainers = { {x,y,z}, ... },
---     categories = { "Food", "Weapons", ... },   -- routing: allowed categories
---     items = { "Base.Banana", "Base.Pistol", ... }, -- routing: allowed fullTypes
---   }
---   Network.version       -- incremented on every change (for cache invalidation)

RemoteTerminal.Network = RemoteTerminal.Network or {
    packers = {},
    terminals = {},
    version = 0,
}

-- ============================================================================
-- ModData Persistence
-- ============================================================================

local MODDATA_KEY = "RemoteTerminal"

--- Save the Network table to ModData.
local function persistNetwork()
    local modData = ModData.getOrCreate(MODDATA_KEY)
    modData.network = RemoteTerminal.Network
end

--- Load the Network table from ModData (called on server start).
local function loadNetwork()
    local modData = ModData.getOrCreate(MODDATA_KEY)
    if modData.network then
        RemoteTerminal.Network = modData.network
    end
end

-- ============================================================================
-- Registration / Unregistration
-- ============================================================================

--- Register a Packer object in the global network table.
--- Called when a Packer is built or when rebuilding from world objects.
--- @param object IsoObject The packer world object.
function RemoteTerminalNetwork.registerPacker(object)
    if not object then return end

    local ip = object:getModData().RemotePackerIP
    if not ip or ip == "" then
        ip = RemoteTerminal.generatePackerIP()
        object:getModData().RemotePackerIP = ip
        object:transmitModData()
    end

    local x = object:getX()
    local y = object:getY()
    local z = object:getZ()

    local old = RemoteTerminal.Network.packers[ip]
    RemoteTerminal.Network.packers[ip] = {
        x = x,
        y = y,
        z = z,
        pin = object:getModData().RemotePackerPIN,
    }

    -- Preserve any terminals already linked to this IP
    if old and old.terminals then
        -- terminals are keyed by code in the main terminals table, no need to migrate
    end

    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

--- Register a Terminal object in the global network table.
--- @param object IsoObject The terminal world object.
function RemoteTerminalNetwork.registerTerminal(object)
    if not object then return end

    local modData = object:getModData()

    local code = modData.RemoteTerminalCode
    if not code or code == "" then
        code = RemoteTerminal.generateTerminalCode()
        modData.RemoteTerminalCode = code
        object:transmitModData()
    end

    local packerIP = modData.RemotePackerIP
    local radius = RemoteTerminal.clampRadius(modData.RemoteTerminalRadius)

    -- Parse linked container coordinates from modData
    local linkedContainers = {}
    local linkedStr = modData.RemoteTerminalLinkedObjects
    if type(linkedStr) == "string" and linkedStr ~= "" then
        for coord in linkedStr:gmatch("[^;]+") do
            local cx, cy, cz = coord:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
            if cx then
                table.insert(linkedContainers, {
                    x = tonumber(cx),
                    y = tonumber(cy),
                    z = tonumber(cz),
                })
            end
        end
    end

    -- Parse routing rules
    local categories = {}
    local catStr = modData.RemoteTerminalCategories
    if type(catStr) == "string" and catStr ~= "" then
        for cat in catStr:gmatch("[^;]+") do
            cat = cat:match("^%s*(.-)%s*$") -- trim
            if cat ~= "" then
                table.insert(categories, cat)
            end
        end
    end

    local items = {}
    local itemStr = modData.RemoteTerminalItems
    if type(itemStr) == "string" and itemStr ~= "" then
        for it in itemStr:gmatch("[^;]+") do
            it = it:match("^%s*(.-)%s*$") -- trim
            if it ~= "" then
                table.insert(items, it)
            end
        end
    end

    RemoteTerminal.Network.terminals[code] = {
        packerIP = packerIP,
        x = object:getX(),
        y = object:getY(),
        z = object:getZ(),
        pin = modData.RemoteTerminalPIN,
        radius = radius,
        linkedContainers = linkedContainers,
        categories = categories,
        items = items,
    }

    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

--- Unregister a Packer from the global table.
--- @param ip string The packer's IP address.
function RemoteTerminalNetwork.unregisterPacker(ip)
    if not ip or not RemoteTerminal.Network.packers[ip] then return end
    RemoteTerminal.Network.packers[ip] = nil
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

--- Unregister a Terminal from the global table.
--- @param code string The terminal's code.
function RemoteTerminalNetwork.unregisterTerminal(code)
    if not code or not RemoteTerminal.Network.terminals[code] then return end
    RemoteTerminal.Network.terminals[code] = nil
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

-- ============================================================================
-- Container Linking
-- ============================================================================

--- Link a container at world coordinates to a terminal.
--- @param terminalCode string The terminal's unique code.
--- @param cx number Container X coordinate.
--- @param cy number Container Y coordinate.
--- @param cz number Container Z coordinate.
function RemoteTerminalNetwork.linkContainerToTerminal(terminalCode, cx, cy, cz)
    local terminal = RemoteTerminal.Network.terminals[terminalCode]
    if not terminal then return false end

    -- Check for duplicate
    for _, existing in ipairs(terminal.linkedContainers) do
        if existing.x == cx and existing.y == cy and existing.z == cz then
            return true -- already linked
        end
    end

    table.insert(terminal.linkedContainers, { x = cx, y = cy, z = cz })

    -- Also update the world object's modData for persistence
    local cell = getCell()
    if cell then
        local sq = cell:getGridSquare(terminal.x, terminal.y, terminal.z)
        if sq then
            for _, obj in ipairs({ sq:getObjects(), sq:getSpecialObjects() }) do
                -- Find the terminal object
                local list = obj
                if type(obj) == "table" then
                    list = nil
                    local ok, objects = pcall(function() return sq:getObjects() end)
                    if ok and objects then
                        for i = 0, objects:size() - 1 do
                            local o = objects:get(i)
                            if o and o:getModData().RemoteTerminalCode == terminalCode then
                                local existing = o:getModData().RemoteTerminalLinkedObjects or ""
                                local newCoord = cx .. "," .. cy .. "," .. cz
                                o:getModData().RemoteTerminalLinkedObjects = existing
                                    .. (existing ~= "" and ";" or "")
                                    .. newCoord
                                o:transmitModData()
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
    return true
end

--- Unlink a container from a terminal.
function RemoteTerminalNetwork.unlinkContainerFromTerminal(terminalCode, cx, cy, cz)
    local terminal = RemoteTerminal.Network.terminals[terminalCode]
    if not terminal then return false end

    for i, existing in ipairs(terminal.linkedContainers) do
        if existing.x == cx and existing.y == cy and existing.z == cz then
            table.remove(terminal.linkedContainers, i)
            RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
            persistNetwork()
            return true
        end
    end
    return false
end

-- ============================================================================
-- Inventory Snapshot
-- ============================================================================

--- Refresh the inventory snapshot for a single container at world coords.
--- Called when a container's contents change or on demand.
--- @return table A snapshot: { fullType, displayName, category, count, weight, ... }
local function refreshContainerSnapshot(cx, cy, cz)
    local cell = getCell()
    if not cell then return nil end

    local sq = cell:getGridSquare(cx, cy, cz)
    if not sq then return nil end

    local items = {}
    local seen = {}

    -- Scan all objects on this square for containers
    local objects = {}
    local ok, objList = pcall(function() return sq:getObjects() end)
    if ok and objList then
        for i = 0, objList:size() - 1 do
            table.insert(objects, objList:get(i))
        end
    end

    for _, obj in ipairs(objects) do
        local container = obj:getContainer()
        if container then
            local containerItems = container:getItems()
            for i = 0, containerItems:size() - 1 do
                local item = containerItems:get(i)
                if item and not seen[item] then
                    seen[item] = true
                    local fullType = item:getFullType()
                    local existing = items[fullType]
                    if not existing then
                        items[fullType] = {
                            fullType = fullType,
                            displayName = item:getDisplayName() or fullType,
                            category = item:getDisplayCategory() or item:getCategory() or "Other",
                            count = 0,
                            totalWeight = 0,
                            hasFridge = false,
                            hasFreezer = false,
                        }
                    end
                    existing = items[fullType]
                    existing.count = existing.count + 1
                    existing.totalWeight = existing.totalWeight + (item:getActualWeight() or 0)

                    -- Detect cold storage
                    local containerType = container:getType()
                    if containerType then
                        local lower = string.lower(containerType)
                        if string.find(lower, "freezer") then
                            existing.hasFreezer = true
                        elseif string.find(lower, "fridge") or string.find(lower, "refrigerator") then
                            existing.hasFridge = true
                        end
                    end
                end
            end
        end
    end

    -- Convert to array
    local result = {}
    for _, entry in pairs(items) do
        table.insert(result, entry)
    end
    table.sort(result, function(a, b)
        return (a.displayName or ""):lower() < (b.displayName or ""):lower()
    end)

    return result
end

--- Get the full network state for a given Packer IP.
--- Returns all terminals linked to this packer and aggregated inventory.
--- This is the primary data payload sent to clients.
--- @param ip string The packer IP to query.
--- @return table|nil Network state or nil if IP not found.
function RemoteTerminalNetwork.getNetworkState(ip)
    if not ip or not RemoteTerminal.Network.packers[ip] then
        return nil
    end

    local packer = RemoteTerminal.Network.packers[ip]
    local state = {
        ip = ip,
        packer = {
            x = packer.x,
            y = packer.y,
            z = packer.z,
            pin = packer.pin,
        },
        terminals = {},
        items = {},       -- aggregated items from all terminals
        version = RemoteTerminal.Network.version,
    }

    local aggregatedItems = {}

    for code, terminal in pairs(RemoteTerminal.Network.terminals) do
        if terminal.packerIP == ip then
            local termInfo = {
                code = code,
                x = terminal.x,
                y = terminal.y,
                z = terminal.z,
                pin = terminal.pin,
                radius = terminal.radius,
                linkedContainers = terminal.linkedContainers,
                categories = terminal.categories,
                items = terminal.items,
                containerCount = #terminal.linkedContainers,
            }
            table.insert(state.terminals, termInfo)

            -- Aggregate items from linked containers
            for _, containerPos in ipairs(terminal.linkedContainers) do
                local snapshot = refreshContainerSnapshot(containerPos.x, containerPos.y, containerPos.z)
                if snapshot then
                    for _, entry in ipairs(snapshot) do
                        local existing = aggregatedItems[entry.fullType]
                        if not existing then
                            aggregatedItems[entry.fullType] = {
                                fullType = entry.fullType,
                                displayName = entry.displayName,
                                category = entry.category,
                                count = 0,
                                totalWeight = 0,
                                hasFridge = false,
                                hasFreezer = false,
                            }
                        end
                        existing = aggregatedItems[entry.fullType]
                        existing.count = existing.count + entry.count
                        existing.totalWeight = existing.totalWeight + entry.totalWeight
                        existing.hasFridge = existing.hasFridge or entry.hasFridge
                        existing.hasFreezer = existing.hasFreezer or entry.hasFreezer
                    end
                end
            end
        end
    end

    -- Convert aggregated items to sorted array
    for _, entry in pairs(aggregatedItems) do
        table.insert(state.items, entry)
    end
    table.sort(state.items, function(a, b)
        return (a.displayName or ""):lower() < (b.displayName or ""):lower()
    end)

    return state
end

-- ============================================================================
-- Item Transfer (Server-Side)
-- ============================================================================

--- Find items of a given fullType in the network and transfer them to a player.
--- Works server-side so it functions even when chunks aren't client-loaded.
--- @param playerObj IsoPlayer The player to receive items.
--- @param ip string The packer IP.
--- @param fullType string The item fullType to transfer.
--- @param count number How many to transfer (or -1 for all available).
--- @return number How many items were actually transferred.
function RemoteTerminalNetwork.transferItemsToPlayer(playerObj, ip, fullType, count)
    if not playerObj or not ip or not fullType then return 0 end

    local state = RemoteTerminalNetwork.getNetworkState(ip)
    if not state then return 0 end

    local transferred = 0
    local maxCount = (count and count > 0) and count or 999999

    -- Find matching items in each terminal's linked containers
    for _, termInfo in ipairs(state.terminals) do
        if transferred >= maxCount then break end

        local cell = getCell()
        if not cell then break end

        for _, containerPos in ipairs(termInfo.linkedContainers) do
            if transferred >= maxCount then break end

            local sq = cell:getGridSquare(containerPos.x, containerPos.y, containerPos.z)
            if sq then
                local objects = {}
                local ok, objList = pcall(function() return sq:getObjects() end)
                if ok and objList then
                    for i = 0, objList:size() - 1 do
                        table.insert(objects, objList:get(i))
                    end
                end

                for _, obj in ipairs(objects) do
                    if transferred >= maxCount then break end

                    local container = obj:getContainer()
                    if container then
                        local items = container:getItems()
                        for i = 0, items:size() - 1 do
                            if transferred >= maxCount then break end

                            local item = items:get(i)
                            if item and item:getFullType() == fullType then
                                -- Check if player can carry it
                                local playerInv = playerObj:getInventory()
                                if playerInv and playerInv:hasRoomFor(playerObj, item) then
                                    playerInv:AddItem(item)
                                    transferred = transferred + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    return transferred
end

--- Store items from a player's inventory into the network.
--- Uses cold storage routing: perishable → freezer/fridge, rest → any linked container.
--- @param playerObj IsoPlayer The player.
--- @param ip string The packer IP.
--- @param items table Array of InventoryItem to store.
--- @return number How many items were stored.
function RemoteTerminalNetwork.storeItemsFromPlayer(playerObj, ip, items)
    if not playerObj or not ip or not items then return 0 end

    local state = RemoteTerminalNetwork.getNetworkState(ip)
    if not state then return 0 end

    local stored = 0
    local cell = getCell()
    if not cell then return 0 end

    -- Collect all available destination containers
    local allContainers = {}
    local coldContainers = {}  -- freezer/fridge

    for _, termInfo in ipairs(state.terminals) do
        for _, containerPos in ipairs(termInfo.linkedContainers) do
            local sq = cell:getGridSquare(containerPos.x, containerPos.y, containerPos.z)
            if sq then
                local objects = {}
                local ok, objList = pcall(function() return sq:getObjects() end)
                if ok and objList then
                    for i = 0, objList:size() - 1 do
                        table.insert(objects, objList:get(i))
                    end
                end

                for _, obj in ipairs(objects) do
                    local container = obj:getContainer()
                    if container then
                        table.insert(allContainers, container)
                        local ctype = string.lower(container:getType() or "")
                        if string.find(ctype, "freezer") or string.find(ctype, "fridge") or string.find(ctype, "refrigerator") then
                            table.insert(coldContainers, container)
                        end
                    end
                end
            end
        end
    end

    -- Route each item
    for _, item in ipairs(items) do
        if item then
            local isPerishable = false
            if instanceof(item, "Food") then
                local okMax, offAgeMax = pcall(function() return item:getOffAgeMax() end)
                if okMax and offAgeMax and offAgeMax > 0 then
                    isPerishable = true
                end
            end

            -- Prefer cold storage for perishable food
            local targets = isPerishable and coldContainers or allContainers
            if #targets == 0 then
                targets = allContainers
            end

            for _, container in ipairs(targets) do
                if container:isItemAllowed(item) and container:hasRoomFor(playerObj, item) then
                    local playerInv = playerObj:getInventory()
                    if playerInv then
                        playerInv:Remove(item)
                        container:AddItem(item)
                        stored = stored + 1
                        break
                    end
                end
            end
        end
    end

    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    return stored
end

-- ============================================================================
-- World Rebuild (on server start)
-- ============================================================================

--- Scan all loaded world objects and rebuild the Network table.
--- Called on server start after ModData is loaded.
function RemoteTerminalNetwork.rebuildNetworkFromWorld()
    local cell = getCell()
    if not cell then return end

    -- First, restore from ModData if available
    loadNetwork()

    -- Then refresh any packers/terminals that exist in loaded chunks
    -- (This also picks up any objects built before this mod was installed)
    local chunkCount = cell:getChunkCount()
    for c = 0, chunkCount - 1 do
        local chunk = cell:getChunk(c)
        if chunk then
            for x = 0, 9 do
                for y = 0, 9 do
                    for z = 0, 7 do
                        local sq = cell:getGridSquare(
                            chunk:getX() * 10 + x,
                            chunk:getY() * 10 + y,
                            z
                        )
                        if sq then
                            local ok, objects = pcall(function() return sq:getObjects() end)
                            if ok and objects then
                                for i = 0, objects:size() - 1 do
                                    local obj = objects:get(i)
                                    if obj then
                                        local md = obj:getModData()
                                        if md.RemotePacker then
                                            RemoteTerminalNetwork.registerPacker(obj)
                                        elseif md.RemoteTerminalObj then
                                            RemoteTerminalNetwork.registerTerminal(obj)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- Server Command Handlers
-- ============================================================================

local function handleServerCommand(moduleName, commandName, playerObj, args)
    if moduleName ~= RemoteTerminal.COMMAND_MODULE then return end

    if commandName == "requestNetworkState" then
        local ip = args and args.ip
        local state = RemoteTerminalNetwork.getNetworkState(ip)
        if state then
            sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "networkState", state)
        else
            sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "networkError", {
                message = "No packer found with IP: " .. tostring(ip),
            })
        end

    elseif commandName == "requestTransfer" then
        local ip = args and args.ip
        local fullType = args and args.fullType
        local count = args and args.count
        local transferred = RemoteTerminalNetwork.transferItemsToPlayer(playerObj, ip, fullType, count)
        sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "transferResult", {
            fullType = fullType,
            transferred = transferred,
        })

    elseif commandName == "requestStore" then
        -- Items to store come from player inventory; server-side processing
        -- The client sends fullType + count, server finds matching items in player inventory
        local ip = args and args.ip
        local fullType = args and args.fullType
        local count = args and args.count or 1

        -- Collect matching items from player inventory
        local playerInv = playerObj:getInventory()
        local toStore = {}
        if playerInv then
            local items = playerInv:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item and item:getFullType() == fullType and #toStore < count then
                    table.insert(toStore, item)
                end
            end
        end

        local stored = RemoteTerminalNetwork.storeItemsFromPlayer(playerObj, ip, toStore)
        sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "storeResult", {
            fullType = fullType,
            stored = stored,
        })

    elseif commandName == "requestLinkContainer" then
        local terminalCode = args and args.terminalCode
        local cx = args and args.x
        local cy = args and args.y
        local cz = args and args.z
        local ok = RemoteTerminalNetwork.linkContainerToTerminal(terminalCode, cx, cy, cz)
        sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "linkResult", {
            terminalCode = terminalCode,
            ok = ok,
        })
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

--- Initialize the network module on server start.
function RemoteTerminalNetwork.init()
    RemoteTerminal.initSandbox()
    RemoteTerminalNetwork.rebuildNetworkFromWorld()

    -- Listen for client commands
    Events.OnClientCommand.Add(handleServerCommand)

    -- Register new objects as they're placed
    -- (Building objects call registerPacker/registerTerminal in their create())
end

-- Auto-init on server load
if isServer and isServer() then
    Events.OnInitGlobalModData.Add(function()
        RemoteTerminalNetwork.init()
    end)
end
