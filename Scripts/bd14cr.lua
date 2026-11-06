-- BlackDog14Mission.cpp port for stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source blob: 5217e98a56da2b57a53f32b9e3fdad6e788b1a18.
-- Complete source (including declarations, comments, and native serialization):
-- References/BlackDog14Source/BlackDog14Mission.cpp.
-- Requires the original mission's labels, paths, ODFs, AIP, WAV, OTF, and DES
-- assets. Map mission-class wiring is a separate integration step.
-- No EXU/OpenShim or Campaign Reimagined helper is required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN14_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn14CoopSourceParity.py).
-- CR co-op layer <<

local function NewState()
    return {
        -- bools: record whether the init code has been done
        startDone = false,
        -- objective complete? (objective1Complete is unused in the source)
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false,
        -- camera info (unused); preserve the source's zero-based array indices
        cameraReady = { [0] = false, [1] = false },
        cameraComplete = { [0] = false, [1] = false },
        -- attacks
        attack1 = false, attack2 = false,
        -- have we won/lost?
        wonLost = false,
        -- times: Setup overrides the native Load initialization (99999.0f)
        initialTime = 999999.9, sound2Time = 999999.9,
        sound3Time = 999999.9, sound4Time = 999999.9,
        wavesTime = 999999.9, scavTime = 999999.9,
        -- handles: User stuff, Units, and nav beacons (none in this mission)
        user = nil, lastUser = nil, recycler = nil, chinRecycler = nil, apc = nil,
        -- Sounds: native int IDs become Lua audio-message userdata
        sound1 = nil, sound6 = nil, sound7 = nil, sound8 = nil,
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN14_COOP.md lists every wrapped call and restoration.
-- RESTORED_TURRET_CONVOY switches the cut three-turret convoy back on (Docs/BDMISN14_COOP.md, "Restored content").
local RESTORED_TURRET_CONVOY = true
local Restored
local ENEMY_TEAM = 5 -- the body says team 2; team 2 is a human slot in co-op
-- Every Chinese combat craft (the attack waves, the ambushes, the APC's escort and the restored turret tanks)
-- becomes a concealed, head-count-scaled ticket. The APC itself and the scavengers are built straight through.
local SCALED_ODFS = { cvfigh = true, cvhraz = true, cvhtnk = true, cvltnk = true, cvwalk = true, cvtnk = true,
    cvtnkc = true, cvturr = true }
-- The geysers under the Chinese base: the factory sits on eggeizr13, the recycler on eggeizr15.
local FACTORY_VENT, RECYCLER_VENT = "eggeizr13_geyser", "eggeizr15_geyser"
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn14", leaderTeam = 1, enemyTeam = ENEMY_TEAM, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared Black Dog base is the recycler
    scaledOdfs = SCALED_ODFS,
    -- The Chinese waves leave from inside their own base and the ambush trigger is 150 m wide, so the default
    -- concealment ring (460 m) would hold every siege-time wave back: 120 m keeps units from popping into a
    -- human's face. A spawn that is watched comes from the next hidden eastern staging point instead.
    safeRadius = 120,
    fallbackEntries = { "spawn_attack_1", "spawn_apc", "spawn_turrets" },
    liveCap = 24, -- the APC wave alone is eighteen units, with the ambushes and the extras on top
    scrapPerGuest = 10,
    failDes = "bd14lose.des", -- out of lives: the stock generic debrief the DLL never names
    wonFlags = { "objective3Complete" }, -- the recycler is down: a late out-of-lives failure is ignored
    endedFlags = { "wonLost" }, -- the result is decided (won or lost): nothing more is built
    -- Ganymede: CREuropaWeather over the generated BD14 sites (five geyser vents, two under the Chinese base).
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD14",
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        startLevel = 1, targetLevel = 1,
        beats = function(ganymede, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local NEVER = 999999
            local function plume(label)
                for index, site in ipairs(ganymede.GetVentSites()) do
                    if site.label == label then return ganymede.TriggerPlume(index) end
                end
            end
            -- The timers read "never" before they are armed and after they fire: latch them while armed.
            if state.wavesTime < NEVER then beats.wavesArmed = true end
            -- The first Chinese raid breaks the silence: the quiet moon begins to stir.
            if (not beats.raid) and state.startDone and state.initialTime >= NEVER then
                beats.raid = true
                ganymede.SetTargetLevel(2)
            end
            -- The big cloaked assault leaves the base: the ice shell flexes.
            if (not beats.assault) and beats.wavesArmed and state.wavesTime >= NEVER then
                beats.assault = true
                ganymede.SetTargetLevel(3)
                ganymede.Quake(0.35, 3.0)
            end
            -- Black Dog reaches the base: the ambush springs over the factory's geyser or the recycler's.
            if (not beats.ambush1) and state.attack1 then
                beats.ambush1 = true
                ganymede.Quake(0.3, 2.5)
                plume(FACTORY_VENT)
            end
            if (not beats.ambush2) and state.attack2 then
                beats.ambush2 = true
                ganymede.Quake(0.3, 2.5)
                plume(RECYCLER_VENT)
            end
            -- The APC with the portal technology comes in: the worst of the sky, Jupiter's radiation surging.
            if (not beats.convoy) and state.apc ~= nil then
                beats.convoy = true
                ganymede.SetTargetLevel(4)
                ganymede.Quake(0.5, 3.5)
                ganymede.Surge(5.0, 0.9)
            end
            -- The shipment is stopped: the sky settles a step.
            if (not beats.intercepted) and state.objective2Complete then
                beats.intercepted = true
                ganymede.SetTargetLevel(3)
                ganymede.Quake(0.4, 3.0)
            end
            -- The Chinese recycler falls: the geyser beneath it opens, then the sky eases for the debrief.
            if (not beats.won) and state.objective3Complete then
                beats.won = true
                ganymede.Quake(0.5, 3.5)
                plume(RECYCLER_VENT)
                ganymede.SetTargetLevel(2)
            end
            -- The mission is lost (the pegasus arrives, or the Recycler is gone): a last surge over the base.
            if (not beats.lost) and state.wonLost and not state.objective3Complete then
                beats.lost = true
                ganymede.Surge(6.0, 0.8)
                ganymede.Quake(0.35, 3.0)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
        update = function(R, _, authority) if Restored then Restored.Update(R, authority) end end,
    },
})
local NativeSetCloaked, NativeGetDistance, NativeAudioDone = SetCloaked, GetDistance, IsAudioMessageDone
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Follow = campaignRuntime and campaignRuntime.Follow or Follow
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local SetAIP = campaignRuntime and campaignRuntime.SetAIP or SetAIP
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SetObjectiveOff = campaignRuntime and campaignRuntime.SetObjectiveOff or SetObjectiveOff
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- "The player" is the runtime's nearest-human token: the proximity ambushes fire for any human of any team.
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local IsValid = campaignRuntime and function(h)
    if h == campaignRuntime.PLAYERS then return true end
    return campaignRuntime.IsValid(h)
