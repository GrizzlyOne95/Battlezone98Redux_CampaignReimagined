--**********************************************************************
-- CRSTORMFX: rain, acid rain, lightning and a dynamic weather director, with
-- EXU-driven fog, ambient and sun that follow the weather.
--
-- Weather subset of the ISDF Chronicles effects.lua (footprints, radiation,
-- earthquakes, ambient tones and lava/acid bubbling were left behind). The
-- particle layers are CRPrecip (falling rain), CRSplash (ground splashes) and
-- CRGroundFX (lightning channel); the engine keeps the strike light, scorch
-- and the old explosion sheets as the fallback where EXU cannot draw particles.
--
-- Everything is a field of the returned table; no globals are created and no
-- BZ API is called at require time.
--
-- Typical mission use:
--   local Storm = require("CRStormFX")
--   M.weather = Storm.StartDynamicWeather(M.weather, { start = { rain = 3, storm = 2 } })
--   function Update() Storm.Update() end        -- every frame
--   Storm.Shutdown()                            -- mission end: restores fog and light
--
-- Rain(i) draws rain at a continuous intensity 0..1 and Lightning(perMinute)
-- schedules strikes. The director blends between random weather states (clear,
-- overcast, drizzle, rain, storm) with slow smoothstep cross-fades.
--**********************************************************************
local Storm = {}

local function optional(name)
	local ok, m = pcall(require, name)
	if ok and type(m) == "table" then return m end
	return nil
end

-- Falling rain, acid rain (EXU particles); optional.
local precip = optional("CRPrecip")
-- Rain splashes on the ground (EXU particles); optional.
local splashfx = optional("CRSplash")
-- Lightning channel and strike sparks (EXU particles); optional.
local lavafx = optional("CRGroundFX")
-- Windshield drops on the screen or on the cockpit glass submesh (EXU); optional.
local wetglass = optional("CRWetGlass")

local dotProductTolerance = 0.999
local acidRainEmissionTimer = 0 -- time-based so high frame rates cannot multiply weather effects
local acidSplashCarry = 0

-- BZ vectors are made on first use so that requiring the module needs no BZ API.
local upVector, placeExplosion = nil, nil
local function up()
	if upVector == nil then upVector = SetVector(0, 1, 0) end
	return upVector
end
local function place()
	if placeExplosion == nil then placeExplosion = SetVector(0, 0, 0) end
	return placeExplosion
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

------------------------------------------------------------------------
-- Map facts from the TRN, looked up on first use
------------------------------------------------------------------------
local trnInfo = nil
local function trn()
	if trnInfo ~= nil then return trnInfo end
	local info = { fogEnd = 250, visibility = 0, world = "Other" }
	local ok, found = pcall(function()
		local filename = GetMapTRNFilename()
		if filename == nil then return false end
		local odf = OpenODF(filename)
		if odf == nil then return false end
		local fogEnd = GetODFFloat(odf, "NormalView", "FogEnd", 250)
		if fogEnd ~= nil and fogEnd > 0 then info.fogEnd = fogEnd end
		info.visibility = GetODFFloat(odf, "NormalView", "VisibilityRange", 0) or 0
		local solid = tostring(GetODFString(odf, "TextureType0", "SolidA0") or "")
		if string.find(solid, "ti") then
			info.world = "Titan"
		elseif string.find(solid, "ve") then
			info.world = "Venus"
		elseif string.find(solid, "mire") then
			info.world = "Mire"
		end
		return true
	end)
	-- Only remember a successful read: a map not loaded yet may answer later.
	if ok and found then trnInfo = info end
	return info
end

-- Heading of a handle flattened onto the ground plane (unit x, z).
local function flatFront(h)
	local front = GetFront(h)
	if front ~= nil then
		local len = math.sqrt(front.x * front.x + front.z * front.z)
		if len > 0.001 then return front.x / len, front.z / len end
	end
	return 0, 1
end

-- Rain splashes (explosion fallback) go where the camera can see them: 65 % in
-- a +-55 degree arc 6-45 m ahead and the rest in a 3-20 m ring all round. The
-- raised crown is 2.5 m of sprite, so past CROWN_RANGE only the ripple is spawned.
local SPLASH_AHEAD = 0.65
local CROWN_RANGE = 32
local function splash(px, py, pz, fx, fz, ring, crown)
	local math_random = math.random
	local a, d
	if math_random() < SPLASH_AHEAD then
		a = math.rad(math_random() * 110 - 55)
		d = math.sqrt(6 * 6 + math_random() * (45 * 45 - 6 * 6)) -- area-weighted
	else
		a = math_random() * 2 * math.pi
		d = math.sqrt(3 * 3 + math_random() * (20 * 20 - 3 * 3))
	end
	local ca, sa = math.cos(a), math.sin(a)
	local at = place()
	at.x = px + (fx * ca - fz * sa) * d
	at.z = pz + (fx * sa + fz * ca) * d
	at.y = py + 5
	-- Floor, not terrain: rain splashes on rooftops too.
	at.y = GetFloorHeightAndNormal(at)
	MakeExplosion(ring, at) --ripple ring on the ground
	if d < CROWN_RANGE then
		MakeExplosion(crown, at) --crown of drops thrown up
	end
