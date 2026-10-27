--[[
    Handy Gnat Anywhere - Grounded 2 (UE4SS Lua mod)
    Version 1.0.2  |  https://github.com/kamibiel/handy-gnat-anywhere
    -------------------------------------------------------------
    Unlocks the Handy Gnat (build mode) in every difficulty, not
    only in Creative.

    How it works
      Grounded 2 stores this permission in the "bBuildModeAvailable"
      option of the game mode presets (SurvivalGameModeSettings).
      Only the Creative presets have it on. This script switches the
      same option on at runtime, by NAME, for the Relaxed / Normal /
      Hard presets and for any copy already loaded in the world.
      Because nothing in the game files is replaced, game updates
      that reorder the preset options do not break it.

    Usage
      Enter your world, open the build menu and press G.

    Hotkeys
      Ctrl + F7         -> re-apply (if the Gnat does not show up)
      Ctrl + Shift + F7 -> re-apply with a full scan (slow, last resort)
      Ctrl + F6  -> toggle free camera (spectator mode), optional

    Log: ...\Grounded2\Augusta\Binaries\Win64\ue4ss\UE4SS.log
         (lines starting with [HandyGnatAnywhere])

    Uso (PT-BR): entre no mundo, abra a construção e aperte G.
      Ctrl+F7 reaplica | Ctrl+F6 câmera livre.
--]]

------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------
local Config = {
    -- Preset options to force. Add more if you like, e.g.:
    --   bAutoCompleteBuildings = true   (instant building)
    --   bUnlockAllRecipes      = true   (all recipes)
    Options = {
        bBuildModeAvailable = true,
    },

    -- Presets that receive the change
    Presets = { "BP_NormalModeSettings", "BP_RelaxedModeSettings", "BP_HardModeSettings", "BP_CustomModeSettings" },

    ApplyDelayMs   = 3000,
    ReapplyKey     = Key.F7,
    SpectatorKey   = Key.F6,
    ModifierKeys   = { ModifierKey.CONTROL },
    MaxStructDepth = 3,
    LogPlaces      = false, -- list every place that was set (diagnostics)
}
------------------------------------------------------------------

local VERSION = "1.0.2"
local TAG = "[HandyGnatAnywhere] "
local function log(msg) print(TAG .. msg .. "\n") end

local function valid(o)
    local ok, r = pcall(function() return o ~= nil and o:IsValid() end)
    return ok and r
end

local function propType(p)
    local t = "?"
    pcall(function() t = p:GetClass():GetFName():ToString() end)
    return t
end

-- 1) Preset defaults (CDOs)
local function applyPresets()
    local n = 0
    for _, name in ipairs(Config.Presets) do
        local path = "/Game/Blueprints/Global/" .. name .. ".Default__" .. name .. "_C"
        local cdo = StaticFindObject(path)
        if not valid(cdo) then
            pcall(function() LoadAsset("/Game/Blueprints/Global/" .. name) end)
            cdo = StaticFindObject(path)
        end
        if valid(cdo) then
            for opt, value in pairs(Config.Options) do
                if pcall(function() cdo[opt] = value end) then n = n + 1 end
            end
        else
            log("Preset not found: " .. name)
        end
    end
    return n
end

-- 2) Any loaded object/struct holding one of the options
local ClassCache = {}

