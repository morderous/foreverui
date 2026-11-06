-- ForeverUI Trainer: what the class trainer has for you, and where, for WoW
-- Forever. Two pages:
-- - Spells: what you can train now (and what it costs in all), what comes at
--   the next levels, and the nearest class trainer, with a map pin.
-- - Weapons: the weapon masters of your faction's capitals, what each one
--   teaches your class, from what level, and what you know already.
-- A notice at each level up, a button in EllesmereUI's minimap list (or a
-- square of its own), a key in Key Bindings > AddOns, /ftr, and a page in the
-- ForeverUI options.
--
-- The list starts from What's Training?'s data (MIT, Sveng: Data.lua and
-- LICENSE-WhatsTraining.txt). Every visit to a class trainer brings the real
-- prices and anything the data lacks, and the spell book's future spells fill
-- in too. The nearest trainer is Polestar's, read while the game runs (never
-- copied): every call to it is checked, and without it the last class trainer
-- you visited is the one shown.

local ADDON, T = ...

---------------------------------------------------------------------------
-- Sizes and colors
---------------------------------------------------------------------------
local PAD = 8
local TOP_H = 28
local TABS_H = 24
local STRIP_H = 48
local ROW_H = 20
local ICON_SIZE = 16
local MIN_W, MAX_W, DEFAULT_W = 360, 720, 420
local MIN_H, MAX_H, DEFAULT_H = 360, 1000, 560

local COLOR_WINDOW = { 0.06, 0.06, 0.06, 0.94 }
local COLOR_LIST = { 0.10, 0.10, 0.10, 0.92 }
local COLOR_BUTTON = { 0.16, 0.16, 0.16, 1 }
local TEXT = { 0.90, 0.90, 0.92 }
local MUTED = { 0.60, 0.60, 0.65 }
local GREEN = { 0.40, 0.90, 0.45 }
local ORANGE = { 1.00, 0.65, 0.25 }
local RED = { 1.00, 0.42, 0.36 }

local ICON_FILE = "Interface\\Icons\\INV_Misc_Book_11"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

_G.BINDING_HEADER_FOREVERUITRAINER = "ForeverUI Trainer"
_G.BINDING_NAME_FOREVERUITRAINER_TOGGLE = "Open or close the trainer window"

