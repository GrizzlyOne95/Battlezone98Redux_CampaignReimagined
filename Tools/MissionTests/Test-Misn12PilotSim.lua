-- Simulation of misn12cr's N64 Pilot Mode branch (misn12cr.lua ~799-873): NO AI DUTIES.
-- The branch is markers only (the header at ~805 says "No AI changes, no AddObject hook, no unit
-- orders"): it makes the hangar and checkpoint cameras objectives while the mission has them on team 1
-- (camera_swap1 / camera_swap2) and drops the markers again, plus the generic command lock. Nothing in
-- the win depends on a unit the branch must order, so there is no win path to simulate. This scenario
-- only asserts that the block runs for two simulated hours of a moving player without errors and
-- without calling any native PilotSim does not model, that the markers follow the two mission flags
-- (each group on and off, three cycles), that no order is ever given to team-1 units (the lock
-- re-issues only what they already had) and that the mission is not failed. Run from the repo root:
--   lua5.1 Tools/MissionTests/Test-Misn12PilotSim.lua
local PilotSim = dofile("Tools/MissionTests/PilotSim.lua")
local CMD = PilotSim.AiCommand

local sim = PilotSim.new{ name = "misn12", script = "Scripts/misn12cr.lua", bzn = "Missions/misn12cr.bzn",
    -- the block assigns into the mission's missionPda table; give it one
    transform = function(s)
        s = s:gsub('missionPda%.pilot = {', 'missionPda = {}\nmissionPda.pilot = {', 1)
        s = s:gsub('require%("PlayerPilotMode"%)', "PlayerPilotMode")
        return (s:gsub('require%("CRPilotBranch"%)', "PilotBranch"))
    end,
    pattern = "(missionPda = {}\nmissionPda%.pilot = {.-)\n%-%- N64 Pilot Mode branch end",
    exports = "update = missionPda.pilot.Update", scrap = 0, pilots = 0 }
local M = sim.M
sim.env.SetObjectiveOff = function(h) sim.marked[h] = nil end
local hangarNames = { "start_cam", "check2_cam", "check3_cam", "check4_cam", "goal_cam" }
for _, name in ipairs(hangarNames) do
    local x, z = sim:pos(name)
    M[name] = sim:add("apcamr", 1, x, z, name .. "_obj")
end
M.center_cam = sim:add("apcamr", 1, sim:pos("center_cam"))
-- A team-1 wingman with a Follow order: the lock must keep it, and nothing else may be ordered.
local wing = sim:add("avtank", 1, 3500, 97900)
sim:unit(wing).cmd, sim:unit(wing).tgt = CMD.FOLLOW, sim.player
local ordersBefore = #sim.log

-- The player wanders between the cameras at hover speed.
local tour = { "start_cam", "check2_cam", "center_cam", "check3_cam", "check4_cam", "goal_cam" }
local leg = 1
sim:each(function(s)
    local p = s:unit(s.player)
    local x, z = s:pos(tour[leg])
    local dx, dz = x - p.x, z - p.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 30 then leg = leg % #tour + 1 else
        local k = math.min(p.speed * s.dt, d) / d; p.x, p.z = p.x + dx * k, p.z + dz * k
    end
end)

local function markers(set) local n = 0; for _, c in ipairs(set) do if sim.marked[M[c]] then n = n + 1 end end; return n end
for cycle = 1, 3 do
    sim:runFor(60)
    sim:expect(markers(hangarNames) == 0 and not sim.marked[M.center_cam], "no markers while the cameras are not on team 1")
    M.camera_swap1 = true; sim:runFor(10)
    sim:expect(markers(hangarNames) == 5 and not sim.marked[M.center_cam], "hangar cameras marked (cycle " .. cycle .. ")")
    M.camera_swap2 = true; sim:runFor(10)
    sim:expect(sim.marked[M.center_cam], "checkpoint camera marked (cycle " .. cycle .. ")")
    M.camera_swap1 = false; sim:runFor(10)
    sim:expect(markers(hangarNames) == 0 and sim.marked[M.center_cam], "hangar markers off, checkpoint still on")
    M.camera_swap2 = false; sim:runFor(10)
    sim:expect(not sim.marked[M.center_cam], "checkpoint marker off")
end
sim:runFor(7200 - sim.t) -- two simulated hours of a quiet mission
sim:expect(sim:unit(wing).cmd == CMD.FOLLOW and sim:unit(wing).tgt == sim.player, "the wingman's order was only re-issued as it was")
sim:expect(#sim.log == ordersBefore, "the branch gave no order and built nothing")
sim:expect(not sim.failed, "the branch did not fail the mission")
print(string.format("misn12 PilotSim OK (no AI duties): %d s without errors or unmodelled natives, markers follow camera_swap1/2 over 3 cycles, no orders given, script %s",
    sim.t, sim.scriptPath))
