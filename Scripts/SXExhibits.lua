-- Native exhibit operations. The mission owns fixtures/cameras; this owns reversible overrides.
local State = require("SXState")
local Scenes = require("SXScenes")
local SXExhibits = {}
SXExhibits.__index = SXExhibits
local unpackValues = unpack or table.unpack

function SXExhibits.New(exu, api)
    return setmetatable({ exu = exu, api = api, state = State.New(exu, api.alive),
        message = "", telemetry = "", commandHits = 0 }, SXExhibits)
end

function SXExhibits:Call(name, ...)
    if not self.exu or self.exu.isStub or type(self.exu[name]) ~= "function" then return false end
    return pcall(self.exu[name], ...)
end
function SXExhibits:Read(name, ...)
    local ok, value = self:Call(name, ...)
    if ok then return value end
    return nil
end
function SXExhibits:Has(...)
    if not self.exu or self.exu.isStub then return false end
    for _, name in ipairs({ ... }) do if type(self.exu[name]) ~= "function" then return false end end
    return true
end
function SXExhibits:Record(key, status, detail) self.api.record(key, status, detail) end
function SXExhibits:Fixture(key) return self.api.ensure(key) end
function SXExhibits:Handle(key) return self.api.handles[key] end
function SXExhibits:Go(key, route)
    local h = self:Handle(key)
    if not self.api.alive(h) then return false end
    Goto(h, Scenes.Routes[route or key], 1)
    return true
end

-- Renderer comparison: a mission-scoped OpenShim content override. "inherit" hands
-- control back to the user's own profile; mission reset clears it as well.
function SXExhibits:Lighting(profile)
    if not self:Has("RequestRenderProfile") then
        self:Record("lighting", "BLOCKED", "EXU render profile API unavailable"); return
    end
    if profile ~= "inherit" and self:Has("SupportsRenderProfile") and self:Read("SupportsRenderProfile", profile) == false then
        self:Record("lighting/" .. profile, "BLOCKED", "profile unsupported on this renderer")
        return
    end
    local ok, accepted = self:Call("RequestRenderProfile", profile)
    accepted = ok and accepted == true
    if accepted then self.lightingOverride = profile ~= "inherit" end
    local effective = self:Read("GetEffectiveRenderProfile")
    self:Record("lighting/" .. profile, accepted and "PASS" or "BLOCKED", "requested " .. profile .. "; effective " .. tostring(effective))
    self:Record("lighting", accepted and "PENDING" or "BLOCKED", "live retro/redux/enhanced cycle; compare the frames")
    self.message = "Render profile: " .. tostring(effective)
end

-- The comparison runs under the map's own lighting: each profile must be judged as
-- shipped (Retro diffuse-only, Redux stock, Enhanced with the terrain/lighting work).
function SXExhibits:LightingEnd()
    if not self.lightingOverride then return true end
    local ok, accepted = self:Call("RequestRenderProfile", "inherit")
    if ok and accepted == true then self.lightingOverride = false end
    return not self.lightingOverride
end

-- Weather bay: the CRStormFX particle weather (ported from ISDF Chronicles) is the
-- single fog/light writer while the bay runs. The Moon's own fog is black, so each
-- phase eases toward its own fog/ambient colour, and an overcast dome hides open
-- space while weather is up. Sprite materials are not fogged, so the dome is a
-- solid sky in each phase's fog colour (Materials/sxsky.material).
SXExhibits.WeatherPhases = {
    rain = { fog = { r = 0.30, g = 0.33, b = 0.38 }, amb = { r = 0.30, g = 0.31, b = 0.35 } },
    storm = { fog = { r = 0.22, g = 0.24, b = 0.29 }, amb = { r = 0.24, g = 0.25, b = 0.29 } },
    snow = { fog = { r = 0.66, g = 0.69, b = 0.74 }, amb = { r = 0.52, g = 0.54, b = 0.58 },
        precip = "snow", level = 1.0, wind = { 0.6, 0.3, 4 }, fogScale = 0.55, light = 0.95 },
    dust = { fog = { r = 0.62, g = 0.40, b = 0.22 }, amb = { r = 0.46, g = 0.32, b = 0.20 },
        precip = "dust", level = 1.0, wind = { 1.0, 0.15, 26 }, fogScale = 0.42, light = 0.80 },
}
-- Inside the map's 250 m view range: a dome beyond the far clip is mostly culled.
SXExhibits.StormSky = { curvature = 10, tiling = 1, distance = 200,
    materials = { rain = "SX_Sky/Rain", storm = "SX_Sky/Storm", snow = "SX_Sky/Snow", dust = "SX_Sky/Dust" } }
