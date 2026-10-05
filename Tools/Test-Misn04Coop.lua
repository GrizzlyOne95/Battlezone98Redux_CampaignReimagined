-- Execute the complete mission with separate Lua 5.1 environments and the real
-- CRCoop registry. Engine/network mocks verify script decisions, not Redux
-- native map loading, physics, pathfinding, Lua wire serialization, or EXU hooks.
-- Peer replicas and the BZRNet envelope are separate: missing object handles
-- cannot become valid merely because a mission message reached a client.
local PeerTransport = dofile("Tools/BZRPeerTransportSim.lua")
local transport, reliableSend = nil, false
local births = {}
local function copy(object)
    local result = {}; for k, v in pairs(object) do result[k] = v end; return result
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
local labels = { "player-1_hover", "apcamr352_camerapod", "apcamr350_camerapod", "apcamr351_camerapod", "apcamr-1_camerapod", "avrecy-1_recycler", "svrecy-1_recycler", "svmuf-1_factory", "svscav-1_scavenger" }
local distances = {}
local function reset()
    now, objects, peers, packets, nextObject = 0, {}, {}, {}, 0
    distances, births = {}, {}
    transport = PeerTransport.New(function(packet)
        if peers[packet.to] then
            peers[packet.to].env.Receive(packet.from, packet.kind, unpack(packet.args))
        end
    end)
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
    p.view = (not network or team == 1) and objects or {}
    for _, other in pairs(peers) do
        for h, object in pairs(objects) do other.view[h] = copy(object) end
    end
    local view = p.view
    local function record(name, ...)
        p.calls[#p.calls + 1] = { name, ... }
    end
    local e = setmetatable({}, { __index = _G })
    e._G = e
    e.print = function() end
    e.IsNetGame = function() return p.net end
    e.IsHosting = function() return p.hosting end
    e.GetTime = function() return now end
    e.GetPlayerHandle = function(remote)
        check(remote == nil, "remote GetPlayerHandle(team) must never be used")
        return p.player
    end
    e.GetHandle = function(label) return view[label] and label end
    e.IsValid = function(h) return view[h] ~= nil and view[h].alive end
    e.IsAlive = e.IsValid
    e.IsCraft = function(h) return e.IsValid(h) and not tostring(h):find("solar") end
    e.IsLocal = function(h) return view[h] and (view[h].team == team or (team == 1 and (view[h].team == 0 or view[h].team >= 5))) end
    e.GetCargo = function(h) return view[h] and view[h].cargo end
    e.HasCargo = function(h) return e.GetCargo(h) ~= nil end
    e.GetTug = function(cargo)
        for h, o in pairs(view) do if o.alive and o.cargo == cargo then return h end end
    end
    e.IsPerson = function(h) return view[h] and view[h].odf == "aspilo" end
    e.IsAudioMessageDone = function() return p.audioDone == true end
    e.GetLastEnemyShot = function() return p.shot or 0 end
    e.GetOdf = function(h) return view[h] and view[h].odf end
    e.SetTeamNum = function(h, t) record("SetTeamNum", h, t); view[h].team = t end
    e.IsOdf = function(h, odf) return view[h] and view[h].odf == odf end
    e.GetTeamNum = function(h) return view[h] and view[h].team or 0 end
    e.GetHealth = function(h) return view[h].health / view[h].maxHealth end
    e.GetMaxHealth = function(h) return view[h].maxHealth end
    e.SetMaxHealth = function(h, value) record("SetMaxHealth", h, value); view[h].maxHealth = value end
    e.SetCurHealth = function(h, value) record("SetCurHealth", h, value); view[h].health = value end
    e.IsDeployed = function(h) return view[h] and view[h].deployed end
    e.GetDistance = function(a, b)
        if view[a] and view[a].odf == "apcamr" and view[b] and view[b].odf == "obdata" then return 20 end
        if tostring(a):find("player") and b == "launch_pad" then
            for _, human in pairs(peers) do
                if human.player == a then return human.nearLaunch and 20 or 1000 end
            end
        end
        if tostring(a):find("built") and b == "launch_pad" then return 20 end
        return distances[tostring(a) .. ":" .. tostring(b)] or 1000
    end
    e.GetPosition = function(h) return { x = 0, y = 0, z = 0 } end
    e.GetPositionNear = function(pos) return pos end
    e.GetVelocity = function() return { x = 0, y = 0, z = 0 } end
    e.CountUnitsNearObject = function(target, distance, objectTeam, odf)
        local n = 0
        for h, object in pairs(view) do
            if object.alive and object.team == objectTeam and (odf == nil or object.odf == odf) and
                e.GetDistance(h, target) < distance then n = n + 1 end
        end
        return n
    end
    local function iterator()
        local key
        return function()
            key = next(view, key)
            while key and not view[key].alive do key = next(view, key) end
            return key
        end
    end
    e.AllCraft, e.AllObjects = iterator, iterator
    e.BuildObject = function(odf, objectTeam, pos)
        nextObject = nextObject + 1
        local h = "built" .. nextObject
        view[h] = { alive = true, team = objectTeam, odf = odf, health = 1000, maxHealth = 1000 }
        births[h] = now + 0.8
        record("BuildObject", h, odf, objectTeam)
        e.AddObject(h)
        return h
    end
    e.RemoveObject = function(h) record("RemoveObject", h); if view[h] then view[h].alive = false end end
    e.CameraCancelled = function() return p.skip == true end
    e.CameraReady = function() check(not p.cameraUp, "camera opened twice"); p.cameraUp = true; record("CameraReady"); p.skip = false end
    e.CameraFinish = function() check(p.cameraUp, "camera finished without an active camera"); p.cameraUp = false; record("CameraFinish") end
    e.Send = function(to, kind, ...)
        local args = { ... }
        -- Conservative payload estimate: doubles plus per-field type tags;
        -- strings include terminators. Actual handle encoding is smaller.
        local bytes = 4
        for _, value in ipairs(args) do bytes = bytes + (type(value) == "string" and #value + 2 or 9) end
        check(bytes < 244, "mission packet exceeds stock payload budget: " .. kind)
        for target, peer in pairs(peers) do
            if target ~= id and (to == 0 or to == nil or target == to) then
                transport:Send(id, target, kind, args, reliableSend)
            end
        end
    end
    for _, name in ipairs({ "Attack", "Goto", "Retreat", "Follow", "Defend", "Defend2", "Patrol",
        "AddHealth", "Damage", "SetCommand", "SetCritical", "SetPathLoop", "SetVelocity",
        "SetPosition", "SetLabel", "SetIndependence", "SetAIP", "MakeExplosion", "SetWeaponMask", "SetScrap", "SetPilot", "SetObjectiveName", "SetObjectiveOn",
        "SetObjectiveOff", "SetUserTarget", "ClearObjectives", "AddObjective", "UpdateObjective",
        "CameraPath", "StartSound", "DisplayMessage", "Ally", "UnAlly", "FailMission", "SucceedMission" }) do
        local n = name
        e[n] = function(...)
            if n == "SetObjectiveOn" or n == "SetObjectiveName" or n == "SetUserTarget" then
                check(e.IsValid((...)), "presentation used a not-yet-replicated handle")
            end
            if n == "CameraPath" then check(p.cameraUp, "camera path without ready") end
            record(n, ...)
        end
    end
    e.StopAudioMessage = function(...) record("StopAudioMessage", ...) end
    e.Pickup = function(...) record("Pickup", ...) end
    e.AiCommand = { UNDEPLOY = 21 }
    local function noop() end
    local aiTeam = { SetConfig = noop, Config = {}, SetCustomStrategy = noop,
        PlanDefensivePerimeter = noop, FindOptimalSiloLocation = noop }
    local ai = { ResetObjectCacheTracking = noop, TrackWorldObject = noop, RefreshObjectCache = noop,
        ActiveTeams = { [1] = aiTeam, [5] = aiTeam },
        AddObject = function(h)
            check(e.IsLocal(h) and not p.coop.IsHumanCraft(h), "aiCore registered remote/human craft")
            record("aiAdd", h)
        end, Factions = { NSDF = 1, CCA = 2 }, Bootstrap = noop,
        AddSpecialObject = function(h) record("AddSpecialObject", h) end,
        Update = function() record("aiUpdate") end, Save = function() return {} end, Load = noop }
    local pilot = { SetCargoJob = function(key, job) p.cargoJob = job end, Initialize = function(options) p.pilotOptions = options end,
        AddObject = function(h) record("PilotAdd", h) end, Save = function() return {} end,
        Update = function() record("pilotUpdate") end }
    local subtitles = { Play = function(file) record("Play", file); return file end,
        Queue = function(file) record("Queue", file) end, Stop = function() record("Stop") end,
        Update = function() record("subtitlesUpdate") end, Initialize = noop }
    local modules = {
        RequireFix = { Initialize = noop }, exu = {
            GetMyNetID = function() return id end, GetDifficulty = function() return p.difficulty end,
            SetDifficulty = function(d) p.difficulty = d end,
            DisableStartingRecycler = function() record("DisableStartingRecycler") end,
            SetLives = function(lives) record("SetLives", lives) end,
        }, aiCore = ai, PlayerPilotMode = pilot, ScriptSubtitles = subtitles,
        TerrainClutter = { BuildLayer = function() record("clutter") end },
        DiffUtils = { SetupTeams = function() return aiTeam, aiTeam end,
            Get = function() return { res = 1, index = p.difficulty } end, ScaleEnemy = function(n) return n end, ScaleRes = function(n) return n end,
            ScaleTimer = function(n) return n end },
        Environment = { Init = noop, Update = function() record("environmentUpdate") end, Save = function() return {} end },
        CRMarsWeather = { AllowWindPush = true, Init = function(options) p.weatherOptions = options end,
            Shutdown = noop, SetAutomatic = function(enabled) p.weatherAutomatic = enabled end,
            GetTargetLevel = function() return p.weatherTarget or 1 end,
            GetLevel = function() return p.weatherLevel or 1 end,
            SetTargetLevel = function(level) p.weatherTarget = level; record("weatherTarget", level) end,
            ForceLevel = function(level, seconds, transition) p.weatherLevel = level; record("weatherForce", level, seconds, transition) end,
            Update = function() record("weatherUpdate") end, Save = function() return {} end },
        PersistentConfig = { Settings = {}, Initialize = noop, UpdateInputs = noop,
            UpdateHeadlights = noop }, AutoSave = { Update = function() record("autosave") end },
    }
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile("Scripts/misn04.lua")), e)()
    p.env, p.coop = e, modules.CRCoop
    p.env.Start()
    p.state = p.env.Save()
    return p
