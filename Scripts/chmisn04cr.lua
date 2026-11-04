-- Chinese04Mission.cpp -> stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: GrizzlyOne95/Battlezone_Source/BZ1/from_bz2_dll_src/Chinese04Mission.cpp
-- Source blob: 11fb5b1a3203fd8a5e864ee30578624eb7788827.
-- All native comments/cut code and serialization declarations are preserved in
-- References/Chinese04Source/Chinese04Mission.cpp. No EXU/helper dependency.
-- Attach to the original ch04 map; its labels, paths and assets are required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/CHMISN04_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Ganymede weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Chmisn04CoopSourceParity.py).
-- CR co-op layer <<

local MS_STARTUP, MS_STARTSCENE, MS_PLAYSOUND7, MS_NEARNAVS = 1, 2, 3, 4
local MS_WAITFORID, WS_WAITFORSOUND2, MS_WAITFORALARM, MS_CAMERAALARM = 6, 7, 8, 9
local MS_NEARSILO, MS_INSPECTSILO, MS_WAITFORSOUND2, MS_WAITFORSOUND3 = 10, 11, 12, 13
local MS_WAITFORSOUND8, MS_WAITFORPORTAL, MS_CAMERAEND, MS_END = 14, 15, 16, 100

local function NewState()
    return {
        lost = false, target_silo_inspected = false, endNear = false,
        insideCloakedShip = true,
        stateTimer = 99999.0, portalTimeOut = 99999.0,
        missionState = MS_STARTUP, uptonavpoint = 0, attackedAlready = 0,
        navPoints = {}, empty = {}, turret = {},
        attackuser1 = {}, attackuser2 = {}, attackuser3 = {},
        attackuser4 = {}, attackuser5 = {}, attackuser6 = {},
        -- Null native handles/audio IDs are nil: user, olduser, target_silo,
        -- portal, cca_factory, factory, fakePlayer, soundHandle, coreFailSound.
        -- lost/fakePlayer and the unused 45-second stateTimer are retained.
    }
end

local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/CHMISN04_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one restoration off (Docs/CHMISN04_COOP.md, "Restored content").
local RESTORED_UNCLOAKED_DETECTION = true -- the cut "uncloaked within 400 m of trigger_1" test and the unused objective ch04004
local RESTORED_SILO_BEACON = true -- the cut nav_silo beacon "Silo"
local RESTORED_ALARM_PILOTS = true -- the cut pilots for empty_15, empty_16 and empty_18..24
local RESTORED_FAKE_CRAFT = true -- the cut stand-in craft that flies auto_end while the player is hidden
local RESTORED_VOICE_LINES = true -- the unused shipped lines ch04004 and ch04005
local Restored = {}
-- The pursuit (twelve chase units) and the portal guards become concealed, head-count-scaled tickets. The two
-- fighters that scramble from the silo (fighter_1, fighter_2) are a set piece and are built directly.
local SCALED_ODFS = { svfigh = true, svfigha = true, svtanka = true }
local DIRECT_PATHS = { fighter_1 = true, fighter_2 = true }
-- IsInfo is local UI state: guests report it to the host (Restored.RelayInfo), the host keeps it for a second.
local INFO_PREFIXES = { sbsiloa = true }
local remoteInfo = {}
-- A save during a shot cannot resume it (the cameras are gone). In a network game a shot also ends at its flight
-- time plus a margin: a skip releases only the skipper's own native camera. CAMERA_ETA is path length / (speed / 100)
-- in seconds (Tools/Test-Chmisn04CoopContract.py recomputes it from the map).
local CAMERA_ETA = { camera_start = 18.67, auto_end = 1.67 } -- auto_end flies at 4500 (TRO 1.3)
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "chmisn04cr", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "factory" }, -- respawn at the shared base: the Chinese factory beside the portal
    scaledOdfs = SCALED_ODFS,
    liveCap = 26, -- the pursuit is 12 chase units and 6 portal guards; four humans add two extras to each of 4 groups
    scrapPerGuest = 0, -- the mission is about the enemy's scrap: nobody gets any
    -- A group whose entry has a human within 460 m comes from the next hidden Soviet approach instead.
    fallbackEntries = { "chase_1", "chase_3", "chase_2", "portal_units" },
    farthestTargets = { "portal" }, -- the retreat is complete only when every human is near the portal
    failDes = "ch04lose.des",
    wonFlags = { "won" },
    endedFlags = { "won", "lost" },
    -- Local-only engine state (hide, perceived team, portal, end shot) runs on every peer through the stream.
    presentationOps = {
        CH4Hide = function() Restored.OpHide() end,
        CH4Disguise = function(team) Restored.OpDisguise(team) end,
        CH4Portal = function(mode) Restored.OpPortal(mode) end,
        CH4Shot = function(path, height, speed) Restored.OpShot(path, height, speed) end,
    },
    weather = { module = "CREuropaWeather", sites = "CRGanymedeSitesCH04", startLevel = 1, targetLevel = 1,
        environment = { lightingMode = "orbit", orbit = { period = 1800, startHour = -40 } },
        ops = { "EuropaState", "EuropaPlume", "EuropaQuake", "EuropaSurge" },
        beats = function(europa, state, s)
            local beats = s.ganymedeBeats
            if beats == nil then beats = {}; s.ganymedeBeats = beats end
            local function raise(level)
                if europa.GetTargetLevel() < level then europa.SetTargetLevel(level) end
            end
            -- The safe path through the minefields: the sky is restless from the first nav.
            if (not beats.route) and state.missionState >= MS_NEARNAVS then
                beats.route = true
                raise(2)
            end
            -- The alarm: pilots run for their craft, the radiation belt flares.
            if (not beats.alarm) and state.missionState >= MS_CAMERAALARM then
                beats.alarm = true
                raise(3)
                europa.Surge(6.0, 0.8)
            end
            -- The silo is identified: the base is overrun, the ice shudders and a vent blows if the map has one.
            if (not beats.silo) and state.missionState >= MS_WAITFORSOUND2 then
                beats.silo = true
                raise(4)
                europa.Quake(0.4, 4.0)
                europa.Surge(6.0, 0.8)
                if #europa.GetVentSites() > 0 then europa.TriggerPlume(1) end
            end
            -- The portal opens inward for the retreat.
            if (not beats.portal) and state.missionState >= MS_WAITFORSOUND3 then
                beats.portal = true
                europa.Quake(0.35, 3.0)
            end
            -- Through the portal: everything calms while the result counts down; a loss leaves the ice restless.
            if (not beats.calm) and state.won then
                beats.calm = true
                europa.ReleaseForcedLevel()
                europa.SetTargetLevel(1)
            end
            if (not beats.lost) and state.lost and not state.won then
                beats.lost = true
                raise(4)
            end
        end },
    hooks = {
        start = function() Restored.OnStart() end,
        load = function() Restored.OnLoad() end,
        update = function(_, _, authority) Restored.OnUpdate(authority) end,
        built = function(_, h, request) Restored.Built(h, request) end,
    },
})
local NativeIsValid, NativeBuildObject, NativeGetCockpitTimer = IsValid, BuildObject, GetCockpitTimer
local NativeHide, NativeSetPerceivedTeam, NativeIsCloaked = Hide, SetPerceivedTeam, IsCloaked
local NativeDecloak, NativeEnableCloaking = Decloak, EnableCloaking
local NativeGetCurHealth, NativeGetMaxHealth, NativeAddHealth = GetCurHealth, GetMaxHealth, AddHealth
local NativePortalIn, NativeDeactivatePortal, NativeSetUserTarget, NativeIsInfo = PortalIn, DeactivatePortal, SetUserTarget, IsInfo
local NativeCameraPathDir = CameraPathDir
local PLAYERS = campaignRuntime and campaignRuntime.PLAYERS
-- The body's "player" is the runtime's token for the humans (as in bdmisn09cr). Each use below gives the token the
-- meaning that keeps a stealth mission fair for several humans (Docs/CHMISN04_COOP.md, "Humans as the player").
-- The token is valid while any human lives; a negative number is a spawn ticket.
local IsValid = campaignRuntime and function(h)
    if h == PLAYERS then return Restored.AnyHuman() end
    return campaignRuntime.IsValid(h)
