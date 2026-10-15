-- The real co-op registry loads shared Lua helpers through require().
package.path = "Scripts/?.lua;" .. package.path
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
    w.audio, w.hold = {}, {}
    e.AudioMessage = function(file)
        Record("AudioMessage", file)
        w.audio[#w.audio + 1] = file
        return { audio = file }
    end
    -- w.hold[file] = true keeps that one message "playing" regardless of w.audioDone.
    e.IsAudioMessageDone = function(msg)
        assert(msg and msg.audio)
        return w.audioDone and not w.hold[msg.audio]
    end
    function w:Since(n)
        local out = {}
        for i = n + 1, #self.audio do out[#out + 1] = self.audio[i] end
        return table.concat(out, ",")
    end
    function w:Played(file)
        local n = 0
        for _, f in ipairs(self.audio) do if f == file then n = n + 1 end end
        return n
    end
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
        "FailMission", "SucceedMission", "Ally", "UnAlly", "DisplayMessage"}) do
        local api = name
        e[api] = function(...) Record(api, ...) end
    end
    -- Offline co-op layer: real CRCoop (single-player semantics) over stubbed
    -- engine modules. subtit.Play forwards to AudioMessage like the real module.
    local function noop() end
    local modules = {
        RequireFix = { Initialize = noop }, exu = {},
        Environment = { Init = function(options) w.environmentOptions=options; Record("environmentInit") end,
            Update = function() Record("environmentUpdate") end, OnObjectCreated = noop },
        CRMarsWeather = {
            Init = function(options) w.weatherOptions=options; w.weatherTarget=options.targetLevel; w.weatherLevel=options.startLevel end,
            Update = function(dt) w.weatherDt=dt; Record("weatherUpdate") end, OnObjectCreated = noop,
            SetAutomatic = function(value) w.weatherAutomatic=value end,
            SetTargetLevel = function(value) w.weatherTarget=value end,
            GetTargetLevel = function() return w.weatherTarget end,
            GetLevel = function() return w.weatherLevel end,
            Save = function() return {level=w.weatherLevel,targetLevel=w.weatherTarget} end,
            Load = function(state) w.weatherLevel=state.level; w.weatherTarget=state.targetLevel end,
            Shutdown = function() Record("weatherShutdown") end,
        },
        ScriptSubtitles = {
            Play = function(file) return e.AudioMessage(file) end,
            Queue = function(file) return e.AudioMessage(file) end,
            Stop = function() Record("SubtitleStop") end,
            Update = noop, Initialize = noop },
    }
    modules.CRCoopComms = assert(loadfile("Scripts/CRCoopComms.lua"))()
    modules.CRCoopRespawn = assert(loadfile("Scripts/CRCoopRespawn.lua"))()
    e.package = setmetatable({ loaded = { exu = modules.exu } }, { __index = package })
    modules.CRCoop = setfenv(assert(loadfile("Scripts/CRCoop.lua")), e)()
    e.require = function(name) return assert(modules[name], name) end
    setfenv(assert(loadfile(script)), e)()
    e.Start()
    e.Update(0)
    w.state = e.Save()
    return e, w, w.state
end

-- Co-op team remap: authored/spawned CCA is team 5, the 5th Platoon cinematic is
-- support team 7, and the player-side camera beacons stay on team 1.
local function CheckTeams(w, context)
    local seen = 0
    for _, c in ipairs(w.calls) do
        if c.name == "BuildObject" then
            local odf, team = c.args[1], c.args[2]
            local want = odf:find("^sv") and 5 or odf:find("^av") and 7 or 1
            Check(team == want, context .. ": " .. odf .. " built on team " .. tostring(team))
            seen = seen + 1
        end
    end
    Check(seen > 0, context .. ": scenario built objects")
end

local e, w, m = NewMission()
Check(w:Count("AudioMessage", "misn0601.wav") == 1 and w:Count("Ally") >= 8 and w:Count("UnAlly") >= 2,
    "offline subtit.Play reaches AudioMessage and alliances are configured")
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
    CheckTeams(w, "patrol choice " .. choice)
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
CheckTeams(w, "attack waves")
w.info.sblpad = true; e.Update(0.1)
Check(m.bugout and m.launchpadreconed, "launchpad info enables extraction")
w.time = m.time1 + 0.1; e.Update(0.1)
Check(m.bustout and m.pickupreached and m.dustoffcam, "early escape creates pickup beacon")
w:Distance(m.player, m.dustoffcam, 99); e.Update(0.1)
Check(w:Count("SucceedMission") == 0, "player alone cannot extract")
w:Distance(m.avrec, m.dustoffcam, 99); e.Update(0.1)
Check(w:Count("SucceedMission") == 1 and m.dustoff, "player plus recycler wins")
e.Update(0.1); Check(w:Count("SucceedMission") == 1, "extraction is latched")

