-- Run from the repository root: lua5.1 Tools/Test-Misns8.lua
-- Engine mocks verify script decisions; AI navigation/production needs BZR.
local script = (arg and arg[1]) or "Scripts/misns8.lua"
local W, tests = nil, 0
local function eq(a, b, why)
    assert(a == b, (why or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function object(odf, team, label)
    local h = #W.objects + 1
    W.objects[h] = {odf = odf, team = team, alive = true, valid = true,
                    health = 1, deployed = false}
    if label then W.labels[label] = h end
    return h
end
local function record(name, ...)
    W.calls[#W.calls + 1] = {name, ...}
end
local function has(name, a, b, c)
    for _, call in ipairs(W.calls) do
        if call[1] == name and (a == nil or call[2] == a)
           and (b == nil or call[3] == b) and (c == nil or call[4] == c) then
            return true
        end
    end
    return false
end
local function count(name)
    local n = 0
    for _, call in ipairs(W.calls) do if call[1] == name then n = n + 1 end end
    return n
end
local function near(a, b, distance)
    W.distances[a .. ":" .. b] = distance or 50
    W.distances[b .. ":" .. a] = distance or 50
end
local function spawn(odf, team)
    local h = object(odf, team or 2)
    AddObject(h)
    return h
end
local function frame(time)
    W.time = time
    Update(0.1)
    return Save()
end
local function reset()
    W = {objects = {}, labels = {}, distances = {}, calls = {}, time = 0,
         scrap = {}, unitCounts = {}, objectives = 0}
    W.player = object("svtank", 1)
    local map = {
        avmuf = "bvmuf", avrecycle = "bvrecy", svrecycle = "svrecy", svmuf = "svmuf",
        cam = "apcamr", basecam = "apcamr", powerplant1 = "abwpow",
        powerplant2 = "abwpow", basetower1 = "abtowe", basetower2 = "abtowe",
    }
    for label, odf in pairs(map) do object(odf, 2, label) end
    for _, label in ipairs({"center_geyser", "first_geyser", "last_geyser", "sv_geyser",
            "av_geyser", "temp_geyser", "turret_geyser", "dis_geyser1", "dis_geyser2",
            "avmuf_geyser"}) do object("eggeizr", 0, label) end
    GetHandle = function(label) return W.labels[label] end
    GetPlayerHandle = function(...) eq(select("#", ...), 0); return W.player end
    GetTime = function() return W.time end
    IsValid = function(h) return W.objects[h] ~= nil and W.objects[h].valid end
    IsAlive = function(h) return W.objects[h] ~= nil and W.objects[h].alive end
    IsOdf = function(h, odf) return IsValid(h) and W.objects[h].odf == odf end
    GetDistance = function(a, b)
        assert(IsValid(a) and IsValid(b), "invalid distance operand")
        return W.distances[a .. ":" .. b] or 3000
    end
    GetScrap = function(team) return W.scrap[team] or 0 end
    SetScrap = function(team, amount) W.scrap[team] = amount; record("SetScrap", team, amount) end
    AddScrap = function(team, amount) W.scrap[team] = GetScrap(team) + amount; record("AddScrap", team, amount) end
    SetPilot = function(...) record("SetPilot", ...) end
    AudioMessage = function(...) record("AudioMessage", ...) end
    ClearObjectives = function() W.objectives = 0; record("ClearObjectives") end
    AddObjective = function(...)
        W.objectives = W.objectives + 1
        assert(W.objectives <= 10, "stock objective capacity exceeded")
        record("AddObjective", ...)
    end
    SetAIP = function(...) record("SetAIP", ...) end
    SetObjectiveName = function(...) record("SetObjectiveName", ...) end
    SetObjectiveOn = function(...) record("SetObjectiveOn", ...) end
    SetPerceivedTeam = function(h, team) W.objects[h].perceived = team; record("SetPerceivedTeam", h, team) end
    SetIndependence = function(...) record("SetIndependence", ...) end
    BuildObject = function(odf, team, where)
        assert(type(where) == "string" or IsValid(where), "invalid spawn location")
        local h = object(odf, team)
        AddObject(h)
        record("BuildObject", odf, team, where, h)
        return h
    end
    RemoveObject = function(h) W.objects[h].alive = false; W.objects[h].valid = false; record("RemoveObject", h) end
    Build = function(...) record("Build", ...) end
    Dropoff = function(...) record("Dropoff", ...) end
    Goto = function(...) record("Goto", ...) end
    Follow = function(...) record("Follow", ...) end
    Defend = function(...) record("Defend", ...) end
    Attack = function(...) record("Attack", ...) end
    Pickup = function(h, target, priority) eq(target, nil, "producer pack target"); record("Pickup", h, target, priority) end
    IsDeployed = function(h) return W.objects[h].deployed end
    CountUnitsNearObject = function(h, radius, team, odf)
        record("CountUnitsNearObject", h, radius, team, odf)
        return W.unitCounts[h .. ":" .. odf] or 2
    end
    GetWhoShotMe = function(h) return W.objects[h].shotBy end
    GetHealth = function(h) return W.objects[h].health end
    AddHealth = function(h, amount) record("AddHealth", h, amount) end
    Damage = function(h, amount) record("Damage", h, amount); W.objects[h].alive = false end
    SucceedMission = function(...) record("SucceedMission", ...) end
    FailMission = function(...) error("source has no failure branch") end
    assert(loadfile(script))()
    Start()
    return W
end
local function test(name, fn)
    reset()
    fn()
    tests = tests + 1
    print("PASS " .. name)
end

test("startup, source defaults and pre-Start object registration", function()
    local rig = spawn("avcns8")
    Start()
    local s = frame(1)
    eq(s.avrig1, rig)
    eq(s.units, 1); eq(s.check2, 1); eq(s.defense1, 3)
    eq(s.next_second, 2); eq(s.unit_spawn_time, 99999)
    eq(s.avturret3, nil); eq(s.plan_a, true)
    eq(W.scrap[1], 25); eq(W.scrap[2], 40)
    eq(count("BuildObject"), 4)
    assert(has("SetPilot", 1, 10) and has("SetPilot", 2, 60))
    assert(has("AudioMessage", "misns800.wav") and has("SetAIP", "misns8.aip"))
    frame(2)
    eq(count("BuildObject"), 4, "startup must run once")
end)

test("base building, scrap field, delayed producer commands and plan B", function()
    local r1, r2 = spawn("avcns8"), spawn("avcns8")
    frame(1)
    assert(has("Build", r1, "abwpow") and has("Build", r2, "abtowe"))
    eq(count("Dropoff"), 0)
    frame(11); eq(count("Dropoff"), 0, "source uses strict timer comparison")
    frame(12)
    assert(has("Dropoff", r1, "rpower1") and has("Dropoff", r2, "rtower1"))
    spawn("abtowe"); spawn("abwpow")
    local s = frame(13)
    assert(has("Goto", r1, "center_path", 1))
    assert(has("BuildObject", "avart8", 2, "american_spawn"))
    frame(103); assert(not s.silo_center_prep)
    frame(104); assert(has("Build", r1, "absilo"))
    frame(109); assert(not s.silo1_build)
    frame(110); assert(has("Dropoff", r1, "center_silo"))
    spawn("absilo"); frame(111)
    assert(has("SetAIP", "misns8b.aip"))
    frame(122)
    assert(has("SetAIP", "misns8g.aip"))
    assert(has("Dropoff", r1, "main_field2") and has("Dropoff", r2, "main_field1"))
    spawn("abtowe"); spawn("abwpow")
    spawn("bvtavk"); spawn("bvtavk"); spawn("bvtavk")
    frame(123); eq(s.welldone_rig, true)
    frame(154)
    eq(s.plan_a, false); eq(s.plan_b, true); eq(s.muf_pack, true)
    assert(has("Pickup", s.avmuf))
end)

test("convoy warning, deployment, AIP and assault priorities", function()
    frame(1)
    local s = Save()
    s.plan_a = false; s.plan_b = true; s.muf_timer = 0
    local f1, f2 = s.avfighter1, spawn("bvra8") -- startup nark occupies slot 1
    frame(2); assert(s.muf_pack)
    frame(13); assert(s.convoy_start)
    assert(has("Goto", s.avmuf, "convoy_path", 1))
    assert(has("Follow", f1, s.avmuf) and has("Follow", f2, s.avmuf))
    near(s.avmuf, s.dis_geyser1)
    frame(24)
    assert(has("AudioMessage", "misns801.wav"))
    assert(has("SetObjectiveName", s.cam3, "Choke Point")); eq(W.objectives, 2)
    near(s.avmuf, s.center_geyser)
    W.objects[s.avmuf].deployed = true
    local bomb, apc, walker = spawn("bvhraz"), spawn("bvapc"), spawn("bvwalk")
    frame(74)
    eq(s.convoy_over, true); eq(s.muf_deployed, true); eq(s.start_attack, true)
    assert(has("SetAIP", "misns8c.aip"))
    assert(has("Attack", bomb, s.ccarecycle, 1))
    assert(has("Attack", apc, s.ccarecycle, 1))
    assert(has("Attack", walker, s.ccarecycle, 0))
end)

test("nearby player suppresses convoy warning", function()
    frame(1)
    local s = Save()
    s.plan_b = true; s.convoy_start = true; s.muf_warning = 0
    near(W.player, s.avmuf); near(s.avmuf, s.dis_geyser1)
    frame(2); eq(s.warning, true)
    assert(not has("AudioMessage", "misns801.wav")); eq(s.cam3, nil)
end)

test("destroyed convoy factory gets one replacement and two attackers", function()
    frame(1)
    local s = Save()
    s.plan_b = true; s.convoy_start = true
    W.objects[s.avmuf].alive = false
    frame(2)
    assert(has("BuildObject", "bvmuf", 2, "american_spawn"))
    assert(has("Goto", s.avmuf, s.avmuf_geyser))
    assert(has("Attack", s.screwu1, s.ccarecycle) and has("Attack", s.screwu2, s.ccarecycle))
    local n = count("BuildObject")
    W.objects[s.avmuf].alive = false; frame(3)
    eq(count("BuildObject"), n, "replacement is one-shot")
end)

test("plan C requires low scrap and a missing defense", function()
    frame(1)
    local s = Save()
    W.scrap[2] = 9
    W.unitCounts[s.avrecycle .. ":abtowe"] = 0
    frame(61); eq(s.plan_c, false)
    frame(62)
    eq(s.plan_c, true); eq(s.plan_a, false); eq(s.plan_b, false)
    assert(has("AudioMessage", "misns815.wav"))
    assert(has("BuildObject", "svtank", 1, "romeski_spawn"))
    eq(W.objects[s.avrecycle].perceived, 1)
    eq(s.pay_off, 67)
    frame(67); eq(s.general_message1, false)
    near(W.player, s.key_tank)
    frame(68); assert(has("Attack", s.key_tank, s.avrecycle, 1))
    frame(69); assert(s.recycle_pack)
    frame(79); eq(s.recycle_move, false)
    frame(80); assert(has("Goto", s.avrecycle, "escape_route", 1))
    near(s.avrecycle, s.last_geyser)
    frame(141); assert(s.recy_goto_geyser); eq(W.objects[s.avrecycle].perceived, 2)
    W.objects[s.avrecycle].deployed = true
    spawn("bvtur8"); spawn("bvtur8")
    frame(152)
    eq(s.recy_deployed, true); eq(s.back_in_business, true)
    assert(has("SetAIP", "misns8f.aip"))
end)

test("low scrap alone does not start plan C", function()
    frame(1); W.scrap[2] = 0; frame(62)
    eq(Save().plan_c, false)
end)

test("SAV follow, betrayal, replacements and first-shooter branch", function()
    frame(1)
    local s = Save()
    local savs = {}
    for i = 1, 6 do savs[i] = spawn("savtnk", 1) end
    s.plan_c = true
    frame(2)
    assert(has("AudioMessage", "misns816.wav"))
    for _, h in ipairs(savs) do assert(has("Follow", h, s.key_tank, 1)); near(h, s.key_tank) end
    frame(13)
    eq(s.sav_attack, true)
    for i = 1, 6 do
        assert(not IsValid(savs[i]))
        assert(IsAlive(s["badsav" .. i]))
        assert(has("Attack", s["badsav" .. i], s.key_tank, 1))
    end
    eq(count("RemoveObject"), 6)
    W.objects[s.key_tank].shotBy = s.badsav1
    frame(14)
    eq(s.sav_payback, true); eq(s.player_payback, false); eq(s.key_open, true)
    W.objects[s.key_tank].health = 0.79
    frame(15); assert(has("AudioMessage", "misns817.wav"))
    near(s.key_tank, W.player)
    frame(20); assert(has("Follow", s.key_tank, W.player, 1))
    assert(has("AudioMessage", "misns810.wav"))
    eq(count("RemoveObject"), 6, "each SAV replacement is one-shot")
end)

test("player first-shot retaliation and Romeski death timer", function()
    frame(1)
    local s = Save()
    s.plan_c = true; frame(2)
    W.objects[s.key_tank].shotBy = W.player
    frame(3)
    eq(s.player_payback, true); eq(s.sav_payback, false); eq(s.key_open, true)
    assert(has("AudioMessage", "misns819.wav"))
    assert(has("Attack", s.key_tank, W.player, 1))
    W.objects[s.key_tank].health = 0.09
    frame(4); assert(has("AudioMessage", "misns812.wav"))
    frame(7); eq(count("Damage"), 0)
    frame(8); assert(has("Damage", s.key_tank, 1000)); eq(s.general_dead, true)
end)

test("no-attacker and unrelated-attacker cases leave decision open", function()
    frame(1)
    local s = Save(); s.plan_c = true; frame(2)
    frame(3); eq(s.key_open, false)
    W.objects[s.key_tank].shotBy = object("bvraz", 2)
    frame(4); eq(s.key_open, false)
    eq(s.sav_payback, false); eq(s.player_payback, false)
end)

for repair = 1, 6 do
  for _, structures in ipairs({0, 1, 2}) do
    test("maintenance " .. repair .. " with " .. structures .. " structures", function()
        frame(1)
        local s = Save()
        spawn("avcns8"); spawn("avcns8")
        s.welldone_rig = true; s.rigs_reordered = true
        s.rig_there = true; s.maintain = true
        s.center_check = 0; s.alt_check = 0
        s["rebuild" .. repair .. "_prep"] = true
        s["rebuilding" .. repair] = true
        for _, site in ipairs({s.temp_geyser, s.last_geyser}) do
            for _, odf in ipairs({"absilo", "abwpow", "abtowe"}) do
                W.unitCounts[site .. ":" .. odf] = structures
            end
        end
        frame(2)
        eq(s["rebuilding" .. repair], structures == 0)
        eq(s["rebuild" .. repair .. "_prep"], structures == 0)
    end)
  end
end

test("missing map handle cannot trigger false convoy arrival", function()
    frame(1)
    local s = Save()
    s.plan_b = true; s.convoy_start = true; s.muf_timer = 0
    s.center_geyser = nil
    frame(2); eq(s.convoy_over, false)
end)

test("save/load retains state without replaying startup", function()
    frame(1)
    local saved = {}
    for key, value in pairs(Save()) do saved[key] = value end
    saved.plan_a = false; saved.plan_b = true; saved.muf_timer = 25
    saved.tank_check = 35; saved.general_message3 = true
    local before = count("BuildObject")
    Load(saved)
    frame(2)
    eq(count("BuildObject"), before)
    eq(Save().muf_timer, 25); eq(Save().tank_check, 35)
    eq(Save().general_message3, true); eq(Save().avrecycle, saved.avrecycle)
end)

for _, alive in ipairs({true, false}) do
    test("victory with Romeski " .. (alive and "alive" or "dead"), function()
        frame(1)
        local s = Save()
        s.key_tank = object("svtank", 1)
        W.objects[s.key_tank].alive = alive
        s.badsav1 = object("savs8", 2)
        W.objects[s.avrecycle].alive = false
        frame(10)
        assert(has("Goto", s.badsav1, s.first_geyser, 1))
        assert(has("SucceedMission", alive and 45 or 35, "misns8w1.des"))
        assert(has("AudioMessage", alive and "misns803.wav" or "misns814.wav"))
        frame(11); eq(count("SucceedMission"), 1)
    end)
end

print("misns8: " .. tests .. " scenarios passed")