local db, charDB
local DEFAULTS = {
    ahead = 10,              -- levels shown after yours
    talents = false,         -- spells that need a talent you don't have
    knownWeapons = true,     -- weapons you know, on the Weapons page
    otherWeapons = false,    -- weapons your class can't learn
    chat = true, notice = true,
    strata = "MEDIUM", scale = 1, alpha = 0.94, escape = true, locked = false,
    width = DEFAULT_W, height = DEFAULT_H,
    ownButton = false,       -- a minimap button of its own (ForeverUI's F has it in its menu)
    mapButton = true, badge = true,
    tab = "spells",
    bookMove = true,         -- the spell book moves by its top bar (Spellbook.lua)
    bookTab = true,          -- a Trainer tab in the spell book (Spellbook.lua)
}

---------------------------------------------------------------------------
-- Little pieces
---------------------------------------------------------------------------
local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe6b85cForeverUI Trainer|r: " .. text)
end

local function Accent()
    if ForeverUI_Accent then return ForeverUI_Accent() end
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return { 1, 0.82, 0 }
end

local function FontPath()
    if ForeverUI_FontPath then return ForeverUI_FontPath() end
    return STANDARD_TEXT_FONT
end

local function Text(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local ok = pcall(fs.SetFont, fs, FontPath(), size, flags or "")
    if not ok or not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A flat box: 1px black border and a fill, as the rest of the UI.
local function Box(f, color)
    local border = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetAllPoints(f)
    fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return fill, border
end

local function FlatButton(parent, width, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    Box(b, COLOR_BUTTON)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.word = Text(b, 10, TEXT)
    b.word:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.word:SetText(label)
    return b
end

local function Money(amount)
    if not amount then return "?" end
    if GetMoneyString then
        local ok, text = pcall(GetMoneyString, amount, true)
        if ok and text then return text end
    end
    return string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

local function MapName(map)
    if map and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(map)
        if info and info.name then return info.name end
    end
    return "?"
end

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Loaded(name)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local _, loaded = C_AddOns.IsAddOnLoaded(name)
    return loaded and true or false
end

local function InsertLink(link)
    if not link then return false end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    return false
end

-- A pin on the map where the trainer stands, and the game's arrow to it
local function Waypoint(map, x, y, who)
    if not (map and x and y and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        Print("The game can't put a pin there.")
        return
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
        Print("The game can't put a pin on " .. MapName(map) .. ".")
        return
    end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if not ok then
        Print("The game can't put a pin there.")
        return
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    Print(string.format("A pin for %s: %s, %.1f %.1f.", who or "the trainer", MapName(map), x, y))
end

---------------------------------------------------------------------------
-- Who you are
---------------------------------------------------------------------------
local levelNow           -- the level a level up just gave, until UnitLevel says it

local function Me()
    local _, class = UnitClass("player")
    local _, _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local level = UnitLevel("player") or 1
    if levelNow and levelNow > level then level = levelNow end
    return class, race, faction, level
end

local function SeenKey()
    local class, race, faction = Me()
    return string.format("%s-%s-%s", class or "?", faction or "?", tostring(race or "?"))
end

---------------------------------------------------------------------------
-- What you know
---------------------------------------------------------------------------
local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local future = {}        -- [spellID] = level: the spell book's future spells
local futureCount = 0
local rankOf             -- [spellID] = { group, index } for the class's ranks
local rankClass
local memo = {}

local function InBook(id)
    local SB = C_SpellBook
    if not SB then return false end
    if SB.IsSpellKnown and SB.IsSpellKnown(id, BANK) then return true end
    if future[id] then return false end
    if SB.IsSpellInSpellBook and SB.IsSpellInSpellBook(id, BANK, false) then return true end
    return false
end

local function Ranks(class)
    if rankClass == class and rankOf then return rankOf end
    rankOf, rankClass = {}, class
    for _, group in ipairs(T.RANKS and T.RANKS[class] or {}) do
        for i, id in ipairs(group) do rankOf[id] = { group = group, index = i } end
    end
    return rankOf
end

-- Known, or a later rank of it known (those replace the earlier ones)
local function Known(id)
    if memo[id] ~= nil then return memo[id] end
    local known = InBook(id)
    if not known then
        local r = rankOf and rankOf[id]
        if r then
            for i = r.index + 1, #r.group do
                if InBook(r.group[i]) then
                    known = true
                    break
                end
            end
        end
    end
    memo[id] = known
    return known
end

-- The spell book's grey spells "learned at level N", outside the General line
local function ScanBook()
    wipe(future)
    futureCount = 0
    local SB = C_SpellBook
    local FUTURE = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    if not (FUTURE and SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then return end
    local general = Enum.SpellBookSkillLineIndex and Enum.SpellBookSkillLineIndex.General or 1
    for line = 1, SB.GetNumSpellBookSkillLines() do
        local info = SB.GetSpellBookSkillLineInfo(line)
        if info and line ~= general and not info.isGuild and not info.shouldHide then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = SB.GetSpellBookItemInfo(slot, BANK)
                if item and item.itemType == FUTURE then
                    local id = item.spellID or item.actionID
                    if id then
                        local level = SB.GetSpellBookItemLevelLearned and SB.GetSpellBookItemLevelLearned(slot, BANK) or 0
                        future[id] = level
                        futureCount = futureCount + 1
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Spell names, icons and ranks (the game loads some later)
---------------------------------------------------------------------------
local asked = {}
local RequestRefresh     -- (below)

local function Ask(id)
    if asked[id] or not (C_Spell and C_Spell.RequestLoadSpellData) then return end
    asked[id] = true
    C_Spell.RequestLoadSpellData(id)
end

local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name then Ask(id) end
    return name or ("Spell " .. id)
end

local function SpellIcon(id)
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or 134400
end

local function SpellRank(id)
    local rank = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if rank == nil then Ask(id) end
    return rank ~= "" and rank or nil
end

---------------------------------------------------------------------------
-- The list: data, what trainers showed, the spell book's future spells
---------------------------------------------------------------------------
local WEAPON = {}
for _, w in ipairs(T.WEAPONS or {}) do WEAPON[w.id] = w end

local dataAll, dataClass = {}, nil
local function DataSet(class)
    if dataClass == class then return dataAll end
    dataAll, dataClass = {}, class
    for _, list in pairs(T.SPELLS and T.SPELLS[class] or {}) do
        for _, s in ipairs(list) do dataAll[s[1]] = true end
    end
    return dataAll
end

local model = { now = {}, missing = {}, levels = {}, levelOrder = {} }

local function ByLevelThenName(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return SpellName(a.id) < SpellName(b.id)
end

local function BuildModel()
    local class, race, faction, level = Me()
    wipe(memo)
    Ranks(class)
    local all = DataSet(class)
    local entries = {}
    for lvl, list in pairs(T.SPELLS and T.SPELLS[class] or {}) do
        for _, s in ipairs(list) do
            if (not s.faction or s.faction == faction) and (not s.race or s.race == race) then
                entries[s[1]] = { id = s[1], level = lvl, cost = s[2], req = s.req, talent = s.talent, skill = s.skill }
            end
        end
    end
    local seen = db.seen[SeenKey()]
    for id, v in pairs(seen or {}) do
        local e = entries[id]
        if e then
            if v.c then e.cost, e.priced = v.c, true end
            if v.l and v.l > 0 then e.level = v.l end
        elseif not all[id] then
            entries[id] = { id = id, level = v.l or 0, cost = v.c, priced = true, fromTrainer = true }
        end
    end
    for id, lvl in pairs(future) do
        if not entries[id] and not all[id] then entries[id] = { id = id, level = lvl, fromBook = true } end
    end

    local now, nowSet, later = {}, {}, {}
    model.nextLevel = nil
    for id, e in pairs(entries) do
        if not Known(id) then
            local talentMissing = e.talent and not Known(e.talent)
            if talentMissing and not db.talents then
                -- (left out: it needs a talent you don't have)
            elseif e.level <= level then
                e.talentMissing = talentMissing
                nowSet[id] = e
            else
                e.talentMissing = talentMissing
                later[#later + 1] = e
                if not model.nextLevel or e.level < model.nextLevel then model.nextLevel = e.level end
            end
        end
    end
    -- trainable now when what it needs is known or trainable in the same visit
    local missing = {}
    for id, e in pairs(nowSet) do
        e.needs = nil
        for _, r in ipairs(e.req or {}) do
            if not Known(r) and not nowSet[r] then
                e.needs = r
                break
            end
        end
        if e.talentMissing then e.needs = e.talent end
        if e.needs then missing[#missing + 1] = e else now[#now + 1] = e end
    end
    table.sort(now, ByLevelThenName)
    table.sort(missing, ByLevelThenName)
    table.sort(later, ByLevelThenName)
    local cost, unpriced = 0, 0
    for _, e in ipairs(now) do
        if e.cost then cost = cost + e.cost else unpriced = unpriced + 1 end
    end
    local levels, order = {}, {}
    for _, e in ipairs(later) do
        if e.level <= level + db.ahead then
            if not levels[e.level] then
                levels[e.level] = {}
                order[#order + 1] = e.level
            end
            table.insert(levels[e.level], e)
        end
    end
    model.now, model.missing, model.levels, model.levelOrder = now, missing, levels, order
    model.cost, model.unpriced, model.level = cost, unpriced, level
    return model
end

local function WeaponKnown(id)
    local SB = C_SpellBook
    if not SB then return false end
    if SB.IsSpellKnown and SB.IsSpellKnown(id, BANK) then return true end
    return SB.IsSpellInSpellBook and SB.IsSpellInSpellBook(id, BANK, false) or false
end

local function WeaponLevel(w)
    local seen = db.seenWeapons[w.id]
    if seen and seen.l and seen.l > 0 then return seen.l end
    return w.level or 1
end

local function WeaponCost(w)
    local seen = db.seenWeapons[w.id]
    if seen and seen.c then return seen.c end
    return w.cost or 1000
end

local function ClassWeapon(w, class)
    return w.classes and w.classes[class] and true or false
end

-- Your faction's capitals: { map, name, masters = { { master, weapons = { w } } } }
local function BuildWeapons()
    local class, _, faction = Me()
    local cities, byMap = {}, {}
    for _, m in ipairs(T.MASTERS or {}) do
        if m.faction == faction then
            local city = byMap[m.map]
            if not city then
                city = { map = m.map, name = MapName(m.map), masters = {} }
                byMap[m.map] = city
                cities[#cities + 1] = city
            end
            local teaches = {}
            for _, id in ipairs(m.teaches) do teaches[id] = true end
            local list = {}
            for _, w in ipairs(T.WEAPONS or {}) do
                if teaches[w.id] and (db.otherWeapons or ClassWeapon(w, class)) and (db.knownWeapons or not WeaponKnown(w.id)) then
                    list[#list + 1] = w
                end
            end
            table.insert(city.masters, { master = m, weapons = list })
        end
    end
    table.sort(cities, function(a, b) return a.name < b.name end)
    -- the levels a weapon needs, for the line on top
    local learnable, known = 0, 0
    for _, w in ipairs(T.WEAPONS or {}) do
        if ClassWeapon(w, class) then
            if WeaponKnown(w.id) then known = known + 1 else learnable = learnable + 1 end
        end
    end
    return cities, learnable, known
end

---------------------------------------------------------------------------
-- Where to train
---------------------------------------------------------------------------
local function PolestarEngine()
    local P = _G.Polestar
    local E = type(P) == "table" and P.Engine
    if type(E) == "table" then return E end
end

local function PolestarIsClassTrainer(npc)
    local E = PolestarEngine()
    if not (E and type(E.IsClassTrainer) == "function") then return false end
    local ok, yes = pcall(E.IsClassTrainer, npc)
    return ok and yes == true
end

-- { name, map, x, y, from = "polestar" | "visited" } or nil
local function NearestTrainer()
    local E = PolestarEngine()
    if E and type(E.NearestClassTrainer) == "function" then
        local ok, t = pcall(E.NearestClassTrainer, false)
        if ok and type(t) == "table" and type(t.map) == "number" and type(t.x) == "number" and type(t.y) == "number" then
            local name = type(t.npcName) == "string" and t.npcName or (type(t.npcEnglish) == "string" and t.npcEnglish) or "?"
            return { name = name, map = t.map, x = t.x, y = t.y, from = "polestar" }
        end
    end
    local last = charDB and charDB.lastTrainer
    if last and last.name then
        return { name = last.name, map = last.map, x = last.x, y = last.y, zone = last.zone, from = "visited" }
    end
end

local function TrainerPlace(t)
    if not t then return nil end
    local place = t.map and MapName(t.map) or t.zone or "?"
    if t.x and t.y then place = string.format("%s  %.1f, %.1f", place, t.x, t.y) end
    return place
end

---------------------------------------------------------------------------
-- The trainer window: every service, with the filters that hide some turned
-- on for the read and back after, kept for the class (race and faction)
---------------------------------------------------------------------------
local FILTERS = { "available", "unavailable" }
local scanning = false
local lastActive = 0
local lastScan

local function NpcID()
    if not UnitGUID then return nil end
    local guid = UnitGUID("npc")
    if type(guid) ~= "string" or Secret(guid) then return nil end
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

local function HerePosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos or not pos.GetXY then return map end
    local x, y = pos:GetXY()
    if not x or Secret(x) then return map end
    return map, x * 100, y * 100
end

local function ScanTrainer(active)
    if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceCost) then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    if C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType
        and C_Trainer.GetTrainerType() ~= Enum.TrainerType.General then return end
    local class = Me()
    local old = {}
    scanning = true
    if active and GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        lastActive = GetTime()
        for _, f in ipairs(FILTERS) do
            old[f] = GetTrainerServiceTypeFilter(f) and true or false
            if not old[f] then SetTrainerServiceTypeFilter(f, true) end
        end
    end
    local found, hits = {}, 0
    local all = DataSet(class)
    for i = 1, GetNumTrainerServices() do
        local _, kind, _, reqLevel = GetTrainerServiceInfo(i)
        if kind and kind ~= "header" then
            local id
            if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
                local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
                if ok and type(data) == "table" and type(data.id) == "number" then id = data.id end
            end
            if id then
                found[#found + 1] = { id = id, level = reqLevel, cost = GetTrainerServiceCost(i) }
                if all[id] then hits = hits + 1 end
            end
        end
    end
    for _, f in ipairs(FILTERS) do
        if old[f] == false then SetTrainerServiceTypeFilter(f, false) end
    end
    scanning = false

    local npc = NpcID()
    local isClass = hits > 0 or (npc and PolestarIsClassTrainer(npc)) or false
    local key = SeenKey()
    db.seen[key] = db.seen[key] or {}
    local spells, weapons = 0, 0
    for _, s in ipairs(found) do
        if WEAPON[s.id] then
            db.seenWeapons[s.id] = { c = s.cost, l = s.level }
            weapons = weapons + 1
        elseif isClass then
            db.seen[key][s.id] = { c = s.cost, l = s.level }
            spells = spells + 1
        end
    end
    if isClass then
        local name = UnitName("npc")
        if Secret(name) then name = nil end
        local map, x, y = HerePosition()
        charDB.lastTrainer = { name = name or "?", npc = npc, map = map, x = x, y = y, zone = GetZoneText(), at = time() }
    end
    lastScan = { all = #found, spells = spells, weapons = weapons, class = isClass }
    RequestRefresh()
end

---------------------------------------------------------------------------
-- Looks: ours (dark and flat), and the book's (its parchment and the game's
-- ink colors), for the spell book without EllesmereUI
---------------------------------------------------------------------------
local DARK = {
    text = TEXT, muted = MUTED, green = GREEN, red = RED, orange = ORANGE,
    strip = COLOR_LIST, stripEdge = { 0, 0, 0, 1 }, shadow = true, hl = { 1, 1, 1, 0.06 },
    rank = "999aa6", need = "ff6b5c", known = "66e673",
}
-- The book's own: its ink (SPELLBOOK_FONT_COLOR), its fonts by size, its
-- divider under a heading
local function BookInk()
    local c = _G.SPELLBOOK_FONT_COLOR
    if c and c.GetRGB then return { c:GetRGB() } end
    return { 0.18, 0.11, 0.04 }
end
local INK = BookInk()
local function Hex(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
-- Everything in the book's ink, as its spells' names and "Passive" are; in
-- its own fonts at its own sizes (24 a page's name, 16 a section, 14 a name,
-- 12 the rest)
local PAPER = {
    text = INK, muted = INK, green = { 0.06, 0.36, 0.03 },
    red = { 0.60, 0.05, 0.02 }, orange = { 0.55, 0.28, 0.0 }, accent = INK,
    strip = { 0, 0, 0, 0 }, stripEdge = { 0, 0, 0, 0 }, shadow = false,
    hl = { 0.35, 0.22, 0.08, 0.10 }, rank = Hex(INK), need = "8c1005", known = "0f5c08", paper = true,
    fonts = { [13] = "SystemFont_Huge2", [12] = "SystemFont_Large", [11] = "SystemFont_Med3",
              [10] = "SystemFont_Med1", [9] = "SystemFont_Med1" },
    divider = "spellbook-divider",
    rowH = 24, stripH = 64, iconSize = 18, indent = 4,
}

local function Ink(look)
    return look.accent or Accent()
end

-- A font string in the look: on parchment, the book's font for that size
local function LookFont(look, fs, size)
    local name = look.fonts and look.fonts[size]
    local obj = name and _G[name]
    if obj then fs:SetFontObject(obj) end
end

local function PText(look, parent, size, color)
    local fs = Text(parent, size, color)
    if not look.shadow then fs:SetShadowColor(0, 0, 0, 0) end
    LookFont(look, fs, size)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

-- The book's divider (its line under a category's name), along a frame's bottom
local function Divider(look, parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetAtlas(look.divider)
    t:SetHeight(11)
    t:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", -6, -4)
    t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 6, -4)
    return t
end

-- A button in the look: ours flat, the game's on parchment
local function LookButton(look, parent, width, height, label)
    if look.paper then
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(width, height)
        b:SetText(label)
        return b
    end
    local b = FlatButton(parent, width, label)
    b:SetHeight(height)
    return b
end

---------------------------------------------------------------------------
-- A page: the strip on top (the trainer, or a line about the masters), the
-- list in a scroll frame, a line at the bottom. The window has one, with its
-- two tabs; the spell book has one too when narrow, and two side by side
-- (Spells, Weapon masters) when it shows both its pages.
---------------------------------------------------------------------------
local pages = {}         -- every page, for the redraw

local function NewPage(parent, look, top)
    local P = { look = look, rows = {}, used = 0, y = 0, parent = parent }
    P.strip = CreateFrame("Frame", nil, parent)
    P.strip:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -top)
    P.strip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -top)
    P.strip:SetHeight(look.stripH or STRIP_H)
    local _, edge = Box(P.strip, look.strip)
    edge:SetColorTexture(look.stripEdge[1], look.stripEdge[2], look.stripEdge[3], look.stripEdge[4])
    P.label = PText(look, P.strip, 9, look.muted)
    P.label:SetPoint("TOPLEFT", P.strip, "TOPLEFT", look.indent or 8, -6)
    P.name = PText(look, P.strip, 12, look.text)
    P.name:SetPoint("TOPLEFT", P.label, "BOTTOMLEFT", 0, -3)
    P.place = PText(look, P.strip, 10, look.muted)
    P.place:SetPoint("TOPLEFT", P.name, "BOTTOMLEFT", 0, -2)
    if look.divider then Divider(look, P.strip) end
    P.pin = LookButton(look, P.strip, 70, 20, "Map pin")
    P.pin:SetPoint("RIGHT", P.strip, "RIGHT", -6, 0)
    P.pin:SetScript("OnClick", function()
        local t = P.trainer
        if t then Waypoint(t.map, t.x, t.y, t.name) end
    end)
    P.pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Map pin")
        GameTooltip:AddLine("A pin on the map at the trainer, and the game's arrow to it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    P.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    P.scroll = CreateFrame("ScrollFrame", nil, parent)
    P.scroll:SetPoint("TOPLEFT", P.strip, "BOTTOMLEFT", 0, -6)
    P.scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PAD - 14, PAD + 14)
    P.scroll:EnableMouseWheel(true)
    P.bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    P.bar:SetPoint("TOPLEFT", P.scroll, "TOPRIGHT", 4, -2)
    P.bar:SetPoint("BOTTOMLEFT", P.scroll, "BOTTOMRIGHT", 4, 2)
    P.bar:SetHideIfUnscrollable(true)
    ScrollUtil.InitScrollFrameWithScrollBar(P.scroll, P.bar)
    P.content = CreateFrame("Frame", nil, P.scroll)
    P.content:SetSize(200, 10)
    P.scroll:SetScrollChild(P.content)

    P.footer = PText(look, parent, 9, look.muted)
    P.footer:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", PAD + 2, PAD)
    P.footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, PAD)
    pages[#pages + 1] = P
    return P
end

-- The two tabs over a page: which page shows is get(), a click calls set
local function NewTabs(parent, look, y, get, set)
    local tabs = {}
    local x = PAD
    for _, spec in ipairs({ { "spells", "Spells" }, { "weapons", "Weapon masters" } }) do
        local tab = CreateFrame("Button", nil, parent)
        tab:SetHeight(TABS_H - 2)
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        tab.wash = tab:CreateTexture(nil, "BACKGROUND")
        tab.wash:SetAllPoints(tab)
        tab.bar = tab:CreateTexture(nil, "BORDER")
        tab.bar:SetHeight(2)
        tab.bar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.bar:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        tab.word = PText(look, tab, 11, look.text)
        tab.word:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.word:SetText(spec[2])
        tab:SetWidth(math.ceil(tab.word:GetStringWidth()) + 28)
        tab.key = spec[1]
        tab:SetScript("OnClick", function(self) set(self.key) end)
        tab:SetScript("OnEnter", function(self) self.hot = true self:Paint() end)
        tab:SetScript("OnLeave", function(self) self.hot = nil self:Paint() end)
        function tab:Paint()
            local c = Ink(look)
            local on = get() == self.key
            self.wash:SetColorTexture(c[1], c[2], c[3], on and 0.18 or (self.hot and 0.07 or 0))
            self.bar:SetColorTexture(c[1], c[2], c[3], on and 1 or 0)
            local t = look.text
            if look.paper then
                self.word:SetTextColor(t[1], t[2], t[3], (on or self.hot) and 1 or 0.7)
            elseif on or self.hot then
                self.word:SetTextColor(1, 1, 1)
            else
                self.word:SetTextColor(t[1] * 0.75, t[2] * 0.75, t[3] * 0.78)
            end
        end
        tabs[#tabs + 1] = tab
        x = x + tab:GetWidth() + 2
    end
    tabs.rule = parent:CreateTexture(nil, "ARTWORK")
    tabs.rule:SetHeight(1)
    tabs.rule:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -(y + TABS_H - 2))
    tabs.rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -(y + TABS_H - 2))
    function tabs:Paint()
        for _, tab in ipairs(self) do tab:Paint() end
        local c = Ink(look)
        self.rule:SetColorTexture(c[1], c[2], c[3], 0.25)
    end
    return tabs
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "ForeverUITrainerFrame", UIParent)
frame:SetSize(DEFAULT_W, DEFAULT_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
frame:SetFrameStrata("MEDIUM")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
frame:EnableMouse(true)
frame:Hide()
local windowFill = Box(frame, COLOR_WINDOW)

local function SetEscape(on)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == frame:GetName() then table.remove(UISpecialFrames, i) end
    end
    if on then tinsert(UISpecialFrames, frame:GetName()) end
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then db.point = { point, relPoint, x, y } end
    db.width = math.floor(frame:GetWidth() + 0.5)
    db.height = math.floor(frame:GetHeight() + 0.5)
end

local function Place()
    frame:ClearAllPoints()
    local p = db.point
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    frame:SetScale(db.scale or 1)
    frame:SetWidth(math.min(MAX_W, math.max(MIN_W, db.width or DEFAULT_W)))
    frame:SetHeight(math.min(MAX_H, math.max(MIN_H, db.height or DEFAULT_H)))
end

-- The title bar moves it
local titleBar = CreateFrame("Frame", nil, frame)
titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0)
titleBar:SetHeight(TOP_H)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function()
    if db and db.locked then return end
    frame:StartMoving()
    frame.moving = true
end)
titleBar:SetScript("OnDragStop", function()
    if not frame.moving then return end
    frame.moving = nil
    frame:StopMovingOrSizing()
    SavePosition()
end)

local titleIcon = frame:CreateTexture(nil, "ARTWORK")
titleIcon:SetSize(16, 16)
titleIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 2, -6)
titleIcon:SetTexture(ICON_FILE)
titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local title = Text(frame, 13, Accent())
title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
title:SetText("Trainer")
local whoText = Text(frame, 10, MUTED)
whoText:SetPoint("RIGHT", frame, "TOPRIGHT", -32, -14)
whoText:SetJustifyH("RIGHT")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
close:SetScript("OnClick", function() frame:Hide() end)

local ShowTab            -- (below)
local windowTabs = NewTabs(frame, DARK, TOP_H, function() return db and db.tab end, function(key) ShowTab(key) end)
local mainPage = NewPage(frame, DARK, TOP_H + TABS_H + 6)

local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture(GRIP .. "Up")
grip:SetHighlightTexture(GRIP .. "Highlight")
grip:SetPushedTexture(GRIP .. "Down")
grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    SavePosition()
    RequestRefresh()
end)

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function RowTooltip(row)
    local e, w = row.entry, row.weapon
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if e then
        GameTooltip:SetSpellByID(e.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Level", tostring(e.level), MUTED[1], MUTED[2], MUTED[3], 1, 1, 1)
        GameTooltip:AddDoubleLine(e.priced and "Price at the trainer" or "Base price", Money(e.cost), MUTED[1], MUTED[2], MUTED[3], 1, 1, 1)
        if e.needs then
            GameTooltip:AddLine((e.talentMissing and "Needs the talent " or "Needs ") .. SpellName(e.needs) .. " first.", RED[1], RED[2], RED[3], true)
        end
        if e.skill then
            GameTooltip:AddLine(string.format("Needs %d in the skill (Poisons).", e.skill[2]), ORANGE[1], ORANGE[2], ORANGE[3], true)
        end
        if e.fromBook then GameTooltip:AddLine("From the spell book (its price shows at the trainer).", MUTED[1], MUTED[2], MUTED[3], true) end
        if e.fromTrainer then GameTooltip:AddLine("Seen at a trainer.", MUTED[1], MUTED[2], MUTED[3], true) end
        GameTooltip:AddLine("Shift-click: put its link in the chat.", 0.7, 0.7, 0.7)
    elseif w then
        GameTooltip:SetSpellByID(w.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("From level", tostring(WeaponLevel(w)), MUTED[1], MUTED[2], MUTED[3], 1, 1, 1)
        GameTooltip:AddDoubleLine(db.seenWeapons[w.id] and "Price at the master" or "Base price", Money(WeaponCost(w)), MUTED[1], MUTED[2], MUTED[3], 1, 1, 1)
    end
    GameTooltip:Show()
end

local function Row(P)
    local look = P.look
    P.used = P.used + 1
    local row = P.rows[P.used]
    if not row then
        row = CreateFrame("Button", nil, P.content)
        row:SetHeight(look.rowH or ROW_H)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints(row)
        row.hl:SetColorTexture(look.hl[1], look.hl[2], look.hl[3], look.hl[4])
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetHeight(1)
        row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(look.iconSize or ICON_SIZE, look.iconSize or ICON_SIZE)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = PText(look, row, 11, look.text)
        row.cost = PText(look, row, 10, look.text)
        row.cost:SetJustifyH("RIGHT")
        row.cost:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.level = PText(look, row, 10, look.muted)
        row.level:SetJustifyH("RIGHT")
        row.level:SetWidth(54)
        row.pin = LookButton(look, row, 64, 18, "Map pin")
        row.pin:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.pin:SetScript("OnClick", function(self)
            local m = self:GetParent().master
            if m then Waypoint(m.map, m.x, m.y, m.name) end
        end)
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnEnter", function(self)
            if self.entry or self.weapon then RowTooltip(self) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local id = self.entry and self.entry.id or (self.weapon and self.weapon.id)
            if id and IsModifiedClick("CHATLINK") and C_Spell and C_Spell.GetSpellLink then
                InsertLink(C_Spell.GetSpellLink(id))
            end
        end)
        if look.divider then
            row.div = Divider(look, row)
            row.div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -6, -2)
            row.div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 6, -2)
        end
        P.rows[P.used] = row
    end
    row.entry, row.weapon, row.master = nil, nil, nil
    row:EnableMouse(true)
    row.icon:Hide()
    row.pin:Hide()
    row.line:Hide()
    if row.div then row.div:Hide() end
    LookFont(look, row.name, 11)
    row.cost:SetText("")
    row.level:SetText("")
    row.name:ClearAllPoints()
    row.name:SetTextColor(look.text[1], look.text[2], look.text[3])
    row.cost:SetTextColor(look.text[1], look.text[2], look.text[3])
    row.level:SetTextColor(look.muted[1], look.muted[2], look.muted[3])
    row:Show()
    return row
end

local function Put(P, row, height)
    height = height or P.look.rowH or ROW_H
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", P.content, "TOPLEFT", 0, -P.y)
    row:SetPoint("TOPRIGHT", P.content, "TOPRIGHT", 0, -P.y)
    P.y = P.y + height
end

-- A header: words in the look's color on the left, a sum on the right
-- (on parchment as the book names its categories: its larger font, the words
-- as they are, its divider under them)
local function Header(P, text, right, first)
    local paper = P.look.paper
    if not first then P.y = P.y + (paper and 10 or 6) end
    local row = Row(P)
    local c = Ink(P.look)
    row:EnableMouse(false)
    row.name:SetPoint("LEFT", row, "LEFT", paper and 4 or 2, paper and 2 or 0)
    row.name:SetPoint("RIGHT", row.cost, "LEFT", -6, paper and 2 or 0)
    row.name:SetTextColor(c[1], c[2], c[3])
    row.cost:SetText(right or "")
    row.cost:SetTextColor(P.look.muted[1], P.look.muted[2], P.look.muted[3])
    if paper then
        LookFont(P.look, row.name, 12)
        row.name:SetText(text)
        row.div:Show()
        Put(P, row, P.look.rowH + 10)
    else
        row.name:SetText(string.upper(text))
        row.line:Show()
        row.line:SetColorTexture(c[1], c[2], c[3], 0.25)
        Put(P, row)
    end
end

local function Note(P, text, color)
    local row = Row(P)
    row:EnableMouse(false)
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetText(text)
    color = color or P.look.muted
    row.name:SetTextColor(color[1], color[2], color[3])
    Put(P, row)
end

local function SpellRow(P, e, money)
    local look = P.look
    local row = Row(P)
    row.entry = e
    row.icon:SetTexture(SpellIcon(e.id))
    row.icon:Show()
    row.level:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    row.level:SetText("Lvl " .. e.level)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
    local rank = SpellRank(e.id)
    local text = SpellName(e.id)
    if rank then text = text .. "  |cff" .. look.rank .. rank .. "|r" end
    if e.needs then text = text .. "  |cff" .. look.need .. "(needs " .. SpellName(e.needs) .. ")|r" end
    row.name:SetText(text)
    row.cost:SetText(e.cost and Money(e.cost) or "?")
    if e.cost and money and e.cost > money then row.cost:SetTextColor(look.red[1], look.red[2], look.red[3]) end
    Put(P, row)
end

local function MasterRow(P, m)
    local row = Row(P)
    row.master = m
    row:EnableMouse(false)
    row.pin:Show()
    row.pin:EnableMouse(true)
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.pin, "LEFT", -6, 0)
    row.name:SetText(string.format("%s  |cff%s%.1f, %.1f|r", m.name, P.look.rank, m.x, m.y))
    Put(P, row, (P.look.rowH or ROW_H) + 2)
end

local function WeaponRow(P, w, class, level, money)
    local look = P.look
    local row = Row(P)
    row.weapon = w
    row.icon:SetTexture(SpellIcon(w.id))
    row.icon:Show()
    row.level:SetPoint("RIGHT", row, "RIGHT", -84, 0)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(w.id) or w.name
    local need = WeaponLevel(w)
    local cost = WeaponCost(w)
    if WeaponKnown(w.id) then
        row.name:SetText(name .. "  |cff" .. look.known .. "Known|r")
        row.name:SetTextColor(look.muted[1], look.muted[2], look.muted[3])
        row.level:SetText("")
        row.cost:SetText("")
    elseif not ClassWeapon(w, class) then
        row.name:SetText(name .. "  |cff" .. look.rank .. "not for your class|r")
        row.name:SetTextColor(look.muted[1], look.muted[2], look.muted[3])
        row.level:SetText("Lvl " .. need)
        row.cost:SetText(Money(cost))
        row.cost:SetTextColor(look.muted[1], look.muted[2], look.muted[3])
    else
        row.name:SetText(name)
        row.level:SetText("Lvl " .. need)
        local c = need > level and look.red or look.green
        row.level:SetTextColor(c[1], c[2], c[3])
        row.cost:SetText(Money(cost))
        if money and cost > money then row.cost:SetTextColor(look.red[1], look.red[2], look.red[3]) end
    end
    Put(P, row)
end

---------------------------------------------------------------------------
-- Drawing the pages
---------------------------------------------------------------------------
-- The small line on top of the strip: in capitals ours, as written on parchment
local function Label(P, text)
    P.label:SetText(P.look.paper and text or string.upper(text))
end

local function DrawSpells(P, m)
    local money = GetMoney()
    local t = NearestTrainer()
    P.trainer = t
    Label(P, t and (t.from == "polestar" and "Nearest class trainer (Polestar)" or "Last class trainer you visited") or "Class trainer")
    if t then
        P.name:SetText(t.name)
        P.place:SetText(TrainerPlace(t))
        P.pin:SetShown(t.map and t.x and true or false)
    else
        P.name:SetText("Not known yet")
        P.place:SetText("Polestar finds it, or open a class trainer once.")
        P.pin:Hide()
    end

    local unpriced = m.unpriced > 0 and string.format(" + %d ?", m.unpriced) or ""
    Header(P, "Train now", #m.now > 0 and (Money(m.cost) .. unpriced) or nil, true)
    if #m.now == 0 then
        Note(P, m.nextLevel and string.format("Nothing to train now. Next at level %d.", m.nextLevel) or "Nothing to train now.")
    end
    for _, e in ipairs(m.now) do SpellRow(P, e, money) end
    if #m.now > 0 and m.cost > money then
        Note(P, string.format("You have %s: %s short.", Money(money), Money(m.cost - money)), P.look.red)
    end
    if #m.missing > 0 then
        Header(P, "Needs something first")
        for _, e in ipairs(m.missing) do SpellRow(P, e, money) end
    end
    for _, lvl in ipairs(m.levelOrder) do
        local sum = 0
        for _, e in ipairs(m.levels[lvl]) do sum = sum + (e.cost or 0) end
        Header(P, "Level " .. lvl, Money(sum))
        for _, e in ipairs(m.levels[lvl]) do SpellRow(P, e, money) end
    end
    if #m.levelOrder == 0 and m.nextLevel and #m.now > 0 then
        Note(P, string.format("Next at level %d.", m.nextLevel))
    end
    local priced = next(db.seen[SeenKey()] or {}) ~= nil
    P.footer:SetText(priced and "Prices as your class trainer showed them. Shift-click a spell: its link in the chat."
        or "Base prices until you open a class trainer once. Shift-click a spell: its link in the chat.")
end

local function DrawWeapons(P)
    local class, _, faction, level = Me()
    local money = GetMoney()
    local cities, learnable, known = BuildWeapons()
    P.trainer = nil
    P.pin:Hide()
    Label(P, (faction or "") .. " capitals' weapon masters")
    P.name:SetText(string.format("Your class can learn %d more weapons (%d known).", learnable, known))
    -- the weapons that need a level, from the data or what a master showed
    local later = {}
    for _, w in ipairs(T.WEAPONS or {}) do
        if ClassWeapon(w, class) and WeaponLevel(w) > 1 then
            later[#later + 1] = string.format("%s from %d", C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(w.id) or w.name, WeaponLevel(w))
        end
    end
    P.place:SetText("From level 1" .. (#later > 0 and (", " .. table.concat(later, ", ")) or "") .. ". A pin shows the way.")
    local first = true
    for _, city in ipairs(cities) do
        Header(P, city.name, nil, first)
        first = false
        for _, entry in ipairs(city.masters) do
            MasterRow(P, entry.master)
            if #entry.weapons == 0 then Note(P, "Nothing new for you here.") end
            for _, w in ipairs(entry.weapons) do WeaponRow(P, w, class, level, money) end
        end
    end
    if first then Note(P, "No weapon masters known for your faction.") end
    P.footer:SetText(next(db.seenWeapons) and "Prices as the masters showed them." or "Base prices until you open a weapon master once.")
end

local function DrawPage(P, kind, m)
    P.used, P.y = 0, 0
    P.content:SetWidth(math.max(100, P.scroll:GetWidth()))
    -- the strip's words stop short of its pin button
    local wide = math.max(60, P.strip:GetWidth() - 92)
    P.label:SetWidth(wide)
    P.name:SetWidth(wide)
    P.place:SetWidth(wide)
    if kind == "weapons" then DrawWeapons(P) else DrawSpells(P, m) end
    for i = P.used + 1, #P.rows do P.rows[i]:Hide() end
    P.content:SetHeight(math.max(10, P.y + 4))
end

---------------------------------------------------------------------------
-- In the spell book (Spellbook.lua lays the ground over its pages and calls
-- these): when the book shows both its pages, Spells on the left one and
-- Weapon masters on the right, as the quest log's two pages; on one page,
-- the two behind tabs. Without EllesmereUI, in the book's own look.
---------------------------------------------------------------------------
local book               -- { frame, look, wide, one, left, right, tabs, heads }

function T.BookLook()
    return Loaded("EllesmereUI") and "dark" or "paper"
end

-- A page's name on top: on parchment as the book names a category (its
-- large font, its divider under it)
local function BookHeading(parent, look, text)
    local h = PText(look, parent, 13, Ink(look))
    h:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + (look.indent or 2), look.paper and -10 or -8)
    h:SetText(text)
    local who = PText(look, parent, 10, look.muted)
    who:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD - 2, look.paper and -18 or -10)
    who:SetJustifyH("RIGHT")
    if look.divider then
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetAtlas(look.divider)
        line:SetHeight(11)
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD - 6, -38)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD + 6, -38)
    end
    return h, who
end

local function MakeBook(holder)
    local look = T.BookLook() == "paper" and PAPER or DARK
    book = { look = look, heads = {} }
    -- (placed and sized by T.FitBook, from the book's own pages: anchored only
    -- to the ground, it never got a size)
    book.frame = CreateFrame("Frame", nil, holder)
    book.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    book.frame:SetSize(holder:GetWidth() > 1 and holder:GetWidth() or 500, holder:GetHeight() > 1 and holder:GetHeight() or 600)
    book.frame:SetFrameLevel(holder:GetFrameLevel() + 2)
    -- both pages
    book.leftHolder = CreateFrame("Frame", nil, book.frame)
    book.leftHolder:SetPoint("TOPLEFT", book.frame, "TOPLEFT", 0, 0)
    book.leftHolder:SetPoint("BOTTOMRIGHT", book.frame, "BOTTOM", -10, 0)
    book.rightHolder = CreateFrame("Frame", nil, book.frame)
    book.rightHolder:SetPoint("TOPLEFT", book.frame, "TOP", 10, 0)
    book.rightHolder:SetPoint("BOTTOMRIGHT", book.frame, "BOTTOMRIGHT", 0, 0)
    local _, lw = BookHeading(book.leftHolder, look, "Spells")
    local _, rw = BookHeading(book.rightHolder, look, "Weapon masters")
    rw:Hide()
    book.heads = { lw }
    local top = look.paper and 54 or 32
    book.left = NewPage(book.leftHolder, look, top)
    book.right = NewPage(book.rightHolder, look, top)
    -- one page
    book.oneHolder = CreateFrame("Frame", nil, book.frame)
    book.oneHolder:SetPoint("TOPLEFT", book.frame, "TOPLEFT", 0, 0)
    book.oneHolder:SetPoint("BOTTOMRIGHT", book.frame, "BOTTOMRIGHT", 0, 0)
    local _, ow = BookHeading(book.oneHolder, look, "Trainer")
    book.heads[2] = ow
    book.tabs = NewTabs(book.oneHolder, look, top - 2, function() return db and db.bookPage or "spells" end, function(key)
        db.bookPage = key
        book.one.scroll:SetVerticalScroll(0)
        RequestRefresh()
    end)
    book.one = NewPage(book.oneHolder, look, top - 2 + TABS_H + 6)
    book.frame:SetScript("OnSizeChanged", function() T.LayoutBook() end)
    book.made = true
end

function T.LayoutBook()
    if not (book and book.made) then return end
    book.wide = book.frame:GetWidth() >= 2 * MIN_W + 20
    book.leftHolder:SetShown(book.wide)
    book.rightHolder:SetShown(book.wide)
    book.oneHolder:SetShown(not book.wide)
    RequestRefresh()
end

function T.ShowBook(holder)
    if not db then error("its settings are not loaded yet") end
    if not book then MakeBook(holder) end
    book.frame:SetFrameLevel(holder:GetFrameLevel() + 2)
    ScanBook()
    book.frame:Show()
    T.LayoutBook()
end

-- For /ftr book: the list over the book's pages
function T.BookList()
    if not book then return "list: not made yet" end
    local w, h = book.frame:GetSize()
    return string.format("list: %s look, %s, shown %s, visible %s, %dx%d, level %d, rows %d / %d / %d",
        book.look.paper and "parchment" or "dark", book.wide and "two pages" or "one page",
        tostring(book.frame:IsShown()), tostring(book.frame:IsVisible()), w or 0, h or 0, book.frame:GetFrameLevel(),
        book.left.used, book.right.used, book.one.used)
end

-- Where the list goes and how big, from the book's pages (paged): the whole
-- of it under the book's tabs (top), and each page of ours over one of the
-- book's own two views, where its spells stand (View1 on the left page,
-- View2 on the right), so ours start and end where its spells do. Sizes are
-- given outright: anchored only, the list never got one.
local function Over(holder, view, fallbackW, fallbackH)
    if not holder then return false end
    holder:ClearAllPoints()
    local w, h = view and view:GetWidth(), view and view:GetHeight()
    if view and w and h and w > 1 and h > 1 then
        holder:SetPoint("TOPLEFT", view, "TOPLEFT", -6, 6)
        holder:SetSize(w + 12, h)
        return true
    end
    holder:SetPoint("TOPLEFT", book.frame, "TOPLEFT", 0, 0)
    holder:SetSize(fallbackW, fallbackH)
    return false
end

function T.FitBook(paged, top)
    -- (asking a size can lay the book out at once, and call this before the list is made)
    if not (book and book.made) then return end
    local pw, ph = paged:GetWidth(), paged:GetHeight()
    local w, h = math.max(1, pw - 16), math.max(1, ph - top - 8)
    book.frame:ClearAllPoints()
    book.frame:SetPoint("TOPLEFT", paged, "TOPLEFT", 8, -top)
    book.frame:SetSize(w, h)
    book.wide = w >= 2 * MIN_W + 20
    local v1, v2 = paged.View1, paged.View2
    if book.wide then
        if not Over(book.leftHolder, v1, w / 2 - 10, h) or not Over(book.rightHolder, v2, w / 2 - 10, h) then
            book.leftHolder:ClearAllPoints()
            book.leftHolder:SetPoint("TOPLEFT", book.frame, "TOPLEFT", 0, 0)
            book.leftHolder:SetSize(w / 2 - 10, h)
            book.rightHolder:ClearAllPoints()
            book.rightHolder:SetPoint("TOPRIGHT", book.frame, "TOPRIGHT", 0, 0)
            book.rightHolder:SetSize(w / 2 - 10, h)
        end
    else
        Over(book.oneHolder, v1, w, h)
    end
    T.LayoutBook()
end

function T.HideBook()
    if book then book.frame:Hide() end
end

local function Redraw()
    if not db then return end
    local m = BuildModel()
    local class, _, _, level = Me()
    local who = string.format("%s %d", UnitClass("player") or class or "", level)
    if frame:IsShown() then
        whoText:SetText(who)
        title:SetTextColor(unpack(Accent()))
        DrawPage(mainPage, db.tab, m)
        windowTabs:Paint()
    end
    if book and book.frame:IsVisible() then
        local ok, err = pcall(function()
            for _, fs in ipairs(book.heads) do fs:SetText(who) end
            if book.wide then
                DrawPage(book.left, "spells", m)
                DrawPage(book.right, "weapons", m)
            else
                DrawPage(book.one, db.bookPage or "spells", m)
                book.tabs:Paint()
            end
        end)
        if not ok and T.Report then T.Report("drawing", err) end
    end
end

function ShowTab(key)
    db.tab = key == "weapons" and "weapons" or "spells"
    mainPage.scroll:SetVerticalScroll(0)
    Redraw()
end

---------------------------------------------------------------------------
-- Refreshing: once a frame at most, the count on the button too
---------------------------------------------------------------------------
local pending = false
local UpdateBadge        -- (below)

function RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        if not db then return end
        if frame:IsShown() or (book and book.frame:IsVisible()) then Redraw() else BuildModel() end
        UpdateBadge()
    end)
