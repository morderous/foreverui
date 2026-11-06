-- ForeverUI XPbar: one XP bar that also shows the XP of the quests that are
-- complete and not yet turned in, rested XP, XP per hour and time played.
-- Shift + drag moves it. /fxp lists the commands; the ForeverUI options have
-- a page for every setting (its "XP bar" page, at the end of this file).

local ADDON = ...

local DEFAULT_WIDTH = 580
local BAR_HEIGHT = 20
local LINE_GAP = 3
local TEXT_SIZE = 12
local BAR_TEXT_SIZE = 13

local COLOR_BACK = { 0.10, 0.10, 0.10, 0.90 }
local COLOR_XP = { 0.13, 0.55, 0.95, 1 }
local COLOR_QUEST = { 1.00, 0.76, 0.03, 1 }
local COLOR_RESTED = { 0.35, 0.45, 0.95, 0.45 }

-- Every setting and its first value. A setting left nil in the saved table
-- has this value, so a reset is a nil.
local DEFAULTS = {
    hidden = false, width = DEFAULT_WIDTH, height = BAR_HEIGHT, scale = 1,
    textSize = TEXT_SIZE, barTextSize = BAR_TEXT_SIZE, outline = "OUTLINE",
    locked = false, strata = "LOW",
    showTop = true, showQuestText = true, showLevel = true, showNumbers = true, showPercent = true,
    shortNumbers = false,     -- 4.1k / 10.1k on the bar instead of 4108 / 10100
    showRate = true, showRested = true, showQuestFill = true, showRestedFill = true, tooltip = true,
    colorXP = COLOR_XP, colorQuest = COLOR_QUEST, colorRested = COLOR_RESTED, colorBack = COLOR_BACK,
    keepBlizzard = false,
}

local db, charDB

local function Get(key)
    local v = db and db[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

-- A color as a text code, for the words in the bar's colors
local function Code(color)
    return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5))
end

-- A lighter one, for words in a color that is faint on the bar (rested)
local function Light(color)
    return color[1] + (1 - color[1]) * 0.3, color[2] + (1 - color[2]) * 0.3, color[3] + (1 - color[3]) * 0.3
end
local state = {
    played = nil, levelTime = nil, playedAt = nil, levelAt = nil,
    questXP = 0, questCount = 0,
    lastXP = nil, lastMax = nil,
    askedAt = nil, questPending = false,
}

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local root = CreateFrame("Frame", "ForeverUIXPBarFrame", UIParent)
root:SetSize(DEFAULT_WIDTH, BAR_HEIGHT + 2 * (TEXT_SIZE + LINE_GAP + 2))
root:SetFrameStrata("LOW")
root:SetClampedToScreen(true)
root:SetMovable(true)
root:EnableMouse(true)
root:RegisterForDrag("LeftButton")

local bar = CreateFrame("Frame", nil, root)
bar:SetPoint("LEFT", root, "LEFT", 0, 0)
bar:SetPoint("RIGHT", root, "RIGHT", 0, 0)
bar:SetHeight(BAR_HEIGHT)

local border = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
border:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
border:SetColorTexture(0, 0, 0, 1)

local back = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
back:SetAllPoints(bar)
back:SetColorTexture(COLOR_BACK[1], COLOR_BACK[2], COLOR_BACK[3], COLOR_BACK[4])

local function Fill(sublevel, color)
    local t = bar:CreateTexture(nil, "ARTWORK", nil, sublevel)
    t:SetPoint("TOP", bar, "TOP", 0, 0)
    t:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    t:SetColorTexture(color[1], color[2], color[3], color[4])
    t:Hide()
    return t
end

local restedFill = Fill(1, COLOR_RESTED)
local questFill = Fill(2, COLOR_QUEST)
local xpFill = Fill(3, COLOR_XP)

