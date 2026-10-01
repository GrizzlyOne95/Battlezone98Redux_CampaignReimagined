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

function SXExhibits:MusicStart()
    if not self.musicBase then
        local original = self:Read("GetMusicState")
        if type(original) ~= "table" or type(original.track) ~= "number"
            or original.track < 0 or original.track > 255 or original.track ~= math.floor(original.track)
            or not self:Has("SetMusicTrack", "StopMusic", "ResetMusic", "GetMusicState")
            or (original.paused and not self:Has("PauseMusic")) then
            self:Record("music", "BLOCKED", "native soundtrack selection/restore unavailable")
            return false
        end
        self.musicBase = State.Copy(original)
    end
    local ok, result = self:Call("SetMusicTrack", 7)
    local current = self:Read("GetMusicState")
    local accepted = ok and result == true and type(current) == "table" and current.track == 7 and current.playing
    self:Record("music", accepted and "PASS" or "BLOCKED", "native track 7; audibility needs operator observation")
    return accepted
end

function SXExhibits:MusicAction(action)
    if not self.musicBase and not self:MusicStart() then return end
    local method, args, expected
    if action == "music-pause" then method, args, expected = "PauseMusic", {}, "paused"
    elseif action == "music-resume" then method, args, expected = "ResumeMusic", {}, "playing"
    elseif action == "music-change" then method, args = "ChangeMusicTrack", { 12, 2, 2 }
    elseif action == "music-stop" then method, args = "StopMusic", {}
    else self:MusicStart(); return end
    local ok, result = self:Call(method, unpackValues(args))
    local current = self:Read("GetMusicState")
    local accepted = ok and result == true and type(current) == "table"
    if expected then accepted = accepted and current[expected] == true end
    if action == "music-stop" then accepted = accepted and not current.playing and not current.paused end
    if action == "music-change" then accepted = accepted and current.fading == true end
    self.message = ({ ["music-pause"] = "Native soundtrack paused", ["music-resume"] = "Native soundtrack resumed",
        ["music-change"] = "Native soundtrack - fade to track 12", ["music-stop"] = "Native soundtrack stopped" })[action]
    self:Record("music/" .. action, accepted and "PASS" or "BLOCKED", "native state readback; sound needs observation")
end

function SXExhibits:RestoreMusic()
    if not self.musicBase then return true end
    local base, all = self.musicBase, true
    local ok, result = self:Call("ResetMusic")
    all = ok and result ~= false
    if base.playing or base.paused then
        ok, result = self:Call("SetMusicTrack", base.track)
        all = all and ok and result == true
        if base.paused then
            ok, result = self:Call("PauseMusic")
            all = all and ok and result == true
        end
    else
        -- Stop retains the selected track. Restore that selection before stopping.
        if base.track >= 0 then
            ok, result = self:Call("SetMusicTrack", base.track)
            all = all and ok and result == true
        end
        ok, result = self:Call("StopMusic")
        all = all and ok and result == true
    end
    local current = self:Read("GetMusicState")
    all = all and type(current) == "table" and current.track == base.track
        and current.playing == base.playing and current.paused == base.paused
    if all then self.musicBase = nil end
    self:Record("restore/music", all and "PASS" or "FAIL", "playback policy restored; exact stream position unavailable")
    return all
end

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
    local ok, weather = pcall(require, "CRWeather")
    if not ok or type(weather) ~= "table" then
        self.state:Discard("weather")
        self:Record("environment", "BLOCKED", "campaign weather controller unavailable"); return
    end
    self.weather = weather
    local started, errorText = pcall(function()
        weather.Init({ enabled = true, quality = 0.45, fogHorizon = 250 })
        local presets = require("CRWeatherPresets")
        local warm = State.Copy(presets.Presets.Clear)
        warm.name, warm.sky = "SXLivewireWarm", nil
        warm.fog = { r = 0.45, g = 0.28, b = 0.18, fogStart = 130, fogEnd = 250 }
        warm.ambient = { r = 0.28, g = 0.15, b = 0.08 }
        warm.diffuse = { r = 0.90, g = 0.47, b = 0.20 }
        warm.sunPowerScale = 0.85
        presets.Presets.SXLivewireWarm = warm
        weather.SetPreset(nil, 0)
    end)
    if not started then
        self:Record("environment", "BLOCKED", tostring(errorText)); self:WeatherEnd(); return
    end
    self:Record("environment", "PENDING", "single weather writer; warm light, dust, and baseline return")
end

function SXExhibits:WeatherEnd()
    local all = true
    if self.weather then
        all = pcall(self.weather.Shutdown)
        if all then self.weather = nil end
    end
    local restored = self.state:Restore("weather")
    return all and restored
end

function SXExhibits:SetupAI()
    for _, key in ipairs({ "ai_stock", "ai_tuned", "ai_target_a", "ai_target_b" }) do self:Fixture(key) end
    self:Record("ai", "PENDING", "native attacks; compare actual ranges and movement")
