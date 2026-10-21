-- Real tree streamer/weather logic against a recording world; no native game.
package.path="Scripts/?.lua;"..package.path
local checks=0
local function check(v,msg) checks=checks+1;assert(v,msg) end
local function copy(v) if type(v)~="table" then return v end;local t={};for k,a in pairs(v) do t[k]=copy(a) end;return t end
local world,id,scans,builds,damage,transforms,removed,culls={},0,0,0,0,0,0,0
function IsValid(h) return world[h] and not world[h].dead end
function GetLabel(h) return world[h].label end
function GetOdf(h) return world[h].odf..".odf" end
function SetLabel(h,label) world[h].label=label end
function BuildPositionRotationMatrix(p,y,r,x,yy,z) return {pitch=p,yaw=y,roll=r,position={x=x,y=yy,z=z}} end
function BuildObject(odf,team,m) id=id+1;builds=builds+1;world[id]={odf=odf,team=team,m=copy(m),label=""};return id end
function Damage(h,n) check(n>=2500,"weather kills the 2500-hull plant");damage=damage+1;world[h].dead=true end
function RemoveObject(h) removed=removed+1;world[h].dead=true end
function SetTransform(h,m) transforms=transforms+1;world[h].m=m end
function AllObjects()
    scans=scans+1;local k=0
    return function() repeat k=k+1 until k>id or IsValid(k);if k<=id then return k end end
end
local x={SetEntityRenderingDistance=function(h,d) check(d==300,"fog cull distance");culls=culls+1 end}
local Trees=require("CRStorm18Trees")
local sites={}
for i,p in ipairs({{320,0,0},{350,0,0},{410,0,0},{900,0,0}}) do
    sites[i]={label="cr18_tree"..i,odf="c17frst1",yaw=.2,position=p}
end
local t=Trees.Create({sites=sites,exu=x});local saved=t.Reset()
local players={{x=0,z=0}}
t.Update(.1,false,players);check(builds==0 and scans==0,"guest builds/scans nothing")
check(t.Strike(320,0,false)==0,"guest cannot damage trees")
t.Update(.1,true,players);check(builds==2 and scans==1,"first slice builds at most two and recovers once")
local before=builds;local positionsRead=0
t.Update(.001,true,function() positionsRead=positionsRead+1;return players end)
check(builds==before and positionsRead==0,"same-slice update does no world/position work")
check(t.Strike(320,0,true)==1 and saved.gone[1] and damage==1,"nearby lightning destroys only matching tree")
check(t.Strike(320,0,true)==0,"repeat lightning is idempotent")
t.Update(.1,true,players,{x=350,z=0,t=10})
check(saved.gone[2] and saved.falling[2] and damage==1,"funnel starts a persistent uproot")
t.Update(.1,true,players)
check(transforms>0 and world[2].m.position.y>0 and world[2].m.pitch>0,"actual tree is lifted and tipped")
-- Recover the same world from a save made mid-uproot, with fresh runtime caches.
t=Trees.Create({sites=sites,exu=x});saved=t.Reset(copy(saved))
t.Update(.1,true,players)
for _=1,15 do t.Update(.1,true,players) end
check(saved.gone[1] and saved.gone[2] and not saved.falling[2] and not IsValid(2),"mid-uproot load finishes death without regrowth")
check(scans==2,"exactly one recovery scan per load")
local b=builds
-- Offscreen tree sites are scarred too, even though no object exists to damage.
check(t.Strike(900,0,true)==1 and saved.gone[4],"lightning persists on an unstreamed site")
-- Combat deaths are distinguished from intentional streaming unloads.
local third
for h,o in pairs(world) do if o.label==sites[3].label and IsValid(h) then third=h end end
check(third~=nil,"third site streamed")
world[third].dead=true
t.Update(.2,true,players);check(saved.gone[3],"combat-killed tree stays gone")
t.Update(.2,true,{{x=550,z=0}});check(builds==b,"gone trees never rebuild on revisit")
-- Populated ring: global and per-slice object budgets, unload/revisit and reset.
world,id,scans,builds,damage,transforms,removed,culls={},0,0,0,0,0,0,0
sites={}
for i=1,300 do local a=i*math.pi*2/300;sites[i]={label="cr18_tree"..i,odf="c17frst2",yaw=0,position={350*math.cos(a),0,350*math.sin(a)}} end
t=Trees.Create({sites=sites,exu=x});saved=t.Reset()
for _=1,180 do
    local b0=builds;t.Update(.11,true,players)
    check(builds-b0<=2 and t.Describe().live<=256,"stream construction budgets")
end
check(t.Describe().live==256,"live-object cap enforced")
local r0=removed;t.Update(.11,true,{{x=4000,z=0}})
check(removed-r0<=4 and removed>r0,"unload is separately budgeted")
local i=next(saved.live);local h
for k,o in pairs(world) do if o.label==sites[i].label and IsValid(k) then h=k end end
check(h~=nil,"live handle is owned")
local goneBefore=next(saved.gone);check(goneBefore==nil,"streaming did not mark deaths")
local c0=t.Describe().candidates;t.Update(.3,true,players,{x=350,z=0,t=10})
check(t.Describe().candidates-c0<=64 and t.Describe().falling<=8,"funnel query and moving-tree budgets")
check(scans==1,"combat never scans AllObjects again")
-- Real generated grid stays within the fixed weather query budget.
local real=require("CRStorm18TreesSites").sites;local cells={}
for _,p in ipairs(real) do
    local k=math.floor(p.position[1]/64)..":"..math.floor(p.position[3]/64)
    cells[k]=(cells[k] or 0)+1;check(cells[k]<=4,"authored cell occupancy")
end
check(#real>500 and #real<1500,"forest has a bounded authored footprint")
print("CRSTORM18 TREES OK ("..checks.." checks)")
