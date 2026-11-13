-- Run from repository root: lua5.1 Tools/MissionTests/Test-EvolveCoop.lua
-- Single Lua 5.1 process acting as the authority (or, for the "host-only body" check, a guest), driving
-- Scripts/evolvecr.lua over the REAL Scripts/CRCCARuntime.lua and Scripts/CRCoop.lua (require()d normally;
-- only the native engine and the "exu" EXU module are mocked). Remote humans are registered through CRCoop's
-- own wire API (CreatePlayer + Receive("H",...)/Receive("Q",...)) rather than a second sandboxed peer
-- environment: the E/A/C presentation wire protocol itself is already covered by Test-CRCoop.lua and by every
-- other CRCCARuntime mission's own peer fixture; this file only has to prove evolvecr's OWN decisions
-- (scaling, nearest-human targeting, the invehicle latch, the shared ending) are wired correctly.
assert(_VERSION == "Lua 5.1")
package.path = "Scripts/?.lua;" .. package.path

local assertions = 0
local function check(v, msg) assertions = assertions + 1; assert(v, msg) end

local clock, objects, nextHandle, calls, timerStart, labels, netGame, hosting, netId

local function reset()
    clock, objects, nextHandle, calls, timerStart, labels = 0, {}, 0, {}, 0, {}
    netGame, hosting, netId = false, true, 1
    objects.player = {alive = true, odf = "asuser", team = 1, pos = {x = 0, y = 0, z = 0}}
    GetTime = function() return clock end
    GetPlayerHandle = function() return "player" end
    IsValid = function(h) return objects[h] ~= nil and not objects[h].removed end
    IsAlive = function(h) return IsValid(h) and objects[h].alive end
    GetOdf = function(h) assert(IsValid(h)); return objects[h].odf end
    GetDistance = function(a, b)
        local oa, ob = objects[a], objects[b]
        if not (oa and ob) then return 1e9 end
        local dx, dy, dz = oa.pos.x - ob.pos.x, oa.pos.y - ob.pos.y, oa.pos.z - ob.pos.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    GetTeamNum = function(h) return objects[h] and objects[h].team end
    GetHandle = function(label) return labels[label] end
    SetLabel = function(h, label) labels[label] = h end
    GetLabel = function(h) for label, v in pairs(labels) do if v == h then return label end end; return "" end
    BuildObject = function(odf, team, where)
        nextHandle = nextHandle + 1
        local h = nextHandle
        objects[h] = {alive = true, odf = odf, team = team, where = where, pos = {x = nextHandle, y = 0, z = 0}}
        calls[#calls + 1] = {"BuildObject", odf, team, where, h}
        return h
    end
    Attack = function(h, target)
        assert(IsValid(h) and IsValid(target), "Attack on an invalid handle")
        calls[#calls + 1] = {"Attack", h, target}
    end
    RemoveObject = function(h) assert(IsValid(h)); objects[h].removed = true end
    AllObjects = function()
        local hs = {}
        for h in pairs(objects) do if IsValid(h) then hs[#hs + 1] = h end end
        local i = 0
        return function() i = i + 1; return hs[i] end
    end
    StartCockpitTimerUp = function(t) timerStart = clock - t end
    GetCockpitTimer = function() return math.floor(clock - timerStart) end
    IsNetGame = function() return netGame end
    IsHosting = function() return hosting end
    Send = function(...) calls[#calls + 1] = {"Send", ...} end
    DisplayMessage = function(...) end
    Ally = function(...) end
    UnAlly = function(...) end
    SetAIControl = function(...) end
    UseItem = function() return nil end -- no bundled durations.csv/subtitle .txt in this harness
    -- CRCoopRespawn's own placement/ground-sampling plumbing; this harness never actually exercises a
    -- respawn (the "game continues"/"single ending" checks drive CRCoop.ReportOutOfLives directly).
    SetVector = function(x, y, z) return {x = x, y = y, z = z} end
    GetPosition = function(h) return objects[h] and objects[h].pos or {x = 0, y = 0, z = 0} end
    SetPosition = function(h, pos) if objects[h] then objects[h].pos = pos end end
    SetVelocity = function(...) end
    GetTerrainHeightAndNormal = function(pos) return pos.y end
    for _, name in ipairs({"SetScrap", "SetMaxScrap", "SetPilot", "ClearObjectives", "AddObjective",
                           "SucceedMission", "FailMission"}) do
        local fn = name
        _G[fn] = function(...) calls[#calls + 1] = {fn, ...} end
    end
    -- Stub the heavy HUD/audio/weather/file-I/O modules outright (same stubs as every other CRCCARuntime
    -- mission's own peer fixture, e.g. Tools/MissionTests/Misns1Fixture.lua): this harness verifies evolvecr's own
    -- decisions, not PersistentConfig's HUD rendering or ScriptSubtitles' durations.csv parsing.
    package.loaded.exu = { GetMyNetID = function() return netId end, DisableStartingRecycler = function() end }
    package.loaded.RequireFix = { Initialize = function() end }
    package.loaded.ScriptSubtitles = { Play = function() end, Queue = function() end, Stop = function() end,
        Update = function() end, Initialize = function() end }
    package.loaded.Environment = { Init = function() end, BindWeatherSensors = function() end,
        Update = function() end, OnObjectCreated = function() end, InvalidateRenderer = function() end }
    package.loaded.PersistentConfig = { Initialize = function() end, UpdateInputs = function() end,
        UpdateHeadlights = function() end }
    for _, name in ipairs({"CRCCARuntime", "CRCoop", "CRCoopComms", "CRCoopRespawn", "CRCoopDiagnostics",
                           "CRWire"}) do
        package.loaded[name] = nil
    end
    dofile("Scripts/evolvecr.lua")
end

local function count(name)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
    return n
end
local function last(name)
    for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end
local function builds()
    local b = {}
    for _, c in ipairs(calls) do if c[1] == "BuildObject" then b[#b + 1] = c end end
    return b
end
local function step(t) clock = t; Update(0.1) end

-- Joins a human on its own team (team == id, the engine's 2-4 guest slots) at id/craft handle/position, acks the
-- leader-side handshake (CreatePlayer + the "H"/"Q" wire messages CRCoop itself expects) so IsSessionReady()
-- admits them without needing a second sandboxed peer.
local function joinHuman(id, x, z)
    local h = "human" .. id
    objects[h] = {alive = true, odf = "asuser", team = id, pos = {x = x, y = 0, z = z}}
    CreatePlayer(id, "P" .. id, id)
    Receive(id, "H", h)
    Receive(id, "Q", h, id, 1)
    return h
end
local function startNetwork(humanCount)
    netGame, hosting, netId = true, true, 1
    Start()
    for id = 2, humanCount do joinHuman(id, 1000 * id, 0) end
    step(0)
end

-- 1-4 humans: the first pilot wave (round 0, native maxroundattackers == 1) scales to
-- min(20, ceil(1 * (1 + 0.5*(humans-1)))) per spawn point (3 spawn points: pilot_1/2/3).
reset()
for humans, expectPerPoint in pairs({[1] = 1, [2] = 2, [3] = 2, [4] = 3}) do
    reset()
    startNetwork(humans)
    local perPoint = {}
    for _, b in ipairs(builds()) do perPoint[b[4]] = (perPoint[b[4]] or 0) + 1 end
    check(perPoint.pilot_1 == expectPerPoint, humans .. " humans: pilot_1 got " .. tostring(perPoint.pilot_1)
        .. ", expected " .. expectPerPoint)
    check(perPoint.pilot_2 == expectPerPoint and perPoint.pilot_3 == expectPerPoint,
        "every spawn point in the round scales the same way")
    check(Save().numOfCurrentAttackers == expectPerPoint * 3, "extras are tracked in the wave-clear bookkeeping")
    for _, b in ipairs(builds()) do
        check(b[3] == 5, "attackers spawn on the co-op enemy team 5, got " .. tostring(b[3]))
    end
end

-- The score HUD (team 1 scrap) is mirrored onto every human team, so each guest's own HUD shows it.
reset(); startNetwork(4)
local scrapTeams = {}
for _, c in ipairs(calls) do if c[1] == "SetScrap" then scrapTeams[c[2]] = c[3] end end
for t = 1, 4 do check(scrapTeams[t] == 0, "team " .. t .. " gets the score, got " .. tostring(scrapTeams[t])) end

-- Cover items and pickups are never scaled, even with four humans (pickups appear strictly after time 1,
-- same native threshold Tools/MissionTests/Test-Evolve.lua checks).
reset(); startNetwork(4)
step(1.01)
check(count("BuildObject") == 3 * 3 + 12, "3 spawn points * 3 scaled pilots + 12 unscaled pickups, got "
    .. count("BuildObject"))

-- Nearest-human targeting: AttackPlayer(h) resolves the PLAYERS token to whichever human is nearest. The
-- host ("player") sits at the default (0,0,0); join the second human much closer to the attacker spawns
-- (pos {attackerHandle, 0, 0}) than the host is, before the opening wave is built.
reset()
netGame, hosting, netId = true, true, 1
Start()
objects.player.pos = {x = 5000, y = 0, z = 5000} -- the host is far from the attacker spawns
joinHuman(2, 1, 0) -- the guest is near every attacker (pos {handle,0,0})
step(0)
local nearAttack = last("Attack")
check(nearAttack ~= nil, "the opening wave attacks somebody")
check(nearAttack[3] == "human2", "retarget chose the nearest human, not an arbitrary one")

-- Any-human vehicle latch: a non-local human's handle changing (not the local/host's) still trips invehicle
-- and retargets every current attacker and unlocked cover item.
reset(); startNetwork(2)
check(not Save().invehicle, "latch starts clear")
local before = count("Attack")
objects.human2b = {alive = true, odf = "avtank", team = 2, pos = {x = 1, y = 0, z = 0}}
Receive(2, "H", "human2b")
step(0.1)
check(Save().invehicle, "a GUEST's handle change latches invehicle, same as the native single-player change")
check(count("Attack") > before, "the handle change retargets every current attacker")

-- Game continues while at least one human still has lives: an ordinary craft death (not an out-of-lives
-- report) must not end the run, matching "not on the first death".
reset(); startNetwork(2)
objects.human2.alive = false
step(0.2); step(0.3)
check(count("SucceedMission") == 0, "a single human's death does not end a shared-lives run")

-- Single ending dispatch when every human is out of lives: the run always SucceedMission-s (never
-- FailMission) with a score-chosen debrief, exactly once, through the body's own FinishRun. One connected
-- human keeps this to the 3.5 s result-publish timer (CRCCARuntime.EndMission): with nobody else to
-- acknowledge the preceding events, the "game continues while someone still has lives" case above already
-- covers a guest's own un-acknowledged events never blocking play.
reset(); startNetwork(1)
local CRCoop = require("CRCoop")
CRCoop.ReportOutOfLives()
step(1); step(4); step(4.1)
check(count("SucceedMission") == 1, "exactly one ending, got " .. count("SucceedMission"))
check(count("FailMission") == 0, "evolve never FailMission-s: the debrief choice is the score comparison")
check(last("SucceedMission")[3] == "sammylse.des", "a fresh baseline score (0) never beats itself")
step(5); check(count("SucceedMission") == 1, "no repeated ending")

-- Save/load round-trips the body's own state and the per-human handle tracking (a save/load does not
-- spuriously relatch invehicle for a human whose handle has not actually changed).
reset(); startNetwork(3)
local saved = Save()
check(saved.score ~= nil and saved.round ~= nil and saved.maxroundattackers ~= nil, "body fields are present")
dofile("Scripts/evolvecr.lua")
Load(saved)
check(Save().round == saved.round and Save().maxroundattackers == saved.maxroundattackers, "state round-trips")
local beforeReload = count("Attack")
joinHuman(2, 1000 * 2, 0); joinHuman(3, 1000 * 3, 0)
step(0.1)
check(count("Attack") == beforeReload, "no spurious relatch for unchanged human handles after a load")

-- Offline (solo) there is no CRCoop life pool: the token resolves to the local player, so the body's own
-- 2 s death grace still ends the run exactly once, as stock.
reset(); Start(); step(0); step(0.5)
check(count("SucceedMission") == 0, "a living solo player keeps playing")
objects.player.alive = false
step(1); step(3.1); step(3.2)
check(count("SucceedMission") == 1, "a solo death ends the run once, got " .. count("SucceedMission"))
step(5); check(count("SucceedMission") == 1, "no repeated solo ending")

-- Host-only body: a non-authority peer (not hosting) never mutates gameplay, even with humans connected.
reset()
netGame, hosting, netId = true, false, 2
Start()
CreatePlayer(1, "Host", 1); Receive(1, "H", "player"); Receive(1, "Q", "player", 1, 1)
step(0.1); step(0.2)
check(#calls == 0 or (count("BuildObject") == 0 and count("SetScrap") == 0 and count("SucceedMission") == 0),
    "a guest's Update never calls a gameplay native")

print("evolvecr co-op: " .. assertions .. " assertions passed")
