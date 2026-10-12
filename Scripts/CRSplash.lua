--**********************************************************************
-- CRSPLASH: rain splashes, puddles and dust puffs as Ogre particles.
--
-- The splashes were MakeExplosion calls, a ripple ring plus a crown of drops
-- per splash: in RAINHEAVY that was about 600 short-lived engine explosion
-- objects a second, each with its own renderer. Here a few particle systems
-- (the ISDF Chronicles tools/precipgen.py) do it:
--   ring    CRWX/SplashRing   ripples lying on the ground
--   crown   CRWX/SplashCrown  droplets thrown up by the nearer splashes
--   hull    CRWX/SplashHull   droplets bouncing off the player's craft
--   puddle  CRWX/Puddle       a spreading wet splat on flat ground, 1 a second
--   dust    CRWX/DustPuff     dust kicked off the ground and blown downwind
-- Ground systems have flat Box emitters; ten times a second each is moved to
-- a fresh patch of ground where the camera can see it and laid on the slope
-- (its direction is the ground normal), and emits there until the next move.
-- What it emitted stays in the world.
--
--   CRSplash.Set("rain", 0.8)     -- every Update while it rains
--   CRSplash.SetWind(1, 0, 30)    -- dust: sim-space direction (x, z), m/s
--
-- Set returns true while the particles draw that kind, false when they cannot
-- (no EXU, or one without particles), so callers keep their MakeExplosion
-- effects as the fallback. Several callers in a frame: the strongest request
-- wins. Kinds: "rain", "acid" (rain's splashes tinted green, no puddles),
-- "dust".
--
-- Named CRSplash, not splash: module names are shared across mods and the
-- asset searcher truncates them to 11 characters.
--
-- Port of the ISDF Chronicles isdfcsplash.lua.
--**********************************************************************
local splash = {}

local PREFIX = "crwx_splash_"
local TICK = 0.1             -- seconds between patch moves
local PUDDLE_TICK = 1.0      -- seconds between puddle spots
local IDLE_HIDE = 2          -- seconds after the last emission before a system hides
local FULL_RATE = 360        -- ripples a second at level 1 (RAINHEAVY's old 12 a frame at 30 fps)
local DROPS = 8              -- droplets per crown
local HULL_RATE = 70         -- droplets a second off the player's craft at level 1
local DUST_RATE = 24         -- dust puffs a second at level 1
local DUST_WIND = 0.15       -- share of the wind speed pushing the puffs (m/s^2 per m/s)
local FIRST_PERSON = { [1] = true, [2] = true, [3] = true } -- GetCameraView: cockpit, no cockpit, no HUD

-- Emitter counts match the ISDF Chronicles tools/precipgen.py.
local SYSTEMS = {
	ring   = { template = "CRWX/SplashRing", emitters = 12 },
	crown  = { template = "CRWX/SplashCrown", emitters = 6 },   -- on the ring's first (nearest) patches
	hull   = { template = "CRWX/SplashHull", emitters = 1 },
	puddle = { template = "CRWX/Puddle", emitters = 1 },
	dust   = { template = "CRWX/DustPuff", emitters = 8 },
}

local RAIN_COLOUR = { ring = { 0.85, 0.90, 0.95, 1.0 }, crown = { 0.86, 0.90, 0.95, 0.75 }, hull = { 0.86, 0.90, 0.95, 0.7 } }
local ACID_COLOUR = { ring = { 0.43, 1.00, 0.31, 1.0 }, crown = { 0.50, 1.00, 0.38, 0.75 }, hull = { 0.50, 1.00, 0.38, 0.7 } }
local KINDS = {
	rain = { ring = true, crown = true, hull = true, puddle = true, colour = RAIN_COLOUR },
	acid = { ring = true, crown = true, hull = true, colour = ACID_COLOUR },
	dust = { dust = true },
}

-- Where patches go, around the camera's flat forward direction. Near patches
-- (which also throw crowns) mix an arc ahead with a ring all round, so there
-- are splashes when looking down or aside; far patches fill the arc ahead.
local NEAR = { ahead = 0.65, half = 55, min = 5, max = 26, ringMin = 3, ringMax = 18 }
local FAR = { ahead = 1, half = 50, min = 24, max = 48 }
local DUST = { ahead = 0.75, half = 60, min = 8, max = 60, ringMin = 5, ringMax = 25 }
local PUDDLE = { ahead = 0.8, half = 60, min = 10, max = 70, ringMin = 8, ringMax = 40 }
local PUDDLE_FLAT = 0.995    -- normal.y: only on flat ground, where water would pool

-- Hull splash box over each craft (from its mesh bounds: about half the width
-- and 60% of the length, 80% of the way up). Unlisted craft get the default.
local HULLS = {
	default = { w = 2.2, l = 4.0, top = 1.55 },
	ivmisl  = { w = 3.3, l = 4.9, top = 1.85 },
}

local exu = nil
local ready = nil            -- nil = not tried, true = working, false = unavailable
local sys = {}               -- key -> live system
local frame, requests = nil, {}
local nextTick, nextPuddle = 0, 0
local kindNow = nil
local wetLevel = 0           -- rain or acid level applied last, for splash.WetLevel
local wind = { x = 1, z = 0, speed = 0, applied = nil }

-- EXU is a module in CR. A stub (isStub) means no native runtime: degrade silently.
local function findExu()
	local e = package and package.loaded and package.loaded["exu"]
	if type(e) ~= "table" then
		local ok, m = pcall(require, "exu")
		e = ok and m or nil
	end
	if type(e) == "table" and e.isStub ~= true then return e end
	return nil
end

-- Parses crwx_precip.particle.payload (and the other CR payloads) on demand.
local function ensureTemplates()
	local ok, templates = pcall(require, "CRParticleTemplates")
	if not ok or type(templates) ~= "table" or type(templates.Ensure) ~= "function" then return false end
	local ran, result = pcall(templates.Ensure)
	return ran and result == true
end

local REQUIRED = {
	"CreateParticleSystem", "DestroyParticleSystem", "SetParticleSystemPosition",
	"SetParticleEmitterEmissionRate", "SetParticleEmitterPosition", "SetParticleEmitterDirection",
	"SetParticleEmitterColor", "SetParticleSystemVisible",
}

local function call(fn, ...)
	if type(exu[fn]) ~= "function" then return nil end
	local ok, r = pcall(exu[fn], ...)
	return ok and r
end

local function create(key)
	local spec = SYSTEMS[key]
	local name = PREFIX .. key
	call("DetachParticleSystem", name)
	call("DestroyParticleSystem", name)
	if call("CreateParticleSystem", name, spec.template, GetPosition(GetPlayerHandle()) or SetVector(0, 0, 0)) ~= true then
		print("CRSplash: could not create " .. spec.template .. " (is crwx_precip.particle.payload loaded?)")
		return nil
	end
	call("SetParticleSystemKeepLocalSpace", name, false)
	call("SetParticleSystemVisible", name, false)
	local s = { key = key, name = name, count = spec.emitters, rate = 0, visible = false, dirs = {}, idleSince = nil }
	for e = 0, s.count - 1 do call("SetParticleEmitterEmissionRate", name, e, 0) end
	return s
end

-- Every system a kind needs, created on first use. False if any fails, and
-- then the ones made for it are removed again.
local function systemsFor(kind)
	local made = {}
	for key in pairs(SYSTEMS) do
		if KINDS[kind][key] and sys[key] == nil then
			local s = create(key)
			if s == nil then
				for _, k in ipairs(made) do call("DestroyParticleSystem", sys[k].name); sys[k] = nil end
				return false
			end
			sys[key] = s
			made[#made + 1] = key
		end
	end
	return true
end

local function init()
	exu = findExu()
	if exu == nil then return false end
	for _, fn in ipairs(REQUIRED) do
		if type(exu[fn]) ~= "function" then return false end
	end
	return ensureTemplates()
end

local function setVisible(s, v)
	if s.visible ~= v then call("SetParticleSystemVisible", s.name, v); s.visible = v end
end

local function setRate(s, perEmitter)
	if s.rate == perEmitter then return end
	if perEmitter > 0 and s.rate > 0 and math.abs(perEmitter - s.rate) <= s.rate * 0.03 then return end
	for e = 0, s.count - 1 do call("SetParticleEmitterEmissionRate", s.name, e, perEmitter) end
	s.rate = perEmitter
	if perEmitter > 0 then s.idleSince = nil; setVisible(s, true) end
end

local function setColour(kind)
	local c = KINDS[kind].colour
	if c == nil then return end
	for key, col in pairs(c) do
		local s = sys[key]
		if s then
			for e = 0, s.count - 1 do call("SetParticleEmitterColor", s.name, e, col[1], col[2], col[3], col[4]) end
		end
	end
end

local function flatFront(player)
	local f = GetFront(player)
	if f ~= nil then
		local len = math.sqrt(f.x * f.x + f.z * f.z)
		if len > 0.001 then return f.x / len, f.z / len end
	end
	return 0, 1
end

-- A random spot around the camera: in the arc ahead (area-weighted, so spots
-- spread evenly instead of bunching near) or in a ring all round.
local function spot(area)
	if math.random() < area.ahead then
		local a = math.rad(math.random() * 2 * area.half - area.half)
		return a, math.sqrt(area.min ^ 2 + math.random() * (area.max ^ 2 - area.min ^ 2))
	end
	return math.random() * 2 * math.pi, math.sqrt(area.ringMin ^ 2 + math.random() * (area.ringMax ^ 2 - area.ringMin ^ 2))
end

-- The ground at a spot, as an offset from pos in render space (z negated) and
-- its normal in render space; nil where there is no floor.
local probe = nil             -- made on first use: no BZ API calls at require time
local function ground(pos, fx, fz, a, d)
	if probe == nil then probe = SetVector(0, 0, 0) end
	local ca, sa = math.cos(a), math.sin(a)
	local dx, dz = (fx * ca - fz * sa) * d, (fx * sa + fz * ca) * d
	probe.x, probe.y, probe.z = pos.x + dx, pos.y + 5, pos.z + dz
	-- Floor, not terrain: splashes on rooftops too.
	local h, n = GetFloorHeightAndNormal(probe)
	if h == nil then return nil end
	local nx, ny, nz = 0, 1, 0
	if n ~= nil and n.y > 0.2 then nx, ny, nz = n.x, n.y, -n.z end
	return SetVector(dx, h + 0.05 - pos.y, -dz), nx, ny, nz
end

local function place(s, e, at, nx, ny, nz)
	call("SetParticleEmitterPosition", s.name, e, at)
	-- The normal barely changes on flat ground: only re-aim when it does.
	local last = s.dirs[e]
	if last == nil or math.abs(last[1] - nx) + math.abs(last[2] - ny) + math.abs(last[3] - nz) > 0.03 then
		call("SetParticleEmitterDirection", s.name, e, SetVector(nx, ny, nz))
		s.dirs[e] = { nx, ny, nz }
	end
end

-- Move the ground patches of the systems in use. Emitter positions are local
-- to each system's node, which is put at the player first.
local function relocate(kind, pos, fx, fz)
	local k = KINDS[kind]
	if k.ring then
		call("SetParticleSystemPosition", sys.ring.name, pos)
		call("SetParticleSystemPosition", sys.crown.name, pos)
		for e = 0, sys.ring.count - 1 do
			local near = e < sys.crown.count
			local at, nx, ny, nz = ground(pos, fx, fz, spot(near and NEAR or FAR))
			if at then
				place(sys.ring, e, at, nx, ny, nz)
				if near then place(sys.crown, e, at, nx, ny, nz) end
			end
		end
	end
	if k.dust then
		call("SetParticleSystemPosition", sys.dust.name, pos)
		for e = 0, sys.dust.count - 1 do
			local at, nx, ny, nz = ground(pos, fx, fz, spot(DUST))
			if at then place(sys.dust, e, at, nx, ny, nz) end
		end
	end
end

-- One puddle a second, at a flat spot in view; none when the spot is sloped.
local function puddle(level, pos, fx, fz)
	local at, nx, ny, nz = ground(pos, fx, fz, spot(PUDDLE))
	if at and ny >= PUDDLE_FLAT then
		at.y = at.y + 0.03          -- over the ripples
		call("SetParticleSystemPosition", sys.puddle.name, pos)
		place(sys.puddle, 0, at, nx, ny, nz)
		setRate(sys.puddle, level)
	else
		setRate(sys.puddle, 0)
	end
end

-- Droplets off the player's craft, seen from outside only: in a first-person
-- view they would burst right in front of the eye.
local function hull(level, player)
	local s = sys.hull
	local view = call("GetCameraView")
	local want = IsCraft(player) and not FIRST_PERSON[view] and type(exu.AttachParticleSystemToObject) == "function"
	if not want and s.attached ~= nil then
		-- Let go of a craft the player left: it may be about to be destroyed.
		call("DetachParticleSystem", s.name)
		s.attached = nil
	end
	if want and s.attached ~= player then
		call("DetachParticleSystem", s.name)
		local odf = string.lower(tostring(GetOdf(player) or "")):gsub("%.odf$", "")
		local box = HULLS[odf] or HULLS.default
		if call("AttachParticleSystemToObject", s.name, player, SetVector(0, box.top, 0)) == true then
			call("SetParticleEmitterParameter", s.name, 0, "width", string.format("%.2f", box.w))
			call("SetParticleEmitterParameter", s.name, 0, "height", string.format("%.2f", box.l))
			s.attached = player
		else
			want = false
		end
	end
	setRate(s, want and HULL_RATE * level or 0)
end

local function applyWind()
	local s = sys.dust
	if s == nil then return end
	local f = wind.speed * DUST_WIND
	local v = string.format("%.3f 0 %.3f", wind.x * f, -wind.z * f)   -- render space: z negated
	if v ~= wind.applied then
		call("SetParticleAffectorParameter", s.name, 0, "force_vector", v)
		wind.applied = v
	end
end

local function apply(now, kind, level)
	wetLevel = (kind == "rain" or kind == "acid") and level or 0
	local player = GetPlayerHandle()
	local active = {}
	if kind ~= nil and level > 0 and IsValid(player) and systemsFor(kind) then
		local k = KINDS[kind]
		if kind ~= kindNow then setColour(kind); kindNow = kind end
		local pos = GetPosition(player)
		if pos ~= nil then
			local fx, fz = flatFront(player)
			if now >= nextTick then
				nextTick = now + TICK
				relocate(kind, pos, fx, fz)
			end
			if k.puddle and now >= nextPuddle then
				nextPuddle = now + PUDDLE_TICK
				puddle(level, pos, fx, fz)
			end
		end
		if k.ring then
			local ring = FULL_RATE * level / sys.ring.count
			setRate(sys.ring, ring)
			setRate(sys.crown, ring * DROPS)
			active.ring, active.crown = true, true
		end
		if k.hull then hull(level, player); active.hull = true end
		if k.puddle then active.puddle = true end
		if k.dust then
			setRate(sys.dust, DUST_RATE * level / sys.dust.count)
			applyWind()
			active.dust = true
		end
	end
	-- Systems nobody wants: stop emitting, hide once the last particles are gone
	-- (puddles live 30 s).
	for key, s in pairs(sys) do
		if not active[key] then setRate(s, 0) end
		if s.rate == 0 and s.visible then
			s.idleSince = s.idleSince or now
			local linger = key == "puddle" and 30 or IDLE_HIDE
			if now - s.idleSince > linger then setVisible(s, false) end
		end
	end
end

local function flush(now)
	if frame ~= nil and now ~= frame then
		local kind, level = nil, 0
		for k, l in pairs(requests) do
			if l > level then kind, level = k, l end
		end
		requests = {}
		local ok, err = pcall(apply, now, kind, level)
		if not ok then
			print("CRSplash: disabled after error: " .. tostring(err))
			for _, s in pairs(sys) do pcall(exu.SetParticleSystemVisible, s.name, false) end
			ready = false
		end
	end
	frame = now
end

--- Asks for a kind ("rain", "acid", "dust") at 0..1 this frame. Returns true
--- while the particles draw it.
function splash.Set(kind, level)
	if ready == nil then ready = init() end
	if not ready or KINDS[kind] == nil then return false end
	if not systemsFor(kind) then return false end
	flush(GetTime())
	level = tonumber(level) or 0
	if level < 0 then level = 0 elseif level > 1 then level = 1 end
	if level > (requests[kind] or 0) then requests[kind] = level end
	return true
end

--- Sets the wind the dust puffs ride: a sim-space ground direction (x, z) and
--- a speed in m/s.
function splash.SetWind(x, z, speed)
	local len = math.sqrt(x * x + z * z)
	if len < 1e-6 then x, z, len = 1, 0, 1 end
	wind.x, wind.z, wind.speed = x / len, z / len, math.max(0, tonumber(speed) or 0)
end

--- How hard it is raining (rain or acid, 0..1) as of the last frame, for
--- anything that wants to know the ground is wet (footsteps).
function splash.WetLevel()
	return wetLevel
end

--- Removes every system and forgets the patches (mission end, weather off).
function splash.Stop()
	requests, frame, kindNow, wetLevel = {}, nil, nil, 0
	nextTick, nextPuddle = 0, 0
	wind.applied = nil
	if exu then
		for key, s in pairs(sys) do
			call("SetParticleSystemVisible", s.name, false)
			call("DetachParticleSystem", s.name)
			call("DestroyParticleSystem", s.name)
			sys[key] = nil
		end
	end
	sys = {}
end

--- Call once per Update from anything that asks for splashes, so they stop
--- when nobody asks (a frame with no Set still needs flushing).
function splash.Update()
	if ready then flush(GetTime()) end
end

return splash
