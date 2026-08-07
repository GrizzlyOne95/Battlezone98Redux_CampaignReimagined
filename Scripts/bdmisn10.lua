-- Black Dog mission 10
-- Source-faithful Lua conversion of BlackDog10Mission.cpp.
-- The original mission has no AIP: its defenders are proximity-triggered
-- ambushes, followed by the APC/recycler extraction cinematics.
-- Source terminology: objective one iterates the map-labelled "destroy" units.

local M = {
    startDone = false,
    objective1Complete = false,
    cameraReady = { false, false, false },
    cameraComplete = { false, false, false },
    arrived = false,
    apcSpawned = false,
    recyclerSpawned = false,
    defencesSpawned = { false, false, false, false },
    patrolsSpawned = { false, false, false, false },
    lost = false,
    won = false,

    navDelay = 999999.9,
    apcDelay = 999999.9,
    apcCameraTimeout = 999999.9,
    cameraTime = 999999.9,

    user = nil,
    destroy = {},
    apc = nil,
    recycler = nil,
    introSound = nil,
    navSound = nil,
    winSound = nil,
}

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

local function checkAmbush(distance, spawnSpot, spawned, units)
    if spawned then return true end

    local nearest = GetNearestUnitOnTeam(spawnSpot, 0, 1)
    if not IsAlive(nearest) or GetDistance(nearest, spawnSpot) >= distance then
        return false
    end

    for _, odf in ipairs(units) do
        local h = BuildObject(odf, 2, spawnSpot)
        Hunt(h, 1)
    end
    return true
end

function Save()
    return M
end

function Load(...)
    if select('#', ...) > 0 then M = ... end
end

function Start()
    M.destroy = {
        GetHandle("destroy_1"),
        GetHandle("destroy_2"),
        GetHandle("destroy_3"),
        GetHandle("destroy_4"),
        GetHandle("destroy_5"),
        GetHandle("destroy_6"),
    }
end

function AddObject(h)
end

function DeleteObject(h)
end

function Update()
    M.user = GetPlayerHandle()

    if not M.startDone then
        SetScrap(1, 100)
        SetScrap(2, 0)
        SetPilot(1, 10)
        ClearObjectives()
        AddObjective("bd10001.otf", "WHITE")
        M.startDone = true
    end

    for i = 1, 4 do
        M.defencesSpawned[i] = checkAmbush(
            400.0, defences[i], M.defencesSpawned[i], defenceUnits[i])
        M.patrolsSpawned[i] = checkAmbush(
            400.0, patrols[i], M.patrolsSpawned[i], patrolUnits[i])
    end

    if not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            CameraReady()
            M.introSound = AudioMessage("bd10001.wav")
            M.cameraReady[1] = true
        end

        if not M.arrived then
            M.arrived = CameraPath("camera_start", 3000, 2000, M.destroy[4])
        end
        if M.arrived and IsAudioMessageDone(M.introSound) and M.cameraTime == 999999.9 then
            M.cameraTime = GetTime() + 2.0
        end

        local sequenceDone = M.cameraTime < GetTime()
        if CameraCancelled() then
            sequenceDone = true
            StopAudioMessage(M.introSound)
        end
        if sequenceDone then
            CameraFinish()
            M.cameraComplete[1] = true
        end
    end

    if not M.objective1Complete then
        M.objective1Complete = true
        for _, h in ipairs(M.destroy) do
            if GetHealth(h) > 0.0 then
                M.objective1Complete = false
                break
            end
        end
        if M.objective1Complete then
            M.navDelay = GetTime() + 10.0
        end
    end

    if M.objective1Complete and M.navDelay < GetTime() then
        M.navDelay = 999999.9
        BuildObject("apcamr", 1, "navcam_end")
        M.navSound = AudioMessage("bd10002.wav")
    end

    if M.objective1Complete and M.navSound and IsAudioMessageDone(M.navSound) then
        M.navSound = nil
        M.apcDelay = GetTime() + 5.0
    end

    if M.objective1Complete and M.apcDelay < GetTime() then
        M.apcDelay = 999999.9
        M.apcSpawned = true
        M.apc = BuildObject("bvapc", 1, "apc")
        Goto(M.apc, "apc_path", 1)
        BuildObject("cbport", 0, "portal")
    end

    if M.apcSpawned and not M.cameraComplete[2] then
        if not M.cameraReady[2] then
            CameraReady()
            M.cameraReady[2] = true
            M.apcCameraTimeout = GetTime() + 7.0
        end

        CameraPath("camera_apc", 30, 200, M.apc)
        if M.apcCameraTimeout < GetTime() or CameraCancelled() then
            CameraFinish()
            M.cameraComplete[2] = true
            M.apcCameraTimeout = 999999.9
        end
    end

    if M.cameraComplete[2] and not M.recyclerSpawned then
        M.recyclerSpawned = true
        M.recycler = BuildObject("bvrecy", 1, "recycler")
        Goto(M.recycler, "recycler_path", 1)

        for _ = 1, 6 do
            local escort = BuildObject("cvtnka", 1, "capture")
            SetIndependence(escort, 0)
            Follow(escort, M.recycler, 1)
        end
    end

    if M.recyclerSpawned and not M.cameraComplete[3] then
        if not M.cameraReady[3] then
            CameraReady()
            M.winSound = AudioMessage("bd10003.wav")
            M.cameraReady[3] = true
            M.arrived = false
            M.cameraTime = GetTime() + 10.0
        end

        if not M.arrived then
            M.arrived = CameraPath("camera_end", 30, 200, M.recycler)
        end

        local sequenceDone = IsAudioMessageDone(M.winSound) and M.cameraTime < GetTime()
        if CameraCancelled() then
            sequenceDone = true
            StopAudioMessage(M.winSound)
        end
        if sequenceDone then
            -- The C++ intentionally leaves the final camera active while the
            -- success screen fades in; CameraFinish() was commented out.
            M.cameraComplete[3] = true
            SucceedMission(GetTime() + 1.0, "bd10win.des")
        end
    end
end
