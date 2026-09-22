-- lcbench-venus.lua
--
-- Live VenusDenseAtmosphere tuning overlay for the existing lcbench world.
-- Copy this file over addon/lcbench/lcbench.lua with Campaign Reimagined
-- enabled, then launch battlezone98redux.exe lcbench.bzn.

-- lcbench runs outside CR's normal mission entry points, so it must perform the
-- same native-module bootstrap they do before requiring Environment/CRWeather.
-- RequireFix adds the enabled CR mod to package.path/package.cpath and exposes
-- the shipped EXU DLL as the `exu` Lua module.
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3686673790" })
local exu = require("exu")
local Environment = require("Environment")
local CRWeatherPresets = require("CRWeatherPresets")
local CRWeather = require("CRWeather")

local PRESET_NAME = "VenusDenseAtmosphere"
local SYSTEM_NAME = "cr_wx_venus_dense_mist"
local preset = assert(CRWeatherPresets.Get(PRESET_NAME), PRESET_NAME .. " preset is missing")
local mist = assert(preset.precipitation[1], PRESET_NAME .. " mist specification is missing")

local defaults = {
    intensity = 1.00,
    hazeR = 0.66,
    hazeG = 0.72,
    hazeB = 0.26,
    emission = 1.25,
    alpha = 0.30,
    scale = 1.25,
    windBearing = -35.0,
    windSpeed = 3.0,
    poolBase = 0.55,
    poolDepth = 8.0,
    poolRadius = 65.0,
    poolSlope = 28.0,
}

local state = {
    selected = 1,
    enabled = true,
    alpha = defaults.alpha,
    hazeR = defaults.hazeR,
    hazeG = defaults.hazeG,
    hazeB = defaults.hazeB,
    windBearing = defaults.windBearing,
    keys = {},
    nextHudAt = 0.0,
}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function ColourText(r, g, b, a)
    return string.format("%.3f %.3f %.3f %.3f", r, g, b, a)
end

local function SetHazeColour(r, g, b)
    state.hazeR = Clamp(r, 0.0, 1.0)
    state.hazeG = Clamp(g, 0.0, 1.0)
    state.hazeB = Clamp(b, 0.0, 1.0)
    local dimR, dimG, dimB = state.hazeR * 0.88, state.hazeG * 0.89, state.hazeB * 0.85
    mist.affectors[0].colour0 = ColourText(state.hazeR, state.hazeG, state.hazeB, 0.0)
    mist.affectors[0].colour1[1] = ColourText(state.hazeR, state.hazeG, state.hazeB, 0.0)
    mist.affectors[0].colour1[2] = ColourText(state.hazeR, state.hazeG, state.hazeB, state.alpha)
    mist.affectors[0].colour2[1] = ColourText(dimR, dimG, dimB, 0.0)
    mist.affectors[0].colour2[2] = ColourText(dimR, dimG, dimB, state.alpha * (0.20 / 0.30))
    mist.affectors[0].colour3 = ColourText(dimR * 0.93, dimG * 0.91, dimB * 0.82, 0.0)
end

local function SetPatchEmission(value)
    value = Clamp(value, 0.0, 5.0)
    for index = 0, 8 do
        mist.emitters[index].rate = value
    end
end

local function SetMistAlpha(value)
    state.alpha = Clamp(value, 0.0, 0.40)
    SetHazeColour(state.hazeR, state.hazeG, state.hazeB)
end

local function ApplyWind()
    local radians = math.rad(state.windBearing)
    preset.wind.x = math.cos(radians)
    preset.wind.y = -0.06
    preset.wind.z = math.sin(radians)
    if state.enabled then
        CRWeather.SetWindOverride(preset.wind, preset.windSpeed)
    end
end

local controls = {
    { label = "Intensity", step = 0.05,
      get = function() return CRWeather.GetIntensity() end,
      set = function(v) CRWeather.SetIntensity(Clamp(v, 0.0, 1.0)) end },
    { label = "Haze red", step = 0.01,
      get = function() return state.hazeR end,
      set = function(v) SetHazeColour(v, state.hazeG, state.hazeB) end },
    { label = "Haze green", step = 0.01,
      get = function() return state.hazeG end,
      set = function(v) SetHazeColour(state.hazeR, v, state.hazeB) end },
    { label = "Haze blue", step = 0.01,
      get = function() return state.hazeB end,
      set = function(v) SetHazeColour(state.hazeR, state.hazeG, v) end },
    { label = "Emission/patch/s", step = 0.25,
      get = function() return mist.emitters[0].rate end,
      set = SetPatchEmission },
    { label = "Haze alpha", step = 0.01,
      get = function() return state.alpha end,
      set = SetMistAlpha },
    { label = "Haze scale/s", step = 0.25,
      get = function() return mist.affectors[1].rate[2] end,
      set = function(v) mist.affectors[1].rate[2] = Clamp(v, 0.0, 8.0) end },
    { label = "Wind bearing deg", step = 5.0,
      get = function() return state.windBearing end,
      set = function(v)
          state.windBearing = ((v + 180.0) % 360.0) - 180.0
          ApplyWind()
      end },
    { label = "Wind speed", step = 0.5,
      get = function() return preset.windSpeed end,
      set = function(v)
          preset.windSpeed = Clamp(v, 0.0, 20.0)
          ApplyWind()
      end },
    { label = "Pool base", step = 0.05,
      get = function() return mist.terrainPool.baseWeight end,
      set = function(v) mist.terrainPool.baseWeight = Clamp(v, 0.0, 1.0) end },
    { label = "Basin depth full", step = 1.0,
      get = function() return mist.terrainPool.depthForFull end,
      set = function(v) mist.terrainPool.depthForFull = Clamp(v, 1.0, 50.0) end },
    { label = "Pool sample radius", step = 5.0,
      get = function() return mist.terrainPool.sampleRadius end,
      set = function(v) mist.terrainPool.sampleRadius = Clamp(v, 10.0, 250.0) end },
    { label = "Pool max slope", step = 1.0,
      get = function() return mist.terrainPool.slopeEnd end,
      set = function(v) mist.terrainPool.slopeEnd = Clamp(v, mist.terrainPool.slopeStart + 0.1, 45.0) end },
}

