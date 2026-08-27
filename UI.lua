AltoWeedUI = {}
local AltoWeedUI = AltoWeedUI
AltoWeedUI.selectedKey = nil

local WINDOW_WIDTH, WINDOW_HEIGHT = 820, 500
local TITLE_HEIGHT = 34
local LEFT_WIDTH = 82 -- ~10% of WINDOW_WIDTH, as requested
local BOTTOM_HEIGHT = 30
local GUTTER = 10
local ITEM_SIZE = 36
local ITEM_PADDING = 6
local SEARCH_HEIGHT = 22
local SEARCH_ROW_HEIGHT = SEARCH_HEIGHT + GUTTER

-- Pulls the item name out of an item link, e.g.
-- "|cffffffff|Hitem:12345::::::::80:::::|h[Foo Bar]|h|r" -> "Foo Bar"
local function ItemNameFromLink(link)
    if not link then return nil end
    return link:match("%[(.-)%]")
end

local function MatchesSearch(name, query)
    if not query or not name then return false end
    return string.find(name:lower(), query, 1, true) ~= nil
end

StaticPopupDialogs["ALTOWEED_DELETE_CHAR"] = {
    text = "Delete recorded items for %s?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        AltoWeed:DeleteCharacter(AltoWeedUI.deleteTargetKey)
        if AltoWeedUI.selectedKey == AltoWeedUI.deleteTargetKey then
            AltoWeedUI.selectedKey = nil
        end
        AltoWeedUI:RefreshCharacterList()
        AltoWeedUI:RefreshItems()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- A small self-contained scrolling area (avoids relying on template quirks).

local function CreateScrollArea(parent, name, totalWidth, height)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    scroll:SetSize(totalWidth, height)
    scroll:EnableMouseWheel(true)

    local slider = CreateFrame("Slider", name .. "Slider", scroll)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(16)
    slider:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -2)
    slider:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 2)
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:Hide()

    local content = CreateFrame("Frame", name .. "Content", scroll)
    content:SetSize(totalWidth - 20, height)
    scroll:SetScrollChild(content)

    slider:SetScript("OnValueChanged", function(self, value)
        scroll:SetVerticalScroll(value)
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local minV, maxV = slider:GetMinMaxValues()
        if maxV <= 0 then return end
        local step = 40
        local newValue = slider:GetValue() - delta * step
        if newValue < minV then newValue = minV end
        if newValue > maxV then newValue = maxV end
        slider:SetValue(newValue)
    end)

    return scroll, content, slider
end

local function FormatMoney(copper)
    copper = copper or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", gold, silver, c)
end

local function UpdateScrollRange(scroll, content, slider)
    local visibleHeight = scroll:GetHeight()
    local maxScroll = math.max(0, content:GetHeight() - visibleHeight)
    slider:SetMinMaxValues(0, maxScroll)
    if maxScroll <= 0 then
        slider:Hide()
        scroll:SetVerticalScroll(0)
        slider:SetValue(0)
    else
        slider:Show()
    end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Character list buttons (pooled and reused across refreshes)

