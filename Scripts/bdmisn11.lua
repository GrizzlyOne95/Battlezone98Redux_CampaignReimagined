-- Faithful BlackDog11Mission port for stock BZR 2.1+ / Lua 5.1.
-- Source blob: 9378d51ee65985f7859fe7f82dd7ffbf185e72b4.
-- Complete original source, including all comments, TEST_EXPLOSION and native
-- serialization: References/BlackDog11Source/BlackDog11Mission.cpp.
-- Zero-based arrays retain native index arithmetic and the 71 enemy slots.
local NEVER = 999999.9
-- //#define TEST_EXPLOSION: disabled in the shipped native source.
local TEST_EXPLOSION = false
local unitBase, NUM_UNITS = 6, 71
local attacks = {
    [0] = 0,
    2,
    4,
    8,
    11,
    14,
    23,
}
local attackSpawns = {
    [0] = "attack_1",
    "attack_2",
    "attack_3",
    "attack_4",
    "attack_5",
    "attack_6",
}
local attackUnits = {
    [0] = "cvhraz", --  attack 1
    "cvhraz",
    "cvhtnk", --  attack 2
    "cvhraz",
    "cvhraz", --  atttack 3
    "cvhraz",
    "cvhtnk",
    "cvhtnk",
    "cvhtnk", --  attack 4
    "cvhtnk",
    "cvhtnk",
    "cvhraz", --  attack 5
    "cvhraz",
    "cvhraz",
    "cvhtnk", --  attack 6
    "cvhtnk",
    "cvhtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh",
    "cvhraz",
    "cvhraz",
    "cvhraz",
}
local defends = {
    [0] = 0,
    4,
    9,
    14,
    21,
    30,
    42,
}
local defendSpawns = {
    [0] = "defend_1",
    "defend_2",
    "defend_3",
    "defend_4",
    "defend_5",
    "defend_6",
}
local defendUnits = {
    [0] = "cvtnk", --  defend 1
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh", --  defend 2
    "cvfigh",
    "cvfigh",
    "cvhtnk",
    "cvltnk",
    "cvtnk", --  defend 3
    "cvtnk",
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh", --  defend 4
    "cvfigh",
    "cvfigh",
    "cvfigh",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvhtnk", --  defend 5
    "cvhtnk",
    "cvhtnk",
    "cvhtnk",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvhtnk", --  defend 6
    "cvhtnk",
    "cvhtnk",
    "cvhtnk",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh",
    "cvfigh",
}
--const int numUnits = unitBase + attacks[7] + defends[7];
local function NewState()
    return {
        startDone = false, objective1Complete = false,
        objective2Complete = false, objective3Complete = false,
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false},
        apcWantsToTransferPilot = false, pilotTransferring = false,
        toldToGo = false, attacksSent = false, navDistanceOk = false,
        retreatSpawned = false, sound4Played = false, sound5Played = false,
        sound6Played = false, cockpitTimerActive = false,
        explodePortal = false, lost = false, won = false,
        recyclerGoTime = NEVER, drive1Time = NEVER,
        attackTimes = {[0] = NEVER, NEVER, NEVER, NEVER, NEVER, NEVER},
        goToPortalTime = NEVER, cameraDestructTime = NEVER,
        explodeTime = NEVER, explodeDelay = NEVER,
        explode1Time = NEVER, explode2Time = NEVER,
        explode3Time = NEVER, explode4Time = NEVER,
        aerial1Time = NEVER, aerial2Time = NEVER, portalTime = NEVER,
        sound8Time = NEVER, sound9Time = NEVER, sound12Time = NEVER,
        portalStage = 0, enemy = {}, retreats = {},
        -- Other handles/audio IDs begin nil (native NULL).
        -- Native unused fields retained: objective3Complete, camera slot 1,
        -- apcWantsToTransferPilot, retreatSpawned, retreats, navEnd,
        -- portalTime and portalStage. Do not invent retreat/portal stages.
    }
end
local M = NewState()
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Health(h)
    -- PORT FIX: deleted/missing handles count as zero health without invoking
    -- a Lua overload on nil. Existing health thresholds/loss ordering are intact.
    return Valid(h) and GetHealth(h) or 0
end
local function StopSound(id)
    if id ~= nil and id ~= 0 then StopAudioMessage(id) end
end
local function AtPathEnd(h, path)
    -- STOCK ADAPTATION: native isAtEndOfPath is not exposed to stock Lua.
    -- Use the last zero-based path point with a 25 m arrival tolerance. Native
    -- helper internals are unavailable here; this approximation changes only
    -- when the escort objective turns green, never the independent wave trigger.
    local count = GetPathPointCount(path)
    return Valid(h) and count > 0 and GetDistance(h, path, count - 1) < 25
