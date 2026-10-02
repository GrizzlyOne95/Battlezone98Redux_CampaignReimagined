-- Faithful stock misn11 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn11Mission.cpp
-- Source blob: 127e2f66fe3de1c79434a4c1a7b284601909ee7c.
-- All original disabled gameplay code remains disabled at its source location.
-- Complete C++/header, including declaration/serialization comments:
-- References/Misn11Source/. Single-player; stock BZR API only.

local function NewState()
    return {
        won = false, lost = false,
        launch_gone = false, escape_start = false, last_wave = false,
        got_there1 = false, got_there2 = false, got_there3 = false,
        escape_path = false, start_done = false, betrayal = false,
        pursuit_warning = false, betrayal_message = false,
        check1 = false, check2 = false, restart = false, launch_attack = false,
        escape_time = 99999.0, last_wave_time = 99999.0,
        camera_time = 99999.0, betrayal_time = 99999.0, start_delay = 99999.0,
        player = nil, recy = nil, cam1 = nil, cam2 = nil, cam3 = nil, cam4 = nil,
        tug1 = nil, tug2 = nil, turr1 = nil, turr2 = nil, turr3 = nil,
        openh = nil, launch = nil, launch2 = nil, tank1 = nil, tank2 = nil,
        audmsg = 0,
    }
end

local M = NewState()