end or IsValid
local IsAlive = campaignRuntime and campaignRuntime.IsAlive or IsAlive
local GetDistance = campaignRuntime and campaignRuntime.GetDistance or GetDistance
local GetPlayerHandle = campaignRuntime and campaignRuntime.GetPlayerHandle or GetPlayerHandle
local AudioMessage = campaignRuntime and campaignRuntime.AudioMessage or AudioMessage
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever.
local nativeAudioDone = IsAudioMessageDone
local function IsAudioMessageDone(message)
    if message == nil or message == 0 then return true end
    return nativeAudioDone(message)
end
local CameraReady = campaignRuntime and campaignRuntime.CameraReady or CameraReady
local CameraFinish = campaignRuntime and campaignRuntime.CameraFinish or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
local ClearObjectives = campaignRuntime and function()
    Restored.OnReset()
    return campaignRuntime.ClearObjectives()
end or ClearObjectives
local AddObjective = campaignRuntime and campaignRuntime.AddObjective or AddObjective
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local SetObjectiveOn = campaignRuntime and campaignRuntime.SetObjectiveOn or SetObjectiveOn
local SetObjectiveOff = campaignRuntime and campaignRuntime.SetObjectiveOff or SetObjectiveOff
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
local Goto = campaignRuntime and campaignRuntime.Goto or Goto
-- Team 1 is the one shared Chinese side: its pilots go to every human team (each human respawns from its own
-- pool). Team 2 is the DLL's enemy and a guest's team here: team 2 -> 5.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
-- Every Soviet craft is built on the enemy team 5 (the runtime maps the body's team 2). A new scripted group (a new
-- frame or a new entry path) is a new scaling event: the first unit of each group is mirrored by
-- min(floor(humans / 2), 2) extras with its orders.
-- The body interleaves the three chase groups unit by unit, so an event is the first unit of an entry path in a frame.
local eventFrame, eventPaths
local BuildObject = campaignRuntime and function(odf, team, where)
    if DIRECT_PATHS[where] then return NativeBuildObject(odf, team == 2 and 5 or team, where) end
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now then eventFrame, eventPaths = now, {} end
        if not eventPaths[where] then
            eventPaths[where] = true
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where)
end or BuildObject
-- Orders at "the player" go to the human nearest to the unit. A unit still waiting for a concealed entry keeps the
-- order with the token as its target; Restored.Built resolves it the moment the unit exists.
local Attack = campaignRuntime and function(h, target, priority)
    if target == PLAYERS and not (type(h) == "number" and h < 0) then
        target = Restored.NearestHuman(h)
        if target == nil then return end
    end
    return campaignRuntime.Attack(h, target, priority)
end or Attack
-- The group is concealed only while every human is cloaked (at the alarm decision); once the base is up, any
-- cloak that is still running is what the core failure shuts down. Decloaking, the cloak lock, hiding, the
-- disguise and the heal reach every human.
local IsCloaked = campaignRuntime and function(h)
    if h ~= PLAYERS then return NativeIsCloaked(h) end
    return Restored.Cloaked()
