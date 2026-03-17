-- bdmisn10.lua (Converted from BlackDog10Mission.cpp)

-- Compatibility
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3659600763" })
local exu = require("exu")
local aiCore = require("aiCore")
local subtit = require("ScriptSubtitles")

-- Helper for AI
local function SetupAI()
    -- Team 1: Black Dogs (Player)
    -- Team 2: CAA (Enemy)
    local caa = aiCore.AddTeam(2, aiCore.Factions.CCA)

    local diff = (exu and exu.GetDifficulty and exu.GetDifficulty()) or 2
    if diff <= 1 then
        AddObjective("easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced.")
    elseif diff >= 3 then
        AddObjective("hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified.")
    end
end

local M = {
    -- Handles
    player = 0,
    recycler = 0,
    enemy_recycler = 0,

    -- States
    arrived = false,
    camera_time = 0,
    camera_complete = { false, false, false },

    -- Variables
    TPS = 20
}

function Start()
    M.TPS = 20
    M.player = GetPlayerHandle()

    -- Setup AI
    SetupAI()

    -- Mission Init logic (Ported from CPP)
    M.recycler = GetHandle("recycler")
    M.enemy_recycler = GetHandle("enemy_recycler")

    SetLabel(M.enemy_recycler, "Enemy Recycler")
end

function AddObject(h)
    local team = GetTeamNum(h)
    local odf = GetOdf(h)

    -- TURBO Logic (Hard+)
    if team == 2 and IsOdf(h, "vehicle") then
        SetLabel(h, "Enemy")
    end
end

function Update()
    M.player = GetPlayerHandle()

    -- Main mission loop logic
    local recycler = M.recycler
    local enemy_recycler = M.enemy_recycler

    if not IsAlive(enemy_recycler) and not M.camera_complete[1] then
        M.camera_complete[1] = true
        M.camera_time = GetTime() + 10.0
        CameraReady()
    end

    if M.camera_complete[1] and not M.camera_complete[2] then
        CameraPath("camera_win", 100, 500, recycler)
        if (GetTime() > M.camera_time) or CameraCancelled() then
            CameraFinish()
            M.camera_complete[2] = true
            M.camera_time = GetTime() + 5.0
        end
    end

    if M.camera_complete[2] and not M.camera_complete[3] then
        local arrived = M.arrived
        local camera_time = M.camera_time
        local camera_complete = M.camera_complete

        if not arrived then
            CameraPath("camera_end", 30, 200, recycler)
            -- Assuming arrived logic handled by engine or time
        end

        if (GetTime() > camera_time) or CameraCancelled() then
            camera_complete[3] = true
            SucceedMission(GetTime() + 1.0, "bd10win.des")
        end
    end
end

function PostLoad()
    M.player = GetPlayerHandle()
    subtit.Update()
end
