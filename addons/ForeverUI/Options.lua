-- ForeverUI options: one window for the pack's settings, a page per addon in
-- the sidebar, in the look of Survivor UI's options.
--
-- Each addon of the pack brings its own page. It adds
--   { key = "xpbar", title = "XP bar", order = 20, build = function(K) ... end,
--     reset = function() ... end }
-- to the global ForeverUI_Pages, and build lays the page out with the kit K:
-- K:Head, K:Section, K:Switch, K:Choice, K:Slider, K:Color, K:Buttons, K:Note,
-- K:Line.
-- Each control reads its value with get and writes it with set; after any
-- change every control of the page refreshes, so the ones that depend on
-- another (usable) fade with it. reset, when given, is "Reset this page".
--
-- Opened by the minimap button, /fui options, the addon compartment, or
-- ForeverUI_OpenOptions(key).

local WIDTH, HEIGHT = 720, 600
local SIDEBAR = 168
local PAGE_X = SIDEBAR + 18
local PAGE_W = WIDTH - PAGE_X - 30      -- (room for the scroll bar)
local LABEL_W = 170                      -- the controls' column
local MUTED = { 0.60, 0.60, 0.65 }
local TEXT = { 0.90, 0.90, 0.92 }
local WELL = { 0.075, 0.075, 0.095 }     -- a control's ground
local EDGE = { 0.20, 0.20, 0.25 }        -- and its edge
local GROUND = { 0.055, 0.055, 0.065, 0.97 }
local SIDE_GROUND = { 0.035, 0.035, 0.045, 1 }

ForeverUI_Pages = ForeverUI_Pages or {}

---------------------------------------------------------------------------
-- Shared bits: the class color and the font
---------------------------------------------------------------------------
function ForeverUI_Accent()
    local _, class = UnitClass("player")
    if class and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c and c.r then return { c.r, c.g, c.b } end
    end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return { 1, 0.82, 0 }
end

-- EllesmereUI's font when it is there, the game's otherwise.
function ForeverUI_FontPath()
    local E = _G.EllesmereUI
    if E and E.GetFontPath then
        local ok, path = pcall(E.GetFontPath)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return STANDARD_TEXT_FONT
end

local function Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    local ok = pcall(fs.SetFont, fs, ForeverUI_FontPath(), size, "")
    if not ok or not fs:GetFont() then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    return fs
end

local function Fill(parent, layer, r, g, b, a, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel or 0)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- A 1px edge round a ground
local function Boxed(f, ground, edge)
    local e = Fill(f, "BACKGROUND", edge[1], edge[2], edge[3], 1, -8)
    e:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    local g = Fill(f, "BACKGROUND", ground[1], ground[2], ground[3], ground[4] or 1, -7)
    g:SetAllPoints(f)
    return g, e
end

local function Light(color, share)
    share = share or 0.35
    return color[1] + (1 - color[1]) * share, color[2] + (1 - color[2]) * share, color[3] + (1 - color[3]) * share
end

---------------------------------------------------------------------------
-- The kit: what a page is made of
---------------------------------------------------------------------------
local Kit = {}
Kit.__index = Kit

function Kit:Add(widget)
    self.widgets[#self.widgets + 1] = widget
    return widget
end

function Kit:Refresh()
    for _, w in ipairs(self.widgets) do w:Refresh() end
end

-- Faded and still while what it depends on is off
local function Usable(usable)
    return not usable or usable() and true or false
end

function Kit:Head(title, line)
    local t = Text(self.page, 15, self.color)
    t:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, 0)
    t:SetText(title)
    self.y = -26
    if line then
        local l = Text(self.page, 10, MUTED)
        l:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, self.y)
        l:SetWidth(PAGE_W)
        l:SetWordWrap(true)
        l:SetText(line)
        self.y = self.y - l:GetStringHeight() - 10
    end
    local rule = Fill(self.page, "ARTWORK", self.color[1], self.color[2], self.color[3], 0.22)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, self.y)
    rule:SetPoint("TOPRIGHT", self.page, "TOPRIGHT", 0, self.y)
    self.y = self.y - 8
