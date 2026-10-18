-- Owner-directed reconstruction of the cut raw/processed crystal concept.
-- The original converter-destruction victory remains in the faithful body.
local Crystals={}
function Crystals.Create(api)
    local C={}
    local observed,nextReport={},0
    local function M() return api.state() end
    local function valid(h) return h~=nil and h~=0 and IsValid(h) end
    local function alive(h) return valid(h) and IsAlive(h) end
    local function state()
        local m=M()
        m.cr17Crystals=m.cr17Crystals or {phase="ready",cargo={},serial=0,hint=0}
        local s=m.cr17Crystals
        if not s.bound then
            for i=1,5 do
                local label="cr17_raw"..i
                s.cargo[label]={label=label,handle=GetHandle(label),kind="raw"}
            end
            s.cargo.cr17_processed={label="cr17_processed",handle=GetHandle("cr17_processed"),kind="processed"}
            s.bound=true
        end
        return s
    end
    function C.AddCargo(label,kind)
        if type(label)~="string" or not label:match("^cr17_prod%d+$") or kind~="processed" then return end
        local s=state()
        s.cargo[label]=s.cargo[label] or {label=label,handle=GetHandle(label),kind=kind}
    end
    function C.Report(team,label,towing)
        local c=state().cargo[label]
        if not api.human(team) or not c or c.consumed or not alive(c.handle) then return end
        if towing==true then c.team=team;c.towing=true
        elseif c.team==team then c.towing=false end
        c.reported=GetTime()
    end
    function C.Poll(authority,send)
        if GetTime()<nextReport then return end
        nextReport=GetTime()+.75
        local s=state()
        local player=GetPlayerHandle()
        local localTeam=valid(player) and GetTeamNum(player) or 0
        for label,c in pairs(s.cargo) do
            -- A guest resolves spawned cargo by its acknowledged label.
            local h=GetHandle(label)
            if valid(h) then c.handle=h end
            if not c.consumed and alive(c.handle) then
                local tug=GetTug(c.handle)
                if valid(tug) and api.human(GetTeamNum(tug)) and (authority or GetTeamNum(tug)==localTeam) then
                    local team=GetTeamNum(tug);observed[label]=team
                    if authority then C.Report(team,label,true) else send(label,true) end
                elseif observed[label] then
                    if authority then C.Report(observed[label],label,false) else send(label,false) end
                    observed[label]=nil
                end
            end
        end
    end
    local function remove(c)
        c.consumed=true
        api.off(c.handle)
        api.remove(c.handle)
    end
    local function near(c,target,radius)
        return alive(c.handle) and alive(target) and GetDistance(c.handle,target)<radius
    end
    local function released(c)
        return c.team and c.towing==false and c.reported and GetTime()-c.reported<4
            and not valid(GetTug(c.handle))
    end
    local function hint(s)
        if s.hint>=3 then return end
        local refinery=GetHandle("cr17_refinery")
        if s.hint==0 and not api.anyNear(refinery,450) and not M().towersdestroyed then return end
        if GetTime()<(s.nextHint or 0) then return end
        s.hint=s.hint+1;s.nextHint=GetTime()+9
        api.voice(({"misn1706.wav","misn1707.wav","misn1708.wav"})[s.hint])
        if s.hint==1 then
            for _,c in pairs(s.cargo) do
                if alive(c.handle) then api.mark(c.handle);api.name(c.handle,c.kind=="raw" and "Raw crystal" or "Processed crystal") end
            end
            api.mark(refinery);api.name(refinery,"Crystal refinery")
            local slot=GetHandle("cr17_receiver");api.mark(slot);api.name(slot,"Converter crystal feed")
        end
    end
    function C.Update()
        local m,s=M(),state()
        if m.missionwon or m.missionfail or m.coopResult then return end
        hint(s)
        local receiver,refinery=GetHandle("cr17_receiver"),GetHandle("cr17_refinery")
        if s.processing and GetTime()>=s.processing.ready then
            if alive(refinery) then
                local p=GetPosition(refinery)
                local h=BuildObject("c17proc",0,SetVector(p.x,p.y+3.1,p.z))
                if valid(h) then
                    s.serial=s.serial+1
                    local label="cr17_prod"..s.serial
                    SetLabel(h,label)
                    s.cargo[label]={label=label,handle=h,kind="processed"}
                    api.mark(h);api.name(h,"Processed crystal")
                    api.cargo(label,"processed")
                    s.processing=nil
                end
            else s.processing=nil end
        end
        -- Ordered labels keep simultaneous deposits deterministic on the leader.
        local labels={};for label in pairs(s.cargo) do labels[#labels+1]=label end;table.sort(labels)
        for _,label in ipairs(labels) do
            local c=s.cargo[label]
            if not c.consumed and released(c) then
                if m.towersdestroyed and near(c,receiver,18) then
                    remove(c)
                    if c.kind=="raw" then
                        s.phase="overload";s.deadline=GetTime()+20;m.crysswitched=true
                        api.voice("misn1702.wav")
                    else
                        s.phase="ready";s.deadline=nil;m.crysswitched=false
                        api.voice("misn1705.wav")
                    end
                elseif c.kind=="raw" and not s.processing and near(c,refinery,13) then
                    remove(c);s.processing={ready=GetTime()+12}
                end
            end
        end
        if s.phase=="overload" and GetTime()>=s.deadline then
            s.phase="sabotaged";s.sabotaged=true
            -- Let the existing victory gate, camera and factory detonation
            -- order do the work. No separate success/result path can race it.
            for i=1,3 do local h=m["factorypart"..i];if alive(h) then Damage(h,1e9) end end
        end
        local raw=0
        for _,c in pairs(s.cargo) do if c.kind=="raw" and not c.consumed and alive(c.handle) then raw=raw+1 end end
        local text
        if s.phase=="overload" then text="Unprocessed crystal installed. Factory overload in "..math.max(0,math.ceil(s.deadline-GetTime())).." seconds."
        elseif raw==0 and not s.processing then text="No raw crystals remain. Destroy the three factory power converters."
        else text="Optional: once the towers fall, haul a RAW crystal to the converter feed. A refined crystal stabilizes it." end
        local revision=m.cr17ObjectiveRevision or 0
        if s.hint>0 and (s.objective~=text or s.objectiveRevision~=revision) then
            api.objective("cr17crystal",s.phase=="overload" and "green" or "white",8,text,
                s.objective==nil or s.objectiveRevision~=revision)
            s.objective=text;s.objectiveRevision=revision
        end
    end
    function C.Reset() observed={};nextReport=0;state().objective=nil end
    return C
end
return Crystals