-- CRPrecip's ISDF Chronicles tuning suits a pilot at ground level; the film camera
-- sits metres up and looks 20-80 m out, so pack the particles closer and larger.
SXExhibits.PrecipLook = { box = 0.4, size = 1.8, rate = 2.2 }

function SXExhibits:WeatherStart()
    if not self:Has("GetFog", "SetFog", "GetAmbientLight", "SetAmbientLight", "GetSunDiffuse", "SetSunDiffuse") then
        self:Record("environment", "BLOCKED", "native fog/light APIs unavailable")
        return
    end
    local required = {
        { "fog", "GetFog", "SetFog" }, { "ambient", "GetAmbientLight", "SetAmbientLight" },
        { "diffuse", "GetSunDiffuse", "SetSunDiffuse" }, { "sunpower", "GetSunPowerScale", "SetSunPowerScale" },
    }
    local all = true
    for _, row in ipairs(required) do
        local captured = self.state:Capture("weather/" .. row[1], "weather", row[2], row[3])
        all = captured and all
    end
    if not all then
        self.state:Discard("weather") -- The controller has not written anything.
        self:Record("environment", "BLOCKED", "scene light baseline not ready"); return
    end
    local ok, storm = pcall(require, "CRStormFX")
    if not ok or type(storm) ~= "table" then
        self.state:Discard("weather")
        self:Record("environment", "BLOCKED", "CRStormFX weather unavailable"); return
    end
    local loaded, templates = pcall(function() return require("CRParticleTemplates").Ensure() end)
    templates = loaded and templates == true
    self.storm, self.weatherPhase, self.weatherTint, self.weatherClock = storm, "clear", nil, 0
    self.skyWasOn = self:Read("GetSkyDomeEnabled")
    self:Record("environment", templates and "PENDING" or "BLOCKED",
        templates and "particle rain/snow/dust, splashes, lightning; single weather writer"
        or "particle templates unavailable; fog/light only")
end

function SXExhibits:WeatherSky(phase)
    local sky = SXExhibits.StormSky
    local material = phase and sky.materials[phase]
    if material and self.skyOn ~= material and self:Has("SetSkyDome") then
        local ok, result = self:Call("SetSkyDome", material, sky.curvature, sky.tiling, sky.distance, true)
        self.skyOn = ok and result ~= false and material or nil
    elseif not material and self.skyOn then
        if self.skyWasOn ~= true then self:Call("SetSkyDomeEnabled", false) end
        self.skyOn = nil
    end
end

function SXExhibits:WeatherPhase(phase)
    local storm = self.storm
    if not storm then return end
    if phase == "rain" or phase == "storm" then
        self:WeatherSky(phase)
        if not storm.GetWeather() then storm.StartDynamicWeather(nil, { start = { drizzle = 1 }, hold = { 900, 900 } }) end
        storm.SetWeather(phase, phase == "rain" and 6 or 5)
        self.message = phase == "rain" and "Weather: rain" or "Weather: storm"
    elseif phase == "snow" or phase == "dust" then
        -- Leave the rain director; its Shutdown also ends the rain sound and splashes.
        if storm.GetWeather() then pcall(storm.Shutdown) end
        self:WeatherSky(phase)
        local w = SXExhibits.WeatherPhases[phase].wind
        storm.Wind(w[1], w[2], w[3])
        self.message = "Weather: " .. phase
    elseif phase == "clear" then
        local prior = SXExhibits.WeatherPhases[self.weatherPhase]
        self.fadePrecip = prior and prior.precip
        self.message = "Weather: clearing"
    else return end
    self.weatherPhase, self.weatherClock = phase, 0
end

