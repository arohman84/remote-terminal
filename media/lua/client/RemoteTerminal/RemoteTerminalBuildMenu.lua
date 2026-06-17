-- RemoteTerminalBuildMenu.lua
-- Build menu integration and world-object context menus for
-- Remote Terminal packers and terminals.
--
-- Adds "Remote Terminals" sub-menu under Build with Packer + Terminal options.
-- Also adds right-click menus for placed packers (view IP, set PIN).
--
-- IMPORTANT: All context menu hooks check test mode first and return
-- early when objects don't belong to this mod, to avoid conflicts.

require "BuildingObjects/ISBuildingObject"
require "server/RemoteTerminal/RemoteTerminalObjects"
require "RemoteTerminal/RemoteTerminal"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISTextBox"

RemoteTerminalBuildMenu = RemoteTerminalBuildMenu or {}

-- ============================================================================
-- Sprites
-- ============================================================================
RemoteTerminalBuildMenu.PACKER_SPRITE   = "appliances_com_01_52"
RemoteTerminalBuildMenu.TERMINAL_SPRITE = "appliances_com_01_40"

-- ============================================================================
-- Material Helpers
-- ============================================================================
local function predicateWeldingMask(item)
    return item:hasTag("WeldingMask") or item:getType() == "WeldingMask"
end

local function getGroundCounts(playerObj)
    local itemMap = buildUtil.getMaterialOnGround(playerObj:getCurrentSquare())
    return buildUtil.getMaterialOnGroundCounts(itemMap)
end

local function getMaterialCount(playerObj, groundCounts, type)
    local count = playerObj:getInventory():getCountTypeRecurse(type)
    if groundCounts[type] then count = count + groundCounts[type] end
    return count
end

-- ============================================================================
-- Requirement Tables
-- ============================================================================
local TERMINAL_REQUIREMENTS = {
    materials = {
        { type = "SheetMetal", fullType = "Base.SheetMetal", count = 6 },
        { type = "MetalPipe",   fullType = "Base.MetalPipe",   count = 4 },
        { type = "Plank",       fullType = "Base.Plank",       count = 6 },
    },
    tools = {
        { type = "BlowTorch", fullType = "Base.BlowTorch" },
        { predicate = predicateWeldingMask, fullType = "Base.WeldingMask" },
    },
    perks = {
        { perk = Perks.Woodwork,     label = "Carpentry",     level = 6 },
        { perk = Perks.MetalWelding, label = "MetalWelding",  level = 4 },
    },
}

local PACKER_REQUIREMENTS = {
    materials = {
        { type = "SheetMetal",    fullType = "Base.SheetMetal",    count = 6 },
        { type = "MetalPipe",     fullType = "Base.MetalPipe",     count = 4 },
        { type = "Plank",         fullType = "Base.Plank",         count = 6 },
        { type = "ElectricWire",  fullType = "Radio.ElectricWire", count = 2 },
        { type = "Wire",          fullType = "Base.Wire",          count = 2 },
    },
    tools = {
        { type = "BlowTorch", fullType = "Base.BlowTorch" },
        { predicate = predicateWeldingMask, fullType = "Base.WeldingMask" },
    },
    perks = {
        { perk = Perks.Woodwork,     label = "Carpentry",     level = 6 },
        { perk = Perks.MetalWelding, label = "MetalWelding",  level = 4 },
    },
}

local function addTooltip(option, playerObj, sprite, requirements)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip = tooltip
    tooltip:setName("Remote Terminal")
    tooltip.texture = sprite
    local groundCounts = getGroundCounts(playerObj)
    for _, mat in ipairs(requirements.materials) do
        local count = getMaterialCount(playerObj, groundCounts, mat.fullType)
        local prefix = count >= mat.count and " <RGB:0,1,0> " or " <RGB:1,0,0> "
        tooltip.description = (tooltip.description or "") .. prefix
            .. mat.type .. " " .. count .. "/" .. mat.count .. " <LINE>"
    end
    for _, tool in ipairs(requirements.tools) do
        local has = tool.predicate
            and playerObj:getInventory():containsEvalRecurse(tool.predicate)
            or playerObj:getInventory():containsTypeRecurse(tool.fullType)
        local prefix = has and " <RGB:0,1,0> " or " <RGB:1,0,0> "
        tooltip.description = (tooltip.description or "") .. prefix .. tool.type .. " <LINE>"
    end
    for _, perk in ipairs(requirements.perks) do
        local level = playerObj:getPerkLevel(perk.perk)
        local prefix = level >= perk.level and " <RGB:0,1,0> " or " <RGB:1,0,0> "
        tooltip.description = (tooltip.description or "") .. prefix
            .. perk.label .. " " .. level .. "/" .. perk.level
    end
end

-- ============================================================================
-- Build Handlers
-- ============================================================================

