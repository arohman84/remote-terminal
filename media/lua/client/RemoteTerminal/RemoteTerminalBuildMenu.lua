-- RemoteTerminalBuildMenu.lua
-- Build menu integration for Remote Terminal packers and terminals.
-- Adds "Remote Terminals" sub-menu under Build with Packer + Terminal options.
-- Follows the WarehouseTerminal_Balanced build menu pattern.

require "BuildingObjects/ISBuildingObject"
require "server/RemoteTerminal/RemoteTerminalObjects"
require "RemoteTerminal/RemoteTerminal"
require "RemoteTerminal/RemoteTerminalData"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"

RemoteTerminalBuildMenu = RemoteTerminalBuildMenu or {}

-- ============================================================================
-- Sprites
-- ============================================================================
RemoteTerminalBuildMenu.PACKER_SPRITE = "appliances_com_01_52"
RemoteTerminalBuildMenu.TERMINAL_SPRITE = "appliances_com_01_40"

-- ============================================================================
-- Helpers
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
    if groundCounts[type] then
        count = count + groundCounts[type]
    end
    return count
end

-- ============================================================================
-- Tooltip Builder
-- ============================================================================
local TERMINAL_REQUIREMENTS = {
    materials = {
        { type = "SheetMetal", fullType = "Base.SheetMetal", count = 6 },
        { type = "MetalPipe",   fullType = "Base.MetalPipe",   count = 4 },
        { type = "Plank",       fullType = "Base.Plank",       count = 6 },
    },
    tools = {
        { type = "BlowTorch",   fullType = "Base.BlowTorch" },
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
        { type = "BlowTorch",   fullType = "Base.BlowTorch" },
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

    -- Materials
    for _, mat in ipairs(requirements.materials) do
        local count = getMaterialCount(playerObj, groundCounts, mat.fullType)
        local ok = count >= mat.count
        local prefix = ok and " <RGB:0,1,0> " or " <RGB:1,0,0> "
        tooltip.description = (tooltip.description or "") .. prefix
            .. mat.type .. " " .. count .. "/" .. mat.count .. " <LINE>"
    end

    -- Tools
    for _, tool in ipairs(requirements.tools) do
        local has = false
        if tool.predicate then
            has = playerObj:getInventory():containsEvalRecurse(tool.predicate)
        else
            has = playerObj:getInventory():containsTypeRecurse(tool.fullType)
        end
        local prefix = has and " <RGB:0,1,0> " or " <RGB:1,0,0> "
        tooltip.description = (tooltip.description or "") .. prefix .. tool.type .. " <LINE>"
    end

    -- Perks
    for _, perk in ipairs(requirements.perks) do
        local level = playerObj:getPerkLevel(perk.perk)
        local ok = level >= perk.level
        local prefix = ok and " <RGB:0,1,0> " or " <RGB:1,0,0> "
        tooltip.description = (tooltip.description or "") .. prefix
            .. perk.label .. " " .. level .. "/" .. perk.level
    end
end

-- ============================================================================
-- Build Handlers (place objects in the world)
-- ============================================================================

function RemoteTerminalBuildMenu.onBuildTerminal(worldobjects, player)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

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
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

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
-- Context Menu Hook: "Build" → "Remote Terminals" → Packer / Terminal
-- ============================================================================

function RemoteTerminalBuildMenu.addToBuildMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then
        return true
    end
    if getCore():getGameMode() == "LastStand" then
        return
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj or playerObj:getVehicle() then
        return
    end

    if test then
        return ISWorldObjectContextMenu.setTest()
    end

    -- Find or create the "Build" sub-menu
    local buildOption = context:getOptionFromName(getText("ContextMenu_Build"))
    local buildSubMenu = nil
    if buildOption and buildOption.subOption then
        buildSubMenu = context:getSubMenu(buildOption.subOption)
    else
        buildOption = context:addOption(getText("ContextMenu_Build"), worldobjects, nil)
        buildSubMenu = ISContextMenu:getNew(context)
        context:addSubMenu(buildOption, buildSubMenu)
    end

    -- Add "Remote Terminals" sub-menu
    local groupOption = buildSubMenu:addOption("Remote Terminals", worldobjects, nil)
    local groupSubMenu = ISContextMenu:getNew(buildSubMenu)
    buildSubMenu:addSubMenu(groupOption, groupSubMenu)

    -- Terminal build option
    local terminalOption = groupSubMenu:addOption(
        "Remote Terminal", worldobjects,
        RemoteTerminalBuildMenu.onBuildTerminal, player
    )
    addTooltip(terminalOption, playerObj, RemoteTerminalBuildMenu.TERMINAL_SPRITE, TERMINAL_REQUIREMENTS)

    -- Packer build option
    local packerOption = groupSubMenu:addOption(
        "Remote Packer", worldobjects,
        RemoteTerminalBuildMenu.onBuildPacker, player
    )
    addTooltip(packerOption, playerObj, RemoteTerminalBuildMenu.PACKER_SPRITE, PACKER_REQUIREMENTS)
end

Events.OnFillWorldObjectContextMenu.Add(RemoteTerminalBuildMenu.addToBuildMenu)

-- ============================================================================
-- Packer Context Menu (right-click on world-placed packer)
-- ============================================================================
local function onPackerContextMenu(player, context, worldobjects, test)
    if not worldobjects or #worldobjects == 0 then return end
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    local packerObj = nil
    for _, obj in ipairs(worldobjects) do
        if RemoteTerminal.isPackerObject(obj) then
            packerObj = obj
            break
        end
    end
    if not packerObj then return end

    if test then return ISWorldObjectContextMenu.setTest() end

    local modData = packerObj:getModData()
    local ip = modData and modData.RemotePackerIP or "???"
    local pin = modData and modData.RemotePackerPIN or ""

    -- "View Packer Info"
    local pinDisplay = pin ~= "" and " (PIN: ****)" or " (no PIN)"
    context:addOption("Packer: " .. ip .. pinDisplay, nil, nil)

    -- "Set Packer PIN"
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
                    modData.RemotePackerPIN = (newPIN ~= "" and newPIN or nil)
                    packerObj:transmitModData()
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
