-- Test-CRShieldTowerFX.lua
--
-- Drives the real Scripts/CRShieldTowerFX.lua against stubbed exu/BZ globals:
-- box scale/centre from ODF values, drawn only while powered, the
-- power-plant fallback range, cleanup on death, and the fallback when
-- exu.IsPowered is missing. Also checks the five shield tower ODFs carry the
-- radial push mode and a symmetric box.
--
-- Usage, from the repository root:   lua Tools/Weapons/Test-CRShieldTowerFX.lua Scripts
-- Prints SHIELD TOWER FX OK on success.

local scriptDir = ... or "Scripts"
package.path = scriptDir .. "\\?.lua;" .. scriptDir .. "/?.lua;" .. package.path

local failures = {}
local function check(cond, msg) if not cond then failures[#failures + 1] = msg end end
local function near(a, b) return math.abs(a - b) < 1e-4 end

-- ODF contract ---------------------------------------------------------------
for _, name in ipairs({ "abshtw", "bbshtw", "cbshtw", "sbshtw", "sxshield" }) do
    local f = io.open("ODF/" .. name .. ".odf", "rb")
    check(f ~= nil, name .. ": ODF missing")
    if f then
        local text = f:read("*a"); f:close()
        local section = text:match("%[ShieldTowerClass%](.-)\n%[") or text:match("%[ShieldTowerClass%](.*)$") or ""
        local function val(k) return tonumber(section:match("\n" .. k .. "%s*=%s*([%-%d%.]+)")) end
        check(section:match('shieldPushMode%s*=%s*"radial"') ~= nil, name .. ": missing shieldPushMode = \"radial\"")
        check(val("shieldMinX") == -12 and val("shieldMaxX") == 12, name .. ": X box not -12..12")
        check(val("shieldMinZ") == -12 and val("shieldMaxZ") == 12, name .. ": Z box not -12..12")
        check(val("shieldMinY") == -4 and val("shieldMaxY") == 24, name .. ": Y box not -4..24")
    end
end

-- Stubs ----------------------------------------------------------------------
local clock = 0.0
local objects = {}   -- handle -> { odf, class, team, x, y, z, valid }
local odfs = {
    ["shtw.odf"] = { ShieldTowerClass = { shieldMinX = -10, shieldMaxX = 14, shieldMinY = -4, shieldMaxY = 24,
                                          shieldMinZ = -6, shieldMaxZ = 6 } },
    ["bigplant.odf"] = { PowerPlantClass = { powerRadius = 250 } },
    ["plantodf.odf"] = {},
}
local allies = {}    -- "a:b" -> true
local rec = { creates = {}, destroys = {}, log = {} }
local poweredAnswer = nil   -- value exu.IsPowered returns

local exu = {}
exu.CreateStaticGeometry = function(name, mesh, material, instances, options)
    rec.creates[#rec.creates + 1] = { name = name, mesh = mesh, material = material, instances = instances, options = options }
    rec.log[#rec.log + 1] = { name = name, on = true }
    return { instanceCount = #instances }
end
exu.DestroyStaticGeometry = function(name)
    rec.destroys[#rec.destroys + 1] = name
    rec.log[#rec.log + 1] = { name = name, on = false }
    return true
end
exu.IsPowered = function() return poweredAnswer end
package.loaded.exu = exu

GetTime = function() return clock end
IsValid = function(h) return objects[h] ~= nil and objects[h].valid end
GetOdf = function(h) return objects[h].odf end
GetClassLabel = function(h) return objects[h].class end
GetTeamNum = function(h) return objects[h].team end
IsTeamAllied = function(a, b) return allies[a .. ":" .. b] or allies[b .. ":" .. a] or false end
GetPosition = function(h) local o = objects[h]; return { x = o.x, y = o.y, z = o.z } end
GetTransform = function(h)
    local o = objects[h]
    local c, s = math.cos(o.yaw or 0), math.sin(o.yaw or 0)
    return { posit_x = o.x, posit_y = o.y, posit_z = o.z,
             right_x = c, right_y = 0, right_z = -s, up_x = 0, up_y = 1, up_z = 0, front_x = s, front_y = 0, front_z = c }
end
OpenODF = function(name) return odfs[name] end
GetODFFloat = function(odf, section, key, default)
    local s = odf[section]
    if s and s[key] ~= nil then return s[key] end
    return default
end
AllObjects = function()
    local list = {}
    for h in pairs(objects) do list[#list + 1] = h end
    table.sort(list)
    local i = 0
    return function() i = i + 1; return list[i] end
end

local function add(h, odf, class, team, x, y, z, yaw)
    objects[h] = { odf = odf, class = class, team = team, x = x, y = y, z = z, yaw = yaw, valid = true }
end

local FX = require("CRShieldTowerFX")
local function step(dt) clock = clock + dt; FX.Update() end
local function last() return rec.creates[#rec.creates] end

-- Box scale / centre / material ------------------------------------------------
add(1, "shtw", "shieldtower", 1, 100, 50, 200, 0)
poweredAnswer = true
FX.Track(1)   -- as RuntimeEnhancements.OnObjectCreated would
step(0.1)
local c = last()
check(c ~= nil, "no StaticGeometry created")
if c then
    local inst = c.instances[1]
    check(c.mesh == "cube_10x10x10.mesh", "wrong mesh " .. tostring(c.mesh))
    check(near(inst.scale.x, 2.4) and near(inst.scale.y, 2.8) and near(inst.scale.z, 1.2), "scale from ODF box")
    check(near(inst.position.x, 102) and near(inst.position.z, 200) and near(inst.position.y, 46), "box centre/floor at tower transform")
    check(c.material == "CR_ShieldTowerField_Green", "powered field uses the green material")
    check(c.name:find("1", 1, true) and c.name:find("CR_ShieldTowerFX_", 1, true), "unique per-handle name")
end

-- Yaw rotates the local centre offset ---------------------------------------------
add(2, "shtw", "shieldtower", 1, 0, 0, 0, math.pi / 2)
FX.Track(2)
step(0.6)
local rotated
for _, cr in ipairs(rec.creates) do if cr.name:find("2$") then rotated = cr end end
check(rotated ~= nil and near(rotated.instances[1].position.x, 0) and near(rotated.instances[1].position.z, -2) or false,
    "local centre (+2,0) at yaw 90 must map through the tower right vector")
check(rotated and near(rotated.instances[1].yaw, math.pi / 2), "yaw from tower front")

-- Power loss hides the field, power return rebuilds it ------------------------------
objects[2].valid = false
local n = #rec.creates
step(0.6); step(0.6)
check(#rec.creates == n, "no rebuild while powered")
local d0 = #rec.destroys
poweredAnswer = false
step(0.6)
check(#rec.destroys == d0 + 1 and rec.destroys[#rec.destroys]:find("1$"), "powered -> unpowered must destroy the field")
step(0.6); step(0.6)
check(#rec.creates == n and #rec.destroys == d0 + 1, "nothing drawn or re-destroyed while unpowered")
poweredAnswer = true
step(0.6)
check(#rec.creates == n + 1 and last().name:find("1$"), "unpowered -> powered must rebuild the field")

-- Re-evaluation rate -------------------------------------------------------------
local calls = 0
exu.IsPowered = function() calls = calls + 1; return true end
local start = clock
for _ = 1, 60 do step(1 / 60) end
check(calls <= 3, "power re-evaluated too often: " .. calls .. " calls in " .. (clock - start) .. " s")

-- Cleanup on death -----------------------------------------------------------------
objects[1].valid = false
local d = #rec.destroys
step(0.6)
check(#rec.destroys > d and rec.destroys[#rec.destroys]:find("1$"), "StaticGeometry destroyed when tower dies")
check(FX.Describe().towers == 0, "dead tower dropped")

-- Fallback without exu.IsPowered ---------------------------------------------------
exu.IsPowered = nil
rec.creates = {}
add(10, "shtw", "shieldtower", 1, 0, 0, 0, 0)
add(11, "plantodf", "powerplant", 1, 190, 0, 0)    -- own plant inside the 200 m default
add(12, "plantodf", "powerplant", 2, 50, 0, 0)     -- enemy plant: ignored
FX.Track(10); FX.Track(11); FX.Track(12)
local function shown(h)
    local name = "CR_ShieldTowerFX_" .. h
    local state = false
    for _, ev in ipairs(rec.log) do if ev.name == name then state = ev.on end end
    return state
end
step(0.6)
check(shown(10), "own plant at 190 m (default 200) powers it")
objects[11].x = 210
step(0.6)
check(not shown(10), "own plant at 210 m (default 200) does not; enemy plant never does")
-- the plant range cache is per ODF name: bigplant reads powerRadius 250
add(13, "bigplant", "powerplant", 1, 240, 0, 0)
FX.Track(13)
step(0.6)
check(shown(10), "plant ODF powerRadius 250 powers a tower at 240 m")
objects[13].valid = false
step(0.6)
check(not shown(10), "dead plant no longer powers")
allies["1:2"] = true
step(0.6)
check(shown(10), "allied team plant powers (enemy plant at 50 m became an ally)")

-- nil answer from exu.IsPowered also falls back ----------------------------------------
exu.IsPowered = function() return nil end
allies["1:2"] = nil
step(0.6)
check(not shown(10), "nil from exu.IsPowered uses the fallback")
exu.IsPowered = function() return true end
step(0.6)
check(shown(10), "exu.IsPowered true overrides the fallback")

-- Reset destroys every box -----------------------------------------------------------------
local before = #rec.destroys
FX.Reset()
check(#rec.destroys > before and FX.Describe().towers == 0, "Reset destroys all geometry")

-- One-time scan picks up pre-placed towers --------------------------------------------------
rec.creates = {}
add(20, "shtw", "shieldtower", 1, 5, 5, 5, 0)
exu.IsPowered = function() return true end
step(0.6)
local found = false
for _, cr in ipairs(rec.creates) do if cr.name:find("20$") then found = true end end
check(found, "initial scan finds existing towers")

-- Old exu without the static geometry API must not error -------------------------------------
exu.CreateStaticGeometry = nil
exu.DestroyStaticGeometry = nil
objects[21] = nil
add(21, "shtw", "shieldtower", 1, 0, 0, 0, 0)
FX.Track(21)
local ok, err = pcall(function() step(0.6); objects[21].valid = false; step(0.6) end)
check(ok, "missing exu static geometry API must not raise: " .. tostring(err))

if #failures > 0 then
    for _, m in ipairs(failures) do print("FAIL: " .. m) end
    os.exit(1)
end
print("SHIELD TOWER FX OK")
