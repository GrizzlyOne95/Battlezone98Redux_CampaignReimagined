-- Run from repository root: lua5.1 Tools/Test-Misns7.lua
-- Strict mock host: verifies script behavior, not native AI/assets/engine saves.
assert(_VERSION == "Lua 5.1")
local now, serial, objects, labels, calls, distances, counts, cancelled, pilots, scrap
local checks = 0
local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
end
local function record(name, ...)
    calls[#calls + 1] = {name, ...}
end
local function called(name, ...)
    local args = {...}
    for _, c in ipairs(calls) do
        local match = c[1] == name
        for i = 1, select("#", ...) do match = match and c[i + 1] == args[i] end
        if match then return true end
    end
    return false
end
local function count(name, arg)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end
    end
    return n
end
local function spawn(odf, team)
    serial = serial + 1
    objects[serial] = {odf = odf, team = team, alive = true, health = 1}
    return serial
end
function GetHandle(label)
    if not labels[label] then labels[label] = spawn("map", 2) end
    return labels[label]
end
function GetPlayerHandle() return GetHandle("player") end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil and objects[h].alive end
function IsAlive(h) return IsValid(h) end
function IsOdf(h, odf) assert(IsValid(h)); return objects[h].odf == odf end
function GetHealth(h) assert(IsAlive(h)); return objects[h].health end
local function key(a, b) return tostring(a) .. ":" .. tostring(b) end
local function distance(a, b, d) distances[key(a,b)] = d end
function GetDistance(a, b)
    assert(IsValid(a) and IsValid(b), "invalid distance overload")
    return distances[key(a,b)] or distances[key(b,a)] or 10000
end
function CountUnitsNearObject(h, radius, team, odf)
    assert(IsAlive(h) and radius == 200 and team == 2 and odf == nil)
    return counts[h] or 0
end
function BuildObject(odf, team, where)
    assert(type(where) == "string" or IsValid(where), "invalid spawn location")
    local h = spawn(odf, team)
    record("BuildObject", odf, team, where, h)
    AddObject(h) -- deliberate synchronous callback, before assignment returns
    return h
end
function RemoveObject(h)
    -- Native removal of an already vanished boarding soldier is a no-op.
    if objects[h] then objects[h].alive = false end
    record("RemoveObject", h)
end
function AudioMessage(name) record("AudioMessage", name); return name end
function CameraCancelled() return cancelled end
function CameraReady() record("CameraReady"); return true end
function CameraFinish() record("CameraFinish"); cancelled = false; return true end
function CameraObject(a, x, y, z, b)
    assert(IsValid(a) and IsValid(b), "invalid camera handle")
    record("CameraObject", a, x, y, z, b)
    return false
end
local panel = 0
function ClearObjectives() panel = 0; record("ClearObjectives") end
function AddObjective(name, color)
    panel = panel + 1
    assert(panel <= 10 and (color == "white" or color == "green"))
    record("AddObjective", name, color)
end
function SetPilot(team, n) pilots[team] = n; record("SetPilot", team, n) end
function AddPilot(team, n) pilots[team] = (pilots[team] or 0) + n; record("AddPilot", team, n) end
function SetScrap(team, n) scrap[team] = n; record("SetScrap", team, n) end
function AddScrap(team, n) scrap[team] = (scrap[team] or 0) + n; record("AddScrap", team, n) end
for _, name in ipairs({"Defend", "Goto", "Attack", "GetIn", "Retreat", "Stop", "Build", "Dropoff",
    "SetIndependence", "SetObjectiveOn", "SetObjectiveName", "SetPerceivedTeam"}) do
    _G[name] = function(h, ...)
        assert(IsValid(h), "invalid " .. name)
        record(name, h, ...)
    end
end
function SetAIControl(team, enabled) record("SetAIControl", team, enabled) end
function SetAIP(name) record("SetAIP", name) end
function SucceedMission(at, des) record("SucceedMission", at, des) end
function FailMission(at, des) record("FailMission", at, des) end
local function step(t) now = t; Update(0.1) end
local function reset()
    now, serial = 0, 0
    objects, labels, calls, distances, counts = {}, {}, {}, {}, {}
    pilots, scrap, cancelled = {}, {}, false
    dofile("Scripts/misns7.lua")
    Start()
    step(0)
    return Save()
end
local function dead(h) objects[h].alive = false end
local function freeze(m)
    -- Isolate late-game scenarios from incidental scripted spawns.
    m.build_scav = true
    m.fight1_built, m.fight2_built, m.fight3_built = true, true, true
    m.avmuf_built, m.plan_b = false, false
end
local function load_copy()
    local copy = {}
    for k,v in pairs(Save()) do copy[k] = v end
    Load(copy)
    return Save()
end

-- Startup, exact strict deadlines, and first-match object discovery.
local m = reset()
check(called("SetAIControl", 2, true), "startup AI enable")
check(pilots[1] == 8 and pilots[2] == 40 and scrap[2] == 40, "initial resources")
check(called("SetObjectiveName", m.jail, "Military Prison"), "prison objective")
check(called("Build", m.avrig, "abtowe"), "first rig build primed")
check(not called("SetAIP"), "no early AIP added")
step(8); check(not m.build_scav, "strict scav deadline")
step(8.01); check(m.build_scav and count("BuildObject", "bvscav") == 2, "two scavs")
check(called("Goto", m.avscav1, m.fed_up_scrap, 0), "scav destination and priority")
local tank = BuildObject("bvtank", 2, "test")
check(m.avtank1 == tank, "tank callback")
local unrelated = BuildObject("svscav", 1, "test")
check(m.avscav1 ~= unrelated, "CCA supplies do not replace enemy slots")
local turret_at = count("Defend", m.bturret1)
step(60); check(count("Defend", m.bturret1) == turret_at, "strict turret refresh")
step(60.1); check(m.bturret_time == 240.1, "periodic turret refresh")

-- Early aggression and the timed prison-discovery escalation.
m = reset(); step(8.1)
objects[m.avscav1].health = 0.90
step(9); check(m.nsdf_adjust and m.fight1_built, "scav attack escalates")
check(called("Attack", m.avfight1, m.user), "first fighter targets player")
step(29.1); check(m.fight2_built and called("Attack", m.avfight2, m.user), "second fighter")
step(49.2); check(m.fight3_built and called("Attack", m.avfight3, m.apc), "third targets APC when second lives")
check(m.build_turret and called("Goto", m.avturr1, "turret_spot"), "aggression turret")
m = reset(); distance(m.user,m.jail,149); step(1)
check(m.adjust_timer == 121 and m.jail_found, "discovery schedules 120 seconds")
step(121); check(not m.nsdf_adjust, "strict discovery deadline")
step(121.01); check(m.nsdf_adjust, "discovery escalation")

-- Prison destruction, 1.5-second soldier spawn, 3.5-second camera, pickup.
m = reset(); freeze(m)
dead(m.jail); step(1)
check(m.jail_dead and m.camera_off_time == 4.5, "prison destruction camera")
step(2.5); check(not m.jail_unit_spawn, "strict prisoner spawn deadline")
step(2.51); check(m.jail_unit_spawn and count("BuildObject", "sssold") == 3, "all prisoners")
for i = 1,3 do
    local h = m["con" .. i]
    check(called("GetIn", h, m.apc, 1) and called("SetIndependence", h, 0), "prisoner boarding order")
    distance(h,m.apc,19)
end
step(2.6); check(m.con1_in_apc and not m.con1_safe, "boarding grace starts")
step(2.81); check(m.con1_safe and m.con2_safe and m.con3_safe and m.fully_loaded, "three survivors loaded")
check(pilots[1] == 11 and count("AudioMessage", "misns702.wav") == 3, "pickup resources/audio")
local saved_deadline = m.camera_off_time
local audio_count = count("AudioMessage")
m = load_copy(); step(3)
check(m.camera_off_time == saved_deadline and count("AudioMessage") == audio_count, "save during prison camera")
step(4.51); check(m.jail_camera_off and m.muf_build_time == 9.51, "camera finish and factory delay")
step(9.52); check(m.avmuf_built and called("Goto", m.avmuf, m.geyser1), "enemy factory spawn")

-- Every survivor permutation, and guards applied to all OR arms.
for mask = 0,7 do
    m = reset(); freeze(m)
    local survivors = 0
    for i = 1,3 do
        local safe = math.floor(mask / 2^(i-1)) % 2 == 1
        m["con"..i.."_safe"], m["con"..i.."_dead"] = safe, not safe
        if safe then survivors = survivors + 1 end
    end
    step(1)
    if survivors == 0 then
        check(called("FailMission",11,"misns7f1.des"), "all dead failure")
    else
        local flag = ({"one_loaded","two_loaded","fully_loaded"})[survivors]
        check(m[flag] and m.first_message_done, "survivor mask "..mask)
        local n = count("AudioMessage")
        step(2); check(count("AudioMessage") == n, "one-shot survivor briefing")
        m[flag] = false; m.get_recycle = true
        step(2.1); check(not m[flag], "no new loading briefing after delivery starts")
    end
end

-- Full mission deliveries, both orders, optional supply, exact spawn delay.
local function loaded(survivors)
    local state = reset(); freeze(state)
    for i = 1,3 do state["con"..i.."_safe"], state["con"..i.."_dead"] = i <= survivors, i > survivors end
    step(1)
    return state
end
local function deliver(state, kind, t, cancel)
    local target = ({recycle=state.svrecycle,muf=state.svmuf,supply=state.supply})[kind]
    distance(state.apc,target,10)
    step(t)
    check(state["get_"..kind], "delivery accepted: "..kind)
    step(t+2); check(not state[kind == "recycle" and "svrecycle_unit_spawn" or kind == "muf" and "svmuf_unit_spawn" or "supply_unit_spawn"], "strict engineer spawn")
    step(t+2.01)
    if cancel then cancelled = true
    else distance(state.engineer,kind == "supply" and state.con_geyser or target,10) end
    step(t+2.1)
    check(state["camera_off_"..kind], "delivery camera ends: "..kind)
    distance(state.apc,target,10000)
end
for _, order in ipairs({{"recycle","muf","supply"},{"muf","supply","recycle"}}) do
    m = loaded(3)
    for i, kind in ipairs(order) do
        deliver(m,kind,10*i,i==2)
        m = load_copy()
    end
    check(m.apc_empty and m.down_to_two and m.down_to_one, "three engineers consumed")
    check(objects[m.svrecycle].odf == "svrecy" and objects[m.svrecycle].team == 1, "recycler replaced")
    check(objects[m.svmuf].odf == "svmuf" and objects[m.svmuf].team == 1, "factory replaced")
    check(scrap[1] == 40 and pilots[1] == 5, "delivery resource accounting")
    step(50)
    check(m.supplies_spawned and m.turret_message, "supply cache spawned")
    check(count("BuildObject", "svscav") == 2 and count("BuildObject", "svturr") == 2, "four supply vehicles")
    check(count("BuildObject", "spammo") == 3 and count("BuildObject", "sprepa") == 2, "five supply powerups")
    check(called("Stop",m.supply1,0) and called("Stop",m.supply4,0), "supply scavengers commandable")
end
m = loaded(1); deliver(m,"muf",10,false)
distance(m.apc,m.svrecycle,10); step(20)
check(m.apc_empty and not m.get_recycle, "one survivor allows only one restoration")
m = loaded(2); deliver(m,"recycle",10,false); deliver(m,"muf",20,false)
distance(m.apc,m.supply,10); step(30)
check(m.apc_empty and not m.get_supply, "two survivors cannot claim supplies")

-- Threat-gated briefing, early locked shed, enemy AIP fallback/rebuild.
m = reset(); m.build_scav = true
dead(m.jail); step(1); step(2.6); step(4.6); step(9.7)
step(39.8)
check(m.fight1_built and not called("Attack",m.avfight1,m.user), "normal first fighter keeps source default command")
distance(m.apc,m.boxes,199); step(69.9)
check(m.fight2_built and called("Attack",m.avfight2,m.apc), "normal second fighter targets nearby APC")
check(called("SetAIP","misns7.aip") and called("AddScrap",2,40), "normal enemy strategic plan")
m = loaded(3)
distance(m.apc,m.svmuf,10); cancelled = true; step(10)
check(not m.camera_off_muf and not m.svmuf_unit_spawn, "camera skip cannot bypass engineer spawn delay")
step(12.1)
check(m.camera_off_muf and m.svmuf_unit_spawn, "camera skip completes after engineer spawn")
m = loaded(3); m.camera_off_recycle = true
local spare = BuildObject("svmuf",1,"test"); step(5)
check(m.new_muf and m.newmuf == spare, "spare factory recognized after recycler restoration")
distance(m.apc,m.svmuf,10); step(10)
check(not m.get_muf, "source spare-factory branch suppresses original recovery")
m = reset(); freeze(m); m.jail_unit_spawn = true
for i=1,3 do m["con"..i] = spawn("sssold",1) end
distance(m.con1,m.apc,19); step(1); step(1.21)
check(m.con1_safe and not m.con2_safe, "partial boarding")
counts[m.apc] = 1; step(6.3)
check(IsAlive(m.con2) and IsAlive(m.con3), "source safe-area cleanup waits for enemies to leave")
counts[m.apc] = 0; step(11.4); step(11.5)
check(m.con2_dead and m.con3_dead and m.one_loaded, "active stranded-prisoner cleanup retained")
m = loaded(3); counts[m.apc] = 1
step(4.1); check(not m.muf_message, "nearby enemy delays briefing")
counts[m.apc] = 0; step(7.2)
check(called("AudioMessage","misns724.wav") and called("AudioMessage","misns717.wav"), "full payload briefing")
step(37.3); check(m.muf_message2 and called("AddObjective","misns702.otf","white"), "later objective")
m = reset(); freeze(m); distance(m.user,m.supply,60); step(1)
check(m.supply_first and called("SetAIP","misns7b.aip"), "locked shed and silo plan")
check(called("AudioMessage","misns715.wav"), "locked message")
m.avmuf = BuildObject("bvmuf",2,"test"); m.avmuf_built = true
dead(m.avmuf); step(2); check(m.plan_b and called("SetAIP","misns7c.aip"), "factory loss fallback")
local replacement = BuildObject("bvmuf",2,"test"); step(3)
check(m.avmuf == replacement and m.plan_c and called("SetAIP","misns7a.aip"), "rebuilt factory resumes plan")
local walker = BuildObject("bvwalk",2,"test")
step(4); check(called("Goto",walker,m.avsilo,0), "walker silo staging")
counts[m.svmuf] = 1; step(240.1)
check(m.muf_located and m.gech_adjust and called("Attack",walker,m.svmuf), "walker retarget after factory scan")

-- Construction milestones, rig relocation and repair callbacks.
m = reset(); freeze(m); objects[m.jail].health = 0.49; step(1)
check(m.in_base and called("Dropoff",m.avrig,"tower1_spot"), "first tower site")
m.avtower1 = BuildObject("abtowe",2,"test"); step(2)
check(m.b1 == true and called("Build",m.avrig,"abwpow"), "power after first tower")
m = load_copy(); step(7); check(not m.build_power1, "strict power build delay survives load")
step(7.1); check(m.build_power1 and called("Dropoff",m.avrig,"power1_spot"), "power site")
m.avpower1 = BuildObject("abwpow",2,"test"); step(12.2)
check(m.b2 == true and called("Build",m.avrig,"abtowe"), "second tower build")
step(17.3); check(m.build_tower2 and called("Dropoff",m.avrig,"tower2_spot"), "second tower site")
m.avtower2 = BuildObject("abtowe",2,"test"); step(22.4)
check(m.new_rig and not IsAlive(m.avrig), "rig removal out of view")
distance(m.user,m.avrecycle,399); step(32.5)
check(m.rig_show and objects[m.avrig].odf == "avcns7", "replacement rig on return")
step(52.6); check(m.blah and called("Dropoff",m.avrig,"barrack_spot"), "barracks dropoff")
step(112.7); check(m.turret4_defend and called("Defend",m.avturr4,1), "base turret defense")
dead(m.main_power); step(113)
check(m.main_off and called("Build",m.avrig,"abwpow"), "repair starts")
step(123.1); check(m.main_build and called("Dropoff",m.avrig,"main_power"), "repair dropoff")
local power = BuildObject("abwpow",2,"repair"); step(124)
check(m.main_power == power and not m.main_off and not m.main_build, "replacement power recognized")
dead(m.main_tower); step(125); step(135.1)
local tower = BuildObject("abtowe",2,"repair"); step(136)
check(m.main_tower == tower and not m.maint_off and not m.maint_build, "replacement tower recognized")
check(not called("Dropoff",m.avrig,"tower3_spot"), "cut tower stays disabled")

-- Terminal ordering and invalid prisoner handles.
m = reset(); dead(m.apc); step(1)
check(called("FailMission",11,"misns7f2.des"), "APC loss before restoration")
m = reset(); m.camera_off_muf = true; dead(m.apc); step(1)
check(not m.game_over, "APC loss permitted after factory restoration")
m = reset(); dead(m.avrecycle); dead(m.apc); step(1)
check(called("SucceedMission",11,"misns7w1.des") and not called("FailMission"), "success wins same-frame terminal tie")
local wins = count("SucceedMission"); step(2)
check(count("SucceedMission") == wins, "one-shot win")
m = reset(); m.jail_unit_spawn = true; freeze(m); step(1)
check(m.con1_dead and m.con2_dead and m.con3_dead and not m.con1_in_apc, "nil soldiers never board")
check(called("FailMission",11,"misns7f1.des"), "missing prisoners fail cleanly")
print("misns7 Lua 5.1 mission checks: " .. checks .. " passed")
