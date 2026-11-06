-- ForeverUI's minimap button: a flat square with an F in the class's color,
-- a black edge that lights up under the mouse, in the look of Survivor UI's.
-- Click: a menu of the pack's windows (Trainer, Quest log), Move UI and the
-- options. Right click: the options.
--
-- Two places for it (the options' General page, after a /reload):
-- - "ellesmere": in EllesmereUI Minimap's list of addon buttons, which opens
--   under the mouse. EllesmereUI gathers the minimap's own named child buttons
--   at least 20 wide, so the button is one of those, and EllesmereUI places,
--   sizes, shows and hides it (its own minimap options).
-- - "own": on the minimap's edge, to drag round it (it keeps to the edge, of
--   a round minimap or a square one). It sits in a frame that is not a
--   button, so EllesmereUI leaves it out of its list.
-- With EllesmereUI Minimap on, the first is the default.

local COLORS = {
    class = nil,                       -- the class's
    gold = { 1.00, 0.78, 0.15 },
    white = { 1.00, 1.00, 1.00 },
    blue = { 0.40, 0.65, 1.00 },
}
local DEFAULT_ANGLE = 225              -- degrees round the minimap: its bottom left
local TEXT = { 0.90, 0.90, 0.92 }
local MUTED = { 0.60, 0.60, 0.65 }

local function DB()
    ForeverUIDB = ForeverUIDB or {}
    return ForeverUIDB
end

local function Loaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Tint()
    return COLORS[DB().mapButtonColor or "class"] or ForeverUI_Accent()
end

-- The place chosen, or the default
local function Place()
    local place = DB().mapButtonPlace
    if place == "own" or place == "ellesmere" then return place end
    return Loaded("EllesmereUIMinimap") and "ellesmere" or "own"
end

local mode            -- the place this session, fixed when the button is made
local holder, button, edge, letter

local function Lit(on)
    if not edge then return end
    if on then
        local c = Tint()
        edge:SetColorTexture(c[1], c[2], c[3], 1)
    else
        edge:SetColorTexture(0, 0, 0, 1)
    end
end

-- The F as big as the button, whoever sized it
local function FitLetter()
    if not letter then return end
    local size = math.max(8, math.floor(math.min(button:GetWidth(), button:GetHeight()) * 0.8 + 0.5))
    local ok = pcall(letter.SetFont, letter, ForeverUI_FontPath(), size, "OUTLINE")
    if not ok or not letter:GetFont() then letter:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
    letter:SetText("F")
    local c = Tint()
    letter:SetTextColor(c[1], c[2], c[3])
end

---------------------------------------------------------------------------
-- On the minimap's edge: an angle round its middle
---------------------------------------------------------------------------
-- Where an angle puts the button's middle, from the minimap's middle: on the
-- circle of a round minimap, on the sides of a square one (an addon that
-- squares it says so with GetMinimapShape).
function ForeverUI_MinimapEdge(angle, size)
    local a = math.rad(angle)
    local x, y = math.cos(a), math.sin(a)
    local over = math.floor((size or 18) / 2) - 6        -- how far out of the edge it sits
    local hw, hh = Minimap:GetWidth() / 2 + over, Minimap:GetHeight() / 2 + over
    local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
    if shape ~= "ROUND" then
        local k = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * k, y * k
    end
    return x * hw, y * hh
end

-- Cuts textures to a circle with the game's round mask (the one its
-- portraits use)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function ForeverUI_Round(owner, ...)
    for i = 1, select("#", ...) do
        local tex = select(i, ...)
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end
end

-- The angle from the minimap's middle to the mouse
function ForeverUI_MinimapCursorAngle()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(cy / s - my, cx / s - mx))
end

local function Angle()
    local db = DB()
    if db.mapButtonAngle then return db.mapButtonAngle end
    -- (a place from before, dragged freely round the minimap)
    if db.mapButtonX and db.mapButtonY then return math.deg(math.atan2(db.mapButtonY, db.mapButtonX)) end
    return DEFAULT_ANGLE
end

function ForeverUI_MapButtonApply()
    if not button then return end
    local db = DB()
    if mode == "own" then
        local size = db.mapButtonSize or 18
        holder:SetSize(size, size)
        holder:ClearAllPoints()
        if Minimap then
            local x, y = ForeverUI_MinimapEdge(Angle(), size)
            holder:SetPoint("CENTER", Minimap, "CENTER", x, y)
        else
            holder:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -12, -12)
        end
        holder:SetShown(db.mapButton ~= false)
    end
    FitLetter()
end

---------------------------------------------------------------------------
-- The menu: the pack's windows, Move UI and the options
---------------------------------------------------------------------------
local menu
local rows = {}

