-- RemoteTerminalNetwork.lua
-- Server-side global data table for the Remote Terminal mod.
--
-- IMPORTANT: All server-only code is guarded with isServer() checks.
-- No chunk scanning. Registration is event-driven. On server start,
-- the table is restored from ModData. Inventory snapshots only
-- access already-loaded chunks.
--
-- Namespaced under RemoteTerminal.Network to avoid any conflicts
-- with base game or other mods.

require "RemoteTerminal/RemoteTerminal"

RemoteTerminalNetwork = RemoteTerminalNetwork or {}

-- ============================================================================
-- Safe server guard (used throughout)
-- ============================================================================
local function isServerSide()
    return isServer and isServer()
end

-- ============================================================================
-- Global Network Table
-- ============================================================================
RemoteTerminal.Network = RemoteTerminal.Network or {
    packers = {},
    terminals = {},
    version = 0,
}

-- ============================================================================
-- ModData Persistence (server only, pcall-wrapped)
-- ============================================================================
local MODDATA_KEY = "RemoteTerminal"

local function persistNetwork()
    if not isServerSide() then return end
    local ok, modData = pcall(ModData.getOrCreate, MODDATA_KEY)
    if ok and modData then
        modData.network = RemoteTerminal.Network
    end
end

local function loadNetwork()
    if not isServerSide() then return end
    local ok, modData = pcall(ModData.getOrCreate, MODDATA_KEY)
    if ok and modData and modData.network then
        RemoteTerminal.Network = modData.network
    end
end

-- ============================================================================
-- Registration (server only)
-- ============================================================================

function RemoteTerminalNetwork.registerPacker(object)
    if not isServerSide() or not object then return end

    local ip = object:getModData().RemotePackerIP
    if not ip or ip == "" then
        ip = RemoteTerminal.generatePackerIP()
        object:getModData().RemotePackerIP = ip
        pcall(object.transmitModData, object)
    end

    RemoteTerminal.Network.packers[ip] = {
        x = object:getX(), y = object:getY(), z = object:getZ(),
        pin = object:getModData().RemotePackerPIN,
    }
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

function RemoteTerminalNetwork.registerTerminal(object)
    if not isServerSide() or not object then return end

    local md = object:getModData()
    local code = md.RemoteTerminalCode
    if not code or code == "" then
        code = RemoteTerminal.generateTerminalCode()
        md.RemoteTerminalCode = code
        pcall(object.transmitModData, object)
    end

    local linkedContainers = {}
    local linkedStr = md.RemoteTerminalLinkedObjects
    if type(linkedStr) == "string" and linkedStr ~= "" then
        for coord in linkedStr:gmatch("[^;]+") do
            local cx, cy, cz = coord:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
            if cx then
                table.insert(linkedContainers, { x = tonumber(cx), y = tonumber(cy), z = tonumber(cz) })
            end
        end
    end

    local categories, items = {}, {}
    local catStr = md.RemoteTerminalCategories
    if type(catStr) == "string" and catStr ~= "" then
        for cat in catStr:gmatch("[^;]+") do
            cat = cat:match("^%s*(.-)%s*$")
            if cat ~= "" then table.insert(categories, cat) end
        end
    end
    local itemStr = md.RemoteTerminalItems
    if type(itemStr) == "string" and itemStr ~= "" then
        for it in itemStr:gmatch("[^;]+") do
            it = it:match("^%s*(.-)%s*$")
            if it ~= "" then table.insert(items, it) end
        end
    end

    RemoteTerminal.Network.terminals[code] = {
        packerIP = md.RemotePackerIP,
        x = object:getX(), y = object:getY(), z = object:getZ(),
        pin = md.RemoteTerminalPIN,
        radius = RemoteTerminal.clampRadius(md.RemoteTerminalRadius),
        linkedContainers = linkedContainers,
        categories = categories,
        items = items,
    }
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

function RemoteTerminalNetwork.unregisterPacker(ip)
    if not isServerSide() or not ip then return end
    RemoteTerminal.Network.packers[ip] = nil
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

function RemoteTerminalNetwork.unregisterTerminal(code)
    if not isServerSide() or not code then return end
    RemoteTerminal.Network.terminals[code] = nil
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
end

-- ============================================================================
-- Container Linking (server only)
-- ============================================================================

