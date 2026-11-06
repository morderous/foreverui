-- ForeverUI's Move UI, in the way of the game's Edit Mode: a grid over the
-- screen, and the pack's bars and notices as they are, each outlined in the
-- class color with its name on a tag, to drag where you want it. Let go near
-- a line of the grid (or the middle of the screen) and it snaps to it. A bar
-- on top says what to do, with "Reset all" and "Done". Right click one: back
-- to its place. Escape or "Done" ends it, and the options come back.
--
-- Only what has no other way to move: the windows (the quest log, the
-- trainer) move by their own title bars at any time.
--
-- Each addon of the pack brings its own: it adds
--   { key = "xpbar", title = "XP bar", frame = theFrame,
--     set = function(point, relPoint, x, y) ... end, reset = function() ... end,
--     show = function() ... end, hide = function() ... end, usable = function() ... end }
-- to the global ForeverUI_Movers. set keeps the new place (relative to
-- UIParent) and puts the frame there; show and hide (optional) show a frame
-- that is hidden now while it moves; usable (optional) leaves it out when it
-- returns false (the XP bar turned off, say).
--
-- Opened by the options' "Move UI" button, the F's menu or /fui move.

ForeverUI_Movers = ForeverUI_Movers or {}

local GRID = 32          -- the grid's step, in UIParent's units
local SNAP = 8           -- how near a line snaps
local MUTED = { 0.60, 0.60, 0.65 }
local TEXT = { 0.90, 0.90, 0.92 }

local bar, grid, active
local marks = {}
local shownHere = {}     -- [mover] = true: shown for the move, hidden after
local backToOptions = false

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local ok = pcall(fs.SetFont, fs, ForeverUI_FontPath(), size, "")
    if not ok or not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function Boxed(f, r, g, b, a, er, eg, eb)
    local e = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    e:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    e:SetColorTexture(er, eg, eb, 1)
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetAllPoints(f)
    fill:SetColorTexture(r, g, b, a)
    return fill, e
end

local function Button(parent, label, strong)
    local c = ForeverUI_Accent()
    local b = CreateFrame("Button", nil, parent)
    b.word = Text(b, 11, TEXT)
    b.word:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.word:SetText(label)
    b:SetSize(math.ceil(b.word:GetStringWidth()) + 28, 22)
    local ground, edge
    if strong then
        ground, edge = Boxed(b, c[1], c[2], c[3], 0.85, c[1], c[2], c[3])
        b.word:SetTextColor(1, 1, 1)
    else
        ground, edge = Boxed(b, 0.075, 0.075, 0.095, 1, 0.20, 0.20, 0.25)
    end
    b:SetScript("OnEnter", function()
        edge:SetColorTexture(c[1], c[2], c[3], 1)
        if not strong then ground:SetColorTexture(c[1], c[2], c[3], 0.12) end
    end)
    b:SetScript("OnLeave", function()
        if strong then return end
        edge:SetColorTexture(0.20, 0.20, 0.25, 1)
        ground:SetColorTexture(0.075, 0.075, 0.095, 1)
    end)
    return b
end

local Stop               -- (below)

local function Usable(m)
    if type(m) ~= "table" or not m.frame or not m.set then return false end
    if m.usable and not m.usable() then return false end
    return true
end

---------------------------------------------------------------------------
-- The grid: faint lines every GRID from the middle of the screen out, the
-- two middle lines in the class color
---------------------------------------------------------------------------
local function Line(parent, vertical, offset, middle)
    local c = ForeverUI_Accent()
    local t = parent:CreateTexture(nil, "BACKGROUND")
    if middle then
        t:SetColorTexture(c[1], c[2], c[3], 0.45)
    else
        t:SetColorTexture(1, 1, 1, 0.08)
    end
    if vertical then
        t:SetWidth(1)
        t:SetPoint("TOP", parent, "TOP", offset, 0)
        t:SetPoint("BOTTOM", parent, "BOTTOM", offset, 0)
    else
        t:SetHeight(1)
        t:SetPoint("LEFT", parent, "LEFT", 0, offset)
        t:SetPoint("RIGHT", parent, "RIGHT", 0, offset)
    end
end

local function MakeGrid()
    grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:SetFrameLevel(0)
    grid:Hide()
    local shade = grid:CreateTexture(nil, "BACKGROUND", nil, -8)
    shade:SetAllPoints(grid)
    shade:SetColorTexture(0, 0, 0, 0.25)
    local w, h = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    Line(grid, true, 0, true)
    Line(grid, false, 0, true)
    for d = GRID, math.max(w, h), GRID do
        if d < w then
            Line(grid, true, d)
            Line(grid, true, -d)
        end
        if d < h then
            Line(grid, false, d)
            Line(grid, false, -d)
        end
    end
end

-- A frame let go near a line goes onto it: its left, right or middle onto a
-- vertical line, its top, bottom or middle onto a horizontal one. Returns its
-- new top left corner (UIParent's units, from UIParent's top left) or nil.
local function Snap(f)
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, top, right, bottom = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
    if not (left and top and right and bottom) then return nil end
    left, top, right, bottom = left * k, top * k, right * k, bottom * k
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    local function Near(values, middle)
        local best, shift
        for _, v in ipairs(values) do
            local onto = middle + math.floor((v - middle) / GRID + 0.5) * GRID
            local d = onto - v
            if math.abs(d) <= SNAP and (not best or math.abs(d) < best) then best, shift = math.abs(d), d end
        end
        return shift or 0
    end
    local dx = Near({ (left + right) / 2, left, right }, cx)
    local dy = Near({ (top + bottom) / 2, top, bottom }, cy)
    return left + dx, top + dy - UIParent:GetHeight(), k
