-- ForeverUI Quest Log: the classic two-page quest log, for WoW Forever.
-- One page has the chosen quest's text, the other the list of quests, side by
-- side: the text on the left and the list on the right (/fql swap flips them).
-- The quest log key (L) opens it; the world map key (M) stays the map.
--
-- Written from scratch. The way the key is taken (an override binding on the
-- keys of TOGGLEQUESTLOG, to a button of our own) is the one Pretty Wide Quest
-- Log (MIT) uses. Nothing of Blizzard's is replaced or hooked, and the quest's
-- text is drawn here instead of borrowing Blizzard's QuestInfo pieces, so the
-- map and the quest giver window never run code of ours.

local ADDON = ...

---------------------------------------------------------------------------
-- Sizes and colors
---------------------------------------------------------------------------
local PAD = 8
local TOP_H = 28
local BOTTOM_H = 34
local DETAIL_W, LIST_W = 360, 320          -- the two pages at the start
local MIN_DETAIL, MIN_LIST = 280, 220
local MIN_W, MAX_W = PAD + MIN_DETAIL + PAD + MIN_LIST + PAD, 1800
local DEFAULT_W = PAD + DETAIL_W + PAD + LIST_W + PAD
local DEFAULT_SPLIT = DETAIL_W / (DETAIL_W + LIST_W)   -- the text page's share of the width
local MIN_H, MAX_H, DEFAULT_H = 360, 1100, 520
local ROW_H = 18
local LIST_TOP = 24                       -- the strip with the quest count
local PAGE_X = 14                         -- the text, in from the page's left edge
local PAGE_TOP = 12
local PAGE_RIGHT = 34                     -- room for the scroll bar
local ITEM_MIN_W, ITEM_H, ITEM_GAP = 150, 40, 4

local COLOR_WINDOW = { 0.06, 0.06, 0.06, 0.94 }
local COLOR_LIST = { 0.10, 0.10, 0.10, 0.92 }
local COLOR_BUTTON = { 0.16, 0.16, 0.16, 1 }
local COLOR_HEADER = { 1.00, 0.82, 0.00 }
local COLOR_FAILED = { 0.90, 0.15, 0.15 }
local COLOR_PAGE_RED = { 0.70, 0.05, 0.05 }

local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local TITLE_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

---------------------------------------------------------------------------
-- Words: the game's own where it has them, so they come in its language
---------------------------------------------------------------------------
local function Word(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

local W = {
    title = Word("QUEST_LOG", "Quest Log"),
    abandon = Word("ABANDON_QUEST_ABBREV", "Abandon"),
    share = Word("SHARE_QUEST_ABBREV", "Share"),
    track = Word("TRACK_QUEST_ABBREV", "Track"),
    untrack = Word("UNTRACK_QUEST_ABBREV", "Untrack"),
    close = Word("CLOSE", "Close"),
    yes = Word("YES", "Yes"),
    no = Word("NO", "No"),
    complete = Word("COMPLETE", "Complete"),
    failed = Word("FAILED", "Failed"),
    elite = Word("ELITE", "Elite"),
    daily = Word("DAILY", "Daily"),
    weekly = Word("WEEKLY", "Weekly"),
    description = Word("QUEST_DESCRIPTION", "Description"),
    rewards = Word("QUEST_REWARDS", "Rewards"),
    choose = Word("REWARD_CHOICES", "You will be able to choose one of these rewards:"),
    receive = Word("REWARD_ITEMS_ONLY", "You will receive:"),
    alsoReceive = Word("REWARD_ITEMS", "You will also receive:"),
    learn = Word("REWARD_SPELL", "You will learn:"),
    experience = Word("EXPERIENCE_COLON", "Experience:"),
    requiredMoney = Word("REQUIRED_MONEY", "Required Money:"),
    groupSize = Word("QUEST_SUGGESTED_GROUP_NUM", "Suggested Players [%d]"),
    countTemplate = Word("QUEST_LOG_COUNT_TEMPLATE", "Quests: %s%d|r/%d"),
    abandonAsk = Word("ABANDON_QUEST_CONFIRM", "Abandon \"%s\"?"),
    tooMany = Word("OBJECTIVES_WATCH_TOO_MANY", "You are tracking too many quests."),
    abandonItems = "These items will be destroyed:",
    noQuests = "You have no quests.",
    loading = "Loading the quest's text...",
    collapseAll = "Collapse all",
    expandAll = "Expand all",
}

_G.BINDING_HEADER_FOREVERUIQUESTLOG = "ForeverUI Quest Log"
_G.BINDING_NAME_FOREVERUIQUESTLOG_TOGGLE = "Open or close the quest log"

-- A format string of the game's, with ours if the game's doesn't take these values.
local function Format(fmt, fallback, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if ok then return text end
    return string.format(fallback, ...)
end

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe6b85cForeverUI Quest Log|r: " .. text)
end

local function Sound(name)
    if ForeverUIQuestLogDB and ForeverUIQuestLogDB.sounds == false then return end
    if SOUNDKIT and SOUNDKIT[name] then PlaySound(SOUNDKIT[name]) end
end

local db, charDB
local DEFAULTS = {
    width = DEFAULT_W, height = DEFAULT_H, split = DEFAULT_SPLIT, scale = 1, listLeft = false, takeKey = true,
    strata = "MEDIUM",        -- the window's layer: "FULLSCREEN_DIALOG" puts it in front of everything
    openAt = "kept",          -- where it opens: "kept" (where it was left) or "center"
    locked = false, alpha = 0.94, escape = true, sounds = true,
}
-- The layers, bottom to top
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

---------------------------------------------------------------------------
-- Little pieces
---------------------------------------------------------------------------
-- A flat box: 1px black border and a fill, as the rest of the UI.
local function Box(f, color)
    local border = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetAllPoints(f)
    fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return fill
end

local function FlatButton(parent, width, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    Box(b, COLOR_BUTTON)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.08)
    b:SetNormalFontObject(GameFontHighlightSmall)
    b:SetDisabledFontObject(GameFontDisableSmall)
    b:SetText(text)
    return b
end

local function UseFont(fs, name, fallback)
    local obj = _G[name] or _G[fallback or "GameFontHighlight"]
    if obj then fs:SetFontObject(obj) end
end

-- Runs fn with questID as the game's selected quest (the quest log functions
-- that take no quest read that one), then puts the old selection back.
local function WithSelected(questID, fn, ...)
    local old = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(questID)
    local a, b, c = fn(...)
    if old ~= nil and old ~= questID then C_QuestLog.SetSelectedQuest(old) end
    return a, b, c
end

local function Money(amount)
    if GetMoneyString then
        local ok, text = pcall(GetMoneyString, amount, true)
        if ok and text then return text end
    end
    return string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end

local function Number(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function PageColors()
    if GetMaterialTextColors then
        local ok, text, title = pcall(GetMaterialTextColors, "Default")
        if ok and text and title then return text, title end
    end
    return { 0.18, 0.12, 0.06 }, { 0, 0, 0 }
end

local function DoneColor()
    local c = QUEST_OBJECTIVE_COMPLETED_FONT_COLOR
    if c and c.GetRGB then return { c:GetRGB() } end
    return { 0.30, 0.30, 0.30 }
end

local function DifficultyColor(q)
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, q.difficulty or q.level or 0, q.scaling, q.questID)
        if ok and c and c.r then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

local function QualityColor(quality)
    if quality and C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
        if ok and r then return r, g, b end
    end
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function InsertLink(link)
    if not link then return false end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    return false
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "ForeverUIQuestLogFrame", UIParent)
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
tinsert(UISpecialFrames, frame:GetName())   -- Escape closes it (/fql options can turn that off)