end or IsCloaked
local Decloak = campaignRuntime and function(h)
    if h ~= PLAYERS then return NativeDecloak(h) end
    return Restored.EachHuman(NativeDecloak)
end or Decloak
local EnableCloaking = campaignRuntime and function(h, on)
    if h ~= PLAYERS then return NativeEnableCloaking(h, on) end
    return Restored.EachHuman(function(human) NativeEnableCloaking(human, on) end)
end or EnableCloaking
-- RestoreHealth(token): current 0 against maximum 1 asks for a heal; AddHealth(token) fills every human.
local GetCurHealth = campaignRuntime and function(h)
    if h ~= PLAYERS then return NativeGetCurHealth(h) end
    return 0
end or GetCurHealth
local GetMaxHealth = campaignRuntime and function(h)
    if h ~= PLAYERS then return NativeGetMaxHealth(h) end
    return 1
end or GetMaxHealth
local AddHealth = campaignRuntime and function(h, amount)
    if h ~= PLAYERS then return NativeAddHealth(h, amount) end
    return Restored.HealHumans()
end or AddHealth
-- Hide, the disguise, the portal and the user target are engine state each peer must apply to its own copy.
local Hide = campaignRuntime and function() return campaignRuntime.Present("CH4Hide", 1) end or Hide
local SetPerceivedTeam = campaignRuntime and function(_, team) return Restored.Disguise(team) end or SetPerceivedTeam
local PortalIn = campaignRuntime and function() return campaignRuntime.Present("CH4Portal", 2) end or PortalIn
local DeactivatePortal = campaignRuntime and function() return campaignRuntime.Present("CH4Portal", 0) end or DeactivatePortal
local SetUserTarget = campaignRuntime and function(h) return Restored.ShareTarget(h) end or SetUserTarget
-- A guest's inspection counts: native IsInfo OR a guest report within the last second.
local IsInfo = campaignRuntime and function(prefix)
    if NativeIsInfo(prefix) then return true end
    local reported = remoteInfo[prefix]
    return reported ~= nil and GetTime() - reported <= 1.0
end or IsInfo
-- The cockpit countdown is presentation: every peer shows the host's timer. The engine cannot keep the clock
-- (the map runs MultSTMission, which restarts the timer upward every frame), so the host counts the 130 s itself.
local StartCockpitTimer = campaignRuntime and function(seconds, ...)
    Restored.TimerStart(seconds)
    return campaignRuntime.Present("StartCockpitTimer", seconds, ...)
end or StartCockpitTimer
local HideCockpitTimer = campaignRuntime and function()
    Restored.TimerStop()
    return campaignRuntime.Present("HideCockpitTimer")
end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
-- The first CameraPath after a load reports arrival (the cameras are gone); in a network game a shot also ends at
-- its flight time plus a margin, because a skip releases only the skipper's own camera.
local camPath, camStart
local CameraPath = campaignRuntime and function(path, height, speed, target)
    if Restored.SkipCamera() then camPath = nil; return true end
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if arrived then camPath = nil; return arrived end
    if CAMERA_ETA[path] and campaignRuntime.Coop.IsNetworkGame() then
        local now = GetTime()
        if camPath ~= path then camPath, camStart = path, now end
        if now - camStart > CAMERA_ETA[path] * 1.25 + 3 then camPath = nil; return true end
    end
    return arrived
end or CameraPath
-- CameraPathDir is not on the runtime's camera stream: the end shot is opened on every peer by CH4Shot.
local CameraPathDir = campaignRuntime and function(path, height, speed) return Restored.Shot(path, height, speed) end or CameraPathDir
-- The results latch won/lost (the runtime's wonFlags/endedFlags and the weather read them). The unused line ch04005
-- ("a most weak and feeble leader") goes with the portal-timeout debrief ch04lseb, as ch04006 goes with ch04lsea.
local SucceedMission = campaignRuntime and function(when, description)
    M.won = true
    return campaignRuntime.SucceedMission(when, description)
end or SucceedMission
local FailMission = campaignRuntime and function(when, description)
    if not M.won then
        M.lost = true
        if RESTORED_VOICE_LINES and description == "ch04lseb.des" then AudioMessage("ch04005.wav") end
    end
    return campaignRuntime.FailMission(when, description)
end or FailMission
-- CR co-op runtime <<
local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end
local function Distance(from, to)
    -- PORT FIX: missing/deleted handles must not become zero-distance triggers
    -- or select a path overload. Valid-map radii and event order are unchanged.
    if not Valid(from) or (type(to) ~= "string" and not Valid(to)) then
        return math.huge
    end
    return GetDistance(from, to)
end
-- CR co-op fixes >>
-- The nearest human is the body's player for every approach trigger (the retreat waits for the farthest, see
-- farthestTargets). The restored uncloaked detection answers "inside 70 m" for an exposed human within 400 m.
if campaignRuntime then
    local nearest = campaignRuntime.WrapDistance(Distance)
    Distance = function(from, to)
        if RESTORED_UNCLOAKED_DETECTION and from == PLAYERS and to == "trigger_1" and M.missionState == MS_WAITFORID
            and Restored.Exposed() then
            return 0
        end
        return nearest(from, to)
    end
end
-- CR co-op fixes <<
local function RestoreHealth(h)
    -- SOURCE BUG FIX: native Execute dereferences factory/portal/player without
    -- a null check. Skip absent objects instead of crashing; surviving objects
    -- receive exactly the source's per-frame heal, with no respawns/new gates.
    if Valid(h) then
        local current, maximum = GetCurHealth(h), GetMaxHealth(h)
        if current ~= maximum then AddHealth(h, maximum - current) end
    end