end

function Kit:Section(text)
    self.y = self.y - 10
    local l = Text(self.page, 9, MUTED)
    l:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, self.y)
    l:SetText(string.upper(text))
    self.y = self.y - 18
end

-- A muted line under the controls, the page's width
function Kit:Note(text)
    local l = Text(self.page, 10, MUTED)
    l:SetPoint("TOPLEFT", self.page, "TOPLEFT", 0, self.y + 2)
    l:SetWidth(PAGE_W)
    l:SetWordWrap(true)
    l:SetText(text)
    self.y = self.y - l:GetStringHeight() - 8
end

local function Label(K, text, height)
    local l = Text(K.page, 11, TEXT)
    l:SetPoint("TOPLEFT", K.page, "TOPLEFT", 0, K.y - math.floor((height - 11) / 2) - 1)
    l:SetWidth(LABEL_W - 10)
    l:SetWordWrap(false)
    l:SetText(text)
    return l
end

-- On or off: a pill with On / Off beside it. detail (optional): a function
-- giving a few words and their color, shown after it (a state).
function Kit:Switch(label, get, set, usable, detail)
    local K = self
    local name = Label(K, label, 20)
    local s = CreateFrame("Button", nil, K.page)
    s:SetSize(80, 20)
    s:SetPoint("TOPLEFT", K.page, "TOPLEFT", LABEL_W, K.y)
    s.track = Fill(s, "BORDER", 0.22, 0.22, 0.27, 1)
    s.track:SetSize(32, 16)
    s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
    s.knob = Fill(s, "ARTWORK", 1, 1, 1, 1)
    s.knob:SetSize(12, 12)
    s.word = Text(s, 11, TEXT)
    s.word:SetPoint("LEFT", s.track, "RIGHT", 8, 0)
    if detail then
        s.detail = Text(K.page, 10, MUTED)
        s.detail:SetPoint("LEFT", s, "RIGHT", 6, 0)
        s.detail:SetWidth(PAGE_W - LABEL_W - 86)
        s.detail:SetWordWrap(false)
    end
    s:SetScript("OnClick", function()
        if not Usable(usable) then return end
        set(not get())
        K:Refresh()
    end)
    s:SetScript("OnEnter", function(self) self.hot = true self:Refresh() end)
    s:SetScript("OnLeave", function(self) self.hot = nil self:Refresh() end)
    function s:Refresh()
        local can = Usable(usable)
        self:SetAlpha(can and 1 or 0.4)
        name:SetAlpha(can and 1 or 0.4)
        local on = get() and true or false
        local c = K.color
        self.knob:ClearAllPoints()
        if on then
            self.track:SetColorTexture(c[1], c[2], c[3], 0.9)
            self.knob:SetPoint("RIGHT", self.track, "RIGHT", -2, 0)
            self.knob:SetColorTexture(1, 1, 1, 1)
        else
            self.track:SetColorTexture(0.22, 0.22, 0.27, 1)
            self.knob:SetPoint("LEFT", self.track, "LEFT", 2, 0)
            self.knob:SetColorTexture(0.62, 0.62, 0.66, 1)
        end
        self.word:SetText(on and "On" or "Off")
        if self.hot then
            self.word:SetTextColor(1, 1, 1)
        elseif on then
            self.word:SetTextColor(Light(c, 0.3))
        else
            self.word:SetTextColor(1, 0.42, 0.36)
        end
        if self.detail then
            local text, color = detail()
            color = color or MUTED
            self.detail:SetText(text or "")
            self.detail:SetTextColor(color[1], color[2], color[3])
        end
    end
    K.y = K.y - 28
    return K:Add(s)
end

-- A name and a state: get gives a few words and their color
function Kit:Line(label, get)
    local K = self
    Label(K, label, 16)
    local v = Text(K.page, 11, TEXT)
    v:SetPoint("TOPLEFT", K.page, "TOPLEFT", LABEL_W, K.y - 2)
    v:SetWidth(PAGE_W - LABEL_W)
    v:SetWordWrap(false)
    local line = {}
    function line:Refresh()
        local text, color = get()
        color = color or TEXT
        v:SetText(text or "")
        v:SetTextColor(color[1], color[2], color[3])
    end
    K.y = K.y - 22
    return K:Add(line)
