-- Chinese06Mission port for stock Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Chinese06Mission.cpp
-- Source blob: fb13ebac8532415ad2a8e3ad29677d1514087d6f.
-- Complete native source (including comments and serialization) is archived at
-- References/Chinese06Source/Chinese06Mission.cpp.
-- Requires the original mission map labels/paths and chmisn06.aip/assets.
-- No EXU/OpenShim or campaign helper is required. Arrays are 1-based here;
-- ranChoice remains the native 0..2 value. Update block order is preserved.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/CHMISN06_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Elysium weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Chmisn06CoopSourceParity.py).
-- CR co-op layer <<

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
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/CHMISN06_COOP.md lists every wrapped call and restoration.
-- Restored content (Docs/CHMISN06_COOP.md, "Restored content"), each switchable:
local RESTORED_RECON_PATROLS = true -- the six authored recon fighters fly their authored routes
local RESTORED_REVEAL = true        -- the Soviet base's disguised buildings are revealed with ch06006
local RESTORED_DEBRIEF = true       -- the unused ch06007 plays before the victory
local DEBRIEF_SECONDS = 13.0        -- ch06007 runs 11.7 s
local Restored
-- The raiders and the second wave (four fighters and four tanks) are the only craft the body builds on the
-- Soviet side: they become concealed, head-count-scaled tickets. The reinforcement convoy (team 1, disguised)
-- is the story and is built where the body says; the Soviet base is authored.
local SCALED_ODFS = { svfigh = true, svltnk = true, svtank = true, svhraz = true }
local ENEMY_TEAM = 5
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "chmisn06", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "avrecy2_recycler" }, -- the shared Chinese base is the recycler
    scaledOdfs = SCALED_ODFS,
    -- Where the body's entry (ran_N for the second wave, annoy_1 for a raid) has a human within 460 m, the
    -- next far edge approach is used (a raid that falls back drives to the base: Restored.Built).
    fallbackEntries = { "ran_1", "ran_2", "ran_3" },
    liveCap = 24, -- up to ten raiders every five minutes and the eight-unit second wave
    scrapPerGuest = 10,
    failDes = "ch06lsea.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- Elysium: the Venus engine in its Earth-like storm dress (Docs/CHMISN06_COOP.md, "Weather: Elysium").
    weather = { module = "CRElysiumWeather", sites = "CRElysiumSitesCH06", startLevel = 1, targetLevel = 2,
        beats = function(elysium, state, s)
            local beats = s.elysiumBeats
            if beats == nil then beats = {}; s.elysiumBeats = beats end
            local r = s.r or {}
            local function strikeAt(h)
                if h == nil or h == 0 or not IsValid(h) then return end
                local p = GetPosition(h)
                if p ~= nil then elysium.TriggerStrike({ x = p.x, y = p.y, z = p.z }) end
            end
            -- The "allies" are on their way (ch06003 is long over): the sky closes in.
            if (not beats.convoy) and state.ranDone then
                beats.convoy = true
                elysium.SetTargetLevel(3)
            end
            -- The betrayal: the storm breaks over the traitors.
            if (not beats.traitor) and state.turnTraitor then
                beats.traitor = true
                elysium.SetTargetLevel(4)
                for i = 1, 12 do
                    local h = state.reinf[i]
                    if h ~= nil and h ~= 0 and IsValid(h) then strikeAt(h); break end
                end
            end
            -- Every second wave and every raid arrives under a strike (the units are tickets for a few frames:
            -- the strike waits for the first one that is built).
            local events, built = r.events or 0, r.builtTotal or 0
            if events > (beats.events or 0) and built > (beats.built or 0) then
                beats.events, beats.built = events, built
                strikeAt(r.lastBuilt)
            end
            -- The convoy is destroyed: the sky eases while the Soviet base is cleared.
            if (not beats.cleared) and state.reinfDestroyed then
                beats.cleared = true
                elysium.SetTargetLevel(3)
            end
            -- Victory: the sky eases for the debrief.
            if (not beats.easing) and state.won then
                beats.easing = true
                elysium.SetTargetLevel(2)
            end
        end },
    hooks = {
        load = function() if Restored then Restored.OnLoad() end end,
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
    },
})
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- A line whose audio handle is absent counts as finished, so the opening cannot wait on it for ever: the body
-- advances only on a non-nil handle, so an absent one is replaced by 0, which IsAudioMessageDone accepts.
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
local AudioMessage = campaignRuntime and function(file)
    local handle = campaignRuntime.AudioMessage(file)
    if handle == nil then return 0 end
    return handle
end or AudioMessage
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
-- The first objective shown ends the opening: s.r.objectiveShown, saved in crcca state, is what arms the
-- restored patrols and what a Load republishes the objective for.
local AddObjective = campaignRuntime and function(...)
    local s = campaignRuntime.State()
    s.r = s.r or {}
    s.r.objectiveShown = true
    return campaignRuntime.AddObjective(...)
