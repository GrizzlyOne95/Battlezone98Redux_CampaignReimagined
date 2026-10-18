-- Solid plants are gameplay scenery. The leader owns their creation; ground
-- cover remains in CRJungle17's peer-local Ogre batches.
local Trees={}
function Trees.Create(api)
    local sites=require("CRJungle17Sites").trees
    local T={}
    function T.Update()
        local M=api.state()
        if not api.authority() or not M.openingcindone or M.minecinstart
            or M.missionwon or M.missionfail or M.coopResult then return end
        M.cr17.treeStream=M.cr17.treeStream or {cursor=1,done={},built=0,nextBuild=0}
        local s=M.cr17.treeStream
        if GetTime()<s.nextBuild then return end
        s.nextBuild=GetTime()+.08
        local built=0
        for _=1,32 do
            local i=s.cursor;s.cursor=i%#sites+1
            local p=sites[i]
            if not s.done[i] then
                if p.preplaced==1 then s.done[i]=true
                else
                    local v=SetVector(p.position[1],p.position[2],p.position[3])
                    if api.safe(v) then
                        local h=BuildObject(p.odf,0,v)
                        if h and IsValid(h) then
                            SetLabel(h,p.label)
                            s.done[i]=true;s.built=s.built+1;built=built+1
                        end
                    end
                end
                if built==2 then break end
            end
        end
    end
    return T
end
return Trees
