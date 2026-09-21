-- lcbench-venus.lua
--
-- Live VenusDenseAtmosphere tuning overlay for the existing lcbench world.
-- Copy this file over addon/lcbench/lcbench.lua, with Campaign Reimagined and
-- EXU's weather resources mounted, then launch battlezone98redux.exe lcbench.bzn.

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
    fogR = 0.46,
    fogG = 0.50,
    fogB = 0.20,
    fogStart = 8.0,
    fogEnd = 155.0,
    emission = 6.0,
    alpha = 0.11,
    scale = 1.50,
    windBearing = -35.0,
    windSpeed = 3.0,
}

local state = {
    selected = 1,
    enabled = true,
    alpha = defaults.alpha,
    windBearing = defaults.windBearing,
    keys = {},
}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function ColourText(r, g, b, a)
    return string.format("%.3f %.3f %.3f %.3f", r, g, b, a)
end

local function SetMistAlpha(value)
    state.alpha = Clamp(value, 0.0, 0.40)
    mist.affectors[0].colour1[2] = ColourText(0.66, 0.72, 0.26, state.alpha)
    mist.affectors[0].colour2[2] = ColourText(0.58, 0.64, 0.22, state.alpha * (0.07 / 0.11))
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
    { label = "Fog red", step = 0.01,
      get = function() return preset.fog.r end,
      set = function(v) preset.fog.r = Clamp(v, 0.0, 1.0) end },
    { label = "Fog green", step = 0.01,
      get = function() return preset.fog.g end,
      set = function(v) preset.fog.g = Clamp(v, 0.0, 1.0) end },
    { label = "Fog blue", step = 0.01,
      get = function() return preset.fog.b end,
      set = function(v) preset.fog.b = Clamp(v, 0.0, 1.0) end },
    { label = "Fog start", step = 2.0,
      get = function() return preset.fog.fogStart end,
      set = function(v) preset.fog.fogStart = Clamp(v, 0.0, preset.fog.fogEnd - 1.0) end },
    { label = "Fog end", step = 5.0,
      get = function() return preset.fog.fogEnd end,
      set = function(v) preset.fog.fogEnd = Clamp(v, preset.fog.fogStart + 1.0, 1000.0) end },
    { label = "Mist emission/s", step = 1.0,
      get = function() return mist.emitters[0].rate end,
      set = function(v) mist.emitters[0].rate = Clamp(v, 0.0, 30.0) end },
    { label = "Mist alpha", step = 0.01,
      get = function() return state.alpha end,
      set = SetMistAlpha },
    { label = "Mist scale/s", step = 0.25,
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
}

local function SelectedText()
    local control = controls[state.selected]
    return string.format(
        "VENUS DEV [%d/%d] %s = %.3f\nF1/F2 select  Left/Right change  Shift=coarse x5\nF3 weather/clear  Home defaults  F4 print all",
        state.selected, #controls, control.label, control.get())
end

local function ShowSelected()
    local text = SelectedText()
    if UpdateObjective then
        pcall(UpdateObjective, "venusdev", state.enabled and "yellow" or "white", 3600.0, text)
    end
    print("[VENUSDEV] " .. string.gsub(text, "\n", " | "))
end

local function PrintAll()
    print(string.format(
        "[VENUSDEV] intensity=%.2f fog=(%.3f %.3f %.3f %.1f %.1f) mist=(quota=%d rate=%.2f alpha=%.3f scale=%.2f) wind=(bearing=%.1f speed=%.2f) system=%s",
        CRWeather.GetIntensity(), preset.fog.r, preset.fog.g, preset.fog.b,
        preset.fog.fogStart, preset.fog.fogEnd, mist.quota, mist.emitters[0].rate,
        state.alpha, mist.affectors[1].rate[2], state.windBearing, preset.windSpeed,
        SYSTEM_NAME))
end

local function ResetDefaults()
    CRWeather.SetIntensity(defaults.intensity)
    preset.fog.r = defaults.fogR
    preset.fog.g = defaults.fogG
    preset.fog.b = defaults.fogB
    preset.fog.fogStart = defaults.fogStart
    preset.fog.fogEnd = defaults.fogEnd
    mist.emitters[0].rate = defaults.emission
    SetMistAlpha(defaults.alpha)
    mist.affectors[1].rate[2] = defaults.scale
    state.windBearing = defaults.windBearing
    preset.windSpeed = defaults.windSpeed
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
    Environment.Update(dt)
end
