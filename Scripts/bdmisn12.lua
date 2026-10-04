-- BlackDog12Mission.cpp: stock BZR 2.1+ / Lua 5.1 port.
-- Source blob: 584450878d2ed983c75195f10d8ccaeb6abcaedc.
-- Complete source, all comments and native serialization scaffolding:
-- References/BlackDog12Source/BlackDog12Mission.cpp.
-- No project helper / EXU / OpenShim dependency. Attach to the original bd12 map.
-- Zero-based arrays, strict timers, command priorities and Execute order kept.

local NEVER = 999999.9
-- low health warnings (source: shield warnings; also used for power units)
local warnings = {[0] = "bd12005.wav", "bd12006.wav", "bd12007.wav", "bd12008.wav"}
local desporSpawnSpots = {[0] = "despor_1", "despor_2", "despor_3", "despor_4"}

local function NewState()
    local s = {
        -- record whether the init code has been done
        startDone = false,
        -- objectives complete?
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused in source
        -- cameras
        cameraReady = {[0] = false, false},
        cameraComplete = {[0] = false, false}, -- second camera unused
        -- sounds
        camera1SoundPlayed = false, portalDeadSoundPlayed = false,
        -- delays initialized
        delaysInitialized = false,
        -- health low warnings? / despor units
        healthLow = {}, desporSpawned = {},
        -- have we lost?
        lost = false, won = false,
        delays = {}, camera1SoundDelay = NEVER, scrapDelay = NEVER,
        portalOnTime = NEVER, portalOffTime = NEVER,
        shields = {}, power = {}, goal = {},
        -- Native null handles/audio IDs are nil: user, recycler, portal,
        -- winSound, introSound, portalDeadSound.
    }
    for i = 0, 7 do s.healthLow[i] = false end
    for i = 0, 3 do s.desporSpawned[i] = false end
    for i = 0, 9 do s.delays[i] = NEVER end
    return s
end
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Health(h)
    -- PORT FIX: deleted/missing objects must count as zero health without
    -- passing nil/stale handles to Lua API calls. This retains native death
    -- checks, warnings and victory/failure triggers for destroyed objects.
    if not Valid(h) then return 0 end
    return GetHealth(h)
end
local function CloakUnit(h)
    -- PORT FIX: failed builds cannot receive Lua commands. Successful builds
    -- keep the exact source cloak calls, targets and priority-1 commands.
    if Valid(h) then SetCloaked(h) end
end
local function AttackUnit(h, target, priority)
    if Valid(h) and Valid(target) then Attack(h, target, priority) end
end
local function DefendUnit(h, target, priority)
    if Valid(h) and Valid(target) then Defend2(h, target, priority) end
end
local function GotoUnit(h, path, priority)
    if Valid(h) then Goto(h, path, priority) end
end
local function BuildAtPortal(odf, team, portal)
    if Valid(portal) then return BuildObjectAtPortal(odf, team, portal) end
end
local function ActivateOutwardPortal()
    if Valid(M.portal) then
        -- Native activatePortal(portal, false): outward activation.
        PortalOut(M.portal)
        ActivatePortal(M.portal)
    end
end
local function ClosePortal()
    if Valid(M.portal) then DeactivatePortal(M.portal) end
end
local function AudioDone(message)
    -- PORT FIX: AudioMessage may return nil if playback fails. Treat that as
    -- completed to avoid an unwinnable/stalled ending or an invalid API call.
    -- Successful audio still gates the same +1 victory / +2 failure delay.
    return message == nil or IsAudioMessageDone(message)
end

function Start()
    M = NewState()
    -- units (native Setup)
    M.portal = GetHandle("portal")
    for i = 0, 3 do
        M.shields[i] = GetHandle("shield_" .. (i + 1))
        M.power[i] = GetHandle("power_" .. (i + 1))
        M.goal[i] = GetHandle("goal_" .. (i + 1))
    end