end

local PlaceNotice        -- (below)

local function Apply()
    if not db then return end
    windowFill:SetColorTexture(COLOR_WINDOW[1], COLOR_WINDOW[2], COLOR_WINDOW[3], db.alpha or COLOR_WINDOW[4])
    frame:SetFrameStrata(db.strata or "MEDIUM")
    SetEscape(db.escape)
    grip:SetShown(not db.locked)
    Place()
    if PlaceNotice then PlaceNotice() end
    if T.BookApply then T.BookApply() end
    RequestRefresh()
end

local function Open(tab)
    if not db then return end
    if tab then db.tab = tab end
    if not frame:IsShown() then
        ScanBook()
        frame:Show()
    end
    ShowTab(db.tab)
end

local function Toggle()
    if frame:IsShown() then frame:Hide() else Open() end
end

-- A few words for ForeverUI's menu: how many to train now
function ForeverUITrainer_Summary()
    if not db then return nil end
    local n = #model.now
    if n > 0 then return string.format("%d to train", n), GREEN end
    if model.nextLevel then return string.format("next at %d", model.nextLevel) end
end

frame:SetScript("OnShow", function()
    if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
end)
frame:SetScript("OnHide", function()
    if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
end)
frame:SetScript("OnSizeChanged", function() if db then RequestRefresh() end end)

