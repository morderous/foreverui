-- The game's world map window, without OpenMap: it moves by its title bar,
-- grows and shrinks from its two bottom corners, and wears the pack's flat
-- look (dark, flat, a 1px edge). With OpenMap, OpenMap's window does all of
-- this and nothing here is made; with Move Any, or EllesmereUI's Shifter on,
-- the window is theirs to place, and with EllesmereUI's window skin, the look
-- is theirs.
--
-- The map is the game's own: the game draws its pins, in combat too, and addon
-- code in that path can block them. So nothing here calls the map's functions
-- or writes into its tables. The window moves and sizes through a secure
-- handler of the game's (SecureHandlerBaseTemplate), out of combat, right
-- after the game has placed it. Its size is its scale: the map keeps its
-- shape, and the game never has to lay its canvas out again. The look only
-- fades the game's art and lays ours under the map. In combat the map opens
-- where the game puts it, and goes back once the combat ends.
-- The full-screen map is the game's: always at its own size and place.

local _, ns = ...

local MIN_SCALE, MAX_SCALE = 0.5, 2
local KEEP_X, KEEP_Y = 80, 40        -- how much of the window stays on the screen
local TITLE_H = 24                   -- the title row, which the drag takes
local LEFT_FLAT, LEFT_GAME = 4, 60   -- the drag leaves the portrait free (the game's look)
local RIGHT_GAP = 62                 -- and the two buttons at the top right
local GRIP = 18                      -- a corner's catch
local GRIP_OUT = 4                   -- how far its middle sits out of the corner

local GROUND = { 0.055, 0.055, 0.065, 0.97 }
local TITLE = { 0.09, 0.09, 0.105, 1 }
local LINE = { 0.20, 0.20, 0.25, 1 }
local MARK = { 0.45, 0.45, 0.50, 0.9 }

local mover = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local map, handle
local grips = {}
local drag              -- { kind, cx, cy, x, y, s, w, h, right, nowX, nowY, nowS } while held
local session           -- { x, y }: where it was dragged this time (middle of the screen)
local setupPending, restorePending, lookPending = false, false, false
local updater = CreateFrame("Frame")
updater:Hide()

local W = {}
ns.MapWindow = W

local function DB()
    ForeverUIDB = ForeverUIDB or {}
    return ForeverUIDB
end

-- A setting that is on until it is turned off
local function On(key)
    local v = DB()[key]
    return v == nil or v == true
end

local function Loaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Num(v)
    return type(v) == "number" and not Secret(v) and v or nil
end

local function ShifterOn()
    local E = _G.EllesmereUIDB
    return type(E) == "table" and E.shifterEnabled == true and Loaded("EllesmereUIQoL") or false
end

-- Who else places the window: nil when it is ours
function W.Owner()
    if Loaded("OpenMap") then return "OpenMap" end
    if Loaded("MoveAny") then return "Move Any" end
    if ShifterOn() then return "EllesmereUI's Shifter" end
    return nil
end

function W.Free()
    return map ~= nil and W.Owner() == nil
end

-- Who else dresses the window: nil when the look is ours to give
function W.Dresser()
    if Loaded("OpenMap") then return "OpenMap" end
    if Loaded("EllesmereUIBlizzardSkin") then return "EllesmereUI's window skin" end
    return nil
end

local function Flat()
    return map ~= nil and W.Dresser() == nil and On("mapFlat")
end

local function Maximized()
    return map ~= nil and map.isMaximized == true
end

---------------------------------------------------------------------------
-- Placing: the window's top left corner at x, y (UIParent's units, from its
-- top left) and its scale s, in one secure step. Without x, the scale alone.
---------------------------------------------------------------------------
local PUT = [[
    local f = self:GetFrameRef("worldmap")
    if not f then return end
    local s = self:GetAttribute("mapscale")
    if not s then return end
    f:SetScale(s)
    local x, y = self:GetAttribute("mapx"), self:GetAttribute("mapy")
    if x and y then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", "$parent", "TOPLEFT", x / s, y / s)
    end
]]

local refSet = false
local function Put(x, y, s)
    if not map or not refSet or InCombatLockdown() then return false end
    mover:SetAttribute("mapscale", s)
    mover:SetAttribute("mapx", x)
    mover:SetAttribute("mapy", y)
    mover:Execute(PUT)
    return true
end

-- Where the window is now: its top left corner, and its scale
local function Corner()
    local left, top, s = Num(map:GetLeft()), Num(map:GetTop()), Num(map:GetScale())
    if not left or not top or not s or s <= 0 then return nil end
    return left * s, top * s - UIParent:GetHeight(), s
end

local function Size(s)
    return (Num(map:GetWidth()) or 0) * s, (Num(map:GetHeight()) or 0) * s
end

