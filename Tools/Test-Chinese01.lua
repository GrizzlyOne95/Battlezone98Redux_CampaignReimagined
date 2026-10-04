-- Run from repository root: lua5.1 Tools/Test-Chinese01.lua
dofile("Scripts/ch01.lua")
-- Offline stock-API mock: no engine gameplay validation is implied.
local now, nextHandle, timerStart, timerDuration, player = 0, 100, nil, nil, 1
local objects, labels, calls, done, info, distances, follows, cargo = {}, {}, {}, {}, false, {}, false, nil
local function record(name, ...) calls[#calls+1] = {name, ...} end
local function object(label)
    if labels[label] then return labels[label] end
    nextHandle = nextHandle + 1
    local h = nextHandle
    labels[label] = h
    objects[h] = {health=1, odf=label, team=2, valid=true}
    return h
end
objects[1] = {health=1, valid=true, odf='cvfigh', team=1}
function GetHandle(label) return object(label) end
function GetPlayerHandle() return player end
function GetTime() return now end
function IsValid(h) return objects[h] ~= nil and objects[h].valid end
function IsAlive(h) return IsValid(h) and objects[h].health > 0 end
function GetHealth(h) assert(IsValid(h)); return objects[h].health end
function GetOdf(h) assert(IsValid(h)); return objects[h].odf end
function IsInfo(odf) assert(type(odf)=='string'); return info end
function IsDeployed(h) assert(IsValid(h)); return objects[h].deployed or false end
function GetTeamNum(h) assert(IsValid(h)); return objects[h].team end
function IsFollowing(h, who) assert(IsValid(h) and IsValid(who)); return follows end
function GetCargo(h) assert(IsValid(h)); return cargo end
function GetPosition(path, point) assert(type(path)=='string' and point==0); return {x=10,y=20,z=30} end
function GetDistance(h, target, point)
    assert(IsValid(h))
    assert(type(target)=='string' or IsValid(target))
    return distances[tostring(h)..':'..tostring(target)] or 10000
end
function BuildObject(odf, team, where, point)
    assert(type(where)=='string' or type(where)=='table' or IsValid(where))
    if type(where)=='string' and point~=nil then assert(point==0) end
    record('BuildObject',odf,team,where,point)
    local h = object('spawn_'..tostring(nextHandle+1))
    objects[h].odf, objects[h].team = odf,team
    return h
end
function AudioMessage(file)
    local h = #calls+1000
    record('AudioMessage',file,h)
    return h
end
function IsAudioMessageDone(h) return done[h] or false end
function StartCockpitTimer(duration,warn,alert)
    timerStart,timerDuration = now,duration; record('StartCockpitTimer',duration,warn,alert)
end
function GetCockpitTimer() return timerDuration and math.ceil(timerDuration-(now-timerStart)) or 0 end
function CameraReady() record('CameraReady'); return true end
function CameraPath(path,height,speed,target) assert(IsValid(target)); record('CameraPath',path,height,speed,target); return false end
function CameraCancelled() return false end
function CameraFinish() record('CameraFinish'); return true end
function MakeExplosion(effect,path) assert(effect=='xpltrsn' and path=='spawn_explosion1'); record('MakeExplosion',effect,path) end
for _,name in ipairs({'SetScrap','SetPilot','EnableAllCloaking','SetName','ClearObjectives','AddObjective','AddScrap','SetPerceivedTeam','SetIndependence','SetObjectiveOn','HideCockpitTimer','ColorFade','FailMission','SucceedMission'}) do
    _G[name]=function(...) record(name,...) end
end
for _,name in ipairs({'Goto','Attack','Defend2'}) do
    _G[name]=function(h,target,priority) assert(IsValid(h)); assert(type(target)=='string' or IsValid(target)); record(name,h,target,priority) end
end
local function count(name, value)
    local n=0
    for _,c in ipairs(calls) do if c[1]==name and (value==nil or c[2]==value) then n=n+1 end end
    return n
end
local function near(h,target,d) distances[tostring(h)..':'..tostring(target)] = d end
local function tick(t) now=t; Update(0.1) end
local function state() return Save() end
local function finish(field) done[state()[field]]=true end
local function reset()
    now,calls,distances,done,info,follows,cargo,timerStart,timerDuration = 0,{},{},{},false,false,nil,nil,nil
    for _,o in pairs(objects) do o.health,o.valid,o.deployed=1,true,false end
    Start()
end

-- Full normal flow: exact strict timer boundaries, wave counts, aerial heights.
reset();tick(0);assert(count('EnableAllCloaking')==1 and state().openingSoundTime==5)
tick(5);assert(count('AudioMessage','ch01001.wav')==0)
tick(5.1);finish('openingSound');tick(5.2);assert(count('BuildObject','apcamr')==1)
info=true;tick(6);finish('hangarSound');tick(7);assert(state().armourySoundTime==22)
tick(22);assert(count('AudioMessage','ch01003.wav')==0)
tick(22.1);finish('armourySound');tick(22.2);assert(count('BuildObject','cvslfb')==1)
objects[state().commTower].health=0;tick(23);objects[state().recycler].deployed=true;tick(24)
tick(84);assert(count('BuildObject','svfigh')==0)
tick(84.1);assert(count('BuildObject','svfigh')==4 and count('BuildObject','svtank')==4)
tick(384.2);assert(count('BuildObject','svtank')==8 and count('BuildObject','svltnk')==3)
tick(684.3);assert(count('BuildObject','svtank')==17 and count('BuildObject','svhraz')==3)
tick(864.4);assert(count('BuildObject','sspilo')==6)
tick(894.5);assert(count('BuildObject','sssold')==4)
tick(954.6);assert(count('BuildObject','svtank')==21 and count('BuildObject','svhraz')==7)
tick(1074.7);assert(count('BuildObject','svhaula')==1 and count('Defend2')==2)
near(state().tug,'nav_tug',999);tick(1075);assert(state().tugNearNav)
objects[state().tug].team=1;near(state().tug,state().recycler,74);tick(1076)
assert(state().objective3Complete and count('BuildObject','svturrb')==4)
assert(count('BuildObject','svtank')==25 and count('BuildObject','svhraz')==11 and count('BuildObject','svltnk')==11)
near(1,state().detectors[0],149);follows=true;tick(1077)
assert(state().arialsSpawned and not state().lost and count('BuildObject','sspilo')==10 and count('BuildObject','sssold')==10)
for _,c in ipairs(calls) do if c[1]=='BuildObject' and (c[2]=='sspilo' or c[2]=='sssold') then assert(c[4].y==220 or c[4].y==120) end end
cargo=state().relic;tick(1078);assert(state().objective4Complete and timerDuration==180)
near(1,state().detectors[0],299);tick(1079);assert(count('BuildObject','cvhtnk')==7)
near(state().navEnd,state().hangar,1000);near(1,state().hangar,951);near(state().relic,state().hangar,951)
tick(1256);assert(count('CameraReady')==1)
tick(1257);assert(count('CameraPath')>=2)
tick(1258);assert(count('SucceedMission')==1 and state().won and count('MakeExplosion')==1)
tick(1261);assert(count('CameraFinish')==1 and count('SucceedMission')==1)
print('PASS: full success, all waves, strict timers, aerial heights, escort/decoys, explosion and camera cleanup')

-- Save/resume preserves the live event clock and does not rerun startup.
reset();tick(0);tick(5.1);local saved=Save();local sound=saved.openingSound
Start();Load(saved);assert(Save().openingSound==sound and Save().startDone)
done[sound]=true;tick(6);assert(count('EnableAllCloaking')==1 and count('BuildObject','apcamr')==1)
print('PASS: Save/Load during opening audio')

reset();tick(0);local m=state();m.tug=BuildObject('svhaula',2,'relic_tug');objects[m.tug].valid=false;tick(1)
assert(m.lost);finish('failedSound');tick(2);assert(count('FailMission')==1 and calls[#calls][3]=='ch01lseb.des')
print('PASS: deleted tug failure')
reset();tick(0);m=state();m.tug=BuildObject('svhaula',2,'relic_tug');near(m.tug,'tug_fail',349);tick(1)
assert(m.lost and count('FailMission')==1)
print('PASS: escaped enemy tug failure')
reset();tick(0);m=state();m.recycler=BuildObject('cvrecyd',1,'recycler');objects[m.recycler].valid=false;tick(1)
assert(m.lost and count('FailMission')==1)
print('PASS: deleted recycler failure')
reset();tick(0);m=state();m.objective3Complete=true;m.escort1=BuildObject('svfigh',1,'fighters');m.escort2=BuildObject('svfigh',1,'fighters')
near(1,m.detectors[0],149);tick(1);assert(m.lost and m.arialsSpawned);finish('detectedSound');tick(2);assert(count('FailMission')==1)
m.objective4Complete=true;m.doingExplosion=false;m.relic=BuildObject('obdata',0,'relic_loc');m.navEnd=BuildObject('apcamr',1,'nav_end')
near(m.navEnd,m.hangar,1000);near(m.relic,m.hangar,2000);tick(3);assert(count('SucceedMission')==0 and count('FailMission')==1)
print('PASS: detection failure cannot be overwritten by later evacuation')
reset();tick(0);m=state();m.objective4Complete=true;m.relic=BuildObject('obdata',0,'relic_loc');m.navEnd=BuildObject('apcamr',1,'nav_end')
near(m.navEnd,m.hangar,1000);near(m.relic,m.hangar,950);tick(1);assert(m.lost and count('FailMission')==1 and count('MakeExplosion')==1)
print('PASS: relic exactly at safety boundary fails (native strict >)')
reset();tick(0);m=state();m.objective4Complete=true;m.relic=BuildObject('obdata',0,'relic_loc');m.navEnd=BuildObject('apcamr',1,'nav_end');objects[m.relic].valid=false
near(m.navEnd,m.hangar,1000);tick(1);assert(m.lost and count('SucceedMission')==0)
print('PASS: destroyed relic does not count as safely evacuated')
