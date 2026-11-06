-- BlackDog09Mission: stock BZR / Lua 5.1 port.
-- Upstream blob: 0f93213b17334acf7c0a408a44cdaf3791e1e644.
-- Complete C++, including comments, unused members and native serialization:
-- References/BlackDog09Source/BlackDog09Mission.cpp.
-- Requires Redux 2.1+ ActivatePortal and IsTouching; no helper/shim required.
-- CR co-op layer >>
-- Campaign Reimagined co-op layer (Docs/BDMISN09_COOP.md). Everything between `-- CR ... >>` and `<<` is
-- the CR layer (shared runtime Scripts/CRCCARuntime.lua, restorations, Elysium weather); outside it this file is
-- the faithful port above, byte for byte (Tools/Test-Bdmisn09CoopSourceParity.py).
-- CR co-op layer <<

local NEVER = 999999.9
local function NewState()
    return {
        startDone = false,
        objective1Complete = false, objective2Complete = false,
        objective3Complete = false, -- unused in source
        cameraReady = {[0] = false, [1] = false},
        cameraComplete = {[0] = false, [1] = false}, -- unused camera info
        trigger1 = false, oneOfTheEnemy = false, deviateSpawned = false,
        gotoBeacon2 = false, gotoBeacon3 = false,
        sound7Played = false, sound2Played = false,
        tankArrived1 = false, tankArrived2 = false, tankArrived3 = false,
        strayed = false, portalActive = false, lost = false, won = false,
        sound1Time = NEVER, sound2Time = NEVER, sound3Time = NEVER,
        sound6Time = NEVER, orderGotoTime1 = NEVER, deviateTime = NEVER,
        -- PORT FIX: Setup used NEVER, but the timer can only arm while < 0.
        -- Start disarmed so the existing ten-minute leave/return mechanic works
        -- even if the player never enters an ODF named cvtnkb before leaving.
        -- The source's ODF test, duration and failure delay remain unchanged.
        tankTimeout = -1,
        -- Native zero handles/messages are nil in Lua. Retained fields:
        -- user, lastUser, fakeUser, portal, cvtnk1..5, beacon1..3;
        -- winSound, sound1, sound2, sound3, sound5, sound7.
    }