end
local function replicate()
    for _, peer in pairs(peers) do
        if peer.view ~= objects then
            for h, object in pairs(objects) do
                if not births[h] or now >= births[h] then peer.view[h] = copy(object) end
            end
        end
    end
end
local function tick(seconds, reverse, drop)
    now = now + seconds
    replicate()
    for _, p in pairs(peers) do p.env.Update() end
    transport:Step(now, reverse, drop)
end
local function settle()
    for i = 1, 30 do tick(0.1) end
end
local function registerAll()
    for _, p in pairs(peers) do
        for id, other in pairs(peers) do p.env.CreatePlayer(id, "P" .. id, other.team) end
    end
end

local function killWave(host, number)
    for i = 1, 6 do local h = host.state["w" .. number .. "u" .. i]; if h then objects[h].alive = false end end
end
local function discover(host, guest)
    distances[guest.player .. ":" .. host.state.relic] = 100
    tick(0.1); settle()
    check(host.state.discoverrelic and host.state.cheater, "guest failed to discover relic")
end
for _, mode in ipairs({ false, true }) do
    reliableSend = mode
    reset()
    local host = makePeer(10, 1, true)
    local clients = { makePeer(20, 2, true), makePeer(30, 3, true), makePeer(40, 4, true) }
    registerAll()
    for i = 1, 30 do tick(0.1, not mode or i < 8, function(packet) return i < 8 and (packet.kind == "E" or packet.kind == "A") end) end
    settle()
    check(host.state.missionstart, "leader opening blocked")
    check(#host.state.scriptedTeam2Handles == 8, "opening defenders not isolated")
    for _, c in ipairs(clients) do
        check(not c.state.missionstart and count(c, "BuildObject") == 0 and count(c, "aiUpdate") == 0, "guest ran simulation")
        check(count(c, "Play") == 1 and c.difficulty == 3, "opening/difficulty lost or duplicated")
        check(last(c, "SetScrap")[2] == c.team and count(c, "SetScrap") == 1, "resources not owner-local")
        check(count(c, "DisableStartingRecycler") == 1 and last(c, "SetLives")[2] == 999, "native hooks missing")
        check(count(c, "autosave") == 0 and count(c, "environmentUpdate") > 0 and count(c, "weatherUpdate") > 0, "guest local modules missing")
        check(c.weatherAutomatic == false and c.weatherOptions.windPush == false, "guest has independent weather physics")
    end
    check(host.weatherAutomatic and host.weatherOptions.windPush == false, "host weather setup missing")
    check(not host.pilotOptions.shouldManageHandle(clients[1].player), "pilot mode claimed guest")
    -- Delayed marker replicas must resolve before the ordered event ACK.
    discover(host, clients[1])
    for _, c in ipairs(clients) do
        check(count(c, "CameraPath") > 0, "discovery camera missing")
        check(last(c, "SetObjectiveOn")[2] == host.state.relic, "relic marker missing")
    end
    clients[1].skip = true; host.skip = true; tick(0.1); settle()
    check(not host.state.cin1done and count(clients[1], "CameraFinish") > 0, "local skip changed shared timeline")
    tick(24); settle()
    check(host.state.cin1done, "stuck audio blocked discovery timer")
    -- Guest-owned tug returns cargo; leader neither orders nor automates it.
    local tug = clients[1].env.BuildObject("avhaul", 2, "start")
    objects[tug] = copy(clients[1].view[tug]); objects[tug].cargo = host.state.relic
    host.view[tug] = objects[tug]
    tick(1); settle()
    check(host.state.halfway and host.state.relicCarrier == tug, "guest tow not recognized")
    check(host.state.tug ~= tug and host.cargoJob.preferredCarrier ~= tug, "guest tug became automated carrier")
    check(not host.pilotOptions.shouldManageHandle(tug), "pilot mode claimed guest-owned tug")
    for _, c in ipairs(clients) do check(last(c, "SetObjectiveOn")[2] == tug, "guest cargo marker missing") end
    -- Drive all five authored waves; every dynamic CCA stays off human teams.
    for wave = 1, 5 do
        host.state["wave" .. wave] = now - 1
        tick(0.1); settle()
        check(host.state["w" .. wave .. "u1"] ~= nil, "wave missing: " .. wave)
        killWave(host, wave); tick(0.1); settle()
    end
    check(host.state.wave5dead and host.state.weatherSetPiece, "final wave/set piece missing")
    for _, c in ipairs(clients) do check(c.weatherLevel == host.weatherLevel and c.weatherLevel == 5, "severe storm not replicated") end
    for _, call in ipairs(host.calls) do
        if call[1] == "BuildObject" and call[3]:find("^sv") then check(call[4] == 5, "CCA spawn on human team") end
        if call[1] == "aiAdd" then
            for _, h in ipairs(host.state.scriptedTeam2Handles) do check(call[2] ~= h, "aiCore stole scripted unit") end
        end
    end
    objects[host.player].alive = false
    host.player = "respawn10"; objects[host.player] = { alive = true, team = 1, odf = "aspilo", health = 1000, maxHealth = 1000 }
    tick(0.1); settle(); check(not host.state.missionfail and host.coop.IsHumanCraft(host.player), "respawn lost mission")
    distances[host.state.relic .. ":avrecy-1_recycler"] = 50
    objects["svrecy-1_recycler"].alive = false
    host.audioDone = true; tick(0.1); settle()
    check(host.state.relicsecure and host.state.basesecure and host.state.cin_started, "secure gates failed")
    tick(21)
    for i = 1, 80 do tick(0.1, not mode or i < 8, function(packet) return i < 8 and packet.kind == "E" end) end
    check(count(host, "SucceedMission") == 1, "leader result missing/duplicated")
    for _, c in ipairs(clients) do check(count(c, "SucceedMission") == 1 and last(c, "SucceedMission")[3] == "misn04w1.des", "guest result missing") end
    check(host.view ~= clients[1].view and transport.delivered > 0, "replica transport unused")
    if mode then check(transport.retries > 0 and transport.rejected > 0, "reliable ordering not tested") end
end
reliableSend = false
-- Destruction must beat both previously latched secure flags.
for _, loss in ipairs({ { "avrecy-1_recycler", "misn04l3.des" }, { "relic", "misn04l2.des" } }) do
    reset(); local host = makePeer(10, 1, true); local guest = makePeer(20, 2, true)
    registerAll(); settle()
    host.state.relicsecure, host.state.basesecure = true, true
    objects[loss[1] == "relic" and host.state.relic or loss[1]].alive = false
    tick(0.1); settle(); settle()
    check(count(host, "FailMission") == 1 and count(guest, "FailMission") == 1, "replicated destruction loss missing")
    check(last(guest, "FailMission")[3] == loss[2] and count(guest, "SucceedMission") == 0, "destruction became victory")
end
-- CCA theft retains debrief and a finite online camera even with stuck audio.
reset(); local host = makePeer(10, 1, true); local guest = makePeer(20, 2, true)
registerAll(); settle(); discover(host, guest)
host.state.ccatug = now - 1; tick(0.1); settle()
objects[host.state.svtug].cargo = host.state.relic
distances[host.state.svtug .. ":svrecy-1_recycler"] = 20
tick(0.1); settle(); check(host.state.missionfail2, "CCA theft failed")
tick(121); settle(); settle()
check(count(guest, "FailMission") == 1 and last(guest, "FailMission")[3] == "misn04l1.des", "theft deadline/debrief missing")
-- Offline retains the campaign cargo job, weather wind, and save rehydration.
reset(); local solo = makePeer(10, 1, false); tick(0.1)
check(solo.state.missionstart and count(solo, "autosave") == 1, "offline startup changed")
check(solo.weatherOptions.windPush == true and solo.weatherAutomatic, "offline weather changed")
local saved = solo.env.Save(); solo.env.Load(saved, {}, {}); tick(3)
check(solo.state.loading_done and count(solo, "autosave") == 2, "offline save/load failed")
-- Survey route and the authored missed-investigation failure.
reset(); host = makePeer(10, 1, true); guest = makePeer(20, 2, true)
registerAll(); settle(); host.state.fetch = now - 1; tick(0.1); settle()
check(host.state.surveysent and not host.state.cheater and host.state.surv1, "timed survey route missing")
tick(61); settle(); host.audioDone = true; tick(0.1); settle()
check(host.state.reconsent and host.state.reliccam, "timed recon marker missing")
for i = 1, 4 do host.state.notfound = now - 1; tick(0.1); settle() end
host.state.notfound = now - 1; tick(0.1); settle(); settle()
check(count(guest, "FailMission") == 1 and last(guest, "FailMission")[3] == "misn04l4.des", "missed investigation debrief missing")
-- Departures, unsupported late joins and repeated same-process starts.
reset(); host = makePeer(10, 1, true); guest = makePeer(20, 2, true)
registerAll(); settle(); guest.env.DeletePlayer(10, "Host", 1); guest.hosting = true; tick(0.1)
check(not guest.coop.IsAuthority() and count(guest, "FailMission") == 1, "host migration inherited mission")
reset(); host = makePeer(10, 1, true); guest = makePeer(20, 2, true)
registerAll(); settle(); local builds = count(host, "BuildObject")
local late = makePeer(30, 3, true)
for _, p in pairs(peers) do p.env.CreatePlayer(30, "Late", 3) end
late.env.CreatePlayer(10, "Host", 1); late.env.CreatePlayer(20, "Guest", 2)
settle(); check(count(host, "BuildObject") == builds and count(host, "DisplayMessage") == 1, "late join progressed")
for _, p in pairs(peers) do p.env.Start(); p.state = p.env.Save() end
registerAll(); settle(); settle()
check(host.state.missionstart and not host.coop.HasLateJoiners(), "restart retained old admission state")
print("misn04 co-op: " .. checks .. " complete-script Lua 5.1 checks passed")