function AltoWeedUI:GetCharButton(i)
    local btn = self.charButtons[i]
    if btn then return btn end

    btn = CreateFrame("Button", nil, self.charListContent)
    btn:SetHeight(18)

    local highlight = btn:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetTexture(0.3, 0.5, 0.9, 0.4)
    highlight:Hide()
    btn.highlight = highlight

    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetTexture(1, 1, 1, 0.15)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 2, 0)
    text:SetPoint("RIGHT", -2, 0)
    text:SetJustifyH("LEFT")
    btn.text = text

    btn:SetScript("OnClick", function(self)
        AltoWeedUI.selectedKey = self.key
        AltoWeedUI:RefreshCharacterList()
        AltoWeedUI:RefreshItems()
    end)

    btn:SetScript("OnEnter", function(self)
        local char = AltoWeedDB.characters[self.key]
        if not char then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(char.name)
        GameTooltip:AddLine(char.realm, 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Level " .. (char.level or "?"), 0.7, 0.7, 0.7)
        GameTooltip:AddLine(date("%Y-%m-%d %H:%M", char.lastVisit or 0), 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.charButtons[i] = btn
    return btn
end

function AltoWeedUI:RefreshCharacterList()
    local keys = {}
    for k in pairs(AltoWeedDB.characters) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return (AltoWeedDB.characters[a].lastVisit or 0) > (AltoWeedDB.characters[b].lastVisit or 0)
    end)

    for _, btn in ipairs(self.charButtons) do
        btn:Hide()
    end

    local width = self.charListContent:GetWidth()
    for i, key in ipairs(keys) do
        local btn = self:GetCharButton(i)
        local char = AltoWeedDB.characters[key]
        local color = RAID_CLASS_COLORS[char.class] or NORMAL_FONT_COLOR
        btn.text:SetText(char.name)
        btn.text:SetTextColor(color.r, color.g, color.b)
        btn.key = key
        btn:SetWidth(width)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", self.charListContent, "TOPLEFT", 0, -(i - 1) * 18)
        if key == self.selectedKey then
            btn.highlight:Show()
        else
            btn.highlight:Hide()
        end
        btn:Show()
    end

    self.charListContent:SetHeight(math.max(#keys * 18, self.charListScroll:GetHeight()))
    UpdateScrollRange(self.charListScroll, self.charListContent, self.charListSlider)
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Item grid buttons (pooled and reused across refreshes)

function AltoWeedUI:GetItemButton(i)
    local btn = self.itemButtons[i]
    if btn then return btn end

    btn = CreateFrame("Button", nil, self.itemContent)
    btn:SetSize(ITEM_SIZE, ITEM_SIZE)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("CENTER")
    border:SetSize(ITEM_SIZE * 1.4, ITEM_SIZE * 1.4)
    btn.border = border

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.count = count

    -- Shown when this item matches the current search; drawn above the
    -- quality border so a match is unmistakable even on a colored item.
    local searchHighlight = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    searchHighlight:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    searchHighlight:SetBlendMode("ADD")
    searchHighlight:SetVertexColor(1, 0.9, 0.1)
    searchHighlight:SetPoint("CENTER")
    searchHighlight:SetSize(ITEM_SIZE * 1.8, ITEM_SIZE * 1.8)
    searchHighlight:Hide()
    btn.searchHighlight = searchHighlight

    btn:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        elseif self.currencyName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.currencyName)
            GameTooltip:AddLine(tostring(self.currencyCount or 0), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.itemButtons[i] = btn
    return btn
end

function AltoWeedUI:GetChestTabHeader(i)
    local fs = self.chestTabHeaders[i]
    if fs then return fs end
    fs = self.itemContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.chestTabHeaders[i] = fs
    return fs
end

function AltoWeedUI:LayoutItems(items, index, y, perRow)
    items = items or {}
    if #items == 0 then
        return index, y
    end
    local query = self.searchQuery
    local col = 0
    for _, item in ipairs(items) do
        local btn = self:GetItemButton(index)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT",
            2 + col * (ITEM_SIZE + ITEM_PADDING), -y)
        btn.icon:SetTexture(item.icon)
        btn.link = item.link
        btn.count:SetText((item.count and item.count > 1) and item.count or "")
        local qc = item.quality and ITEM_QUALITY_COLORS[item.quality]
        if qc and item.quality > 1 then
            btn.border:SetVertexColor(qc.r, qc.g, qc.b)
            btn.border:Show()
        else
            btn.border:Hide()
        end
        if query and MatchesSearch(ItemNameFromLink(item.link), query) then
            btn.searchHighlight:Show()
        else
            btn.searchHighlight:Hide()
        end
        btn:Show()

        index = index + 1
        col = col + 1
        if col >= perRow then
            col = 0
            y = y + ITEM_SIZE + ITEM_PADDING
        end
    end
    if col > 0 then
        y = y + ITEM_SIZE + ITEM_PADDING
    end
    return index, y
end

function AltoWeedUI:LayoutCurrency(items, index, y, perRow)
    items = items or {}
    if #items == 0 then
        return index, y
    end
    local query = self.searchQuery
    local col = 0
    for _, item in ipairs(items) do
        local btn = self:GetItemButton(index)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT",
            2 + col * (ITEM_SIZE + ITEM_PADDING), -y)
        btn.icon:SetTexture(item.icon)
        btn.link = nil
        btn.currencyName = item.name
        btn.currencyCount = item.count
        btn.count:SetText(item.count or 0)
        btn.border:Hide()
        if query and MatchesSearch(item.name, query) then
            btn.searchHighlight:Show()
        else
            btn.searchHighlight:Hide()
        end
        btn:Show()

        index = index + 1
        col = col + 1
        if col >= perRow then
            col = 0
            y = y + ITEM_SIZE + ITEM_PADDING
        end
    end
    if col > 0 then
        y = y + ITEM_SIZE + ITEM_PADDING
    end
    return index, y
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Search

function AltoWeedUI:RunSearch(text)
    text = strtrim(text or "")
    self.searchQuery = (text ~= "") and text:lower() or nil
    self:RefreshItems()
end

function AltoWeedUI:RefreshItems()
    local char = self.selectedKey and AltoWeedDB.characters[self.selectedKey]

    for _, btn in ipairs(self.itemButtons) do
        btn:Hide()
        btn.link = nil
        btn.currencyName = nil
        btn.currencyCount = nil
        btn.searchHighlight:Hide()
    end
    for _, fs in ipairs(self.chestTabHeaders) do
        fs:Hide()
    end

    if not char then
        self.bagsHeader:Hide()
        self.bankHeader:Hide()
        self.currencyHeader:Hide()
        self.moneyText:Hide()
        self.chestHeader:Hide()
        self.itemContent:SetHeight(self.itemScroll:GetHeight())
        UpdateScrollRange(self.itemScroll, self.itemContent, self.itemSlider)
        return
    end

    local perRow = math.max(1, math.floor(self.itemContent:GetWidth() / (ITEM_SIZE + ITEM_PADDING)))
    local index, y = 1, 0

    self.currencyHeader:Show()
    self.currencyHeader:ClearAllPoints()
    self.currencyHeader:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT", 2, -y)
    y = y + 18

    self.moneyText:Show()
    self.moneyText:ClearAllPoints()
    self.moneyText:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT", 2, -y)
    self.moneyText:SetText(FormatMoney(char.money))
    y = y + 18

    index, y = self:LayoutCurrency(char.currency, index, y, perRow)

    y = y + 12
    self.bagsHeader:Show()
    self.bagsHeader:ClearAllPoints()
    self.bagsHeader:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT", 2, -y)
    y = y + 18

    index, y = self:LayoutItems(char.bags, index, y, perRow)

    y = y + 12
    self.bankHeader:Show()
    self.bankHeader:ClearAllPoints()
    self.bankHeader:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT", 2, -y)
    y = y + 18

    index, y = self:LayoutItems(char.bank, index, y, perRow)

    if char.chest and #char.chest > 0 then
        y = y + 12
        self.chestHeader:Show()
        self.chestHeader:ClearAllPoints()
        self.chestHeader:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT", 2, -y)
        y = y + 18

        for tabIndex, tab in ipairs(char.chest) do
            local tabHeader = self:GetChestTabHeader(tabIndex)
            tabHeader:SetText(tab.name)
            tabHeader:Show()
            tabHeader:ClearAllPoints()
            tabHeader:SetPoint("TOPLEFT", self.itemContent, "TOPLEFT", 10, -y)
            y = y + 16

            index, y = self:LayoutItems(tab.items, index, y, perRow)
            y = y + 8
        end
    else
        self.chestHeader:Hide()
    end

    self.itemContent:SetHeight(math.max(y, self.itemScroll:GetHeight()))
    UpdateScrollRange(self.itemScroll, self.itemContent, self.itemSlider)
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Frame construction

function AltoWeedUI:CreateFrame()
    local frame = CreateFrame("Frame", "AltoWeedFrame", UIParent)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:Hide()
    table.insert(UISpecialFrames, "AltoWeedFrame") -- lets Escape close it

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("AltoWeed")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Left: character list (~10% of the window width)
    local listAreaHeight = WINDOW_HEIGHT - TITLE_HEIGHT - BOTTOM_HEIGHT - GUTTER * 2
    local charScroll, charContent, charSlider = CreateScrollArea(frame, "AltoWeedCharScroll", LEFT_WIDTH, listAreaHeight)
    charScroll:SetPoint("TOPLEFT", GUTTER, -TITLE_HEIGHT)
    self.charListScroll = charScroll
    self.charListContent = charContent
    self.charListSlider = charSlider

    local deleteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteBtn:SetSize(LEFT_WIDTH, 22)
    deleteBtn:SetPoint("BOTTOMLEFT", GUTTER, GUTTER)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        if not AltoWeedUI.selectedKey then return end
        local char = AltoWeedDB.characters[AltoWeedUI.selectedKey]
        AltoWeedUI.deleteTargetKey = AltoWeedUI.selectedKey
        StaticPopup_Show("ALTOWEED_DELETE_CHAR", char and char.name or AltoWeedUI.selectedKey)
    end)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(1, 1, 1, 0.15)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", charScroll, "TOPRIGHT", GUTTER, 0)
    divider:SetPoint("BOTTOMLEFT", deleteBtn, "BOTTOMRIGHT", GUTTER, 0)

    -- Right: search bar, then item grid (currency, bags, bank, chest)
    local itemAreaWidth = WINDOW_WIDTH - LEFT_WIDTH - GUTTER * 4

    local searchBtn = CreateFrame("Button", "AltoWeedSearchButton", frame)
    searchBtn:SetSize(SEARCH_HEIGHT, SEARCH_HEIGHT)
    searchBtn:SetPoint("TOPRIGHT", divider, "TOPRIGHT", GUTTER + itemAreaWidth, -4)
    local searchIcon = searchBtn:CreateTexture(nil, "ARTWORK")
    searchIcon:SetAllPoints()
    searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    searchBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    searchBtn:SetScript("OnClick", function()
        AltoWeedUI:RunSearch(AltoWeedUI.searchBox:GetText())
    end)
    self.searchButton = searchBtn

    local searchBox = CreateFrame("EditBox", "AltoWeedSearchBox", frame, "InputBoxTemplate")
    searchBox:SetHeight(SEARCH_HEIGHT)
    searchBox:SetWidth(itemAreaWidth - SEARCH_HEIGHT - 14)
    searchBox:SetPoint("TOPLEFT", divider, "TOPRIGHT", GUTTER + 6, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(4, 4, 0, 0)
    searchBox:SetScript("OnEnterPressed", function(self)
        AltoWeedUI:RunSearch(self:GetText())
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.searchBox = searchBox

    local itemAreaHeight = WINDOW_HEIGHT - TITLE_HEIGHT - GUTTER * 2 - SEARCH_ROW_HEIGHT
    local itemScroll, itemContent, itemSlider = CreateScrollArea(frame, "AltoWeedItemScroll", itemAreaWidth, itemAreaHeight)
    itemScroll:SetPoint("TOPLEFT", divider, "TOPRIGHT", GUTTER, -SEARCH_ROW_HEIGHT)
    self.itemScroll = itemScroll
    self.itemContent = itemContent
    self.itemSlider = itemSlider

    local bagsHeader = itemContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bagsHeader:SetText("Bags")
    self.bagsHeader = bagsHeader

    local bankHeader = itemContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bankHeader:SetText("Bank")
    self.bankHeader = bankHeader

    local currencyHeader = itemContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currencyHeader:SetText("Currency")
    self.currencyHeader = currencyHeader

    local moneyText = itemContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.moneyText = moneyText

    local chestHeader = itemContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chestHeader:SetText("Personal Storage")
    self.chestHeader = chestHeader

    self.charButtons = {}
    self.itemButtons = {}
    self.chestTabHeaders = {}
    self.searchQuery = nil
end

function AltoWeedUI:Toggle()
    if not AltoWeedFrame then
        self:CreateFrame()
    end

    if AltoWeedFrame:IsShown() then
        AltoWeedFrame:Hide()
        return
    end

    if not self.selectedKey then
        self.selectedKey = AltoWeed:GetCharacterKey()
    end

    AltoWeedFrame:Show()
    self:RefreshCharacterList()
    self:RefreshItems()
end
