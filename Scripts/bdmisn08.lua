-- BlackDog08Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source blob: f0fbb7371b4a584a4852889e1f33f741ad11695a.
-- Complete original (all comments, TEST_PORTAL branches, native serialization):
-- References/BlackDog08Source/BlackDog08Mission.cpp.
-- No EXU/OpenShim or Campaign Reimagined helpers are required.

local NEVER = 999999.9
-- //#define TEST_PORTAL: disabled in the shipped source. Enable only for tests.
local TEST_PORTAL = false
local attackers = {
    "cvtnk", "cvtnk", "cvltnk", "cvfigh", "cvfigh",
    "cvfigh", "cvfigh", "cvfigh", "cvrckt", "cvhraz",
}

local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused source flags retained
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false}, arrived = false,
        pilotSpawned1 = false, pilotSpawned2 = false,
        portalReprogrammed = false, apcHeadingBack = false,
        apcCommandeered = false,
        scheduleLose1 = false, scheduleLose2 = false, scheduleLose3 = false,
        lost = false, won = false,
        secondCameraTime = NEVER, activateTime = NEVER, attackWaveTime = NEVER,
        apcTime = NEVER, apcPilotTime1 = NEVER, apcPilotTime2 = NEVER,
        apcGoBackTime = NEVER, sound3Time = NEVER, waveCount = 0,
        -- Nil handles/audio IDs represent native NULL, including unused waveHandle.
        pilotBoarding = false, -- only additional state: asynchronous stock GetIn
    }
end
local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Healthy(h)
    -- PORT FIX: native pointer assertions do not prevent release-build crashes
    -- after APC/pilot destruction. Never query or mutate a missing Lua handle.
    -- Missing objects count as zero health; normal health-based loss gates and
    -- all timer values remain unchanged. Empty vehicles still count as healthy.
    return Valid(h) and GetHealth(h) > 0.0
end
local function Touching(a, b)
    return Healthy(a) and Healthy(b) and IsTouching(a, b)
end
local function Team(h)
    if Valid(h) then return GetTeamNum(h) end
    return nil
end
local function Activate(inward)
    if Healthy(M.portal) then
        -- Native activatePortal(portal, false/true) combines these operations.
        if inward then PortalIn(M.portal) else PortalOut(M.portal) end
        ActivatePortal(M.portal)
    end
end
local function Done(sound)
    return sound == nil or sound == 0 or IsAudioMessageDone(sound)
end

