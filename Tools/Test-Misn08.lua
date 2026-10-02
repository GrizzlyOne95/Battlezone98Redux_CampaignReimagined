-- Run from repository root: lua5.1 Tools/Test-Misn08.lua
-- Mock-engine checks; these do not claim engine/asset/in-game validation.
local mission = arg and arg[1] or "Scripts/misn08.lua"
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function world(initial)
    local E = {
        assert = assert, type = type, pairs = pairs, ipairs = ipairs,
        now = 0, log = {}, alive = {}, odfs = {}, distances = {},
        health = {}, deployed = {}, counts = {}, info = {}, objects = initial or {},
    }
    local function record(name, ...)
        E.log[#E.log + 1] = { name, ... }
    end
    local function add(h, odf)
        E.alive[h] = true
        E.odfs[h] = odf
        return h
    end
    for _, h in ipairs(E.objects) do add(h[1], h[2]) end
    function E.GetTime() return E.now end
    function E.GetHandle(label)
        if E.alive[label] == nil then add(label, "") end
        return label
    end
    function E.GetPlayerHandle() return add("player", "avtank") end
    function E.IsAlive(h) return h ~= nil and E.alive[h] == true end
    E.IsValid = E.IsAlive
    function E.IsOdf(h, odf) return E.odfs[h] == odf end
    function E.GetHealth(h) return E.health[h] or 1 end
    function E.IsDeployed(h) return E.deployed[h] or false end
    function E.IsInfo(odf) return E.info[odf] or false end
    function E.GetDistance(a, b)
        return E.distances[tostring(a) .. "/" .. tostring(b)] or 10000
    end
    function E.distance(a, b, value)
        E.distances[tostring(a) .. "/" .. tostring(b)] = value
        E.distances[tostring(b) .. "/" .. tostring(a)] = value
    end
    function E.CountUnitsNearObject(h, range, team, odf)
        record("CountUnitsNearObject", h, range, team, odf)
        return E.counts[odf] or 0
    end
    function E.AllObjects()
        local i = 0
        return function()
            i = i + 1
            if E.objects[i] then return E.objects[i][1] end
        end
    end
    function E.BuildObject(odf, team, where)
        local h = odf .. "#" .. tostring(#E.log + 1)
        add(h, odf)
        record("BuildObject", odf, team, where, h)
        E.AddObject(h) -- real BuildObject invokes AddObject synchronously
        return h
    end
    function E.Damage(h, amount)
        record("Damage", h, amount)
        E.alive[h] = false
    end
    function E.RemoveObject(h)
        record("RemoveObject", h)
        E.alive[h] = false
    end
    for _, name in ipairs({
        "SetAIControl", "AudioMessage", "ClearObjectives", "AddObjective",
        "SetPilot", "SetScrap", "Defend", "Goto", "Attack", "SetWeaponMask",
        "SetObjectiveName", "SetObjectiveOn", "SetAIP", "AddHealth",
        "SucceedMission", "FailMission",
    }) do
        local api = name
        E[api] = function(...) record(api, ...) end
    end
    setmetatable(E, { __index = function(_, key) error("Unexpected global/API: " .. key) end })
    local chunk = assert(loadfile(mission))
    setfenv(chunk, E)
    chunk()
    E.Start()
    function E.step(t) E.now = t; E.Update(0.05) end
    function E.has(api, first, second)
        for _, event in ipairs(E.log) do
            if event[1] == api and (first == nil or event[2] == first)
                and (second == nil or event[3] == second) then return true end
        end
        return false
    end
    function E.n(api, first)
        local count = 0
        for _, event in ipairs(E.log) do
            if event[1] == api and (first == nil or event[2] == first) then count = count + 1 end
        end
        return count
    end
    return E
end

local E = world({ {"factory", "avmu8"}, {"tower1", "abtowe"}, {"tower2", "abtowe"} })
check(E.has("SetAIControl", 2, true), "native AI startup")
check(E.Save().nsdfmuf == "factory" and E.Save().guntower2 == "tower2", "map object bootstrap")
E.step(0)
check(E.n("AudioMessage", "misn0800.wav") == 1, "opening radio")
check(E.n("AddObjective") == 2 and E.has("SetScrap", 1, 30), "opening objectives/resources")
check(E.has("SetWeaponMask", "sovgech1", 1), "initial walker weapons")
E.step(20)
check(not E.Save().first_wave, "strict timer boundary")
E.step(20.1)
check(E.has("Goto", "svpatrol2_2", "avrecycle") and E.Save().first_wave, "first fighters")
E.deployed.factory = true
E.step(22.2)
check(E.Save().base_set and E.has("AddObjective", "misn0800.otf", "green"), "factory deployment")
E.step(100.1)
check(E.n("BuildObject", "svfigh") == 3 and E.Save().fresh_meat, "reinforcement trio")
E.step(200.1)
check(E.has("AudioMessage", "misn0817.wav"), "fighter radio")
E.distance("player", "cam5", 300)
E.step(280.1)
check(not E.Save().colorado_under_attack, "Colorado attack deferred within 400m")
E.distance("player", "cam5", 10000)
E.step(290.2)
check(E.Save().colorado_under_attack and E.n("BuildObject", "svwalk") == 1, "Colorado walker spawn")
check(E.n("BuildObject", "svfigh") == 4 and E.n("BuildObject", "svltnk") == 1, "source duplicate slot still spawns both units")
local walker3 = E.Save().ccagech3
check(E.has("Attack", walker3, "colorado"), "Colorado targeted")
E.step(300.3)
check(E.has("AudioMessage", "misn0803.wav"), "Colorado second radio")
E.step(307.4)
check(E.has("AudioMessage", "misn0802.wav") and E.has("AudioMessage", "misn0804.wav"), "Colorado final radios")
E.step(317.5)
check(E.has("Damage", "colorado", 20000) and E.Save().kill_colorado, "Colorado destruction")
E.step(329.1)
check(E.has("Goto", "sovgech1", "gech_path1") and E.has("Goto", "sovgech2", "gech_path2"), "walker route start")
E.step(332.6)
check(E.has("RemoveObject", "cam5") and E.Save().colorado_destroyed, "Colorado nav removed")
E.step(337.7)
check(E.has("SetAIP", "misn08.aip") and E.has("SetScrap", 2, 40) and E.has("SetPilot", 2, 40), "strategic AI activation")
check(E.has("Goto", walker3, "gech_path2") and not E.Save().gech3_move, "disabled third walker movement stays cut")
E.step(367.8)
check(E.has("AudioMessage", "misn0810.wav"), "general radio")
E.counts.avfigh, E.counts.avtank = 5, 2
E.step(757.8)
check(E.has("SetAIP", "misn08b.aip"), "fighter-heavy AIP")
E.counts.avfigh, E.counts.avtank = 1, 4
E.step(1178)
check(E.has("SetAIP", "misn08a.aip"), "tank-heavy AIP")

for _, variant in ipairs({1, 2}) do
    E = world(); E.step(0)
    local found = "sovgech" .. variant
    local other = "sovgech" .. (3 - variant)
    E.distance("player", found, 300)
    E.step(61.1)
    check(E.Save()["gech_found" .. variant] and E.n("AudioMessage", "misn0806.wav") == 1, "early walker discovery " .. variant)
    E.step(variant == 1 and 81.2 or 66.2)
    check(E.has("AudioMessage", "misn0807.wav"), "asymmetric followup " .. variant)
    E.distance("player", other, 50)
    E.step(variant == 1 and 103 or 122)
    check(E.Save().run_into_other_gech and E.has("AudioMessage", "misn0813.wav"), "stumble into other walker " .. variant)
end

for _, variant in ipairs({1, 2}) do
    E = world(); E.step(0)
    E.distance("player", "sovgech" .. variant, 300); E.step(61.1)
    E.distance(variant == 1 and "giez_spawn2" or "giez_spawn3", "sovgech" .. (3 - variant), 50)
    E.step(74.2)
    check(E.Save().second_gech_warning and E.has("BuildObject", "apcamr"), "second walker remote warning " .. variant)
end

for _, variant in ipairs({2, 3}) do
    E = world(); E.step(0)
    E.distance("giez_spawn" .. variant, "sovgech" .. (variant == 2 and 2 or 1), 50)
    E.step(280.1); E.step(285.1)
    check(E.Save()["gech_at_nav" .. variant], "undiscovered walker reaches trigger " .. variant)
    E.step(305.2)
    check(E.Save().player_warned_ofgech and E.has("SetObjectiveName", E.Save()[variant == 2 and "nav2" or "nav3"], variant == 2 and "Nav Alpha 1" or "Nav Alpha 2"), "first nav warning " .. variant)
    E.distance(variant == 2 and "giez_spawn3" or "giez_spawn2", "sovgech" .. (variant == 2 and 1 or 2), 50)
    E.step(319.3)
    check(E.Save().second_gech_warning, "second nav warning " .. variant)
end

E = world(); E.step(0)
E.distance("player", "cam5", 600); E.step(45.1)
check(E.Save().gech_spawn_time == 55.1 and E.has("Attack", "svpatrol1_1", "player"), "nosey player acceleration")
E.step(55.2)
check(E.Save().colorado_under_attack, "accelerated Colorado attack")

E = world(); E.step(0)
E.distance("player", "sovgech1", 300); E.step(61.1)
E.distance("sovgech1", "stop_geyser3", 50)
E.health.sovgech1 = 0.2
E.step(70)
check(E.Save().gech1_blossom and E.has("SetWeaponMask", "sovgech1", 4), "popper threshold")
E.step(76.1)
check(E.has("AudioMessage", "misn0816.wav"), "popper warning")
E.step(100.1)
check(E.Save().gech1_at_base and E.has("Attack", "sovgech1", "avrecycle") and E.has("SetWeaponMask", "sovgech1", 5), "walker arrival weapons and target")
E.AddObject("apc")
E.odfs.apc, E.alive.apc = "svapc", true
E.AddObject("apc")
E.odfs.tower, E.alive.tower = "abtowe", true
E.AddObject("tower"); E.step(101)
check(E.Save().ccaapc == "apc" and E.has("Attack", "apc", "tower"), "repaired APC tracking")

for _, relicFirst in ipairs({true, false}) do
    E = world(); E.step(0)
    if relicFirst then
        E.distance("player", "hbcerb1_i76building", 60); E.step(30.1)
        check(E.has("AudioMessage", "misn0819.wav") and E.n("SucceedMission") == 0, "relic-first waits for base")
    end
    E.alive.svrecycle, E.alive.svmuf = false, false
    E.step(31)
    if not relicFirst then
        check(E.has("SetObjectiveOn", "hbcerb1_i76building") and E.has("AddObjective", "misn0802.otf"), "base-first relic objective")
        E.distance("player", "hbcerb1_i76building", 60); E.step(34.2)
    end
    check(E.n("SucceedMission") == 1 and E.has("AudioMessage", "misn0826.wav"), "victory order " .. tostring(relicFirst))
end

E = world(); E.step(0)
E.alive.avrecycle = false; E.step(1); E.step(2)
check(E.n("FailMission") == 1 and E.has("FailMission", 16, "misn08f1.des"), "recycler loss scheduled once")

E = world(); E.step(0); E.step(280.1); E.step(290.2)
local snapshot = {}
for k, v in pairs(E.Save()) do snapshot[k] = v end
local resumed = world()
resumed.alive, resumed.odfs = E.alive, E.odfs
resumed.Load(snapshot)
resumed.step(297.3)
check(resumed.n("AudioMessage", "misn0800.wav") == 0 and resumed.n("BuildObject") == 0, "load does not replay initialization/spawn")
check(resumed.has("AudioMessage", "misn0802.wav") and resumed.Save().ccagech3 == snapshot.ccagech3, "load continues Colorado radio and walker handle")
check(resumed.Save().gech_spawn_time == snapshot.gech_spawn_time and resumed.Save().start_gech_time == snapshot.start_gech_time, "saved timers retained")

print("misn08: " .. checks .. " Lua 5.1 mock-engine checks passed")
