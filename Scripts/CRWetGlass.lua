--**********************************************************************
-- CRWETGLASS: raindrops on the windshield (port of the ISDF Chronicles wetglass.lua).
--
-- Module name CRWetGlass; materials CRWX_*, files crwx_*; no globals, nothing runs at require time.
-- Optional: CRStormFX requires it and feeds it the rain intensity.
--
-- Drops are drawn on the screen itself with Extra Utilities overlays, so they
-- stay on the glass whatever the craft does. Four bead layers fade in, sit and
-- fade away on slow, staggered cycles, never more than three at once, so the
-- glass is always part-clear; heavier rain allows more of them at a time. On still glass two rivulet layers of long, thin water tracks creep
-- down between them. At speed the airflow blows the beads and rivulets away and
-- a streak layer of drops racing up the glass takes over. When the rain stops
-- the glass dries.
--
-- Shown only for a craft in a first-person view (F1, F2, F5), never on foot,
-- in the chase/orbit cameras, the satellite view or a menu. Without EXU (or
-- an EXU without overlays) it does nothing.
--
-- Textures and the alpha-stepped materials (crwx_wetglass.material) come from the ISDFC tools/wetglassgen.py.
-- Drops show only through the canopy glass where the craft has a cockpit
-- mask (MASKS, made by the ISDFC tools/wetmaskgen.py; CR ships none, so the open mask is used);
-- elsewhere they cover the view.
-- The camera pitches and rolls against the cockpit as the craft moves, so each
-- frame the camera's rotation in the craft frame goes to the shader through the
-- mask unit's texture transform (see crwx_wetglass.hlsl) and the mask turns
-- with the cockpit.
-- Call CRWetGlass.Update(intensity 0..1) every Update; CRStormFX.Rain does. Several callers in one frame are fine: the largest wins.
--
-- COCKPIT GLASS. In the cockpit view (F1), a craft whose cockpit mesh carries an
-- CRWX_CockpitGlass submesh (Tools/cockpitglass.py adds one over the window
-- openings, just outside the frame) gets every layer on that glass instead of the
-- screen: EXU moves the glass sub-entity of the cockpit entity into render queue
-- group GLASS_GROUP (after the world; the rest of the cockpit draws in group 10,
-- before terrain, and its depth hides the glass behind the frame, struts and dash)
-- and swaps its material for CRWX_CockpitGlass_W<a>C<b> (crwx_cockpitglass.material):
-- one pass per visible layer, wrap layers first, each pointed at its texture and
-- window (exu.SetMaterialTextureWindow) and faded by its pass diffuse alpha. The
-- glass UVs are view angles (U_SPAN x V_SPAN per unit), so the windows are the
-- overlay's with SHELL_AR for the aspect, and crack/splat screen positions are
-- turned into view angles. Without that EXU support, without glass on the craft, or
-- in F2/F5, the screen overlay draws them as before.
--
-- The same overlay also carries two damage layers for a damage caller (none in CR yet), drawn with the same mask, canopy
-- mapping and opacity steps (the ISDFC tools/windshieldgen.py makes their textures):
--   CRWetGlass.SetCrack(level 0..1, x, y)   an impact star at screen fraction (x, y); level 0 clears it (fast fade)
--   CRWetGlass.Splat(amount 0..1, x, y, flip) a dirt splat that fades over a few seconds (3 at once)
--   CRWetGlass.Busy()                        true while either is on the glass: keep calling Update(0)
--   CRWetGlass.ClearSplats()
--
-- WEATHER LAYERS (not rain). Two more wrap families on the same glass, driven by weather directors
-- (CREuropaWeather snow, CRMarsWeather grit) through CRWetGlass.Weather(kind, level 0..1), then Update(0):
--   "snow"  CRWX_WinSnow: two layers of sparse soft-white flakes that gather over seconds, sit, melt away and
--           return elsewhere on staggered cycles; no streaks, never covers the view
--   "grit"  CRWX_WinGrit: two layers of fine tan specks that stay put and follow the level (the director
--           shapes the slow build and clear)
-- Rain wins the pass budget: the weather layers are the last wrap layers. Textures: crwx_winsnow.png and
-- crwx_wingrit.png, materials crwx_glassweather.material, both made by Tools/Generate-GlassWeatherAssets.py.
--**********************************************************************
local wetglass = {}

local STEPS = 16            -- opacity steps in crwx_wetglass.material
local BEAD_LAYERS = 4
local RIVULET_LAYERS = 2
local OVERLAY = "crwx_wetglass"
local Z_ORDER = 5           -- under custom HUD overlays
local VIEW_OK = { [1] = true, [2] = true, [3] = true } -- cockpit, no cockpit, no HUD
local FAMILIES = { "CRWX_WetBeads", "CRWX_WetStreak", "CRWX_WetRivulet", "CRWX_WindCrack", "CRWX_WindDirt",
	"CRWX_WinSnow", "CRWX_WinGrit" }