local function MaxScale()
    local w, h = Num(map:GetWidth()), Num(map:GetHeight())
    local most = MAX_SCALE
    if w and w > 0 then most = math.min(most, UIParent:GetWidth() / w) end
    if h and h > 0 then most = math.min(most, UIParent:GetHeight() / h) end
    return math.max(MIN_SCALE, most)
end

local function WantedScale()
    if not On("mapResize") then return 1 end
    local s = tonumber(DB().mapScale) or 1
    return math.max(MIN_SCALE, math.min(MaxScale(), s))
end

local function Clamp(x, y, s)
    local w = Size(s)
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    x = math.max(KEEP_X - w, math.min(sw - KEEP_X, x))
    y = math.max(-(sh - KEEP_Y), math.min(0, y))
    return x, y
end

-- Where the window goes now; nil: where the game puts it
local function Wanted(s)
    if session then return session[1], session[2] end
    if DB().mapOpenAt == "center" then
        local w, h = Size(s)
        return (UIParent:GetWidth() - w) / 2, -(UIParent:GetHeight() - h) / 2
    end
    local p = DB().mapPoint
    if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) then return p[1], p[2] end
    return nil
end

-- Where the game puts the windowed map: its left panel place (the panel
-- layout's own numbers, as the game reckons it)
local function GamePlace(s)
    local left = GetUIPanelLayoutAttribute and tonumber(GetUIPanelLayoutAttribute("LEFT_OFFSET")) or 16
    local y = GetUIPanelLayoutAttribute and tonumber(GetUIPanelLayoutAttribute("TOP_OFFSET")) or -116
    local _, h = Size(s)
    local bottom = UIParent:GetHeight() + y - h
    if bottom < 140 then y = y + (140 - bottom) end
    if y > 0 then y = 0 end
    return left, y
end

local function Restore()
    if not map or drag or not map:IsShown() or not W.Free() then return end
    if InCombatLockdown() then
        restorePending = true
        return
    end
    local cx, cy, cs = Corner()
    if not cx then return end
    if Maximized() then
        if math.abs(cs - 1) > 0.001 then Put(nil, nil, 1) end
        return
    end
    local s = WantedScale()
    local x, y = Wanted(s)
    if x then
        x, y = Clamp(x, y, s)
    elseif math.abs(cs - s) > 0.001 then
        x, y = cx, cy                    -- the game's place, at the new size: its top left stays
    else
        return
    end
    if math.abs(cs - s) < 0.001 and math.abs(cx - x) < 0.5 and math.abs(cy - y) < 0.5 then return end
    Put(x, y, s)
end
W.Restore = Restore

---------------------------------------------------------------------------
-- The drag: the title bar moves the window, a bottom corner sizes it (the
-- other side of the top stays put). The size follows the corner along the
-- window's diagonal, so it keeps its shape.
---------------------------------------------------------------------------
local PaintGrips

local function Stop()
    local d = drag
    drag = nil
    updater:Hide()
    if PaintGrips then PaintGrips() end
    if not d or not d.moved then return end   -- (a click, no drag: nothing changes)
    if d.kind ~= "move" then DB().mapScale = d.nowS end
    if DB().mapOpenAt == "center" then
        session = { d.nowX, d.nowY }
    else
        DB().mapPoint = { d.nowX, d.nowY }
    end
end

local function Begin(kind)
    if drag or InCombatLockdown() or Maximized() or not W.Free() then return end
    local x, y, s = Corner()
    if not x then return end
    local w, h = Size(s)
    if w <= 0 or h <= 0 then return end
    local cx, cy = GetCursorPosition()
    drag = { kind = kind, cx = cx, cy = cy, x = x, y = y, s = s, w = w, h = h, right = x + w,
        nowX = x, nowY = y, nowS = s, moved = false }
    updater:Show()
    if PaintGrips then PaintGrips() end
end

updater:SetScript("OnUpdate", function()
    local d = drag
    if not d then
        updater:Hide()
        return
    end
    if InCombatLockdown() or not map:IsShown() or Maximized() or not IsMouseButtonDown("LeftButton") then
        Stop()
        return
    end
    local cx, cy = GetCursorPosition()
    local ues = UIParent:GetEffectiveScale()
    local dx, dy = (cx - d.cx) / ues, (cy - d.cy) / ues
    local x, y, s = d.x, d.y, d.s
    if d.kind == "move" then
        x, y = x + dx, y + dy
    else
        local out = d.kind == "BOTTOMLEFT" and -dx or dx
        local grow = 1 + (out * d.w - dy * d.h) / (d.w * d.w + d.h * d.h)
        s = math.max(MIN_SCALE, math.min(MaxScale(), d.s * grow))
        if d.kind == "BOTTOMLEFT" then x = d.right - (Num(map:GetWidth()) or 0) * s end
    end
    x, y = Clamp(x, y, s)
    if x ~= d.nowX or y ~= d.nowY or s ~= d.nowS then
        if Put(x, y, s) then d.nowX, d.nowY, d.nowS, d.moved = x, y, s, true end
    end
end)

-- Back where the game puts it (and, in the middle mode, in the middle)
function W.BackToPlace()
    DB().mapPoint = nil
    session = nil
    if not map or not map:IsShown() or Maximized() or not W.Free() or InCombatLockdown() then return end
    if DB().mapOpenAt == "center" then
        Restore()
    else
        local s = WantedScale()
        local x, y = GamePlace(s)
        Put(x, y, s)
    end
end

function W.BackToSize()
    DB().mapScale = nil
    Restore()
end

function W.SetScale(v)
    DB().mapScale = v
    Restore()
end

function W.Scale()
    return tonumber(DB().mapScale) or 1
end

---------------------------------------------------------------------------
-- The pieces: a strip over the title, and a catch in each bottom corner.
-- They are ours, on the map's border frame (over the map, under its buttons).
---------------------------------------------------------------------------
local function Controls()
    if not handle then return end
    local free = W.Free() and not Maximized()
    handle:SetShown(free and On("mapMove"))
    handle:SetPoint("TOPLEFT", map, "TOPLEFT", Flat() and LEFT_FLAT or LEFT_GAME, 0)
    for _, g in ipairs(grips) do g:SetShown(free and On("mapResize")) end
end
W.Controls = Controls

PaintGrips = function()
    local c = ForeverUI_Accent and ForeverUI_Accent() or { 1, 0.82, 0 }
    for _, g in ipairs(grips) do
        local hot = g.hot or (drag and drag.kind == g.corner)
        for _, t in ipairs(g.marks) do
            if hot then
                t:SetColorTexture(c[1], c[2], c[3], 1)
            else
                t:SetColorTexture(MARK[1], MARK[2], MARK[3], MARK[4])
            end
        end
    end
end

local function MakeGrip(corner, bf)
    local left = corner == "BOTTOMLEFT"
    local g = CreateFrame("Frame", nil, bf)
    g.corner = corner
    g:SetSize(GRIP, GRIP)
    g:SetPoint("CENTER", map, corner, left and -GRIP_OUT or GRIP_OUT, -GRIP_OUT)
    g:SetFrameLevel(math.min(bf:GetFrameLevel() + 900, 9000))
    g:EnableMouse(true)
    -- the mark: a little corner along the window's edges
    local across = g:CreateTexture(nil, "OVERLAY")
    across:SetSize(10, 2)
    across:SetPoint(corner, map, corner, 0, 0)
    local up = g:CreateTexture(nil, "OVERLAY")
    up:SetSize(2, 10)
    up:SetPoint(corner, map, corner, 0, 0)
    g.marks = { across, up }
    g:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Begin(corner) end
    end)
    g:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and drag then
            Stop()
        elseif button == "RightButton" and not drag then
            W.BackToSize()
        end
    end)
    g:SetScript("OnEnter", function(self)
        self.hot = true
        PaintGrips()
    end)
    g:SetScript("OnLeave", function(self)
        self.hot = nil
        PaintGrips()
    end)
    g:SetScript("OnHide", function()
        if drag and drag.kind == corner then Stop() end
    end)
    grips[#grips + 1] = g
end

local function MakeHandle(bf)
    handle = CreateFrame("Frame", nil, bf)
    handle:SetPoint("TOPLEFT", map, "TOPLEFT", LEFT_GAME, 0)
    handle:SetPoint("TOPRIGHT", map, "TOPRIGHT", -RIGHT_GAP, 0)
    handle:SetHeight(TITLE_H)
    handle:SetFrameLevel(bf:GetFrameLevel() + 2)
    handle:EnableMouse(true)
    handle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Begin("move") end
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and drag then
            Stop()
        elseif button == "RightButton" and not drag then
            W.BackToPlace()
        end
    end)
    handle:SetScript("OnHide", function()
        if drag and drag.kind == "move" then Stop() end
    end)
