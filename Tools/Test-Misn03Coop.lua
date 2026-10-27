-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
-- Execute the complete mission with separate Lua 5.1 environments and the real
-- CRCoop registry. Engine/network mocks verify script decisions, not Redux
-- native replication, native map loading, pathfinding, or EXU's binary hooks.
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
local labels = { "avrec3-1_recycler", "scav1", "scav2", "svfigh1", "svfigh2",
    "enemyturret_1", "enemyturret_2", "enemyturret_3", "enemyturret_4", "geyser1",
    "solar1", "solar2", "solar3", "solar4", "launch_pad", "build1", "build3",
    "build4", "build5", "hanger", "cam_geyser", "shot_geyser", "box1",
    "crate1", "crate2", "crate3", "guy1", "guy2", "sucker" }
local function reset()
    now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
    for _, label in ipairs(labels) do
        objects[label] = { alive = true, team = label:find("^sv") and 5 or 1,
            odf = label, health = 1000, maxHealth = 1000, deployed = false }
    end
end
local function count(peer, name)
    local n = 0
    for _, c in ipairs(peer.calls) do if c[1] == name then n = n + 1 end end
    return n
end
local function last(peer, name)
    for i = #peer.calls, 1, -1 do if peer.calls[i][1] == name then return peer.calls[i] end end
