-- cmisn07.lua (Converted from Chinese07Mission.cpp)

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

-- Mission States/Logic Bools
local start_done = false
local objective1_complete = false
local objective2_complete = false
local objective3_complete = false
local camera_complete = {false, false, false}
local camera_ready = {false, false, false}
local do_burglar_sequence = false
local burglar_sequence_played = false
local do_north_sequence = false
local do_east_sequence = false
local convoy_spawned = false
local bomb_destroyed = false
local snipers_spawned = false
local sound6_played = false
local triggered = false
local arrived = false
local backups = {false, false, false, false}
local rescue = false
local won = false
local lost = false

-- Timers
local opening_sound_time = 99999.0
local burglar_stop_time = 99999.0
local foot1_time = 99999.0
local sound5_time = 99999.0
local convoy_time = 99999.0
local cin_burglar_timeout = 99999.0

-- Handles
local user, last_user, fake_player
local comm_tower, relic_apc, nav_bridge
local foot = {} -- 6
local fighters = {} -- 7
local bombs = {} -- 2
local end_guy = {} -- 6
local ammo1, ammo2, repair1, repair2
local opening_sound, seq_sound, win_sound, sound7

-- Data
local direction = 0 -- 0=North, 1=East
local relic_idx = 0 -- 0..2
local convoy_count = 0
local told_to_attack = {} -- 7
local zn_attacked = {} -- 7
for i=1,7 do zn_attacked[i] = false; told_to_attack[i] = false end

local specials = {
    "svapcc", "svapcd", "svapce", "svapcf", "svapcg",
    "svapch", "svapci", "svapcj", "svapck", "svapcl",
    "svapcm", "svapcn", "svapco", "svapcp", "svapcs"
}
local otf2 = {"ch07002n.otf", "ch07002e.otf"}

function Start()
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
        if exu.SetGlobalTurbo then exu.SetGlobalTurbo(true) end
    end
    SetupAI()
    direction = math.random(0, 1)
    relic_idx = math.random(0, 2)
    start_done = false
end

function AddObject(h)
    if GetTeamNum(h) == 2 then aiCore.AddObject(h) end
end

function DeleteObject(h)
end

