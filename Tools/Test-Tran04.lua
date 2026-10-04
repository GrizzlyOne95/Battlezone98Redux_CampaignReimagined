-- Run from repository root: lua5.1 Tools/Test-Tran04.lua
local function Mission()
    local world = {
        time = 0, selected = {}, deployed = {}, shot = {}, sounds = {}, outcomes = {},
        live = {recycler = true, drone1 = true, drone2 = true, camera = true, player = true},
        labels = {avturr12_turrettank = "drone1", ["avturr-1_turrettank"] = "drone2",
            ["avrecy-1_recycler"] = "recycler", ["apcamr-1_camerapod"] = "camera",
            ["player-1_hover"] = "player"},
        team = {}, odf = {}, distance = 400,
    }
    local env = setmetatable({}, {__index = _G})
    env.GetHandle = function(label) return world.labels[label] end
    env.IsValid = function(h) return world.live[h] == true end
    env.IsAlive = env.IsValid
    env.GetTime = function() return world.time end
    env.GetTeamNum = function(h) return world.team[h] end
    env.IsOdf = function(h, odf) return world.odf[h] == odf end
    env.IsSelected = function(h)
        assert(world.live[h], "selection queried on deleted object")
        return world.selected[h] == true
    end
    env.IsDeployed = function(h) return world.deployed[h] == true end
    env.GetLastEnemyShot = function(h) return world.shot[h] or 0 end
    env.GetUserTarget = function() return world.target end
    env.GetDistance = function() return world.distance end
    env.SetScrap = function(team, amount) world.scrap = amount end
    env.AudioMessage = function(s) world.sounds[#world.sounds + 1] = s end
    env.ClearObjectives = function() world.clears = (world.clears or 0) + 1 end
    env.AddObjective = function(name, color) world.objective = {name, color} end
    env.SetObjectiveOn = function(h) world.marker = h end
    env.SetObjectiveName = function(h, name) world.name = name end
    env.FailMission = function(time, file) world.outcomes[#world.outcomes + 1] = {"fail", time, file} end
    env.SucceedMission = function(time, file) world.outcomes[#world.outcomes + 1] = {"win", time, file} end
    setfenv(assert(loadfile("Scripts/tran04.lua")), env)()
    function world:Tick(time) self.time = time or self.time; env.Update(0.1) end
    function world:Fighter(h, team)
        self.live[h] = true; self.team[h] = team or 1; self.odf[h] = "avfigh"; env.AddObject(h)
    end
    return env, world
end

local function Count(w, sound)
    local count = 0
    for _, s in ipairs(w.sounds) do if s == sound then count = count + 1 end end
    return count
end

local e, w = Mission()
-- Startup callbacks survive Start; enemy fighters cannot replace the wingman.
w:Fighter("wing")
w:Fighter("enemy", 2)
e.Start()
assert(e.Save().wing == "wing")
w:Tick()
assert(w.scrap == 30 and w.clears == 1 and #w.sounds == 3)
assert(w.objective[1] == "tran0401.otf" and w.objective[2] == "white")
w.selected.recycler = true; w.deployed.recycler = true; w:Tick(1)
assert(e.Save().message6 and Count(w, "tran0406.wav") == 1)
w.selected.recycler = false; w:Tick(2)
w:Tick(7); assert(Count(w, "tran0408.wav") == 0) -- strict >
w:Tick(7.1); assert(Count(w, "tran0408.wav") == 1)
w.target = "camera"; w:Tick(8)
w:Tick(11); assert(not e.Save().message9)
w:Tick(11.1); assert(e.Save().message9)
w.selected.wing = true; w:Tick(12)
w.selected.wing = false; w:Tick(13)
w:Tick(23); assert(not e.Save().message11)
-- Save/load in the timed instruction: initialization and deadline must survive.
local saved = e.Save()
local restored, rw = Mission()
rw.live.wing = true; restored.Load(saved); rw:Tick(23.1)
assert(restored.Save().message11 and Count(rw, "tran0412.wav") == 1)
assert(rw.scrap == nil and rw.clears == nil)
w.shot.wing = 1; w:Tick(24); w:Tick(25)
assert(Count(w, "tran0413.wav") == 1)
w.live.drone1 = false; w.distance = 299; w:Tick(26)
assert(w.marker == "drone2" and w.name == "Drone 2")
assert(e.Save().message13 and Count(w, "tran0418.wav") == 1)
w.target = "drone2"; w.selected.wing = true; w:Tick(27)
assert(e.Save().message15 and Count(w, "tran0420.wav") == 1)
w.live.drone2 = false; w:Tick(28); w:Tick(29)
assert(#w.outcomes == 1 and w.outcomes[1][1] == "win" and w.outcomes[1][2] == 38)
assert(w.outcomes[1][3] == "tran04w1.des")

-- Targeting the camera before building a fighter must not fail the tutorial.
e, w = Mission(); e.Start(); w:Tick()
w.selected.recycler = true; w.deployed.recycler = true; w:Tick()
w.selected.recycler = false; w.target = "camera"; w:Tick(1); w:Tick(5)
assert(#w.outcomes == 0 and not e.Save().message9)
w:Fighter("wing"); w:Tick(6); assert(e.Save().message9)
-- Wingman death takes precedence over simultaneous destruction of both drones;
-- the later selection query must never touch the removed handle.
e.Save().message14 = true
w.live.wing = false; w.live.drone1 = false; w.live.drone2 = false; w:Tick(7); w:Tick(8)
assert(#w.outcomes == 1 and w.outcomes[1][1] == "fail" and w.outcomes[1][2] == 12)
assert(w.outcomes[1][3] == "tran04l1.des")

-- Destroying either target before the combat instruction retains native loss.
e, w = Mission(); w.live.drone1 = false; w:Tick(10); w:Tick(11)
assert(#w.outcomes == 1 and w.outcomes[1][1] == "fail" and w.outcomes[1][2] == 15)
print("Tran04: tutorial, strict delays, save/load, callbacks, victory and failure checks passed")
