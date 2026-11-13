-- Crystal reconstruction tests use the real module, including haul observations.
assert(_VERSION=="Lua 5.1")
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
local function fixture()
    local f={now=0,objects={},labels={},voices={},events={},marks={},objectives={},damage=0}
    local m={cr17={},towersdestroyed=false}
    local nextHandle=0
    function f.add(label,team,x,z)
        nextHandle=nextHandle+1
        f.objects[nextHandle]={alive=true,team=team or 0,x=x or 0,y=0,z=z or 0}
        if label then f.labels[label]=nextHandle end
        return nextHandle
    end
    for i=1,5 do f.add("cr17_raw"..i,0,100+i*30,0) end
    f.add("cr17_processed",0,400,0)
    f.refinery=f.add("cr17_refinery",0,500,0)
    f.receiver=f.add("cr17_receiver",6,1000,0)
    f.player=f.add("player",2,0,0)
    f.tug=f.add("tug",2,0,0)
    for i=1,3 do m["factorypart"..i]=f.add("factory"..i,6,1500,0) end
    local function valid(h) return f.objects[h]~=nil and f.objects[h].alive end
    local env=setmetatable({
        GetTime=function() return f.now end,
        GetHandle=function(label) return f.labels[label] end,
        IsValid=valid,IsAlive=valid,
        GetPlayerHandle=function() return f.player end,
        GetTeamNum=function(h) return f.objects[h].team end,
        GetTug=function(h) return f.objects[h].tug end,
        GetDistance=function(a,b)
            local p,q=f.objects[a],f.objects[b]
            return math.sqrt((p.x-q.x)^2+(p.z-q.z)^2)
        end,
        GetPosition=function(h) return f.objects[h] end,
        SetVector=function(x,y,z) return {x=x,y=y,z=z} end,
        BuildObject=function(odf,team,p)
            f.builds=(f.builds or 0)+1
            if f.rejectBuild then return nil end
            local h=f.add(nil,team,p.x,p.z);f.objects[h].odf=odf;return h
        end,
        SetLabel=function(h,label) f.labels[label]=h end,
        Damage=function(h) f.objects[h].alive=false;f.damage=f.damage+1 end,
    },{__index=_G})
    local api={state=function() return m end,human=function(t) return t>=1 and t<=4 end,
        off=function() end,remove=function(h) f.objects[h].alive=false end,
        voice=function(v) f.voices[#f.voices+1]=v end,
        anyNear=function() return f.discovered end,
        mark=function(h) f.marks[h]=true end,name=function() end,
        cargo=function(label,kind) f.events[#f.events+1]={label,kind} end,
        objective=function(id,color,duration,text,add) f.objectives[#f.objectives+1]={text=text,add=add} end}
    local module=setfenv(assert(loadfile("Scripts/CRCrystals17.lua")),env)()
    f.C=module.Create(api);f.C.Reset()
    function f.state() return m.cr17Crystals end
    function f.M() return m end
    function f.restore(saved)
        m=saved;f.C=module.Create(api);f.C.Reset()
    end
    function f.move(label,target)
        local p,q=f.objects[f.labels[label]],f.objects[target];p.x=q.x;p.z=q.z
    end
    function f.deliver(label,target,team)
        local c=f.objects[f.labels[label]];c.tug=f.tug
        f.C.Report(team or 2,label,true)
        c.tug=nil;f.move(label,target);f.C.Report(team or 2,label,false);f.C.Update()
    end
    return f
end

local f=fixture();f.move("cr17_raw1",f.receiver);f.M().towersdestroyed=true;f.C.Update()
check(f.state().phase=="ready" and f.objects[f.labels.cr17_raw1].alive,"proximity alone cannot install cargo")
f.C.Report(6,"cr17_raw1",true);f.C.Report(6,"cr17_raw1",false);f.C.Update()
check(not f.state().cargo.cr17_raw1.team,"enemy team cannot submit cargo")
f.C.Report(2,"unknown",true)
check(f.state().cargo.unknown==nil,"unknown cargo rejected")
f.C.Report(2,"cr17_raw1",true);f.objects[f.labels.cr17_raw1].tug=f.tug;f.C.Report(2,"cr17_raw1",false);f.C.Update()
check(f.state().phase=="ready","native tug attachment blocks a claimed drop")
f.objects[f.labels.cr17_raw1].tug=nil;f.now=5;f.C.Update()
check(f.state().phase=="ready","stale drop reports cannot activate a receiver")
f.C.Report(2,"cr17_raw1",false);f.C.Update()
check(f.state().phase=="overload" and f.state().deadline==25,"fresh human raw delivery starts twenty second overload")
check(not f.objects[f.labels.cr17_raw1].alive and f.state().cargo.cr17_raw1.consumed,"installed cargo consumed exactly once")
local voices=#f.voices;f.C.Update();check(#f.voices==voices,"consumed cargo cannot replay install VO")
f.now=24.9;f.C.Update();check(f.damage==0,"converter damage waits for overload deadline")
f.now=25;f.C.Update();check(f.damage==3 and f.state().sabotaged,"overload destroys all existing converter handles")
f.C.Update();check(f.damage==3,"sabotage damage runs once")

f=fixture();f.deliver("cr17_raw1",f.receiver)
check(f.state().phase=="ready" and f.objects[f.labels.cr17_raw1].alive,"receiver waits for tower gate")
f.M().towersdestroyed=true;f.deliver("cr17_raw1",f.receiver)
f.now=10;f.deliver("cr17_processed",f.receiver)
check(f.state().phase=="ready" and not f.state().deadline and not f.M().crysswitched,"processed crystal cancels overload")
check(f.voices[#f.voices]=="misn1705.wav","stabilization VO plays")
f.now=30;f.C.Update();check(f.damage==0,"stabilized converters remain alive past old deadline")
f.deliver("cr17_raw2",f.receiver);check(f.state().phase=="overload","remaining raw crystal can restart sabotage")
f.M().missionfail=true;f.now=60;f.C.Update();check(f.damage==0,"recycler failure prevents pending sabotage")

f=fixture();f.deliver("cr17_raw1",f.refinery)
check(f.state().processing.ready==12 and f.state().cargo.cr17_raw1.consumed,"refinery consumes legitimately hauled raw cargo")
f.now=11.9;f.C.Update();check(not f.builds,"refinery waits twelve seconds")
f.rejectBuild=true;f.now=12;f.C.Update();check(f.state().processing~=nil,"failed output spawn retains processing request")
f.rejectBuild=false;f.C.Update()
check(f.state().processing==nil and f.labels.cr17_prod1~=nil,"successful retry creates labeled processed cargo")
check(f.events[1][1]=="cr17_prod1" and f.events[1][2]=="processed","output label announced to guests")
check(f.state().cargo.cr17_prod1.kind=="processed","output registered for later hauling")
local builds=f.builds;f.C.Update();check(f.builds==builds,"completed refinery batch cannot duplicate output")
f.C.AddCargo("injected","processed");check(not f.state().cargo.injected,"arbitrary cargo labels rejected")
f.C.AddCargo("cr17_prod9","raw");check(not f.state().cargo.cr17_prod9,"generated cargo must be processed")

f=fixture();f.deliver("cr17_raw1",f.refinery);f.objects[f.refinery].alive=false;f.now=12;f.C.Update()
check(not f.state().processing and not f.builds,"destroyed refinery cannot create output")
check(not f.M().missionfail,"lost optional refinery leaves stock victory available")

f=fixture();f.M().towersdestroyed=true;f.now=10;f.deliver("cr17_raw1",f.receiver)
local saved=f.M();f.restore(saved);f.now=29;f.C.Update()
check(f.state().deadline==30 and f.damage==0,"load keeps original overload deadline")
f.now=30;f.C.Update();check(f.damage==3,"saved overload completes at original deadline")
f=fixture();f.deliver("cr17_raw1",f.refinery);saved=f.M();f.restore(saved);f.now=12;f.C.Update()
check(f.labels.cr17_prod1 and #f.events==1,"load resumes one pending refinery batch")

f=fixture();local sent={};local function send(label,towing) sent[#sent+1]={label,towing} end
f.objects[f.labels.cr17_raw1].tug=f.tug;f.C.Poll(false,send)
check(#sent==1 and sent[1][1]=="cr17_raw1" and sent[1][2],"guest reports its own haul")
check(not f.state().cargo.cr17_raw1.team,"guest polling cannot directly mutate accepted delivery state")
f.now=.8;f.objects[f.labels.cr17_raw1].tug=nil;f.C.Poll(false,send)
check(#sent==2 and sent[2][2]==false,"guest sends release after observed hauling")
f.now=1.6;f.C.Poll(false,send);check(#sent==2,"idle cargo produces no repeated release messages")
f.objects[f.tug].team=3;f.objects[f.labels.cr17_raw2].tug=f.tug;f.now=2.4;f.C.Poll(false,send)
check(#sent==2,"guest does not report another human team's tug")
f.C.Poll(true,send);f.now=3.2;f.C.Poll(true,send)
check(f.state().cargo.cr17_raw2.team==3,"leader observes all human tugs")
f.objects[f.labels.cr17_raw2].tug=nil;f.now=4;f.C.Poll(true,send)
check(f.state().cargo.cr17_raw2.towing==false,"leader observes release directly")

f=fixture();f.discovered=true;f.C.Update();check(f.voices[1]=="misn1706.wav","discovery starts cut instruction VO")
f.now=8;f.C.Update();check(#f.voices==1,"hints do not overlap")
f.now=9;f.C.Update();f.now=18;f.C.Update()
check(f.voices[2]=="misn1707.wav" and f.voices[3]=="misn1708.wav","instruction sequence completes in order")
check(f.marks[f.refinery] and f.marks[f.receiver],"discovery marks both logistics stations")
check(f.objectives[1].add,"optional objective initially added")
local count=#f.objectives;f.C.Update();check(#f.objectives==count,"unchanged objective not repainted")
f.M().cr17ObjectiveRevision=1;f.C.Update();check(f.objectives[#f.objectives].add,"primary objective clear restores optional objective")
for i=1,5 do f.objects[f.labels["cr17_raw"..i]].alive=false end
f.C.Update();check(f.objectives[#f.objectives].text:find("Destroy the three factory",1,true),"lost cargo directs players to stock fallback")
check(not f.M().missionfail,"cargo loss never fails required mission")
print("misn17 crystals: "..checks.." checks passed")