function SXExhibits:WeatherTick(dt)
    local storm = self.storm
    local phase = SXExhibits.WeatherPhases[self.weatherPhase]
    self.weatherClock = (self.weatherClock or 0) + dt
    if self.precipLook == nil then
        local ok, precip = pcall(require, "CRPrecip")
        self.precipLook = ok and type(precip) == "table" and type(precip.SetLook) == "function" and precip or false
    end
    if self.precipLook then self.precipLook.SetLook(SXExhibits.PrecipLook) end
    -- Ease the colour toward the phase, or back to the captured base when clearing.
    local base = storm.BaseEnvironment()
    local goal = phase or (base and { fog = base.fog, amb = base.amb })
    if goal and goal.fog and (phase or self.weatherTint) then
        local tint = self.weatherTint or { fog = base and base.fog or goal.fog, amb = base and base.amb or goal.amb }
        local k = math.min(1, dt / 3.5)
        local function ease(a, b)
            if not b then return a end
            a = a or b
            return { r = a.r + (b.r - a.r) * k, g = a.g + (b.g - a.g) * k, b = a.b + (b.b - a.b) * k }
        end
        self.weatherTint = { fog = ease(tint.fog, goal.fog), amb = ease(tint.amb, goal.amb) }
        storm.SetTint(self.weatherTint.fog, self.weatherTint.amb)
    end
    if phase and phase.precip then
        local ramp = math.min(1, self.weatherClock / 4)
        storm.Precip(phase.precip, phase.level * ramp)
        storm.Atmosphere(1 + (phase.fogScale - 1) * ramp, 1 + (phase.light - 1) * ramp)
    elseif self.weatherPhase == "clear" then
        if self.fadePrecip then storm.Precip(self.fadePrecip, math.max(0, 1 - self.weatherClock / 3)) end
        if storm.GetWeather() then
            if not self.clearing then storm.SetWeather("clear", 4); self.clearing = true end
        else
            local fade = math.max(0, 1 - self.weatherClock / 4)
            storm.Atmosphere(1 - 0.45 * fade, 1 - 0.15 * fade)
        end
        if self.weatherClock > 2 then self:WeatherSky(nil) end
    end
    storm.Update()
end

function SXExhibits:WeatherEnd()
    local all = true
    if self.storm then
        all = pcall(self.storm.Shutdown)
        if all then self.storm = nil end
    end
    self:WeatherSky(nil)
    if self.precipLook then pcall(self.precipLook.SetLook, nil) end
    self.weatherPhase, self.weatherTint, self.clearing, self.fadePrecip, self.precipLook = nil, nil, nil, nil, nil
    local restored = self.state:Restore("weather")
    return all and restored
end

-- OpenShim kiting acts inside the native AttackTask, which fighters run and tanks do
-- not, so the duel is fighter against a fixed turret, which also keeps the gap readable. The ranges sit just inside the avfigh's
-- ~119 m guns: back off inside 85 m, settle at 105, give up the kite past 117. Stock
-- fighters close to 50-70 m, so the gap reads on screen.
SXExhibits.AiTuning = { engageRange = 118, weaponRangeMin = 110, retargetPeriod = 0.75,
    kiteDesiredRange = 105, kiteEnterRange = 85, kiteExitRange = 117,
    kitePreserveLos = true, kiteStrafe = 1.0, kiteSwitchPeriod = 1.6 }

function SXExhibits:SetupAI()
    for _, key in ipairs({ "ai_look", "ai_stock", "ai_tuned", "ai_target_a", "ai_target_b" }) do self:Fixture(key) end
    self:Record("ai", "PENDING", "native attacks; compare actual ranges and movement")
end
function SXExhibits:TuneAI(h)
    if not self:Has("SetAiUnitTuning", "GetAiUnitTuning", "ClearAiUnitTuning") then
        self:Record("ai/api", "BLOCKED", "tuning or cleanup API unavailable"); return
    end
    local tuning, tier = State.Copy(SXExhibits.AiTuning), "V3 standoff / kiting / strafe"
    local ok, accepted = self:Call("SetAiUnitTuning", h, tuning)
    if not ok or accepted ~= true then
        tuning.kiteStrafe, tuning.kiteSwitchPeriod = nil, nil
        ok, accepted = self:Call("SetAiUnitTuning", h, tuning); tier = "V2 standoff / kiting"
    end
    if not ok or accepted ~= true then
        tuning = { engageRange = tuning.engageRange, weaponRangeMin = tuning.weaponRangeMin, retargetPeriod = tuning.retargetPeriod }
        ok, accepted = self:Call("SetAiUnitTuning", h, tuning); tier = "V1 range floors"
    end
    local read = self:Read("GetAiUnitTuning", h)
    local matches = ok and accepted == true and type(read) == "table" and read.engageRange == tuning.engageRange
    self:Record("ai/api", matches and "PASS" or "BLOCKED", tier .. "; mirror is not behavioral proof")
    self.message = "AI tuning: " .. (matches and tier or "unavailable")
end
function SXExhibits:AIAction(action)
    if action ~= "ai-attack" then return end
    local a, b = self:Handle("ai_stock"), self:Handle("ai_tuned")
    local ta, tb = self:Handle("ai_target_a"), self:Handle("ai_target_b")
    if not self.api.alive(a) or not self.api.alive(b) or not self.api.alive(ta) or not self.api.alive(tb) then
        self:Record("ai", "BLOCKED", "AI fixtures unavailable"); return
    end
    -- Tune before the first order so the comparison runs side by side from frame one.
    -- The turrets need no order: they fire at whatever comes into range.
    self:TuneAI(b)
    Attack(a, ta, 1); Attack(b, tb, 1)