end

------------------------------------------------------------------------
-- Private random stream. Seeded from run-to-run entropy (the heap addresses of
-- a fresh table and closure, os time/clock when the sandbox has them) so a
-- replay does not roll the same weather, and kept apart from math.random so
-- other scripts' sequences are left alone. Park-Miller: exact in doubles.
------------------------------------------------------------------------
local rngState = 0
local function mix(s, value)
	local text = tostring(value)
	for i = 1, #text do s = (s * 31 + string.byte(text, i)) % 2147483647 end
	return s
end
local function seedRandom()
	local s = mix(7, tostring({}))
	s = mix(s, tostring(function() end))
	pcall(function() s = mix(s, os.time()) end)
	pcall(function() s = mix(s, os.clock()) end)
	-- One draw from the shared stream, in case the host seeds it per run.
	pcall(function() s = mix(s, math.random(1, 2147483646)) end)
	if s <= 0 then s = 1234567 end
	rngState = s
end
local function rand() -- uniform in (0, 1)
	if rngState == 0 then seedRandom() end
	rngState = (rngState * 16807) % 2147483647
	return rngState / 2147483647
end
local function randRange(a, b) return a + (b - a) * rand() end
-- Fixed seed for offline tests; missions never call it.
local function SeedRandom(seed)
	rngState = math.floor(seed) % 2147483646 + 1
end

------------------------------------------------------------------------
-- Environment (EXU): fog, ambient and sun follow the weather; strokes flash.
------------------------------------------------------------------------
local function findExu()
	local e = package and package.loaded and package.loaded["exu"]
	if type(e) ~= "table" then
		local ok, m = pcall(require, "exu")
		e = ok and m or nil
	end
	if type(e) == "table" and e.isStub ~= true and type(e.SetFog) == "function" then return e end
	return nil
end

local env = {
	lib = nil, base = nil, nextProbe = 0,
	fogScale = 1, lightScale = 1, -- set by the weather director
	flash = 0,                    -- lightning flash, 0..1, decays
	nextFog = 0, nextSun = 0,
	fogS = nil, fogE = nil, fogR = nil, ambR = nil, ambK = nil, sunR = nil,
	-- Optional colour overrides (SetTint). A map whose own fog is black (the
	-- Moon) needs a weather colour, not a darker black.
	tintFog = nil, tintAmb = nil, fogKey = nil,
}

local function probeEnvironment(now)
	if env.base ~= nil or now < env.nextProbe then return env.base end
	env.nextProbe = now + 2
	local e = findExu()
	if e == nil then return nil end
	local function get(name)
		if type(e[name]) ~= "function" then return nil end
		local ok, v = pcall(e[name])
		if ok and type(v) == "table" then return v end
		return nil
	end
	local fog, amb, sun = get("GetFog"), get("GetAmbientLight"), get("GetSunDiffuse")
	-- Older EXU builds return zeros instead of nil before the scene exists;
	-- wait for real values rather than fading the map toward black.
	if fog and not ((tonumber(fog.ending) or 0) > 0) then fog = nil end
	if amb and not (((amb.r or 0) + (amb.g or 0) + (amb.b or 0)) > 0) then amb = nil end
	if sun and not (((sun.r or 0) + (sun.g or 0) + (sun.b or 0)) > 0) then sun = nil end
	if fog == nil and amb == nil then return nil end
	env.lib = e
	env.base = { fog = fog, amb = amb, sun = sun }
	return env.base
end

