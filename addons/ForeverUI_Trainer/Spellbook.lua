-- ForeverUI Trainer in the spell book: a Trainer tab beside the book's own
-- tabs (below), and the book moves by its top bar, as ForeverUI's quest log
-- does, and opens where you left it.
--
-- The spell book (PlayerSpellsFrame) is one of the game's managed windows: the
-- game places it each time it, or another window, opens or closes. It is never
-- moved here with plain addon code, which would taint it (and the spells cast
-- from it): every move goes through a secure handler of the game's
-- (SecureHandlerBaseTemplate), out of combat, and right after the game has
-- placed it, it goes back where you put it. In combat it opens where the game
-- puts it, and goes back once the combat ends. Nothing is written into the
-- spell book's own tables.
-- EllesmereUI's Shifter, when it is on, moves Blizzard's windows itself (the
-- spell book too): this then stands aside.

local _, T = ...

local KEEP_X, KEEP_Y = 80, 40    -- how much of the book stays on the screen
local LEFT_GAP, RIGHT_GAP = 60, 60  -- the handle leaves the portrait and the buttons free
local HANDLE_H = 24

local mover = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local book, handle
local dragging           -- { cx, cy, x, y, nowX, nowY } while the top is held
local setupPending, restorePending = false, false
local updater = CreateFrame("Frame")
updater:Hide()

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Loaded(name)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local _, loaded = C_AddOns.IsAddOnLoaded(name)
    return loaded and true or false
end

-- EllesmereUI's Shifter, on
function T.ShifterOn()
    local E = _G.EllesmereUIDB
    return type(E) == "table" and E.shifterEnabled == true and Loaded("EllesmereUIQoL") or false
end

local function Active()
    local db = T.db
    return db and db.bookMove and book and not T.ShifterOn() and true or false
end

-- The book's top left corner at x, y: UIParent's units, from its top left
local function Put(x, y)
    if not book or InCombatLockdown() then return false end
    local ues, es = UIParent:GetEffectiveScale(), book:GetEffectiveScale()
    if not ues or not es or es == 0 or Secret(es) then return false end
    mover:SetFrameRef("book", book)
    mover:SetAttribute("bookx", x * ues / es)
    mover:SetAttribute("booky", y * ues / es)
    mover:Execute([[
        local f = self:GetFrameRef("book")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", "$parent", "TOPLEFT", self:GetAttribute("bookx"), self:GetAttribute("booky"))
    ]])
    return true
end

-- Where the book's top left corner is now, in the same units
local function Corner()
    local left, top = book:GetLeft(), book:GetTop()
    if not left or not top or Secret(left) or Secret(top) then return nil end
    local k = book:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * k, top * k - UIParent:GetHeight()
end

local function Restore()
    if not Active() or dragging or not book:IsShown() then return end
    local p = T.db.bookPoint
    if not p then return end
    if InCombatLockdown() then
        restorePending = true
        return
    end
    Put(p[1], p[2])
end

local function Clamp(x, y)
    local k = book:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w = (book:GetWidth() or 0) * k
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    x = math.max(KEEP_X - w, math.min(sw - KEEP_X, x))
    y = math.max(-(sh - KEEP_Y), math.min(0, y))
    return x, y
end

local function StopDrag()
    local d = dragging
    dragging = nil
    updater:Hide()
    if d and d.nowX and T.db then T.db.bookPoint = { d.nowX, d.nowY } end
end

updater:SetScript("OnUpdate", function()
    local d = dragging
    if not d or InCombatLockdown() then
        StopDrag()
        return
    end
    local cx, cy = GetCursorPosition()
    local ues = UIParent:GetEffectiveScale()
    local x, y = Clamp(d.x + (cx - d.cx) / ues, d.y + (cy - d.cy) / ues)
    if x ~= d.nowX or y ~= d.nowY then
        if Put(x, y) then d.nowX, d.nowY = x, y end
    end
end)

---------------------------------------------------------------------------
-- The Trainer tab: a square with the book beside the spell book's own
-- category tabs (General, the specs). It lays the trainer window over the
-- book's pages, on a ground of its own that keeps the clicks off the spells
-- under it, until another tab is picked, the search box is used, or the book
-- closes. Only the tab, the ground and the window are ours: nothing of the
-- book is hidden or changed.
---------------------------------------------------------------------------
local tab, pages
-- The tab is drawn as the book's own icon tabs are (their art by its atlas
-- names, nothing of their code run): the icon under the square mask, the
-- tab's frame over it, and its glow while it is the one open.
local TAB_W, TAB_H = 44, 40

local function PaintTab()
    if not tab then return end
    local on = pages and pages:IsShown() and true or false
    tab.frameArt:SetShown(not on)
    tab.frameOn:SetShown(on)
    tab.glow:SetShown(on)
end

function T.CloseBookPages()
    if pages and pages:IsShown() then
        pages:Hide()
        if T.HideBook then T.HideBook() end
    end
    PaintTab()
end

local sbfRef, pagedRef, tabsRef
local paper = {}         -- the book's parchment, copied over its pages (without EllesmereUI)