end or IsValid
-- The token's distance is the nearest human's. The runtime's WrapDistance forwards two arguments only, so every
-- other call keeps all of its arguments.
local GetDistance = campaignRuntime and (function()
    local nearestHuman = campaignRuntime.WrapDistance(NativeGetDistance)
    return function(from, to, ...)
        if from == campaignRuntime.PLAYERS then return nearestHuman(from, to) end
        return NativeGetDistance(from, to, ...)
    end
end)() or GetDistance
-- A failed AudioMessage yields 0, never nil: the body's gates (`sound ~= nil and done`) must still open.
local AudioMessage = campaignRuntime and function(file)
    return campaignRuntime.AudioMessage(file) or 0
end or AudioMessage
-- A line whose audio handle is absent (nil or 0) counts as finished, so no gate can wait on it for ever.
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return NativeAudioDone(message)
end
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool). Its team 2 (the Chinese, 100 pilots) is the co-op enemy: team 2 is a human slot.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
    elseif team == 2 then
        team = ENEMY_TEAM
    end
    return SetPilot(team, count)
end or SetPilot
-- Each scripted group (a new frame or a new entry path) is a new scaling event: the first unit of the group is
-- mirrored by min(floor(humans / 2), 2) extras with its orders. The APC and the scavengers are built straight through.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where)
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- Every Chinese craft is cloaked right after it is built. A unit that is still a ticket (a negative id) is cloaked
-- when the real unit is built (Restored.Built); a build refused after the result is nil and is ignored.
local SetCloaked = campaignRuntime and function(h)
    if h == nil then return end
    if type(h) == "number" and h < 0 then
        if Restored then Restored.DeferCloak(-h) end
        return
    end
    return NativeSetCloaked(h)
end or SetCloaked
-- CR co-op runtime <<

local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
-- Stock bug: bd14004 ("that APC's getting a little too close") is on a timer 50 s after the convoy appears and
-- plays even after the APC is dead ("Good work") or the mission is decided.
local AudioMessage = (function()
    local NativeAudioMessage = AudioMessage
    return function(file)
        if file == "bd14004.wav" and (M.objective2Complete or M.wonLost) then return 0 end
        return NativeAudioMessage(file)
    end
end)()

