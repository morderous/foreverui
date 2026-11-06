-- The options' Modules page: the pack's addons, which are here and which are
-- on. Ours (ForeverUI XPbar, Quest Log and Trainer) turn on or off from here,
-- for every character, from the next reload, as the game's AddOns list does
-- with "All characters". The others show their state: every part of ForeverUI
-- checks for them before it uses them, so a missing one only leaves its part
-- out.

local GREEN = { 0.40, 0.90, 0.45 }
local ORANGE = { 1.00, 0.65, 0.25 }
local RED = { 1.00, 0.42, 0.36 }
local GREY = { 0.60, 0.60, 0.65 }

local OURS = {
    { "ForeverUI_XPBar", "ForeverUI XPbar" },
    { "ForeverUI_QuestLog", "ForeverUI Quest Log" },
    { "ForeverUI_Trainer", "ForeverUI Trainer" },
}
local REQUIRED = {
    { "EllesmereUI", "EllesmereUI" },
    { "OpenMap", "OpenMap" },
    { "Polestar", "Polestar" },
}
local EXTRAS = {
    { "ForeverQuestTint", "Forever Quest Tint" },
    { "DialogueUI", "Dialogue UI" },
    { "Spoken", "Spoken" },
}

local A = C_AddOns
local changed = {}     -- ours turned on or off here this session

local function Exists(name)
    return A and A.DoesAddOnExist and A.DoesAddOnExist(name) and true or false
end

local function Loaded(name)
    if not (A and A.IsAddOnLoaded) then return false end
    local _, loaded = A.IsAddOnLoaded(name)
    return loaded and true or false
end

-- On for the next load, for every character (nil: all of them)
local function Enabled(name)
    if not (A and A.GetAddOnEnableState) then return Loaded(name) end
    local ok, state = pcall(A.GetAddOnEnableState, name, nil)
    return ok and type(state) == "number" and state > 0 or false
end

local function State(name)
    if not Exists(name) then return "Not installed", RED end
    local loaded, enabled = Loaded(name), Enabled(name)
    if loaded and enabled then return "On", GREEN end
    if loaded then return "Off after a reload", ORANGE end
    if enabled then
        if changed[name] then return "On after a reload", ORANGE end
        -- on, and yet not loaded: the game's reason (a dependency off, an old version ...)
        local reason = A.GetAddOnInfo and select(5, A.GetAddOnInfo(name))
        if type(reason) == "string" and reason ~= "" then
            return "Not loaded: " .. (_G["ADDON_" .. reason] or reason), RED
        end
        return "On after a reload", ORANGE
    end
    return "Off", GREY
end

local function Toggle(name, on)
    if not (A and A.EnableAddOn and A.DisableAddOn) then return end
    if on then A.EnableAddOn(name, nil) else A.DisableAddOn(name, nil) end
    changed[name] = true
end

ForeverUI_Pages = ForeverUI_Pages or {}
ForeverUI_Pages[#ForeverUI_Pages + 1] = {
    key = "modules",
    title = "Modules",
    order = 90,
    build = function(K)
        K:Head("Modules", "The pack's addons: which are here, and which are on. Ours turn on and off here, for every character, from the next reload.")
        K:Buttons({ { "Reload now", function() ReloadUI() end, true } })

        K:Section("Ours")
        K:Line("ForeverUI", function() return "On: these options, the minimap button, the look", GREEN end)
        for _, addon in ipairs(OURS) do
            local name = addon[1]
            K:Switch(addon[2], function() return Enabled(name) end, function(v) Toggle(name, v) end,
                function() return Exists(name) end, function() return State(name) end)
        end
        K:Note("An addon of ours turned off is not loaded at all after the reload: its page here goes, and nothing of it runs.")

        K:Section("The pack's required")
        for _, addon in ipairs(REQUIRED) do
            local name = addon[1]
            K:Line(addon[2], function() return State(name) end)
        end
        K:Note("Without EllesmereUI, the look installs without its profile, and these windows use the game's font. Without OpenMap, the map is Blizzard's, and the Map page's Opens is off. Without Polestar, there are no guides, and the look leaves its settings out.")

        K:Section("Extras")
        for _, addon in ipairs(EXTRAS) do
            local name = addon[1]
            K:Line(addon[2], function() return State(name) end)
        end
        K:Note("ForeverUI Manager installs and updates all of these. The game's AddOns list turns the others on and off.")
    end,
}