local texts = {}
local function Text(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetWordWrap(false)
    fs.size = size
    texts[#texts + 1] = fs
    return fs
end

local topLeft = Text(root, TEXT_SIZE)
topLeft:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 2, LINE_GAP)
local topRight = Text(root, TEXT_SIZE)
topRight:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", -2, LINE_GAP)

local barLeft = Text(bar, BAR_TEXT_SIZE)
barLeft:SetPoint("LEFT", bar, "LEFT", 6, 0)
local barCenter = Text(bar, BAR_TEXT_SIZE)
barCenter:SetPoint("CENTER", bar, "CENTER", 0, 0)
local barRight = Text(bar, BAR_TEXT_SIZE)
barRight:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
barLeft.onBar, barCenter.onBar, barRight.onBar = true, true, true

local bottomLeft = Text(root, TEXT_SIZE)
bottomLeft:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -LINE_GAP)
local bottomRight = Text(root, TEXT_SIZE)
bottomRight:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -2, -LINE_GAP)

-- The font EllesmereUI uses for everything, when it is there.
local function FontPath()
    local E = _G.EllesmereUI
    if E and E.GetFontPath then
        local ok, path = pcall(E.GetFontPath)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return STANDARD_TEXT_FONT
end

-- The outline chosen (none, OUTLINE or THICKOUTLINE), in EllesmereUI's way
-- when it is there.
local function FontFlags()
    local outline = Get("outline")
    if outline ~= "OUTLINE" and outline ~= "THICKOUTLINE" then return "" end
    local E = _G.EllesmereUI
    if E and E.SlugFlag then
        local ok, flags = pcall(E.SlugFlag, outline .. ", SLUG")
        if ok and type(flags) == "string" then return flags end
    end
    return outline
end

local function ApplyFonts()
    local path, flags = FontPath(), FontFlags()
    for i = 1, #texts do
        local fs = texts[i]
        local size = fs.onBar and Get("barTextSize") or Get("textSize")
        local ok = pcall(fs.SetFont, fs, path, size, flags)
        if not ok or not fs:GetFont() then
            fs:SetFont(STANDARD_TEXT_FONT, size, flags)
        end
        -- Without an outline, a shadow keeps the words readable
        if flags == "" then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
        fs:SetShadowColor(0, 0, 0, 1)
    end
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local function Clock(seconds)
    seconds = math.floor(seconds or 0)
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

local function Short(n)
    if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return string.format("%d", n)
end

---------------------------------------------------------------------------
-- What the bar shows
---------------------------------------------------------------------------
local function AtMax()
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
        return GameRulesUtil.IsPlayerAtEffectiveMaxLevel()
    end
    return false
end

local function Session()
    return charDB and charDB.session
end

local function Rate()
    local s = Session()
    if not s or (s.gained or 0) <= 0 then return nil end
    local elapsed = time() - s.start
    if elapsed < 60 then return nil end
    return s.gained / elapsed * 3600
end

local function SetFill(tex, from, width)
    if width < 1 then tex:Hide() return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", bar, "TOPLEFT", from, 0)
    tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", from, 0)
    tex:SetWidth(width)
    tex:Show()
end

