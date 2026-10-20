--**********************************************************************
-- CRGROUNDFX: lava and toxic pool bubbles, footsteps, lightning strikes and
-- radiation zones as Ogre particles.
--
-- Port of the ISDF Chronicles isdfclava.lua. Its effects.BubblingLava / BubblingAcid picked a spot on the pool every fraction
-- of a second. That spot used to get the xlavar bubble sphere and the xvent
-- smoke twirl (or xtoxic), explosions that popped in and out. Now it gets:
--   Glow     a bubble swelling into a flat glow on the surface
--   Drops    the pop's drops arcing out and falling back
--   Embers   sparks riding the heat up (toxic: slow glowing motes)
--   Smoke    a plume lit red from below, greying as it climbs (toxic: low gas)
-- The damage and sound stay with the engine: callers fire the particle-less
-- xlavarh / xventh / xtoxich explosions at the same spot.
--
-- Each system has a few emitter slots; an event takes the next slot of every
-- system, which emits there for its while and then stops, so recent bubbles
-- keep smoking while new ones pop.
--
--   if CRGroundFX.Event("lava", pos) then MakeExplosion("xlavarh", pos) ... end
--   CRGroundFX.Update()   -- every Update (turns finished slots off)
--
-- Event returns false when the particles cannot draw (no EXU, or one without
-- particles): callers keep the old explosions.
--
-- Footsteps (the ISDF Chronicles effects.Footprints) used the same slots: "stepdust" kicks a little
-- dust off dry ground, "stepwet" a ripple and flicked droplets in the rain.
-- Event's optional scale multiplies the rates (a landing kicks more dust);
-- SetColour tints a kind's emitters (the world's soil for the dust).
--
-- Lightning: Bolt draws a fresh jagged, branching channel from the cloud base
-- to a ground point into BoltCore / BoltBranch (each emitter one segment),
-- BoltStroke lights it for one return stroke; "strike" is the flash, sparks
-- and steam at the ground. The engine keeps the light and scorch (xbgnd*l).
-- Radiation: Event("radiation", spot) gives a zone its slots for good (motes,
-- haze, crackle); the engine keeps the green light (xradih).
-- Footprints: Print lays one boot on the ground under a foot, turned to the
-- nearest of 16 headings (Print00..15, one system each: a particle cannot be
-- turned on its own) and tilted to the slope.
--**********************************************************************
local lava = {}

local PREFIX = "crwx_lava_"
local REANCHOR = 400         -- m: move the systems' node when the player gets this far from it

-- Per system: template, slots (the ISDF Chronicles tools/precipgen.py LAVA_SLOTS), how long a slot
-- emits after an event (s) and its rate meanwhile (particles/s).
local KINDS = {
	lava = {
		{ key = "glow",   template = "CRWX/LavaGlow",   slots = 4,  on = 0.25, rate = 4 },
		{ key = "drops",  template = "CRWX/LavaDrops",  slots = 4,  on = 0.25, rate = 60 },
		{ key = "embers", template = "CRWX/LavaEmbers", slots = 8,  on = 1.5,  rate = 10 },
		{ key = "smoke",  template = "CRWX/LavaSmoke",  slots = 12, on = 2.0,  rate = 6 },
	},
	toxic = {
		{ key = "glow",  template = "CRWX/ToxicGlow",  slots = 4,  on = 0.25, rate = 4 },
		{ key = "drops", template = "CRWX/ToxicDrops", slots = 4,  on = 0.25, rate = 36 },
		{ key = "motes", template = "CRWX/ToxicMotes", slots = 8,  on = 2.0,  rate = 6 },
		{ key = "gas",   template = "CRWX/ToxicGas",   slots = 12, on = 3.0,  rate = 3 },
	},
	-- Liquid-sulphur pools (Venus): the toxic layout in yellow and pale gas.
	sulfur = {
		{ key = "glow",  template = "CRWX/SulfurGlow",  slots = 4,  on = 0.25, rate = 4 },
		{ key = "drops", template = "CRWX/SulfurDrops", slots = 4,  on = 0.25, rate = 30 },
		{ key = "motes", template = "CRWX/SulfurMotes", slots = 6,  on = 2.0,  rate = 5 },
		{ key = "gas",   template = "CRWX/SulfurGas",   slots = 8,  on = 3.0,  rate = 3 },
	},
	stepdust = {
		{ key = "dust", template = "CRWX/StepDust", slots = 4, on = 0.12, rate = 40, colour = { 0.55, 0.50, 0.42, 0.5 } },
	},
	strike = {
		{ key = "sparks", template = "CRWX/StrikeSparks", slots = 2, on = 0.08, rate = 250 },
		{ key = "flash",  template = "CRWX/StrikeFlash",  slots = 2, on = 0.05, rate = 24 },
		{ key = "steam",  template = "CRWX/StrikeSteam",  slots = 2, on = 0.3,  rate = 16 },
	},
	radiation = {
		{ key = "motes",   template = "CRWX/RadMotes",   slots = 8, on = math.huge, rate = 30 },
		{ key = "haze",    template = "CRWX/RadHaze",    slots = 8, on = math.huge, rate = 1.5 },
		{ key = "crackle", template = "CRWX/RadCrackle", slots = 8, on = math.huge, rate = 4 },
	},
	-- Rates are set per segment by Bolt; on is one return stroke.
	bolt = {
		{ key = "core",   template = "CRWX/BoltCore",   slots = 12, on = 0.07, rate = 0 },
		{ key = "branch", template = "CRWX/BoltBranch", slots = 10, on = 0.07, rate = 0 },
	},
	stepwet = {
		{ key = "ripple", template = "CRWX/StepRipple", slots = 2, on = 0.1, rate = 10, colour = { 0.85, 0.90, 0.95, 1.0 } },
		{ key = "drops",  template = "CRWX/StepDrops",  slots = 2, on = 0.1, rate = 90, colour = { 0.86, 0.90, 0.95, 0.75 } },
	},
}