local function MenuItems()
    local items = {}
    if ForeverUITrainer_Toggle then
        items[#items + 1] = { "Trainer", "Interface\\Icons\\INV_Misc_Book_11", ForeverUITrainer_Toggle, ForeverUITrainer_Summary }
    end
    if ForeverUIQuestLog_Toggle then
        items[#items + 1] = { "Quest log", "Interface\\Icons\\INV_Misc_Book_08", ForeverUIQuestLog_Toggle }
    end
    if ForeverUI_MoveUI then
        items[#items + 1] = { "Move UI", "Interface\\Cursor\\UI-Cursor-Move", ForeverUI_MoveUI }
    end
    items[#items + 1] = { "Options", "Interface\\AddOns\\ForeverUI\\Media\\Icon", function() ForeverUI_ToggleOptions() end }
    return items
end

local function MakeMenu()
    menu = CreateFrame("Frame", "ForeverUIMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu.edge = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
    menu.edge:SetPoint("TOPLEFT", menu, "TOPLEFT", -1, 1)
    menu.edge:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 1, -1)
    local ground = menu:CreateTexture(nil, "BACKGROUND", nil, -7)
    ground:SetAllPoints(menu)
    ground:SetColorTexture(0.055, 0.055, 0.065, 0.97)
    menu.title = menu:CreateFontString(nil, "OVERLAY")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
    tinsert(UISpecialFrames, menu:GetName())
    -- a click anywhere else closes it
    menu:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not (button and button:IsMouseOver()) then self:Hide() end
    end)
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
end

local function MenuRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetHeight(24)
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetAllPoints(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.word = row:CreateFontString(nil, "OVERLAY")
    row.word:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.detail = row:CreateFontString(nil, "OVERLAY")
    row.detail:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row:SetScript("OnEnter", function(self)
        local c = Tint()
        self.wash:SetColorTexture(c[1], c[2], c[3], 0.14)
        self.word:SetTextColor(1, 1, 1)
    end)
    row:SetScript("OnLeave", function(self)
        self.wash:SetColorTexture(0, 0, 0, 0)
        self.word:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    end)
    row:SetScript("OnClick", function(self)
        menu:Hide()
        if self.run then self.run() end
    end)
    rows[i] = row
    return row
end

local function SetFont(fs, size)
    local ok = pcall(fs.SetFont, fs, ForeverUI_FontPath(), size, "")
    if not ok or not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
end

local function ShowMenu()
    if not menu then MakeMenu() end
    local c = Tint()
    menu.edge:SetColorTexture(c[1], c[2], c[3], 1)
    SetFont(menu.title, 10)
    menu.title:SetText("FOREVERUI")
    menu.title:SetTextColor(c[1], c[2], c[3])
    local items = MenuItems()
    local width = 150
    for i, item in ipairs(items) do
        local row = MenuRow(i)
        SetFont(row.word, 11)
        SetFont(row.detail, 10)
        row.word:SetText(item[1])
        row.word:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
        row.icon:SetTexture(item[2])
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.run = item[3]
        local text, color = nil, nil
        if item[4] then text, color = item[4]() end
        color = color or MUTED
        row.detail:SetText(text or "")
        row.detail:SetTextColor(color[1], color[2], color[3])
        row.wash:SetColorTexture(0, 0, 0, 0)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -24 - (i - 1) * 24)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -24 - (i - 1) * 24)
        row:Show()
        width = math.max(width, 8 + 16 + 8 + row.word:GetStringWidth() + 16 + row.detail:GetStringWidth() + 10)
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    menu:SetSize(math.ceil(width), 24 + #items * 24 + 6)
    -- beside the mouse, on the side with room
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    x, y = x / s, y / s
    menu:ClearAllPoints()
    local h = x > UIParent:GetWidth() / 2 and "RIGHT" or "LEFT"
    local v = y > UIParent:GetHeight() / 2 and "TOP" or "BOTTOM"
    menu:SetPoint(v .. h, UIParent, "BOTTOMLEFT", x, y)
    menu:Show()
end

local function ToggleMenu()
    if menu and menu:IsShown() then menu:Hide() else ShowMenu() end
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------
local function Make()
    if button then return end
    mode = Place()
    if not Minimap then mode = "own" end
    if mode == "ellesmere" then
        -- A child button of the minimap, 24 wide (EllesmereUI's own size): its list takes it.
        -- Until it does (or if it never does), it shows outside the minimap's corner.
        button = CreateFrame("Button", "ForeverUIMinimapButton", Minimap)
        button:SetSize(24, 24)
        button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        button:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", -5, 0)
    else
        holder = CreateFrame("Frame", "ForeverUIMapButtonHolder", Minimap or UIParent)
        holder:SetSize(18, 18)
        holder:SetFrameStrata("MEDIUM")
        holder:SetFrameLevel((Minimap and Minimap:GetFrameLevel() or 1) + 8)
        if holder.SetDontSavePosition then holder:SetDontSavePosition(true) end
        button = CreateFrame("Button", "ForeverUIMinimapButton", holder)
        button:SetAllPoints(holder)
        button:RegisterForDrag("LeftButton")
        -- dragged, it slides round the minimap's edge after the mouse
        button:SetScript("OnDragStart", function(self)
            if not Minimap then return end
            if menu then menu:Hide() end
            self:SetScript("OnUpdate", function()
                DB().mapButtonAngle = ForeverUI_MinimapCursorAngle()
                ForeverUI_MapButtonApply()
            end)
        end)
        button:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            DB().mapButtonX, DB().mapButtonY = nil, nil
            ForeverUI_MapButtonApply()
        end)
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- On the minimap's edge it is round (an edge ring and a dark disc), in
    -- EllesmereUI's list square like the others there.
    local round = mode == "own"
    local out = round and 2 or 1
    edge = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetPoint("TOPLEFT", button, "TOPLEFT", -out, out)
    edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", out, -out)
    edge:SetColorTexture(0, 0, 0, 1)
    local ground = button:CreateTexture(nil, "BACKGROUND", nil, -7)
    ground:SetAllPoints(button)
    ground:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    if round then ForeverUI_Round(button, edge, ground) end
    letter = button:CreateFontString(nil, "OVERLAY")
    letter:SetPoint("CENTER", button, "CENTER", round and 0.5 or 1, 0)

    button:SetScript("OnSizeChanged", FitLetter)
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if menu then menu:Hide() end
            ForeverUI_ToggleOptions()
        else
            GameTooltip:Hide()
            ToggleMenu()
        end
    end)
    button:SetScript("OnEnter", function(self)
        Lit(true)
        local c = Tint()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("ForeverUI", c[1], c[2], c[3])
        GameTooltip:AddLine("Click: the menu (" .. (ForeverUITrainer_Toggle and "trainer, " or "")
            .. (ForeverUIQuestLog_Toggle and "quest log, " or "") .. "Move UI, options)", 1, 1, 1, true)
        GameTooltip:AddLine("Right click: options", 1, 1, 1)
        if mode == "own" then GameTooltip:AddLine("Drag: slide it round the minimap", 0.7, 0.7, 0.7) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        Lit(false)
        GameTooltip:Hide()
    end)
    ForeverUI_MapButtonApply()
end

-- Made as ForeverUI's settings load: before EllesmereUI gathers the minimap's
-- buttons, which it does from the login on.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "ForeverUI" then return end
    Make()
    ForeverUI_MapButtonApply()
end)

---------------------------------------------------------------------------
-- The options' first page: this button and the look
---------------------------------------------------------------------------
ForeverUI_Pages = ForeverUI_Pages or {}
ForeverUI_Pages[#ForeverUI_Pages + 1] = {
    key = "general",
    title = "General",
    order = 10,
    build = function(K)
        K:Head("General", "The minimap button, and the ForeverUI look.")
        K:Section("Minimap button")
        local hasEllesmere = Loaded("EllesmereUIMinimap")
        K:Choice("Place", { { "ellesmere", "In EllesmereUI's list" }, { "own", "On the minimap's edge" } },
            Place, function(v) DB().mapButtonPlace = v end,
            function() return hasEllesmere end)
        if hasEllesmere then
            K:Buttons({ { "Reload to move it", function()
                if Place() ~= mode then ReloadUI() end
            end } })
            K:Note("A new place takes a reload. In EllesmereUI's list it opens with the others under the mouse; EllesmereUI's minimap options show, hide and size it there.")
        else
            K:Note("EllesmereUI Minimap is off: the button sits on the minimap's edge.")
        end
        local function Own() return mode == "own" end
        local function OwnShown() return mode == "own" and DB().mapButton ~= false end
        K:Switch("Show it", function() return DB().mapButton ~= false end, function(v)
            DB().mapButton = v
            ForeverUI_MapButtonApply()
        end, Own)
        K:Slider("Size", 14, 32, 1, function() return DB().mapButtonSize or 18 end, function(v)
            DB().mapButtonSize = v
            ForeverUI_MapButtonApply()
        end, "%d", OwnShown)
        K:Choice("Color", { { "class", "Class" }, { "gold", "Gold" }, { "white", "White" }, { "blue", "Blue" } },
            function() return DB().mapButtonColor or "class" end,
            function(v)
                DB().mapButtonColor = v
                ForeverUI_MapButtonApply()
            end)
        K:Buttons({ { "Back to its place", function()
            if mode ~= "own" then return end
            local db = DB()
            db.mapButtonAngle, db.mapButtonX, db.mapButtonY = nil, nil, nil
            ForeverUI_MapButtonApply()
        end } })
        K:Note("On the minimap's edge: drag it, and it slides round the edge after the mouse. Click: the menu (the trainer, the quest log, Move UI, these options). Right click: these options.")
        K:Section("The ForeverUI look")
        K:Buttons({ { "Install the look", function()
            if ForeverUI_ShowInstaller then ForeverUI_ShowInstaller() end
        end } })
        K:Note("The EllesmereUI profile, the Edit Mode layout and the interface settings of the pack. /fui undo puts your old setup back.")
    end,
    reset = function()
        local db = DB()
        db.mapButton, db.mapButtonSize, db.mapButtonColor, db.mapButtonX, db.mapButtonY = nil, nil, nil, nil, nil
        db.mapButtonAngle, db.mapButtonPlace = nil, nil
        ForeverUI_MapButtonApply()
    end,
}
