-- CRVenusMap.lua
--
-- The pure half of the Venus weather director: everything that can be decided
-- from numbers alone, with no engine, no particle system and no clock of its own.
--
--   rng        a small seeded generator. Both peers of a co-op game build their
--              weather schedule from the same seed, so the generator has to be
--              ours -- math.random is neither seedable per stream nor guaranteed
--              identical across builds.
--   ladder     the storm severity timeline (calm -> haze -> rising -> storm ->
--              severe) as an event list generated from the seed. It is a pure
--              function of (seed, target level, time): frame rate cannot change
--              it, and two peers that started from the same seed hold the same
--              timeline.
--   basins     low-lying ground, found by sampling terrain height over the
--              playable box and flood-filling the lowest percentile. This is
--              where the fog pools.
--   sulfur     clusters of liquid-sulphur tiles, from a material grid, where
--              the pools bubble.
--   picks      weighted choice for lightning targets.
--
-- Nothing here touches exu or the BZ globals, which is what lets
-- Tools/Test-CRVenusWeather.lua exercise every decision on synthetic data.

local Map = {}

local floor = math.floor
local sqrt = math.sqrt

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function SmoothStep(t)
    t = Clamp(t, 0.0, 1.0)
    return t * t * (3.0 - (2.0 * t))
end

Map.Clamp = Clamp
Map.SmoothStep = SmoothStep

-- =============================================================================
-- Random numbers
-- =============================================================================

local MODULUS = 2147483647
local MULTIPLIER = 48271

-- Park-Miller. The intermediate product stays under 2^47, so it is exact in a
-- double on every platform -- which is the whole point: the stream must be
-- bit-identical on both peers.
function Map.NewRng(seed)
    local state = floor(math.abs(tonumber(seed) or 1)) % (MODULUS - 1) + 1
    local rng = {}

    function rng.Next()
        state = (state * MULTIPLIER) % MODULUS
        return state / MODULUS
    end

    function rng.Range(low, high)
        return low + (rng.Next() * (high - low))
    end

    -- Inclusive on both ends.
    function rng.Int(low, high)
        return low + floor(rng.Next() * (high - low + 1))
    end

    function rng.Chance(p)
        return rng.Next() < p
    end

    function rng.GetState()
        return state
    end

    -- Restores a value GetState returned. Unlike the constructor this takes the
    -- raw state, so a saved stream continues exactly where it stopped.
    function rng.SetState(value)
        state = Clamp(floor(math.abs(tonumber(value) or 1)), 1, MODULUS - 1)
    end

    return rng
end

-- A different, reproducible stream per concern, so adding a draw to one system
-- (say, wind) can never shift the ladder.
function Map.DeriveSeed(seed, salt)
    local base = floor(math.abs(tonumber(seed) or 1)) % MODULUS
    return ((base * 1103 + (salt or 0) * 7919 + 12345) % (MODULUS - 2)) + 1
end

-- =============================================================================
-- Weighted pick
-- =============================================================================

-- items: array of tables with a numeric `weight`. Returns the item and its
-- index, or nil for an empty / zero-weight list.
function Map.PickWeighted(rng, items)
    local total = 0.0
    for i = 1, #items do
        local w = items[i].weight or 0.0
        if w > 0.0 then total = total + w end
    end
    if total <= 0.0 then
        return nil, nil
    end

    local roll = rng.Next() * total
    local running = 0.0
    local last = nil
    for i = 1, #items do
        local w = items[i].weight or 0.0
        if w > 0.0 then
            running = running + w
            last = i
            if roll < running then
                return items[i], i
            end
        end
    end
    return items[last], last
end