end

---------------------------------------------------------------------------
-- The look: the game's gold frame, portrait and grey bars faded out, and a
-- dark flat ground with a 1px edge laid under the map. The map, the bar of
-- places and the buttons stay the game's.
---------------------------------------------------------------------------
local look              -- our textures, made once
local faded = {}        -- the game's pieces we faded, and their alpha before

local function Pieces()
    local bf = map.BorderFrame
    local list = { bf.NineSlice, bf.PortraitContainer, bf.Bg, bf.InsetBorderTop, bf.TopTileStreaks }
    local nav = map.NavBar
    if nav then
        for _, region in ipairs({ nav:GetRegions() }) do list[#list + 1] = region end
        if nav.overlay then list[#list + 1] = nav.overlay end
    end
    return list
end

local function MakeLook()
    look = {}
    local function Tex(sublevel, c)
        local t = map:CreateTexture(nil, "BACKGROUND", nil, sublevel)
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        look[#look + 1] = t
        return t
    end
    local edge = Tex(-8, { 0, 0, 0, 1 })
    edge:SetPoint("TOPLEFT", map, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 1, -1)
    local ground = Tex(-7, GROUND)
    ground:SetAllPoints(map)
    local title = Tex(-5, TITLE)
    title:SetPoint("TOPLEFT", map, "TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", map, "TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    local under = Tex(-4, LINE)
    under:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
    under:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, 0)
    under:SetHeight(1)
    local sc = map.ScrollContainer
    if sc then
        local over = Tex(-4, LINE)
        over:SetPoint("BOTTOMLEFT", sc, "TOPLEFT", 0, 0)
        over:SetPoint("BOTTOMRIGHT", sc, "TOPRIGHT", 0, 0)
        over:SetHeight(1)
    end
end

-- The close and full-screen buttons inside the title row (the game's stick
-- out over the top edge), and back as the game had them
local buttonsWere
local function FitButtons(flat)
    local bf = map.BorderFrame
    local close, both = bf.CloseButton, bf.MaximizeMinimizeFrame
    if not close then return end
    if flat then
        if not buttonsWere then
            local point, rel, relPoint, x, y = close:GetPoint(1)
            if not point or Secret(x) or Secret(y) then return end
            buttonsWere = { point = { point, rel, relPoint, x, y },
                w = close:GetWidth(), h = close:GetHeight(),
                bw = both and both:GetWidth(), bh = both and both:GetHeight() }
        end
        close:SetSize(TITLE_H - 2, TITLE_H - 2)
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1, -1)
        if both then both:SetSize(TITLE_H - 2, TITLE_H - 2) end
    elseif buttonsWere then
        local p = buttonsWere.point
        close:SetSize(buttonsWere.w, buttonsWere.h)
        close:ClearAllPoints()
        close:SetPoint(p[1], p[2], p[3], p[4], p[5])
        if both and buttonsWere.bw then both:SetSize(buttonsWere.bw, buttonsWere.bh) end
    end
end

local function ApplyLook()
    if not map then return end
    if InCombatLockdown() then
        lookPending = true
        return
    end
    lookPending = false
    if Flat() then
        if not look then MakeLook() end
        for _, t in ipairs(look) do t:Show() end
        for _, piece in ipairs(Pieces()) do
            if piece and piece.SetAlpha and faded[piece] == nil then
                faded[piece] = piece:GetAlpha()
                piece:SetAlpha(0)
            end
        end
        FitButtons(true)
    else
        if look then
            for _, t in ipairs(look) do t:Hide() end
        end
        for piece, alpha in pairs(faded) do piece:SetAlpha(alpha) end
        wipe(faded)
        FitButtons(false)
    end
    Controls()
end
W.ApplyLook = ApplyLook

---------------------------------------------------------------------------
-- Setting up, once the game's map is there (out of combat)
---------------------------------------------------------------------------
local function Setup()
    if map or not _G.WorldMapFrame then return end
    if Loaded("OpenMap") then return end         -- OpenMap's window: nothing of ours
    if InCombatLockdown() then
        setupPending = true
        return
    end
    setupPending = false
    local m = _G.WorldMapFrame
    local bf = m.BorderFrame
    if not bf then return end
    map = m
    -- (a map the secure handlers can't take: it then stays where the game puts it)
    refSet = pcall(mover.SetFrameRef, mover, "worldmap", map) and true or false

    MakeHandle(bf)
    MakeGrip("BOTTOMRIGHT", bf)
    MakeGrip("BOTTOMLEFT", bf)
    PaintGrips()
    ApplyLook()

    -- Back where you put it after the game places it
    map:HookScript("OnShow", function()
        Controls()
        Restore()
        C_Timer.After(0, Restore)
    end)
    map:HookScript("OnHide", function()
        if drag then Stop() end
        session = nil
    end)
    local function Again()
        if map:IsShown() then
            Controls()
            Restore()
        end
    end
    hooksecurefunc("ShowUIPanel", Again)
    hooksecurefunc("HideUIPanel", Again)
    hooksecurefunc("UpdateUIPanelPositions", Again)
    if map:IsShown() then Again() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_WorldMap" then Setup() end
    elseif event == "PLAYER_LOGIN" then
        Setup()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if setupPending then Setup() end
        if lookPending then ApplyLook() end
        if restorePending then
            restorePending = false
            Restore()
        end
    end
end)
