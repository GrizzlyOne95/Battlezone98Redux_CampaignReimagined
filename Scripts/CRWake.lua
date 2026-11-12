--**********************************************************************
-- CRWAKE: surface-appropriate ground kickup under low, moving vehicles and
-- under pilots on foot.
--
-- One shared, render-only module. A weather director owns it: it calls
-- Init() once, Update(dt) from its own Update and Stop() from its Shutdown.
-- It never touches gameplay, objects, AI or the network: every client works
-- out its own local view (so co-op needs no replication).
--
--   Wake.Init({ surface = "mars" })                  -- a fixed surface
--   Wake.Init({ surface = resolver,                  -- or per-craft
--               surfaces = { "water", "grass" } })   --   (payloads to load)
--       resolver(x, z, ground, y) -> surfaceName [, rateScale [, lift]]
--       (lift raises the systems above the terrain, for a water surface that
--       sits above the bed)
--   Wake.SetSurface("ice")        -- change the surface (name or resolver)
--   Wake.SetEnabled(false)        -- switch off (destroys every system)
--   Wake.SetQuality(0.5)          -- multiplies every emission rate
--   Wake.Update(dt)               -- seconds; the director's real-clock dt
--   Wake.Stop()                   -- destroy everything (call from Shutdown)
--
-- Surfaces: regolith (Moon), mars, ice (Europa), ganymede, water, grass
-- (Achilles), mud, sulfur (Io), ash (Venus). The regolith surface reuses
-- CR/Moon/HoverDust, which the Moon director has already loaded; every other
-- one lives in cr_wake.particle.payload, loaded here through
-- CRParticleTemplates.
--
-- PHYSICS AND AIM. Each profile carries the world's real gravity `g` and
-- whether it is a `vacuum`. Every mover's emitters are aimed at run time (exu
-- emitter direction / velocity / time-to-live, no-ops when the API is missing):
-- the fine sheet leaves low and trails BEHIND the mover, the chips leave higher.
-- In a vacuum the time-to-live is the ballistic flight time 2*v*sin(el)/g, so a
-- grain lands as it fades instead of hanging. A pilot on foot ("foot" mode, a
-- separate system pool entry) emits only while walking close to the ground, has
-- no idle emission, a small sprite, and a launch speed capped so the apex stays
-- under FootApex (0.6 m): dust never reaches the eyes of the player it follows.
--
-- LOAD BUDGET (the user's hard requirement: only craft the player can see)
--   * craft are scanned at most 4 times a second, never per frame;
--   * only craft within TrackRange (default 140 m) of the viewpoint (the EXU
--     camera when it reports one, else the local player's craft) are looked
--     at, and craft behind the camera are skipped when the camera reports a
--     facing (CullBehind);
--   * at most MaxSystems particle systems (default 4, hard max 6) exist at
--     once across ALL surfaces (pilots on foot included), given to the nearest
--     mover first, the local player's own pilot always first;
--   * a craft that stops is silenced, lingers, and its system is reused by
--     the next craft that needs one before anything new is created;
--   * emission fades with distance and scales with Quality; the templates
--     carry quotas of a few dozen particles.
--
-- It fails closed: no EXU / no particle API / missing payload is a no-op, and
-- any Lua error disables the module (and destroys its systems) after one
-- log line, like CRSplash.
--
-- Named CRWake: module names are shared across mods and the asset searcher
-- truncates them to 11 characters.
--**********************************************************************
local okExu, exu = pcall(require, "exu")
if not okExu then exu = nil end

local V = {}

-- =============================================================================
-- Tuning
-- =============================================================================

V.Enabled         = true
V.Debug           = false
V.Quality         = 1.0      -- multiplies every emission rate (0 = no particles)

V.ScanInterval    = 0.25     -- seconds between scans (never faster than 4 Hz)
V.TrackRange      = 140.0    -- craft further than this from the viewpoint are ignored
V.MaxSystems      = 4        -- every particle system, all surfaces, at once
V.HardMaxSystems  = 6
V.CullBehind      = true     -- skip craft behind the camera (needs the EXU camera)
V.BehindDot       = -0.25    -- cosine below which a craft counts as behind the camera
V.BehindNear      = 25.0     -- ... but craft this close are always kept (dust drifts into view)
V.FadeStart       = 0.65     -- share of TrackRange where emission starts to fade out
V.MaxCameraOffset = 600.0    -- a camera further than this from the player is not trusted
V.MaxFailuresPerTemplate = 3

-- Hover gating (the Moon's proven numbers).
V.MaxHeight       = 7.0      -- above this the thrusters do not reach the ground
V.MinSpeed        = 2.5      -- units/second; slower craft only emit the idle share
V.FullSpeed       = 28.0
V.IdleShare       = 0.20     -- share of the rate a craft emits just after slowing down
V.IdleMaxHeight   = 3.0      -- ... and only when this close to the ground
V.IdleGrace       = 6.0      -- ... and only this long after it last moved
V.Linger          = 4.0      -- a silent system is destroyed after this long
V.RateOverride    = nil      -- a number replaces every profile's full-speed rate

-- Aiming (see the header). Directions are unit vectors built from `back`, the
-- horizontal unit vector opposite the velocity.
V.AimMinTurn      = 0.985    -- cosine: re-aim only after turning more than ~10 degrees ...
V.AimMinSpeedStep = 0.15     -- ... or after the speed changed by this share (min 1 m/s)
V.VelocitySpread  = 0.30     -- launch speed range is +/- this share
V.MinTTL          = 0.6      -- ballistic flight time clamp (vacuum craft, pilots), seconds
V.MaxTTL          = 4.0
V.SheetUp         = 0.35     -- sheet direction  = back + up * SheetUp
V.ChipBack        = 0.6      -- chip direction   = back * ChipBack + up

-- Pilots on foot (every surface).
V.FootMinSpeed    = 1.0      -- below this a pilot emits nothing (no idle emission)
V.FootMaxHeight   = 1.2      -- only while this close to the terrain (covers a mid-body origin; the puff itself sits on the terrain)
V.FootRateShare   = 0.12     -- of the profile rate
V.FootSize        = 0.3      -- sprite size, metres (0.25 - 0.35)
V.FootApex        = 0.6      -- no grain rises higher than this above its launch
V.FootBox         = 0.5      -- emitter Box width/depth around the boots
V.FootAngle       = 20.0     -- spread, degrees

-- Surface profiles. `shares` are the per-emitter shares of the rate (emitter
-- index = position - 1). `accent` is an optional flat second system, created
-- only when a slot is spare. `payload` is the extra payload to load (nil = the
-- director already loaded it).
--
-- `g` is the world's real surface gravity (m/s^2) and `vacuum` is true where
-- there is no air to billow or hang the dust. `fall` (default g) is the downward
-- acceleration the TEMPLATE actually applies where it is deliberately softer
-- than g (light grass bits, ash in dense air); keep it equal to the template's
-- LinearForce. `aim = false` leaves a template's own emitters alone (water).
V.Profiles = {
    regolith = { template = "CR/Moon/HoverDust", shares = { 1.0, 0.35 }, rate = 30.0, g = 1.62, vacuum = true },
    ganymede = { template = "CRWake/GanymedeSpray", payload = "cr_wake", shares = { 1.0, 0.45 }, rate = 28.0,
                 g = 1.43, vacuum = true },
    ice      = { template = "CRWake/IceSpray", payload = "cr_wake", shares = { 1.0, 0.40 }, rate = 28.0,
                 g = 1.31, vacuum = true },
    sulfur   = { template = "CRWake/SulfurDust", payload = "cr_wake", shares = { 1.0, 0.40 }, rate = 28.0,
                 g = 1.80, vacuum = true },
    mars     = { template = "CRWake/MarsDust", payload = "cr_wake", shares = { 1.0, 0.45 }, rate = 50.0,
                 g = 3.71, vacuum = false },
    ash      = { template = "CRWake/AshDust", payload = "cr_wake", shares = { 1.0, 0.40 }, rate = 50.0,
                 g = 8.87, vacuum = false, fall = 2.4 },
    water    = { template = "CRWake/WaterSpray", payload = "cr_wake", shares = { 1.0, 0.60 }, rate = 45.0,
                 accent = "CRWake/WaterRing", accentShare = 0.35, g = 9.81, vacuum = false, aim = false, fall = 7.0 },
    mud      = { template = "CRWake/MudClods", payload = "cr_wake", shares = { 1.0, 0.50 }, rate = 42.0,
                 g = 9.81, vacuum = false },
    grass    = { template = "CRWake/GrassBits", payload = "cr_wake", shares = { 1.0, 0.40 }, rate = 40.0,
                 g = 9.81, vacuum = false, fall = 6.0 },
}

-- =============================================================================
-- State
-- =============================================================================

V.Initialized = false
V.Disabled    = false     -- set after a Lua error; cleared by Init
V.Usable      = false     -- EXU particle API present
V.Surface     = nil       -- name or resolver
V.Avail       = {}        -- surface name -> true when its templates can be created
V.Failures    = {}        -- template -> failed creates
V.Clock       = 0.0
V.NextScan    = 0.0
V.ScanId      = 0
V.Serial      = 0
V.Count       = 0         -- live particle systems
V.Sys         = {}        -- name -> { name, template, kind, mode, profile, owner, rate, shares, idleSince, stamp, aim state }
V.Craft       = {}        -- handle -> { main = sys, accent = sys }
V.Moved       = {}        -- handle -> last time it moved faster than MinSpeed
V.Player      = nil       -- the local player's handle (set by ReadViewpoint)
V.Stats       = { scans = 0, tracked = 0, created = 0, destroyed = 0, errors = 0, lastSelected = 0 }

-- Scratch, reused every scan so a scan allocates nothing per craft.
V.Sel         = {}        -- nearest-first selection, V.SelN long
V.SelN        = 0
V.Free        = {}        -- unused candidate records
V.View        = { x = 0.0, z = 0.0, fx = 0.0, fz = 0.0, facing = false }

-- =============================================================================
-- Helpers
-- =============================================================================

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function Log(message)
    if V.Debug then print("CRWake: " .. tostring(message)) end
end

local function Vec(x, y, z)
    if type(SetVector) == "function" then return SetVector(x, y, z) end
    return { x = x, y = y, z = z }
end

local function Call(name, ...)
    if exu == nil or type(exu[name]) ~= "function" then return nil end
    local ok, result = pcall(exu[name], ...)
    if not ok then
        Log("exu." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

-- Engine vectors are userdata; read them without building a table.
local function Fields3(p) return p.x, p.y, p.z end

local function ValidHandle(h)
    if h == nil then return false end
    if type(IsValid) == "function" then
        local ok, valid = pcall(IsValid, h)
        return ok and valid and true or false
    end
    return true
end

local function IsPersonHandle(h)
    if type(IsPerson) ~= "function" then return false end
    local ok, person = pcall(IsPerson, h)
    return ok and person and true or false
end

local function XYZ(h)
    if type(GetPosition) ~= "function" then return nil end
    local ok, p = pcall(GetPosition, h)
    if not ok or p == nil then return nil end
    local okf, x, y, z = pcall(Fields3, p)
    if okf and type(x) == "number" and type(z) == "number" then return x, tonumber(y) or 0.0, z end
    return nil
end

local function TerrainHeight(x, z)
    if type(GetTerrainHeightAndNormal) ~= "function" then return nil end
    local ok, height = pcall(GetTerrainHeightAndNormal, Vec(x, 0.0, z))
    if ok and type(height) == "number" then return height end
    return nil
end

local function CameraFields(m) return m.posit_x, m.posit_y, m.posit_z, m.front_x, m.front_z end

-- The viewpoint (camera when EXU reports one, else the player's craft) written
-- into V.View. Returns false when neither is known.
local function ReadViewpoint()
    local view = V.View
    view.facing = false
    local player = nil
    if type(GetPlayerHandle) == "function" then
        local ok, h = pcall(GetPlayerHandle)
        if ok and ValidHandle(h) then player = h end
    end
    V.Player = player
    local px, pz
    if player ~= nil then
        local x, _, z = XYZ(player)
        if x ~= nil then px, pz = x, z end
    end
    local m = Call("GetCameraTransformMatrix")
    if m ~= nil then
        local ok, cx, _, cz, fx, fz = pcall(CameraFields, m)
        if ok and type(cx) == "number" and type(cz) == "number" then
            local trusted = true
            if px ~= nil then
                local dx, dz = cx - px, cz - pz
                trusted = ((dx * dx) + (dz * dz)) <= (V.MaxCameraOffset * V.MaxCameraOffset)
            end
            if trusted then
                view.x, view.z = cx, cz
                if type(fx) == "number" and type(fz) == "number" then
                    local len = math.sqrt((fx * fx) + (fz * fz))
                    if len > 0.001 then
                        view.fx, view.fz, view.facing = fx / len, fz / len, true
                    end
                end
                return true
            end
        end
    end
    if px == nil then return false end
    view.x, view.z = px, pz
    return true
end

-- =============================================================================
-- Particle systems (budgeted, pooled)
-- =============================================================================

local function Destroy(s)
    if s == nil or V.Sys[s.name] ~= s then return end
    Call("DestroyParticleSystem", s.name)
    V.Sys[s.name] = nil
    V.Count = V.Count - 1
    V.Stats.destroyed = V.Stats.destroyed + 1
    if s.owner ~= nil then
        local c = V.Craft[s.owner]
        if c ~= nil then
            if c.main == s then c.main = nil end
            if c.accent == s then c.accent = nil end
            if c.main == nil and c.accent == nil then V.Craft[s.owner] = nil end
        end
    end
end

local function Create(template, kind, shares, mode, x, y, z)
    if (V.Failures[template] or 0) >= V.MaxFailuresPerTemplate then return nil end
    V.Serial = V.Serial + 1
    local name = "cr_wake_" .. tostring(V.Serial)
    if Call("CreateParticleSystem", name, template, Vec(x, y, z)) ~= true then
        local failures = (V.Failures[template] or 0) + 1
        V.Failures[template] = failures
        if failures >= V.MaxFailuresPerTemplate then
            print("CRWake: " .. template .. " disabled after " .. tostring(failures) ..
                " failed particle creates (template unavailable)")
        end
        return nil
    end
    V.Failures[template] = 0
    Call("SetParticleSystemKeepLocalSpace", name, false)
    Call("SetParticleSystemNonVisibleUpdateTimeout", name, 3.0)
    local s = { name = name, template = template, kind = kind, mode = mode, profile = nil, owner = nil,
                rate = 0.0, shares = shares, idleSince = nil, stamp = 0 }
    if mode == "foot" then
        -- A pilot's system is small and tight around the boots; it keeps these for life
        -- (a system is only ever reused for the same template AND mode).
        Call("SetParticleSystemDefaultDimensions", name, V.FootSize, V.FootSize)
        for i = 0, #shares - 1 do
            Call("SetParticleEmitterParameter", name, i, "width", V.FootBox)
            Call("SetParticleEmitterParameter", name, i, "height", 0.1)
            Call("SetParticleEmitterParameter", name, i, "depth", V.FootBox)
            Call("SetParticleEmitterAngle", name, i, V.FootAngle)
        end
    end
    V.Sys[name] = s
    V.Count = V.Count + 1
    V.Stats.created = V.Stats.created + 1
    return s
end

-- Silent systems waiting out their linger are the pool: a same-template one is
-- reused before anything is created, and any of them is sacrificed when the
-- cap is reached. "Stale" systems (not refreshed by this scan) count as silent:
-- their craft was not selected. A main system may also take an accent's slot.
local function Acquire(template, kind, shares, mode, x, y, z)
    local best = nil
    for _, s in pairs(V.Sys) do
        if (s.idleSince ~= nil or s.stamp ~= V.ScanId) and s.template == template and s.mode == mode then
            if best == nil or (s.idleSince or -1.0) < (best.idleSince or -1.0) then best = s end
        end
    end
    if best ~= nil then return best end
    if V.Count < V.MaxSystems then return Create(template, kind, shares, mode, x, y, z) end

    local idle, stale, accent = nil, nil, nil
    for _, s in pairs(V.Sys) do
        if s.idleSince ~= nil then
            if idle == nil or s.idleSince < idle.idleSince then idle = s end
        elseif s.stamp ~= V.ScanId then
            stale = stale or s
        elseif kind == "main" and s.kind == "accent" then
            accent = accent or s
        end
    end
    local victim = idle or stale or accent
    if victim == nil then return nil end
    Destroy(victim)
    return Create(template, kind, shares, mode, x, y, z)
end

local function SetRate(s, rate)
    if rate <= 0.0 then
        if s.rate <= 0.0 then return end
        rate = 0.0
    elseif math.abs(rate - s.rate) <= 0.5 then
        return
    end
    s.rate = rate
    local shares = s.shares
    for i = 1, #shares do
        Call("SetParticleEmitterEmissionRate", s.name, i - 1, rate * shares[i])
    end
end

local function Attach(s, h)
    if s.owner ~= h then
        if s.owner ~= nil then
            local old = V.Craft[s.owner]
            if old ~= nil then
                if old.main == s then old.main = nil end
                if old.accent == s then old.accent = nil end
                if old.main == nil and old.accent == nil then V.Craft[s.owner] = nil end
            end
        end
        s.owner = h
        s.aimSpeed, s.bx, s.bz = nil, nil, nil   -- a new mover: aim from scratch
    end
    s.idleSince = nil
    s.stamp = V.ScanId
end

-- Aim a mover's two emitters (0 = fine sheet, 1 = chips) by its velocity. Only
-- called with a live system; throttled to real changes of heading or speed.
-- Pilots on foot launch both emitters like chips, capped so the apex of the
-- fastest grain stays under FootApex.
local function Aim(s, c)
    local foot = s.mode == "foot"
    local profile = s.profile
    if profile == nil or (profile.aim == false and not foot) then return end
    local speed = c.speed
    if speed > 0.05 and (foot or speed >= V.MinSpeed) then
        s.bx, s.bz = -c.vx / speed, -c.vz / speed
    elseif s.bx == nil then
        if speed > 0.05 then s.bx, s.bz = -c.vx / speed, -c.vz / speed else s.bx, s.bz = 1.0, 0.0 end
    end
    if s.aimSpeed ~= nil then
        local turned = (s.bx * s.abx) + (s.bz * s.abz) < V.AimMinTurn
        local stepped = math.abs(speed - s.aimSpeed) > math.max(1.0, V.AimMinSpeedStep * s.aimSpeed)
        if not (turned or stepped) then return end
    end
    s.abx, s.abz, s.aimSpeed = s.bx, s.bz, speed

    local gTtl = foot and (profile.fall or profile.g) or profile.g
    local ballistic = foot or profile.vacuum
    for i = 0, #s.shares - 1 do
        local sheet = (i == 0) and not foot
        local k, up, v
        if sheet then
            k, up = 1.0, V.SheetUp
            v = Clamp(2.0 + (0.35 * speed), 2.0, 12.0)
        else
            k, up = V.ChipBack, 1.0
            v = Clamp(2.5 + (0.25 * speed), 2.5, 9.0)
        end
        if foot then
            -- apex = (v sin)^2 / 2g <= (vmax)^2 / 2g = FootApex, with vmax the fastest grain
            local vmax = math.sqrt(2.0 * (profile.fall or profile.g) * V.FootApex)
            v = math.min(v, vmax / (1.0 + V.VelocitySpread))
        end
        local len = math.sqrt((k * k) + (up * up))
        Call("SetParticleEmitterDirection", s.name, i, Vec(s.bx * k / len, up / len, s.bz * k / len))
        Call("SetParticleEmitterVelocity", s.name, i, v * (1.0 - V.VelocitySpread), v * (1.0 + V.VelocitySpread))
        if ballistic then
            local t = Clamp(2.0 * v * (up / len) / gTtl, V.MinTTL, V.MaxTTL)
            Call("SetParticleEmitterTimeToLive", s.name, i, t * 0.8, t * 1.2)
        end
    end
end

local function DestroyAll()
    local list = {}
    for _, s in pairs(V.Sys) do list[#list + 1] = s end
    for i = 1, #list do Destroy(list[i]) end
    V.Sys, V.Craft, V.Moved = {}, {}, {}
    V.Count = 0
    V.SelN = 0
end

-- =============================================================================
-- Scan
-- =============================================================================

local function RateOf(speed, height, movedAgo, base)
    if height > V.MaxHeight then return 0.0 end
    local near = 1.0 - Clamp(height / V.MaxHeight, 0.0, 1.0)
    local rate = 0.0
    if speed >= V.MinSpeed then
        rate = base * Clamp(speed / V.FullSpeed, 0.1, 1.0) * (0.35 + (0.65 * near))
    elseif height <= V.IdleMaxHeight and movedAgo <= V.IdleGrace then
        rate = base * V.IdleShare * near
    end
    return rate * V.Quality
end

local function FadeOf(d)
    local start = V.TrackRange * V.FadeStart
    if d <= start then return 1.0 end
    return Clamp((V.TrackRange - d) / (V.TrackRange - start), 0.0, 1.0)
end

local function VelFields(v) return v.x, v.z end

local function ResolveSurface(x, z, ground, y)
    local surface = V.Surface
    if type(surface) == "function" then
        local ok, name, scale, lift = pcall(surface, x, z, ground, y)
        if not ok then return nil end
        return name, tonumber(scale) or 1.0, tonumber(lift) or 0.0
    end
    return surface, 1.0, 0.0
end

local function Offer(h, d, x, y, z)
    local cap = V.MaxSystems
    local n = V.SelN
    local sel = V.Sel
    -- The local player's own pilot ranks ahead of every other mover.
    local key = (h == V.Player) and 0.0 or d
    -- Already holding a full set of nearer craft: nothing to gain.
    if n >= cap and key >= sel[n].d then return end

    local free = V.Free
    local top = #free
    if top == 0 then return end

    if type(GetVelocity) ~= "function" then return end
    local okv, vel = pcall(GetVelocity, h)
    if not okv or vel == nil then return end
    local okf, vx, vz = pcall(VelFields, vel)
    if not okf or type(vx) ~= "number" or type(vz) ~= "number" then return end
    local speed = math.sqrt((vx * vx) + (vz * vz))
    local person = IsPersonHandle(h)
    if person then
        -- On foot: nothing while standing (no idle emission), nothing off the ground.
        if speed < V.FootMinSpeed then return end
    else
        if speed >= V.MinSpeed then V.Moved[h] = V.Clock end
    end
    local movedAgo = V.Clock - (V.Moved[h] or -1000.0)
    -- A parked craft that has not moved lately costs nothing more.
    if not person and speed < V.MinSpeed and movedAgo > V.IdleGrace then return end

    local ground = TerrainHeight(x, z)
    if ground == nil then return end
    local height = y - ground
    if height > (person and V.FootMaxHeight or V.MaxHeight) then return end

    local surface, scale, lift = ResolveSurface(x, z, ground, y)
    local profile = surface and V.Profiles[surface]
    if profile == nil or not V.Avail[surface] then return end

    local base = V.RateOverride or profile.rate
    local rate
    if person then
        rate = base * V.FootRateShare * Clamp(speed / 6.0, 0.25, 1.0) * V.Quality * FadeOf(d) * scale
    else
        rate = RateOf(speed, height, movedAgo, base) * FadeOf(d) * scale
    end
    if rate <= 0.01 then return end

    local rec = free[top]
    free[top] = nil
    rec.h, rec.d, rec.x, rec.z, rec.ground, rec.rate, rec.profile = h, key, x, z, ground + lift, rate, profile
    rec.vx, rec.vz, rec.speed, rec.mode = vx, vz, speed, person and "foot" or "craft"

    local i = n
    while i >= 1 and sel[i].d > key do i = i - 1 end
    local pos = i + 1
    if n >= cap then
        local evicted = sel[cap]
        free[#free + 1] = evicted
        for k = cap, pos + 1, -1 do sel[k] = sel[k - 1] end
        sel[pos] = rec
    else
        for k = n + 1, pos + 1, -1 do sel[k] = sel[k - 1] end
        sel[pos] = rec
        V.SelN = n + 1
    end
end

local ACCENT_SHARES = { 1.0 }

local function Scan()
    V.Stats.scans = V.Stats.scans + 1
    V.ScanId = V.ScanId + 1

    -- Return last scan's records to the free list.
    local free = V.Free
    for i = 1, V.SelN do
        free[#free + 1] = V.Sel[i]
        V.Sel[i] = nil
    end
    V.SelN = 0

    local view = V.View
    if type(AllCraft) == "function" and ReadViewpoint() then
        local okIt, iterator = pcall(AllCraft)
        if okIt and type(iterator) == "function" then
            local range2 = V.TrackRange * V.TrackRange
            local near2 = V.BehindNear * V.BehindNear
            local cull = V.CullBehind and view.facing
            for h in iterator do
                if ValidHandle(h) then
                    local x, y, z = XYZ(h)
                    if x ~= nil then
                        local dx, dz = x - view.x, z - view.z
                        local d2 = (dx * dx) + (dz * dz)
                        if d2 <= range2 then
                            local keep = true
                            if cull and d2 > near2 then
                                local dot = ((dx * view.fx) + (dz * view.fz)) / math.sqrt(d2)
                                if dot < V.BehindDot then keep = false end
                            end
                            if keep then Offer(h, math.sqrt(d2), x, y, z) end
                        end
                    end
                end
            end
        end
    end
    V.Stats.lastSelected = V.SelN

    -- Claim what the selected craft already hold, so no other craft takes it.
    local sel = V.Sel
    for i = 1, V.SelN do
        local held = V.Craft[sel[i].h]
        if held ~= nil then
            if held.main ~= nil then held.main.stamp, held.main.idleSince = V.ScanId, nil end
        end
    end

    -- Main systems for the nearest craft first.
    for i = 1, V.SelN do
        local c = sel[i]
        local profile = c.profile
        local rec = V.Craft[c.h]
        local s = rec and rec.main
        if s ~= nil and (s.template ~= profile.template or s.mode ~= c.mode) then
            -- The surface changed under the craft: let the old one go quiet.
            SetRate(s, 0.0)
            s.idleSince = V.Clock
            s.owner = nil
            rec.main = nil
            if rec.accent == nil then V.Craft[c.h] = nil end
            s = nil
        end
        if s == nil then
            s = Acquire(profile.template, "main", profile.shares, c.mode, c.x, c.ground + 0.2, c.z)
            if s ~= nil then
                if V.Craft[c.h] == nil then V.Craft[c.h] = {} end
                s.profile = profile
                s.shares = profile.shares
                Attach(s, c.h)
                V.Craft[c.h].main = s
                V.Stats.tracked = V.Stats.tracked + 1
            end
        else
            s.stamp = V.ScanId
            s.idleSince = nil
        end
        if s ~= nil then
            Call("SetParticleSystemPosition", s.name, Vec(c.x, c.ground + 0.2, c.z))
            Aim(s, c)
            SetRate(s, c.rate)
        end
        c.main = s
    end

    -- Accents (flat wake rings) only with a spare slot, and never for a pilot on foot.
    for i = 1, V.SelN do
        local c = sel[i]
        local profile = c.profile
        local rec = V.Craft[c.h]
        local a = rec and rec.accent
        if a ~= nil and (a.template ~= profile.accent or c.main == nil) then a = nil end
        if profile.accent ~= nil and c.main ~= nil and c.mode == "craft" then
            if a == nil and V.Count < V.MaxSystems then
                a = Create(profile.accent, "accent", ACCENT_SHARES, "craft", c.x, c.ground + 0.1, c.z)
                if a ~= nil then
                    if V.Craft[c.h] == nil then V.Craft[c.h] = {} end
                    Attach(a, c.h)
                    V.Craft[c.h].accent = a
                end
            end
            if a ~= nil then
                a.stamp = V.ScanId
                a.idleSince = nil
                Call("SetParticleSystemPosition", a.name, Vec(c.x, c.ground + 0.1, c.z))
                SetRate(a, c.rate * (profile.accentShare or 0.35))
            end
        end
    end

    -- Everything not refreshed this scan goes quiet, lingers, then is destroyed.
    local drop = nil
    for _, s in pairs(V.Sys) do
        if s.stamp ~= V.ScanId then
            if s.idleSince == nil then
                SetRate(s, 0.0)
                s.idleSince = V.Clock
            end
            if (V.Clock - s.idleSince) >= V.Linger or (s.owner ~= nil and not ValidHandle(s.owner)) then
                drop = drop or {}
                drop[#drop + 1] = s
            end
        end
    end
    if drop ~= nil then
        for i = 1, #drop do Destroy(drop[i]) end
    end

    -- Forget craft that have not moved for a long while (or are gone).
    for h, at in pairs(V.Moved) do
        if (V.Clock - at) > (V.IdleGrace * 5.0) or not ValidHandle(h) then V.Moved[h] = nil end
    end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

local function EnsurePayloads(surfaces)
    local wanted, seen = {}, {}
    for _, name in ipairs(surfaces) do
        local profile = V.Profiles[name]
        if profile ~= nil then
            if profile.payload == nil then
                V.Avail[name] = true
            elseif seen[profile.payload] == nil then
                seen[profile.payload] = false
                wanted[#wanted + 1] = profile.payload
            end
        end
    end
    if #wanted > 0 then
        local okT, templates = pcall(require, "CRParticleTemplates")
        if okT and type(templates) == "table" and type(templates.EnsureExtra) == "function" then
            for _, payload in ipairs(wanted) do
                local ok, ready, reason = pcall(templates.EnsureExtra, payload)
                if ok and ready then
                    seen[payload] = true
                else
                    print("CRWake: " .. payload .. " particle templates unavailable (" ..
                        tostring(ok and reason or ready) .. "); vehicle wakes are off for those surfaces")
                end
            end
        end
    end
    for _, name in ipairs(surfaces) do
        local profile = V.Profiles[name]
        if profile ~= nil and profile.payload ~= nil and seen[profile.payload] == true then
            V.Avail[name] = true
        end
    end
end

local TUNING_KEYS = {
    trackRange = "TrackRange", maxHeight = "MaxHeight", minSpeed = "MinSpeed", fullSpeed = "FullSpeed",
    idleShare = "IdleShare", idleMaxHeight = "IdleMaxHeight", idleGrace = "IdleGrace", linger = "Linger",
    interval = "ScanInterval", rate = "RateOverride", maxSystems = "MaxSystems", cullBehind = "CullBehind",
    maxCameraOffset = "MaxCameraOffset",
}

-- options:
--   surface      a surface name (regolith mars ice ganymede water grass mud
--                sulfur ash), or a resolver function(x, z, ground, y) ->
--                name [, rateScale]
--   surfaces     the names a resolver may return (their payloads are loaded)
--   enabled, debug, quality
--   maxSystems   system cap (default 4, clamped to 1..6)
--   trackRange   metres from the viewpoint (default 140)
--   tuning       table of overrides: trackRange maxHeight minSpeed fullSpeed
--                idleShare idleMaxHeight idleGrace linger interval rate
--                maxSystems cullBehind maxCameraOffset
-- Returns true when the module can draw anything.
function V.Init(options)
    if V.Initialized then V.Stop() end
    options = options or {}

    V.Disabled = false
    V.Avail = {}
    V.Failures = {}
    V.Clock, V.NextScan, V.ScanId, V.LastReal = 0.0, 0.0, 0, nil
    V.Stats = { scans = 0, tracked = 0, created = 0, destroyed = 0, errors = 0, lastSelected = 0 }
    V.Sys, V.Craft, V.Moved = {}, {}, {}
    V.Count = 0

    if options.enabled ~= nil then V.Enabled = options.enabled and true or false end
    if options.debug ~= nil then V.Debug = options.debug and true or false end
    if options.quality ~= nil then V.Quality = math.max(0.0, tonumber(options.quality) or 1.0) end
    local tuning = type(options.tuning) == "table" and options.tuning or {}
    for key, field in pairs(TUNING_KEYS) do
        local value = tuning[key]
        if value ~= nil then
            if type(V[field]) == "boolean" then V[field] = value and true or false
            else V[field] = tonumber(value) or V[field] end
        end
    end
    if options.maxSystems ~= nil then V.MaxSystems = tonumber(options.maxSystems) or V.MaxSystems end
    if options.trackRange ~= nil then V.TrackRange = tonumber(options.trackRange) or V.TrackRange end
    V.MaxSystems = math.floor(Clamp(V.MaxSystems, 1, V.HardMaxSystems))
    V.TrackRange = Clamp(V.TrackRange, 20.0, 300.0)
    V.ScanInterval = math.max(0.25, V.ScanInterval)

    V.Free = {}
    for i = 1, V.MaxSystems + 1 do
        V.Free[i] = { h = nil, d = 0.0, x = 0.0, z = 0.0, ground = 0.0, rate = 0.0, profile = nil, main = nil,
                      vx = 0.0, vz = 0.0, speed = 0.0, mode = "craft" }
    end
    V.Sel, V.SelN = {}, 0

    V.Surface = options.surface
    V.Usable = exu ~= nil and type(exu.CreateParticleSystem) == "function"
        and type(exu.DestroyParticleSystem) == "function"
    V.Initialized = true
    if not V.Usable then
        Log("EXU particle API unavailable; vehicle wakes are off")
        return false
    end

    local names = {}
    if type(options.surface) == "string" then names[#names + 1] = options.surface end
    if type(options.surfaces) == "table" then
        for _, name in ipairs(options.surfaces) do names[#names + 1] = name end
    end
    EnsurePayloads(names)
    local any = false
    for _ in pairs(V.Avail) do any = true break end
    return any
end

function V.SetSurface(surface)
    V.Surface = surface
    if type(surface) == "string" and V.Profiles[surface] ~= nil and not V.Avail[surface] and V.Initialized then
        EnsurePayloads({ surface })
    end
end

function V.SetEnabled(enabled)
    enabled = enabled and true or false
    if V.Enabled == enabled then return end
    V.Enabled = enabled
    if not enabled then DestroyAll() end
end

function V.SetQuality(quality)
    V.Quality = math.max(0.0, tonumber(quality) or 1.0)
end

function V.Stop()
    DestroyAll()
    V.Initialized = false
    V.Usable = false
    V.Surface = nil
    V.Avail = {}
end

-- Loading a save rebuilds the Ogre scene: every system is already gone.
function V.Reset()
    DestroyAll()
    V.NextScan = 0.0
end

-- Adapters may pass a fixed 1/TPS dt that is really a frame count, so take
-- elapsed time from GetTime when there is one (the other directors do too).
local function RealDelta(fallback)
    if type(GetTime) ~= "function" then return fallback end
    local ok, now = pcall(GetTime)
    if not ok or type(now) ~= "number" then return fallback end
    local last = V.LastReal
    V.LastReal = now
    if last == nil then return 0.0 end
    local delta = now - last
    if delta <= 0.0 or delta > 1.0 then return 0.0 end
    return delta
end

function V.Update(dt)
    if not (V.Initialized and V.Usable and V.Enabled) or V.Disabled then return end
    dt = tonumber(dt) or 0.0
    if dt <= 0.0 then return end
    dt = RealDelta(dt)
    if dt <= 0.0 then return end
    V.Clock = V.Clock + dt
    if V.Clock < V.NextScan then return end
    V.NextScan = V.Clock + V.ScanInterval

    local ok, err = pcall(Scan)
    if not ok then
        V.Disabled = true
        V.Stats.errors = V.Stats.errors + 1
        print("CRWake: disabled after error: " .. tostring(err))
        DestroyAll()
    end
end

function V.GetSystemCount() return V.Count end
function V.GetStats() return V.Stats end
function V.IsActive() return V.Initialized and V.Usable and V.Enabled and not V.Disabled end

function V.Describe()
    return string.format("wake systems %d/%d scans %d tracked %d", V.Count, V.MaxSystems,
        V.Stats.scans, V.Stats.tracked)
end

return V