-- =============================================================================
-- Severity ladder
-- =============================================================================
--
-- cfg:
--   levels        number of rungs
--   start         first rung
--   durations     [rung] = { low, high } seconds the rung is held
--   moveWeights   { up, same, down } when the target is above / at / below
--   episode       nil, or { chance, minLevel, minTarget, peak = {lo, hi},
--                 stepDwell = {lo, hi}, hold = {lo, hi}, cooldown }
--
-- The timeline is a list of { t, dur, level, episode }. It is extended lazily as
-- time passes, and only ever by appending, so it is a function of the seed and
-- of the target level at the moment each segment was generated.
--
-- An episode is a temporary storm: the ladder climbs one rung at a time to a
-- peak, holds, and walks back down to where it started. Climbing and falling
-- are generated as ordinary one-rung segments, so a transition never skips a
-- rung however intense the episode is.

local DEFAULT_MOVE = {
    up   = { 6, 3, 1 },   -- target above current: { up, same, down }
    same = { 2, 5, 2 },
    down = { 1, 3, 6 },
}

function Map.NewLadder(seed, cfg)
    local ladder = {
        cfg        = cfg,
        rng        = Map.NewRng(Map.DeriveSeed(seed, 1)),
        seed       = seed,
        timeline   = {},
        index      = 1,
        cooldownTo = 0.0,
    }

    local start = Clamp(cfg.start or 1, 1, cfg.levels)
    local dur = ladder.rng.Range(cfg.durations[start][1], cfg.durations[start][2])
    ladder.timeline[1] = { t = 0.0, dur = dur, level = start, episode = false }

    local function PickNext(current, target)
        local row
        if target > current then row = DEFAULT_MOVE.up
        elseif target < current then row = DEFAULT_MOVE.down
        else row = DEFAULT_MOVE.same end
        local up, same, down = row[1], row[2], row[3]
        local move = cfg.moveWeights
        if move ~= nil then
            local custom = target > current and move.up or (target < current and move.down or move.same)
            if custom ~= nil then up, same, down = custom[1], custom[2], custom[3] end
        end

        -- At an end of the ladder the unavailable move folds into staying put.
        if current >= cfg.levels then same = same + up; up = 0 end
        if current <= 1 then same = same + down; down = 0 end

        local roll = ladder.rng.Next() * (up + same + down)
        if roll < up then return current + 1 end
        if roll < (up + same) then return current end
        return current - 1
    end

    local function Append(t, level, dur, episode)
        ladder.timeline[#ladder.timeline + 1] = { t = t, dur = dur, level = level, episode = episode }
    end

    function ladder:Extend(target)
        local last = self.timeline[#self.timeline]
        local t = last.t + last.dur
        local episode = cfg.episode

        if episode ~= nil and not last.episode
            and last.level >= (episode.minLevel or 3)
            and (target or 1) >= (episode.minTarget or 3)
            and t >= self.cooldownTo
            and self.rng.Next() < (episode.chance or 0.0)
        then
            local base = last.level
            local peak = Clamp(self.rng.Int(episode.peak[1], episode.peak[2]), 1, cfg.levels)
            if peak > base then
                local level = base
                while level < peak do
                    level = level + 1
                    local step = self.rng.Range(episode.stepDwell[1], episode.stepDwell[2])
                    Append(t, level, step, true)
                    t = t + step
                end
                -- The hold is added to the peak segment rather than appended, so
                -- the peak is one segment however long it lasts.
                local hold = self.rng.Range(episode.hold[1], episode.hold[2])
                local top = self.timeline[#self.timeline]
                top.dur = top.dur + hold
                t = t + hold
                while level > base do
                    level = level - 1
                    local step = self.rng.Range(episode.stepDwell[1], episode.stepDwell[2])
                    -- Only the segment that lands back on the base rung stops
                    -- being "episode": that is where the storm is over.
                    Append(t, level, step, level > base)
                    t = t + step
                end
                self.cooldownTo = t + (episode.cooldown or 120.0)
                return
            end
        end

        local nextLevel = PickNext(last.level, target or 1)
        local range = cfg.durations[nextLevel]
        Append(t, nextLevel, self.rng.Range(range[1], range[2]), false)
    end

    -- Level in force at `now`. `target` is the rung the mission wants the
    -- weather to trend toward; it only matters at the moment a new segment is
    -- generated.
    function ladder:Advance(now, target)
        local guard = 0
        local timeline = self.timeline
        while now >= (timeline[#timeline].t + timeline[#timeline].dur) do
            self:Extend(target)
            guard = guard + 1
            if guard > 500 then break end   -- a runaway clock must not hang the frame
        end

        local index = self.index
        if index > #timeline then index = #timeline end
        while index < #timeline and now >= (timeline[index].t + timeline[index].dur) do
            index = index + 1
        end
        self.index = index

        -- Forget history nobody can ask about again.
        if index > 24 then
            for _ = 1, 16 do table.remove(timeline, 1) end
            self.index = self.index - 16
            index = self.index
        end

        local segment = timeline[index]
        return segment.level, segment.episode
    end

    function ladder:Current()
        local segment = self.timeline[self.index]
        return segment.level, segment.episode
    end

    -- The state a save needs: enough to continue the same timeline.
    function ladder:Save()
        local segments = {}
        for i = math.max(1, self.index), #self.timeline do
            local s = self.timeline[i]
            segments[#segments + 1] = { s.t, s.dur, s.level, s.episode and 1 or 0 }
        end
        return { seed = self.seed, rng = self.rng.GetState(), cooldown = self.cooldownTo, segments = segments }
    end

    function ladder:Load(state)
        if type(state) ~= "table" or type(state.segments) ~= "table" or #state.segments == 0 then
            return false
        end
        self.timeline = {}
        for i = 1, #state.segments do
            local s = state.segments[i]
            self.timeline[i] = { t = s[1], dur = s[2], level = s[3], episode = s[4] == 1 }
        end
        self.index = 1
        self.rng.SetState(state.rng)
        self.cooldownTo = tonumber(state.cooldown) or 0.0
        return true
    end

    return ladder
end

-- =============================================================================
-- Fog banks -- rare, short, dense sulphur fog
-- =============================================================================
--
-- A fog bank is a scheduled moment, not a rung of the ladder: the air closes to
-- pea soup for tens of seconds and opens again. The schedule is a PURE function
-- of the seed -- it never reads the ladder, the mission target or anything a
-- peer could disagree about -- so every peer derives the same banks at the same
-- clock times with no traffic at all. Whether a bank is allowed to show (not in a
-- storm, not during a forced set piece) is decided by the caller, at run time,
-- and only scales the envelope; it never moves the schedule.
--
-- cfg:
--   firstDelay   { lo, hi }  seconds before the first bank starts
--   gap          { lo, hi }  seconds between one bank ending and the next starting
--   total        { lo, hi }  seconds from first roll-in to fully clear
--   rollIn       { lo, hi }  seconds to close
--   rollOut      { lo, hi }  seconds to open
--   power        { lo, hi }  peak strength 0..1
--
-- Each bank is { start, rollIn, hold, rollOut, dur, power }. `dur` is the sum of
-- the three phases and always lies inside `total` (the hold absorbs the slack).

function Map.NewFogBanks(seed, cfg)
    local sched = {
        cfg = cfg,
        rng = Map.NewRng(Map.DeriveSeed(seed, 6)),
        events = {},
        cursor = 1,
    }

    local function Append()
        local rng = sched.rng
        local last = sched.events[#sched.events]
        local start
        if last == nil then
            start = rng.Range(cfg.firstDelay[1], cfg.firstDelay[2])
        else
            start = last.start + last.dur + rng.Range(cfg.gap[1], cfg.gap[2])
        end
        local total = rng.Range(cfg.total[1], cfg.total[2])
        local rollIn = rng.Range(cfg.rollIn[1], cfg.rollIn[2])
        local rollOut = rng.Range(cfg.rollOut[1], cfg.rollOut[2])
        local hold = math.max(4.0, total - rollIn - rollOut)
        local power = rng.Range(cfg.power[1], cfg.power[2])
        sched.events[#sched.events + 1] = {
            start = start, rollIn = rollIn, hold = hold, rollOut = rollOut,
            dur = rollIn + hold + rollOut, power = power,
        }
    end

    -- Every bank that starts at or before `untilT`.
    function sched:Events(untilT)
        local guard = 0
        while (#self.events == 0 or self.events[#self.events].start <= untilT) and guard < 500 do
            Append()
            guard = guard + 1
        end
        return self.events
    end

    -- The bank whose window contains `now` (nil between banks).
    function sched:Active(now)
        self:Events(now)
        local events = self.events
        local i = self.cursor
        if i > #events then i = #events end
        if i > 1 and events[i].start > now then i = 1 end     -- the clock moved backwards (load)
        while i < #events and now >= (events[i].start + events[i].dur) do i = i + 1 end
        self.cursor = i
        local e = events[i]
        if e ~= nil and now >= e.start and now < (e.start + e.dur) then return e end
        return nil
    end

    return sched
end

-- 0..1 shape of a bank at `now`: smooth in, flat, smooth out. Multiply by
-- bank.power for the strength.
function Map.FogEnvelope(bank, now)
    if bank == nil then return 0.0 end
    local t = now - bank.start
    local total = bank.rollIn + bank.hold + bank.rollOut
    if t <= 0.0 or t >= total then return 0.0 end
    if t < bank.rollIn then return SmoothStep(t / bank.rollIn) end
    if t < (bank.rollIn + bank.hold) then return 1.0 end
    return SmoothStep(1.0 - ((t - bank.rollIn - bank.hold) / bank.rollOut))
end

-- =============================================================================
-- Basins -- where the fog pools
-- =============================================================================

-- Samples terrain height on a regular grid over `bounds`. The scan is
-- incremental because a few thousand terrain queries do not belong in one frame:
-- call scan:Step(budget) once per frame until it returns true.
--
-- sampleFn(x, z) -> height, or nil where there is no terrain. `inset` keeps the
-- scan off the playable box's outer edge, where the terrain is the unreachable
-- apron the engine draws beyond the map.
function Map.NewHeightScan(bounds, nx, nz, sampleFn, inset)
    inset = inset or 0.0
    local minX, maxX = bounds.minX + inset, bounds.maxX - inset
    local minZ, maxZ = bounds.minZ + inset, bounds.maxZ - inset
    nx = math.max(2, floor(nx))
    nz = math.max(2, floor(nz))

    local scan = {
        minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ,
        nx = nx, nz = nz,
        dx = (maxX - minX) / (nx - 1),
        dz = (maxZ - minZ) / (nz - 1),
        heights = {},
        cursor = 0,
        total = nx * nz,
        sampleFn = sampleFn,
    }

    function scan:Step(budget)
        local n = 0
        while self.cursor < self.total and n < budget do
            local k = self.cursor
            local i = k % self.nx
            local j = floor(k / self.nx)
            local h = self.sampleFn(self.minX + (i * self.dx), self.minZ + (j * self.dz))
            if type(h) == "number" and h == h then
                self.heights[k + 1] = h
            else
                self.heights[k + 1] = false
            end
            self.cursor = k + 1
            n = n + 1
        end
        return self.cursor >= self.total
    end

    function scan:IsDone()
        return self.cursor >= self.total
    end

    return scan
end

local function Percentile(sorted, p)
    local n = #sorted
    if n == 0 then return nil end
    local index = floor(Clamp(p, 0.0, 1.0) * (n - 1)) + 1
    return sorted[index]
end

-- opts:
--   lowPercentile   fraction of the playable ground that counts as "low" (0.22)
--   minDepth        the lowest ground must sit this far under the median, or the
--                   map has no basins worth fogging (6)
--   minCells        smallest cluster kept (6)
--   anchorSpacing   minimum distance between fog systems in one basin (110)
--   maxPerCluster   most fog systems one basin can hold (8)
--   maxAnchors      fog systems overall (24); the director streams a few of these
--                   around the players, so this is a candidate list, not a draw count
--   reliefRadius    how far around a cell to look for enclosing higher ground (220)
--   minRelief       how much higher that ring must be, on average (3)
--
-- Returns nil when the scan is incomplete or has no usable samples. Otherwise:
--   median, lowest, threshold, ridgeLevel, poolLevel
--   clusters  { id, count, cx, cz, level, minHeight, radius, depth, weight }
--   anchors   { x, z, y, level, weight, cluster }, deepest basin first
function Map.AnalyseBasins(scan, opts)
    if scan == nil or not scan:IsDone() then
        return nil
    end
    opts = opts or {}

    local sorted = {}
    for k = 1, scan.total do
        local h = scan.heights[k]
        if h then sorted[#sorted + 1] = h end
    end
    if #sorted < 4 then
        return nil
    end
    table.sort(sorted)

    local median = Percentile(sorted, 0.5)
    local lowest = sorted[1]
    local minDepth = opts.minDepth or 6.0
    -- The low band is the lowest percentile, but never so close to the median
    -- that ordinary flat ground qualifies: on a map that is mostly one flat
    -- shelf with a few pits, the 22nd percentile IS the shelf.
    local threshold = math.min(Percentile(sorted, opts.lowPercentile or 0.22), median - (0.5 * minDepth))
    local ridge = Percentile(sorted, 0.85)

    local result = {
        median = median, lowest = lowest, threshold = threshold, ridgeLevel = ridge,
        poolLevel = threshold, clusters = {}, anchors = {}, validCount = #sorted,
    }

    if (median - lowest) < minDepth then
        return result   -- flat ground: nothing is "low" in a way a player would see
    end

    -- Flood fill the low mask, eight-connected.
    local nx, nz = scan.nx, scan.nz
    local seen = {}
    local minCells = opts.minCells or 6
    local clusterId = 0

    -- "Low" is not enough: a map can have one huge flat floor that is the lowest
    -- ground everywhere, and fogging all of it is not a pool. A pooled cell must
    -- also sit under its surroundings -- the mean height of a ring around it has
    -- to be at least `minRelief` above it -- which keeps the lowlands that
    -- hills actually enclose and drops the open plain.
    local reliefRadius = opts.reliefRadius or 220.0
    local minRelief = opts.minRelief or 3.0
    local ringI = math.max(1, floor((reliefRadius / math.max(scan.dx, 1e-6)) + 0.5))
    local ringJ = math.max(1, floor((reliefRadius / math.max(scan.dz, 1e-6)) + 0.5))
    local function Relief(k)
        local i = (k - 1) % nx
        local j = floor((k - 1) / nx)
        local own = scan.heights[k]
        local sum, n = 0.0, 0
        for a = 0, 7 do
            local ang = a * (math.pi / 4.0)
            local ni = i + floor((math.cos(ang) * ringI) + (math.cos(ang) >= 0 and 0.5 or -0.5))
            local nj = j + floor((math.sin(ang) * ringJ) + (math.sin(ang) >= 0 and 0.5 or -0.5))
            if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
                local h = scan.heights[(nj * nx) + ni + 1]
                if h then sum = sum + h; n = n + 1 end
            end
        end
        if n < 3 then return 0.0 end
        return (sum / n) - own
    end

    local pooled = {}
    for k = 1, scan.total do
        local h = scan.heights[k]
        if h and h <= threshold and Relief(k) >= minRelief then
            pooled[k] = true
        end
    end

    for start = 1, scan.total do
        local h0 = scan.heights[start]
        if pooled[start] and not seen[start] then
            local cells = {}
            local stack = { start }
            seen[start] = true
            while #stack > 0 do
                local k = table.remove(stack)
                cells[#cells + 1] = k
                local i = (k - 1) % nx
                local j = floor((k - 1) / nx)
                for dj = -1, 1 do
                    for di = -1, 1 do
                        if di ~= 0 or dj ~= 0 then
                            local ni, nj = i + di, j + dj
                            if ni >= 0 and ni < nx and nj >= 0 and nj < nz then
                                local nk = (nj * nx) + ni + 1
                                if pooled[nk] and not seen[nk] then
                                    seen[nk] = true
                                    stack[#stack + 1] = nk
                                end
                            end
                        end
                    end
                end
            end

            if #cells >= minCells then
                clusterId = clusterId + 1
                local sx, sz, hs = 0.0, 0.0, {}
                for c = 1, #cells do
                    local k = cells[c]
                    sx = sx + (scan.minX + (((k - 1) % nx) * scan.dx))
                    sz = sz + (scan.minZ + (floor((k - 1) / nx) * scan.dz))
                    hs[c] = scan.heights[k]
                end
                local cx, cz = sx / #cells, sz / #cells
                table.sort(hs)
                local level = Percentile(hs, 0.9)

                local radius = 0.0
                for c = 1, #cells do
                    local k = cells[c]
                    local dx = scan.minX + (((k - 1) % nx) * scan.dx) - cx
                    local dz = scan.minZ + (floor((k - 1) / nx) * scan.dz) - cz
                    local d = sqrt((dx * dx) + (dz * dz))
                    if d > radius then radius = d end
                end

                local span = math.max(1e-6, median - lowest)
                result.clusters[#result.clusters + 1] = {
                    id = clusterId, count = #cells, cx = cx, cz = cz,
                    level = level, minHeight = hs[1], radius = radius,
                    depth = median - level,
                    weight = Clamp((median - level) / span, 0.15, 1.0),
                    cells = cells,
                }
            end
        end
    end

    if #result.clusters > 0 then
        local weighted, total = 0.0, 0.0
        for i = 1, #result.clusters do
            local c = result.clusters[i]
            weighted = weighted + (c.level * c.count)
            total = total + c.count
        end
        result.poolLevel = weighted / total
    end

    -- Anchors: greedy, lowest ground first, kept apart so one wide basin gets a
    -- few overlapping banks of fog instead of fifty identical ones. A basin's
    -- share grows with its size, and the overall list interleaves basins by
    -- importance so a big shallow floor cannot be starved by a small deep pit
    -- (or the reverse): every basin gets its first anchor before any gets its
    -- second.
    local spacing = opts.anchorSpacing or 110.0
    local perClusterMax = opts.maxPerCluster or 8
    local perPick = {}
    local order = {}
    for ci = 1, #result.clusters do
        local c = result.clusters[ci]
        local ordered = {}
        for n = 1, #c.cells do ordered[n] = c.cells[n] end
        table.sort(ordered, function(a, b)
            local ha, hb = scan.heights[a], scan.heights[b]
            if ha ~= hb then return ha < hb end
            return a < b
        end)

        local want = Clamp(floor(#c.cells / 5), 1, perClusterMax)
        local picked = {}
        for n = 1, #ordered do
            if #picked >= want then break end
            local k = ordered[n]
            local x = scan.minX + (((k - 1) % nx) * scan.dx)
            local z = scan.minZ + (floor((k - 1) / nx) * scan.dz)
            local ok = true
            for p = 1, #picked do
                local ddx, ddz = x - picked[p].x, z - picked[p].z
                if sqrt((ddx * ddx) + (ddz * ddz)) < spacing then ok = false; break end
            end
            if ok then
                picked[#picked + 1] = {
                    x = x, z = z, y = scan.heights[k], level = c.level,
                    weight = c.weight, cluster = c.id,
                }
            end
        end
        perPick[ci] = picked
        order[#order + 1] = ci
    end

    table.sort(order, function(a, b)
        local ia = result.clusters[a].count * result.clusters[a].weight
        local ib = result.clusters[b].count * result.clusters[b].weight
        if ia ~= ib then return ia > ib end
        return a < b
    end)

    local maxAnchors = opts.maxAnchors or 24
    local round = 1
    while #result.anchors < maxAnchors do
        local added = false
        for n = 1, #order do
            local pick = perPick[order[n]][round]
            if pick ~= nil and #result.anchors < maxAnchors then
                result.anchors[#result.anchors + 1] = pick
                added = true
            end
        end
        if not added then break end
        round = round + 1
    end

    -- The cells are bulky and only needed to build the anchors.
    for i = 1, #result.clusters do result.clusters[i].cells = nil end
    return result
end

-- 1 deep in a pool, 0 up on the ridges. `y` is the observer's altitude.
-- The pool level is the nearest basin's when the observer is over (or just
-- beside) one, otherwise the map-wide pool level, so a valley floor that is
-- higher than the lowest basin still counts as being "down in the fog".
function Map.PoolFactor(result, x, y, z, opts)
    if result == nil then
        return 0.0
    end
    opts = opts or {}
    local margin = opts.margin or 60.0
    local level = result.poolLevel

    local best = nil
    for i = 1, #result.clusters do
        local c = result.clusters[i]
        local dx, dz = x - c.cx, z - c.cz
        local d = sqrt((dx * dx) + (dz * dz))
        if d <= (c.radius + margin) and (best == nil or d < best) then
            best = d
            level = c.level
        end
    end

    local band = opts.band or math.max(8.0, ((result.ridgeLevel or level) - level) * 0.5)
    return 1.0 - SmoothStep((y - level) / band)
end

-- =============================================================================
-- Sulfur -- clusters of liquid-sulphur tiles
-- =============================================================================

-- Expands the run-length data written by Tools/Build-VenusSites.py:
-- sulfur = { cols, rows, cell, originX, originZ, runs = { {row, col, len, w} } }
-- into a sparse map  cells[row * cols + col] = weight.
function Map.ExpandRuns(sulfur)
    local cells = {}
    local count = 0
    local cols = sulfur.cols
    for i = 1, #(sulfur.runs or {}) do
        local run = sulfur.runs[i]
        for c = run[2], run[2] + run[3] - 1 do
            local key = (run[1] * cols) + c
            if cells[key] == nil then count = count + 1 end
            cells[key] = run[4]
        end
    end
    return cells, count
end

-- The same cell map straight from raw .mat entries: base material in bits
-- 15-12, next material in bits 11-8. cellFn(col, row) -> uint16.
function Map.CellsFromMat(cols, rows, cellFn, types, transitionWeight)
    local wanted = {}
    for i = 1, #types do wanted[types[i]] = true end
    local cells, count = {}, 0
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local raw = cellFn(col, row) or 0
            local base = floor(raw / 4096) % 16
            local nxt = floor(raw / 256) % 16
            local w = nil
            if wanted[base] then w = 1.0
            elseif wanted[nxt] then w = transitionWeight or 0.5 end
            if w then
                cells[(row * cols) + col] = w
                count = count + 1
            end
        end
    end
    return cells, count
end

-- geom: { cols, rows, cell, originX, originZ }
-- opts:
--   minCells        smallest cluster kept (4)
--   gap             cells of empty space a cluster may bridge (1)
--   emitterSpacing  minimum distance between emitters in a cluster (34)
--   maxPerCluster   emitters per cluster (6)
--   maxEmitters     emitters overall (24)
function Map.ClusterSulfur(cells, geom, opts)
    opts = opts or {}
    local minCells = opts.minCells or 4
    local gap = opts.gap or 1
    local cols = geom.cols
    local cell = geom.cell

    -- Stable iteration order, so every peer builds the same clusters.
    local keys = {}
    for key in pairs(cells) do keys[#keys + 1] = key end
    table.sort(keys)

    local seen = {}
    local clusters = {}
    for n = 1, #keys do
        local startKey = keys[n]
        if not seen[startKey] then
            local members = {}
            local stack = { startKey }
            seen[startKey] = true
            while #stack > 0 do
                local key = table.remove(stack)
                members[#members + 1] = key
                local row = floor(key / cols)
                local col = key - (row * cols)
                for dr = -(1 + gap), (1 + gap) do
                    for dc = -(1 + gap), (1 + gap) do
                        if dr ~= 0 or dc ~= 0 then
                            local nr, nc = row + dr, col + dc
                            if nc >= 0 and nc < cols and nr >= 0 and nr < geom.rows then
                                local nk = (nr * cols) + nc
                                if cells[nk] ~= nil and not seen[nk] then
                                    seen[nk] = true
                                    stack[#stack + 1] = nk
                                end
                            end
                        end
                    end
                end
            end

            if #members >= minCells then
                table.sort(members)
                local sx, sz, sw = 0.0, 0.0, 0.0
                for m = 1, #members do
                    local key = members[m]
                    local row = floor(key / cols)
                    local col = key - (row * cols)
                    local w = cells[key]
                    sx = sx + ((geom.originX + ((col + 0.5) * cell)) * w)
                    sz = sz + ((geom.originZ + ((row + 0.5) * cell)) * w)
                    sw = sw + w
                end
                local cx, cz = sx / sw, sz / sw
                local radius = 0.0
                for m = 1, #members do
                    local key = members[m]
                    local row = floor(key / cols)
                    local col = key - (row * cols)
                    local dx = geom.originX + ((col + 0.5) * cell) - cx
                    local dz = geom.originZ + ((row + 0.5) * cell) - cz
                    local d = sqrt((dx * dx) + (dz * dz))
                    if d > radius then radius = d end
                end

                clusters[#clusters + 1] = {
                    id = #clusters + 1, count = #members, weight = sw,
                    cx = cx, cz = cz, radius = radius, members = members,
                }
            end
        end
    end

    -- Emitters: solid cells before transition cells, kept apart.
    local spacing = opts.emitterSpacing or 34.0
    local perCluster = opts.maxPerCluster or 6
    local all = {}
    for ci = 1, #clusters do
        local c = clusters[ci]
        local ordered = {}
        for m = 1, #c.members do ordered[m] = c.members[m] end
        table.sort(ordered, function(a, b)
            local wa, wb = cells[a], cells[b]
            if wa ~= wb then return wa > wb end
            return a < b
        end)

        local picked = {}
        for m = 1, #ordered do
            if #picked >= perCluster then break end
            local key = ordered[m]
            local row = floor(key / cols)
            local col = key - (row * cols)
            local x = geom.originX + ((col + 0.5) * cell)
            local z = geom.originZ + ((row + 0.5) * cell)
            local ok = true
            for p = 1, #picked do
                local dx, dz = x - picked[p].x, z - picked[p].z
                if sqrt((dx * dx) + (dz * dz)) < spacing then ok = false; break end
            end
            if ok then
                picked[#picked + 1] = { x = x, z = z, weight = cells[key], cluster = c.id }
            end
        end
        c.emitters = picked
        c.members = nil
        for p = 1, #picked do all[#all + 1] = picked[p] end
    end

    table.sort(all, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        if a.x ~= b.x then return a.x < b.x end
        return a.z < b.z
    end)
    local maxEmitters = opts.maxEmitters or 24
    local emitters = {}
    for n = 1, math.min(maxEmitters, #all) do emitters[n] = all[n] end

    return { clusters = clusters, emitters = emitters }
end

-- =============================================================================
-- Vents
-- =============================================================================

-- A volcano is modelled in the BZN as a clump of geyser objects a few metres
-- apart. One plume per clump, not one per object: the clump is a single vent as
-- far as the eye is concerned. vents: { {x, y, z, major, label} }.
function Map.MergeVents(vents, radius)
    radius = radius or 45.0
    local merged = {}
    for i = 1, #vents do
        local v = vents[i]
        local home = nil
        for m = 1, #merged do
            local dx, dz = v.x - merged[m].x, v.z - merged[m].z
            if sqrt((dx * dx) + (dz * dz)) <= radius then home = merged[m]; break end
        end
        if home == nil then
            merged[#merged + 1] = {
                x = v.x, y = v.y or 0.0, z = v.z, major = v.major and true or false,
                count = 1, label = v.label,
            }
        else
            local n = home.count
            home.x = ((home.x * n) + v.x) / (n + 1)
            home.z = ((home.z * n) + v.z) / (n + 1)
            home.y = math.max(home.y, v.y or 0.0)
            home.count = n + 1
            if v.major then home.major = true end
        end
    end
    return merged
end

return Map