local function Exists(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

-- BZR adaptation: a missing object cannot satisfy a proximity trigger.
-- Guard both handle operands so nil/zero is never passed to a position overload.
-- Keep the explicit path-point argument (notably "check2", 1) intact.
local function Distance(from, to, point)
    if not Exists(from) then return math.huge end
    if type(to) ~= "string" and not Exists(to) then return math.huge end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

-- BUG FIX (native null dereferences): Setup's Execute block called SetName /
-- SetObjective through unchecked GetObj pointers. Skip only absent objects;
-- present objects receive the same names/markers, and no timers or transitions
-- change. Missing transports still enter the original failure branch below.
local function NameObject(h, name, objective)
    if Exists(h) then
        if objective then SetObjectiveOn(h) end
        SetObjectiveName(h, name)
    end
end

-- Native IsOdf matched an ODF basename. Accept the equivalent .odf spelling
-- too, as in the existing source ports; do not add any team/ownership filter.
local function IsOdfBase(h, name)
    return Exists(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

function Start()
    -- The source initializes every member before Setup. Keep unused members
    -- (escape_path, camera_time, recy, cam4, audmsg) for cut-content work.
    M = NewState()
end

function Update(timestep)
    M.player = GetPlayerHandle()
    if not M.start_done then
        --[[
            -paths
            base
            openheimer
            escape
            units
            avhaul0_tug
            avhaul1_tug
            avhaul2_tug
            -camera
            apcamr3_camerapod
            apcamr4_camerapod
            apcamr5_camerapod
        ]]
        --[[
            misn1501.wav
            Now that we've captured the SAV relics
            we need to ransport this key technology
            off of Io.  This could win the war for us.
        ]]
        M.tug1 = GetHandle("avhaul0_tug")
        M.tug2 = GetHandle("avhaul1_tug")
        M.openh = GetHandle("avhaul2_tug")
        M.turr1 = GetHandle("svturr2_turrettank")
        M.turr2 = GetHandle("second_blockade")
        M.turr3 = GetHandle("svturr3_turrettank")
        M.cam1 = GetHandle("apcamr3_camerapod")
        M.cam2 = GetHandle("apcamr4_camerapod")
        M.cam3 = GetHandle("apcamr5_camerapod")
        M.launch = GetHandle("launch_pad")
        M.launch2 = GetHandle("launch_pad2")
        NameObject(M.cam1, "Waypoint 1")
        NameObject(M.cam2, "Waypoint 2")
        NameObject(M.cam3, "Launch Pad")
        NameObject(M.tug1, "Transport 1", true)
        NameObject(M.tug2, "Transport 2", true)
        NameObject(M.openh, "Transport 3", true)

        SetUserTarget(M.cam1)
        SetScrap(1, 50)
        AudioMessage("misn1101.wav")
        ClearObjectives()
        AddObjective("misn1101.otf", "white")
        M.start_delay = GetTime() + 15.0
        M.start_done = true
    end
    --[[
        Mad Dr. Openheimer
        has magic shields that
        prevent him from being killer.
    ]]
    -- Preserve the original +300 health EACH Execute, including after betrayal;
    -- multiplying by timestep or making this full invulnerability changes play.
    if IsAlive(M.openh) then AddHealth(M.openh, 300.0) end

    if GetTime() > M.start_delay then
        --[[
            Moving out!
        ]]
        AudioMessage("misn1102.wav")
        M.start_delay = 99999.0
        Goto(M.tug1, "base1", 1)
        Goto(M.tug2, "base1", 1)
        Goto(M.openh, "base1", 0)
    end
    --[[
        if (isDamaged(tug1) || is damaged(tug2)
        AudioMessage(misn1402)
        get your ass up here and help us out, etc.
    ]]
    if not M.betrayal and Distance(M.cam1, M.openh) < 50.0 then
        M.betrayal_time = GetTime() + 15.0 -- when we announce it
        Goto(M.openh, "openheimer", 1)
        M.betrayal = true
    end
    if GetTime() > M.betrayal_time then
        M.betrayal_time = 99999.0
        AudioMessage("misn1103.wav") -- transport 3 seems to be braking off
        AudioMessage("misn1104.wav") -- farewell capitalist pigs!!
        -- BUG FIX: GetObj(openh)->SetTeam(2) could dereference an object killed
        -- after betrayal started. Skip the team write only if it no longer
        -- exists; keep the announcement, reinforcements, and objectives on the
        -- same schedule. A present transport still changes to team 2 here.
        if Exists(M.openh) then SetTeamNum(M.openh, 2) end
        Defend(M.turr1, 0)
        Defend(M.turr3, 0)
        AudioMessage("misn1105.wav")
        BuildObject("svfigh", 2, "strike1")
        -- Preserve the source's complete object-list scan, including existing
        -- fighters and any team. Re-tasking only the newly built unit differs.
        for h in AllObjects() do
            if IsOdfBase(h, "svfigh") then Goto(h, "strike_path1", 0) end
        end
        M.betrayal_message = true
        ClearObjectives()
        AddObjective("misn1102.otf", "white")
    end
    -- The original condition has no distance threshold: GetDistance alone is
    -- a C++ boolean conversion. Explicit ~= 0 preserves it (Lua treats 0 as
    -- true). Guessing a pursuit radius would change the warning's timing.
    if M.betrayal_message and not M.pursuit_warning
        and IsAlive(M.turr1) and Distance(M.turr1, M.player) ~= 0 then
        AudioMessage("misn1106.wav") -- do not pursue..
        M.pursuit_warning = true
    end
    if (Distance(M.cam1, M.tug1) < 50.0
        or Distance(M.cam1, M.player) < 50.0) and not M.check1 then
        M.check1 = true
        SetUserTarget(M.cam2)
    end
    if Distance(M.tug1, "check2", 1) < 50.0 and not M.check2 then -- was cam2
        --[[
            At this point openheimer
            has escaped..
        ]]
        if Exists(M.openh) then SetObjectiveOff(M.openh) end
        M.check2 = true
        SetUserTarget(M.cam3)
        AudioMessage("misn1107.wav")
        --[[
            Now send another enemy
        ]]
        BuildObject("svfigh", 2, "strike2")
        for h in AllObjects() do
            if IsOdfBase(h, "svfigh") then Goto(h, "strike_path2", 0) end
        end
    end
    if M.check2 and not M.restart and not IsAlive(M.turr2) then
        AudioMessage("misn1102.wav")
        Goto(M.tug1, "base2", 1)
        Goto(M.tug2, "base2", 1)
        M.restart = true
    end
    if M.restart and not M.launch_attack
        and (Distance(M.launch, M.player) < 450.0
            or Distance(M.launch, M.tug1) < 450.0) then
        M.tank1 = BuildObject("svtank", 2, "launch_attack")
        M.tank2 = BuildObject("svtank", 2, "launch_attack")
        -- Preserve the literal native health delta -0.90, not a guessed 90%
        -- damage conversion. The later two-tank-death branch guarantees the
        -- scripted loss of the pad even if this tiny delta leaves it standing.
        -- BUG FIX: guard the source's unchecked GetObj(launch) dereference;
        -- an absent pad needs no health write. Intact-pad behavior is identical.
        if Exists(M.launch) then AddHealth(M.launch, -0.90) end
        AudioMessage("misn1108.wav")
        Attack(M.tank1, M.launch, 1)
        Attack(M.tank2, M.launch, 1)
        --[[
        ObjectList &list = *GameObject::objectList;
        for (ObjectList::iterator i = list.begin(); i != list.end(); i++)
        {
            GameObject *o=*i;
            Handle h=GameObjectHandle::Find(o);
            if (IsOdf(h,"svtank"))
            {
                Attack(h,launch,1); // attack the launch pad
            }

        }
        ]]
        M.launch_attack = true
    end
    if M.launch_attack and not IsAlive(M.launch) and not M.launch_gone then
        AudioMessage("misn1109.wav")
        M.launch_gone = true
        M.escape_time = GetTime() + 40.0
    end
    --[[
        If both tanks die
        and somehow
        the launch pad is ok..
        It's not!
    ]]
    if M.launch_attack and not IsAlive(M.tank1) and not IsAlive(M.tank2)
        and IsAlive(M.launch) then
        RemoveObject(M.launch)
        M.launch_gone = true
        M.escape_time = GetTime() + 10.0
    end
    if M.launch_gone and GetTime() > M.escape_time then
        Goto(M.tug1, "escape")
        Goto(M.tug2, "escape")
        AudioMessage("misn1110.wav")
        SetObjectiveOn(M.launch2)
        ClearObjectives()
        AddObjective("misn1103.otf", "white")
        SetObjectiveName(M.launch2, "Launch Pad 2")
        M.escape_time = 99999.0
    end
    if M.launch_gone and (Distance(M.tug2, M.cam3) < 50.0
        or not IsAlive(M.cam3)) and not M.escape_start then -- in case cam3 is shot
        M.escape_start = true
        M.last_wave_time = GetTime() + 15.0
        M.launch_gone = true
    end
    if not M.last_wave and M.last_wave_time < GetTime() then
        BuildObject("svfigh", 2, "strike2")
        BuildObject("svfigh", 2, "strike2")
        for h in AllObjects() do
            if IsOdfBase(h, "svfigh") then
                Attack(h, M.tug2, 1) -- attack the launch pad
            end
        end
        -- we put this one in later
        -- cuz we want it to wait
        local last_guy = BuildObject("svfigh", 2, M.launch2)
        Attack(last_guy, M.player)
        BuildObject("avcamr", 1, "last_camera")
        M.last_wave = true
        M.last_wave_time = 99999.0
    end
    if not M.lost and (not IsAlive(M.tug1) or not IsAlive(M.tug2)
        or (not M.betrayal and not IsAlive(M.openh))) then
        if M.betrayal then
            ClearObjectives()
            AddObjective("misn1102.otf", "white")
        end
        AudioMessage("misn1111.wav")
        AudioMessage("misn1112.wav")
        M.lost = true
        FailMission(GetTime() + 15, "misn11l1.des")
    end
    if M.last_wave and not M.got_there1 and Distance(M.player, M.launch2) < 200.0 then
        M.got_there1 = true
        -- we do each check seperately in case
        -- the vehicles get to safety & leave
    end
    if M.last_wave and not M.got_there2 and Distance(M.tug1, M.launch2) < 200.0 then
        M.got_there2 = true
    end
    if M.last_wave and not M.got_there3 and Distance(M.tug2, M.launch2) < 200.0 then
        M.got_there3 = true
    end
    if not M.won and M.last_wave and IsAlive(M.tug1) and IsAlive(M.tug2)
        and M.got_there1 and M.got_there2 and M.got_there3 then
        AudioMessage("misn1113.wav")
        M.won = true
        SucceedMission(GetTime() + 15, "misn11w1.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores serialized game handles. Do not call Start / replay
    -- initialization here; the source's native ConvertHandle loop is unnecessary.
    M = state
end