end

-- One of a few, side by side in one box: the chosen one lit with a bar under
-- it. options: { { value, "Name" }, ... }. Too wide for the column, it goes
-- under its name.
function Kit:Choice(label, options, get, set, usable)
    local K = self
    local name = Label(K, label, 24)
    local holder = CreateFrame("Frame", nil, K.page)
    holder:SetHeight(24)
    Boxed(holder, WELL, EDGE)
    holder.parts = {}
    local x = 2
    for _, option in ipairs(options) do
        local part = CreateFrame("Button", nil, holder)
        part:SetHeight(20)
        part:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -2)
        part.wash = Fill(part, "BACKGROUND", 1, 1, 1, 0)
        part.wash:SetAllPoints(part)
        part.bar = Fill(part, "BORDER", 1, 1, 1, 0)
        part.bar:SetHeight(2)
        part.bar:SetPoint("BOTTOMLEFT", part, "BOTTOMLEFT", 0, 0)
        part.bar:SetPoint("BOTTOMRIGHT", part, "BOTTOMRIGHT", 0, 0)
        part.word = Text(part, 10, TEXT)
        part.word:SetPoint("CENTER", part, "CENTER", 0, 0)
        part.word:SetText(option[2])
        part:SetWidth(math.ceil(part.word:GetStringWidth()) + 20)
        part.value = option[1]
        x = x + part:GetWidth()
        part:SetScript("OnClick", function(self)
            if not Usable(usable) then return end
            set(self.value)
            K:Refresh()
        end)
        part:SetScript("OnEnter", function(self) self.hot = true holder:Refresh() end)
        part:SetScript("OnLeave", function(self) self.hot = nil holder:Refresh() end)
        holder.parts[#holder.parts + 1] = part
    end
    holder:SetWidth(x + 2)
    if x + 2 > PAGE_W - LABEL_W then
        K.y = K.y - 22
        holder:SetPoint("TOPLEFT", K.page, "TOPLEFT", 0, K.y)
    else
        holder:SetPoint("TOPLEFT", K.page, "TOPLEFT", LABEL_W, K.y)
    end
    function holder:Refresh()
        local can = Usable(usable)
        self:SetAlpha(can and 1 or 0.4)
        name:SetAlpha(can and 1 or 0.4)
        local chosen = get()
        local c = K.color
        for _, part in ipairs(self.parts) do
            local on = chosen == part.value
            part.wash:SetColorTexture(c[1], c[2], c[3], on and 0.24 or (part.hot and 0.08 or 0))
            part.bar:SetColorTexture(c[1], c[2], c[3], on and 1 or 0)
            if part.hot then
                part.word:SetTextColor(1, 1, 1)
            elseif on then
                part.word:SetTextColor(Light(c))
            else
                part.word:SetTextColor(TEXT[1] * 0.75, TEXT[2] * 0.75, TEXT[3] * 0.78)
            end
        end
    end
    K.y = K.y - 32
    return K:Add(holder)
end

-- A bar to drag, with the value on its right. format: a format string or a
-- function of the value.
function Kit:Slider(label, low, high, step, get, set, format, usable)
    local K = self
    local name = Label(K, label, 18)
    local width = PAGE_W - LABEL_W
    local holder = CreateFrame("Frame", nil, K.page)
    holder:SetSize(width, 18)
    holder:SetPoint("TOPLEFT", K.page, "TOPLEFT", LABEL_W, K.y)
    holder.value = Text(holder, 10, K.color)
    holder.value:SetPoint("RIGHT", holder, "RIGHT", -2, 0)
    holder.value:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width - 64, 14)
    slider:SetPoint("LEFT", holder, "LEFT", 0, 0)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouseWheel(true)
    slider.track = Fill(slider, "BACKGROUND", 0.14, 0.14, 0.18, 1)
    slider.track:SetHeight(4)
    slider.track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    slider.track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    slider.fill = Fill(slider, "BORDER", K.color[1], K.color[2], K.color[3], 0.8)
    slider.fill:SetHeight(4)
    slider.fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
    local thumb = Fill(slider, "OVERLAY", 1, 1, 1, 1)
    thumb:SetSize(8, 14)
    slider:SetThumbTexture(thumb)
    local function Round(v)
        return math.floor(v / step + 0.5) * step
    end
    local function Show(v)
        holder.value:SetText(type(format) == "function" and format(v) or string.format(format or "%d", v))
        slider.fill:SetWidth(math.max(1, (slider:GetWidth() - 8) * (v - low) / (high - low) + 4))
    end
    slider:SetScript("OnValueChanged", function(self)
        local v = Round(self:GetValue())
        Show(v)
        if self.quiet then return end
        if not Usable(usable) then
            self.quiet = true
            self:SetValue(get())
            self.quiet = nil
            return
        end
        if v ~= self.last then
            self.last = v
            set(v)
            K:Refresh()
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.min(high, math.max(low, self:GetValue() + delta * step)))
    end)
    slider:SetScript("OnEnter", function() thumb:SetColorTexture(K.color[1], K.color[2], K.color[3], 1) end)
    slider:SetScript("OnLeave", function() thumb:SetColorTexture(1, 1, 1, 1) end)
    function holder:Refresh()
        local can = Usable(usable)
        self:SetAlpha(can and 1 or 0.4)
        name:SetAlpha(can and 1 or 0.4)
        local v = get()
        slider.quiet = true
        slider:SetValue(v)
        slider.quiet = nil
        slider.last = Round(v)
        Show(Round(v))
    end
    K.y = K.y - 26
    return K:Add(holder)
