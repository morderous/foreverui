-- The options' Map page, and the map's layer (its frame strata) and where its
-- window opens. Without OpenMap, MapWindow.lua moves, sizes and dresses the
-- game's map window; with OpenMap, these are the settings OpenMap has not.
--
-- The layer goes on the game's map frame itself (OpenMap's map is the game's,
-- stitched), each time it opens, after the game's own (a game rule may set
-- one when it opens). Only frame properties: no code of the game runs ours.
-- The game keeps the map's border (its title, close and full-screen buttons)
-- one layer over the map, and the black behind the full-screen map one under
-- it: the map frame takes the mouse over its whole window, and it is raised
-- each time it opens, so in the same layer it covered its own buttons and
-- they stopped working. Without OpenMap, each of the map's pieces keeps its
-- step from the map's layer, as the game set it; "Front of all" then lays the
-- map one layer under the top, so its border fits under the tooltips.
--
-- "Middle of the screen" with OpenMap goes in as OpenMap's saved place (OpenMap
-- puts it back whenever anything places the map), then the map is put there;
-- without it, MapWindow.lua puts it there. With Move Any, the window is Move
-- Any's and this leaves it be. The full-screen map is never moved.

local _, ns = ...

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local function DB()
    ForeverUIDB = ForeverUIDB or {}
    return ForeverUIDB
end

local function Loaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

local function Map()
    return _G.WorldMapFrame
end

local function Window()
    return ns.MapWindow
end

-- In combat a protected frame can't change; then it waits for the end of combat
local function Blocked(frame)
    return InCombatLockdown() and frame.IsProtected and frame:IsProtected()
end

local function Step(strata)
    for i, s in ipairs(STRATA) do
        if s == strata then return i end
    end
    return nil
end