local function SetEscape(on)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == frame:GetName() then table.remove(UISpecialFrames, i) end
    end
    if on then tinsert(UISpecialFrames, frame:GetName()) end
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then db.point = { point, relPoint, x, y } end
    db.width = frame:GetWidth()
    db.height = frame:GetHeight()
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

-- The title bar moves the window
local titleBar = CreateFrame("Frame", nil, frame)
titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0)
titleBar:SetHeight(TOP_H)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function()
    if not db.locked then frame:StartMoving() end
end)
titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SavePosition()
end)

local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", frame, "TOP", 0, -8)
titleText:SetText(W.title)

-- Not UIPanelCloseButton: its script goes through the panel manager.
local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
closeX:SetScript("OnClick", function() frame:Hide() end)

-- The grip in the corner makes it wider, narrower, taller or shorter
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
end)

local detailPane = CreateFrame("Frame", nil, frame)
local listPane = CreateFrame("Frame", nil, frame)

-- The bar between the two pages: dragged, it gives one more room and the other less
local divider = CreateFrame("Frame", nil, frame)
divider:EnableMouse(true)
local dividerLine = divider:CreateTexture(nil, "ARTWORK")
dividerLine:SetPoint("TOP", divider, "TOP", 0, 0)
dividerLine:SetPoint("BOTTOM", divider, "BOTTOM", 0, 0)
dividerLine:SetWidth(2)
dividerLine:SetColorTexture(1, 0.82, 0, 0.5)
dividerLine:Hide()

local detailW, listW = DETAIL_W, LIST_W
local contentW = DETAIL_W - PAGE_X - PAGE_RIGHT   -- the width of the page's text

-- The two pages share the window's width, the text page by db.split, each kept
-- to its least width.
local function Widths()
    local inner = frame:GetWidth() - 3 * PAD
    local share = math.floor(inner * (db and db.split or DEFAULT_SPLIT) + 0.5)
    local d = math.max(MIN_DETAIL, math.min(inner - MIN_LIST, share))
    return d, inner - d
end

local function LayoutPanes()
    detailW, listW = Widths()
    contentW = detailW - PAGE_X - PAGE_RIGHT
    detailPane:ClearAllPoints()
    listPane:ClearAllPoints()
    local left, right = detailPane, listPane
    if db and db.listLeft then left, right = listPane, detailPane end
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP_H)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, BOTTOM_H)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -TOP_H)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, BOTTOM_H)
    detailPane:SetWidth(detailW)
    listPane:SetWidth(listW)
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
end
LayoutPanes()

---------------------------------------------------------------------------
-- The page: the chosen quest's text, on parchment
---------------------------------------------------------------------------
local parchment = Box(detailPane, { 0.85, 0.77, 0.60, 1 })
if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
    parchment:SetAtlas("QuestBG-Parchment", false)
    parchment:SetAllPoints(detailPane)
