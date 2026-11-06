-- Faithful BlackDog02Mission port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/BlackDog02Mission.cpp
-- Source blob: 3d27e9760c7eb6d4a4f0adaf8c263552b66c3b23.
-- Disabled C++ is retained in place; the complete original (including native
-- declarations, serialization and all comments) is in References/BlackDog02Source/.
-- Stock BZR 2.1+ is required for SetCloaked. No campaign helpers are required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN02_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn02CoopSourceParity.py).
-- CR co-op layer <<

-- Keep the original state numbers and spellings, including the gap at state 12.
local MS_STARTUP = 0
local MS_FIRSTWAVE = 1
local MS_WAITFORSOUND1 = 2
local MS_WAITFORWAVE1 = 3
local MS_PLAYDECLOCK = 4
local MS_WAITINGOBJ2 = 5
local MS_WAVE1DEAD = 6
local MS_WAITFORWAVE2 = 7
local MS_WAVE2DEAD = 8
local MS_PLAYSOUND4 = 9
local MS_WAITFORSOUND4 = 10
local MS_WAITFORSOUND5 = 11
local MS_HARRASDEAD = 13
local MS_WAITFORBOMBERRUN = 14
local MS_BOMBERRUN = 15
local MS_RECYCLERDIE = 16
local MS_ENDWAIT = 17
local MS_END = 18

local function NewState()
    return {
        -- bools: have we lost? / recycler retreat ambush latch
        lost = false, recyclerRetreated = false,
        -- floats: timer to say when the next state starts / so I know when it's been hit..
        stateTimer = 99999.0, recyclerHealth = 99999.0,
        -- PORT FIX: native Load sets deadTimer to 99999; if the player is dead
        -- on the first Update, that postpones the death check for hours. Zero
        -- arms the intended two-second grace period immediately. A normal
        -- living-player first frame already writes zero, so normal flow is unchanged.
        deadTimer = 0,
        -- integers: the state of the mission / sound handle (nil replaces C++ 0)
        missionState = MS_STARTUP,
        -- Handles start nil: user, recycler, wave1_scout1/2, wave1_tank1,
        -- wave2_scout1..4, enemy_scout1..4, enemy_ltnk1/2, enemy_tank1/2,
        -- enemy_turret1..4, nav_alpha, harrass_scout1, harrass_ltnk1,
        -- bomber1_scripted, bomber2_scripted; soundhandle is audio userdata.
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN02_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/BDMISN02_COOP.md, "Restored content").
local RESTORED_BOMBER_ROUTES = true
local Restored
-- The Chinese combat craft become concealed, head-count-scaled tickets. The bombers (cvhraz) are scripted
-- actors and the units of the two films are stage props: all of those are built directly (see STAGE_PATHS).
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true }
-- Spawn paths whose unit a camera must see: the decloak shot's scout and the whole massive-attack wave.
local STAGE_PATHS = {
    spawn_wave1_scout1 = true,
    spawn_enemy_scout1 = true, spawn_enemy_scout2 = true, spawn_enemy_scout3 = true, spawn_enemy_scout4 = true,
    spawn_enemy_ltnk = true, spawn_enemy_ltnk2 = true, spawn_enemy_tank = true, spawn_enemy_tank2 = true,
}
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bd02cr", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared base is the recycler
    scaledOdfs = SCALED_ODFS,
    -- A unit whose entry has a human within 460 m comes from the next hidden Chinese approach instead.
    fallbackEntries = { "spawn_wave2_scout3", "spawn_wave1_scout2", "spawn_wave2_scout1", "spawn_bomber_1" },
    scrapPerGuest = 10,
    failDes = "bd02lose.des",
    wonFlags = { "crWon" },
    endedFlags = { "lost", "crWon" },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesBD02",
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        startLevel = 1, targetLevel = 1,
        beats = function(ganymede, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local mission = state.missionState or 0
            local function vent(label)
                for index, site in ipairs(ganymede.GetVentSites()) do
                    if site.label == label then return index end
                end
            end
            -- The first Chinese wave decloaks over the ridge: the quiet moon begins to stir.
            if (not beats.stirring) and mission >= MS_PLAYDECLOCK then
                beats.stirring = true
                ganymede.SetTargetLevel(2)
            end
            -- The massive attack: the ice shell flexes and Jupiter's radiation surges over the column.
            if (not beats.massive) and mission >= MS_WAITFORSOUND4 then
                beats.massive = true
                ganymede.SetTargetLevel(3)
                ganymede.Quake(0.35, 3.0)
                ganymede.Surge(6.0, 0.8)
            end
            -- The recycler is crippled and runs: a geyser erupts at the abandoned base.
            if (not beats.retreat) and mission >= MS_HARRASDEAD then
                beats.retreat = true
                ganymede.SetTargetLevel(4)
                ganymede.TriggerPlume(vent("eggeizr11_geyser"))
            end
            -- The bombers come in: another vent opens along their run.
            if (not beats.bombers) and mission >= MS_BOMBERRUN then
                beats.bombers = true
                ganymede.TriggerPlume(vent("eggeizr10_geyser"))
            end
            -- The recycler goes down: a hard quake and a surge, then the sky eases for the debrief.
            if (not beats.down) and mission >= MS_ENDWAIT then
                beats.down = true
                ganymede.Quake(0.6, 4.0)
                ganymede.Surge(5.0, 0.9)
            end
            if (not beats.easing) and mission >= MS_END then
                beats.easing = true
                ganymede.SetTargetLevel(2)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
        -- The sensor modifier of the weather director, bound once it exists (misn12cr / misn13cr do the same).
        update = function(R) if Restored then Restored.Sensors(R) end end,
    },
})
local NativeBuildObject = BuildObject
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local GetDistance = campaignRuntime and campaignRuntime.GetDistance or GetDistance
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraPath = campaignRuntime and campaignRuntime.CameraPath or CameraPath
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local ClearObjectives = campaignRuntime and campaignRuntime.ClearObjectives or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local SucceedMission = campaignRuntime and function(when, description)
    M.crWon = true
    return campaignRuntime.SucceedMission(when, description)
