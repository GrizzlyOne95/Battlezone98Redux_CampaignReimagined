-- BlackDog07Mission.cpp faithfully ported to stock BZR / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog07Mission.cpp
-- Source blob: 35e2f6e94e88cd33a2c00e544da5600f46b7cc53.
-- Complete C++ (including every comment and native Load/Save/PostLoad) is
-- retained in References/BlackDog07Source/BlackDog07Mission.cpp.
-- The source contains no disabled gameplay code. No external helpers required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN07_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Elysium weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn07CoopSourceParity.py).
-- CR co-op layer <<

local NEVER = 999999.9

local function NewState()
    return {
        -- record whether the init code has been done
        startDone = false,
        -- objectives (2 and 3 are unused in the source, but retained)
        objective1Complete = false,
        objective2Complete = false,
        objective3Complete = false,
        -- waves spawned?
        wavesSpawned = true,
        -- have we lost?
        lost = false, won = false,
        sound1Time = NEVER, sound2Time = NEVER, sound3Time = NEVER,
        waveDelay = {[0] = NEVER, [1] = NEVER},
        annoyTime = NEVER,
        -- *** User stuff: user starts nil.
        -- *** Units: retain the source's zero-based arrays and fixed bounds.
        mustDestroy = {}, mustSave = {}, waveUnits1 = {}, waveUnits2 = {},
        -- *** Sounds: sound1, sound2, sound3 start nil (native NULL).
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN07_COOP.md lists every wrapped call and restoration.
-- RESTORED_WAVE_ATTACK switches the cut wave attack off (Docs/BDMISN07_COOP.md, "Restored content").
local RESTORED_WAVE_ATTACK = true
local Restored
-- The harassment raiders (3 fighters + 2 light tanks every five minutes) are the only craft the body builds: they
-- become concealed, head-count-scaled tickets. The two map waves and the whole Chinese base are authored.
local SCALED_ODFS = { cvfigh = true, cvltnk = true }
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn07", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared Black Dog base is the recycler
    scaledOdfs = SCALED_ODFS,
    -- The raid enters at annoy_1 on the east edge; if a human is within 460 m of it the raid comes from the start
    -- of the second or the first map wave path instead.
    fallbackEntries = { "attack_path2", "attack_path1" },
    liveCap = 16, -- a raid every five minutes, and the raiders hunt until they die
    scrapPerGuest = 10,
    failDes = "bd07lose.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- Elysium: the Venus engine in its Earth-like storm dress (Docs/BDMISN07_COOP.md, "Weather: Elysium").
    weather = { module = "CRElysiumWeather", sites = "CRElysiumSitesBD07", startLevel = 1, targetLevel = 2,
        beats = function(elysium, state, s)
            local beats = s.elysiumBeats
            if beats == nil then beats = {}; s.elysiumBeats = beats end
            local r = s.r or {}
            local function strikeAt(h)
                if h == nil or h == 0 or not IsValid(h) then return end
                local p = GetPosition(h)
                if p ~= nil then elysium.TriggerStrike({ x = p.x, y = p.y, z = p.z }) end
            end
            -- The first Chinese wave (three scouts) is on its way: the sky closes in.
            if (not beats.scouts) and r.wave1 then
                beats.scouts = true
                elysium.SetTargetLevel(3)
            end
            -- The second wave (tanks, scouts, bombers) hits the base: the storm breaks.
            if (not beats.storm) and r.wave2 then
                beats.storm = true
                elysium.SetTargetLevel(4)
            end
            -- The go-ahead: the waves are beaten and lightning walks over the Chinese base.
            if (not beats.goahead) and state.objective1Complete then
                beats.goahead = true
                elysium.SetTargetLevel(4)
                strikeAt(GetHandle("nav_chinbase"))
            end
            -- Every harassment raid arrives under a strike.
            -- (the raiders are tickets for a few frames: the strike waits for the first one that is built)
            local raids, built = r.raids or 0, r.raiderTotal or 0
            if raids > (beats.raids or 0) and built > (beats.built or 0) then
                beats.raids, beats.built = raids, built
                local list = r.raiders or {}
                strikeAt(list[#list])
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
local NativeGetScrap = GetScrap
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- A line whose audio handle is absent counts as finished, so the briefing cannot wait on it for ever: the body
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
-- The first objective shown ends the briefing (the body shows them only after bd07003): r.briefDone, saved in
-- crcca state, is what arms the restored waves and what a Load republishes the objectives for.
local AddObjective = campaignRuntime and function(...)
    local s = campaignRuntime.State()
    s.r = s.r or {}
    s.r.briefDone = true
    return campaignRuntime.AddObjective(...)
end or AddObjective
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- Stock bug (CR layer only): the body reads the Chinese scrap with GetScrap(2), but team 2 is a guest's team in
-- co-op; the Chinese are team 5 here (SetScrap(2, 40) is mapped by the runtime).
local GetScrap = campaignRuntime and function(team)
    if team == 2 then team = 5 end
    return NativeGetScrap(team)
end or GetScrap
-- The body's "player" (M.user) is the runtime's nearest-human token, so every order aimed at it and every
-- liveness test on it needs a meaning. The shadows below sit BEFORE the body's Valid/Alive helpers.
local IsValid, IsAlive, Goto, Attack, SetPilot = IsValid, IsAlive, Goto, Attack, SetPilot
local BuildObject = BuildObject
if campaignRuntime then
    local runtime = campaignRuntime
    local PLAYERS = runtime.PLAYERS
    local runtimeIsValid, runtimeIsAlive = runtime.IsValid, runtime.IsAlive
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
    -- The nearest living human to a unit: orders at "the player" go to this human.
    local function NearestHuman(unit)
        local best, bestDistance
        runtime.Coop.ForEachPlayerHandle(function(human)
            if runtimeIsAlive(human) then
                local d = runtime.GetDistance(unit, human)
                if bestDistance == nil or d < bestDistance then best, bestDistance = human, d end
            end
        end)
        return best
    end
    function runtime.NearestHumanTo(unit) return NearestHuman(unit) end
    -- Goto/Attack(unit, M.user): a real unit gets the nearest human now; a waiting ticket remembers the order
    -- (the runtime drops one whose target is the token) and is ordered the moment it is built.
    local function OrderAtPlayer(op)
        local base = runtime[op]
        return function(h, target, ...)
            if target ~= PLAYERS then return base(h, target, ...) end
            if PendingTicket(h) then
                local s = runtime.State()
                s.r = s.r or {}
                s.r.orders = s.r.orders or {}
                s.r.orders[tostring(-h)] = op
                return
            end
            if runtimeIsAlive(h) then
                local human = NearestHuman(h)
                if human ~= nil then return base(h, human) end
            end
        end
    end
    Goto, Attack = OrderAtPlayer("Goto"), OrderAtPlayer("Attack")
    -- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human
    -- respawns from its own pool).
    local nativeSetPilot = SetPilot
    SetPilot = function(team, count)
        if team == 1 then
            runtime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then nativeSetPilot(humanTeam, count) end end)
            return nativeSetPilot(1, count)
        end
        if team == 2 then team = 5 end
        return nativeSetPilot(team, count)
    end
    -- Every raider is a ticket; a new raid (a new frame or a new entry path) is a new scaling event: the first
    -- unit of the raid is mirrored by min(floor(humans / 2), 2) extras with its orders.
    local eventFrame, eventWhere
    BuildObject = function(odf, team, where)
        if SCALED_ODFS[odf] then
            local now = GetTime()
            if eventFrame ~= now or eventWhere ~= where then
                eventFrame, eventWhere = now, where
                runtime.BeginEvent()
                if Restored then Restored.Raid(where) end
            end
        end
        return runtime.Spawn(odf, team, where)
    end
end
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

local function Alive(h)
    return Valid(h) and IsAlive(h)
end

local function Healthy(h)
    -- PORT FIX: a missing/deleted handle cannot be passed safely through Lua
    -- health overloads. Treat it as zero health, as the native failed lookup
    -- does. Existing objects still use GetHealth > 0, not pilot-based IsAlive;
    -- the original "at least one protected structure survives" rule is intact.
    return Valid(h) and GetHealth(h) > 0.0
end

local function ShowObjectives()
    -- PORT FIX: sound3 can finish after the waves/base have already been
    -- destroyed, and wave completion can occur after victory was scheduled.
    -- Native unconditional refreshes then restore an obsolete white objective.
    -- Render the current earned phase instead. This only fixes the display:
    -- no audio, timers, AI commands, resources, or win/loss gates are changed.
    ClearObjectives()
    if M.won then
        AddObjective("bd07002.otf", "green")
    elseif M.objective1Complete then
        AddObjective("bd07002.otf", "white")
    else
        AddObjective("bd07001.otf", "white")
    end
end

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/BDMISN07_COOP.md lists it with the cut block it
-- comes from), plus the co-op fixes that need state. The restoration is gated by RESTORED_WAVE_ATTACK and by
-- the map actually carrying both wave paths, so a map without them runs the faithful mission.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local WAVE_DELAY = 120 -- seconds from the objectives being shown to the first wave setting out
    local HUNT_EVERY = 20  -- seconds between checks that no raider stands idle
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- A ticket becoming a unit: an order aimed at the player is issued to the nearest human; every raider is
    -- remembered (extras too) so an idle one can be sent out again.
    function Restored.Built(h, request, id)
        local r = RState()
        local key = tostring((request and request.primary) or id)
        local op = r.orders and r.orders[key]
        if op then
            local human = runtime.NearestHumanTo(h)
            if human ~= nil then runtime[op](h, human) end
        end
        if request and request.where == "annoy_1" then
            r.raiders = r.raiders or {}
            r.raiders[#r.raiders + 1] = h
            r.raiderTotal = (r.raiderTotal or 0) + 1
        end
    end
    -- The runtime's Load resets the presentation, which drops the objectives: Step republishes them.
    function Restored.OnLoad()
        RState().afterLoad = true
    end
    -- A new harassment raid is one scaling event (called by the BuildObject shadow).
    function Restored.Raid(where)
        if where ~= "annoy_1" then return end
        local r = RState()
        r.raids = (r.raids or 0) + 1
    end
    -- Cut: the body arms waveDelay[0] nowhere (Setup leaves it at "never" and sets wavesSpawned = TRUE), so the
    -- two preplaced Chinese waves, and the authored paths attack_path1 / attack_path2 that end at the Black Dog
    -- base, are never sent. Once the briefing has finished and the objectives are shown, the body's own timer
    -- is armed: wave 1 sets out WAVE_DELAY seconds later and wave 2 follows 30 s after it, exactly as the body
    -- already codes. Nothing is armed when the waves are already beaten or the mission is decided.
    function Restored.WaveAttack(r)
        if not RESTORED_WAVE_ATTACK or r.waveArmed then return end
        if not r.briefDone or M.objective1Complete or M.won or M.lost then return end
        r.waveArmed = true
        if not (runtime.PathExists("attack_path1") and runtime.PathExists("attack_path2")) then return end
        r.waveSet = true
        M.waveDelay[0] = GetTime() + WAVE_DELAY
    end
    -- What the weather beats read: wave 1 has been sent (the body cleared its timer), wave 2 too.
    function Restored.WaveFlags(r)
        if not r.waveSet then return end
        if not r.wave1 and M.waveDelay[0] >= NEVER then r.wave1 = true end
        if r.wave1 and not r.wave2 and M.waveDelay[1] >= NEVER then r.wave2 = true end
    end
    -- Stock bug: a raider's order is lost when no human is alive at that moment (the body skips the order) and
    -- a raider whose target died stands idle for good. Every HUNT_EVERY seconds an idle raider attacks the
    -- nearest living human.
    function Restored.Hunt(r)
        if M.won or not r.raiders then return end
        local now = GetTime()
        if now < (r.huntAt or 0) then return end
        r.huntAt = now + HUNT_EVERY
        local kept = {}
        for _, h in ipairs(r.raiders) do
            if h ~= nil and h ~= 0 and IsValid(h) and IsAlive(h) then
                kept[#kept + 1] = h
                if GetCurrentCommand(h) == AiCommand.NONE then
                    local human = runtime.NearestHumanTo(h)
                    if human ~= nil then Attack(h, human) end
                end
            end
        end
        r.raiders = kept
    end
    -- Runs at the end of the body's Update, in the frame the triggering block ran.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        -- ShowObjectives reads M, so the earned phase (patrol, destroy, done) is the one republished.
        if r.afterLoad then
            r.afterLoad = nil
            if r.briefDone then ShowObjectives() end
        end
        Restored.WaveAttack(r)
        Restored.WaveFlags(r)
        Restored.Hunt(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn07] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    -- Native Load initializes state, then Setup resolves the map objects.
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<

    -- units
    M.mustSave[0] = GetHandle("recycler")
    M.mustSave[1] = GetHandle("myfactory")
    M.mustSave[2] = GetHandle("my_hq")
    M.mustDestroy[0] = GetHandle("chin_recycler")
    M.mustDestroy[1] = GetHandle("chin_factory")
    M.mustDestroy[2] = GetHandle("chin_solar1")
    M.mustDestroy[3] = GetHandle("chin_solar2")
    M.mustDestroy[4] = GetHandle("chin_solar3")
    M.mustDestroy[5] = GetHandle("chin_tower1")
    M.mustDestroy[6] = GetHandle("chin_tower2")
    M.mustDestroy[7] = GetHandle("chin_tower3")
    M.mustDestroy[8] = GetHandle("chin_supply")
    M.mustDestroy[9] = GetHandle("chin_hq")
    M.mustDestroy[10] = GetHandle("chin_hangar")
    M.waveUnits1[0] = GetHandle("chin_scout1")
    M.waveUnits1[1] = GetHandle("chin_scout2")
    M.waveUnits1[2] = GetHandle("chin_scout3")
    M.waveUnits2[0] = GetHandle("chin_scout4")
    M.waveUnits2[1] = GetHandle("chin_scout5")
    M.waveUnits2[2] = GetHandle("chin_scout6")
    M.waveUnits2[3] = GetHandle("chin_ltnk1")
    M.waveUnits2[4] = GetHandle("chin_ltnk2")
    M.waveUnits2[5] = GetHandle("chin_tank1")
    M.waveUnits2[6] = GetHandle("chin_bomber1")
    M.waveUnits2[7] = GetHandle("chin_bomber2")

    -- label the nav beacons; stock SetObjectiveName is native SetName's alias.
    local h = GetHandle("nav_mybase")
    if Valid(h) then SetObjectiveName(h, "Black Dog Base") end
    h = GetHandle("nav_chinbase")
    if Valid(h) then SetObjectiveName(h, "Chinese Base") end
    -- PORT SAFETY: absent beacons simply skip naming; mission flow is unchanged.

    -- SOURCE QUIRK PRESERVED: Setup sets wavesSpawned = TRUE, and Execute
    -- never arms waveDelay[0]. Keep the preplaced waves and dormant path-timer
    -- branches; inventing an initial delay would alter the original attack flow.
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()

    if not M.startDone then
        SetAIP("bdmisn07.aip")
        SetScrap(1, 8)
        SetPilot(1, 10)
        -- don't do this part after the first shot
        M.startDone = true
        M.sound1Time = now + 5.0
    end

    -- sound1
    if M.sound1Time < now then
        M.sound1Time = NEVER
        M.sound1 = AudioMessage("bd07001.wav")
    end
    if M.sound1 ~= nil and IsAudioMessageDone(M.sound1) then
        M.sound1 = nil
        M.sound2Time = now + 1.0
    end

    -- sound 2
    if M.sound2Time < now then
        M.sound2Time = NEVER
        M.sound2 = AudioMessage("bd07002.wav")
    end
    if M.sound2 ~= nil and IsAudioMessageDone(M.sound2) then
        M.sound2 = nil
        M.sound3Time = now + 2.0
    end

    -- sound 3
    if M.sound3Time < now then
        M.sound3Time = NEVER
        M.sound3 = AudioMessage("bd07003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        -- set the objectives
        ShowObjectives()
    end

    if M.waveDelay[0] < now then
        M.waveDelay[0] = NEVER
        M.waveDelay[1] = now + 30.0
        -- get first wave to attack
        for i = 0, 2 do
            if Valid(M.waveUnits1[i]) then
                Goto(M.waveUnits1[i], "attack_path1", 1)
            end
        end
    end
    if M.waveDelay[1] < now then
        M.waveDelay[1] = NEVER
        -- get second wave to attack
        for i = 0, 7 do
            if Valid(M.waveUnits2[i]) then
                Goto(M.waveUnits2[i], "attack_path2", 1)
            end
        end
        M.wavesSpawned = true
    end
    -- PORT SAFETY: path commands skip missing/deleted units only. Both source
    -- path names, priorities, fixed array bounds, and 30-second gap are intact.

    if M.wavesSpawned and not M.objective1Complete then
        M.objective1Complete = true
        for i = 0, 2 do
            if Alive(M.waveUnits1[i]) then
                M.objective1Complete = false
                break
            end
        end
        for i = 0, 7 do
            if Alive(M.waveUnits2[i]) then
                M.objective1Complete = false
                break
            end
        end
        if M.objective1Complete then
            ShowObjectives()
            AudioMessage("bd07004.wav")
            M.annoyTime = now + 1.0
            local scrap = GetScrap(2)
            if scrap < 40 then SetScrap(2, 40) end
        end
    end

    if M.annoyTime < now then
        M.annoyTime = now + 5 * 60.0
        for i = 0, 2 do
            local h = BuildObject("cvfigh", 2, "annoy_1")
            -- PORT SAFETY: failed builds or an absent player cannot receive a
            -- valid attack order. Keep spawning and the original cadence;
            -- valid objects still target the current player with default priority.
            if Valid(h) and Valid(M.user) then Attack(h, M.user) end
        end
        for i = 0, 1 do
            local h = BuildObject("cvltnk", 2, "annoy_1")
            if Valid(h) and Valid(M.user) then Attack(h, M.user) end
        end
    end

    -- have we met all the goals?
    if not M.won and not M.lost then
        M.won = true
        for i = 0, 10 do
            if Alive(M.mustDestroy[i]) then
                M.won = false
                break
            end
        end
        -- have we won?
        if M.won then
            ShowObjectives()
            SucceedMission(now + 1.0, "bd07win.des")
        end
    end

    if not M.lost and not M.won then
        M.lost = true
        for i = 0, 2 do
            if Healthy(M.mustSave[i]) then
                M.lost = false
                break
            end
        end
        -- have we lost?
        if M.lost then FailMission(now + 1.0, "bd07lose.des") end
    end
    -- Preserve victory-before-defeat ordering and the source's continued audio/
    -- harassment processing during the one-second mission outcome delay.
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
    -- LuaMission restores serializable state and engine handles. Unlike native
    -- PostLoad, no manual ConvertHandle is needed. Do not rerun Setup, replay
    -- briefing/resource initialization, or replace saved wave/harassment timers.
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
