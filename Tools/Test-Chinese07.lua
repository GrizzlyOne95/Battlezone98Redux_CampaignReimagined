-- Run from repository root: lua5.1 Tools/Test-Chinese07.lua
-- Stock API doubles verify mission logic; this is not an engine playtest.
local script = arg and arg[1] or "Scripts/ch07.lua"
local calls, distances, health, alive, now, cancel, done, player
local function log(name, ...) calls[#calls+1] = {name, ...} end
local function count(name, odf)
    local n = 0
    for _, c in ipairs(calls) do
        if c[1] == name and (odf == nil or c[2] == odf) then n = n + 1 end
    end
    return n
end
function GetHandle(label) return label end
function GetPlayerHandle() return player end
function GetTime() return now end
function GetDistance(h, target) return distances[h .. ":" .. target] or distances[target] or 10000 end
function GetHealth(h) return health[h] or 1 end
function IsAlive(h) return h ~= nil and alive[h] ~= false end
function BuildObject(odf, team, where, point)
    log("BuildObject", odf, team, where, point)
    return odf .. ":" .. #calls
end
function AudioMessage(name) log("AudioMessage", name); return name end
function IsAudioMessageDone() return done end
function CameraPath(...) log("CameraPath", ...); return true end
function CameraCancelled() return cancel end
local curAmmo, curHealth = 50, 50
function GetCurAmmo() return curAmmo end
function GetMaxAmmo() return 100 end
function GetCurHealth() return curHealth end
function GetMaxHealth() return 100 end
function SetCurAmmo(h, n) curAmmo=n; log("SetCurAmmo", h, n) end
function SetCurHealth(h, n) curHealth=n; log("SetCurHealth", h, n) end
for _, name in ipairs({"SetPilot", "SetScrap", "SetPerceivedTeam", "CameraReady",
    "CameraFinish", "StopAudioMessage", "ClearObjectives", "AddObjective",
    "Attack", "Hide", "UnHide", "Goto", "RemoveObject", "SetPosition", "SetName",
    "SetPilotClass", "Defend2", "MakeExplosion", "FailMission", "SucceedMission",
    "ColorFade", "StartSound"}) do
    local key=name
    _G[key]=function(...) log(key, ...) end
end
local function fresh(direction, relic)
    calls, distances, health, alive = {}, {}, {}, {}
    now, cancel, done, player = 0, false, false, "player"
    curAmmo, curHealth = 50, 50
    dofile(script); Start()
    local s=Save(); s.direction=direction; s.relic=relic
    Update(0.1)
    assert(s.cameraComplete[0] and not s.arrived, "opening local shadow")
    assert(s.convoyTime==840 and s.sound5Time==780)
    return s
end
for direction=0,1 do
    for relic=0,2 do
        local s=fresh(direction,relic)
        distances.commtower=20; Update(0.1)
        assert(s.doBurglarSequence and s.burglarSequencePlayed)
        cancel=true; Update(0.1); cancel=false; done=true; Update(0.1)
        assert(s.objective1Complete and s.foot1Time==10)
        assert(count("BuildObject","apcamr")==1)
        assert(count("AudioMessage",direction==0 and "ch07002.wav" or "ch07003.wav")==1)
        distances.commtower=10000
        now=10; Update(0.1); assert(count("AudioMessage","ch07004.wav")==0)
        now=10.1; Update(0.1); assert(count("AudioMessage","ch07004.wav")==1)
        now=840; Update(0.1); assert(s.convoyCount==0)
        for i=0,2 do
            now=840.1+8.1*i; Update(0.1)
            assert(s.convoyCount==i+1)
            if i==relic then assert(s.relicApc~=nil) end
            local snapshot=Save(); Load(snapshot); assert(Save()==snapshot)
        end
        assert(count("BuildObject","svapca")==1 and count("BuildObject","svfigh")==3)
        assert(count("SetPilotClass")==6 and s.convoySpawned)
        now=900; Update(0.1); assert(s.convoyCount==3)
        -- Destroyed APC cannot produce a spurious escape failure.
        health[s.relicApc]=0; alive[s.relicApc]=false
        distances[direction==0 and "north_fail" or "east_fail"]=0
        Update(0.1); assert(s.objective3Complete and not s.lost)
        distances.nav_end=40; Update(0.1)
        assert(s.snipersSpawned and s.rescue and not s.won)
        assert(count("BuildObject","cspilo")==5)
        for i=0,5 do alive[s.endGuy[i]]=false end
        Update(0.1); assert(s.won and count("SucceedMission")==1)
        Update(0.1); assert(count("SucceedMission")==1)
    end
end
local s=fresh(0,0)
-- All seven source ambushes remain ungated by the comm tower objective.
for i=1,7 do distances["zn_"..i.."_trig"]=899 end
Update(0.1)
assert(count("BuildObject")==81, "seven zones must spawn exactly 81 units")
Update(0.1); assert(count("BuildObject")==81)
-- Bridge trigger remains ungated by convoySpawned.
distances.north_trig=349; Update(0.1); assert(s.objective2Complete and not s.convoySpawned)
health[s.bombs[0]]=0; Update(0.1); assert(count("MakeExplosion")==1)
Update(0.1); assert(count("MakeExplosion")==1)
-- Full pickups stay; depleted pickups refill once.
distances.ammo_1=4; curAmmo=100; Update(0.1); assert(s.ammo1~=nil)
curAmmo=10; Update(0.1); assert(s.ammo1==nil and curAmmo==100)
distances.repair_1=4; curHealth=100; Update(0.1); assert(s.repair1~=nil)
curHealth=10; Update(0.1); assert(s.repair1==nil and curHealth==100)
-- Completed loss audio schedules only once, including after save/load.
s=fresh(1,1); s.relicApc="relic"; distances.east_fail=49
Update(0.1); assert(s.lost and count("FailMission")==0)
done=true; Update(0.1); assert(count("FailMission")==1)
Load(Save()); Update(0.1); assert(count("FailMission")==1)
print("Chinese07: Lua 5.1 mission regression checks passed")