end
function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)

    M.user = GetPlayerHandle() --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 50)
        SetScrap(2, 10)
        SetPilot(1, 10)

        -- don't do this part after the first shot
        M.startDone = true
    end

    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            M.cameraReady[0] = true
            CameraReady()
            M.camera1SoundDelay = GetTime() + 3.0
        end

        -- PORT FIX: finish a shot whose subject was deleted/missing via the
        -- same arrival branch; a valid portal keeps the original camera path.
        local arrived = not Valid(M.portal)
        if not arrived then arrived = CameraPath("camera_start", 300, 2000, M.portal) end

        if M.camera1SoundDelay < GetTime() then
            M.camera1SoundDelay = 999999.9
            M.camera1SoundPlayed = true
            M.introSound = AudioMessage("bd12001.wav")
        end

        if CameraCancelled() then
            arrived = true
            if M.introSound ~= nil then
                StopAudioMessage(M.introSound)
            end
        end

        if arrived then
            CameraFinish()
            M.cameraComplete[0] = true

            -- show objectives
            ClearObjectives()
            AddObjective("bd12001.otf", "white")
        end
    end

    -- objects spawned
    if not M.delaysInitialized then
        M.delaysInitialized = true

        M.delays[0] = GetTime() + 120.0 -- 2 minutes
        M.delays[1] = GetTime() + 240.0 -- 4 minutes
        M.delays[2] = GetTime() + 360.0 -- 6 minutes
        M.delays[3] = GetTime() + 480.0 -- 8 minutes
        -- SOURCE TIMING CONFLICT (preserved): 13*60 is 780 seconds despite
        -- "9 minutes" below. Escorts (546/552), portal close (554) and
        -- objective advance (555) occur before open (778)/recycler (780).
        -- Intent is ambiguous; retiming would change mission gameplay.
        M.delays[4] = GetTime() + 13 * 60.0 -- 9 minutes
        M.portalOnTime = M.delays[4] - 2.0
        M.delays[5] = GetTime() + 546.0 -- 9.1 minutes
        M.delays[6] = GetTime() + 552.0 -- 9.2 minutes
        M.portalOffTime = M.delays[6] + 2.0
        M.delays[7] = GetTime() + 555.0 -- 9.2 minutes + 3 seconds

        M.scrapDelay = 60.0
    end

    -- delay 1
    if M.delays[0] < GetTime() then
        M.delays[0] = 999999.9

        -- 3 fighters
        local a1 = BuildObject("cvfigh", 2, "attack_1")
        CloakUnit(a1)
        AttackUnit(a1, M.power[0], 1)
        local a2 = BuildObject("cvfigh", 2, "attack_1")
        CloakUnit(a2)
        AttackUnit(a2, M.power[0], 1)
        local a3 = BuildObject("cvfigh", 2, "attack_1")
        CloakUnit(a3)
        AttackUnit(a3, M.power[0], 1)

        -- 2 defenders
        local d1 = BuildObject("cvtnk", 2, "defend_1")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvtnk", 2, "defend_1")
        CloakUnit(d2)
        DefendUnit(d2, a2, 1)
    end

    -- delay 2
    if M.delays[1] < GetTime() then
        M.delays[1] = 999999.9

        -- 3 fighters
        local a1 = BuildObject("cvfigh", 2, "attack_2")
        CloakUnit(a1)
        AttackUnit(a1, M.power[1], 1)
        local a2 = BuildObject("cvfigh", 2, "attack_2")
        CloakUnit(a2)
        AttackUnit(a2, M.power[1], 1)
        local a3 = BuildObject("cvfigh", 2, "attack_2")
        CloakUnit(a3)
        AttackUnit(a3, M.power[1], 1)

        -- 1 heavy tank
        local a4 = BuildObject("cvhtnk", 2, "attack_2")
        CloakUnit(a4)
        AttackUnit(a4, M.power[1], 1)

        -- defenders
        local d1 = BuildObject("cvfigh", 2, "defend_2")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvfigh", 2, "defend_2")
        CloakUnit(d2)
        DefendUnit(d2, a2, 1)
        local d3 = BuildObject("cvfigh", 2, "defend_2")
        CloakUnit(d3)
        DefendUnit(d3, a3, 1)
        local d4 = BuildObject("cvhtnk", 2, "defend_2")
        CloakUnit(d4)
        DefendUnit(d4, a4, 1)
    end

    -- delay 3
    if M.delays[2] < GetTime() then
        M.delays[2] = 999999.9

        -- 2 bombers
        local a1 = BuildObject("cvhraz", 2, "attack_3")
        CloakUnit(a1)
        AttackUnit(a1, M.power[2], 1)
        local a2 = BuildObject("cvhraz", 2, "attack_3")
        CloakUnit(a2)
        AttackUnit(a2, M.power[2], 1)

        -- 2 fighters
        local a3 = BuildObject("cvfigh", 2, "attack_3")
        CloakUnit(a3)
        AttackUnit(a3, M.power[2], 1)
        local a4 = BuildObject("cvfigh", 2, "attack_3")
        CloakUnit(a4)
        AttackUnit(a4, M.power[2], 1)

        -- defenders
        local d1 = BuildObject("cvtnk", 2, "defend_3")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvtnk", 2, "defend_3")
        CloakUnit(d2)
        DefendUnit(d2, a2, 1)
        local d3 = BuildObject("cvfigh", 2, "defend_3")
        CloakUnit(d3)
        DefendUnit(d3, a3, 1)
        local d4 = BuildObject("cvfigh", 2, "defend_3")
        CloakUnit(d4)
        DefendUnit(d4, a4, 1)
    end

    -- delay 4
    if M.delays[3] < GetTime() then
        M.delays[3] = 999999.9

        -- attacker 1
        local a1 = BuildObject("cvwalk", 2, "attack_4")
        AttackUnit(a1, M.shields[0], 1)
        -- and it's defence
        local d1 = BuildObject("cvltnk", 2, "defend_4")
        CloakUnit(d1)
        DefendUnit(d1, a1, 1)
        local d2 = BuildObject("cvltnk", 2, "defend_4")
        CloakUnit(d2)
        DefendUnit(d2, a1, 1)

        -- attacker 2
        local a2 = BuildObject("cvwalk", 2, "attack_5")
        AttackUnit(a2, M.shields[1], 1)
        -- and it's defence
        local d3 = BuildObject("cvltnk", 2, "defend_5")
        CloakUnit(d3)
        DefendUnit(d3, a2, 1)
        local d4 = BuildObject("cvltnk", 2, "defend_5")
        CloakUnit(d4)
        DefendUnit(d4, a2, 1)

        -- attacker 3
        local a3 = BuildObject("cvwalk", 2, "attack_6")
        AttackUnit(a3, M.shields[2], 1)
        -- and it's defence
        local d5 = BuildObject("cvtnk", 2, "defend_6")
        CloakUnit(d5)
        DefendUnit(d5, a3, 1)
        local d6 = BuildObject("cvtnk", 2, "defend_6")
        CloakUnit(d6)
        DefendUnit(d6, a3, 1)

        -- attacker 4
        local a4 = BuildObject("cvwalk", 2, "attack_7")
        AttackUnit(a4, M.shields[3], 1)
        -- and it's defence
        local d7 = BuildObject("cvtnk", 2, "defend_7")
        CloakUnit(d7)
        DefendUnit(d7, a4, 1)
        local d8 = BuildObject("cvtnk", 2, "defend_7")
        CloakUnit(d8)
        DefendUnit(d8, a4, 1)

        -- attacker 5
        local a5 = BuildObject("cvwalk", 2, "attack_8")
        AttackUnit(a5, M.portal, 1)
        -- and it's defence
        local d9 = BuildObject("cvhtnk", 2, "defend_8")
        CloakUnit(d9)
        DefendUnit(d9, a5, 1)
        local d10 = BuildObject("cvhtnk", 2, "defend_8")
        CloakUnit(d10)
        DefendUnit(d10, a5, 1)
    end

    -- turn on/off the portal
    if M.portalOnTime < GetTime() then
        M.portalOnTime = 999999.9
        ActivateOutwardPortal()
    end

    if M.portalOffTime < GetTime() then
        M.portalOffTime = 999999.9
        ClosePortal()
    end

    -- delay 5
    if M.delays[4] < GetTime() then
        M.delays[4] = 999999.9

        M.recycler = BuildAtPortal("bvrecyd", 1, M.portal)
        GotoUnit(M.recycler, "follow", 1)
    end

    -- delay 6
    if M.delays[5] < GetTime() then
        M.delays[5] = 999999.9

        local h
        h = BuildAtPortal("bvtank", 1, M.portal)
        GotoUnit(h, "follow", 1)
        h = BuildAtPortal("bvtank", 1, M.portal)
        GotoUnit(h, "follow", 1)
    end

    -- delay 7
    if M.delays[6] < GetTime() then
        M.delays[6] = 999999.9

        local h = BuildAtPortal("bvfigh", 1, M.portal)
        GotoUnit(h, "follow", 1)
    end

    -- delay 8
    if M.delays[7] < GetTime() then
        M.delays[7] = 999999.9

        ClearObjectives()
        AddObjective("bd12001.otf", "green")
        AddObjective("bd12002.otf", "white")
        M.objective1Complete = true
    end

    -- check the goals
    if M.objective1Complete and not M.objective2Complete then
        M.objective2Complete = true
        for i = 0, 3 do
            if Health(M.goal[i]) > 0.0 then
                M.objective2Complete = false
                break
            end
        end

        if M.objective2Complete then
            -- start the sound
            M.winSound = AudioMessage("bd12003.wav")
        end
    end

    if M.objective2Complete and not M.won and not M.lost then
        if AudioDone(M.winSound) then
            M.won = true
            SucceedMission(GetTime() + 1.0, "bd12win.des")
        end
    end

    -- spawn scrap
    if M.scrapDelay < GetTime() then
        M.scrapDelay = GetTime() + 60.0

        BuildObject("npscr1", 0, "scrap_1")
        BuildObject("npscr1", 0, "scrap_1")
        BuildObject("npscr1", 0, "scrap_1")
        BuildObject("npscr1", 0, "scrap_2")
        BuildObject("npscr1", 0, "scrap_2")
        BuildObject("npscr1", 0, "scrap_2")
    end

    -- low health warnings?
    for i = 0, 3 do
        -- check the power units
        if not M.healthLow[i] and Health(M.power[i]) < 0.25 then
            M.healthLow[i] = true
            AudioMessage(warnings[i])
        end

        -- check the shield units
        if not M.healthLow[4+i] and Health(M.shields[i]) < 0.25 then
            M.healthLow[4+i] = true
            AudioMessage(warnings[i])
        end
    end

    -- shields or power dead?
    for i = 0, 3 do
        if not M.desporSpawned[i] then
            if Health(M.power[i]) <= 0.0 or Health(M.shields[i]) <= 0.0 then
                M.desporSpawned[i] = true
                local h
                h = BuildObject("cvltnk", 2, desporSpawnSpots[i])
                CloakUnit(h)
                AttackUnit(h, M.portal, 1)
                h = BuildObject("cvltnk", 2, desporSpawnSpots[i])
                CloakUnit(h)
                AttackUnit(h, M.portal, 1)
            end
        end
    end

    -- portal dead?
    if Health(M.portal) <= 0.0 and not M.portalDeadSoundPlayed then
        M.portalDeadSoundPlayed = true
        M.portalDeadSound = AudioMessage("bd12004.wav")
    end

    if M.portalDeadSoundPlayed and not M.lost and not M.won then
        if AudioDone(M.portalDeadSound) then
            M.lost = true
            FailMission(GetTime() + 2.0, "bd12lsea.des")
        end

    end

end

function Save()
    return M
end
function Load(state)
    -- LuaMission restores tables and remaps handles/messages; do not rerun
    -- Setup or reset timers, cameras, warnings, spawns or outcome latches.
    M = state
end
