--**********************************************************************
-- CRPRECIP: rain, acid rain, snow and dust as Ogre particle systems.
--
-- The old weather was MakeExplosion sprites: every rain sheet a 100 m quad,
-- every snow puff a 50 m one, each an engine explosion object, and most of
-- them placed where the camera could not see them. These are real particles:
-- thousands of small streaks and flakes around the camera, drawn by Ogre's
-- ParticleFX in one batch per system, through Extra Utilities.
--
-- Each system is attached to the camera: its emitter volume travels with the
-- view while emitted particles stay in world space, so rain does not slide
-- when the player turns. Intensity is the emission rate; wind is a force.
--
--   CRPrecip.Set("rain", 0.8)   -- every Update, for each kind wanted
--   CRPrecip.SetWind(1, 0, 12)  -- sim-space direction (x, z) and m/s
--
-- Set returns true while the particle layer is drawing that kind, false when
-- it cannot (no EXU, or an EXU without particles), so callers keep their old
-- explosion effects as the fallback. Several callers in one frame are fine:
-- the strongest request for each kind wins. A kind nobody asks for in a frame
-- fades out (its emission stops; live particles finish their short lives).
--
-- Port of the ISDF Chronicles precip.lua. Templates and materials: the ISDF Chronicles tools/precipgen.py (crwx_precip.particle.payload).
--**********************************************************************
local precip = {}

local PREFIX = "crwx_precip_"

-- Full-intensity emission and camera offset per system. The attach height is
-- about one particle lifetime of fall above the eye, so the rain reaches the
-- ground in view instead of dying overhead (see EXU's exu_weather notes).
local SYSTEMS = {
	rain  = { { key = "rain", template = "CRWX/Rain", rate = 1650, offset = { 0, 24, 0 }, wind = 0.9,
	            size = { 0.22, 3.2 }, quota = 5200 },
	          { key = "mist", template = "CRWX/RainMist", rate = 20, offset = { 0, 8, 0 }, wind = 0.3, from = 0.45 } },
	acid  = { { key = "acid", template = "CRWX/AcidRain", rate = 630, offset = { 0, 26, 0 }, wind = 0.6 } },
	snow  = { { key = "snow", template = "CRWX/Snow", rate = 760, offset = { 0, 22, 0 }, wind = 0.35,
	            size = { 0.34, 0.34 }, quota = 6500 } },
	-- Dust is carried by the wind, so its volume sits upwind: motes and grit
	-- are born before the camera and blow across the view instead of away.
	dust  = { { key = "dust", template = "CRWX/DustMotes", rate = 60, offset = { 0, 16, 0 }, wind = 0.25, upwind = 70 },
	          { key = "grit", template = "CRWX/DustGrit", rate = 1100, offset = { 0, 5, 0 }, wind = 0.0, upwind = 45, aim = true } },
}

local exu = nil
local ready = nil          -- nil = not tried, true = working, false = unavailable
local live = {}            -- key -> { name, spec, rate, visible }
local frame, requests, applied = nil, {}, {}
local wind = { x = 1, z = 0, speed = 0 }
-- Presentation override (SetLook): box shrinks the emitter footprint around the
-- camera, size scales billboards, rate scales emission. 1/1/1 = ISDF Chronicles tuning.
local look = { box = 1, size = 1, rate = 1 }

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
	"CreateParticleSystem", "DestroyParticleSystem", "AttachParticleSystemToCamera",
	"SetParticleEmitterEmissionRate", "SetParticleSystemEmitting", "SetParticleSystemVisible",
}

local function call(fn, ...)
	if type(exu[fn]) ~= "function" then return nil end
	local ok, r = pcall(exu[fn], ...)
	if not ok then return nil end
	return r
end

local function vec(t) return SetVector(t[1], t[2], t[3]) end

-- Sim space is z-forward; Ogre render space negates z (EXU OgreRenderSpace).
local function renderVec(x, y, z) return string.format("%.3f %.3f %.3f", x, y, -z) end

local function create(spec)
	local name = PREFIX .. spec.key
	-- A system left by an earlier load of this scene: EXU finds it by name.
	call("DetachParticleSystem", name)
	call("DestroyParticleSystem", name)
	if call("CreateParticleSystem", name, spec.template) ~= true then
		print("CRPrecip: could not create " .. spec.template .. " (is crwx_precip.particle.payload loaded?)")
		return nil
	end
	call("SetParticleSystemKeepLocalSpace", name, false)
	call("SetParticleSystemNonVisibleUpdateTimeout", name, 2.0)
	if call("AttachParticleSystemToCamera", name, vec(spec.offset)) ~= true then
		call("DestroyParticleSystem", name)
		print("CRPrecip: could not attach " .. spec.template .. " to the camera")
		return nil
	end
	call("SetParticleEmitterEmissionRate", name, 0, 0)
	call("SetParticleSystemEmitting", name, false)
	call("SetParticleSystemVisible", name, false)
	local sys = { name = name, spec = spec, rate = 0, visible = false, upwind = nil }
	-- The template's own box, read once, so SetLook can scale it and scale back.
	sys.box = {}
	for _, key in ipairs({ "width", "depth" }) do
		sys.box[key] = tonumber(call("GetParticleEmitterParameter", name, 0, key))
	end
	return sys
end

local function applyLook(sys)
	local spec = sys.spec
	for key, base in pairs(sys.box) do
		call("SetParticleEmitterParameter", sys.name, 0, key, string.format("%.2f", base * look.box))
	end
	if spec.size then
		call("SetParticleSystemDefaultDimensions", sys.name, spec.size[1] * look.size, spec.size[2] * look.size)
	end
	if spec.quota then
		call("SetParticleSystemParticleQuota", sys.name, math.floor(spec.quota * math.max(1, look.rate) + 0.5))
	end
	sys.look = look