end
function SXExhibits:AIAction(action)
    local a, b = self:Handle("ai_stock"), self:Handle("ai_tuned")
    local ta, tb = self:Handle("ai_target_a"), self:Handle("ai_target_b")
    if not self.api.alive(a) or not self.api.alive(b) or not self.api.alive(ta) or not self.api.alive(tb) then
        self:Record("ai", "BLOCKED", "AI fixtures unavailable"); return
    end
    if action == "ai-attack" then Attack(a, ta, 1); Attack(b, tb, 1)
    elseif action == "ai-tune" then
        if not self:Has("SetAiUnitTuning", "GetAiUnitTuning", "ClearAiUnitTuning") then
            self:Record("ai/api", "BLOCKED", "tuning or cleanup API unavailable"); return
        end
        local tuning = { engageRange = 180, weaponRangeMin = 120, retargetPeriod = 0.75,
            kiteDesiredRange = 120, kiteEnterRange = 70, kiteExitRange = 160,
            kitePreserveLos = true, kiteStrafe = 0.35, kiteSwitchPeriod = 1.2 }
        local ok, accepted = self:Call("SetAiUnitTuning", b, tuning)
        local tier = "V3 standoff / kiting / strafe"
        if not ok or accepted ~= true then
            tuning.kiteStrafe, tuning.kiteSwitchPeriod = nil, nil
            ok, accepted = self:Call("SetAiUnitTuning", b, tuning); tier = "V2 standoff / kiting"
        end
        if not ok or accepted ~= true then
            tuning = { engageRange = 180, weaponRangeMin = 120, retargetPeriod = 0.75 }
            ok, accepted = self:Call("SetAiUnitTuning", b, tuning); tier = "V1 range floors"
        end
        local read = self:Read("GetAiUnitTuning", b)
        local matches = ok and accepted == true and type(read) == "table" and read.engageRange == 180
        self:Record("ai/api", matches and "PASS" or "BLOCKED", tier .. "; mirror is not behavioral proof")
        self.message = "AI comparison - " .. (matches and tier or "tuning unavailable; stock control")
    elseif action == "ai-cut" then self.aiSide = true end
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
        self.message = "Proximity lanes - protected teams cross first"
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
        self.message = "Proximity lanes - configured teams trigger the mines"
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
    self.message = muted and "Radio - unit responses muted" or (normal and "Radio - normal responses" or "Radio - throttled response queue")
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
    self.message = mode == 0 and "Radar - compact native map" or "Radar - larger live scan"
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
    self.message = "Cockpit - live stock numbers in new instrument slots"
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
    self.message = "Cockpit - native hull and ammo bars respond to live values"
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
    self.message = "Options - press Esc and open the real settings pages"
    self:Record("options", "PENDING", "native options exercise is interactive; saved preferences are not overwritten")
end

function SXExhibits:Begin(scene)
    self.message, self.telemetry, self.aiSide = "Baseline first; watch the live change", "", false
    if scene.target and Scenes.Fixtures[scene.target] then self:Fixture(scene.target) end
    if scene.id == "ai" then self:SetupAI()
    elseif scene.id == "chunks" then self:Fixture("break_craft"); self:Fixture("break_building")
        self:Record("chunks", "PENDING", "requires enabled OpenShim chunks and compatible assets; inspect both deaths")
    elseif scene.id == "filters" then self:SetupFilters()
    elseif scene.id == "control" then self:SetupControl() end
end

function SXExhibits:Cue(scene, cue)
    local id = cue.id
    if id == "music-start" or id == "music-restart" then self:MusicStart()
    elseif id:match("^music%-") then self:MusicAction(id)
    elseif id == "weather-start" then self:WeatherStart()
    elseif id == "weather-warm" and self.weather then
        self.weather.SetPreset("SXLivewireWarm", 6); self.message = "Atmosphere - warm light and haze"
    elseif id == "weather-storm" and self.weather then
        self.weather.SetPreset("MarsDustStorm", 8)
        self.weather.SetIntensity(0.75); self.weather.SetWindOverride({ x = 0.85, y = -0.05, z = 0.30 }, 8)
        self.message = "Atmosphere - camera-following dust front"
    elseif id == "weather-clear" and self.weather then
        self.weather.SetPreset(nil, 8); self.message = "Atmosphere - clearing to the captured baseline"
    elseif id:match("^ai%-") then self:AIAction(id)
    elseif id == "break-craft" or id == "break-building" then
        local key = id == "break-craft" and "break_craft" or "break_building"
        local h = self:Handle(key)
        if self.api.alive(h) then
            Damage(h, GetCurHealth(h) + GetMaxHealth(h) + 1000)
            self:Record("chunks/" .. key, "PENDING", "native damage/death issued; no chunk-count query")
        else self:Record("chunks/" .. key, "BLOCKED", "destruction fixture unavailable") end
        self.message = id == "break-craft" and "Destruction - watch real vehicle fragments" or "Destruction - watch real building fragments"
    elseif id:match("^shield%-") or id:match("^magnet%-") or id:match("^prox%-") then self:FilterAction(id)
    elseif id:match("^radio%-") then self:RadioPolicy(id)
    elseif id == "command-film" then
        local ok, accepted = self:Call("TriggerStockCmdReplacement", self:Handle("radio"), "Hunt")
        if not ok or accepted ~= true then self:Record("command", "BLOCKED", "film dispatch refused") end
        self.message = "Command hook - Hunt slot runs the trial route"
    elseif id == "cockpit-start" then self:CockpitStart()
    elseif id == "radar-map" then self:Radar(0)
    elseif id == "radar-scan" then self:Radar(1)
    elseif id == "hud-move" then self:MoveHUD()
    elseif id == "hud-values" then self:HUDValues()
    elseif id == "cockpit-baseline" then
        self:Record("restore/cockpit", self:CockpitEnd() and "PASS" or "FAIL", "live meters, radar and text baselines")
        self.message = "Cockpit - original layout and values restored"
    elseif id == "autosave-preview" then
        self.api.overlay:Notify("Autosaving...", 4, self.api.clock(), true)
        self.message = "Autosave overlay demonstration - notification preview"
        self:Record("autosave", self.api.overlay.ready and "PENDING" or "BLOCKED",
            "notification preview; sx save requests a real dedicated checkpoint")
    elseif id == "options" then self:Options()
    elseif id == "freeplay" then self.message = "Your proving ground - replay any bay with sx <chapter>" end
