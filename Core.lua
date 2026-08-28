local ADDON_NAME = ...

AltoWeed = {}
local AltoWeed = AltoWeed
AltoWeed.bankOpen = false
AltoWeed.chestOpen = false
AltoWeed.tradeSkillOpen = false

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

-- Recognized WotLK profession/secondary-skill names. Used to pick professions
-- out of the generic Skills list (see ScanSkillLines below) without relying
-- on that list's category headers, which may not match a custom client.
local KNOWN_PROFESSIONS = {
    ["Alchemy"] = true, ["Blacksmithing"] = true, ["Enchanting"] = true,
    ["Engineering"] = true, ["Herbalism"] = true, ["Inscription"] = true,
    ["Jewelcrafting"] = true, ["Leatherworking"] = true, ["Mining"] = true,
    ["Skinning"] = true, ["Tailoring"] = true,
    ["Cooking"] = true, ["First Aid"] = true, ["Fishing"] = true,
}

-- The generic Skills list (GetNumSkillLines/GetSkillLineInfo - the same data
-- that backs the Skills tab in the default spellbook) has rank/max rank for
-- every profession, including pure-gathering ones like Herbalism, Mining, and
-- Skinning that never open a trade skill window and so are otherwise
-- invisible to ScanTradeSkill(). No window needs to be open for this.
--
-- Its headers can be collapsed, same quirk as the currency tab - expand
-- everything first, read, then restore the original collapse state.
local function ScanSkillLines()
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end

    local collapsedNames = {}
    if ExpandSkillHeader then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded then
                collapsedNames[name] = true
            end
        end

        local i = 1
        while i <= GetNumSkillLines() do
            local name, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded then
                ExpandSkillHeader(i)
            else
                i = i + 1
            end
        end
    end

    local results = {}
    for i = 1, GetNumSkillLines() do
        local name, isHeader, isExpanded, rank, _, _, maxRank = GetSkillLineInfo(i)
        if not isHeader and KNOWN_PROFESSIONS[name] then
            results[name] = { rank = rank, maxRank = maxRank }
        end
    end

    if ExpandSkillHeader then
        for i = GetNumSkillLines(), 1, -1 do
            local name, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and isExpanded and collapsedNames[name] then
                ExpandSkillHeader(i)
            end
        end
    end

    return results
end

-- Profession summary (rank/max rank per profession). Tries the Skills list
-- first (works for every profession, no window needed), then layers on
-- GetProfessions()/GetProfessionInfo() where available (also gives an icon).
-- Some private-server clients (e.g. Ascension, which adds classes like Monk
-- that don't exist in real 3.3.5a) don't expose GetProfessions() at all, so
-- that part is best-effort and simply skipped if missing.
function AltoWeed:ScanProfessions()
    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then return end
    char.professions = char.professions or {}

    local skillResults = ScanSkillLines()
    if skillResults then
        for name, info in pairs(skillResults) do
            local prof = char.professions[name] or {}
            prof.name = name
            prof.rank = info.rank
            prof.maxRank = info.maxRank
            char.professions[name] = prof
        end
    end

    if GetProfessions and GetProfessionInfo then
        local numSlots = select("#", GetProfessions())
        local slots = { GetProfessions() }
        for i = 1, numSlots do
            local slotIndex = slots[i]
            if slotIndex then
                local name, icon, rank, maxRank = GetProfessionInfo(slotIndex)
                if name and name ~= "" then
                    local prof = char.professions[name] or {}
                    prof.name = name
                    prof.icon = icon
                    prof.rank = rank
                    prof.maxRank = maxRank
                    char.professions[name] = prof
                end
            end
        end
    end

    char.lastVisit = time()

    self:RefreshUIIfShowing(key)
end

-- Difficulty color for a recipe row, keyed by the strings GetTradeSkillInfo()
-- returns for recipe difficulty ("optimal"/"medium"/"easy"/"trivial"). Kept
-- local rather than relying on a Blizzard global of the same purpose.
local TRADESKILL_DIFFICULTY_COLORS = {
    optimal = { r = 1.00, g = 0.50, b = 0.00 },
    medium  = { r = 1.00, g = 1.00, b = 0.00 },
    easy    = { r = 0.25, g = 0.75, b = 0.25 },
    trivial = { r = 0.60, g = 0.60, b = 0.60 },
}
AltoWeed.TRADESKILL_DIFFICULTY_COLORS = TRADESKILL_DIFFICULTY_COLORS

-- Recipes known for a profession only show up in GetTradeSkillInfo() while
-- that profession's trade skill window is actually open, same "only while
-- open" quirk as the bank and chest. Enchanting shares this same API in this
-- client version (the older separate Craft API was folded into it before
-- Wrath), so no special-casing is needed there.
function AltoWeed:ScanTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillInfo) then return end

    local key = self:GetCharacterKey()
    local char = AltoWeedDB.characters[key]
    if not char then return end

    local skillName, currentLevel, maxLevel = GetTradeSkillLine()
    if not skillName or skillName == "" or skillName == "UNKNOWN" then return end

    char.professions = char.professions or {}
    local prof = char.professions[skillName] or {}
    prof.name = skillName
    prof.rank = currentLevel
    prof.maxRank = maxLevel

    local recipes = {}
    local category = nil
    for i = 1, GetNumTradeSkills() do
        local name, skillType = GetTradeSkillInfo(i)
        if skillType == "header" or skillType == "subheader" then
            category = name
        elseif name then
            recipes[#recipes + 1] = {
                name = name,
                link = GetTradeSkillItemLink and GetTradeSkillItemLink(i) or nil,
                icon = GetTradeSkillIcon and GetTradeSkillIcon(i) or nil,
                difficulty = skillType,
                category = category,
            }
        end
    end
    prof.recipes = recipes
    char.professions[skillName] = prof
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
        char = { bags = {}, bank = {}, currency = {}, money = 0, chest = {}, professions = {} }
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
local pendingProfessionScan, pendingTradeSkillScan = false, false
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
    if pendingProfessionScan then
        pendingProfessionScan = false
        AltoWeed:ScanProfessions()
    end
    if pendingTradeSkillScan then
        pendingTradeSkillScan = false
        AltoWeed:ScanTradeSkill()
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

local function RequestProfessionScan()
    pendingProfessionScan = true
    throttleFrame:Show()
end

local function RequestTradeSkillScan()
    pendingTradeSkillScan = true
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
eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_UPDATE")
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")

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
        AltoWeed:ScanProfessions()
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
    elseif event == "SKILL_LINES_CHANGED" then
        RequestProfessionScan()
    elseif event == "TRADE_SKILL_SHOW" then
        AltoWeed.tradeSkillOpen = true
        AltoWeed:ScanTradeSkill()
    elseif event == "TRADE_SKILL_UPDATE" then
        if AltoWeed.tradeSkillOpen then
            RequestTradeSkillScan()
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        AltoWeed.tradeSkillOpen = false
    end
end)
