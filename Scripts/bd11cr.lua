-- Faithful BlackDog11Mission port for stock BZR 2.1+ / Lua 5.1.
-- Source blob: 9378d51ee65985f7859fe7f82dd7ffbf185e72b4.
-- Complete original source, including all comments, TEST_EXPLOSION and native
-- serialization: References/BlackDog11Source/BlackDog11Mission.cpp.
-- Zero-based arrays retain native index arithmetic and the 71 enemy slots.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN11_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Elysium weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn11CoopSourceParity.py).
-- CR co-op layer <<
local NEVER = 999999.9
-- //#define TEST_EXPLOSION: disabled in the shipped native source.
local TEST_EXPLOSION = false
local unitBase, NUM_UNITS = 6, 71
local attacks = {
    [0] = 0,
    2,
    4,
    8,
    11,
    14,
    23,
}
local attackSpawns = {
    [0] = "attack_1",
    "attack_2",
    "attack_3",
    "attack_4",
    "attack_5",
    "attack_6",
}
local attackUnits = {
    [0] = "cvhraz", --  attack 1
    "cvhraz",
    "cvhtnk", --  attack 2
    "cvhraz",
    "cvhraz", --  atttack 3
    "cvhraz",
    "cvhtnk",
    "cvhtnk",
    "cvhtnk", --  attack 4
    "cvhtnk",
    "cvhtnk",
    "cvhraz", --  attack 5
    "cvhraz",
    "cvhraz",
    "cvhtnk", --  attack 6
    "cvhtnk",
    "cvhtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh",
    "cvhraz",
    "cvhraz",
    "cvhraz",
}
local defends = {
    [0] = 0,
    4,
    9,
    14,
    21,
    30,
    42,
}
local defendSpawns = {
    [0] = "defend_1",
    "defend_2",
    "defend_3",
    "defend_4",
    "defend_5",
    "defend_6",
}
local defendUnits = {
    [0] = "cvtnk", --  defend 1
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh", --  defend 2
    "cvfigh",
    "cvfigh",
    "cvhtnk",
    "cvltnk",
    "cvtnk", --  defend 3
    "cvtnk",
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh", --  defend 4
    "cvfigh",
    "cvfigh",
    "cvfigh",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvhtnk", --  defend 5
    "cvhtnk",
    "cvhtnk",
    "cvhtnk",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvhtnk", --  defend 6
    "cvhtnk",
    "cvhtnk",
    "cvhtnk",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvtnk",
    "cvfigh",
    "cvfigh",
    "cvfigh",
    "cvfigh",
}
--const int numUnits = unitBase + attacks[7] + defends[7];
local function NewState()
    return {
        startDone = false, objective1Complete = false,
        objective2Complete = false, objective3Complete = false,
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false},
        apcWantsToTransferPilot = false, pilotTransferring = false,
        toldToGo = false, attacksSent = false, navDistanceOk = false,
        retreatSpawned = false, sound4Played = false, sound5Played = false,
        sound6Played = false, cockpitTimerActive = false,
        explodePortal = false, lost = false, won = false,
        recyclerGoTime = NEVER, drive1Time = NEVER,
        attackTimes = {[0] = NEVER, NEVER, NEVER, NEVER, NEVER, NEVER},
        goToPortalTime = NEVER, cameraDestructTime = NEVER, waveFallbackTime = NEVER,
        explodeTime = NEVER, explodeDelay = NEVER,
        explode1Time = NEVER, explode2Time = NEVER,
        explode3Time = NEVER, explode4Time = NEVER,
        aerial1Time = NEVER, aerial2Time = NEVER, portalTime = NEVER,
        sound8Time = NEVER, sound9Time = NEVER, sound12Time = NEVER,
        portalStage = 0, enemy = {}, retreats = {},
        -- Other handles/audio IDs begin nil (native NULL).
        -- Native unused fields retained: objective3Complete, camera slot 1,
        -- apcWantsToTransferPilot, retreatSpawned, retreats, navEnd,
        -- portalTime and portalStage. Do not invent retreat/portal stages.
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN11_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut block off (Docs/BDMISN11_COOP.md, "Restored content").
local RESTORED_TROUBLE_LINE = true
local RESTORED_DETONATION_WARNING = true
local RESTORED_NAV_END = true
local Restored
-- Every Chinese combat craft and soldier the body builds becomes a concealed, head-count-scaled ticket.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvtnk = true, cvhtnk = true, cvhraz = true, cvwalk = true, cssold = true }
local NativeColorFade, NativeMakeExplosion = ColorFade, MakeExplosion
local NativeGetCockpitTimer = GetCockpitTimer
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bdmisn11", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2,
    rallyPoints = { [0] = "recycler" }, -- the shared Black Dog base is the recycler
    scaledOdfs = SCALED_ODFS,
    -- A spawn path with a human within 460 m (the aerial drop sits 230 m from the geyser the recycler settles on)
    -- comes from the next hidden Chinese approach instead.
    fallbackEntries = { "attack_5", "attack_1", "drive_1", "attack_4", "attack_2" },
    liveCap = 24, -- six waves with their escorts, two aerial drops and two raids can overlap
    scrapPerGuest = 10,
    failDes = "bd11lseb.des", -- out of lives: the surrender debrief of a lost Recycler
    -- The portal blast ends the mission whatever it does to the humans next to it (the win is unconditional).
    wonFlags = { "won", "explodePortal" },
    endedFlags = { "won", "lost" },
    -- Light and sound of the portal's end are local effects: every peer shows its own.
    presentationOps = {
        ColorFade = function(...) if NativeColorFade then NativeColorFade(...) end end,
        BD11Boom = function(odf, where) if Restored then Restored.Boom(odf, where) end end,
    },
    -- Elysium: the Venus engine in its Earth-like storm dress (Docs/BDMISN11_COOP.md, "Weather: Elysium").
    weather = { module = "CRElysiumWeather", sites = "CRElysiumSitesBD11", startLevel = 1, targetLevel = 1,
        beats = function(elysium, state, s)
            local beats = s.elysiumBeats
            if beats == nil then beats = {}; s.elysiumBeats = beats end
            local function strikeAt(h)
                if h == nil or h == 0 or not IsValid(h) then return end
                local p = GetPosition(h)
                if p ~= nil then elysium.TriggerStrike({ x = p.x, y = p.y, z = p.z }) end
            end
            local sent = state.attacksSent and state.attackTimes
            local function waveSent(i) return sent and sent[i] == NEVER end
            -- The pilot is aboard: the Black Dogs have a Recycler again and the sky takes notice.
            if (not beats.crewed) and state.objective1Complete then
                beats.crewed = true
                elysium.SetTargetLevel(2)
            end
            -- The Recycler reaches the geyser and the first raiders drive in: the cloud deck closes.
            if (not beats.raid) and state.attacksSent then
                beats.raid = true
                elysium.SetTargetLevel(3)
            end
            -- The third wave: the storm breaks.
            if (not beats.storm) and waveSent(2) then
                beats.storm = true
                elysium.SetTargetLevel(4)
            end
            -- Each aerial drop comes down under a strike over the base.
            if (not beats.aerial1) and sent and state.aerial1Time == NEVER then
                beats.aerial1 = true
                strikeAt(state.recycler)
            end
            if (not beats.aerial2) and sent and state.aerial2Time == NEVER then
                beats.aerial2 = true
                strikeAt(state.recycler)
            end
            -- The last and largest wave.
            if (not beats.last) and waveSent(5) then
                beats.last = true
                strikeAt(state.recycler)
            end
            -- "Get to the portal": the ninety-second run is made under the worst of the sky.
            if (not beats.run) and state.cockpitTimerActive then
                beats.run = true
                elysium.SetTargetLevel(5)
            end
            -- The portal blows: lightning walks over it.
            if (not beats.blast) and state.explodePortal then
                beats.blast = true
                strikeAt(state.portal)
            end
            -- Victory: the sky eases for the debrief.
            if (not beats.easing) and state.won then
                beats.easing = true
                elysium.SetTargetLevel(2)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        load = function() if Restored then Restored.OnLoad() end end,
    },
})
local NativeBuildObject, NativeSetCloaked = BuildObject, SetCloaked
local IsValid = campaignRuntime and campaignRuntime.IsValid or IsValid
local Attack = campaignRuntime and campaignRuntime.Attack or Attack
local Defend2 = campaignRuntime and campaignRuntime.Defend2 or Defend2
local SetScrap = campaignRuntime and campaignRuntime.SetScrap or SetScrap
-- A line whose audio handle is absent counts as finished, so no gate can wait on it for ever: a failed
-- AudioMessage returns 0 (the body's `~= nil` gates then see an already finished line).
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
local StopAudioMessage = campaignRuntime and campaignRuntime.StopAudioMessage or StopAudioMessage
-- The opening ends when the shot arrives. The runtime stops driving a shot the host skipped (it releases only the
-- host's own camera), so in a network game that shot would never arrive and the guests would stay in the film for
-- ever: a host skip raised after the shot began ends the shared opening instead.
local shotStart, shotSkipped = nil, false
local CameraReady = campaignRuntime and function()
    shotStart, shotSkipped = GetTime(), false
    return campaignRuntime.CameraReady()
end or CameraReady
local CameraPath = campaignRuntime and function(path, height, speed, target)
    if Restored and path == "camera_destruct" then Restored.Destruct(true) end
    if shotSkipped then return true end
    local cancelled = campaignRuntime.Coop.IsNetworkGame() and shotStart ~= nil and GetTime() > shotStart
        and campaignRuntime.Native.CameraCancelled()
    local arrived = campaignRuntime.CameraPath(path, height, speed, target)
    if cancelled then shotSkipped = true; return true end
    return arrived
end or CameraPath
local CameraFinish = campaignRuntime and function()
    if Restored then Restored.Destruct(false) end
    return campaignRuntime.CameraFinish()
end or CameraFinish
local CameraCancelled = campaignRuntime and campaignRuntime.CameraCancelled or CameraCancelled
-- Every published objective list is remembered, so a load can publish it again (the runtime's Load resets the
-- presentation).
local ClearObjectives = campaignRuntime and function()
    if Restored then Restored.Objectives(nil) end
    return campaignRuntime.ClearObjectives()
end or ClearObjectives
local AddObjective = campaignRuntime and function(text, color)
    if Restored then Restored.Objectives(text, color) end
    return campaignRuntime.AddObjective(text, color)
end or AddObjective
local SetObjectiveName = campaignRuntime and campaignRuntime.SetObjectiveName or SetObjectiveName
local SetObjectiveOn = campaignRuntime and function(h)
    if Restored then Restored.Marked(h) end
    return campaignRuntime.SetObjectiveOn(h)
end or SetObjectiveOn
local RemoveObject = campaignRuntime and campaignRuntime.RemoveObject or RemoveObject
local SucceedMission = campaignRuntime and campaignRuntime.SucceedMission or SucceedMission
local FailMission = campaignRuntime and campaignRuntime.FailMission or FailMission
-- The portal countdown is presentation: every peer shows the host's timer. The engine cannot keep the clock (the
-- map runs MultSTMission, which restarts the cockpit timer upward every frame), so the host counts the 90 s itself.
local StartCockpitTimer = campaignRuntime and function(seconds, warn, alert)
    Restored.TimerStart(seconds, warn, alert)
    return campaignRuntime.Present("StartCockpitTimer", seconds, warn, alert)
end or StartCockpitTimer
local HideCockpitTimer = campaignRuntime and function()
    Restored.TimerHide()
    return campaignRuntime.Present("HideCockpitTimer")
end or HideCockpitTimer
local GetCockpitTimer = campaignRuntime and function() return Restored.TimerLeft() end or GetCockpitTimer
local ColorFade = campaignRuntime and function(...) return campaignRuntime.Present("ColorFade", ...) end or ColorFade
-- The blast particles are a local effect too: the host makes its own (with the damage) and the guests theirs.
local MakeExplosion = campaignRuntime and function(odf, where)
    NativeMakeExplosion(odf, where)
    if campaignRuntime.Coop.IsNetworkGame() then
        -- a path travels by name, the portal object as 1 (every peer has its own copy by label)
        return campaignRuntime.Present("BD11Boom", odf, (type(where) == "string" and where ~= M.portal) and where or 1)
    end
end or MakeExplosion
-- Only the dead TEST_EXPLOSION block names a team (the user turns Chinese); the Chinese are team 5 here.
local SetPerceivedTeam = campaignRuntime and function(h, team)
    if team == 2 then team = 5 end
    return SetPerceivedTeam(h, team)
end or SetPerceivedTeam
-- The body's team 1 is the one shared Black Dog side: its 10 pilots go to every human team (each human respawns
-- from its own pool); the Chinese are team 2 in the DLL and team 5 here.
local SetPilot = campaignRuntime and function(team, count)
    if team == 1 then
        campaignRuntime.Coop.ForEachHumanTeam(function(humanTeam) if humanTeam ~= 1 then SetPilot(humanTeam, count) end end)
        return SetPilot(1, count)
    end
    if team == 2 then team = 5 end
    return SetPilot(team, count)
