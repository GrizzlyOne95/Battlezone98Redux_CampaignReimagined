-- PilotSim: a tiny world for simulating the win path of the N64 Pilot Mode branches.
--
-- The per-mission Test-*PilotMode.lua tests assert that orders are given. PilotSim runs the
-- mission's real pilot block against a small world (units that move, producers that build,
-- scavengers that earn scrap) so a scenario can assert that the orders actually get the job
-- done, e.g. that the convoy reaches the last nav or the tug becomes affordable. Run from the
-- repo root with Lua 5.1; the mission script and Missions/<mission>.bzn are read from disk.
--
-- Writing a scenario (see Test-Misns2PilotSim.lua):
--   local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
--   local sim = PilotSim.new{
--       name = "misn09", script = "Scripts/misn09cr.lua",            -- env PILOTSIM_SCRIPT overrides script
--       pattern = "(local function PilotState%(%).-)\n%-%- CR pilot mode <<",  -- captures the pilot block
--       exports = "update = PilotUpdate, add = PilotAddObject",      -- locals the block should return
--       bzn = "Missions/misn09cr.bzn",                               -- initial objects and paths
--       scrap = 20, pilots = 7, maxScrap = 100 }                     -- team-1 mission values
--   sim.M.start_done = true                                         -- mission flags the block reads
--   sim:hook(function(h) return sim.api.add(h) end)                  -- the engine's AddObject call
--   local fact = sim:get("avmuf")                                   -- BZN object by label
--   sim:add("obdata", 0, x, z)                                      -- an object the mission spawns later
--   sim:stallOnce(unit, function(s, u) return u.cmd == 3 end)        -- the unit drops its order once
--   sim:each(function(s) ... end)                                   -- per-tick scenario code (the player)
--   sim:when(function(s) return cond end, function(s) ... end)       -- one-shot event
--   sim:runUntil(function(s) return goal end, 300, "what we wait for")  -- errors with a state dump if late
--   sim:expect(cond, "message")                                      -- assertion
--
-- World constants (rough, documented on purpose):
--   tick 0.25 s; speed: hover 25 m/s, tracked/wheeled 15, walker 12, base producers 10
--   (recycler/factory/constructor/armory); arrival radius 10 m for Goto/Dropoff/Pickup,
--   Follow holds 30 m, Attack closes to 60 m; no terrain or pathfinding (only the stall
--   injector blocks units); Goto along a path name walks its points in order.
--   Goto onto a geyser deploys a recycler/factory/armory/constructor on arrival; a Goto order
--   to a deployed producer undeploys it at once and it drives off.
--   Scrap is per team, capped at maxScrap; each scavenger in SCAVENGE earns 0.15 scrap/s (Follow
--   and idle units earn nothing; a scavenger the sim builds starts in SCAVENGE like the engine's).
--   Build/BuildAt charge ODF scrapCost when ordered and refuse (counted in sim.refused) when
--   unaffordable; the unit appears after ODF buildTime (5 s if absent) and goes through the hook.
--   Vehicles (second letter v) cost one pilot when built. RECYCLE removes the unit after 3 s
--   with no refund (conservative).
local PilotSim = {}
PilotSim.__index = PilotSim

local CMD = { NONE = 0, SELECT = 1, STOP = 2, GO = 3, ATTACK = 4, FOLLOW = 5, FORMATION = 6, PICKUP = 7,
    DROPOFF = 8, NO_DROPOFF = 9, GET_REPAIR = 10, GET_RELOAD = 11, GET_WEAPON = 12, GET_CAMERA = 13,
    GET_BOMB = 14, DEFEND = 15, GO_TO_GEYSER = 16, RESCUE = 17, RECYCLE = 18, SCAVENGE = 19, HUNT = 20 }
PilotSim.AiCommand = CMD

local ARRIVE, FOLLOW_DIST, ATTACK_DIST = 10, 30, 60
local SCAV_RATE, RECYCLE_TIME, DEFAULT_BUILD = 0.15, 3, 5
PilotSim.constants = { arrive = ARRIVE, followDist = FOLLOW_DIST, attackDist = ATTACK_DIST,
    scavRate = SCAV_RATE, recycleTime = RECYCLE_TIME, hover = 25, tracked = 15, walker = 12, producer = 10 }

-- Natives the pilot blocks may call that need no model.
local HARMLESS = { SetObjectiveOff = true, AudioMessage = true, AddObjective = true, SetObjectiveName = true }

local function readFile(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a"); f:close()
    return (s:gsub("\r\n", "\n"))
end
PilotSim.readFile = readFile

-- ---------------------------------------------------------------- BZN reader
-- Line format: "key [n] =" then the value on the next line, or "key = value".
function PilotSim.parseBzn(path)
    local lines = {}
    for line in (readFile(path) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local objects, paths = {}, {}
    local cur, curPath
    local i = 1
    local function nextLine() i = i + 1; return lines[i] end
    while i <= #lines do
        local line = lines[i]
        if line == "[GameObject]" then
            cur = {}; objects[#objects + 1] = cur; curPath = nil
        elseif line == "[AiPath]" then
            cur = nil; curPath = { points = {} }
        elseif line:match("^%[") then
            cur, curPath = nil, nil
        elseif cur then
            if line:match("^PrjID") and not cur.odf then cur.odf = nextLine()
            elseif line:match("^team %[") and not cur.team then cur.team = tonumber(nextLine())
            elseif line:match("^isUser %[") and not cur.isUser then cur.isUser = tonumber(nextLine()) == 1
            elseif line:match("^label = ") and not cur.label then cur.label = line:match("^label = (.*)$")
            elseif line == "pos [1] =" and not cur.x then
                nextLine(); cur.x = tonumber(nextLine()); nextLine(); cur.y = tonumber(nextLine())
                nextLine(); cur.z = tonumber(nextLine())
            end
        elseif curPath then
            if line:match("^label = ") then
                curPath.label = line:match("^label = (.*)$")
                paths[curPath.label] = curPath.points
            elseif line:match("^  x %[") then
                local x = tonumber(nextLine()); nextLine()
                curPath.points[#curPath.points + 1] = { x, tonumber(nextLine()) }
            end
        end
        i = i + 1
    end
    return { objects = objects, paths = paths }
end

-- ---------------------------------------------------------------- ODF costs
local odfCache = {}
function PilotSim.odfCost(odf, table_)
    if odfCache[odf] then return odfCache[odf] end
    local cost
    local f = io.open("ODF/" .. odf .. ".odf", "rb")
    if f then
        local s = f:read("*a"); f:close()
        local sc = s:match("[Ss]crapCost%s*=%s*(%d+)")
        local bt = s:match("[Bb]uildTime%s*=%s*([%d%.]+)")
        if sc then cost = { scrap = tonumber(sc), time = tonumber(bt) or DEFAULT_BUILD } end
    end
    if not cost and table_ and table_[odf] then cost = table_[odf] end
    if not cost then error("PilotSim: no scrapCost for odf '" .. odf .. "' (no ODF/" .. odf .. ".odf and no scenario cost table entry)") end
    odfCache[odf] = cost
    return cost
end

-- ---------------------------------------------------------------- classes
local function speedOf(odf, override)
    if override and override[odf] then return override[odf] end
    if odf == "player" or odf:match("hover") or odf:match("^%a%vfigh") then return 25 end
    if odf:match("^%a%v") then
        if odf:match("rec") or odf:match("muf") or odf:match("cns") or odf:match("slf") or odf:match("fac")
            or odf:match("arm") then return 10 end
        if odf:match("walk") then return 12 end
        return 15
    end
    return 0 -- buildings, beacons, pods, mines, geysers do not move
end
local function isCraft(odf) return odf == "player" or odf:match("^%a%v") ~= nil end
local function isProducer(odf)
    return odf:match("^%a%v") ~= nil and (odf:match("rec") or odf:match("muf") or odf:match("cns") or odf:match("slf")
        or odf:match("fac") or odf:match("arm")) ~= nil
end

-- ---------------------------------------------------------------- world
function PilotSim.new(opts)
    local sim = setmetatable({}, PilotSim)
    sim.name = opts.name or "scenario"
    sim.dt, sim.t = opts.dt or 0.25, 0
    sim.objs, sim.order, sim.paths, sim.counter = {}, {}, {}, 0
    sim.scrap, sim.pilots, sim.maxScrap = { [1] = opts.scrap or 0 }, { [1] = opts.pilots or 0 }, opts.maxScrap or 100
    sim.costs, sim.speeds = opts.costs, opts.speeds
    sim.refused, sim.built, sim.log, sim.marked = 0, {}, {}, {}
    sim.income = 0
    sim.stalls, sim.events, sim.eachFns, sim.tracked = {}, {}, {}, {}
    sim.failed, sim.M = false, {}
    sim.refund = {}

    if opts.bzn then
        local bzn = PilotSim.parseBzn(opts.bzn)
        sim.paths = bzn.paths
        for _, o in ipairs(bzn.objects) do
            local h = sim:add(o.odf, o.team or 0, o.x, o.z, o.label)
            if o.isUser then sim.player = h end
        end
    end

    -- Load the script and extract the pilot block.
    local path = os.getenv("PILOTSIM_SCRIPT") or opts.script
    sim.scriptPath = path
    local source = readFile(path)
    if opts.transform then source = opts.transform(source) end
    local block = source:match(opts.pattern)
    assert(block, "PilotSim: pilot block pattern did not match " .. path)

    local env = setmetatable({}, { __index = function(_, k)
        local v = _G[k]
        if v ~= nil then return v end
        if type(k) == "string" and k:match("^%u") then
            if HARMLESS[k] then return function() end end
            return function() error("PilotSim: unmodelled native '" .. k .. "' called by the pilot block (add it to PilotSim)", 2) end
        end
    end })
    sim.env = env
    sim:installNatives(env)
    env.M = sim.M
    env.AiCommand = CMD
    env.PlayerPilotMode = { IsEnabled = function() return true end,
        Initialize = function(adapter) sim.adapter = adapter end }
    local libChunk = assert(loadfile("Scripts/CRPilotBranch.lua"))
    setfenv(libChunk, env)
    env.PilotBranch = libChunk()
    env.require = function(name)
        assert(name == "CRPilotBranch", "PilotSim: require('" .. tostring(name) .. "') is not modelled")
        return env.PilotBranch
    end
    local chunk = assert(loadstring("local M, PlayerPilotMode, PilotBranch = M, PlayerPilotMode, PilotBranch\n" .. block ..
        "\nreturn { " .. opts.exports .. " }"))
    setfenv(chunk, env)
    sim.api = chunk()
    sim.update = opts.update or function() sim.api.update() end
    return sim
end

-- Add an object; returns its handle (the BZN label when unique, else odf#n).
function PilotSim:add(odf, team, x, z, label)
    self.counter = self.counter + 1
    local h = (label and label ~= "" and not self.objs[label]) and label or (odf .. "#" .. self.counter)
    self.objs[h] = { h = h, odf = odf, team = team, x = x or 0, z = z or 0, alive = true, health = 1, ammo = 1,
        deployed = false, cmd = CMD.NONE, speed = speedOf(odf, self.speeds), craft = isCraft(odf) }
    self.order[#self.order + 1] = h
    return h
end

function PilotSim:get(label) assert(self.objs[label], "PilotSim: no object labelled " .. label); return label end
function PilotSim:unit(h) return assert(self.objs[h], "PilotSim: unknown handle " .. tostring(h)) end
function PilotSim:setPlayer(h) self.player = h end
function PilotSim:hook(fn) self.addHook = fn end
function PilotSim:track(name, h) self.tracked[#self.tracked + 1] = { name, h } end
function PilotSim:each(fn) self.eachFns[#self.eachFns + 1] = fn end
function PilotSim:when(cond, fn) self.events[#self.events + 1] = { cond, fn } end
function PilotSim:stallOnce(h, when) self.stalls[#self.stalls + 1] = { h = h, when = when } end
function PilotSim:say(msg) self.log[#self.log + 1] = string.format("[%7.2f] %s", self.t, msg); if #self.log > 400 then table.remove(self.log, 1) end end

-- Position of a handle, path name (first point) or vector; nil when dead or unknown.
function PilotSim:pos(ref)
    if type(ref) == "table" then return ref.x, ref.z end
    local o = self.objs[ref]
    if o then
        if not o.alive then return nil end
        return o.x, o.z
    end
    local p = self.paths[ref]
    if p then return p[1][1], p[1][2] end
    error("PilotSim: cannot resolve '" .. tostring(ref) .. "' to an object, path or vector")
end

function PilotSim:dist(a, b)
    local ax, az = self:pos(a)
    local bx, bz = self:pos(b)
    if not ax or not bx then return 1e9 end
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

local function setOrder(sim, h, cmd, target, label)
    local u = sim:unit(h)
    u.cmd, u.tgt, u.route, u.ri = cmd, target, nil, 1
    if cmd == CMD.GO and type(target) == "string" and not sim.objs[target] and sim.paths[target] then
        u.route, u.ri = sim.paths[target], 1
    end
    if cmd == CMD.GO and u.deployed then u.deployed = false end
    if cmd == CMD.RECYCLE then u.recycleAt = sim.t + RECYCLE_TIME end
    sim:say(string.format("%s %s -> %s", label, h, tostring(type(target) == "table" and ("(" .. target.x .. "," .. target.z .. ")") or target)))
end

function PilotSim:installNatives(env)
    local sim = self
    local function U(h) return sim:unit(h) end
    env.GetTime = function() return sim.t end
    env.GetPlayerHandle = function() return sim.player end
    env.GetHandle = function(label) local o = sim.objs[label]; if o and o.alive then return label end end
    env.IsAlive = function(h) local o = sim.objs[h]; return o ~= nil and o.alive end
    env.IsValid = env.IsAlive
    env.IsDeployed = function(h) return U(h).deployed end
    env.IsBusy = function(h) return U(h).build ~= nil end
    env.IsOdf = function(h, odf) return U(h).odf == odf end
    env.IsOdfBase = env.IsOdf
    env.GetTeamNum = function(h) return U(h).team end
    env.GetHealth = function(h) return U(h).health end
    env.GetAmmo = function(h) return U(h).ammo end
    env.GetScrap = function(team) return math.floor(sim.scrap[team or 1] or 0) end
    env.GetPilot = function(team) return sim.pilots[team or 1] or 0 end
    env.GetCurrentCommand = function(h) return U(h).cmd end
    env.GetCurrentWho = function(h) local u = U(h); return type(u.tgt) == "string" and u.tgt or nil end
    env.GetTug = function(h) return U(h).tug end
    env.GetDistance = function(a, b) return sim:dist(a, b) end
    env.GetPosition = function(h) local x, z = sim:pos(h); return { x = x, y = 0, z = z } end
    env.SetVector = function(x, y, z) return { x = x, y = y, z = z } end
    env.GetTerrainHeightAndNormal = function() return 0, { x = 0, y = 1, z = 0 } end
    env.AllCraft = function()
        local list, i = {}, 0
        for _, h in ipairs(sim.order) do local o = sim.objs[h]; if o.alive and o.craft then list[#list + 1] = h end end
        return function() i = i + 1; return list[i] end
    end
    env.AllObjects = function()
        local list, i = {}, 0
        for _, h in ipairs(sim.order) do if sim.objs[h].alive then list[#list + 1] = h end end
        return function() i = i + 1; return list[i] end
    end
    env.SetUserTarget = function(h) sim.userTarget = h end
    env.SetObjectiveOn = function(h) sim.marked[h] = true end
    env.FailMission = function() sim.failed = true; sim:say("FailMission") end
    env.SetCommand = function(h, cmd, pri, who)
        local u = U(h)
        if cmd == CMD.NONE or cmd == CMD.STOP then u.cmd, u.tgt, u.route = CMD.NONE, nil, nil
        elseif u.cmd == cmd and u.tgt == who then return -- the Lock sweep re-issues the same order
        else setOrder(sim, h, cmd, who, "SetCommand") end
    end
    env.Goto = function(h, t) setOrder(sim, h, CMD.GO, t, "Goto") end
    env.Follow = function(h, t) setOrder(sim, h, CMD.FOLLOW, t, "Follow") end
    env.Attack = function(h, t) setOrder(sim, h, CMD.ATTACK, t, "Attack") end
    env.Pickup = function(h, t) setOrder(sim, h, CMD.PICKUP, t, "Pickup") end
    env.Dropoff = function(h, t) setOrder(sim, h, CMD.DROPOFF, t, "Dropoff") end
    env.Stop = function(h) local u = U(h); u.cmd, u.tgt, u.route = CMD.NONE, nil, nil; sim:say("Stop " .. h) end
    local function startBuild(h, odf, at)
        local u = U(h)
        if u.build then sim:say("Build refused (busy) " .. h .. " " .. odf); return end
        local cost = PilotSim.odfCost(odf, sim.costs)
        local team = u.team
        local pilotNeeded = (odf:match("^%a%v") and 1) or 0
        if math.floor(sim.scrap[team] or 0) < cost.scrap or (sim.pilots[team] or 0) < pilotNeeded then
            sim.refused = sim.refused + 1
            sim:say(string.format("Build refused %s %s (scrap %d < %d)", h, odf, math.floor(sim.scrap[team] or 0), cost.scrap))
            return
        end
        sim.scrap[team] = sim.scrap[team] - cost.scrap
        sim.pilots[team] = (sim.pilots[team] or 0) - pilotNeeded
        u.build = { odf = odf, at = at, left = cost.time }
        sim:say(string.format("Build %s %s (scrap now %d)", h, odf, math.floor(sim.scrap[team])))
    end
    env.Build = function(h, odf) startBuild(h, odf, nil) end
    env.BuildAt = function(h, odf, target) startBuild(h, odf, target) end
end

-- ---------------------------------------------------------------- stepping
local function targetPoint(sim, u)
    if u.route then
        local p = u.route[u.ri]
        return p and p[1], p and p[2]
    end
    if u.tgt == nil then return nil end
    return sim:pos(u.tgt)
end

local function move(u, tx, tz, dt, stopAt)
    local dx, dz = tx - u.x, tz - u.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d <= stopAt then return d end
    local stepLen = math.min(u.speed * dt, d - stopAt)
    u.x, u.z = u.x + dx / d * stepLen, u.z + dz / d * stepLen
    return d - stepLen
end

function PilotSim:stepUnit(u)
    local dt = self.dt
    if u.speed <= 0 then return end
    local cmd = u.cmd
    if cmd == CMD.GO or cmd == CMD.DROPOFF or cmd == CMD.PICKUP then
        local tx, tz = targetPoint(self, u)
        if not tx then u.cmd = CMD.NONE; return end
        local d = move(u, tx, tz, dt, 0)
        if d <= ARRIVE then
            if u.route and u.ri < #u.route then u.ri = u.ri + 1; return end
            local tgtObj = type(u.tgt) == "string" and self.objs[u.tgt]
            if cmd == CMD.PICKUP and tgtObj then tgtObj.tug = u.h; u.carry = u.tgt end
            if cmd == CMD.DROPOFF and u.carry then self.objs[u.carry].tug = nil; u.carry = nil end
            if cmd == CMD.GO and tgtObj and tgtObj.odf:match("^eggeizr") and isProducer(u.odf) then
                u.deployed = true
                self:say(u.h .. " deployed on " .. u.tgt)
            end
            u.cmd, u.tgt, u.route = CMD.NONE, nil, nil
            self:say(u.h .. " arrived")
        end
    elseif cmd == CMD.FOLLOW or cmd == CMD.ATTACK then
        local tx, tz = targetPoint(self, u)
        if not tx then u.cmd = CMD.NONE; return end
        move(u, tx, tz, dt, cmd == CMD.FOLLOW and FOLLOW_DIST or ATTACK_DIST)
    end
    if u.carry then local c = self.objs[u.carry]; c.x, c.z = u.x, u.z end
end

function PilotSim:finishBuild(u)
    local b = u.build
    u.build = nil
    local x, z = u.x + 20, u.z + 20
    if b.at then x, z = self:pos(b.at) end
    local h = self:add(b.odf, u.team, x, z)
    local o = self.objs[h]
    if b.odf:match("scav") then o.cmd = CMD.SCAVENGE end
    table.insert(self.built, { odf = b.odf, h = h, t = self.t })
    self:say("built " .. h)
    local consumed = false
    if self.addHook then consumed = self.addHook(h) end
    if self.onSpawn then self.onSpawn(h, consumed) end
end

function PilotSim:step()
    local dt = self.dt
    for _, s in ipairs(self.stalls) do
        local u = self.objs[s.h]
        if not s.done and u and u.alive and u.cmd == CMD.GO then
            local ok
            if type(s.when) == "number" then ok = self.t >= s.when else ok = s.when(self, u) end
            if ok then
                s.done, s.at = true, self.t
                u.cmd, u.tgt, u.route = CMD.NONE, nil, nil
                self:say("STALL injected: " .. s.h .. " drops its order")
            end
        end
    end
    local scavs = 0
    for _, h in ipairs(self.order) do
        local u = self.objs[h]
        if u.alive then
            self:stepUnit(u)
            if u.build then
                u.build.left = u.build.left - dt
                if u.build.left <= 0 then self:finishBuild(u) end
            end
            if u.cmd == CMD.RECYCLE and self.t >= (u.recycleAt or 0) then u.alive = false; self:say(h .. " recycled") end
            if u.cmd == CMD.SCAVENGE and u.team == 1 then scavs = scavs + 1 end
        end
    end
    if scavs > 0 then
        local gain = scavs * SCAV_RATE * dt
        self.income = self.income + gain
        self.scrap[1] = math.min(self.maxScrap, (self.scrap[1] or 0) + gain)
    end
end

function PilotSim:tick()
    self.update()
    self:step()
    for _, fn in ipairs(self.eachFns) do fn(self) end
    for i = #self.events, 1, -1 do
        local ev = self.events[i]
        if ev[1](self) then table.remove(self.events, i); ev[2](self) end
    end
    self.t = self.t + self.dt
end

function PilotSim:dump()
    local out = { string.format("t=%.1f scrap=%d pilots=%d income=%.1f refused=%d failed=%s", self.t,
        math.floor(self.scrap[1] or 0), self.pilots[1] or 0, self.income, self.refused, tostring(self.failed)) }
    for _, tr in ipairs(self.tracked) do
        local u = self.objs[tr[2]]
        if u then
            local tgt = type(u.tgt) == "table" and "vec" or tostring(u.tgt)
            out[#out + 1] = string.format("  %-10s %-9s (%.0f,%.0f) alive=%s cmd=%d tgt=%s deployed=%s busy=%s", tr[1], u.odf,
                u.x, u.z, tostring(u.alive), u.cmd, tgt, tostring(u.deployed), tostring(u.build ~= nil))
        end
    end
    local n = #self.log
    for i = math.max(1, n - 8), n do out[#out + 1] = "  log " .. self.log[i] end
    return table.concat(out, "\n")
end

-- Run until cond(sim) is true; error with a state dump if it takes longer than `timeout` simulated seconds.
function PilotSim:runUntil(cond, timeout, what)
    local limit = self.t + timeout
    while not cond(self) do
        if self.failed then error(string.format("PilotSim[%s]: the mission failed while waiting for %s\n%s", self.name, what, self:dump()), 0) end
        if self.t > limit then
            error(string.format("PilotSim[%s]: STUCK waiting for %s (gave up after %ds)\n%s", self.name, what, timeout, self:dump()), 0)
        end
        self:tick()
    end
    return self.t
end

function PilotSim:runFor(seconds)
    local limit = self.t + seconds
    while self.t < limit do self:tick() end
end

function PilotSim:stallsFired()
    local n = 0
    for _, s in ipairs(self.stalls) do if s.done then n = n + 1 end end
    return n, #self.stalls
end

function PilotSim:expect(cond, msg)
    self.checks = (self.checks or 0) + 1
    if not cond then error(string.format("PilotSim[%s]: expectation failed: %s\n%s", self.name, msg, self:dump()), 0) end
end

-- Keep the player within `offset` metres of a handle (flies at hover speed each tick).
function PilotSim:playerEscort(h, offset)
    self:each(function(s)
        local p = s.objs[s.player]
        local x, z = s:pos(h)
        if x then move(p, x, z, s.dt, offset or 50) end
    end)
end

return PilotSim