end

---------------------------------------------------------------------------
-- The outline over each thing that moves
---------------------------------------------------------------------------
local function MakeMark(m)
    local c = ForeverUI_Accent()
    local b = CreateFrame("Button", nil, UIParent)
    b:SetFrameStrata("FULLSCREEN")
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("RightButtonUp")
    b.wash = b:CreateTexture(nil, "BACKGROUND")
    b.wash:SetAllPoints(b)
    b.wash:SetColorTexture(c[1], c[2], c[3], 0.06)
    b.lines = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], 0.9)
        t:SetPoint(spec[1], b, spec[1], 0, 0)
        t:SetPoint(spec[2], b, spec[2], 0, 0)
        if spec[3] then t:SetHeight(2) else t:SetWidth(2) end
        b.lines[i] = t
    end
    -- the name on a tag over the top left corner
    b.tag = CreateFrame("Frame", nil, b)
    b.tag:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 2)
    b.tag:SetHeight(18)
    Boxed(b.tag, c[1], c[2], c[3], 0.9, 0, 0, 0)
    b.tag.word = Text(b.tag, 10, { 1, 1, 1 })
    b.tag.word:SetPoint("LEFT", b.tag, "LEFT", 6, 0)
    b.tag.word:SetText(m.title or m.key or "?")
    b.tag:SetWidth(math.ceil(b.tag.word:GetStringWidth()) + 12)
    local function Lit(on)
        b.wash:SetColorTexture(c[1], c[2], c[3], on and 0.16 or 0.06)
        for _, t in ipairs(b.lines) do t:SetColorTexture(c[1], c[2], c[3], on and 1 or 0.9) end
    end
    b:SetScript("OnEnter", function()
        Lit(true)
        GameTooltip:SetOwner(b, "ANCHOR_CURSOR")
        GameTooltip:SetText(m.title or m.key or "?", c[1], c[2], c[3])
        GameTooltip:AddLine("Drag: move it (it snaps to the grid)", 1, 1, 1)
        if m.reset then GameTooltip:AddLine("Right click: back to its place", 1, 1, 1) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        Lit(false)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStart", function()
        local f = m.frame
        GameTooltip:Hide()
        f:SetMovable(true)
        f:StartMoving()
        b.moving = true
    end)
    b:SetScript("OnDragStop", function()
        if not b.moving then return end
        b.moving = nil
        local f = m.frame
        f:StopMovingOrSizing()
        local x, y, k = Snap(f)
        if x then
            m.set("TOPLEFT", "TOPLEFT", x / k, y / k)
        else
            local point, _, relPoint, px, py = f:GetPoint(1)
            if point then m.set(point, relPoint, px, py) end
        end
    end)
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" and m.reset then m.reset() end
    end)
    return b
end

local function MakeBar()
    local c = ForeverUI_Accent()
    bar = CreateFrame("Frame", "ForeverUIMoveBar", UIParent)
    bar:SetSize(460, 62)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -12)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:Hide()
    Boxed(bar, 0.055, 0.055, 0.065, 0.97, 0, 0, 0)
    local title = Text(bar, 14, c)
    title:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -10)
    title:SetText("Move UI")
    local line = Text(bar, 10, MUTED)
    line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    line:SetWidth(270)
    line:SetJustifyH("LEFT")
    line:SetText("Drag what is outlined; it snaps to the grid. Right click it: back to its place.")
    local done = Button(bar, "Done", true)
    done:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    done:SetScript("OnClick", function() Stop() end)
    local reset = Button(bar, "Reset all")
    reset:SetPoint("RIGHT", done, "LEFT", -8, 0)
    reset:SetScript("OnClick", function()
        for _, m in ipairs(ForeverUI_Movers) do
            if Usable(m) and m.reset then m.reset() end
        end
    end)
    tinsert(UISpecialFrames, bar:GetName())   -- Escape ends it
    bar:SetScript("OnHide", function() if active then Stop() end end)
end

local function Start()
    if active or InCombatLockdown() then return end
    if not bar then MakeBar() end
    if not grid then MakeGrid() end
    active = true
    backToOptions = ForeverUIOptions and ForeverUIOptions:IsShown() or false
    if ForeverUIOptions then ForeverUIOptions:Hide() end
    grid:Show()
    for i, m in ipairs(ForeverUI_Movers) do
        if Usable(m) then
            if not m.frame:IsShown() then
                if m.show then m.show() else m.frame:Show() end
                shownHere[m] = true
            end
            marks[i] = marks[i] or MakeMark(m)
            local b = marks[i]
            b:ClearAllPoints()
            b:SetAllPoints(m.frame)
            b:Show()
        end
    end
    bar:Show()
end

function Stop()
    if not active then return end
    active = false
    for _, b in pairs(marks) do
        if b.moving then b:GetScript("OnDragStop")(b) end
        b:Hide()
    end
    for m in pairs(shownHere) do
        if m.hide then m.hide() else m.frame:Hide() end
    end
    wipe(shownHere)
    grid:Hide()
    bar:Hide()
    if backToOptions and ForeverUI_OpenOptions then ForeverUI_OpenOptions() end
end

function ForeverUI_MoveUI()
    if active then Stop() else Start() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function() Stop() end)