end or AddObjective
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- Restored debrief: ch06007 ("Good work, Major ...") is never played by the DLL. It is spoken when the victory
-- is declared and the result waits for it (the body declares it exactly once).
local SucceedMission = campaignRuntime and function(when, description)
    if RESTORED_DEBRIEF then
        AudioMessage("ch06007.wav")
        when = when + DEBRIEF_SECONDS
    end
    return campaignRuntime.SucceedMission(when, description)
end or SucceedMission
-- The Soviets are the map's team 2 in the DLL and team 5 here; team 2 is a human slot in co-op.
local nativeSetPilot, nativeAddScrap = SetPilot, AddScrap
local nativeSetTeamNum, nativeSetPerceivedTeam, nativeGetTeamNum = SetTeamNum, SetPerceivedTeam, GetTeamNum
-- The body's 10 pilots go to every human team (each human respawns from its own pool).
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then nativeSetPilot(humanTeam, count) end end)
        return nativeSetPilot(1, count)
    end
    if team == 2 then team = ENEMY_TEAM end
    return nativeSetPilot(team, count)
end or SetPilot
local AddScrap = campaignRuntime and function(team, amount)
    if team == 2 then team = ENEMY_TEAM end
    return nativeAddScrap(team, amount)
end or AddScrap
-- The traitors turn Soviet and are perceived as Soviet: team 5 in co-op.
local SetTeamNum = campaignRuntime and function(h, team)
    if team == 2 then team = ENEMY_TEAM end
    return nativeSetTeamNum(h, team)
end or SetTeamNum
local SetPerceivedTeam = campaignRuntime and function(h, team)
    if team == 2 then team = ENEMY_TEAM end
    return nativeSetPerceivedTeam(h, team)
end or SetPerceivedTeam
-- Stock bug (CR layer only): the victory scan reads "team 2" as the enemy, but team 2 is a guest's team in
-- co-op. The Soviets answer 2; every human team answers 1.
local GetTeamNum = campaignRuntime and function(h)
    local team = nativeGetTeamNum(h)
    if team == ENEMY_TEAM then return 2 end
    if type(team) == "number" and team >= 1 and team <= 4 then return 1 end
    return team
end or GetTeamNum
-- Orders on a waiting ticket are recorded and replayed on the unit when it is built.
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local IsValid, IsAlive, GetHealth = IsValid, IsAlive, GetHealth
local BuildObject = BuildObject
if campaignRuntime then
    local runtime = campaignRuntime
    local PLAYERS = runtime.PLAYERS
    local runtimeIsValid, runtimeIsAlive, nativeGetHealth = runtime.IsValid, runtime.IsAlive, GetHealth
    local function PendingTicket(h)
        return type(h) == "number" and h < 0
    end
    IsValid = function(h)
        if h == PLAYERS then return true end
        -- A negative number is a spawn ticket (or one the runtime dropped): never ask the engine about it.
        if PendingTicket(h) then return runtime.State().arrivals[-h] ~= nil end
        return runtimeIsValid(h)
    end
    IsAlive = function(h)
        if PendingTicket(h) then return runtime.State().arrivals[-h] ~= nil end
        return runtimeIsAlive(h)
    end
    -- A waiting ticket is a raider at full health (its slot must not be refilled while it waits).
    GetHealth = function(h)
        if PendingTicket(h) then return runtime.State().arrivals[-h] ~= nil and 1.0 or 0.0 end
        return nativeGetHealth(h)
    end
    -- Every Soviet craft is a ticket; a new wave or raid (a new frame or a new entry path) is a new scaling
    -- event: the first unit of it is mirrored by min(floor(humans / 2), 2) extras with its orders.
    local eventFrame, eventWhere
    BuildObject = function(odf, team, where)
        if SCALED_ODFS[odf] then
            local now = GetTime()
            if eventFrame ~= now or eventWhere ~= where then
                eventFrame, eventWhere = now, where
                runtime.BeginEvent()
                if Restored then Restored.Event(where) end
            end
        end
        return runtime.Spawn(odf, team, where)
    end