end
local function makePeer(id, team, network)
    local p = { id = id, team = team, net = network, hosting = team == 1,
        calls = {}, difficulty = team == 1 and 3 or 0, player = "player" .. id }
    peers[id] = p
    objects[p.player] = { alive = true, team = team, odf = "avtank", health = 1000, maxHealth = 1000 }
    local function record(name, ...)
        p.calls[#p.calls + 1] = { name, ... }
    end
    local e = setmetatable({}, { __index = _G })
    e._G = e
    p.printed = {}
    e.print = function(...) p.printed[#p.printed + 1] = table.concat({ ... }, " ") end
    e.IsNetGame = function() return p.net end
    e.IsHosting = function() return p.hosting end
    e.GetTime = function() return now end
    e.GetPlayerHandle = function(remote)
        check(remote == nil, "remote GetPlayerHandle(team) must never be used")
        return p.player
    end
    e.SetLabel = function(h, l) record("SetLabel", h, l) end
    e.GetHandle = function(label) return objects[label] and label end
    e.IsAudioMessageDone = function() return true end
    e.IsValid = function(h) return objects[h] ~= nil and objects[h].alive end
    e.IsAlive = e.IsValid
    e.IsCraft = function(h) return e.IsValid(h) and not tostring(h):find("solar") end
    e.IsLocal = function(h) return objects[h] and (objects[h].team == team or (team == 1 and objects[h].team == 5)) end
    e.IsOdf = function(h, odf) return objects[h] and objects[h].odf == odf end
    e.GetTeamNum = function(h) return objects[h] and objects[h].team or 0 end
    e.GetHealth = function(h) return objects[h].health / objects[h].maxHealth end
    e.GetMaxHealth = function(h) return objects[h].maxHealth end
    e.SetMaxHealth = function(h, value) record("SetMaxHealth", h, value); objects[h].maxHealth = value end
    e.SetCurHealth = function(h, value) record("SetCurHealth", h, value); objects[h].health = value end
    e.IsDeployed = function(h) return objects[h] and objects[h].deployed end
    e.GetDistance = function(a, b)
        if tostring(a):find("player") and b == "launch_pad" then
            for _, human in pairs(peers) do
                if human.player == a then return human.nearLaunch and 20 or 1000 end
            end
        end
        if tostring(a):find("built") and b == "launch_pad" then return 20 end
        return 1000
    end
    e.GetPosition = function(h) return { x = 0, y = 0, z = 0 } end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function() return { x = 0, y = 0, z = 0 } end
    e.CountUnitsNearObject = function(target, distance, objectTeam, odf)
        local n = 0
        for h, object in pairs(objects) do
            if object.alive and object.team == objectTeam and object.odf == odf and
                e.GetDistance(h, target) < distance then n = n + 1 end
        end
        return n
    end
    local function iterator()
        local key
        return function()
            key = next(objects, key)
            while key and not objects[key].alive do key = next(objects, key) end
            return key
        end
    end
    e.AllCraft, e.AllObjects = iterator, iterator
    e.BuildObject = function(odf, objectTeam, pos)
        nextObject = nextObject + 1
        local h = "built" .. nextObject
        objects[h] = { alive = true, team = objectTeam, odf = odf, health = 1000, maxHealth = 1000 }
        record("BuildObject", h, odf, objectTeam)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h) record("RemoveObject", h); if objects[h] then objects[h].alive = false end end
    e.CameraCancelled = function() return p.skip == true end
    e.CameraReady = function() record("CameraReady"); p.skip = false end
    e.CameraFinish = function() record("CameraFinish") end
    -- Launch-film engine surface (the NSDF closing shot): poses, camera and EXU particles.
    e.CameraObject = function(...) record("CameraObject", ...) end
    e.GetTransform = function(h)
        local o = objects[h]
        local pose = o and o.pose or { posit_x = 0, posit_y = 0, posit_z = 0 }
        return { posit_x = pose.posit_x, posit_y = pose.posit_y, posit_z = pose.posit_z }
    end
    e.SetTransform = function(h, pose) record("SetTransform", h, pose.posit_y) end
    e.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    e.GetTerrainHeightAndNormal = function() return 0, { x = 0, y = 1, z = 0 } end
    e.Send = function(to, kind, ...)
        for i = 1, select("#", ...) do local v = select(i, ...); assert(type(v) ~= "string" or #v <= 127, "Send string over 127 bytes on " .. tostring(kind)) end
        local args = { ... }
        -- Conservative payload estimate: doubles plus per-field type tags;
        -- strings include terminators. Actual handle encoding is smaller.
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        check(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target, peer in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then
                packets[#packets + 1] = { from = id, to = target, kind = kind, args = args }
            end
        end
    end
    for _, name in ipairs({ "Attack", "Goto", "Retreat", "Follow", "Defend", "Defend2", "Patrol",
        "AddHealth", "Damage", "SetCommand", "SetCritical", "SetPathLoop", "SetVelocity",
        "SetWeaponMask", "SetScrap", "SetPilot", "SetObjectiveName", "SetObjectiveOn",
        "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective", "UpdateObjective",
        "CameraPath", "StartSound", "DisplayMessage", "Ally", "UnAlly", "FailMission", "SucceedMission" }) do
        local n = name
        e[n] = function(...) record(n, ...) end
    end
    e.AiCommand = { UNDEPLOY = 21 }
    local function noop() end
    local aiTeam = { SetConfig = noop }
    local ai = { Factions = { NSDF = 1, CCA = 2 }, Bootstrap = noop,
        AddSpecialObject = function(h) record("AddSpecialObject", h) end,
        Update = function() record("aiUpdate") end, Save = function() return {} end, Load = noop }
    local pilot = { Initialize = function(options) p.pilotOptions = options end,
        AddObject = function(h) record("PilotAdd", h) end, Save = function() return {} end,
        Update = function() record("pilotUpdate") end }
    local subtitles = { Play = function(file) record("Play", file); return file end,
        Queue = function(file) record("Queue", file) end, Stop = function() record("Stop") end,
        Update = function() record("subtitlesUpdate") end, Initialize = noop }
    -- CR Moon weather: the real director has its own suite (Test-CRMoonWeather.lua); this records the wiring.
    p.moon = {updates = 0, announces = 0, shutdowns = 0, events = {}}
    local moonModules = {
        CRMoonWeather = {
            Init = function(options) p.moon.init = options end,
            Update = function() p.moon.updates = p.moon.updates + 1 end,
            Shutdown = function() p.moon.shutdowns = p.moon.shutdowns + 1 end, OnObjectCreated = noop,
            Save = function() return {saved = true} end, Load = function(state) p.moon.loaded = state end,
            AnnounceState = function() p.moon.announces = p.moon.announces + 1 end,
            ApplyNetEvent = function(op, ...) p.moon.events[#p.moon.events + 1] = {op, ...}; return true end,
            Seed = 4242,
        },
        CRMoonSites03 = {mission = "misn03"},
    }
    p.fx = { systems = {}, lights = {}, created = 0, destroyed = 0 }
    local fx = p.fx
    local function particles()
        local x = {}
        x.CreateParticleSystem = function(name, template, at)
            fx.systems[name] = { template = template, at = at, rates = {}, offsets = {} }
            fx.created = fx.created + 1
            return true
        end
        x.DestroyParticleSystem = function(name) fx.systems[name] = nil; fx.destroyed = fx.destroyed + 1; return true end
        x.SetParticleSystemPosition = function(name, at) fx.systems[name].at = at; return true end
        x.SetParticleEmitterEmissionRate = function(name, index, rate) fx.systems[name].rates[index] = rate; return true end
        x.SetParticleEmitterPosition = function(name, index, at) fx.systems[name].offsets[index] = at; return true end
        x.SetParticleSystemKeepLocalSpace = function() end
        x.SetParticleSystemNonVisibleUpdateTimeout = function() end
        x.CreatePointLight = function(name, at, color, range)
            fx.lights[name] = { at = at, color = color, range = range }; return true
        end
        x.SetPointLightPosition = function(name, at) fx.lights[name].at = at; return true end
        x.SetPointLightPowerScale = function() return true end
        x.DestroyPointLight = function(name) fx.lights[name] = nil; return true end
        return x
    end
    local modules = {
        Environment = { Init = function(options) p.environmentOptions = options end,
            BindWeatherSensors = function(name, director) p.weatherSensors = {name, director} end,
            InvalidateRenderer = function() record("environmentInvalidate") end,
            Update = function() record("environmentUpdate") end },
        RequireFix = { Initialize = noop }, exu = {
            GetMyNetID = function() return id end, GetDifficulty = function() return p.difficulty end,
            SetDifficulty = function(d) p.difficulty = d end,
            DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(lives) record("SetLives", lives) end,
        }, aiCore = ai, PlayerPilotMode = pilot, ScriptSubtitles = subtitles,
        DiffUtils = { SetupTeams = function() return aiTeam, aiTeam end,
            Get = function() return { res = 1 } end, ScaleRes = function(n) return n end,
            ScaleTimer = function(n) return n end },
        PersistentConfig = { Settings = {}, Initialize = noop, UpdateInputs = noop,
            UpdateHeadlights = noop }, AutoSave = { Update = function() record("autosave") end },
    }
    for k, v in pairs(moonModules) do modules[k] = v end
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRWire = assert(loadfile("Scripts/CRWire.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    for name, fn in pairs(particles()) do modules.exu[name] = fn end
    modules.CR03RocketLayout = assert(loadfile("Scripts/CR03RocketLayout.lua"))()
    modules.CR06LaunchFilm = assert(loadfile("Scripts/CR06LaunchFilm.lua"))()
    modules.CR06LaunchFX = assert(loadfile("Scripts/CR06LaunchFX.lua"))()
    modules.CRParticleTemplates = { EnsureExtra = function() return true end }
    e.package = setmetatable({loaded={exu=modules.exu}}, {__index=package})
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile("Scripts/misn03.lua")), e)()
    p.env, p.coop = e, modules.CRCoop
    p.env.Start()
    p.state = p.env.Save()
    return p
end
local function deliver(reverse, drop)
    local batch = packets
    packets = {}
    if reverse then
        local reversed = {}; for i = #batch, 1, -1 do reversed[#reversed + 1] = batch[i] end
        batch = reversed
    end
    for _, packet in ipairs(batch) do
        if not (drop and drop(packet)) then
            peers[packet.to].env.Receive(packet.from, packet.kind, unpack(packet.args))
        end
    end
end
local function tick(seconds, reverse, drop)
    now = now + seconds
    for _, p in pairs(peers) do p.env.Update() end
    deliver(reverse, drop)
end
local function settle()
    for i = 1, 30 do tick(0.1) end
end
local function registerAll()
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
end

-- Four humans, distinct difficulty preferences: leader settings win. Opening
-- runs once even when the first event/ACK packets are lost or reordered.
reset()
local host = makePeer(10, 1, true)
local clients = { makePeer(20, 2, true), makePeer(30, 3, true), makePeer(40, 4, true) }
registerAll()
for i = 1, 20 do tick(0.1, true, function(packet) return i < 8 and (packet.kind == "E" or packet.kind == "A") end) end
settle()
check(host.state.first_wave_done, "host did not run the opening")
-- CR Moon weather: the leader runs the director on the map data, guests follow the ordered stream.
check(host.moon.init.authority and host.moon.init.sites.mission == "misn03", "the leader runs the Moon weather director on the misn03 sites")
check(host.environmentOptions.lightingMode == "night" and host.environmentOptions.nativeBaseline
    and host.environmentOptions.nightGameplay == false and host.environmentOptions.skySun.elevation < 0,
    "misn03 is a visual-only lunar night with the sun below the horizon")
check(host.weatherSensors and host.weatherSensors[1] == "Moon" and host.weatherSensors[2].Seed == 4242,
    "Moon weather director is bound to Environment sensors")
check(count(host, "environmentUpdate") > 0, "Moon updates Environment alongside weather")
for _, c in ipairs(clients) do
    check(not c.moon.init.authority and c.moon.init.seed == nil, "guests run the director from the host's events")
    check(c.moon.updates > 0, "guests update the Moon weather every frame")
end
check(host.moon.announces == 1 and host.moon.init.send ~= nil and host.moon.updates > 0, "the leader announces the weather state once the session is ready")
host.moon.init.send("MoonGlow", 1, 0.8, 60.0)
tick(0.1); settle()
for _, c in ipairs(clients) do
    local glows, state = 0, 0
    for _, e in ipairs(c.moon.events) do
        if e[1] == "MoonGlow" and e[2] == 1 and e[3] == 0.8 and e[4] == 60.0 then glows = glows + 1 end
        if e[1] == "MoonState" then state = state + 1 end
    end
    check(glows == 1, "a scripted glow reaches each guest exactly once")
    check(state <= 1, "a MoonState rides the same ordered stream without duplicating")
end
check(#host.moon.events == 0, "the leader never applies its own weather events twice")
for _, client in ipairs(clients) do
    check(not client.state.first_wave_done and not client.state.start_done, "client executed campaign logic")
    check(count(client, "BuildObject") == 0 and count(client, "Attack") == 0, "client created/ordered mission AI")
    check(count(client, "Play") == 1, "opening dialogue was lost/duplicated")
    check(client.difficulty == 3, "host difficulty was not applied to client")
    check(last(client, "SetScrap")[2] == client.team, "client mutated another team's resources")
    check(count(client, "aiUpdate") == 0 and count(client, "pilotUpdate") == 0, "client ran shared mission AI")
    check(count(client, "SetMaxHealth") == 2, "custom defense health maximums were not delivered")
    check(count(client, "DisableStartingRecycler") == 1 and last(client, "SetLives")[2] == 999,
        "native co-op startup/respawn hooks missing")
end
check(not host.pilotOptions.shouldManageHandle(clients[1].player), "Pilot Mode may claim remote human")
local oldAudio = count(clients[1], "Play")
clients[1].env.Receive(30, "E", 999, "Play", now + 5, "fake.wav")
check(count(clients[1], "Play") == oldAudio, "non-leader injected presentation")

-- Complete actual evacuation camera and authoritative spawn/order blocks.
host.state.support_time, host.state.apc_spawn_time = now - 1, now - 1
tick(0.1); settle()
check(host.state.help_spawn and host.state.camera_ready, "evacuation did not start")
clients[1].skip = true
tick(0.1); settle()
check(count(clients[1], "CameraFinish") > 0, "client skip did not release camera")
check(not host.state.movie_over, "client skip ended everyone's movie")
host.skip = true
tick(0.1)
check(not host.state.movie_over, "host skip bypassed shared film timer")
host.state.movie_time = now - 1
tick(0.1); settle()
check(host.state.movie_over and host.state.remove_props, "evacuation film did not complete")
local transports = 0
for _, call in ipairs(host.calls) do
    if call[1] == "BuildObject" and call[3] == "avapc2" then transports = transports + 1 end
end
check(transports == 2, "authoritative transport spawn duplicated")
for _, client in ipairs(clients) do
    check(count(client, "BuildObject") == 0 and count(client, "RemoveObject") > 0, "prop cleanup did not reach client")
    check(last(client, "SetObjectiveOn") ~= nil and count(client, "Play") >= 3, "evacuation HUD/audio missing")
end
host.state.pull_out_time, host.state.turret_move_time = now - 1, now - 1
host.nearLaunch = true
tick(0.1); settle()
check(host.state.third_objective and not host.state.final_objective, "one human at pad completed everyone's mission")
for _, client in ipairs(clients) do client.nearLaunch = true end
tick(0.1); settle()
check(host.state.final_objective and host.state.startfinishingmovie, "all-player launch gate failed")
host.state.coopOutroDeadline = now - 1
tick(0.1); settle()
for i = 1, 40 do tick(0.1, true, function(packet) return i < 3 and packet.kind == "E" end) end
check(count(host, "SucceedMission") == 1, "host did not settle one successful result")
for _, client in ipairs(clients) do
    check(count(client, "SucceedMission") == 1 and count(client, "FailMission") == 0, "client result missing/duplicated")
    check(last(client, "SucceedMission")[3] == "misn03w1.des", "co-op victory debrief changed")
end

-- Offline: same mission Update, immediate stock result semantics and autosave.
reset()
local offline = makePeer(10, 1, false)
tick(0.1)
check(offline.state.first_wave_done and count(offline, "autosave") == 1, "offline startup/autosave changed")
check(count(offline, "DisableStartingRecycler") == 0 and #packets == 0, "offline used network startup/transport")
objects.solar1.alive = false
tick(0.1)
check(last(offline, "FailMission")[3] == "misn03f1.des", "offline tower failure debrief changed")
local saved = offline.env.Save()
-- CR Moon weather offline: the host path with nothing sent, and its state survives Save.
check(offline.moon.init.authority and offline.moon.init.send == nil and offline.moon.announces == 0
    and offline.moon.init.sites.mission == "misn03", "offline Moon weather is the host path with nothing sent")
check(offline.moon.updates > 0 and saved.moonWeatherState ~= nil and saved.moonWeatherState.saved, "Moon weather state is saved and the seed persists")
local savedWeather=saved.moonWeatherState
offline.env.Load(saved, {}, {})
now = now + 3
offline.env.Update()
check(offline.state.loading_done, "offline save/load did not rehydrate")
check(offline.moon.loaded==savedWeather and count(offline,"environmentInvalidate")>0,
    "load restores Moon weather and reapplies renderer state")

-- Replicated loss is also an ordered event and cannot turn into success.
reset()
host = makePeer(10, 1, true)
local client = makePeer(20, 2, true)
registerAll(); settle()
objects.solar1.alive = false
tick(0.1); settle()
check(count(host, "FailMission") == 1 and count(client, "FailMission") == 1, "failure result did not reach both peers")
check(last(client, "FailMission")[3] == "misn03f1.des" and count(client, "SucceedMission") == 0,
    "loss debrief/terminal latch changed")

-- Missing/destroyed marker handles hold delivery briefly, then release the
-- stream. They must not deadlock cleanup and terminal results forever.
local expectedAck = last(client, "SucceedMission")
check(expectedAck == nil, "failure client acquired a success result")
local previousClear = count(client, "ClearObjectives")
local nextSeq
-- The stream's latest acknowledgement is observable in the outbound transport.
client.env.Receive(10, "E", 0, "ClearObjectives", now + 5)
nextSeq = packets[#packets].args[1] + 1
client.env.Receive(10, "E", nextSeq, "SetObjectiveOn", 5, "not-yet-replicated")
client.env.Receive(10, "E", nextSeq + 1, "ClearObjectives", 5)
check(count(client, "ClearObjectives") == previousClear, "sequence gap did not defer following event")
now = now + 6
client.env.Receive(10, "E", nextSeq, "SetObjectiveOn", 5, "not-yet-replicated")
client.env.Receive(10, "E", nextSeq + 1, "ClearObjectives", 5)
client.env.Receive(10, "E", nextSeq + 1, "ClearObjectives", 5)
check(count(client, "ClearObjectives") == previousClear + 1, "expired marker/duplicate handling failed")

-- A map object the engine cannot carry as a handle goes by "@label" and resolves via the
-- guest's GetHandle. The wait is relative to the guest's own clock, so a leader clock
-- far from the guest's can never drop the marker, and it still lands when the object
-- finally resolves. A label that never resolves drops after the guest's own ttl.
local labelSeq = nextSeq + 2
local markers = count(client, "SetObjectiveOn")
client.env.Receive(10, "E", labelSeq, "SetObjectiveOn", 5, "@900@late_geyser")
client.env.Receive(10, "E", labelSeq + 1, "ClearObjectives", 5)
check(count(client, "SetObjectiveOn") == markers and count(client, "ClearObjectives") == previousClear + 1,
    "an unresolved label must hold the ordered stream")
now = now + 3
objects.late_geyser = { alive = true, team = 0, odf = "eggeizr1", health = 1, maxHealth = 1 }
client.env.Receive(10, "E", labelSeq, "SetObjectiveOn", 5, "@900@late_geyser")
client.env.Receive(10, "E", labelSeq + 1, "ClearObjectives", 5)
check(count(client, "SetObjectiveOn") == markers + 1 and last(client, "SetObjectiveOn")[2] == "late_geyser" and
    count(client, "ClearObjectives") == previousClear + 2, "a late-resolving label marker must land, then the next event")
client.env.Receive(10, "E", labelSeq + 2, "SetObjectiveOn", 5, "@901@never_exists")
client.env.Receive(10, "E", labelSeq + 3, "ClearObjectives", 5)
now = now + 5.5
client.env.Receive(10, "E", labelSeq + 2, "SetObjectiveOn", 5, "@901@never_exists")
client.env.Receive(10, "E", labelSeq + 3, "ClearObjectives", 5)
check(count(client, "SetObjectiveOn") == markers + 1 and count(client, "ClearObjectives") == previousClear + 3,
    "a label that never resolves must drop after the guest's own wait without blocking")
-- A label only the leader knows (SetLabel on a spawned, replicated object) falls back to
-- the replicated handle carried in the same argument.
objects[902] = { alive = true, team = 1, odf = "avscav", health = 1, maxHealth = 1 }
client.env.Receive(10, "E", labelSeq + 4, "SetObjectiveOn", 5, "@902@leader_only_label")
check(count(client, "SetObjectiveOn") == markers + 2 and last(client, "SetObjectiveOn")[2] == 902,
    "a leader-only label must fall back to the replicated handle")

-- Label events replicate a leader-side SetLabel; a gone flag skips cleanly; only the long
-- never-hang guard ends a wait, loudly (log + counter for the harness probe).
local baseSeq = labelSeq + 5
local labelsSet, setClears = count(client, "SetLabel"), count(client, "ClearObjectives")
client.env.Receive(10, "E", baseSeq, "Label", 15, "@907@spawned_label", "spawned_label")
client.env.Receive(10, "E", baseSeq + 1, "SetObjectiveOn", 15, "@907@spawned_label")
check(count(client, "SetLabel") == labelsSet, "a Label for a spawn that has not replicated holds the stream")
objects[907] = { alive = true, team = 1, odf = "avscav", health = 1, maxHealth = 1 }
client.env.Receive(10, "E", baseSeq, "Label", 15, "@907@spawned_label", "spawned_label")
client.env.Receive(10, "E", baseSeq + 1, "SetObjectiveOn", 15, "@907@spawned_label")
check(count(client, "SetLabel") == labelsSet + 1 and last(client, "SetLabel")[2] == 907 and
    last(client, "SetLabel")[3] == "spawned_label", "the guest labels its replicated handle")
check(last(client, "SetObjectiveOn")[2] == 907, "the following marker resolves the real object")
local ons = count(client, "SetObjectiveOn")
client.env.Receive(10, "E", baseSeq + 2, "SetObjectiveOn", 15, "!")
client.env.Receive(10, "E", baseSeq + 3, "ClearObjectives", 15)
check(count(client, "SetObjectiveOn") == ons and count(client, "ClearObjectives") == setClears + 1,
    "a marker the leader reports gone is skipped without holding the stream")
local unresolvedBefore = client.env.Save().coopUnresolved or 0
client.env.Receive(10, "E", baseSeq + 4, "SetObjectiveOn", 15, "@908@never_label")
client.env.Receive(10, "E", baseSeq + 5, "ClearObjectives", 15)
now = now + 14
client.env.Receive(10, "E", baseSeq + 4, "SetObjectiveOn", 15, "@908@never_label")
check(count(client, "ClearObjectives") == setClears + 1, "a marker waits through the old 5 s window")
now = now + 2
client.env.Receive(10, "E", baseSeq + 4, "SetObjectiveOn", 15, "@908@never_label")
client.env.Receive(10, "E", baseSeq + 5, "ClearObjectives", 15)
check(count(client, "ClearObjectives") == setClears + 2 and count(client, "SetObjectiveOn") == ons,
    "the never-hang guard drops only the stale marker")
check((client.env.Save().coopUnresolved or 0) == unresolvedBefore + 1, "the timeout is counted for the probe")
local loud = false
for _, line in ipairs(client.printed) do loud = loud or line:find("%[coop%] unresolved never_label") ~= nil end
check(loud, "the timeout logs a loud [coop] unresolved line")

-- Camera snapshots are label-aware and WAIT for the real object; there is no fallback aim.
reset(); host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll()
local camSerial = 5000
local function camFrame(generation, target)
    client.env.Receive(10, "C", camSerial, generation, "camera_path", 175, 850, target)
    camSerial = camSerial + 1
    client.env.Update()
end
local function endFilm()
    client.env.Receive(10, "C", camSerial, 1, "", 0, 0); camSerial = camSerial + 1; client.env.Update()
end
local casts = count(client, "CameraPath")
camFrame(1, "@903@late_cam_target")
check(count(client, "CameraPath") == casts, "an unresolved camera target waits for the replica")
now = now + 10; camFrame(1, "@903@late_cam_target")
check(count(client, "CameraPath") == casts, "the camera keeps waiting for the real object, however long")
objects.late_cam_target = { alive = true, team = 0, odf = "eggeizr1", health = 1, maxHealth = 1 }
camFrame(1, "@903@late_cam_target")
check(count(client, "CameraPath") == casts + 1 and last(client, "CameraPath")[5] == "late_cam_target",
    "a late-resolving label target is the one the film aims at")
endFilm()
-- A spawned object the leader labelled: its label is replicated by a Label event, and the
-- camera resolves through the replicated handle while the label is not yet known.
casts = count(client, "CameraPath")
camFrame(2, "@905@leader_spawn_label")
check(count(client, "CameraPath") == casts, "a spawned target that has not replicated yet holds the film")
objects[905] = { alive = true, team = 1, odf = "avscav", health = 1, maxHealth = 1 }
camFrame(2, "@905@leader_spawn_label")
check(count(client, "CameraPath") == casts + 1 and last(client, "CameraPath")[5] == 905,
    "the film aims at the real replicated spawn, not a stand-in")
endFilm()
-- The leader reports the target gone: play with what remains valid, without waiting.
casts = count(client, "CameraPath")
camFrame(3, "!")
check(count(client, "CameraPath") == casts + 1 and last(client, "CameraPath")[5] == nil,
    "a target the leader reports gone must not hold the film")
endFilm()
-- Never-hang guard: logged loudly, counted for the harness, then the film plays.
casts = count(client, "CameraPath")
local unresolved = client.env.Save().coopUnresolved or 0
camFrame(4, "@906@never_exists_cam")
check(count(client, "CameraPath") == casts, "an unresolvable target waits")
now = now + 14; camFrame(4, "@906@never_exists_cam")
check(count(client, "CameraPath") == casts, "still waiting inside the safety window")
now = now + 2; camFrame(4, "@906@never_exists_cam")
check(count(client, "CameraPath") == casts + 1, "the never-hang guard lets the film play")
check((client.env.Save().coopUnresolved or 0) == unresolved + 1, "the timeout is counted for the probe")
local logged = false
for _, line in ipairs(client.printed) do logged = logged or line:find("%[coop%] unresolved") ~= nil end
check(logged, "the timeout logs a loud [coop] unresolved line")

-- A deleted human no longer holds the all-player proximity/readiness gate.
reset()
host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle()
host.env.DeletePlayer(20, "P20", 2)
peers[20] = nil; host.nearLaunch = true
check(host.coop.AllPlayersNear("launch_pad", 100), "departed guest still blocked launch")

-- Respawn/vehicle changes are refreshed by each owner and exchanged. Late
-- join is fail-closed and a migrated host never inherits campaign simulation.
reset()
host = makePeer(10, 1, true); client = makePeer(20, 2, true)
registerAll(); settle()
objects[client.player].alive = false
client.player = "player20respawn"
objects[client.player] = { alive = true, team = 2, odf = "aspilo", health = 1000, maxHealth = 1000 }
settle()
check(host.coop.IsHumanCraft(client.player) and host.coop.HasAllPlayerHandles(), "remote respawn handle was not refreshed")
local late = makePeer(30, 3, true)
for _, p in pairs(peers) do
    p.env.CreatePlayer(30, "Late", 3)
    if p == late then
        p.env.CreatePlayer(10, "Host", 1); p.env.CreatePlayer(20, "Client", 2)
    end
end
settle()
local builds = count(host, "BuildObject")
host.state.support_time = now - 1
settle()
check(count(host, "BuildObject") == builds and count(host, "DisplayMessage") > 0, "late join ran unreconciled mission state")
client.env.DeletePlayer(10, "Host", 1)
client.hosting = true
client.env.Update()
check(not client.coop.IsAuthority() and count(client, "FailMission") == 1, "host migration inherited authority or left mission running")
print("misn03 co-op: " .. checks .. " complete-script Lua 5.1 checks passed")
