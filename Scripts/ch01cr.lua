-- Chinese01Mission.cpp -> stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Chinese01Mission.cpp
-- Source blob: 210bb8193c11836ffb299bb15bf89afd945e48c5.
-- Complete original source (including every comment, #if block, declaration,
-- and native Load/Save/PostLoad scaffold):
-- References/Chinese01Source/Chinese01Mission.cpp.
-- No Campaign Reimagined helpers, EXU, or OpenShim required.
-- Keep zero-based arrays and native strict timer/distance comparisons.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/CHMISN01_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Chmisn01CoopSourceParity.py).
-- CR co-op layer <<

local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, objective4Complete = false,
        objective5Complete = false, -- unused in active source
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false}, -- unused native arrays
        hangarIdentified = false, recyclerDeployed = false,
        tugNearNav = false, arialsSpawned = false,
        focusOnExplosion = false, doingExplosion = false, doNuke = false,
        sound12Played = false, decoySpawned = false, won = false, lost = false,
        detectors = {},
        -- Native null handles and audio IDs are nil (Lua zero is truthy).
        -- All eleven native timers are assigned by Setup in Start below;
        -- unused wave5Time/explodeTime and tugDiedSound remain retained.
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/CHMISN01_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one restoration off (Docs/CHMISN01_COOP.md, "Restored content").
local RESTORED_RECYCLER_OBJECTIVES = true -- the unused objectives ch01006 (deploy) and ch01007 (protect)
local RESTORED_VOICE_LINES = true -- the unused shipped line ch01010
local ENEMY_TEAM = 5
local Restored = {}
-- Every CCA ground unit of the waves becomes a concealed, head-count-scaled ticket. The tug (an objective the body
-- keeps and tests), the escorts (team 1), the paratroopers (built at a height, not at a path) and the Chinese
-- navs, decoys and base are built directly, see BuildObject below.
local SCALED_ODFS = { svfigh = true, svtank = true, svltnk = true, svhraz = true, svturrb = true }
-- IsInfo is local UI state: guests report it to the host (Restored.OnInfo), the host keeps it for a second.
local INFO_ODFS = { sbhanga = true }
local remoteInfo = {}
local CONVOY_RADIUS = 100 -- every human must stay this close to the escorted one to share its cover
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
-- The Recycler's dropship delivery (Scripts/CRDropIn.lua, Docs/CHMISN01_COOP.md "Dropship delivery"), offline and co-op:
-- when the comm array falls the body builds the Recycler at the path "recycler"; the BuildObject shadow below builds it
-- the same way, rides it in the hold of a CRA cvdrop and lets it drive out, and the body keeps running (the stock
-- branch stores the handle, the wave-1 timer starts when it deploys). The beachhead is far from the base the humans
-- are fighting at, so the drop uses no camera and no control lock (no EXU mask, no pod camera). A missing module, a
-- failing start or an old save (the Recycler already exists) leaves the stock Recycler where it stands. The plan rides
-- the runtime's ordered stream as the presentation ops below. Natives here are the engine's.
local DropIn
if not CR_TEST_FAITHFUL then
    local okDropIn, module = pcall(require, "CRDropIn")
    if okDropIn then DropIn = module else print("[ch01] stock Recycler: CRDropIn unavailable: " .. tostring(module)) end
end
local dropOps = {}
for _, op in ipairs({ "DropShip", "DropCrew", "DropGo" }) do
    dropOps[op] = function(...)
        if DropIn then
            M.dropin = M.dropin or {}
            DropIn.Apply(M.dropin, op, ...)
        end
    end
end
local function DropStart(R)
    if not DropIn then return end
    DropIn.Configure({
        present = R.Present, log = function(line)
            if not line:find("control lock unavailable", 1, true) then print(line) end -- no EXU mask is passed on purpose
        end,
        owner = "mission:ch01-dropship",
        isNetwork = R.Coop.IsNetworkGame, isLeader = R.Coop.IsAuthority,
        myTeam = R.Coop.GetLocalTeam, player = R.Native.GetPlayerHandle,
        forEachHuman = function(fn) R.Coop.ForEachPlayerHandle(function(h) fn(h) end) end,
    })
    DropIn.Reset()
end
-- Leader, every frame after the body: the drop plays alongside the mission, nothing waits for it.
local function DropUpdate()
    if DropIn and M.dropin and M.dropin.phase ~= "done" then DropIn.Update(M.dropin) end
end
-- Every frame the body does not run for this peer: a guest follows the plan, and a co-op warn state (host gone, late
-- joiner, bad team) takes the drop down.
local function DropStandby(R)
    if not (DropIn and M.dropin) or M.dropin.phase == "done" then return end
    local coop = R.Coop
    if coop.IsNetworkGame() then
        if coop.HasLeaderDeparted() or coop.HasUnsupportedPlayerTeam() or coop.HasLateJoiners() then
            pcall(DropIn.Abort, M.dropin)
            return
        end
        if not coop.IsSessionReady() then return end
    end
    if not coop.IsAuthority() then
        local ok, err = pcall(DropIn.Update, M.dropin)
        if not ok then print("[ch01] dropship follow failed: " .. tostring(err)); pcall(DropIn.Abort, M.dropin) end
    end
