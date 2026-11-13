-- Mission 06's launch film helper, configured for the Mission 03 NSDF rocket:
-- fixture label, half-height terrain probe, eleven-second shot, skip/save/loss.
local Film = assert(loadfile('Scripts/CR06LaunchFilm.lua'))()
local Layout = assert(loadfile('Scripts/CR03RocketLayout.lua'))()
local checks=0
local function check(v,why) assert(v,why);checks=checks+1 end
local function world()
    local w={now=100,ready=0,finished=0,removed=0,frames=0,fx=0,stops=0,
        pad={alive=true},rocket={alive=true}}
    local a={
        label='cr03_rocket', halfHeight=-Layout.nozzleY,
        valid=function(h) return h and h.alive end,
        time=function() return w.now end,
        handle=function(label) check(label=='cr03_rocket','the NSDF fixture is the actor');return w.rocket end,
        transform=function(h) check(h==w.rocket,'actor pose');return{posit_x=1000,posit_y=120,posit_z=2000}end,
        ready=function()w.ready=w.ready+1 end,
        camera=function(subject,x,y,z,target)
            check(subject==w.rocket and target==w.rocket,'steady tracking camera on cr03_rocket')
            w.cameraOffset={x,y,z};w.frames=w.frames+1
        end,
        finish=function()w.finished=w.finished+1 end,
        cancelled=function()return w.cancelled end,
        remove=function(h)check(h==w.rocket,'only the rocket is removed');h.alive=false;w.removed=w.removed+1 end,
        fxBegin=function(pose,age)w.fx=w.fx+1;w.age=age;check(pose.posit_y==120,'resume keeps the original launch altitude')end,
        fxStop=function()w.stops=w.stops+1 end,
    }
    return w,a,{}
end
local w,a,s=world()
Film.Begin(s,a,w.pad);Film.Begin(s,a,w.pad);Film.Update(s,a)
check(w.ready==1 and w.frames==1 and w.fx==1,'one film and one shared launch event')
check(s.launchFilm.started==100,'the start time is state, so it survives a save')
w.now=105;Film.Update(s,a);check(w.fx==1,'launch event not resent every frame')
w.cancelled=true;Film.Update(s,a)
check(w.finished==1 and s.launchFilm.skipped,'offline skip releases the camera')
w.now=108;Film.Update(s,a);Film.Load(s);Film.Update(s,a)
check(w.ready==1 and w.fx==2 and w.age==8,'load resumes the flight at its age without reopening a skipped shot')
w,a,s=world();Film.Begin(s,a,w.pad);Film.Update(s,a);w.now=105;Film.Update(s,a);Film.Load(s);Film.Update(s,a)
check(w.ready==2 and w.fx==2 and w.age==5,'mid-launch load re-acquires the camera and the effect age')
w.now=111;Film.Update(s,a)
check(w.finished==1 and s.launchFilm.viewDone,'the shot releases its own camera after eleven seconds')
w.now=120;Film.Update(s,a)
check(s.launchFilm==nil and w.removed==1 and w.stops==1 and w.pad.alive,'the 20 s flight ends with a bounded cleanup')
for _,lost in ipairs({'pad','rocket'})do
    w,a,s=world();Film.Begin(s,a,w.pad);Film.Update(s,a);w[lost].alive=false;Film.Update(s,a)
    check(not s.launchFilm and w.finished==1 and w.stops==1,'target loss closes the owned film: '..lost)
end
w,a,s=world();w.pad.alive=false;Film.Begin(s,a,w.pad)
check(w.ready==0 and s.launchFilmStarted,'a missing pad skips the shot')
w,a,s=world();w.rocket.alive=false;Film.Begin(s,a,w.pad);Film.Update(s,a)
check(w.ready==0 and not s.launchFilm,'an older map without the fixture never takes the camera')
w,a,s=world();s.launchFilmTerminal=true;Film.Begin(s,a,w.pad)
check(not s.launchFilmStarted,'a finished mission cannot start another film')
-- The clearing probe uses the NSDF rocket's own half-height, not misn06's 48.5 m.
local probe
w,a,s=world();a.terrain=function(x,z)probe=probe or {};probe[#probe+1]={x,z};return 0 end
Film.Begin(s,a,w.pad);Film.Update(s,a)
check(#probe==12 and not s.launchFilm.highFallback and w.cameraOffset[2]<0,'clear terrain uses the low view')
local start=w.cameraOffset
w.now=110;Film.Update(s,a)
check(w.cameraOffset[1]^2+w.cameraOffset[3]^2>start[1]^2+start[3]^2,'the view pulls back during the ascent')
for _,height in ipairs({{72.0,false},{72.5,true}})do
    w,a,s=world();a.terrain=function()return height[1] end
    Film.Begin(s,a,w.pad);Film.Update(s,a)
    -- First probe: 76.16 m on the climb line less the 4 m allowance is 72.16 m (a 48.5 m half-height gives 69.9).
    check((s.launchFilm.highFallback or false)==height[2],'obstruction probe is measured from this rocket nozzle plane: '..height[1])
end
print('misn03 launch film checks passed: '..checks)