end or SetPilot
-- Every Chinese craft is a ticket. A new scripted spawn (a new frame or a new entry path) is a new scaling event:
-- the first unit of each is mirrored by min(floor(humans / 2), 2) extras with its orders. The body's point index
-- (400 on the one-point path aerial_1) is the C++ altitude offset, so it is passed on as the ticket's drop height.
local eventFrame, eventWhere
local BuildObject = campaignRuntime and function(odf, team, where, lift)
    if SCALED_ODFS[odf] then
        local now = GetTime()
        if eventFrame ~= now or eventWhere ~= where then
            eventFrame, eventWhere = now, where
            campaignRuntime.BeginEvent()
        end
    end
    return campaignRuntime.Spawn(odf, team, where, lift)
end or BuildObject
-- The wave units are cloaked: a unit that is still a ticket is cloaked when the real unit is built (Restored.Built).
local SetCloaked = campaignRuntime and function(h)
    if type(h) == "number" and h < 0 then
        if Restored then Restored.DeferCloak(-h) end
        return
    end
    return NativeSetCloaked(h)
end or SetCloaked
-- CR co-op runtime <<
local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Health(h)
    -- PORT FIX: deleted/missing handles count as zero health without invoking
    -- a Lua overload on nil. Existing health thresholds/loss ordering are intact.
    return Valid(h) and GetHealth(h) or 0