end

function SXExhibits:Update(dt, scene)
    if self.weather then
        local ok, err = pcall(self.weather.Update, dt)
        if not ok then self:Record("environment", "FAIL", err); self:WeatherEnd() end
    end
    if self.musicBase then self:Call("UpdateMusic", dt) end
    if self.commandRegistered then self:Call("UpdateCommandReplacements") end
    if not scene then self.telemetry = self:PlayerTelemetry(); return end
    if scene.id == "environment" and self.weather then
        local fog = self:Read("GetFog")
        local systems = 0
        for _ in pairs(self.weather.LiveSystems or {}) do systems = systems + 1 end
        self.telemetry = string.format("Weather %s | particle systems %d | fog end %.0fm | wind %.1f",
            self.weather.GetPreset(), systems, type(fog) == "table" and (fog.ending or fog.fogEnd or 0) or 0,
            self.weather.GetWindSpeed())
    elseif scene.id == "ai" then
        local function Range(a, b)
            return self.api.alive(self:Handle(a)) and self.api.alive(self:Handle(b)) and GetDistance(self:Handle(a), self:Handle(b)) or 0
        end
        self.telemetry = string.format("Actual target ranges: stock %.1fm | tuned %.1fm", Range("ai_stock", "ai_target_a"), Range("ai_tuned", "ai_target_b"))
    elseif scene.id == "filters" then
        local a, b = self:Handle("magnet_ally"), self:Handle("magnet_enemy")
        self.telemetry = string.format("Magnet distances: ally %.1fm | enemy %.1fm", self.api.alive(a) and GetDistance(a, "sx_magnet") or 0,
            self.api.alive(b) and GetDistance(b, "sx_magnet") or 0)
    elseif scene.id == "control" then
        local music = self:Read("GetMusicState")
        self.telemetry = string.format("Command callbacks %d | radio muted %s | native music %s", self.commandHits,
            tostring(self:Read("GetUnitVoMuted")), type(music) == "table" and (tostring(music.track) .. (music.paused and " paused" or (music.playing and " playing" or " stopped"))) or "unavailable")
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
    -- Cleanup failures remain visible and can be retried; other bays still run.
    return true
end

function SXExhibits:Restore()
    local all = self:WeatherEnd()
    local cockpit = self:CockpitEnd()
    local command = self:RemoveCommand()
    local selection = self:RestoreSelection()
    local state = self.state:Restore()
    local music = self:RestoreMusic()
    if self.api.valid(self:Handle("ai_tuned")) then self:Call("ClearAiUnitTuning", self:Handle("ai_tuned")) end
    for _, group in ipairs({ "ai", "chunks", "filters" }) do
        local removed = self.api.removeGroup(group)
        all = removed and all
    end
    return all and cockpit and command and selection and state and music
end

function SXExhibits:Snapshot()
    return { state = self.state:Snapshot(), musicBase = State.Copy(self.musicBase), selection = self.selection,
        player = self.player, hudMoved = self.hudMoved, hudWidth = self.hudWidth, hudHeight = self.hudHeight,
        commandRegistered = self.commandRegistered }
end
function SXExhibits:Load(snapshot)
    if not snapshot then return end
    self.state:Load(snapshot.state)
    self.musicBase, self.selection, self.player = snapshot.musicBase, snapshot.selection, snapshot.player
    self.hudMoved, self.hudWidth, self.hudHeight = snapshot.hudMoved, snapshot.hudWidth, snapshot.hudHeight
    self.commandRegistered = snapshot.commandRegistered
end

return SXExhibits