function RemoteTerminalNetwork.linkContainerToTerminal(terminalCode, cx, cy, cz)
    if not isServerSide() then return false end
    local t = RemoteTerminal.Network.terminals[terminalCode]
    if not t then return false end
    for _, e in ipairs(t.linkedContainers) do
        if e.x == cx and e.y == cy and e.z == cz then return true end
    end
    table.insert(t.linkedContainers, { x = cx, y = cy, z = cz })
    RemoteTerminal.Network.version = (RemoteTerminal.Network.version or 0) + 1
    persistNetwork()
    return true
end

-- ============================================================================
-- Inventory Snapshot (server only — only loaded chunks)
-- ============================================================================

local function refreshContainerSnapshot(cx, cy, cz)
    if not isServerSide() then return nil end
    local cell = getCell()
    if not cell then return nil end
    local sq = cell:getGridSquare(cx, cy, cz)
    if not sq then return nil end

    local aggregated, seen = {}, {}
    local ok, objList = pcall(function() return sq:getObjects() end)
    if not ok or not objList then return nil end

    for i = 0, objList:size() - 1 do
        local obj = objList:get(i)
        local container = obj and obj:getContainer()
        if container then
            local items = container:getItems()
            for j = 0, items:size() - 1 do
                local item = items:get(j)
                if item and not seen[item] then
                    seen[item] = true
                    local ft = item:getFullType()
                    if not aggregated[ft] then
                        aggregated[ft] = {
                            fullType = ft,
                            displayName = item:getDisplayName() or ft,
                            category = item:getDisplayCategory() or item:getCategory() or "Other",
                            count = 0, totalWeight = 0,
                            hasFridge = false, hasFreezer = false,
                        }
                    end
                    local e = aggregated[ft]
                    e.count = e.count + 1
                    e.totalWeight = e.totalWeight + (item:getActualWeight() or 0)
                    local ct = string.lower(container:getType() or "")
                    if ct:find("freezer") then e.hasFreezer = true
                    elseif ct:find("fridge") or ct:find("refrigerator") then e.hasFridge = true end
                end
            end
        end
    end

    local result = {}
    for _, v in pairs(aggregated) do table.insert(result, v) end
    table.sort(result, function(a, b) return (a.displayName or ""):lower() < (b.displayName or ""):lower() end)
    return result
end

-- ============================================================================
-- Network State Query (server only)
-- ============================================================================

function RemoteTerminalNetwork.getNetworkState(ip)
    if not isServerSide() then return nil end
    if not ip or not RemoteTerminal.Network.packers[ip] then return nil end

    local packer = RemoteTerminal.Network.packers[ip]
    local state = {
        ip = ip,
        packer = { x = packer.x, y = packer.y, z = packer.z, pin = packer.pin },
        terminals = {}, items = {},
        version = RemoteTerminal.Network.version,
    }
    local agg = {}

    for code, t in pairs(RemoteTerminal.Network.terminals) do
        if t.packerIP == ip then
            table.insert(state.terminals, {
                code = code,
                x = t.x, y = t.y, z = t.z,
                pin = t.pin, radius = t.radius,
                linkedContainers = t.linkedContainers,
                categories = t.categories, items = t.items,
                containerCount = #t.linkedContainers,
            })
            for _, cp in ipairs(t.linkedContainers) do
                local snap = refreshContainerSnapshot(cp.x, cp.y, cp.z)
                if snap then
                    for _, entry in ipairs(snap) do
                        local ex = agg[entry.fullType]
                        if not ex then
                            agg[entry.fullType] = {
                                fullType = entry.fullType,
                                displayName = entry.displayName,
                                category = entry.category,
                                count = 0, totalWeight = 0,
                                hasFridge = false, hasFreezer = false,
                            }
                            ex = agg[entry.fullType]
                        end
                        ex.count = ex.count + entry.count
                        ex.totalWeight = ex.totalWeight + entry.totalWeight
                        ex.hasFridge = ex.hasFridge or entry.hasFridge
                        ex.hasFreezer = ex.hasFreezer or entry.hasFreezer
                    end
                end
            end
        end
    end

    for _, v in pairs(agg) do table.insert(state.items, v) end
    table.sort(state.items, function(a, b) return (a.displayName or ""):lower() < (b.displayName or ""):lower() end)
    return state
end

-- ============================================================================
-- Item Transfer (server only, loaded chunks only)
-- ============================================================================

