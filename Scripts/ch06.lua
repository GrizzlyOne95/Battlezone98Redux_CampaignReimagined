-- Chinese06Mission port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Chinese06Mission.cpp
-- Source blob: fb13ebac8532415ad2a8e3ad29677d1514087d6f.
-- Complete native source (including comments and serialization) is archived at
-- References/Chinese06Source/Chinese06Mission.cpp.
-- Requires the original mission map labels/paths and chmisn06.aip/assets.
-- No EXU/OpenShim or campaign helper is required. Arrays are 1-based here;
-- ranChoice remains the native 0..2 value. Update block order is preserved.

local DISABLED_TIME = 999999.9
local spawns = { "ran_1", "ran_2", "ran_3" }
local routes = { "ran_1_path", "ran_2_path", "ran_3_path" }
local triggers = { "ran_1_trigger", "ran_2_trigger", "ran_3_trigger" }
local raidUnits = { "svfigh", "svltnk", "svtank", "svhraz" }

local function NewState()
    return {
        -- record whether the init code has been done
        startDone = false,
        -- objectives (unused in native Execute)
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        -- cameras (unused in native Execute)
        cameraReady = { false, false }, cameraComplete = { false, false },
        -- random thingy done?
        ranDone = false, turnTraitor = false, reinfDestroyed = false,
        alien1 = false,
        -- won or lost?
        won = false, lost = false,
        openingSoundTime = DISABLED_TIME, sound2Time = DISABLED_TIME,
        sound3Time = DISABLED_TIME, sound4Time = DISABLED_TIME,
        ranTime = DISABLED_TIME, annoyStartTime = DISABLED_TIME,
        annoyTime = DISABLED_TIME, giveScrapTime = DISABLED_TIME,
        moreRanTime = DISABLED_TIME,
        reinf = {}, psu = {}, annoy = {},
        ranChoice = 0, maxAnnoy = 10, numAnnoyRounds = 0,
        -- user/base handles and openingSound/sound2/sound3/sound4 start nil.
    }
end

local M = NewState()

local function valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function health(h)
    -- PORT FIX: native NULL/deleted handles mean zero health. Lua nil must
    -- not reach the handle overload. This keeps loss, damage and base-target
    -- gates identical for surviving objects, including a destroyed convoy
    -- member triggering betrayal rather than silently excluding that member.
    if valid(h) then return GetHealth(h) end
    return 0.0
end

local function alive(h)
    return valid(h) and IsAlive(h)
end

function Start()
    M = NewState()
    -- units
    M.recycler = GetHandle("avrecy2_recycler")
    M.factory = GetHandle("avmuf2_factory")
    M.armoury = GetHandle("avslf2_armory")
    M.silo1 = GetHandle("absilo2_scrapsilo")
    M.silo2 = GetHandle("absilo3_scrapsilo")
    for i = 1, 4 do M.psu[i] = GetHandle("psu_" .. i) end
    -- navs: no native Setup entries
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