local function SelectedText()
    local control = controls[state.selected]
    local pool = CRWeather.GetTerrainPoolState(SYSTEM_NAME) or {}
    return string.format(
        "VENUS GROUND HAZE [%d/%d] %s = %.3f\nPool avg %.2f max %.2f  center depth %.1f slope %.1f\nF1/F2 select  Left/Right change  Shift=coarse x5\nF3 weather/clear  Home defaults  F4 print all",
        state.selected, #controls, control.label, control.get(),
        pool.weight or 0.0, pool.maxWeight or 0.0,
        pool.basinDepth or 0.0, pool.slopeDegrees or 0.0)
end

local function ShowSelected(writeLog)
    local text = SelectedText()
    if UpdateObjective then
        pcall(UpdateObjective, "venusdev", state.enabled and "yellow" or "white", 3600.0, text)
    end
    if writeLog ~= false then
        print("[VENUSDEV] " .. string.gsub(text, "\n", " | "))
    end
end

local function PrintAll()
    print(string.format(
        "[VENUSDEV] intensity=%.2f haze=(%.3f %.3f %.3f quota=%d emitters=9 rate/patch=%.2f alpha=%.3f scale=%.2f) wind=(bearing=%.1f speed=%.2f) pool=(base=%.2f depth=%.1f radius=%.1f slope=%.1f) system=%s",
        CRWeather.GetIntensity(), state.hazeR, state.hazeG, state.hazeB,
        mist.quota, mist.emitters[0].rate, state.alpha, mist.affectors[1].rate[2],
        state.windBearing, preset.windSpeed, mist.terrainPool.baseWeight,
        mist.terrainPool.depthForFull, mist.terrainPool.sampleRadius,
        mist.terrainPool.slopeEnd, SYSTEM_NAME))
end

local function ResetDefaults()
    CRWeather.SetIntensity(defaults.intensity)
    SetPatchEmission(defaults.emission)
    SetHazeColour(defaults.hazeR, defaults.hazeG, defaults.hazeB)
    SetMistAlpha(defaults.alpha)
    mist.affectors[1].rate[2] = defaults.scale
    state.windBearing = defaults.windBearing
    preset.windSpeed = defaults.windSpeed
    mist.terrainPool.baseWeight = defaults.poolBase
    mist.terrainPool.depthForFull = defaults.poolDepth
    mist.terrainPool.sampleRadius = defaults.poolRadius
    mist.terrainPool.slopeEnd = defaults.poolSlope
    ApplyWind()
end

local function KeyDown(name)
    local ok, down = pcall(exu.GetGameKey, name)
    return ok and down == true
end

local function KeyPressed(name)
    local down = KeyDown(name)
    local pressed = down and not state.keys[name]
    state.keys[name] = down
    return pressed
end

local function UpdateInput()
    local changed = false

    if KeyPressed("F1") then
        state.selected = state.selected - 1
        if state.selected < 1 then state.selected = #controls end
        changed = true
    end
    if KeyPressed("F2") then
        state.selected = state.selected + 1
        if state.selected > #controls then state.selected = 1 end
        changed = true
    end

    local direction = 0.0
    if KeyPressed("LARROW") then direction = direction - 1.0 end
    if KeyPressed("RARROW") then direction = direction + 1.0 end
    if direction ~= 0.0 then
        local control = controls[state.selected]
        local multiplier = (KeyDown("SHIFT") or KeyDown("LSHIFT") or KeyDown("RSHIFT")) and 5.0 or 1.0
        control.set(control.get() + (control.step * direction * multiplier))
        changed = true
    end

    if KeyPressed("F3") then
        state.enabled = not state.enabled
        if state.enabled then
            CRWeather.SetPreset(PRESET_NAME, 0.75)
            ApplyWind()
        else
            CRWeather.ClearWindOverride()
            CRWeather.SetPreset("Clear", 0.75)
        end
        changed = true
    end

    if KeyPressed("HOME") then
        ResetDefaults()
        changed = true
    end
    if KeyPressed("F4") then PrintAll() end

    if changed then ShowSelected() end
end

function Start()
    -- Environment must initialize first so CRWeather finds and registers with
    -- the single renderer-state owner instead of taking its standalone path.
    Environment.EnableVisualRuntime = false
    Environment.Init()
    CRWeather.Init({ debug = true, quality = 1.0 })
    ResetDefaults()
    CRWeather.SetPreset(PRESET_NAME, 0.75)
    ApplyWind()

    if AddObjective then
        pcall(AddObjective, "venusdev", "yellow", 3600.0, SelectedText())
    end
    ShowSelected()
    PrintAll()
end

function Update(dt)
    UpdateInput()
    -- Weather advances first; Environment then composes that live contribution
    -- into its frame and remains the only writer of fog, ambient and sun state.
    CRWeather.Update(dt)
    if CRWeather.Clock >= state.nextHudAt then
        state.nextHudAt = CRWeather.Clock + 0.5
        ShowSelected(false)
    end
    Environment.Update(dt)
end
