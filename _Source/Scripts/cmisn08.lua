-- cmisn08.lua (Converted from Chinese08Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SettLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"})
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.CRA, aiCore.Factions.CCA, 2)
end

-- Mission States
local MS_STARTUP = 1
local MS_WAITFORTRIGGER = 3
local MS_CAMERATRIGGER = 4
local MS_SPAWNAPC1 = 5
local MS_SPAWNAPC2 = 6
local MS_SPAWNAPC3 = 7
local MS_SPAWNAPC4 = 8
local MS_SPAWNAPC5 = 9
local MS_WAITFORSCAP = 10
local MS_WAITSTARTSOUND4 = 11
local MS_WAITFORSOUND4 = 13
local MS_DISPLAYOBJ1 = 14
local MS_TRIGGER1 = 15
local MS_WAITFORJUMPOUT = 16
local MS_WAITFORWRECKER = 17
local MS_BANGCAMERA = 18
local MS_BANGCAMERA2 = 19
local MS_TRIGGERNWNE = 21
local MS_DESTROYPOWERS = 23
local MS_WRECKER10 = 27
local MS_WRECKER22 = 28
local MS_WRECKER33 = 29
local MS_WRECKER42 = 30
local MS_WRECKER55 = 31
local MS_WRECKER70 = 32
local MS_WRECKER85 = 33
local MS_WRECKER92 = 34
local MS_WRECKER100 = 35
local MS_WRECKER106 = 36
local MS_END = 100

-- Variables
local mission_state = MS_STARTUP
local lost = false
local apc_in_line = 0
local user_cloak_state = 0
local west_power_dead = false
local east_power_dead = false
local west_comm_dead = false
local east_comm_dead = false
local apc3_objective_on = false
local howitzer_objective_on = false
local spawns_done = {false, false, false, false, false, false}

-- Timers
local state_timer = 99999.0

-- Handles
local user, old_user, sound_handle, core_fail_sound
local west_1_1, west_1_2, west_1_3, west_1_4
local east_1_1, east_1_2, east_1_3, east_1_4
local howitzer_nw, howitzer_ne, west_power, east_power, west_comm, east_comm
local west_bolt, east_bolt, walker_1, recycler, factory, nav
local apc = {} -- 1..5
local magpull = {} -- 1..6
local west_mag = {} -- 1..4
local east_mag = {} -- 1..4
local snipers = {} -- 1..26

local specials = {
    "svapcc", "svapcd", "svapce", "svapcf", "svapcg", "svapch", "svapci",
    "svapcj", "svapck", "svapcl", "svapcm", "svapcn", "svapco", "svapcp", "svapcs"
}

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
end

function AddObject(h)
    if GetTeamNum(h) == 2 then aiCore.AddObject(h) end
end

function DeleteObject(h)
end

local function ResetObjectives()
    ClearObjectives()
    if mission_state >= MS_WAITFORSCAP and mission_state < MS_WAITSTARTSOUND4 then
        AddObjective("ch08001.otf", "white")
    elseif mission_state >= MS_WAITSTARTSOUND4 and mission_state < MS_TRIGGER1 then
        AddObjective("ch08006.otf", "white")
    elseif mission_state >= MS_TRIGGER1 and mission_state < MS_TRIGGERNWNE then
        AddObjective("ch08005.otf", "white")
    elseif mission_state >= MS_TRIGGERNWNE and mission_state < MS_DESTROYPOWERS then
        AddObjective("ch08007.otf", "white")
    elseif mission_state >= MS_DESTROYPOWERS and mission_state < MS_WRECKER10 then
        AddObjective("ch08002.otf", "white")
    elseif mission_state >= MS_WRECKER106 then
        AddObjective("ch08004.otf", "green")
    elseif mission_state >= MS_WRECKER10 then
        AddObjective("ch08004.otf", "white")
    end
end