local function applyEnvironment(now, dt)
	if env.flash > 0 then
		env.flash = env.flash * math.exp(-dt / 0.12)
		if env.flash < 0.01 then env.flash = 0 end
	end
	local base = probeEnvironment(now)
	if base == nil then return end
	local e = env.lib
	local flashing = env.flash > 0 or env.fogR ~= nil and env.fogR > 0 or env.ambR ~= nil and env.ambR > 0

	-- Fog distance moves at 5 Hz (it drifts over tens of seconds); the fog and
	-- ambient colour update every frame while a flash is decaying.
	if base.fog and type(e.SetFog) == "function" and (now >= env.nextFog or flashing) then
		env.nextFog = now + 0.2
		local b = base.fog
		local c = env.tintFog or b
		local info = trn()
		local f = b.ending * env.fogScale
		if info.visibility > 0 then f = math.min(f, b.ending * (info.visibility * 0.9 / info.fogEnd)) end
		local s = math.min(b.start * env.fogScale, f * 0.9)
		local shade = 0.55 + 0.45 * clamp(env.lightScale, 0, 1)
		local lift = 0.35 * env.flash
		local key = c.r * 1e6 + c.g * 1e3 + c.b
		if env.fogE == nil or math.abs(f - env.fogE) > 0.25 or math.abs(s - env.fogS) > 0.25
			or math.abs(lift - (env.fogR or 0)) > 0.003 or math.abs(key - (env.fogKey or -1)) > 2 then
			env.fogS, env.fogE, env.fogR, env.fogKey = s, f, lift, key
			pcall(e.SetFog, math.min(1, c.r * shade + lift), math.min(1, c.g * shade + lift),
				math.min(1, c.b * shade + lift), s, f)
		end
	end

	if (env.tintAmb or base.amb) and type(e.SetAmbientLight) == "function" then
		local a = env.tintAmb or base.amb
		local k = env.lightScale
		local lift = 0.5 * env.flash
		local key = k * 1000 + lift + (a.r * 1e6 + a.g * 1e3 + a.b) * 1e3
		if env.ambR == nil or math.abs(key - env.ambK) > 2 or math.abs(lift - env.ambR) > 0.003 then
			env.ambK, env.ambR = key, lift
			pcall(e.SetAmbientLight, a.r * k + lift, a.g * k + lift, a.b * k + lift)
		end
	end

	-- The sun setters log on this EXU build, so the sun only moves at 2 Hz and
	-- only when the change is visible.
	if base.sun and type(e.SetSunDiffuse) == "function" and now >= env.nextSun then
		env.nextSun = now + 0.5
		local k = env.lightScale
		if env.sunR == nil or math.abs(k - env.sunR) > 0.01 then
			env.sunR = k
			local sd = base.sun
			pcall(e.SetSunDiffuse, sd.r * k, sd.g * k, sd.b * k)
		end
	end
end

------------------------------------------------------------------------
-- Rain
------------------------------------------------------------------------
local rain = {
	carryGround = 0, carrySheets = 0,
	nextTick = 0, nextPuddle = 0,
	soundFile = nil, soundVol = 0,
	level = 0,
}

-- The rain loop is restarted only when the wanted volume moves by 12 or more
-- (StartSound cannot change the volume of a playing loop).
local function rainSound(player, volume)
	local file = nil
	if volume > 0 then
		if IsPerson(player) then
			file = "erain01.wav"
		elseif IsCraft(player) then
			file = "erain02.wav"
		else
			file = rain.soundFile
		end
	end
	if file == rain.soundFile and (file == nil or math.abs(volume - rain.soundVol) < 12) then return end
	if rain.soundFile then StopSound(rain.soundFile) end
	rain.soundFile, rain.soundVol = file, volume
	if file then StartSound(file, nil, 100, true, math.floor(volume + 0.5)) end
end

-- Emits at 10 Hz. Counts are per tick and may be fractional: the remainder
-- carries, so density follows the intensity smoothly instead of in steps.
local function emitRain(player, ground, sheets, puddleChance)
	local now = GetTime()
	if now < rain.nextTick then return end
	rain.nextTick = now + 0.1
	local pos = GetPosition(player)
	if pos == nil then return end
	local math_random = math.random
	local px, py, pz = pos.x, pos.y, pos.z
	local fx, fz = flatFront(player)

	-- Ground splashes: a ripple ring, plus the crown of drops thrown up nearby.
	rain.carryGround = rain.carryGround + ground
	local n = math.floor(rain.carryGround)
	rain.carryGround = rain.carryGround - n
	for _ = 1, n do
		splash(px, py, pz, fx, fz, "xraindr", "xrainsp")
	end

	-- Rain sheets 35-120 m ahead in a +-50 degree arc, where they can be seen.
	rain.carrySheets = rain.carrySheets + sheets
	n = math.floor(rain.carrySheets)
	rain.carrySheets = rain.carrySheets - n
	if n > 0 then
		local at = place()
		for _ = 1, n do
			local a = math.rad(math_random() * 100 - 50)
			local ca, sa = math.cos(a), math.sin(a)
			local d = math.sqrt(35 * 35 + math_random() * (120 * 120 - 35 * 35))
			at.x = px + (fx * ca - fz * sa) * d
			at.z = pz + (fx * sa + fz * ca) * d
			at.y = py - 10 + math_random() * 35
			MakeExplosion("xrain", at) --rain sheets
		end
	end

	-- Large puddles on flat ground only, at most one a second.
	if now >= rain.nextPuddle then
		rain.nextPuddle = now + 1
		if math_random() < puddleChance then
			local at = place()
			at.x = px + math_random(-100, 100)
			at.z = pz + math_random(-100, 100)
			at.y = py + 5
			local height, normal = GetFloorHeightAndNormal(at)
			if normal ~= nil and DotProduct(normal, up()) > dotProductTolerance then
				at.y = height
				MakeExplosion("xpuddle", at)
			end
		end
	end
