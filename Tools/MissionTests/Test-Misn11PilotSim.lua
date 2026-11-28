-- Simulation of misn11cr's N64 Pilot Mode branch (misn11cr.lua ~66-153): NO AI DUTIES.
-- The branch only (a) makes the three wingman tanks follow the player (once, on a craft change and
-- every 30 s) and (b) lets the armory build three ammo and three repair pods on the player after the
-- first transport reaches "check2". The win (misn11cr.lua ~1188) is that both tugs (avhaul0_tug and
-- avhaul1_tug, which the MISSION script itself sends along base1/base2/escape, ~993-1132) and every
-- player reach the launch point after the last wave; nothing the player cannot do alone as a pilot is
-- left to the branch (no deploy, no build that the win needs, no unit that must reach a place).
-- So this scenario only asserts that the branch runs for 15 simulated minutes of a moving player
-- without errors and without calling any native PilotSim does not model, that the wingmen follow,
-- and that the six pods are built. Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn11PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local sim = PilotSim.new{ name = "misn11", script = "Scripts/misn11cr.lua", bzn = "Missions/misn11cr.bzn",
    pattern = "(local Pilot = {.-)\n%-%- N64 Pilot Mode branch end",
    transform = function(s)
        s = s:gsub('require%("PlayerPilotMode"%)', "PlayerPilotMode")
        return (s:gsub('require%("CRPilotBranch"%)', "PilotBranch"))
    end,
    exports = "update = Pilot.Update, add = Pilot.AddObject", scrap = 20, pilots = 10 }
local M = sim.M
M.check2 = false
local slf = "avslf0_armory"
sim:unit(slf).deployed = true
local escorts = {}
for _, h in ipairs(sim.order) do
    local o = sim:unit(h)
    if o.team == 1 and (o.odf == "avtank" or o.odf == "avltnk") then escorts[#escorts + 1] = h end
end
sim:expect(#escorts == 3, "three wingman tanks in the BZN (" .. #escorts .. ")")
sim:hook(function(h) return sim.api.add(h) end)
for _, h in ipairs(escorts) do sim.api.add(h) end -- the engine's AddObject for the map's own units
local pods = { napammo = 0, naprepa = 0 }
sim.onSpawn = function(h) local o = sim:unit(h).odf; if pods[o] then pods[o] = pods[o] + 1 end end

-- The player flies to check2, then on to the launch point area and parks.
local legs = { { x = 1946, z = 99844 }, { x = 2600, z = 100800 } }
sim:each(function(s)
    local p = s:unit(s.player)
    local leg = (s.t < 200) and legs[1] or legs[2]
    local dx, dz = leg.x - p.x, leg.z - p.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d > 20 then local k = math.min(p.speed * s.dt, d - 20) / d; p.x, p.z = p.x + dx * k, p.z + dz * k end
end)
sim:when(function(s) return s.t >= 100 end, function() M.check2 = true end) -- the first transport reaches check2

sim:runFor(5)
for _, h in ipairs(escorts) do sim:expect(sim:unit(h).cmd == CMD.FOLLOW and sim:unit(h).tgt == sim.player, h .. " follows the player") end
sim:runUntil(function() return pods.napammo == 3 and pods.naprepa == 3 end, 600, "three ammo pods and three repair pods")
sim:expect(M.pilot.reloadLeft == 0 and M.pilot.repairLeft == 0, "the pod counters ran down")
sim:runFor(900 - sim.t)
for _, h in ipairs(escorts) do
    sim:expect(sim:unit(h).cmd == CMD.FOLLOW and sim:dist(h, sim.player) < 45, h .. " still follows the player and is within 45 m after 15 minutes")
end
sim:expect(pods.napammo == 3 and pods.naprepa == 3 and not sim.failed, "no extra pods, no failure")
print(string.format("misn11 PilotSim OK (no AI duties): 900 s without errors or unmodelled natives, wingmen follow, 3+3 pods built, script %s", sim.scriptPath))