local DIRT_LAYERS = 3
local SNOW_LAYERS = 2       -- crwx_glassweather.material; Weather("snow", level)
local GRIT_LAYERS = 2       -- crwx_glassweather.material; Weather("grit", level)
local SNOW_PEAK = 0.60      -- opacity of the snow layers at level 1 (the sheet itself is sparse)
local GRIT_PEAK = 0.50      -- opacity of the grit layers at level 1
local CRACK_PEAK = 0.9      -- opacity of a fully cracked windshield
local CRACK_RATE = 6        -- opacity per second the crack fades in and out at

-- Cockpit glass masks by craft ODF. The shader keeps drops off the frame and
-- dash; any other craft uses the open mask (drops over the whole view).
local OPEN_MASK = "crwx_wetmask_open.png"
local MASKS = {
	-- [odf] = "crwx_wetmask_<odf>.png"   (none shipped: every craft uses the open mask)
}
local MASKED_TECHNIQUES = { 0, 1 } -- SM4 and SM3 techniques; unit 1 is the mask
local POSE_EPS = 0.002      -- radians; smaller camera moves do not touch Ogre
local POSE_MAX = 0.6        -- radians; beyond this the camera is not in the cockpit

-- Cockpit glass (Tools/cockpitglass.py, crwx_cockpitglass.material).
local GLASS_BASE = "CRWX_CockpitGlass"      -- the no-op every glass submesh ships with
local GLASS_GROUP = 90                       -- after the world and effects, before overlays (100)
local SHELL_AR = 96 / 64                     -- glass UV: 96 deg of yaw, 64 deg of pitch per unit
local U_SPAN, V_SPAN = math.rad(96), math.rad(64)
local SHELL_STEPS = 32                       -- glass opacity steps (pass diffuse alpha)
local SHELL_RGB = 0.45                       -- pass diffuse colour (lit: ambient + diffuse * sun)
local MAX_WRAP, MAX_CLAMP = 7, 4             -- passes in the largest CRWX_CockpitGlass_W<a>C<b>
local LAYER_TEXTURE = {
	CRWX_WetBeads = "crwx_wetbeads.png", CRWX_WetRivulet = "crwx_wetrivulet.png",
	CRWX_WetStreak = "crwx_wetstreak.png", CRWX_WindCrack = "crwx_windcrack.png",
	CRWX_WindDirt = "crwx_winddirt.png",
	CRWX_WinSnow = "crwx_winsnow.png", CRWX_WinGrit = "crwx_wingrit.png",
}
-- Pass diffuse colour where a layer wants more than SHELL_RGB: snow stays pale in dim Europan light.
local LAYER_RGB = { CRWX_WinSnow = 0.92 }
local CLAMPED = { CRWX_WindCrack = true, CRWX_WindDirt = true }
local SHELL_API = { "SetSubEntityRenderQueueGroup", "SetSubEntityMaterial", "SetMaterialTextureWindow",
	"SetMaterialTexture", "SetMaterialPassColors" }

local exu = nil
local state = nil           -- nil = not built yet, false = unavailable
local frame, pending = nil, 0
local lastRun = nil
local crackWant, crackX, crackY = 0, 0.5, 0.4   -- what the damage caller asked for; applied by run()
local splats = {}                               -- queued { amount, x, y, flip }
local snowWant, gritWant = 0, 0                 -- Weather() levels 0..1, kept until changed
local mode = "overlay"                          -- where the layers draw this frame: "overlay" or "shell"

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function smoothstep(a, b, x)
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function randRange(a, b) return a + (b - a) * math.random() end

-- EXU is a module in CR. A stub (isStub) means no native runtime: do nothing.
local function findExu()
	local e = package and package.loaded and package.loaded["exu"]
	if type(e) ~= "table" then
		local ok, m = pcall(require, "exu")
		e = ok and m or nil
	end
	if type(e) == "table" and e.isStub ~= true then return e end
	return nil
end

local REQUIRED = {
	"CreateOverlay", "DestroyOverlay", "ShowOverlay", "HideOverlay", "SetOverlayZOrder",
	"CreateOverlayElement", "DestroyOverlayElement", "AddOverlay2D", "ShowOverlayElement",
	"HideOverlayElement", "SetOverlayMetricsMode", "SetOverlayPosition", "SetOverlayDimensions",
	"SetOverlayMaterial", "SetOverlayParameter",
}

local function call(fn, ...)
	local ok, r = pcall(exu[fn], ...)
	return ok and r ~= false
end

local function aspect()
	local ok, a = pcall(exu.GetCameraAspectRatio or function() end)
	if ok and type(a) == "number" and a > 0.2 and a < 6 then return a end
	ok, a = pcall(function()
		local w, h = exu.GetGameResolution()
		return w / h
	end)
	if ok and type(a) == "number" and a > 0.2 and a < 6 then return a end
	return 16 / 9
end

local function newPanel(name, family)
	-- EXU keeps overlays across Lua states: clear one left by an earlier load.
	pcall(exu.DestroyOverlayElement, name)
	if not call("CreateOverlayElement", "Panel", name) then return nil end
	call("SetOverlayMetricsMode", name, 0)
	call("SetOverlayPosition", name, 0, 0)
	call("SetOverlayDimensions", name, 1, 1)
	call("AddOverlay2D", OVERLAY, name)
	call("HideOverlayElement", name)
	return { name = name, family = family, step = 0, alpha = 0 }
