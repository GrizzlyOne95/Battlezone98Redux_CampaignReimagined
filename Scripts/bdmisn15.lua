-- BlackDog15Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source blob: 7a7d7d440cbc1ec875abf02a97683349820d1814.
-- Complete original (including every comment, cut statement and native save code):
-- References/BlackDog15Source/BlackDog15Mission.cpp.
-- Single-player mission; no campaign helpers, EXU or OpenShim are required.

local DISABLED_TIME = 999999.9
-- //#define DO_EXPLOSION
-- Native #ifdef DO_EXPLOSION skips the battle for finale testing. Keep disabled.
local DO_EXPLOSION = false
-- Native useD3D & 4 selects xpltrso, otherwise xpltrsp. Stock Lua does not
-- expose useD3D; Redux uses hardware rendering, so retain the hardware effect.
-- The original software-renderer alternative is preserved: "xpltrsp".
local EXPLOSION_ODF = "xpltrso"

local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused source flags, retained for cut content
        doingCamera = false, doingExplosion = false, doingCountdown = false,
        sound10Played = false, allUnitsSpawned = false, wonLost = false,
        sound2Time = DISABLED_TIME, sound3Time = DISABLED_TIME,
        sound4Time = DISABLED_TIME, sound5Time = DISABLED_TIME,
        sound6Time = DISABLED_TIME, sound8Time = DISABLED_TIME,
        sound9Time = DISABLED_TIME, sound12Time = DISABLED_TIME,
        eastWaveTime = DISABLED_TIME,
        user = nil, lastUser = nil,
        intro1 = nil, -- GetHandle("chin_fighter_intro1");
        intro2 = nil, -- GetHandle("chin_fighter_intro2");
        units = {}, numUnits = 0,
        sound1 = nil, sound2 = nil, sound3 = nil, sound4 = nil,
        sound7 = nil, sound11 = nil, sound12 = nil,
        finaleTarget = nil, -- stock camera adapter, not one of the enemy units
    }
end
local M = NewState()

function Start()
    -- Setup defaults are established above; first Update runs SOE #1.
end
function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end
function Save() return M end
function Load(state)
    -- LuaMission restores saved handles/audio IDs; do not replay Setup.
    M = state
end

local function HasMessage(id) return id ~= nil and id ~= 0 end
local function Alive(h) return h ~= nil and h ~= 0 and IsAlive(h) end
local function Spawn(odf, direction)
    local h = BuildObject(odf, 2, "spawn_" .. direction .. "_wave")
    -- Native units[numUnits++] becomes a 1-based table plus an explicit count.
    -- Count even a failed spawn; the completion scan treats missing handles dead.
    M.numUnits = M.numUnits + 1
    M.units[M.numUnits] = h
    if h ~= nil and h ~= 0 and IsValid(h) then
        Goto(h, "path_" .. direction .. "_wave")
        SetObjectiveOn(h)
    end
end
local function Wave(direction, odfs)
    for i = 1, #odfs do Spawn(odfs[i], direction) end
end

local function FinaleCamera()
    -- Native CameraPathPath("camera_finale", 2400, 0, "spawn_explosion1")
    -- has no stock Lua binding; CameraPath requires an object handle. Use a
    -- hidden, neutral nav camera at the same path point as a stationary target.
    -- It is excluded from units, receives no marker/orders, and is made durable
    -- so the explosion cannot remove the camera target. No wave/escape gate
    -- depends on it. Runtime QA must verify camera alignment and hidden radar.
    if M.finaleTarget == nil or M.finaleTarget == 0 or not IsValid(M.finaleTarget) then
        M.finaleTarget = BuildObject("apcamr", 0, "spawn_explosion1")
        if M.finaleTarget ~= nil and M.finaleTarget ~= 0
            and IsValid(M.finaleTarget) then
            SetMaxHealth(M.finaleTarget, 1000000000)
            SetCurHealth(M.finaleTarget, 1000000000)
            Hide(M.finaleTarget)
        end
    end
    if M.finaleTarget ~= nil and M.finaleTarget ~= 0
        and IsValid(M.finaleTarget) then
        CameraPath("camera_finale", 2400, 0, M.finaleTarget)
    end
end