local function collect(struct, prefix, depth, out)
    local s, guard = struct, 0
    while valid(s) and guard < 64 do
        guard = guard + 1
        pcall(function()
            s:ForEachProperty(function(p)
                local n = p:GetFName():ToString()
                local path = {}
                for i, x in ipairs(prefix) do path[i] = x end
                path[#path + 1] = n
                if Config.Options[n] ~= nil then
                    out[#out + 1] = { path = path, opt = n }
                elseif depth < Config.MaxStructDepth and propType(p) == "StructProperty" then
                    local okS, inner = pcall(function() return p:GetStruct() end)
                    if okS and valid(inner) then collect(inner, path, depth + 1, out) end
                end
            end)
        end)
        local ok, sup = pcall(function() return s:GetSuperStruct() end)
        if not ok then break end
        s = sup
    end
end

local function pathsFor(cls)
    local a = cls:GetAddress()
    if ClassCache[a] == nil then
        local out = {}
        collect(cls, {}, 0, out)
        ClassCache[a] = out
    end
    return ClassCache[a]
end

-- Places found by the last full scan, re-used on later applies so the
-- (expensive) full object scan runs only once per world.
local Tracked = {}

local function setEntry(obj, e)
    local want = Config.Options[e.opt]
    local changed = false
    local ok = pcall(function()
        local v = obj
        for i = 1, #e.path - 1 do v = v[e.path[i]] end
        local last = e.path[#e.path]
        if v[last] ~= want then
            v[last] = want
            changed = true
        end
    end)
    return ok, changed
end

-- Objects found by a full scan are remembered (by path) in this file, so the
-- next sessions find them instantly with StaticFindObject instead of scanning.
local LEARNED_FILE = "HandyGnatAnywhere_targets.txt"

local function objectPath(obj)
    -- GetFullName() is "<Class> <Path>"; StaticFindObject wants just <Path>
    local full = ""
    pcall(function() full = obj:GetFullName() end)
    return (full:match("^%S+%s+(.+)$")) or full
end

local function loadLearned()
    local list = {}
    local f = io.open(LEARNED_FILE, "r")
    if not f then return list end
    for line in f:lines() do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then list[#list + 1] = line end
    end
    f:close()
    return list
end

local function saveLearned(paths)
    local f = io.open(LEARNED_FILE, "w")
    if not f then log("could not write " .. LEARNED_FILE) return end
    f:write("# Handy Gnat Anywhere - objects that hold bBuildModeAvailable (written by a full scan)\n")
    for _, p in ipairs(paths) do f:write(p .. "\n") end
    f:close()
end

local function fullScan()
    Tracked = {}
    local changed = 0
    local learned, seen = {}, {}
    ForEachUObject(function(obj)
        if not valid(obj) then return end
        local okC, cls = pcall(function() return obj:GetClass() end)
        if not okC or not valid(cls) then return end
        local paths = pathsFor(cls)
        if #paths == 0 then return end
        local p = objectPath(obj)
        for _, e in ipairs(paths) do
            Tracked[#Tracked + 1] = { obj = obj, entry = e }
            local ok, did = setEntry(obj, e)
            if did then changed = changed + 1 end
            if not ok then log("Failed to set " .. table.concat(e.path, ".")) end
            log(string.format("PLACE %s :: %s%s", p, table.concat(e.path, "."), did and " (changed)" or ""))
        end
        -- transient objects (renamed every session) are found by class instead
        if not seen[p] and not p:find("/Engine/Transient", 1, true) then
            seen[p] = true
            learned[#learned + 1] = p
        end
    end)
    saveLearned(learned)
    return changed, #Tracked
end

-- Cheap path: only the places already known. Returns nil if they are gone
-- (new world loaded), so the caller falls back to a full scan.
local function quickApply()
    if #Tracked == 0 then return nil end
    local changed, alive = 0, 0
    for _, t in ipairs(Tracked) do
        if valid(t.obj) then
            alive = alive + 1
            local _, did = setEntry(t.obj, t.entry)
            if did then changed = changed + 1 end
        end
    end
    if alive == 0 then return nil end
    return changed, alive
end

-- Targeted scan: only the classes known to hold the game mode settings
-- (found with a full scan on game version 0.6). No walk over every object in
-- the game, so no freeze, even in big worlds.
local TargetClasses = {
    "SurvivalModeManagerComponent",
    "BP_SurvivalGameInstance_Augusta_C", "BP_SurvivalGameInstance_C", "SurvivalGameInstance",
    "BP_NormalModeSettings_C", "BP_RelaxedModeSettings_C", "BP_HardModeSettings_C",
    "BP_CustomModeSettings_C", "SurvivalGameModeSettings",
}

-- Known objects (paths) that hold the setting, including the game's default
-- objects that FindAllOf does not return. Filled from a full scan on 0.6.0.3.
local KnownObjects = {
    "/Script/Maine.Default__SurvivalGameModeSettings",
    "/Script/Maine.Default__SurvivalModeManagerComponent",
    "/Script/Maine.Default__InGameGameState:SurvivalModeManagerComponent",
    "/Script/Maine.Default__SurvivalGameState:SurvivalModeManagerComponent",
    "/Script/Maine.Default__LobbyGameState:SurvivalModeManagerComponent",
    "/Script/Maine.Default__SurvivalGameInstance",
    "/Game/Blueprints/Global/BP_SurvivalGameState.Default__BP_SurvivalGameState_C:SurvivalModeManagerComponent",
    "/Game/Blueprints/Global/BP_SurvivalGameInstance.Default__BP_SurvivalGameInstance_C",
    "/Game/_Augusta/Global/GameInstance/BP_SurvivalGameInstance_Augusta.Default__BP_SurvivalGameInstance_Augusta_C",
    "/Game/Blueprints/Global/BP_NormalModeSettings.Default__BP_NormalModeSettings_C",
    "/Game/Blueprints/Global/BP_RelaxedModeSettings.Default__BP_RelaxedModeSettings_C",
    "/Game/Blueprints/Global/BP_HardModeSettings.Default__BP_HardModeSettings_C",
    "/Game/Blueprints/Global/BP_CustomModeSettings.Default__BP_CustomModeSettings_C",
    "/Game/Blueprints/Global/BP_CreativeModeSettings.Default__BP_CreativeModeSettings_C",
    "/Game/Blueprints/Global/BP_CreativeCreaturesModeSettings.Default__BP_CreativeCreaturesModeSettings_C",
    "/Game/Blueprints/Global/BP_InventorModeSettings.Default__BP_InventorModeSettings_C",
}

local function targetedScan()
    Tracked = {}
    local changed, seenObj = 0, {}
    local function candidates()
        local out = {}
        local paths = {}
        for _, p in ipairs(KnownObjects) do paths[#paths + 1] = p end
        for _, p in ipairs(loadLearned()) do paths[#paths + 1] = p end
        for _, p in ipairs(paths) do
            local o = nil
            pcall(function() o = StaticFindObject(p) end)
            if valid(o) then out[#out + 1] = o end
        end
        for _, cname in ipairs(TargetClasses) do
            local list = nil
            pcall(function() list = FindAllOf(cname) end)
            for _, o in ipairs(list or {}) do out[#out + 1] = o end
        end
        -- The world's ACTIVE preset object (renamed every session): follow the
        -- live mode manager's GameModeSettings pointer to it.
        pcall(function()
            for _, comp in ipairs(FindAllOf("SurvivalModeManagerComponent") or {}) do
                if valid(comp) then
                    local gms = nil
                    pcall(function() gms = comp.GameModeSettings end)
                    if valid(gms) then out[#out + 1] = gms end
                end
            end
        end)
        -- The running GameInstance lives under /Engine/Transient with a new
        -- name every session: reach it through the engine instead.
        pcall(function() out[#out + 1] = FindFirstOf("GameInstance") end)
        pcall(function()
            local eng = FindFirstOf("GameEngine")
            if valid(eng) then out[#out + 1] = eng.GameInstance end
        end)
        pcall(function()
            local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
            for _, pc in ipairs(FindAllOf("PlayerController") or FindAllOf("SurvivalPlayerController") or {}) do
                if valid(pc) and valid(gs) then out[#out + 1] = gs:GetGameInstance(pc) break end
            end
        end)
        return out
    end
    do
        local list = candidates()
        for _, obj in ipairs(list) do
            if valid(obj) then
                local addr = obj:GetAddress()
                if not seenObj[addr] then
                    seenObj[addr] = true
                    local okC, cls = pcall(function() return obj:GetClass() end)
                    if okC and valid(cls) then
                        for _, e in ipairs(pathsFor(cls)) do
                            Tracked[#Tracked + 1] = { obj = obj, entry = e }
                            local ok, did = setEntry(obj, e)
                            if did then changed = changed + 1 end
                            if not ok then log("Failed to set " .. table.concat(e.path, ".")) end
                            if Config.LogPlaces then
                                log(string.format("TPLACE %s :: %s%s", objectPath(obj), table.concat(e.path, "."), did and " (changed)" or ""))
                            end
                        end
                    end
                end
            end
        end
    end
    return changed, #Tracked
end

local function applyAll(mode)
    local t0 = os.clock()
    local p = applyPresets()
    local changed, seen
    if mode == "quick" then
        changed, seen = quickApply()
        if changed == nil then mode = "targeted" end
    end
    if mode == "targeted" then
        changed, seen = targetedScan()
    elseif mode == "full" then
        changed, seen = fullScan()
    end
    local ms = (os.clock() - t0) * 1000
    if mode ~= "quick" or changed > 0 then
        -- Ask the game itself whether build mode (Handy Gnat) is now available
        local verdict = "unknown"
        pcall(function()
            for _, comp in ipairs(FindAllOf("SurvivalModeManagerComponent") or {}) do
                if valid(comp) then
                    local r = comp:IsBuildModeAvailable()
                    verdict = tostring(r)
                    break
                end
            end
        end)
        log(string.format("Applied (%s, %.0f ms): %d preset option(s), %d change(s) in %d place(s). Game says Handy Gnat available: %s",
            mode, ms, p, changed, seen, verdict))
    end
end

local function safeApply(mode)
    ExecuteInGameThread(function()
        local ok, err = pcall(applyAll, mode)
        if not ok then log("Error: " .. tostring(err)) end
    end)
end

-- Apply when the player spawns in a world. ClientRestart also fires on every
-- mount/dismount and respawn, so collapse bursts into a single (cheap) apply.
local Pending = false
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    if Pending then return end
    Pending = true
    ExecuteWithDelay(Config.ApplyDelayMs, function()
        Pending = false
        safeApply("quick")
    end)
end)

-- Ctrl+F7: targeted re-apply. Ctrl+Shift+F7: full scan of every object
-- (slow - a few seconds of freeze - only as a last resort).
RegisterKeyBind(Config.ReapplyKey, Config.ModifierKeys, function()
    log("Re-applying...")
    safeApply("targeted")
end)
RegisterKeyBind(Config.ReapplyKey, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
    log("Re-applying with a FULL scan (the game may freeze for a few seconds)...")
    safeApply("full")
end)

-- Optional free camera
RegisterKeyBind(Config.SpectatorKey, Config.ModifierKeys, function()
    ExecuteInGameThread(function()
        pcall(function()
            for _, pc in ipairs(FindAllOf("SurvivalPlayerController") or {}) do
                if valid(pc) and pc:IsLocalController() then
                    pc:ToggleSpectatorMode()
                    log("Free camera toggled.")
                    return
                end
            end
        end)
    end)
end)

log("v" .. VERSION .. " loaded. Handy Gnat will be unlocked when you enter a world (build menu -> G).")