function RemoteTerminalBuildMenu.onBuildTerminal(worldobjects, player)
    local terminal = RemoteTerminalObject:new(
        RemoteTerminalBuildMenu.TERMINAL_SPRITE,
        RemoteTerminalBuildMenu.TERMINAL_SPRITE,
        RemoteTerminalBuildMenu.TERMINAL_SPRITE,
        RemoteTerminalBuildMenu.TERMINAL_SPRITE
    )
    terminal.player = player
    terminal:setMaterialAmounts()
    getCell():setDrag(terminal, player)
end

function RemoteTerminalBuildMenu.onBuildPacker(worldobjects, player)
    local packer = RemotePackerObject:new(
        RemoteTerminalBuildMenu.PACKER_SPRITE,
        RemoteTerminalBuildMenu.PACKER_SPRITE,
        RemoteTerminalBuildMenu.PACKER_SPRITE,
        RemoteTerminalBuildMenu.PACKER_SPRITE
    )
    packer.player = player
    packer:setMaterialAmounts()
    getCell():setDrag(packer, player)
end

-- ============================================================================
-- Build Menu Hook: "Build" → "Remote Terminals" → Packer / Terminal
-- ============================================================================

local function onFillBuildMenu(player, context, worldobjects, test)
    -- Test mode: signal that we add options, but don't actually add them
    if test and ISWorldObjectContextMenu.Test then return true end
    if getCore():getGameMode() == "LastStand" then return end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then return end
    if test then return ISWorldObjectContextMenu.setTest() end

    local buildOption = context:getOptionFromName(getText("ContextMenu_Build"))
    local buildSubMenu
    if buildOption and buildOption.subOption then
        buildSubMenu = context:getSubMenu(buildOption.subOption)
    else
        buildOption = context:addOption(getText("ContextMenu_Build"), worldobjects, nil)
        buildSubMenu = ISContextMenu:getNew(context)
        context:addSubMenu(buildOption, buildSubMenu)
    end

    local groupOption = buildSubMenu:addOption("Remote Terminals", worldobjects, nil)
    local groupSubMenu = ISContextMenu:getNew(buildSubMenu)
    buildSubMenu:addSubMenu(groupOption, groupSubMenu)

    local termOpt = groupSubMenu:addOption(
        "Remote Terminal", worldobjects,
        RemoteTerminalBuildMenu.onBuildTerminal, player
    )
    addTooltip(termOpt, playerObj, RemoteTerminalBuildMenu.TERMINAL_SPRITE, TERMINAL_REQUIREMENTS)

    local packOpt = groupSubMenu:addOption(
        "Remote Packer", worldobjects,
        RemoteTerminalBuildMenu.onBuildPacker, player
    )
    addTooltip(packOpt, playerObj, RemoteTerminalBuildMenu.PACKER_SPRITE, PACKER_REQUIREMENTS)
end

Events.OnFillWorldObjectContextMenu.Add(onFillBuildMenu)

-- ============================================================================
-- Packer Context Menu (right-click on placed packer)
-- ============================================================================

local function onPackerContextMenu(player, context, worldobjects, test)
    -- Test mode: signal presence but don't add options
    if test and ISWorldObjectContextMenu.Test then return true end
    if not worldobjects or #worldobjects == 0 then return end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    -- Only act if one of the clicked objects is a Remote Packer
    local packerObj = nil
    for _, obj in ipairs(worldobjects) do
        if RemoteTerminal.isPackerObject(obj) then
            packerObj = obj
            break
        end
    end
    if not packerObj then return end  -- NOT our object — don't interfere

    if test then return ISWorldObjectContextMenu.setTest() end

    local md = packerObj:getModData()
    local ip = md.RemotePackerIP or "???"
    local pin = md.RemotePackerPIN or ""

    context:addOption("Packer: " .. ip .. (pin ~= "" and " (PIN: ****)" or " (no PIN)"), nil, nil)

    context:addOption("Set Packer PIN", packerObj, function()
        local modal = ISTextBox:new(
            0, 0, 360, 150,
            "Set Packer PIN (" .. (pin ~= "" and "****" or "none") .. ")",
            "", nil,
            function(_target, button)
                if button.internal ~= "OK" then return end
                local text = button.parent and button.parent.entry and button.parent.entry:getText() or ""
                local newPIN = RemoteTerminal.normalizePIN(text, true)
                if newPIN then
                    md.RemotePackerPIN = (newPIN ~= "" and newPIN or nil)
                    pcall(packerObj.transmitModData, packerObj)
                end
            end,
            playerObj:getPlayerNum()
        )
        modal.maxChars = 4
        modal:initialise()
        modal:setOnlyNumbers(true)
        modal:addToUIManager()
    end)
end

Events.OnFillWorldObjectContextMenu.Add(onPackerContextMenu)