end
local function StopSound(id)
    if id ~= nil and id ~= 0 then StopAudioMessage(id) end
end
local function AtPathEnd(h, path)
    -- STOCK ADAPTATION: native isAtEndOfPath is not exposed to stock Lua.
    -- TRO 1.3: 12 m 2D (x,z) distance to the last path point (FUN_0042b850). This changes only
    -- when the escort objective turns green, never the independent wave trigger.
    if not Valid(h) then return false end
    local count = GetPathPointCount(path)
    if count <= 0 then return false end
    local p, q = GetPosition(h), GetPosition(path, count - 1)
    local dx, dz = p.x - q.x, p.z - q.z
    return math.sqrt(dx * dx + dz * dz) < 12
end
-- STOCK BUG FIX (TRO LUA-Patch 2939339901, original TRO): the C++ 400 is an altitude, which stock Lua reads as a
-- point index, so the paratroopers landed on the ground. Drop each one from that height over a 10-50 m scatter
-- round the path's point.
local DropAt = function(odf, team, path, lift)
    local p = GetPosition(path)
    local a, r = math.random() * 2 * math.pi, 10 + math.random() * 40
    return BuildObject(odf, team, SetVector(p.x + r * math.cos(a), p.y + lift, p.z + r * math.sin(a)))
end
-- CR co-op runtime >>
-- The runtime builds the drop as tickets at the path (one scaling event) and lifts each by the height itself.
DropAt = campaignRuntime and function(odf, team, path, lift) return BuildObject(odf, team, path, lift) end or DropAt
-- CR co-op runtime <<
local function SpawnAerial()
    for i = 0, 7 do
        local h = DropAt("cssold", 2, "aerial_1", 400)
        if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
    end