-- The ground starts under the book's tabs (they hang over the top of its
-- pages), and on parchment it is the book's own: its page textures, from the
-- ground's top down, so it runs on from what shows above.
local function FitGround()
    if not pages then return end
    local top = 6
    local pt, tb = pagedRef:GetTop(), tabsRef:GetBottom()
    if pt and tb and not Secret(pt) and not Secret(tb) and pt - tb > -6 then top = pt - tb + 6 end
    if pages.top ~= top then
        pages.top = top
        pages:ClearAllPoints()
        pages:SetPoint("TOPLEFT", pagedRef, "TOPLEFT", 8, -top)
        pages:SetPoint("BOTTOMRIGHT", pagedRef, "BOTTOMRIGHT", -8, 8)
    end
    -- the list: the same place, with its size given outright
    local pw, ph = pagedRef:GetWidth(), pagedRef:GetHeight()
    if T.FitBook and pw and ph and not Secret(pw) then T.FitBook(pagedRef, top) end
    for _, p in ipairs(paper) do
        local bg = p.bg
        local shown = bg and bg:IsShown() and bg:GetAtlas()
        local bt, bh, gt = bg and bg:GetTop(), bg and bg:GetHeight(), pagedRef:GetTop()
        if shown and bt and bh and bh > 0 and gt and not Secret(bt) then
            local cut = math.max(0, bt - (gt - top))
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(shown)
            if info and (info.file or info.filename) then
                p.tex:SetTexture(info.file or info.filename)
                local t, b = info.topTexCoord, info.bottomTexCoord
                p.tex:SetTexCoord(info.leftTexCoord, info.rightTexCoord, t + (b - t) * cut / bh, b)
                p.tex:ClearAllPoints()
                p.tex:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, -cut)
                p.tex:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
                p.tex:Show()
            else
                p.tex:Hide()
            end
        else
            p.tex:Hide()
        end
    end
end

-- A failure here says so in the chat once, with its line (the game hides Lua
-- errors unless its own option shows them)
local reported = {}
function T.Report(what, err)
    if reported[what] then return end
    reported[what] = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffe6b85cForeverUI Trainer|r: the spell book's " .. what
        .. " failed: " .. tostring(err) .. " (please send this line to the author)")
end

local function OpenBookPages()
    if not pages then return end
    if not T.ShowBook then
        T.Report("list", "ForeverUI_Trainer.lua did not load (a Lua error as the game loaded it)")
        return
    end
    local ok, err = pcall(FitGround)
    if not ok then T.Report("ground", err) end
    pages:SetFrameLevel(pagedRef:GetFrameLevel() + 30)
    pages:Show()
    ok, err = pcall(T.ShowBook, pages)
    if not ok then T.Report("list", err) end
    ok, err = pcall(FitGround)       -- (again: the list is made by now)
    if not ok then T.Report("ground", err) end
    PaintTab()
end