end
local M = NewState()
-- CR co-op runtime >>
-- Offline and co-op share this adapter (Scripts/CRCCARuntime.lua); the faithful tests set CR_TEST_FAITHFUL.
-- Lexical wrappers affect this mission only. Docs/BDMISN09_COOP.md lists every wrapped call and restoration.
-- Each RESTORED_* flag switches one cut-content restoration off (Docs/BDMISN09_COOP.md, "Restored content").
local RESTORED_COMPLETED_OBJECTIVE = true
local Restored
-- The map's enemy is team 2 in the DLL; the co-op map and the runtime move it to team 5.
local ENEMY_TEAM = 5
-- Every Chinese combat craft the mission builds is a concealed, head-count-scaled ticket. The Black Dog nav
-- beacons (apcamr, team 1) are built directly.
local SCALED_ODFS = { cvfigh = true, cvltnk = true, cvhtnk = true, cvrckt = true, cvtnk = true }
if not CR_TEST_FAITHFUL then require("RequireFix").Initialize({"campaignReimagined", "3686673790"}) end -- the asset searcher cuts module names to 11 chars
local campaignRuntime = not CR_TEST_FAITHFUL and require("CRCCARuntime").Create(function() return M end, {
    id = "bd09cr", leaderTeam = 1, enemyTeam = ENEMY_TEAM, mapEnemyTeam = 2,
    rallyPoints = { [0] = "cvtnk1" }, -- no base in this mission: respawn with the convoy
    scaledOdfs = SCALED_ODFS,
    -- A unit whose entry has a human within 460 m comes from the next hidden approach instead (east and south first).
    fallbackEntries = { "spawn_deviate5", "spawn_deviate6", "spawn_deviate2", "spawn_deviate3", "spawn_deviate4",
        "spawn_deviate1" },
    liveCap = 16, -- the eleven-unit ambush plus its extras, with the final five
    scrapPerGuest = 0, -- the mission starts with no scrap on purpose (SetScrap(1, 0)): no bonus per guest
    failDes = "bd09lose.des",
    wonFlags = { "won" },
    endedFlags = { "lost", "won" },
    -- ActivatePortal is a local effect of the object: every peer opens its own copy of the map's portal.
    presentationOps = { PortalOpen = function()
        local portal = GetHandle("portal")
        if portal ~= nil and portal ~= 0 and IsValid(portal) then ActivatePortal(portal) end
    end },
    weather = { module = "CRElysiumWeather", sites = "CRElysiumSitesBD09", startLevel = 1, targetLevel = 1,
        beats = function(elysium, state, s)
            local beats = s.elysiumBeats
            if beats == nil then beats = {}; s.elysiumBeats = beats end
            -- The tank is stolen and the convoy rolls: a haze closes in.
            if (not beats.haze) and state.objective1Complete then
                beats.haze = true
                elysium.SetTargetLevel(2)
            end
            -- The first beacon is reached: the sky darkens.
            if (not beats.rising) and state.gotoBeacon2 then
                beats.rising = true
                elysium.SetTargetLevel(3)
            end
            -- "That's not the path we were expecting": the storm builds over the road to the portal.
            if (not beats.storm) and state.gotoBeacon3 then
                beats.storm = true
                elysium.SetTargetLevel(4)
            end
            -- The cover is blown: a violent burst, and a strike where the ambush springs.
            if (not beats.blown) and state.deviateSpawned then
                beats.blown = true
                elysium.SetTargetLevel(4)
                elysium.ForceLevel(5, 100.0, 12.0)
                local ok, where = pcall(GetPosition, "spawn_deviate1")
                if ok and type(where) == "table" then
                    elysium.TriggerStrike({ x = where.x, y = where.y, z = where.z })
                end
            end
            -- The last five tanks at the portal: the worst of the weather.
            if (not beats.stand) and state.trigger1 then
                beats.stand = true
                elysium.SetTargetLevel(5)
            end
            -- Through the portal: the sky eases for the debrief.
            if (not beats.easing) and state.won then
                beats.easing = true
                elysium.SetTargetLevel(2)
            end
        end },
    hooks = {
        built = function(_, h, request, id) if Restored then Restored.Built(h, request, id) end end,
        -- The runtime's Load resets the presentation: Restored.Run publishes the objectives and markers again.
        load = function() if Restored then Restored.OnLoad() end end,
    },
})
local NativeIsOdf, NativeSetPerceivedTeam, NativeIsTouching = IsOdf, SetPerceivedTeam, IsTouching
local NativeAudioDone = IsAudioMessageDone
local IsValid, GetDistance, GetPlayerHandle, IsOdf = IsValid, GetDistance, GetPlayerHandle, IsOdf
local SetPerceivedTeam, IsTouching, ActivatePortal = SetPerceivedTeam, IsTouching, ActivatePortal
local Goto, Attack, BuildObject, SetScrap, SetPilot = Goto, Attack, BuildObject, SetScrap, SetPilot
local AudioMessage, IsAudioMessageDone = AudioMessage, IsAudioMessageDone
local ClearObjectives, AddObjective, SetObjectiveOn, SetObjectiveOff = ClearObjectives, AddObjective, SetObjectiveOn, SetObjectiveOff
local SucceedMission, FailMission = SucceedMission, FailMission
local function CRState()
    local s = campaignRuntime.State()
    s.r = s.r or {}
    return s.r
