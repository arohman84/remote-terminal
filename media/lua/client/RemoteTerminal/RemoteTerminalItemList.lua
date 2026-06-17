-- RemoteTerminalItemList.lua
-- Shared scrollable item list component used by both the walk-up Terminal UI
-- and the handheld Remote Terminal UI.
--
-- Features: search filtering, view tabs (name/category/fridge/freezer),
-- multi-select (Ctrl+Shift), 28px row height with icon + name + count.

require "ISUI/ISScrollingListBox"
require "RemoteTerminal/RemoteTerminal"
require "RemoteTerminal/RemoteTerminalData"

RemoteTerminalItemList = ISScrollingListBox:derive("RemoteTerminalItemList")

local ROW_HEIGHT = 28
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

-- ============================================================================
-- View Modes
-- ============================================================================
RemoteTerminalItemList.VIEW_NAME     = "name"
RemoteTerminalItemList.VIEW_CATEGORY = "category"
RemoteTerminalItemList.VIEW_FRIDGE   = "fridge"
RemoteTerminalItemList.VIEW_FREEZER  = "freezer"

-- ============================================================================
-- Constructor
-- ============================================================================

function RemoteTerminalItemList:new(x, y, width, height)
    local o = ISScrollingListBox:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.itemHeight = ROW_HEIGHT
    o.selected = -1
    o.selectedTypes = {}    -- set of selected fullType strings
    o.viewMode = RemoteTerminalItemList.VIEW_NAME
    o.searchText = ""
    o.entries = {}          -- all available item entries (from server)
    o.filteredEntries = {}  -- entries after search + view filter

    -- Styling
    o.backgroundColor = RemoteTerminal.Colors.list
    o.borderColor = RemoteTerminal.Colors.border
    o.drawBorder = true

    return o
end

-- ============================================================================
-- Data Binding
-- ============================================================================

--- Set the item entries (from server network state).
--- @param entries table Array of { fullType, displayName, category, count, totalWeight, hasFridge, hasFreezer }
function RemoteTerminalItemList:setEntries(entries)
    self.entries = entries or {}
    self.selectedTypes = {}
    self:applyFilters()
end

--- Set the view mode and re-filter.
--- @param mode string One of VIEW_NAME, VIEW_CATEGORY, VIEW_FRIDGE, VIEW_FREEZER
function RemoteTerminalItemList:setViewMode(mode)
    self.viewMode = mode or RemoteTerminalItemList.VIEW_NAME
    self:applyFilters()
end

--- Set the search text and re-filter.
--- @param text string
function RemoteTerminalItemList:setSearchText(text)
    self.searchText = string.lower(tostring(text or ""))
    self:applyFilters()
end

--- Apply search + view mode filters to produce filteredEntries.
function RemoteTerminalItemList:applyFilters()
    local results = {}

    for _, entry in ipairs(self.entries) do
        -- Search filter
        if self.searchText ~= "" then
            local name = string.lower(tostring(entry.displayName or ""))
            local cat = string.lower(tostring(entry.category or ""))
            if not string.find(name, self.searchText, 1, true)
               and not string.find(cat, self.searchText, 1, true) then
                goto skipEntry
            end
        end

        -- View mode filter
        if self.viewMode == RemoteTerminalItemList.VIEW_FRIDGE and not entry.hasFridge then
            goto skipEntry
        end
        if self.viewMode == RemoteTerminalItemList.VIEW_FREEZER and not entry.hasFreezer then
            goto skipEntry
        end

        table.insert(results, entry)
        ::skipEntry::
    end

    -- Sort by name (or category)
    if self.viewMode == RemoteTerminalItemList.VIEW_CATEGORY then
        table.sort(results, function(a, b)
            local ca = string.lower(tostring(a.category or ""))
            local cb = string.lower(tostring(b.category or ""))
            if ca ~= cb then return ca < cb end
            return string.lower(tostring(a.displayName or "")) < string.lower(tostring(b.displayName or ""))
        end)
    else
        table.sort(results, function(a, b)
            return string.lower(tostring(a.displayName or "")) < string.lower(tostring(b.displayName or ""))
        end)
    end

    self.filteredEntries = results
end

-- ============================================================================
-- Selection
-- ============================================================================

--- Toggle selection of a fullType.
--- @param fullType string
--- @param add boolean If true, add to selection (Ctrl+click). If false, toggle.
function RemoteTerminalItemList:toggleSelection(fullType, add)
    if not fullType then return end

    if add then
        self.selectedTypes[fullType] = true
    else
        if self.selectedTypes[fullType] then
            self.selectedTypes[fullType] = nil
        else
            self.selectedTypes = { [fullType] = true }
        end
    end
end

--- Get all selected entries.
--- @return table Array of selected entry tables.
function RemoteTerminalItemList:getSelectedEntries()
    local result = {}
    for _, entry in ipairs(self.filteredEntries) do
        if self.selectedTypes[entry.fullType] then
            table.insert(result, entry)
        end
    end
    return result
end

--- Clear all selections.
function RemoteTerminalItemList:clearSelection()
    self.selectedTypes = {}
    self.selected = -1
end

-- ============================================================================
-- Mouse Input
-- ============================================================================

