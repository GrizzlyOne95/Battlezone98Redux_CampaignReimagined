-- Execute the mission's presentation adapter in isolated Lua 5.1 peers.
-- This covers primitive protocol decisions, not native handle serialization.
local file = assert(io.open("Scripts/misn06.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local adapter = assert(source:match("(local unpackArgs =.-)\n%-%- BuildObject invokes"))
local atmosphere = assert(source:match("(InitAtmosphere = function%(%)\n.-)\n%-%- CR atmosphere <<"))
local now, peers, packets = 0, {}, {}
local registry = {[1]={team=1}, [2]={team=2}, [3]={team=3}, [4]={team=4}}
local checks = 0
local function check(value, why) assert(value, why); checks = checks + 1 end
local function peer(id)
    local p = {calls={}, valid={subject=true, target=true}, cancelled=false, info={},
        resources={scrap=0, pilots=0, maxScrap=id == 1 and 35 or 0, maxPilots=id == 1 and 15 or 0}}
    local env = setmetatable({}, {__index=_G})
    local function record(op, ...)
        p.calls[#p.calls+1] = {op, ...}
    end
    for _, op in ipairs({"ClearObjectives", "AddObjective", "UpdateObjective", "SetObjectiveOn",
        "SetObjectiveOff", "SetObjectiveName", "SetUserTarget", "RemoveObject", "SucceedMission",
        "FailMission", "CameraReady", "CameraObject", "CameraPath", "CameraFinish",
        "StartCockpitTimer", "StopCockpitTimer", "HideCockpitTimer"}) do
        local name = op
        env[name] = function(...)
            record(name, ...)
            if name == "CameraObject" and p.cancelOnObject then p.cancelled = true end
        end
    end
    env.CameraCancelled = function() return p.cancelled end
    env.IsInfo = function(prefix) return p.info[prefix] == true end
    env.GetMaxScrap = function(team) assert(team == id); return p.resources.maxScrap end
    env.GetMaxPilot = function(team) assert(team == id); return p.resources.maxPilots end
    env.SetMaxScrap = function(team, n) assert(team == id); p.resources.maxScrap = n end
    env.SetMaxPilot = function(team, n) assert(team == id); p.resources.maxPilots = n end
    env.SetScrap = function(team, n) assert(team == id); p.resources.scrap = math.min(n, p.resources.maxScrap) end
    env.SetPilot = function(team, n) assert(team == id); p.resources.pilots = math.min(n, p.resources.maxPilots) end
    -- p.clock offsets this peer's GetTime() from the shared test clock (clock skew).
    -- p.labels maps handle -> map label (GetLabel); p.byLabel maps label -> handle (GetHandle).
    env.GetTime = function() return now + (p.clock or 0) end
    p.labels, p.byLabel = {}, {}
    env.GetPlayerHandle = function() return "craft" .. id end
    p.valid["craft" .. id] = true
    env.GetLabel = function(h) return p.labels[h] end
    env.GetHandle = function(label) return p.byLabel[label] end
    env.IsValid = function(h) return p.valid[h] == true end
    env.Send = function(to, kind, ...)
        packets[#packets+1] = {from=id, to=to, kind=kind, args={...}}
    end
    env.CRCoop = {
        IsNetworkGame=function() return true end,
        IsAuthority=function() return id == 1 end,
        GetPlayers=function() return registry end,
        IsHumanTeam=function(t) return t >= 1 and t <= 4 end,
        GetLocalPlayerId=function() return id end,
        GetLocalTeam=function() return id end,
    }
    env.subtit = {Play=function(...) record("Play", ...); return "audio" end,
        Queue=function(...) record("Queue", ...) end, Stop=function() record("Stop") end}
    env.Environment = {Init=function() end, Update=function() record("EnvironmentUpdate") end}
    p.weather = {level=1,target=2}
    env.CRMarsWeather = {
        Init=function(options) p.weather.options=options end,
        Load=function() end,
        SetAutomatic=function(enabled) p.weather.automatic=enabled end,
        SetTargetLevel=function(value) p.weather.target=value end,
        GetTargetLevel=function() return p.weather.target end,
        GetLevel=function() return p.weather.level end,
        ForceLevel=function(level) p.weather.level=level end,
        Update=function() record("WeatherUpdate") end,
    }
    env.M = {}
    env.launchFX = {Begin=function(...) record('RocketFX',...) end,
        Stop=function() record('RocketFXStop') end,Reset=function() record('RocketFXReset') end}
    p.M = env.M
    p.printed = {}
    env.print = function(...) p.printed[#p.printed + 1] = table.concat({ ... }, " ") end
    env.SetLabel = function(h, l) record("SetLabel", h, l); p.labels[h] = l; p.byLabel[l] = h end
    local chunk = assert(loadstring("local CRCoop, M, subtit, LEADER_TEAM = CRCoop, M, subtit, 1\nlocal InitAtmosphere, weatherStarted, nextWeatherSync\n" .. adapter .. "\n" .. atmosphere .. [[
        return { ready=CameraReady, object=CameraObject, path=CameraPath, finish=CameraFinish,
            cancelled=CameraCancelled, present=Present, reset=ResetPresentation, ending=EndMission, receive=ReceivePresentation,
            update=UpdatePresentationTransport, isInfo=IsInfo, relay=UpdateInfoRelay,
            play=subtit.Play, timer=StartCockpitTimer, hide=HideCockpitTimer,
            weatherUpdate=UpdateAtmosphere,
            state=function() return localCameraActive, cameraSkipped, receivedEvent end }
    ]]))
    setfenv(chunk, env)
    p.api = chunk(); p.env = env; peers[id] = p
    return p
end
local function count(p, op, first)
    local n = 0
    for _, call in ipairs(p.calls) do
        if call[1] == op and (first == nil or call[2] == first) then n = n + 1 end
    end
    return n
end
local function last(p, op)
    for i = #p.calls, 1, -1 do if p.calls[i][1] == op then return p.calls[i] end end
end
local function deliver(reverse)
    local batch = packets; packets = {}
    for j=1,#batch do
        local packet = batch[reverse and (#batch+1-j) or j]
        for id, p in pairs(peers) do
            if (packet.to == 0 and id ~= packet.from) or packet.to == id then
                p.api.receive(packet.from, packet.kind, unpack(packet.args))
            end
        end
    end
end
local function tick(reverse)
    now = now + 0.25
    for _, p in pairs(peers) do p.api.update() end
    deliver(reverse); deliver()
end
local host, guest = peer(1), peer(2)
local third, fourth = peer(3), peer(4)

-- Starting resources: every owner reserves native capacity (guests start with none).
for team=1,4 do host.api.present("Resources", team, 5, 10) end
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(p.resources.scrap == 5 and p.resources.pilots == 10,
        "every owner receives starting resources despite native capacity clamps")
end
check(host.resources.maxPilots == 15, "starting resources must preserve larger authored capacity")
check(host.resources.scrap == 5 and guest.resources.scrap == 5,
    "a team resource presentation must not write another owner")

-- Audio and cockpit timers are presented to every peer; the leader gets the handle.
check(host.api.play("misn0601.wav") == "audio", "the leader receives the native audio handle")
host.api.timer(540.0, 362.0, 180.0)
host.api.hide()
for _=1,4 do tick() end
for _, p in pairs(peers) do
    check(count(p, "Play", "misn0601.wav") == 1, "every peer hears the narration exactly once")
    local timer = last(p, "StartCockpitTimer")
    check(count(p, "StartCockpitTimer") == 1 and timer[2] == 540 and timer[3] == 362 and timer[4] == 180,
        "every peer starts the cockpit timer once with the stock thresholds")
    check(count(p, "HideCockpitTimer") == 1, "every peer hides the cockpit timer")
end

-- Object camera (wAu1 / sim5 shots): waits for replicas; skips are local.
host.api.ready(); host.api.object("subject", 0, 5000, -5000, "target")
guest.valid.target = false
tick(); tick()
check(not guest.api.state(), "a camera must wait for its native target replica")
check(third.api.state() and fourth.api.state(), "other peers should receive the object film")
guest.valid.target = true; tick()
check(guest.api.state(), "a delayed target should start the film")
guest.cancelOnObject = true; tick()
local active, skipped = guest.api.state()
check(not active and skipped and third.api.state(), "guest skip must be local")
host.cancelOnObject = true; host.api.object("subject", 0, 5000, -5000, "target"); tick()
check(not host.api.state() and third.api.state(), "host skip must keep publishing the film")
check(host.api.cancelled() == false, "net games never surface a skip to the shared mission timing")
host.api.finish(); tick(); tick()
check(not third.api.state() and not fourth.api.state(), "finish snapshot releases every watcher")
third.api.receive(1, "C", 1, 1, "O", "subject", 0, 1, 2, "target"); third.api.update()
check(not third.api.state(), "stale snapshots cannot restart a finished film")

-- Path camera (opening flyover / Hephaestus cam1path): snapshot reaches guests.
host.cancelled, guest.cancelled, host.cancelOnObject, guest.cancelOnObject = false, false, false, false
host.api.ready(); host.api.path("openingcampath", 1000, 500, "target"); tick(); tick()
for _, p in ipairs({guest, third, fourth}) do
    local call = last(p, "CameraPath")
    check(p.api.state() and call and call[2] == "openingcampath" and call[3] == 1000 and call[4] == 500 and call[5] == "target",
        "path camera runs natively on every guest with the leader arguments")
end
check(count(host, "CameraPath") >= 1 and host.api.state(), "the leader runs its own path camera")
host.api.path("openingcampath", 1015, 500, "target"); tick(); tick()
check(last(third, "CameraPath")[3] == 1015, "the latest height replaces earlier snapshots")
guest.cancelled = true; tick()
active, skipped = guest.api.state()
check(not active and skipped and third.api.state() and host.api.state(), "guest path skip must be local")
local guestFrames = count(guest, "CameraPath")
tick(); check(count(guest, "CameraPath") == guestFrames, "a skipped guest stays out until the next film")
guest.cancelled = false
host.cancelled = true; host.api.path("openingcampath", 1030, 500, "target"); tick()
check(not host.api.state() and third.api.state(), "host path skip must keep publishing the film")
host.cancelled = false
host.api.finish(); tick(); tick()
check(not third.api.state() and not fourth.api.state() and not guest.api.state(), "finish snapshot releases path watchers")
host.api.ready(); host.api.path("cam1path", 800, 1000, "target"); tick(); tick()
check(guest.api.state() and last(guest, "CameraPath")[2] == "cam1path", "a new generation clears local skip")
guest.api.receive(3, "C", 999, 99, "", 0, 0, 0); guest.api.update()
check(guest.api.state(), "non-leader camera messages must be ignored")
host.api.finish(); tick(); tick()
guest.valid.target = false
host.api.ready(); host.api.path("cam1path", 800, 1000, "target"); tick(); tick()
check(not guest.api.state() and third.api.state(), "a path camera waits for its native target replica")
guest.valid.target = true
host.api.finish(); tick(); tick()

-- IsInfo is guest UI state: guests relay it, the leader honours it for one second.
check(host.api.isInfo("obheph") == false, "no report means no info")
guest.info.obheph = true
guest.api.relay(); guest.api.relay()
check(#packets == 1 and packets[1].kind == "I" and packets[1].to == 1 and packets[1].args[1] == "obheph",
    "guest relay is throttled and addressed to the leader")
deliver()
check(host.api.isInfo("obheph") == true and host.api.isInfo("sblpad") == false, "leader accepts the report")
guest.info.obheph = false
now = now + 0.9
check(host.api.isInfo("obheph") == true, "report persists within one second")
now = now + 0.2
check(host.api.isInfo("obheph") == false, "report expires after one second")
host.info.sblpad = true
check(host.api.isInfo("sblpad") == true, "the leader own native IsInfo still counts")
host.info.sblpad = false
host.api.receive(2, "I", "bogus"); host.api.receive(9, "I", "obstp1"); host.api.receive(2, "I", 5)
check(not host.api.isInfo("bogus") and not host.api.isInfo("obstp1"), "unknown prefixes and non-players are rejected")
guest.api.receive(3, "I", "obstp3")
check(not guest.api.isInfo("obstp3"), "only the leader records reports")
guest.info.obstp3 = true; now = now + 0.3; guest.api.relay(); deliver()
check(host.api.isInfo("obstp3"), "each of the five prefixes is relayed")

-- Camera snapshots are label-aware and WAIT for the real object; there is no fallback aim.
host.valid.camgeyser, host.labels.camgeyser, host.byLabel.cam_geyser = true, "cam_geyser", "camgeyser"
guest.byLabel.cam_geyser, fourth.byLabel.cam_geyser = nil, nil
third.byLabel.cam_geyser, third.valid["cg@3"] = "cg@3", true
host.api.finish(); tick(); tick()
host.api.ready(); host.api.path("cam1path", 800, 1000, "camgeyser")
tick(); tick(); tick()
check(third.api.state() and last(third, "CameraPath")[5] == "cg@3", "a resolvable label target aims the film at the guest's replica")
check(not guest.api.state() and not fourth.api.state(), "an unresolved target holds the film's start")
for _=1,40 do tick() end -- ten seconds: still the real object or nothing
check(not guest.api.state() and not fourth.api.state(), "the film keeps waiting for the real object")
guest.byLabel.cam_geyser = "cg@2"; guest.valid["cg@2"] = true
tick()
check(guest.api.state() and last(guest, "CameraPath")[5] == "cg@2", "a late-resolving label starts the film aimed at the real object")
fourth.byLabel.cam_geyser, fourth.valid["cg@4"] = "cg@4", true
tick(); check(fourth.api.state() and last(fourth, "CameraPath")[5] == "cg@4", "every guest ends up aimed at its own real replica")
host.api.finish(); tick(); tick()
-- A spawned target that replicates late: waits, then the real handle.
local LATE = 9010
host.valid[LATE] = true
third.valid[LATE], fourth.valid[LATE] = true, true
host.api.ready(); host.api.path("cam1path", 800, 1000, LATE)
tick(); tick()
check(not guest.api.state(), "a spawned target that has not replicated yet holds the film")
guest.valid[LATE] = true; tick()
check(guest.api.state() and last(guest, "CameraPath")[5] == LATE, "the film aims at the real replicated spawn")
host.api.finish(); tick(); tick()
-- The leader reports the target gone: no waiting, plays with what remains valid.
local DOOMED = 9011
host.valid[DOOMED] = true
host.api.ready(); host.api.path("cam1path", 800, 1000, DOOMED)
host.valid[DOOMED] = false
tick(); tick()
check(guest.api.state() and third.api.state(), "a target the leader reports gone must not hold the film")
host.api.finish(); tick(); tick()
-- Never-hang guard: loud log + counter, then the film plays.
local NEVER = 9012
host.valid[NEVER], host.labels[NEVER], host.byLabel.never_cam = true, "never_cam", NEVER
local before = guest.M.coopUnresolved or 0
host.api.ready(); host.api.path("cam1path", 800, 1000, NEVER)
for _=1,40 do tick() end
check(not guest.api.state(), "an unresolvable target still waits inside the safety window")
for _=1,30 do tick() end
-- One timeout, logged once: whichever of the Label event / the film gives up first covers both.
check(guest.api.state() and (guest.M.coopUnresolved or 0) == before + 1, "the never-hang guard lets the film play and counts it")
local loud = false
for _, line in ipairs(guest.printed) do loud = loud or line:find("%[coop%] unresolved camera") ~= nil end
check(loud, "the camera timeout logs a loud [coop] unresolved line")
host.api.finish(); tick(); tick()

-- Object camera (O kind): subject and target resolve by label and the film waits for both.
host.valid.osub, host.labels.osub, host.byLabel.o_sub = true, "o_sub", "osub"
third.byLabel.o_sub, third.valid["os@3"] = "os@3", true
fourth.byLabel.o_sub, fourth.valid["os@4"] = "os@4", true
host.api.ready(); host.api.object("osub", 0, 500, -500, "camgeyser")
tick(); tick(); tick()
check(third.api.state() and last(third, "CameraObject")[2] == "os@3" and last(third, "CameraObject")[6] == "cg@3",
    "an object camera aims at the real subject and target")
check(not guest.api.state(), "an object camera waits for an unresolved subject")
guest.byLabel.o_sub, guest.valid["os@2"] = "os@2", true
tick()
check(guest.api.state() and last(guest, "CameraObject")[2] == "os@2" and last(guest, "CameraObject")[6] == "cg@2",
    "a late-resolving subject starts the object camera on the real objects")
host.api.finish(); tick(); tick()

-- Drop the first event and reorder the retransmission; markers wait for replicas.
-- Real handles are numbers; strings on the wire are map labels.
local MARKER = 9001
guest.valid[MARKER] = false
third.valid[MARKER], fourth.valid[MARKER] = true, true
host.valid[MARKER] = true
host.api.present("SetObjectiveName", MARKER, "Starport")
host.api.present("AddObjective", "misn0606.otf", "white")
host.api.ending("SucceedMission", now, "misn06w1.des")
host.api.update(); packets = {} -- loss
tick(true)
check(count(guest, "SetObjectiveName") == 0 and count(guest, "SucceedMission") == 0,
    "missing replica and out-of-order events must hold the result")
guest.valid[MARKER] = true
for _=1,8 do tick(true) end
check(count(guest, "SetObjectiveName") == 1 and count(guest, "AddObjective") == 1,
    "retries apply ordered events exactly once")
for _, p in pairs(peers) do
    check(count(p, "SucceedMission") == 1, "all four peers must receive exactly one result")
end
-- A map object the engine cannot carry as a handle (the rendezvous geyser, nil on
-- every guest in the live 4-client run) goes by LABEL. Guest clocks are far from the
-- leader's (the old absolute `expires` made a guest drop the marker on first
-- receipt) and the label may resolve late: the marker must still land, in order,
-- exactly once.
local LABEL = "eggeizr1-1_geyser"
host.labels.geyser, host.byLabel[LABEL], host.valid.geyser = LABEL, "geyser", true
guest.clock, third.clock, fourth.clock = 100, -50, 0
third.byLabel[LABEL], fourth.byLabel[LABEL] = "geyser@3", "geyser@4"
third.valid["geyser@3"], fourth.valid["geyser@4"] = true, true
local mark = #guest.calls
host.api.present("SetObjectiveName", "geyser", "5th Platoon")
host.api.present("SetObjectiveOn", "geyser")
host.api.present("AddObjective", "misn0610.otf", "white")
for _=1,4 do tick() end
check(count(host, "SetObjectiveName", "geyser") == 1 and count(host, "SetObjectiveOn", "geyser") == 1,
    "the leader applies its own marker with the real handle")
check(count(third, "SetObjectiveName", "geyser@3") == 1 and count(fourth, "SetObjectiveOn", "geyser@4") == 1,
    "a label resolves per guest whatever the guest clock reads")
check(last(third, "SetObjectiveName")[3] == "5th Platoon", "the objective name survives the label swap")
check(count(guest, "SetObjectiveName", "geyser@2") == 0 and count(guest, "AddObjective", "misn0610.otf") == 0,
    "a label not yet resolvable on a guest holds the stream in order, even with its clock far ahead")
guest.byLabel[LABEL] = "geyser@2"; guest.valid["geyser@2"] = true
for _=1,3 do tick() end
check(count(guest, "SetObjectiveName", "geyser@2") == 1 and count(guest, "SetObjectiveOn", "geyser@2") == 1 and
    count(guest, "AddObjective", "misn0610.otf") == 1, "a late-resolving marker lands once, before the next event")
check(count(third, "SetObjectiveOn", "geyser@3") == 1, "retransmission never double-applies")

-- An object with no map label still travels as a plain handle (unchanged path).
local DYN = 9002
host.valid[DYN] = true
for _, p in ipairs({guest, third, fourth}) do p.valid[DYN] = true end
host.api.present("SetUserTarget", DYN); for _=1,4 do tick() end
check(count(guest, "SetUserTarget", DYN) == 1, "unlabelled objects keep the plain handle path")
-- A label only the leader knows (SetLabel on a spawned, replicated object): guests that cannot
-- resolve the label use the replicated handle sent beside it.
local SPAWNED = 9003
host.labels[SPAWNED], host.byLabel.leader_only, host.valid[SPAWNED] = "leader_only", SPAWNED, true
for _, p in ipairs({guest, third, fourth}) do p.valid[SPAWNED] = true end
host.api.present("SetObjectiveOn", SPAWNED); for _=1,4 do tick() end
check(count(guest, "SetObjectiveOn", SPAWNED) == 1 and count(fourth, "SetObjectiveOn", SPAWNED) == 1,
    "a leader-only label falls back to the replicated handle")

-- Genuinely gone: a marker whose target the leader reports gone is skipped without waiting,
-- and an Off for a label nobody can resolve never holds the stream.
host.valid.doomed, host.labels.doomed, host.byLabel.doomed_lbl = true, "doomed_lbl", "doomed"
host.api.present("SetObjectiveOn", "doomed"); host.valid.doomed = false
host.api.present("AddObjective", "misn06111.otf", "white")
host.api.present("SetObjectiveOff", "never_seen")
host.api.present("AddObjective", "misn06112.otf", "white")
for _=1,6 do tick() end
for _, p in ipairs({guest, third, fourth}) do
    check(count(p, "SetObjectiveOn", "doomed") == 0, "a marker the leader reports gone is skipped")
    check(count(p, "AddObjective", "misn06111.otf") == 1 and count(p, "AddObjective", "misn06112.otf") == 1,
        "the stream resumes right after a gone marker")
end

-- A marker waits for the real object past any short window; only the 15 s guard ends it.
local STUCK = 9020
host.valid[STUCK], host.labels[STUCK], host.byLabel.stuck_lbl = true, "stuck_lbl", STUCK
local before = guest.M.coopUnresolved or 0
host.api.present("SetObjectiveOn", STUCK)
host.api.present("AddObjective", "misn06113.otf", "white")
for _=1,32 do tick() end -- 8 s
check(count(guest, "AddObjective", "misn06113.otf") == 0, "an unresolved marker keeps the stream waiting well past 5 s")
for _=1,36 do tick() end
check(count(guest, "AddObjective", "misn06113.otf") == 1 and count(guest, "SetObjectiveOn", STUCK) == 0,
    "the safety guard drops only the stale marker")
check((guest.M.coopUnresolved or 0) == before + 1, "the timeout is counted for the harness probe")
local loud = false
for _, line in ipairs(guest.printed) do loud = loud or line:find("%[coop%] unresolved stuck_lbl") ~= nil end
check(loud, "the timeout logs a loud [coop] unresolved line")

-- A spawned object nobody labelled gets a deterministic unique label from the leader, and a
-- Label event makes the guests carry it before the marker that uses it.
local SPAWN = 9021
host.valid[SPAWN] = true
for _, p in ipairs({guest, third, fourth}) do p.valid[SPAWN] = true end
host.api.present("SetObjectiveOn", SPAWN); for _=1,4 do tick() end
local label = host.labels[SPAWN]
check(type(label) == "string" and label:find("^crco_") ~= nil, "the leader labels an unlabelled spawned target")
for _, p in ipairs({guest, third, fourth}) do
    check(count(p, "SetLabel", SPAWN) == 1 and last(p, "SetLabel")[3] == label, "each guest carries the leader's label")
    check(count(p, "SetObjectiveOn", SPAWN) == 1, "the marker lands on the real replicated object")
end
-- Late-replicating spawn: Label and marker wait, then both land on the real handle.
local LATESPAWN = 9022
host.valid[LATESPAWN] = true
host.api.present("SetObjectiveOn", LATESPAWN)
for _=1,6 do tick() end
check(count(guest, "SetLabel", LATESPAWN) == 0 and count(guest, "SetObjectiveOn", LATESPAWN) == 0,
    "a spawn that has not replicated holds its Label and marker")
guest.valid[LATESPAWN] = true
for _=1,4 do tick() end
check(count(guest, "SetLabel", LATESPAWN) == 1 and count(guest, "SetObjectiveOn", LATESPAWN) == 1,
    "the Label and the marker apply to the real object once it replicates")
-- ResetPresentation must reset the real camera/label locals (declared above it), not leak
-- globals: a mid-wait reset on a guest clears the wait state without touching _G.
fourth.api.receive(1, "C", 700000, 77, "P", "cam1path", 800, 1000, "@9999@never_declared")
now = now + 0.25; fourth.api.update()
fourth.api.reset()
for _, name in ipairs({"cameraWaitSince", "cameraGaveUp", "cameraLast", "announced", "gaveUp", "pendingSeq"}) do
    check(rawget(fourth.env, name) == nil and rawget(_G, name) == nil, "ResetPresentation leaked global " .. name)
end
fourth.api.receive(1, "C", 700001, 77, "P", "cam1path", 800, 1000, "@9999@never_declared")
now = now + 0.25; fourth.api.update()
check(not fourth.api.state(), "an unresolved camera still waits after a presentation reset")
print("misn06 path/object-camera, timer, IsInfo relay, replica wait, local skip and ordered result checks passed: " .. checks)

-- Actual story helper + actual ordered presentation adapter on four peers.
packets={}
host,guest,third,fourth=peer(1),peer(2),peer(3),peer(4)
host.M.starportreconed=true; host.weather.level=3
host.api.weatherUpdate(0.1)
for _=1,12 do tick() end
for _,p in pairs(peers) do
    p.api.weatherUpdate(0.1)
    check(p.weather.target==3,'every peer receives host story target')
    check(p.weather.level==3,'every peer receives host actual weather rung')
    check(p.weather.automatic==(p==host),'only host runs automatic weather ladder')
    check(count(p,'WeatherUpdate')>0 and count(p,'EnvironmentUpdate')>0,'all peers compose weather and Environment')
end
-- A guest cannot use the weather presentation operations to change the leader.
host.api.receive(2,'E',900001,'WeatherTarget',15,5)
check(host.weather.target==3,'guest cannot dictate host weather')
print('misn06 four-peer weather target, rung authority and renderer-update wiring passed')

host.api.present('RocketFX',10,77,30,0)
for _=1,8 do tick() end
for _,p in pairs(peers)do
    check(count(p,'RocketFX')==1,'every peer receives rocket translation and FX exactly once')
    local call=last(p,'RocketFX')
    check(call[2]==10 and call[3]==77 and call[4]==30 and call[5]==0,'primitive launch payload preserved')
end
host.api.present('RocketFXStop')
for _=1,8 do tick() end
for _,p in pairs(peers)do check(count(p,'RocketFXStop')==1,'every peer stops rocket FX')end
host.api.receive(2,'E',900002,'RocketFX',15,0,0,0,0)
check(count(host,'RocketFX')==1,'guest cannot dictate shared rocket flight')
print('misn06 four-peer rocket event/FX relay checks passed')
