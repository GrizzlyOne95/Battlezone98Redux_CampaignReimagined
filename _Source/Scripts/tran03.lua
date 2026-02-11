-- tran03.lua
-- Ported from Tran03Mission.cpp
-- Training Mission 3: Strategy & Building

-- Compatibility
SetLabel = SetLabel or SettLabel

-- Libraries
local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3659600763"}) 
local exu = require("exu")
local DiffUtils = require("DiffUtils")
local Subtitles = require("ScriptSubtitles")

-- Mission State
local found = false
local start_done = false
local first_message = false
local second_message = false
local third_message = false
local fourth_message = false
local fifth_message = false
local fifthb_message = false
local sixth_message = false
local seventh_message = false
local eighth_message = false
local scav_died = false

local delay_message = 99999.0

-- Handles
local scav = nil
local attacker = nil
local geyser = nil
local recycler = nil

function Save()
    return found, start_done, first_message, second_message, third_message,
           fourth_message, fifth_message, fifthb_message, sixth_message,
           seventh_message, eighth_message, scav_died,
           delay_message,
           scav, attacker, geyser, recycler
end

function Load(...)
    local arg = {...}
    if #arg > 0 then
        found, start_done, first_message, second_message, third_message,
        fourth_message, fifth_message, fifthb_message, sixth_message,
        seventh_message, eighth_message, scav_died,
        delay_message,
        scav, attacker, geyser, recycler = unpack(arg)
    end
end

function Start()
    Subtitles.Initialize("durations.csv")
    DiffUtils.SetupTeams(1, 2, 0) 
    
    geyser = GetHandle("eggeizr111_geyser")
    recycler = GetHandle("avrecy-1_recycler")
    attacker = GetHandle("svfigh-1_wingman")
    
    delay_message = 99999.0
    
    -- QOL Improvements
    if exu then
        if exu.SetShotConvergence then exu.SetShotConvergence(true) end
        if exu.SetReticleRange then exu.SetReticleRange(500) end
    end
end

function AddObject(h)
    -- Check for Scavenger built by player (Team 1)
    local odf = GetOdf(h)
    if odf then 
        odf = string.lower(odf) 
        -- Clean nulls
        odf = string.gsub(odf, "%z", "")
    end
    
    if GetTeamNum(h) == 1 and odf and string.find(odf, "avscav") then
        found = true
        scav = h
    end
end

function Update()
    Subtitles.Update()
    if exu and exu.UpdateOrdnance then exu.UpdateOrdnance() end
    
    if not start_done then
        Subtitles.Play("tran0301.wav")
        Subtitles.Play("tran0302.wav")
        
        geyser = geyser or GetHandle("eggeizr111_geyser")
        recycler = recycler or GetHandle("avrecy-1_recycler")
        attacker = attacker or GetHandle("svfigh-1_wingman")
        
        if IsAlive(recycler) then
            SetObjectiveOn(recycler)
            SetObjectiveName(recycler, "Recycler")
            SetScrap(1, 7)
        end
        
        -- Difficulty Scaling for Attacker
        if IsAlive(attacker) and DiffUtils.Get().enemyTurbo then
             -- Turbo only on Very Hard (or Hard if tweaked in DiffUtils)
             if exu and exu.SetUnitTurbo then exu.SetUnitTurbo(attacker, true) end
        end
        
        ClearObjectives()
        AddObjective("tran0301.otf", "white")
        AddObjective("tran0302.otf", "white")
        
        start_done = true
    end
    
    if start_done and not first_message and IsAlive(recycler) and IsSelected(recycler) then
        Subtitles.Play("tran0303.wav")
        SetObjectiveOff(recycler)
        SetObjectiveOn(geyser)
        SetObjectiveName(geyser, "Check Point 1")
        first_message = true
    end
    
    if first_message and not second_message and IsAlive(recycler) then
        if not IsDeployed(recycler) then
            Subtitles.Play("tran0304.wav")
            second_message = true
        end
    end
    
    if second_message and not third_message and IsAlive(recycler) then
        local dist = GetDistance(geyser, recycler)
        if dist < 200.0 then
            Subtitles.Play("tran0305.wav")
            third_message = true
        end
    end
    
    if third_message and not fourth_message and IsAlive(recycler) and IsSelected(recycler) then
        Subtitles.Play("tran0306.wav")
        fourth_message = true
    end
    
    if third_message and not fifth_message and IsAlive(recycler) then
        -- User Corrected: Use native IsDeployed
        if IsDeployed(recycler) then
            SetObjectiveOff(geyser)
            ClearObjectives()
            AddObjective("tran0301.otf", "green")
            AddObjective("tran0302.otf", "white")
            
            Subtitles.Play("tran0307.wav")
            fifth_message = true
        end
    end
    
    if fifth_message and not fifthb_message and IsSelected(recycler) then
         Subtitles.Play("tran0309.wav")
         fifthb_message = true
    end
    
    if IsAlive(attacker) and not sixth_message then
         AddHealth(attacker, 50.0) 
    end
    
    if fifth_message and not sixth_message then
        local money = GetScrap(1)
        if money < 5 and found then
            Subtitles.Play("tran0308.wav")
            sixth_message = true
            delay_message = GetTime() + 5.0
            
            if IsAlive(attacker) and IsAlive(scav) then
                SetCommand(attacker, "attack", scav)
            end
        end
    end
    
    if not scav_died and ( not IsAlive(recycler) or (sixth_message and not IsAlive(scav)) ) then
        scav_died = true
        Subtitles.Play("tran0313.wav")
        FailMission(GetTime() + 10.0, "tran03l1.des")
    end
    
    if GetTime() > delay_message then
        delay_message = 99999.0
    end
    
    if sixth_message and not seventh_message and not IsAlive(attacker) then
        Subtitles.Play("tran0314.wav")
        seventh_message = true
    end
    
    if seventh_message and not eighth_message then
        local money = GetScrap(1)
        if money > 1 then
            Subtitles.Play("tran0310.wav")
            Subtitles.Play("tran0315.wav")
            eighth_message = true
            SucceedMission(GetTime() + 20.0, "tran03w1.des")
        end
    end

end