function ForeverUITrainer_Toggle() Toggle() end
function ForeverUITrainer_Open(tab) Open(tab) end
function ForeverUITrainer_OnAddonCompartmentClick() Toggle() end

---------------------------------------------------------------------------
-- The notice at a level up
---------------------------------------------------------------------------
local notice = CreateFrame("Button", "ForeverUITrainerNotice", UIParent)
notice:SetSize(320, 44)
notice:SetPoint("TOP", UIParent, "TOP", 0, -150)
notice:SetFrameStrata("HIGH")
notice:Hide()
local _, noticeEdge = Box(notice, COLOR_WINDOW)
local noticeIcon = notice:CreateTexture(nil, "ARTWORK")
noticeIcon:SetSize(28, 28)
noticeIcon:SetPoint("LEFT", notice, "LEFT", 8, 0)
noticeIcon:SetTexture(ICON_FILE)
noticeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local noticeTitle = Text(notice, 12, TEXT)
noticeTitle:SetPoint("TOPLEFT", noticeIcon, "TOPRIGHT", 8, -1)
noticeTitle:SetWidth(320 - 8 - 28 - 8 - 8)
local noticeLine = Text(notice, 10, MUTED)
noticeLine:SetPoint("BOTTOMLEFT", noticeIcon, "BOTTOMRIGHT", 8, 1)
noticeLine:SetWidth(320 - 8 - 28 - 8 - 8)
local fade = notice:CreateAnimationGroup()
local fadeOut = fade:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(1.2)
fadeOut:SetStartDelay(8)
fade:SetScript("OnFinished", function() notice:Hide() end)
notice:RegisterForClicks("LeftButtonUp", "RightButtonUp")
notice:SetScript("OnClick", function(_, mouse)
    fade:Stop()
    notice:Hide()
    if mouse ~= "RightButton" then Open("spells") end
end)
notice:SetScript("OnEnter", function() fade:Stop() notice:SetAlpha(1) end)
notice:SetScript("OnLeave", function() fade:Play() end)

