local ADDON_NAME = ...

AltoWeed = {}
local AltoWeed = AltoWeed
AltoWeed.bankOpen = false
AltoWeed.chestOpen = false

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Saved variables

local function EnsureDB()
    if not AltoWeedDB then
        AltoWeedDB = {}
    end
    if not AltoWeedDB.characters then
        AltoWeedDB.characters = {}
    end
    if not AltoWeedDB.minimap then
        AltoWeedDB.minimap = { angle = 200 }
    end
end

function AltoWeed:GetCharacterKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Scanning

local function ScanBagIntoTable(bagID, target)
    local numSlots = GetContainerNumSlots(bagID)
    if not numSlots or numSlots == 0 then
        return
    end
    for slot = 1, numSlots do
        local icon, count, _, quality, _, _, link = GetContainerItemInfo(bagID, slot)
        if link then
            target[#target + 1] = {
                link = link,
                icon = icon,
                count = count or 1,
                quality = quality or 1,
                itemID = GetContainerItemID(bagID, slot),
            }
        end
    end
end

function AltoWeed:ScanBags()
    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then return end

    local items = {}
    for bag = 0, NUM_BAG_SLOTS do
        ScanBagIntoTable(bag, items)
    end
    char.bags = items
    char.lastVisit = time()

    self:RefreshUIIfShowing(key)
end

function AltoWeed:ScanBank()
    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then return end

    local items = {}
    ScanBagIntoTable(BANK_CONTAINER, items)
    for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
        ScanBagIntoTable(bag, items)
    end
    char.bank = items
    char.lastVisit = time()

    self:RefreshUIIfShowing(key)
end

-- Currency headers can be collapsed in the player's Currency tab, and entries
-- under a collapsed header don't show up in GetCurrencyListInfo() at all, so
-- everything has to be expanded first. We restore the original collapse
-- state afterwards so we don't mess with the player's own UI.
local function ScanCurrencyList()
    local collapsedNames = {}
    for i = 1, GetCurrencyListSize() do
        local name, isHeader, isExpanded = GetCurrencyListInfo(i)
        if isHeader and not isExpanded then
            collapsedNames[name] = true
        end
    end

    local i = 1
    while i <= GetCurrencyListSize() do
        local name, isHeader, isExpanded = GetCurrencyListInfo(i)
        if isHeader and not isExpanded then
            ExpandCurrencyList(i, true)
        else
            i = i + 1
        end
    end

    local list = {}
    for j = 1, GetCurrencyListSize() do
        local name, isHeader, isExpanded, isUnused, isWatched, count, extraCurrencyType, icon = GetCurrencyListInfo(j)
        if not isHeader and count and count > 0 then
            list[#list + 1] = { name = name, count = count, icon = icon }
        end
    end

    -- Collapse from the bottom up: collapsing header j only removes rows
    -- after j, so indices at or before j we haven't processed yet stay valid.
    for j = GetCurrencyListSize(), 1, -1 do
        local name, isHeader, isExpanded = GetCurrencyListInfo(j)
        if isHeader and isExpanded and collapsedNames[name] then
            ExpandCurrencyList(j, false)
        end
    end

    return list
end

function AltoWeed:ScanCurrency()
    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then return end

    char.money = GetMoney()
    char.currency = ScanCurrencyList()
    char.lastVisit = time()

    self:RefreshUIIfShowing(key)
end

-- The "Personal Bank" chest opens a real Guild Bank window (confirmed via
-- GUILDBANKFRAME_OPENED). Tab contents are only sent by the server after
-- QueryGuildBankTab() is called for that tab, same "only while open" quirk
-- as the regular bank.
local function QueryAllChestTabs()
    local numTabs = GetNumGuildBankTabs() or 0
    for tab = 1, numTabs do
        QueryGuildBankTab(tab)
    end
end

function AltoWeed:ScanChest()
    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then return end

    local maxSlots = MAX_GUILDBANK_SLOTS_PER_TAB or 98
    local numTabs = GetNumGuildBankTabs() or 0
    local tabs = {}
    for tab = 1, numTabs do
        local name = GetGuildBankTabInfo(tab)
        local items = {}
        for slot = 1, maxSlots do
            local texture, count, locked, isFiltered, quality = GetGuildBankItemInfo(tab, slot)
            if texture then
                items[#items + 1] = {
                    icon = texture,
                    count = count or 1,
                    quality = quality or 1,
                    link = GetGuildBankItemLink(tab, slot),
                }
            end
        end
        tabs[tab] = { name = (name and name ~= "" and name) or ("Tab " .. tab), items = items }
    end
    char.chest = tabs
    char.lastVisit = time()

    self:RefreshUIIfShowing(key)
end

-- Only refreshes the parts of the window that need it, and only if it's open.
function AltoWeed:RefreshUIIfShowing(key)
    if not (AltoWeedFrame and AltoWeedFrame:IsShown()) then return end
    AltoWeedUI:RefreshCharacterList()
    if AltoWeedUI.selectedKey == key then
        AltoWeedUI:RefreshItems()
    end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Character bookkeeping

function AltoWeed:UpdateCharacterMeta()
    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then
        char = { bags = {}, bank = {}, currency = {}, money = 0, chest = {} }
        AltoWeedDB.characters[key] = char
    end
    char.name = UnitName("player")
    char.realm = GetRealmName()
    local _, classFile = UnitClass("player")
    char.class = classFile
    char.level = UnitLevel("player")
    char.lastVisit = time()
end

function AltoWeed:DeleteCharacter(key)
    if AltoWeedDB and AltoWeedDB.characters then
        AltoWeedDB.characters[key] = nil
    end
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- BAG_UPDATE and PLAYERBANKSLOTS_CHANGED can fire many times in a row (e.g.
-- looting several items at once), so batch them up instead of rescanning on
-- every single event.

local pendingBagScan, pendingBankScan, pendingCurrencyScan, pendingChestScan = false, false, false, false
local elapsedSince = 0
local throttleFrame = CreateFrame("Frame")
throttleFrame:Hide()
throttleFrame:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.3 then return end
    elapsedSince = 0
    self:Hide()
    if pendingBagScan then
        pendingBagScan = false
        AltoWeed:ScanBags()
    end
    if pendingBankScan then
        pendingBankScan = false
        AltoWeed:ScanBank()
    end
    if pendingCurrencyScan then
        pendingCurrencyScan = false
        AltoWeed:ScanCurrency()
    end
    if pendingChestScan then
        pendingChestScan = false
        AltoWeed:ScanChest()
    end
end)