end
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "ch01cr", leaderTeam = 1, enemyTeam = ENEMY_TEAM, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- respawn at the Chinese beachhead where the Recycler is delivered
    scaledOdfs = SCALED_ODFS,
    liveCap = 50, -- waves of 8 to 16 units; only the co-op extras are dropped for the cap
    scrapPerGuest = 0, -- the mission starts with no scrap on purpose (SetScrap(1, 0)): no bonus per guest
    -- A group whose entry has a human within 460 m comes from the next hidden CCA approach instead.
    fallbackEntries = { "wave_2", "wave_3", "wave_4", "wave_1", "wave_5" },
    failDes = "ch01lsea.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- Local-only engine state (the disguise, cloaking, the flash and the blast) runs on every peer through the stream.
    presentationOps = {
        CH1Cloak = function(on) Restored.OpCloak(on) end,
        CH1Disguise = function(team) Restored.OpDisguise(team) end,
        CH1Fade = function(...) Restored.OpFade(...) end,
        CH1Blast = function(effect, where) Restored.OpBlast(effect, where) end,
        DropShip = dropOps.DropShip, DropCrew = dropOps.DropCrew, DropGo = dropOps.DropGo,
    },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesCH01", startLevel = 1, targetLevel = 1,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local function raise(level)
                if europa.GetTargetLevel() < level then europa.SetTargetLevel(level) end
            end
            -- The comm array falls: the ice shudders and the vapour stirs.
            if (not beats.comm) and state.objective2Complete then
                beats.comm = true
                raise(2)
                europa.Quake(0.3, 3.0)
            end
            -- The Recycler deploys beside the beachhead geysers (map vents 4-7) and the CCA answers.
            if (not beats.deploy) and state.recyclerDeployed then
                beats.deploy = true
                raise(3)
                if #europa.GetVentSites() >= 5 then europa.TriggerPlume(5) end
            end
            -- The tug is inbound and the sky darkens over the convoy road.
            if (not beats.tug) and state.tugNearNav then
                beats.tug = true
                raise(3)
                europa.Surge(6.0, 0.8)
            end
            -- The relic is aboard: the radiation belt flares for the run to the safe distance.
            if (not beats.relic) and state.objective4Complete then
                beats.relic = true
                raise(4)
                europa.Quake(0.4, 4.0)
            end
            -- The blast: the base vent blows, the ground heaves.
            if (not beats.blast) and state.doingExplosion then
                beats.blast = true
                raise(4)
                europa.Quake(0.7, 5.0)
                europa.Surge(6.0, 1.0)
                if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end
            end
            -- Everything calms while the result counts down.
            if (not beats.calm) and state.won then
                beats.calm = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
        end },
    hooks = {
        start = function(R) Restored.OnStart(); DropStart(R) end,
        load = function()
            Restored.OnLoad()
            if DropIn then DropIn.OnLoad(M.dropin) end
        end,
        update = function(_, _, authority) Restored.OnUpdate(authority) end,
    },
})
local NativeBuildObject, NativeGetCockpitTimer, NativeGetTeamNum = BuildObject, GetCockpitTimer, GetTeamNum
local NativeSetPerceivedTeam, NativeIsFollowing, NativeIsInfo = SetPerceivedTeam, IsFollowing, IsInfo
local NativeColorFade, NativeMakeExplosion, NativeEnableAllCloaking = ColorFade, MakeExplosion, EnableAllCloaking
-- The Recycler the body asks for at the path "recycler", delivered by a cvdrop that lands near that spot (the cargo's
-- goal) and lets it drive out. The Recycler exists from this call (the body stores the handle, the Recycler objectives
-- and the loss test read it) and is held in the hold until the ramp is down. Any failure leaves it on the path.
local function DropRecycler(odf, team, where)
    local recy = NativeBuildObject(odf, team, where)
    if not (DropIn and recy ~= nil and IsValid(recy)) then return recy end
    M.dropin = {}
    local pos = GetPosition(recy)
    local goal = { x = pos.x, z = pos.z }
    local ok, begun = pcall(DropIn.Begin, M.dropin, { profile = "cvdrop", exclude = { [recy] = true }, ships = {
        { anchor = goal, delay = 0, cargo = { { h = recy, goal = goal, slot = "recycler" } } },
    } })
    if not (ok and begun) then
        pcall(DropIn.Abort, M.dropin)
        M.dropin.phase = "done"
    end
    return recy
end
-- The body's "player" is the runtime's nearest-human token; the token is valid while any human lives.
local IsValid = campaignRuntime and function(h)
    if h == campaignRuntime.PLAYERS then return Restored.AnyHuman() end
    return campaignRuntime.IsValid(h)
end or IsValid
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
-- A line the engine cannot start has no handle, and the body's gates only advance on a handle that reports done.
-- A missing line is a finished line.
local AudioMessage = campaignRuntime and function(file)
    local handle = campaignRuntime.AudioMessage(file)
    if handle == nil then return 0 end
    return handle
end or AudioMessage
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local CameraPath = campaignRuntime and campaignRuntime.CameraPath or CameraPath
-- The objective list is remembered so a load can publish it again (Restored.AfterLoad).
local ClearObjectives = campaignRuntime and function()
    Restored.Remember(nil)
    return campaignRuntime.ClearObjectives()
end or ClearObjectives
local AddObjective = campaignRuntime and function(text, color)
    Restored.Remember(text, color)
    return campaignRuntime.AddObjective(text, color)