end

local pageScroll = CreateFrame("ScrollFrame", nil, detailPane)
pageScroll:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 0, -2)
pageScroll:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -16, 2)
pageScroll:EnableMouseWheel(true)
local pageBar = CreateFrame("EventFrame", nil, detailPane, "MinimalScrollBar")
pageBar:SetPoint("TOPLEFT", pageScroll, "TOPRIGHT", 4, -4)
pageBar:SetPoint("BOTTOMLEFT", pageScroll, "BOTTOMRIGHT", 4, 4)
pageBar:SetHideIfUnscrollable(true)
ScrollUtil.InitScrollFrameWithScrollBar(pageScroll, pageBar)

local page = CreateFrame("Frame", nil, pageScroll)
page:SetSize(DETAIL_W - 16, 10)
pageScroll:SetScrollChild(page)

-- What's on the page, top to bottom: texts and rows of reward buttons
local blocks = {}
local texts, textsUsed = {}, 0
local items, itemsUsed = {}, 0

local function PageText(text, font, color, gap)
    textsUsed = textsUsed + 1
    local fs = texts[textsUsed]
    if not fs then
        fs = page:CreateFontString(nil, "ARTWORK")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        texts[textsUsed] = fs
    end
    UseFont(fs, font, "GameFontBlack")
    fs:SetWidth(contentW)
    fs:SetText(text)
    fs:SetTextColor(color[1], color[2], color[3])
    blocks[#blocks + 1] = { region = fs, gap = gap or 0 }
    return fs
end

local function ItemEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.spellID then
        GameTooltip:SetSpellByID(self.spellID)
    else
        local ok = WithSelected(self.questID, pcall, GameTooltip.SetQuestLogItem, GameTooltip, self.kind, self.index, self.questID, true)
        if not ok and self.itemID then GameTooltip:SetItemByID(self.itemID) end
    end
    GameTooltip:Show()
end

local function ItemLeave()
    GameTooltip:Hide()
end

local function ItemClick(self)
    local link
    if self.spellID then
        if C_Spell and C_Spell.GetSpellLink then link = C_Spell.GetSpellLink(self.spellID) end
    elseif GetQuestLogItemLink then
        link = WithSelected(self.questID, GetQuestLogItemLink, self.kind, self.index)
    end
    if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
end

local function ItemButton(questID, kind, index, name, texture, count, quality, itemID, spellID)
    itemsUsed = itemsUsed + 1
    local b = items[itemsUsed]
    if not b then
        b = CreateFrame("Button", nil, page)
        b:SetSize(ITEM_MIN_W, ITEM_H)
        local back = b:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(b)
        back:SetColorTexture(0, 0, 0, 0.55)   -- so white and green names read on the parchment
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(ITEM_H - 4, ITEM_H - 4)
        b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 2)
        b.name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        b.name:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
        b.name:SetPoint("RIGHT", b, "RIGHT", -3, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(true)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b)
        hl:SetColorTexture(1, 1, 1, 0.10)
        b:SetScript("OnEnter", ItemEnter)
        b:SetScript("OnLeave", ItemLeave)
        b:SetScript("OnClick", ItemClick)
        items[itemsUsed] = b
    end
    b.questID, b.kind, b.index, b.itemID, b.spellID = questID, kind, index, itemID, spellID
    b.icon:SetTexture(texture or 134400)   -- (the question mark icon)
    b.count:SetText((count and count > 1) and count or "")
    b.name:SetText(name or "")
    b.name:SetTextColor(QualityColor(quality))
    if not name then page.waitingItems = true end   -- (drawn again when the item's data comes)
    return b
end

local function PageItems(list, gap)
    if #list > 0 then blocks[#blocks + 1] = { items = list, gap = gap or 0 } end
end

local function ClearPage()
    for i = 1, textsUsed do texts[i]:Hide() end
    for i = 1, itemsUsed do items[i]:Hide() end
    textsUsed, itemsUsed = 0, 0
    wipe(blocks)
    page.waitingItems = false
end

-- Places everything at the page's width now: the texts wrap to it, and the
-- rewards take as many columns as fit, each stretched to fill the row.
local function LayoutPage()
    local cols = math.max(1, math.floor((contentW + ITEM_GAP) / (ITEM_MIN_W + ITEM_GAP)))
    local itemW = math.floor((contentW - (cols - 1) * ITEM_GAP) / cols)
    local y = PAGE_TOP
    for i, b in ipairs(blocks) do
        if i > 1 then y = y + b.gap end
        if b.items then
            for n, button in ipairs(b.items) do
                local col = (n - 1) % cols
                local row = math.floor((n - 1) / cols)
                button:SetWidth(itemW)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_X + col * (itemW + ITEM_GAP), -(y + row * (ITEM_H + ITEM_GAP)))
                button:Show()
            end
            local rows = math.ceil(#b.items / cols)
            y = y + rows * ITEM_H + (rows - 1) * ITEM_GAP
        else
            local fs = b.region
            fs:SetWidth(contentW)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_X, -y)
            fs:Show()
            y = y + fs:GetStringHeight()
        end
    end
    page:SetHeight(y + 14)
    pageScroll:UpdateScrollChildRect()
end