local function Refresh()
    if not db then return end
    if AtMax() or Get("hidden") then root:Hide() return end
    root:Show()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not max or max <= 0 then return end
    local rested = GetXPExhaustion() or 0
    local w = bar:GetWidth()

    local xpW = math.min(w, w * cur / max)
    local questW = Get("showQuestFill") and math.min(w - xpW, w * state.questXP / max) or 0
    local restedW = Get("showRestedFill") and math.min(w - xpW - questW, w * rested / max) or 0
    SetFill(xpFill, 0, xpW)
    SetFill(questFill, xpW, questW)
    SetFill(restedFill, xpW + questW, restedW)

    local now = GetTime()
    local played, levelTime = "--", "--"
    if state.played then played = Clock(state.played + now - state.playedAt) end
    if state.levelTime then levelTime = Clock(state.levelTime + now - state.levelAt) end
    topLeft:SetText(string.format("Played: %s  This Level: %s", played, levelTime))
    topRight:SetText(string.format("Completed Quests: %s%.1f%%|r", Code(Get("colorQuest")), state.questXP / max * 100))

    barLeft:SetText(string.format("Level %d", UnitLevel("player")))
    if Get("shortNumbers") then
        barCenter:SetText(string.format("%s / %s", Short(cur), Short(max)))
    else
        barCenter:SetText(string.format("%d / %d", cur, max))
    end
    barRight:SetText(string.format("%.1f%%", cur / max * 100))

    local rate = Rate()
    if rate then
        bottomLeft:SetText(string.format("%s to level at %s/h", Clock((max - cur) / rate * 3600), Short(rate)))
    else
        bottomLeft:SetText("No XP yet this session")
    end
    local restedColor = Get("colorRested")
    bottomRight:SetText(string.format("Rested: %s%.1f%%|r", Code({ Light(restedColor) }), rested / max * 100))
end

-- XP of the quests in the log that are done and only wait to be turned in.
local function ScanQuests()
    local xp, count = 0, 0
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 then
            local done = C_QuestLog.IsComplete(id)
            if not done and C_QuestLog.ReadyForTurnIn then done = C_QuestLog.ReadyForTurnIn(id) end
            if done then
                local reward = GetQuestLogRewardXP(id) or 0
                if reward > 0 then
                    xp = xp + reward
                    count = count + 1
                end
            end
        end
    end
    state.questXP, state.questCount = xp, count
end

local function QuestsChanged()
    if state.questPending then return end
    state.questPending = true
    C_Timer.After(0.3, function()
        state.questPending = false
        ScanQuests()
        Refresh()
    end)
end

-- XP gained since the last look. XP only goes down on a level up, and then
-- the rest of the old level counts too.
local function TrackXP()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local s = Session()
    if state.lastXP and s then
        local gained
        if cur < state.lastXP then
            gained = (state.lastMax - state.lastXP) + cur
        else
            gained = cur - state.lastXP
        end
        if gained > 0 then s.gained = (s.gained or 0) + gained end
    end
    state.lastXP, state.lastMax = cur, max
end

---------------------------------------------------------------------------
-- Time played: asked once per load, kept out of the chat window
---------------------------------------------------------------------------
local muted = {}

local function UnmuteChat()
    for i = 1, #muted do muted[i]:RegisterEvent("TIME_PLAYED_MSG") end
    wipe(muted)
end

local function AskPlayed()
    local windows = NUM_CHAT_WINDOWS
        or (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows)
        or 10
    for i = 1, windows do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = cf
        end
    end
    state.askedAt = GetTime()
    RequestTimePlayed()
    -- No answer: give the chat window its event back anyway.
    C_Timer.After(10, function()
        if #muted > 0 then UnmuteChat() end
    end)
end

---------------------------------------------------------------------------
-- Place and size
---------------------------------------------------------------------------
local function Place()
    root:ClearAllPoints()
    local p = db.point
    if p then
        root:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        root:SetPoint("TOP", UIParent, "TOP", 0, -40)
    end
    root:SetScale(Get("scale"))
    root:SetWidth(Get("width"))
    root:EnableMouse(not Get("locked"))
end

local function SavePlace()
    local point, _, relPoint, x, y = root:GetPoint(1)
    db.point = { point, relPoint, x, y }
end

-- Everything the options set, at once
local function Apply()
    if not db then return end
    root:SetFrameStrata(Get("strata"))
    bar:SetHeight(Get("height"))
    root:SetHeight(Get("height") + 2 * (Get("textSize") + LINE_GAP + 2))
    local function Paint(tex, key)
        local c = Get(key)
        tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    Paint(xpFill, "colorXP")
    Paint(questFill, "colorQuest")
    Paint(restedFill, "colorRested")
    Paint(back, "colorBack")
    topLeft:SetShown(Get("showTop"))
    topRight:SetShown(Get("showQuestText"))
    barLeft:SetShown(Get("showLevel"))
    barCenter:SetShown(Get("showNumbers"))
    barRight:SetShown(Get("showPercent"))
    bottomLeft:SetShown(Get("showRate"))
    bottomRight:SetShown(Get("showRested"))
    ApplyFonts()
    Place()
    Refresh()