end or SucceedMission
-- Stock bug (CR layer only): the recycler-loss debrief bd02lsea.des does not exist in the game; the generic
-- defeat debrief is used for it.
local FailMission = campaignRuntime and function(when, description)
    if description == "bd02lsea.des" then description = "bd02lose.des" end
    return campaignRuntime.FailMission(when, description)
end or FailMission
-- The body's "player" (M.user) is the runtime's nearest-human token, so every order aimed at it and every
-- liveness test on it needs a meaning. The shadows below sit BEFORE the body's Valid/Alive helpers.
local IsValid, IsAlive, Goto, Attack = IsValid, IsAlive, Goto, Attack
local IsAudioMessageDone, RemoveObject, SetPilot, CameraPathDir = IsAudioMessageDone, RemoveObject, SetPilot, CameraPathDir
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
    local function AnyHumanAlive()
        local alive = false
        runtime.Coop.ForEachPlayerHandle(function(human)
            if runtimeIsAlive(human) then alive = true end
        end)
        return alive
    end
    IsAlive = function(h)
        -- Offline the player dying fails the mission after the body's two-second grace, as in the DLL. In a
        -- network game the shared lives (CRCoop) own that decision, so the token never reads as dead.
        if h == PLAYERS then return runtime.Coop.IsNetworkGame() or AnyHumanAlive() end
        if PendingTicket(h) then return runtime.State().arrivals[-h] ~= nil end
        return runtimeIsAlive(h)
    end
    -- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever.
    local nativeAudioDone = IsAudioMessageDone
    IsAudioMessageDone = function(message)
        if message == nil or message == 0 then return true end
        return nativeAudioDone(message)
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
    -- A unit that is still a ticket is cancelled, not removed (the runtime would send a negative handle).
    RemoveObject = function(h)
        if PendingTicket(h) then
            runtime.State().arrivals[-h] = nil
            return
        end
        return runtime.RemoveObject(h)
    end
    -- Pilots are the lives CRCoop owns in a network game; offline the body keeps its own bookkeeping.
    local nativeSetPilot = SetPilot
    SetPilot = function(team, count)
        if runtime.Coop.IsNetworkGame() and team >= 1 and team <= 4 then return end
        return nativeSetPilot(team, count)
    end
    -- Stock bug: the final fallback shot is a native CameraPathDir, which no guest would see. Keep the shot on
    -- the shared stream, aimed at a surviving bomber (they cannot be killed), else path-only.
    CameraPathDir = function(path, height, speed)
        local target
        for _, key in ipairs({ "bomber1_scripted", "bomber2_scripted" }) do
            local h = M[key]
            if h ~= nil and h ~= 0 and runtimeIsValid(h) then target = h; break end
        end
        return runtime.CameraPath(path, height, speed, target)
    end
    -- Stage props are built directly; every other scaled craft is a ticket. One scaling event per frame: the
    -- first scaled unit of a scripted wave is mirrored by min(floor(humans / 2), 2) extras with its orders.
    local eventFrame
    BuildObject = function(odf, team, where)
        if STAGE_PATHS[where] then return NativeBuildObject(odf, team == 2 and 5 or team, where) end
        if SCALED_ODFS[odf] then
            local now = GetTime()
            if eventFrame ~= now then
                eventFrame = now
                runtime.BeginEvent()
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

