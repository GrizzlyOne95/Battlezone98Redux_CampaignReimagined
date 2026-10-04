-- Chinese04Mission.cpp -> stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Chinese04Mission.cpp
-- Source blob: 11fb5b1a3203fd8a5e864ee30578624eb7788827.
-- All native comments/cut code and serialization declarations are preserved in
-- References/Chinese04Source/Chinese04Mission.cpp. No EXU/helper dependency.
-- Attach to the original ch04 map; its labels, paths and assets are required.

local MS_STARTUP, MS_STARTSCENE, MS_PLAYSOUND7, MS_NEARNAVS = 1, 2, 3, 4
local MS_WAITFORID, WS_WAITFORSOUND2, MS_WAITFORALARM, MS_CAMERAALARM = 6, 7, 8, 9
local MS_NEARSILO, MS_INSPECTSILO, MS_WAITFORSOUND2, MS_WAITFORSOUND3 = 10, 11, 12, 13
local MS_WAITFORSOUND8, MS_WAITFORPORTAL, MS_CAMERAEND, MS_END = 14, 15, 16, 100

local function NewState()
    return {
        lost = false, target_silo_inspected = false, endNear = false,
        insideCloakedShip = true,
        stateTimer = 99999.0, portalTimeOut = 99999.0,
        missionState = MS_STARTUP, uptonavpoint = 0, attackedAlready = 0,
        navPoints = {}, empty = {}, turret = {},
        attackuser1 = {}, attackuser2 = {}, attackuser3 = {},
        attackuser4 = {}, attackuser5 = {}, attackuser6 = {},
        -- Null native handles/audio IDs are nil: user, olduser, target_silo,
        -- portal, cca_factory, factory, fakePlayer, soundHandle, coreFailSound.
        -- lost/fakePlayer and the unused 45-second stateTimer are retained.
    }
end

local M = NewState()
local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Distance(from, to)
    -- PORT FIX: missing/deleted handles must not become zero-distance triggers
    -- or select a path overload. Valid-map radii and event order are unchanged.
    if not Valid(from) or (type(to) ~= "string" and not Valid(to)) then
        return math.huge
    end
    return GetDistance(from, to)
end
local function RestoreHealth(h)
    -- SOURCE BUG FIX: native Execute dereferences factory/portal/player without
    -- a null check. Skip absent objects instead of crashing; surviving objects
    -- receive exactly the source's per-frame heal, with no respawns/new gates.
    if Valid(h) then
        local current, maximum = GetCurHealth(h), GetMaxHealth(h)
        if current ~= maximum then AddHealth(h, maximum - current) end
    end
end
local function Strike(h)
    if Valid(h) and Valid(M.user) then Attack(h, M.user) end
end
local function Remove(h)
    if Valid(h) then RemoveObject(h) end
end
local function Target(h)
    if Valid(h) then SetUserTarget(h) end
end
local function Perceived(team)
    if Valid(M.user) then SetPerceivedTeam(M.user, team) end
end
local function Cloaked()
    return Valid(M.user) and IsCloaked(M.user)
end
local function DisableCloaking(h)
    if Valid(h) then EnableCloaking(h, false) end
end
local function Done(message)
    -- Native zero audio IDs mean there is no message to wait for. Lua audio
    -- handles are userdata/nil; never pass the native numeric sentinel.
    return message == nil or IsAudioMessageDone(message)
end
local function InspectSilo()
    -- API ADAPTATION: native IsInfo accepts a handle; stock Lua IsInfo accepts
    -- an ODF name. Query the actual map object's ODF, not a guessed silo class.
    return Valid(M.target_silo) and IsInfo(GetOdf(M.target_silo))
end
local function ResetObjectives()
    ClearObjectives()
    if M.missionState >= MS_WAITFORID then
        AddObjective("ch04001.otf", "green")
    elseif M.missionState >= MS_NEARNAVS then
        AddObjective("ch04001.otf", "white")
    end
    if M.target_silo_inspected then
        AddObjective("ch04002.otf", "green")
    elseif M.missionState >= MS_WAITFORID then
        AddObjective("ch04002.otf", "white")
    end
    if M.missionState >= MS_WAITFORSOUND2 then
        AddObjective("ch04003.otf", "white")
    end
