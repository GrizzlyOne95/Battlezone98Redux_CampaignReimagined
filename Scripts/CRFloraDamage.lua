-- Local, render-only destruction of registered StaticGeometry foliage.
-- No object scans, networking, health changes or callback-time Ogre calls.
-- Placement/index work happens once at registration; combat work is sliced.
local D = {}
local ok, exu = pcall(require, "exu")
if not ok then exu = {} end
local CELL, MAX_RADIUS = 32, 64
local TICK, REBUILD, DEBOUNCE = .1, .2, .3
local CANDIDATES, CELLS, EVENTS = 192, 96, 8
local layers, grid, dirty, queue = {}, {}, {}, {}
local qhead, qtail, work, nextTick, nextBuild, started = 1, 0, nil, 0, 0, false
local dirtyCount=0
local stats = {removed=0,events=0,rebuilds=0,failures=0,dropped=0,candidates=0,cells=0}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function now() return type(GetTime)=="function" and GetTime() or 0 end
local function cell(x,z) return x..":"..z end
local function clearDirty(name)
    if dirty[name] then dirty[name]=nil;dirtyCount=dirtyCount-1 end
end
local function pos(p) local a=p.position; if a then return a.x,a.y,a.z end; return p[1],p[2],p[3] end
local function start()
    if started then return end
    if type(exu.SetExplosionEventsEnabled)=="function" then
        started = exu.SetExplosionEventsEnabled(true)==true
    end
end

-- Native radius is the actual loaded ExplosionClass damageRadius. Zero-radius
-- stock ballistic/laser ground impacts get a tiny cosmetic footprint. Arbitrary
-- zero-radius smoke/visual effects deliberately do not become destructive.
local impact = {xbulgnd=1.25,xlasgnd=2,xlgtgnd=2,xlgtgndg=2,xlgtgndr=2}
function D.Radius(event)
    if not finite(event.radius) or event.radius<0 then return nil end
    if event.radius==0 then return impact[string.lower(event.odf or "")] end
    return math.min(MAX_RADIUS, math.max(1, event.radius))
end

