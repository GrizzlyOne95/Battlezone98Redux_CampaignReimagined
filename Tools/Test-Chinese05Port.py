from lupa.lua51 import LuaRuntime
from pathlib import Path
# Requires the Lupa package with its Lua 5.1 runtime: python Tools/Test-Chinese05Port.py
root = Path(__file__).resolve().parents[1]
script = (root / 'Scripts/ch05.lua').read_text()
harness=r'''
now=0; scrap=0; calls={}; distances={}; objects={}; counter=0
function record(name, ...) calls[#calls+1]={name,...} end
function GetTime() return now end
function GetHandle(label) objects[label]=true;return label end
function GetPlayerHandle() return 'user' end
objects.user=true
function BuildObject(odf,team,pos,point)
 assert(point==nil,'Lua point index used as altitude')
 counter=counter+1;local h=odf..counter;objects[h]=true;record('build',odf,team,pos,h);return h
end
function IsAlive(h) return h~=nil and objects[h]==true end
function IsValid(h) return IsAlive(h) end
function GetDistance(a,b) if not objects[a] then return 1e30 end; return distances[a..'|'..tostring(b)] or (b=='trigger_1' and 1000 or 200) end
function GetTug(h) return cargoTug end
function GetScrap(t) return scrap end
function SetScrap(t,n) scrap=n;record('scrap',t,n) end
function AudioMessage(s) record('audio',s);return s end
function IsAudioMessageDone(s) return audioDone==true end
function CameraCancelled() return cancelled==true end
function RemoveObject(h) objects[h]=false;record('remove',h) end
function GetClassSig(h) return signatures[h] or 'avtk' end
function GetClassLabel(h) return classes[h] or 'hover' end
signatures={};classes={}
function AllObjects() local a={};for h,alive in pairs(objects) do if alive then a[#a+1]=h end end;local i=0;return function() i=i+1;return a[i] end end
function GetPosition(p) return {x=1,y=20,z=3} end
function SetVector(x,y,z) return {x=x,y=y,z=z} end
for _,name in ipairs({'SetPilot','SetPerceivedTeam','ClearObjectives','AddObjective','Stop','Goto','Formation','SetName','SetUserTarget','RemovePilot','Defend2','Pickup','CameraReady','CameraPath','CameraFinish','SetObjectiveOn','SetObjectiveOff','Follow','Attack','FailMission','SucceedMission'}) do
 _G[name]=function(...) record(name,...) end
end
function tick(t) now=t;Update(0.1) end
function count(name,arg) local n=0;for _,c in ipairs(calls) do if c[1]==name and (arg==nil or c[2]==arg) then n=n+1 end end;return n end
'''
def env():
 l=LuaRuntime();l.execute(harness);l.execute(script);l.execute('Start()');return l
l=env();l.execute('''
tick(0);assert(Save().wave7Time==999999.9);assert(count('build')==0)
scrap=3;tick(1);assert(count('build','cvfighh')==4)
local s=Save(); distances[s.leadScout..'|trigger_1']=20;tick(2);assert(Save().trigger1)
audioDone=true;tick(3.1);tick(8.2);assert(Save().objective1Complete)
distances['user|trigger_1']=399;tick(9);local s=Save();assert(s.tugSpawned)
objects.scrapA=true;classes.scrapA='scrap';objects.nsA=true;signatures.nsA='nsp';objects.keep=true
cargoTug=s.tug;tick(9.6);assert(Save().doHaulCam);assert(Save().mustBeCloseToTug)
local s=Save();Load(s);assert(Save().doHaulCam and Save().openingSound==nil)
cancelled=true;tick(9.7);assert(not objects.scrapA and objects.keep)
distances[s.tug..'|trigger_2']=100;tick(10);tick(15.1);tick(20.2);tick(22.3)
assert(not objects.nsA and objects.keep);assert(Save().factory);assert(scrap==50)
tick(32.4);assert(count('SetPerceivedTeam')>0)
tick(262.4);assert(Save().wave1Time==262.4);tick(262.5);assert(count('build','svwalk')==2)
local aerial=0;for _,c in ipairs(calls) do if c[1]=='build' and c[2]=='sssold' and type(c[4])=='table' then assert(c[4].y==420);aerial=aerial+1 end end;assert(aerial==8)
local origin=262.4
for _,offset in ipairs({120,300,480,540,720,900,960,1020,1200,1320,1340}) do tick(origin+offset+0.1) end
assert(Save().numMustKill==13 and Save().wave7Spawned);assert(count('SucceedMission')==0)
for i=0,12 do objects[Save().mustKill[i]]=false end;tick(origin+1341);assert(count('SucceedMission','ch05win.des')==0);assert(count('SucceedMission')==1)
local waveCounts={7,9,7,10,13,8,13}
for n,expected in ipairs(waveCounts) do local total=0;for _,c in ipairs(calls) do if c[1]=='build' and c[4]=='wave_'..n then total=total+1 end end;assert(total==expected,'wave '..n..' count '..total) end
assert(count('build','apwrck')==8)
''')
print('PASS full mission sequence, wave composition, all Daywreckers, altitude, removal snapshot, active-camera save/load, final-wave victory')
for code,setup in [('ch05lsea.des',"distances['user|silo']=251"),('ch05lseb.des',"local s=Save();s.tugSpawned=true;s.tug='tug';objects.tug=true;distances['user|tug']=174"),('ch05lsed.des',"local s=Save();s.tugSpawned=true;s.mustBeCloseToTug=true;s.tug='tug';objects.tug=true;distances['user|tug']=501"),('ch05lsec.des',"local s=Save();s.factory='factory';objects.recycler=false;objects.factory=false")]:
 l=env();l.execute('tick(0);'+setup+';tick(1);assert(count("FailMission")==1);assert(calls[#calls][3]=="'+code+'");tick(2);assert(count("FailMission")==1)');print('PASS loss',code)
l=env();l.execute('tick(0);local s=Save();s.artl1="a";s.artl2="b";s.day7Time=100;s.day8Time=120;tick(1);assert(s.day7Time==999999.9 and s.day8Time==999999.9)');print('PASS artillery destruction cancels future Daywreckers')
archive = script.split('Original C++ source, including every comment, disabled block and save/load wrapper.\n', 1)[1]
assert '#if 0' in archive and 'strnicmp(buf, "nsp", 2)' in archive
assert '//\tif (GetHealth(silo)' in archive
print('PASS cut/debug source archive retained')
l=env();l.execute('tick(0);tick(3.1);local s=Save();assert(s.openingSound=="ch05001.wav");Load(s);assert(Save().openingSound=="ch05001.wav");audioDone=true;tick(3.2);assert(Save().openingSound==nil)');print('PASS pending audio save/load continuation')