local function getBase()
    local candidates = {}
    -- Avoid a sparse handle table: nil bases must not truncate enumeration.
    for _, name in ipairs({ "recycler", "factory", "armoury", "silo1", "silo2" }) do
        if health(M[name]) > 0.0 then
            candidates[#candidates + 1] = M[name]
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

local function attackBase(h)
    -- PORT FIX: don't mutate deleted attackers or issue Attack with a NULL
    -- target when all five bases are gone. Existing living bases still get
    -- one independently random target per attacker at native priority 0;
    -- the original recycler/factory defeat gate below is unchanged.
    if valid(h) then
        local target = getBase()
        if target ~= nil then Attack(h, target, 0) end
    end
end

local function nearActivation(h)
    -- PORT FIX: missing/deleted producers cannot activate a raid through an
    -- undefined distance query. Living producers retain the exact 500 m gate.
    return health(h) > 0.0 and
        (GetDistance(h, "activate_1") < 500 or GetDistance(h, "activate_2") < 500)
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame

    if not M.startDone then
        SetAIP("chmisn06.aip")
        SetPilot(1, 10)
        SetScrap(2, 0)
        SetScrap(1, 50)
        -- don't do this part after the first shot
        M.startDone = true
        M.openingSoundTime = GetTime() + 2.0
        M.sound2Time = GetTime() + 60.0
        M.annoyStartTime = GetTime() + 10 * 60.0
        M.giveScrapTime = GetTime() + 20 * 60.0
        --BuildObject("cvtnk", 1, user);
        -- Disabled native debug spawn; Lua equivalent:
        -- BuildObject("cvtnk", 1, M.user)
    end

    if M.giveScrapTime < GetTime() then
        M.giveScrapTime = DISABLED_TIME
        AddScrap(2, 50)
    end
    if M.openingSoundTime < GetTime() then
        M.openingSoundTime = DISABLED_TIME
        M.openingSound = AudioMessage("ch06001.wav")
        ClearObjectives()
        AddObjective("ch06001.otf", "white")
    end
    if M.openingSound ~= nil and IsAudioMessageDone(M.openingSound) then
        M.openingSound = nil
    end
    if M.sound2Time < GetTime() then
        M.sound2Time = DISABLED_TIME
        M.sound2 = AudioMessage("ch06002.wav")
    end
    if M.sound2 ~= nil and IsAudioMessageDone(M.sound2) then
        M.sound2 = nil
        local h = BuildObject("apcamr", 1, "nav_1")
        SetObjectiveName(h, "CCA Base") -- stock equivalent of native SetName
        M.sound3Time = GetTime() + 15.0
    end
    if M.sound3Time < GetTime() then
        M.sound3Time = DISABLED_TIME
        M.sound3 = AudioMessage("ch06003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        M.sound4Time = GetTime() + 1.0
    end
    if M.sound4Time < GetTime() then
        M.sound4Time = DISABLED_TIME
        M.sound4 = AudioMessage("ch06004.wav")
    end
    if M.sound4 ~= nil and IsAudioMessageDone(M.sound4) then
        M.sound4 = nil
        M.ranTime = GetTime() + 180.0
    end

    if M.ranTime < GetTime() then
        M.ranTime = DISABLED_TIME
        M.ranChoice = math.random(3) - 1
        local spawn = spawns[M.ranChoice + 1]
        local path = routes[M.ranChoice + 1]
        for i = 1, 12 do
            local odf = i <= 4 and "cvfigh" or (i <= 8 and "cvtnk" or "cvhraz")
            M.reinf[i] = BuildObject(odf, 1, spawn)
        end
        for i = 1, 12 do
            local h = M.reinf[i]
            if valid(h) then
                SetPerceivedTeam(h, 2)
                Goto(h, path, 1)
                -- put a sspilo in each one
                -- Native GameObject::curPilot assignment maps to stock Lua.
                SetPilotClass(h, "sspilo")
            end
        end
        M.ranDone = true
    end

    if M.ranDone and not M.turnTraitor then
        local p = triggers[M.ranChoice + 1]
        for i = 1, 12 do
            if health(M.reinf[i]) < 0.70 then -- come under attack?
                M.turnTraitor = true
                break
            elseif alive(M.reinf[i]) and GetDistance(M.reinf[i], p) < 75.0 then
                -- gone far enough?
                M.turnTraitor = true
                break
            end
        end
        if M.turnTraitor then
            --_DEBUGMSG0("Setting traitor's team number to 2");
            for i = 1, 12 do
                local h = M.reinf[i]
                if valid(h) then
                    SetTeamNum(h, 2)
                    SetPerceivedTeam(h, 2)
                    attackBase(h)
                end
            end
            AudioMessage("ch06005.wav")
            M.moreRanTime = GetTime() + 2 * 60.0
        end
    end

    if M.moreRanTime < GetTime() then
        -- SOURCE BUG FIX: C++ never resets moreRanTime, causing eight new
        -- enemies EVERY FRAME forever after the two-minute deadline. Disable
        -- this one-shot timer just like ranTime/giveScrapTime. The first wave's
        -- deadline, alternate-entry selection, 4 fighters + 4 tanks and attack
        -- orders are unchanged. Only the unintended per-frame flood is removed;
        -- PSU raids retain their separate five-minute recurrence below.
        M.moreRanTime = DISABLED_TIME
        local others = {}
        for i = 1, 3 do
            if M.ranChoice ~= i - 1 then others[#others + 1] = spawns[i] end
        end
        local p = others[math.random(2)]
        for i = 1, 4 do attackBase(BuildObject("svfigh", 2, p)) end
        for i = 1, 4 do attackBase(BuildObject("svtank", 2, p)) end
    end

    if M.ranDone and not M.reinfDestroyed then
        M.reinfDestroyed = true
        for i = 1, 12 do
            if alive(M.reinf[i]) then M.reinfDestroyed = false end
        end
        if M.reinfDestroyed then AudioMessage("ch06006.wav") end
    end

    if M.reinfDestroyed and not M.won and not M.lost then
        M.won = true
        -- see if everything on the mission is dead
        -- AllObjects maps native GameObject::objectList, including pilots and
        -- buildings. AllCraft/ObjectiveObjects would narrow the victory gate.
        for h in AllObjects() do
            if GetTeamNum(h) == 2 and IsAlive(h) then M.won = false end
        end
        if M.won then SucceedMission(GetTime() + 1.0, "ch06win.des") end
    end

    if health(M.recycler) <= 0.0 and health(M.factory) <= 0.0
        and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime(), "ch06lsea.des")
    end

    if M.annoyStartTime < GetTime() then
        -- is the recycler or factory within range?
        if nearActivation(M.recycler) or nearActivation(M.factory) then
            M.annoyTime = GetTime()
            M.annoyStartTime = DISABLED_TIME
        else
            -- check again in 60 seconds
            M.annoyStartTime = GetTime() + 60.0
        end
    end
    if M.annoyTime < GetTime() then
        -- are the psu units still alive?
        if alive(M.psu[1]) or alive(M.psu[2]) or alive(M.psu[3]) or alive(M.psu[4]) then
            M.annoyTime = GetTime() + 5 * 60.0
            M.numAnnoyRounds = M.numAnnoyRounds + 1
            if M.numAnnoyRounds == 3 then M.maxAnnoy = 6 end
            -- spawn; retain surviving slot occupants and only refill deaths
            for i = 1, M.maxAnnoy do
                if health(M.annoy[i]) <= 0.0 then
                    M.annoy[i] = BuildObject(raidUnits[math.random(4)], 2, "annoy_1")
                    Goto(M.annoy[i], "annoy_1_path")
                end
            end
        else
            -- these raids stop now
            M.annoyTime = DISABLED_TIME
        end
    end
end

function Save()
    return M
end

function Load(state)
    -- LuaMission saves tables, handles and audio messages. Native PostLoad
    -- ConvertHandle is performed by the engine; don't rerun Setup/Start or
    -- replay audio/spawns/resources. Unused native fields are retained above.
    M = state
end
