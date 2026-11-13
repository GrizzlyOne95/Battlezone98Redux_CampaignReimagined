-- Lua 5.1 host regression: the RuntimeEnhancements emissive pulse must reach the
-- per-object CRSurfaceEffects clone that is actually drawn, not only its source.
-- Run from the repository root: lua5.1 Tools/TexturesAndSky/Test-EmissivePulse.lua
package.path = "Scripts/?.lua;" .. package.path

local E, objects, writes, clones = {}, {}, {}, {}
local now = 0
objects[1] = { material = "avtank00", health = 1, class = "turret", powered = true }

package.loaded.exu = E
package.loaded.bzfile = {}
package.loaded.LogPaths = { Path = function(name) return name end }
package.loaded.CRWeather = { GetSurfaceWetness = function() return 0 end }

function GetTime() return now end
function IsValid(h) return objects[h] ~= nil end
function GetPlayerHandle() return nil end
function IsCraft() return false end
function GetClassLabel(h) return objects[h].class end
function GetHealth(h) return objects[h].health end
function GetTeamNum() return 1 end
function GetDistance() return 10 end
function SetVector(x, y, z) return { x = x, y = y, z = z } end
function AllObjects() return function() return nil end end

local function obj(t) return objects[type(t) == "table" and t.handle or t] end
local function noop() return true end
-- Capability probe (RuntimeEnhancements.Initialize).
E.MaterialExists, E.CloneMaterial, E.GetMaterialPassColors = noop, noop, noop
E.GetMaterialName, E.SetMaterialName, E.SetEntityMaterial = noop, noop, noop
function E.GetSubEntityCount() return 1 end
function E.GetSubEntityMaterial(t) return obj(t) and obj(t).material end
function E.SetSubEntityMaterial(t, _, name) obj(t).material = name; return true end
E.SetSurfaceMaterial = E.SetSubEntityMaterial
function E.CloneSurfaceMaterial(source, name) clones[name] = source; return true end
function E.ReleaseSurfaceMaterial(name) clones[name] = nil; return true end
function E.SetSurfaceTexture() return 1 end
function E.SetSurfaceFragmentProgram() return 1 end
function E.SetMaterialShaderVector() return 1 end
function E.EntityLocalPoint(_, p) return p end
function E.GetWeaponMuzzlePosition() return nil end
function E.IsGunTowerPowered(h) return objects[h].powered end
function E.GetCameraView() return 1 end
function E.GetSatState() return 0 end
function E.SetReactiveChunksEnabled() end
function E.GetEffectiveRenderProfile() return "Enhanced" end
function E.SetMaterialPassColors(name, colors)
    writes[#writes + 1] = { name = name, r = colors.emissive and colors.emissive.r }
    return true
end

local RE = assert(loadfile("Scripts/RuntimeEnhancements.lua"))()
local S = package.loaded.CRSurfaceEffects
assert(S, "RuntimeEnhancements must load CRSurfaceEffects")

local function step(n)
    for _ = 1, n do now = now + 0.05; RE.Update() end
end
local function writesTo(name)
    local list = {}
    for _, w in ipairs(writes) do if w.name == name then list[#list + 1] = w.r end end
    return list
end

RE.PulseMaterials = { avtank00 = { colors = { emissive = { r = 0.5, g = 0.5, b = 0.5, a = 1 } } } }
S.Register(1)
step(40)
local clone = objects[1].material
assert(string.find(clone, "^exu_surface_cr_"), "the tower is drawn with a surface clone, got " .. tostring(clone))

RE.SetEmissivePulseEnabled(true)
writes = {}
step(40) -- 2 s: a full pulse period at the default 2.4 s is not needed, only motion
local source, drawn = writesTo("avtank00"), writesTo(clone)
assert(#source > 0, "pulse writes the source material")
assert(#drawn == #source, string.format("pulse writes the drawn clone on every tick (%d of %d)", #drawn, #source))
local lo, hi = math.huge, -math.huge
for _, r in ipairs(drawn) do lo, hi = math.min(lo, r), math.max(hi, r) end
assert(hi - lo > 0.02, "the clone's emissive actually moves")
assert(lo >= 0.5 * 0.72 - 1e-6 and hi <= 0.5 + 1e-6, "factor stays in 0.72..1.0")

-- Throttle: no more than one pulse write per 0.08 s.
assert(#source <= math.floor(2.0 / 0.08) + 1, "pulse stays throttled, got " .. #source)

-- Turning the pulse off restores the base on the clone too.
writes = {}
RE.SetEmissivePulseEnabled(false)
local off = writesTo(clone)
assert(#off == 1 and math.abs(off[1] - 0.5) < 1e-6, "pulse off restores the clone's base emissive")
RE.SetEmissivePulseEnabled(true)

-- A powered-off tower wears the _off clone; the normal clone stays live.
objects[1].powered = false; step(20)
assert(string.find(objects[1].material, "_off", 1, true), "tower swaps to its _off clone")
assert(S.LiveClones("avtank00")[1] == clone, "normal clone stays live across the _off swap")
objects[1].powered = true; step(20)

-- Release: once the clone is gone the pulse must stop writing it.
S.Unregister(1)
assert(clones[clone] == nil, "unregister releases the clone")
writes = {}
step(10)
assert(#writesTo("avtank00") > 0, "source still pulses")
assert(#writesTo(clone) == 0, "released clone is no longer written")
assert(S.LiveClones("avtank00") == nil, "live lookup forgets released clones")

-- A scene reset forgets every live clone.
S.Register(1); step(40)
assert(S.LiveClones("avtank00"), "rebound clone is live again")
S.ResetScene()
assert(S.LiveClones("avtank00") == nil, "ResetScene clears the live lookup")

print("Test-EmissivePulse: OK")