-- One boot per heading; Print lights a slot for a moment (about one print).
local PRINT_HEADINGS = 16
for k = 0, PRINT_HEADINGS - 1 do
	KINDS[string.format("print%02d", k)] = {
		{ key = "boot", template = string.format("CRWX/Print%02d", k), slots = 2, on = 0.05, rate = 25 },
	}
end

local exu = nil
local ready = nil            -- nil = not tried, true = working, false = unavailable
local live = {}              -- kind -> { systems..., anchor } once created, false if it failed

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
	"SetParticleEmitterEmissionRate", "SetParticleEmitterPosition",
}

local function call(fn, ...)
	if type(exu[fn]) ~= "function" then return nil end
	local ok, r = pcall(exu[fn], ...)
	return ok and r
end

local function init()
	exu = findExu()
	if exu == nil then return false end
	for _, fn in ipairs(REQUIRED) do
		if type(exu[fn]) ~= "function" then return false end
	end
	return ensureTemplates()
end

-- Every system of a kind, at a node placed where the player is.
local function build(kind, at)
	local set = { anchor = SetVector(at.x, at.y, at.z), systems = {} }
	for _, spec in ipairs(KINDS[kind]) do
		local name = PREFIX .. kind .. "_" .. spec.key
		call("DetachParticleSystem", name)
		call("DestroyParticleSystem", name)
		if call("CreateParticleSystem", name, spec.template, set.anchor) ~= true then
			print("CRGroundFX: could not create " .. spec.template .. " (is crwx_precip.particle.payload loaded?)")
			for _, s in ipairs(set.systems) do call("DestroyParticleSystem", s.name) end
			return false
		end
		call("SetParticleSystemKeepLocalSpace", name, false)
		local s = { name = name, spec = spec, next = 0, slots = {} }
		for e = 0, spec.slots - 1 do
			call("SetParticleEmitterEmissionRate", name, e, 0)
			if spec.colour then
				local c = spec.colour
				call("SetParticleEmitterColor", name, e, c[1], c[2], c[3], c[4])
			end
			s.slots[e] = { offAt = nil, at = nil }
		end
		set.systems[#set.systems + 1] = s
	end
	return set
end

-- Emitter positions are local to the node, in render space (z negated).
local function offset(set, p)
	return SetVector(p.x - set.anchor.x, p.y - set.anchor.y, -(p.z - set.anchor.z))
end

-- Keep the node near the player so offsets stay small; slots still emitting
-- are re-placed relative to the new anchor.
local function reanchor(set, player)
	local pos = GetPosition(player)
	if pos == nil then return end
	local dx, dz = pos.x - set.anchor.x, pos.z - set.anchor.z
	if dx * dx + dz * dz < REANCHOR * REANCHOR then return end
	set.anchor = SetVector(pos.x, pos.y, pos.z)
	for _, s in ipairs(set.systems) do
		call("SetParticleSystemPosition", s.name, set.anchor)
		for e, slot in pairs(s.slots) do
			if slot.offAt ~= nil then call("SetParticleEmitterPosition", s.name, e, offset(set, slot.at)) end
		end
	end
end

local function ensure(kind)
	if ready == nil then ready = init() end
	if not ready or KINDS[kind] == nil then return nil end
	if live[kind] == nil then live[kind] = build(kind, GetPosition(GetPlayerHandle()) or SetVector(0, 0, 0)) end
	return live[kind] or nil
end

--- An event of a kind ("lava", "toxic", "sulfur", "stepdust", "stepwet") at a
--- sim-space ground point, its rates times scale (default 1). mask optionally
--- multiplies one system's rate by its key (mask.smoke = 0.3; 0 skips that
--- system). Returns true when the particles draw it.
function lava.Event(kind, pos, scale, mask)
	if pos == nil then return false end
	local set = ensure(kind)
	if not set then return false end
	scale = tonumber(scale) or 1
	local ok, err = pcall(function()
		reanchor(set, GetPlayerHandle())
		local now = GetTime()
		local at = SetVector(pos.x, pos.y + 0.1, pos.z)
		local local_ = offset(set, at)
		for _, s in ipairs(set.systems) do
			local m = mask and mask[s.spec.key]
			if m == nil then m = 1 end
			if m > 0 then
				local e = s.next
				s.next = (e + 1) % s.spec.slots
				call("SetParticleEmitterPosition", s.name, e, local_)
				call("SetParticleEmitterEmissionRate", s.name, e, s.spec.rate * scale * m)
				s.slots[e].offAt, s.slots[e].at = now + s.spec.on, at
			end
		end
	end)
	if not ok then
		print("CRGroundFX: disabled after error: " .. tostring(err))
		ready = false
		return false
	end
	return true