function RemoteTerminalNetwork.transferItemsToPlayer(playerObj, ip, fullType, count)
    if not isServerSide() or not playerObj or not ip or not fullType then return 0 end
    local state = RemoteTerminalNetwork.getNetworkState(ip)
    if not state then return 0 end

    local transferred, maxCount = 0, (count and count > 0) and count or 999999
    local cell = getCell()
    if not cell then return 0 end

    for _, ti in ipairs(state.terminals) do
        if transferred >= maxCount then break end
        for _, cp in ipairs(ti.linkedContainers) do
            if transferred >= maxCount then break end
            local sq = cell:getGridSquare(cp.x, cp.y, cp.z)
            if sq then
                local ok, objList = pcall(function() return sq:getObjects() end)
                if ok and objList then
                    for i = 0, objList:size() - 1 do
                        if transferred >= maxCount then break end
                        local container = objList:get(i):getContainer()
                        if container then
                            local items = container:getItems()
                            for j = 0, items:size() - 1 do
                                if transferred >= maxCount then break end
                                local item = items:get(j)
                                if item and item:getFullType() == fullType then
                                    local inv = playerObj:getInventory()
                                    if inv and inv:hasRoomFor(playerObj, item) then
                                        inv:AddItem(item)
                                        transferred = transferred + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return transferred
end

function RemoteTerminalNetwork.storeItemsFromPlayer(playerObj, ip, items)
    if not isServerSide() or not playerObj or not ip or not items then return 0 end
    local state = RemoteTerminalNetwork.getNetworkState(ip)
    if not state then return 0 end

    local stored = 0
    local cell = getCell()
    if not cell then return 0 end

    local allC, coldC = {}, {}
    for _, ti in ipairs(state.terminals) do
        for _, cp in ipairs(ti.linkedContainers) do
            local sq = cell:getGridSquare(cp.x, cp.y, cp.z)
            if sq then
                local ok, objList = pcall(function() return sq:getObjects() end)
                if ok and objList then
                    for i = 0, objList:size() - 1 do
                        local c = objList:get(i):getContainer()
                        if c then
                            table.insert(allC, c)
                            local ct = string.lower(c:getType() or "")
                            if ct:find("freezer") or ct:find("fridge") or ct:find("refrigerator") then
                                table.insert(coldC, c)
                            end
                        end
                    end
                end
            end
        end
    end

    for _, item in ipairs(items) do
        if not item then goto continue end
        local perishable = false
        if instanceof(item, "Food") then
            local ok, oam = pcall(function() return item:getOffAgeMax() end)
            if ok and oam and oam > 0 then perishable = true end
        end
        local targets = perishable and coldC or allC
        if #targets == 0 then targets = allC end
        for _, c in ipairs(targets) do
            if c:isItemAllowed(item) and c:hasRoomFor(playerObj, item) then
                local inv = playerObj:getInventory()
                if inv then
                    inv:Remove(item)
                    c:AddItem(item)
                    stored = stored + 1
                    break
                end
            end
        end
        ::continue::
    end
    return stored
end

-- ============================================================================
-- Server Command Handler (server only)
-- ============================================================================

local function handleServerCommand(moduleName, commandName, playerObj, args)
    if not isServerSide() then return end
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
        local ip, ft, cnt = args and args.ip, args and args.fullType, args and args.count
        local transferred = RemoteTerminalNetwork.transferItemsToPlayer(playerObj, ip, ft, cnt)
        sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "transferResult", {
            fullType = ft, transferred = transferred,
        })

    elseif commandName == "requestStore" then
        local ip, ft, cnt = args and args.ip, args and args.fullType, args and args.count or 1
        local inv = playerObj:getInventory()
        local toStore = {}
        if inv then
            local items = inv:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item and item:getFullType() == ft and #toStore < cnt then
                    table.insert(toStore, item)
                end
            end
        end
        local stored = RemoteTerminalNetwork.storeItemsFromPlayer(playerObj, ip, toStore)
        sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "storeResult", {
            fullType = ft, stored = stored,
        })

    elseif commandName == "requestLinkContainer" then
        local tc, cx, cy, cz = args and args.terminalCode, args and args.x, args and args.y, args and args.z
        local ok = RemoteTerminalNetwork.linkContainerToTerminal(tc, cx, cy, cz)
        sendServerCommand(playerObj, RemoteTerminal.COMMAND_MODULE, "linkResult", {
            terminalCode = tc, ok = ok,
        })
    end
end

-- ============================================================================
-- Initialization (server only — NO chunk scanning)
-- ============================================================================

function RemoteTerminalNetwork.init()
    if not isServerSide() then return end
    RemoteTerminal.initSandbox()
    loadNetwork()
    Events.OnClientCommand.Add(handleServerCommand)
end

if isServerSide() then
    Events.OnInitGlobalModData.Add(function()
        RemoteTerminalNetwork.init()
    end)
end