-- Offline hostile assault targets the one player; the recycler alone cannot extract.
e, w, m = NewMission()
m.opencamdone = false; m.starportreconed = true; e.Update(0.1)
local attacks = 0
for _, c in ipairs(w.calls) do
    if c.name == "Attack" and c.args[2] == w.player then attacks = attacks + 1 end
end
Check(attacks == 2 and m.ccaattack, "offline escorts attack the local player")
m.pickupreached = true; m.dustoffcam = e.GetHandle("dustoff"); m.avrec = e.GetHandle("avrecy-1_recycler")
w:Distance(m.avrec, m.dustoffcam, 50); e.Update(0.1)
Check(w:Count("SucceedMission") == 0, "recycler alone cannot extract")
w:Distance(m.player, m.dustoffcam, 50); e.Update(0.1)
Check(w:Count("SucceedMission") == 1, "recycler and player together extract")

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
CheckTeams(w, "CCA pursuit")

-- Cinematic completion gates and source cancellation cleanup.
e, w, m = NewMission()
m.opencamdone = false; m.threemin = true; m.threeminsplatoon = -1
w.audioDone = false; e.Update(0.1)
Check(m.simcam and m.sim10, "5th Platoon cinematic creates ten staged units")
w.audioDone = true; e.Update(0.1)
Check(m.breakout1 and m.removal and not m.sim5.alive, "cinematic completion removes staged platoon")
CheckTeams(w, "5th Platoon cinematic")
Check(m.sim1.team == 7 and m.sim6.team == 7, "5th Platoon cinematic units use the support team")

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

-- Campaign Reimagined restored voice-over (RESTORED_VO) ------------------------
local function Wav(n) return "misn06" .. string.format("%02d", n) .. ".wav" end
local function Names(...)
    local t = {}
    for _, n in ipairs({...}) do t[#t + 1] = Wav(n) end
    return table.concat(t, ",")
end

-- B1..B5: escorts die -> transport lands -> 1 min / 1.5 min broadcasts.
local function ChainToTransport()
    local e, w, m = NewMission()
    m.opencamdone = false; m.starportreconed = true
    w.hold[Wav(13)] = true
    m.wAu1.alive = false; m.wAu2.alive = false; e.Update(0.1)
    Check(m.ccapullout and m.transarrive, "escort loss starts transport countdown")
    return e, w, m
end
do
    local e, w, m = ChainToTransport()
    local n = #w.audio
    e.Update(0.1)
    Check(w:Played(Wav(23)) == 0, "B1 waits for 0612/0613 to finish")
    w.hold[Wav(13)] = nil; n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == Names(23, 15, 52), "B1: touchdown, Collins blockade order, Yes sir")
    n = #w.audio; e.Update(0.1); e.Update(0.1)
    Check(w:Since(n) == "", "B1 fires once")

    w.time = m.transportarrive + 0.1; n = #w.audio
    w.hold[Wav(20)] = true; e.Update(0.1)
    Check(w:Since(n) == Names(14, 16, 17, 18, 19, 20), "B2: 0614 then 0616-0620, no 0628")
    Check(m.aud6.audio == Wav(14) and m.aud7.audio == Wav(20), "cockpit gate follows first and last B2 lines")
    Check(not m.lprecon and w:Count("StartCockpitTimer") == 0, "cockpit timer waits for 0620")
    Check(m.vob3choice == Wav(24) or m.vob3choice == Wav(41), "B3 opener is 0624 or 0641, chosen at B2 time")
    w.hold[Wav(20)] = nil; e.Update(0.1)
    Check(m.lprecon and w:Count("StartCockpitTimer", 540) == 1, "cockpit timer + objective start after 0620")

    local choice = m.vob3choice
    w.time = m.oneminstrans - 1; n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == "", "B3 waits for the one-minute mark")
    w.hold[Wav(22)] = true
    w.time = m.oneminstrans + 0.1; n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == choice .. "," .. Names(21, 22), "B3: random opener, 0621, 0622")
    w.time = m.transaway + 0.1; n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == "", "B4 waits for B3 audio")
    w.hold[Wav(22)] = nil; w.hold[Wav(26)] = true; n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == Names(25, 26), "B4: 0625 then 0626")
    n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == "", "B5 waits for B4 audio")
    w.hold[Wav(26)] = nil; e.Update(0.1)
    Check(w:Since(n) == Names(27, 28), "B5: 0627 then 0628 while the launchpad is unreconed")
    n = #w.audio; e.Update(0.1); e.Update(0.1)
    Check(w:Since(n) == "" and w:Played(Wav(21)) == 1 and w:Played(Wav(25)) == 1 and w:Played(Wav(27)) == 1,
        "B3, B4 and B5 each fire once")