local function Health(h)
    -- PORT ADAPTATION: an absent/deleted native object has zero health.
    -- Preserve destruction conditions without querying a missing Lua handle.
    if not Valid(h) then return 0.0 end
    return GetHealth(h)
end

local function AtEndOfPath(h, path)
    -- PORT ADAPTATION: isAtEndOfPath is a native helper, not a stock Lua API.
    -- Stock Redux does expose path queries; use the final zero-based waypoint.
    -- TRO 1.3: 12 m 2D (x,z) distance to the last path point (FUN_0042b850).
    if not Valid(h) or Health(h) <= 0.0 then return false end
    local count = GetPathPointCount(path)
    if count <= 0 then return false end
    local p, q = GetPosition(h), GetPosition(path, count - 1)
    local dx, dz = p.x - q.x, p.z - q.z
    return math.sqrt(dx * dx + dz * dz) < 12.0
end

-- CR restored content >>
-- The co-op fixes that need state, the weather sensor binding and the cut turret convoy (Docs/BDMISN14_COOP.md
-- lists each). The convoy is gated by RESTORED_TURRET_CONVOY and by the map carrying its two paths.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    function Restored.DeferCloak(id)
        local r = RState()
        r.cloak = r.cloak or {}
        r.cloak[id] = true
    end
    function Restored.Built(h, request, id)
        local r = RState()
        local key = (request and request.primary) or id
        if r.cloak and r.cloak[key] then NativeSetCloaked(h) end
    end
    -- The objective list as the body publishes it, rebuilt from the mission state.
    local function ResetObjectives()
        local fired = M.startDone and M.initialTime >= 999999
        ClearObjectives()
        if not fired then return end
        if M.objective3Complete then
            AddObjective("bd14002.otf", "green")
            AddObjective("bd14003.otf", "green")
        elseif M.objective2Complete then
            AddObjective("bd14002.otf", "green")
            AddObjective("bd14003.otf", "white")
        elseif M.sound7 ~= nil then
            AddObjective("bd14001.otf", "red")
            AddObjective("bd14002.otf", "red")
        elseif M.sound2Time >= 999999 then
            AddObjective("bd14001.otf", "white")
            AddObjective("bd14002.otf", "white")
        else
            AddObjective("bd14001.otf", "white")
        end
    end
    local sensorsBound = false
    function Restored.OnLoad()
        sensorsBound = false
        RState().afterLoad = true
    end
    -- The runtime's Load resets the presentation (objective list, markers): the list and the APC's marker come back.
    function Restored.AfterLoad()
        ResetObjectives()
        if Valid(M.apc) and not M.objective2Complete then SetObjectiveOn(M.apc) end
    end
    -- Every peer, every frame. The weather director's sensor modifier follows the director once both exist.
    function Restored.Update(R)
        if not sensorsBound and R.Weather and R.Weather.module.Initialized then
            sensorsBound = true
            pcall(function() require("Environment").BindWeatherSensors("Ganymede", R.Weather.module) end)
        end
    end
    -- Cut content: three Chinese turret tanks ride in behind the APC (`#if 0` block of SOE #5: BuildObject cvturr
    -- at spawn_turrets, Goto path_turrets). They are built in the frame the body builds the APC.
    function Restored.TurretConvoy(r)
        if not RESTORED_TURRET_CONVOY or r.turrets or M.apc == nil or M.wonLost then return end
        r.turrets = true
        if not runtime.PathExists("spawn_turrets") or not runtime.PathExists("path_turrets") then return end
        for _ = 1, 3 do
            local h = BuildObject("cvturr", 2, "spawn_turrets")
            Goto(h, "path_turrets")
        end
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad() end
        Restored.TurretConvoy(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn14] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    -- Native Load/Setup defaults. LuaMission manages handle conversion on Load.
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    M.recycler = GetHandle("recycler")
    M.chinRecycler = GetHandle("chin_recycler")
end