end

local function init()
	exu = findExu()
	if exu == nil then return false end
	for _, fn in ipairs(REQUIRED) do
		if type(exu[fn]) ~= "function" then return false end
	end
	return ensureTemplates()
end

-- One frame's worth of requests reaches Ogre here.
local function apply(levels)
	for kind, specs in pairs(SYSTEMS) do
		local level = levels[kind] or 0
		for _, spec in ipairs(specs) do
			local w = level
			if spec.from then w = math.max(0, (level - spec.from) / (1 - spec.from)) end
			local sys = live[spec.key]
			if sys == nil and w > 0 then
				sys = create(spec)
				live[spec.key] = sys or false
			end
			if sys then
				if sys.look ~= look then applyLook(sys) end
				local rate = spec.rate * w * look.rate
				if math.abs(rate - sys.rate) > spec.rate * 0.02 or (rate == 0) ~= (sys.rate == 0) then
					call("SetParticleEmitterEmissionRate", sys.name, 0, rate)
					call("SetParticleSystemEmitting", sys.name, rate > 0)
					sys.rate = rate
				end
				-- Keep drawing while the last particles die; hide once idle.
				if rate > 0 then
					sys.idleSince = nil
					if not sys.visible then call("SetParticleSystemVisible", sys.name, true); sys.visible = true end
				elseif sys.visible then
					sys.idleSince = sys.idleSince or GetTime()
					if GetTime() - sys.idleSince > 10 then
						call("SetParticleSystemVisible", sys.name, false)
						sys.visible = false
					end
				end
				if rate > 0 then
					local s = wind.speed
					if spec.wind > 0 then
						call("SetParticleAffectorParameter", sys.name, 0, "force_vector",
							renderVec(wind.x * s * spec.wind, 0, wind.z * s * spec.wind))
					end
					if spec.aim then
						call("SetParticleEmitterDirection", sys.name, 0, SetVector(wind.x, -0.08, -wind.z))
					end
					if spec.upwind then
						local u = spec.upwind * math.min(1, s / 20)
						local ox, oz = -wind.x * u, -wind.z * u
						if sys.upwind == nil or math.abs(ox - sys.upwind[1]) + math.abs(oz - sys.upwind[2]) > 2 then
							sys.upwind = { ox, oz }
							-- Offsets are render space (z negated). Only moves when the wind turns.
							call("DetachParticleSystem", sys.name)
							call("AttachParticleSystemToCamera", sys.name,
								SetVector(spec.offset[1] + ox, spec.offset[2], -(spec.offset[3] + oz)))
						end
					end
				end
			end
		end
	end
	-- Camera followers need one tick a frame when the camera has no scene node.
	call("UpdateParticleFollowers")
end

local function flush(now)
	if frame ~= nil and now ~= frame then
		applied = requests
		requests = {}
		local ok, err = pcall(apply, applied)
		if not ok then
			print("CRPrecip: disabled after error: " .. tostring(err))
			for _, sys in pairs(live) do
				if sys then pcall(exu.SetParticleSystemVisible, sys.name, false) end
			end
			ready = false
		end
	end
	frame = now
end

--- Asks for a kind of weather ("rain", "acid", "snow", "dust") at 0..1 this
--- frame. Returns true while the particle layer draws it.
function precip.Set(kind, level)
	if ready == nil then ready = init() end
	if not ready or SYSTEMS[kind] == nil then return false end
	flush(GetTime())
	level = tonumber(level) or 0
	if level < 0 then level = 0 elseif level > 1 then level = 1 end
	if level > (requests[kind] or 0) then requests[kind] = level end
	-- A template that failed to load leaves live[key] == false: report it.
	return live[SYSTEMS[kind][1].key] ~= false
end

--- Presentation override for cinematic cameras: { box = footprint scale,
--- size = billboard scale, rate = emission scale } (each defaults to 1). The
--- ISDF Chronicles tuning suits a pilot at ground level; a film camera
--- several metres up wants the particles packed closer and drawn larger.
--- Call with nil to return to the template look.
function precip.SetLook(t)
	t = type(t) == "table" and t or {}
	local box, size, rate = tonumber(t.box) or 1, tonumber(t.size) or 1, tonumber(t.rate) or 1
	if box ~= look.box or size ~= look.size or rate ~= look.rate then
		look = { box = box, size = size, rate = rate } -- live systems re-apply on their next frame
	end
end

--- Sets the wind: a sim-space ground direction (x, z) and a speed in m/s.
function precip.SetWind(x, z, speed)
	local len = math.sqrt(x * x + z * z)
	if len < 1e-6 then x, z, len = 1, 0, 1 end
	wind.x, wind.z, wind.speed = x / len, z / len, math.max(0, tonumber(speed) or 0)
end

--- Applies last frame's requests to Ogre. Call once per frame from whatever
--- drives the weather, so a kind nobody asked for this frame fades out.
function precip.Update()
	if ready then flush(GetTime()) end
end

--- Stops every kind and removes the systems (mission end, weather off). The
--- next Set recreates them.
function precip.Stop()
	requests, applied, frame = {}, {}, nil
	look = { box = 1, size = 1, rate = 1 }
	if not exu then return end
	for key, sys in pairs(live) do
		if sys then
			call("SetParticleEmitterEmissionRate", sys.name, 0, 0)
			call("SetParticleSystemEmitting", sys.name, false)
			call("SetParticleSystemVisible", sys.name, false)
			call("DetachParticleSystem", sys.name)
			call("DestroyParticleSystem", sys.name)
		end
		live[key] = nil
	end
end

--- True when the particle layer can run (EXU with particle support).
function precip.Available()
	if ready == nil then ready = init() end
	return ready
end

return precip