end
-- CR co-op runtime <<

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

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/CHMISN06_COOP.md lists it with the source it comes
-- from), plus the co-op fixes that need state. Each restoration is gated by its RESTORED_* flag and by the map
-- actually carrying what it needs, so a map without them runs the faithful mission.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local HUNT_EVERY = 20 -- seconds between checks that no attacker stands idle
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local function Real(h)
        return h ~= nil and h ~= 0 and not (type(h) == "number" and h < 0) and IsValid(h)
    end
    -- A scaling event (called by the BuildObject shadow): a second wave or a raid.
    function Restored.Event(where)
        local r = RState()
        r.events = (r.events or 0) + 1
    end
    -- A ticket becoming a unit: every Soviet attacker is remembered (extras too) so an idle one can be sent
    -- against the base again. A raid that fell back to a far edge (a human was near annoy_1) drives to the base.
    function Restored.Built(h, request, id)
        local r = RState()
        r.hunters = r.hunters or {}
        r.hunters[#r.hunters + 1] = h
        r.builtTotal = (r.builtTotal or 0) + 1
        r.lastBuilt = h
        if request and request.where == "annoy_1" and GetDistance(h, "annoy_1") > 150 then
            runtime.Goto(h, "activate_2")
        end
    end
    -- The runtime's Load resets the presentation, which drops the objective: Step republishes it.
    function Restored.OnLoad()
        RState().afterLoad = true
    end
    -- True while a Soviet request waits for a safe entry (the victory must not be declared in that gap).
    function Restored.Pending()
        return next(runtime.State().arrivals) ~= nil
    end
    -- Cut: the map carries six recon fighters on the Chinese side (sw_patrol / nw_patrol) and their routes
    -- sw_path / nw_path, which the body never orders. Once the opening objective is shown they fly their routes.
    function Restored.Patrols(r)
        if not RESTORED_RECON_PATROLS or r.patrolsSent or not r.objectiveShown then return end
        r.patrolsSent = true
        for _, group in ipairs({ "sw", "nw" }) do
            local path = group .. "_path"
            if runtime.PathExists(path) then
                for h in AllCraft() do
                    local ok, label = pcall(GetLabel, h)
                    if ok and label == group .. "_patrol" then Goto(h, path, 1) end
                end
            end
        end
    end
    -- Cut: ch06006 says the Soviets use "the Factory that we left on Ganymede" and warns of more Chinese units.
    -- The map's stolen factory and the two long-range power plants carry the Chinese disguise; with the line
    -- they are revealed as Soviet and the factory is marked.
    function Restored.Reveal(r)
        if not RESTORED_REVEAL or r.revealed or not M.reinfDestroyed then return end
        r.revealed = true
        local stolen = GetHandle("stolen")
        if Real(stolen) then
            SetPerceivedTeam(stolen, 2)
            SetObjectiveName(stolen, "Stolen Factory")
            runtime.SetObjectiveOn(stolen)
        end
        for h in AllObjects() do
            local ok, label = pcall(GetLabel, h)
            if ok and label == "ld_power" then SetPerceivedTeam(h, 2) end
        end
    end
    -- Stock bug: a Soviet attacker whose base target died or whose order was dropped stands idle for good.
    -- Every HUNT_EVERY seconds an idle attacker (the traitors too, once turned) attacks the nearest living
    -- building of the base.
    local function BaseTarget(unit)
        local best, bestDistance
        for _, name in ipairs({ "recycler", "factory", "armoury", "silo1", "silo2" }) do
            local base = M[name]
            if Real(base) and GetHealth(base) > 0.0 then
                local d = GetDistance(unit, base)
                if bestDistance == nil or d < bestDistance then best, bestDistance = base, d end
            end
        end
        return best
    end
    function Restored.Hunt(r)
        if M.won or M.lost then return end
        local now = GetTime()
        if now < (r.huntAt or 0) then return end
        r.huntAt = now + HUNT_EVERY
        r.hunters = r.hunters or {}
        if M.turnTraitor and not r.traitorsListed then
            r.traitorsListed = true
            for i = 1, 12 do
                if Real(M.reinf[i]) then r.hunters[#r.hunters + 1] = M.reinf[i] end
            end
        end
        local kept = {}
        for _, h in ipairs(r.hunters) do
            if Real(h) and IsAlive(h) then
                kept[#kept + 1] = h
                if GetCurrentCommand(h) == AiCommand.NONE then
                    local target = BaseTarget(h)
                    if target ~= nil then Attack(h, target, 0) end
                end
            end
        end
        r.hunters = kept
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then
            r.afterLoad = nil
            if r.objectiveShown then
                ClearObjectives()
                AddObjective("ch06001.otf", "white")
            end
        end
        Restored.Patrols(r)
        Restored.Reveal(r)
        Restored.Hunt(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[chmisn06] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
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
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
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
        -- PSU raids retain their separate ten-minute recurrence below.
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
-- CR co-op victory >>
        -- A Soviet request still waiting for a safe entry is a living enemy: no victory yet.
        if campaignRuntime and Restored.Pending() then M.won = false end
-- CR co-op victory <<
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
            M.annoyTime = GetTime() + 10 * 60.0 -- TRO 1.3: 600 s (FUN_005b6f10)
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
-- CR restored content >>
    if campaignRuntime then Restored.Run() end
-- CR restored content <<
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.AfterUpdate() end
-- CR co-op callback <<
end

function Save()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Save() end
-- CR co-op callback <<
    return M
end

function Load(state)
    -- LuaMission saves tables, handles and audio messages. Native PostLoad
    -- ConvertHandle is performed by the engine; don't rerun Setup/Start or
    -- replay audio/spawns/resources. Unused native fields are retained above.
    M = state
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Load() end
-- CR co-op callback <<
end
-- CR co-op callbacks >>
function AddObject(h) if campaignRuntime then return campaignRuntime.AddObject(h) end end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...) if campaignRuntime then return campaignRuntime.Receive(from,kind,...) end end
-- CR co-op callbacks <<
