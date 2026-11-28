-- Execute misn12cr's N64 Pilot Mode branch (missionPda.pilot) with stubbed natives: markers only.
-- The hangar and checkpoint cameras become objectives while the mission has them on team 1
-- (camera_swap1 / camera_swap2) and drop off when it switches them back; no orders, no AddObject.
local file = assert(io.open("Scripts/misn12cr.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local block = assert(source:match("(missionPda%.pilot = {.-)\n%-%- N64 Pilot Mode branch end"))
local checks = 0
local function check(v, why) assert(v, why); checks = checks + 1 end

local now, enabled = 0, true
local objs, calls = {}, {}
local function obj(name) objs[name] = { alive = true, team = 7 }; return name end
local hangar = { obj("start_cam"), obj("check2_cam"), obj("check3_cam"), obj("check4_cam"), obj("goal_cam") }
local centerCam = obj("center_cam")
local player = "player"
local env = setmetatable({}, { __index = _G })
env.M = { start_cam = "start_cam", check2_cam = "check2_cam", check3_cam = "check3_cam",
          check4_cam = "check4_cam", goal_cam = "goal_cam", center_cam = "center_cam",
          camera_swap1 = false, camera_swap2 = false }
env.missionPda = {}
env.AiCommand = { NONE = 0 }
env.CRCoop = { IsNetworkGame = function() return false end }
env.pcall = pcall
env.require = function(name)
    if name == "PlayerPilotMode" then
        return { IsEnabled = function() return enabled end,
                 Initialize = function(adapter, state) env.adapter, env.initState = adapter, state end,
                 Update = function() env.ticked = true end, Save = function() return { saved = true } end }
    elseif name == "CRPilotBranch" then
        local B = assert(loadfile("Scripts/CRPilotBranch.lua"))()
        for _, f in pairs(B) do if type(f) == "function" then setfenv(f, env) end end
        return B
    end
end
env.GetTime = function() return now end
env.GetPlayerHandle = function() return player end
env.IsAlive = function(h) return h == player or (objs[h] ~= nil and objs[h].alive) end
env.IsValid = env.IsAlive
env.GetTeamNum = function() return 1 end
env.GetCurrentCommand = function() return 0 end
env.GetCurrentWho = function() return nil end
env.AllCraft = function() return function() return nil end end
env.SetCommand = function() calls[#calls + 1] = { "setcommand" } end
env.SetObjectiveOn = function(h) calls[#calls + 1] = { "on", h } end
env.SetObjectiveOff = function(h) calls[#calls + 1] = { "off", h } end
local chunk = assert(loadstring("local M, missionPda = M, missionPda\n" .. block .. "\nreturn missionPda.pilot"))
setfenv(chunk, env)
local Pilot = chunk()
local function count(kind, who)
    local n = 0
    for _, c in ipairs(calls) do if c[1] == kind and (who == nil or c[2] == who) then n = n + 1 end end
    return n
end

Pilot.Init()
check(env.adapter and env.adapter.scripted == true and env.adapter.update == Pilot.Update, "scripted adapter")
check(env.adapter.disable ~= nil, "adapter has a disable hook")
check(Pilot.Save().saved and env.M.playerPilotModeState.saved, "Save keeps the PlayerPilotMode state")
Pilot.Tick(); check(env.ticked, "Tick drives PlayerPilotMode.Update")

-- Nothing before the mission switches a camera group to team 1.
Pilot.Update(); now = 1; Pilot.Update()
check(#calls == 0, "no markers before the cameras are revealed")

-- Hangar cameras (center/sbhqt2 within 100 m): all five become objectives, once.
env.M.camera_swap1 = true
Pilot.Update()
check(count("on") == 5, "five hangar cameras marked")
for _, cam in ipairs(hangar) do check(count("on", cam) == 1, cam .. " marked once") end
check(count("on", centerCam) == 0, "checkpoint camera untouched")
Pilot.Update(); now = 2; Pilot.Update(); check(count("on") == 5, "markers are not re-sent every frame")

-- Checkpoint camera (checktower1 within 100 m).
env.M.camera_swap2 = true
Pilot.Update()
check(count("on") == 6 and count("on", centerCam) == 1, "checkpoint camera marked")

-- Player past 300 m: the mission clears the swap flag and the markers go off (hangar first).
env.M.camera_swap1 = false
Pilot.Update()
check(count("off") == 5 and count("off", centerCam) == 0, "hangar markers off")
env.M.camera_swap2 = false
Pilot.Update()
check(count("off") == 6 and count("off", centerCam) == 1, "checkpoint marker off")
Pilot.Update(); check(count("off") == 6 and count("on") == 6, "no further calls")

-- Re-entry marks again.
env.M.camera_swap2 = true; Pilot.Update(); check(count("on", centerCam) == 2, "checkpoint re-marked on re-entry")

-- A dead camera is skipped; disable clears live markers and a toggle cycle adds no duplicates.
env.M.camera_swap1 = true; objs.check3_cam.alive = false
local before = count("on")
Pilot.Update()
check(count("on") == before + 4 and count("on", "check3_cam") == 1, "dead camera skipped")
env.adapter.disable()
check(count("off", centerCam) == 2 and count("off", "start_cam") == 2, "disable clears the markers")
local offs = count("off")
env.adapter.disable(); check(count("off") == offs, "second disable is a no-op")
Pilot.Update()
check(count("on", "start_cam") == 3 and count("on", centerCam) == 3, "markers return on re-enable")
check(count("setcommand") == 0, "no unit orders in this branch")
print("misn12 Pilot Mode branch checks passed: " .. checks)