function Update()
    last_user = user
    user = GetPlayerHandle()
    aiCore.Update()
    
    if not start_done then
        SetPilot(1, DiffUtils.ScaleRes(10))
        SetScrap(1, DiffUtils.ScaleRes(8))
        burglar_stop_time = GetTime() + DiffUtils.ScaleTimer(90.0)
        sound5_time = GetTime() + DiffUtils.ScaleTimer(780.0)
        convoy_time = GetTime() + DiffUtils.ScaleTimer(840.0)
        
        comm_tower = GetHandle("commtower")
        for i=1,3 do foot[i] = GetHandle("foot_1_"..i) end
        for i=4,6 do foot[i] = GetHandle("foot_2_"..(i-3)) end
        
        for i=1,3 do fighters[i] = GetHandle("figh_1_"..i) end
        for i=4,5 do fighters[i] = GetHandle("figh_2_"..(i-3)) end
        for i=6,7 do fighters[i] = GetHandle("figh_3_"..(i-5)) end
        
        bombs[0] = GetHandle("bomb_north")
        bombs[1] = GetHandle("bomb_east")
        
        ammo1 = GetHandle("ammo_1"); ammo2 = GetHandle("ammo_2")
        repair1 = GetHandle("repair_1"); repair2 = GetHandle("repair_2")
        
        start_done = true
    end
    
    if won or lost then return end
    
    if user ~= last_user and not do_burglar_sequence then
        SetPerceivedTeam(user, 1)
    end
    
    -- Intro
    if not camera_complete[1] then
        if not camera_ready[1] then
            camera_ready[1] = true; CameraReady()
            opening_sound = AudioMessage("ch07001.wav")
        end
        local arrived_cam = CameraPath("cin_start", 800, 2400, comm_tower)
        if arrived_cam or CameraCancelled() then
            if CameraCancelled() and opening_sound then StopAudioMessage(opening_sound) end
            CameraFinish(); camera_complete[1] = true
            ClearObjectives(); AddObjective("ch07001.otf", "white")
        end
    end
    
    -- Fighter Aggro
    for i=1,7 do
        if IsAlive(fighters[i]) and not told_to_attack[i] and GetDistance(user, fighters[i]) < 160.0 then
            Attack(fighters[i], user, 1); told_to_attack[i] = true
        end
    end
    
    -- Burglar Trigger
    if not burglar_sequence_played and GetDistance(user, comm_tower) < 30.0 then
        do_burglar_sequence = true; burglar_sequence_played = true
    end
    
    if do_burglar_sequence then
        if not camera_ready[2] then
            CameraReady(); camera_ready[2] = true
            Hide(user); SetPerceivedTeam(user, 2)
            fake_player = BuildObject("sspilo", 0, "fake_spn")
            Goto(fake_player, "fake_vanish", 1)
        end
        CameraPath("cin_burglar", 400, 0, comm_tower)
        if fake_player and GetDistance(fake_player, "fake_vanish") < 10.0 then
            RemoveObject(fake_player); fake_player = nil
            cin_burglar_timeout = GetTime() + 3.0
        end
        if GetTime() > cin_burglar_timeout or CameraCancelled() then
            CameraFinish()
            if fake_player then RemoveObject(fake_player) end
            SetPerceivedTeam(user, 1); UnHide(user)
            SetPosition(user, "burglar_exit")
            do_burglar_sequence = false; objective1_complete = true
            if direction == 0 then do_north_sequence = true else do_east_sequence = true end
        end
    end
    
    -- Choice Sequences
    if do_north_sequence then
        if not camera_ready[3] then
            camera_ready[3] = true; CameraReady()
            seq_sound = AudioMessage("ch07002.wav")
            nav_bridge = BuildObject("apcamr", 1, "nav_north"); SetName(nav_bridge, "North Bridge")
        end
        local arrived_choice = false
        if not arrived then arrived = CameraPath("cin_north", 1600, 1800, bombs[0]) end
        if arrived and IsAudioMessageDone(seq_sound) then arrived_choice = true end
        if arrived_choice or CameraCancelled() then
            if CameraCancelled() and seq_sound then StopAudioMessage(seq_sound) end
            CameraFinish(); do_north_sequence = false
            ClearObjectives(); AddObjective("ch07001.otf", "green"); AddObjective(otf2[1], "white")
            foot1_time = GetTime() + 10.0
        end
    end
    
    if do_east_sequence then
        if not camera_ready[3] then
            camera_ready[3] = true; CameraReady()
            seq_sound = AudioMessage("ch07003.wav")
            nav_bridge = BuildObject("apcamr", 1, "nav_east"); SetName(nav_bridge, "East Bridge")
        end
        local arrived_choice = false
        if not arrived then arrived = CameraPath("cin_east", 1600, 1800, bombs[1]) end
        if arrived and IsAudioMessageDone(seq_sound) then arrived_choice = true end
        if arrived_choice or CameraCancelled() then
            if CameraCancelled() and seq_sound then StopAudioMessage(seq_sound) end
            CameraFinish(); do_east_sequence = false
            ClearObjectives(); AddObjective("ch07001.otf", "green"); AddObjective(otf2[2], "white")
            foot1_time = GetTime() + 10.0
        end
    end
    
    if GetTime() > foot1_time then
        foot1_time = 99999.0
        for i=1,6 do if IsAlive(foot[i]) then Attack(foot[i], user, 1) end end
        AudioMessage("ch07004.wav")
    end
    
    -- Zone Attacks (Optimized loop)
    for i=1,7 do
        if not zn_attacked[i] and GetDistance(user, "zn_"..i.."_trig") < 900.0 then
            zn_attacked[i] = true
            local function S(odf, s) local h = BuildObject(odf, 2, s); Attack(h, user) end
            if i==1 then
                for j=1, DiffUtils.ScaleEnemy(5) do S("ssusera", "zn_1_snip_"..((j-1)%5+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(2) do S("sssold", "zn_1_sold_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("svturr", "zn_1_turr_"..((j-1)%3+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("sspilo", "zn_1_pilo_"..((j-1)%3+1).."_spn") end
            elseif i==2 then
                for j=1, DiffUtils.ScaleEnemy(6) do S("ssusera", "zn_2_snip_"..((j-1)%6+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(2) do S("sssold", "zn_2_sold_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(6) do S("svturr", "zn_2_turr_"..((j-1)%6+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("sspilo", "zn_2_pilo_"..((j-1)%3+1).."_spn") end
            elseif i==3 then
                for j=1, DiffUtils.ScaleEnemy(5) do S("ssusera", "zn_3_snip_"..((j-1)%5+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(2) do S("sssold", "zn_3_sold_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(6) do S("svturr", "zn_3_turr_"..((j-1)%6+1).."_spn") end
            elseif i==4 then
                for j=1, DiffUtils.ScaleEnemy(5) do S("ssusera", "zn_4_snip_"..((j-1)%5+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(2) do S("sssold", "zn_4_sold_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("svturr", "zn_4_turr_"..((j-1)%3+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("sspilo", "zn_4_pilo_"..((j-1)%3+1).."_spn") end
            elseif i==5 then
                for j=1, DiffUtils.ScaleEnemy(6) do S("ssusera", "zn_5_snip_"..((j-1)%6+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(2) do S("sssold", "zn_5_sold_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("svturr", "zn_5_turr_"..((j-1)%3+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("sspilo", "zn_5_pilo_"..((j-1)%3+1).."_spn") end
            elseif i==6 then
                for j=1, DiffUtils.ScaleEnemy(2) do S("ssusera", "zn_6_snip_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(4) do S("svturr", "zn_6_turr_"..((j-1)%4+1).."_spn") end
            elseif i==7 then
                for j=1, DiffUtils.ScaleEnemy(2) do S("ssusera", "zn_7_snip_"..((j-1)%2+1).."_spn") end
                for j=1, DiffUtils.ScaleEnemy(3) do S("svturr", "zn_7_turr_"..((j-1)%3+1).."_spn") end
            end
        end
    end
    
    -- Convoy Spawn
    if GetTime() > convoy_time then
        local spawn_nodes = {"north_spn", "east_spn"}
        local path_nodes = {"north_path", "east_path"}
        local loc = spawn_nodes[direction+1]
        local h
        if convoy_count == relic_idx then
            h = BuildObject("svapca", 2, loc); relic_apc = h
        else
            if convoy_count == 2 or (convoy_count == 1 and relic_idx == 2) then
                h = BuildObject(specials[math.random(1, #specials)], 2, loc)
            else
                h = BuildObject("svapcb", 2, loc)
            end
        end
        Goto(h, path_nodes[direction+1])
        local d = BuildObject("svfigh", 2, loc); Defend2(d, h, 1)
        
        convoy_count = convoy_count + 1
        if convoy_count == 3 then convoy_time = 99999.0; convoy_spawned = true
        else convoy_time = GetTime() + 8.0 end
    end
    
    -- Triggred Intercept
    if not triggered then
        local trigs = {"north_trig", "east_trig"}
        if GetDistance(user, trigs[direction+1]) < 350.0 then
            triggered = true
            local sold_spns = {{"sold_north_1_spn", "sold_north_2_spn"}, {"sold_east_1_spn", "sold_east_2_spn"}}
            local pilo_spns = {{"pilo_north_1_spn", "pilo_north_2_spn"}, {"pilo_east_1_spn", "pilo_east_2_spn"}}
            local function S(o, spn) local h = BuildObject(o, 2, spn); Attack(h, user, 1) end
            S("sssold", sold_spns[direction+1][1]); S("sssold", sold_spns[direction+1][2])
            S("sspilo", pilo_spns[direction+1][1]); S("sspilo", pilo_spns[direction+1][2])
            objective2_complete = true; ClearObjectives()
            AddObjective("ch07001.otf", objective1_complete and "green" or "white")
            AddObjective(otf2[direction+1], "green"); AddObjective("ch07003.otf", "white")
        end
    end
    
    -- Bomb
    if not bomb_destroyed and IsAlive(bombs[direction]) and GetHealth(bombs[direction]) <= 0.0 then
        bomb_destroyed = true
        local expl_spns = {"expl_north_spn", "expl_east_spn"}
        MakeExplosion("xtorxpla", expl_spns[direction+1])
        local sold_spns = {{"north_sold_1_spn", "north_sold_2_spn", "north_sold_3_spn"}, {"east_sold_1_spn", "east_sold_2_spn", "east_sold_3_spn"}}
        for j=1,3 do local h = BuildObject("sssold", 2, sold_spns[direction+1][j]); Attack(h, user) end
    end
    
    -- Relic Destruction
    if relic_apc and GetHealth(relic_apc) <= 0.0 and not objective3_complete then
        objective3_complete = true
        ClearObjectives()
        AddObjective("ch07001.otf", objective1_complete and "green" or "white")
        AddObjective(otf2[direction+1], "green")
        AddObjective("ch07003.otf", "green"); AddObjective("ch07004.otf", "white")
        AudioMessage("ch07008.wav")
        local h = BuildObject("apcamr", 1, "nav_end"); SetName(h, "Drop Zone")
    end
    
    if objective3_complete then
        if not backups[1] and GetDistance(user, "zn_8_trig") < 800.0 then
            backups[1] = true
            for j=1, DiffUtils.ScaleEnemy(4) do local h = BuildObject("sssold", 2, "back_1_"..((j-1)%4+1).."_spn"); Attack(h, user) end
        end
        if not backups[2] and GetDistance(user, "zn_9_trig") < 800.0 then
            backups[2] = true
            for j=1, DiffUtils.ScaleEnemy(4) do local h = BuildObject("sssold", 2, "back_2_"..((j-1)%4+1).."_spn"); Attack(h, user) end
        end
        if not backups[3] and GetDistance(user, "nav_end") < 1000.0 then
            backups[3] = true
            for j=1, DiffUtils.ScaleEnemy(8) do local h = BuildObject("sspilo", 2, "pilo_end_"..((j-1)%8+1).."_spn"); Attack(h, user) end
        end
    end
    
    -- Relic APC Escape
    if relic_apc and not lost and not won then
        local w_spots = {"north_wav", "east_wav"}
        local f_spots = {"north_fail", "east_fail"}
        if GetDistance(relic_apc, w_spots[direction+1]) < 50.0 and not sound6_played then
            sound6_played = true; AudioMessage("ch07006.wav")
        end
        if GetDistance(relic_apc, f_spots[direction+1]) < 50.0 then
            lost = true; sound7 = AudioMessage("ch07007.wav")
        end
    end
    if sound7 and IsAudioMessageDone(sound7) then FailMission(GetTime() + 1.0, "ch07lose.des") end
    
    -- Finale
    if objective3_complete and GetDistance(user, "nav_end") < 170.0 and not snipers_spawned then
        snipers_spawned = true
        for j=1, DiffUtils.ScaleEnemy(3) do end_guy[j] = BuildObject("ssusera", 2, "snip_end_"..((j-1)%3+1).."_spn"); Attack(end_guy[j], user, 1) end
        for j=1, DiffUtils.ScaleEnemy(3) do end_guy[j+DiffUtils.ScaleEnemy(3)] = BuildObject("sssold", 2, "sold_end_"..((j-1)%3+1).."_spn"); Attack(end_guy[j+DiffUtils.ScaleEnemy(3)], user, 1) end
    end
    
    if objective3_complete and GetDistance(user, "nav_end") < 140.0 and not rescue then
        rescue = true
        for j=1,5 do BuildObject("cspilo", 1, "rescue_"..j.."_spn") end
    end
    
    if objective3_complete and snipers_spawned and GetDistance(user, "nav_end") < 50.0 and not won and not lost then
        local all_dead = true
        for j=1,6 do if IsAlive(end_guy[j]) then all_dead = false; break end end
        if all_dead then
            won = true; win_sound = AudioMessage("ch07009.wav")
        end
    end
    if win_sound and IsAudioMessageDone(win_sound) then SucceedMission(GetTime() + 1.0, "ch07win.des") end
    
    -- Pickups
    local function CheckPk(h_ref, odf, is_health)
        if h_ref and GetDistance(user, h_ref) < 5.0 then
            local success = is_health and GiveMaxHealth(user) or GiveMaxAmmo(user)
            if success then
                ColorFade(1.0, 5.0, 0, 255, 0); AudioMessage("repair.wav")
                RemoveObject(h_ref); return nil
            end
        end
        return h_ref
    end
    ammo1 = CheckPk(ammo1, "ammo_1", false); ammo2 = CheckPk(ammo2, "ammo_2", false)
    repair1 = CheckPk(repair1, "repair_1", true); repair2 = CheckPk(repair2, "repair_2", true)
end