end
-- CR restored content >>
-- The co-op fixes that need state and the cut content (Docs/BDMISN11_COOP.md lists each; every restoration is
-- behind a RESTORED_* flag at the top of the runtime region and gated on what the shipped map carries).
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    local function RState()
        local s = runtime.State()
        s.r = s.r or {}
        return s.r
    end
    -- The body cloaks every wave unit right after building it; for a ticket the cloak waits for the real unit
    -- (and for the extras that mirror it).
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
    -- What the presentation shows is remembered (saved with the mission state) so a load can show it again.
    function Restored.Objectives(text, color)
        local r = RState()
        if text == nil then r.objectives = {} else
            r.objectives = r.objectives or {}
            r.objectives[#r.objectives + 1] = { text, color }
        end
    end
    function Restored.Marked(h)
        if h ~= nil and h == M.portal then RState().portalOn = true end
    end
    function Restored.Destruct(on) RState().destruct = on or nil end
    function Restored.TimerStart(seconds, warn, alert)
        local r = RState()
        r.timerEnd, r.timerWarn, r.timerAlert = GetTime() + seconds, warn, alert
    end
    function Restored.TimerHide() RState().timerEnd = nil end
    function Restored.TimerLeft()
        local finish = RState().timerEnd
        if finish ~= nil then return math.max(0, finish - GetTime()) end
        return NativeGetCockpitTimer()
    end
    function Restored.Boom(odf, where)
        if runtime.Coop.IsAuthority() then return end -- the host made its own
        local target = where
        if where == 1 then target = GetHandle("portal") end
        if target ~= nil then NativeMakeExplosion(odf, target) end
    end
    function Restored.OnLoad() RState().afterLoad = true end
    -- A load resets the presentation: the objective list, the markers, the portal countdown and a running film
    -- are shown again from the state the mission saved. A load cannot resume a camera (the shots are gone): the
    -- opening keeps calling its CameraPath every frame and ends itself, the destruction shot opens again.
    function Restored.AfterLoad(r)
        if M.cameraReady[0] and not M.cameraComplete[0] then CameraReady() end
        if r.destruct and Valid(M.portal) then
            CameraReady()
            CameraPath("camera_destruct", 1000, 0, M.portal)
        end
        if r.objectives then
            runtime.ClearObjectives()
            for _, entry in ipairs(r.objectives) do runtime.AddObjective(entry[1], entry[2]) end
        end
        if Valid(M.navRecycler) then runtime.SetObjectiveName(M.navRecycler, "Recycler") end
        if Valid(r.navEnd) then runtime.SetObjectiveName(r.navEnd, "Portal") end
        if r.portalOn and Valid(M.portal) then runtime.SetObjectiveOn(M.portal) end
        if M.cockpitTimerActive and r.timerEnd then
            runtime.Present("StartCockpitTimer", math.max(1, r.timerEnd - GetTime()), r.timerWarn or 30, r.timerAlert or 10)
        end
    end
    -- Unused voice line bd11003 ("We're in trouble here, Lieutenant."): the first of the Recycler's distress calls,
    -- ahead of bd11004 ("I don't know how much more we could take"): once, when the Recycler first drops to
    -- three quarters health, never after a later call has played.
    function Restored.TroubleLine(r)
        if not RESTORED_TROUBLE_LINE or r.trouble or not M.objective1Complete then return end
        if M.sound4Played or M.won or M.lost then return end
        local h = Health(M.recycler)
        if h > 0.5 and h <= 0.75 then
            r.trouble = true
            AudioMessage("bd11003.wav")
        end
    end
    -- Cut: `//navEnd = BuildObject("bpcamr", 1, "nav_end");` when the evacuation order arrives. The map carries the
    -- path (16 m from the portal): a Portal nav beacon appears with the order.
    function Restored.NavEnd(r)
        if not RESTORED_NAV_END or r.navEndDone or not M.objective2Complete then return end
        if not runtime.PathExists("nav_end") then return end
        r.navEndDone = true
        local h = BuildObject("bpcamr", 1, "nav_end")
        if Valid(h) then
            r.navEnd = h
            SetObjectiveName(h, "Portal")
        end
    end
    -- Unused objective bd11004.otf ("Resonance cascade detected / Portal detonation imminent / Minimum safe
    -- distance: 700m"): shown when the countdown runs out, until the blast.
    function Restored.Warning(r)
        if not RESTORED_DETONATION_WARNING or r.warned or not M.navDistanceOk or M.explodePortal then return end
        r.warned = true
        ClearObjectives()
        AddObjective("bd11004.otf", "red")
    end
    -- Runs at the end of the body's Update.
    function Restored.Step()
        if not M.startDone then return end
        local r = RState()
        if r.afterLoad then r.afterLoad = nil; Restored.AfterLoad(r) end
        Restored.TroubleLine(r)
        Restored.NavEnd(r)
        Restored.Warning(r)
        -- Stock fix: a Recycler lost after the blast latches the body's lost flag (the failure itself is
        -- ignored by wonFlags) and the body's win check needs not lost, so finish the win here.
        if M.explodePortal and M.lost and not M.won and M.winMessage ~= nil and IsAudioMessageDone(M.winMessage) then
            M.won = true
            SucceedMission(GetTime() + 3.0, "bd11win.des")
        end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(Restored.Step)
        if not ok and not failed then
            failed = true
            print("[bdmisn11] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then campaignRuntime.Start() end
-- CR co-op callback <<
    M.recycler = GetHandle("recycler")
    M.portal = GetHandle("portal")
    M.apc = GetHandle("apc")
    for i = 0, 5 do M.enemy[i] = GetHandle("enemy_" .. (i + 1)) end
    assert(NUM_UNITS == unitBase + attacks[6] + defends[6])
end
function AddObject(h)
    -- Native AddObject(Handle) is empty.
end
function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<

    M.user = GetPlayerHandle()  --assigns the player a handle every frame

    if not M.startDone then
        SetScrap(1, 100)
        SetPilot(1, 10)

        -- setup the initial objectives
        ClearObjectives()
        AddObjective("bd11001.otf", "white")

        -- don't do this part after the first shot
        M.startDone = true

        M.navRecycler = BuildObject("bpcamr", 1, "recy_nav")
        if Valid(M.navRecycler) then SetObjectiveName(M.navRecycler, "Recycler") end

        --#define TEST_EXPLOSION
        if TEST_EXPLOSION then
            SetPerceivedTeam(M.user, 2)
            M.goToPortalTime = GetTime()
        end
    end
    if not TEST_EXPLOSION then
        -- is the recycler dead?
        if not M.lost and Health(M.recycler) <= 0.0 and not M.won then
            M.lost = true
            if M.navDistanceOk then
                FailMission(GetTime() + 1.0, "bd11lseb.des")
            else
                FailMission(GetTime() + 1.0, "bd11lsed.des")
            end
        end

        -- has the apc made it to the recycler yet?
        if not M.objective1Complete and Health(M.apc) <= 0.0 and not M.won and not M.lost then
            M.lost = true
            FailMission(GetTime() + 1.0, "bd11lsea.des")
        end

        if not M.cameraComplete[0] then
            if not M.cameraReady[0] then
                M.cameraReady[0] = true
                CameraReady()

                M.introSound = AudioMessage("bd11001.wav")
            end

            local arrived = true
            if Valid(M.recycler) then arrived = CameraPath("camera_start", 1000, 1600, M.recycler) end

            if CameraCancelled() then
                arrived = true
                StopSound(M.introSound)
            end
            if arrived then
                CameraFinish()
                M.cameraComplete[0] = true
            end
        end

        -- is the apc close enough to the "pilot transfer point" ?
        if not M.objective1Complete and not M.pilotTransferring and Valid(M.apc) and Valid(M.recycler) and not M.lost then
            local distance = GetDistance(M.apc, M.recycler)
            -- PORT FIX: no nearest enemy means the transfer area is clear.
            -- Keep the native 50 m approach / 200 m enemy-distance gates for live units.
            local nearestEnemy = GetNearestEnemy(M.apc)
            if distance < 50.0 and (not Valid(nearestEnemy) or GetDistance(M.apc, nearestEnemy) > 200.0) then
                -- stop the apc
                Stop(M.apc, 1)

                -- spawn the pilot
                M.pilotTransferring = true
                M.pilot = BuildObject("aspilo", 1, M.apc)
                if Valid(M.pilot) then Retreat(M.pilot, M.recycler, 1) end
            end
        end

        if M.pilotTransferring then
            if Valid(M.pilot) and Health(M.pilot) > 0 then GiveMaxHealth(M.pilot) end
            -- BUG FIX: never heal a dead/missing transfer pilot before checking defeat.
            -- Live pilots retain native per-frame full health; destroyed ones now reach
            -- the existing bd11lsec loss instead of an invalid-handle call or resurrection.
            -- has the pilot been killed?
            if not M.lost and Health(M.pilot) <= 0.0 and not M.won then
                M.lost = true
                FailMission(GetTime() + 1.0, "bd11lsec.des")
            end

            -- STOCK BUG FIX (TRO LUA-Patch 2447482585): 15 m sits inside the Recycler's hull, so the pilot
            -- often stopped short and never transferred. 25, not the patch's 50: the APC stops anywhere
            -- inside 50 m, so 50 would transfer the pilot the frame it is built.
            if Valid(M.pilot) and Valid(M.recycler) and not M.lost and GetDistance(M.pilot, M.recycler) < 25.0 then
                M.pilotTransferring = false
                M.objective1Complete = true
                RemoveObject(M.pilot)
                M.pilot = nil
                -- STOCK ADAPTATION: native curPilot assignment / AiProcess::Attach is
                -- represented by SetPilotClass. Goto below supplies the scripted AI command;
                -- no extra pilot, boarding delay, health reset or recycler replacement occurs.
                SetPilotClass(M.recycler, "bspilo")

                M.recyclerGoTime = GetTime() + 2.0
                -- STOCK BUG FIX: the waves (and so the portal and the win) arm only when the Recycler
                -- reaches wave_trigger; a Recycler parked or deployed elsewhere stalled the mission.
                M.waveFallbackTime = GetTime() + 6 * 60.0
                -- play sound
                AudioMessage("bd11002.wav")
            end
        end

        if M.recyclerGoTime < GetTime() then
            M.toldToGo = true
            if Valid(M.recycler) then SetTeamNum(M.recycler, 1) end
            M.recyclerGoTime = NEVER
            -- get the recycler moving to the geiser
            if Valid(M.recycler) then Goto(M.recycler, "recycler_path", 1) end

            -- setup drive 1 attack
            M.drive1Time = GetTime() + 20.0
        end

        if M.toldToGo and AtPathEnd(M.recycler, "recycler_path") then
            M.toldToGo = false
            ClearObjectives()
            AddObjective("bd11001.otf", "green")
            AddObjective("bd11002.otf", "white")
            --Goto(recycler, GetHandle("geyser_1"));
        end

        if not M.attacksSent and Valid(M.recycler)
            and (GetDistance(M.recycler, "wave_trigger") < 50.0 or (M.waveFallbackTime or NEVER) < GetTime()) then
            -- start attacks
            M.attacksSent = true
            M.attackTimes[0] = GetTime() + 2 * 60.0
            M.attackTimes[1] = GetTime() + 5 * 60.0
            M.attackTimes[2] = GetTime() + 9 * 60.0
            M.attackTimes[3] = GetTime() + 14 * 60.0
            M.attackTimes[4] = GetTime() + 18 * 60.0
            M.attackTimes[5] = GetTime() + 21 * 60.0

            M.goToPortalTime = GetTime() + 26 * 60.0
            M.aerial1Time = GetTime() + 8 * 60.0
            -- BUG FIX: source assigns aerial1Time twice, losing the 8-minute wave
            -- and never arming aerial2Time. Restore the two explicitly coded waves;
            -- the six main waves and 26-minute portal phase retain their schedule.
            M.aerial2Time = GetTime() + 13 * 60.0

            local h
            h = BuildObject("cvltnk", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvltnk", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvltnk", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvhraz", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
            h = BuildObject("cvhraz", 2, "drive_2")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler) end
        end

        if M.objective1Complete then
            local h = Health(M.recycler)
            -- check the recycler's health
            if h > 0.5 then
                -- do nothing
            elseif not M.sound4Played and h > 0.25 then
                M.sound4Played = true
                M.sound4 = AudioMessage("bd11004.wav")
            elseif not M.sound5Played and h > 0.15 then
                -- stop any previous sounds
                StopSound(M.sound4)

                M.sound5Played = true
                M.sound5 = AudioMessage("bd11005.wav")
            elseif not M.sound6Played and h > 0.0 then
                -- stop any previous sounds
                StopSound(M.sound4)
                StopSound(M.sound5)

                M.sound6Played = true
                M.sound6 = AudioMessage("bd11006.wav")
            end
        end

        if M.drive1Time < GetTime() then
            M.drive1Time = NEVER

            local h = BuildObject("cvwalk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
            h = BuildObject("cvwalk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
            h = BuildObject("cvltnk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
            h = BuildObject("cvltnk", 2, "drive_1")
            if Valid(h) and Valid(M.recycler) then Attack(h, M.recycler, 1) end
        end

        if M.aerial1Time < GetTime() then
            M.aerial1Time = NEVER

            SpawnAerial()
        end

        if M.aerial2Time < GetTime() then
            M.aerial2Time = NEVER

            SpawnAerial()
        end

        for i = 0, 5 do
            if M.attacksSent and M.attackTimes[i] < GetTime() then

                -- so this attack doesn't happen again
                M.attackTimes[i] = NEVER

                -- build the attackers
                local numAttackers = attacks[i+1] - attacks[i]
                for j = 0, numAttackers - 1 do
                    -- build the enemy
                    local unum = unitBase + attacks[i] + defends[i] + j
                    assert(M.enemy[unum] == nil)
                    M.enemy[unum] = BuildObject(attackUnits[attacks[i] + j], 2, attackSpawns[i])
                    if Valid(M.enemy[unum]) then SetCloaked(M.enemy[unum]) end
                    if Valid(M.enemy[unum]) and Valid(M.recycler) then Attack(M.enemy[unum], M.recycler) end
                end

                -- build the defenders
                local numDefenders = defends[i+1] - defends[i]
                for j = 0, numDefenders - 1 do
                    local h = nil
                    local unum = unitBase + attacks[i+1] + defends[i] + j
                    assert(M.enemy[unum] == nil)
                    h = BuildObject(defendUnits[defends[i] + j], 2, defendSpawns[i])
                    M.enemy[unum] = h
                    if Valid(M.enemy[unum]) then SetCloaked(M.enemy[unum]) end
                    local anum = unitBase + attacks[i] + defends[i] + (j % numAttackers)
                    if Valid(h) and Valid(M.enemy[anum]) then Defend2(h, M.enemy[anum], 1) end
                end
            end
        end
    end
    if M.goToPortalTime < GetTime() then
        M.goToPortalTime = NEVER
        ClearObjectives()
        AddObjective("bd11002.otf", "green")
        M.objective2Complete = true

        -- spawn the nav
        --navEnd = BuildObject("bpcamr", 1, "nav_end");
        AudioMessage("bd11007.wav")
        M.sound8Time = GetTime() + 3.0
    end

    if M.sound8Time < GetTime() then
        M.sound8Time = NEVER
        M.sound8 = AudioMessage("bd11008.wav")
    end

    if M.sound8 ~= nil and IsAudioMessageDone(M.sound8) then
        M.sound8 = nil
        M.sound9Time = GetTime() + 5.0
    end

    if M.sound9Time < GetTime() then
        M.sound9Time = NEVER
        AudioMessage("bd11009.wav")
        M.sound10 = AudioMessage("bd11010.wav")
    end

    if M.sound10 ~= nil and IsAudioMessageDone(M.sound10) then
        M.sound10 = nil
        M.sound12Time = GetTime() + 5.0
    end

    if M.sound12Time < GetTime() then
        M.sound12Time = NEVER
        M.sound12 = AudioMessage("bd11012.wav")
    end

    if M.sound12 ~= nil and IsAudioMessageDone(M.sound12) then
        M.sound12 = nil

        ClearObjectives()
        AddObjective("bd11003.otf", "white")

        if Valid(M.portal) then SetObjectiveOn(M.portal) end
        -- start the timer
        StartCockpitTimer(90, 30, 10)
        M.cockpitTimerActive = true
    end

    if M.cockpitTimerActive and GetCockpitTimer() <= 0.0 then
        M.cockpitTimerActive = false
        HideCockpitTimer()
        M.explode1Time = GetTime()
        M.explode2Time = GetTime() + 2.0
        M.explode3Time = GetTime() + 4.0
        M.explode4Time = GetTime() + 6.0
        M.explodeTime = GetTime() + 18.0
        M.cameraDestructTime = M.explodeTime - 1.0
        M.navDistanceOk = true
    end

    -- 4 explosions
    if M.explode1Time < GetTime() then
        M.explode1Time = NEVER
        MakeExplosion("xpltrsk", "dw_1")
    end

    if M.explode2Time < GetTime() then
        M.explode2Time = NEVER
        MakeExplosion("xpltrsk", "dw_2")
    end

    if M.explode3Time < GetTime() then
        M.explode3Time = NEVER
        MakeExplosion("xpltrsk", "dw_3")
    end

    if M.explode4Time < GetTime() then
        M.explode4Time = NEVER
        MakeExplosion("xpltrsk", "dw_4")
    end

    if M.cameraDestructTime < GetTime() then
        M.cameraDestructTime = NEVER
        CameraReady()
        if Valid(M.portal) then CameraPath("camera_destruct", 1000, 0, M.portal) end
    end

    if M.explodeTime < GetTime() then
        M.explodeTime = NEVER
        M.explodeDelay = GetTime() + 3.0
        ColorFade(1.0, 0.5, 255, 255, 255)
        M.explodePortal = true
        -- STOCK ADAPTATION: Lua has no native useD3D renderer bitfield.
        -- Redux uses the hardware-renderer effect; software fallback is archived:
        -- if (useD3D & 4) MakeExplosion(portal, "xpltrso");
        -- else MakeExplosion(portal, "xpltrsp");
        if Valid(M.portal) then MakeExplosion("xpltrso", M.portal) end
    end

    if M.explodeDelay < GetTime() then
        -- finish the camera
        CameraFinish()

        M.explodeDelay = NEVER

        M.winMessage = AudioMessage("bd11011.wav")

        ClearObjectives()
        AddObjective("bd11003.otf", "green")
    end

    if M.winMessage ~= nil and not M.won and not M.lost then
        if IsAudioMessageDone(M.winMessage) then
            M.won = true
            SucceedMission(GetTime() + 3.0, "bd11win.des")
        end
    end

    if Health(M.portal) <= 0.0 and not M.explodePortal and not M.won and not M.lost then
        M.lost = true
        FailMission(GetTime() + 1.0, "bd11lsee.des")
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
    -- Engine restores saved handles/audio; never rerun Setup or reset timers.
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