end or AddObjective
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SetName = campaignRuntime and campaignRuntime.SetObjectiveName or SetName -- stock SetName alias
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- Orders on a ticket are recorded and replayed on the real unit; orders on real units pass through.
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local SetIndependence = campaignRuntime and campaignRuntime.SetIndependence or SetIndependence
-- Team 1 is the one shared Chinese side: its pilots go to every human team (each human respawns from its own pool).
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = ENEMY_TEAM end
    return SetPilot(team, count)
end or SetPilot
-- Every CCA craft is built on the enemy team 5 (the runtime maps the body's team 2); a new scripted group (a new
-- frame or a new entry path) is a new scaling event: the first unit of each group is mirrored by
-- min(floor(humans / 2), 2) extras with its orders. Everything the body builds for the Chinese side or for nobody
-- (team 1 and 0: navs, armoury, Recycler, escorts, decoys, relic) is built directly and never as a ticket.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where)
    if odf == "cvrecyd" and team == 1 and where == "recycler" then return DropRecycler(odf, team, where) end
    if team ~= 2 then return NativeBuildObject(odf, team, where) end
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- The tug is "still the enemy's" while it flies the CCA team: the body's enemy is team 2 (here 5) and its own side is
-- team 1 (here the human teams 1-4: a guest who steals the tug must not read as the enemy).
local GetTeamNum = campaignRuntime and function(h)
    local team = NativeGetTeamNum(h)
    if team == ENEMY_TEAM then return 2 end
    if team >= 2 and team <= 4 then return 1 end
    return team
end or GetTeamNum
-- Escorts: one cover for the party. The escorted human is the one both fighters follow; the others share its cover
-- while they stay within CONVOY_RADIUS of it. The disguise reaches every human on every peer, and the DLL's team 2
-- is the co-op enemy team 5.
local IsFollowing = campaignRuntime and function(h, target)
    if target == campaignRuntime.PLAYERS then return Restored.Covered() end
    return NativeIsFollowing(h, target)
end or IsFollowing
local SetPerceivedTeam = campaignRuntime and function(h, team)
    if team == 2 then team = ENEMY_TEAM end
    if h == campaignRuntime.PLAYERS then return Restored.Disguise(team) end
    return NativeSetPerceivedTeam(h, team)
end or SetPerceivedTeam
local EnableAllCloaking = campaignRuntime and function(on)
    return campaignRuntime.Present("CH1Cloak", on and 1 or 0)
end or EnableAllCloaking
-- A guest's inspection counts: native IsInfo OR a guest report within the last second.
local IsInfo = campaignRuntime and function(odf)
    if NativeIsInfo(odf) then return true end
    local reported = remoteInfo[odf]
    return reported ~= nil and GetTime() - reported <= 1.0
end or IsInfo
-- The cockpit countdown is presentation: every peer shows the host's timer. The engine cannot keep the clock (the
-- map runs MultSTMission, which restarts the timer upward every frame), so the host counts the three minutes itself.
local StartCockpitTimer = campaignRuntime and function(seconds, ...)
    Restored.TimerStart(seconds)
    return campaignRuntime.Present("StartCockpitTimer", seconds, ...)
end or StartCockpitTimer
local HideCockpitTimer = campaignRuntime and function() return campaignRuntime.Present("HideCockpitTimer") end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
-- The flash and the blast are local effects: every peer plays its own copy.
local ColorFade = campaignRuntime and function(...) return campaignRuntime.Present("CH1Fade", ...) end or ColorFade
local MakeExplosion = campaignRuntime and function(effect, where)
    return campaignRuntime.Present("CH1Blast", effect, where)
end or MakeExplosion
-- CR co-op runtime <<
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
-- Stock map bug: the path "spawn_explosion1" is not in the map; the blast goes off at the relic instead.
local MakeExplosion = (function()
    local NativeMakeExplosion = MakeExplosion
    return function(effect, where)
        local ok, count = pcall(GetPathPointCount, where)
        if not (ok and type(count) == "number" and count > 0) then where = "relic_loc" end
        return NativeMakeExplosion(effect, where)
    end
end)()
local function Alive(h) return Valid(h) and IsAlive(h) end
local function Health(h)
    -- PORT FIX: deleted objects cannot be queried safely. Treat them as dead,
    -- matching the native <=0 destruction gates. Unspawned slots are gated
    -- separately; intact units retain the native fractional-health tests.
    if not Valid(h) then return 0 end
    return GetHealth(h)
end
local function Distance(h, target, point)
    -- PORT FIX: nil/deleted handles must not satisfy proximity/safety tests
    -- or select the wrong Lua overload. Existing objects/paths are unchanged.
    if not Valid(h) or (type(target) ~= "string" and not Valid(target)) then
        return math.huge
    end
    if point ~= nil then return GetDistance(h, target, point) end
    return GetDistance(h, target)
end
local function Following(h, target)
    return Valid(h) and Valid(target) and IsFollowing(h, target)
end
local function HangarInfo()
    -- API ADAPTATION: native IsInfo takes a handle; stock Lua takes an ODF.
    -- Resolve the actual mapped hangar's ODF rather than assuming its class.
    return Valid(M.hangar) and IsInfo(GetOdf(M.hangar))
