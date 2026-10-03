-- BlackDog01Mission.cpp -> Battlezone 98 Redux, stock Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog01Mission.cpp
-- Source blob: c55ead909f5e1c4415c7fe43d6d14115ff9e2dc4.
-- The complete original (ALL comments, declarations, and native save code)
-- is retained in References/BlackDog01Source/BlackDog01Mission.cpp.
-- No campaign helpers, EXU, OpenShim, or community mission code required.

-- messages; keep the native zero-based indices.
local NUM_MESSAGES = 4
local BD01002, BD01003, BD01004, BD01005 = 0, 1, 2, 3
local NEVER = 999999.9

local function NewState()
    local s = {
        startDone = false,
        objective1Complete = false, objective2Complete = false, objective3Complete = false,
        cameraReady = false, cameraComplete = {[0] = false, [1] = false},
        scavengersCreated = false, scavengers = {},
        soundStarted = {}, soundPlayed = {}, soundHandle = {},
        beaconSpawned1 = false, beaconSpawned2 = false,
        ambushRetreat = false, wave1Ready = false, wave2Ready = false,
        wave2Delay = 999999.0, delayTime1 = 999999.0,
        delayTime2 = 999999.0, delayTime3 = 999999.0,
        sound6Time = NEVER, sound7Time = NEVER, sound8Time = NEVER, sound9Time = NEVER,
        -- PORT FIX: latch a scheduled failure so victory cannot overwrite it.
        -- No surviving-recycler victory prerequisite or normal delay changes.
        failed = false,
    }
    -- PORT FIX: Setup used i < 9 for four-entry soundStarted/soundPlayed
    -- arrays, corrupting adjacent flags. Initialize only NUM_MESSAGES entries;
    -- all intended flags retain their original initial values and event timing.
    -- Original: for (i = 0; i < 9; i++) { soundStarted[i] = FALSE; soundPlayed[i] = FALSE; }
    for i = 0, NUM_MESSAGES - 1 do
        s.soundStarted[i], s.soundPlayed[i] = false, false
    end
    -- Native Load zeros all handles/integers before Setup. Lua handle/audio
    -- slots start nil: user, recycler, wingman1/2, both ambushers, four wave1
    -- and five wave2 units, beacon, openingSound, attackSound, sound6..sound9.
    -- Unused BD01003, scavengers[0/1], and delayTime3 remain retained state.
    return s
end

local M = NewState()
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end
local function Deployed() return Valid(M.recycler) and IsDeployed(M.recycler) end

local function Distance(h, where)
    -- PORT FIX: missing handles must not satisfy proximity tests or select an
    -- invalid Lua overload. All valid-object/path distances remain unchanged.
    if not Valid(h) or (type(where) ~= "string" and not Valid(where)) then
        return math.huge
    end
    return GetDistance(h, where)
end

local function ResetObjectives()
    ClearObjectives()
    AddObjective("bd01001.otf", M.objective1Complete and "green" or "white")
    if not M.beaconSpawned2 then return end
    AddObjective("bd01002.otf", M.objective2Complete and "green" or "white")
    if not M.wave1Ready then return end
    AddObjective("bd01003.otf", M.objective3Complete and "green" or "white")
end

local function Fail(time, description)
    if not M.failed then
        M.failed = true
        FailMission(time, description)
    end
end

local function ClearReminder(first, second)
    if M[first] ~= nil then StopAudioMessage(M[first]); M[first] = nil end
    if M[second] ~= nil then StopAudioMessage(M[second]); M[second] = nil end
    M[first .. "Time"], M[second .. "Time"] = NEVER, NEVER
end

local function CompleteNav()
    if M.objective2Complete then return end
    M.objective2Complete = true
    -- PORT FIX: source only cancels future timers. A reminder already playing
    -- could re-arm the next one or fail AFTER reaching Nav Alpha. Cancel those
    -- pending messages too; the 60/30-second deadlines and encounter gates stay
    -- unchanged for a player who has not reached/revealed the ambush.
    ClearReminder("sound6", "sound7")
    ResetObjectives()
end