function RemoteTerminalItemList:onMouseDown(x, y)
    if not self.filteredEntries or #self.filteredEntries == 0 then
        return false
    end

    local row = self:rowAt(x, y)
    if row and row >= 1 and row <= #self.filteredEntries then
        local entry = self.filteredEntries[row]
        if entry then
            local ctrlHeld = isCtrlKeyDown()
            local shiftHeld = isShiftKeyDown()
            self:toggleSelection(entry.fullType, ctrlHeld or shiftHeld)
            self.selected = row
        end
        return true
    end

    return false
end

function RemoteTerminalItemList:onMouseDownOutside()
    self.selected = -1
end

-- ============================================================================
-- Rendering
-- ============================================================================

function RemoteTerminalItemList:prerender()
    ISScrollingListBox.prerender(self)

    local colors = RemoteTerminal.Colors

    -- Draw header
    local headerY = self:getY() - FONT_HGT_SMALL - 6
    local headerText = "Items"
    if self.viewMode == RemoteTerminalItemList.VIEW_CATEGORY then
        headerText = "Items (by Category)"
    elseif self.viewMode == RemoteTerminalItemList.VIEW_FRIDGE then
        headerText = "Fridge Items"
    elseif self.viewMode == RemoteTerminalItemList.VIEW_FREEZER then
        headerText = "Freezer Items"
    end
    self:drawText(headerText, self:getX() + 4, headerY,
        colors.textDim.r, colors.textDim.g, colors.textDim.b, colors.textDim.a, UIFont.Small)

    -- Draw count
    local countText = #self.filteredEntries .. " types"
    local countX = self:getX() + self:getWidth() - getTextManager():MeasureStringX(UIFont.Small, countText) - 6
    self:drawText(countText, countX, headerY,
        colors.textDim.r, colors.textDim.g, colors.textDim.b, colors.textDim.a, UIFont.Small)
end

function RemoteTerminalItemList:doDrawItem(y, item, alt)
    if not item then return end

    local colors = RemoteTerminal.Colors
    local x = 4
    local maxW = self:getWidth() - 8

    -- Row background
    if self.selectedTypes and self.selectedTypes[item.fullType] then
        self:drawRect(0, y, self:getWidth(), ROW_HEIGHT - 1,
            colors.rowSelected.a, colors.rowSelected.r, colors.rowSelected.g, colors.rowSelected.b)
    elseif alt then
        self:drawRect(0, y, self:getWidth(), ROW_HEIGHT - 1,
            colors.rowAlt.a, colors.rowAlt.r, colors.rowAlt.g, colors.rowAlt.b)
    end

    -- Item icon
    local iconSize = 20
    local iconX = x
    local iconY = y + (ROW_HEIGHT - iconSize) / 2
    local texture = item.fullType and getTexture("Item_" .. item.fullType)
    if texture then
        self:drawTexture(texture, iconX, iconY, iconSize, iconSize, 1, 1, 1, 1)
    end

    x = x + iconSize + 6

    -- Cold storage indicator
    if item.hasFreezer then
        self:drawText("*", x, y + 4, colors.cold.r, colors.cold.g, colors.cold.b, colors.cold.a, UIFont.Small)
        x = x + getTextManager():MeasureStringX(UIFont.Small, "* ") + 2
    elseif item.hasFridge then
        self:drawText("~", x, y + 4, colors.cold.r, colors.cold.g, colors.cold.b, colors.cold.a, UIFont.Small)
        x = x + getTextManager():MeasureStringX(UIFont.Small, "~ ") + 2
    end

    -- Item name
    local nameX = x
    local nameW = maxW - nameX - 80
    RemoteTerminalData.drawClippedText(self, item.displayName or item.fullType, nameX, y + 4,
        nameW, colors.text.r, colors.text.g, colors.text.b, colors.text.a, UIFont.Small)

    -- Category (in view modes where category matters)
    if self.viewMode == RemoteTerminalItemList.VIEW_CATEGORY then
        local catText = item.category or ""
        local catX = nameX + nameW + 6
        RemoteTerminalData.drawClippedText(self, catText, catX, y + 4,
            maxW - catX - 60, colors.textDim.r, colors.textDim.g, colors.textDim.b, colors.textDim.a, UIFont.Small)
    end

    -- Count
    local countText = "x" .. tostring(item.count or 0)
    local countX = self:getWidth() - getTextManager():MeasureStringX(UIFont.Small, countText) - 6
    self:drawText(countText, countX, y + 4,
        colors.accent.r, colors.accent.g, colors.accent.b, colors.accent.a, UIFont.Small)

    -- Bottom border
    self:drawRect(0, y + ROW_HEIGHT - 1, self:getWidth(), 1,
        colors.rowBorder.a, colors.rowBorder.r, colors.rowBorder.g, colors.rowBorder.b)
end

-- ============================================================================
-- ISScrollingListBox overrides
-- ============================================================================

function RemoteTerminalItemList:onMouseWheel(del)
    if #self.filteredEntries == 0 then return end
    self:setYScroll(self:getYScroll() + del * ROW_HEIGHT * 3)
    return true
end

function RemoteTerminalItemList:getItems()
    return self.filteredEntries
end

function RemoteTerminalItemList:getItemCount()
    return self.filteredEntries and #self.filteredEntries or 0
end
