--[[
    Handy Gnat Anywhere - Grounded 2 (UE4SS Lua mod)
    Version 1.0.0  |  https://github.com/kamibiel/handy-gnat-anywhere
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
      Ctrl + F7  -> re-apply (if the Gnat does not show up)
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
    Presets = { "BP_NormalModeSettings", "BP_RelaxedModeSettings", "BP_HardModeSettings" },

    ApplyDelayMs   = 3000,
    ReapplyKey     = Key.F7,
    SpectatorKey   = Key.F6,
    ModifierKeys   = { ModifierKey.CONTROL },
    MaxStructDepth = 3,
}
------------------------------------------------------------------

local VERSION = "1.0.0"
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

local function applyEverywhere()
    local changed, seen = 0, 0
    ForEachUObject(function(obj)
        if not valid(obj) then return end
        local okC, cls = pcall(function() return obj:GetClass() end)
        if not okC or not valid(cls) then return end
        local paths = pathsFor(cls)
        if #paths == 0 then return end
        for _, e in ipairs(paths) do
            seen = seen + 1
            local want = Config.Options[e.opt]
            local ok = pcall(function()
                local v = obj
                for i = 1, #e.path - 1 do v = v[e.path[i]] end
                local last = e.path[#e.path]
                if v[last] ~= want then
                    v[last] = want
                    changed = changed + 1
                    local nm = "?"
                    pcall(function() nm = obj:GetFullName() end)
                    log(string.format("%s :: %s -> %s", nm, table.concat(e.path, "."), tostring(want)))
                end
            end)
            if not ok then log("Failed to set " .. table.concat(e.path, ".")) end
        end
    end)
    return changed, seen
end

local function applyAll()
    local p = applyPresets()
    local changed, seen = applyEverywhere()
    log(string.format("Applied: %d preset option(s), %d change(s) in %d place(s). Open the build menu and press G.",
        p, changed, seen))
end

local function safeApply()
    ExecuteInGameThread(function()
        local ok, err = pcall(applyAll)
        if not ok then log("Error: " .. tostring(err)) end
    end)
end

-- Apply when the player spawns in a world
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteWithDelay(Config.ApplyDelayMs, safeApply)
end)

RegisterKeyBind(Config.ReapplyKey, Config.ModifierKeys, function()
    log("Re-applying...")
    safeApply()
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
