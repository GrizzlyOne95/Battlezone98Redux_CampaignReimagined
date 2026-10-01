-- Run from the repository root: lua5.1 Tools/Test-Misn06.lua
-- Stock API host fakes test mission decisions, not native AI/camera rendering.
assert(_VERSION == "Lua 5.1", "use Lua 5.1")
local script = arg[1] or "Scripts/misn06.lua"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function NewMission()
    local w = { time = 0, objects = {}, calls = {}, distances = {}, info = {},
        audioDone = true, cancelled = false, nextId = 0, objectives = 0 }
    local e = setmetatable({}, { __index = _G })
    local function Object(label, odf)
        w.nextId = w.nextId + 1
        local h = { id = label or ("spawn" .. w.nextId), alive = true, odf = odf,
            pos = { x = 10000 + w.nextId * 1000, y = 20, z = 0 } }
        w.objects[h.id] = h
        return h
    end
    w.player = Object("player", "avtank")
    w.player.pos.x = 0
    local function Record(name, ...)
        w.calls[#w.calls + 1] = { name = name, args = {...} }
    end
    function w:Count(name, first)
        local n = 0
        for _, c in ipairs(self.calls) do
            if c.name == name and (first == nil or c.args[1] == first) then n = n + 1 end
        end
        return n
    end
    function w:Distance(a, b, d)
        local aid, bid = a.id, type(b) == "string" and b or b.id
        self.distances[aid .. ":" .. bid] = d
        self.distances[bid .. ":" .. aid] = d
    end
    e.GetTime = function() return w.time end
    e.GetPlayerHandle = function(...) assert(select("#", ...) == 0); return w.player end
    e.GetHandle = function(label)
        Check(not label:find("M%.", 1), "map labels are literal source labels")
        return w.objects[label] or Object(label)
    end
    e.IsValid = function(h) return type(h) == "table" and h.id ~= nil and h.alive end
    e.IsAlive = e.IsValid
    e.IsOdf = function(h, odf)
        assert(e.IsValid(h), "do not query a destroyed object's ODF")
        return h.odf == odf
    end
    e.GetPosition = function(h)
        assert(e.IsValid(h)); return { x = h.pos.x, y = h.pos.y, z = h.pos.z }
    end
    e.SetPosition = function(h, p) h.pos = p; Record("SetPosition", h, p) end
    e.GetNearestEnemy = function(h) assert(e.IsValid(h)); return h.enemy end
    e.GetDistance = function(a, b)
        assert(e.IsValid(a), "invalid origin reached native distance query")
        assert(type(b) == "string" or e.IsValid(b), "invalid destination")
        local bid = type(b) == "string" and b or b.id
        return w.distances[a.id .. ":" .. bid] or 10000
    end
    e.AudioMessage = function(file)
        Record("AudioMessage", file)
        return { audio = file }
    end
    e.IsAudioMessageDone = function(msg) assert(msg and msg.audio); return w.audioDone end
    e.StopAudioMessage = function(msg) assert(msg and msg.audio); Record("StopAudioMessage", msg) end
    e.IsInfo = function(odf) return w.info[odf] == true end
    e.CameraCancelled = function() return w.cancelled end
    e.BuildObject = function(odf, team, where)
        local h = Object(nil, odf)
        h.team = team
        Record("BuildObject", odf, team, where, h)
        e.AddObject(h) -- native creation may invoke this synchronously
        return h
    end
    e.RemoveObject = function(h)
        assert(e.IsValid(h)); h.alive = false; Record("RemoveObject", h)
    end
    e.ClearObjectives = function() w.objectives = 0; Record("ClearObjectives") end
    e.AddObjective = function(file, color)
        assert(color == "white" or color == "green")
        w.objectives = w.objectives + 1
        assert(w.objectives <= 10, "objective buffer overflow")
        Record("AddObjective", file, color)
    end
    for _, name in ipairs({"SetObjectiveName", "SetObjectiveOn", "SetObjectiveOff",
        "SetScrap", "Defend", "AddHealth", "Patrol", "Attack", "SetIndependence",
        "CameraReady", "CameraPath", "CameraObject", "CameraFinish", "Goto",
        "StartCockpitTimer", "StopCockpitTimer", "HideCockpitTimer",
        "FailMission", "SucceedMission"}) do
        local api = name
        e[api] = function(...) Record(api, ...) end
    end
    setfenv(assert(loadfile(script)), e)()
    e.Start()
    e.Update(0)
    w.state = e.Save()
    return e, w, w.state
end

local e, w, m = NewMission()
Check(m.corbettalive and m.fifthplatoon, "source setup enables Corbett and 5th Platoon")
Check(m.haephestus.pos.y == 20 and w:Count("SetPosition") == 0, "DLL source leaves Hephestus placement unchanged")
Check(m.turret.id == "turret" and m.svu1.id == "svu1", "uncorrupted source labels")
Check(m.opencamtime == 28 and w:Count("SetScrap", 1) == 1, "opening timing and resources")
Check(w:Count("BuildObject") == 0, "absent enemy/handles do not spawn patrols or platoon")
w.time = 28; w.audioDone = false; e.Update(0.1)
Check(m.opencamdone, "opening uses strict 28-second deadline")
w.time = 28.1; e.Update(0.1)
Check(not m.opencamdone and not m.p5u3.alive, "opening completes and removes staged units")
Check(w:Count("AudioMessage", "misn0601.wav") == 1, "opening initialization is one-shot")

e, w, m = NewMission()
w.cancelled = true; e.Update(0.1)
Check(not m.opencamdone and w:Count("CameraFinish") >= 1, "opening can be cancelled")

-- All four native rand()%4 patrol/extraction choices remain reachable.
for choice = 0, 3 do
    e, w, m = NewMission()
    m.patrol1start = choice; m.patrol2start = choice; m.patrol3start = choice
    m.extractpoint = choice
    m.turret.enemy = w.player; w:Distance(m.turret, w.player, 199)
    e.Update(0.1)
    Check(m.trigger1 and m.startpat1 and m.startpat2 and m.startpat3, "patrol trigger fires once")
    for n = 1, 3 do
        local h = m["pu1p" .. n]
        Check(h.odf == (choice == 2 and "svtank" or "svfigh"), "source patrol unit choice")
        h.enemy = w.player; w:Distance(h, w.player, 449)
    end
    w.time = 31; e.Update(0.1)
    Check(m.patrol1spawned and m.patrol2spawned and m.patrol3spawned, "patrol reinforcements use enemy distance")
    local builds = w:Count("BuildObject"); e.Update(0.1)
    Check(w:Count("BuildObject") == builds, "patrol reinforcement latches")
    m.pickupset = true; e.Update(0.1)
    local last
    for _, c in ipairs(w.calls) do if c.name == "BuildObject" then last = c end end
    Check(last.args[3] == "bugout" .. (choice + 1), "random extraction path is preserved")
end

e, w, m = NewMission()
w:Distance(m.player, m.haephestus, 999); w.audioDone = false; e.Update(0.1)
Check(m.haephestusdisc and not m.loopbreaker, "discovery waits for narration")
w.time = 10; w.audioDone = true; e.Update(0.1)
Check(m.hephdisctime == 60, "DLL approach deadline begins at discovery")
w:Distance(m.player, m.haephestus, 124); w.audioDone = false; e.Update(0.1)
Check(m.cam1done and m.identtime == 30, "DLL identity deadline begins at cinematic entry")
w.time = 30; w.audioDone = true; e.Update(0.1)
Check(not m.cam1done and m.identtime == 30, "cinematic completion preserves DLL identity deadline")
w.info.obheph = true; e.Update(0.1)
Check(m.hephikey and m.processtime == 35, "Hephestus info starts five-second processing")
w.time = 35; e.Update(0.1); Check(not m.neworders, "strict native timer comparison")
w.time = 35.1; e.Update(0.1)
Check(m.neworders and m.starportcam and m.discstar == 115.1, "processing creates starport beacon")
w.info.obstp1 = true; w.info.obstp8 = true; e.Update(0.1)
Check(not m.starportreconed, "all three starport types required")
w.info.obstp3 = true; e.Update(0.1)
Check(m.starportreconed and m.star, "three info scans finish recon and queued orders")
m.wAu1.alive = false; m.wAu2.alive = false; e.Update(0.1)
Check(m.ccapullout and m.transportarrive == w.time + 50, "defeated escorts schedule transport")
Check(m.wave1 == w.time + 60 and m.wave2 == w.time + 180 and m.wave3 == w.time + 300,
    "three wave delays match source")
w.time = m.transportarrive + 0.1; e.Update(0.1)
Check(m.lprecon and m.platoonarrive == w.time + 1410, "transport loss sets native pursuit deadline")
Check(w:Count("StartCockpitTimer", 540) == 1, "stock 540/360/180 timer starts")
w.time = m.wave3 + 0.1; e.Update(0.1)
Check(m.wave1start and m.wave2start and m.wave3start, "hitch crosses all three waves in source order")
Check(w:Count("BuildObject", "svtank") == 3, "each attack wave has one tank")
w.info.sblpad = true; e.Update(0.1)
Check(m.bugout and m.launchpadreconed, "launchpad info enables extraction")
w.time = m.time1 + 0.1; e.Update(0.1)
Check(m.bustout and m.pickupreached and m.dustoffcam, "early escape creates pickup beacon")
w:Distance(m.player, m.dustoffcam, 99); e.Update(0.1)
Check(w:Count("SucceedMission") == 0, "player alone cannot extract")
w:Distance(m.avrec, m.dustoffcam, 99); e.Update(0.1)
Check(w:Count("SucceedMission") == 1 and m.dustoff, "player plus recycler wins")
e.Update(0.1); Check(w:Count("SucceedMission") == 1, "extraction is latched")

-- The alternate late-launchpad route waits for the delayed CCA scout.
e, w, m = NewMission()
m.opencamdone = false; m.bugout = true; m.launchpadreconed = true
m.corbettalive = false; m.time1 = -1
e.Update(0.1)
Check(m.breakme and m.pickupreached and m.deathtime == 30, "late escape starts 30-second scout delay")
w.time = 31; e.Update(0.1)
Check(m.death and m.ccap1, "late scout arrives once")
m.ccap1.enemy = w.player; w:Distance(m.ccap1, w.player, 409); e.Update(0.1)
Check(m.economyccaplatoon and m.ccap9 and not m.ccap10, "CCA pursuit has nine active units")

-- Cinematic completion gates and source cancellation cleanup.
e, w, m = NewMission()
m.opencamdone = false; m.threemin = true; m.threeminsplatoon = -1
w.audioDone = false; e.Update(0.1)
Check(m.simcam and m.sim10, "5th Platoon cinematic creates ten staged units")
w.audioDone = true; e.Update(0.1)
Check(m.breakout1 and m.removal and not m.sim5.alive, "cinematic completion removes staged platoon")

for _, failure in ipairs({
    { flag = "missionfail4", file = "misn06l1.des", audio = "aud105" },
    { flag = "missionfail", file = "misn06l2.des", audio = "aud100" },
    { flag = "missionfail3", file = "misn06l3.des", audio = "aud101" },
    { flag = "endme", file = "misn06l4.des", audio = "aud102" },
    { flag = "missionfail1", file = "misn06l5.des", audio = "aud20" },
    { flag = "fail3", file = "misn06l6.des", audio = "aud54" },
}) do
    e, w, m = NewMission()
    m[failure.flag] = true; m[failure.audio] = { audio = "pending" }
    w.audioDone = false; e.Update(0.1)
    Check(w:Count("FailMission") == 0, "failure waits for queued voice")
    w.audioDone = true; e.Update(0.1)
    local found = false
    for _, c in ipairs(w.calls) do
        if c.name == "FailMission" and c.args[2] == failure.file then found = true end
    end
    Check(found, "failure description preserved: " .. failure.file)
end

-- Lua state survives Load without Start or replaying first-frame side effects.
e, w, m = NewMission()
local saved = {}; for k, v in pairs(e.Save()) do saved[k] = v end
saved.hephikey = true; saved.processtime = 50; saved.extractpoint = 3
e.Start(); e.Load(saved); w.time = 1
local narration = w:Count("AudioMessage", "misn0601.wav")
local moves = w:Count("SetPosition")
e.Update(0.1)
Check(e.Save() == saved and m ~= saved, "Load restores the serialized mission table")
Check(saved.hephikey and saved.processtime == 50 and saved.extractpoint == 3,
    "Load preserves recon, deadlines, and random extraction choice")
Check(w:Count("AudioMessage", "misn0601.wav") == narration and w:Count("SetPosition") == moves,
    "Load does not replay startup audio")

print("Misn06: " .. checks .. " Lua 5.1 host checks passed")
