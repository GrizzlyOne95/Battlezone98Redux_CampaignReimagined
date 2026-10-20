--**********************************************************************
-- CRPOOLFX: sparse bubbles, embers and spatter on lava and liquid-sulphur
-- pools, drawn through CRGroundFX (the ISDF Chronicles lava port).
--
-- A weather director owns one state per pool kind:
--
--   local fx = CRPoolFX.New{ kind = "lava", sites = pools, weightAt = fn, rng = FxRng }
--   CRPoolFX.Update(fx, dt, playerPos, { scale = rung, quality = q, enabled = true })
--   CRPoolFX.Stop(fx)                                -- shutdown / load
--
-- Cheap by construction:
--   * only the maxNear pool anchors nearest the player, and only inside
--     `range`, are ever eligible (refreshed once a second);
--   * every eligible anchor fires one event every gap[1]..gap[2] seconds
--     (shorter at a higher rung), and no two events start closer than
--     minSpacing, so the director adds at most about maxNear / gap events a
--     second;
--   * CRGroundFX holds a fixed ring of emitter slots per kind (4 systems), so
--     the live particle emitters have a hard cap whatever happens here.
--
-- Cosmetic and local: it reads only static map data and the local player,
-- writes no gameplay state, sends nothing over the network and never plays
-- the engine's damaging xlavarh / xtoxich explosions. It draws from the
-- director's local FX rng, so peers do not need to agree on it.
--**********************************************************************
local P = {}

local sqrt, cos, sin, pi = math.sqrt, math.cos, math.sin, math.pi

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function LoadGroundFX()
    local ok, mod = pcall(require, "CRGroundFX")
    if ok and type(mod) == "table" and type(mod.Event) == "function" then return mod end
    return nil
end