end

-- A color: a swatch that opens the game's color picker. get returns
-- { r, g, b, a }; hasAlpha lets the picker set the opacity too.
function Kit:Color(label, get, set, hasAlpha, usable)
    local K = self
    local name = Label(K, label, 18)
    local b = CreateFrame("Button", nil, K.page)
    b:SetSize(40, 18)
    b:SetPoint("TOPLEFT", K.page, "TOPLEFT", LABEL_W, K.y)
    local _, edge = Boxed(b, { 0, 0, 0, 1 }, EDGE)
    b.swatch = Fill(b, "ARTWORK", 1, 1, 1, 1)
    b.swatch:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    b.swatch:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function() edge:SetColorTexture(K.color[1], K.color[2], K.color[3], 1) end)
    b:SetScript("OnLeave", function() edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1) end)
    b:SetScript("OnClick", function()
        if not Usable(usable) or not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
        local c = get()
        local function Picked()
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            local a = c[4] or 1
            if hasAlpha and ColorPickerFrame.GetColorAlpha then a = ColorPickerFrame:GetColorAlpha() or a end
            set({ r, g, bl, a })
            K:Refresh()
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = hasAlpha and true or false,
            swatchFunc = Picked, opacityFunc = Picked,
            cancelFunc = function()
                local r, g, bl, a = ColorPickerFrame:GetPreviousValues()
                set({ r, g, bl, a or c[4] or 1 })
                K:Refresh()
            end,
        })
    end)
    function b:Refresh()
        local can = Usable(usable)
        self:SetAlpha(can and 1 or 0.4)
        name:SetAlpha(can and 1 or 0.4)
        local c = get()
        self.swatch:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    K.y = K.y - 26
    return K:Add(b)
end