end
local function UnitsAttackPlayer()
    if M.user == M.olduser then return end
    for i = 0, 24 do
        if Valid(M.attackuser1[i]) and IsAlive(M.attackuser1[i]) then Strike(M.attackuser1[i]) end
    end
    for i = 0, 3 do
        if Valid(M.attackuser2[i]) and IsAlive(M.attackuser2[i]) then Strike(M.attackuser2[i]) end
    end
    if M.missionState >= MS_WAITFORSOUND3 then
        for i = 0, 3 do
            if Valid(M.attackuser3[i]) and IsAlive(M.attackuser3[i]) then Strike(M.attackuser3[i]) end
            if Valid(M.attackuser4[i]) and IsAlive(M.attackuser4[i]) then Strike(M.attackuser4[i]) end
            if Valid(M.attackuser5[i]) and IsAlive(M.attackuser5[i]) then Strike(M.attackuser5[i]) end
        end
        for i = 0, 5 do
            if Valid(M.attackuser6[i]) and IsAlive(M.attackuser6[i]) then Strike(M.attackuser6[i]) end
        end
    end
end
local function AttackBaseUnits()
    M.attackedAlready = 1
    Perceived(1)
    for i = 0, 24 do M.attackuser1[i] = M.empty[i]; Strike(M.attackuser1[i]) end
    for i = 0, 3 do M.attackuser2[i] = M.turret[i]; Strike(M.attackuser2[i]) end
end
local function CoreFailure()
    if M.attackedAlready ~= 0 then
        if M.coreFailSound ~= nil then
            if Done(M.coreFailSound) then M.coreFailSound = nil end
        elseif Cloaked() then
            M.coreFailSound = AudioMessage("ch04002.wav")
            Decloak(M.user)
            DisableCloaking(M.user)
        end
    end
end
local function SpawnPilots(indices)
    for _, n in ipairs(indices) do
        local h = BuildObject("sspilo", 2, "pilot_" .. n)
        if Valid(h) and Valid(M.empty[n - 1]) then Retreat(h, M.empty[n - 1]) end
    end
end