-- Each piece of the map that the game sets in another layer than the map's
-- (the border, the black, the quest log, the buttons over the map), and how
-- many layers over (or under) the map it is. Read once, before any change.
local ladder
local function ReadLadder(map)
    if ladder then return end
    ladder = {}
    local base = Step(map:GetFrameStrata())
    local found = false
    if base then
        for _, child in ipairs({ map:GetChildren() }) do
            local step = Step(child:GetFrameStrata())
            if step and step ~= base then
                ladder[child] = step - base
                found = true
            end
        end
    end
    if not found then
        -- (read after a game rule had laid everything in one layer: as the game's files set them)
        if map.BorderFrame then ladder[map.BorderFrame] = 1 end
        if map.BlackoutFrame then ladder[map.BlackoutFrame] = -1 end
        local log = map.QuestLog or _G.QuestMapFrame
        if log then ladder[log] = 1 end
    end
end

-- The map's own layer for a chosen one: the pieces over it must fit under
-- the tooltips' layer, so "Front of all" lays the map one under it
local function Base(want)
    local step = Step(want)
    if not step then return want end
    local up = 0
    for _, offset in pairs(ladder or {}) do
        if offset > up then up = offset end
    end
    local top = #STRATA - 1
    if step + up > top then step = math.max(1, top - up) end
    return STRATA[step]
end

local function Climb(map, strata)
    local base = Step(strata)
    if not base or not ladder then return end
    for child, offset in pairs(ladder) do
        if child:GetParent() == map and not Blocked(child) then
            local s = STRATA[math.max(1, math.min(#STRATA, base + offset))]
            if child:GetFrameStrata() ~= s then child:SetFrameStrata(s) end
        end
    end
end

local own            -- the map's layer before ours, to give back
local pending = false

local function ApplyLayer()
    local map = Map()
    if not map then return end
    if Blocked(map) then
        pending = true
        return
    end
    pending = false
    ReadLadder(map)
    local want = DB().mapStrata
    local log = _G.QuestMapFrame
    local openMap = Loaded("OpenMap")
    if want and want ~= "game" then
        own = own or map:GetFrameStrata()
        local base = openMap and want or Base(want)
        if map:GetFrameStrata() ~= base then map:SetFrameStrata(base) end
        if not openMap then
            Climb(map, base)
        elseif log and log:GetParent() == map and log:GetFrameStrata() ~= want and not Blocked(log) then
            -- (as it always was with OpenMap: the quest log beside the map in the map's layer)
            log:SetFrameStrata(want)
        end
    elseif own then
        map:SetFrameStrata(own)
        if not openMap then
            Climb(map, own)
        elseif log and log:GetParent() == map and not Blocked(log) then
            log:SetFrameStrata("HIGH")
        end
        own = nil
    end
end

-- OpenMap's window, which "Middle of the screen" goes through
local function OpenMapWindow()
    return Loaded("OpenMap") and not Loaded("MoveAny")
end

local function CanCenter()
    if not Map() then return false end
    if Loaded("OpenMap") then return OpenMapWindow() end
    local W = Window()
    return W ~= nil and W.Free()
end

local function Center()
    if DB().mapOpenAt ~= "center" or not Map() or not OpenMapWindow() then return end
    local map = Map()
    if (map.IsMaximized and map:IsMaximized()) or Blocked(map) then return end
    local odb = type(OpenMapDB) == "table" and type(OpenMapDB.worldmap) == "table" and OpenMapDB.worldmap
    if odb then odb.window = { "CENTER", "CENTER", 0, 0 } end
    map:ClearAllPoints()
    map:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function OnShow()
    ApplyLayer()
    Center()
end

local hooked = false
local function Hook()
    local map = Map()
    if hooked or not map then return end
    hooked = true
    ReadLadder(map)
    map:HookScript("OnShow", OnShow)
    if map.AttachQuestLog then hooksecurefunc(map, "AttachQuestLog", ApplyLayer) end
    if map:IsShown() then OnShow() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then ApplyLayer() end
    elseif event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then
        Hook()
    end
end)

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Percent(v)
    return string.format("%d%%", math.floor(v * 100 + 0.5))
end

ForeverUI_Pages = ForeverUI_Pages or {}
ForeverUI_Pages[#ForeverUI_Pages + 1] = {
    key = "map",
    title = "Map",
    order = 40,
    build = function(K)
        local openMap = Loaded("OpenMap")
        local W = Window()
        if openMap then
            K:Head("Map", "The world map (OpenMap). OpenMap's own settings are in its options; these are the ones it doesn't have.")
            if OpenMap_OnAddonCompartmentClick then
                K:Buttons({ { "OpenMap's options", function() OpenMap_OnAddonCompartmentClick(nil, "RightButton") end } })
            end
        else
            K:Head("Map", "The game's world map. Without OpenMap, ForeverUI moves it, sizes it and gives it the pack's look.")
        end

        K:Section("Window")
        K:Choice("Layer", { { "game", "The game's" }, { "MEDIUM", "Medium" }, { "HIGH", "High" }, { "DIALOG", "Dialog" },
            { "FULLSCREEN_DIALOG", "Front of all" } },
            function() return DB().mapStrata or "game" end,
            function(v)
                DB().mapStrata = v
                ApplyLayer()
            end)
        if openMap then
            K:Note("Front of all puts the map over every other window, the quest log's too unless it is in front of all as well. Above High, a question box of the game, or one of OpenMap's own (a pin's note), opens under the map while it is open.")
        else
            K:Note("Front of all puts the map over every other window, the quest log's too unless it is in front of all as well. Above High, a question box of the game opens under the map while it is open. The map's title and buttons stay over it in every layer.")
        end
        K:Choice("Opens", { { "kept", "Where I left it" }, { "center", "Middle of the screen" } },
            function() return DB().mapOpenAt or "kept" end,
            function(v)
                DB().mapOpenAt = v
                local map = Map()
                if map and map:IsShown() then
                    if openMap then Center() elseif W then W.Restore() end
                end
            end, CanCenter)
        if not CanCenter() then
            local who = Loaded("MoveAny") and "Move Any" or (W and W.Owner())
            K:Note(who and (who .. " places the map window: Opens is its, not ours.") or "Opens needs the game's map.")
        else
            K:Note("Middle of the screen opens the windowed map in the middle every time; dragged, it stays there until it closes. The full-screen map is left alone.")
        end

        if openMap or not W then return end
        local function Free() return W.Free() end
        local function Words(text) return function() return text end end
        local function Value(key) return function() local v = DB()[key] return v == nil or v == true end end
        local function Set(key, after)
            return function(v)
                DB()[key] = v and true or false
                W.Controls()
                if after then after() end
            end
        end

        K:Section("Move and size")
        K:Switch("Move it", Value("mapMove"), Set("mapMove"), Free, Words("drag its title bar"))
        K:Switch("Size it", Value("mapResize"), Set("mapResize", W.Restore), Free, Words("drag a bottom corner"))
        K:Slider("Size", 0.5, 2, 0.05, W.Scale, W.SetScale, Percent,
            function() return W.Free() and Value("mapResize")() end)
        K:Buttons({ { "Back to its place", W.BackToPlace }, { "Back to its size", W.BackToSize } })
        local owner = W.Owner()
        if owner then
            K:Note(owner .. " places the map window: moving and sizing it are its, not ours.")
        else
            K:Note("The map keeps its shape: a corner makes all of it bigger or smaller. Right click the title bar: back to its place; a corner: back to its size. In combat it opens where the game puts it, and goes back after. The full-screen map stays the game's.")
        end

        K:Section("Look")
        K:Switch("Flat look", Value("mapFlat"), Set("mapFlat", W.ApplyLook), function() return W.Dresser() == nil end,
            Words("dark, flat, a 1px edge"))
        local dresser = W.Dresser()
        if dresser then
            K:Note(dresser .. " dresses the map window: the look is its, not ours.")
        else
            K:Note("The game's gold frame, portrait and grey bars give way to a dark flat window, as the rest of the pack. The map, its bar of places and its buttons stay the game's.")
        end
    end,
    reset = function()
        local d = DB()
        d.mapStrata, d.mapOpenAt = nil, nil
        d.mapMove, d.mapResize, d.mapFlat = nil, nil, nil
        ApplyLayer()
        local W = Window()
        if W and not Loaded("OpenMap") then
            W.BackToSize()
            W.BackToPlace()
            W.ApplyLook()
        end
    end,
}
