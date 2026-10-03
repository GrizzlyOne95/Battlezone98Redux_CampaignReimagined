-- Faithful BlackDog10Mission port for stock BZR / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog10Mission.cpp
-- Source blob: a1b4f90298b15f8c622f920e90ab5603c672b72e.
-- Full native source, including declarations, comments and serialization:
-- References/BlackDog10Source/BlackDog10Mission.cpp.
-- No EXU/OpenShim or campaign helper is required. C++ array indexes are
-- translated to Lua's 1-based indexes; commands, timings and order are retained.

local DISABLED_TIME = 999999.9
local defences = { "defend_a", "defend_b", "defend_c", "defend_d" }
local defenceUnits = {
    { "cvtnk", "cvtnk", "cvltnk", "cvltnk", "cvfigh", "cvfigh" },
    { "cvfigh", "cvfigh", "cvfigh", "cvwalk", "cvhtnk", "cvtnk" },
    { "cvtnk", "cvtnk", "cvtnk", "cvfigh", "cvfigh", "cvwalk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk", "cvtnk", "cvtnk", "cvwalk" },
}
local patrols = { "patrol_a", "patrol_b", "patrol_c", "patrol_d" }
local patrolUnits = {
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvtnk" },
}

local function NewState()
    -- Native Load initializes all members, including Setup's untouched flags.
    -- Handles and audio messages use nil instead of native NULL/0.
    return {
        startDone = false, objective1Complete = false,
        cameraReady = { false, false, false },
        cameraComplete = { false, false, false }, arrived = false,
        apcSpawned = false, recyclerSpawned = false,
        defencesSpawned = { false, false, false, false },
        patrolsSpawned = { false, false, false, false },
        lost = false, won = false, -- unused in source; no new defeat/win gates
        navDelay = DISABLED_TIME, apcDelay = DISABLED_TIME,
        apcCameraTimeout = DISABLED_TIME, cameraTime = DISABLED_TIME,
        destroy = {},
    }
end

local M = NewState()

function Start()
    -- setup handles; one-shot resources/objectives still run in first Update.
    for i = 1, 6 do
        M.destroy[i] = GetHandle("destroy_" .. i)
    end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

local function checkAmbush(distance, spawn_spot, spawned, units)
    -- if we're already spawned, then leave
    if spawned then return true end
    -- Path overload: path, point, team (same order as the native call).
    local h = GetNearestUnitOnTeam(spawn_spot, 0, 1)
    if h == nil or h == 0 then return false end
    -- is the closest unit close enough?
    if GetDistance(h, spawn_spot, 0) < distance then
        -- yep, spawn the units (the native NULL terminator becomes table end).
        for i = 1, #units do
            local unit = BuildObject(units[i], 2, spawn_spot)
            Hunt(unit)
        end
        return true
    end
    return false
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    if not M.startDone then
        SetScrap(1, 100) -- we start with 100 scrap
        SetScrap(2, 0) -- enemy starts with 0 scrap
        SetPilot(1, 10)
        -- setup the initial objectives
        ClearObjectives()
        AddObjective("bd10001.otf", "white")
        -- don't do this part after the first shot
        M.startDone = true
    end

    -- should we spawn the defences?
    for i = 1, 4 do
        M.defencesSpawned[i] = checkAmbush(400.0, defences[i],
            M.defencesSpawned[i], defenceUnits[i])
    end
    -- how about the patrols?
    for i = 1, 4 do
        M.patrolsSpawned[i] = checkAmbush(400.0, patrols[i],
            M.patrolsSpawned[i], patrolUnits[i])
    end

    if not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.introSound = AudioMessage("bd10001.wav")
            M.cameraReady[1] = true
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("camera_start", 3000, 2000, M.destroy[4])
        end
        if M.arrived and IsAudioMessageDone(M.introSound)
            and M.cameraTime == DISABLED_TIME then
            M.cameraTime = GetTime() + 2.0
        end
        if M.cameraTime < GetTime() then seqDone = true end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.introSound)
        end
        if seqDone then
            CameraFinish()
            M.cameraComplete[1] = true
        end
    end

    if not M.objective1Complete then
        -- have we killed all the "destroy" units? assume we have
        M.objective1Complete = true
        for i = 1, 6 do
            local h = M.destroy[i]
            -- PORT FIX: Lua NULL is nil, not a native null Handle. Avoid passing
            -- missing/deleted objects to the health overload. They count as
            -- zero health as in native code; surviving targets still block
            -- completion, so valid-map gameplay and the six-target gate match.
            if h ~= nil and h ~= 0 and IsValid(h) and GetHealth(h) > 0.0 then
                -- nope, not yet
                M.objective1Complete = false
                break
            end
        end
        if M.objective1Complete then M.navDelay = GetTime() + 10.0 end
    end

    if M.objective1Complete and M.navDelay < GetTime() then
        M.navDelay = DISABLED_TIME
        -- spawn the nav beacon
        BuildObject("apcamr", 1, "navcam_end")
        -- start the sound
        M.navSound = AudioMessage("bd10002.wav")
    end
    if M.objective1Complete and M.navSound ~= nil
        and IsAudioMessageDone(M.navSound) then
        M.navSound = nil
        M.apcDelay = GetTime() + 5.0
    end
    if M.objective1Complete and M.apcDelay < GetTime() then
        M.apcDelay = DISABLED_TIME
        -- spawn the APC
        M.apcSpawned = true
        M.apc = BuildObject("bvapc", 1, "apc")
        Goto(M.apc, "apc_path", 1)
        -- spawn the portal
        BuildObject("cbport", 0, "portal")
    end

    if M.apcSpawned and not M.cameraComplete[2] then
        if not M.cameraReady[2] then
            -- get the camera ready
            CameraReady()
            M.cameraReady[2] = true
            M.apcCameraTimeout = GetTime() + 7.0
        end
        CameraPath("camera_apc", 30, 200, M.apc)
        if M.apcCameraTimeout < GetTime() or CameraCancelled() then
            CameraFinish()
            M.cameraComplete[2] = true
            M.apcCameraTimeout = DISABLED_TIME
        end
    end

    if M.cameraComplete[2] and not M.recyclerSpawned then
        M.recyclerSpawned = true
        M.recycler = BuildObject("bvrecy", 1, "recycler")
        Goto(M.recycler, "recycler_path", 1)
        for i = 1, 6 do
            local h = BuildObject("cvtnka", 1, "capture")
            SetIndependence(h, 0)
            Follow(h, M.recycler, 1)
        end
    end

    if M.recyclerSpawned and not M.cameraComplete[3] then
        if not M.cameraReady[3] then
            -- get the camera ready
            CameraReady()
            -- start the audio
            M.winSound = AudioMessage("bd10003.wav")
            M.cameraReady[3] = true
            M.arrived = false
            M.cameraTime = GetTime() + 10.0
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("camera_end", 30, 200, M.recycler)
        end
        if IsAudioMessageDone(M.winSound) and M.cameraTime < GetTime() then
            seqDone = true
        end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.winSound)
        end
        if seqDone then
            --CameraFinish();
            -- Source intentionally leaves the final camera active until the
            -- one-second victory transition; preserve this cut/disabled line.
            M.cameraComplete[3] = true
            SucceedMission(GetTime() + 1.0, "bd10win.des")
        end
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission serializes tables and engine handles/audio messages. Native
    -- PostLoad/ConvertHandle has no Lua equivalent to call. Do not rerun Setup,
    -- replay audio, reset timers or spawn already-created waves after loading.
    M = state
end