end
local function Strike(h)
    if Valid(h) and Valid(M.user) then Attack(h, M.user) end
end
local function Remove(h)
    if Valid(h) then RemoveObject(h) end
end
local function Target(h)
    if Valid(h) then SetUserTarget(h) end
end
local function Perceived(team)
    if Valid(M.user) then SetPerceivedTeam(M.user, team) end
end
local function Cloaked()
    return Valid(M.user) and IsCloaked(M.user)
end
local function DisableCloaking(h)
    if Valid(h) then EnableCloaking(h, false) end
end
local function Done(message)
    -- Native zero audio IDs mean there is no message to wait for. Lua audio
    -- handles are userdata/nil; never pass the native numeric sentinel.
    return message == nil or IsAudioMessageDone(message)
end
local function InspectSilo()
    -- API ADAPTATION: native IsInfo accepts a handle; stock Lua IsInfo accepts
    -- an ODF name. Query the actual map object's ODF, not a guessed silo class.
    return Valid(M.target_silo) and IsInfo(GetOdf(M.target_silo))
end
local function ResetObjectives()
    ClearObjectives()
    if M.missionState >= MS_WAITFORID then
        AddObjective("ch04001.otf", "green")
    elseif M.missionState >= MS_NEARNAVS then
        AddObjective("ch04001.otf", "white")
    end
    if M.target_silo_inspected then
        AddObjective("ch04002.otf", "green")
    elseif M.missionState >= MS_WAITFORID then
        AddObjective("ch04002.otf", "white")
    end
    if M.missionState >= MS_WAITFORSOUND2 then
        AddObjective("ch04003.otf", "white")
    end
end
local function UnitsAttackPlayer()
    if M.user == M.olduser then return end
    for i = 0, 24 do
        if Valid(M.attackuser1[i]) and IsAlive(M.attackuser1[i]) then Strike(M.attackuser1[i]) end
    end
    for i = 0, 3 do
        if Valid(M.attackuser2[i]) and IsAlive(M.attackuser2[i]) then Strike(M.attackuser2[i]) end
    end
    if M.missionState >= MS_WAITFORSOUND3 then
        for i = 0, 3 do
            if Valid(M.attackuser3[i]) and IsAlive(M.attackuser3[i]) then Strike(M.attackuser3[i]) end
            if Valid(M.attackuser4[i]) and IsAlive(M.attackuser4[i]) then Strike(M.attackuser4[i]) end
            if Valid(M.attackuser5[i]) and IsAlive(M.attackuser5[i]) then Strike(M.attackuser5[i]) end
        end
        for i = 0, 5 do
            if Valid(M.attackuser6[i]) and IsAlive(M.attackuser6[i]) then Strike(M.attackuser6[i]) end
        end
    end
end
local function AttackBaseUnits()
    M.attackedAlready = 1
    Perceived(1)
    for i = 0, 24 do M.attackuser1[i] = M.empty[i]; Strike(M.attackuser1[i]) end
    for i = 0, 3 do M.attackuser2[i] = M.turret[i]; Strike(M.attackuser2[i]) end
end
local function CoreFailure()
    if M.attackedAlready ~= 0 then
        if M.coreFailSound ~= nil then
            if Done(M.coreFailSound) then M.coreFailSound = nil end
        elseif Cloaked() then
            M.coreFailSound = AudioMessage("ch04002.wav")
            Decloak(M.user)
            DisableCloaking(M.user)
        end
    end
end
local function SpawnPilots(indices)
    for _, n in ipairs(indices) do
        local h = BuildObject("sspilo", 2, "pilot_" .. n)
        if Valid(h) and Valid(M.empty[n - 1]) then Retreat(h, M.empty[n - 1]) end
    end
end