function Update(dt)
    assert(M.numUnits < 100, "BlackDog15 numUnits >= 100")
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()
    -- SOE #1
    if not M.startDone then
        SetScrap(1, 50)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        ClearObjectives()
        AddObjective("bd15001.otf", "white")
        M.sound1 = AudioMessage("bd15001.wav")
        if DO_EXPLOSION then M.sound7 = AudioMessage("bd15007.wav") end
    end

    if not DO_EXPLOSION then -- native #ifndef DO_EXPLOSION
        -- SOE #1
        if HasMessage(M.sound1) and IsAudioMessageDone(M.sound1) then
            M.sound1 = nil
            M.sound2Time = now + 20.0
        end
        if not M.sound10Played and M.user ~= nil and M.user ~= 0
            and IsValid(M.user) and GetDistance(M.user, "chin_launch") < 300.0 then
            M.sound10Played = true
            AudioMessage("bd15010.wav")
        end
        -- SOE #2
        if M.sound2Time < now then
            M.sound2Time = DISABLED_TIME
            M.sound2 = AudioMessage("bd15002.wav")
            Wave("west", {"cvfigh"})
        end
        if HasMessage(M.sound2) and IsAudioMessageDone(M.sound2) then
            M.sound2 = nil
            M.sound3Time = now + 40.0
        end
        -- SOE #3
        if M.sound3Time < now then
            M.sound3Time = DISABLED_TIME
            M.sound3 = AudioMessage("bd15003.wav")
            Wave("south", {"cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvtnk", "cvapc"})
        end
        if HasMessage(M.sound3) and IsAudioMessageDone(M.sound3) then
            M.sound3 = nil
            M.sound4Time = now + 120.0
        end
        -- SOE #4
        if M.sound4Time < now then
            M.sound4Time = DISABLED_TIME
            M.sound4 = AudioMessage("bd15004.wav")
            Wave("north", {"cvapc", "cvapc", "cvapc", "cvhtnk", "cvtnk", "cvtnk", "cvtnk"})
        end
        if HasMessage(M.sound4) and IsAudioMessageDone(M.sound4) then
            M.sound4 = nil
            M.sound5Time = now + 180.0
        end
        -- SOE #5
        if M.sound5Time < now then
            M.sound5Time = DISABLED_TIME
            AudioMessage("bd15005.wav")
            Wave("east", {"cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvltnk", "cvltnk"})
            M.eastWaveTime = now + 60.0
        end
        if M.eastWaveTime < now then
            M.eastWaveTime = DISABLED_TIME
            Wave("east", {"cvltnk", "cvltnk", "cvhraz", "cvhraz", "cvfigh", "cvfigh"})
            M.sound6Time = now + 180.0
        end
        -- SOE #6
        if M.sound6Time < now then
            M.sound6Time = DISABLED_TIME
            AudioMessage("bd15006.wav")
            Spawn("cvhtnk", "south")
            Wave("north", {"cvfigh", "cvfigh"})
            Wave("west", {"cvapc", "cvapc", "cvhaul"})
            M.allUnitsSpawned = true
        end
        -- SOE #7
        for i = 1, M.numUnits do
            if M.wonLost then break end
            -- PORT FIX: destroyed/absent handles must not trigger a launch-site
            -- breach from stale positions or an invalid distance result. Only
            -- living attackers can breach; all living-unit timing is unchanged.
            if Alive(M.units[i]) and GetDistance(M.units[i], "chin_launch") < 100.0 then
                M.sound11 = AudioMessage("bd15011.wav")
                M.wonLost = true
                break
            end
        end
        if HasMessage(M.sound11) and IsAudioMessageDone(M.sound11) then
            M.sound11 = nil
            M.sound12Time = now + 5.0
        end
        if M.sound12Time < now then
            M.sound12Time = DISABLED_TIME
            M.sound12 = AudioMessage("bd15012.wav")
        end
        if HasMessage(M.sound12) and IsAudioMessageDone(M.sound12) then
            M.sound12 = nil
            FailMission(now, "bd15lose.des")
        end
        -- SOE #8
        -- PORT FIX: native completion lacks !wonLost. Killing the last enemy
        -- after a breach can queue both victory and defeat. A latched breach
        -- now keeps the loss sequence exclusive; an unbreached defence follows
        -- exactly the same all-units-dead gate and escape countdown as before.
        if M.allUnitsSpawned and not M.objective1Complete and not M.wonLost then
            M.objective1Complete = true
            for i = 1, M.numUnits do
                if Alive(M.units[i]) then
                    M.objective1Complete = false
                    break
                end
            end
            if M.objective1Complete then
                M.sound7 = AudioMessage("bd15007.wav")
                ClearObjectives()
                AddObjective("bd15001.otf", "green")
                AddObjective("bd15002.otf", "white")
            end
        end
    end

    if HasMessage(M.sound7) and IsAudioMessageDone(M.sound7) then
        M.sound7 = nil
        M.doingCountdown = true
        StartCockpitTimer(30, 10, 5)
        --explTime = GetTime() + 32.0f;
        --cameraTime = GetTime() + 30.0f;
        --sound8Time = GetTime() + 32.0f;
    end
    -- SOE #9
    if M.doingCountdown and GetCockpitTimer() <= 0 and not M.doingExplosion then
        -- hopefully, if the player get's caught in the explosion,
        -- this success won't happen
        HideCockpitTimer()
        SucceedMission(now + 5.0, "bd15win.des")
        M.doingExplosion = true
        ColorFade(1.0, 0.5, 255, 255, 255)
        -- Lua MakeExplosion takes ODF first, unlike the native call.
        MakeExplosion(EXPLOSION_ODF, "spawn_explosion1")
    end
    if M.doingCountdown and GetCockpitTimer() <= 2 and not M.doingCamera then
        -- float dist = GetDistance(user, "spawn_explosion1"); (unused)
        --if (dist > 800.0f)
        --sound9 = AudioMessage("bd15013.wav");
        -- focus on the explosion
        CameraReady()
        M.doingCamera = true
    end
    -- PORT FIX: native submits its camera only once. Stock cinematic controls
    -- need updates every frame, also after Load. Reissue the stationary view
    -- without resetting CameraReady, moving its start time, or adding a skip.
    -- Source never calls CameraFinish; keep the view until mission transition.
    if M.doingCamera then FinaleCamera() end
end