end
if campaignRuntime then
    local runtime = campaignRuntime
    local PLAYERS = runtime.PLAYERS
    local runtimeIsAlive = runtime.IsAlive
    local function PendingTicket(h)
        return type(h) == "number" and h < 0
    end
    -- The body's "player" (M.user) is the runtime's token for the humans. Each use below gives it the meaning that
    -- keeps a disguise mission fair for several humans (Docs/BDMISN09_COOP.md, "Humans as the player").
    local function ForEachHuman(fn)
        runtime.Coop.ForEachPlayerHandle(function(human, id)
            if runtimeIsAlive(human) then fn(human, id) end
        end)
    end
    local function IsHumanShip(h)
        local found = false
        runtime.Coop.ForEachPlayerHandle(function(human) if human == h then found = true end end)
        return found
    end
    IsValid = function(h)
        -- The token is valid while any human lives. A negative number is a spawn ticket (or one the runtime
        -- dropped): never ask the engine about it.
        if h == PLAYERS then
            local any = false
            ForEachHuman(function() any = true end)
            return any
        end
        if PendingTicket(h) then return runtime.State().arrivals[-h] ~= nil end
        return runtime.IsValid(h)
    end
    -- The nearest human to the point or object (the body's approach triggers).
    GetDistance = runtime.WrapDistance(runtime.GetDistance)
    -- Capture: "M.user == cvtnk1" needs a real handle. While the first tank is still unclaimed, the human sitting
    -- in it is the player; at every other time (and for every other test) the player is the token.
    GetPlayerHandle = function()
        if not M.objective1Complete and M.sound2Played and M.cvtnk1 ~= nil and M.cvtnk1 ~= 0 then
            local seated
            runtime.Coop.ForEachPlayerHandle(function(human) if human == M.cvtnk1 then seated = human end end)
            if seated ~= nil then return seated end
        end
        return PLAYERS
    end
    -- IsOdf(player, odf): the stolen APC is the disguise, so it holds only while EVERY living human is in one
    -- (the exposure test is the exact complement of the briefing test); any other craft, such as the tracked
    -- tank, is "the party has one" (the ten-minute departure timer). A missing remote handle never exposes.
    local ALL_HUMANS = { cvapc = true }
    IsOdf = function(h, odf)
        if h ~= PLAYERS then return NativeIsOdf(h, odf) end
        local count, matching = 0, 0
        ForEachHuman(function(human)
            count = count + 1
            if NativeIsOdf(human, odf) then matching = matching + 1 end
        end)
        if ALL_HUMANS[odf] then
            if runtime.Coop.IsNetworkGame() and not runtime.Coop.HasAllPlayerHandles() then return true end
            return count > 0 and matching == count
        end
        return matching > 0
    end
    -- The disguise and the reveal reach every human. The DLL's enemy team 2 is team 5 here; a reveal (team 1)
    -- puts each human back on their own team and ends the disguise for good (the body never restores it).
    SetPerceivedTeam = function(h, team)
        if team == 2 then team = ENEMY_TEAM end
        if h ~= PLAYERS then return NativeSetPerceivedTeam(h, team) end
        if team == 1 then CRState().revealed = true end
        ForEachHuman(function(human)
            NativeSetPerceivedTeam(human, team == 1 and GetTeamNum(human) or team)
        end)
    end
    -- Orders at "the player" go to the human nearest the unit; a ticket remembers the order and is ordered the
    -- moment it is built (the runtime drops one whose target is the token). A tank a human is driving is never
    -- ordered.
    local function NearestHuman(unit)
        local best, bestDistance
        ForEachHuman(function(human)
            local d = runtime.GetDistance(unit, human)
            if bestDistance == nil or d < bestDistance then best, bestDistance = human, d end
        end)
        return best
    end
    function runtime.NearestHumanTo(unit) return NearestHuman(unit) end
    local function OrderAtPlayer(op)
        local base = runtime[op]
        return function(h, target, ...)
            if IsHumanShip(h) then return end
            if target ~= PLAYERS then return base(h, target, ...) end
            if PendingTicket(h) then
                local r = CRState()
                r.orders = r.orders or {}
                r.orders[tostring(-h)] = op
                return
            end
            if runtimeIsAlive(h) then
                local human = NearestHuman(h)
                if human ~= nil then return base(h, human) end
            end
        end
    end
    Goto, Attack = OrderAtPlayer("Goto"), OrderAtPlayer("Attack")
    -- Stock bug: a line the engine cannot start has no handle, and the body's gates only advance on a handle that
    -- reports done. A missing line is a finished line.
    AudioMessage = function(file)
        local handle = runtime.AudioMessage(file)
        if handle == nil then return 0 end
        return handle
    end
    IsAudioMessageDone = function(message)
        if message == nil or message == 0 then return true end
        return NativeAudioDone(message)
    end
    -- The objective list is remembered so a load can publish it again (Restored.Resume), and the cut green first
    -- line is restored in front of the second objective.
    ClearObjectives = function()
        CRState().objectives = {}
        return runtime.ClearObjectives()
    end
    AddObjective = function(text, color)
        local r = CRState()
        r.objectives = r.objectives or {}
        local list = r.objectives
        if RESTORED_COMPLETED_OBJECTIVE and text == "bd09002.otf" and color == "white" and #list == 0 then
            list[#list + 1] = { "bd09001.otf", "green" }
            runtime.AddObjective("bd09001.otf", "green")
        end
        list[#list + 1] = { text, color }
        return runtime.AddObjective(text, color)
    end
    SetObjectiveOn, SetObjectiveOff = runtime.SetObjectiveOn, runtime.SetObjectiveOff
    SetScrap = runtime.SetScrap
    SucceedMission, FailMission = runtime.SucceedMission, runtime.FailMission
    -- Pilots are the lives CRCoop owns in a network game; offline the body keeps its own bookkeeping.
    local nativeSetPilot = SetPilot
    SetPilot = function(team, count)
        if runtime.Coop.IsNetworkGame() and team >= 1 and team <= 4 then return end
        return nativeSetPilot(team, count)
    end
    -- The portal ends the mission for everyone only when EVERY living human has touched it (sticky per player, so
    -- a human who went through and died or was respawned still counts). Contact is read here, every frame the body
    -- asks; a human with no ship is not waited for.
    IsTouching = function(a, b)
        if a ~= PLAYERS then return NativeIsTouching(a, b) end
        local r = CRState()
        r.through = r.through or {}
        ForEachHuman(function(human, id)
            if NativeIsTouching(human, b) then r.through[tostring(id or "local")] = true end
        end)
        return runtime.Coop.AllPlayersSatisfy(function(_, id)
            return r.through[tostring(id or "local")] == true
        end)
    end
    ActivatePortal = function() return runtime.Present("PortalOpen") end
    -- One scaling event per frame: the first scaled unit of a scripted wave (the ambush, the last five) is
    -- mirrored by min(floor(humans / 2), 2) extras with its orders.
    local eventFrame
    BuildObject = function(odf, team, where)
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
local function Distance(a, b)
    -- PORT FIX: absent/deleted objects must not satisfy proximity checks.
    -- In particular beacon1/2/3 do not exist at mission startup. Infinity also
    -- treats destroyed convoy members as absent for the straying test.
    if not Valid(a) or (type(b) ~= "string" and not Valid(b)) then
        return math.huge
    end
    return GetDistance(a, b)
end
local function Odf(h, name)
    return Valid(h) and IsOdf(h, name)
end
local function Perceived(team)
    if Valid(M.user) then SetPerceivedTeam(M.user, team) end
end
local function AttackPlayer(h)
    -- Invalid/deleted units and failed builds cannot receive commands in Lua.
    if Valid(h) and Valid(M.user) then Attack(h, M.user) end
end
local function AnyTankNear(beacon)
    for i = 1, 5 do
        if Distance(beacon, M["cvtnk" .. i]) < 100 then return true end
    end
    return false
end

-- CR restored content >>
-- The co-op fixes that need state (Docs/BDMISN09_COOP.md lists each one and the cut block the restoration comes
-- from). Each is gated by a RESTORED_* flag where it restores content, and runs on the authority only.
Restored = {}
if campaignRuntime then
    local runtime = campaignRuntime
    -- the perceived team may not survive a save: forget who was disguised so Disguise re-applies it
    function Restored.OnLoad() local r = CRState(); r.afterLoad = true; r.disguised = nil end
    -- A ticket becoming a unit: an order aimed at the player is issued to the nearest human.
    function Restored.Built(h, request, id)
        local r = CRState()
        local op = r.orders and r.orders[tostring((request and request.primary) or id)]
        if op then
            local human = runtime.NearestHumanTo(h)
            if human ~= nil then runtime[op](h, human) end
        end
    end
    -- Every human's ship carries the disguise from the first frame (the map authors it only on the host's own
    -- APC), and so does any ship it becomes while the cover holds: the pilot, the stolen tank, a respawn.
    function Restored.Disguise(r)
        if r.revealed then return end
        r.disguised = r.disguised or {}
        runtime.Coop.ForEachPlayerHandle(function(human)
            local key = tostring(human)
            if not r.disguised[key] and runtime.IsAlive(human) then
                r.disguised[key] = true
                NativeSetPerceivedTeam(human, ENEMY_TEAM)
            end
        end)
    end
    -- A load resets the presentation (the runtime's Load), so the objective list and the two markers the body
    -- set once are published again from the remembered list and the saved state.
    function Restored.Resume()
        local ok, err = pcall(function()
            local saved = CRState().objectives
            if saved ~= nil then
                ClearObjectives()
                for _, entry in ipairs(saved) do AddObjective(entry[1], entry[2]) end
            end
            if M.startDone and not M.objective1Complete and Valid(M.cvtnk1) then SetObjectiveOn(M.cvtnk1) end
            if M.gotoBeacon3 and M.sound6Time == NEVER and Valid(M.portal) then SetObjectiveOn(M.portal) end
        end)
        if not ok then print("[bd09cr] resume failed: " .. tostring(err)) end
    end
    local failed
    function Restored.Run()
        local ok, err = pcall(function()
            local r = CRState()
            if r.afterLoad then r.afterLoad = nil; Restored.Resume() end
            Restored.Disguise(r)
        end)
        if not ok and not failed then
            failed = true
            print("[bd09cr] restored content failed: " .. tostring(err))
        end
    end
end
-- CR restored content <<
function Start()
    M = NewState()
-- CR co-op callback >>
    if campaignRuntime then
        campaignRuntime.Start()
        -- Stock hazard: the runtime rewrites every state value equal to a built ticket's negative id, and the body
        -- keeps its disarmed tank timer at -1. Tickets start at 2 so no ticket can ever equal it.
        local arrivals = campaignRuntime.State()
        arrivals.serial = math.max(arrivals.serial, 1)
    end
-- CR co-op callback <<
    -- units (native Setup)
    M.portal = GetHandle("portal")
    for i = 1, 5 do M["cvtnk" .. i] = GetHandle("cvtnk" .. i) end
end

function AddObject(h)
    -- Native AddObject(Handle) is empty.
end

function Update(dt)
-- CR co-op callback >>
    if campaignRuntime and not campaignRuntime.Update(dt) then return end
-- CR co-op callback <<
    M.lastUser = M.user
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    local now = GetTime()

    if not M.startDone then
        SetScrap(1, 0)
        SetPilot(1, 0)
        -- don't do this part after the first shot
        M.startDone = true
        M.sound1Time = now + 1
        ClearObjectives()
        AddObjective("bd09001.otf", "white")
        if Valid(M.cvtnk1) then SetObjectiveOn(M.cvtnk1) end
    end

    -- SOE #1
    if M.sound1Time < now then
        M.sound1Time = NEVER
        M.sound1 = AudioMessage("bd09001.wav")
    end
    if M.sound1 ~= nil and IsAudioMessageDone(M.sound1) then
        M.sound1 = nil
        M.sound2Time = now + 15
    end

    -- SOE #2
    if M.sound2Time < now then
        M.sound2Time = NEVER
        if Odf(M.user, "cvapc") then
            M.sound2Played = true
            M.oneOfTheEnemy = true
            M.sound2 = AudioMessage("bd09002.wav")
        end
    end
    if not M.sound2Played and Valid(M.user) and not Odf(M.user, "cvapc") then
        M.oneOfTheEnemy = false
        Perceived(1)
        -- get the guys to attack
        for i = 2, 5 do AttackPlayer(M["cvtnk" .. i]) end
        -- PORT FIX: assigning now+1 every frame prevented SOE #10 from ever
        -- firing while exposed. Arm once; detection, units and one-second
        -- response delay are unchanged, and no repeat ambush is introduced.
        if M.deviateTime == NEVER and not M.deviateSpawned then
            M.deviateTime = now + 1
        end
    end
    if M.sound2 ~= nil and IsAudioMessageDone(M.sound2) then
        M.sound2 = nil
        -- C++ cut content: SetPerceivedTeam(user, 2);
        -- SetPerceivedTeam(M.user, 2)
    end
    if M.oneOfTheEnemy then Perceived(2) end

    -- SOE #3
    if M.objective1Complete and Valid(M.user) and not M.strayed then
        -- check distance to each of the other cvtnks
        if Distance(M.user, M.cvtnk2) > 75 and
           Distance(M.user, M.cvtnk3) > 75 and
           Distance(M.user, M.cvtnk4) > 75 and
           Distance(M.user, M.cvtnk5) > 75 then
            Perceived(1)
            M.strayed = true
            -- cut to SOE #10
            M.deviateTime = now + 2
        end
    end

    -- SOE #4
    if not M.objective1Complete and Valid(M.user) and
       M.user == M.cvtnk1 and M.sound2Played then
        M.oneOfTheEnemy = false
        M.objective1Complete = true
        SetObjectiveOff(M.cvtnk1)
        M.sound3Time = now + 5
        M.beacon1 = BuildObject("apcamr", 1, "spawn_beacon1")
    end
    if M.sound3Time < now and not M.deviateSpawned then
        M.sound3Time = NEVER
        M.sound3 = AudioMessage("bd09003.wav")
    end
    if M.sound3 ~= nil and IsAudioMessageDone(M.sound3) then
        M.sound3 = nil
        ClearObjectives()
        -- C++ cut content: AddObjective("bd09001.otf", GREEN);
        -- AddObjective("bd09001.otf", "green")
        AddObjective("bd09002.otf", "white")
        M.orderGotoTime1 = now + 1
    end

    -- SOE #5
    if M.orderGotoTime1 < now then
        M.orderGotoTime1 = NEVER
        for i = 2, 5 do
            local h = M["cvtnk" .. i]
            if Valid(h) and IsAlive(h) then Goto(h, "tank_path", 1) end
        end
    end

    -- SOE #6
    if not M.tankArrived1 and AnyTankNear(M.beacon1) then
        M.tankArrived1 = true
        -- spawn the next beacon
        M.beacon2 = BuildObject("apcamr", 1, "spawn_beacon2")
    end
    if M.objective1Complete and not M.gotoBeacon2 and not M.deviateSpawned then
        -- has the player arrived?
        if Distance(M.user, M.beacon1) < 100 then
            M.gotoBeacon2 = true
            AudioMessage("bd09004.wav")
        end
    end

    -- SOE #7
    if not M.tankArrived2 and AnyTankNear(M.beacon2) then
        M.tankArrived2 = true
        -- spawn the next beacon
        M.beacon3 = BuildObject("apcamr", 1, "spawn_beacon3")
    end
    if M.objective1Complete and not M.gotoBeacon3 and not M.deviateSpawned then
        -- has the player arrived?
        if Distance(M.user, M.beacon2) < 100 then
            M.gotoBeacon3 = true
            AudioMessage("bd09005.wav")
            M.sound6Time = now + 5
        end
    end

    -- #SOE #8
    if M.sound6Time < now then
        M.sound6Time = NEVER
        AudioMessage("bd09006.wav")
        if Valid(M.portal) then SetObjectiveOn(M.portal) end
    end
    if not M.objective2Complete then
        if M.gotoBeacon2 and M.gotoBeacon3 and Distance(M.user, M.beacon3) < 100 then
            M.objective2Complete = true
            ClearObjectives()
            AddObjective("bd09001.otf", "green")
            AddObjective("bd09002.otf", "green")
            AddObjective("bd09003.otf", "white")
        end
    end

    -- SOE #10
    if M.deviateTime < now and not M.deviateSpawned then
        Perceived(1)
        M.deviateTime = NEVER
        M.deviateSpawned = true
        local wave = {
            {"cvfigh", "spawn_deviate1"}, {"cvfigh", "spawn_deviate1"},
            {"cvltnk", "spawn_deviate2"}, {"cvltnk", "spawn_deviate2"},
            {"cvhtnk", "spawn_deviate3"},
            {"cvrckt", "spawn_deviate4"}, {"cvrckt", "spawn_deviate4"},
            {"cvfigh", "spawn_deviate5"}, {"cvfigh", "spawn_deviate5"},
            {"cvtnk", "spawn_deviate6"}, {"cvtnk", "spawn_deviate6"},
        }
        for _, unit in ipairs(wave) do AttackPlayer(BuildObject(unit[1], 2, unit[2])) end
        AudioMessage("bd09007.wav")
        -- Native GameObject::objectList traversal; AllObjects is stock Lua.
        for h in AllObjects() do
            if Odf(h, "cvturrc") then AttackPlayer(h) end
        end
    end

    if M.objective1Complete and Valid(M.user) and not Odf(M.user, "cvtnkb") and M.tankTimeout < 0 then
        M.tankTimeout = now + 10 * 60
    end
    if M.tankTimeout > 0 and Odf(M.user, "cvtnkb") then
        -- player is back into a cvtnk
        M.tankTimeout = -1
    end
    if M.tankTimeout > 0 and M.tankTimeout < now and not M.won and not M.lost then
        -- the player has been out of the tank for too long
        M.tankTimeout = -1
        -- PORT FIX: source omitted lost here, allowing portal touch/destruction
        -- to replace this failure during its one-second delay. Latch the same
        -- failure as other endings; timeout length and failure time stay intact.
        M.lost = true
        FailMission(now + 1, "bd09lose.des")
    end

    -- SOE #11
    if Distance(M.user, "trigger_1") < 200 and not M.trigger1 then
        M.trigger1 = true
        for i = 0, 4 do AttackPlayer(BuildObject("cvtnk", 2, "last_one")) end
    end

    -- SOE #12
    if Distance(M.user, M.portal) < 250 and not M.portalActive then
        M.portalActive = true
        -- Native activatePortal(portal, true) maps to the stock Lua API.
        ActivatePortal(M.portal)
        M.winSound = AudioMessage("bd09008.wav")
    end
    -- Native isTouching maps to stock Redux IsTouching (case is significant).
    -- Keep immediate victory: no objective-completion/audio gate is added.
    if Valid(M.user) and Valid(M.portal) and IsTouching(M.user, M.portal) and not M.won and not M.lost then
        M.won = true
        SucceedMission(now, "bd09win.des")
    end
    -- lost the portal? Native GetHealth also fails for a destroyed portal.
    if (not Valid(M.portal) or GetHealth(M.portal) <= 0) and not M.lost and not M.won then
        M.lost = true
        FailMission(now + 1, "bd09lseb.des")
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
    -- LuaMission restores table/handle/message values; do not replay Setup.
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
