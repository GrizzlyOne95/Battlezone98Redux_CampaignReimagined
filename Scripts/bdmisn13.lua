-- Faithful BlackDog13Mission port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog13Mission.cpp
-- Source blob: ac9bdec108f18a8d5ad933353ebd612fc156da34.
-- Complete source, including comments/declarations/native serialization:
-- References/BlackDog13Source/BlackDog13Mission.cpp.
-- No executable commented-out code occurs in this source revision.
-- No EXU/OpenShim or campaign helper is required; stock Redux 2.1+ is needed
-- for IsRecycledByTeam. C++ array indices below are translated to 1-based Lua.

local DISABLED_TIME = 999999.9
local waveUnits = {
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvltnk", "cvltnk", "cvtnk" },
    { "cvrckt", "cvrckt", "cvltnk", "cvltnk", "cvtnk", "cvtnk" },
    { "cvhraz", "cvhraz", "cvhraz", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvfigh" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh", "cvhtnk", "cvhtnk" },
}
local defenderUnits = {
    { "cvfigh", "cvfigh", "cvltnk", "cvltnk" },
    { "cvltnk", "cvltnk", "cvltnk", "cvltnk" },
    { "cvfigh", "cvfigh", "cvrckt", "cvrckt" },
    { "cvtnk", "cvtnk", "cvltnk", "cvltnk" },
    { "cvfigh", "cvfigh", "cvfigh", "cvfigh" },
    { "cvhtnk", "cvhtnk", "cvfigh", "cvfigh" },
}

local function NewState()
    -- Native Load initializes all members before Setup, including unused ones.
    -- Handles/audio messages use nil in place of native NULL; unused handles
    -- user and lastUser and sound1/3/4/5 are initially absent table entries.
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        cameraReady = { false, false }, cameraComplete = { false, false },
        defendersSpawned = { false, false, false, false, false, false },
        recycled = { false, false, false, false, false, false },
        silosRecycled = false, recycleChecked = false, sound2Played = false,
        arrived = false, lost = false, won = false,
        wave1Time = DISABLED_TIME, wave2Time = DISABLED_TIME,
        wave3Time = DISABLED_TIME, wave4Time = DISABLED_TIME,
        silos = {}, scrapValue = 0, lastScrapValue = 0,
    }
end

local M = NewState()

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Health(h)
    -- PORT FIX: native absent-object health is zero. Guard nil/deleted handles
    -- before Lua's health overload, preserving every native zero-health gate.
    -- Living-object values and mission ordering are unchanged.
    if not Valid(h) then return 0.0 end
    return GetHealth(h)
end

