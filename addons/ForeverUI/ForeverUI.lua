-- ForeverUI: installs the ForeverUI look for whoever gets the ForeverUI pack
-- (a window on first login, or /fui), and captures it from the author's own
-- UI (/fui capture). Profile.lua holds the captured look; it is made by
-- tools/make_profile.py from what /fui capture saves.
--
-- Nothing here writes a file of another addon: the EllesmereUI profile goes in
-- through EllesmereUI's own installer API, the Edit Mode layout through the
-- game's, and OpenMap, Polestar and XPbar settings into their own tables
-- before a reload saves them.

local ADDON = ...
local PROFILE_NAME = "ForeverUI"

local db

local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4d9cffForeverUI|r: " .. msg)
end

local function Loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name) and true or false
    end
    return false
end

local function Metadata(name, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(name, field)
    end
end

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------
-- Keys that hold a player's own things, never settings: map favorites,
-- notes and drawings.
local PRIVATE_KEYS = { favorites = true, paint = true, sketch = true, notes = true, strokes = true }

local function Copy(value, skip)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        local t = type(v)
        if not (skip and skip[k]) and t ~= "function" and t ~= "userdata" and t ~= "thread" then
            out[k] = Copy(v, skip)
        end
    end
    return out
end

local function Merge(into, from)
    for k, v in pairs(from) do
        if type(v) == "table" then
            if type(into[k]) ~= "table" then into[k] = {} end
            Merge(into[k], v)
        else
            into[k] = v
        end
    end
end

local function Count(t)
    local n = 0
    if type(t) == "table" then
        for _ in pairs(t) do n = n + 1 end
    end
    return n
end

-- What a table's top keys held before, so /fui undo can put them back.
local function Remember(target, keys)
    local saved = {}
    for k in pairs(keys) do
        saved[k] = { v = Copy(target[k]) }
    end
    return saved
end

local function Restore(target, saved)
    for k, entry in pairs(saved) do
        target[k] = Copy(entry.v)
    end
end

---------------------------------------------------------------------------
-- Interface settings (CVars)
---------------------------------------------------------------------------
-- Graphics, sound, network, debug and GM settings stay each player's own,
-- and so does the UI scale.
local function SkippedCategory(category)
    local c = Enum.ConsoleCategory
    if not c then
        return category == 0 or category == 1 or category == 2 or category == 6
            or category == 7 or category == 8 or category == 9
    end
    return category == c.Debug or category == c.Graphics or category == c.Console
        or category == c.Net or category == c.Sound or category == c.Gm or category == c.Reveal
end

local SKIP_CVARS = {
    uiScale = true, useUiScale = true, textLocale = true, audioLocale = true,
    agentUILocale = true, portal = true, realmList = true, realmName = true,
    accountName = true, accountList = true,
}

local SKIP_CVAR_PATTERNS = {
    "^last", "[Tt]utorial", "^closedInfoFrame", "^seen", "^cameraSaved",
    "^gx", "^[Ss]ound", "^graphics", "^raidGraphics", "^realm", "^account",
    "^Contrast", "^Brightness", "^Gamma",
}

local function SkippedCVar(name)
    if SKIP_CVARS[name] then return true end
    for i = 1, #SKIP_CVAR_PATTERNS do
        if string.find(name, SKIP_CVAR_PATTERNS[i]) then return true end
    end
    return false
end

local function CaptureCVars()
    local out, n = {}, 0
    if not ConsoleGetAllCommands then return out, n end
    local cvarType = (Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar) or 0
    for _, info in ipairs(ConsoleGetAllCommands()) do
        local name = info.command
        if info.commandType == cvarType and type(name) == "string"
            and not SkippedCategory(info.category) and not SkippedCVar(name) then
            local ok, value, default, _, _, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, name)
            if ok and value ~= nil and value ~= default and not locked and not secure and not readOnly then
                out[name] = value
                n = n + 1
            end
        end
    end
    return out, n
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------
local function PresetCount()
    return (Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues) or 2
end

local function CaptureEditMode()
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
    local all = C_EditMode.GetLayouts()
    if not all or not all.activeLayout then return nil end
    local presets = PresetCount()
    if all.activeLayout <= presets then
        return { preset = all.activeLayout }
    end
    local layout = all.layouts and all.layouts[all.activeLayout - presets]
    if not layout then return nil end
    local ok, text = pcall(C_EditMode.ConvertLayoutInfoToString, layout)
    if ok and type(text) == "string" and text ~= "" then
        return { string = text, name = layout.layoutName }
    end
