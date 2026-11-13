-- Exercise weapon callbacks with local and replicated objects (Lua 5.1).
local exu, net, localHandle = {}, true, "local"
package.loaded.exu = exu
local writes = {}
local vector = {}
vector.__index = vector
function SetVector(x, y, z) return setmetatable({x=x, y=y, z=z}, vector) end
function vector.__add(a, b) return SetVector(a.x+b.x, a.y+b.y, a.z+b.z) end
function vector.__sub(a, b) return SetVector(a.x-b.x, a.y-b.y, a.z-b.z) end
function vector.__mul(a, b) return SetVector(a.x*b, a.y*b, a.z*b) end
function Normalize(v) return v end
function IsValid(h) return h ~= nil end
function IsLocal(h) return h == localHandle end
function IsNetGame() return net end
function GetPlayerHandle() return localHandle end
function GetVelocity() return SetVector(0, 0, 0) end
GetOmega = GetVelocity
function SetVelocity(h, v) writes[#writes+1] = {h, "velocity", v} end
function SetOmega(h, v) writes[#writes+1] = {h, "omega", v} end
local physics = dofile("Scripts/PhysicsImpact.lua")
local transform = {front_x=0, front_y=0, front_z=1}
local function fire(h) exu.BulletInit("blast", h, transform) end
local function hit(h) exu.BulletHit("blast", "remote", h, transform) end
fire("remote"); hit("remote"); fire(nil); hit(nil)
assert(#writes == 0, "replicas and missing objects must receive no physics writes")
fire(localHandle); hit(localHandle)
assert(#writes == 3 and writes[1][1] == localHandle and writes[2][2] == "omega")
assert(writes[1][3].z < 0 and writes[3][3].z > 0, "owner still receives recoil and impact")
net, writes = false, {}
fire("remote"); hit("remote")
assert(#writes == 3, "offline AI physics must be preserved")
IsNetGame, writes = nil, {}
fire("remote"); hit("remote")
assert(#writes == 3, "older offline environments must keep physics behavior")
print("PhysicsImpact owner-local callbacks and offline behavior passed")