local function CheckAPCs()
    if not IsAlive(apc[5]) and GetHealth(apc[5]) <= 0 then
        FailMission(GetTime() + 2.0, "ch08lsed.des"); mission_state = MS_END; return true
    end
    
    if GetDistance(apc[4], "break_point") < 50.0 then apc_in_line = 2 end
    
    if not IsAlive(apc[5]) and apc_in_line == 0 then
        apc_in_line = GetTime() + 25.0
    elseif apc_in_line > 2 and apc_in_line < GetTime() then
        if GetDistance(apc[5], apc[4]) > 100.0 then
            AudioMessage("ch08005.wav"); FailMission(GetTime() + 20.0, "ch08lseb.des"); mission_state = MS_END; return true
        end
        apc_in_line = 1
    elseif apc_in_line == 1 then
        if GetDistance(apc[5], apc[4]) > 100.0 then
            AudioMessage("ch08005.wav"); FailMission(GetTime() + 20.0, "ch08lsee.des"); mission_state = MS_END; return true
        end
    end
    
    for i=1,4 do
        if not IsAlive(apc[i]) then
            FailMission(GetTime() + 2.0, "ch08lsed.des"); mission_state = MS_END; return true
        end
    end
    return false
end

local function CheckSpawns()
    local function TrySpawn(id, loc, wave)
        if not spawns_done[id] then
            local t = GetNearestUnitOnTeam(loc, 0, 1) -- 0 radius? C++ uses 1 for team
            if t and GetDistance(t, loc) < 100.0 then
                spawns_done[id] = true
                for j=1, DiffUtils.ScaleEnemy(3) do Goto(BuildObject("svfigh", 2, "wave_"..wave), "wave_"..wave) end
                if wave ~= 1 and wave ~= 4 then 
                    for j=1, DiffUtils.ScaleEnemy(5) do Goto(BuildObject("svtank", 2, "wave_"..wave), "wave_"..wave) end
                elseif wave == 4 then
                    for j=1, DiffUtils.ScaleEnemy(3) do Goto(BuildObject("svwalk", 2, "wave_4"), "wave_4") end
                end
            end
        end
    end
    TrySpawn(1, "spawn_1", 1)
    TrySpawn(2, "spawn_2", 2); TrySpawn(2, "spawn_2a", 2)
    TrySpawn(3, "spawn_3", 3); TrySpawn(3, "spawn_3a", 3)
    TrySpawn(4, "spawn_4", 4)
    TrySpawn(5, "spawn_5", 5)
    TrySpawn(6, "spawn_6", 6)
end