end

-- The active layout by name (or preset number), for /fui undo.
local function ActiveEditMode()
    local all = C_EditMode and C_EditMode.GetLayouts and C_EditMode.GetLayouts()
    if not all or not all.activeLayout then return nil end
    local presets = PresetCount()
    if all.activeLayout <= presets then return { preset = all.activeLayout } end
    local layout = all.layouts and all.layouts[all.activeLayout - presets]
    return layout and { name = layout.layoutName } or nil
end

local function SetEditMode(which)
    local all = C_EditMode.GetLayouts()
    if which.preset then
        C_EditMode.SetActiveLayout(which.preset)
        return true
    end
    for i, layout in ipairs(all.layouts or {}) do
        if layout.layoutName == which.name then
            C_EditMode.SetActiveLayout(PresetCount() + i)
            return true
        end
    end
    return false
end

-- A new account layout named ForeverUI (an older one of that name goes),
-- placed after the other account layouts as Edit Mode itself does, then made
-- the active one.
local function InstallEditMode(e)
    if e.preset then
        C_EditMode.SetActiveLayout(e.preset)
        return true
    end
    local info = C_EditMode.ConvertStringToLayoutInfo(e.string)
    if not info then return false, "the Edit Mode layout could not be read" end
    local all = C_EditMode.GetLayouts()
    local saved = all.layouts or {}
    for i = #saved, 1, -1 do
        if saved[i].layoutName == PROFILE_NAME then table.remove(saved, i) end
    end
    info.layoutName = PROFILE_NAME
    info.layoutType = Enum.EditModeLayoutType.Account
    local at = 1
    for i = 1, #saved do
        if saved[i].layoutType == Enum.EditModeLayoutType.Account then at = i + 1 end
    end
    table.insert(saved, at, info)
    local full = {}
    if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        full = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    end
    local presets = #full
    for i = 1, #saved do full[#full + 1] = saved[i] end
    all.layouts = full
    all.activeLayout = presets + at
    C_EditMode.SaveLayouts(all)
    C_EditMode.SetActiveLayout(presets + at)
    return true
end