local function RequestBagScan()
    pendingBagScan = true
    throttleFrame:Show()
end

local function RequestBankScan()
    pendingBankScan = true
    throttleFrame:Show()
end

local function RequestCurrencyScan()
    pendingCurrencyScan = true
    throttleFrame:Show()
end

local function RequestChestScan()
    pendingChestScan = true
    throttleFrame:Show()
end

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
eventFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
eventFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
eventFrame:RegisterEvent("GUILDBANK_UPDATE_TABS")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            EnsureDB()
        end
    elseif event == "PLAYER_LOGIN" then
        EnsureDB()
        AltoWeed:UpdateCharacterMeta()
        AltoWeed:ScanBags()
        AltoWeed:ScanCurrency()
        if AltoWeedMinimap then
            AltoWeedMinimap:Create()
        end
    elseif event == "BAG_UPDATE" then
        RequestBagScan()
    elseif event == "BANKFRAME_OPENED" then
        AltoWeed.bankOpen = true
        AltoWeed:ScanBank()
    elseif event == "BANKFRAME_CLOSED" then
        AltoWeed.bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if AltoWeed.bankOpen then
            RequestBankScan()
        end
    elseif event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" then
        RequestCurrencyScan()
    elseif event == "GUILDBANKFRAME_OPENED" then
        AltoWeed.chestOpen = true
        QueryAllChestTabs()
        AltoWeed:ScanChest()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        AltoWeed.chestOpen = false
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        if AltoWeed.chestOpen then
            RequestChestScan()
        end
    elseif event == "GUILDBANK_UPDATE_TABS" then
        if AltoWeed.chestOpen then
            QueryAllChestTabs()
            RequestChestScan()
        end
    end
end)
