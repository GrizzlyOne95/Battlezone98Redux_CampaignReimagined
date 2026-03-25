-- Weather_Example.lua
-- Example mission-side integration for the reusable Weather module.

local RequireFix = require("RequireFix")
local Weather = require("Weather")

local M = {
    weather = nil,
    nextStageAt = nil,
    nextLightningAt = nil,
    stage = 0,
}

function Start()
    M.weather = Weather.New({
        id = "weather_example",
        followPlayer = true,

        -- Keep this false on maps that already own a skybox, skydome, or skyplane.
        -- Turn it on only when you explicitly want the weather module to provide
        -- a moving cloud layer.
        forceSkyPlaneOverride = false,
    })

    M.weather:TransitionToPreset("overcast", 2.0)
    M.stage = 1
    M.nextStageAt = GetTime() + 20.0
    M.nextLightningAt = GetTime() + 30.0

    print("Weather example: overcast started")
end

function Update()
    if not M.weather then
        return
    end

    M.weather:Update()

    local now = GetTime()

    if M.stage == 1 and now >= M.nextStageAt then
        M.weather:TransitionToPreset("lightning_storm", 4.0)
        M.stage = 2
        M.nextStageAt = now + 30.0
        print("Weather example: transitioned to lightning storm")
    elseif M.stage == 2 and now >= M.nextStageAt then
        M.weather:TransitionToPreset("dust_storm", 3.0)
        M.stage = 3
        M.nextStageAt = now + 25.0
        print("Weather example: transitioned to dust storm")
    elseif M.stage == 3 and now >= M.nextStageAt then
        M.weather:Clear(4.0)
        M.stage = 4
        print("Weather example: clearing back to baseline")
    end

    if M.stage == 2 and now >= M.nextLightningAt then
        M.weather:TriggerLightning({
            intensity = 1.25,
            secondaryIntensity = 0.65,
        })
        M.nextLightningAt = now + 7.0
    end
end

function AddObject(h)
    local _ = h
end

function Save()
    return M
end

-- Alternative pattern:
-- Anchor weather to a fixed marker, objective, or handle instead of the player.
--
--   M.weather:SetAnchor("storm_marker")
--   M.weather:TransitionToPreset("dust_storm", 2.5)
--
-- You can also provide particle templates up front:
--
--   M.weather = Weather.New({
--       id = "misn04_storm",
--       followPlayer = true,
--       particleTemplates = {
--           rain = "Weather/Rain/Heavy",
--           snow = "Weather/Snow/Light",
--           dust = "Weather/Dust/Loop",
--       },
--   })
