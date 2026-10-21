-- Solid, authority-owned firs. A fixed site grid handles weather queries; only
-- a bounded stream of nearby sites becomes GameObjects. No combat object scan.
local Trees = {}
Trees.TUNING = { step=.1, scan=128, build=2, drop=4, live=256,
    near=280, far=460, unload=560, strike=24, funnel=45, fallSeconds=1.2 }
local C = Trees.TUNING
local function valid(h) return h and type(IsValid)=="function" and IsValid(h) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function key(x,z) return math.floor(x/64)..":"..math.floor(z/64) end

function Trees.Create(api)
    api=api or {}
    local sites=api.sites or require("CRStorm18TreesSites").sites
    local T,grid,byLabel,handles={},{},{},{}
    local s,clock,nextStep,lastStep,nextFunnel,adopted,liveCount,fallCount
    local metrics={candidates=0,built=0,unloaded=0,lightning=0,tornado=0,combat=0}
    for i,p in ipairs(sites) do
        byLabel[p.label]=i
        local k=key(p.position[1],p.position[3]);grid[k]=grid[k] or {}
        grid[k][#grid[k]+1]=i
    end
    local function cull(h)
        local x=api.exu or {}
        if type(x.SetEntityRenderingDistance)=="function" then pcall(x.SetEntityRenderingDistance,h,300) end
    end
    function T.AddObject(h)
        if not valid(h) then return end
        -- Remote labels may arrive after AddObject. Cull by ODF on every peer.
        if type(GetOdf) == "function" then
            local odf=GetOdf(h)
            if type(odf)=="string" and odf:lower():gsub("%.odf$",""):match("^c17frst[1-4]$") then cull(h) end
        end
        if type(GetLabel)=="function" then
            local i=byLabel[GetLabel(h)]
            if i then handles[i]=h;cull(h) end
        end
    end
    function T.Reset(saved)
        s=type(saved)=="table" and saved or {}
        s.live,s.gone,s.falling=s.live or {},s.gone or {},s.falling or {}
        s.cursor=math.max(1,math.min(#sites,tonumber(s.cursor) or 1))
        handles={};clock,nextStep,lastStep,nextFunnel,adopted,liveCount,fallCount=0,0,0,0,false,0,0
        return s
    end
    local function retire(i,damage)
        local h=handles[i]
        if valid(h) and damage and type(Damage)=="function" then Damage(h,100000) end
        if s.live[i] then liveCount=math.max(0,liveCount-1) end
        handles[i],s.live[i],s.falling[i]=nil,nil,nil
    end
    local function destroy(i,kind)
        if s.gone[i] then return false end
        s.gone[i]=true;metrics[kind]=metrics[kind]+1
        if kind=="tornado" and valid(handles[i]) and fallCount<8 and
            type(SetTransform)=="function" and type(BuildPositionRotationMatrix)=="function" then
            s.falling[i]={age=0};fallCount=fallCount+1
        else retire(i,true) end
        return true
    end
    local function query(x,z,r,kind)
        if not (s and adopted and finite(x) and finite(z)) then return 0 end
        local seen,killed=0,0
        for cx=math.floor((x-r)/64),math.floor((x+r)/64) do
            for cz=math.floor((z-r)/64),math.floor((z+r)/64) do
                for _,i in ipairs(grid[cx..":"..cz] or {}) do
                    seen=seen+1;metrics.candidates=metrics.candidates+1
                    local p=sites[i].position
                    if (p[1]-x)^2+(p[3]-z)^2<=r*r and destroy(i,kind) then killed=killed+1 end
                    if seen>=64 then return killed end -- authored grid has <=4 sites/cell
                end
            end
        end
        return killed
    end
    -- Called only by the director's authority-side first ground stroke.
    function T.Strike(x,z,authority)
        if not authority then return 0 end
        return query(x,z,C.strike,"lightning")
    end
    local function nearest(players,p)
        local d=math.huge
        for _,a in ipairs(players) do
            local v=(a.x-p[1])^2+(a.z-p[3])^2;if v<d then d=v end
        end
        return d
    end
    function T.Update(dt,authority,players,tornado)
        if not s then T.Reset() end
        clock=clock+math.max(0,tonumber(dt) or 0)
        if not authority or clock<nextStep then return end
        local elapsed=math.min(.5,clock-lastStep);lastStep=clock;nextStep=clock+C.step
        if not adopted then
            -- One recovery scan after Start/Load; never a recurring world scan.
            if type(AllObjects)=="function" then for h in AllObjects() do T.AddObject(h) end end
            for i in pairs(handles) do
                if not s.gone[i] or s.falling[i] then s.live[i]=true end
            end
            for i in pairs(s.live) do
                if valid(handles[i]) then liveCount=liveCount+1
                else s.live[i]=nil;s.gone[i]=true;s.falling[i]=nil end
            end
            for i in pairs(s.falling) do
                if valid(handles[i]) then fallCount=fallCount+1 else s.falling[i]=nil end
            end
            adopted=true
        end
        for i,f in pairs(s.falling) do
            f.age=f.age+elapsed
            if not valid(handles[i]) or f.age>=C.fallSeconds then
                retire(i,true);fallCount=math.max(0,fallCount-1)
            else
                local p=sites[i].position;local t=f.age/C.fallSeconds
                -- Lift the actual plant, tip its trunk and turn it into the swirl;
                -- no AI commands or unbounded physics/debris objects.
                SetTransform(handles[i],BuildPositionRotationMatrix(t*.9,sites[i].yaw+t*2,t*.55,
                    p[1],p[2]+t*18,p[3]))
            end
        end
        if tornado and (tornado.t or 0)>=5 and clock>=nextFunnel then
            nextFunnel=clock+.25;query(tornado.x,tornado.z,C.funnel,"tornado")
        end
        local built,dropped=0,0
        players=type(players)=="function" and players() or players or {}
        if #players==0 or #sites==0 then return end
        for _=1,math.min(C.scan,#sites) do
            local i=s.cursor;s.cursor=i%#sites+1
            local p=sites[i];local h=handles[i]
            if not s.falling[i] then
                if s.live[i] and not valid(h) then
                    s.gone[i]=true;retire(i,false);metrics.combat=metrics.combat+1
                elseif not s.gone[i] then
                    local d=nearest(players,p.position)
                    if s.live[i] and d>C.unload^2 and dropped<C.drop then
                        if type(RemoveObject)=="function" then RemoveObject(h) end
                        retire(i,false);dropped=dropped+1;metrics.unloaded=metrics.unloaded+1
                    elseif not s.live[i] and d>C.near^2 and d<C.far^2 and built<C.build and
                        liveCount<C.live and type(BuildObject)=="function" then
                        local hnew=BuildObject(p.odf,0,BuildPositionRotationMatrix(0,p.yaw,0,
                            p.position[1],p.position[2],p.position[3]))
                        if valid(hnew) then
                            SetLabel(hnew,p.label);handles[i]=hnew;s.live[i]=true;cull(hnew)
                            liveCount=liveCount+1;built=built+1;metrics.built=metrics.built+1
                        end
                    end
                end
            end
        end
    end
    function T.Save() return s end
    function T.Describe()
        local out={live=liveCount or 0,falling=fallCount or 0,sites=#sites}
        for k,v in pairs(metrics) do out[k]=v end
        return out
    end
    return T
end
return Trees