local function PlaySoundAndWait(index, filename)
    -- Native PLAY_SOUND_AND_WAIT(a), including its Execute early-return gate.
    -- #a in the macro stringifies BD01002 (not its numeric expansion).
    if not M.soundStarted[index] then
        M.soundStarted[index] = true
        M.soundHandle[index] = AudioMessage(filename)
    end
    if not M.soundPlayed[index] then
        if IsAudioMessageDone(M.soundHandle[index]) then
            M.soundPlayed[index] = true
        else
            return false
        end
    end
    return true
end

local function Ambusher()
    local h = BuildObject("cvfigh", 2, "spawn_attack_ambush")
    if Valid(h) then
        -- Native: GameObject *o = GameObjectHandle::GetObj(h);
        -- _ASSERTE(o != NULL); o->curPilot = 0;
        -- curPilot is the pilot CLASS pointer, not the active AI process.
        -- Stock SetPilotClass(h, "") clears that class (nil resets the nation's
        -- default). Preserve patrol AI; RemovePilot/KillPilot would disable it.
        SetPilotClass(h, "")
        Patrol(h, "ambush_patrol_path", 1)
        Cloak(h)
    end
    return h
end

local function Attacker(odf, path, decloak)
    local h = BuildObject(odf, 2, path)
    if Valid(h) then
        if Valid(M.recycler) then Attack(h, M.recycler, 1) end
        if decloak then
            -- Preserve the source's visible decloaking effect and call order.
            SetCloaked(h)
            Decloak(h)
        end
    end
    return h
end

function Start()
    -- Setup resolves map handles here. Load restores saved state without Setup.
    M.recycler = GetHandle("recycler")
    M.wingman1 = GetHandle("wingman1_bobcat")
    M.wingman2 = GetHandle("wingman2_bobcat")
end

