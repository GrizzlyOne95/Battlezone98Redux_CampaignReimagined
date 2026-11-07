-- Offline coverage for Scripts/CRTeamSkins.lua with an EXU material stub. Lua 5.1.
--   lua5.1 Tools/Test-CRTeamSkins.lua
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
package.path = toolsDir .. "/../Scripts/?.lua;" .. package.path

local now = 0
local objects = {}
GetTime = function() return now end
GetTeamNum = function(h) return h.team end
IsValid = function(h) return h.valid ~= false end
AllObjects = function()
    local i = 0
    return function() i = i + 1; return objects[i] end
end

-- EXU stub: materials by name, sub-entity material lists per handle.
local materials = { avtank00 = true, avtank00_tm = true, glass = true, cockpit = true,
    exu_surface_cr_frost_avtank00 = true }
local uniforms = {}
local clones = 0
local exu = {
    GetSubEntityCount = function(h) return h.subs and #h.subs or nil end,
    GetSubEntityMaterial = function(h, i) return h.subs[i + 1] end,
    SetSubEntityMaterial = function(h, i, m) assert(materials[m], "unknown material " .. m); h.subs[i + 1] = m; return true end,
    MaterialExists = function(m) return materials[m] == true end,
    CloneMaterial = function(src, dst) assert(materials[src]); materials[dst] = true; clones = clones + 1; return true end,
    -- returns the number of passes that declare the uniform (en-high wrappers)
    SetMaterialShaderVector = function(m, name, x, y, z, w, tech, pass)
        assert(name == "teamPaint" and tech == -1 and pass == -1)
        uniforms[m] = { r = x, g = y, b = z, a = w }
        return 7
    end,
}

local T = require("CRTeamSkins")
T.exu = exu

local net = true
local players = {}
local coop = {
    IsNetworkGame = function() return net end,
    GetLeaderTeam = function() return 1 end,
    IsHumanTeam = function(t) return t >= 1 and t <= 3 end,
    ForEachPlayerHandle = function(fn) for _, h in ipairs(players) do fn(h) end end,
}

local function unit(team)
    local h = { team = team, subs = { "glass", "avtank00", "cockpit" } }
    objects[#objects + 1] = h
    return h
end
local function sweep() now = now + 1.5; T.Update(coop) end

local host = unit(1)
local wing = unit(1)
local guest = unit(2)
local guest3 = unit(3)
local enemy = unit(5)
local aiAlly = unit(4)  -- team 4 is outside this mission's human range
local pilot = { team = 2, subs = { "glass" } }
objects[#objects + 1] = pilot
players = { host, guest, guest3 }

-- single player: nothing happens
net = false
sweep()
assert(host.subs[2] == "avtank00" and guest.subs[2] == "avtank00", "single player must not paint")
net = true

sweep()
assert(host.subs[2] == "avtank00@crteam_host", "host ship camo: " .. host.subs[2])
assert(wing.subs[2] == "avtank00", "host team wingman keeps default paint")
assert(guest.subs[2] == "avtank00@crteam_t2", "guest team 2 tint")
assert(guest3.subs[2] == "avtank00@crteam_t3", "guest team 3 tint")
assert(enemy.subs[2] == "avtank00", "enemy team untouched")
assert(aiAlly.subs[2] == "avtank00", "AI team in the guest range untouched")
assert(host.subs[1] == "glass" and host.subs[3] == "cockpit", "non-paint sub-entities untouched")
local c = uniforms["avtank00@crteam_host"]
assert(c.r == 0 and c.a > 2, "host clone is camo mode")
c = uniforms["avtank00@crteam_t2"]
assert(c.r > 0.5 and c.a == 2, "guest clone is solid tint mode")
assert(clones == 3, "one clone per skin, got " .. clones)
-- host + 2 guests + the guest pilot (recorded as "nothing paintable", skipped later)
assert(T.TrackedCount() == 4, "tracked count " .. T.TrackedCount())

-- throttle: no sweep before T.SWEEP elapses
guest.subs[2] = "avtank00"
now = now + 0.1; T.Update(coop)
assert(guest.subs[2] == "avtank00", "sweep is throttled")
-- engine material reset is repainted
sweep()
assert(guest.subs[2] == "avtank00@crteam_t2", "engine reset repainted")

-- host changes ship: old ship back to default, new ship camo
local newShip = unit(1)
players = { newShip, guest, guest3 }
sweep()
assert(host.subs[2] == "avtank00", "old host ship restored: " .. host.subs[2])
assert(newShip.subs[2] == "avtank00@crteam_host", "new host ship camo")

-- sniped/hijacked craft changes team
wing.team = 3
sweep()
assert(wing.subs[2] == "avtank00@crteam_t3", "team change retints")
guest.team = 1
sweep()
assert(guest.subs[2] == "avtank00", "craft taken by host team restored")

-- another module's clone (CRSurfaceEffects) is not fought
guest3.subs[2] = "exu_surface_cr_frost_avtank00"
sweep()
assert(guest3.subs[2] == "exu_surface_cr_frost_avtank00", "foreign clone left alone")

-- entity not built yet: retried later
local late = { team = 2 }
objects[#objects + 1] = late
sweep()
late.subs = { "avtank00" }
sweep()
assert(late.subs[1] == "avtank00@crteam_t2", "late entity painted on retry")

-- dead handles pruned
local before = T.TrackedCount()
late.valid = false
sweep()
assert(T.TrackedCount() == before - 1, "invalid handle pruned")

-- no EXU: silent no-op
T.Reset()
T.exu = nil
package.loaded.exu = nil
local fresh = unit(2)
sweep()
assert(fresh.subs[2] == "avtank00", "no EXU = no paint, no error")

print("CRTeamSkins checks passed")
