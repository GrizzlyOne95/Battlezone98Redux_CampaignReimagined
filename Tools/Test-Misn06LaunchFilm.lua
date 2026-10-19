-- Real film helper: preplaced actor, camera ownership, timing, skip/save/loss.
local Film = assert(loadfile('Scripts/CR06LaunchFilm.lua'))()
local checks=0
local function check(v,why) assert(v,why);checks=checks+1 end
local function world()
    local w={now=100,ready=0,finished=0,removed=0,frames=0,fx=0,stops=0,
        pad={alive=true},rocket={alive=true}}
    local a={
        valid=function(h) return h and h.alive end,
        time=function() return w.now end,
        handle=function(label) check(label=='cr06_rocket','preplaced labelled actor');return w.rocket end,
        transform=function(h) check(h==w.rocket,'actor pose, not gantry pivot');return{posit_x=1000,posit_y=77,posit_z=2000}end,
        ready=function()w.ready=w.ready+1 end,
        camera=function(subject,x,y,z,target)
            check(subject==w.rocket and target==w.rocket,'steady tracking camera')
            w.cameraOffset={x,y,z}
            w.frames=w.frames+1
        end,
        finish=function()w.finished=w.finished+1 end,
        cancelled=function()return w.cancelled end,
        remove=function(h)check(h==w.rocket,'only rocket removed');h.alive=false;w.removed=w.removed+1 end,
        fxBegin=function(pose,age)w.fx=w.fx+1;w.age=age;check(pose.posit_y==77,'resume keeps original launch altitude')end,
        fxStop=function()w.stops=w.stops+1 end,
    }
    return w,a,{}
end
local w,a,s=world()
Film.Begin(s,a,w.pad);Film.Begin(s,a,w.pad);Film.Update(s,a)
check(w.ready==1 and w.frames==1 and w.fx==1,'one film and shared launch event')
w.now=105;Film.Update(s,a);check(w.fx==1,'launch event not resent every frame')
w.cancelled=true;Film.Update(s,a)
check(w.finished==1 and s.launchFilm.skipped,'offline skip releases camera')
w.now=108;Film.Update(s,a);Film.Load(s);Film.Update(s,a)
check(w.ready==1 and w.fx==2 and w.age==8,'load resumes flight without reopening skipped shot')
w.now=111;Film.Update(s,a)
check(s.launchFilm~=nil and w.removed==0,'rocket remains after film so it leaves above the horizon')
w.now=120;Film.Update(s,a);Film.Stop(s,a)
check(not s.launchFilm and w.removed==1 and w.finished==1 and w.stops==1 and w.pad.alive,'bounded cleanup keeps mission pad')
for _,lost in ipairs({'pad','rocket'})do
    w,a,s=world();Film.Begin(s,a,w.pad);Film.Update(s,a);w[lost].alive=false;Film.Update(s,a)
    check(not s.launchFilm and w.finished==1 and w.stops==1,'target loss closes owned film: '..lost)
end
w,a,s=world();Film.Begin(s,a,w.pad);Film.Update(s,a);Film.Load(s);Film.Update(s,a)
check(w.ready==2 and w.fx==2,'load reacquires local camera and restores shared effect age')
w.now=111;Film.Update(s,a)
check(w.finished==1 and s.launchFilm.viewDone,'natural shot finishes after eleven seconds')
Film.Load(s);Film.Update(s,a);check(w.ready==2,'loading completed view never reopens camera')
w,a,s=world();w.pad.alive=false;Film.Begin(s,a,w.pad)
check(w.ready==0 and s.launchFilmStarted,'missing pad skips insert')
w,a,s=world();w.rocket.alive=false;Film.Begin(s,a,w.pad);Film.Update(s,a)
check(w.ready==0 and not s.launchFilm,'old save without fixture never takes camera')
w,a,s=world();s.launchFilmTerminal=true;Film.Begin(s,a,w.pad)
check(not s.launchFilmStarted,'terminal mission cannot start another film')
w,a,s=world();a.terrain=function()return 0 end;Film.Begin(s,a,w.pad);Film.Update(s,a)
local start=w.cameraOffset
check(not s.launchFilm.highFallback and start[2]<0,'clear terrain uses the low view')
w.now=110;Film.Update(s,a)
check(w.cameraOffset[1]^2+w.cameraOffset[3]^2>start[1]^2+start[3]^2,'view pulls back during ascent')
w,a,s=world();a.terrain=function()return 1000 end;Film.Begin(s,a,w.pad);Film.Update(s,a)
check(s.launchFilm.highFallback and w.cameraOffset[2]>10000,'obstructed clearing retains high-shot fallback')
print('misn06 launch film checks passed: '..checks)