function AddObject(h)
    -- Native GameObject callback tests !scavengersCreated, then calls an EMPTY
    -- AddObject(Handle). Retain the hook without inventing a scavenger gate.
    -- Original comment: if we still have scavengers to create, then test what we just made
    if not M.scavengersCreated then
        -- BlackDog01Mission::AddObject(Handle h) { }
    end
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    if not M.startDone then
        SetScrap(1, 12)
        SetPilot(1, 10)
        -- objectives
        ResetObjectives()
        if Valid(M.recycler) then Goto(M.recycler, "start_path_recycler", 0) end
        if Valid(M.wingman1) then Goto(M.wingman1, "start_path_wingman1", 0) end
        if Valid(M.wingman2) then Goto(M.wingman2, "start_path_wingman2", 0) end
        -- Native Goto defaults to commandable priority 0; Lua defaults to 1.
        -- play the opening sound
        M.openingSound = AudioMessage("bd01001.wav")
        -- don't do this part after the first shot
        M.startDone = true
        --SucceedMission(GetTime(), "bd01win.des");
    end

    -- if we lose the recycler, play the "failure" message
    if (not Valid(M.recycler) or GetHealth(M.recycler) <= 0.0) and not M.soundStarted[BD01005] then
        M.soundStarted[BD01005] = true
        M.soundHandle[BD01005] = AudioMessage("bd01005.wav")
    end
    -- when the sound's done, end the mission
    if M.soundStarted[BD01005] and not M.soundPlayed[BD01005] then
        if IsAudioMessageDone(M.soundHandle[BD01005]) then
            Fail(GetTime() + 4.0, "bd01lsea.des") -- lost the recycler
            M.soundPlayed[BD01005] = true
        end
    end

    -- start the camera going
    if not M.cameraComplete[0] then
        if not M.cameraReady then
            CameraReady() -- get the camera ready
            -- start the audio (native comment only; opening audio already started)
            M.cameraReady = true
        end
        -- PORT FIX: release a shot with a missing subject instead of passing
        -- nil into CameraPath. Normal paths, heights, speeds and timing stay.
        local arrived = not Valid(M.recycler)
        if not arrived then arrived = CameraPath("camera_start_arc", 3000, 3500, M.recycler) end
        if CameraCancelled() then
            arrived = true
            StopAudioMessage(M.openingSound)
        end
        if arrived then
            CameraFinish()
            M.cameraComplete[0], M.cameraReady = true, false
            -- A deployment completed during the shot must not re-arm warnings.
            if not M.scavengersCreated then M.sound8Time = GetTime() + 90.0 end
        end
    end

    -- PORT FIX: recognize deployment before processing an already-playing
    -- failure reminder. Source processes sound9 first and can fail a deployed
    -- recycler. The deployment gate, 20-second wait and 90/30-second warnings
    -- retain their original timing; only obsolete warning audio is stopped.
    if not M.scavengersCreated and Deployed() then
        -- this variable should change names since we're
        -- not waiting for scavengers to be created anymore
        M.scavengersCreated = true
        M.delayTime1 = GetTime() + 20.0
        ClearReminder("sound8", "sound9")
        M.objective1Complete = true
        ResetObjectives()
    end
    if M.sound8Time < GetTime() then
        M.sound8Time = NEVER
        if not Deployed() then M.sound8 = AudioMessage("bd01008.wav") end
    end
    if M.sound8 ~= nil and IsAudioMessageDone(M.sound8) then
        M.sound8 = nil
        M.sound9Time = GetTime() + 30.0
    end
    if M.sound9Time < GetTime() then
        M.sound9Time = NEVER
        if not Deployed() then M.sound9 = AudioMessage("bd01009.wav") end
    end
    if M.sound9 ~= nil and IsAudioMessageDone(M.sound9) then
        M.sound9 = nil
        Fail(GetTime() + 1.0, "bd01lseb.des")
    end

    -- if the player doesn't have scavengers created yet, don't continue
    if not M.scavengersCreated then return end
    if GetTime() < M.delayTime1 then return end -- delayTime1 is set in AddObject (stale native comment)
    if not M.beaconSpawned1 then
        -- spawn our beacon
        M.beaconSpawned1 = true
        M.beacon = BuildObject("apcamr", 1, "spawn_nav_beacon")
        if Valid(M.beacon) then SetObjectiveName(M.beacon, "Nav Alpha") end -- stock SetName alias
        M.badGuy1_ambush = Ambusher()
        M.badGuy2_ambush = Ambusher()
    end
    if not PlaySoundAndWait(BD01002, "BD01002.WAV") then return end
    if not M.beaconSpawned2 then
        -- spawn our beacon (native flag only; no second object)
        M.beaconSpawned2 = true
        -- try to select the beacon here so that the little window shows up
        if Valid(M.beacon) then SetUserTarget(M.beacon) end
        -- also setup new objectives
        ResetObjectives()
        M.sound6Time = GetTime() + 60.0
    end

    if M.sound6Time < GetTime() + 60.0 or M.sound7Time < GetTime() + 30.0 then
        -- check to see if any ally units near the nav
        -- Lua path overload takes (path, point, team), matching the native call.
        local h = GetNearestUnitOnTeam("spawn_nav_beacon", 0, 1)
        if Distance(h, "spawn_nav_beacon") < 100.0
            or not (Valid(M.badGuy1_ambush) and IsCloaked(M.badGuy1_ambush))
            or not (Valid(M.badGuy2_ambush) and IsCloaked(M.badGuy2_ambush)) then
            CompleteNav()
        end
    end
    -- PORT FIX: the native player/beacon fallback was below sound7 failure.
    -- Evaluate the SAME <100 test before obsolete audio can fail this frame.
    if not M.objective2Complete and Distance(M.user, M.beacon) < 100.0 then CompleteNav() end
    if M.sound6Time < GetTime() then
        M.sound6Time = NEVER
        M.sound6 = AudioMessage("bd01006.wav")
    end
    if M.sound6 ~= nil and IsAudioMessageDone(M.sound6) then
        M.sound6 = nil
        M.sound7Time = GetTime() + 30.0
    end
    if M.sound7Time < GetTime() then
        M.sound7Time = NEVER
        M.sound7 = AudioMessage("bd01007.wav")
    end
    if M.sound7 ~= nil and IsAudioMessageDone(M.sound7) then
        M.sound7 = nil
        Fail(GetTime() + 1.0, "bd01lsec.des")
    end

    -- ok, wait until one of the 2 ambushers is dead
    if not M.ambushRetreat then
        local survivor
        if not Alive(M.badGuy1_ambush) then survivor = M.badGuy2_ambush
        elseif not Alive(M.badGuy2_ambush) then survivor = M.badGuy1_ambush end
        if not Alive(M.badGuy1_ambush) or not Alive(M.badGuy2_ambush) then
            -- retreat #2 (or #1, if #2 died first)
            if Alive(survivor) then Retreat(survivor, "ambush_retreat_path", 1); Cloak(survivor) end
            M.delayTime2 = GetTime() + 5.0
            M.ambushRetreat = true
        end
    end
    -- if one of the ambushers hasn't retreated yet, don't continue
    if not M.ambushRetreat then return end
    if GetTime() < M.delayTime2 then return end -- time delay
    if not M.wave1Ready then
        M.wave1Ready = true
        M.badGuy1_wave1 = Attacker("cvfigh", "spawn_attack_wave1", true)
        M.badGuy2_wave1 = Attacker("cvfigh", "spawn_attack_wave1", true)
        M.wave2Delay = GetTime() + 60.0
        ResetObjectives() -- add in the other objectives
    end
    if not M.cameraComplete[1] then
        if not M.cameraReady then
            CameraReady() -- get the camera ready
            -- start the audio
            M.cameraReady = true
            -- get any survivers of the ambush to continue
            if Alive(M.badGuy1_ambush) and Valid(M.recycler) then Attack(M.badGuy1_ambush, M.recycler, 1) end
            if Alive(M.badGuy2_ambush) and Valid(M.recycler) then Attack(M.badGuy2_ambush, M.recycler, 1) end
            M.attackSound = AudioMessage("bd01003.wav") -- play the sound
        end
        local arrived = not Valid(M.badGuy1_wave1)
        if not arrived then arrived = CameraPath("camera_attack_view", 2000, 1000, M.badGuy1_wave1) end
        if CameraCancelled() then
            arrived = true
            StopAudioMessage(M.attackSound)
        end
        if arrived then
            -- if the audio is complete (native checks camera arrival, not audio)
            CameraFinish()
            M.cameraComplete[1], M.cameraReady = true, false
            M.badGuy3_wave1 = Attacker("cvfigh", "spawn_attack_wave1a", true)
            M.badGuy4_wave1 = Attacker("cvfigh", "spawn_attack_wave1a", true)
        end
    end
    -- don't continue until the delay is done
    if M.wave2Delay > GetTime() then return end
    if not M.wave2Ready then
        M.wave2Ready = true
        -- create the 2nd wave
        M.badGuy1_wave2 = Attacker("cvfigh", "spawn_attack_wave2", false)
        M.badGuy2_wave2 = Attacker("cvfigh", "spawn_attack_wave2", false)
        M.badGuy3_wave2 = Attacker("cvltnk", "spawn_attack_wave2", false)
        M.badGuy4_wave2 = Attacker("cvfigh", "spawn_attack_wave2a", false)
        M.badGuy5_wave2 = Attacker("cvfigh", "spawn_attack_wave2a", false)
    end
    -- have we killed everything? Include the surviving ambusher as in source.
    -- PORT FIX: recycler loss takes precedence even while its audio is playing,
    -- and pending wave1 camera reinforcements cannot be mistaken for dead units.
    -- This only blocks contradictory/early victory, preserving all eleven enemy
    -- checks, the congratulatory audio gate and original four-second win delay.
    if not M.failed and not M.soundStarted[BD01005] and M.cameraComplete[1]
        and not Alive(M.badGuy1_wave1) and not Alive(M.badGuy2_wave1)
        and not Alive(M.badGuy3_wave1) and not Alive(M.badGuy4_wave1)
        and not Alive(M.badGuy1_wave2) and not Alive(M.badGuy2_wave2)
        and not Alive(M.badGuy3_wave2) and not Alive(M.badGuy4_wave2)
        and not Alive(M.badGuy5_wave2) and not Alive(M.badGuy1_ambush)
        and not Alive(M.badGuy2_ambush) and not M.soundStarted[BD01004] then
        M.soundStarted[BD01004] = true -- start the "congrats" message
        M.soundHandle[BD01004] = AudioMessage("bd01004.wav")
        M.objective3Complete = true
        ResetObjectives()
    end
    -- when the sound's done, end the level
    if not M.failed and not M.soundStarted[BD01005]
        and M.soundStarted[BD01004] and not M.soundPlayed[BD01004] then
        if IsAudioMessageDone(M.soundHandle[BD01004]) then
            M.soundPlayed[BD01004] = true
            SucceedMission(GetTime() + 4.0, "bd01win.des")
        end
    end
end

function Save() return M end
function Load(state)
    -- LuaMission serializes tables/game handles/audio messages and restores
    -- handle identity. No native ConvertHandle or Setup replay is needed.
    M = state
    ResetObjectives()
end
