-- Chinese07Mission.cpp faithfully ported to stock BZR / Lua 5.1.
-- Source blob: 15672b609a6bb5bda727c99ced2b7ed25dad3b6e.
-- Complete source (including ALL comments, #if 0 blocks, and cut content):
-- References/Chinese07Source/Chinese07Mission.cpp
-- Zero-based explicit tables preserve native indexes (direction/relic included).
-- No EXU, OpenShim, or campaign helper dependency.
local otf2 = { [0] = "ch07002n.otf", [1] = "ch07002e.otf" }
local specials = {
    [0] = "svapcc",
    [1] = "svapcd",
    [2] = "svapce",
    [3] = "svapcf",
    [4] = "svapcg",
    [5] = "svapch",
    [6] = "svapci",
    [7] = "svapcj",
    [8] = "svapck",
    [9] = "svapcl",
    [10] = "svapcm",
    [11] = "svapcn",
    [12] = "svapco",
    [13] = "svapcp",
    [14] = "svapcs",
}

local function NewState()
    -- Native Load clears all flags, including Setup's unused/untouched fields.
    local s = {}
    s.arrived = false
    s.backup1 = false
    s.backup2 = false
    s.backup3 = false
    s.backup4 = false
    s.bombDestroyed = false
    s.bombs = {}
    s.burglarSequencePlayed = false
    s.cameraComplete = {}
    s.cameraReady = {}
    s.convoySpawned = false
    s.detected = false
    s.doBurglarSequence = false
    s.doEastSequence = false
    s.doNorthSequence = false
    s.endGuy = {}
    s.fighters = {}
    s.foot = {}
    s.gotInFighter = false
    s.gotOutOfFighter = false
    s.inHauler = false
    s.lost = false
    s.objective1Complete = false
    s.objective2Complete = false
    s.objective3Complete = false
    s.rescue = false
    s.snipersSpawned = false
    s.sound6Played = false
    s.startDone = false
    s.toldToAttackFighter = {}
    s.triggered = false
    s.won = false
    s.znAttacked = {}
    return s
end
local M = NewState()

local function Refill(h, health)
    -- Native GiveMax* returns whether a refill happened; the Lua bindings do
    -- not promise a boolean. Test current/max first so a full vehicle does not
    -- consume a pickup. Preserve the original distance, effect, and removal.
    local current = health and GetCurHealth(h) or GetCurAmmo(h)
    local maximum = health and GetMaxHealth(h) or GetMaxAmmo(h)
    if current >= maximum then return false end
    if health then SetCurHealth(h, maximum) else SetCurAmmo(h, maximum) end
    return true
end

function Start()
    M = NewState()
    M.startDone = false
    M.objective1Complete = false
    M.objective2Complete = false
    M.objective3Complete = false
    M.doBurglarSequence = false
    M.burglarSequencePlayed = false
    M.detected = false
    M.doNorthSequence = false
    M.doEastSequence = false
    M.convoySpawned = false
    M.bombDestroyed = false
    M.gotInFighter = false
    M.gotOutOfFighter = false
    M.snipersSpawned = false
    M.sound6Played = false
    M.triggered = false
    M.arrived = false
    M.backup1 = false
    M.backup2 = false
    M.backup3 = false
    M.backup4 = false
    M.rescue = false
    M.inHauler = false
    for i = 0, 2 do
        M.cameraReady[i] = false
        M.cameraComplete[i] = false
    end
    for i = 0, 6 do
        M.znAttacked[i] = false
    end
    for i = 0, 6 do
        M.toldToAttackFighter[i] = false
    end
    M.user = nil
    M.lastUser = nil
    M.commTower = GetHandle("commtower")
    M.relicApc = nil
    M.foot[0] = GetHandle("foot_1_1")
    M.foot[1] = GetHandle("foot_1_2")
    M.foot[2] = GetHandle("foot_1_3")
    M.foot[3] = GetHandle("foot_2_1")
    M.foot[4] = GetHandle("foot_2_2")
    M.foot[5] = GetHandle("foot_2_3")
    M.fighters[0] = GetHandle("figh_1_1")
    M.fighters[1] = GetHandle("figh_1_2")
    M.fighters[2] = GetHandle("figh_1_3")
    M.fighters[3] = GetHandle("figh_2_1")
    M.fighters[4] = GetHandle("figh_2_2")
    M.fighters[5] = GetHandle("figh_3_1")
    M.fighters[6] = GetHandle("figh_3_2")
    M.bombs[0] = GetHandle("bomb_north")
    M.bombs[1] = GetHandle("bomb_east")
    for i = 0, 5 do
        M.endGuy[i] = nil
    end
    M.ammo1 = GetHandle("ammo_1")
    M.ammo2 = GetHandle("ammo_2")
    M.repair1 = GetHandle("repair_1")
    M.repair2 = GetHandle("repair_2")
    M.navBridge = nil
    M.openingSound = nil
    M.seqSound = nil
    M.winSound = nil
    M.sound7 = nil
    M.figh1Time = 999999.9
    M.figh2Time = 999999.9
    M.figh3Time = 999999.9
    M.sound5Time = 999999.9
    M.burglarStopTime = 999999.9
    M.foot1Time = 999999.9
    M.convoyTime = 999999.9
    M.cinBurglarTimeout = 999999.9
    M.direction = math.random(0, 1)
    M.relic = math.random(0, 2)
    M.convoyCount = 0
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

-- Native getBase() is unused and its entire candidate list is #if 0.
local function getBase()
    -- Disabled native candidate selection (#if 0), kept for cut-content work:
    -- local candidates = {}
    -- if GetHealth(recycler) > 0 then candidates[#candidates + 1] = recycler end
    -- if GetHealth(factory) > 0 then candidates[#candidates + 1] = factory end
    -- if GetHealth(armoury) > 0 then candidates[#candidates + 1] = armoury end
    -- if GetHealth(silo1) > 0 then candidates[#candidates + 1] = silo1 end
    -- if GetHealth(silo2) > 0 then candidates[#candidates + 1] = silo2 end
    -- if #candidates > 0 then return candidates[math.random(1, #candidates)] end
    return nil
end

function Update(dt)
    M.lastUser = M.user
    M.user = GetPlayerHandle()
    if not M.startDone then
        SetPilot(1, 10)
        SetScrap(1, 8)
        M.startDone = true
        M.burglarStopTime = GetTime() + 90.0
        M.sound5Time = GetTime() + 13 * 60.0
        M.convoyTime = GetTime() + 14 * 60.0
        -- Native #if 0 debugging block (inactive):
        -- SetPerceivedTeam(M.user, 0)
        -- M.doNorthSequence = true
        -- M.cameraComplete[0] = true
        -- SetObjectiveOn(M.bombs[M.direction])
    end
    if M.user ~= M.lastUser and not M.doBurglarSequence then
        SetPerceivedTeam(M.user, 1)
    end
    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            M.cameraReady[0] = true
            CameraReady()
            M.openingSound = AudioMessage("ch07001.wav")
        end
        local openingArrived = CameraPath("cin_start", 800, 2400, M.commTower)
        if CameraCancelled() then
            openingArrived = true
            StopAudioMessage(M.openingSound)
        end
        if openingArrived then
            CameraFinish()
            M.cameraComplete[0] = true
            ClearObjectives()
            AddObjective("ch07001.otf", "white")
        end
    end
    for i = 0, 6 do
        if IsAlive(M.fighters[i]) and not M.toldToAttackFighter[i] and GetDistance(M.user, M.fighters[i]) < 160.0 then
            Attack(M.fighters[i], M.user, 1)
            M.toldToAttackFighter[i] = true
        end
    end
    if not M.burglarSequencePlayed and GetDistance(M.user, M.commTower) < 30.0 then
        M.doBurglarSequence = true
        M.burglarSequencePlayed = true
    end
    if M.doBurglarSequence then
        if not M.cameraReady[1] then
            CameraReady()
            M.cameraReady[1] = true
            Hide(M.user)
            SetPerceivedTeam(M.user, 2)
            M.fakePlayer = BuildObject("sspilo", 0, "fake_spn")
            Goto(M.fakePlayer, "fake_vanish", 1)
        end
        CameraPath("cin_burglar", 400, 0, M.commTower)
        if M.fakePlayer ~= nil and GetDistance(M.fakePlayer, "fake_vanish") < 10.0 then
            RemoveObject(M.fakePlayer)
            M.fakePlayer = nil
            M.cinBurglarTimeout = GetTime() + 3.0
        end
        if M.cinBurglarTimeout < GetTime() or
			CameraCancelled() then
            CameraFinish()
            if M.fakePlayer ~= nil then
                RemoveObject(M.fakePlayer)
            end
            SetPerceivedTeam(M.user, 1)
            UnHide(M.user)
            SetPosition(M.user, "burglar_exit")
            M.doBurglarSequence = false
            if M.direction == 0 then
                M.doNorthSequence = true
            else
                if M.direction == 1 then
                    M.doEastSequence = true
                end
            end
            M.objective1Complete = true
        end
    end
    if M.doNorthSequence then
        if not M.cameraReady[2] then
            M.cameraReady[2] = true
            CameraReady()
            M.seqSound = AudioMessage("ch07002.wav")
            M.navBridge = BuildObject("apcamr", 1, "nav_north")
            SetName(M.navBridge, "North Bridge")
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("cin_north", 1600, 1800, M.bombs[0])
        end
        if M.arrived and IsAudioMessageDone(M.seqSound) then
            seqDone = true
        end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.seqSound)
        end
        if seqDone then
            CameraFinish()
            M.doNorthSequence = false
            ClearObjectives()
            AddObjective("ch07001.otf", "green")
            AddObjective("ch07002n.otf", "white")
            M.foot1Time = GetTime() + 10.0
        end
    end
    if M.doEastSequence then
        if not M.cameraReady[2] then
            M.cameraReady[2] = true
            CameraReady()
            M.seqSound = AudioMessage("ch07003.wav")
            M.navBridge = BuildObject("apcamr", 1, "nav_east")
            SetName(M.navBridge, "East Bridge")
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("cin_east", 1600, 1800, M.bombs[1])
        end
        if M.arrived and IsAudioMessageDone(M.seqSound) then
            seqDone = true
        end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.seqSound)
        end
        if seqDone then
            CameraFinish()
            M.doEastSequence = false
            ClearObjectives()
            AddObjective("ch07001.otf", "green")
            AddObjective("ch07002e.otf", "white")
            M.foot1Time = GetTime() + 10.0
        end
    end
    if M.foot1Time < GetTime() then
        M.foot1Time = 999999.9
        for i = 0, 5 do
            if IsAlive(M.foot[i]) then
                Attack(M.foot[i], M.user, 1)
            end
        end
        AudioMessage("ch07004.wav")
    end
    -- Native //if (objective1Complete) is deliberately disabled.
    if not M.znAttacked[0] and GetDistance(M.user, "zn_1_trig") < 900.0 then
        M.znAttacked[0] = true
        local h
        h = BuildObject("ssusera", 2, "zn_1_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_1_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_1_snip_3_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_1_snip_4_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_1_snip_5_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_1_sold_1_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_1_sold_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_1_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_1_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_1_turr_3_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_1_pilo_1_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_1_pilo_2_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_1_pilo_3_spn")
        Attack(h, M.user)
    end
    if not M.znAttacked[1] and GetDistance(M.user, "zn_2_trig") < 900.0 then
        M.znAttacked[1] = true
        local h
        h = BuildObject("ssusera", 2, "zn_2_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_2_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_2_snip_3_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_2_snip_4_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_2_snip_5_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_2_snip_6_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_2_sold_1_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_2_sold_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_2_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_2_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_2_turr_3_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_2_turr_4_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_2_turr_5_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_2_turr_6_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_2_pilo_1_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_2_pilo_2_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_2_pilo_3_spn")
        Attack(h, M.user)
    end
    if not M.znAttacked[2] and GetDistance(M.user, "zn_3_trig") < 900.0 then
        M.znAttacked[2] = true
        local h
        h = BuildObject("ssusera", 2, "zn_3_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_3_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_3_snip_3_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_3_snip_4_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_3_snip_5_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_3_sold_1_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_3_sold_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_3_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_3_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_3_turr_3_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_3_turr_4_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_3_turr_5_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_3_turr_6_spn")
        Attack(h, M.user)
    end
    if not M.znAttacked[3] and GetDistance(M.user, "zn_4_trig") < 900.0 then
        M.znAttacked[3] = true
        local h
        h = BuildObject("ssusera", 2, "zn_4_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_4_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_4_snip_3_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_4_snip_4_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_4_snip_5_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_4_sold_1_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_4_sold_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_4_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_4_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_4_turr_3_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_4_pilo_1_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_4_pilo_2_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_4_pilo_3_spn")
        Attack(h, M.user)
    end
    if not M.znAttacked[4] and GetDistance(M.user, "zn_5_trig") < 900.0 then
        M.znAttacked[4] = true
        local h
        h = BuildObject("ssusera", 2, "zn_5_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_5_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_5_snip_3_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_5_snip_4_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_5_snip_5_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_5_snip_6_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_5_sold_1_spn")
        Attack(h, M.user)
        h = BuildObject("sssold", 2, "zn_5_sold_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_5_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_5_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_5_turr_3_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_5_pilo_1_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_5_pilo_2_spn")
        Attack(h, M.user)
        h = BuildObject("sspilo", 2, "zn_5_pilo_3_spn")
        Attack(h, M.user)
    end
    if not M.znAttacked[5] and GetDistance(M.user, "zn_6_trig") < 900.0 then
        M.znAttacked[5] = true
        local h
        h = BuildObject("ssusera", 2, "zn_6_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_6_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_6_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_6_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_6_turr_3_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_6_turr_4_spn")
        Attack(h, M.user)
    end
    if not M.znAttacked[6] and GetDistance(M.user, "zn_7_trig") < 900.0 then
        M.znAttacked[6] = true
        local h
        h = BuildObject("ssusera", 2, "zn_7_snip_1_spn")
        Attack(h, M.user)
        h = BuildObject("ssusera", 2, "zn_7_snip_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_7_turr_1_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_7_turr_2_spn")
        Attack(h, M.user)
        h = BuildObject("svturr", 2, "zn_7_turr_3_spn")
        Attack(h, M.user)
    end
    if M.sound5Time < GetTime() and M.burglarSequencePlayed then
        M.sound5Time = 999999.9
        AudioMessage("ch07005.wav")
    end
    if M.convoyTime < GetTime() then
        local spawn = { [0] = "north_spn", [1] = "east_spn" }
        local path = { [0] = "north_path", [1] = "east_path" }
        local h
        if M.convoyCount == M.relic then
            h = BuildObject("svapca", 2, spawn[M.direction])
            M.relicApc = h
        else
            if ((M.convoyCount == 2) or
				(M.convoyCount == 1 and M.relic == 2)) then
                local numMembers = 15
                h = BuildObject(specials[math.random(0, numMembers - 1)], 2, spawn[M.direction])
            else
                h = BuildObject("svapcb", 2, spawn[M.direction])
            end
        end
        -- Native //#ifndef _DEBUG and //#endif were commented out;
        -- special APC selection remains active in every build.
        Goto(h, path[M.direction])
        -- curPilot = 0 clears the pilot CLASS, retaining convoy/escort AI.
        -- SetPilotClass(nil) restores defaults; empty string clears the class.
        SetPilotClass(h, "")
        local d = BuildObject("svfigh", 2, spawn[M.direction])
        SetPilotClass(d, "")
        Defend2(d, h, 1)
        M.convoyCount = M.convoyCount + 1
        if M.convoyCount == 3 then
            M.convoyTime = 999999.9
            M.convoySpawned = true
        else
            M.convoyTime = GetTime() + 8.0
        end
    end
    -- Native gate: /* convoySpawned && */ !triggered (keep ungated).
    if not M.triggered then
        local trig = { [0] = "north_trig", [1] = "east_trig" }
        local spawn = { [0] = { [0] = "sold_north_1_spn", [1] = "sold_north_2_spn" }, [1] = { [0] = "sold_east_1_spn", [1] = "sold_east_2_spn" } }
        local spawn2 = { [0] = { [0] = "pilo_north_1_spn", [1] = "pilo_north_2_spn" }, [1] = { [0] = "pilo_east_1_spn", [1] = "pilo_east_2_spn" } }
        if GetDistance(M.user, trig[M.direction]) < 350.0 then
            M.triggered = true
            local h = BuildObject("sssold", 2, spawn[M.direction][0])
            Attack(h, M.user, 1)
            h = BuildObject("sssold", 2, spawn[M.direction][1])
            Attack(h, M.user, 1)
            h = BuildObject("sspilo", 2, spawn2[M.direction][0])
            Attack(h, M.user, 1)
            h = BuildObject("sspilo", 2, spawn2[M.direction][1])
            Attack(h, M.user, 1)
            M.objective2Complete = true
            ClearObjectives()
            if M.objective1Complete then
                AddObjective("ch07001.otf", "green")
            else
                AddObjective("ch07001.otf", "white")
            end
            if M.burglarSequencePlayed then
                AddObjective(otf2[M.direction], "green")
            end
            AddObjective("ch07003.otf", "white")
        end
    end
    if not M.bombDestroyed then
        local expl = { [0] = "expl_north_spn", [1] = "expl_east_spn" }
        local spn = { [0] = { [0] = "north_sold_1_spn", [1] = "north_sold_2_spn", [2] = "north_sold_3_spn" }, [1] = { [0] = "east_sold_1_spn", [1] = "east_sold_2_spn", [2] = "east_sold_3_spn" } }
        if GetHealth(M.bombs[M.direction]) <= 0.0 then
            M.bombDestroyed = true
            -- Native MakeExplosion(location, odf) becomes Lua (odf, location).
            -- Redux uses the native D3D effect. The software-renderer branch
            -- is archived below; the trigger and troop spawns are unchanged.
            MakeExplosion("xtorxplb", expl[M.direction])
            local h
            h = BuildObject("sssold", 2, spn[M.direction][0])
            Attack(h, M.user)
            h = BuildObject("sssold", 2, spn[M.direction][1])
            Attack(h, M.user)
            h = BuildObject("sssold", 2, spn[M.direction][2])
            Attack(h, M.user)
        end
    end
    if M.relicApc ~= nil and GetHealth(M.relicApc) <= 0.0 and not M.objective3Complete then
        M.objective3Complete = true
        ClearObjectives()
        if M.objective1Complete then
            AddObjective("ch07001.otf", "green")
        else
            AddObjective("ch07001.otf", "white")
        end
        if M.burglarSequencePlayed then
            AddObjective(otf2[M.direction], "green")
        end
        AddObjective("ch07003.otf", "green")
        AddObjective("ch07004.otf", "white")
        AudioMessage("ch07008.wav")
        local h
        h = BuildObject("apcamr", 1, "nav_end")
        SetName(h, "Drop Zone")
    end
    if M.objective3Complete then
        if not M.backup1 and GetDistance(M.user, "zn_8_trig") < 800.0 then
            M.backup1 = true
            local h
            h = BuildObject("sssold", 2, "back_1_1_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_1_2_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_1_3_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_1_4_spn")
            Attack(h, M.user)
            -- Native cut reinforcements (inactive here; backup4 spawns them):
            -- h = BuildObject("sssold", 2, "back_1_5_spn")
            -- Attack(h, M.user)
            -- h = BuildObject("sssold", 2, "back_1_6_spn")
            -- Attack(h, M.user)
        end
        if not M.backup2 and GetDistance(M.user, "zn_9_trig") < 800.0 then
            M.backup2 = true
            local h
            h = BuildObject("sssold", 2, "back_2_1_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_2_2_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_2_3_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_2_4_spn")
            Attack(h, M.user)
            -- Native cut reinforcements (inactive here; backup4 spawns them):
            -- h = BuildObject("sssold", 2, "back_2_5_spn")
            -- Attack(h, M.user)
            -- h = BuildObject("sssold", 2, "back_2_6_spn")
            -- Attack(h, M.user)
        end
        if not M.backup3 and GetDistance(M.user, "nav_end") < 1000.0 then
            M.backup3 = true
            local h
            h = BuildObject("sspilo", 2, "pilo_end_1_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_2_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_3_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_4_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_5_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_6_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_7_spn")
            Attack(h, M.user)
            h = BuildObject("sspilo", 2, "pilo_end_8_spn")
            Attack(h, M.user)
        end
        if not M.backup4 and GetDistance(M.user, "zn_3_trig") < 800.0 then
            M.backup4 = true
            local h
            h = BuildObject("sssold", 2, "back_1_5_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_1_6_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_2_5_spn")
            Attack(h, M.user)
            h = BuildObject("sssold", 2, "back_2_6_spn")
            Attack(h, M.user)
        end
    end
    -- BUGFIX: only a live relic APC can reach warning/escape waypoints.
    -- Native code queries the destroyed handle after awarding objective 3;
    -- invalid-handle distances can falsely lose the mission. Live convoy
    -- timing and routes are unchanged; destruction still enables extraction.
    if IsAlive(M.relicApc) and not M.lost and not M.won then
        local spot1 = { [0] = "north_wav", [1] = "east_wav" }
        local spot2 = { [0] = "north_fail", [1] = "east_fail" }
        if GetDistance(M.relicApc, spot1[M.direction]) < 50.0 and
			not M.sound6Played then
            M.sound6Played = true
            AudioMessage("ch07006.wav")
        end
        if GetDistance(M.relicApc, spot2[M.direction]) < 50.0 then
            M.lost = true
            M.sound7 = AudioMessage("ch07007.wav")
        end
    end
    if M.sound7 ~= nil and IsAudioMessageDone(M.sound7) then
        -- BUGFIX: consume the completed loss message once. Native code
        -- reschedules GetTime()+1 every frame, potentially postponing defeat
        -- forever. Keep the same audio gate, one-second delay, and result.
        M.sound7 = nil
        FailMission(GetTime() + 1.0, "ch07lose.des")
    end
    if M.objective3Complete and GetDistance(M.user, "nav_end") < 170.0 and
		not M.snipersSpawned then
        M.snipersSpawned = true
        local h = BuildObject("ssusera", 2, "snip_end_1_spn")
        M.endGuy[0] = h
        Attack(h, M.user, 1)
        h = BuildObject("ssusera", 2, "snip_end_2_spn")
        M.endGuy[1] = h
        Attack(h, M.user, 1)
        h = BuildObject("ssusera", 2, "snip_end_3_spn")
        M.endGuy[2] = h
        Attack(h, M.user, 1)
        h = BuildObject("sssold", 2, "sold_end_1_spn")
        M.endGuy[3] = h
        Attack(h, M.user, 1)
        h = BuildObject("sssold", 2, "sold_end_2_spn")
        M.endGuy[4] = h
        Attack(h, M.user, 1)
        h = BuildObject("sssold", 2, "sold_end_3_spn")
        M.endGuy[5] = h
        Attack(h, M.user, 1)
    end
    if M.objective3Complete and GetDistance(M.user, "nav_end") < 140.0 and
		not M.rescue then
        M.rescue = true
        -- Keep the native fourth path argument (200) verbatim. Both native
        -- and stock Lua expose an integer path-point parameter; do not
        -- reinterpret it as altitude. Validate the supplied mission paths.
        local h
        h = BuildObject("cspilo", 1, "rescue_1_spn", 200)
        h = BuildObject("cspilo", 1, "rescue_2_spn", 200)
        h = BuildObject("cspilo", 1, "rescue_3_spn", 200)
        h = BuildObject("cspilo", 1, "rescue_4_spn", 200)
        h = BuildObject("cspilo", 1, "rescue_5_spn", 200)
    end
    if M.objective3Complete and M.snipersSpawned and GetDistance(M.user, "nav_end") < 50.0 and not M.won and not M.lost then
        M.won = true
        for i = 0, 5 do
            if IsAlive(M.endGuy[i]) then
                M.won = false
                break
            end
        end
        if M.won then
            M.winSound = AudioMessage("ch07009.wav")
            ClearObjectives()
            if M.objective1Complete then
                AddObjective("ch07001.otf", "green")
            else
                AddObjective("ch07001.otf", "white")
            end
            if M.burglarSequencePlayed then
                AddObjective(otf2[M.direction], "green")
            end
            AddObjective("ch07003.otf", "green")
            AddObjective("ch07004.otf", "green")
        end
    end
    if M.winSound ~= nil and IsAudioMessageDone(M.winSound) then
        M.winSound = nil
        SucceedMission(GetTime() + 1.0, "ch07win.des")
    end
    if M.ammo1 ~= nil and GetDistance(M.user, M.ammo1) < 5.0 then
        if Refill(M.user, false) then
            ColorFade(1.0, 5.0, 0, 255, 0)
            StartSound("repair.wav")
            RemoveObject(M.ammo1)
            M.ammo1 = nil
        end
    end
    if M.ammo2 ~= nil and GetDistance(M.user, M.ammo2) < 5.0 then
        if Refill(M.user, false) then
            ColorFade(1.0, 5.0, 0, 255, 0)
            StartSound("repair.wav")
            RemoveObject(M.ammo2)
            M.ammo2 = nil
        end
    end
    if M.repair1 ~= nil and GetDistance(M.user, M.repair1) < 5.0 then
        if Refill(M.user, true) then
            ColorFade(1.0, 5.0, 0, 255, 0)
            StartSound("repair.wav")
            RemoveObject(M.repair1)
            M.repair1 = nil
        end
    end
    if M.repair2 ~= nil and GetDistance(M.user, M.repair2) < 5.0 then
        if Refill(M.user, true) then
            ColorFade(1.0, 5.0, 0, 255, 0)
            StartSound("repair.wav")
            RemoveObject(M.repair2)
            M.repair2 = nil
        end
    end
end

function Save()
    return M
end

function Load(state)
    M = state
end

--[=[
Native comment / cut-content archive, in source order.
See the adjacent complete C++ file for declaration and line context.
Native line 13:
// Toni
Native line 14:
// Richard
Native line 15:
// Mick
Native line 16:
// Shane
Native line 17:
// Matt
Native line 18:
// Kochun
Native line 19:
// Tom
Native line 20:
// Stephen
Native line 21:
// Dan
Native line 22:
// Joel
Native line 23:
// Crista
Native line 24:
// David
Native line 25:
// Support
Native line 26:
// Robert
Native line 27:
// Buffy the Vampire Slayer
Native line 30:
/*
	Chinese07Mission
*/
Native line 54:
// bools
Native line 58:
// record whether the init code has been done
Native line 61:
// objectives
Native line 66:
// cameras
Native line 69:
// burgler
Native line 74:
// north or east?
Native line 79:
// zn attacks
Native line 82:
// convoy
Native line 85:
// bomb destroyed?
Native line 88:
// got in fighter?
Native line 92:
// snipers spawned
Native line 95:
// sounds played?
Native line 98:
// been told to attack player?
Native line 101:
// misc. triggers
Native line 104:
// backups
Native line 107:
// rescue units
Native line 110:
// player is in a hauler?
Native line 113:
// won or lost?
Native line 121:
// floats
Native line 138:
// handles
Native line 142:
// the user
Native line 146:
// units
Native line 155:
// ammo stuff
Native line 158:
// navs
Native line 161:
// place holder
Native line 167:
// integers
Native line 171:
// 0 = north
Native line 172:
// 1 = east
Native line 173:
// apc # with relic
Native line 174:
// number of convoy units spawned
Native line 176:
// sounds
Native line 204:
// init bools
Native line 210:
// init floats
Native line 216:
// init handles
Native line 222:
// init ints
Native line 234:
// bools
Native line 239:
// floats
Native line 244:
// Handles
Native line 249:
// ints
Native line 281:
// bools
Native line 286:
// floats
Native line 291:
// Handles
Native line 296:
// ints
Native line 348:
// cameras
Native line 360:
// units
Native line 387:
// navs
Native line 390:
// sounds
Native line 396:
// times
Native line 406:
// ints
Native line 416:
#if 0
	if (GetHealth(recycler) > 0.0f)
		h[numH++] = recycler;
	if (GetHealth(factory) > 0.0f)
		h[numH++] = factory;
	if (GetHealth(armoury) > 0.0f)
		h[numH++] = armoury;
	if (GetHealth(silo1) > 0.0f)
		h[numH++] = silo1;
	if (GetHealth(silo2) > 0.0f)
		h[numH++] = silo2;
#endif
Native line 438:
//assigns the player a handle every frame
Native line 445:
// don't do this part after the first shot
Native line 451:
#if 0
		// for debugging
		SetPerceivedTeam(user, 0);
		doNorthSequence = TRUE;
		cameraComplete[0] = TRUE;
		SetObjectiveOn(bombs[direction]);
#endif
Native line 488:
// if the fighters are close enough
Native line 621:
// sick 'em
Native line 630:
//if (objective1Complete)
Native line 852:
// spawn the convoy
Native line 864:
//#ifndef _DEBUG
Native line 872:
//#endif
Native line 898:
/* convoySpawned && */
Native line 937:
//_DEBUGMSG1("bomb was destroyed, %s should go boom now",
Native line 938:
//	expl[direction]);
Native line 989:
//h = BuildObject("sssold", 2, "back_1_5_spn");
Native line 990:
//Attack(h, user);
Native line 991:
//h = BuildObject("sssold", 2, "back_1_6_spn");
Native line 992:
//Attack(h, user);
Native line 1006:
//h = BuildObject("sssold", 2, "back_2_5_spn");
Native line 1007:
//Attack(h, user);
Native line 1008:
//h = BuildObject("sssold", 2, "back_2_6_spn");
Native line 1009:
//Attack(h, user);
Native line 1111:
// make sure all the snipers are dead
Native line 1144:
// check distances to ammo stuff
]=]