end

-- 0628 is dropped when the launchpad was reconed before B5.
do
    local e, w, m = ChainToTransport()
    w.hold[Wav(13)] = nil; e.Update(0.1)
    w.time = m.transportarrive + 0.1; e.Update(0.1)
    w.time = m.oneminstrans + 0.1; e.Update(0.1)
    w.time = m.transaway + 0.1; w.hold[Wav(26)] = true; e.Update(0.1)
    m.launchpadreconed = true; w.hold[Wav(26)] = nil
    local n = #w.audio; e.Update(0.1)
    Check(w:Since(n) == Names(27), "0628 only plays when the launchpad is not yet reconed")
end

-- B3/B4 (and so B5) are skipped once the player has bugged out.
for _, flag in ipairs({"bugout", "launchpadreconed"}) do
    local e, w, m = ChainToTransport()
    w.hold[Wav(13)] = nil; e.Update(0.1)
    w.time = m.transportarrive + 0.1; e.Update(0.1)
    m[flag] = true; m.time1 = 1e9
    w.time = m.oneminstrans + 0.1; e.Update(0.1)
    w.time = m.transaway + 0.1; e.Update(0.1); e.Update(0.1)
    Check(w:Played(Wav(21)) == 0 and w:Played(Wav(22)) == 0 and w:Played(Wav(25)) == 0
        and w:Played(Wav(26)) == 0 and w:Played(Wav(27)) == 0, "B3/B4/B5 skipped after " .. flag)
end
-- B3 played, then bugout before B4: B4 is skipped.
do
    local e, w, m = ChainToTransport()
    w.hold[Wav(13)] = nil; e.Update(0.1)
    w.time = m.transportarrive + 0.1; e.Update(0.1)
    w.time = m.oneminstrans + 0.1; e.Update(0.1)
    Check(w:Played(Wav(21)) == 1, "B3 played before bugout")
    m.bugout = true; m.time1 = 1e9
    w.time = m.transaway + 0.1; e.Update(0.1)
    Check(w:Played(Wav(25)) == 0 and w:Played(Wav(27)) == 0, "B4 skipped when bugout happened after B3")
end
-- B1 is skipped if the transport block already fired.
do
    local e, w, m = ChainToTransport()
    w.time = m.transportarrive + 0.1; e.Update(0.1)
    Check(m.touchdown, "transport block fired")
    w.hold[Wav(13)] = nil; e.Update(0.1)
    Check(w:Played(Wav(23)) == 0 and w:Played(Wav(52)) == 0, "B1 skipped after touchdown block fired")
end

-- 0610 delays 0605.
do
    local e, w, m = NewMission()
    w.hold[Wav(10)] = true; w.info.obheph = true; w.time = 1; e.Update(0.1)
    Check(w:Played(Wav(10)) == 1 and m.aud610 and m.processtime == 6, "Hephestus info plays 0610")
    w.time = 6.1; e.Update(0.1)
    Check(not m.neworders and w:Played(Wav(5)) == 0, "0605 waits for 0610")
    w.hold[Wav(10)] = nil; e.Update(0.1)
    Check(m.neworders and w:Played(Wav(5)) == 1, "0605 plays after 0610; DLL deadline unchanged")
end

-- 0609 waits for no enemy within 300 m of any player.
do
    local e, w, m = NewMission()
    local foe = e.GetHandle("foe"); w.player.enemy = foe; w:Distance(w.player, foe, 200)
    w:Distance(w.player, m.blockade1, 400); w.hold[Wav(36)] = true; w.time = 1; e.Update(0.1)
    Check(m.blockadefound and w:Played(Wav(36)) == 1 and m.aud636.audio == Wav(36), "0636 handle retained")
    w.hold[Wav(36)] = nil; e.Update(0.1)
    Check(w:Played(Wav(9)) == 0, "0609 waits while an enemy is within 300 m")
    w:Distance(w.player, foe, 301); e.Update(0.1); e.Update(0.1)
    Check(w:Played(Wav(9)) == 1, "0609 plays once when clear")