end

--- Tints every emitter of a kind (or only its system named key): r, g, b, a
--- in 0..1. Returns true when set.
function lava.SetColour(kind, r, g, b, a, key)
	local set = ensure(kind)
	if not set then return false end
	for _, s in ipairs(set.systems) do
		if key == nil or s.spec.key == key then
			for e = 0, s.spec.slots - 1 do call("SetParticleEmitterColor", s.name, e, r, g, b, a) end
		end
	end
	return true
end

--- How many zones a kind can hold at once (radiation keeps a slot per zone).
function lava.Capacity(kind)
	local spec = KINDS[kind]
	return spec and spec[1].slots or 0
end

--- Lays one boot print at a sim-space ground point: normal is the ground's
--- (sim space), heading the walking direction in radians (from +z toward +x),
--- colour r, g, b, a, and fade the alpha lost per second (so 1/fade seconds
--- to vanish). Returns true when the particles draw it.
function lava.Print(pos, normal, heading, r, g, b, a, fade)
	if pos == nil then return false end
	local step = 2 * math.pi / PRINT_HEADINGS
	local k = math.floor((heading or 0) / step + 0.5) % PRINT_HEADINGS
	local set = ensure(string.format("print%02d", k))
	if not set then return false end
	local s = set.systems[1]
	local ok, err = pcall(function()
		reanchor(set, GetPlayerHandle())
		local look = string.format("%.3f %.3f %.3f %.3f %.4f", r, g, b, a, fade)
		if s.look ~= look then
			for e = 0, s.spec.slots - 1 do call("SetParticleEmitterColor", s.name, e, r, g, b, a) end
			call("SetParticleAffectorParameter", s.name, 0, "alpha", string.format("%.4f", -fade))
			s.look = look
		end
		local e = s.next
		s.next = (e + 1) % s.spec.slots
		local at = SetVector(pos.x, pos.y + 0.02, pos.z)   -- just above the ground and the ripples
		local nx, ny, nz = 0, 1, 0
		if normal ~= nil and normal.y > 0.2 then nx, ny, nz = normal.x, normal.y, normal.z end
		call("SetParticleEmitterPosition", s.name, e, offset(set, at))
		call("SetParticleEmitterDirection", s.name, e, SetVector(nx, ny, -nz))
		call("SetParticleEmitterEmissionRate", s.name, e, s.spec.rate)
		s.slots[e].offAt, s.slots[e].at = GetTime() + s.spec.on, at
	end)
	if not ok then
		print("CRGroundFX: prints disabled after error: " .. tostring(err))
		live[string.format("print%02d", k)] = false
		return false
	end
	return true
end

------------------------------------------------------------------------
-- Lightning channel
------------------------------------------------------------------------
local BOLT_TOP = 300          -- m: cloud base above the ground
local CORE_SPACING, CORE_TTL = 0.9, 0.09      -- glow points every 0.9 m, living ~0.09 s
local BRANCH_SPACING, BRANCH_TTL = 1.0, 0.075
local bolt = { rates = {} }   -- system name -> slot -> rate for a stroke

local function rnd(a, b) return a + (b - a) * math.random() end