-- CR restored content >>
-- The co-op state the single-player body keeps in one handle (M.user, the DLL's player), the stock-bug fixes that
-- need state, and the restorations (Docs/CHMISN04_COOP.md). Each restoration has a RESTORED_* flag. Only the
-- authority runs the body; every peer runs the ops and the update hook.
if campaignRuntime then
    local runtime = campaignRuntime
    local coop = runtime.Coop
    local seen, attackSig, nextInfoSend, sensorsBound = {}, nil, 0, false -- per-peer, not saved
    local shot, shotStart -- the end film this peer is showing, not saved
    local function Real(h) return h ~= nil and h ~= 0 and NativeIsValid(h) end
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end

    -- ---------------------------------------------------------------- the humans
    local function Humans()
        local list = {}
        coop.ForEachPlayerHandle(function(h) list[#list + 1] = h end)
        return list
    end
    function Restored.EachHuman(fn) coop.ForEachPlayerHandle(function(h) fn(h) end) end
    function Restored.AnyHuman() return #Humans() > 0 end
    function Restored.NearestHuman(from)
        local best, bestDistance
        for _, h in ipairs(Humans()) do
            local ok, distance = pcall(GetDistance, from, h)
            if ok and type(distance) == "number" and (bestDistance == nil or distance < bestDistance) then
                best, bestDistance = h, distance
            end
        end
        return best
    end
    -- At the alarm decision the group is concealed only if every human is cloaked; afterwards any running cloak counts
    -- (the core failure shuts down whatever is still up).
    function Restored.Cloaked()
        local count, up = 0, 0
        coop.ForEachPlayerHandle(function(h)
            count = count + 1
            if NativeIsCloaked(h) then up = up + 1 end
        end)
        if count == 0 then return false end
        if M.missionState == MS_CAMERAALARM then return up == count end
        return up > 0
    end
    -- The cut detection: an uncloaked human within 400 m of trigger_1 sets the alarm off.
    function Restored.Exposed()
        local exposed = false
        coop.ForEachPlayerHandle(function(h)
            if not exposed and not NativeIsCloaked(h) then
                local ok, distance = pcall(GetDistance, h, "trigger_1")
                if ok and type(distance) == "number" and distance <= 400 then exposed = true end
            end
        end)
        return exposed
    end
    function Restored.HealHumans()
        coop.ForEachPlayerHandle(function(h)
            local current, maximum = NativeGetCurHealth(h), NativeGetMaxHealth(h)
            if current ~= maximum then NativeAddHealth(h, maximum - current) end
        end)
    end

    -- ---------------------------------------------------------------- hide and the disguise
    function Restored.OpHide()
        coop.ForEachPlayerHandle(function(h) NativeHide(h) end)
    end
    -- The body disguises its one player as the enemy (the DLL's team 2, mapped to 5) when the route ends and again at
    -- the portal, and reveals it (team 1) when the base is alarmed. Every human gets the same treatment on every peer;
    -- 0 is a reveal: each human back on their own team. A human whose pilot died and respawned as a new pilot gets the
    -- current state again. Ejecting from a craft is not a respawn: as in the body, that pilot is not disguised.
    function Restored.OpDisguise(team)
        coop.ForEachPlayerHandle(function(h) NativeSetPerceivedTeam(h, team == 0 and GetTeamNum(h) or team) end)
    end
    local function Track()
        local respawned = false
        coop.ForEachPlayerHandle(function(h, id)
            local key = id or "local"
            local before = seen[key]
            local person = type(IsPerson) == "function" and IsPerson(h) or false
            if before ~= nil and before.handle ~= h and person and not Real(before.handle) then
                respawned = true
            end
            seen[key] = { handle = h, person = person }
        end)
        return respawned
    end
    function Restored.Disguise(team)
        local value = team == 2 and 5 or 0
        RState().disguise = value
        Track()
        return runtime.Present("CH4Disguise", value)
    end
    local function Redisguise(r)
        if Track() then runtime.Present("CH4Disguise", r.disguise) end
    end

    -- ---------------------------------------------------------------- the portal, the user target, the end film
    function Restored.OpPortal(mode)
        local portal = GetHandle("portal")
        if not Real(portal) then return end
        if mode == 2 then NativePortalIn(portal) else NativeDeactivatePortal(portal) end
    end
    -- SetUserTarget is the local player's target: a network game marks the object for every human (and the previous
    -- mark goes out).
    function Restored.ShareTarget(h)
        if not Real(h) then return end
        if coop.IsNetworkGame() then
            local r = RState()
            if r.target ~= nil and r.target ~= h and Real(r.target) then runtime.SetObjectiveOff(r.target) end
            r.target = h
            runtime.SetObjectiveOn(h)
        end
        return NativeSetUserTarget(h)
    end
    -- The end film is a CameraPathDir (look along the path), which the runtime's camera stream does not carry: every
    -- peer opens it on CH4Shot and runs it from its own update hook; the authority runs it from the body.
    function Restored.OpShot(path, height, speed)
        if not coop.IsAuthority() and shot == nil then runtime.Native.CameraReady() end
        shot = { path = path, height = height, speed = speed }
    end
    function Restored.Shot(path, height, speed)
        local now = GetTime()
        if shot == nil then shotStart = now end
        if shot == nil or shot.path ~= path or shot.height ~= height or shot.speed ~= speed then
            runtime.Present("CH4Shot", path, height, speed)
        end
        local arrived = NativeCameraPathDir(path, height, speed)
        local eta = CAMERA_ETA[path]
        if not arrived and eta and speed > 0 and coop.IsNetworkGame() and now - shotStart > eta * 1.25 + 3 then
            arrived = true
        end
        return arrived
    end

    -- ---------------------------------------------------------------- the 130-second route
    function Restored.TimerStart(seconds) RState().timerEnd = GetTime() + seconds end
    function Restored.TimerStop() RState().timerEnd = nil end
    function Restored.TimerLeft()
        local finish = RState().timerEnd
        if finish ~= nil then return math.max(0, finish - GetTime()) end
        return NativeGetCockpitTimer()
    end

    -- ---------------------------------------------------------------- loads
    function Restored.OnStart()
        seen, attackSig, sensorsBound, shot = {}, nil, false, nil
    end
    function Restored.OnLoad()
        local r = RState()
        r.afterLoad = true
        -- The opening shot and the alarm shot cannot resume: both report arrival; the alarm shot ends at once.
        if M.missionState == MS_STARTSCENE or M.missionState == MS_CAMERAALARM then r.skipShot = true end
        if M.missionState == MS_CAMERAALARM then M.stateTimer = 0 end
        -- The end film needs a camera again; it is shown from the start of its path.
        if M.missionState == MS_CAMERAEND then runtime.CameraReady() end
    end
    function Restored.SkipCamera()
        local r = RState()
        if not r.skipShot then return false end
        if M.missionState == MS_STARTSCENE or M.missionState == MS_CAMERAALARM then return true end
        r.skipShot = nil
        return false
    end
    function Restored.OnReset() RState().reset = true end
    -- The runtime's Load resets the presentation: rebuild the objective list from the saved state (the body's own
    -- list), the running route timer and the disguise (the body only issues them at their events).
    function Restored.AfterLoad(r)
        ClearObjectives()
        if M.missionState >= MS_WAITFORID then
            AddObjective("ch04001.otf", "green")
        elseif M.missionState >= MS_NEARNAVS then
            AddObjective("ch04001.otf", "white")
        end
        if M.target_silo_inspected then
            AddObjective("ch04002.otf", "green")
        elseif M.missionState >= MS_WAITFORID then
            AddObjective("ch04002.otf", "white")
        end
        if M.missionState >= MS_WAITFORSOUND2 then AddObjective("ch04003.otf", "white") end
        if r.timerEnd ~= nil then
            local remaining = r.timerEnd - GetTime()
            if remaining > 0 then runtime.Present("StartCockpitTimer", remaining) end
        end
        if r.disguise then runtime.Present("CH4Disguise", r.disguise) end
    end

    -- ---------------------------------------------------------------- the inspection relay
    function Restored.OnInfo(from, prefix)
        local player = coop.GetPlayers()[from]
        if coop.IsNetworkGame() and coop.IsAuthority() and player and coop.IsHumanTeam(player.team)
            and type(prefix) == "string" and INFO_PREFIXES[prefix] then
            remoteInfo[prefix] = GetTime()
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
        for prefix in pairs(INFO_PREFIXES) do
            if NativeIsInfo(prefix) then
                Send(leaderId, "I", prefix)
                nextInfoSend = now + 0.25
            end
        end
    end
    -- Every peer, every frame after the session is ready.
    function Restored.OnUpdate(authority)
        if not sensorsBound and runtime.Weather then
            sensorsBound = true
            local ok, Environment = pcall(require, "Environment")
            if ok and type(Environment) == "table" and Environment.BindWeatherSensors then
                pcall(Environment.BindWeatherSensors, "Ganymede", runtime.Weather.module)
            end
        end
        if coop.IsNetworkGame() and not authority then
            RelayInfo()
            if shot ~= nil then NativeCameraPathDir(shot.path, shot.height, shot.speed) end
        end
    end

    -- ---------------------------------------------------------------- the authority's step (after the body)
    local function Signature()
        local parts = {}
        for _, h in ipairs(Humans()) do parts[#parts + 1] = tostring(h) end
        table.sort(parts)
        return table.concat(parts, ",")
    end
    local function Group(t, last)
        local list = {}
        for i = 0, last do list[#list + 1] = t[i] end
        return list
    end
    -- Stock: the attack groups retarget only when the player's handle changes, and the body's player is now a token
    -- that never changes. A human who dies, respawns or changes craft would leave them on a dead handle: order them
    -- again, each at the human nearest to it. The portal guards (never ordered) are ordered only on such a change,
    -- as in the body.
    local function Reorder()
        local groups = { Group(M.attackuser1, 24), Group(M.attackuser2, 3) }
        if M.missionState >= MS_WAITFORSOUND3 then
            groups[#groups + 1] = Group(M.attackuser3, 3)
            groups[#groups + 1] = Group(M.attackuser4, 3)
            groups[#groups + 1] = Group(M.attackuser5, 3)
            groups[#groups + 1] = Group(M.attackuser6, 5)
        end
        for _, group in ipairs(groups) do
            for _, h in ipairs(group) do
                if Real(h) and NativeIsValid(h) and IsAlive(h) then Attack(h, PLAYERS) end
            end
        end
    end
    -- A ticket whose order named the token is ordered at the nearest human when the unit is built.
    function Restored.Built(h, request)
        for _, order in ipairs(request.orders) do
            if order[1] == "Attack" and order[2] == PLAYERS then
                local target = Restored.NearestHuman(h)
                if target ~= nil then runtime.Attack(h, target, order[3]) end
            end
        end
    end
    local NINE = { 15, 16, 18, 19, 20, 21, 22, 23, 24 }
    function Restored.Step()
        local r = RState()
        local state = M.missionState
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad(r) end
        if r.disguise then Redisguise(r) end
        if M.attackedAlready ~= 0 and state <= MS_WAITFORPORTAL then
            local sig = Signature()
            if attackSig ~= nil and sig ~= attackSig then Reorder() end
            attackSig = sig
        else
            attackSig = nil
        end
        -- Unused shipped objective ch04004.otf "Remember to cloak!", with the cut detection that gives it meaning: on
        -- the list from the first nav until the base is alarmed or the silo is identified. The body just rebuilt the
        -- list (ClearObjectives ran this frame): append to it.
        if r.reset then
            r.reset = nil
            if RESTORED_UNCLOAKED_DETECTION and state >= MS_NEARNAVS and state <= MS_INSPECTSILO and M.attackedAlready == 0 then
                runtime.AddObjective("ch04004.otf", "white")
            end
        end
        -- Cut: `navPoints[0] = BuildObject("apcamr", 1, "nav_silo"); SetName(navPoints[0], "Silo"); SetUserTarget(navPoints[0]);`
        if RESTORED_SILO_BEACON then
            if state == MS_WAITFORID and not r.siloBeacon and not r.siloBeaconDone and Real(M.target_silo) then
                r.siloBeaconDone = true
                local beacon = BuildObject("apcamr", 1, "nav_silo")
                if Real(beacon) then
                    r.siloBeacon = beacon
                    SetObjectiveName(beacon, "Silo")
                    Restored.ShareTarget(beacon)
                end
            elseif r.siloBeacon ~= nil and state >= MS_WAITFORSOUND2 then
                if Real(r.siloBeacon) then RemoveObject(r.siloBeacon) end
                r.siloBeacon = nil
            end
        end
        -- Cut: the pilots for empty_15, empty_16 and empty_18..24 (`Retreat(BuildObject("sspilo", 2, temp), temp)`), beside
        -- the other sixteen, when the alarm shot ends.
        if RESTORED_ALARM_PILOTS and state == MS_NEARSILO and not r.nine then
            r.nine = true
            for _, n in ipairs(NINE) do
                local craft = M.empty[n - 1]
                if Real(craft) then
                    local pilot = BuildObject("sspilo", 2, craft)
                    if Real(pilot) then Retreat(pilot, craft) end
                end
            end
        end
        -- Unused shipped line ch04004 "As we thought, they are stockpiling scrap, now get back to base." when the silo is
        -- identified; it queues behind the core-failure line ch04002 and ahead of the alarm ch04003.
        if RESTORED_VOICE_LINES and state == MS_WAITFORSOUND2 and not r.l404 then
            r.l404 = true
            AudioMessage("ch04004.wav")
        end
        -- The body heals and hides its one player at the portal; every human gets the same. Cut: `fakePlayer =
        -- BuildObject(cfg, 1, user); ... Goto(fakePlayer, "auto_end");` the hidden player's stand-in flies the path the end
        -- film follows (here one per human, a copy of their craft).
        if state == MS_CAMERAEND then
            Restored.HealHumans()
            if RESTORED_FAKE_CRAFT and not r.fakes then
                r.fakes = {}
                for _, human in ipairs(Humans()) do
                    local ok, odf = pcall(GetOdf, human)
                    if ok and type(odf) == "string" then
                        local fake = BuildObject(odf, 1, human)
                        if Real(fake) then
                            r.fakes[#r.fakes + 1] = fake
                            local current, fakeCurrent = NativeGetCurHealth(human), NativeGetCurHealth(fake)
                            if current ~= fakeCurrent then NativeAddHealth(fake, current - fakeCurrent) end
                            Goto(fake, "auto_end")
                        end
                    end
                end
            end
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[chmisn04cr] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
    M.target_silo = GetHandle("target_silo")
    M.navPoints[0] = GetHandle("nav_1")
    M.cca_factory = GetHandle("cca_factory")
    M.factory = GetHandle("factory")
    M.portal = GetHandle("portal")
    for i = 0, 24 do M.empty[i] = GetHandle("empty_" .. (i + 1)) end
    for i = 0, 3 do M.turret[i] = GetHandle("turret_" .. (i + 1)) end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    RestoreHealth(M.factory)
    RestoreHealth(M.portal)
    if M.missionState == MS_CAMERAEND then RestoreHealth(M.user) end
    if M.attackedAlready ~= 0 and M.missionState <= MS_WAITFORPORTAL then UnitsAttackPlayer() end
    if M.missionState ~= MS_STARTUP and M.user ~= M.olduser then
        if M.insideCloakedShip then
            if Valid(M.olduser) then Decloak(M.olduser) end
            DisableCloaking(M.olduser)
        end
        M.insideCloakedShip = false
    end

    -- Deliberate native fall-through: startup executes the first camera frame
    -- immediately; WAITFORALARM executes CAMERAALARM on the spawning frame.
    if M.missionState == MS_STARTUP then
        SetScrap(1, 0)
        SetPilot(1, 10)
        M.olduser = M.user
        M.missionState = MS_STARTSCENE
        M.soundHandle = AudioMessage("ch04001.wav")
        CameraReady()
    end
    if M.missionState == MS_WAITFORALARM and M.stateTimer < GetTime() then
        SpawnPilots({1, 2, 3, 4, 5, 6, 11, 14, 17, 25})
        M.missionState = MS_CAMERAALARM
        M.stateTimer = GetTime() + 5
        CameraReady()
    end

    if M.missionState == MS_STARTSCENE then
        local arrived = CameraPath("camera_start", 1000, 1200, M.target_silo)
        if arrived or CameraCancelled() then
            if M.soundHandle ~= nil then StopAudioMessage(M.soundHandle) end
            CameraFinish()
            M.missionState = MS_PLAYSOUND7
            M.stateTimer = GetTime() + 5
        end
    elseif M.missionState == MS_PLAYSOUND7 then
        if M.stateTimer < GetTime() then
            AudioMessage("ch04007.wav")
            StartCockpitTimer(2 * 60 + 10)
            M.missionState = MS_NEARNAVS
            M.uptonavpoint = 0
            ResetObjectives()
            Target(M.navPoints[0])
        end
    elseif M.missionState == MS_NEARNAVS then
        if GetCockpitTimer() < 1 then
            AudioMessage("ch04006.wav")
            FailMission(GetTime() + 2, "ch04lsea.des")
            M.missionState = MS_END
        elseif Distance(M.user, M.navPoints[M.uptonavpoint]) < 50 then
            if M.uptonavpoint >= 5 then
                for i = 0, M.uptonavpoint do Remove(M.navPoints[i]) end
                HideCockpitTimer()
                M.missionState = MS_WAITFORID
                M.stateTimer = GetTime() + 20 -- TRO 1.3: 20 s fallback if the player never reaches trigger_1 (FUN_005b33a0)
                ResetObjectives()
                -- Cut SetUserTarget(target_silo)/nav_silo beacon: source archive.
                Perceived(2)
                if Valid(M.target_silo) then SetObjectiveOn(M.target_silo) end
            else
                M.uptonavpoint = M.uptonavpoint + 1
                M.navPoints[M.uptonavpoint] = BuildObject("apcamr", 1, "nav_" .. (M.uptonavpoint + 1))
                if M.uptonavpoint == 5 and Valid(M.navPoints[5]) then
                    SetObjectiveName(M.navPoints[5], "Pit Entrance") -- native SetName alias
                end
                Target(M.navPoints[M.uptonavpoint])
            end
        end
    elseif M.missionState == MS_WAITFORID then
        M.target_silo_inspected = InspectSilo()
        -- Disabled cloak/distance<=400 detection and ch04002: source archive.
        if Distance(M.user, "trigger_1") <= 70 or M.target_silo_inspected or M.stateTimer < GetTime() then
            M.soundHandle = nil
            M.missionState = WS_WAITFORSOUND2
        end
    elseif M.missionState == WS_WAITFORSOUND2 then
        if Done(M.soundHandle) then
            -- soundHandle = AudioMessage("ch04003.wav"); -- disabled in source
            M.stateTimer = GetTime() + 1
            M.missionState = MS_WAITFORALARM
        end
    elseif M.missionState == MS_CAMERAALARM then
        CameraPath("camera_alarm", 2000, 0, M.cca_factory)
        -- Disabled alarm audio and pilots at empty_15/16/18..24: source archive.
        if CameraCancelled() or M.stateTimer < GetTime() then
            CameraFinish()
            SpawnPilots({7, 8, 9, 10, 12, 13})
            if not Cloaked() then AttackBaseUnits() else M.attackedAlready = 0 end
            M.missionState = MS_NEARSILO
        end
    elseif M.missionState == MS_NEARSILO then
        -- Disabled delayed ch04003 audio: source archive.
        CoreFailure()
        if Distance(M.user, M.target_silo) <= 200 then
            local h = BuildObject("svfigh", 2, "fighter_1")
            if Valid(h) then Goto(h, "figh1_path") end
            h = BuildObject("svfigh", 2, "fighter_2")
            if Valid(h) then Goto(h, "figh2_path") end
            M.missionState = MS_INSPECTSILO
        end
    elseif M.missionState == MS_INSPECTSILO then
        CoreFailure()
        if not M.target_silo_inspected then M.target_silo_inspected = InspectSilo() end
        if M.target_silo_inspected then
            M.soundHandle = nil
            if Valid(M.target_silo) then SetObjectiveOff(M.target_silo) end
            M.missionState = MS_WAITFORSOUND2
            M.stateTimer = GetTime() + 45 -- intentionally unused in source
            ResetObjectives()
            if M.attackedAlready == 0 then
                if Cloaked() then
                    M.soundHandle = AudioMessage("ch04002.wav")
                    Decloak(M.user)
                end
                DisableCloaking(M.user)
                AttackBaseUnits()
            end
        end
    elseif M.missionState == MS_WAITFORSOUND2 then
        if Done(M.soundHandle) then
            M.soundHandle = AudioMessage("ch04003.wav")
            for i = 0, 3 do
                M.attackuser3[i] = BuildObject("svfigha", 2, "chase_1"); Strike(M.attackuser3[i])
                M.attackuser4[i] = BuildObject("svtanka", 2, "chase_2"); Strike(M.attackuser4[i])
                M.attackuser5[i] = BuildObject("svfigha", 2, "chase_3"); Strike(M.attackuser5[i])
            end
            -- Source gives these six no initial Attack command. They retarget
            -- only on a later player-handle change; preserve that behavior.
            for i = 0, 5 do M.attackuser6[i] = BuildObject("svfigh", 2, "portal_units") end
            -- Native activatePortal(portal, TRUE) selects inward direction.
            if Valid(M.portal) then PortalIn(M.portal) end
            M.missionState = MS_WAITFORSOUND3
        end
    elseif M.missionState == MS_WAITFORSOUND3 then
        if Done(M.soundHandle) then
            M.soundHandle = AudioMessage("ch04008.wav")
            M.missionState = MS_WAITFORSOUND8
        end
    elseif M.missionState == MS_WAITFORSOUND8 then
        if Done(M.soundHandle) then
            M.portalTimeOut = GetTime() + 60 * 2 + 15
            -- RemoveObject(navPoints[0]); -- disabled in source
            M.navPoints[0] = BuildObject("apcamr", 1, "nav_base")
            Target(M.navPoints[0])
            M.missionState = MS_WAITFORPORTAL
        end
    elseif M.missionState == MS_WAITFORPORTAL then
        if M.portalTimeOut < GetTime() then
            FailMission(GetTime() + 2, "ch04lseb.des")
            M.missionState = MS_END
        elseif Distance(M.user, M.portal) < 100 then
            Remove(M.navPoints[0])
            HideCockpitTimer()
            -- Cut fakePlayer creation/health copy/Goto: source archive.
            Perceived(2)
            RestoreHealth(M.user)
            if Valid(M.user) then Hide(M.user) end
            M.missionState = MS_CAMERAEND
            CameraReady()
            M.endNear = false
            M.stateTimer = 0
        end
    elseif M.missionState == MS_CAMERAEND then
        -- PORT ADAPTATION: native 'arrived' is assigned only on the moving
        -- branch and short-circuiting prevents its use on the stationary one.
        -- Initialize false in Lua; camera arrival, the 2-second hold and
        -- victory timing are unchanged.
        local arrived = false
        if not M.endNear then
            arrived = CameraPathDir("auto_end", 500, 4500) -- TRO 1.3: 4500 (FUN_005b33a0)
        else
            CameraPathDir("auto_end", 500, 0)
        end
        -- Cut GetCurrentCommand(fakePlayer) == CMD_NONE check: source archive.
        if not M.endNear and arrived then
            M.endNear = true
            M.stateTimer = GetTime() + 2
        end
        if M.endNear and M.stateTimer < GetTime() then
            if Valid(M.portal) then DeactivatePortal(M.portal) end
            M.missionState = MS_END
            SucceedMission(GetTime() + 4, "ch04win.des")
        end
        -- Native end camera intentionally has no cancellation/CameraFinish.
    end
    if M.user ~= M.olduser then M.olduser = M.user end
end

function Save()
    return M
end
function Load(state)
    -- LuaMission serializes tables and engine handles; do not rerun Start or
    -- replay spawns/cameras/audio on load. Zero-based arrays remain intact.
    M = state
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
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
    BodyUpdate(dt)
    if campaignRuntime then
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