--- cfg:
---   kind        CRGroundFX kind ("lava" or "sulfur")
---   sites       array of { x, z, weight? } pool anchors (sim space)
---   rng         local rng with Range(lo, hi) (the director's FxRng)
---   weightAt    optional fn(x, z) -> 0..1, so spatter stays on the pool
---   heightAt    optional fn(x, z) -> ground height
---   range       eligible distance from the player (m)        default 170
---   maxNear     anchors active at once                        default 3
---   gap         per-anchor seconds between events             default { 1.4, 3.6 }
---   radius      spread around an anchor (m)                   default 32
---   minWeight   weightAt needed for a spot                    default 0.5
---   minSpacing  seconds between any two events                default 0.35
---   mask        per-system multipliers, e.g. { smoke = 0.3 }  (0 = off)
---   groundFx    CRGroundFX module override (tests)
function P.New(cfg)
    cfg = cfg or {}
    local gap = cfg.gap or { 1.4, 3.6 }
    return {
        kind = cfg.kind or "lava",
        sites = cfg.sites or {},
        rng = cfg.rng,
        weightAt = cfg.weightAt,
        heightAt = cfg.heightAt,
        range = cfg.range or 170.0,
        maxNear = cfg.maxNear or 3,
        gap = { gap[1], gap[2] },
        radius = cfg.radius or 32.0,
        minWeight = cfg.minWeight or 0.5,
        minSpacing = cfg.minSpacing or 0.35,
        mask = cfg.mask,
        groundFx = cfg.groundFx,
        clock = 0.0,
        nextRefresh = 0.0,
        lastEvent = -100.0,
        near = {},          -- array of site indexes, nearest first
        due = {},           -- site index -> clock when it fires next
        failures = 0,
        retryAt = 0.0,
        stats = { events = 0, skipped = 0 },
        started = false,
    }
end

local function Refresh(state, playerPos)
    local limit = state.range * state.range
    local best = {}
    local sites = state.sites
    for i = 1, #sites do
        local s = sites[i]
        local dx, dz = s.x - playerPos.x, s.z - playerPos.z
        local d2 = dx * dx + dz * dz
        if d2 < limit then
            -- insertion into a short sorted list (maxNear is tiny)
            local at = #best + 1
            while at > 1 and best[at - 1].d2 > d2 do at = at - 1 end
            if at <= state.maxNear then
                table.insert(best, at, { index = i, d2 = d2 })
                if #best > state.maxNear then best[#best] = nil end
            end
        end
    end
    local near = {}
    for i = 1, #best do near[i] = best[i].index end
    state.near = near
end

local function PickSpot(state, site)
    local rng = state.rng
    if rng == nil then return site.x, site.z end
    for _ = 1, 4 do
        local a = rng.Range(0.0, 2.0 * pi)
        local r = state.radius * sqrt(rng.Range(0.0, 1.0))
        local x, z = site.x + cos(a) * r, site.z + sin(a) * r
        if state.weightAt == nil or state.weightAt(x, z) >= state.minWeight then
            return x, z
        end
    end
    if state.weightAt == nil or state.weightAt(site.x, site.z) >= state.minWeight then
        return site.x, site.z
    end
    return nil
end

--- Advance the clock and fire any due events. opts: enabled (default true),
--- scale (rung/severity multiplier, default 1), quality (0 = off, default 1).
--- Returns the number of events fired this call.
function P.Update(state, dt, playerPos, opts)
    if state == nil then return 0 end
    opts = opts or {}
    dt = tonumber(dt) or 0.0
    if dt > 0.0 then state.clock = state.clock + dt end

    local quality = tonumber(opts.quality)
    if quality == nil then quality = 1.0 end
    if opts.enabled == false or quality <= 0.05 or playerPos == nil or #state.sites == 0 then
        if state.started then P.Stop(state) end
        return 0
    end

    local fx = state.groundFx or LoadGroundFX()
    if fx == nil then return 0 end
    state.groundFx = fx
    state.started = true
    if state.clock < state.retryAt then
        fx.Update()
        return 0
    end

    if state.clock >= state.nextRefresh then
        state.nextRefresh = state.clock + 1.0
        Refresh(state, playerPos)
    end

    local scale = Clamp(tonumber(opts.scale) or 1.0, 0.25, 3.0)
    local pace = scale * Clamp(quality, 0.25, 1.5)
    local rateScale = Clamp(0.7 + (0.3 * scale), 0.5, 1.5) * Clamp(quality, 0.25, 1.0)
    local fired = 0
    local rng = state.rng

    for n = 1, #state.near do
        local index = state.near[n]
        local due = state.due[index]
        if due == nil then
            -- First sight of this pool: stagger so a cluster does not pop on one beat.
            due = state.clock + (rng and rng.Range(0.0, state.gap[2]) or state.gap[2])
            state.due[index] = due
        end
        if state.clock >= due and (state.clock - state.lastEvent) >= state.minSpacing then
            local site = state.sites[index]
            local x, z = PickSpot(state, site)
            state.due[index] = state.clock
                + ((rng and rng.Range(state.gap[1], state.gap[2]) or state.gap[1]) / pace)
            if x == nil then
                state.stats.skipped = state.stats.skipped + 1
            else
                local y = (state.heightAt and state.heightAt(x, z)) or site.y or 0.0
                local ok = fx.Event(state.kind, { x = x, y = y, z = z }, rateScale, state.mask)
                if ok then
                    state.failures = 0
                    state.lastEvent = state.clock
                    state.stats.events = state.stats.events + 1
                    state.stats.lastX, state.stats.lastZ = x, z
                    fired = fired + 1
                else
                    state.failures = state.failures + 1
                    if state.failures >= 3 then
                        -- No particles (no EXU, or the payload is missing): back off.
                        state.failures = 0
                        state.retryAt = state.clock + 30.0
                        break
                    end
                end
            end
        end
    end

    fx.Update()
    return fired
end

--- Forget timers and remove this kind's systems.
function P.Stop(state)
    if state == nil then return end
    state.started = false
    state.near, state.due = {}, {}
    state.nextRefresh = 0.0
    local fx = state.groundFx
    if fx ~= nil and type(fx.StopKind) == "function" then pcall(fx.StopKind, state.kind) end
end

return P