end
local function SpawnAerial()
    for i = 0, 7 do
        -- SOURCE QUIRK PRESERVED: both aerial waves use "aerial_1", point
        -- 400. Stock/native path overloads use a point index; do not invent an
        -- altitude or a second path. Validate this unusual index in the map.
        local h = BuildObject("cssold", 2, "aerial_1", 400)
        if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
    end
end
function Start()
    M = NewState()
    M.recycler = GetHandle("recycler")
    M.portal = GetHandle("portal")
    M.apc = GetHandle("apc")
    for i = 0, 5 do M.enemy[i] = GetHandle("enemy_" .. (i + 1)) end
    assert(NUM_UNITS == unitBase + attacks[6] + defends[6])
end
function AddObject(h)
    -- Native AddObject(Handle) is empty.
end
function Update(dt)

    M.user = GetPlayerHandle()  --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 100)
        SetPilot(1, 10)

        -- setup the initial objectives
        ClearObjectives()
        AddObjective("bd11001.otf", "white")

        -- don't do this part after the first shot
        M.startDone = true

        M.navRecycler = BuildObject("apcamr", 1, "recy_nav")
        if Valid(M.navRecycler) then SetObjectiveName(M.navRecycler, "Recycler") end

        --#define TEST_EXPLOSION
        if TEST_EXPLOSION then
            SetPerceivedTeam(M.user, 2)
            M.goToPortalTime = GetTime()
        end
    end
    if not TEST_EXPLOSION then
        -- is the recycler dead?
        if not M.lost and Health(M.recycler) <= 0.0 and not M.won then
            M.lost = true
            if M.navDistanceOk then
                FailMission(GetTime() + 1.0, "bd11lseb.des")
            else
                FailMission(GetTime() + 1.0, "bd11lsed.des")
            end
        end

        -- has the apc made it to the recycler yet?
        if not M.objective1Complete and Health(M.apc) <= 0.0 and not M.won and not M.lost then
            M.lost = true
            FailMission(GetTime() + 1.0, "bd11lsea.des")
        end

        if not M.cameraComplete[0] then
            if not M.cameraReady[0] then
                M.cameraReady[0] = true
                CameraReady()

                M.introSound = AudioMessage("bd11001.wav")
            end

            local arrived = true
            if Valid(M.recycler) then arrived = CameraPath("camera_start", 1000, 1600, M.recycler) end

            if CameraCancelled() then
                arrived = true
                StopSound(M.introSound)
            end
            if arrived then
                CameraFinish()
                M.cameraComplete[0] = true
            end
        end

        -- is the apc close enough to the "pilot transfer point" ?
        if not M.objective1Complete and not M.pilotTransferring and Valid(M.apc) and Valid(M.recycler) and not M.lost then
            local distance = GetDistance(M.apc, M.recycler)
            -- PORT FIX: no nearest enemy means the transfer area is clear.
            -- Keep the native 50 m approach / 200 m enemy-distance gates for live units.
            local nearestEnemy = GetNearestEnemy(M.apc)
            if distance < 50.0 and (not Valid(nearestEnemy) or GetDistance(M.apc, nearestEnemy) > 200.0) then
                -- stop the apc
                Stop(M.apc, 1)

                -- spawn the pilot
                M.pilotTransferring = true
                M.pilot = BuildObject("aspilo", 1, M.apc)
                if Valid(M.pilot) then Retreat(M.pilot, M.recycler, 1) end
            end
        end

        if M.pilotTransferring then
            if Valid(M.pilot) and Health(M.pilot) > 0 then GiveMaxHealth(M.pilot) end
            -- BUG FIX: never heal a dead/missing transfer pilot before checking defeat.
            -- Live pilots retain native per-frame full health; destroyed ones now reach
            -- the existing bd11lsec loss instead of an invalid-handle call or resurrection.
            -- has the pilot been killed?
            if not M.lost and Health(M.pilot) <= 0.0 and not M.won then
                M.lost = true
                FailMission(GetTime() + 1.0, "bd11lsec.des")
            end

            if Valid(M.pilot) and Valid(M.recycler) and not M.lost and GetDistance(M.pilot, M.recycler) < 15.0 then
                M.pilotTransferring = false
                M.objective1Complete = true
                RemoveObject(M.pilot)
                M.pilot = nil
                -- STOCK ADAPTATION: native curPilot assignment / AiProcess::Attach is
                -- represented by SetPilotClass. Goto below supplies the scripted AI command;
                -- no extra pilot, boarding delay, health reset or recycler replacement occurs.
                SetPilotClass(M.recycler, "bspilo")

                M.recyclerGoTime = GetTime() + 2.0
                -- play sound
                AudioMessage("bd11002.wav")
            end
        end

        if M.recyclerGoTime < GetTime() then
            M.toldToGo = true
            if Valid(M.recycler) then SetTeamNum(M.recycler, 1) end
            M.recyclerGoTime = NEVER
            -- get the recycler moving to the geiser
            if Valid(M.recycler) then Goto(M.recycler, "recycler_path", 1) end

            -- setup drive 1 attack
            M.drive1Time = GetTime() + 20.0
        end

        if M.toldToGo and AtPathEnd(M.recycler, "recycler_path") then
            M.toldToGo = false
            ClearObjectives()
            AddObjective("bd11001.otf", "green")
            AddObjective("bd11002.otf", "white")
            --Goto(recycler, GetHandle("geyser_1"));
        end

        if not M.attacksSent and Valid(M.recycler) and GetDistance(M.recycler, "wave_trigger") < 50.0 then
            -- start attacks
            M.attacksSent = true
            M.attackTimes[0] = GetTime() + 2 * 60.0
            M.attackTimes[1] = GetTime() + 5 * 60.0
            M.attackTimes[2] = GetTime() + 9 * 60.0
            M.attackTimes[3] = GetTime() + 14 * 60.0
            M.attackTimes[4] = GetTime() + 18 * 60.0
            M.attackTimes[5] = GetTime() + 21 * 60.0

            M.goToPortalTime = GetTime() + 26 * 60.0
            M.aerial1Time = GetTime() + 8 * 60.0
            -- BUG FIX: source assigns aerial1Time twice, losing the 8-minute wave
            -- and never arming aerial2Time. Restore the two explicitly coded waves;
            -- the six main waves and 26-minute portal phase retain their schedule.
            M.aerial2Time = GetTime() + 13 * 60.0

            local h
            h = BuildObject("cvltnk", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvltnk", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvltnk", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvhraz", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvhraz", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
        end

        if M.objective1Complete then
            local h = Health(M.recycler)
            -- check the recycler's health
            if h > 0.5 then
                -- do nothing
            elseif not M.sound4Played and h > 0.25 then
                M.sound4Played = true
                M.sound4 = AudioMessage("bd11004.wav")
            elseif not M.sound5Played and h > 0.15 then
                -- stop any previous sounds
                StopSound(M.sound4)

                M.sound5Played = true
                M.sound5 = AudioMessage("bd11005.wav")
            elseif not M.sound6Played and h > 0.0 then
                -- stop any previous sounds
                StopSound(M.sound4)
                StopSound(M.sound5)

                M.sound6Played = true
                M.sound6 = AudioMessage("bd11006.wav")
            end
        end

        if M.drive1Time < GetTime() then
            M.drive1Time = NEVER

            local h = BuildObject("cvwalk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
            h = BuildObject("cvwalk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
            h = BuildObject("cvltnk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
            h = BuildObject("cvltnk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
        end

        if M.aerial1Time < GetTime() then
            M.aerial1Time = NEVER

            SpawnAerial()
        end

        if M.aerial2Time < GetTime() then
            M.aerial2Time = NEVER

            SpawnAerial()
        end

        for i = 0, 5 do
            if M.attacksSent and M.attackTimes[i] < GetTime() then

                -- so this attack doesn't happen again
                M.attackTimes[i] = NEVER

                -- build the attackers
                local numAttackers = attacks[i+1] - attacks[i]
                for j = 0, numAttackers - 1 do
                    -- build the enemy
                    local unum = unitBase + attacks[i] + defends[i] + j
                    assert(M.enemy[unum] == nil)
                    M.enemy[unum] = BuildObject(attackUnits[attacks[i] + j], 2, attackSpawns[i])
                    if Valid(M.enemy[unum]) then SetCloaked(M.enemy[unum]) end
                    if Valid(M.enemy[unum]) and Valid(M.recycler) then Attack(M.enemy[unum], M.recycler) end
                end

                -- build the defenders
                local numDefenders = defends[i+1] - defends[i]
                for j = 0, numDefenders - 1 do
                    local h = nil
                    local unum = unitBase + attacks[i+1] + defends[i] + j
                    assert(M.enemy[unum] == nil)
                    h = BuildObject(defendUnits[defends[i] + j], 2, defendSpawns[i])
                    M.enemy[unum] = h
                    if Valid(M.enemy[unum]) then SetCloaked(M.enemy[unum]) end
                    local anum = unitBase + attacks[i] + defends[i] + (j % numAttackers)
                    if Valid(h) and Valid(M.enemy[anum]) then Defend2(h, M.enemy[anum], 1) end
                end
            end
        end
    end
    if M.goToPortalTime < GetTime() then
        M.goToPortalTime = NEVER
        ClearObjectives()
        AddObjective("bd11002.otf", "green")
        M.objective2Complete = true

        -- spawn the nav
        --navEnd = BuildObject("apcamr", 1, "nav_end");
        AudioMessage("bd11007.wav")
        M.sound8Time = GetTime() + 3.0
    end

    if M.sound8Time < GetTime() then
        M.sound8Time = NEVER
        M.sound8 = AudioMessage("bd11008.wav")
    end

    if M.sound8 ~= nil and IsAudioMessageDone(M.sound8) then
        M.sound8 = nil
        M.sound9Time = GetTime() + 5.0
    end

    if M.sound9Time < GetTime() then
        M.sound9Time = NEVER
        AudioMessage("bd11009.wav")
        M.sound10 = AudioMessage("bd11010.wav")
    end

    if M.sound10 ~= nil and IsAudioMessageDone(M.sound10) then
        M.sound10 = nil
        M.sound12Time = GetTime() + 5.0
    end

    if M.sound12Time < GetTime() then
        M.sound12Time = NEVER
        M.sound12 = AudioMessage("bd11012.wav")
    end

    if M.sound12 ~= nil and IsAudioMessageDone(M.sound12) then
        M.sound12 = nil

        ClearObjectives()
        AddObjective("bd11003.otf", "white")

        if Valid(M.portal) then SetObjectiveOn(M.portal) end
        -- start the timer
        StartCockpitTimer(90, 30, 10)
        M.cockpitTimerActive = true
    end

    if M.cockpitTimerActive and GetCockpitTimer() <= 0.0 then
        M.cockpitTimerActive = false
        HideCockpitTimer()
        M.explode1Time = GetTime()
        M.explode2Time = GetTime() + 2.0
        M.explode3Time = GetTime() + 4.0
        M.explode4Time = GetTime() + 6.0
        M.explodeTime = GetTime() + 18.0
        M.cameraDestructTime = M.explodeTime - 1.0
        M.navDistanceOk = true
    end

    -- 4 explosions
    if M.explode1Time < GetTime() then
        M.explode1Time = NEVER
        MakeExplosion("xpltrsk", "dw_1")
    end

    if M.explode2Time < GetTime() then
        M.explode2Time = NEVER
        MakeExplosion("xpltrsk", "dw_2")
    end

    if M.explode3Time < GetTime() then
        M.explode3Time = NEVER
        MakeExplosion("xpltrsk", "dw_3")
    end

    if M.explode4Time < GetTime() then
        M.explode4Time = NEVER
        MakeExplosion("xpltrsk", "dw_4")
    end

    if M.cameraDestructTime < GetTime() then
        M.cameraDestructTime = NEVER
        CameraReady()
        if Valid(M.portal) then CameraPath("camera_destruct", 1000, 0, M.portal) end
    end

    if M.explodeTime < GetTime() then
        M.explodeTime = NEVER
        M.explodeDelay = GetTime() + 3.0
        ColorFade(1.0, 0.5, 255, 255, 255)
        M.explodePortal = true
        -- STOCK ADAPTATION: Lua has no native useD3D renderer bitfield.
        -- Redux uses the hardware-renderer effect; software fallback is archived:
        -- if (useD3D & 4) MakeExplosion(portal, "xpltrso");
        -- else MakeExplosion(portal, "xpltrsp");
        if Valid(M.portal) then MakeExplosion("xpltrso", M.portal) end
    end

    if M.explodeDelay < GetTime() then
        -- finish the camera
        CameraFinish()

        M.explodeDelay = NEVER

        M.winMessage = AudioMessage("bd11011.wav")

        ClearObjectives()
        AddObjective("bd11003.otf", "green")
    end

    if M.winMessage ~= nil and not M.won and not M.lost then
        if IsAudioMessageDone(M.winMessage) then
            M.won = true
            SucceedMission(GetTime() + 3.0, "bd11win.des")
        end
    end

    if Health(M.portal) <= 0.0 and not M.explodePortal and not M.won and not M.lost then
        M.lost = true
        FailMission(GetTime() + 1.0, "bd11lsee.des")
    end
end

function Save()
    return M
end
function Load(state)
    -- Engine restores saved handles/audio; never rerun Setup or reset timers.
    M = state
end