local function AddRewards(questID, textColor, titleColor)
    if C_QuestLog.ShouldShowQuestRewards and not C_QuestLog.ShouldShowQuestRewards(questID) then return end
    local numChoices = GetNumQuestLogChoices and GetNumQuestLogChoices(questID) or 0
    local numRewards = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0

    local choices, received, spells = {}, {}, {}
    for i = 1, numChoices do
        local name, texture, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
        if name or texture then
            choices[#choices + 1] = ItemButton(questID, "choice", i, name, texture, count, quality, itemID)
        end
    end
    for i = 1, numRewards do
        local name, texture, count, quality, _, itemID = GetQuestLogRewardInfo(i, questID)
        if name or texture then
            received[#received + 1] = ItemButton(questID, "reward", i, name, texture, count, quality, itemID)
        end
    end
    local info = C_QuestInfoSystem
    if info and info.GetQuestRewardSpells and info.GetQuestRewardSpellInfo then
        for _, spellID in ipairs(info.GetQuestRewardSpells(questID) or {}) do
            local spell = spellID and spellID > 0 and info.GetQuestRewardSpellInfo(questID, spellID)
            if spell and spell.texture and not spell.garrFollowerID then
                spells[#spells + 1] = ItemButton(questID, "spell", nil, spell.name, spell.texture, nil, nil, nil, spellID)
            end
        end
    end
    if #choices == 0 and #received == 0 and #spells == 0 and money <= 0 and xp <= 0 then return end

    PageText(W.rewards, "QuestTitleFont", titleColor, 20)
    if #choices > 0 then
        PageText(#choices == 1 and W.receive or W.choose, "QuestFont", textColor, 6)
        PageItems(choices, 6)
    end
    if #spells > 0 then
        PageText(W.learn, "QuestFont", textColor, 10)
        PageItems(spells, 6)
    end
    if #received > 0 or money > 0 or xp > 0 then
        PageText(#choices > 0 and W.alsoReceive or W.receive, "QuestFont", textColor, 10)
        PageItems(received, 6)
        if money > 0 then PageText(Money(money), "QuestFont", textColor, 6) end
        if xp > 0 then PageText(W.experience .. " " .. Number(xp), "QuestFont", textColor, 4) end
    end
end

local asked = {}   -- quests whose text was asked for once already

local function RenderPage(questID, resetScroll)
    ClearPage()
    page.questID = questID
    local textColor, titleColor = PageColors()
    if not questID then
        PageText(W.noQuests, "QuestFont", textColor)
        LayoutPage()
        return
    end

    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    local description, objectives = WithSelected(questID, GetQuestLogQuestText, logIndex)
    local title = C_QuestLog.GetTitleForQuestID(questID) or ""
    if C_QuestLog.IsFailed(questID) then title = title .. " (" .. W.failed .. ")" end
    PageText(title, "QuestTitleFont", titleColor)

    if (not description or description == "") and (not objectives or objectives == "") and not asked[questID] then
        asked[questID] = true
        if C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(questID) end
        PageText(W.loading, "QuestFont", textColor, 8)
        LayoutPage()
        return
    end

    if objectives and objectives ~= "" then PageText(objectives, "QuestFont", textColor, 6) end

    local done = DoneColor()
    local first = true
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        if o.type ~= "spell" and o.type ~= "log" then
            local text = (o.text and o.text ~= "") and o.text or o.type or ""
            if o.finished then
                PageText(text .. " (" .. W.complete .. ")", "QuestFontNormalSmall", done, first and 10 or 2)
            else
                PageText(text, "QuestFontNormalSmall", textColor, first and 10 or 2)
            end
            first = false
        end
    end

    local money = C_QuestLog.GetRequiredMoney and C_QuestLog.GetRequiredMoney(questID) or 0
    if money > 0 then
        PageText(W.requiredMoney .. " " .. Money(money), "QuestFont", GetMoney() < money and COLOR_PAGE_RED or textColor, 10)
    end
    local group = C_QuestLog.GetSuggestedGroupSize and C_QuestLog.GetSuggestedGroupSize(questID) or 0
    if group > 0 then
        PageText(Format(W.groupSize, "Suggested Players [%d]", group), "QuestFont", textColor, 10)
    end

    if description and description ~= "" then
        PageText(W.description, "QuestTitleFont", titleColor, 20)
        PageText(description, "QuestFont", textColor, 6)
    end

    AddRewards(questID, textColor, titleColor)
    LayoutPage()
    if resetScroll then pageScroll:SetVerticalScroll(0) end
    -- Once more next frame, when every font has its size
    C_Timer.After(0, function()
        if page.questID == questID then LayoutPage() end
    end)
end

---------------------------------------------------------------------------
-- The list of quests
---------------------------------------------------------------------------
Box(listPane, COLOR_LIST)

local countText = listPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
countText:SetPoint("TOPLEFT", listPane, "TOPLEFT", 8, -6)

local allButton = CreateFrame("Button", nil, listPane)
allButton:SetPoint("TOPRIGHT", listPane, "TOPRIGHT", -6, -3)
allButton:SetSize(90, 18)
allButton:SetNormalFontObject(GameFontNormalSmall)
allButton:SetHighlightFontObject(GameFontHighlightSmall)
allButton:SetText(W.collapseAll)
do
    local fs = allButton:GetFontString()
    fs:ClearAllPoints()
    fs:SetAllPoints(allButton)
    fs:SetJustifyH("RIGHT")
end

local listScroll = CreateFrame("ScrollFrame", nil, listPane)
listScroll:SetPoint("TOPLEFT", listPane, "TOPLEFT", 4, -LIST_TOP)
listScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -16, 4)
listScroll:EnableMouseWheel(true)
local listBar = CreateFrame("EventFrame", nil, listPane, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 4, -4)
listBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 4, 4)
listBar:SetHideIfUnscrollable(true)
ScrollUtil.InitScrollFrameWithScrollBar(listScroll, listBar)

local listChild = CreateFrame("Frame", nil, listScroll)
listChild:SetSize(LIST_W - 20, 10)
listScroll:SetScrollChild(listChild)

local emptyText = listPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("TOP", listPane, "TOP", 0, -60)
emptyText:SetText(W.noQuests)
emptyText:Hide()

local entries = {}   -- the rows to draw: zones, and the quests of the open ones
local order = {}     -- every quest, in list order, open zone or not
local zones = {}
local rows = {}
local Refresh, Select, ToggleTrack

local function RowClick(self, button)
    local e = self.entry
    if not e then return end
    if e.isHeader then
        if IsShiftKeyDown() then
            local collapse = false
            for _, z in ipairs(zones) do if not z.collapsed then collapse = true end end
            for _, z in ipairs(zones) do charDB.collapsed[z.title] = collapse or nil end
        else
            charDB.collapsed[e.title] = (not e.collapsed) or nil
        end
        Refresh()
        return
    end
    if button == "RightButton" then
        ToggleTrack(e.questID)
    elseif IsShiftKeyDown() then
        -- Shift-click: into the chat line when one is open, else track or untrack, as in Classic
        if not InsertLink(GetQuestLink and GetQuestLink(e.questID)) then ToggleTrack(e.questID) end
    else
        Select(e.questID)
    end
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, listChild)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.selected = r:CreateTexture(nil, "BACKGROUND")
    r.selected:SetAllPoints(r)
    r.selected:SetTexture(TITLE_HIGHLIGHT)
    r.selected:SetBlendMode("ADD")
    r.selected:Hide()
    r.hover = r:CreateTexture(nil, "HIGHLIGHT")
    r.hover:SetAllPoints(r)
    r.hover:SetTexture(TITLE_HIGHLIGHT)
    r.hover:SetBlendMode("ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.tag = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    r.tag:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.tag:SetJustifyH("RIGHT")
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", RowClick)
    rows[i] = r
    return r
end

local function QuestTag(q)
    if C_QuestLog.IsFailed(q.questID) then return W.failed, true end
    if C_QuestLog.IsComplete(q.questID) then return W.complete end
    local info = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(q.questID)
    if info and info.tagName and info.tagName ~= "" then return info.tagName end
    if C_QuestLog.IsEliteQuest and C_QuestLog.IsEliteQuest(q.questID) then return W.elite end
    local freq = Enum and Enum.QuestFrequency
    if freq and q.frequency == freq.Daily then return W.daily end
    if freq and q.frequency == freq.Weekly then return W.weekly end
end

local function BuildList()
    wipe(entries)
    wipe(order)
    wipe(zones)
    local loose, all = {}, {}
    local zone
    local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                zone = { isHeader = true, title = info.title or "", quests = {} }
                all[#all + 1] = zone
            elseif info.questID and not info.isHidden and not info.isTask and not info.isBounty and not info.isInternalOnly then
                local q = { questID = info.questID, title = info.title or "", level = info.level,
                    difficulty = info.difficultyLevel, scaling = info.isScaling, frequency = info.frequency }
                if zone then
                    zone.quests[#zone.quests + 1] = q
                else
                    loose[#loose + 1] = q
                end
            end
        end
    end
    for _, q in ipairs(loose) do
        entries[#entries + 1] = q
        order[#order + 1] = q
    end
    for _, z in ipairs(all) do
        if #z.quests > 0 then
            z.collapsed = charDB.collapsed[z.title] and true or false
            zones[#zones + 1] = z
            entries[#entries + 1] = z
            for _, q in ipairs(z.quests) do
                order[#order + 1] = q
                if not z.collapsed then entries[#entries + 1] = q end
            end
        end
    end
end

-- The chosen quest stays chosen while it's in the log; else the first one shown.
local function ValidateSelection()
    for _, q in ipairs(order) do
        if q.questID == charDB.selected then return end
    end
    local pick
    for _, e in ipairs(entries) do
        if not e.isHeader then pick = e.questID break end
    end
    charDB.selected = pick or (order[1] and order[1].questID) or nil
end

local function DrawList()
    for i, e in ipairs(entries) do
        local r = Row(i)
        r.entry = e
        r.text:ClearAllPoints()
        if e.isHeader then
            r.icon:SetTexture(e.collapsed and PLUS or MINUS)
            r.icon:Show()
            r.text:SetPoint("LEFT", r, "LEFT", 20, 0)
            r.text:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
            r.text:SetText(e.title)
            r.text:SetTextColor(COLOR_HEADER[1], COLOR_HEADER[2], COLOR_HEADER[3])
            r.tag:SetText("")
            r.hover:SetVertexColor(0.6, 0.6, 0.6)
            r.selected:Hide()
        else
            local cr, cg, cb = DifficultyColor(e)
            if C_QuestLog.GetQuestWatchType(e.questID) ~= nil then
                r.icon:SetTexture(CHECK)
                r.icon:Show()
            else
                r.icon:Hide()
            end
            r.text:SetPoint("LEFT", r, "LEFT", 22, 0)
            r.text:SetPoint("RIGHT", r.tag, "LEFT", -4, 0)
            r.text:SetText(e.level and e.level > 0 and ("[" .. e.level .. "] " .. e.title) or e.title)
            local tag, failed = QuestTag(e)
            r.tag:SetText(tag and ("(" .. tag .. ")") or "")
            if failed then
                r.tag:SetTextColor(COLOR_FAILED[1], COLOR_FAILED[2], COLOR_FAILED[3])
            else
                r.tag:SetTextColor(cr, cg, cb)
            end
            r.hover:SetVertexColor(cr, cg, cb)
            if e.questID == charDB.selected then
                r.selected:SetVertexColor(cr, cg, cb)
                r.selected:Show()
                r.text:SetTextColor(1, 1, 1)
            else
                r.selected:Hide()
                r.text:SetTextColor(cr, cg, cb)
            end
        end
        r:Show()
    end
    for i = #entries + 1, #rows do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    listChild:SetHeight(math.max(1, #entries * ROW_H))
    listScroll:UpdateScrollChildRect()
    emptyText:SetShown(#order == 0)

    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    local consts = Constants and Constants.QuestLogConsts
    local max = consts and consts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT
    if numQuests and max then
        local color = numQuests > max and (RED_FONT_COLOR_CODE or "|cffff2020") or "|cffffffff"
        countText:SetText(Format(W.countTemplate, "Quests: %s%d|r/%d", color, numQuests, max))
    else
        countText:SetText("")
    end

    local anyOpen = false
    for _, z in ipairs(zones) do if not z.collapsed then anyOpen = true end end
    allButton:SetText(anyOpen and W.collapseAll or W.expandAll)
    allButton:SetShown(#zones > 0)
    allButton.collapse = anyOpen
end

allButton:SetScript("OnClick", function(self)
    for _, z in ipairs(zones) do charDB.collapsed[z.title] = self.collapse or nil end
    Refresh()
end)

---------------------------------------------------------------------------
-- The buttons under the pages, and abandoning
---------------------------------------------------------------------------
local abandonButton = FlatButton(frame, 96, W.abandon)
abandonButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, 6)
local shareButton = FlatButton(frame, 96, W.share)
shareButton:SetPoint("LEFT", abandonButton, "RIGHT", 6, 0)
local closeButton = FlatButton(frame, 96, W.close)
closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 6)
closeButton:SetScript("OnClick", function() frame:Hide() end)
local trackButton = FlatButton(frame, 96, W.track)
trackButton:SetPoint("RIGHT", closeButton, "LEFT", -6, 0)

local ask = CreateFrame("Frame", "ForeverUIQuestLogAbandonFrame", frame)
ask:SetSize(320, 110)
ask:SetPoint("CENTER", frame, "CENTER", 0, 20)
ask:SetFrameStrata("DIALOG")
ask:EnableMouse(true)
ask:Hide()
Box(ask, { 0.08, 0.08, 0.08, 0.98 })
tinsert(UISpecialFrames, ask:GetName())
ask.text = ask:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ask.text:SetPoint("TOP", ask, "TOP", 0, -16)
ask.text:SetWidth(290)
ask.text:SetWordWrap(true)
local askYes = FlatButton(ask, 100, W.yes)
askYes:SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -4, 12)
local askNo = FlatButton(ask, 100, W.no)
askNo:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 4, 12)
askNo:SetScript("OnClick", function() ask:Hide() end)

-- Our own question instead of Blizzard's popup: a popup opened by an addon
-- carries the addon's taint into the popups that come after it.
local function AskAbandon(questID)
    if not questID or not C_QuestLog.CanAbandonQuest(questID) then return end
    local title = C_QuestLog.GetTitleForQuestID(questID) or ""
    local text = Format(W.abandonAsk, "Abandon \"%s\"?", title)
    local ids = WithSelected(questID, function()
        C_QuestLog.SetAbandonQuest()
        return C_QuestLog.GetAbandonQuestItems and C_QuestLog.GetAbandonQuestItems()
    end)
    local names = {}
    for _, itemID in ipairs(ids or {}) do
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        if name then names[#names + 1] = name end
    end
    if #names > 0 then
        text = text .. "\n\n|cffff4040" .. W.abandonItems .. "|r\n" .. table.concat(names, ", ")
    end
    ask.questID = questID
    ask.text:SetText(text)
    ask:SetHeight(ask.text:GetStringHeight() + 64)
    ask:Show()
end

askYes:SetScript("OnClick", function()
    local questID = ask.questID
    ask:Hide()
    if not questID or not C_QuestLog.GetLogIndexForQuestID(questID) then return end
    WithSelected(questID, function()
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
    end)
    Sound("IG_QUEST_LOG_ABANDON_QUEST")
end)

function ToggleTrack(questID)
    if not questID then return end
    if C_QuestLog.GetQuestWatchType(questID) ~= nil then
        C_QuestLog.RemoveQuestWatch(questID)
    else
        local consts = Constants and Constants.QuestWatchConsts
        local max = consts and consts.MAX_QUEST_WATCHES
        if max and C_QuestLog.GetNumQuestWatches() >= max then
            UIErrorsFrame:AddMessage(W.tooMany, 1.0, 0.1, 0.1, 1.0)
            return
        end
        C_QuestLog.AddQuestWatch(questID)
    end
end

local function UpdateButtons()
    local q = charDB.selected
    abandonButton:SetEnabled(q ~= nil and C_QuestLog.CanAbandonQuest(q) and true or false)
    shareButton:SetEnabled(q ~= nil and C_QuestLog.IsPushableQuest(q) and IsInGroup() and true or false)
    trackButton:SetEnabled(q ~= nil)
    trackButton:SetText(q and C_QuestLog.GetQuestWatchType(q) ~= nil and W.untrack or W.track)
end

abandonButton:SetScript("OnClick", function() AskAbandon(charDB.selected) end)
shareButton:SetScript("OnClick", function()
    local q = charDB.selected
    local index = q and C_QuestLog.GetLogIndexForQuestID(q)
    if index then
        QuestLogPushQuest(index)
        Sound("IG_QUEST_LOG_OPEN")
    end
end)
trackButton:SetScript("OnClick", function() ToggleTrack(charDB.selected) end)

---------------------------------------------------------------------------
-- Widths: the window's grip and the bar between the pages
---------------------------------------------------------------------------
local function Relayout()
    LayoutPanes()
    page:SetWidth(detailW - 16)
    listChild:SetWidth(listW - 20)
    LayoutPage()
    listScroll:UpdateScrollChildRect()
end

frame:SetScript("OnSizeChanged", function()
    if db then Relayout() end
end)

local function DragSplit()
    local left = frame:GetLeft()
    if not left or not db then return end
    local x = GetCursorPosition() / frame:GetEffectiveScale()
    local inner = frame:GetWidth() - 3 * PAD
    local leftW = x - left - PAD - PAD / 2          -- the width of the page on the left
    local d = db.listLeft and (inner - leftW) or leftW
    d = math.max(MIN_DETAIL, math.min(inner - MIN_LIST, d))
    db.split = d / inner
    Relayout()
end

divider:SetScript("OnEnter", function() dividerLine:Show() end)
divider:SetScript("OnLeave", function(self)
    if not self.dragging then dividerLine:Hide() end
end)
divider:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.dragging = true
    self:SetScript("OnUpdate", DragSplit)
end)
divider:SetScript("OnMouseUp", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    dividerLine:SetShown(self:IsMouseOver())
end)

---------------------------------------------------------------------------
-- Drawing it all
---------------------------------------------------------------------------
function Refresh(resetPage)
    if not charDB then return end
    BuildList()
    local before = charDB.selected
    ValidateSelection()
    DrawList()
    local q = charDB.selected
    RenderPage(q, resetPage or q ~= before or q ~= page.questID)
    UpdateButtons()
end

function Select(questID)
    if questID == charDB.selected then return end
    charDB.selected = questID
    Refresh(true)
end

-- The quest log changes in bursts: one redraw a frame at most, and only while open
local pending = false
local function RequestRefresh()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if frame:IsShown() then Refresh() end
    end)
end

local function Toggle()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
_G.ForeverUIQuestLog_Toggle = Toggle

frame:SetScript("OnShow", function()
    if db and db.openAt == "center" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    Sound("IG_QUEST_LOG_OPEN")
    Refresh()
end)

-- Everything the options set, at once
local function Apply()
    if not db then return end
    frame:SetFrameStrata(db.strata)
    -- The abandon question one layer above the window, never under a dialog
    local above = "DIALOG"
    for i, name in ipairs(STRATA) do
        if name == db.strata and STRATA[i + 1] and i + 1 > 5 then above = STRATA[i + 1] end
    end
    ask:SetFrameStrata(above)
    windowFill:SetColorTexture(COLOR_WINDOW[1], COLOR_WINDOW[2], COLOR_WINDOW[3], db.alpha)
    SetEscape(db.escape)
    grip:SetShown(not db.locked)
    Place()
    Relayout()
    if frame:IsShown() and db.openAt == "center" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
frame:SetScript("OnHide", function()
    Sound("IG_QUEST_LOG_CLOSE")
    ask:Hide()
end)

---------------------------------------------------------------------------
-- The quest log key: an override binding on its keys, to a button of ours, so
-- the key never opens Blizzard's (the map with its quest log). Bindings can't
-- change in combat, so a change then waits for it to end.
---------------------------------------------------------------------------
local keyOwner = CreateFrame("Frame")
local toggleButton = CreateFrame("Button", "ForeverUIQuestLogToggleButton", UIParent)
toggleButton:Hide()
toggleButton:SetScript("OnClick", Toggle)

local routed = nil       -- the keys taken now, as one string
local routePending = false

local function RouteKey()
    if InCombatLockdown() then
        routePending = true
        return
    end
    routePending = false
    local keys = {}
    if db and db.takeKey then keys = { GetBindingKey("TOGGLEQUESTLOG") } end
    local now = table.concat(keys, " ")
    if now == routed then return end
    ClearOverrideBindings(keyOwner)
    for _, key in ipairs(keys) do
        SetOverrideBindingClick(keyOwner, false, key, toggleButton:GetName())
    end
    routed = now
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UPDATE_BINDINGS")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_MONEY")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        ForeverUIQuestLogDB = ForeverUIQuestLogDB or {}
        ForeverUIQuestLogCharDB = ForeverUIQuestLogCharDB or {}
        db, charDB = ForeverUIQuestLogDB, ForeverUIQuestLogCharDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        charDB.collapsed = charDB.collapsed or {}
        Apply()
    elseif event == "PLAYER_LOGIN" or event == "UPDATE_BINDINGS" then
        RouteKey()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if routePending then RouteKey() end
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        -- (asked stays set: a quest whose text is really empty is drawn without it)
        if ... == page.questID then RequestRefresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if page.waitingItems then RequestRefresh() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if frame:IsShown() and charDB then UpdateButtons() end
    else
        RequestRefresh()
    end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
SLASH_FOREVERUIQUESTLOG1 = "/fql"
SLASH_FOREVERUIQUESTLOG2 = "/foreverql"
SlashCmdList.FOREVERUIQUESTLOG = function(msg)
    local cmd, rest = strmatch(strtrim(msg or ""):lower(), "^(%S*)%s*(.-)$")
    if not db then return end
    if cmd == "" then
        Toggle()
    elseif cmd == "swap" then
        db.listLeft = not db.listLeft
        Relayout()
        Print(db.listLeft and "The list is on the left now." or "The list is on the right now.")
    elseif cmd == "key" then
        db.takeKey = not db.takeKey
        RouteKey()
        local wait = routePending and " (after combat)" or ""
        Print((db.takeKey and "The quest log key opens this window" or "The quest log key opens Blizzard's quest log again") .. wait .. ".")
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 2 then
            db.scale = n
            frame:SetScale(n)
        else
            Print("/fql scale takes a number from 0.5 to 2.")
        end
    elseif cmd == "reset" then
        db.point, db.width, db.height, db.split, db.scale = nil, DEFAULT_W, DEFAULT_H, DEFAULT_SPLIT, 1
        Place()
        Relayout()
        Print("Place, size, the pages' widths and scale are back to the start.")
    elseif cmd == "options" and ForeverUI_OpenOptions then
        ForeverUI_OpenOptions("questlog")
    else
        Print("/fql opens or closes it. /fql swap: the list on the other side. /fql key: the quest log key for this window or for Blizzard's. /fql scale 1.2. /fql reset."
            .. (ForeverUI_OpenOptions and " /fql options: every setting." or ""))
    end
end

---------------------------------------------------------------------------
-- The ForeverUI options' "Quest log" page (ForeverUI's Options.lua draws it)
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
    key = "questlog",
    title = "Quest log",
    order = 30,
    build = function(K)
        K:Head("Quest log", "The classic two-page quest log: the quest's text on one page, the list on the other. The quest log key (L) opens it, and the map key (M) stays the map.")
        K:Buttons({ { "Open the quest log", function() frame:Show() end, true } })

        K:Section("The quest log key")
        K:Switch("L opens this window", Value("takeKey"), function(v)
            db.takeKey = v
            RouteKey()
        end)
        K:Note("Off, L opens Blizzard's quest log beside the map again, and this window keeps a key of its own in Key Bindings > AddOns.")

        K:Section("Window")
        K:Choice("Layer", { { "LOW", "Low" }, { "MEDIUM", "Medium" }, { "HIGH", "High" }, { "DIALOG", "Dialog" },
            { "FULLSCREEN_DIALOG", "Front of all" } }, Value("strata"), Set("strata"))
        K:Choice("Opens", { { "kept", "Where I left it" }, { "center", "Middle of the screen" } }, Value("openAt"), Set("openAt"))
        K:Switch("Locked in place", Value("locked"), Set("locked"))
        K:Slider("Scale", 0.5, 2, 0.05, Value("scale"), Set("scale"), "%.2f")
        K:Slider("Width", MIN_W, MAX_W, 10, function() return math.floor(frame:GetWidth() + 0.5) end, Set("width"), "%d")
        K:Slider("Height", MIN_H, MAX_H, 10, function() return math.floor(frame:GetHeight() + 0.5) end, Set("height"), "%d")
        K:Slider("Background opacity", 0.3, 1, 0.01, Value("alpha"), Set("alpha"), function(v)
            return string.format("%d%%", v * 100 + 0.5)
        end)
        K:Note("Front of all puts it over every other window. The grip in its corner and the bar between its pages size it too.")

        K:Section("Pages")
        K:Choice("The list", { { false, "On the right" }, { true, "On the left" } }, Value("listLeft"), Set("listLeft"))
        K:Slider("The text page's share", 0.3, 0.7, 0.01, Value("split"), Set("split"), function(v)
            return string.format("%d%%", v * 100 + 0.5)
        end)

        K:Section("Behavior")
        K:Switch("Escape closes it", Value("escape"), Set("escape"))
        K:Switch("Sounds", Value("sounds"), Set("sounds"))
    end,
    reset = function()
        for key, v in pairs(DEFAULTS) do db[key] = v end
        db.point = nil
        RouteKey()
        Apply()
    end,
}
