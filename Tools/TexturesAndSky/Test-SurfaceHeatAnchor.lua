-- Lua 5.1 host regression: weapon heat follows the visible flash anchor
-- (native mount + craft flashOffset<N>, else weapon flashOffset), read only.
local E, uniforms, odfReads = {}, {}, 0
local hull = { right = {0,0,-1}, up = {0,1,0}, front = {1,0,0}, posit = {100,0,0} }
local craftOdf, weaponOdf = "avtank", "gatstab"
local odfs = {
    avtank = { CraftClass = { flashOffset1 = '"0.20 0.10 2.41"' } },
    badtank = { CraftClass = { flashOffset1 = '"21 0 0"' } },
    gatstab = { WeaponClass = { flashOffset = '"0 0 1"', ordName = "rocket" } },
    gspstab = { WeaponClass = { ordName = "rocket3" } },
    gpea = { WeaponClass = { ordName = "pea" } },
    gnoord = { WeaponClass = {} },
    rocket = { OrdnanceClass = { damageBallistic = 80 } },
    rocket3 = { OrdnanceClass = { damageBallistic = 180, damageConcussion = 50 } },
    pea = { OrdnanceClass = { damageBallistic = 20 } },
    gheavy = { WeaponClass = { ordName = "heavy" } },
    heavy = { OrdnanceClass = { damageBallistic = 900 } },
    gpop = { WeaponClass = { ordName = "pop" } },
    pop = { OrdnanceClass = { damageBallistic = 0 } },
    gnodmg = { WeaponClass = { ordName = "nodmg" } },
    nodmg = { OrdnanceClass = { lifeSpan = 2 } },
}
local function matrix(m)
    return { right_x = m.right[1], right_y = m.right[2], right_z = m.right[3],
        up_x = m.up[1], up_y = m.up[2], up_z = m.up[3],
        front_x = m.front[1], front_y = m.front[2], front_z = m.front[3],
        posit_x = m.posit[1], posit_y = m.posit[2], posit_z = m.posit[3] }
end
package.loaded.exu = E
package.loaded.CRWeather = { GetSurfaceWetness = function() return 0 end }
function IsValid(h) return h == 1 end
function GetPlayerHandle() return 1 end
function IsCraft() return true end
function GetClassLabel() return "wingman" end
function GetHealth() return 1 end
function GetDistance() return 10 end
function SetVector(x, y, z) return { x = x, y = y, z = z } end
function GetTransform() return matrix(hull) end
function GetOdf() return craftOdf end
function GetWeaponClass(_, slot) return slot <= 1 and weaponOdf or "" end
function OpenODF(name) odfReads = odfReads + 1; return odfs[name] and name end
function GetODFFloat(odf, section, label, default)
    local s = odfs[odf] and odfs[odf][section]
    if s and type(s[label]) == "number" then return s[label], true end
    return default, false
end
function GetODFString(odf, section, label, default)
    local s = odfs[odf] and odfs[odf][section]
    if s and s[label] then return s[label], true end
    return default, false