-- still: no fade (Move UI shows it to move it)
local function ShowNotice(line1, line2, still)
    local c = Accent()
    noticeEdge:SetColorTexture(c[1], c[2], c[3], 1)
    noticeTitle:SetText(line1)
    noticeTitle:SetTextColor(c[1], c[2], c[3])
    noticeLine:SetText(line2 or "")
    fade:Stop()
    notice:SetAlpha(1)
    notice:Show()
    if not still then fade:Play() end
end

function PlaceNotice()
    notice:ClearAllPoints()
    local p = db and db.noticePoint
    if p then
        notice:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        notice:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
end

local function LevelNews(level, test)
    local m = BuildModel()
    local new = 0
    for _, e in ipairs(m.now) do
        if e.level == level then new = new + 1 end
    end
    if new == 0 and not test then return end
    local t = NearestTrainer()
    local where = t and (t.name .. ", " .. (t.map and MapName(t.map) or t.zone or "?")) or nil
    local head
    if new > 0 then
        head = string.format("Level %d: %d new spell%s to train", level, new, new == 1 and "" or "s")
    else
        head = string.format("Level %d: nothing new to train", level)
    end
    local sum = #m.now > 0 and string.format("%d in all, %s", #m.now, Money(m.cost)) or nil
    if db.chat or test then
        Print(head .. (sum and (" (" .. sum .. ")") or "") .. (where and (" at " .. where) or "") .. ".")
    end
    if db.notice or test then
        ShowNotice(head, (sum and (sum .. (where and ("  |  " .. where) or ""))) or where or "Click: the trainer window")
    end