end

local function build()
	exu = findExu()
	if exu == nil then return false end
	for _, fn in ipairs(REQUIRED) do
		if type(exu[fn]) ~= "function" then return false end
	end
	pcall(exu.DestroyOverlay, OVERLAY)
	if not call("CreateOverlay", OVERLAY) then return false end
	call("SetOverlayZOrder", OVERLAY, Z_ORDER)
	local s = { beads = {}, visible = false, streakV = 0, mask = OPEN_MASK, posed = {} }
	for k = 1, BEAD_LAYERS do
		local p = newPanel(OVERLAY .. "_b" .. k, "CRWX_WetBeads")
		if p == nil then return false end
		p.phase, p.wait = "off", randRange(0, 0.8) * k
		s.beads[k] = p
	end
	s.streak = newPanel(OVERLAY .. "_s", "CRWX_WetStreak")
	if s.streak == nil then return false end
	s.rivulets = {}
	for k = 1, RIVULET_LAYERS do
		local p = newPanel(OVERLAY .. "_r" .. k, "CRWX_WetRivulet")
		if p == nil then return false end
		p.phase, p.wait = "off", randRange(0.5, 2.5) * k
		s.rivulets[k] = p
	end
	s.crack = newPanel(OVERLAY .. "_c", "CRWX_WindCrack")
	if s.crack == nil then return false end
	s.dirt = {}
	for k = 1, DIRT_LAYERS do
		local p = newPanel(OVERLAY .. "_d" .. k, "CRWX_WindDirt")
		if p == nil then return false end
		p.phase = "off"
		s.dirt[k] = p
	end
	s.snow, s.grit = {}, {}
	for k = 1, SNOW_LAYERS do
		local p = newPanel(OVERLAY .. "_n" .. k, "CRWX_WinSnow")
		if p == nil then return false end
		p.phase, p.wait = "off", (k - 1) * randRange(6, 11)
		s.snow[k] = p
	end
	for k = 1, GRIT_LAYERS do
		local p = newPanel(OVERLAY .. "_g" .. k, "CRWX_WinGrit")
		if p == nil then return false end
		p.phase = "off"
		s.grit[k] = p
	end
	return s
end

-- Opacity is quantised to the material steps; only a change of step touches Ogre.
-- p.on says whether the layer shows at all (either mode); p.step is what the
-- overlay panel is showing, so it only changes in overlay mode.
local function setAlpha(p, a)
	p.alpha = a
	local step = math.floor(clamp(a, 0, 1) * STEPS + 0.5)
	p.on = step > 0
	if mode ~= "overlay" or step == p.step then return end
	if step == 0 then
		call("HideOverlayElement", p.name)
	else
		call("SetOverlayMaterial", p.name, p.family .. "_A" .. step)
		if p.step == 0 then call("ShowOverlayElement", p.name) end
	end
	p.step = step
end

local function setUV(p, u0, v0, du, dv)
	p.uv = { u0, v0, du, dv }
	if mode ~= "overlay" then return end
	call("SetOverlayParameter", p.name, "uv_coords",
		string.format("%.4f %.4f %.4f %.4f", u0, v0, u0 + du, v0 + dv))
end