function Start()
    assert(type(IsRecycledByTeam) == "function",
        "bdmisn13 requires stock Redux 2.1+ IsRecycledByTeam")
    M = NewState()
    -- units
    M.recycler = GetHandle("recycler")
    M.chinRecycler = GetHandle("chin_recycler")
    for i = 1, 6 do M.silos[i] = GetHandle("chin_silo" .. i) end
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 30)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        M.wave1Time = GetTime() + 3 * 60.0
        M.wave2Time = GetTime() + 10 * 60.0
        M.wave3Time = GetTime() + 15 * 60.0
        M.wave4Time = GetTime() + 30 * 60.0
        StartCockpitTimer(45 * 60, 30, 10)
        -- label the navs
        for i = 1, 6 do
            local h = GetHandle("nav_chin_silo" .. i)
            if Valid(h) then SetObjectiveName(h, "Scrap Field") end
        end
    end

    M.lastScrapValue = M.scrapValue
    M.scrapValue = GetScrap(1)

    if not M.cameraComplete[1] then
        if not M.cameraReady[1] then
            CameraReady()
            M.cameraReady[1] = true
            M.sound1 = AudioMessage("bd13001.wav")
        end
        local seqDone = false
        if not M.arrived then
            M.arrived = CameraPath("camera_intro", 500, 1500, M.silos[6])
        end
        if M.arrived and IsAudioMessageDone(M.sound1) then seqDone = true end
        if CameraCancelled() then
            seqDone = true
            StopAudioMessage(M.sound1)
        end
        if seqDone then
            M.cameraComplete[1] = true
            CameraFinish()
            ClearObjectives()
            AddObjective("bd13001.otf", "white")
        end
    end

    for wave = 1, 4 do
        local key = "wave" .. wave .. "Time"
        if M[key] < GetTime() then
            M[key] = DISABLED_TIME
            for i = 1, #waveUnits[wave] do
                local h = BuildObject(waveUnits[wave][i], 2, "spawn_attack_waves")
                Goto(h, M.recycler, 1)
            end
        end
    end

    for i = 1, 6 do
        -- Source: !defendersSpawned[i] && GetDistance(user, silos[i]).
        -- C++ converts zero to false; Lua treats zero as true, so compare
        -- explicitly. No threshold was supplied: retain every nonzero distance,
        -- including the source's immediate spawns on a normal map start.
        -- Missing handles skip distance binding; valid-map behavior is unchanged.
        if not M.defendersSpawned[i] and Valid(M.user) and Valid(M.silos[i])
            and GetDistance(M.user, M.silos[i]) ~= 0 then
            M.defendersSpawned[i] = true
            for unit = 1, 4 do
                -- All six groups really use spawn_defend1 and spawn_defend6.
                local path = unit <= 2 and "spawn_defend1" or "spawn_defend6"
                local h = BuildObject(defenderUnits[i][unit], 2, path)
                Defend2(h, M.silos[i])
            end
        end
    end

    -- Keep deadline check before this frame's silo checks, as in native code.
    if not M.recycleChecked and GetCockpitTimer() <= 0.0 and not M.lost and not M.won then
        M.recycleChecked = true
        if M.silosRecycled then
            HideCockpitTimer()
        else
            M.lost = true
            M.sound5 = AudioMessage("bd13005.wav")
        end
    end
    if M.sound5 ~= nil and IsAudioMessageDone(M.sound5) then
        M.sound5 = nil
        FailMission(GetTime() + 1.0, "bd13lsea.des")
    end

    if not M.silosRecycled and not M.lost and not M.won then
        -- check to see if any silos are gone this frame
        -- Native unused local: int numSilosGone = 0;
        for i = 1, 6 do
            -- The native continue becomes this guard (Lua 5.1 has no continue).
            if not M.recycled[i] and Health(M.silos[i]) <= 0.0 then
                -- find all the construction rigs in the world
                -- did any of them just recycle this silo?
                -- Stock IsRecycledByTeam is the capitalized Lua counterpart;
                -- do not gate on IsValid: the query must accept the dead handle.
                local h = M.silos[i]
                local r = h ~= nil and h ~= 0 and IsRecycledByTeam(h, 1)
                if r then
                    M.recycled[i] = true
                else
                    M.lost = true
                    FailMission(GetTime() + 1.0, "bd13lsec.des")
                end
            end
        end
        -- check to see if they're all recycled
        M.silosRecycled = true
        for i = 1, 6 do
            if not M.recycled[i] then M.silosRecycled = false end
        end
    end

    if M.silosRecycled and not M.sound2Played then
        HideCockpitTimer()
        M.recycleChecked = true
        M.sound2Played = true
        AudioMessage("bd13002.wav")
        ClearObjectives()
        AddObjective("bd13001.otf", "green")
        AddObjective("bd13002.otf", "white")
    end

    -- has the player lost his recycler?
    if Health(M.recycler) <= 0.0 and not M.lost and not M.won then
        M.lost = true
        M.sound4 = AudioMessage("bd13004.wav")
    end
    if M.sound4 ~= nil and IsAudioMessageDone(M.sound4) then
        M.sound4 = nil
        FailMission(GetTime() + 1.0, "bd13lseb.des")
    end
    -- has the chinese recycler taken any damage?
    if Health(M.chinRecycler) < 1.0 and not M.silosRecycled and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime() + 1.0, "bd13lsed.des")
    end
    if Health(M.chinRecycler) <= 0.0 and M.silosRecycled and not M.won and not M.lost then
        M.won = true
        M.sound3 = AudioMessage("bd13003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        SucceedMission(GetTime() + 1.0, "bd13win.des")
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission restores serialized tables and engine handles/audio userdata.
    -- Do not rerun Setup or replay resources, waves, timer, or intro on resume.
    -- Native PostLoad's ConvertHandle is handled by the LuaMission serializer.
    M = state
end