-- A row of buttons: { { "Text", onClick, strong }, ... }. A strong one is
-- filled with the page's color; the rest are outlines.
function Kit:Buttons(list)
    local K = self
    local x = 0
    for _, spec in ipairs(list) do
        local b = CreateFrame("Button", nil, K.page)
        b.word = Text(b, 11, TEXT)
        b.word:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.word:SetText(spec[1])
        b:SetSize(math.ceil(b.word:GetStringWidth()) + 28, 22)
        b:SetPoint("TOPLEFT", K.page, "TOPLEFT", x, K.y)
        local c = K.color
        local ground, edge = Boxed(b, spec[3] and { c[1], c[2], c[3], 0.85 } or WELL, spec[3] and c or EDGE)
        if spec[3] then b.word:SetTextColor(1, 1, 1) end
        b:SetScript("OnEnter", function()
            edge:SetColorTexture(c[1], c[2], c[3], 1)
            if not spec[3] then ground:SetColorTexture(c[1], c[2], c[3], 0.12) end
        end)
        b:SetScript("OnLeave", function()
            if spec[3] then return end
            edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
            ground:SetColorTexture(WELL[1], WELL[2], WELL[3], 1)
        end)
        b:SetScript("OnClick", function()
            spec[2]()
            K:Refresh()
        end)
        x = x + b:GetWidth() + 8
    end
    K.y = K.y - 32
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win, pageScroll, current
local tabs, built = {}, {}

