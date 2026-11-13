-- The real concealed plant streamer; no craft AI setters are available here.
assert(_VERSION=="Lua 5.1")
local checks,now,builds,labels=0,0,0,{}
local function check(v,s) assert(v,s);checks=checks+1 end
local sites={}
for i=1,40 do sites[i]={odf="c17tree1",position={i*10,2,100000},label="tree"..i,preplaced=i==1 and 1 or 0} end
local m={cr17={},openingcindone=true}
local authority,safe,reject=true,false,false
local env=setmetatable({
    require=function(name) assert(name=="CRJungle17Sites");return {trees=sites} end,
    GetTime=function() return now end,
    SetVector=function(x,y,z) return {x=x,y=y,z=z} end,
    BuildObject=function(odf,team,p)
        check(odf=="c17tree1" and team==0,"plants remain neutral")
        check(safe,"plant creation requires safe visibility guard")
        builds=builds+1;return reject and 0 or builds
    end,
    IsValid=function(h) return h>0 end,
    SetLabel=function(h,label) check(not labels[label],"completed plant never created twice");labels[label]=h end,
},{__index=_G})
local module=setfenv(assert(loadfile("Scripts/CRJungleTrees17.lua")),env)()
local api={state=function() return m end,authority=function() return authority end,safe=function() return safe end}
local T=module.Create(api)
T.Update();check(builds==0,"watched sites remain queued")
authority=false;safe=true;now=1;T.Update();check(builds==0,"guests never create gameplay plants")
authority=true;m.openingcindone=false;T.Update();check(builds==0,"intro camera suppresses streaming")
m.openingcindone=true;m.minecinstart=true;T.Update();check(builds==0,"mine film suppresses streaming")
m.minecinstart=false;m.coopResult="FailMission";T.Update();check(builds==0,"shared result suppresses streaming")
m.coopResult=nil;T.Update();check(builds==2,"one update creates at most two plants")
check(not labels.tree1,"preplaced plant excluded from creation")
local count=builds;T.Update();check(builds==count,"cadence prevents repeated same-frame creation")
for _=1,25 do now=now+.1;T.Update() end
check(m.cr17.treeStream.built==39 and builds==39,"all concealed non-preplaced sites eventually built")
T=module.Create(api);now=now+1;T.Update();check(builds==39,"saved completed sites survive runtime reconstruction")
check(m.cr17.treeStream.done[1],"preplaced site recorded without native construction")
local saved=m.cr17.treeStream;m={cr17={treeStream=saved},openingcindone=true};T=module.Create(api)
now=now+1;T.Update();check(builds==39,"restored mission state cannot duplicate plants")
print("misn17 trees: "..checks.." checks passed")
