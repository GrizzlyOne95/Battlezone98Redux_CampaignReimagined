-- BlackDog05Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog05Mission.cpp
-- Source blob: 4446a98596a903f1f7764a0a65ff909645913061.
-- Complete native source, all comments, and serialization scaffolding:
-- References/BlackDog05Source/BlackDog05Mission.cpp.
-- No EXU/OpenShim/project helper dependency. Attach to the original bd05 map.
-- Zero-based arrays, Execute ordering, strict timers and priorities are kept.

local function NewState()
    return {
        -- record whether the init code has been done
        startDone = false,
        -- have we lost?
        lost = false, won = false,
        -- met the objectives?
        objective1Complete = false, objective2Complete = false,
        -- cameras
        cameraReady = false, cameraComplete = {[0] = false, false},
        -- wait
        waitsInitialized = false,
        waitOver = {[0] = false, false, false, false, false},
        waitTime = {[0] = 99999.0, 99999.0, 99999.0, 99999.0, 99999.0},
        -- quitters
        quittersSpawned = false, quitterMovieDone = false,
        rearAttackTime1 = 999999.9, rearAttackTime2 = 999999.9,
        howitzerTime = 999999.9, quitterDelay = 999999.0,
        bomberTime = 999999.9, portalTime = -1, quitterCamTime = 999999.9,
        -- the user, recycler, portal and audio-message handles start nil.
        -- badguys (0-14 = units, 15-18 = attack1,
        -- 19-22 = attack2, 23-27 = attack3,
        -- 28-33 = attack4
        -- 34-38 = rear_attack 1
        -- 39-43 = rear_attack 2
        -- 44-45 = howit
        units = {},
        -- quiters
        quitters = {},
        numBombers = 0, whichTimer = 0, portalStage = 0,
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function SpawnUnit(index, odf, path, command)
    local h = BuildObject(odf, 2, path)
    M.units[index] = h
    -- PORT FIX: failed spawns/deleted targets cannot receive Lua handle calls.
    -- Successful spawns retain the source's cloak and priority-1 commands.
    if Valid(h) then
        SetCloaked(h)
        if Valid(M.recycler) then command(h, M.recycler, 1) end
    end
end

local function resetObjectives()
    ClearObjectives()
    -- objective 1
    if M.objective1Complete then
        AddObjective("bd05001.otf", "green")
    else
        AddObjective("bd05001.otf", "white")
    end
end

function Start()
    M = NewState()
    -- handles
    M.recycler = GetHandle("recycler")
    M.portal = GetHandle("portal")
    for i = 0, 14 do M.units[i] = GetHandle("unit_" .. (i + 1)) end
    -- Native slots 15..45 and all message handles are null until assigned.
    -- number of bombers built; remaining Setup defaults are in NewState().
end

function AddObject(h)
    -- Native AddObject(Handle) has no active body. Do not enable the cut gate.
    --[==[
#if 0
    if (numBombers >= 7)
        return;

    GameObject *obj = GameObjectHandle::GetObj(h);
    if (obj->GetTeam() == GameObject::GetUserTeam())
    {
        // get the object's team slot
        int slot = obj->GetTeamSlot();

        // get the object's class
        GameObjectClass *c = obj->GetClass();
        _ASSERTE(c != NULL);

        if ((slot >= TEAM_SLOT_MIN_OFFENSE) && (slot <= TEAM_SLOT_MAX_OFFENSE))
        {
            // offensive unit built
            numBombers++;
            if (numBombers == 7)
            {
                objective1Complete = TRUE;
                resetObjectives();

                // start the new counter
                StopCockpitTimer();
                StartCockpitTimer(40 * 60, 60, 10);
                whichTimer = 2;
            }
        }
    }
#endif
    ]==]
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 8)
        SetPilot(1, 10)
        -- setup the initial objectives
        ClearObjectives()
        -- portal = BuildObject("cbport", 0, "portal");
        -- don't do this part after the first shot
        M.startDone = true
        --[==[
#if 0
        // debugging stuff
        cameraComplete[0] = TRUE;
        objective1Complete = TRUE;
        objective2Complete = TRUE;
#endif
        ]==]
    end

    -- start the camera going
    if not M.cameraComplete[0] then
        if not M.cameraReady then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.introSound = AudioMessage("bd05001.wav")
            resetObjectives()
            M.cameraReady = true
        end

        -- PORT FIX: a missing/deleted subject ends the same shot rather than
        -- passing a null handle to CameraPath. Normal arrival is unchanged.
        local arrived = not Valid(M.recycler)
        if not arrived then
            arrived = CameraPath("camera_start_arc", 3000, 2000, M.recycler)
        end
        if CameraCancelled() then
            arrived = true
            if M.introSound ~= nil then StopAudioMessage(M.introSound) end
        end
        if arrived then
            -- if the audio is complete (source actually checks arrival)
            CameraFinish()
            M.cameraComplete[0] = true
            M.cameraReady = false
            ClearObjectives()
            AddObjective("bd05001.otf", "white")
        end
    end

    -- setup the time delays (these run during the intro, as in Execute)
    if not M.waitsInitialized then
        M.waitTime[0] = GetTime() + 240.0
        M.waitTime[1] = GetTime() + 300.0
        M.waitTime[2] = GetTime() + 540.0
        M.waitTime[3] = GetTime() + 840.0
        M.waitTime[4] = GetTime() + 1140.0
        M.howitzerTime = GetTime() + 420
        M.rearAttackTime1 = GetTime() + 450
        M.rearAttackTime2 = GetTime() + 660
        M.waitsInitialized = true
    end

    -- check each of the time delays
    if not M.waitOver[0] and M.waitTime[0] < GetTime() then
        AudioMessage("bd05002.wav")
        M.waitOver[0] = true
    end

    if not M.waitOver[1] and M.waitTime[1] < GetTime() then
        -- spawn first wave
        SpawnUnit(15, "cvfigh", "first_wave", Goto)
        SpawnUnit(16, "cvfigh", "first_wave", Goto)
        SpawnUnit(17, "cvltnk", "first_wave", Goto)
        SpawnUnit(18, "cvltnk", "first_wave", Goto)
        -- these guys should just attack the general base area
        M.waitOver[1] = true
    end

    if not M.waitOver[2] and M.waitTime[2] < GetTime() then
        -- spawn first wave (native comment; this is the second wave)
        SpawnUnit(19, "cvltnk", "second_wave", Attack)
        SpawnUnit(20, "cvltnk", "second_wave", Attack)
        SpawnUnit(21, "cvtnk", "second_wave", Attack)
        SpawnUnit(22, "cvtnk", "second_wave", Attack)
        M.waitOver[2] = true
    end

    if not M.waitOver[3] and M.waitTime[3] < GetTime() then
        SpawnUnit(23, "cvtnk", "third_wave", Goto)
        SpawnUnit(24, "cvtnk", "third_wave", Goto)
        SpawnUnit(25, "cvhraz", "third_wave", Goto)
        SpawnUnit(26, "cvhraz", "third_wave", Goto)
        SpawnUnit(27, "cvwalk", "third_wave", Goto)
        -- attack general base area
        M.waitOver[3] = true
    end

    if not M.waitOver[4] and M.waitTime[4] < GetTime() then
        SpawnUnit(28, "cvtnk", "fourth_wave", Goto)
        SpawnUnit(29, "cvtnk", "fourth_wave", Goto)
        SpawnUnit(30, "cvhraz", "fourth_wave", Goto)
        SpawnUnit(31, "cvhraz", "fourth_wave", Goto)
        SpawnUnit(32, "cvwalk", "fourth_wave", Goto)
        SpawnUnit(33, "cvwalk", "fourth_wave", Goto)
        -- attack anything blackdog
        M.waitOver[4] = true
    end

    if M.rearAttackTime1 < GetTime() then
        M.rearAttackTime1 = 999999.9
        SpawnUnit(34, "cvtnk", "rear_attack", Attack)
        SpawnUnit(35, "cvtnk", "rear_attack", Attack)
        SpawnUnit(36, "cvtnk", "rear_attack", Attack)
        SpawnUnit(37, "cvtnk", "rear_attack", Attack)
        SpawnUnit(38, "cvtnk", "rear_attack", Attack)
    end

    if M.rearAttackTime2 < GetTime() then
        M.rearAttackTime2 = 999999.9
        SpawnUnit(39, "cvtnk", "rear_attack", Attack)
        SpawnUnit(40, "cvtnk", "rear_attack", Attack)
        SpawnUnit(41, "cvtnk", "rear_attack", Attack)
        SpawnUnit(42, "cvtnk", "rear_attack", Attack)
        SpawnUnit(43, "cvtnk", "rear_attack", Attack)
    end

    if M.howitzerTime < GetTime() then
        M.howitzerTime = 999999.9
        SpawnUnit(44, "cvartl", "howit", Goto)
        SpawnUnit(45, "cvartl", "howit", Goto)
    end

    if not M.objective2Complete and M.waitOver[4] then
        -- test to see if everything has been beaten
        local allDead = true
        for i = 0, 45 do
            if Alive(M.units[i]) then
                allDead = false
                break
            end
        end
        M.objective2Complete = allDead
        if M.objective2Complete then
            -- SOURCE BUG FIX: objective1Complete's only true assignment is in
            -- disabled AddObject/debug code, but victory still requires it.
            -- Complete the orphaned flag at the existing all-46-dead event.
            -- This repairs the unwinnable gate and green objective display;
            -- no wave, retreat, movie, timing or seven-unit build gate changes.
            M.objective1Complete = true
            AudioMessage("bd05004.wav")
            resetObjectives()
        end
    end

    if M.objective2Complete and not M.quittersSpawned then
        M.quitters[0] = BuildObject("cvtnk", 2, "quitters")
        M.quitters[1] = BuildObject("cvtnk", 2, "quitters")
        M.quitters[2] = BuildObject("cvwalk", 2, "quitters")
        M.quitters[3] = BuildObject("cvwalk", 2, "quitters")
        M.quitters[4] = BuildObject("cspilo", 2, "quitters")
        M.quitters[5] = BuildObject("cvltnk", 2, "quitters")
        -- have these bastards head towards the portal
        for i = 0, 5 do
            if Valid(M.quitters[i]) then Retreat(M.quitters[i], "portal_in", 1) end
        end
        M.quittersSpawned = true
        -- Native activatePortal(portal, true) selects inward activation.
        if Valid(M.portal) then PortalIn(M.portal) end
    end

    if M.quittersSpawned then
        -- Native allGone was always true and its branch was empty. Retained
        -- as inert scaffolding; do not invent an all-six-escaped victory gate.
        local allGone = true
        for i = 0, 5 do
            local h = M.quitters[i]
            if h ~= nil then
                if not Alive(h) then
                    M.quitters[i] = nil
                elseif Valid(M.portal) and IsTouching(h, M.portal) then
                    RemoveObject(h)
                    M.quitters[i] = nil
                end
            end
        end
        if allGone then
            -- empty in the native source
        end
    end

    if M.quittersSpawned and M.cameraComplete[0] and not M.cameraComplete[1] then
        if not M.cameraReady then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.quitterSound = AudioMessage("bd05005.wav")
            M.quitterCamTime = GetTime() + 15.0
            -- PORT FIX: a failed AudioMessage returns nil, so its completion
            -- branch can never arm the 3-second delay. Treat absent audio as
            -- complete while retaining the 15-second minimum movie duration.
            -- Successful narration still arms the delay only when it ends.
            if M.quitterSound == nil then M.quitterDelay = GetTime() + 3.0 end
            M.cameraReady = true
        end

        local seqDone = false
        if Valid(M.portal) then CameraPath("camera_retreat", 3000, 0, M.portal) end
        -- if we're done the sound, start the time delay
        if M.quitterSound ~= nil and IsAudioMessageDone(M.quitterSound) then
            M.quitterDelay = GetTime() + 3.0
            M.quitterSound = nil
        end
        if M.quitterDelay < GetTime() and M.quitterCamTime < GetTime() then
            seqDone = true
        end
        -- cancelled or out of time?
        -- PORT FIX: absent portal releases an invalid shot via the same exit.
        if seqDone or CameraCancelled() or not Valid(M.portal) then
            -- if the audio is complete (cancellation need not await narration)
            CameraFinish()
            M.cameraComplete[1] = true
            M.cameraReady = false
            M.quitterMovieDone = true
        end
    end

    if M.objective1Complete and M.objective2Complete and M.quitterMovieDone
        and not M.won and not M.lost then
        M.sound6 = AudioMessage("bd05006.wav")
        M.won = true
        -- PORT FIX: absent congratulations audio must not stall success.
        -- Normal playback still waits for the same completion check below.
        if M.sound6 == nil then SucceedMission(GetTime() + 0.1, "bd05win.des") end
    end

    if M.sound6 ~= nil and IsAudioMessageDone(M.sound6) then
        M.sound6 = nil
        -- PORT FIX: the stock Lua API takes absolute mission time; native
        -- SucceedMission(0.1f, ...) is already in the past at this point.
        -- Schedule its intended 0.1-second delay after the same final audio.
        SucceedMission(GetTime() + 0.1, "bd05win.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission serializes tables and remaps game handles. Do not rerun
    -- Setup, restart delays, or replay any camera/audio/spawn when loading.
    M = state
end