end

-- Pilot deaths: SkinnedGibs (OpenShim) cuts each person's own skinned mesh into posed
-- limb gibs. Damage() takes the native person-death path the hook watches.
function SXExhibits:SetupPilots()
    -- Runners are built when their run starts: standing idle, some wander off.
    local runner = {}
    for _, key in ipairs(Scenes.GibRunners) do runner[key] = true end
    local built, expected = 0, 0
    for key, spec in pairs(Scenes.Fixtures) do
        if spec.group == "pilots" and not runner[key] then
            expected = expected + 1
            if self.api.valid(self:Fixture(key)) then built = built + 1 end
        end
    end
    self.gibKills = 0
    self:Record("gibs", built == expected and "PENDING" or "BLOCKED",
        string.format("%d/%d people; needs OpenShim [General] SkinnedGibs = 1", built, expected))
end
function SXExhibits:KillPerson(key)
    local h = self:Handle(key)
    if not self.api.alive(h) then
        if not (self.gibDone and self.gibDone[key]) then self:Record("gibs/" .. key, "BLOCKED", "person fixture unavailable") end
        return
    end
    Damage(h, GetCurHealth(h) + GetMaxHealth(h) + 1000)
    self.gibDone = self.gibDone or {}
    self.gibDone[key] = true
    self.gibKills = (self.gibKills or 0) + 1
    self:Record("gibs/" .. key, "PENDING", "native person death issued; gib count is in the OpenShim log")
    self.message = string.format("Pilots down: %d", self.gibKills)
end
function SXExhibits:PilotTick()
    for key, mark in pairs(Scenes.GibMarks) do
        local h = self:Handle(key)
        if self.gibRunning and self.api.alive(h) and GetDistance(h, mark) < 6 then self:KillPerson(key) end
    end
end

function SXExhibits:SetupFilters()
    self.protected, self.protectedPassed, self.targetHealth = nil, false, nil
    local count, expected, classesMatch = 0, 0, true
    for key, spec in pairs(Scenes.Fixtures) do
        if spec.group == "filters" then
            expected = expected + 1
            local h = self:Fixture(key)
            if self.api.valid(h) then
                count = count + 1
                if spec.class and type(GetClassLabel) == "function" and GetClassLabel(h) ~= spec.class then
                    classesMatch = false
                    self:Record("filters/" .. key, "BLOCKED", "native class mismatch")
                end
            end
        end
    end
    self:Record("filters", count == expected and classesMatch and "PENDING" or "BLOCKED",
        "enemy-only shield/magnet; enemy-only and ally-only proximity lanes")
end

function SXExhibits:FilterAction(action)
    local moves = { ["shield-ally"] = "shield_ally", ["shield-enemy"] = "shield_enemy",
        ["magnet-ally"] = "magnet_ally", ["magnet-enemy"] = "magnet_enemy" }
    if moves[action] then self:Go(moves[action]); self.message = action:gsub("%-", " "); return end
    if action == "prox-protected" then
        if not self.api.alive(self:Handle("pe_ally")) or not self.api.alive(self:Handle("pa_enemy")) then
            self:Record("filters/protected", "BLOCKED", "protected craft unavailable"); return
        end
        self.protected = { pe = GetCurHealth(self:Handle("pe_ally")), pa = GetCurHealth(self:Handle("pa_enemy")) }
        self:Go("pe_ally"); self:Go("pa_enemy")
        self.message = "Mines: allies cross"
    elseif action == "prox-check" then
        local pe, pa = self:Handle("pe_ally"), self:Handle("pa_enemy")
        local safe = self.protected and self.api.alive(pe) and self.api.alive(pa)
            and self.api.alive(self:Handle("prox_enemy")) and self.api.alive(self:Handle("prox_ally"))
            and GetCurHealth(pe) == self.protected.pe and GetCurHealth(pa) == self.protected.pa
        local crossed = safe and GetDistance(pe, "sx_pe_ally_exit") < 12
            and GetDistance(pa, "sx_pa_enemy_exit") < 12
        self.protectedPassed = crossed == true
        self:Record("filters/protected", crossed and "PASS" or "PENDING", "protected craft survive and reach lane exit")
    elseif action == "prox-targeted" then
        local pe, pa = self:Handle("pe_enemy"), self:Handle("pa_ally")
        if self.api.alive(pe) and self.api.alive(pa) then
            self.targetHealth = { pe = GetCurHealth(pe), pa = GetCurHealth(pa) }
            self:Go("pe_enemy"); self:Go("pa_ally")
        end
        self.message = "Mines: enemies cross"
    end