end

---------------------------------------------------------------------------
-- The minimap button: the book in a flat square, the count of spells to
-- train in its corner. In EllesmereUI Minimap's list of addon buttons with
-- ForeverUI's F (a named child button of the minimap, 24 wide, made as this
-- addon loads), or a square of its own under the F. ForeverUI's General page
-- picks the place for both.
---------------------------------------------------------------------------
local mapMode, mapHolder, mapButton, mapEdge, badge

local function MapPlace()
    local fdb = _G.ForeverUIDB
    local place = type(fdb) == "table" and fdb.mapButtonPlace
    if place == "own" or place == "ellesmere" then return place end
    return Loaded("EllesmereUIMinimap") and "ellesmere" or "own"
end

-- On the minimap's edge, at an angle round its middle: ForeverUI's own rule
-- when it is there (round or square minimap), a circle otherwise
local function EdgePoint(angle, size)
    if ForeverUI_MinimapEdge then return ForeverUI_MinimapEdge(angle, size) end
    local a = math.rad(angle)
    local r = Minimap:GetWidth() / 2 + math.floor(size / 2) - 6
    return math.cos(a) * r, math.sin(a) * r
end

local function CursorAngle()
    if ForeverUI_MinimapCursorAngle then return ForeverUI_MinimapCursorAngle() end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(cy / s - my, cx / s - mx))