end
function E.GetSubEntityCount() return 1 end
local material = "metal"
function E.GetSubEntityMaterial() return material end
function E.SetSubEntityMaterial(_, _, name) material = name; return true end
E.SetSurfaceMaterial = E.SetSubEntityMaterial
function E.CloneSurfaceMaterial() return true end
function E.ReleaseSurfaceMaterial() return true end
function E.SetSurfaceTexture() return 1 end
function E.SetMaterialShaderVector(name, key, ...) uniforms[name .. key] = {...}; return 1 end
local localTargets = {}
function E.EntityLocalPoint(t, p) localTargets[#localTargets + 1] = t; return p end
-- Native mounts: slot 0 one metre above the hull origin, slot 1 beside it.
function E.GetWeaponMuzzlePosition(_, slot)
    if slot == 0 then return SetVector(hull.posit[1], hull.posit[2] + 1, hull.posit[3]) end
    if slot == 1 then return SetVector(hull.posit[1], hull.posit[2] + 1, hull.posit[3] + 3) end
end
function E.IsGunTowerPowered() return true end
function E.GetCameraView() return 0 end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled() end
function E.GetEffectiveRenderProfile() return "Enhanced" end
function E.SetSurfaceFragmentProgram() return 1 end

local function near(a, b, label)
    assert(type(a) == "number" and math.abs(a - b) < 0.001, label .. ": got " .. tostring(a) .. " want " .. tostring(b))
end
local function load()
    material = "metal"; uniforms = {}
    local S = assert(loadfile("Scripts/CRSurfaceEffects.lua"))()
    S.Register(1)
    for _ = 1, 4 do S.Update(0.05) end
    return S
end
local function ticks(S, n) for _ = 1, n do S.Update(0.05) end end
local function shot(slot, front)
    local m = matrix(hull)
    local mount = E.GetWeaponMuzzlePosition(1, slot)
    m.posit_x, m.posit_y, m.posit_z = mount.x, mount.y, mount.z
    if front then m.front_x, m.front_y, m.front_z = front[1], front[2], front[3] end
    E.BulletInit("bullet", 1, m)
end
local function anchor(key) return uniforms[material .. (key or "surfaceMuzzle0")] end

-- 1. Craft flashOffset1 along the hull: right 0.2 (world -Z), up 0.1, forward 2.41 (world +X).
local S = load()
shot(0); ticks(S, 6)
local a = anchor()
assert(a, "heat anchor written")
near(a[1], 102.41, "forward offset"); near(a[2], 1.1, "up offset"); near(a[3], -0.2, "right offset"); near(a[4], 0.6, "radius")
-- The heated stretch ends BarrelLength (0.8) back from the flash point toward
-- the mount (100,1,0): flash (102.41,1.1,-0.2), barrel length 2.4229.
local b = anchor("surfaceBarrel0")
assert(b, "barrel end written")
local k = 0.8 / math.sqrt(2.41^2 + 0.1^2 + 0.2^2)
near(b[1], 102.41 - 2.41*k, "barrel end x"); near(b[2], 1.1 - 0.1*k, "barrel end y"); near(b[3], -0.2 + 0.2*k, "barrel end z"); near(b[4], 0.35, "barrel radius")

-- 2. The anchor rides the hull: rotate and move the craft, the barrel tip follows.
hull = { right = {1,0,0}, up = {0,1,0}, front = {0,0,1}, posit = {0,0,50} }
ticks(S, 2)
a = anchor()
near(a[1], 0.2, "rotated right"); near(a[2], 1.1, "rotated up"); near(a[3], 52.41, "rotated forward")

-- 3. A turret shot: the offset follows the shot direction, not the hull nose.
S = load()
hull = { right = {0,0,-1}, up = {0,1,0}, front = {1,0,0}, posit = {100,0,0} }
shot(0, {0,0,1}); ticks(S, 4)
a = anchor()
near(a[1], 100.2, "turret right"); near(a[2], 1.1, "turret up"); near(a[3], 2.41, "turret forward")

-- 4. No craft key for slot 1: the weapon's own flashOffset is used.
S = load()
shot(1); ticks(S, 4)
a = anchor()
near(a[1], 101, "weapon fallback forward"); near(a[3], 3, "weapon fallback side")

-- 5. A malformed craft value falls back to the weapon value, like the native parser.
craftOdf = "badtank"
S = load()
shot(0); ticks(S, 4)
near(anchor()[1], 101, "invalid craft offset falls back to weapon")

-- 6. No offset anywhere: the native mount, unchanged.
craftOdf, weaponOdf = "plain", "plainwep"
S = load()
shot(0); ticks(S, 4)
a = anchor()
near(a[1], 100, "mount x"); near(a[2], 1, "mount y"); near(a[3], 0, "mount z")
near(anchor("surfaceBarrel0")[4], 0, "no flash offset keeps the round tip mask")

-- 7. Without the ODF API the controller still heats the native mount.
local open = OpenODF; OpenODF = nil
craftOdf = "avtank"
S = load()
shot(0); ticks(S, 4)
near(anchor()[1], 100, "no ODF API keeps the mount")
OpenODF = open

-- 8. ODF reads are cached per key and bounded.
S = load()
odfReads = 0
for _ = 1, 20 do shot(0); ticks(S, 1) end
-- One craft read for the offset, then the weapon and its ordnance for the heat scale.
assert(odfReads <= 3, "flash offsets and heat scale must be cached, read " .. odfReads)
S.MaxFlashCache = 2
for i = 1, 10 do craftOdf = "tank" .. i; shot(0); ticks(S, 1) end
assert(S.flashCacheCount <= 2, "flash offset cache is bounded")

-- 9. Heat still ramps and cools smoothly at the offset anchor (no snap).
craftOdf, weaponOdf = "avtank", "gatstab"
S = load()
local last, maxStep = 0, 0
for i = 1, 160 do
    if i <= 20 then shot(0) end
    ticks(S, 1)
    local record = S.records[1]
    local heat = record and record.heat[0]
    local display = heat and heat.display or 0
    maxStep = math.max(maxStep, math.abs(display - last)); last = display
end
assert(maxStep < 0.06, "heat display steps must stay small, got " .. maxStep)

-- 9b. Slow sustained fire (1.5 shots/s for 30 s) holds a warm glow
-- instead of cooling away between shots; stopping lets it fade.
S = load()
for i = 1, 600 do
    if i % 13 == 0 then shot(0) end
    ticks(S, 1)
end
local warm = S.records[1].heat[0]
assert(warm and warm.energy > 0.35, "slow sustained fire stays warm, got " .. tostring(warm and warm.energy))
local warmEnergy = warm.energy
ticks(S, 200)
assert((S.records[1].heat[0] and S.records[1].heat[0].energy or 0) < warmEnergy * 0.5, "heat fades after firing stops")

local function approx(a, b, label)
    assert(math.abs(a - b) < 0.01, label .. ": got " .. a .. " want ~" .. b)
end
-- 9c. Heat per shot scales with ordnance damage over 80, clamped 1..3:
-- rocket3 (230) adds 2.875x, a 20-damage round 1x, 900 damage caps at 3x,
-- zero-damage ordnance adds no heat, no ordnance data 1x.
local function firstShot(weapon)
    weaponOdf = weapon
    local S = load(); S.HeatCool, S.HeatFloor = 0, 0
    shot(0); ticks(S, 1)
    local e = S.records[1].heat[0] and S.records[1].heat[0].energy or 0
    weaponOdf = "gatstab"
    return e
end
local base = firstShot("gatstab")
approx(firstShot("gspstab") / base, 2.875, "heavy ordnance heats more per shot")
approx(firstShot("gpea") / base, 1, "light ordnance keeps the base heat")
approx(firstShot("gheavy") / base, 3, "very heavy ordnance caps at 3x")
approx(firstShot("gpop"), 0, "zero-damage ordnance adds no heat")
approx(firstShot("gnoord") / base, 1, "no ordnance damage: base heat")
approx(firstShot("gnodmg") / base, 1, "ordnance without damage keys: base heat")
approx(base / (1 * 0.06), 1, "AT-Stabber reference round adds the base heat")

-- 10. In F1 the player's cockpit model heats too, anchored in its own space.
E.GetCameraView = function() return 1 end
S = load()
localTargets = {}
for _ = 1, 10 do shot(0); ticks(S, 1) end
assert(S.cockpit and S.cockpit.heat[0] and S.cockpit.heat[0].energy > 0.3, "cockpit barrel heats")
assert(S.records[1].heat[0], "hull still heats alongside the cockpit")
local sawCockpit = false
for _, t in ipairs(localTargets) do if type(t) == "table" and t.kind == "cockpit" then sawCockpit = true end end
assert(sawCockpit, "cockpit anchor uses the cockpit model target")
local cockpitAnchor
for k, v in pairs(uniforms) do if k:find("_cockpitsurfaceMuzzle0", 1, true) and v[4] > 0 then cockpitAnchor = v end end
assert(cockpitAnchor, "cockpit muzzle anchor written")
near(cockpitAnchor[1], 102.41, "cockpit anchor at the flash offset")
E.GetCameraView = function() return 0 end

-- 11. The player's own shots flash one reused point light ahead of the muzzle.
local lights, lightCalls = {}, {}
local function lightCall(name) lightCalls[#lightCalls + 1] = name end
E.HasPointLight = function(name) return lights[name] ~= nil end
E.CreatePointLight = function(name, at, colour, range)
    lightCall("create"); lights[name] = {at = at, colour = colour, range = range, visible = true, power = 1}; return true
end
E.SetPointLightPosition = function(name, at) lightCall("move"); if not lights[name] then return false end; lights[name].at = at; return true end
E.SetPointLightRange = function(name, r) if not lights[name] then return false end; lights[name].range = r; return true end
E.SetPointLightVisible = function(name, v) if not lights[name] then return false end; lights[name].visible = v; return true end
E.SetPointLightPowerScale = function(name, p) if not lights[name] then return false end; lights[name].power = p; return true end
E.DestroyPointLight = function(name) lightCall("destroy"); lights[name] = nil; return true end
local function fire(odf, shooter)
    local m = matrix(hull)
    m.posit_x, m.posit_y, m.posit_z = 100, 1, 0
    E.BulletInit(odf or "bullet", shooter or 1, m)
end
S = load()
local name = S.MuzzleLightName
fire(); S.Update(0.01)
local l = lights[name]
assert(l and l.visible, "player shot shows the muzzle light")
near(l.at.x, 100 + S.MuzzleLightAhead, "light sits ahead of the muzzle"); near(l.at.y, 1, "light height"); near(l.range, S.MuzzleLightRange, "base range")
S.Update(0.05)
assert(l.power < 1 and l.power > 0, "light fades")
S.Update(0.1)
assert(not l.visible, "light hides after its life")
lightCalls = {}
fire("rocket3"); S.Update(0.01)
assert(lightCalls[1] == "move" and #lightCalls == 1, "light is reused, not recreated")
assert(l.visible and l.power > 0.9, "a new shot relights at full power")
near(l.range, S.MuzzleLightRange + S.MuzzleLightRangePerScale * (2.875 - 1), "heavy rounds light further")
S.Update(0.2)
lightCalls = {}
fire("bullet", 2); S.Update(0.01)
assert(#lightCalls == 0 and not l.visible, "other shooters do not flash the player light")
fire("pop"); S.Update(0.01)
assert(not l.visible, "zero-damage rounds do not flash")
lights[name] = nil
fire(); S.Update(0.01)
assert(lights[name] and lights[name].visible, "a light lost elsewhere is recreated")
-- A move refused while the light is still live keeps it (no destroy/create).
local move = E.SetPointLightPosition
E.SetPointLightPosition = function() lightCall("move"); return false end
lightCalls = {}
fire(); S.Update(0.01)
for _, c in ipairs(lightCalls) do assert(c ~= "create" and c ~= "destroy", "live light is not recreated") end
assert(S.mlightMade, "live light stays owned")
E.SetPointLightPosition = move
S.ResetScene()
assert(lights[name] == nil, "scene reset destroys the light")
fire(); S.Update(0.01)
assert(lights[name], "light back after reset")
S.mlightMade = false
S.Suspend()
assert(lights[name] == nil, "suspend destroys a light even when not marked owned")
lights = {}
S = load()
E.CreatePointLight = function() lightCall("create"); return false end
lightCalls = {}
fire(); S.Update(0.01); fire(); S.Update(0.01)
assert(#lightCalls == 1, "a refused create backs off instead of retrying every shot")
for _, k in ipairs({"HasPointLight", "CreatePointLight", "SetPointLightPosition", "SetPointLightRange",
    "SetPointLightVisible", "SetPointLightPowerScale", "DestroyPointLight"}) do E[k] = nil end

print("SurfaceHeatAnchor: craft offset, hull follow, turret shot, weapon fallback, invalid value, mount, no API, cache, smoothness, slow fire, damage scale, cockpit, barrel, player muzzle light PASS")
