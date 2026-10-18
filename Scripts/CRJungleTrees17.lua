-- Solid plants are gameplay scenery. The leader owns their creation; ground
-- cover remains in CRJungle17's peer-local Ogre batches.
--
-- Streamed trees exist only in a ring around the players. Every tree GameObject
-- costs simulation, HUD and scene-graph time whether or not it is in view, and
-- misn17's fog ends at 250 m: 2,900 standing trees held the frame near 45 ms.
-- A site is built once every player is at least BUILD_MIN away (beyond the
-- fog, so it never pops in) and one is within BUILD_MAX; it is removed again
-- when every player is beyond DROP. A tree that dies stays dead.
local BUILD_MIN,BUILD_MAX,DROP=300,460,560
-- Peer-local Ogre cull: fogged out past 250 m, so draw no further than this.
local RENDER_DISTANCE=300
local Trees={}
function Trees.Create(api)
    local sites=require("CRJungle17Sites").trees
    local T={}
    local culled,nextCull,isSite={},0,nil
    local function cull()
        -- Every peer, every tree it can see, preplaced ones included. Keyed by
        -- handle: a rebuilt tree gets a new handle and needs it again.
        -- Walk the objects that exist rather than look sites up by label: the
        -- engine logs and flushes "No object named" for every site that is not
        -- standing, and at 1,280 lookups a second that was ~2% of a frame.
        -- A tree is built beyond the fog, so a second's delay never shows.
        local x=rawget(_G,"exu")
        if type(x)~="table" or type(x.SetEntityRenderingDistance)~="function" then return end
        if GetTime()<nextCull then return end
        nextCull=GetTime()+1
        if not isSite then
            isSite={}
            for _,p in ipairs(sites) do isSite[p.label]=true end
        end
        local seen={}
        for h in AllObjects() do
            seen[h]=true
            if not culled[h] then
                local ok,label=pcall(GetLabel,h)
                if ok and isSite[label] and pcall(x.SetEntityRenderingDistance,h,RENDER_DISTANCE) then culled[h]=true end
            end
        end
        for h in pairs(culled) do
            if not seen[h] then culled[h]=nil end
        end
    end
    local function nearest(players,p)
        local best=math.huge
        for _,a in ipairs(players) do
            local dx,dz=a.x-p[1],a.z-p[3]
            local d=dx*dx+dz*dz
            if d<best then best=d end
        end
        return best
    end
    function T.Update()
        cull()
        local M=api.state()
        if not api.authority() or not M.openingcindone or M.minecinstart
            or M.missionwon or M.missionfail or M.coopResult then return end
        M.cr17.treeStream=M.cr17.treeStream or {cursor=1,live={},gone={},built=0,removed=0,nextBuild=0}
        local s=M.cr17.treeStream
        if not s.live then s.live,s.gone,s.removed=s.done or {},{},0;s.done=nil end
        if GetTime()<s.nextBuild then return end
        s.nextBuild=GetTime()+.08
        local players=api.players()
        if #players==0 then return end
        local built,removed=0,0
        for _=1,128 do
            local i=s.cursor;s.cursor=i%#sites+1
            local p=sites[i]
            if p.preplaced~=1 and not s.gone[i] then
                local d=nearest(players,p.position)
                if s.live[i] then
                    local h=GetHandle(p.label)
                    if not (h and IsValid(h)) then s.live[i]=nil;s.gone[i]=true
                    elseif d>DROP*DROP and removed<4 then
                        RemoveObject(h);s.live[i]=nil;s.removed=s.removed+1;removed=removed+1
                    end
                elseif d>BUILD_MIN*BUILD_MIN and d<BUILD_MAX*BUILD_MAX and built<3 then
                    local h=BuildObject(p.odf,0,SetVector(p.position[1],p.position[2],p.position[3]))
                    if h and IsValid(h) then
                        SetLabel(h,p.label)
                        s.live[i]=true;s.built=s.built+1;built=built+1
                    end
                end
            end
        end
    end
    return T
end
return Trees