end

-- Blizzard's XP and reputation bars. EllesmereUI Action Bars hides them
-- unless its "Use Blizzard data bars" is on; when they are still shown
-- here, they go the way EllesmereUI does it (their events come back only
-- with a reload). Never in combat, and not at max level, where this bar
-- is hidden and Blizzard's reputation bar may be wanted.
local function HideBlizzardBar()
    local manager = _G.StatusTrackingBarManager
    if not manager or Get("keepBlizzard") or AtMax() then return end
    if InCombatLockdown() then
        state.blizzardPending = true
        return
    end
    state.blizzardPending = false
    if manager:IsShown() then
        manager:UnregisterAllEvents()
        manager:Hide()
    end
end

root:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not Get("locked") then self:StartMoving() end
end)

root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePlace()
end)

root:SetScript("OnSizeChanged", function() Refresh() end)

root:SetScript("OnEnter", function(self)
    if not Get("tooltip") then return end
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if not max or max <= 0 then return end
    local rested = GetXPExhaustion() or 0
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("ForeverUI XPbar")
    GameTooltip:AddDoubleLine("XP", string.format("%s / %s", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(max)), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("To level", BreakUpLargeNumbers(max - cur), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Completed quests", string.format("%d (%s XP)", state.questCount, BreakUpLargeNumbers(state.questXP)), 1, 1, 1, 1, 0.76, 0.1)
    GameTooltip:AddDoubleLine("Rested", BreakUpLargeNumbers(rested), 1, 1, 1, 0.3, 0.6, 1)
    local s = Session()
    if s then
        GameTooltip:AddDoubleLine("This session", string.format("%s XP in %s", BreakUpLargeNumbers(s.gained or 0), Clock(time() - s.start)), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine("Shift + drag to move. /fxp for more.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)

root:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local loaded = false

root:RegisterEvent("ADDON_LOADED")
root:RegisterEvent("PLAYER_LOGIN")
root:RegisterEvent("PLAYER_ENTERING_WORLD")
root:RegisterEvent("PLAYER_XP_UPDATE")
root:RegisterEvent("PLAYER_LEVEL_UP")
root:RegisterEvent("UPDATE_EXHAUSTION")
root:RegisterEvent("PLAYER_UPDATE_RESTING")
root:RegisterEvent("QUEST_LOG_UPDATE")
root:RegisterEvent("TIME_PLAYED_MSG")
root:RegisterEvent("PLAYER_LOGOUT")
root:RegisterEvent("PLAYER_REGEN_ENABLED")

root:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        ForeverUIXPBarDB = ForeverUIXPBarDB or {}
        ForeverUIXPBarCharDB = ForeverUIXPBarCharDB or {}
        db, charDB = ForeverUIXPBarDB, ForeverUIXPBarCharDB
        -- A reload or a quick relog keeps the session; a long break starts a new one.
        local s = charDB.session
        if not s or not s.seen or time() - s.seen > 600 then
            charDB.session = { start = time(), gained = 0, seen = time() }
        end
        Apply()
    elseif event == "PLAYER_LOGIN" then
        ApplyFonts()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not loaded then
            loaded = true
            state.lastXP, state.lastMax = UnitXP("player"), UnitXPMax("player")
            C_Timer.After(2, AskPlayed)
            C_Timer.After(1, HideBlizzardBar)
            C_Timer.NewTicker(1, Refresh)
        end
        ScanQuests()
        Refresh()
    elseif event == "PLAYER_XP_UPDATE" then
        TrackXP()
        Refresh()
    elseif event == "PLAYER_LEVEL_UP" then
        state.levelTime, state.levelAt = 0, GetTime()
        QuestsChanged()
    elseif event == "QUEST_LOG_UPDATE" then
        QuestsChanged()
    elseif event == "TIME_PLAYED_MSG" then
        local total, level = ...
        state.played, state.levelTime = total, level
        state.playedAt, state.levelAt = GetTime(), GetTime()
        if #muted > 0 then C_Timer.After(0, UnmuteChat) end
        Refresh()
    elseif event == "PLAYER_LOGOUT" then
        if charDB and charDB.session then charDB.session.seen = time() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.blizzardPending then HideBlizzardBar() end
    else
        Refresh()
    end
end)

---------------------------------------------------------------------------
-- /fxp
---------------------------------------------------------------------------
local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4d9cffForeverUI XPbar|r: " .. msg)
end

SLASH_FOREVERUIXPBAR1 = "/fxp"
SLASH_FOREVERUIXPBAR2 = "/foreverxp"
SlashCmdList.FOREVERUIXPBAR = function(input)
    local cmd, value = string.match(string.lower(input or ""), "^%s*(%S*)%s*(%S*)")
    local n = tonumber(value)
    if cmd == "scale" and n then
        db.scale = math.max(0.5, math.min(2, n))
        Place()
        Say(string.format("scale %.2f", db.scale))
    elseif cmd == "width" and n then
        db.width = math.max(300, math.min(1600, math.floor(n)))
        Place()
        Say(string.format("width %d", db.width))
    elseif cmd == "lock" then
        db.locked = true
        Place()
        Say("locked: clicks go through it, no tooltip.")
    elseif cmd == "unlock" then
        db.locked = false
        Place()
        Say("unlocked: Shift + drag to move.")
    elseif cmd == "reset" then
        db.point, db.scale, db.width, db.locked = nil, nil, nil, nil
        Place()
        Say("back to the top of the screen.")
    elseif cmd == "session" then
        charDB.session = { start = time(), gained = 0, seen = time() }
        Refresh()
        Say("XP per hour starts again.")
    elseif cmd == "blizzard" then
        db.keepBlizzard = not db.keepBlizzard
        if db.keepBlizzard then
            Say("Blizzard's XP bar is kept: it comes back after a /reload.")
        else
            HideBlizzardBar()
            Say("Blizzard's XP bar is hidden.")
        end
    elseif cmd == "options" and ForeverUI_OpenOptions then
        ForeverUI_OpenOptions("xpbar")
    else
        Say("/fxp scale 1.2 | width 700 | lock | unlock | reset | session | blizzard" .. (ForeverUI_OpenOptions and " | options" or ""))
    end
end

---------------------------------------------------------------------------
-- The ForeverUI options' "XP bar" page (ForeverUI's Options.lua draws it)
---------------------------------------------------------------------------
local function Set(key)
    return function(v)
        db[key] = v
        Apply()
    end
end

local function Is(key)
    return function() return Get(key) and true or false end
end

local function Value(key)
    return function() return Get(key) end
end

ForeverUI_Pages = ForeverUI_Pages or {}
ForeverUI_Pages[#ForeverUI_Pages + 1] = {
    key = "xpbar",
    title = "XP bar",
    order = 20,
    build = function(K)
        K:Head("XP bar", "One bar for your XP, the XP of the quests that only wait to be turned in, rested XP, XP per hour and time played.")
        K:Switch("Show the bar", function() return not Get("hidden") end, function(v)
            db.hidden = not v
            Apply()
        end)
        local function Shown() return not Get("hidden") end
        local function Unlocked() return Shown() and not Get("locked") end

        K:Section("Size")
        K:Slider("Width", 300, 1600, 10, Value("width"), Set("width"), "%d", Shown)
        K:Slider("Bar height", 6, 40, 1, Value("height"), Set("height"), "%d", Shown)
        K:Slider("Scale", 0.5, 2, 0.05, Value("scale"), Set("scale"), "%.2f", Shown)
        K:Slider("Text size", 8, 20, 1, Value("textSize"), Set("textSize"), "%d", Shown)
        K:Slider("Text size on the bar", 8, 20, 1, Value("barTextSize"), Set("barTextSize"), "%d", Shown)
        K:Choice("Text outline", { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" } },
            Value("outline"), Set("outline"), Shown)

        K:Section("Place")
        K:Switch("Locked", Is("locked"), Set("locked"), Shown)
        K:Choice("Layer", { { "BACKGROUND", "Background" }, { "LOW", "Low" }, { "MEDIUM", "Medium" }, { "HIGH", "High" } },
            Value("strata"), Set("strata"), Shown)
        K:Buttons({
            { "Top of the screen", function()
                db.point = nil
                Apply()
            end },
            { "Bottom of the screen", function()
                db.point = { "BOTTOM", "BOTTOM", 0, 150 }
                Apply()
            end },
        })
        K:Note("Unlocked, Shift + drag moves it. Locked, clicks go through it and it has no tooltip.")

        K:Section("Words")
        K:Switch("Time played and this level", Is("showTop"), Set("showTop"), Shown)
        K:Switch("Completed quests, in %", Is("showQuestText"), Set("showQuestText"), Shown)
        K:Switch("Level, on the bar", Is("showLevel"), Set("showLevel"), Shown)
        K:Switch("XP numbers, on the bar", Is("showNumbers"), Set("showNumbers"), Shown)
        K:Switch("Short numbers (4.1k)", Is("shortNumbers"), Set("shortNumbers"), function()
            return Shown() and Get("showNumbers")
        end)
        K:Switch("Percent, on the bar", Is("showPercent"), Set("showPercent"), Shown)
        K:Switch("Time to level, XP per hour", Is("showRate"), Set("showRate"), Shown)
        K:Switch("Rested, in %", Is("showRested"), Set("showRested"), Shown)
        K:Switch("Tooltip", Is("tooltip"), Set("tooltip"), Unlocked)

        K:Section("Colors")
        K:Switch("Completed quests on the bar", Is("showQuestFill"), Set("showQuestFill"), Shown)
        K:Switch("Rested on the bar", Is("showRestedFill"), Set("showRestedFill"), Shown)
        K:Color("XP", Value("colorXP"), Set("colorXP"), false, Shown)
        K:Color("Completed quests", Value("colorQuest"), Set("colorQuest"), false, function()
            return Shown() and Get("showQuestFill")
        end)
        K:Color("Rested", Value("colorRested"), Set("colorRested"), true, function()
            return Shown() and Get("showRestedFill")
        end)
        K:Color("Background", Value("colorBack"), Set("colorBack"), true, Shown)

        K:Section("Blizzard's bar")
        K:Switch("Hide Blizzard's XP bar", function() return not Get("keepBlizzard") end, function(v)
            db.keepBlizzard = not v
            if v then HideBlizzardBar() end
        end)
        K:Note("Blizzard's bar comes back only after a /reload.")

        K:Section("XP per hour")
        K:Buttons({ { "Start the session again", function()
            charDB.session = { start = time(), gained = 0, seen = time() }
            Refresh()
        end } })
    end,
    reset = function()
        for key in pairs(DEFAULTS) do db[key] = nil end
        db.point = nil
        Apply()
    end,
}

---------------------------------------------------------------------------
-- ForeverUI's Move UI (ForeverUI's MoveUI.lua outlines it to drag)
---------------------------------------------------------------------------
ForeverUI_Movers = ForeverUI_Movers or {}
ForeverUI_Movers[#ForeverUI_Movers + 1] = {
    key = "xpbar",
    title = "XP bar",
    frame = root,
    usable = function() return db ~= nil and not Get("hidden") end,
    set = function(point, relPoint, x, y)
        db.point = { point, relPoint, x, y }
        Apply()
    end,
    reset = function()
        db.point = nil
        Apply()
    end,
}