-- Every layer, wrap layers first (pass order on the glass).
local function allLayers()
	local list = {}
	for _, p in ipairs(state.beads) do list[#list + 1] = p end
	for _, p in ipairs(state.rivulets) do list[#list + 1] = p end
	list[#list + 1] = state.streak
	-- Weather layers come last among the wrap layers: if the pass budget runs out, rain wins.
	for _, p in ipairs(state.snow) do list[#list + 1] = p end
	for _, p in ipairs(state.grit) do list[#list + 1] = p end
	list[#list + 1] = state.crack
	for _, p in ipairs(state.dirt) do list[#list + 1] = p end
	return list
end

-- Point every wet-glass material at the mask for the player's craft.
local function useMask(player)
	if type(exu.SetMaterialTexture) ~= "function" then return end
	local odf = string.lower(tostring(GetOdf(player) or "")):gsub("%.odf$", "")
	local want = MASKS[odf] or OPEN_MASK
	if want == state.mask then return end
	for _, family in ipairs(FAMILIES) do
		for k = 1, STEPS do
			for _, t in ipairs(MASKED_TECHNIQUES) do
				pcall(exu.SetMaterialTexture, family .. "_A" .. k, want, t, 0, 1)
			end
		end
	end
	state.mask = want
	state.posed = {}
end

local atan2 = math.atan2 or math.atan -- 5.1 (the game) / 5.3+

local function dot(m, a, n, b)
	return m[a .. "_x"] * n[b .. "_x"] + m[a .. "_y"] * n[b .. "_y"] + m[a .. "_z"] * n[b .. "_z"]
end

-- The camera's rotation in the craft's frame as yaw, pitch, roll (the camera
-- ray to cockpit ray is yaw(y) * pitch(x) * roll(z)), or nil when it cannot be
-- measured or the camera is not sitting in the cockpit.
local function cameraPose(player)
	if type(exu.GetCameraTransformMatrix) ~= "function" then return nil end
	local ok, cam = pcall(exu.GetCameraTransformMatrix)
	local craft = GetTransform(player)
	if not ok or cam == nil or craft == nil then return nil end
	-- A world-to-camera matrix here would put the camera far from the craft.
	local dx, dy, dz = cam.posit_x - craft.posit_x, cam.posit_y - craft.posit_y, cam.posit_z - craft.posit_z
	if dx * dx + dy * dy + dz * dz > 400 then return nil end
	local fx, fy, fz = dot(craft, "right", cam, "front"), dot(craft, "up", cam, "front"), dot(craft, "front", cam, "front")
	local rx, ry, rz = dot(craft, "right", cam, "right"), dot(craft, "up", cam, "right"), dot(craft, "front", cam, "right")
	local pitch = math.asin(clamp(fy, -1, 1))
	local yaw = atan2(fx, fz)
	-- Take yaw and pitch back off the camera's right axis; what is left is roll.
	local sy, cy, sp, cp = math.sin(yaw), math.cos(yaw), math.sin(pitch), math.cos(pitch)
	local ax, ay, az = cy * rx - sy * rz, ry, sy * rx + cy * rz
	local roll = atan2(cp * ay - sp * az, ax)
	if math.abs(yaw) > POSE_MAX or math.abs(pitch) > POSE_MAX or math.abs(roll) > POSE_MAX then return nil end
	return yaw, pitch, roll
end

-- Give the camera pose to the materials the panels are drawing with.
local function poseMask(player)
	if state.mask == OPEN_MASK or type(exu.SetMaterialTextureScroll) ~= "function"
		or type(exu.SetMaterialTextureRotate) ~= "function" then return end
	local yaw, pitch, roll = cameraPose(player)
	if yaw == nil then yaw, pitch, roll = 0, 0, 0 end
	local panels = { state.streak, state.crack }
	for _, p in ipairs(state.dirt) do panels[#panels + 1] = p end
	for _, p in ipairs(state.beads) do panels[#panels + 1] = p end
	for _, p in ipairs(state.rivulets) do panels[#panels + 1] = p end
	for _, p in ipairs(state.snow) do panels[#panels + 1] = p end
	for _, p in ipairs(state.grit) do panels[#panels + 1] = p end
	for _, p in ipairs(panels) do
		if p.step > 0 then
			local mat = p.family .. "_A" .. p.step
			local was = state.posed[mat]
			if was == nil or math.abs(was[1] - yaw) + math.abs(was[2] - pitch) + math.abs(was[3] - roll) > POSE_EPS then
				for _, t in ipairs(MASKED_TECHNIQUES) do
					pcall(exu.SetMaterialTextureScroll, mat, yaw, pitch, t, 0, 1)
					pcall(exu.SetMaterialTextureRotate, mat, roll, t, 0, 1)
				end
				state.posed[mat] = { yaw, pitch, roll }
			end
		end
	end
end

-- Screen fractions (x right, y down, 0..1) -> glass UV through the camera's FOV:
-- the glass UV is the view angle, U_SPAN / V_SPAN radians per unit.
local function screenToShell(x, y)
	local vfov = math.rad(64)
	local ok, f = pcall(exu.GetCameraFOV or function() end)
	if ok and type(f) == "number" and f > 0.2 and f < 3 then vfov = f end
	local ty = math.tan(vfov / 2)
	local tx = ty * aspect()
	local yaw = math.atan((2 * x - 1) * tx)
	local pitch = math.atan((1 - 2 * y) * ty)
	return 0.5 + yaw / U_SPAN, 0.5 - pitch / V_SPAN
end

local function shellCapable()
	if type(exu.animation) ~= "table" or type(exu.animation.TargetCockpit) ~= "function" then return false end
	for _, fn in ipairs(SHELL_API) do
		if type(exu[fn]) ~= "function" then return false end
	end
	local ok, caps = pcall(exu.animation.GetCapabilities or function() end)
	return ok and type(caps) == "table" and caps.glass == true
end

-- Finds the glass sub-entity on the player's cockpit entity and keeps it in GLASS_GROUP.
-- The cockpit entity is rebuilt on vehicle and view changes (back to GLASS_BASE, own
-- group lost), so this runs every frame: one cheap call while nothing changed.
local function shellBind(player)
	if state.shellOk == nil then state.shellOk = shellCapable() end
	if not state.shellOk then return false end
	local ok, v = pcall(exu.GetCameraView or function() return 1 end)
	if not ok or v ~= 1 then return false end         -- cockpit view only; F2/F5 use the overlay
	local okT, target = pcall(exu.animation.TargetCockpit, player)
	if not okT or target == nil then return false end
	local sh = state.shell
	if sh == nil or sh.handle ~= player then
		sh = { handle = player, mat = GLASS_BASE, passes = {} }
		state.shell = sh
	end
	local okQ, n, idx = pcall(exu.SetSubEntityRenderQueueGroup, target, sh.mat, GLASS_GROUP)
	if (not okQ or (tonumber(n) or 0) < 1) and sh.mat ~= GLASS_BASE then
		okQ, n, idx = pcall(exu.SetSubEntityRenderQueueGroup, target, GLASS_BASE, GLASS_GROUP)
		sh.mat, sh.passes = GLASS_BASE, {}
	end
	if not okQ or (tonumber(n) or 0) < 1 or idx == nil then return false end
	sh.target, sh.index = target, idx
	return true
end

-- Puts the visible layers on the glass: picks CRWX_CockpitGlass_W<a>C<b> and gives each
-- pass its layer's texture, window and opacity. Only what changed touches Ogre.
local function shellApply()
	local sh = state.shell
	local wrap, clamped = {}, {}
	for _, p in ipairs(allLayers()) do
		if p.on and p.uv then
			if CLAMPED[p.family] then clamped[#clamped + 1] = p else wrap[#wrap + 1] = p end
		end
	end
	while #wrap > MAX_WRAP do table.remove(wrap) end
	while #clamped > MAX_CLAMP do table.remove(clamped) end
	local mat = GLASS_BASE
	if #wrap + #clamped > 0 then mat = string.format("%s_W%dC%d", GLASS_BASE, #wrap, #clamped) end
	if mat ~= sh.mat then
		if not pcall(exu.SetSubEntityMaterial, sh.target, sh.index, mat) then return false end
		sh.mat, sh.passes = mat, {}
	end
	local order = {}
	for _, p in ipairs(wrap) do order[#order + 1] = p end
	for _, p in ipairs(clamped) do order[#order + 1] = p end
	for i, p in ipairs(order) do
		local pass = i - 1
		local was = sh.passes[pass]
		if was == nil or was.layer ~= p then
			was = { layer = p }
			sh.passes[pass] = was
			for t = 0, 1 do pcall(exu.SetMaterialTexture, mat, LAYER_TEXTURE[p.family], t, pass, 0) end
		end
		local uv = p.uv
		local key = string.format("%.4f %.4f %.4f %.4f", uv[1], uv[2], uv[3], uv[4])
		if was.uv ~= key then
			pcall(exu.SetMaterialTextureWindow, mat, uv[1], uv[2], uv[3], uv[4], -1, pass, 0)
			was.uv = key
		end
		local step = math.floor(clamp(p.alpha, 0, 1) * SHELL_STEPS + 0.5)
		if was.step ~= step then
			local rgb = LAYER_RGB[p.family] or SHELL_RGB
			pcall(exu.SetMaterialPassColors, mat,
				{ diffuse = { r = rgb, g = rgb, b = rgb, a = step / SHELL_STEPS } }, -1, pass)
			was.step = step
		end
	end
	return true
end

-- Switches between the screen overlay and the glass. Leaving the glass puts its
-- sub-entity back on the no-op material; returning to the overlay re-sends every
-- panel's window and opacity, which were only recorded while on the glass.
local function setMode(want)
	if want == mode then return end
	local was = mode
	mode = want
	print(string.format("CRWetGlass: layers on the %s (%s)", want == "shell" and "cockpit glass" or "screen overlay",
		want == "shell" and ("sub-entity " .. tostring(state.shell and state.shell.index) .. ", group " .. GLASS_GROUP)
		or ("glass support " .. tostring(state.shellOk))))
	if was == "shell" and state.shell and state.shell.target and state.shell.mat ~= GLASS_BASE then
		pcall(exu.SetSubEntityMaterial, state.shell.target, state.shell.index, GLASS_BASE)
		state.shell.mat, state.shell.passes = GLASS_BASE, {}
	end
	if want == "overlay" then
		for _, p in ipairs(allLayers()) do
			if p.uv then setUV(p, p.uv[1], p.uv[2], p.uv[3], p.uv[4]) end
			setAlpha(p, p.alpha or 0)
		end
	end
end

local function show(visible)
	if visible == state.visible then return end
	state.visible = visible
	call(visible and "ShowOverlay" or "HideOverlay", OVERLAY)
end

local function viewAllowsGlass(player)
	if not IsCraft(player) then return false end
	local ok, v = pcall(exu.GetCameraView or function() return 1 end)
	if ok and type(v) == "number" and not VIEW_OK[v] then return false end
	ok, v = pcall(exu.GetSatState or function() return 0 end)
	if ok and v == 1 then return false end
	ok, v = pcall(exu.IsPauseMenuOpen or function() return false end)
	if ok and v == true then return false end
	return true
end

local function forwardSpeed(player)
	local vel, front = GetVelocity(player), GetFront(player)
	if vel == nil or front == nil then return 0 end
	return math.max(0, vel.x * front.x + vel.y * front.y + vel.z * front.z)
end

-- Windshield damage: the crack follows crackWant; each queued splat takes a free dirt layer (or the faintest one),
-- fades in at once, holds, then clears slowly. Returns true while any of it is visible.
local function damageLayers(ar, dt)
	local any = false
	local c = state.crack
	local target = CRACK_PEAK * clamp(crackWant, 0, 1)
	local cx, cy = crackX, crackY
	if mode == "shell" then cx, cy = screenToShell(crackX, crackY) end
	local key = string.format("%s %.3f %.3f %.3f", mode, cx, cy, ar)
	if c.alpha ~= target then
		local a = c.alpha
		if a < target then a = math.min(target, a + CRACK_RATE * dt) else a = math.max(target, a - CRACK_RATE * dt) end
		if a > 0 and c.key ~= key then
			-- Clamped texture with a transparent border, star at its centre: window it so the star lands at (x, y).
			local dv = 1.5
			local du = dv * ar
			setUV(c, 0.5 - cx * du, 0.5 - cy * dv, du, dv)
			c.key = key
		end
		setAlpha(c, a)
	elseif c.alpha > 0 and c.key ~= key then
		local dv = 1.5
		local du = dv * ar
		setUV(c, 0.5 - cx * du, 0.5 - cy * dv, du, dv)
		c.key = key
	end
	any = any or c.on == true

	while #splats > 0 do
		local sp = table.remove(splats, 1)
		local p
		for _, d in ipairs(state.dirt) do
			if d.phase == "off" then p = d; break end
			if p == nil or d.alpha < p.alpha then p = d end
		end
		p.phase, p.t = "in", 0
		p.peak = clamp(0.35 + 0.6 * sp.amount, 0, 0.95)
		p.hold = 0.6 + 2.0 * sp.amount
		p.fade = 2.5 + 3.0 * sp.amount
		local dv = 2.8 - sp.amount            -- a harder hit throws a bigger splat
		local du = dv * ar
		local sx, sy = sp.x, sp.y
		if mode == "shell" then sx, sy = screenToShell(sp.x, sp.y) end
		local u0, v0 = 0.5 - sx * du, 0.5 - sy * dv
		if sp.flip then setUV(p, u0 + du, v0, -du, dv) else setUV(p, u0, v0, du, dv) end
	end
	for _, p in ipairs(state.dirt) do
		if p.phase ~= "off" then
			p.t = p.t + dt
			local a
			if p.phase == "in" then
				a = p.peak * clamp(p.t / 0.06, 0, 1)
				if p.t >= 0.06 then p.phase, p.t = "hold", 0 end
			elseif p.phase == "hold" then
				a = p.peak
				if p.t >= p.hold then p.phase, p.t = "out", 0 end
			else
				a = p.peak * (1 - smoothstep(0, p.fade, p.t))
				if p.t >= p.fade then p.phase, a = "off", 0 end
			end
			setAlpha(p, a)
			any = any or p.on == true
		end
	end
	return any
end

-- Snow flakes: sparse crystals land slowly (fade in over seconds), sit, then melt away (slow
-- fade) and come back somewhere else. Two layers on staggered cycles, so the glass is never
-- covered and never snaps. No motion but a very slow slide. Returns true while any shows.
local function snowLayers(ar, dt)
	local s = clamp(snowWant, 0, 1)
	local peak = SNOW_PEAK * (0.35 + 0.65 * s)
	local any = false
	for k, p in ipairs(state.snow) do
		local awake = s > 0.02 + 0.45 * (k - 1)
		if p.phase == "off" then
			p.wait = p.wait - dt
			if awake and p.wait <= 0 then
				p.phase, p.t = "in", 0
				p.v = randRange(0.9, 1.5)            -- vertical tiles: flake size varies per landing
				p.u0, p.v0 = math.random() * 8, math.random() * 8
				p.rise = randRange(5, 12)            -- flakes gather slowly
				p.hold = randRange(14, 32)
				p.fade = randRange(10, 22)           -- and melt slowly
			end
		end
		if p.phase ~= "off" then
			p.t = p.t + dt
			local a
			if p.phase == "in" then
				a = peak * smoothstep(0, p.rise, p.t)
				if p.t >= p.rise then p.phase, p.t = "hold", 0 end
			elseif p.phase == "hold" then
				a = peak
				if p.t >= p.hold or not awake then p.phase, p.t = "out", 0 end
			else
				a = peak * (1 - smoothstep(0, p.fade, p.t))
				if p.t >= p.fade then
					p.phase, a = "off", 0
					p.wait = randRange(2, 9) / (0.4 + s)
				end
			end
			p.v0 = p.v0 - 0.003 * dt                 -- UV/s; negative slides down the glass
			if a > 0 then setUV(p, p.u0, p.v0, p.v * ar, p.v) end
			setAlpha(p, a)
			any = any or p.on == true
		end
	end
	return any
end

-- Grit: fine dust specks stay where they are and follow the level (the caller shapes how fast it
-- builds and clears). Layer 1 shows first, layer 2 joins as the level climbs; each has its own
-- scale and offset, picked when it first appears.
local function gritLayers(ar, dt)
	local g = clamp(gritWant, 0, 1)
	local any = false
	for k, p in ipairs(state.grit) do
		local a = GRIT_PEAK * smoothstep(0.45 * (k - 1), 0.5 + 0.5 * (k - 1), g)
		if a > 0 then
			if p.v == nil then
				p.v = (k == 1) and randRange(1.0, 1.3) or randRange(0.7, 0.9)
				p.u0, p.v0 = math.random() * 8, math.random() * 8
			end
			local key = string.format("%s %.3f", mode, ar)
			if p.key ~= key then
				setUV(p, p.u0, p.v0, p.v * ar, p.v)
				p.key = key
			end
			p.phase = "on"
		else
			p.phase = "off"
		end
		setAlpha(p, a)
		any = any or p.on == true
	end
	return any
end

local function run(intensity, dt)
	local player = GetPlayerHandle()
	if not IsValid(player) or not viewAllowsGlass(player) then
		if mode == "shell" then setMode("overlay") end
		show(false)
		return
	end
	local onGlass = shellBind(player)
	setMode(onGlass and "shell" or "overlay")
	if onGlass then show(false) else useMask(player) end
	local i = clamp(intensity, 0, 1)
	local speed = forwardSpeed(player)
	local blow = smoothstep(14, 40, speed)   -- beads blown off
	local rush = smoothstep(20, 90, speed)   -- streak speed
	local ar = onGlass and SHELL_AR or aspect()
	local any = false

	-- Beads: land (fade in), sit, run off (fade out while sliding), wait.
	local peak = (0.35 + 0.45 * i) * (1 - 0.85 * blow)
	-- Layers on the glass at once: one in a drizzle, three in a downpour.
	local limit = 1 + math.floor(2 * i + 0.5)
	local active = 0
	for _, p in ipairs(state.beads) do if p.phase ~= "off" then active = active + 1 end end
	local drift = -0.012 * (1 - blow) + 0.35 * blow  -- UV/s; + moves drops up the glass
	for k, p in ipairs(state.beads) do
		local awake = i > (k - 1) / BEAD_LAYERS * 0.85
		if p.phase == "off" then
			p.wait = p.wait - dt
			if awake and p.wait <= 0 and active < limit then
				active = active + 1
				p.phase, p.t = "in", 0
				p.v = randRange(1.2, 1.7)          -- vertical tiles: drop size varies per landing
				p.u0, p.v0 = math.random() * 8, math.random() * 8
				p.rise = randRange(0.9, 2.4)         -- slow fades: drops gather, then clear
				p.hold = randRange(1.6, 3.8)
				p.fade = randRange(1.5, 3.2)
			end
		end
		if p.phase ~= "off" then
			p.t = p.t + dt
			local a
			if p.phase == "in" then
				a = peak * smoothstep(0, p.rise, p.t)
				if p.t >= p.rise then p.phase, p.t = "hold", 0 end
			elseif p.phase == "hold" then
				a = peak
				-- Airflow and a stop in the rain both end the hold early.
				if p.t >= p.hold * (1 - 0.75 * blow) or not awake or i <= 0.01 then p.phase, p.t = "out", 0 end
			else
				a = peak * (1 - smoothstep(0, p.fade, p.t))
				if p.t >= p.fade then
					p.phase = "off"
					p.wait = randRange(0.1, 1.0) / (0.35 + i)
					a = 0
				end
			end
			p.v0 = p.v0 + drift * dt
			if a > 0 then setUV(p, p.u0, p.v0, p.v * ar, p.v) end
			setAlpha(p, a)
			any = any or p.on == true
		end
	end

	-- Rivulets: long tracks creeping down still glass. Each layer shows one
	-- pattern for a long spell, then fades and comes back somewhere else, so the
	-- tracks never read as one texture sliding. Airflow wipes them.
	local rpeak = (0.45 + 0.50 * i) * (1 - blow)
	for k, p in ipairs(state.rivulets) do
		if p.phase == "off" then
			p.wait = p.wait - dt
			if i > 0.05 + 0.3 * (k - 1) and blow < 0.5 and p.wait <= 0 then
				p.phase, p.t = "in", 0
				p.v = randRange(0.6, 0.8)            -- vertical tiles across the screen
				p.u0, p.v0 = math.random() * 8, math.random() * 8
				p.speed = randRange(0.008, 0.02)     -- UV/s down the glass
				p.hold = randRange(9, 18)
			end
		end
		if p.phase ~= "off" then
			p.t = p.t + dt
			local a
			if p.phase == "in" then
				a = rpeak * clamp(p.t / 2.5, 0, 1)
				if p.t >= 2.5 then p.phase, p.t = "hold", 0 end
			elseif p.phase == "hold" then
				a = rpeak
				if p.t >= p.hold or i <= 0.01 or blow > 0.5 then p.phase, p.t = "out", 0 end
			else
				a = rpeak * (1 - clamp(p.t / 2.0, 0, 1))
				if p.t >= 2.0 then p.phase, p.wait, a = "off", randRange(0.5, 3), 0 end
			end
			p.v0 = p.v0 - p.speed * dt
			-- Texture is 256x1024: equal texel scale on both axes needs U = 4 * V * aspect.
			if a > 0 then setUV(p, p.u0, p.v0, 4 * p.v * ar, p.v) end
			setAlpha(p, a)
			any = any or p.on == true
		end
	end

	-- Streaks: only at speed, scrolling up faster the faster the craft goes.
	local s = state.streak
	local sa = (0.30 + 0.70 * i) * blow
	if i <= 0.01 then sa = 0 end
	state.streakV = (state.streakV + (0.5 + 1.6 * rush) * dt) % 64
	if sa > 0 then
		-- Texture is 256x512: equal texel scale on both axes needs U = 2 * V * aspect.
		setUV(s, 0.37, state.streakV, 2 * ar, 1)
	end
	setAlpha(s, sa)
	any = any or s.on == true

	if snowLayers(ar, dt) then any = true end
	if gritLayers(ar, dt) then any = true end
	if damageLayers(ar, dt) then any = true end

	if onGlass then
		if not shellApply() then state.shellOk = false end   -- the glass refused: overlay from now on
		return
	end
	poseMask(player)
	show(any)
end

--- Impact star on the windshield: level 0..1 (0 clears it) at screen fractions (x, y), 0 = left/top.
function wetglass.SetCrack(level, x, y)
	crackWant = clamp(tonumber(level) or 0, 0, 1)
	if tonumber(x) then crackX = clamp(tonumber(x), 0, 1) end
	if tonumber(y) then crackY = clamp(tonumber(y), 0, 1) end
end

--- A dirt splat of strength amount 0..1 centred at screen fractions (x, y); flip mirrors it. Quietly ignored
--- while the layers are unavailable.
function wetglass.Splat(amount, x, y, flip)
	if state == false then return end
	amount = clamp(tonumber(amount) or 0, 0, 1)
	if amount <= 0 then return end
	if #splats >= 4 then table.remove(splats, 1) end
	splats[#splats + 1] = { amount = amount, x = clamp(tonumber(x) or 0.5, 0, 1), y = clamp(tonumber(y) or 0.4, 0, 1),
		flip = flip == true }
end

--- Weather layers on the glass: kind "snow" (soft flakes that land and melt) or "grit" (fine dust
--- specks), level 0..1. The level stays until changed; 0 lets it fade out. The caller keeps calling
--- Update (Update(0) when there is no rain) while Busy() is true.
function wetglass.Weather(kind, level)
	level = clamp(tonumber(level) or 0, 0, 1)
	if kind == "snow" then snowWant = level
	elseif kind == "grit" then gritWant = level end
end

--- True while a crack is wanted or showing, a splat is queued or fading, or a weather layer is wanted
--- or showing: the caller must keep calling Update.
function wetglass.Busy()
	if state == false then return false end
	if crackWant > 0 or #splats > 0 or snowWant > 0 or gritWant > 0 then return true end
	if state then
		if state.crack.alpha > 0 then return true end
		for _, p in ipairs(state.dirt) do if p.phase ~= "off" then return true end end
		for _, p in ipairs(state.snow) do if p.phase ~= "off" then return true end end
		for _, p in ipairs(state.grit) do if p.on then return true end end
	end
	return false
end

--- Drops every queued and fading splat at once (a vehicle change).
function wetglass.ClearSplats()
	splats = {}
	if state then
		for _, p in ipairs(state.dirt) do p.phase = "off"; setAlpha(p, 0) end
	end
end

--- Where the layers draw now: "shell" (the cockpit glass submesh) or "overlay" (the screen).
function wetglass.Mode() return mode end

--- Screen fractions (x, y) -> cockpit glass UV (view angles; Tools/cockpitglass.py U_SPAN/V_SPAN).
function wetglass.ScreenToShell(x, y)
	if exu == nil then exu = findExu() end
	if exu == nil then return 0.5 + math.atan((2 * x - 1) * math.tan(math.rad(32)) * 16 / 9) / U_SPAN,
		0.5 - math.atan((1 - 2 * y) * math.tan(math.rad(32))) / V_SPAN end
	return screenToShell(x, y)
end

--- Hides the overlay, puts the glass back on the no-op material and forgets the built state (mission end).
function wetglass.Stop()
	if state == nil then return end
	if state and exu then
		pcall(exu.HideOverlay, OVERLAY)
		if mode == "shell" and state.shell and state.shell.target then
			pcall(exu.SetSubEntityMaterial, state.shell.target, state.shell.index, GLASS_BASE)
		end
		pcall(exu.DestroyOverlay, OVERLAY)
	end
	state, mode, frame, pending, lastRun = nil, "overlay", nil, 0, nil
	crackWant, splats = 0, {}
	snowWant, gritWant = 0, 0
end

--- Rain on the windshield at intensity 0..1; call every Update.
function wetglass.Update(intensity)
	local now = GetTime()
	intensity = tonumber(intensity) or 0
	if now == frame then
		if intensity > pending then pending = intensity end
		return
	end
	-- First call of a new frame: draw last frame's strongest request.
	local want = pending
	frame, pending = now, intensity
	if state == nil then state = build() end
	if not state then return end
	local dt = 0
	if lastRun ~= nil then dt = clamp(now - lastRun, 0, 0.25) end
	lastRun = now
	local ok, err = pcall(run, math.max(want, intensity), dt)
	if not ok then
		print("CRWetGlass: disabled after error: " .. tostring(err))
		pcall(exu.HideOverlay, OVERLAY)
		if mode == "shell" and state and state.shell and state.shell.target then
			pcall(exu.SetSubEntityMaterial, state.shell.target, state.shell.index, GLASS_BASE)
		end
		state = false
	end
end

return wetglass