end

-- Particle rain when EXU can draw it; the explosion sheets are the fallback.
-- Returns the sheet count to spawn (0 with particles), or nil for "use sheets".
local function particleRain(i)
	if precip and precip.Set("rain", i) then
		precip.SetWind(0.8, 0.35, 3 + 13 * i)
		return 0
	end
	return nil
end

--- Rain at a continuous intensity: 0 is dry, 1 is the old "Heavy" preset.
local function Rain(intensity)
	local i = clamp(tonumber(intensity) or 0, 0, 1)
	rain.level = i
	local player = GetPlayerHandle()
	local sheets = particleRain(i) or 2.2 * i
	-- Ground splashes as particles when EXU can draw them, explosions otherwise.
	local ground = 16 * i
	if splashfx ~= nil and splashfx.Set("rain", i) then ground = 0 end
	if i > 0.01 then
		emitRain(player, ground, sheets, i)
	end
	if wetglass then wetglass.Update(i) end
	local volume = 0
	if i > 0.06 or (rain.soundFile ~= nil and i > 0.04) then volume = 45 + 55 * i end
	rainSound(player, volume)
end

--- Slowly falling green rain with green ground splashes.
local function AcidRain()
	-- Particle splashes are asked for every frame (a gap reads as "stop"); the
	-- explosion fallback below keeps its 10 Hz tick.
	local particleSplash = splashfx ~= nil and splashfx.Set("acid", 0.5)
	-- Time-based: one xraina explosion per rendered frame piled up at high altitude.
	if GetTime() < acidRainEmissionTimer then return end
	acidRainEmissionTimer = GetTime() + 0.1

	local DropsCount = 1
	local math_random = math.random
	local playerHandle = GetPlayerHandle()
	if not IsValid(playerHandle) then return end

	local PlayerPos = GetPosition(playerHandle)
	if PlayerPos == nil then return end
	local PlayerPos_x = PlayerPos.x
	local PlayerPos_z = PlayerPos.z
	local PlayerPos_y = PlayerPos.y
	local fx, fz = flatFront(playerHandle)

	-- Particle acid rain when EXU can draw it; otherwise sheets 20-90 m ahead in
	-- a +-50 degree arc, where they can be seen.
	if precip and precip.Set("acid", 1) then
		precip.SetWind(0.6, 0.8, 5)
		DropsCount = 0
	end
	local at = place()
	for _ = 1, DropsCount do
		local a = math.rad(math_random() * 100 - 50)
		local d = math.sqrt(20 * 20 + math_random() * (90 * 90 - 20 * 20))
		local ca, sa = math.cos(a), math.sin(a)
		at.x = PlayerPos_x + (fx * ca - fz * sa) * d
		at.z = PlayerPos_z + (fx * sa + fz * ca) * d

		-- Cap emission to 30 m above local terrain so jetpack altitude cannot
		-- multiply the lifetime of falling acid-rain effects.
		local terrainProbe = SetVector(at.x, PlayerPos_y, at.z)
		local terrainHeight = GetTerrainHeightAndNormal(terrainProbe)
		if terrainHeight ~= nil then
			at.y = math.min(PlayerPos_y, terrainHeight + 30)
		else
			at.y = PlayerPos_y
		end

		MakeExplosion("xraina", at)
	end

	-- Acid splashes: green copies of the rain's ripple and crown, 8 a tick
	-- (none while CRSplash draws them as particles).
	if particleSplash then return end
	acidSplashCarry = acidSplashCarry + 8
	local n = math.floor(acidSplashCarry)
	acidSplashCarry = acidSplashCarry - n
	for _ = 1, n do
		splash(PlayerPos_x, PlayerPos_y, PlayerPos_z, fx, fz, "xraindra", "xrainspa")
	end
end