local function Distance(h, path)
    -- PORT FIX: an absent object must not satisfy a proximity trigger. Guard
    -- the Lua handle overload; distances for surviving objects are unchanged.
    if not Valid(h) then return math.huge end
    return GetDistance(h, path)
end

local function HealBomber(h)
    -- PORT FIX: native code tests only a nonzero handle, then dereferences
    -- GetObj even after destruction. Skip missing objects instead of crashing;
    -- surviving bombers receive exactly the same per-frame health top-up.
    -- This does not resurrect/rebuild bombers or make them damage-immune.
    if Valid(h) then
        local current, maximum = GetCurHealth(h), GetMaxHealth(h)
        if current ~= maximum then AddHealth(h, maximum - current) end
    end
end

local function RecyclerCamera()
    if Valid(M.recycler) then
        CameraPath("camera_bomber_chasecam", 1000, 0, M.recycler)
    else
        -- PORT FIX: destruction can invalidate the camera's target before the
        -- final narration ends. Continue on the same path facing along it;
        -- no replacement unit, mission gate, narration or delay is introduced.
        CameraPathDir("camera_bomber_chasecam", 1000, 0)
    end
end

local function ResetObjectives()
    ClearObjectives()
    if M.missionState < MS_HARRASDEAD then
        AddObjective("bd02001.otf", M.missionState >= MS_WAVE1DEAD and "green" or "white")
        if M.missionState >= MS_WAITFORSOUND4 then
            AddObjective("bd02002.otf", "green")
        elseif M.missionState >= MS_WAVE1DEAD then
            AddObjective("bd02002.otf", "white")
        end
    end
    if M.missionState >= MS_END then
        AddObjective("bd02003.otf", "red")
    elseif M.missionState >= MS_HARRASDEAD then
        AddObjective("bd02003.otf", "white")
    end
end