function Start()
    M = NewState()
    M.target_silo = GetHandle("target_silo")
    M.navPoints[0] = GetHandle("nav_1")
    M.cca_factory = GetHandle("cca_factory")
    M.factory = GetHandle("factory")
    M.portal = GetHandle("portal")
    for i = 0, 24 do M.empty[i] = GetHandle("empty_" .. (i + 1)) end
    for i = 0, 3 do M.turret[i] = GetHandle("turret_" .. (i + 1)) end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    RestoreHealth(M.factory)
    RestoreHealth(M.portal)
    if M.missionState == MS_CAMERAEND then RestoreHealth(M.user) end
    if M.attackedAlready ~= 0 and M.missionState <= MS_WAITFORPORTAL then UnitsAttackPlayer() end
    if M.missionState ~= MS_STARTUP and M.user ~= M.olduser then
        if M.insideCloakedShip then
            if Valid(M.olduser) then Decloak(M.olduser) end
            DisableCloaking(M.olduser)
        end
        M.insideCloakedShip = false
    end

    -- Deliberate native fall-through: startup executes the first camera frame
    -- immediately; WAITFORALARM executes CAMERAALARM on the spawning frame.
    if M.missionState == MS_STARTUP then
        SetScrap(1, 0)
        SetPilot(1, 10)
        M.olduser = M.user
        M.missionState = MS_STARTSCENE
        M.soundHandle = AudioMessage("ch04001.wav")
        CameraReady()
    end
    if M.missionState == MS_WAITFORALARM and M.stateTimer < GetTime() then
        SpawnPilots({1, 2, 3, 4, 5, 6, 11, 14, 17, 25})
        M.missionState = MS_CAMERAALARM
        M.stateTimer = GetTime() + 5
        CameraReady()
    end

    if M.missionState == MS_STARTSCENE then
        local arrived = CameraPath("camera_start", 1000, 1200, M.target_silo)
        if arrived or CameraCancelled() then
            if M.soundHandle ~= nil then StopAudioMessage(M.soundHandle) end
            CameraFinish()
            M.missionState = MS_PLAYSOUND7
            M.stateTimer = GetTime() + 5
        end
    elseif M.missionState == MS_PLAYSOUND7 then
        if M.stateTimer < GetTime() then
            AudioMessage("ch04007.wav")
            StartCockpitTimer(2 * 60 + 10)
            M.missionState = MS_NEARNAVS
            M.uptonavpoint = 0
            ResetObjectives()
            Target(M.navPoints[0])
        end
    elseif M.missionState == MS_NEARNAVS then
        if GetCockpitTimer() < 1 then
            AudioMessage("ch04006.wav")
            FailMission(GetTime() + 2, "ch04lsea.des")
            M.missionState = MS_END
        elseif Distance(M.user, M.navPoints[M.uptonavpoint]) < 50 then
            if M.uptonavpoint >= 5 then
                for i = 0, M.uptonavpoint do Remove(M.navPoints[i]) end
                HideCockpitTimer()
                M.missionState = MS_WAITFORID
                ResetObjectives()
                -- Cut SetUserTarget(target_silo)/nav_silo beacon: source archive.
                Perceived(2)
                if Valid(M.target_silo) then SetObjectiveOn(M.target_silo) end
            else
                M.uptonavpoint = M.uptonavpoint + 1
                M.navPoints[M.uptonavpoint] = BuildObject("apcamr", 1, "nav_" .. (M.uptonavpoint + 1))
                if M.uptonavpoint == 5 and Valid(M.navPoints[5]) then
                    SetObjectiveName(M.navPoints[5], "Pit Entrance") -- native SetName alias
                end
                Target(M.navPoints[M.uptonavpoint])
            end
        end
    elseif M.missionState == MS_WAITFORID then
        M.target_silo_inspected = InspectSilo()
        -- Disabled cloak/distance<=400 detection and ch04002: source archive.
        if Distance(M.user, "trigger_1") <= 70 or M.target_silo_inspected then
            M.soundHandle = nil
            M.missionState = WS_WAITFORSOUND2
        end
    elseif M.missionState == WS_WAITFORSOUND2 then
        if Done(M.soundHandle) then
            -- soundHandle = AudioMessage("ch04003.wav"); -- disabled in source
            M.stateTimer = GetTime() + 1
            M.missionState = MS_WAITFORALARM
        end
    elseif M.missionState == MS_CAMERAALARM then
        CameraPath("camera_alarm", 2000, 0, M.cca_factory)
        -- Disabled alarm audio and pilots at empty_15/16/18..24: source archive.
        if CameraCancelled() or M.stateTimer < GetTime() then
            CameraFinish()
            SpawnPilots({7, 8, 9, 10, 12, 13})
            if not Cloaked() then AttackBaseUnits() else M.attackedAlready = 0 end
            M.missionState = MS_NEARSILO
        end
    elseif M.missionState == MS_NEARSILO then
        -- Disabled delayed ch04003 audio: source archive.
        CoreFailure()
        if Distance(M.user, M.target_silo) <= 200 then
            local h = BuildObject("svfigh", 2, "fighter_1")
            if Valid(h) then Goto(h, "figh1_path") end
            h = BuildObject("svfigh", 2, "fighter_2")
            if Valid(h) then Goto(h, "figh2_path") end
            M.missionState = MS_INSPECTSILO
        end
    elseif M.missionState == MS_INSPECTSILO then
        CoreFailure()
        if not M.target_silo_inspected then M.target_silo_inspected = InspectSilo() end
        if M.target_silo_inspected then
            M.soundHandle = nil
            if Valid(M.target_silo) then SetObjectiveOff(M.target_silo) end
            M.missionState = MS_WAITFORSOUND2
            M.stateTimer = GetTime() + 45 -- intentionally unused in source
            ResetObjectives()
            if M.attackedAlready == 0 then
                if Cloaked() then
                    M.soundHandle = AudioMessage("ch04002.wav")
                    Decloak(M.user)
                end
                DisableCloaking(M.user)
                AttackBaseUnits()
            end
        end
    elseif M.missionState == MS_WAITFORSOUND2 then
        if Done(M.soundHandle) then
            M.soundHandle = AudioMessage("ch04003.wav")
            for i = 0, 3 do
                M.attackuser3[i] = BuildObject("svfigha", 2, "chase_1"); Strike(M.attackuser3[i])
                M.attackuser4[i] = BuildObject("svtanka", 2, "chase_2"); Strike(M.attackuser4[i])
                M.attackuser5[i] = BuildObject("svfigha", 2, "chase_3"); Strike(M.attackuser5[i])
            end
            -- Source gives these six no initial Attack command. They retarget
            -- only on a later player-handle change; preserve that behavior.
            for i = 0, 5 do M.attackuser6[i] = BuildObject("svfigh", 2, "portal_units") end
            -- Native activatePortal(portal, TRUE) selects inward direction.
            if Valid(M.portal) then PortalIn(M.portal) end
            M.missionState = MS_WAITFORSOUND3
        end
    elseif M.missionState == MS_WAITFORSOUND3 then
        if Done(M.soundHandle) then
            M.soundHandle = AudioMessage("ch04008.wav")
            M.missionState = MS_WAITFORSOUND8
        end
    elseif M.missionState == MS_WAITFORSOUND8 then
        if Done(M.soundHandle) then
            M.portalTimeOut = GetTime() + 60 * 2 + 15
            -- RemoveObject(navPoints[0]); -- disabled in source
            M.navPoints[0] = BuildObject("apcamr", 1, "nav_base")
            Target(M.navPoints[0])
            M.missionState = MS_WAITFORPORTAL
        end
    elseif M.missionState == MS_WAITFORPORTAL then
        if M.portalTimeOut < GetTime() then
            FailMission(GetTime() + 2, "ch04lseb.des")
            M.missionState = MS_END
        elseif Distance(M.user, M.portal) < 100 then
            Remove(M.navPoints[0])
            HideCockpitTimer()
            -- Cut fakePlayer creation/health copy/Goto: source archive.
            Perceived(2)
            RestoreHealth(M.user)
            if Valid(M.user) then Hide(M.user) end
            M.missionState = MS_CAMERAEND
            CameraReady()
            M.endNear = false
            M.stateTimer = 0
        end
    elseif M.missionState == MS_CAMERAEND then
        -- PORT ADAPTATION: native 'arrived' is assigned only on the moving
        -- branch and short-circuiting prevents its use on the stationary one.
        -- Initialize false in Lua; camera arrival, the 2-second hold and
        -- victory timing are unchanged.
        local arrived = false
        if not M.endNear then
            arrived = CameraPathDir("auto_end", 500, 3000)
        else
            CameraPathDir("auto_end", 500, 0)
        end
        -- Cut GetCurrentCommand(fakePlayer) == CMD_NONE check: source archive.
        if not M.endNear and arrived then
            M.endNear = true
            M.stateTimer = GetTime() + 2
        end
        if M.endNear and M.stateTimer < GetTime() then
            if Valid(M.portal) then DeactivatePortal(M.portal) end
            M.missionState = MS_END
            SucceedMission(GetTime() + 4, "ch04win.des")
        end
        -- Native end camera intentionally has no cancellation/CameraFinish.
    end
    if M.user ~= M.olduser then M.olduser = M.user end
end

function Save()
    return M
end
function Load(state)
    -- LuaMission serializes tables and engine handles; do not rerun Start or
    -- replay spawns/cameras/audio on load. Zero-based arrays remain intact.
    M = state
end