-- For /ftr book: where the ground is
function T.BookGround()
    if not pages then return "no Trainer tab in the spell book yet (the book not opened since the login)" end
    local w, h = pages:GetSize()
    local shown = 0
    for _, p in ipairs(paper) do
        if p.tex:IsShown() then shown = shown + 1 end
    end
    return string.format("ground: shown %s, visible %s, %dx%d, level %d (the book's pages %d), parchment %d of %d",
        tostring(pages:IsShown()), tostring(pages:IsVisible()), w or 0, h or 0, pages:GetFrameLevel(),
        pagedRef:GetFrameLevel(), shown, #paper)
end

local function MakeTab(sbf)
    local tabs = sbf.CategoryTabSystem
    local paged = sbf.PagedSpellsFrame
    if not (tabs and paged) then return end

    -- as big as one of the book's own tabs, beside the last of them
    local w, h = TAB_W, TAB_H
    local ref = tabs.GetChildren and select(1, tabs:GetChildren())
    if ref and ref.GetWidth then
        local rw, rh = ref:GetWidth(), ref:GetHeight()
        if rw and rw > 10 and not Secret(rw) then w = rw end
        if rh and rh > 10 and not Secret(rh) then h = rh end
    end
    tab = CreateFrame("Button", nil, sbf)
    tab:SetSize(w, h)
    tab:SetPoint("BOTTOMLEFT", tabs, "BOTTOMRIGHT", 10, 0)
    tab:SetFrameLevel(tabs:GetFrameLevel() + 2)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(36, 35)
    tab.icon:SetPoint("BOTTOM", tab, "BOTTOM", 0, 0)
    tab.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    local mask = tab:CreateMaskTexture()
    mask:SetAtlas("SquareMask")
    mask:SetPoint("TOPLEFT", tab.icon, "TOPLEFT", 0, -2)
    mask:SetPoint("BOTTOMRIGHT", tab.icon, "BOTTOMRIGHT", -2, 0)
    tab.icon:AddMaskTexture(mask)
    tab.frameArt = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.frameArt:SetAtlas("spellbook-Tab-Frame-C60", true)
    tab.frameArt:SetPoint("BOTTOM", tab, "BOTTOM", 0, 1)
    tab.frameOn = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.frameOn:SetAtlas("spellbook-Tab-Frame-Glow-C60", true)
    tab.frameOn:SetPoint("BOTTOM", tab, "BOTTOM", 0, 1)
    tab.glow = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.glow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60", true)
    tab.glow:SetPoint("BOTTOM", tab, "BOTTOM", 0, 0)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAtlas("spellbook-Tab-Frame-C60", true)
    hl:SetPoint("BOTTOM", tab, "BOTTOM", 0, 1)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)
    tab:SetScript("OnClick", function()
        if pages:IsShown() then T.CloseBookPages() else OpenBookPages() end
    end)
    -- the tooltip as the book's tabs have theirs (the name, then a line)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -12, 0)
        GameTooltip:SetText("Trainer", 1, 1, 1)
        local text = ForeverUITrainer_Summary and ForeverUITrainer_Summary()
        if text then GameTooltip:AddLine(text, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b) end
        GameTooltip:AddLine("ForeverUI Trainer: what your trainer has for you, and where.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- (PaintTab reads pages, made just below; shown off until then)
    tab.frameOn:Hide()
    tab.glow:Hide()

    -- the ground over the pages, under the list
    sbfRef, pagedRef, tabsRef = sbf, paged, tabs
    pages = CreateFrame("Frame", nil, sbf)
    pages:SetPoint("TOPLEFT", paged, "TOPLEFT", 8, -6)
    pages:SetPoint("BOTTOMRIGHT", paged, "BOTTOMRIGHT", -8, 8)
    pages:SetFrameLevel(paged:GetFrameLevel() + 30)
    pages:EnableMouse(true)
    pages:Hide()
    if T.BookLook and T.BookLook() == "paper" then
        -- the book's own page textures, copied (Spellbook.lua never changes them)
        for _, key in ipairs({ "BookBGLeft", "BookBGRight", "BookBGHalved" }) do
            local tex = pages:CreateTexture(nil, "BACKGROUND", nil, -7)
            tex:Hide()
            paper[#paper + 1] = { bg = sbf[key], tex = tex }
        end
    else
        local edge = pages:CreateTexture(nil, "BACKGROUND", nil, -8)
        edge:SetPoint("TOPLEFT", pages, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", pages, "BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0, 0, 0, 1)
        local fill = pages:CreateTexture(nil, "BACKGROUND", nil, -7)
        fill:SetAllPoints(pages)
        fill:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    end
    local fitting = false
    pages:SetScript("OnSizeChanged", function()
        if fitting then return end
        fitting = true
        FitGround()
        fitting = false
    end)

    -- back to the spells: another tab, the search box, the book closing
    if type(sbf.OnActiveCategoryChanged) == "function" then
        hooksecurefunc(sbf, "OnActiveCategoryChanged", T.CloseBookPages)
    end
    if sbf.SearchBox and sbf.SearchBox.HookScript then
        sbf.SearchBox:HookScript("OnEditFocusGained", T.CloseBookPages)
    end
    sbf:HookScript("OnHide", T.CloseBookPages)
end

function T.BookApply()
    if handle then handle:EnableMouse(Active()) end
    if tab then
        local on = T.db and T.db.bookTab and true or false
        tab:SetShown(on)
        if not on then T.CloseBookPages() end
    end
end

local function Setup()
    if book or not PlayerSpellsFrame then return end
    if InCombatLockdown() then
        setupPending = true
        return
    end
    setupPending = false
    book = PlayerSpellsFrame

    -- A strip of our own over the top bar, between the portrait and the buttons
    handle = CreateFrame("Frame", nil, book)
    handle:SetPoint("TOPLEFT", book, "TOPLEFT", LEFT_GAP, 0)
    handle:SetPoint("TOPRIGHT", book, "TOPRIGHT", -RIGHT_GAP, 0)
    handle:SetHeight(HANDLE_H)
    handle:SetFrameLevel(book:GetFrameLevel() + 10)
    handle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not Active() or InCombatLockdown() then return end
        local x, y = Corner()
        if not x then return end
        local cx, cy = GetCursorPosition()
        dragging = { cx = cx, cy = cy, x = x, y = y }
        updater:Show()
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and dragging then StopDrag() end
    end)
    handle:SetScript("OnHide", function()
        if dragging then StopDrag() end
    end)
    if book.SpellBookFrame then MakeTab(book.SpellBookFrame) end
    T.BookApply()

    -- Back where you put it after the game places it
    book:HookScript("OnShow", function()
        T.BookApply()
        C_Timer.After(0, Restore)
    end)
    hooksecurefunc("ShowUIPanel", function() if book:IsShown() then Restore() end end)
    hooksecurefunc("HideUIPanel", function() if book:IsShown() then Restore() end end)
    hooksecurefunc("UpdateUIPanelPositions", function() if book:IsShown() then Restore() end end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_PlayerSpells" then Setup() end
    elseif event == "PLAYER_LOGIN" then
        if Loaded("Blizzard_PlayerSpells") then Setup() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if setupPending then Setup() end
        if restorePending then
            restorePending = false
            Restore()
        end
    end
end)
