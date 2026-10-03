-- Run from the repository root: lua5.1 Tools/Test-Misn18.lua
-- Engine fakes exercise source mission decisions; native rendering/AI and the
-- engine's save serializer still need in-game validation.
assert(_VERSION == "Lua 5.1", "run these checks with Lua 5.1")
local script = arg[1] or "Scripts/misn18.lua"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function NewMission()
    local w = {time = 0, serial = 0, objects = {}, labels = {}, calls = {},
        distances = {}, cameraDone = {}, audioDone = false, cancelled = false,
        objectives = 0, nearest = nil, timer = nil}
    local e = setmetatable({}, {__index = _G})
    local function Record(name, ...)
        w.calls[#w.calls + 1] = {name = name, args = {...}}
    end
    local function Object(odf)
        w.serial = w.serial + 1
        w.objects[w.serial] = {alive = true, odf = odf}
        return w.serial
    end
    function w:Count(name, first)
        local n = 0
        for _, c in ipairs(self.calls) do
            if c.name == name and (first == nil or c.args[1] == first) then n = n + 1 end
        end
        return n
    end
    function w:Last(name)
        for i = #self.calls, 1, -1 do
            if self.calls[i].name == name then return self.calls[i].args end
        end
    end
    function w:Near(h, target, distance)
        self.distances[tostring(h) .. ":" .. tostring(target)] = distance
    end
    function w:Kill(h) self.objects[h].alive = false end
    function w:Remove(h) self.objects[h] = nil end
    function w:Advance(time) self.time = time; e.Update(0.05) end
    e.GetTime = function() return w.time end
    e.GetHandle = function(label)
        if not w.labels[label] then w.labels[label] = Object("map") end
        return w.labels[label]
    end
    w.player = e.GetHandle("player")
    e.GetPlayerHandle = function(...) assert(select("#", ...) == 0); return w.player end
    e.IsValid = function(h) return h ~= nil and w.objects[h] ~= nil end
    e.IsAlive = function(h) return e.IsValid(h) and w.objects[h].alive end
    e.GetDistance = function(h, target)
        assert(e.IsValid(h), "invalid distance origin reached native Lua API")
        assert(type(target) == "string" or e.IsValid(target), "invalid distance destination")
        return w.distances[tostring(h) .. ":" .. tostring(target)] or 10000
    end
    e.GetNearestEnemy = function(h)
        assert(e.IsValid(h)); Record("GetNearestEnemy", h); return w.nearest
    end
    e.AudioMessage = function(file)
        Record("AudioMessage", file); return {audio = file}
    end
    e.IsAudioMessageDone = function(msg) assert(msg and msg.audio); return w.audioDone end
    e.StopAudioMessage = function(msg) assert(msg and msg.audio); Record("StopAudioMessage", msg) end
    e.CameraCancelled = function() return w.cancelled end
    e.CameraPath = function(path, ...)
        Record("CameraPath", path, ...); return w.cameraDone[path] == true
    end
    e.BuildObject = function(odf, team, where)
        local h = Object(odf); Record("BuildObject", odf, team, where, h); return h
    end
    e.RemoveObject = function(h)
        assert(e.IsValid(h)); w:Remove(h); Record("RemoveObject", h)
    end
    e.AddHealth = function(h, amount)
        assert(e.IsAlive(h)); Record("AddHealth", h, amount)
    end
    e.Damage = function(h, amount)
        -- Native damage is harmless if the hull was destroyed independently.
        if e.IsValid(h) then w:Kill(h) end
        Record("Damage", h, amount)
    end
    e.StartCockpitTimer = function(time, warn, alert)
        w.timer = {start = w.time, duration = time}; Record("StartCockpitTimer", time, warn, alert)
    end
    e.GetCockpitTimer = function()
        return w.timer and math.max(0, w.timer.duration - (w.time - w.timer.start)) or 0
    end
    e.ClearObjectives = function() w.objectives = 0; Record("ClearObjectives") end
    e.AddObjective = function(file, color)
        assert(color == "white" or color == "green")
        w.objectives = w.objectives + 1
        assert(w.objectives <= 10, "objective buffer overflow")
        Record("AddObjective", file, color)
    end
    for _, name in ipairs({"SetScrap", "SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff",
        "StartEarthquake", "UpdateEarthQuake", "CameraReady", "CameraFinish", "CameraObject",
        "Goto", "SetIndependence", "Attack", "FailMission", "SucceedMission"}) do
        local api = name
        e[api] = function(...) Record(api, ...) end
    end
    setfenv(assert(loadfile(script)), e)()
    e.Start()
    w.state = e.Save()
    e.Update(0.05)
    return e, w, w.state
end

local function DestroyThrusters(e, w, m)
    for _, name in ipairs({"thrusterone", "thrustertwo", "thrusterthree", "thrusterfour"}) do
        w:Kill(m[name])
    end
    e.Update(0.05)
end

local e, w, m = NewMission()
Check(m.missionstart and m.avrec == w.labels.avrecy2_recycler, "first-frame map initialization")
Check(m.transport == w.labels.hbtran0038_i76building and m.thrusterfour == w.labels.hbtrn20052_i76building,
    "original transport/thruster labels")
Check(w:Last("SetObjectiveName")[2] == "Home Base" and w:Last("SetScrap")[2] == 80, "name and starting resources")
Check(m.rand1 == 150 and m.rand2 == 230 and m.rand3 == 310 and m.gettosavtrans == 600, "initial deadlines")
Check(m.next_second == 5 and m.enemycheck == 3 and m.quake_level == 2 and m.quake_check == 2,
    "healing, enemy poll, and earthquake setup")
Check(m.x == 5980 and m.camera1 and w:Last("CameraPath")[1] == "opencam3", "opening starts on source camera three")
Check(w:Count("StartEarthquake", 2) == 1 and w:Count("UpdateEarthQuake") == 0, "cut earthquake modulation stays disabled")
Check(w:Count("BuildObject") == 0 and not m.transportfound, "nil enemy does not discover transport")
e.Update(0.05)
Check(w:Count("AudioMessage", "misn1801.wav") == 1 and w:Count("SetScrap") == 1, "first-frame effects latch")
w:Advance(3)
Check(w:Count("GetNearestEnemy") == 0, "enemy poll strict boundary")
w:Advance(3.1)
Check(w:Count("GetNearestEnemy") == 1 and m.enemy == nil and not m.transportfound, "nil enemy poll is safe")

-- Cameras advance in native block order; camera two/three can complete together.
e, w, m = NewMission()
w.cameraDone.opencam3 = true; e.Update(0.05)
Check(m.camera2 and not m.camera1 and w:Last("CameraPath")[1] == "opencam3", "first shot schedules second on next update")
w.cameraDone.opencam1 = true; w.cameraDone.opencam2 = true; e.Update(0.05)
Check(not m.camera2 and not m.camera3 and w:Count("RemoveObject") == 2, "later shots chain and remove both camera objects")
Check(not m.openingcindone, "path completion still waits for opening audio")
w.audioDone = true; e.Update(0.05)
Check(m.openingcindone and w:Count("CameraFinish") == 1 and w:Count("StopAudioMessage") == 1, "audio finishes cinematic")
e.Update(0.05); Check(w:Count("CameraFinish") == 1, "opening cinematic ends once")
e, w, m = NewMission()
w.cancelled = true; e.Update(0.05)
Check(m.openingcindone and not m.camera1 and not m.camera2 and not m.camera3, "cancel clears camera flags")
Check(w:Count("RemoveObject") == 0 and w:Count("StopAudioMessage") == 1, "cancel preserves native camera-object cleanup behavior")

-- Each of the twelve approach/alternate/shortcut triggers retains its threshold.
for wave = 1, 3 do
    for _, route in ipairs({{"spawn", 100}, {"spawnalt", 100}, {"cheat", 200}, {"cheatalt", 200}}) do
        e, w, m = NewMission()
        local path = route[1] .. wave .. "a"
        w:Near(m.player, path, route[2]); e.Update(0.05)
        Check(w:Count("BuildObject") == 0, "approach strict boundary: " .. path)
        w:Near(m.player, path, route[2] - 1); e.Update(0.05)
        Check(m["wave" .. wave .. "start"] and w:Count("BuildObject", "hvsat") == 2,
            "approach spawns both route units: " .. path)
        local builds = {}
        for _, c in ipairs(w.calls) do if c.name == "BuildObject" then builds[#builds + 1] = c.args end end
        Check(builds[1][2] == 2 and builds[1][3] == "spawn" .. wave .. "b" and
            builds[2][3] == "spawnalt" .. wave .. "b", "approach source spawn paths")
        Check(w:Count("Goto") == 2 and w:Last("Goto")[2] == "transport" .. (wave * 2) and
            w:Count("SetIndependence") == 2, "approach orders and independence")
        e.Update(0.05); Check(w:Count("BuildObject") == 2, "approach waves latch")
    end
end

e, w, m = NewMission()
for index, deadline in ipairs({150, 230, 310}) do
    w:Advance(deadline)
    Check(not m["rand" .. index .. "brk"], "timed reinforcements use strict boundary")
    w:Advance(deadline + 0.1)
    Check(m["rand" .. index .. "brk"] and w:Last("Goto")[2] == "transport" .. (6 + index),
        "timed reinforcement route")
end
Check(w:Count("BuildObject", "hvsav") == 3, "three timed reinforcements")
w:Advance(400); Check(w:Count("BuildObject", "hvsav") == 3, "timed waves latch")
e, w, m = NewMission(); w:Advance(311)
Check(m.rand1brk and m.rand2brk and m.rand3brk, "hitch crosses all reinforcement deadlines")

-- Discovery can be caused by the player or a live nearest enemy, even off route.
e, w, m = NewMission()
w:Near(m.player, "transfound", 100); e.Update(0.05)
Check(not m.transportfound, "player discovery strict boundary")
w:Near(m.player, "transfound", 99); e.Update(0.05)
Check(m.transportfound and m.savattack == 180, "player discovery schedules pressure wave")
Check(w:Count("BuildObject", "hvsat") == 6 and w:Count("SetObjectiveOff", m.transport) == 1,
    "discovery fills all missing approach waves and hides hull marker")
Check(w:Count("SetObjectiveOn") == 5, "all four live thrusters marked")
e.Update(0.05)
Check(w:Last("AddObjective")[1] == "misn1802.otf" and w:Last("AddObjective")[2] == "white", "destroy-thrusters objective")
e, w, m = NewMission()
w.nearest = e.BuildObject("hvsat", 2, "enemy-test")
w:Near(w.nearest, m.transport, 200); w:Advance(3.1)
Check(not m.transportfound, "enemy discovery strict boundary")
w:Near(w.nearest, m.transport, 199); e.Update(0.05)
Check(m.transportfound and m.savattack == 183.1, "cached enemy triggers discovery between polls")
e, w, m = NewMission()
w.nearest = e.BuildObject("hvsat", 2, "enemy-test"); w:Advance(3.1)
w:Remove(w.nearest); e.Update(0.05)
Check(not m.transportfound, "removed cached enemy does not reach native distance query")

-- Shared healing cadence is preserved, including the per-update hull repair.
e, w, m = NewMission(); w:Advance(5)
Check(w:Count("AddHealth") == 0, "healing strict initial boundary")
w:Advance(5.1)
Check(w:Count("AddHealth", m.transport) == 1 and w:Count("AddHealth") == 5 and m.next_second == 6.1,
    "undiscovered hull and four thrusters heal together")
w:Advance(6.1); Check(w:Count("AddHealth") == 5, "healing strict repeat boundary")
w:Near(m.player, "transfound", 99); w:Advance(6.2)
Check(w:Count("AddHealth") == 10 and m.next_second == 7.2, "healing precedes discovery in same update")
w:Advance(7.3); e.Update(0.05)
Check(w:Count("AddHealth", m.transport) == 4 and w:Count("AddHealth", m.thrusterone) == 2 and m.next_second == 7.2,
    "found hull heals every update while thrusters stop")

-- Source pressure wave requires discovery plus 180 seconds, then all four dead.
e, w, m = NewMission(); w:Near(m.player, "transfound", 99); e.Update(0.05)
w:Advance(180); Check(not m.savwaves, "pressure-wave strict boundary")
w:Advance(180.1)
Check(m.savwaves and w:Count("Attack") == 4, "four fighters attack recycler")
Check(w:Last("Attack")[2] == m.avrec, "pressure-wave target is the original recycler")
w:Kill(m.fury1); e.Update(0.05)
Check(w:Count("Attack") == 4, "partial wave loss does not respawn")
for index = 2, 4 do w:Kill(m["fury" .. index]) end
e.Update(0.05); Check(w:Count("Attack") == 8, "all four lost replaces wave")
DestroyThrusters(e, w, m)
for index = 1, 4 do w:Kill(m["fury" .. index]) end
e.Update(0.05)
Check(w:Count("Attack") == 12 and m.transdestroyed, "already-enabled wave continues after transport destruction")
e, w, m = NewMission(); w:Near(m.player, "transfound", 99); e.Update(0.05)
DestroyThrusters(e, w, m); w:Advance(181)
Check(not m.savwaves and w:Count("Attack") == 0, "early destruction prevents pressure-wave activation")

-- Thruster voice/count state remains latched; simultaneous losses skip counts.
e, w, m = NewMission()
for index, name in ipairs({"thrusterone", "thrustertwo", "thrusterthree"}) do
    w:Kill(m[name]); e.Update(0.05)
    Check(m.z == index and w:Count("AudioMessage", "misn18" .. (12 + index) .. ".wav") == 1,
        "sequential thruster progress voice")
    e.Update(0.05); Check(m.z == index, "thruster counted once")
end
w.time = 10; w:Kill(m.thrusterfour); e.Update(0.05)
Check(m.transdestroyed and m.z == 4 and w:Count("StartCockpitTimer", 180) == 1, "four losses start escape timer once")
Check(w:Last("StartCockpitTimer")[2] == 120 and w:Last("StartCockpitTimer")[3] == 30 and
    m.hurry1 == 70 and m.hurry2 == 95 and m.hurry3 == 125 and m.hurry4 == 150, "escape warning thresholds")
Check(w:Count("Damage") == 0 and not m.transblownup, "hull destruction deferred by source block order")
e.Update(0.05)
Check(m.transblownup and w:Count("Damage", m.transport) == 1 and m.quake_level == 6, "hull damaged on following update")
Check(w:Count("StartEarthquake") == 1 and w:Count("UpdateEarthQuake") == 0, "quake level six remains dormant with cut modulation")
Check(w:Last("AddObjective")[1] == "misn1801.otf", "undiscovered demolition keeps source extra approach objective")
for index, deadline in ipairs({70, 95, 125, 150}) do
    w:Advance(deadline)
    Check(w:Count("AudioMessage", "misn18" .. string.format("%02d", 8 + index) .. ".wav") == 0,
        "hurry voice strict boundary")
    w:Advance(deadline + 0.1)
    Check(w:Count("AudioMessage", "misn18" .. string.format("%02d", 8 + index) .. ".wav") == 1,
        "hurry voice occurs once")
end
e, w, m = NewMission(); DestroyThrusters(e, w, m)
Check(m.z == 4 and not m.message1 and not m.message2 and not m.message3, "simultaneous losses preserve skipped progress voices")

-- Wrong-route warning gates the three ambushes; both return entries share one wave.
e, w, m = NewMission(); DestroyThrusters(e, w, m)
w:Near(m.player, "dontgo1", 99); e.Update(0.05)
Check(not m.dg1, "ambush requires wrong-route warning")
w:Near(m.player, "dontgo", 50); e.Update(0.05)
Check(not m.dontgo, "wrong-route warning strict boundary")
w:Near(m.player, "dontgo", 49); e.Update(0.05)
Check(m.dontgo and m.dg1 and w:Count("AudioMessage", "misn1805.wav") == 1, "wrong-route warning and first ambush")
for index = 2, 3 do
    w:Near(m.player, "dontgo" .. index, 100); e.Update(0.05)
    Check(not m["dg" .. index], "ambush strict boundary")
    w:Near(m.player, "dontgo" .. index, 99); e.Update(0.05)
    Check(m["dg" .. index], "remaining wrong-route ambush")
end
Check(w:Count("BuildObject", "hvsat") == 3 and w:Count("BuildObject", "hvsav") == 3 and w:Count("Goto") == 0,
    "ambush source composition and uncommanded behavior")
for _, path in ipairs({"return1", "return2"}) do
    e, w, m = NewMission()
    w:Near(m.player, path, 99); e.Update(0.05)
    Check(not m.returnwave, "return wave requires demolition")
    DestroyThrusters(e, w, m)
    Check(m.returnwave and w:Count("BuildObject", "hvsat") == 1 and m.sav2 == nil and m.sav3 == nil,
        "both return routes spawn only the single active source unit")
    e.Update(0.05); Check(w:Count("BuildObject") == 1, "return wave latches")
end

-- All three failures and victory preserve their delays, files, and boundaries.
e, w, m = NewMission(); w:Advance(600)
Check(not m.fail1, "approach timeout strict ten-minute boundary")
w:Advance(600.1)
Check(m.fail1 and w:Last("FailMission")[1] == 605.1 and w:Last("FailMission")[2] == "misn18l1.des",
    "approach timeout description and five-second delay")
e.Update(0.05); Check(w:Count("FailMission") == 1, "approach failure latches")
e, w, m = NewMission(); DestroyThrusters(e, w, m); w:Near(m.player, m.avrec, 401)
w:Advance(179.9); Check(not m.fail2, "escape fails only when countdown expires")
w:Advance(180)
Check(m.fail2 and m.blastoff and m.y == 2000 and w:Last("FailMission")[1] == 187 and
    w:Last("FailMission")[2] == "misn18l2.des", "missed escape camera and seven-second failure")
e.Update(0.05); Check(m.y == 2500 and w:Count("FailMission") == 1, "blastoff rises per update and failure latches")
for _, distance in ipairs({200, 300, 400}) do
    e, w, m = NewMission(); DestroyThrusters(e, w, m); w:Near(m.player, m.avrec, distance); w:Advance(180)
    Check(not m.fail2 and not m.missionwon, "source neutral escape distance band: " .. distance)
end
e, w, m = NewMission(); w:Near(m.player, m.avrec, 199); e.Update(0.05)
Check(not m.missionwon, "arrival alone cannot win before demolition")
DestroyThrusters(e, w, m)
Check(m.missionwon and m.fail2 and w:Last("SucceedMission")[1] == 12, "return after demolition wins with twelve-second delay")
e.Update(0.05)
Check(w:Last("AddObjective")[1] == "misn1801.otf" and w.objectives == 3, "undiscovered victory retains independent approach-objective block")
w:Advance(141); Check(w:Count("AudioMessage", "misn1809.wav") == 0 and w:Count("SucceedMission") == 1, "victory suppresses hurry voices and latches")
e, w, m = NewMission(); w:Near(m.player, "transfound", 99); e.Update(0.05)
DestroyThrusters(e, w, m); w:Near(m.player, m.avrec, 199); w:Advance(10); e.Update(0.05)
Check(w.objectives == 2 and w:Last("AddObjective")[1] == "misn1802.otf" and w:Last("AddObjective")[2] == "green",
    "normal victory shows two green objectives")
e, w, m = NewMission(); w:Kill(m.avrec); w:Advance(10)
Check(m.fail3 and w:Last("FailMission")[1] == 17 and w:Last("FailMission")[2] == "misn18l3.des" and
    w:Count("AudioMessage", "misn1704.wav") == 1, "recycler loss retains source failure and mission-17 audio")
e.Update(0.05); Check(w:Count("FailMission") == 1, "recycler-loss failure latches")
e, w, m = NewMission(); w:Remove(m.avrec); e.Update(0.05)
Check(m.fail3 and not m.missionwon, "removed recycler is safe in all distance checks")

-- Save/load uses a copied table to ensure restored values drive later updates.
e, w, m = NewMission(); w:Near(m.player, "transfound", 99); e.Update(0.05)
local saved = {}; for key, value in pairs(e.Save()) do saved[key] = value end
local briefing, scrap = w:Count("AudioMessage", "misn1801.wav"), w:Count("SetScrap")
e.Start(); e.Load(saved); w:Advance(180.1)
Check(e.Save() == saved and saved ~= m and saved.transportfound and saved.savwaves,
    "Load restores flags and pressure-wave deadline without Setup")
Check(saved.aud1 == m.aud1 and saved.transport == m.transport and saved.enemycheck == m.enemycheck,
    "Load retains audio token, object handles, and poll timer")
Check(w:Count("AudioMessage", "misn1801.wav") == briefing and w:Count("SetScrap") == scrap, "Load does not replay startup")
Check(saved.wave4start == false and saved.w6u4 == nil and saved.explosions == 99999 and saved.message4 == false,
    "unused source state remains available for cut-content reconstruction")

print("Misn18: " .. checks .. " Lua 5.1 host checks passed")