end

function SXExhibits:FilterWitness()
    if not self.targetHealth then return end
    local function Hurt(key, before)
        local h = self:Handle(key)
        return not self.api.alive(h) or GetCurHealth(h) < before
    end
    local triggered = not self.api.alive(self:Handle("prox_enemy")) and not self.api.alive(self:Handle("prox_ally"))
        and Hurt("pe_enemy", self.targetHealth.pe) and Hurt("pa_ally", self.targetHealth.pa)
    self:Record("filters/proximity", self.protectedPassed and triggered and "PASS" or "PENDING",
        "native mine disappearance + damage + protected crossing; shield/magnet require observation")
end

function SXExhibits:SetupControl()
    local h = self:Fixture("radio")
    self.commandHits = 0
    if not self.api.valid(h) or not self:Has("ReplaceStockCmd", "RemoveStockCmdReplacement",
        "TriggerStockCmdReplacement", "UpdateCommandReplacements", "HasStockCmdReplacement") then
        self:Record("command", "BLOCKED", "native command replacement unavailable"); return
    end
    local ok, result = self:Call("ReplaceStockCmd", h, "Hunt", "Run trial", function(unit, _, _, origin)
        if not self.api.alive(unit) then return false end
        self.commandHits = self.commandHits + 1
        Goto(unit, Scenes.Routes.radio, 1)
        local intercepted = origin == "native_set_active_mode" or origin == "stock_command_poll"
        self:Record("command/dispatch", "PASS", "callback origin=" .. tostring(origin))
        self:Record("command", intercepted and "PASS" or "PENDING",
            intercepted and "real Hunt interception" or "film dispatch; real Hunt check remains interactive")
        return true
    end)
    local registered = ok and result ~= false and self:Read("HasStockCmdReplacement", h, "Hunt") == true
    self.commandRegistered = registered
    self:Record("command", registered and "PENDING" or "BLOCKED", "select the radio tank and use Hunt / Run trial")
    if registered and self:Has("SelectOne", "SelectNone", "SelectAdd") and type(SelectedObjects) == "function" then
        self.selection = {}
        for selected in SelectedObjects() do self.selection[#self.selection + 1] = selected end
        self:Call("SelectOne", h)
    end
end

function SXExhibits:RadioPolicy(mode)
    local normal = mode == "radio-normal"
    local muted = mode == "radio-muted"
    local rows = {
        { "muted", "GetUnitVoMuted", "SetUnitVoMuted", muted },
        { "throttle", "GetUnitVoThrottle", "SetUnitVoThrottle", normal and 0 or 1500 },
        { "depth", "GetUnitVoQueueDepthLimit", "SetUnitVoQueueDepthLimit", normal and 8 or 2 },
        { "stale", "GetUnitVoQueueStaleMs", "SetUnitVoQueueStaleMs", normal and 5000 or 1200 },
    }
    local all = true
    for _, row in ipairs(rows) do
        local changed = self.state:Write("radio/" .. row[1], "radio", row[2], row[3], { row[4] }, { preserveExternal = true })
        all = changed and all
    end
    self:Record("radio/api", all and "PASS" or "BLOCKED", mode .. "; queue/mute readback")
    self:Record("radio", all and "PENDING" or "BLOCKED", "listen to actual unit acknowledgements; narration is separate")
    self.message = muted and "Radio muted" or (normal and "Radio normal" or "Radio throttled")
    if self.api.alive(self:Handle("radio")) then
        Goto(self:Handle("radio"), normal and Scenes.Routes.radio or Scenes.Routes.radio_return, 0)
    end
end

function SXExhibits:CockpitStart()
    self.player = GetPlayerHandle()
    self.hudWidth, self.hudHeight = self.api.resolution()
    self.state:Write("view", "view", "GetCameraView", "SetCameraView", { 1 }, { preserveExternal = true })
    self:Record("hud", "PENDING", "real stock cockpit; meter values and scrap/pilot anchors")
end

function SXExhibits:Radar(mode)
    local player = self.player
    local all = self.state:Write("radar/mode", "cockpit", "GetRadarState", "SetRadarState", { mode }, { preserveExternal = true })
    local resized = self.state:Write("radar/scale", "cockpit", "GetRadarSizeScale", "SetRadarSizeScale",
        { mode == 0 and 0.75 or 1.15 }, { preserveExternal = true })
    all = resized and all
    if self.api.alive(player) then
        local range = self.state:Write("radar/range", "cockpit", "GetRadarRange", "SetRadarRange",
            { mode == 0 and 220 or 460 }, { args = { player }, handle = true })
        local period = self.state:Write("radar/period", "cockpit", "GetRadarPeriod", "SetRadarPeriod",
            { mode == 0 and 2 or 0.75 }, { args = { player }, handle = true })
        all = range and period and all
    else all = false end
    self:Record("radar", all and "PASS" or "BLOCKED", "native map/scan, size, range and period readback; SP only")
    self.message = mode == 0 and "Radar: map" or "Radar: scan"
end

function SXExhibits:MoveHUD()
    local width, height = self.api.resolution()
    local all = true
    for _, row in ipairs({ { "scrap", "Scrap", 0.68, 0xff70ddff }, { "pilot", "Pilot", 0.82, 0xffffcc70 } }) do
        local position = self.state:Write("hud/" .. row[1], "cockpit", "Get" .. row[2] .. "HudTopLeft",
            "Set" .. row[2] .. "HudTopLeft", { math.floor(width * row[3]), math.floor(height * 0.63) }, { preserveExternal = true })
        local color = self.state:Write("hud/" .. row[1] .. "Color", "cockpit", "Get" .. row[2] .. "HudColor",
            "Set" .. row[2] .. "HudColor", { row[4] }, { preserveExternal = true })
        all = position and color and all
    end
    self.hudMoved = all
    self.api.overlay:Slots(all)
    self:Record("hud", all and "PASS" or "BLOCKED", "live stock scrap/pilot text moved and recolored; meters stay native")
    self.message = "HUD readouts moved"
end

function SXExhibits:HUDValues()
    local h = self.player
    if not self.api.alive(h) then self:Record("hud/values", "BLOCKED", "player object unavailable"); return end
    local health, ammo = GetCurHealth(h), GetCurAmmo(h)
    local a = self.state:Write("player/health", "cockpit", "GetCurHealth", "SetCurHealth",
        { math.max(1, math.floor(health * 0.65)) }, { scope = "stock", args = { h }, handle = true })
    local b = self.state:Write("player/ammo", "cockpit", "GetCurAmmo", "SetCurAmmo",
        { math.max(0, math.floor(ammo * 0.50)) }, { scope = "stock", args = { h }, handle = true })
    self:Record("hud/values", a and b and "PASS" or "BLOCKED", "controlled live health/ammo change, restored after the shot")
    self.message = "Hull and ammo set live"
end

function SXExhibits:CockpitEnd()
    if self.hudMoved then
        local w, h = self.api.resolution()
        for _, id in ipairs({ "hud/scrap", "hud/pilot" }) do
            local entry = self.state.entries[id]
            if entry and self.hudWidth and self.hudHeight then
                entry.values[1] = math.floor(entry.values[1] * w / self.hudWidth + 0.5)
                entry.values[2] = math.floor(entry.values[2] * h / self.hudHeight + 0.5)
            end
        end
        self.hudWidth, self.hudHeight = w, h
    end
    self.hudMoved = false
    self.api.overlay:Slots(false)
    return self.state:Restore("cockpit")
end

function SXExhibits:Options()
    self.message = "Press Esc for settings"
    self:Record("options", "PENDING", "native options exercise is interactive; saved preferences are not overwritten")
end

function SXExhibits:Begin(scene)
    self.message, self.telemetry = "", ""
    if scene.target and Scenes.Fixtures[scene.target] then self:Fixture(scene.target) end
    -- Later shots cut to their own anchors; build them now so no cut falls back.
    for _, shot in ipairs(scene.shots or {}) do
        if shot.target and Scenes.Fixtures[shot.target] then self:Fixture(shot.target) end
    end
    if scene.id == "ai" then self:SetupAI()
    elseif scene.id == "chunks" then
        local built = 0
        for _, key in ipairs(Scenes.Breaks) do
            if self.api.valid(self:Fixture(key)) then built = built + 1 end
        end
        self.kills = 0
        self:Record("chunks", built == #Scenes.Breaks and "PENDING" or "BLOCKED",
            string.format("%d/%d victims; requires enabled OpenShim chunks and compatible assets", built, #Scenes.Breaks))
    elseif scene.id == "pilots" then self.gibDone, self.gibRunning = {}, false; self:SetupPilots()
    elseif scene.id == "filters" then self:SetupFilters()
    elseif scene.id == "control" then self:SetupControl() end
end

function SXExhibits:Cue(scene, cue)
    local id = cue.id
    if id:match("^light%-") then self:Lighting(id:sub(7))
    elseif id == "weather-start" then self:WeatherStart()
    elseif id == "weather-strike" and self.storm then self.storm.StrikeNow(cue.cloud == true)
    elseif id:match("^weather%-") and self.storm then self:WeatherPhase(id:sub(9))
    elseif id:match("^ai%-") then self:AIAction(id)
    elseif id == "break" then
        local key = cue.key
        local h = self:Handle(key)
        if self.api.alive(h) then
            Damage(h, GetCurHealth(h) + GetMaxHealth(h) + 1000)
            self.kills = (self.kills or 0) + 1
            self:Record("chunks/" .. key, "PENDING", "native damage/death issued; no chunk-count query")
        else self:Record("chunks/" .. key, "BLOCKED", "destruction fixture unavailable") end
        self.message = string.format("Destroyed: %d/%d", self.kills or 0, #Scenes.Breaks)
    elseif id == "gib-kill" then self:KillPerson(cue.key)
    elseif id == "gib-run" then
        for _, key in ipairs(Scenes.GibRunners) do self:Fixture(key); self:Go(key) end
        self.gibRunning = true
    elseif id == "gib-flush" then
        for _, key in ipairs(Scenes.GibRunners) do self:KillPerson(key) end
    elseif id:match("^shield%-") or id:match("^magnet%-") or id:match("^prox%-") then self:FilterAction(id)
    elseif id:match("^radio%-") then self:RadioPolicy(id)
    elseif id == "command-film" then
        local ok, accepted = self:Call("TriggerStockCmdReplacement", self:Handle("radio"), "Hunt")
        if not ok or accepted ~= true then self:Record("command", "BLOCKED", "film dispatch refused") end
        self.message = "Custom Hunt order"
    elseif id == "cockpit-start" then self:CockpitStart()
    elseif id == "radar-map" then self:Radar(0)
    elseif id == "radar-scan" then self:Radar(1)
    elseif id == "hud-move" then self:MoveHUD()
    elseif id == "hud-values" then self:HUDValues()
    elseif id == "cockpit-baseline" then
        self:Record("restore/cockpit", self:CockpitEnd() and "PASS" or "FAIL", "live meters, radar and text baselines")
        self.message = "HUD restored"
    elseif id == "autosave-preview" then
        self.api.overlay:Notify("Autosaving...", 4, self.api.clock(), true)
        self.message = "Autosave notice preview"
        self:Record("autosave", self.api.overlay.ready and "PENDING" or "BLOCKED",
            "notification preview; sx save requests a real dedicated checkpoint")
    elseif id == "options" then self:Options()
    elseif id == "freeplay" then self.message = "Free play. sx <chapter> replays a chapter." end
end

function SXExhibits:Update(dt, scene)
    if self.storm then
        local ok, err = pcall(self.WeatherTick, self, dt)
        if not ok then self:Record("environment", "FAIL", err); self:WeatherEnd() end
    end
    if self.commandRegistered then self:Call("UpdateCommandReplacements") end
    if not scene then self.telemetry = self:PlayerTelemetry(); return end
    if scene.id == "environment" and self.storm then
        local fog = self:Read("GetFog")
        self.telemetry = string.format("Weather %s | rain %.2f | fog end %.0fm | dome %s", tostring(self.weatherPhase),
            self.storm.GetRainIntensity() or 0, type(fog) == "table" and (fog.ending or fog.fogEnd or 0) or 0,
            self.skyOn and "on" or "off")
    elseif scene.id == "lighting" then
        self.telemetry = "Effective render profile: " .. tostring(self:Read("GetEffectiveRenderProfile"))
    elseif scene.id == "ai" then
        local function Range(a, b)
            return self.api.alive(self:Handle(a)) and self.api.alive(self:Handle(b)) and GetDistance(self:Handle(a), self:Handle(b)) or 0
        end
        self.telemetry = string.format("Range: stock %.0f m | tuned %.0f m", Range("ai_stock", "ai_target_a"), Range("ai_tuned", "ai_target_b"))
    elseif scene.id == "pilots" then
        self:PilotTick()
        self.telemetry = string.format("People down %d / %d", self.gibKills or 0, #Scenes.GibStanders + #Scenes.GibRunners)
    elseif scene.id == "filters" then
        local a, b = self:Handle("magnet_ally"), self:Handle("magnet_enemy")
        self.telemetry = string.format("Magnet distances: ally %.1fm | enemy %.1fm", self.api.alive(a) and GetDistance(a, "sx_magnet") or 0,
            self.api.alive(b) and GetDistance(b, "sx_magnet") or 0)
    elseif scene.id == "control" then
        self.telemetry = string.format("Command callbacks %d | radio muted %s", self.commandHits, tostring(self:Read("GetUnitVoMuted")))
    elseif scene.id == "cockpit" or scene.id == "handover" then self.telemetry = self:PlayerTelemetry() end
end

function SXExhibits:PlayerTelemetry()
    local player = GetPlayerHandle()
    if not self.api.alive(player) then return "Player object unavailable" end
    local width, height = self.api.resolution()
    return string.format("Live hull %.0f | ammo %.0f | %dx%d | UI scale %s | music setting %s/10",
        GetCurHealth(player), GetCurAmmo(player), width, height, tostring(self:Read("GetUIScaling")), tostring(self:Read("GetMusicVolume")))
end

function SXExhibits:RestoreSelection()
    if not self.selection then return true end
    local selected = {}
    if type(SelectedObjects) == "function" then for h in SelectedObjects() do selected[#selected + 1] = h end end
    local all = true
    -- Preserve a new player selection made while the chapter was running.
    if #selected == 1 and selected[1] == self:Handle("radio") then
        all = self:Call("SelectNone")
        for _, h in ipairs(self.selection) do if self.api.valid(h) then
            local ok, result = self:Call("SelectAdd", h); all = ok and result ~= false and all
        end end
    end
    if all then self.selection = nil end
    return all
end

function SXExhibits:RemoveCommand()
    if not self.commandRegistered then return true end
    local h = self:Handle("radio")
    if not self.api.valid(h) then self.commandRegistered = false; return true end
    local queried, exists = self:Call("HasStockCmdReplacement", h, "Hunt")
    if queried and exists == false then self.commandRegistered = false; return true end
    local ok, result = self:Call("RemoveStockCmdReplacement", h, "Hunt")
    if ok and result ~= false then self.commandRegistered = false; return true end
    return false
end

function SXExhibits:Leave(scene)
    local all = true
    if scene.id == "environment" then all = self:WeatherEnd()
    elseif scene.id == "lighting" then all = self:LightingEnd()
    elseif scene.id == "pilots" then self.gibRunning = false
    elseif scene.id == "ai" then
        local h = self:Handle("ai_tuned")
        if self.api.valid(h) then self:Call("ClearAiUnitTuning", h) end
    elseif scene.id == "filters" then self:FilterWitness()
    elseif scene.id == "control" then
        all = self:RemoveCommand()
        local radio = self.state:Restore("radio")
        local selection = self:RestoreSelection()
        all = radio and selection and all
    elseif scene.id == "cockpit" then all = self:CockpitEnd() end
    local removed = self.api.removeGroup(scene.id)
    all = removed and all
    if not all then self:Record("restore/" .. scene.id, "FAIL", "temporary override restoration incomplete") end
    -- Stop at this boundary: later bays must not inherit failed overrides.
    return all
end

function SXExhibits:Restore()
    local all = self:WeatherEnd()
    local cockpit = self:CockpitEnd()
    local command = self:RemoveCommand()
    local selection = self:RestoreSelection()
    local state = self.state:Restore()
    local lighting = self:LightingEnd()
    self.gibRunning = false
    if self.api.valid(self:Handle("ai_tuned")) then self:Call("ClearAiUnitTuning", self:Handle("ai_tuned")) end
    for _, group in ipairs({ "ai", "chunks", "pilots", "filters" }) do
        local removed = self.api.removeGroup(group)
        all = removed and all
    end
    return all and cockpit and command and selection and state and lighting
end

function SXExhibits:Snapshot()
    return { state = self.state:Snapshot(), lightingOverride = self.lightingOverride, selection = self.selection,
        player = self.player, hudMoved = self.hudMoved, hudWidth = self.hudWidth, hudHeight = self.hudHeight,
        commandRegistered = self.commandRegistered }
end
function SXExhibits:Load(snapshot)
    if not snapshot then return end
    self.state:Load(snapshot.state)
    self.lightingOverride, self.selection, self.player = snapshot.lightingOverride, snapshot.selection, snapshot.player
    self.hudMoved, self.hudWidth, self.hudHeight = snapshot.hudMoved, snapshot.hudWidth, snapshot.hudHeight
    self.commandRegistered = snapshot.commandRegistered
end

return SXExhibits