local function Sorted()
    local list = {}
    for _, spec in ipairs(ForeverUI_Pages) do
        if type(spec) == "table" and spec.key and spec.build then list[#list + 1] = spec end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    return list
end

local function DB()
    ForeverUIDB = ForeverUIDB or {}
    return ForeverUIDB
end

local ShowPage

local function Build()
    local accent = ForeverUI_Accent()
    win = CreateFrame("Frame", "ForeverUIOptions", UIParent)
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:Hide()
    Boxed(win, GROUND, { 0, 0, 0 })
    tinsert(UISpecialFrames, win:GetName())
    local p = DB().optionsPoint
    if p then
        win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    end

    -- Dragged by the sidebar's top or the page's top
    local drag = CreateFrame("Frame", nil, win)
    drag:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", win, "TOPRIGHT", -30, 0)
    drag:SetHeight(26)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() win:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local point, _, relPoint, x, y = win:GetPoint(1)
        if point then DB().optionsPoint = { point, relPoint, x, y } end
    end)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButtonNoScripts")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() win:Hide() end)

    -- The sidebar
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
    side:SetWidth(SIDEBAR)
    local sg = Fill(side, "BACKGROUND", SIDE_GROUND[1], SIDE_GROUND[2], SIDE_GROUND[3], SIDE_GROUND[4], -6)
    sg:SetAllPoints(side)
    local line = Fill(side, "BORDER", accent[1], accent[2], accent[3], 0.25)
    line:SetWidth(1)
    line:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)

    local brand = Text(side, 16, accent)
    brand:SetPoint("TOPLEFT", side, "TOPLEFT", 14, -14)
    brand:SetText("ForeverUI")
    local version = Text(side, 9, MUTED)
    version:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverUI", "Version")
    version:SetText(v and ("Options  |  v" .. v) or "Options")

    local y = -58
    for _, spec in ipairs(Sorted()) do
        local tab = CreateFrame("Button", nil, side)
        tab:SetSize(SIDEBAR - 1, 26)
        tab:SetPoint("TOPLEFT", side, "TOPLEFT", 0, y)
        tab.wash = Fill(tab, "BACKGROUND", accent[1], accent[2], accent[3], 0)
        tab.wash:SetAllPoints(tab)
        tab.mark = Fill(tab, "BORDER", accent[1], accent[2], accent[3], 1)
        tab.mark:SetWidth(3)
        tab.mark:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
        tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.word = Text(tab, 12, TEXT)
        tab.word:SetPoint("LEFT", tab, "LEFT", 16, 0)
        tab.word:SetText(spec.title)
        tab.key = spec.key
        tab:SetScript("OnClick", function(self) ShowPage(self.key) end)
        tab:SetScript("OnEnter", function(self) self.hot = true self:Paint() end)
        tab:SetScript("OnLeave", function(self) self.hot = nil self:Paint() end)
        function tab:Paint()
            local on = current == self.key
            self.wash:SetColorTexture(accent[1], accent[2], accent[3], on and 0.16 or (self.hot and 0.06 or 0))
            self.mark:SetShown(on)
            if on or self.hot then
                self.word:SetTextColor(1, 1, 1)
            else
                self.word:SetTextColor(TEXT[1] * 0.8, TEXT[2] * 0.8, TEXT[3] * 0.82)
            end
        end
        tabs[spec.key] = tab
        y = y - 26
    end

    -- Move UI: every window and bar of the pack at once (MoveUI.lua)
    local move = CreateFrame("Button", nil, side)
    move.word = Text(move, 11, TEXT)
    move.word:SetPoint("CENTER", move, "CENTER", 0, 0)
    move.word:SetText("Move UI")
    move.word:SetTextColor(1, 1, 1)
    move:SetSize(SIDEBAR - 28, 24)
    move:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 14, 44)
    local moveGround = Boxed(move, { accent[1], accent[2], accent[3], 0.85 }, accent)
    move:SetScript("OnEnter", function()
        moveGround:SetColorTexture(Light(accent, 0.15))
        GameTooltip:SetOwner(move, "ANCHOR_RIGHT")
        GameTooltip:SetText("Move UI")
        GameTooltip:AddLine("Every window and bar of the pack at once, each under a box to drag.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    move:SetScript("OnLeave", function()
        moveGround:SetColorTexture(accent[1], accent[2], accent[3], 0.85)
        GameTooltip:Hide()
    end)
    move:SetScript("OnClick", function()
        GameTooltip:Hide()
        if ForeverUI_MoveUI then ForeverUI_MoveUI() end
    end)

    local hint = Text(side, 9, MUTED)
    hint:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 14, 12)
    hint:SetWidth(SIDEBAR - 24)
    hint:SetWordWrap(true)
    hint:SetText("/fui options opens this window. /fui move: Move UI.")

    -- The page, in a scroll frame
    pageScroll = CreateFrame("ScrollFrame", nil, win)
    pageScroll:SetPoint("TOPLEFT", win, "TOPLEFT", PAGE_X, -16)
    pageScroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -26, 14)
    pageScroll:EnableMouseWheel(true)
    local bar = CreateFrame("EventFrame", nil, win, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", pageScroll, "TOPRIGHT", 8, -4)
    bar:SetPoint("BOTTOMLEFT", pageScroll, "BOTTOMRIGHT", 8, 4)
    bar:SetHideIfUnscrollable(true)
    ScrollUtil.InitScrollFrameWithScrollBar(pageScroll, bar)

    win:SetScript("OnShow", function()
        if current and built[current] then built[current]:Refresh() end
    end)
end

local function BuildPage(spec)
    local page = CreateFrame("Frame", nil, pageScroll)
    page:SetSize(PAGE_W, 10)
    local K = setmetatable({ page = page, y = 0, widgets = {}, color = ForeverUI_Accent() }, Kit)
    spec.build(K)
    if spec.reset then
        K.y = K.y - 14
        K:Buttons({ { "Reset this page", function() spec.reset() end } })
    end
    page:SetHeight(-K.y + 10)
    return K
end

function ShowPage(key)
    local list = Sorted()
    local spec
    for _, s in ipairs(list) do
        if s.key == key then spec = s end
    end
    spec = spec or list[1]
    if not spec then return end
    if current and built[current] then built[current].page:Hide() end
    current = spec.key
    built[current] = built[current] or BuildPage(spec)
    local K = built[current]
    pageScroll:SetScrollChild(K.page)
    K.page:Show()
    pageScroll:SetVerticalScroll(0)
    pageScroll:UpdateScrollChildRect()
    K:Refresh()
    DB().optionsPage = current
    for _, tab in pairs(tabs) do tab:Paint() end
end

function ForeverUI_OpenOptions(key)
    if not win then Build() end
    ShowPage(key or current or DB().optionsPage)
    win:Show()
end

function ForeverUI_ToggleOptions(key)
    if win and win:IsShown() and (not key or key == current) then
        win:Hide()
    else
        ForeverUI_OpenOptions(key)
    end
end

-- The addon compartment (the game's addon menu by the minimap)
function ForeverUI_OnAddonCompartmentClick()
    ForeverUI_ToggleOptions()
end