end

-- First starport reminder is 0693; spfail fail path unchanged.
do
    local e, w, m = NewMission()
    m.reconsptime = 0; w.time = 1; e.Update(0.1)
    Check(w:Played(Wav(93)) == 1 and w:Played(Wav(54)) == 0 and m.spfail == 1, "first reminder is 0693")
    for i = 2, 4 do
        w.time = w.time + 15.1; e.Update(0.1)
        Check(m.spfail == i and w:Played(Wav(54)) == i - 1, "later reminder " .. i .. " is 0654")
    end
    w.time = w.time + 15.1; e.Update(0.1)
    Check(m.fail3 and w:Played(Wav(94)) == 1 and m.spfail == 4 and w:Played(Wav(93)) == 1,
        "four reminders then the unchanged 0694 failure")
end

-- Late escape uses 0637 only; early (Corbett alive) escape is unchanged.
do
    local e, w, m = NewMission()
    m.opencamdone = false; m.bugout = true; m.launchpadreconed = true
    m.corbettalive = false; m.time1 = -1; e.Update(0.1)
    Check(w:Played(Wav(37)) == 1 and w:Played(Wav(29)) == 0 and w:Played(Wav(30)) == 0 and m.breakme,
        "late bugout plays 0637 not 0629/0630")
    e, w, m = NewMission()
    m.opencamdone = false; m.bugout = true; m.launchpadreconed = true
    m.threemin = true; m.time1 = -1; e.Update(0.1)
    Check(w:Played(Wav(29)) == 1 and w:Played(Wav(37)) == 0, "Corbett-alive bugout still plays 0629")
end

-- Extraction success: 0639 for late escape, 0649 otherwise.
for _, late in ipairs({true, false}) do
    local e, w, m = NewMission()
    m.opencamdone = false; m.corbettalive = not late
    m.pickupreached = true; m.dustoffcam = e.GetHandle("dustoff"); m.avrec = e.GetHandle("avrecy-1_recycler")
    w:Distance(m.avrec, m.dustoffcam, 50); w:Distance(w.player, m.dustoffcam, 50); e.Update(0.1)
    Check(w:Count("SucceedMission") == 1, "extraction succeeded")
    Check(w:Played(Wav(late and 39 or 49)) == 1 and w:Played(Wav(late and 49 or 39)) == 0,
        late and "late escape success is 0639" or "normal success is 0649")
end

-- New state lives in the saved M table.
do
    local e, w, m = ChainToTransport()
    w.hold[Wav(13)] = nil; e.Update(0.1)
    Check(m.vob1 == true and e.Save() == m, "B1 latch lives in the saved mission table")
end

-- Story/weather wiring uses the real mission phases and save/load callbacks.
e,w,m = NewMission()
Check(w.weatherOptions.profile == "Plains" and w.weatherOptions.sensorDegrade and not w.weatherOptions.windPush,
    "mission06 uses Mars sensor effects without wind handling changes")
Check(w.environmentOptions==nil,"mission06 uses the shared Environment night policy")
Check(w.weatherTarget == 1 and w.weatherAutomatic, "recon begins calm and host drives the ladder")
m.hephikey=true; e.Update(0.1); Check(w.weatherTarget==2,"Hephaestus scan raises breeze")
m.starportreconed=true; e.Update(0.1); Check(w.weatherTarget==3,"starport recon raises dust")
m.lprecon=true; e.Update(0.1); Check(w.weatherTarget==4,"blockade/launch assault trends stormy")
m.launchpadreconed=true; e.Update(0.1); Check(w.weatherTarget==2,"extraction clears weather")
local saved=e.Save(); w.weatherLevel=3; saved.weatherState.level=2
e.Load(saved); e.Update(0.1)
Check(w.weatherLevel==2 and w:Count("weatherShutdown")==1,"load restores saved weather and rebuilds runtime")
Check(w:Count("environmentUpdate") > 0 and w:Count("weatherUpdate") > 0,"mission updates weather and environment together")
e.Update(); Check(w.weatherDt>0,"argument-free Redux Update does not freeze weather clock")
e.Update(0); Check(w.weatherDt==0,"explicit zero timestep still settles without advancing weather")
print("Misn06: " .. checks .. " Lua 5.1 host checks passed, including atmosphere story/save wiring")