-- Lay one segment a..b (sim space) into emitter e of system s.
local function segment(set, s, e, a, b, spacing, ttl)
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 0.01 then return end
	local mid = SetVector((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
	call("SetParticleEmitterPosition", s.name, e, offset(set, mid))
	call("SetParticleEmitterDirection", s.name, e, SetVector(dx / len, dy / len, -dz / len))
	call("SetParticleEmitterParameter", s.name, e, "depth", string.format("%.2f", len))
	s.slots[e].at = mid
	bolt.rates[s.name][e] = len / spacing / ttl
end

--- Draws a fresh channel from the cloud base down to the ground point
--- (x, ground, z), coloured r, g, b. Nothing shows until BoltStroke. Returns
--- true when the particles can draw it.
function lava.Bolt(x, ground, z, r, g, b)
	local set = ensure("bolt")
	if not set then return false end
	local core, branch = set.systems[1], set.systems[2]
	local ok, err = pcall(function()
		reanchor(set, GetPlayerHandle())
		for _, s in ipairs(set.systems) do
			bolt.rates[s.name] = {}
			for e = 0, s.spec.slots - 1 do call("SetParticleEmitterColor", s.name, e, r, g, b, 1) end
		end
		-- Core: a random walk sideways, pulled back so it ends on the strike point.
		local n = core.spec.slots
		local top = SetVector(x + rnd(-40, 40), ground + BOLT_TOP, z + rnd(-40, 40))
		local wx, wz, walk = 0, 0, {}
		for i = 1, n do
			wx, wz = wx + rnd(-14, 14), wz + rnd(-14, 14)
			walk[i] = { wx, wz }
		end
		local nodes = { top }
		for i = 1, n do
			local t = i / n
			local jy = (i < n) and rnd(-0.3, 0.3) * BOLT_TOP / n or 0
			nodes[i + 1] = SetVector(top.x + (x - top.x) * t + walk[i][1] - t * walk[n][1],
				top.y + (ground - top.y) * t + jy,
				top.z + (z - top.z) * t + walk[i][2] - t * walk[n][2])
		end
		for i = 1, n do segment(set, core, i - 1, nodes[i], nodes[i + 1], CORE_SPACING, CORE_TTL) end
		-- Branches fork off the upper two thirds, reaching out and down.
		local e = 0
		while e < branch.spec.slots do
			local from = nodes[math.random(2, math.max(2, math.floor(n * 0.66)))]
			local a = rnd(0, 2 * math.pi)
			local ox, oz = math.cos(a), math.sin(a)
			local p = from
			for _ = 1, math.random(2, 4) do
				if e >= branch.spec.slots then break end
				local len = rnd(10, 22)
				local q = SetVector(p.x + ox * len * rnd(0.5, 1) + rnd(-4, 4), p.y - rnd(6, 16), p.z + oz * len * rnd(0.5, 1) + rnd(-4, 4))
				segment(set, branch, e, p, q, BRANCH_SPACING, BRANCH_TTL)
				p, e = q, e + 1
			end
		end
	end)
	if not ok then
		print("CRGroundFX: bolt disabled after error: " .. tostring(err))
		live.bolt = false
		return false
	end
	return true
end

--- One return stroke: the last Bolt's channel glows for a moment. Call once
--- per stroke (a strike is 1-4 of them).
function lava.BoltStroke()
	local set = live.bolt
	if not set then return false end
	local now = GetTime()
	for _, s in ipairs(set.systems) do
		for e, rate in pairs(bolt.rates[s.name] or {}) do
			call("SetParticleEmitterEmissionRate", s.name, e, rate)
			s.slots[e].offAt = now + s.spec.on
		end
	end
	return true
end

--- Removes every system of every kind and forgets the slots (mission end).
--- Later events recreate them.
function lava.Stop()
	if exu then
		for kind, set in pairs(live) do
			if set then
				for _, s in ipairs(set.systems) do
					call("DetachParticleSystem", s.name)
					call("DestroyParticleSystem", s.name)
				end
			end
			live[kind] = nil
		end
	end
	live = {}
	bolt.rates = {}
end

--- Removes only the systems of one kind (a director leaving its pools alone
--- must not tear down another feature's systems). Later events recreate them.
function lava.StopKind(kind)
	local set = live[kind]
	if set and exu then
		for _, s in ipairs(set.systems) do
			call("DetachParticleSystem", s.name)
			call("DestroyParticleSystem", s.name)
		end
	end
	live[kind] = nil
end

--- Turns off slots whose while is over. Call every Update.
function lava.Update()
	if not ready then return end
	local now = GetTime()
	for _, set in pairs(live) do
		if set then
			for _, s in ipairs(set.systems) do
				for e, slot in pairs(s.slots) do
					if slot.offAt ~= nil and now >= slot.offAt then
						call("SetParticleEmitterEmissionRate", s.name, e, 0)
						slot.offAt = nil
					end
				end
			end
		end
	end
end

return lava