function AddObject(h)
    -- Native AddObject(Handle h) is empty; engine bookkeeping is automatic.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<

    M.lastUser = M.user
    M.user = GetPlayerHandle() --assigns the player a handle every frame

    -- SOE #1
    if not M.startDone then
        SetAIP("bdmisn14.aip")
        SetScrap(1,4)
        SetPilot(1,10)
        SetScrap(2, 0)
        SetPilot(2, 100)

         -- don't do this part after the first shot
        M.startDone = true

        M.sound1 = AudioMessage("bd14001.wav")

        M.initialTime = GetTime()

         -- cloak some of the units
        SetCloaked(GetHandle("start1_1"))
        SetCloaked(GetHandle("start1_2"))
        SetCloaked(GetHandle("start1_3"))
        SetCloaked(GetHandle("start2_1"))
        SetCloaked(GetHandle("start2_2"))
        SetCloaked(GetHandle("start2_3"))
    end

    if M.sound1 ~= nil and IsAudioMessageDone(M.sound1) then
        M.sound1 = nil
    end

    if M.initialTime < GetTime() then
        M.initialTime = 999999.9

        local h
        h = BuildObject("cvfigh", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        h = BuildObject("cvfigh", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        h = BuildObject("cvfigh", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")
        -- TRO 1.3: one cvhraz in the opening strike (FUN_005ac1a0)
        h = BuildObject("cvhraz", 2, "spawn_initial_attack")
        SetCloaked(h)
        Goto(h, "path_initial_attack")

        ClearObjectives()
        AddObjective("bd14001.otf", "white")

        M.sound2Time = GetTime() + 120.0
        M.wavesTime = GetTime() + 240.0
    end

    -- SOE #2
    if M.sound2Time < GetTime() then
        M.sound2Time = 999999.9
        AudioMessage("bd14002.wav")
        ClearObjectives()
        AddObjective("bd14001.otf", "white")
        AddObjective("bd14002.otf", "white")
    end

    -- SOE #3
    if M.wavesTime < GetTime() then
        M.wavesTime = 999999.9

        local h
        h = BuildObject("cvhtnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvhtnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        -- TRO 1.3: 1 cvltnk + 2 cvtnk close the main wave (FUN_005ac1a0)
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvtnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvtnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")

        M.sound3Time = GetTime() + 5 * 60.0
    end

    -- SOE #4 (missing)

    -- SOE #5
    if M.sound3Time < GetTime() then
        M.sound3Time = 999999.9

        AudioMessage("bd14003.wav")

        local h
        M.apc = BuildObject("cvapcc", 2, "spawn_apc")
        SetObjectiveOn(M.apc)
        Goto(M.apc, "path_apc_travel")
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)
        h = BuildObject("cvtnk", 2, "spawn_apc")
        Defend2(h, M.apc)

        --[[ #if 0 (cut content; intentionally inactive)
		// turrets
		h = BuildObject("cvturr", 2, "spawn_turrets");
		Goto(h, "path_turrets");
		h = BuildObject("cvturr", 2, "spawn_turrets");
		Goto(h, "path_turrets");
		h = BuildObject("cvturr", 2, "spawn_turrets");
		Goto(h, "path_turrets");
        #endif ]]
         -- attackers
        -- TRO 1.3: 2 cvhraz, 1 cvltnk, 2 cvfigh (FUN_005ac1a0)
        h = BuildObject("cvhraz", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvhraz", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvltnk", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        h = BuildObject("cvfigh", 2, "spawn_attack_waves")
        SetCloaked(h)
        Goto(h, "path_attack_waves")
        -- SOURCE BUG FIX: each native walker spawn calls SetCloaked(h), where
        -- h still names the last light tank. Cloak w1/w2/w3 instead so the
        -- walkers match their cloaked wave. Unit counts, spawn order, routes,
        -- followers, event conditions, and timers are unchanged; only the
        -- intended cloak state changes (which can affect detection/combat).
        local w1 = BuildObject("cvwalk", 2, "spawn_attack_waves")
        SetCloaked(w1)
        Goto(w1, "path_attack_waves")
        local w2 = BuildObject("cvwalk", 2, "spawn_attack_waves")
        SetCloaked(w2)
        Goto(w2, "path_attack_waves")
        local w3 = BuildObject("cvwalk", 2, "spawn_attack_waves")
        SetCloaked(w3)
        Goto(w3, "path_attack_waves")
        h = BuildObject("cvtnkc", 2, "spawn_attack_waves")
        Follow(h, w1)
        h = BuildObject("cvtnkc", 2, "spawn_attack_waves")
        Follow(h, w2)
        h = BuildObject("cvtnkc", 2, "spawn_attack_waves")
        Follow(h, w3)


        M.sound4Time = GetTime() + 50.0
    end

    -- SOE #6
    if M.sound4Time < GetTime() then
        M.sound4Time = 999999.9

        AudioMessage("bd14004.wav")
    end

    -- SOE #7
    if not M.objective2Complete and M.apc ~= nil and Health(M.apc) <= 0.0 then
        -- PORT ADAPTATION: a deleted APC still completes the intercept, but
        -- its vanished marker needs no mutation through an invalid handle.
        if Valid(M.apc) then SetObjectiveOff(M.apc) end
        M.objective2Complete = true

        AudioMessage("bd14005.wav")

        ClearObjectives()
        AddObjective("bd14002.otf", "green")
        AddObjective("bd14003.otf", "white")

        M.scavTime = GetTime() + 4 * 60.0
    end

    if M.scavTime < GetTime() then
        M.scavTime = 999999.9

        BuildObject("cvscav", 2, "spawn_scav")
        BuildObject("cvscav", 2, "spawn_scav")
    end

    -- SOE #8
    if not M.objective3Complete and Health(M.chinRecycler) <= 0.0 and not M.wonLost then
        M.wonLost = true
        M.objective3Complete = true

        ClearObjectives()
        AddObjective("bd14002.otf", "green")
        AddObjective("bd14003.otf", "green")

        M.sound6 = AudioMessage("bd14006.wav")
    end

    if M.sound6 ~= nil and IsAudioMessageDone(M.sound6) then
        M.sound6 = nil
        SucceedMission(GetTime(), "bd14win.des")
    end

    -- SOE #9
    -- SOURCE BUG FIX: the native test has no APC existence/death guard, even
    -- after SOE #7 records its destruction. A wreck at the endpoint must not
    -- lose an already completed intercept. This only excludes absent/dead APCs;
    -- the living APC's arrival loss and the source's win/loss precedence remain.
    if not M.objective2Complete and not M.objective3Complete and AtEndOfPath(M.apc, "path_apc_travel") and not M.wonLost then
        M.wonLost = true
        M.sound7 = AudioMessage("bd14007.wav")

        ClearObjectives()
        AddObjective("bd14001.otf", "red")
        AddObjective("bd14002.otf", "red")
    end

    if M.sound7 ~= nil and IsAudioMessageDone(M.sound7) then
        M.sound7 = nil
        FailMission(GetTime(), "bd14lsea.des")
    end

    -- SOE #10
    if Health(M.recycler) <= 0.0 and not M.wonLost then
        M.wonLost = true
        M.sound8 = AudioMessage("bd14008.wav")
    end

    if M.sound8 ~= nil and IsAudioMessageDone(M.sound8) then
        M.sound8 = nil
        FailMission(GetTime(), "bd14lseb.des")
    end

    -- PORT FIX: an absent player handle cannot trigger proximity ambushes.
    -- Valid-player distances, thresholds, and one-shot timing are unchanged.
    if not M.attack1 and Valid(M.user) and GetDistance(M.user, "trigger_attack_1") < 150.0 then
        M.attack1 = true

        -- TRO 1.3: 2 cvhraz, 2 cvltnk, 2 cvtnk, 2 cvfigh (FUN_005ac1a0)
        for i = 0, 1 do
            local h = BuildObject("cvhraz", 2, "spawn_attack_1")
            Goto(h, "path_attack_1")
            SetCloaked(h)
        end
        for i = 0, 1 do
            local h = BuildObject("cvltnk", 2, "spawn_attack_1")
            Goto(h, "path_attack_1")
            SetCloaked(h)
        end
        for i = 0, 1 do
            local h = BuildObject("cvtnk", 2, "spawn_attack_1")
            Goto(h, "path_attack_1")
            SetCloaked(h)
        end
        for i = 0, 1 do
            local h = BuildObject("cvfigh", 2, "spawn_attack_1")
            Goto(h, "path_attack_1")
            SetCloaked(h)
        end
        for i = 0, 1 do
            local h = BuildObject("cvwalk", 2, "spawn_defend")
            Goto(h, "path_defend")
        end
        for i = 0, 4 do
            local h = BuildObject("cvltnk", 2, "spawn_defend")
            Goto(h, "path_defend")
        end
    end

    if not M.attack2 and Valid(M.user) and GetDistance(M.user, "trigger_attack_2") < 150.0 then
        M.attack2 = true

        -- TRO 1.3: 3 cvltnk + 2 cvtnk (FUN_005ac1a0)
        for i = 0, 2 do
            local h = BuildObject("cvltnk", 2, "spawn_attack_2")
            Goto(h, "path_attack_2")
            SetCloaked(h)
        end
        for i = 0, 1 do
            local h = BuildObject("cvtnk", 2, "spawn_attack_2")
            Goto(h, "path_attack_2")
            SetCloaked(h)
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
    -- All mission state, including unused fields and audio handles, is saved.
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Save() end
-- CR co-op callback <<
    return M
end

function Load(state)
    -- Do not replay Setup, resources, audio, or spawns after restoring a game.
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
