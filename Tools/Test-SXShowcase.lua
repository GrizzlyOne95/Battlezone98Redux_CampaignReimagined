-- Run with Lua 5.1+: lua Tools/Test-SXShowcase.lua Scripts
-- Pure host fakes exercise lifecycle/rollback; no native visual claim is made.
local scriptRoot = arg[1] or "Scripts"
package.path = scriptRoot .. "/?.lua;" .. package.path
local unpackValues = unpack or table.unpack
local Director = require("SXDirector")
local Materials = require("SXMaterials")
local Overlay = require("SXOverlay")
local total = 0
local function Check(value, message)
    assert(value, message)
    total = total + 1
end
local function Copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = Copy(v) end
    return r
end

-- Cues cross thresholds once, including a hitch across both scenes.
local events, finishes, ticks = {}, {}, 0
local d = Director.New({
    { id = "a", duration = 3, cues = { { at = 0, id = "zero" }, { at = 2, id = "two" } } },
    { id = "b", duration = 4, cues = { { at = 1, id = "b-one" } } },
}, { cue = function(_, c) events[#events + 1] = c.id end,
    tick = function() ticks = ticks + 1 end,
    finish = function(reason) finishes[#finishes + 1] = reason end })
Check(d:Start(), "director start")
d:Update(0); d:Update(-1); d:Update(0/0); d:Update(math.huge)
Check(#events == 0, "invalid/paused steps do not fire cues")
d:Update(7)
Check(table.concat(events, ",") == "zero,two,b-one", "hitch processes all crossed cues once")
Check(d.mode == "freeplay" and finishes[1] == "complete", "bounded handover")
d:Update(7)
Check(#events == 3 and ticks == 2, "completed director stays inactive")
Check(d:Start("b"), "selected scene replay")
Check(not d:Start("missing") and d.mode == "tour", "invalid request preserves active tour")
d:Finish("cancelled"); d:Update(99)
Check(#events == 3 and #finishes == 2, "cancel does not execute remaining cues")
d:Start("a"); d:Update(7)
Check(#events == 5 and d.mode == "freeplay", "selected chapter ends before later chapters/cues")
local entered, cleanupReason = 0, nil
local cleanup = Director.New({
    { id = "first", duration = 1, cues = {} },
    { id = "second", duration = 1, cues = {} },
}, { enter = function() entered = entered + 1 end,
    leave = function() return false end,
    finish = function(reason) cleanupReason = reason end })
cleanup:Start(); cleanup:Update(2)
Check(entered == 1 and cleanup.mode == "freeplay" and cleanupReason == "cleanup-error",
    "failed chapter cleanup stops before the next chapter")
cleanup:Start("second"); cleanup:Update(1)
Check(cleanupReason == "cleanup-error", "final chapter cleanup cannot report successful completion")

local broken = Director.New({ { id = "bad", duration = 2, cues = { { at = 1 } } } },
    { cue = function() error("fixture failure") end })
broken:Start(); broken:Update(1)
Check(broken.mode == "freeplay" and broken.error:match("fixture failure"), "callback error ends safely")

local function FakeExu(world)
    local x = { graphReady = true, showing = false, uiOpen = false,
        width = 1280, height = 720, nodes = {}, glow = {}, missingTint = nil }
    function x.GetSubEntityCount(h) return x.graphReady and world[h] and #world[h].names or nil end
    function x.GetSubEntityMaterial(h, i) return x.graphReady and world[h] and world[h].names[i + 1] or nil end
    -- Authored tint materials (sxtint.material); a missing one models an absent script.
    function x.MaterialExists(name) return name:match("^SX_tint_") ~= nil and name ~= x.missingTint end
    function x.SetMaterialPassColors(name, colors, technique)
        if x.rejectColors then return false end
        if x.legacyColors and technique == -1 then error("old API") end
        x.lastColors = Copy(colors)
        x.glow[name] = colors.emissive and colors.emissive.r
        return true
    end
    function x.SetSubEntityMaterial(h, i, name)
        if x.rejectService and name:match("^SX_tint_") then return false end
        world[h].names[i + 1] = name -- Deliberately returns nil, as a void setter can.
    end
    function x.CreateOverlay() x.created = true; return true end
    function x.DestroyOverlay() x.created = false end
    function x.CreateOverlayElement(_, name) x.nodes[name] = true; return true end
    function x.DestroyOverlayElement(name) x.nodes[name] = nil end
    function x.ShowOverlay() x.showing = true end
    function x.HideOverlay() x.showing = false end
    function x.SetOverlayTextFont() return not x.rejectFont end
    function x.GetGameResolution() return x.width, x.height end
    function x.IsGameUiOpen() return x.uiOpen end
    function x.IsPauseMenuOpen() return x.uiOpen end
    for _, name in ipairs({ "AddOverlay2D", "AddOverlayElementChild", "SetOverlayZOrder",
        "SetOverlayMetricsMode", "SetOverlayPosition", "SetOverlayDimensions", "SetOverlayCaption",
        "SetOverlayTextCharHeight", "SetOverlayTextColor", "ShowOverlayElement",
        "RemoveOverlay2D", "RemoveOverlayElementChild" }) do x[name] = function() end end
    return x
end

local world = { [1] = { names = { "avfigh00", "avfigh01" } }, [2] = { names = { "avfigh00", "avfigh01" } } }
local x = FakeExu(world)
local valid = function(h) return world[h] ~= nil end
local m = Materials.New(x, valid)
Check(m:Prepare(1, 2), "material baseline")
Check(m:Flash("red") and m.status == "PASS", "void assignment setters verified by readback")
Check(world[2].names[1] == "SX_tint_red" and world[2].names[2] == "avfigh01", "only the hull subentity is repainted")
Check(world[1].names[1] == "avfigh00", "control twin is untouched")
Check(m:Flash("cyan") and world[2].names[1] == "SX_tint_cyan", "livery cuts between authored tints")
Check(m:SetGlow(true), "glow enabled on the live livery")
m:Pulse(0.33)
Check(x.glow.SX_tint_cyan and x.glow.SX_tint_cyan > 1, "pulse drives emissive intensity above 1x")
Check(m:Flash("gold") and x.glow.SX_tint_cyan == 1, "leaving a livery resets its glow")
Check(m:Restore() and world[2].names[1] == "avfigh00" and x.glow.SX_tint_gold == 1, "baseline restore")
for _ = 1, 3 do m:Prepare(1, 2); m:Flash("blue"); m:Restore() end
Check(world[2].names[1] == "avfigh00" and not m.active, "replays return to the baseline")
x.rejectService = true
Check(not m:Flash("red") and world[2].names[1] == "avfigh00" and world[2].names[2] == "avfigh01",
    "assignment failure rolls back")
x.rejectService, x.legacyColors = false, true
Check(m:Flash("green") and m:SetGlow(true), "legacy pass-index fallback")
x.rejectColors = true; m:Pulse(1)
Check(not m.active and m.status == "FAIL" and world[2].names[1] == "avfigh00", "pulse failure restores originals")
x.rejectColors, x.legacyColors = false, false
m:Apply()
Check(world[2].names[1] == "SX_tint_cyan", "operator service variant is the cyan livery")
local savedA, savedB = Copy(m.controlBase), Copy(m.changedBase)
local loaded = Materials.New(x, valid)
loaded.controlBase, loaded.changedBase = savedA, savedB
x.graphReady = false
Check(not loaded:Prepare(1, 2), "load can precede render graph")
x.graphReady = true
Check(loaded:Prepare(1, 2) and loaded:Restore() and world[2].names[1] == "avfigh00",
    "deferred load retains saved original materials")
x.missingTint = "SX_tint_magenta"
local missing = Materials.New(x, valid)
Check(not missing:Prepare(1, 2) and missing.status == "BLOCKED", "missing tint script blocks honestly")
x.missingTint = nil
local other = { [1] = { names = { "body" } }, [2] = { names = { "body" } } }
local foreign = Materials.New(FakeExu(other), function(h) return other[h] ~= nil end)
Check(not foreign:Prepare(1, 2) and foreign.status == "BLOCKED", "non-scout fixture blocks instead of guessing")
world[2] = nil
Check(loaded:Restore(), "deleted fixture does not prevent restoring survivor/reset")
Check(not Materials.New({ isStub = true }, valid):Available(), "stub EXU never counts as supported")
Check(not Materials.New({}, valid):Available(), "missing material APIs blocked")

local o = Overlay.New(x)
Check(o:Create() and x.showing, "overlay created")
x.width, x.height = 1920, 1080
o:Update("title", "status", "help")
Check(o.width == 1920 and o.height == 1080, "resolution change relayout")
-- A caption longer than one row must stay in the safe frame without losing words.
local captions, positions, dimensions = {}, {}, {}
function x.SetOverlayCaption(name, value) captions[name] = value end
function x.SetOverlayPosition(name, left, top) positions[name] = { left, top } end
function x.SetOverlayDimensions(name, width, height) dimensions[name] = { width, height } end
local longCaption = "OpenShim + EXU: a living proving ground inside Battlezone 98 Redux"
for _, resolution in ipairs({ {560, 315}, {1280, 720}, {1920, 1080}, {3840, 2160} }) do
    x.width, x.height = resolution[1], resolution[2]
    o:Update("OPERATION LIVEWIRE", longCaption, "Replay a chapter", 0, "Telemetry")
    local wrapped = captions["SX/Livewire/Status"]
    local fits = true
    for line in wrapped:gmatch("[^\n]+") do fits = fits and #line * o.charHeight * 1.12 <= o.textWidth end
    Check(fits and wrapped:gsub("\n", " ") == longCaption, "caption fits and keeps words at " .. x.width)
    Check(positions["SX/Livewire/Telemetry"][2] >= positions["SX/Livewire/Status"][2]
        + dimensions["SX/Livewire/Status"][2], "wrapped caption cannot overlap next row")
end

x.width, x.height = 1920, 1080
x.uiOpen = true; o:Update("title", "status", "help")
Check(not x.showing, "native menu suppresses custom overlay")
x.uiOpen = false; o:Update("title", "status", "help")
Check(x.showing, "overlay resumes after native menu")
o:Destroy()
Check(not x.created and next(x.nodes) == nil, "overlay cleanup")
Check(o:Create() and o.width == 1920 and o.height == 1080, "recreated overlay receives layout")
o:Destroy()
x.rejectFont = true
Check(not o:Create() and not x.created and next(x.nodes) == nil, "partial overlay failure cleaned up")


-- Serialized override state: false/multiple results, partial writes, external settings and dead handles.
local State = require("SXState")
local props = { flag = false, value = 4, pair = { 10, 20 } }
local owner = {}
function owner.GetFlag() return props.flag end
function owner.SetFlag(v) props.flag = v end
function owner.GetValue() return props.value end
function owner.SetValue(v) props.value = v; return not props.refuse end
function owner.GetPair() return props.pair[1], props.pair[2] end
function owner.SetPair(a, b) props.pair = { a, b } end
local state = State.New(owner)
Check(state:Write("flag", "demo", "GetFlag", "SetFlag", { true }) and state:Restore("demo") and not props.flag,
    "false-valued native baseline survives serialization/restore")
Check(state:Write("pair", "demo", "GetPair", "SetPair", { 30, 40 }) and state:Restore() and props.pair[2] == 20,
    "multi-return native anchors restore exactly")
state:Write("value", "demo", "GetValue", "SetValue", { 8 }, { preserveExternal = true })
props.value = 11
Check(state:Restore() and props.value == 11, "a real user options change takes precedence over our override")
props.refuse = true
Check(not state:Write("value", "demo", "GetValue", "SetValue", { 18 }) and not state:Restore(),
    "partial/refused native writes retain cleanup state")
props.refuse = false
Check(state:Restore() and props.value == 11, "failed restoration can be retried")
function SXTestGet(h) return h + 10 end
function SXTestSet() error("must not touch expired game handles") end
state = State.New(owner, function() return false end)
state:Capture("expired", "demo", "SXTestGet", "SXTestSet", { scope = "stock", args = { 42 }, handle = true })
Check(state:Restore() and next(state.entries) == nil, "expired native handles are discarded without a setter call")

-- Integration fakes validate mission requests/lifecycle, not native graphics, audio, AI or physics.
local Scenes = require("SXScenes")
local assetRoot = arg[2] or (scriptRoot .. "/..")
local file = assert(io.open(assetRoot .. "/Missions/sxshow.bzn", "r"))
local map = file:read("*a"); file:close()
local paths = {}
for block in map:gmatch("%[AiPath%](.-)pathType = %x+") do
    local label = block:match("label = ([^\n]+)")
    if label then
        paths[label] = {}
        for px, pz in block:gmatch("  x %[%d+%] =\n([^\n]+)\n  z %[%d+%] =\n([^\n]+)") do
            paths[label][#paths[label] + 1] = { x = tonumber(px), y = 99.9, z = tonumber(pz) }
        end
    end
end
local duration = 0
for _, scene in ipairs(Scenes.List) do duration = duration + scene.duration end
Check(duration == 453 and #Scenes.List == 11, "full authored tour is eleven chapters / 453 simulation seconds")

world = {}
x = FakeExu(world)
x.props = { camera = 2, radar = 1, radarScale = 1, voMuted = false, voThrottle = 300,
    voDepth = 4, voStale = 2500, scrapColor = 0xffffffff, pilotColor = 0xffffffff,
    scrapPos = { 90, 620 }, pilotPos = { 90, 646 }, uiScale = 1, musicVolume = 6,
    fog = { r = 0.1, g = 0.2, b = 0.3, start = 175, ending = 250 },
    ambient = { r = 0.2, g = 0.2, b = 0.2, a = 1 }, diffuse = { r = 0.5, g = 0.5, b = 0.5 }, power = 1,
    specular = { r = 0.3, g = 0.3, b = 0.3 }, sunDir = { x = 0.2, y = -0.9, z = 0.4 } }
x.music = { track = 3, playing = true, paused = false, gain = 1, fading = false, userVolume = 6 }
x.callbacks, x.scrolls, x.tuning, x.captions = {}, {}, {}, {}
x.saveCount, x.uiOpen = 0, false
local selected = { 99998 }
local function NativePair(getter, setter, key)
    x[getter] = function() return Copy(x.props[key]) end
    x[setter] = function(v) x.props[key] = Copy(v); return not x.refuseRestore end
end
for _, row in ipairs({ { "GetCameraView", "SetCameraView", "camera" }, { "GetRadarState", "SetRadarState", "radar" },
    { "GetRadarSizeScale", "SetRadarSizeScale", "radarScale" }, { "GetUnitVoMuted", "SetUnitVoMuted", "voMuted" },
    { "GetUnitVoThrottle", "SetUnitVoThrottle", "voThrottle" }, { "GetUnitVoQueueDepthLimit", "SetUnitVoQueueDepthLimit", "voDepth" },
    { "GetUnitVoQueueStaleMs", "SetUnitVoQueueStaleMs", "voStale" }, { "GetScrapHudColor", "SetScrapHudColor", "scrapColor" },
    { "GetPilotHudColor", "SetPilotHudColor", "pilotColor" }, { "GetFog", "SetFog", "fog" },
    { "GetAmbientLight", "SetAmbientLight", "ambient" }, { "GetSunDiffuse", "SetSunDiffuse", "diffuse" },
    { "GetSunPowerScale", "SetSunPowerScale", "power" }, { "GetSunSpecular", "SetSunSpecular", "specular" } }) do
    NativePair(row[1], row[2], row[3])
end
function x.GetSunDirection() return Copy(x.props.sunDir) end
function x.SetSunDirection(a, b, c) x.props.sunDir = { x = a, y = b, z = c } end
function x.GetScrapHudTopLeft() return x.props.scrapPos[1], x.props.scrapPos[2] end
function x.SetScrapHudTopLeft(a, b) x.props.scrapPos = { a, b } end
function x.GetPilotHudTopLeft() return x.props.pilotPos[1], x.props.pilotPos[2] end
function x.SetPilotHudTopLeft(a, b) x.props.pilotPos = { a, b } end
function x.GetUIScaling() return x.props.uiScale end
function x.GetMusicVolume() return x.props.musicVolume end
function x.SetOverlayCaption(name, caption) x.captions[name] = caption end
function x.GetRadarRange(h) return world[h].radarRange end
function x.SetRadarRange(h, v) world[h].radarRange = v end
function x.GetRadarPeriod(h) return world[h].radarPeriod end
function x.SetRadarPeriod(h, v) world[h].radarPeriod = v end
function x.GetMusicState() return Copy(x.music) end
function x.SetMusicTrack(track)
    x.music.track, x.music.playing, x.music.paused, x.music.fading = track, true, false, false; return true
end
function x.StopMusic() x.music.playing, x.music.paused, x.music.fading = false, false, false; return true end
function x.PauseMusic() x.music.paused, x.music.playing = true, false; return true end
function x.ResumeMusic() x.music.paused, x.music.playing = false, true; return true end
function x.ChangeMusicTrack(track, outTime, inTime)
    x.music.fading, x.music.nextTrack, x.music.left = true, track, outTime + inTime; return true
end
function x.UpdateMusic(dt)
    if x.music.fading and not x.music.paused then
        x.music.left = x.music.left - dt
        if x.music.left <= 0 then x.SetMusicTrack(x.music.nextTrack) end
    end
    return true
end
function x.ResetMusic() x.music.gain, x.music.fading, x.music.nextTrack, x.music.left = 1, false, nil, nil; return true end
function x.SetAiUnitTuning(h, tuning)
    if (x.aiTier == 1 and tuning.kiteDesiredRange) or (x.aiTier == 2 and tuning.kiteStrafe) then return false end
    x.tuning[h] = Copy(tuning); return true
end
function x.GetAiUnitTuning(h) return x.tuning[h] end
function x.ClearAiUnitTuning(h) x.tuning[h] = nil; return true end
function x.ReplaceStockCmd(h, _, label, callback) x.callbacks[h] = { callback = callback, label = label }; return true end
function x.HasStockCmdReplacement(h) return x.callbacks[h] ~= nil end
function x.RemoveStockCmdReplacement(h) local existed = x.callbacks[h] ~= nil; x.callbacks[h] = nil; return existed end
function x.TriggerStockCmdReplacement(h) return x.callbacks[h] and x.callbacks[h].callback(h, "Hunt", "Run trial", "manual") or false end
function x.UpdateCommandReplacements() end
function x.SelectOne(h) selected = { h } end
function x.SelectNone() selected = {} end
function x.SelectAdd(h) selected[#selected + 1] = h end
function x.GetRenderEffectStatus() return false, false, false, "not-implemented" end
x.renderRequests = {}
function x.SupportsRenderProfile(profile) return profile ~= x.unsupportedProfile end
function x.RequestRenderProfile(profile) x.renderRequests[#x.renderRequests + 1] = profile; x.renderProfile = profile; return true end
function x.GetEffectiveRenderProfile() return (x.renderProfile == nil or x.renderProfile == "inherit") and "enhanced" or x.renderProfile end
function x.SaveGame(path)
    x.saveCount = x.saveCount + 1; x.lastSave = Copy({ Save() }); return true, path
end

-- CRStormFX stand-in: a fog/light writer like the real module, recording what the
-- weather bay asks of it.
local wx = { strikes = 0, precip = {}, weather = nil, tint = nil, live = false }
function wx.BaseEnvironment() return wx.live and { fog = Copy(x.props.fog), amb = Copy(x.props.ambient) } or nil end
function wx.StartDynamicWeather() wx.weather, wx.live = "drizzle", true; return {} end
function wx.SetWeather(name) wx.weather = name; x.props.fog = { r = 0.3, g = 0.3, b = 0.35, start = 60, ending = 160 }; return true end
function wx.GetWeather() return wx.weather end
function wx.GetRainIntensity() return wx.weather and 0.6 or 0 end
function wx.StrikeNow() wx.strikes = wx.strikes + 1 end
function wx.Precip(kind, level) wx.precip[kind] = math.max(wx.precip[kind] or 0, level); wx.live = true; return true end
function wx.Wind(_, _, speed) wx.wind = speed end
function wx.Atmosphere(fogScale) x.props.fog = { r = 0.5, g = 0.4, b = 0.3, start = 40, ending = 250 * fogScale } end
function wx.SetTint(fog) wx.tint = fog end
function wx.Update() end
function wx.Shutdown() wx.weather, wx.tint, wx.live = nil, nil, false end
package.loaded.exu, package.loaded.CRStormFX, package.loaded.CRParticleTemplates = nil, nil, nil
package.preload.exu = function() return x end
package.preload.CRStormFX = function() return wx end
package.preload.CRParticleTemplates = function() return { Ensure = function() return true end } end
x.sky = { enabled = false, material = nil }
function x.GetSkyDomeEnabled() return x.sky.enabled end
function x.SetSkyDome(material) x.sky.enabled, x.sky.material = true, material; return true end
function x.SetSkyDomeEnabled(on) x.sky.enabled = on end
package.preload.RequireFix = function() return { Initialize = function() end } end

local nextHandle, cameraCalls, readyCalls, finishCalls = 0, 0, 0, 0
-- Engine camera stack: a push while up or a pop while empty is the native
-- "Fsm error: Camera Stack 0verfow" alert seen in game.
local cameraDepth, cameraFaults = 0, {}
local cancelled, net = false, false
local classes = { sxanchor = "camerapod", sxshield = "shieldtower", sxmag = "magnet", sxproxe = "proximity", sxproxa = "proximity",
    avtank = "wingman", avfigh = "wingman", abspow = "powerplant", abbarr = "barracks",
    abcomm = "commtower", sbcomm = "commtower", cbcomm = "commtower", abtowe = "turret", sbtowe = "turret",
    cbtowe = "turret", abhqcp = "commbunker", svturr = "turrettank", aspilo = "person", bspilo = "person", cspilo = "person",
    sspilo = "person", assold = "person", sssold = "person", cssold = "person" }
local function Unit(odf, team, point)
    return { odf = odf, team = team, names = odf == "avfigh" and { "avfigh00", "avfigh01" } or { "body", "glass" }, health = 3000, maxHealth = 3000,
        ammo = 1200, radarRange = 400, radarPeriod = 5, pos = Copy(point), class = classes[odf] or "wingman" }
end
world[99999] = Unit("avtank", 1, paths.sx_control[1]); world[99999].label = "player"
world[99998] = Unit("avtank", 1, paths.sx_control[1]); world[99998].label = "original_selection"
function IsValid(h) return world[h] ~= nil end
function IsAlive(h) return world[h] ~= nil and world[h].health > 0 end
function IsNetGame() return net end
function BuildObject(odf, team, path)
    assert(paths[path], "unbound BuildObject path " .. tostring(path))
    nextHandle = nextHandle + 1; world[nextHandle] = Unit(odf, team, paths[path][1]); return nextHandle
end
function SetLabel(h, label) world[h].label = label end
function GetHandle(label) for h, obj in pairs(world) do if obj.label == label then return h end end end
function GetPlayerHandle() return 99999 end
function GetClassLabel(h) return world[h].class end
local unsafeIndependenceCalls, heldCraft = 0, {}
function SetIndependence(h, value)
    if world[h].class ~= "wingman" then
        unsafeIndependenceCalls = unsafeIndependenceCalls + 1
        error("SetIndependence requires a UnitProcess, not " .. world[h].odf)
    end
    if world[h].label and world[h].label:match("^sx_brk_") then heldCraft[world[h].label] = value end
end
function SetWeaponMask() end
function SetCurAmmo(h, v) world[h].ammo = v end
function GetCurAmmo(h) return world[h].ammo end
function SetCurHealth(h, v) world[h].health = v end
function GetCurHealth(h) return world[h].health end
function SetMaxHealth(h, v) world[h].maxHealth = v end
function GetMaxHealth(h) return world[h].maxHealth end
function SetObjectiveName() end
function SetObjectiveOn() end
function Stop() end
function RemoveObject(h)
    if h == x.rejectRemove then return false end
    world[h] = nil; DeleteObject(h)
end
function Damage(h, amount) world[h].health = world[h].health - amount; if world[h].health <= 0 then RemoveObject(h) end end
function GetDistance(h, target)
    local point = type(target) == "string" and paths[target][1] or world[target].pos
    local pos = world[h].pos; return math.sqrt((pos.x - point.x)^2 + (pos.z - point.z)^2)
end
function Attack(h, target) world[h].attack = target end
function Goto(h, route)
    assert(paths[route], "unbound Goto path " .. tostring(route))
    -- Supply expected observations to test the mission's witness gates. This is
    -- deliberately not a simulation or qualification of native mine physics.
    local hits = {}
    for mine, obj in pairs(world) do
        if obj.odf == "sxproxe" or obj.odf == "sxproxa" then
            local targets = obj.odf == "sxproxe" and world[h].team == 5 or obj.odf == "sxproxa" and world[h].team == 1
            if x.ignoreFilters then targets = world[h].team == 5 end
            for _, point in ipairs(paths[route]) do
                local dx, dz = point.x - obj.pos.x, point.z - obj.pos.z
                if targets and dx*dx + dz*dz < 30*30 then hits[mine] = true end
            end
        end
    end
    world[h].pos = Copy(paths[route][#paths[route]])
    for mine in pairs(hits) do world[h].health = world[h].health - 1000; RemoveObject(mine) end
end
function SelectedObjects()
    local i = 0; return function() i = i + 1; return selected[i] end
end
function ClearObjectives() end
function AddObjective() end
function DisplayMessage() end
function CameraReady()
    readyCalls = readyCalls + 1
    if cameraDepth > 0 then cameraFaults[#cameraFaults + 1] = "ready while a camera is up" end
    cameraDepth = cameraDepth + 1
end
function CameraPath(path, _, _, target) assert(paths[path] and IsValid(target)); cameraCalls = cameraCalls + 1 end
function CameraObject(base, _, _, _, target) assert(IsValid(base) and IsValid(target)); cameraCalls = cameraCalls + 1 end
function CameraFinish()
    finishCalls = finishCalls + 1
    if cameraDepth == 0 then cameraFaults[#cameraFaults + 1] = "finish with no camera up"
    else cameraDepth = cameraDepth - 1 end
end
function CameraCancelled() return cancelled end
local function Mission() package.loaded.exu = nil; cameraDepth = 0; dofile(scriptRoot .. "/sxshow.lua"); Start() end
local function Snapshot() return Copy({ Save() })[2] end
local function OwnedCount()
    local n = 0; for _, obj in pairs(world) do if obj.label and obj.label:match("^sx_") then n = n + 1 end end; return n
end
local baseline = Copy(x.props)
local musicBaseline = Copy(x.music)
Mission(); Update(0)
Check(OwnedCount() == 10 and readyCalls == 1, "first frame builds ten permanent stations/scouts, no range actors")
x.uiOpen = true; Update(100)
Check(Snapshot().scene.elapsed == 0 and not x.showing, "native menus hide the overlay and freeze nonzero timesteps")
x.props.uiScale = 2; x.uiOpen = false; Update(0)
Check(Snapshot().results["options/readback"].status == "PASS", "real options readback changes are recorded")
x.props.uiScale = 1
Update(25); Update(6)
local changedHandle = GetHandle("sx_changed")
Check(world[changedHandle].names[1] == "SX_tint_red" and world[GetHandle("sx_control")].names[1] == "avfigh00",
    "film livery cue changes only the twin")
Command("sx", "visual pass")
local saved = Copy({ Save() })
local beforeReady = readyCalls
x.graphReady = false; Load(unpackValues(saved)); x.graphReady = true; Update(0.25)
Check(readyCalls == beforeReady and Snapshot().scene.mode == "freeplay", "load never resumes a camera cue")
Check(world[changedHandle].names[1] == "avfigh00" and Snapshot().results.load.status == "PASS", "deferred load restores saved materials")
Check(next(Snapshot().observations) == nil, "loaded observations require confirmation again")
Check(Command("unrelated", "") == false, "unrelated console commands remain unhandled")
Command("sx", "service"); x.rejectColors = true; Update(0.25); x.rejectColors = false
Check(Snapshot().results.materials.status == "FAIL" and world[changedHandle].names[1] == "avfigh00", "pulse failure reports rollback")
Command("sx", "tour")
for _ = 1, 940 do Update(0.5) end
local finished = Snapshot()
Check(finished.scene.mode == "freeplay" and finished.results.tour.status == "PASS", "full eleven-chapter tour completes")
for _, feature in ipairs(Scenes.Features) do Check(finished.results[feature] ~= nil, "full tour exercises " .. feature) end
local killed = 0
for _, key in ipairs(Scenes.Breaks) do
    if finished.results["chunks/" .. key] and finished.results["chunks/" .. key].status == "PENDING" then killed = killed + 1 end
end
Check(killed == 19 and #Scenes.Breaks == 19, "destruction yard issues all nineteen kills")
for _, cue in ipairs(Scenes.Find("chunks").cues) do
    local shot
    for _, s in ipairs(Scenes.Find("chunks").shots) do if s.at <= cue.at then shot = s end end
    Check(Scenes.Fixtures[cue.key].path:match("^sx_brk_") and shot and cue.at - shot.at >= 1.5,
        "kill " .. cue.key .. " lands after its cluster's cut")
end
local people = 0
for _, key in ipairs({ "gib_aspilo", "gib_bspilo", "gib_cspilo", "gib_sspilo", "gib_assold", "gib_sssold", "gib_cssold" }) do
    if finished.results["gibs/" .. key] and finished.results["gibs/" .. key].status == "PENDING" then people = people + 1 end
end
Check(people == 7, "pilot chapter kills all seven people, runners included")
Check(finished.results["lighting/retro"].status == "PASS" and finished.results["lighting/enhanced"].status == "PASS"
    and x.renderProfile == "inherit", "lighting cycles render profiles and hands the user's own profile back")
Check(unsafeIndependenceCalls == 0, "tour never writes UnitProcess independence on camera markers or buildings, even through pcall")
local heldCount = 0
for _, independence in pairs(heldCraft) do if independence == 0 then heldCount = heldCount + 1 end end
Check(heldCount == 11, "all eleven destruction craft hold position without commanding buildings or people")
Check(State.Equal(x.props, baseline) and State.Equal(x.music, musicBaseline), "full tour restores captured global settings and music policy")
Check(world[99999].health == 3000 and world[99999].ammo == 1200 and world[99999].radarRange == 400,
    "live player meters and radar ranges restore")
Check(OwnedCount() == 10 and next(x.tuning) == nil and next(x.callbacks) == nil and wx.weather == nil and not x.sky.enabled,
    "full tour removes range actors, tuning, callbacks, weather and the storm sky")
Check(wx.strikes == 4 and wx.precip.snow == 1 and wx.precip.dust == 1 and x.sky.material == "CR_Sky/MarsStorm",
    "weather bay strikes four times, runs snow and dust at full strength under the storm sky")
Check(#selected == 1 and selected[1] == 99998, "original selected unit is restored")

-- Presentation: shot lists cut cleanly, captions replace telemetry unless `sx debug`.
Command("sx", "ai"); Update(0.5)
local readyBeforeCut = readyCalls
Update(21)
Check(readyCalls == readyBeforeCut + 1 and Snapshot().scene.scene == "ai", "AI shot list cuts to its second camera at 21 s")
Update(0.5)
Check(x.captions["SX/Livewire/Status"]:gsub("\n", " ") == Scenes.Find("ai").cues[2].caption
    and x.captions["SX/Livewire/Telemetry"]:match("^Range: stock"), "AI film shows the caption plus the live range readout")
Command("sx", "debug"); Update(0.5)
Check(x.captions["SX/Livewire/Telemetry"] ~= "", "sx debug restores raw telemetry")
Command("sx", "debug"); Command("sx", "skip"); Update(0.5)
Command("sx", "chunks"); Update(0.5)
local anchored = true
for _, shot in ipairs(Scenes.Find("chunks").shots) do anchored = anchored and GetHandle("sx_" .. shot.target) ~= nil end
Check(anchored, "every destruction shot has its own anchor before the first cut")
Command("sx", "skip"); Update(0.5)
Command("sx", "filters"); Update(5)
Check(x.captions["SX/Livewire/Telemetry"] == "", "other chapters show the trailer caption, not raw telemetry")
Command("sx", "skip"); Update(0.5)
Check(x.saveCount == 0 and finished.results.autosave.detail:match("preview"), "automatic film notification never writes a save")
Check(world[GetHandle("sx_changed")].names[1] == "avfigh00", "film livery is restored after the tour")
Check(finished.results["filters/proximity"].status == "PASS", "proximity witness requires protected crossing and actual target damage")
Command("sx", "filters"); x.ignoreFilters = true; Update(55); x.ignoreFilters = false
Check(Snapshot().results["filters/proximity"].status ~= "PASS", "stock/faulty filter behavior cannot produce a witness pass")
Command("sx", "autosave"); Update(0)
Check(x.captions["SX/Livewire/Notification"]:match("Autosaving") and x.saveCount == 0, "preview notification is visible without saving")
Update(5)
Check(x.captions["SX/Livewire/Notification"] == "", "notification expires on simulation time")
Command("sx", "save"); x.uiOpen = true; Update(10)
Check(x.saveCount == 0, "native saving waits until the real UI closes")
x.uiOpen = false; Update(0.25)
Check(x.saveCount == 1 and x.lastSave[1] == 2 and x.lastSave[2].scene.mode == "freeplay", "explicit checkpoint invokes the native serializer from safe gameplay")
Update(3)
Check(x.saveCount == 1, "queued native save is once-only")
Command("sx", "control"); Update(10)
local controlSave = Copy({ Save() })
x.callbacks = {} -- A fresh Lua/native state has no old callback closure.
Load(unpackValues(controlSave)); Update(0)
Check(Snapshot().results.load.status == "PASS" and next(x.callbacks) == nil, "load cleanup tolerates an already-cleared native command registry")
Command("sx", "cockpit"); Update(21)
x.props.radarScale = 1.4
Command("sx", "skip")
Check(x.props.radarScale == 1.4, "user radar option changes during a bay are preserved")
x.props.radarScale = 1
Command("sx", "ai"); x.aiTier = 1; Update(13)
Check(Snapshot().results["ai/api"].status == "PASS" and Snapshot().results["ai/api"].detail:match("V1"), "older AI bridge tiers fall back honestly")
x.aiTier = nil
cancelled = true; Update(1); cancelled = false
Check(OwnedCount() == 10 and next(x.tuning) == nil and Snapshot().scene.mode == "freeplay", "native cancel clears active AI overrides/actors")
Command("sx", "service"); saved = Copy({ Save() })
x.graphReady = false; Load(unpackValues(saved)); Update(5)
Check(Snapshot().results.load.status == "BLOCKED", "render readiness timeout is reported")
x.graphReady = true; Command("sx", "baseline")
RemoveObject(changedHandle)
Command("sx", "reset"); Update(0)
Check(OwnedCount() == 10 and IsValid(99999) and IsValid(99998), "reset recovers deleted fixtures and preserves original player/selection objects")
for _ = 1, 2 do Command("sx", "tour"); Update(400) end
Check(OwnedCount() == 10 and world[GetHandle("sx_changed")].names[1] == "avfigh00", "repeated whole-tour hitches keep objects bounded and the livery restored")
Command("sx", "cockpit"); Update(15); x.refuseRestore = true; Command("sx", "reset")
Check(Snapshot().results.reset.status == "FAIL" and OwnedCount() == 10, "failed native restoration refuses destructive reset")
x.refuseRestore = false; Command("sx", "reset"); Update(0)
Command("sx", "ai"); Update(13); x.rejectRemove = GetHandle("sx_ai_stock")
Command("sx", "reset")
Check(Snapshot().results.reset.status == "FAIL" and IsValid(x.rejectRemove), "refused actor cleanup blocks reset and retains the actor for retry")
x.rejectRemove = nil; Command("sx", "reset"); Update(0); Command("sx", "skip")
Command("sx", "lighting"); Update(12); Command("sx", "skip")
Check(x.renderProfile == "inherit" and State.Equal(x.props, baseline),
    "skipping mid-comparison returns the render profile and leaves lighting untouched")
x.unsupportedProfile = "retro"; Command("sx", "lighting"); Update(1); Command("sx", "skip"); x.unsupportedProfile = nil
Check(Snapshot().results["lighting/retro"].status == "BLOCKED", "an unsupported profile is reported, not requested")
Command("sx", "ai"); Update(13)
x.rejectRemove = GetHandle("sx_ai_stock")
Update(60)
Check(Snapshot().scene.mode == "freeplay" and Snapshot().results.tour.status == "FAIL"
    and IsValid(x.rejectRemove), "chapter cleanup failure aborts the tour and retains retry state")
Command("sx", "tour")
Check(Snapshot().results.tour.status == "BLOCKED", "replay remains blocked until cleanup succeeds")
x.rejectRemove = nil; Command("sx", "baseline")
Check(OwnedCount() == 10, "baseline command retries failed actor cleanup")
Mission(); Command("sx", "skip")
local startupReady = readyCalls
Update(1)
Check(Snapshot().scene.mode ~= "tour" and readyCalls == startupReady,
    "skip before the first update cancels pending automatic startup")
Command("sx", "tour"); Update(170)
Check(Snapshot().scene.scene == "ai", "AI chapter follows lighting and weather")
x.rejectRemove = GetHandle("sx_ai_stock")
Update(61)
Check(Snapshot().scene.mode == "freeplay" and Snapshot().scene.scene == "ai"
    and GetHandle("sx_brk_avtank") == nil, "full film stops at failed AI cleanup before spawning destruction actors")
x.rejectRemove = nil; Command("sx", "baseline")
local nativePath = CameraPath
CameraPath = function() error("camera failure") end
Command("sx", "arrival"); Update(1)
Check(Snapshot().results.tour.status == "FAIL", "camera callback failure is reported as failure, not pending observation")
CameraPath = nativePath
local beforeNet, beforeSave = nextHandle, x.saveCount
net = true; Mission(); Update(10); Command("sx", "save"); Command("sx", "ai")
Check(nextHandle == beforeNet and x.saveCount == beforeSave, "network mode permits only a local overlay, no world/save/tuning mutation")
net = false
local nativeX = x
x = { isStub = true }; Mission(); Update(0); Update(460)
Check(Snapshot().scene.mode == "freeplay" and Snapshot().results.environment.status == "BLOCKED"
    and Snapshot().results.lighting.status == "BLOCKED", "stub EXU completes stock scenes while reporting blocked native exhibits")
x = nativeX
Check(cameraCalls > 0 and finishCalls > 0, "both native path and object-camera callbacks exercised")
Check(#cameraFaults == 0, string.format("native camera stack stays balanced (%d faults, first: %s)",
    #cameraFaults, tostring(cameraFaults[1])))
print(string.format("SXShowcase: %d checks passed (%s host; native visuals/audio/physics unverified)", total, _VERSION))