---------------------------------------------------------------------------
-- Capture: the author's whole UI, into ForeverUICapture
---------------------------------------------------------------------------
local function Capture()
    if InCombatLockdown() then Say("not in combat.") return end
    local p = { captured = time(), build = GetBuildInfo() }
    local said = {}

    local E = _G.EllesmereUI
    if E and E.ExportCurrentProfile then
        local ok, text = pcall(E.ExportCurrentProfile)
        if ok and type(text) == "string" and text ~= "" then
            p.ellesmere = {
                string = text,
                from = EllesmereUIDB and EllesmereUIDB.activeProfile,
                version = Metadata("EllesmereUI", "Version"),
            }
            said[#said + 1] = "EllesmereUI profile"
        else
            Say("EllesmereUI did not give its profile.")
        end
    end

    p.editmode = CaptureEditMode()
    if p.editmode then
        said[#said + 1] = "Edit Mode layout " .. (p.editmode.name or ("preset " .. p.editmode.preset))
    end

    local cvars, n = CaptureCVars()
    p.cvars = cvars
    said[#said + 1] = n .. " interface settings"

    if type(OpenMapDB) == "table" then
        p.openmap = Copy(OpenMapDB, PRIVATE_KEYS)
        said[#said + 1] = "OpenMap"
    end
    if type(PolestarDB) == "table" and type(PolestarDB.settings) == "table" then
        p.polestar = Copy(PolestarDB.settings)
        said[#said + 1] = "Polestar"
    end
    if type(ForeverUIXPBarDB) == "table" then
        p.xpbar = Copy(ForeverUIXPBarDB)
        said[#said + 1] = "XPbar"
    end

    ForeverUICapture = p
    -- The author's own client already has this look: no install window for it.
    db.installed = p.captured
    Say("captured " .. table.concat(said, ", ") .. ".")
    Say("Type /reload to write it to disk, then run tools/make_profile.py.")
end

---------------------------------------------------------------------------
-- Install
---------------------------------------------------------------------------
local PARTS = {
    {
        key = "ellesmere", label = "EllesmereUI profile",
        can = function() return Loaded("EllesmereUI") and _G.EllesmereUI and _G.EllesmereUI.ImportProfileSilent end,
        apply = function(p, backup)
            backup.ellesmere = EllesmereUIDB and EllesmereUIDB.activeProfile
            return _G.EllesmereUI.ImportProfileSilent({
                importString = p.ellesmere.string,
                profileName = PROFILE_NAME,
                applyUIScale = false,
            })
        end,
    },
    {
        key = "editmode", label = "Edit Mode layout",
        can = function() return C_EditMode and C_EditMode.SaveLayouts end,
        apply = function(p, backup)
            backup.editmode = ActiveEditMode()
            return InstallEditMode(p.editmode)
        end,
    },
    {
        key = "cvars", label = "Interface settings",
        detail = function(p) return Count(p.cvars) end,
        can = function() return true end,
        apply = function(p, backup)
            backup.cvars = {}
            local refused = 0
            for name, value in pairs(p.cvars) do
                backup.cvars[name] = C_CVar.GetCVar(name)
                local ok, set = pcall(C_CVar.SetCVar, name, value)
                if not ok or set == false then refused = refused + 1 end
            end
            if refused > 0 then return false, refused .. " interface settings were refused" end
            return true
        end,
    },
    {
        key = "openmap", label = "OpenMap settings",
        can = function() return type(OpenMapDB) == "table" end,
        apply = function(p, backup)
            backup.openmap = Remember(OpenMapDB, p.openmap)
            Merge(OpenMapDB, p.openmap)
            return true
        end,
    },
    {
        key = "polestar", label = "Polestar settings",
        can = function() return type(PolestarDB) == "table" end,
        apply = function(p, backup)
            if type(PolestarDB.settings) ~= "table" then PolestarDB.settings = {} end
            backup.polestar = Remember(PolestarDB.settings, p.polestar)
            Merge(PolestarDB.settings, p.polestar)
            return true
        end,
    },
    {
        key = "xpbar", label = "ForeverUI XPbar place and size",
        can = function() return type(ForeverUIXPBarDB) == "table" end,
        apply = function(p, backup)
            backup.xpbar = Remember(ForeverUIXPBarDB, p.xpbar)
            Merge(ForeverUIXPBarDB, p.xpbar)
            return true
        end,
    },
}

local function Install(chosen)
    local p = ForeverUI_Profile
    if InCombatLockdown() then return { "Not in combat." } end
    local backup = { captured = p.captured }
    local problems = {}
    -- The EllesmereUI profile goes last: it is the biggest change, and its
    -- import never reloads by itself.
    for i = #PARTS, 1, -1 do
        local part = PARTS[i]
        if part.key ~= "ellesmere" and chosen[part.key] then
            local ok, done, err = pcall(part.apply, p, backup)
            if not ok then problems[#problems + 1] = part.label .. ": " .. tostring(done)
            elseif done == false or done == nil then problems[#problems + 1] = part.label .. ": " .. tostring(err or "refused") end
        end
    end
    if chosen.ellesmere then
        local ok, done, err = pcall(PARTS[1].apply, p, backup)
        if not ok then problems[#problems + 1] = PARTS[1].label .. ": " .. tostring(done)
        elseif not done then problems[#problems + 1] = PARTS[1].label .. ": " .. tostring(err or "refused") end
    end
    db.backup = backup
    db.installed = p.captured
    return problems
end

local function Undo()
    local b = db.backup
    if not b then Say("nothing to undo.") return end
    if InCombatLockdown() then Say("not in combat.") return end
    if b.cvars then
        for name, value in pairs(b.cvars) do pcall(C_CVar.SetCVar, name, value) end
    end
    if b.openmap and type(OpenMapDB) == "table" then Restore(OpenMapDB, b.openmap) end
    if b.polestar and type(PolestarDB) == "table" and type(PolestarDB.settings) == "table" then
        Restore(PolestarDB.settings, b.polestar)
    end
    if b.xpbar and type(ForeverUIXPBarDB) == "table" then Restore(ForeverUIXPBarDB, b.xpbar) end
    if b.editmode then pcall(SetEditMode, b.editmode) end
    if b.ellesmere and _G.EllesmereUI and _G.EllesmereUI.SwitchProfile then
        pcall(_G.EllesmereUI.SwitchProfile, b.ellesmere)
    end
    db.backup = nil
    ReloadUI()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local win

local function Edge(frame)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    local back = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    back:SetAllPoints(frame)
    back:SetColorTexture(0.08, 0.08, 0.09, 0.96)
end

local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    return b
end

local function BuildWindow()
    win = CreateFrame("Frame", "ForeverUIInstaller", UIParent)
    win:SetSize(380, 200)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    Edge(win)
    tinsert(UISpecialFrames, "ForeverUIInstaller")

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", 16, -14)
    win.title:SetText("ForeverUI")

    win.text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.text:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -8)
    win.text:SetPoint("RIGHT", win, "RIGHT", -16, 0)
    win.text:SetJustifyH("LEFT")

    win.boxes = {}
    for i, part in ipairs(PARTS) do
        local box = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box.part = part
        box.label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
        win.boxes[i] = box
    end

    win.install = Button(win, "Install", 110)
    win.later = Button(win, "Not now", 110)
    win.never = Button(win, "Don't ask", 110)
    win.later:SetPoint("BOTTOM", win, "BOTTOM", 0, 14)
    win.install:SetPoint("RIGHT", win.later, "LEFT", -8, 0)
    win.never:SetPoint("LEFT", win.later, "RIGHT", 8, 0)

    win.later:SetScript("OnClick", function() win:Hide() end)
    win.never:SetScript("OnClick", function()
        db.skipped = ForeverUI_Profile and ForeverUI_Profile.captured
        win:Hide()
        Say("the install window will not open by itself for this profile. /fui opens it.")
    end)
    win.installClick = function()
        local chosen, any = {}, false
        for _, box in ipairs(win.boxes) do
            if box:IsShown() and box:IsEnabled() and box:GetChecked() then
                chosen[box.part.key] = true
                any = true
            end
        end
        if not any then return end
        local problems = Install(chosen)
        if #problems == 0 then
            ReloadUI()
            return
        end
        win.text:SetText("Installed, with problems:\n" .. table.concat(problems, "\n")
            .. "\n\nReload now to see the rest. /fui undo puts your old setup back.")
        win.install:SetText("Reload")
        win.install:SetScript("OnClick", function() ReloadUI() end)
        for _, box in ipairs(win.boxes) do box:Hide(); box.label:Hide() end
        win:SetHeight(140 + win.text:GetStringHeight())
    end
end

local function ShowWindow()
    local p = ForeverUI_Profile
    if not p then Say("this pack has no profile yet.") return end
    if not win then BuildWindow() end
    win.install:SetText("Install")
    win.install:SetScript("OnClick", win.installClick)
    win.text:SetText("Install the ForeverUI look? Your own EllesmereUI profiles stay in its profile list, and /fui undo puts your old setup back.")
    local y = -14 - win.title:GetStringHeight() - 8 - win.text:GetStringHeight() - 10
    local shown = 0
    for _, box in ipairs(win.boxes) do
        local part = box.part
        local has = p[part.key] ~= nil and (part.key ~= "cvars" or Count(p.cvars) > 0)
        if has then
            local can = part.can() and true or false
            local label = part.label
            if part.detail then label = label .. " (" .. part.detail(p) .. ")" end
            if not can then label = label .. " - not installed" end
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", win, "TOPLEFT", 14, y)
            box:SetChecked(can)
            box:SetEnabled(can)
            box.label:SetText(label)
            box.label:SetTextColor(can and 1 or 0.5, can and 1 or 0.5, can and 1 or 0.5)
            box:Show()
            box.label:Show()
            y = y - 26
            shown = shown + 1
        else
            box:Hide()
            box.label:Hide()
        end
    end
    win:SetHeight(-y + 50)
    win:Show()
end

---------------------------------------------------------------------------
-- Events and /fui
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        ForeverUIDB = ForeverUIDB or {}
        db = ForeverUIDB
    elseif event == "PLAYER_LOGIN" then
        local p = ForeverUI_Profile
        if p and p.captured and db.installed ~= p.captured and db.skipped ~= p.captured then
            C_Timer.After(3, function()
                if not InCombatLockdown() then ShowWindow() end
            end)
        end
    end
end)

SLASH_FOREVERUI1 = "/fui"
SLASH_FOREVERUI2 = "/foreverui"
SlashCmdList.FOREVERUI = function(input)
    local cmd = string.lower(string.match(input or "", "^%s*(%S*)") or "")
    if cmd == "" or cmd == "install" then
        ShowWindow()
    elseif cmd == "capture" then
        Capture()
    elseif cmd == "undo" then
        Undo()
    else
        Say("/fui opens the install window. /fui undo puts your old setup back.")
    end
end
