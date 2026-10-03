-- BlackDog07Mission.cpp faithfully ported to stock BZR / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog07Mission.cpp
-- Source blob: 35e2f6e94e88cd33a2c00e544da5600f46b7cc53.
-- Complete C++ (including every comment and native Load/Save/PostLoad) is
-- retained in References/BlackDog07Source/BlackDog07Mission.cpp.
-- The source contains no disabled gameplay code. No external helpers required.

local NEVER = 999999.9

local function NewState()
    return {
        -- record whether the init code has been done
        startDone = false,
        -- objectives (2 and 3 are unused in the source, but retained)
        objective1Complete = false,
        objective2Complete = false,
        objective3Complete = false,
        -- waves spawned?
        wavesSpawned = true,
        -- have we lost?
        lost = false, won = false,
        sound1Time = NEVER, sound2Time = NEVER, sound3Time = NEVER,
        waveDelay = {[0] = NEVER, [1] = NEVER},
        annoyTime = NEVER,
        -- *** User stuff: user starts nil.
        -- *** Units: retain the source's zero-based arrays and fixed bounds.
        mustDestroy = {}, mustSave = {}, waveUnits1 = {}, waveUnits2 = {},
        -- *** Sounds: sound1, sound2, sound3 start nil (native NULL).
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function Healthy(h)
    -- PORT FIX: a missing/deleted handle cannot be passed safely through Lua
    -- health overloads. Treat it as zero health, as the native failed lookup
    -- does. Existing objects still use GetHealth > 0, not pilot-based IsAlive;
    -- the original "at least one protected structure survives" rule is intact.
    return Valid(h) and GetHealth(h) > 0.0
end

local function ShowObjectives()
    -- PORT FIX: sound3 can finish after the waves/base have already been
    -- destroyed, and wave completion can occur after victory was scheduled.
    -- Native unconditional refreshes then restore an obsolete white objective.
    -- Render the current earned phase instead. This only fixes the display:
    -- no audio, timers, AI commands, resources, or win/loss gates are changed.
    ClearObjectives()
    if M.won then
        AddObjective("bd07002.otf", "green")
    elseif M.objective1Complete then
        AddObjective("bd07002.otf", "white")
    else
        AddObjective("bd07001.otf", "white")
    end
end

function Start()
    -- Native Load initializes state, then Setup resolves the map objects.
    M = NewState()

    -- units
    M.mustSave[0] = GetHandle("recycler")
    M.mustSave[1] = GetHandle("myfactory")
    M.mustSave[2] = GetHandle("my_hq")
    M.mustDestroy[0] = GetHandle("chin_recycler")
    M.mustDestroy[1] = GetHandle("chin_factory")
    M.mustDestroy[2] = GetHandle("chin_solar1")
    M.mustDestroy[3] = GetHandle("chin_solar2")
    M.mustDestroy[4] = GetHandle("chin_solar3")
    M.mustDestroy[5] = GetHandle("chin_tower1")
    M.mustDestroy[6] = GetHandle("chin_tower2")
    M.mustDestroy[7] = GetHandle("chin_tower3")
    M.mustDestroy[8] = GetHandle("chin_supply")
    M.mustDestroy[9] = GetHandle("chin_hq")
    M.mustDestroy[10] = GetHandle("chin_hangar")
    M.waveUnits1[0] = GetHandle("chin_scout1")
    M.waveUnits1[1] = GetHandle("chin_scout2")
    M.waveUnits1[2] = GetHandle("chin_scout3")
    M.waveUnits2[0] = GetHandle("chin_scout4")
    M.waveUnits2[1] = GetHandle("chin_scout5")
    M.waveUnits2[2] = GetHandle("chin_scout6")
    M.waveUnits2[3] = GetHandle("chin_ltnk1")
    M.waveUnits2[4] = GetHandle("chin_ltnk2")
    M.waveUnits2[5] = GetHandle("chin_tank1")
    M.waveUnits2[6] = GetHandle("chin_bomber1")
    M.waveUnits2[7] = GetHandle("chin_bomber2")

    -- label the nav beacons; stock SetObjectiveName is native SetName's alias.
    local h = GetHandle("nav_mybase")
    if Valid(h) then SetObjectiveName(h, "Black Dog Base") end
    h = GetHandle("nav_chinbase")
    if Valid(h) then SetObjectiveName(h, "Chinese Base") end
    -- PORT SAFETY: absent beacons simply skip naming; mission flow is unchanged.

    -- SOURCE QUIRK PRESERVED: Setup sets wavesSpawned = TRUE, and Execute
    -- never arms waveDelay[0]. Keep the preplaced waves and dormant path-timer
    -- branches; inventing an initial delay would alter the original attack flow.
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()

    if not M.startDone then
        SetAIP("bdmisn07.aip")
        SetScrap(1, 8)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        M.sound1Time = now + 5.0
    end

    -- sound1
    if M.sound1Time < now then
        M.sound1Time = NEVER
        M.sound1 = AudioMessage("bd07001.wav")
    end
    if M.sound1 ~= nil and IsAudioMessageDone(M.sound1) then
        M.sound1 = nil
        M.sound2Time = now + 1.0
    end

    -- sound 2
    if M.sound2Time < now then
        M.sound2Time = NEVER
        M.sound2 = AudioMessage("bd07002.wav")
    end
    if M.sound2 ~= nil and IsAudioMessageDone(M.sound2) then
        M.sound2 = nil
        M.sound3Time = now + 2.0
    end

    -- sound 3
    if M.sound3Time < now then
        M.sound3Time = NEVER
        M.sound3 = AudioMessage("bd07003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        -- set the objectives
        ShowObjectives()
    end

    if M.waveDelay[0] < now then
        M.waveDelay[0] = NEVER
        M.waveDelay[1] = now + 30.0
        -- get first wave to attack
        for i = 0, 2 do
            if Valid(M.waveUnits1[i]) then
                Goto(M.waveUnits1[i], "attack_path1", 1)
            end
        end
    end
    if M.waveDelay[1] < now then
        M.waveDelay[1] = NEVER
        -- get second wave to attack
        for i = 0, 7 do
            if Valid(M.waveUnits2[i]) then
                Goto(M.waveUnits2[i], "attack_path2", 1)
            end
        end
        M.wavesSpawned = true
    end
    -- PORT SAFETY: path commands skip missing/deleted units only. Both source
    -- path names, priorities, fixed array bounds, and 30-second gap are intact.

    if M.wavesSpawned and not M.objective1Complete then
        M.objective1Complete = true
        for i = 0, 2 do
            if Alive(M.waveUnits1[i]) then
                M.objective1Complete = false
                break
            end
        end
        for i = 0, 7 do
            if Alive(M.waveUnits2[i]) then
                M.objective1Complete = false
                break
            end
        end
        if M.objective1Complete then
            ShowObjectives()
            AudioMessage("bd07004.wav")
            M.annoyTime = now + 1.0
            local scrap = GetScrap(2)
            if scrap < 40 then SetScrap(2, 40) end
        end
    end

    if M.annoyTime < now then
        M.annoyTime = now + 5 * 60.0
        for i = 0, 2 do
            local h = BuildObject("cvfigh", 2, "annoy_1")
            -- PORT SAFETY: failed builds or an absent player cannot receive a
            -- valid attack order. Keep spawning and the original cadence;
            -- valid objects still target the current player with default priority.
            if Valid(h) and Valid(M.user) then Attack(h, M.user) end
        end
        for i = 0, 1 do
            local h = BuildObject("cvltnk", 2, "annoy_1")
            if Valid(h) and Valid(M.user) then Attack(h, M.user) end
        end
    end

    -- have we met all the goals?
    if not M.won and not M.lost then
        M.won = true
        for i = 0, 10 do
            if Alive(M.mustDestroy[i]) then
                M.won = false
                break
            end
        end
        -- have we won?
        if M.won then
            ShowObjectives()
            SucceedMission(now + 1.0, "bd07win.des")
        end
    end

    if not M.lost and not M.won then
        M.lost = true
        for i = 0, 2 do
            if Healthy(M.mustSave[i]) then
                M.lost = false
                break
            end
        end
        -- have we lost?
        if M.lost then FailMission(now + 1.0, "bd07lose.des") end
    end
    -- Preserve victory-before-defeat ordering and the source's continued audio/
    -- harassment processing during the one-second mission outcome delay.
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores serializable state and engine handles. Unlike native
    -- PostLoad, no manual ConvertHandle is needed. Do not rerun Setup, replay
    -- briefing/resource initialization, or replace saved wave/harassment timers.
    M = state
end