------------------------------------------------------------------------
-- Lightning
--
-- A strike is placed ahead of the player (sometimes anywhere around them)
-- inside the fog, where it can be seen. Thunder is delayed by the distance at
-- 343 m/s and picked by range: a crack up close, a rumble far away. About 30 %
-- are in-cloud flashes that never reach the ground.
------------------------------------------------------------------------
local THUNDER_NEAR = { "thunder.wav", "thund02.wav" }
local THUNDER_MID = { "xlitblt1.wav", "xlitblt2.wav" }
local THUNDER_FAR = { "xlitblt3.wav", "atlas.wav" }
local BOLT_ROOT = 135     -- channel sprite centre above the ground (sprite radius 150)
local STRIKE_GAP = 2.5    -- minimum seconds between strikes
local bolt = { last = -100, clock = nil, events = {}, sounds = {} }
-- "particles": the channel is a fresh jagged, branching path of Ogre particles
-- every strike (CRGroundFX) and the ground flash, sparks and steam are
-- particles too; the engine keeps the strike's light and scorch mark.
-- "sprites": the old xbolt/xbgnd explosions. Without EXU particles it is
-- always sprites.
local BOLT_STYLE = "particles"
local BOLT_COLOUR = { y = { 1.00, 0.86, 0.60 }, w = { 0.82, 0.88, 1.00 } }

local function defaultPalette()
	return (trn().world == "Other") and "w" or "y"
end

