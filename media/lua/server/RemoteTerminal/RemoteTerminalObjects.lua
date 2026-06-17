-- RemoteTerminalObjects.lua
-- Building object definitions for the Remote Terminal mod.
-- Defines two world-placeable objects:
--   1. Remote Packer     — network hub (holds no items, just routes)
--   2. Remote Terminal   — storage access point (has container, links to packer)
--
-- Uses base-game sprites and follows WarehouseTerminal_Balanced patterns.

require "BuildingObjects/ISBuildingObject"
require "RemoteTerminal/RemoteTerminal"
require "server/RemoteTerminal/RemoteTerminalNetwork"

-- ============================================================================
-- Helper: check for welding mask in inventory
-- ============================================================================
local function hasWeldingMask(inventory)
    return inventory:containsEvalRecurse(function(item)
        return item:hasTag("WeldingMask") or item:getType() == "WeldingMask"
    end)
end

-- ============================================================================
-- REMOTE TERMINAL OBJECT
-- ============================================================================
RemoteTerminalObject = ISBuildingObject:derive("RemoteTerminalObject")

function RemoteTerminalObject:create(x, y, z, north, sprite)
    local cell = getWorld():getCell()
    self.sq = cell:getGridSquare(x, y, z)
    self.javaObject = IsoThumpable.new(cell, self.sq, sprite, north, self)

    buildUtil.setInfo(self.javaObject, self)
    buildUtil.consumeMaterial(self)

    self.javaObject:setMaxHealth(self:getHealth())
    self.javaObject:setHealth(self.javaObject:getMaxHealth())
    self.javaObject:setBreakSound("BreakObject")
    self.javaObject:setThumpSound("ZombieThumpMetal")

    self.javaObject:getModData().RemoteTerminalObj = true
    if not self.javaObject:getModData().RemoteTerminalCode then
        self.javaObject:getModData().RemoteTerminalCode = RemoteTerminal.generateTerminalCode()
    end
    if self.javaObject:getContainer() then
        self.javaObject:getContainer():setType("crate")
    end

    self.sq:AddSpecialObject(self.javaObject)
    self.javaObject:transmitCompleteItemToServer()
    self.javaObject:transmitModData()

    -- Register in global network table
    RemoteTerminalNetwork.registerTerminal(self.javaObject)
end

function RemoteTerminalObject:getHealth()
    return 700 + (buildUtil.getWoodHealth(self) / 2)
end

function RemoteTerminalObject:hasRequiredToolsAndSkills()
    if ISBuildMenu.cheat then
        return true
    end
    local playerObj = getSpecificPlayer(self.player)
    if not playerObj then
        return false
    end
    local inventory = playerObj:getInventory()
    return playerObj:getPerkLevel(Perks.Woodwork) >= 6
        and playerObj:getPerkLevel(Perks.MetalWelding) >= 4
        and inventory:containsTypeRecurse("BlowTorch")
        and hasWeldingMask(inventory)
end

function RemoteTerminalObject:isValid(square)
    if buildUtil.stairIsBlockingPlacement(square, true) then
        return false
    end
    if not self:hasRequiredToolsAndSkills() then
        return false
    end
    return ISBuildingObject.isValid(self, square)
end

function RemoteTerminalObject:render(x, y, z, square)
    ISBuildingObject.render(self, x, y, z, square)
end

function RemoteTerminalObject:new(sprite, northSprite, eastSprite, southSprite)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()

    o:setSprite(sprite)
    o:setNorthSprite(northSprite)
    o:setEastSprite(eastSprite)
    o:setSouthSprite(southSprite)

    o.name = "Remote Terminal"
    o.isContainer = true
    o.containerType = "crate"
    o.blockAllTheSquare = true
    o.dismantable = true
    o.canBarricade = false
    o.canBeLockedByPadlock = false
    o.canBeAlwaysPlaced = false
    o.noNeedHammer = true
    o.firstItem = "BlowTorch"
    o.secondItem = "WeldingMask"
    o.actionAnim = "BlowTorchMid"
    o.craftingBank = "BlowTorch"
    o.completionSound = "BuildMetalStructureMedium"

    o.modData["RemoteTerminalObj"] = true
    o.modData["need:Base.SheetMetal"] = "6"
    o.modData["need:Base.MetalPipe"] = "4"
    o.modData["need:Base.Plank"] = "6"
    o.modData["xp:Woodwork"] = "5"
    o.modData["xp:MetalWelding"] = "10"

    return o