end

local function ApplyMapButton()
    if not mapButton or not db then return end
    if mapMode == "own" then
        mapHolder:ClearAllPoints()
        local x, y = EdgePoint(db.mapAngle or 200, 18)
        mapHolder:SetPoint("CENTER", Minimap, "CENTER", x, y)
        mapHolder:SetShown(db.mapButton ~= false)
    end
    local size = math.floor(math.min(mapButton:GetWidth(), mapButton:GetHeight()) * 0.5 + 0.5)
    local ok = pcall(badge.SetFont, badge, FontPath(), math.max(8, size), "OUTLINE")
    if not ok or not badge:GetFont() then badge:SetFont(STANDARD_TEXT_FONT, math.max(8, size), "OUTLINE") end
end

function UpdateBadge()
    if not badge or not db then return end
    local n = #model.now
    badge:SetText(n > 0 and tostring(n) or "")
    badge:SetShown(db.badge and n > 0)
end

local function MakeMapButton()
    if mapButton or not Minimap then return end
    mapMode = MapPlace()
    if mapMode == "ellesmere" then
        mapButton = CreateFrame("Button", "ForeverUITrainerMinimapButton", Minimap)
        mapButton:SetSize(24, 24)
        mapButton:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        mapButton:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -5, -4)
    else
        mapHolder = CreateFrame("Frame", "ForeverUITrainerMapButtonHolder", Minimap)
        mapHolder:SetSize(18, 18)
        mapHolder:SetFrameStrata("MEDIUM")
        mapHolder:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        if mapHolder.SetDontSavePosition then mapHolder:SetDontSavePosition(true) end
        mapButton = CreateFrame("Button", "ForeverUITrainerMinimapButton", mapHolder)
        mapButton:SetAllPoints(mapHolder)
        mapButton:RegisterForDrag("LeftButton")
        -- dragged, it slides round the minimap's edge after the mouse
        mapButton:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                db.mapAngle = CursorAngle()
                ApplyMapButton()
            end)
        end)
        mapButton:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            ApplyMapButton()
        end)
    end
    mapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- round on the minimap's edge, as ForeverUI's F; square in EllesmereUI's list
    local round = mapMode == "own"
    local out = round and 2 or 1
    mapEdge = mapButton:CreateTexture(nil, "BACKGROUND", nil, -8)
    mapEdge:SetPoint("TOPLEFT", mapButton, "TOPLEFT", -out, out)
    mapEdge:SetPoint("BOTTOMRIGHT", mapButton, "BOTTOMRIGHT", out, -out)
    mapEdge:SetColorTexture(0, 0, 0, 1)
    local ground = mapButton:CreateTexture(nil, "BACKGROUND", nil, -7)
    ground:SetAllPoints(mapButton)
    ground:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    local icon = mapButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", mapButton, "TOPLEFT", round and 1 or 2, round and -1 or -2)
    icon:SetPoint("BOTTOMRIGHT", mapButton, "BOTTOMRIGHT", round and -1 or -2, round and 1 or 2)
    icon:SetTexture(ICON_FILE)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    if round then
        local cut = ForeverUI_Round or function(owner, ...)
            for i = 1, select("#", ...) do
                local tex = select(i, ...)
                local mask = owner:CreateMaskTexture()
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(tex)
                tex:AddMaskTexture(mask)
            end
        end
        cut(mapButton, mapEdge, ground, icon)
    end
    badge = mapButton:CreateFontString(nil, "OVERLAY")
    badge:SetPoint("BOTTOMRIGHT", mapButton, "BOTTOMRIGHT", 1, -1)
    badge:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    badge:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    mapButton:SetScript("OnSizeChanged", ApplyMapButton)
    mapButton:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" and ForeverUI_OpenOptions then
            ForeverUI_OpenOptions("trainer")
        else
            Toggle()
        end
    end)
    mapButton:SetScript("OnEnter", function(self)
        local c = Accent()
        mapEdge:SetColorTexture(c[1], c[2], c[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("ForeverUI Trainer", c[1], c[2], c[3])
        local m = model
        if #m.now > 0 then
            GameTooltip:AddLine(string.format("%d to train now: %s", #m.now, Money(m.cost)), 1, 1, 1)
        elseif m.nextLevel then
            GameTooltip:AddLine(string.format("Nothing to train now. Next at level %d.", m.nextLevel), 1, 1, 1)
        end
        GameTooltip:AddLine("Click: the trainer window", 0.8, 0.8, 0.8)
        if ForeverUI_OpenOptions then GameTooltip:AddLine("Right click: its options", 0.8, 0.8, 0.8) end
        if mapMode == "own" then GameTooltip:AddLine("Drag: slide it round the minimap", 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    mapButton:SetScript("OnLeave", function()
        mapEdge:SetColorTexture(0, 0, 0, 1)
        GameTooltip:Hide()
    end)
    ApplyMapButton()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("TRAINER_UPDATE")

local bookPending = false
local function BookLater()
    if bookPending then return end
    bookPending = true
    C_Timer.After(0.3, function()
        bookPending = false
        ScanBook()
        RequestRefresh()
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        ForeverUITrainerDB = ForeverUITrainerDB or {}
        ForeverUITrainerCharDB = ForeverUITrainerCharDB or {}
        db, charDB = ForeverUITrainerDB, ForeverUITrainerCharDB
        T.db = db
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        db.seen = db.seen or {}
        db.seenWeapons = db.seenWeapons or {}
        if db.ownButton then MakeMapButton() end
        Apply()
    elseif not db then
        return
    elseif event == "PLAYER_LOGIN" then
        BookLater()
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        BookLater()
    elseif event == "PLAYER_LEVEL_UP" then
        local level = ...
        levelNow = level
        C_Timer.After(1.5, function()
            ScanBook()
            LevelNews(level)
            RequestRefresh()
        end)
    elseif event == "TRAINER_SHOW" then
        C_Timer.After(0.1, function() ScanTrainer(true) end)
    elseif event == "TRAINER_UPDATE" then
        -- (the filters ScanTrainer turns on and off send this too: those are left alone)
        if scanning or GetTime() - lastActive < 1 then return end
        C_Timer.After(0.2, function() ScanTrainer(false) end)
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        if frame:IsShown() then RequestRefresh() end
    else
        RequestRefresh()
    end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
SLASH_FOREVERUITRAINER1 = "/ftr"
SLASH_FOREVERUITRAINER2 = "/forevertrainer"
SlashCmdList.FOREVERUITRAINER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if not db then return end
    if cmd == "" then
        Toggle()
    elseif cmd == "weapons" then
        Open("weapons")
    elseif cmd == "reset" then
        db.point, db.width, db.height, db.scale = nil, DEFAULT_W, DEFAULT_H, 1
        Place()
        RequestRefresh()
        Print("Place, size and scale are back to the start.")
    elseif cmd == "notice" then
        LevelNews(select(4, Me()), true)
    elseif cmd == "info" then
        ScanBook()
        local class = Me()
        local m = BuildModel()
        local data = 0
        for _, list in pairs(T.SPELLS and T.SPELLS[class] or {}) do data = data + #list end
        local seen = 0
        for _ in pairs(db.seen[SeenKey()] or {}) do seen = seen + 1 end
        Print(string.format("%s: %d spells in the data (%s), %d seen at trainers, %d future spells in the spell book. Now: %d (%s), needs first: %d.",
            class or "?", data, T.SOURCE or "?", seen, futureCount, #m.now, Money(m.cost), #m.missing))
        if lastScan then
            Print(string.format("Last trainer window: %d services, %d kept as spells, %d as weapons (%s).",
                lastScan.all, lastScan.spells, lastScan.weapons, lastScan.class and "a class trainer" or "not a class trainer"))
        end
        local t = NearestTrainer()
        Print(t and string.format("Trainer: %s, %s (%s).", t.name, TrainerPlace(t) or "?", t.from) or "No trainer known yet.")
    elseif cmd == "book" then
        Print(T.BookGround and T.BookGround() or "Spellbook.lua did not load.")
        Print(T.BookList())
        Print("EllesmereUI " .. (Loaded("EllesmereUI") and "on" or "off") .. ", tab " .. (db.bookTab and "on" or "off") .. ".")
    elseif cmd == "options" and ForeverUI_OpenOptions then
        ForeverUI_OpenOptions("trainer")
    else
        Print("/ftr opens or closes it. /ftr weapons: the weapon masters. /ftr notice: shows the level-up notice. /ftr info: what it knows. /ftr reset."
            .. (ForeverUI_OpenOptions and " /ftr options: every setting." or ""))
    end
end

---------------------------------------------------------------------------
-- The ForeverUI options' "Trainer" page (ForeverUI's Options.lua draws it)
---------------------------------------------------------------------------
local function Set(key)
    return function(v)
        db[key] = v
        Apply()
    end
end

local function Value(key)
    return function() return db[key] end
end

ForeverUI_Pages = ForeverUI_Pages or {}
ForeverUI_Pages[#ForeverUI_Pages + 1] = {
    key = "trainer",
    title = "Trainer",
    order = 35,
    build = function(K)
        K:Head("Trainer", "What your class trainer has for you now and at the next levels, where the nearest one is, and the weapon masters of your capitals.")
        K:Buttons({ { "Open the trainer window", function() Open("spells") end, true }, { "Weapon masters", function() Open("weapons") end } })

        K:Section("Spells")
        K:Slider("Levels ahead", 1, 60, 1, Value("ahead"), Set("ahead"), "%d")
        K:Switch("Spells that need a talent", Value("talents"), Set("talents"))
        K:Note("Off, a spell that needs a talent you don't have stays out of the list.")

        K:Section("Weapon masters")
        K:Switch("Weapons I know", Value("knownWeapons"), Set("knownWeapons"))
        K:Switch("Weapons my class can't use", Value("otherWeapons"), Set("otherWeapons"))

        K:Section("Level up")
        K:Switch("A line in the chat", Value("chat"), Set("chat"))
        K:Switch("A notice on the screen", Value("notice"), Set("notice"))
        K:Buttons({ { "Show the notice", function() LevelNews(select(4, Me()), true) end } })
        K:Note("At each level with something new at the trainer: how many spells, what they cost in all, and where. A click on the notice opens the window.")

        K:Section("Window")
        K:Choice("Layer", { { "LOW", "Low" }, { "MEDIUM", "Medium" }, { "HIGH", "High" }, { "DIALOG", "Dialog" },
            { "FULLSCREEN_DIALOG", "Front of all" } }, Value("strata"), Set("strata"))
        K:Slider("Scale", 0.5, 2, 0.05, Value("scale"), Set("scale"), "%.2f")
        K:Slider("Background opacity", 0.3, 1, 0.01, Value("alpha"), Set("alpha"), function(v)
            return string.format("%d%%", v * 100 + 0.5)
        end)
        K:Switch("Locked in place", Value("locked"), Set("locked"))
        K:Switch("Escape closes it", Value("escape"), Set("escape"))

        K:Section("Spell book")
        K:Switch("A Trainer tab in it", Value("bookTab"), Set("bookTab"))
        K:Note("A square with the book beside the spell book's own tabs: it lays the list over the book's pages, until you pick another tab. With both pages open, Spells on the left one and Weapon masters on the right; on one page, the two behind tabs. Without EllesmereUI, on the book's own parchment.")
        K:Switch("Drag it by its top bar", Value("bookMove"), Set("bookMove"), function()
            return not (T.ShifterOn and T.ShifterOn())
        end, function()
            if T.ShifterOn and T.ShifterOn() then return "EllesmereUI's Shifter moves it", ORANGE end
        end)
        K:Buttons({ { "Back to its place", function()
            db.bookPoint = nil
            Print("The spell book opens where the game puts it again, from the next time it opens.")
        end } })
        K:Note("The spell book moves by its top bar, as the quest log does, and opens where you left it. In combat it opens where the game puts it, and goes back once the combat ends. With EllesmereUI's Shifter on, the Shifter moves it instead.")

        K:Section("Minimap button")
        K:Switch("A button of its own", Value("ownButton"), function(v) db.ownButton = v end, nil, function()
            if (db.ownButton and true or false) ~= (mapButton ~= nil) then return "after a reload", ORANGE end
        end)
        K:Switch("The count of spells to train on it", Value("badge"), function(v)
            db.badge = v
            UpdateBadge()
        end, function() return mapButton ~= nil end)
        K:Buttons({ { "Reload now", function() ReloadUI() end } })
        K:Note("ForeverUI's F has the trainer in its menu, so this one starts off. On, it goes where ForeverUI's General page puts the F: in EllesmereUI's list of addon buttons, or on the minimap's edge (drag it round). Click: the window. Right click: this page.")

        K:Section("Where the list comes from")
        K:Note("The spells start from What's Training? (MIT License, by Sveng). Each visit to a class trainer brings the real prices and anything new, and the spell book's future spells fill in too. The nearest trainer comes from Polestar while the game runs.")
    end,
    reset = function()
        local seen, seenWeapons = db.seen, db.seenWeapons
        for key, v in pairs(DEFAULTS) do db[key] = v end
        db.seen, db.seenWeapons = seen, seenWeapons
        db.point, db.mapAngle, db.bookPoint, db.noticePoint = nil, nil, nil, nil
        Apply()
        ApplyMapButton()
        UpdateBadge()
    end,
}

---------------------------------------------------------------------------
-- ForeverUI's Move UI: the level-up notice (the window moves by its title bar)
---------------------------------------------------------------------------
ForeverUI_Movers = ForeverUI_Movers or {}
ForeverUI_Movers[#ForeverUI_Movers + 1] = {
    key = "trainernotice",
    title = "Level-up notice",
    frame = notice,
    usable = function() return db ~= nil end,
    set = function(point, relPoint, x, y)
        db.noticePoint = { point, relPoint, x, y }
        PlaceNotice()
    end,
    reset = function()
        db.noticePoint = nil
        PlaceNotice()
    end,
    show = function() ShowNotice("Level up: new spells to train", "The trainer's notice, shown here to move it", true) end,
    hide = function()
        fade:Stop()
        notice:Hide()
    end,
}