function Start()
    M = NewState()
    M.recycler = GetHandle("recycler")
    M.portal = GetHandle("portal")
    M.command = GetHandle("command")
    M.factory = GetHandle("factory")
    M.navPortal = GetHandle("nav_portal")
    M.navBase = GetHandle("nav_base")
    if Valid(M.navPortal) then SetObjectiveName(M.navPortal, "Portal") end
    if Valid(M.navBase) then SetObjectiveName(M.navBase, "Black Dog Base") end
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()
    if not M.startDone then
        SetScrap(1, 100)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        -- #ifdef TEST_PORTAL / SetPerceivedTeam(user, 2); / #endif
        if TEST_PORTAL and Valid(M.user) then SetPerceivedTeam(M.user, 2) end
    end

    if not M.cameraComplete[0] then
        if not M.cameraReady[0] then
            M.cameraReady[0] = true
            CameraReady()
            M.introSound = AudioMessage("bd08001.wav")
        end
        if not M.arrived and Valid(M.user) then
            M.arrived = CameraPath("path_camera_intro", 800, 1500, M.user)
        end
        local seqDone = M.arrived and Done(M.introSound)
        if CameraCancelled() then
            seqDone = true
            if M.introSound ~= nil and M.introSound ~= 0 then
                StopAudioMessage(M.introSound)
            end
        end
        if seqDone then
            M.arrived = false
            CameraFinish()
            M.cameraComplete[0] = true
            M.secondCameraTime = now + 25.0
        end
    end

    if M.secondCameraTime < now and not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            M.cameraReady[1] = true
            CameraReady()
            M.intro2Sound = AudioMessage("bd08002.wav")
            ClearObjectives()
            AddObjective("bd08001.otf", "white")
            M.activateTime = now + 0.5
            -- #ifndef TEST_PORTAL: +90.0f; #else: +15.0f; #endif
            M.apcTime = now + (TEST_PORTAL and 15.0 or 90.0)
        end
        if Valid(M.portal) then
            M.arrived = CameraPath("path_portalcam", 4000, 1000, M.portal)
        end
        if M.arrived or CameraCancelled() or not Valid(M.portal) then
            CameraFinish()
            M.cameraComplete[1] = true
            --StopAudioMessage(M.intro2Sound);
            --M.sound3Time = GetTime() + 5.0;
        end
    end

    if M.activateTime < now then
        Activate(false)
        if Healthy(M.portal) and isPortalActive(M.portal) then
            M.attackWaveTime = now + 1.0
            M.activateTime = NEVER
        end
    end
    -- #ifndef TEST_PORTAL: entire attack-wave block disabled in debug mode.
    if not TEST_PORTAL and M.attackWaveTime < now then
        if M.apcTime < now + 45.0 then
            -- temporarily disable the attack wave so that the apc can arrive
            M.attackWaveTime = NEVER
        else
            local h
            if Healthy(M.portal) then
                h = BuildObjectAtPortal(attackers[math.random(0, 9) + 1], 2, M.portal)
            end
            local path = math.random(0, 99) < 50 and "attack_path1" or "attack_path2"
            if Valid(h) then Goto(h, path, 1) end
            M.waveCount = M.waveCount + 1
            if M.waveCount < 4 then
                M.attackWaveTime = now + 4.0
            else
                M.waveCount = 0
                M.attackWaveTime = now + 30.0
            end
        end
    end

    if M.apcTime < now then
        M.apcTime = NEVER
        if Healthy(M.portal) then M.apc = BuildObjectAtPortal("cvapc", 2, M.portal) end
        -- PORT FIX: native _ASSERTMSG0(apc != NULL, "Failed to create APC")
        -- cannot recover from a failed build. Use the existing APC-loss outcome
        -- rather than continuing with an impossible objective/invalid handle.
        if Healthy(M.apc) then
            Goto(M.apc, "portal_out", 1)
            M.attackWaveTime = now + 30.0
            M.apcPilotTime1 = now + 20.0
            M.sound3Time = now + 1.0
        elseif not M.lost and not M.won then
            M.scheduleLose3 = true
        end
    end

    if M.sound3Time < now then
        M.sound3Time = NEVER
        AudioMessage("bd08003.wav")
    end
    if M.apcPilotTime1 < now then
        M.apcPilotTime1 = NEVER
        if Healthy(M.apc) then
            Stop(M.apc, 1)
            -- Native: o->curPilot = 0;
            -- PORT ADAPTATION: RemovePilot is the stock clean removal API.
            -- It also detaches the now-idle AI, so the later handoff uses GetIn
            -- to restore both the pilot and AI. No HopOut/ejection or extra pilot.
            RemovePilot(M.apc)
            M.pilot = BuildObject("cspilo", 2, M.apc) --PilotGetOut(apc);
            SetPerceivedTeam(M.apc, 0)
            if Healthy(M.pilot) and Healthy(M.portal) then
                Retreat(M.pilot, M.portal, 1)
            end
            M.pilotSpawned1 = true
            ClearObjectives()
            AddObjective("bd08001.otf", "white")
            AddObjective("bd08002.otf", "white")
            SetObjectiveOn(M.apc)
        end
    end

    if M.pilotSpawned1 then
        if Touching(M.pilot, M.portal) then
            RemoveObject(M.pilot)
            M.pilotSpawned1 = false
            -- #ifndef TEST_PORTAL: +9*60.0; #else: +15.0f; #endif
            M.apcPilotTime2 = now + (TEST_PORTAL and 15.0 or 9 * 60.0)
        elseif not Healthy(M.pilot) then
            -- pilot killed before reprogramming the portal
            M.scheduleLose2 = true
            M.pilotSpawned1 = false
        end
    end

    if M.apcPilotTime2 < now then
        M.apcPilotTime2 = NEVER
        M.pilot = BuildObject("cspilo", 2, "spawn_pilot")
        if Healthy(M.apc) then RemovePilot(M.apc) end
        if Healthy(M.pilot) and Healthy(M.apc) then Retreat(M.pilot, M.apc, 1) end
        M.pilotSpawned2 = true
        M.portalReprogrammed = true
        AudioMessage("bd08004.wav")
        if Healthy(M.portal) then DeactivatePortal(M.portal) end
        ClearObjectives()
        AddObjective("bd08002.otf", "green")
        AddObjective("bd08003.otf", "white")
        M.attackWaveTime = NEVER
    end

    if M.pilotSpawned2 and Team(M.apc) == 1 then
        M.pilotSpawned2 = false
        if Healthy(M.pilot) and Healthy(M.apc) then Attack(M.pilot, M.apc) end
    end
    if M.pilotSpawned2 and not Healthy(M.pilot) then
        M.pilot = nil
        M.pilotSpawned2 = false
    end
    if M.pilotSpawned2 and Touching(M.pilot, M.apc) then
        M.pilotSpawned2 = false
        M.apcGoBackTime = now + 25.0
        if GetPilotClass(M.apc) == nil or GetPilotClass(M.apc) == "" then
            -- Native: AiProcess::Attach(this, o); o->curPilot = *(PrjID*)"cspilo";
            -- RemoveObject(pilot); pilot = NULL; SetPerceivedTeam(apc, 2);
            -- PORT ADAPTATION: GetIn performs real boarding and reattaches AI,
            -- which SetPilotClass alone cannot do. Keep the 25-second timer
            -- anchored to contact, not boarding completion. The engine consumes
            -- the pilot; removing it here would cancel the boarding command.
            GetIn(M.pilot, M.apc, 1)
            M.pilotBoarding = true
        elseif Healthy(M.user) then
            Attack(M.pilot, M.user)
        end
    end
    if M.pilotBoarding then
        if Team(M.apc) == 1 then
            -- A capture between command and boarding must not be overwritten.
            M.pilotBoarding = false
            if Healthy(M.pilot) and Healthy(M.apc) then Attack(M.pilot, M.apc) end
        elseif not Valid(M.pilot) and Healthy(M.apc) and IsAliveAndPilot(M.apc) then
            M.pilotBoarding = false
            M.pilot = nil
            SetPerceivedTeam(M.apc, 2)
        elseif not Healthy(M.pilot) or not Healthy(M.apc) then
            M.pilotBoarding = false
        end
    end

    if M.apcGoBackTime < now then
        M.apcGoBackTime = NEVER
        if Healthy(M.apc) and IsAliveAndPilot(M.apc) then
            M.apcHeadingBack = true
            Activate(true)
            Retreat(M.apc, "portal_in", 1)
        end
    end
    if M.apcHeadingBack and Team(M.apc) == 1 then M.apcHeadingBack = false end
    if M.apcHeadingBack and not M.lost and not M.won then
        if Touching(M.apc, M.portal) then
            RemoveObject(M.apc)
            M.apc = nil
            M.apcHeadingBack = false
            -- the player has lost
            M.scheduleLose2 = true
        end
    end

    -- have we lost any significant units?
    if (not Healthy(M.recycler) or
        --GetHealth(factory) <= 0.0f ||
        not Healthy(M.command)) and not M.lost and not M.won then
        M.scheduleLose2 = true
    elseif M.apc ~= nil and not Healthy(M.apc) and not M.lost and not M.won then
        M.apc = nil
        M.scheduleLose3 = true
    end
    if M.scheduleLose2 then
        M.scheduleLose2 = false
        M.loseSound2 = AudioMessage("bd08006.wav")
        M.lost = true
    end
    if M.loseSound2 ~= nil and Done(M.loseSound2) then
        M.loseSound2 = nil
        FailMission(now + 1.0, "bd08lsea.des")
    end
    if M.scheduleLose3 then
        M.scheduleLose3 = false
        M.loseSound3 = AudioMessage("bd08006.wav")
        M.lost = true
    end
    if M.loseSound3 ~= nil and Done(M.loseSound3) then
        M.loseSound3 = nil
        FailMission(now + 1.0, "bd08lseb.des")
    end
    if M.apc ~= nil and not M.apcCommandeered then
        if Team(M.apc) == 1 then M.apcCommandeered = true end
    end
    -- SOURCE QUIRK PRESERVED: capture is a historical latch, not a continuous
    -- ownership test. Do not add a base-return requirement or move this gate.
    if M.apcCommandeered and M.portalReprogrammed and M.winSound == nil
        and not M.won and not M.lost then
        M.won = true
        M.winSound = AudioMessage("bd08007.wav")
    end
    if M.winSound ~= nil and Done(M.winSound) then
        M.winSound = nil
        SucceedMission(now + 1.0, "bd08win.des")
    end
    -- has the portal been destroyed? Source checks this AFTER the victory gate.
    if not Healthy(M.portal) and not M.won and not M.lost then
        M.lost = true
        FailMission(now + 1.0, "bd08lsec.des")
    end
end

function Save()
    return M
end
function Load(state)
    -- LuaMission serializes tables and remaps handles. Native ConvertHandle /
    -- PostLoad is unnecessary; never rerun Setup or replay startup resources.
    M = state
end