-- CR restored content >>
-- Content the DLL cut, restored in the CR layer only (Docs/BDMISN02_COOP.md lists each one with the cut block
-- it comes from), plus the co-op fixes that need state. Each restoration is gated by a RESTORED_* flag and by
-- the map actually carrying the path, so a map without it runs the faithful mission.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local function Present(h) return h ~= nil and h ~= 0 and IsValid(h) end
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    local BOMBER_ROUTES = { { "bomber1_scripted", "path_bomber_1_attackpath" }, { "bomber2_scripted", "path_bomber_2_attackpath" } }
    local BOMBER_ROUTE_SECONDS = 60 -- a bomber that has not finished its route by then attacks anyway
    local BOMBER_ROUTE_GRACE = 3    -- a fresh Goto may still read as no command for a moment
    local HARRASS_PATHS = { spawn_scout1_harrass = true, spawn_ltnk1_harrass = true }
    -- A ticket becoming a unit: an order aimed at the player is issued to the nearest human; the harassment
    -- group (the body removes only its two named units) is remembered so extras can be removed with them.
    function Restored.Built(h, request, id)
        local r = RState()
        local key = tostring((request and request.primary) or id)
        local op = r.orders and r.orders[key]
        if op then
            local human = runtime.NearestHumanTo(h)
            if human ~= nil then runtime[op](h, human) end
        end
        if request and HARRASS_PATHS[request.where] then
            r.harrass = r.harrass or {}
            r.harrass[#r.harrass + 1] = h
        end
    end
    -- The weather director's sensor modifier follows the director once both exist.
    local sensorsBound = false
    function Restored.OnLoad()
        sensorsBound = false
        RState().afterLoad = true
    end
    function Restored.Sensors(R)
        if sensorsBound or not R.Weather or not R.Weather.module.Initialized then return end
        sensorsBound = true
        pcall(function() require("Environment").BindWeatherSensors("Ganymede", R.Weather.module) end)
    end
    -- A load cannot resume a camera (the shots are gone): the states that hold one open it again; the body
    -- keeps calling its CameraPath every frame and ends the film itself.
    local FILM_STATES = { [MS_PLAYDECLOCK] = true, [MS_WAITFORSOUND4] = true, [MS_WAITFORSOUND5] = true,
        [MS_RECYCLERDIE] = true, [MS_ENDWAIT] = true }
    function Restored.AfterLoad()
        if FILM_STATES[M.missionState] and not M.lost then CameraReady() end
    end
    -- Cut: `//Goto(bomber_scripted, "path_bomber_attackpath");` in front of the Attack on the recycler. The map
    -- carries one authored route per bomber that ends at the bomber-chase camera trigger, which the body tests
    -- (within 50 m) to start the final film. The bombers fly their route first and attack once they finish it
    -- (or when the film has begun, or after BOMBER_ROUTE_SECONDS).
    function Restored.BomberRoutes(r)
        if not RESTORED_BOMBER_ROUTES or r.bombersDone then return end
        if M.missionState ~= MS_BOMBERRUN and M.missionState ~= MS_RECYCLERDIE then return end
        local now = GetTime()
        if not r.bomberStart then
            local routed = false
            for _, route in ipairs(BOMBER_ROUTES) do
                if Present(M[route[1]]) and runtime.PathExists(route[2]) then
                    Goto(M[route[1]], route[2])
                    routed = true
                end
            end
            if not routed then r.bombersDone = true; return end
            r.bomberStart = now
            return
        end
        local go = M.missionState == MS_RECYCLERDIE or now - r.bomberStart >= BOMBER_ROUTE_SECONDS
        if not go and now - r.bomberStart >= BOMBER_ROUTE_GRACE then
            for _, route in ipairs(BOMBER_ROUTES) do
                local h = M[route[1]]
                if Present(h) and GetCurrentCommand(h) == AiCommand.NONE then go = true end
            end
        end
        if go then
            r.bombersDone = true
            for _, route in ipairs(BOMBER_ROUTES) do
                if Present(M[route[1]]) and Present(M.recycler) then Attack(M[route[1]], M.recycler) end
            end
        end
    end
    -- Co-op extras are not in the body's lists: when the body removes the harassment pair, the extras go too.
    function Restored.HarrassSweep(r)
        if M.missionState < MS_BOMBERRUN or r.harrassSwept then return end
        r.harrassSwept = true
        for _, h in ipairs(r.harrass or {}) do
            if Present(h) then RemoveObject(h) end
        end
        -- Extras still waiting for a hidden approach are cancelled, never built after the pair is gone.
        local arrivals = runtime.State().arrivals
        for id, request in pairs(arrivals) do
            if HARRASS_PATHS[request.where] then arrivals[id] = nil end
        end
    end
    -- Stock hang: the decloak film ends only when the host's own camera arrives (or the host skips it). In a
    -- network game a skip by the host releases its view for good and CameraPath is never answered again, so
    -- the film (and the whole mission) would wait for ever. After DECLOAK_GUARD seconds the film is ended
    -- exactly as the body ends it.
    local DECLOAK_GUARD = 30
    function Restored.FilmGuard(r)
        if M.missionState ~= MS_PLAYDECLOCK or not runtime.Coop.IsNetworkGame() then r.decloakStart = nil; return end
        local now = GetTime()
        if not r.decloakStart then r.decloakStart = now; return end
        if now - r.decloakStart >= DECLOAK_GUARD then
            r.decloakStart = nil
            CameraFinish()
            M.missionState = MS_WAITINGOBJ2
            M.stateTimer = now + 5
        end
    end
    -- Runs at the end of the body's Update, in the frame the triggering block ran.
    function Restored.Step()
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad() end
        Restored.FilmGuard(r)
        Restored.BomberRoutes(r)
        Restored.HarrassSweep(r)
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bd02cr] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    -- Setup: resource/cloak/objective startup still happens on the first Update.
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    M.recycler = GetHandle("recycler")
    M.enemy_turret1 = GetHandle("enemy_turret1")
    M.enemy_turret2 = GetHandle("enemy_turret2")
    M.enemy_turret3 = GetHandle("enemy_turret3")
    M.enemy_turret4 = GetHandle("enemy_turret4")
end