end
local function Airborne(odf, team, path, height)
    -- API ADAPTATION: native fourth argument is spawn height, while Lua's
    -- fourth path argument is a POINT INDEX. Use point 0's position plus the
    -- native 200/100-metre vertical offset; preserve unit and spawn order.
    local p = GetPosition(path, 0)
    p.y = p.y + height
    return BuildObject(odf, team, p)
end
-- CR co-op fixes >>
-- The body's player is one handle (GetPlayerHandle). In co-op it is the runtime's nearest-human token, so every
-- approach test (the detectors, the decoys, the blast shot) asks "is ANY human this close"; the body's Distance
-- keeps its three-argument path overload for everything else.
if campaignRuntime then
    local nearestHuman = campaignRuntime.WrapDistance(function() return math.huge end)
    local PathDistance = Distance
    Distance = function(h, target, point)
        if h == campaignRuntime.PLAYERS then return nearestHuman(h, target) end
        return PathDistance(h, target, point)
    end
end
-- CR co-op fixes <<
-- CR restored content >>
-- The co-op state the single-player body keeps in one handle (the DLL's player), the stock-bug fixes that need
-- state, and the restorations (Docs/CHMISN01_COOP.md). Each restoration has a RESTORED_* flag. Only the authority
-- runs the body; every peer runs the ops and the update hook.
if campaignRuntime then
    local runtime = campaignRuntime
    local coop = runtime.Coop
    local nextInfoSend = 0 -- per-peer, not saved
    local cover -- {t = frame, value = bool}, per-peer, not saved
    local function Real(h) return h ~= nil and h ~= 0 and IsValid(h) end
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- Every human with a usable handle (offline: the player).
    local function Humans()
        local list = {}
        coop.ForEachPlayerHandle(function(h) list[#list + 1] = h end)
        return list
    end
    local function Signature()
        local parts = {}
        for _, h in ipairs(Humans()) do parts[#parts + 1] = tostring(h) end
        table.sort(parts)
        return table.concat(parts, ",")
    end
    function Restored.AnyHuman() return #Humans() > 0 end

    -- ---------------------------------------------------------------- the escort cover
    -- Both escorts follow one human (the escorted one) and every human is within CONVOY_RADIUS of it: the party is
    -- covered. One answer per frame, so the body's two IsFollowing asks agree.
    function Restored.Covered()
        local now = GetTime()
        if cover ~= nil and cover.t == now then return cover.value end
        local value = false
        if Real(M.escort1) and Real(M.escort2) then
            local humans = Humans()
            for _, lead in ipairs(humans) do
                if NativeIsFollowing(M.escort1, lead) and NativeIsFollowing(M.escort2, lead) then
                    value = true
                    for _, other in ipairs(humans) do
                        if other ~= lead and GetDistance(other, lead) > CONVOY_RADIUS then value = false; break end
                    end
                    if value then break end
                end
            end
        end
        cover = { t = now, value = value }
        return value
    end

    -- ---------------------------------------------------------------- the disguise and other local state
    -- The body re-applies the perceived team every frame while the party is inside the base: only a change (or a new
    -- human handle, a respawn) is published. Team 1 means "no cover": each human is perceived as their own team.
    function Restored.Disguise(team)
        local r = RState()
        local value = (team == ENEMY_TEAM) and ENEMY_TEAM or 1
        if r.disguise ~= value then
            r.disguise = value
            r.sig = nil
        end
    end
    function Restored.OpDisguise(team)
        coop.ForEachPlayerHandle(function(h)
            NativeSetPerceivedTeam(h, team == 1 and NativeGetTeamNum(h) or team)
        end)
    end
    function Restored.OpCloak(on) NativeEnableAllCloaking(on == 1) end
    function Restored.OpFade(...) NativeColorFade(...) end
    function Restored.OpBlast(effect, where) NativeMakeExplosion(effect, where) end

    -- ---------------------------------------------------------------- the three-minute countdown
    function Restored.TimerStart(seconds) RState().timerEnd = GetTime() + seconds end
    function Restored.TimerLeft()
        local finish = RState().timerEnd
        if finish ~= nil then return math.max(0, finish - GetTime()) end
        return NativeGetCockpitTimer()
    end

    -- ---------------------------------------------------------------- the objective list, remembered for loads
    function Restored.Remember(text, color)
        local r = RState()
        if text == nil then r.objectives = {}; return end
        r.objectives = r.objectives or {}
        r.objectives[#r.objectives + 1] = { text, color }
    end

    -- ---------------------------------------------------------------- the inspection relay
    function Restored.OnInfo(from, odf)
        local player = coop.GetPlayers()[from]
        if coop.IsNetworkGame() and coop.IsAuthority() and player and coop.IsHumanTeam(player.team)
            and type(odf) == "string" and INFO_ODFS[odf] then
            remoteInfo[odf] = GetTime()
        end
    end
    -- A guest reports which inspection its info panel shows.
    local function RelayInfo()
        local now = GetTime()
        if now < nextInfoSend then return end
        local leaderId = 0
        for id, player in pairs(coop.GetPlayers()) do
            if player.team == coop.GetLeaderTeam() then leaderId = id; break end
        end
        for odf in pairs(INFO_ODFS) do
            if NativeIsInfo(odf) then
                Send(leaderId, "I", odf)
                nextInfoSend = now + 0.25
            end
        end
    end

    -- ---------------------------------------------------------------- loads and hooks
    function Restored.OnStart()
        cover, nextInfoSend = nil, 0
        for odf in pairs(remoteInfo) do remoteInfo[odf] = nil end
    end
    function Restored.OnLoad() RState().afterLoad = true end
    -- The runtime's Load resets the presentation: publish the objective list, the countdown, the disguise and the
    -- blast shot again from the saved state (the body only issues them at their events).
    local function AfterLoad(r)
        local saved = r.objectives
        if saved ~= nil then
            local copy = {}
            for i, entry in ipairs(saved) do copy[i] = entry end
            ClearObjectives()
            for _, entry in ipairs(copy) do AddObjective(entry[1], entry[2]) end
        end
        if r.timerEnd ~= nil and not M.doingExplosion then
            local remaining = r.timerEnd - GetTime()
            if remaining > 0 then runtime.Present("StartCockpitTimer", remaining, 15, 5) end
        end
        r.sig = nil
        if M.focusOnExplosion then CameraReady() end
    end
    -- Every peer, every frame after the session is ready.
    function Restored.OnUpdate(authority)
        if coop.IsNetworkGame() and not authority then RelayInfo() end
    end

    -- ---------------------------------------------------------------- the authority's step (after the body)
    local function Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; AfterLoad(r) end
        if r.disguise ~= nil then
            local sig = Signature()
            if r.sig ~= sig then
                r.sig = sig
                runtime.Present("CH1Disguise", r.disguise)
            end
        end
        -- Cut: the objectives ch01006 "Deploy your Recycler." and ch01007 "Protect your Recycler. Build Turrets to
        -- help." ship with the game but the body never lists them.
        if RESTORED_RECYCLER_OBJECTIVES and not M.tugNearNav and not M.objective3Complete and not M.lost and not M.won then
            if M.objective2Complete and Real(M.recycler) and not r.deployObjective then
                r.deployObjective = true
                AddObjective("ch01006.otf", "white")
            end
            if M.recyclerDeployed and not r.protectObjective then
                r.protectObjective = true
                ClearObjectives()
                AddObjective("ch01001.otf", "green")
                AddObjective("ch01002.otf", "green")
                AddObjective("ch01006.otf", "green")
                AddObjective("ch01007.otf", "white")
            end
        end
        -- Unused shipped line ch01010 "Shield your eyes, Major. This should cover our tracks sufficiently." just
        -- before the blast.
        if RESTORED_VOICE_LINES and M.objective4Complete and not M.doingExplosion and not M.lost and not M.won
            and r.timerEnd ~= nil and not r.l1010 and Restored.TimerLeft() <= 6.0 then
            r.l1010 = true
            M.sound12Played = true -- the body's TRO-timed ch01010 (<= 5 s) stands down once this has played
            AudioMessage("ch01010.wav")
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Step)
        if not ok and not failed then
            failed = true
            print("[ch01cr] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end
function Save() return M end
function Load(state)
    -- LuaMission serializes/remaps handles in tables. Do not rerun Setup or
    -- restart timers/messages after loading; native ConvertHandle is implicit.
    if state ~= nil then M = state end
end

function Start()
    M = NewState()
    local i = 0
    M.startDone = false
    M.objective1Complete = false
    M.objective2Complete = false
    M.objective3Complete = false
    M.objective4Complete = false
    M.objective5Complete = false
    M.hangarIdentified = false
    M.recyclerDeployed = false
    M.tugNearNav = false
    M.arialsSpawned = false
    M.focusOnExplosion = false
    M.doingExplosion = false
    M.doNuke = false
    M.sound12Played = false
    M.decoySpawned = false

    -- cameras
    for i = 0, 1 do
        M.cameraReady[i] = false
        M.cameraComplete[i] = false
    end

    -- units
    M.hangar = GetHandle("target_1")
    M.commTower= GetHandle("target_2")
    M.bbTower = GetHandle("bb_tower")
    M.recycler = nil
    M.tug = nil
    M.relic = nil
    M.escort1 = nil
    M.escort2 = nil
    M.detectors[0] = GetHandle("sp_turret_1")
    M.detectors[1] = GetHandle("sp_turret_2")
    M.detectors[2] = GetHandle("sp_turret_3")
    M.detectors[3] = GetHandle("sp_tower_1")
    M.detectors[4] = GetHandle("sp_tower_2")
    M.detectors[5] = GetHandle("sp_tower_3")
    M.detectors[6] = GetHandle("sp_tower_4")
    M.detectors[7] = GetHandle("sp_tower_5")
    M.detectors[8] = GetHandle("sp_tower_6")
    M.detectors[9] = GetHandle("sp_tower_7")

    -- navs
    M.navStart = nil
    M.navTug = nil
    M.navEnd = nil

    -- sounds
    M.openingSound = nil
    M.hangarSound = nil
    M.armourySound = nil
    M.tugDiedSound = nil
    M.failedSound = nil
    M.detectedSound = nil

    -- times
    M.openingSoundTime = 999999.9
    M.armourySoundTime = 999999.9
    M.wave1Time = 999999.9
    M.wave2Time = 999999.9
    M.wave3Time = 999999.9
    M.wave4Time = 999999.9
    M.wave5Time = 999999.9
    M.arial1Time = 999999.9
    M.arial2Time = 999999.9
    M.tugTime = 999999.9
    M.explodeTime = 999999.9
end

function Update(dt)
    local i = 0
    M.user = GetPlayerHandle(); --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1,0)
        SetPilot(1,10)

        -- don't do this part after the first shot
        M.startDone = true

        M.openingSoundTime = GetTime() + 5.0

        -- disable all cloaking for this mission
        EnableAllCloaking(false)
        --[=[ Original disabled startup/debug block (#if 0):
        		relic = BuildObject("obdata", 0, "relic_loc");
        		SetObjectiveOn(relic);
        		tug = BuildObject("svhaula", 2, user);
        		//nuke = BuildObject("obdata", 0, tug);
        		//setCargo(tug, nuke);
        		//tugEquipedWithNuke = TRUE;
        		SetObjectiveOn(tug);
        		SetPerceivedTeam(user, 2);
        		objective3Complete = TRUE;
        		SetObjectiveOn(hangar);
        ]=]
    end
    -- #if 1 (active native code)
    if M.openingSoundTime < GetTime() then
        M.openingSoundTime = 999999.9

        M.openingSound = AudioMessage("ch01001.wav")
    end

    if M.openingSound ~= nil and IsAudioMessageDone(M.openingSound) then
        M.openingSound = nil

        -- spawn the nav camera
        M.navStart = BuildObject("apcamr", 1, "nav_start")
        SetName(M.navStart, "CCA Base")

        ClearObjectives()
        AddObjective("ch01001.otf", "white")
    end

    if not M.hangarIdentified and HangarInfo() then
        M.hangarIdentified = true

        -- play the message
        M.hangarSound = AudioMessage("ch01002.wav")

        -- update objectives
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        M.objective1Complete = true
    end

    if M.hangarSound ~= nil and IsAudioMessageDone(M.hangarSound) then
        M.hangarSound = nil

        M.armourySoundTime = GetTime() + 15.0
    end

    if M.armourySoundTime < GetTime() then
        M.armourySoundTime = 999999.9

        M.armourySound = AudioMessage("ch01003.wav")
    end

    if M.armourySound ~= nil and IsAudioMessageDone(M.armourySound) then
        M.armourySound = nil

        -- spawn the armoury
        BuildObject("cvslfb", 1, "armoury")
        AudioMessage("ch01004.wav")

        -- update objectives
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        AddObjective("ch01002.otf", "white")

        AddScrap(1, 99)
    end

    if not M.objective2Complete and Health(M.commTower) <= 0.0 then
        M.objective2Complete = true

        AudioMessage("ch01005.wav")

        M.recycler = BuildObject("cvrecyd", 1, "recycler")
        AddScrap(1, 50)

        -- update objectives
        ClearObjectives()
        AddObjective("ch01001.otf", "green")
        AddObjective("ch01002.otf", "green")
    end

    if Valid(M.recycler) and not M.recyclerDeployed and IsDeployed(M.recycler) then
        M.recyclerDeployed = true

        M.wave1Time = GetTime() + 60.0
    end

    if M.wave1Time < GetTime() then
        M.wave1Time = 999999.9

        -- spawn the first wave
        local h
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svfigh", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)
        h = BuildObject("svtank", 2, "wave_1")
        Goto(h, "follow_1", 1)

        -- time to next wave
        M.wave2Time = GetTime() + 300.0
    end

    if M.wave2Time < GetTime() then
        M.wave2Time = 999999.9

        -- spawn the second wave
        local h
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svtank", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svltnk", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svltnk", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svltnk", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "follow_2", 1)
        h = BuildObject("svfigh", 2, "wave_2")
        Goto(h, "follow_2", 1)

        -- time to next wave
        M.wave3Time = GetTime() + 300.0
    end

    if M.wave3Time < GetTime() then
        M.wave3Time = 999999.9

        -- spawn the second wave
        local h
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svtank", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svhraz", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svhraz", 2, "wave_3")
        Goto(h, "follow_3", 1)
        h = BuildObject("svhraz", 2, "wave_3")
        Goto(h, "follow_3", 1)

        -- next attack
        M.arial1Time = GetTime() + 180.0
    end

    if M.arial1Time < GetTime() then
        M.arial1Time = 999999.9

        -- spawn the arial units
        local h
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sspilo", 2, "aerial_1", 200)
        Attack(h, M.recycler, 1)

        -- next attack
        M.arial2Time = GetTime() + 30.0
    end

    if M.arial2Time < GetTime() then
        M.arial2Time = 999999.9

        -- spawn the arial units
        local h
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)
        h = Airborne("sssold", 2, "aerial_2", 200)
        Attack(h, M.recycler, 1)

        -- next attack
        M.wave4Time = GetTime() + 60.0
    end

    if M.wave4Time < GetTime() then
        M.wave4Time = 999999.9

        -- spawn the wave
        local h
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svtank", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svhraz", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)
        h = BuildObject("svltnk", 2, "wave_4")
        Goto(h, "follow_4", 1)

        -- tug time
        M.tugTime = GetTime() + 120.0
    end

    if M.tugTime < GetTime() then
        M.tugTime = 999999.9

        M.tug = BuildObject("svhaula", 2, "relic_tug")
        Goto(M.tug, "tug_path", 1)

        local h
        h = BuildObject("svfigh", 2, "tug_defend")
        Defend2(h, M.tug, 1)
        h = BuildObject("svfigh", 2, "tug_defend")
        Defend2(h, M.tug, 1)
    end

    if Valid(M.tug) and not M.tugNearNav and Distance(M.tug, "nav_tug", 0) < 1000.0 then
        M.tugNearNav = true

        AudioMessage("ch01006.wav")

        M.navTug = BuildObject("apcamr", 1, "nav_tug")

        -- update objectives
        ClearObjectives()
        AddObjective("ch01002.otf", "green")
        AddObjective("ch01003.otf", "white")
    end

    -- has the tug been killed?
    if M.tug ~= nil and Health(M.tug) <= 0.0 and not M.lost and not M.won then
        M.lost = true

        M.failedSound = AudioMessage("ch01011.wav")
    end

    if M.failedSound ~= nil and IsAudioMessageDone(M.failedSound) then
        M.failedSound = nil

        FailMission(GetTime() + 1.0, "ch01lseb.des")
    end

    -- has the tug gotten away from us?
    if Valid(M.tug) and Distance(M.tug, "tug_fail") < 350.0 and GetTeamNum(M.tug) == 2 and not M.lost and not M.won then
        FailMission(GetTime() + 1.0, "ch01lsea.des")
        M.lost = true
    end

    -- is the tug within 75 metres of the recycler?
    if Valid(M.tug) and Distance(M.tug, M.recycler) < 75.0 and not M.objective3Complete then
        -- message
        AudioMessage("ch01007.wav")

        -- attack
        M.escort1 = BuildObject("svfigh", 1, "fighters")
        SetPerceivedTeam(M.escort1, 2)
        SetIndependence(M.escort1, 0)
        SetPerceivedTeam(M.escort1, 2)
        Goto(M.escort1, "fighters_to", 1)
        M.escort2 = BuildObject("svfigh", 1, "fighters")
        SetPerceivedTeam(M.escort2, 2)
        SetIndependence(M.escort2, 0)
        SetPerceivedTeam(M.escort2, 2)
        Goto(M.escort2, "fighters_to", 1)

        -- update objectives
        M.objective3Complete = true
        ClearObjectives()
        AddObjective("ch01003.otf", "green")
        AddObjective("ch01004.otf", "white")

        -- spawn the relic
        M.relic = BuildObject("obdata", 0, "relic_loc")

        -- units
        local h
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svtank", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svhraz", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svltnk", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5", 1)
        h = BuildObject("svturrb", 2, "wave_5")
        Goto(h, "follow_5", 1)
    end

    if M.objective3Complete and not M.objective4Complete and not M.lost and not M.won then
        local withinRange = false
        for i = 0, 9 do
            if Alive(M.detectors[i]) and Distance(M.user, M.detectors[i]) < 150.0 then
                withinRange = true
                break
            end
        end

        if not M.arialsSpawned and withinRange then
            -- spawn the arial units
            local h
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sspilo", 2, "aerial_3", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            h = Airborne("sssold", 2, "aerial_4", 100)
            M.arialsSpawned = true
        end


        -- are we currently being escorted?
        if Following(M.escort1, M.user) and Following(M.escort2, M.user) then
            -- we're being escorted, we're safe
        elseif withinRange then
            -- our cover is blown
            M.lost = true
            M.detectedSound = AudioMessage("ch01008.wav")
            -- Native assertion: _ASSERTE(!objective4Complete);
        end
    end

    if M.objective3Complete and not M.objective4Complete then
        -- are we currently being escorted?
        if Following(M.escort1, M.user) and Following(M.escort2, M.user) then
            -- we're being escorted, we're safe
            SetPerceivedTeam(M.user, 2)
        else
            SetPerceivedTeam(M.user, 1)
        end
    end

    -- we've been detected
    if M.detectedSound ~= nil and IsAudioMessageDone(M.detectedSound) then
        M.detectedSound = nil
        --failedSound = AudioMessage("ch01011.wav");
        FailMission(GetTime(), "ch01lsec.des")
    end
    -- #endif (active native code)
    -- if we get the relic
    if M.objective3Complete and not M.objective4Complete and Valid(M.relic) and Valid(M.tug) and GetCargo(M.tug) == M.relic then
        --_DEBUGMSG0("Relic picked up by Tug");
        M.objective4Complete = true

        -- reset objectives
        ClearObjectives()
        AddObjective("ch01004.otf", "green")
        AddObjective("ch01005.otf", "white")

        M.navEnd = BuildObject("apcamr", 1, "nav_end")
        -- Native assertion: _ASSERTE(navEnd != NULL);
        SetName(M.navEnd, "Safe Distance")
        SetObjectiveOn(M.navEnd)

        StartCockpitTimer(180, 15, 5)
        M.explodeTime = GetTime() + 30.0
    end

    if M.objective4Complete and not M.decoySpawned then
        -- are we close enough to the turrets?
        local withinRange = false
        for i = 0, 9 do
            if Alive(M.detectors[i]) and Distance(M.user, M.detectors[i]) < 300.0 then
                withinRange = true
                break
            end
        end

        if withinRange then
            M.decoySpawned = true

            -- decoy sound
            AudioMessage("ch01009.wav")

            for i = 0, 6 do
                local h = BuildObject("cvhtnk", 1, "decoy_units")
                Goto(h, M.detectors[math.random(0, 9)], 1)
            end
        end
    end

    if M.objective4Complete and not M.doingExplosion then
        -- TRO 1.3: ch01010 plays once at <= 5 s when the player is outside the blast radius (FUN_005ae660)
        if not M.sound12Played and not M.focusOnExplosion and GetCockpitTimer() > 0 and GetCockpitTimer() <= 5.0
            and Valid(M.navEnd) and Valid(M.hangar) and Valid(M.user)
            and Distance(M.user, M.hangar) > Distance(M.navEnd, M.hangar) - 50 then
            M.sound12Played = true
            AudioMessage("ch01010.wav")
        end
        if GetCockpitTimer() <= 0 then
            M.explodeTime = 999999.9
            HideCockpitTimer()

            -- make the thing explode
            M.doNuke = true
            M.doingExplosion = true
            ColorFade(1.0, 0.5, 255, 255, 255)
        elseif GetCockpitTimer() <= 2.0  and not M.focusOnExplosion and M.cameraFinishTime == nil then
            -- pre-explosion
            local nukeDistance = Distance(M.navEnd, M.hangar) - 50
            if Valid(M.bbTower) and Distance(M.user, M.hangar) > nukeDistance and not M.focusOnExplosion and M.cameraFinishTime == nil then
                CameraReady()
                M.cameraFinishTime = GetTime() + 5.0
                CameraPath("cut_end", 3000, 0, M.bbTower)
                M.focusOnExplosion = true
            end
        end
    end

    if M.doNuke then
        M.doNuke = false
        if M.focusOnExplosion then M.cameraFinishTime = GetTime() + 3.0 end

        -- where's the relic?
        local nukeDistance = Distance(M.navEnd, M.hangar) - 50.0
        -- PORT FIX: a previously detected/killed/escaped tug must not turn
        -- an already-lost mission into a win at countdown expiry. Preserve
        -- the three-second result and distance test on nonterminal runs.
        -- Destroyed relic/nav/hangar cannot count as safely evacuated.
        if not M.lost and not M.won then
            if Valid(M.relic) and Valid(M.navEnd) and Valid(M.hangar) and
                Distance(M.relic, M.hangar) > nukeDistance then
                SucceedMission(GetTime() + 3.0, "ch01win.des")
                M.won = true
            else
                FailMission(GetTime() + 3.0, "ch01lsee.des")
                M.lost = true
            end
        end
        -- API ADAPTATION: native MakeExplosion(location, effect) is reversed
        -- in Lua. Redux uses the D3D effect; legacy renderer flag useD3D is
        -- unavailable. Original fallback xpltrsq is preserved in the archive.
        MakeExplosion("xpltrsn", "spawn_explosion1")
    end

    -- PORT FIX: native CameraPath is called only once and CameraFinish never
    -- runs. Pump the same stationary shot until result transition (3 seconds
    -- after detonation) or cancellation, then return camera control. This
    -- changes only camera cleanup, not countdown or mission-result gates.
    if M.focusOnExplosion then
        if CameraCancelled() or GetTime() >= M.cameraFinishTime or not Valid(M.bbTower) then
            CameraFinish()
            M.focusOnExplosion = false
        else
            CameraPath("cut_end", 3000, 0, M.bbTower)
        end
    end

    -- has the recycler been lost?
    if M.recycler ~= nil and Health(M.recycler) <= 0.0 and not M.objective3Complete and not M.lost and not M.won then
        M.lost = true
        FailMission(GetTime() + 1.0, "ch01lsed.des")
    end
end
-- CR co-op callbacks >>
-- The body is never edited: the runtime's per-frame calls wrap its callbacks here.
local BodyStart, BodyAddObject, BodyUpdate, BodySave, BodyLoad = Start, AddObject, Update, Save, Load
function Start()
    BodyStart()
    if campaignRuntime then campaignRuntime.Start() end
end
function AddObject(h)
    BodyAddObject(h)
    if campaignRuntime then return campaignRuntime.AddObject(h) end
end
function Update(dt)
    if campaignRuntime and not campaignRuntime.Update(dt) then DropStandby(campaignRuntime); return end
    BodyUpdate(dt)
    if campaignRuntime then
        DropUpdate()
        Restored.Run()
        campaignRuntime.AfterUpdate()
    end
end
function Save()
    if campaignRuntime then campaignRuntime.Save() end
    return BodySave()
end
function Load(state)
    BodyLoad(state)
    if campaignRuntime then campaignRuntime.Load() end
end
function CreatePlayer(id,name,team) if campaignRuntime then return campaignRuntime.CreatePlayer(id,name,team) end end
function AddPlayer(id,name,team) if campaignRuntime then return campaignRuntime.AddPlayer(id,name,team) end end
function DeletePlayer(id) if campaignRuntime then return campaignRuntime.DeletePlayer(id) end end
function Receive(from,kind,...)
    if campaignRuntime then
        -- "I": a guest's report of the object its info panel shows (the only packet kind this mission adds).
        if kind == "I" then return Restored.OnInfo(from, ...) or true end
        return campaignRuntime.Receive(from,kind,...)
    end
end
-- CR co-op callbacks <<