end

-- ============================================================================
-- REMOTE PACKER OBJECT
-- ============================================================================
RemotePackerObject = ISBuildingObject:derive("RemotePackerObject")

function RemotePackerObject:create(x, y, z, north, sprite)
    local cell = getWorld():getCell()
    self.sq = cell:getGridSquare(x, y, z)
    self.javaObject = IsoThumpable.new(cell, self.sq, sprite, north, self)

    buildUtil.setInfo(self.javaObject, self)
    buildUtil.consumeMaterial(self)

    self.javaObject:setMaxHealth(self:getHealth())
    self.javaObject:setHealth(self.javaObject:getMaxHealth())
    self.javaObject:setBreakSound("BreakObject")
    self.javaObject:setThumpSound("ZombieThumpMetal")

    self.javaObject:getModData().RemotePacker = true
    self.javaObject:getModData().RemotePackerIP = self.javaObject:getModData().RemotePackerIP
        or RemoteTerminal.generatePackerIP()

    self.sq:AddSpecialObject(self.javaObject)
    self.javaObject:transmitCompleteItemToServer()
    self.javaObject:transmitModData()

    -- Register in global network table
    RemoteTerminalNetwork.registerPacker(self.javaObject)
end

function RemotePackerObject:getHealth()
    return 700 + (buildUtil.getWoodHealth(self) / 2)
end

function RemotePackerObject:hasRequiredToolsAndSkills()
    if ISBuildMenu.cheat then
        return true
    end
    local playerObj = getSpecificPlayer(self.player)
    if not playerObj then
        return false
    end
    local inventory = playerObj:getInventory()
    return playerObj:getPerkLevel(Perks.Woodwork) >= 6
        and playerObj:getPerkLevel(Perks.MetalWelding) >= 4
        and inventory:containsTypeRecurse("BlowTorch")
        and hasWeldingMask(inventory)
end

function RemotePackerObject:isValid(square)
    if buildUtil.stairIsBlockingPlacement(square, true) then
        return false
    end
    if not self:hasRequiredToolsAndSkills() then
        return false
    end
    return ISBuildingObject.isValid(self, square)
end

function RemotePackerObject:render(x, y, z, square)
    ISBuildingObject.render(self, x, y, z, square)
end

function RemotePackerObject:new(sprite, northSprite, eastSprite, southSprite)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()

    o:setSprite(sprite)
    o:setNorthSprite(northSprite)
    o:setEastSprite(eastSprite)
    o:setSouthSprite(southSprite)

    o.name = "Remote Packer"
    o.isContainer = false
    o.blockAllTheSquare = true
    o.dismantable = true
    o.canBarricade = false
    o.canBeLockedByPadlock = false
    o.canBeAlwaysPlaced = false
    o.noNeedHammer = true
    o.firstItem = "BlowTorch"
    o.secondItem = "WeldingMask"
    o.actionAnim = "BlowTorchMid"
    o.craftingBank = "BlowTorch"
    o.completionSound = "BuildMetalStructureMedium"

    o.modData["RemotePacker"] = true
    o.modData["need:Base.SheetMetal"] = "6"
    o.modData["need:Base.MetalPipe"] = "4"
    o.modData["need:Base.Plank"] = "6"
    o.modData["need:Radio.ElectricWire"] = "2"
    o.modData["need:Base.Wire"] = "2"
    o.modData["xp:Woodwork"] = "5"
    o.modData["xp:MetalWelding"] = "10"

    return o
end