-- saved is a per-layer plain table, owned by this client's mission save state.
-- The fingerprint rejects membership from changed placement data.
function D.Register(name, spec, saved)
    if layers[name] then return layers[name].saved end
    local points=spec.points or {}
    local hash=17
    for _,p in ipairs(points) do
        local x,y,z=pos(p)
        if not (finite(x) and finite(y) and finite(z)) then return nil end
        hash=(hash*31+math.floor(x*100+.5)+math.floor(y*100+.5)*3+math.floor(z*100+.5)*7)%2147483647
    end
    local version=spec.mesh..":"..#points..":"..hash
    if type(saved)~="table" or saved.version~=version then saved={version=version,gone={}} end
    if type(saved.gone)~="table" then saved.gone={} end
    local l={name=name,spec=spec,saved=saved,resident=false,remaining=#points,cells={}}
    layers[name]=l
    for i,p in ipairs(points) do
        if saved.gone[i] then l.remaining=l.remaining-1
        else
            local x,_,z=pos(p)
            local key=cell(math.floor(x/CELL),math.floor(z/CELL))
            local bucket=grid[key] or {};grid[key]=bucket
            bucket[#bucket+1]={layer=l,index=i,point=p}
            l.cells[key]=true
        end
    end
    start()
    return saved
end

function D.Instances(name)
    local l=layers[name]; if not l then return nil end
    local out={}
    for i,p in ipairs(l.spec.points) do
        if not l.saved.gone[i] then
            -- Already-normalized TerrainClutter points can be reused directly.
            if p.position then out[#out+1]=p
            else out[#out+1]={position={x=p[1],y=p[2],z=p[3]},yaw=p[4],scale=p[5]} end
        end
    end
    return out
end
function D.IsRemoved(name,i) local l=layers[name];return l and l.saved.gone[i]==true or false end
function D.Resident(name,on) local l=layers[name];if l then l.resident=on==true end end
function D.Saved(name) return layers[name] and layers[name].saved end
function D.Has(name) return layers[name]~=nil end

-- A provider removes all its names at teardown, retaining the saved tables.
function D.Unregister(name)
    local l=layers[name];if not l then return end
    l.retired=true;layers[name]=nil;clearDirty(name)
    for key in pairs(l.cells) do
        local bucket=grid[key];local keep={}
        for _,entry in ipairs(bucket or {}) do if entry.layer~=l then keep[#keep+1]=entry end end
        grid[key]=#keep>0 and keep or nil
    end
    if not next(layers) then
        if started then exu.SetExplosionEventsEnabled(false) end
        grid,dirty,queue={}, {}, {};qhead,qtail,work,started=1,0,nil,false
        nextTick,nextBuild=0,0
        dirtyCount=0
    end
end

function D.Notify(event)
    local r=D.Radius(event)
    if not r or not finite(event.x) or not finite(event.y) or not finite(event.z) then return false end
    if qtail-qhead+1>=128 then stats.dropped=stats.dropped+1;return false end
    qtail=qtail+1;queue[qtail]={x=event.x,y=event.y,z=event.z,r=r}
    return true
end
local function beginEvent(e)
    e.minx=math.floor((e.x-e.r)/CELL);e.maxx=math.floor((e.x+e.r)/CELL)
    e.minz=math.floor((e.z-e.r)/CELL);e.maxz=math.floor((e.z+e.r)/CELL)
    e.cx,e.cz,e.i=e.minx,e.minz,1
    stats.events=stats.events+1
    return e
end
local function stepEvent(t,budget)
    local e=work
    local bucket=grid[cell(e.cx,e.cz)]
    while bucket and e.i<=#bucket and budget.points>0 do
        local entry=bucket[e.i];e.i=e.i+1;budget.points=budget.points-1;stats.candidates=stats.candidates+1
        local l,i=entry.layer,entry.index
        if not l.retired and not l.saved.gone[i] then
            local x,y,z=pos(entry.point)
            if (x-e.x)^2+(y-e.y)^2+(z-e.z)^2<=e.r*e.r then
                l.saved.gone[i]=true;l.remaining=l.remaining-1;stats.removed=stats.removed+1
                -- Do not continually postpone a busy meadow's oldest edit.
                if not dirty[l.name] then dirty[l.name]=t+DEBOUNCE;dirtyCount=dirtyCount+1 end
                if l.spec.onRemove then l.spec.onRemove(entry.point) end
            end
        end
    end
    if bucket and e.i<=#bucket then return end
    budget.cells=budget.cells-1;stats.cells=stats.cells+1
    e.i=1;e.cz=e.cz+1
    if e.cz>e.maxz then e.cz=e.minz;e.cx=e.cx+1 end
    if e.cx>e.maxx then work=nil end
end
local function rebuild(t)
    if t<nextBuild then return end
    local oldest,chosen
    for name,ready in pairs(dirty) do
        local l=layers[name]
        if not l or not l.resident then clearDirty(name)
        elseif t>=ready and (not oldest or ready<oldest) then oldest,chosen=ready,name end
    end
    if chosen then
            local name=chosen;local l=layers[name]
            nextBuild=t+REBUILD
            local good,info,reason
            if l.remaining==0 then
                good,info=pcall(exu.DestroyStaticGeometry,name)
                if good and info then l.resident=false end
            else
                good,info,reason=pcall(exu.CreateStaticGeometry,name,l.spec.mesh,l.spec.material,D.Instances(name),l.spec.options)
            end
            if good and info then
                clearDirty(name);stats.rebuilds=stats.rebuilds+1
                if type(info)=="table" then
                    local ms=tonumber(info.totalMilliseconds or info.buildMilliseconds) or 0
                    stats.lastBuildMilliseconds=ms
                    stats.maxBuildMilliseconds=math.max(stats.maxBuildMilliseconds or 0,ms)
                end
            else
                stats.failures=stats.failures+1;stats.lastError=tostring(reason or info)
                dirty[name]=t+5
            end
            return -- at most one Ogre replacement in this timed service slice
    end
end
function D.Update()
    if not next(layers) then return end
    local t=now();if t<nextTick then return end;nextTick=t+TICK
    if started and type(exu.DrainExplosionEvents)=="function" then
        local events,dropped=exu.DrainExplosionEvents(32)
        stats.nativeDropped=dropped or 0
        for _,e in ipairs(events or {}) do D.Notify(e) end
    end
    local budget={points=CANDIDATES,cells=CELLS}
    local events=0
    while budget.points>0 and budget.cells>0 and events<EVENTS do
        if not work then
            if qhead>qtail then queue={};qhead,qtail=1,0;break end
            work=beginEvent(queue[qhead]);queue[qhead]=nil;qhead=qhead+1;events=events+1
        end
        stepEvent(t,budget)
    end
    rebuild(t)
end
function D.Describe()
    local out={};for k,v in pairs(stats) do out[k]=v end
    out.dirty=dirtyCount;out.pending=qtail-qhead+1+(work and 1 or 0);out.native=started
    return out
end
return D
