-- BlackDog04Mission.cpp faithfully ported to stock BZR 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog04Mission.cpp
-- Source blob: d3d0ee442c4140050186402965d851e19a5ea7a1.
-- Complete native source, including every comment and serialization member:
-- References/BlackDog04Source/BlackDog04Mission.cpp. No EXU/helper dependency.
-- Original zero-based arrays, update order, priorities, timers, and unused
-- members are retained. Attach as the Lua mission for the original bd04 map.

local function NewState()
    return {
        startDone = false,
        cameraReady = {[0] = false, false, false},
        cameraComplete = {[0] = false, false, false},
        gotoScav = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        inBaseArea = false, doAttack = false, startAttack = false,
        outOfScav = false, fightersSpawned = false, trigger1 = false,
        idFragment = false, gotFragment = false,
        returnAttack = {[0] = false, false, false, false},
        lost = false, won = false,
        cameraCompleteDelay = 999999.9, getInScavTimeout = 999999.0,
        portalCamTime = 999999.9, portalOffTime = 999999.9,
        portalUnitTime = {[0] = 999999.9, 999999.9},
        portalSoundTime = 99999.0, inBaseSoundTime = 999999.9,
        sound4Time = 99999.0, bomberTime = 999999.9,
        turret = {}, portalUnit = {},
        -- Native handles and audio IDs start null; Lua represents them as nil:
        -- user, lastUser, pilot, nav1/2, silo, portal, fragment, navBeacon,
        -- hauler, scav1/2/3, scavMessage, introSound, sound4/5/6,
        -- portalSound, congrats, inBaseSound1/2.
        timeoutWarningStarted = false, dropZoneReady = false,
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Distance(from, to, point)
    -- PORT FIX: null/deleted handles must not satisfy proximity checks or
    -- select the wrong Lua overload. Valid-map distances are unchanged.
    if not Valid(from) then return math.huge end
    if type(to) ~= "string" and not Valid(to) then return math.huge end
    if point ~= nil then return GetDistance(from, to, point) end
    return GetDistance(from, to)
end

local function Go(h, where, priority)
    if Valid(h) then Goto(h, where, priority) end
end

local function Strike(h, target, priority)
    -- Destroyed turrets/spawn failures cannot receive orders; do not substitute
    -- targets or change the source's explicit/default command priorities.
    if Valid(h) and Valid(target) then Attack(h, target, priority) end
end

local function Done(message)
    return message ~= nil and IsAudioMessageDone(message)
end

local function StopMessage(message)
    if message ~= nil then StopAudioMessage(message) end
end

function Start()
    M = NewState()
    M.silo = GetHandle("silo")
    M.portal = GetHandle("portal")
    M.scav1 = GetHandle("scav_1")
    M.scav2 = GetHandle("scav_2")
    M.scav3 = GetHandle("scav_3")
    M.fragment = GetHandle("fragment")
    M.hauler = GetHandle("hauler_1")
    for i = 0, 8 do M.turret[i] = GetHandle("turret_" .. (i + 1)) end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 8)
        SetPilot(1, 10)
        -- setup the initial objectives
        ClearObjectives()
        -- don't do this part after the first shot
        M.startDone = true
    end

    -- SOE #1: start the camera going
    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            CameraReady()
            -- spawn the pilot
            M.pilot = BuildObject("aspilo", 1, "pilot")
            Go(M.pilot, "pilot_path", 1)
            if Valid(M.user) then Hide(M.user) end
            M.introSound = AudioMessage("bd04001.wav")
            M.cameraReady[0] = true
        end

        -- PORT FIX: release a shot if its spawned subject is missing; this
        -- avoids a stuck/invalid camera and runs the same completion actions.
        local arrived = not Valid(M.pilot)
        if not arrived then
            arrived = CameraPath("camera_start_up", 750, 400, M.pilot)
        end
        -- should we spawn the beacons?
        if M.nav1 == nil and Distance(M.pilot, "nav_1", 0) < 1.0 then
            M.nav1 = BuildObject("apcamr", 0, "nav_1")
        end
        if M.nav2 == nil and Distance(M.pilot, "nav_2", 0) < 1.0 then
            M.nav2 = BuildObject("apcamr", 0, "nav_2")
            M.cameraCompleteDelay = GetTime() + 2.0
        end
        if CameraCancelled() then
            arrived = true
            StopMessage(M.introSound)
        end
        if arrived or M.cameraCompleteDelay < GetTime() then
            -- if the audio is complete (source checks arrival/delay, not audio)
            CameraFinish()
            M.cameraComplete[0] = true
            M.cameraReady[0] = false
            M.cameraCompleteDelay = 999999.9
            -- remove the pilot
            if Valid(M.pilot) then RemoveObject(M.pilot) end
            M.pilot = nil
            if Valid(M.user) then UnHide(M.user) end
            -- if the nav's don't exist, add them
            if M.nav1 == nil then M.nav1 = BuildObject("apcamr", 0, "nav_1") end
            if M.nav2 == nil then M.nav2 = BuildObject("apcamr", 0, "nav_2") end
            if Valid(M.user) then SetPerceivedTeam(M.user, 2) end
        end
    end

    -- SOE #2
    if M.cameraComplete[0] and not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            M.cameraReady[1] = true
            M.cameraComplete[1] = false
            CameraReady()
            -- Native activatePortal(portal, false): outward portal activation.
            if Valid(M.portal) then PortalOut(M.portal) end
            M.portalCamTime = GetTime() + 6.0
            M.portalSoundTime = GetTime() + 4.0 -- 2 seconds before the sound
            M.portalUnitTime[0] = GetTime() + 1.5
            M.portalUnitTime[1] = GetTime() + 4.0
            M.portalOffTime = GetTime() + 7.0
        end
        if Valid(M.portal) then CameraPath("camera_portal", 3000, 0, M.portal) end
        if CameraCancelled() or not Valid(M.portal) then
            M.portalCamTime = -1
            StopMessage(M.portalSound)
        end
        if M.portalCamTime < GetTime() then
            M.portalCamTime = 999999.9
            M.cameraReady[1] = false
            M.cameraComplete[1] = true
            CameraFinish()
        elseif M.portalSoundTime < GetTime() then
            M.portalSoundTime = 999999.9
            M.portalSound = AudioMessage("bd04002.wav")
        end
    end

    for i = 0, 1 do
        if M.portalUnitTime[i] < GetTime() then
            M.portalUnitTime[i] = 999999.9
            if Valid(M.portal) then
                M.portalUnit[i] = BuildObjectAtPortal("cvfigh", 2, M.portal)
                -- Native assertion: "Failed to create Portal Unit %i", i.
                Go(M.portalUnit[i], "unit_path", 1)
            end
        end
    end
    if M.portalOffTime < GetTime() then
        M.portalOffTime = 999999.9
        if Valid(M.portal) then DeactivatePortal(M.portal) end
    end

    -- SOE #3
    if M.cameraComplete[1] and not M.gotoScav then
        M.scavMessage = AudioMessage("bd04003.wav")
        ClearObjectives()
        AddObjective("bd04001.otf", "white")
        if Valid(M.scav3) then
            SetObjectiveOn(M.scav3)
            SetObjectiveName(M.scav3, "Scavenger")
            SetUserTarget(M.scav3)
        end
        M.gotoScav = true
        M.getInScavTimeout = GetTime() + 120.0
    end
    -- time out and play message again
    if not M.objective1Complete and M.getInScavTimeout < GetTime() then
        M.getInScavTimeout = GetTime() + 120.0
        M.scavMessage = AudioMessage("bd04003.wav")
    end
    -- are we in the scav?
    if Valid(M.user) and M.user == M.scav3 then
        if not M.objective1Complete and not M.objective2Complete then
            -- stop the "goto scav" message if it's still playing
            if M.scavMessage ~= nil and not Done(M.scavMessage) then
                StopMessage(M.scavMessage)
            end
            ClearObjectives()
            AddObjective("bd04001.otf", "green")
            AddObjective("bd04002.otf", "white")
            M.objective1Complete = true
            SetObjectiveOff(M.scav3)
            M.getInScavTimeout = 999999.0
            Go(M.scav1, "scav_path")
            Go(M.scav2, "scav_path")
            AudioMessage("bd04010.wav")
            if Valid(M.portal) then SetObjectiveOn(M.portal) end
        end
    end

    -- SOE #4
    if not M.trigger1 and M.scav3 == M.user and Distance(M.scav3, "trigger_1") < 400.0 then
        M.trigger1 = true
    end
    -- Native isIn(user, "base_limit") is an area query, NOT portal IsIn.
    if Valid(M.user) and IsInsideArea("base_limit", M.user) and not M.inBaseArea then
        M.inBaseArea = true
        if M.trigger1 then
            -- we're safe since we went by trigger_1
        elseif M.user == M.scav3 then
            M.inBaseSound1 = AudioMessage("bd04005.wav")
        else
            M.doAttack = true
        end
    end
    if Done(M.inBaseSound1) then
        M.inBaseSound1 = nil
        M.inBaseSoundTime = GetTime() + 1.0
    end
    if M.inBaseSoundTime < GetTime() then
        M.inBaseSoundTime = 999999.9
        M.inBaseSound2 = AudioMessage("bd04006.wav")
    end
    if Done(M.inBaseSound2) then
        M.inBaseSound2 = nil
        M.doAttack = true
    end
    if M.doAttack then
        --doAttack = FALSE;
        if not M.startAttack or M.lastUser ~= M.user then
            M.startAttack = true
            -- turrets lock on and attack
            for i = 0, 8 do Strike(M.turret[i], M.user, 1) end
        end
    end

    if not M.objective2Complete and IsInfo("cbport") then
        ClearObjectives()
        AddObjective("bd04004.otf", "white")
        M.sound4Time = GetTime() + 2.0
        M.objective2Complete = true
        if Valid(M.portal) then SetObjectiveOff(M.portal) end
        StartCockpitTimer(60, 15, 5)
    end
    -- play the audio message after a 2 second delay
    if M.sound4Time < GetTime() then
        M.sound4Time = 999999.9
        M.sound4 = AudioMessage("bd04004.wav")
    end
    -- once played
    if Done(M.sound4) then M.sound4 = nil end

    if M.objective2Complete and not M.idFragment and not M.timeoutWarningStarted
        and GetCockpitTimer() <= 0.0 then
        -- PORT FIX: native code starts bd04005 every frame after expiry,
        -- replacing sound5 so bd04006/attack may never follow. Latch the
        -- existing timeout once; the 60-second deadline and warning/attack
        -- sequence remain unchanged. Save this latch with the mission state.
        M.timeoutWarningStarted = true
        HideCockpitTimer()
        M.sound5 = AudioMessage("bd04005.wav")
    end
    -- once played
    if Done(M.sound5) then
        M.sound5 = nil
        M.sound6 = AudioMessage("bd04006.wav")
    end
    -- once played
    if Done(M.sound6) then
        M.sound6 = nil
        M.doAttack = true
    end

    -- SOE #4a
    if M.objective2Complete and not M.idFragment and IsInfo("obdataa") then
        StopCockpitTimer()
        HideCockpitTimer()
        M.idFragment = true
        AudioMessage("bd04007.wav")
        ClearObjectives()
        AddObjective("bd04003.otf", "white")
        M.objective3Complete = true
    end
    if M.objective3Complete and not M.outOfScav then
        if M.user ~= M.scav3 then
            M.outOfScav = true
            M.doAttack = true
        end
    end

    -- SOE #4b
    if not M.gotFragment then
        -- PORT FIX: absent cargo/player handles must not count as pickup
        -- through nil == nil. Actual tug/player equality is unchanged.
        if Valid(M.fragment) and Valid(M.user) and GetTug(M.fragment) == M.user then
            M.gotFragment = true
            M.navBeacon = BuildObject("apcamr", 1, "rv_scout")
            --SetUserTarget(navBeacon);
            -- Native repeatedly overwrites a local h; these escorts receive
            -- no scripted command. Keep their original default AI behavior.
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvfigh", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            BuildObject("bvtank", 1, "escort_units")
            M.bomberTime = GetTime() + 30.0
        end
    end
    if M.bomberTime < GetTime() then
        M.bomberTime = 999999.9
        for i = 1, 5 do
            local h = BuildObject("bvhraza", 1, "bomber_wing_x5_spawn_point")
            -- Native assertion: "bomber not created @ bomber_wing_x5_spawn_point".
            Go(h, "trigger_1")
        end
        M.navBeacon = BuildObject("apcamr", 1, "proposed_end_area")
        if Valid(M.navBeacon) then
            SetObjectiveName(M.navBeacon, "Drop Zone") -- native SetName alias
            SetObjectiveOn(M.navBeacon)
        end
        M.dropZoneReady = true
        --SetUserTarget(navBeacon);

        -- spawn the fighers to kill the player here (source targets hauler)
        for i = 1, 6 do
            local h = BuildObject("cvfighg", 2, "chinese_scout_x6_spawn_point")
            Strike(h, M.hauler, 1)
        end
        for i = 1, 2 do
            local h = BuildObject("cvfighg", 2, "attack_1")
            Strike(h, M.hauler, 1)
        end
        for i = 1, 4 do
            local h = BuildObject("cvfighg", 2, "attack_2")
            Strike(h, M.hauler, 1)
        end
        for i = 1, 3 do
            local h = BuildObject("cvtnk", 2, "attack_3")
            Strike(h, M.hauler, 1)
        end
    end
    for i = 0, 3 do
        local spot = "return_" .. (i + 1)
        -- Preserve ungated route ambushes: proximity alone triggers each one.
        if not M.returnAttack[i] and Distance(M.hauler, spot) < 300.0 then
            M.returnAttack[i] = true
            for j = 1, 3 do
                local h = BuildObject("cvfigh", 2, spot)
                Strike(h, M.hauler)
            end
        end
    end

    if (not Valid(M.hauler) or GetHealth(M.hauler) <= 0.0) and not M.lost and not M.won then
        FailMission(GetTime() + 1.0, "bd04lose.des")
        M.lost = true
    end

    -- SOE #5
    -- PORT FIX: native navBeacon is null before pickup, then rv_scout until
    -- bomberTime replaces it. Only test the final Drop Zone after that source
    -- event. This prevents null-handle/temporary-rendezvous victories while
    -- keeping the intended extraction route, 30-second event, and 50m radius.
    if M.objective3Complete and M.dropZoneReady and Distance(M.fragment, M.navBeacon) < 50.0
        and not M.won and not M.lost then
        ClearObjectives()
        AddObjective("bd04003.otf", "green")
        M.won = true
        M.congrats = AudioMessage("bd04008.wav")
    end
    if Done(M.congrats) then
        M.congrats = nil
        -- PORT FIX: SucceedMission takes an absolute mission time. Native 0.1
        -- is already in the past here; schedule its intended 0.1-second delay
        -- after the same congratulations audio, with no new victory gate.
        SucceedMission(GetTime() + 0.1, "bd04win.des")
    end
    -- what if the portal is destroyed?
    if (not Valid(M.portal) or GetHealth(M.portal) <= 0.0) and not M.won and not M.lost then
        M.lost = true
        FailMission(GetTime() + 1.0, "bd04lose.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores table values and engine handles. Do not rerun Setup
    -- or replay cameras, audio, spawns, countdowns, or ambushes after loading.
    M = state
end