function Update()
    user = GetPlayerHandle()
    aiCore.Update()
    
    if mission_state < MS_END and mission_state > MS_BANGCAMERA then
        if not IsAlive(recycler) and not IsAlive(factory) then
            FailMission(GetTime() + 2.0, "ch08lsea.des"); mission_state = MS_END
        end
    end
    
    if mission_state == MS_STARTUP or old_user ~= user then
        for i=1,26 do if IsAlive(snipers[i]) then Attack(snipers[i], user) end end
    end
    
    if mission_state >= MS_SPAWNAPC1 and mission_state <= MS_WAITFORSCAP and sound_handle and IsAudioMessageDone(sound_handle) then
        sound_handle = nil
        local t = BuildObject("apcamr", 1, "apc_nav"); SetName(t, "APC Convoy"); SetUserTarget(t)
    end
    
    -- Detection Logic
    if user_cloak_state == 0 then
        if GetDistance(user, "east_cloak") < 200 or GetDistance(user, "west_cloak") < 200 then
            if IsCloaked(user) then core_fail_sound = AudioMessage("ch04002.wav"); SetDecloaked(user) end
            user_cloak_state = 1; EnableCloaking(user, false)
        end
    else
        if core_fail_sound then if IsAudioMessageDone(core_fail_sound) then core_fail_sound = nil end
        elseif IsCloaked(user) then core_fail_sound = AudioMessage("ch04002.wav"); SetDecloaked(user) end
    end
    
    -- States
    if mission_state == MS_STARTUP then
        old_user = user
        SetScrap(1, DiffUtils.ScaleRes(0)); SetPilot(1, DiffUtils.ScaleRes(10)); SetScrap(2, 0)
        
        west_1_1 = GetHandle("west_1_1"); west_1_2 = GetHandle("west_1_2"); west_1_3 = GetHandle("west_1_3"); west_1_4 = GetHandle("west_1_4")
        east_1_1 = GetHandle("east_1_1"); east_1_2 = GetHandle("east_1_2"); east_1_3 = GetHandle("east_1_3"); east_1_4 = GetHandle("east_1_4")
        nav = GetHandle("nav"); SetName(nav, "Base")
        howitzer_nw = GetHandle("howitzer_nw"); howitzer_ne = GetHandle("howitzer_ne")
        west_power = GetHandle("west_power"); east_power = GetHandle("east_power")
        east_bolt = GetHandle("east_bolt"); west_bolt = GetHandle("west_bolt")
        walker_1 = GetHandle("walker_1")
        west_comm = GetHandle("west_comm"); east_comm = GetHandle("east_comm")
        
        for i=1,6 do magpull[i] = GetHandle("magpull_"..i) end
        for i=1,4 do west_mag[i] = GetHandle("west_mag_"..i); east_mag[i] = GetHandle("east_mag_"..i) end
        for i=1,26 do snipers[i] = GetHandle("sniper_"..i) end
        
        AudioMessage("ch08001.wav")
        SetCloaked(west_1_1); SetCloaked(west_1_2); SetCloaked(west_1_3); SetCloaked(west_1_4)
        SetCloaked(east_1_1); SetCloaked(east_1_2); SetCloaked(east_1_3); SetCloaked(east_1_4)
        
        CameraReady()
        mission_state = MS_WAITFORTRIGGER
        
    elseif mission_state == MS_WAITFORTRIGGER then
        CameraPath("cut_1", 2000, 0, west_1_1)
        if GetDistance(west_1_1, "cut_trigger") < 50 or GetDistance(east_1_1, "cut_trigger") < 50 then
            mission_state = MS_CAMERATRIGGER; state_timer = GetTime() + 22.0
        end

    elseif mission_state == MS_CAMERATRIGGER then
        CameraPath("cut_1", 2000, 0, west_1_1)
        if GetTime() > state_timer then
            CameraFinish(); mission_state = MS_SPAWNAPC1; state_timer = GetTime() + 30.0; AudioMessage("ch08002.wav")
            RemoveObject(west_1_1); RemoveObject(west_1_2); RemoveObject(west_1_3); RemoveObject(west_1_4)
            RemoveObject(east_1_1); RemoveObject(east_1_2); RemoveObject(east_1_3); RemoveObject(east_1_4)
            RemoveObject(walker_1)
        end

    elseif mission_state == MS_SPAWNAPC1 then
        if GetTime() > state_timer then
            sound_handle = AudioMessage("ch08003.wav")
            apc[1] = BuildObject("svapc", 2, "apc_spawn"); SetName(apc[1], "apc_1"); Goto(apc[1], "apc_path")
            local d1 = BuildObject("svfigh", 2, "apc_escort"); Defend2(d1, apc[1], 1)
            local d2 = BuildObject("svfigh", 2, "apc_escort"); Defend2(d2, apc[1], 1)
            mission_state = MS_SPAWNAPC2; ResetObjectives(); state_timer = GetTime() + 5.0
        end

    elseif mission_state == MS_SPAWNAPC2 or mission_state == MS_SPAWNAPC3 or mission_state == MS_SPAWNAPC4 then
        if GetTime() > state_timer then
            local idx = (mission_state == MS_SPAWNAPC2) and 2 or (mission_state == MS_SPAWNAPC3 and 3 or 4)
            apc[idx] = BuildObject("svapc", 2, "apc_spawn"); SetName(apc[idx], "apc_"..idx); Goto(apc[idx], "apc_path")
            mission_state = (idx == 4) and MS_SPAWNAPC5 or (idx == 2 and MS_SPAWNAPC3 or MS_SPAWNAPC4)
            ResetObjectives(); state_timer = GetTime() + 5.0
        end

    elseif mission_state == MS_SPAWNAPC5 then
        if GetTime() > state_timer then
            apc[5] = BuildObject("svapc", 2, "apc_spawn"); SetName(apc[5], "apc_5"); Goto(apc[5], "apc_path")
            mission_state = MS_WAITFORSCAP; ResetObjectives()
        end

    elseif mission_state == MS_WAITFORSCAP then
        if CheckAPCs() then return end
        if apc[5] == user and GetDistance(apc[5], nav) <= 30.0 then
            state_timer = GetTime() + 5.0; mission_state = MS_WAITSTARTSOUND4; ResetObjectives()
        elseif GetDistance(apc[4], "apc_fail") < 30.0 or (GetDistance(apc[5], "trigger_1") < 30.0 and GetDistance(apc[4], "apc_fail") > 300.0) then
            AudioMessage("ch08005.wav"); FailMission(GetTime() + 20.0, "ch08lsec.des"); mission_state = MS_END
        end

    elseif mission_state == MS_WAITSTARTSOUND4 then
        if CheckAPCs() then return end
        if GetTime() > state_timer then
            SetScrap(1, 100); sound_handle = AudioMessage("ch08004.wav")
            mission_state = MS_WAITFORSOUND4; ResetObjectives()
            SetObjectiveOn(apc[4]); apc3_objective_on = true
        end

    elseif mission_state == MS_WAITFORSOUND4 then
        if CheckAPCs() then return end
        if apc3_objective_on and GetDistance(apc[4], user) < 100.0 then apc3_objective_on = false; SetObjectiveOff(apc[4]) end
        if IsAudioMessageDone(sound_handle) then mission_state = MS_TRIGGER1; ResetObjectives() end

    elseif mission_state == MS_TRIGGER1 then
        if CheckAPCs() then return end
        if apc[5] == user and GetDistance(user, "trigger_1") < 30.0 then
            AudioMessage("ch08006.wav"); mission_state = MS_WAITFORJUMPOUT; state_timer = GetTime() + 20.0
        end

    elseif mission_state == MS_WAITFORJUMPOUT then
        if GetTime() > state_timer then FailMission(GetTime() + 2.0, "ch08lseg.des"); mission_state = MS_END
        elseif apc[5] ~= user then SetPerceivedTeam(user, 2); mission_state = MS_WAITFORWRECKER; state_timer = GetTime() + 20.0 end

    elseif mission_state == MS_WAITFORWRECKER then
        if apc[5] == user then FailMission(GetTime() + 2.0, "ch08lseg.des"); mission_state = MS_END
        elseif GetTime() > state_timer then CameraReady(); mission_state = MS_BANGCAMERA; state_timer = GetTime() + 5.0 end

    elseif mission_state == MS_BANGCAMERA or mission_state == MS_BANGCAMERA2 then
        CameraPath("cut_bang", 2000, 0, apc[5])
        local cam_done = CameraCancelled() or (GetTime() > state_timer)
        if cam_done then
            if mission_state == MS_BANGCAMERA then
                MakeExplosion("xpltrsa", apc[5]); MakeExplosion("xpltrsd", "wrecker_1")
                SetPerceivedTeam(user, 1); for i=1,6 do RemoveObject(magpull[i]) end
                recycler = BuildObject("cvrecy", 1, "military_spawn"); Goto(recycler, "military_path")
                factory = BuildObject("cvmuf", 1, "military_spawn"); Goto(factory, "military_path")
                local slf = BuildObject("cvslf", 1, "military_spawn"); Goto(slf, "military_path")
                SetScrap(1, 100)
            end
            CameraFinish(); mission_state = MS_TRIGGERNWNE; ResetObjectives(); state_timer = GetTime() + 300.0
        end

    elseif mission_state == MS_TRIGGERNWNE then
        if GetTime() > state_timer then state_timer = 0; SetScrap(2, 100) end
        local t_nw = GetDistance(user, "nw_trigger") <= 60.0
        local t_ne = GetDistance(user, "ne_trigger") <= 60.0
        if t_nw or t_ne then
            AudioMessage("ch08007.wav"); AudioMessage("ch08008.wav")
            SetObjectiveOn(howitzer_nw); SetObjectiveOn(howitzer_ne); howitzer_objective_on = true
            SetObjectiveOn(west_power); SetObjectiveOn(east_power); SetObjectiveOn(west_comm); SetObjectiveOn(east_comm)
            mission_state = MS_DESTROYPOWERS; ResetObjectives(); SetUserTarget(t_nw and howitzer_nw or howitzer_ne)
        end

    elseif mission_state == MS_DESTROYPOWERS then
        if (west_power_dead or east_power_dead or west_comm_dead or east_comm_dead) and GetCockpitTimer() < 1 then
            FailMission(GetTime() + 2.0, "ch08lsef.des"); mission_state = MS_END
        end
        if howitzer_objective_on and (user == howitzer_nw or user == howitzer_ne) then 
            howitzer_objective_on = false; SetObjectiveOff(howitzer_nw); SetObjectiveOff(howitzer_ne) 
        end
        
        local function CheckDead(h, var, start_timer)
            if not var and not IsAlive(h) then
                if not west_power_dead and not east_power_dead and not west_comm_dead and not east_comm_dead then StartCockpitTimer(DiffUtils.ScaleTimer(270)) end
                return true
            end
            return var
        end
        west_power_dead = CheckDead(west_power, west_power_dead)
        if west_power_dead then for i=1,4 do RemoveObject(west_mag[i]) end; RemoveObject(west_bolt) end
        west_comm_dead = CheckDead(west_comm, west_comm_dead)
        east_power_dead = CheckDead(east_power, east_power_dead)
        if east_power_dead then for i=1,4 do RemoveObject(east_mag[i]) end; RemoveObject(east_bolt) end
        east_comm_dead = CheckDead(east_comm, east_comm_dead)
        
        if west_power_dead and east_power_dead and west_comm_dead and east_comm_dead then
            HideCockpitTimer(); mission_state = MS_WRECKER10; ResetObjectives(); state_timer = GetTime() + 40.0
        end

    elseif mission_state >= MS_WRECKER10 and mission_state <= MS_WRECKER106 then
        if GetTime() > state_timer then
            local next_s = {
                [MS_WRECKER10] = {MS_WRECKER22, 12, {"day_1", "day_1a"}},
                [MS_WRECKER22] = {MS_WRECKER33, 11, {"day_2", "day_2a"}},
                [MS_WRECKER33] = {MS_WRECKER42, 9, {"day_3"}},
                [MS_WRECKER42] = {MS_WRECKER55, 13, {"day_4", "day_4a"}},
                [MS_WRECKER55] = {MS_WRECKER70, 15, {"day_5", "day_5a"}},
                [MS_WRECKER70] = {MS_WRECKER85, 15, {"day_6"}},
                [MS_WRECKER85] = {MS_WRECKER92, 7, {"day_7", "day_7a"}},
                [MS_WRECKER92] = {MS_WRECKER100, 8, {"day_8", "day_8a"}},
                [MS_WRECKER100] = {MS_WRECKER106, 6, {"day_9", "day_9a"}},
                [MS_WRECKER106] = {MS_END, 0, {"day_10"}}
            }
            local data = next_s[mission_state]
            for _, loc in ipairs(data[3]) do MakeExplosion("xpltrsd", loc) end
            if data[1] == MS_END then
                AudioMessage("ch08009.wav"); SucceedMission(GetTime() + 10.0, "ch08win.des"); mission_state = MS_END
            else
                mission_state = data[1]; state_timer = GetTime() + data[2]
            end
        end
    end
    
    CheckSpawns()
    old_user = user
end