function AddObject(h)
    --[[ Original cut factory gate. MS_WAITFORFACTORY is not defined in this mission.
	if (missionState == MS_WAITFORFACTORY && IsOdf(h, "bvmuf"))
	{
		// set to first wave and setup the timer till it kicks off
		missionState = MS_WAITFORWAVE1;
		stateTimer = GetTime() + (60 + 5); // 30 seconds to build factory??
//		stateTimer = GetTime() + (5); // 30 seconds to build factory??
		resetObjectives();
	}
    ]]
end

local function Lose(filename)
    FailMission(GetTime() + 2.0, filename)
    M.lost = true
    -- PORT FIX: release an active pre-ending cinematic on defeat; native code
    -- can leave camera control held. This only releases the view and retains
    -- the original failure filename and two-second delay.
    if M.missionState == MS_PLAYDECLOCK or M.missionState == MS_WAITFORSOUND4
        or M.missionState == MS_WAITFORSOUND5 then
        CameraFinish()
    end
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    -- PORT FIX: once defeat is scheduled, stop mission work even if the player
    -- is still dead. Native !lost && !IsAlive can otherwise leave one more
    -- state transition in the recycler-loss frame, entering the ending and
    -- bypassing its later lost check. Living mission flow is unchanged.
    if M.lost then return end
    if M.missionState < MS_RECYCLERDIE then
        if not Alive(M.user) then
            -- Lua considers 0 true; explicitly reproduce C++'s timer test.
            if M.deadTimer ~= 0 then
                if M.deadTimer < GetTime() then
                    Lose("bd02lose.des")
                    return
                end
            else
                M.deadTimer = GetTime() + 2
            end
        else
            M.deadTimer = 0
        end
        if not Alive(M.recycler) then
            Lose("bd02lsea.des")
            return
        end
    end

    local state = M.missionState
    if state == MS_STARTUP then
        SetScrap(1, 20)
        SetPilot(1, 10)
        -- setup the cloaked turrets
        if Valid(M.enemy_turret1) then SetCloaked(M.enemy_turret1) end
        if Valid(M.enemy_turret2) then SetCloaked(M.enemy_turret2) end
        if Valid(M.enemy_turret3) then SetCloaked(M.enemy_turret3) end
        if Valid(M.enemy_turret4) then SetCloaked(M.enemy_turret4) end
        -- setup the initial objectives
        ResetObjectives()
        M.missionState = MS_FIRSTWAVE
        M.stateTimer = GetTime() + 2
    elseif state == MS_FIRSTWAVE then
        if M.stateTimer < GetTime() then
            M.soundhandle = AudioMessage("bd02001.wav")
            M.missionState = MS_WAITFORSOUND1
            M.stateTimer = 0
        end
    elseif state == MS_WAITFORSOUND1 then
        if IsAudioMessageDone(M.soundhandle) then
            M.missionState = MS_WAITFORWAVE1
            M.stateTimer = GetTime() + 20
        end
    elseif state == MS_WAITFORWAVE1 then
        if M.stateTimer < GetTime() then
            M.wave1_scout1 = BuildObject("cvfigh", 2, "spawn_wave1_scout1")
            M.wave1_scout2 = BuildObject("cvfigh", 2, "spawn_wave1_scout2")
            M.wave1_tank1 = BuildObject("cvtnk", 2, "spawn_wave1_tank1")
            AudioMessage("bd02002.wav")
            CameraReady()
            M.missionState = MS_PLAYDECLOCK
            if Valid(M.wave1_scout1) then Goto(M.wave1_scout1, "wave1_scout1_attackpath") end
            if Valid(M.wave1_scout2) then Goto(M.wave1_scout2, "wave1_scout2_attackpath") end
            if Valid(M.wave1_tank1) then Goto(M.wave1_tank1, "wave1_tank1_attackpath") end
            -- Native switch deliberately falls through into MS_PLAYDECLOCK.
            state = MS_PLAYDECLOCK
        end
    elseif state == MS_WAITINGOBJ2 then
        if M.stateTimer < GetTime() then
            M.missionState = MS_WAVE1DEAD
            AudioMessage("bd02003.wav")
            ResetObjectives()
        end
    elseif state == MS_WAVE1DEAD then
        if not Alive(M.wave1_scout1) and not Alive(M.wave1_scout2) and not Alive(M.wave1_tank1) then
            M.missionState = MS_WAITFORWAVE2
            M.stateTimer = GetTime() + 20
        end
    elseif state == MS_WAITFORWAVE2 then
        if M.stateTimer < GetTime() then
            M.missionState = MS_WAVE2DEAD
            M.wave2_scout1 = BuildObject("cvfigh", 2, "spawn_wave2_scout1")
            M.wave2_scout2 = BuildObject("cvfigh", 2, "spawn_wave2_scout2")
            M.wave2_scout3 = BuildObject("cvfigh", 2, "spawn_wave2_scout3")
            M.wave2_scout4 = BuildObject("cvfigh", 2, "spawn_wave2_scout4")
            -- TRO 1.3: wave 2 attacks the recycler directly instead of following authored paths
            if Valid(M.wave2_scout1) and Valid(M.recycler) then Attack(M.wave2_scout1, M.recycler) end
            if Valid(M.wave2_scout2) and Valid(M.recycler) then Attack(M.wave2_scout2, M.recycler) end
            if Valid(M.wave2_scout3) and Valid(M.recycler) then Attack(M.wave2_scout3, M.recycler) end
            if Valid(M.wave2_scout4) and Valid(M.recycler) then Attack(M.wave2_scout4, M.recycler) end
        end
    elseif state == MS_WAVE2DEAD then
        if not Alive(M.wave2_scout1) and not Alive(M.wave2_scout2)
            and not Alive(M.wave2_scout3) and not Alive(M.wave2_scout4) then
            M.missionState = MS_PLAYSOUND4
            M.stateTimer = GetTime() + 10
        end
    elseif state == MS_PLAYSOUND4 then
        if M.stateTimer < GetTime() then
            M.soundhandle = AudioMessage("bd02004.wav")
            M.missionState = MS_WAITFORSOUND4
            ResetObjectives()
            M.enemy_scout1 = BuildObject("cvfigh", 2, "spawn_enemy_scout1")
            M.enemy_scout2 = BuildObject("cvfigh", 2, "spawn_enemy_scout2")
            M.enemy_scout3 = BuildObject("cvfigh", 2, "spawn_enemy_scout3")
            M.enemy_scout4 = BuildObject("cvfigh", 2, "spawn_enemy_scout4")
            M.enemy_ltnk1 = BuildObject("cvltnk", 2, "spawn_enemy_ltnk")
            M.enemy_ltnk2 = BuildObject("cvltnk", 2, "spawn_enemy_ltnk2")
            M.enemy_tank1 = BuildObject("cvtnk", 2, "spawn_enemy_tank")
            M.enemy_tank2 = BuildObject("cvtnk", 2, "spawn_enemy_tank2")
            if Valid(M.enemy_scout1) then Goto(M.enemy_scout1, "spawn_nav_alpha") end
            if Valid(M.enemy_scout2) then Goto(M.enemy_scout2, "spawn_nav_alpha") end
            if Valid(M.enemy_scout3) then Goto(M.enemy_scout3, "spawn_nav_alpha") end
            if Valid(M.enemy_scout4) then Goto(M.enemy_scout4, "spawn_nav_alpha") end
            if Valid(M.enemy_ltnk1) then Goto(M.enemy_ltnk1, "spawn_nav_alpha") end
            if Valid(M.enemy_ltnk2) then Goto(M.enemy_ltnk2, "spawn_nav_alpha") end
            if Valid(M.enemy_tank1) then Goto(M.enemy_tank1, "spawn_nav_alpha") end
            if Valid(M.enemy_tank2) then Goto(M.enemy_tank2, "spawn_nav_alpha") end
            if Alive(M.enemy_turret1) then Goto(M.enemy_turret1, "path_turret1") end
            if Alive(M.enemy_turret2) then Goto(M.enemy_turret2, "path_turret2") end
            if Alive(M.enemy_turret3) then Goto(M.enemy_turret3, "path_turret3") end
            if Alive(M.enemy_turret4) then Goto(M.enemy_turret4, "path_turret4") end
            CameraReady()
            -- The second intentional native switch fall-through.
            state = MS_WAITFORSOUND4
        end
    elseif state == MS_WAITFORSOUND5 then
        -- TRO 1.3: cancelling the film skips the rest of the sequence (read before CameraPath)
        local skipped = M.massiveSkipped or CameraCancelled()
        if Valid(M.enemy_tank1) then CameraPath("camera_massive_attack", 2000, 10, M.enemy_tank1) end
        if skipped or IsAudioMessageDone(M.soundhandle) then
            if skipped and M.soundhandle ~= nil and not IsAudioMessageDone(M.soundhandle) then
                StopAudioMessage(M.soundhandle)
            end
            CameraFinish()
            if Valid(M.enemy_scout1) then RemoveObject(M.enemy_scout1) end
            if Valid(M.enemy_scout2) then RemoveObject(M.enemy_scout2) end
            if Valid(M.enemy_scout3) then RemoveObject(M.enemy_scout3) end
            if Valid(M.enemy_scout4) then RemoveObject(M.enemy_scout4) end
            if Valid(M.enemy_ltnk1) then RemoveObject(M.enemy_ltnk1) end
            if Valid(M.enemy_ltnk2) then RemoveObject(M.enemy_ltnk2) end
            if Valid(M.enemy_tank1) then RemoveObject(M.enemy_tank1) end
            if Valid(M.enemy_tank2) then RemoveObject(M.enemy_tank2) end
            -- nav alpha (what else could it be???)
            M.nav_alpha = BuildObject("apcamr", 1, "spawn_nav_alpha")
            if Valid(M.nav_alpha) then SetObjectiveName(M.nav_alpha, "Nav Alpha") end -- native SetName alias
            M.missionState = MS_HARRASDEAD
            M.stateTimer = GetTime() + 4 -- retained even though the source never tests it
            ResetObjectives()
            -- Retreat(recycler, "path_recycler_retreat");
            Goto(M.recycler, "path_recycler_retreat")
            M.recyclerRetreated = false
            M.harrass_scout1 = BuildObject("cvfigh", 2, "spawn_scout1_harrass")
            M.harrass_ltnk1 = BuildObject("cvltnk", 2, "spawn_ltnk1_harrass")
            -- Attack(harrass_scout1, user);
            -- Attack(harrass_ltnk1, user);
            if Valid(M.harrass_scout1) and Valid(M.user) then Goto(M.harrass_scout1, M.user) end
            if Valid(M.harrass_ltnk1) and Valid(M.user) then Goto(M.harrass_ltnk1, M.user) end
        end
    elseif state == MS_HARRASDEAD then
        if not M.recyclerRetreated and Distance(M.recycler, "trigger_1") < 100 then
            for i = 0, 5 do
                local temp = BuildObject("cvfigh", 2, "fighter_1")
                if Valid(temp) and Valid(M.user) then Attack(temp, M.user) end
            end
            M.recyclerRetreated = true
        end
        -- Source does not require harassment deaths or the unused +4 timer.
        if GetCurrentCommand(M.recycler) == AiCommand.NONE then
            Stop(M.recycler)
            M.soundhandle = AudioMessage("bd02006.wav")
            M.missionState = MS_WAITFORBOMBERRUN
        end
    elseif state == MS_WAITFORBOMBERRUN then
        if IsAudioMessageDone(M.soundhandle) then
            if Valid(M.harrass_scout1) then RemoveObject(M.harrass_scout1) end
            if Valid(M.harrass_ltnk1) then RemoveObject(M.harrass_ltnk1) end
            if Valid(M.enemy_turret1) then RemoveObject(M.enemy_turret1) end
            if Valid(M.enemy_turret2) then RemoveObject(M.enemy_turret2) end
            if Valid(M.enemy_turret3) then RemoveObject(M.enemy_turret3) end
            if Valid(M.enemy_turret4) then RemoveObject(M.enemy_turret4) end
            AudioMessage("bd02007.wav")
            M.bomber1_scripted = BuildObject("cvhraz", 2, "spawn_bomber_1")
            -- Goto(bomber_scripted, "path_bomber_attackpath");
            if Valid(M.bomber1_scripted) then Attack(M.bomber1_scripted, M.recycler) end
            M.bomber2_scripted = BuildObject("cvhraz", 2, "spawn_bomber_2")
            if Valid(M.bomber2_scripted) then Attack(M.bomber2_scripted, M.recycler) end
            M.recyclerHealth = GetHealth(M.recycler)
            M.soundhandle = nil -- C++ 0; do not pass Lua number 0 as audio userdata
            M.missionState = MS_BOMBERRUN
        end
    elseif state == MS_BOMBERRUN then
        HealBomber(M.bomber1_scripted)
        HealBomber(M.bomber2_scripted)
        if Distance(M.bomber1_scripted, "camera_bomber_chasecam") <= 50
            or Distance(M.bomber2_scripted, "camera_bomber_chasecam") <= 50 then
            CameraReady()
            M.missionState = MS_RECYCLERDIE
        end
    elseif state == MS_RECYCLERDIE and CameraCancelled() then
        -- TRO 1.3: cancelling the final film ends the mission at once (+5 s), skipping the narration
        if M.hitSound ~= nil and not IsAudioMessageDone(M.hitSound) then StopAudioMessage(M.hitSound) end
        if M.soundhandle ~= nil and not IsAudioMessageDone(M.soundhandle) then StopAudioMessage(M.soundhandle) end
        M.missionState = MS_END
        CameraFinish()
        SucceedMission(GetTime() + 5.0, "bd02win.des")
    elseif state == MS_RECYCLERDIE then
        HealBomber(M.bomber1_scripted)
        HealBomber(M.bomber2_scripted)
        -- CameraPath("camera_bomber_chasecam", 1000, 0, bomber_scripted);
        RecyclerCamera()
        if M.recyclerHealth ~= 0 and (not Alive(M.recycler) or M.recyclerHealth ~= GetHealth(M.recycler)) then -- it's been hit...
            -- Recycler *myRecycler = (Recycler *) GameObjectHandle::GetObj(recycler);
            -- myRecycler->Explode();
            M.recyclerHealth = 0
            M.hitSound = AudioMessage("bd02008.wav")
            -- myRecycler->AddHealth(-((myRecycler->GetCurHealth() / 4) * 3));
            -- Stop(bomber_scripted);
            -- RemoveObject(bomber_scripted);
            -- bomber_scripted = 0;
            -- stateTimer = GetTime() + 3;
        end
        if M.soundhandle == nil and not Alive(M.recycler) then
            M.soundhandle = AudioMessage("bd02009.wav")
        end
        -- PORT FIX: source has `if (!soundhandle && IsAudioMessageDone(soundhandle))`.
        -- It polls a zero handle before destruction, and becomes false once
        -- bd02009 supplies a real handle, potentially skipping/stalling the end.
        -- Wait for that real final message. This restores the existing intended
        -- recycler-death -> narration -> three-second camera hold -> success
        -- sequence; all waves, prerequisites and original delays stay intact.
        if M.soundhandle ~= nil and IsAudioMessageDone(M.soundhandle) then
            --[[
//				Recycler *myRecycler = (Recycler *) GameObjectHandle::GetObj(recycler);
//				if(myRecycler)
//				{
//					myRecycler->Explode();
//				}
            ]]
            M.missionState = MS_ENDWAIT
            M.stateTimer = GetTime() + 3
            ResetObjectives()
        end
    elseif state == MS_ENDWAIT and CameraCancelled() then
        -- TRO 1.3: cancelling the final film ends the mission at once (+5 s)
        M.missionState = MS_END
        CameraFinish()
        SucceedMission(GetTime() + 5.0, "bd02win.des")
    elseif state == MS_ENDWAIT then
        RecyclerCamera()
        if M.stateTimer < GetTime() then
            M.missionState = MS_END
            CameraFinish()
            SucceedMission(GetTime() + 5.0, "bd02win.des")
        end
    end

    -- Separate blocks reproduce only the two deliberate C++ fall-throughs;
    -- all other state changes wait until the next Update, as in the switch.
    if state == MS_PLAYDECLOCK then
        local arrived = false
        if Valid(M.wave1_scout1) then
            arrived = CameraPath("camera_decloak", 2000, 1000, M.wave1_scout1)
        end
        -- PORT FIX: release the decloak shot if its subject vanishes. This
        -- substitutes for an unusable camera's completion, retaining the +5 wait.
        if arrived or CameraCancelled() or not Valid(M.wave1_scout1) then
            CameraFinish()
            M.missionState = MS_WAITINGOBJ2
            M.stateTimer = GetTime() + 5
        end
    elseif state == MS_WAITFORSOUND4 then
        -- TRO 1.3: cancelling the film skips bd02005 and the rest of the sequence (read before CameraPath)
        local skipped = CameraCancelled()
        if Valid(M.enemy_tank1) then CameraPath("camera_massive_attack", 2000, 10, M.enemy_tank1) end
        if skipped then
            M.massiveSkipped = true
            M.missionState = MS_WAITFORSOUND5
        elseif IsAudioMessageDone(M.soundhandle) then
            M.soundhandle = AudioMessage("bd02005.wav")
            M.missionState = MS_WAITFORSOUND5
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
    -- LuaMission restores the state table, including engine handles/audio.
    -- Do not replay Setup, rebuild units, reset objectives, or restart timers.
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