local function pick(list) return list[1 + math.floor(rand() * #list)] end

local function Strike(palette, cloudOnly)
	local player = GetPlayerHandle()
	local pos = GetPosition(player)
	if pos == nil then return end
	local fx, fz = 0, 1
	local front = GetFront(player)
	if front ~= nil then
		local len = math.sqrt(front.x * front.x + front.z * front.z)
		if len > 0.001 then fx, fz = front.x / len, front.z / len end
	end
	local angle
	if rand() < 0.8 then angle = math.rad(randRange(-55, 55)) else angle = rand() * 2 * math.pi end
	local maxD = clamp(trn().fogEnd * env.fogScale * 0.8, 120, 360)
	local d = randRange(60, maxD)
	local ca, sa = math.cos(angle), math.sin(angle)
	local x = pos.x + (fx * ca - fz * sa) * d
	local z = pos.z + (fx * sa + fz * ca) * d
	local ground = GetTerrainHeightAndNormal(SetVector(x, pos.y, z))
	if ground == nil then return end
	local near = 1 - (d - 60) / math.max(1, maxD - 60) -- 1 close .. 0 far
	local now = GetTime()
	local ev = bolt.events

	if cloudOnly then
		local sky = SetVector(x, ground + randRange(220, 320), z)
		ev[#ev + 1] = { at = now, odf = "xbsky" .. palette, pos = sky, flash = 0.25 + 0.2 * near }
		if rand() < 0.6 then
			ev[#ev + 1] = { at = now + randRange(0.08, 0.25), odf = "xbsky" .. palette, pos = sky, flash = 0.2 }
		end
	else
		local channel = SetVector(x, ground + BOLT_ROOT, z)
		local c = BOLT_COLOUR[palette] or BOLT_COLOUR.w
		local particles = BOLT_STYLE == "particles" and lavafx ~= nil and lavafx.Bolt(x, ground, z, c[1], c[2], c[3])
		local variant = "xbolt" .. palette .. (1 + math.floor(rand() * 4))
		local t = now
		for k = 1, 1 + math.floor(rand() * 3.4) do
			ev[#ev + 1] = { at = t, odf = (not particles) and variant or nil, stroke = particles, pos = channel,
				flash = (k == 1) and (0.55 + 0.45 * near) or (0.35 + 0.35 * near) }
			t = t + randRange(0.05, 0.16)
		end
		local groundAt = SetVector(x, ground, z)
		if particles then
			-- Light and scorch stay with the engine; flash, sparks and steam are particles.
			ev[#ev + 1] = { at = now, odf = "xbgnd" .. palette .. "l", strike = c, pos = groundAt, flash = 0 }
		else
			ev[#ev + 1] = { at = now, odf = "xbgnd" .. palette, pos = groundAt, flash = 0 }
		end
		ev[#ev + 1] = { at = now, odf = "xbsky" .. palette, pos = SetVector(x, ground + 300, z), flash = 0 }
	end

	local list, volume
	if cloudOnly then
		list, volume = THUNDER_FAR, 45 + 25 * near
	elseif d < 130 then
		list, volume = THUNDER_NEAR, 100
	elseif d < 240 then
		list, volume = THUNDER_MID, 90
	else
		list, volume = THUNDER_FAR, 75
	end
	local delay = d / 343
	if cloudOnly then delay = delay + randRange(0.5, 2.0) end
	bolt.sounds[#bolt.sounds + 1] = { at = now + delay, file = pick(list), volume = math.floor(volume) }
end

local function runLightningEvents(now)
	if lavafx then lavafx.Update() end   -- strike particle slots switch off here
	local ev = bolt.events
	local i = 1
	while i <= #ev do
		local e = ev[i]
		if now >= e.at then
			if e.odf then MakeExplosion(e.odf, e.pos) end
			if e.stroke and lavafx then lavafx.BoltStroke() end
			if e.strike and lavafx then
				local c = e.strike
				lavafx.SetColour("strike", c[1], c[2], c[3], 1, "sparks")
				lavafx.SetColour("strike", c[1], c[2], c[3], 1, "flash")
				lavafx.Event("strike", e.pos)
			end
			if e.flash > env.flash then env.flash = e.flash end
			table.remove(ev, i)
		else
			i = i + 1
		end
	end
	local snd = bolt.sounds
	i = 1
	while i <= #snd do
		local s = snd[i]
		if now >= s.at then
			StartSound(s.file, nil, nil, false, s.volume)
			table.remove(snd, i)
		else
			i = i + 1
		end
	end
end

--- Lightning at an average rate of perMinute strikes a minute (0 = none).
--- Also advances the flash and the EXU environment, so call it every Update.
local function Lightning(perMinute, palette)
	local now = GetTime()
	local dt = 0
	if bolt.clock ~= nil then
		dt = now - bolt.clock
		if dt < 0 or dt > 0.5 then dt = 0 end
	end
	bolt.clock = now
	perMinute = tonumber(perMinute) or 0
	-- A constant hazard, so a gradual change of rate is a gradual change of
	-- frequency, with a short refractory gap after each strike.
	if perMinute > 0 and #bolt.events == 0 and now - bolt.last >= STRIKE_GAP then
		if rand() < perMinute / 60 * dt then
			bolt.last = now
			Strike(palette or defaultPalette(), rand() < 0.3)
		end
	end
	runLightningEvents(now)
	applyEnvironment(now, dt)
end

--- One strike at once, outside the schedule; cloudOnly = true for an in-cloud
--- flash. Lightning() must still run every Update (Storm.Update does): it plays
--- the strokes, the thunder and the flash.
local function StrikeNow(cloudOnly, palette)
	bolt.last = GetTime()
	Strike(palette or defaultPalette(), cloudOnly == true)
end

local RAIN_PRESETS = {
	-- Heavy was 12 splashes a tick, fewer than Medium's 15.
	Light  = { level = 0.35, ground = 7,  sheets = 1, volume = 80,  bolts = 1.0 },
	Medium = { level = 0.65, ground = 12, sheets = 1, volume = 95,  bolts = 2.0 },
	Heavy  = { level = 1.00, ground = 16, sheets = 2, volume = 100, bolts = 3.0 },
}

--- Overcast without the weather director: scales the map's fog distance and
--- light (1 = as authored) through EXU, eased by the caller. Call every Update.
local function Atmosphere(fogScale, lightScale)
	env.fogScale = tonumber(fogScale) or 1
	env.lightScale = tonumber(lightScale) or 1
	Lightning(0)
end

--- Fixed rain with lightning. Call from Update with "Light", "Medium" or "Heavy".
local function RainAndBolt(intensity)
	local p = RAIN_PRESETS[intensity]
	if p == nil then return end
	local player = GetPlayerHandle()
	rain.level = p.level
	emitRain(player, p.ground, particleRain(p.level) or p.sheets, 1)
	if wetglass then wetglass.Update(p.level) end
	rainSound(player, p.volume)
	Lightning(p.bolts)
end

------------------------------------------------------------------------
-- Dynamic weather
--
-- Each state is a target: rain intensity, lightning strikes a minute, a fog
-- distance multiplier and a light multiplier. The director holds a state,
-- then blends toward a neighbour over 35-80 s with smoothstep; targets are
-- jittered each time, and a slow gust modulates the rain, so no two visits to
-- a state look quite alike. States only step to neighbours, so clear never
-- jumps straight to storm.
------------------------------------------------------------------------
local WEATHER = {
	clear    = { rain = 0.00, bolts = 0.0, fog = 1.30, light = 1.00, next = { overcast = 1 } },
	overcast = { rain = 0.00, bolts = 0.4, fog = 1.10, light = 0.84, next = { clear = 2, drizzle = 2, rain = 1 } },
	drizzle  = { rain = 0.30, bolts = 0.0, fog = 0.95, light = 0.78, next = { overcast = 2, rain = 2 } },
	rain     = { rain = 0.65, bolts = 1.5, fog = 0.82, light = 0.70, next = { drizzle = 2, storm = 2, overcast = 1 } },
	storm    = { rain = 1.00, bolts = 6.0, fog = 0.65, light = 0.58, next = { rain = 1 } },
}
local WEATHER_KEYS = { "rain", "bolts", "fog", "light" }
local dyn = nil       -- live state; the mission keeps this table in M so it saves
local dynOptions = {} -- not saved: the mission passes the same options on load

local function pickWeighted(weights)
	local names, total = {}, 0
	for name, w in pairs(weights) do
		if WEATHER[name] and w > 0 then
			names[#names + 1] = name
			total = total + w
		end
	end
	table.sort(names)
	local r = rand() * total
	for _, name in ipairs(names) do
		r = r - weights[name]
		if r <= 0 then return name end
	end
	return names[#names] or "overcast"
end

local function targetFor(name)
	local s = WEATHER[name]
	local function jitter(v, spread) return v * (1 + spread * (rand() * 2 - 1)) end
	return {
		rain = clamp(jitter(s.rain, 0.15), 0, 1),
		bolts = math.max(0, jitter(s.bolts, 0.3)),
		fog = jitter(s.fog, 0.06),
		light = jitter(s.light, 0.05),
	}
end

local function range(pair, a, b)
	if type(pair) == "table" and pair[1] and pair[2] then return randRange(pair[1], pair[2]) end
	return randRange(a, b)
end

local function currentWeather()
	local t = 1
	local span = dyn.t1 - dyn.t0
	if span > 0 then
		t = clamp((dyn.clock - dyn.t0) / span, 0, 1)
		t = t * t * (3 - 2 * t)
	end
	local out = {}
	for _, k in ipairs(WEATHER_KEYS) do
		out[k] = dyn.from[k] + (dyn.to[k] - dyn.from[k]) * t
	end
	return out
end

local function blendTo(name, seconds)
	dyn.from = currentWeather()
	dyn.to = targetFor(name)
	dyn.name = name
	dyn.t0 = dyn.clock
	dyn.t1 = dyn.clock + math.max(1, seconds)
	dyn.hold = dyn.t1 + range(dynOptions.hold, 90, 240)
end

--- Starts (or, given the saved table, resumes) the dynamic weather.
--- Store the result in the mission's M and pass it back after a load:
---   M.weather = Storm.StartDynamicWeather(M.weather, { start = { rain = 3, storm = 2 } })
--- options: start = weights of the opening state, hold = {min, max} seconds a
--- state is held, blend = {min, max} seconds a change takes, palette = "w"/"y".
local function StartDynamicWeather(saved, options)
	dynOptions = options or {}
	if type(saved) == "table" and WEATHER[saved.name] and type(saved.from) == "table"
		and type(saved.to) == "table" and tonumber(saved.clock) then
		dyn = saved
	else
		local first = pickWeighted(dynOptions.start or { overcast = 1, drizzle = 1, rain = 2, storm = 1 })
		local t = targetFor(first)
		dyn = { name = first, from = t, to = t, t0 = 0, t1 = 0, clock = 0,
			gust1 = rand() * 6.2832, gust2 = rand() * 6.2832 }
		dyn.hold = range(dynOptions.hold, 90, 240)
	end
	dyn.lastTime = nil
	return dyn
end

--- Advances the dynamic weather; call every Update in place of RainAndBolt.
local function UpdateDynamicWeather()
	if dyn == nil then return end
	local now = GetTime()
	local dt = 0
	if dyn.lastTime ~= nil then
		dt = now - dyn.lastTime
		if dt < 0 or dt > 0.5 then dt = 0 end
	end
	dyn.lastTime = now
	dyn.clock = dyn.clock + dt
	if dyn.clock >= dyn.t1 and dyn.clock >= dyn.hold then
		blendTo(pickWeighted(WEATHER[dyn.name].next), range(dynOptions.blend, 35, 80))
	end
	local v = currentWeather()
	local c = dyn.clock
	local gust = 1 + 0.12 * math.sin(c * 0.21 + dyn.gust1) + 0.08 * math.sin(c * 0.53 + dyn.gust2)
	env.fogScale, env.lightScale = v.fog, v.light
	Rain(v.rain * gust)
	Lightning(v.bolts, dynOptions.palette)
end

--- Scripted change: blend to a named state over `seconds` (default 30), hold
--- it, then carry on at random. Returns false for an unknown state.
local function SetWeather(name, seconds)
	if dyn == nil or WEATHER[name] == nil then return false end
	blendTo(name, tonumber(seconds) or 30)
	return true
end

--- Name of the current (or incoming) state and its blended values.
local function GetWeather()
	if dyn == nil then return nil end
	return dyn.name, currentWeather()
end

--- Rain intensity 0..1 drawn this frame (for scripted extras such as cutscene rain).
local function GetRainIntensity()
	return rain.level
end

------------------------------------------------------------------------
-- Per-frame driver and shutdown
------------------------------------------------------------------------

--- Everything a mission needs each frame, in the order the ISDF Chronicles
--- mission loop and test range ran it: last frame's particle requests reach
--- Ogre (a frame nobody asked for a kind stops it), then the director steps
--- (rain, splashes, strikes, fog and light). With no director, strikes fired
--- by hand and the lightning flash still play out once the environment has
--- been captured. Cheap when nothing is going on.
local function Update()
	if precip then precip.Update() end
	if splashfx then splashfx.Update() end
	if lavafx then lavafx.Update() end
	if dyn ~= nil then
		UpdateDynamicWeather()
	elseif env.base ~= nil or #bolt.events > 0 or #bolt.sounds > 0 or env.flash > 0 then
		Lightning(0)
	end
end

--- Puts everything back: stops rain, acid, snow and dust precipitation and the
--- splash and strike particles, stops the rain sound loop, drops pending
--- strikes and ends the director. Fog, ambient light and sun go back to what
--- was captured before the first write, once; a second call, or a call when
--- nothing was captured, restores nothing.
local function Shutdown()
	pcall(function()
		if rain.soundFile then StopSound(rain.soundFile) end
	end)
	rain.soundFile, rain.soundVol, rain.level = nil, 0, 0
	rain.carryGround, rain.carrySheets, rain.nextTick, rain.nextPuddle = 0, 0, 0, 0
	acidRainEmissionTimer, acidSplashCarry = 0, 0
	bolt.events, bolt.sounds, bolt.last, bolt.clock = {}, {}, -100, nil
	dyn, dynOptions = nil, {}

	if precip then pcall(precip.Stop) end
	if splashfx then pcall(splashfx.Stop) end
	if lavafx then pcall(lavafx.Stop) end
	if wetglass and wetglass.Stop then pcall(wetglass.Stop) end

	local base, e = env.base, env.lib
	if base ~= nil and e ~= nil then
		if env.fogE ~= nil and base.fog and type(e.SetFog) == "function" then
			local b = base.fog
			pcall(e.SetFog, b.r, b.g, b.b, b.start, b.ending)
		end
		if env.ambR ~= nil and base.amb and type(e.SetAmbientLight) == "function" then
			local a = base.amb
			pcall(e.SetAmbientLight, a.r, a.g, a.b)
		end
		if env.sunR ~= nil and base.sun and type(e.SetSunDiffuse) == "function" then
			local sd = base.sun
			pcall(e.SetSunDiffuse, sd.r, sd.g, sd.b)
		end
	end
	env.lib, env.base, env.nextProbe = nil, nil, 0
	env.fogScale, env.lightScale, env.flash = 1, 1, 0
	env.nextFog, env.nextSun = 0, 0
	env.fogS, env.fogE, env.fogR, env.ambR, env.ambK, env.sunR = nil, nil, nil, nil, nil, nil
	env.tintFog, env.tintAmb, env.fogKey = nil, nil, nil
end

--- The fog, ambient and sun captured before the weather first changed them:
--- { fog = {r,g,b,start,ending}, amb = {r,g,b}, sun = {r,g,b} } (each may be
--- nil), or nil while nothing has been captured.
local function BaseEnvironment()
	return env.base
end

--- Asks CRPrecip for a kind ("rain", "acid", "snow", "dust") at 0..1 this
--- frame. Returns true while the particle layer draws it.
local function Precip(kind, level)
	if precip == nil then return false end
	return precip.Set(kind, level) == true
end

--- Sets the wind for particle precipitation and dust splashes: a sim-space
--- ground direction (x, z) and a speed in m/s.
local function Wind(x, z, speed)
	if precip then precip.SetWind(x, z, speed) end
	if splashfx then splashfx.SetWind(x, z, speed) end
end

--- Overrides the colour the weather fogs and lights toward ({r, g, b} 0..1, or
--- nil for the map's own). The director still scales distance and brightness;
--- the caller eases the colour by calling this every frame. Shutdown clears it.
local function SetTint(fog, ambient)
	local function colour(c)
		if type(c) ~= "table" then return nil end
		return { r = clamp(tonumber(c.r) or 0, 0, 1), g = clamp(tonumber(c.g) or 0, 0, 1), b = clamp(tonumber(c.b) or 0, 0, 1) }
	end
	env.tintFog, env.tintAmb = colour(fog), colour(ambient)
end

Storm.SetTint = SetTint
Storm.Rain = Rain
Storm.AcidRain = AcidRain
Storm.Lightning = Lightning
Storm.StrikeNow = StrikeNow
Storm.Atmosphere = Atmosphere
Storm.RainAndBolt = RainAndBolt
Storm.StartDynamicWeather = StartDynamicWeather
Storm.UpdateDynamicWeather = UpdateDynamicWeather
Storm.SetWeather = SetWeather
Storm.GetWeather = GetWeather
Storm.GetRainIntensity = GetRainIntensity
Storm.SeedRandom = SeedRandom
Storm.Update = Update
Storm.Shutdown = Shutdown
Storm.BaseEnvironment = BaseEnvironment
Storm.Precip = Precip
Storm.Wind = Wind

return Storm
