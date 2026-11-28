-- Unit test of the pilotMode hook in Scripts/CRCCARuntime.lua (StartPilotMode / PilotCall and the Start, Update,
-- AddObject, Save and Load call sites). Loads the real runtime the way the Misns*Coop tests do (the Misns1
-- fixture's stubbed natives and registry) and drives one Runtime.Create instance with a recording stand-in for
-- PlayerPilotMode. Run from the repository root:
--   lua5.1 Tools/MissionTests/Test-CCARuntimePilotMode.lua
assert(_VERSION == "Lua 5.1")
local F = dofile("Tools/MissionTests/Misns1Fixture.lua")
local checks = 0
local function check(ok, why) assert(ok, why); checks = checks + 1 end

-- One peer in a fresh world (the faithful misns1 script: no runtime of its own) and a runtime instance with
-- `cfg`. `pilot` is the PlayerPilotMode stand-in; `log` counts everything it and the hooks see.
local function scenario(network, cfg, pilotModule)
    F.reset()
    local peer = F.makePeer(1, 1, network, { faithful = true })
    local log = { required = 0, init = {}, updates = 0, enabledChecks = 0, saves = 0, added = {}, enable = 0, disable = 0 }
    log.enabled = false
    local pilot = pilotModule or {
        Initialize = function(adapter, state) log.init[#log.init + 1] = { adapter = adapter, state = state } end,
        Update = function() log.updates = log.updates + 1 end,
        IsEnabled = function() log.enabledChecks = log.enabledChecks + 1; return log.enabled end,
        Save = function() log.saves = log.saves + 1; log.saved = { n = log.saves }; return log.saved end,
    }
    peer.modules.PlayerPilotMode = nil
    setmetatable(peer.modules, { __index = function(_, name)
        if name == "PlayerPilotMode" then
            log.required = log.required + 1
            return pilot
        end
    end })
    local M = {}
    local config = { id = "pilotunit", leaderTeam = 1, enemyTeam = 5, mapEnemyTeam = 2, blackDogUnits = true,
        failDes = "x.des", wonFlags = { "missionwon" } }
    for k, v in pairs(cfg or {}) do config[k] = v end
    local R = peer.runtime.Create(function() return M end, config)
    return peer, R, M, log, pilot
end
local function newObject(peer)
    return peer.env.BuildObject("svtank", 1, "tank1")
end

-- 1. No pilotMode config: PlayerPilotMode is never required, nothing is called.
do
    local peer, R, M, log = scenario(false, nil)
    R.Start()
    check(R.Update(0.25) == true, "authority frame runs the body")
    R.AddObject(newObject(peer))
    R.Save()
    R.Load()
    check(log.required == 0, "no pilotMode config: PlayerPilotMode is never required")
    check(#log.init == 0 and log.updates == 0 and log.enabledChecks == 0 and log.saves == 0, "and never called")
    check(M.crcca.pilotModeState == nil, "no pilot state is saved")
end

-- 2. A pilotMode config that is not a table is ignored.
do
    local peer, R, M, log = scenario(false, { pilotMode = true })
    R.Start(); R.Update(0.25)
    check(log.required == 0, "a non-table pilotMode is ignored")
end

-- 3. Single player: Start initializes it with the scripted adapter and the saved state.
local peer, R, M, log, pilot
do
    local hooksLog = { added = {}, enable = 0, disable = 0 }
    local cfg = {
        update = function() end,
        addObject = function(h) hooksLog.added[#hooksLog.added + 1] = h end,
        enable = function() hooksLog.enable = hooksLog.enable + 1 end,
        disable = function() hooksLog.disable = hooksLog.disable + 1 end,
    }
    peer, R, M, log, pilot = scenario(false, { pilotMode = cfg })
    local saved = { enabled = true, marker = "from-the-save" }
    M.crcca = { arrivals = {}, serial = 0, live = {}, pilotModeState = saved }
    R.Start()
    check(log.required == 1, "single player: PlayerPilotMode is required once at Start")
    check(#log.init == 1, "Initialize called once")
    local adapter = log.init[1].adapter
    check(adapter.scripted == true, "the adapter is scripted")
    check(adapter.update == cfg.update and adapter.enable == cfg.enable and adapter.disable == cfg.disable,
        "the adapter carries the mission's update/enable/disable hooks")
    check(log.init[1].state == saved, "Initialize gets the saved crcca.pilotModeState")

    -- Update: the pilot updates only on frames where R.Update returns true.
    check(R.Update(0.25) == true and log.updates == 1, "PlayerPilotMode.Update runs on an authority frame")
    check(R.Update(0.25) == true and log.updates == 2, "and on the next one")
    M.coopResult = true
    check(R.Update(0.25) == false, "a finished co-op result frame returns false")
    check(log.updates == 2, "PlayerPilotMode.Update is not called on a frame R.Update returns false")
    M.coopResult = nil
    check(R.Update(0.25) == true and log.updates == 3, "updates resume")

    -- AddObject: the mission hook runs only while IsEnabled is true.
    local a, b = newObject(peer), newObject(peer)
    log.enabled = false
    R.AddObject(a)
    check(#hooksLog.added == 0, "addObject is not called while the mode is off")
    check(log.enabledChecks >= 1, "the runtime asked IsEnabled")
    log.enabled = true
    R.AddObject(b)
    check(#hooksLog.added == 1 and hooksLog.added[1] == b, "addObject is called with the object while the mode is on")
    R.AddObject(nil)
    R.AddObject(0)
    check(#hooksLog.added == 1, "an invalid handle never reaches the mission hook")

    -- Save stores PlayerPilotMode.Save() in crcca.pilotModeState.
    R.Save()
    check(log.saves == 1 and M.crcca.pilotModeState == log.saved, "Save stores PlayerPilotMode.Save() in crcca.pilotModeState")

    -- Load re-initializes with the saved state.
    local inits = #log.init
    R.Load()
    check(#log.init == inits + 1, "Load re-initializes PlayerPilotMode")
    check(log.init[#log.init].state == log.saved, "with the state Save stored")
    check(log.init[#log.init].adapter.scripted == true, "and a scripted adapter again")

    -- A failing pilot call never breaks the runtime.
    local failing = {
        Initialize = function() end,
        Update = function() error("boom") end,
        IsEnabled = function() error("boom") end,
        Save = function() error("boom") end,
    }
    local _, R2, M2 = scenario(false, { pilotMode = { addObject = function() end } }, failing)
    R2.Start()
    check(R2.Update(0.25) == true, "a failing Update does not stop the frame")
    R2.AddObject(newObject(peer))
    R2.Save()
    check(M2.crcca.pilotModeState == nil, "a failing Save stores nothing")
end

-- 4. PlayerPilotMode unavailable / failing to start: the mission runs without it.
do
    local hooksLog = { added = {} }
    local peer2, R2, M2, log2 = scenario(false, { pilotMode = { addObject = function(h) hooksLog.added[#hooksLog.added + 1] = h end } },
        { Initialize = function() error("no start") end, Update = function() error("never") end,
          IsEnabled = function() return true end, Save = function() error("never") end })
    R2.Start()
    check(R2.Update(0.25) == true, "Update runs with a pilot that failed to start")
    R2.AddObject(newObject(peer2))
    R2.Save()
    check(#hooksLog.added == 0 and M2.crcca.pilotModeState == nil, "a pilot that failed to start is never called again")
end

-- 5. Network game: nothing is required or called.
do
    local hooksLog = { added = {}, enable = 0, disable = 0 }
    local cfg = {
        update = function() hooksLog.update = true end,
        addObject = function(h) hooksLog.added[#hooksLog.added + 1] = h end,
        enable = function() hooksLog.enable = hooksLog.enable + 1 end,
        disable = function() hooksLog.disable = hooksLog.disable + 1 end,
    }
    local peerN, RN, MN, logN = scenario(true, { pilotMode = cfg })
    logN.enabled = true
    RN.Start()
    F.connect()
    RN.Update(0.25)
    for _ = 1, 8 do F.tick(0.25); RN.Update(0.25) end
    RN.AddObject(newObject(peerN))
    RN.Save()
    RN.Load()
    check(logN.required == 0, "network game: PlayerPilotMode is never required")
    check(#logN.init == 0 and logN.updates == 0 and logN.enabledChecks == 0 and logN.saves == 0,
        "network game: no PlayerPilotMode call")
    check(#hooksLog.added == 0 and not hooksLog.update and hooksLog.enable == 0 and hooksLog.disable == 0,
        "network game: no mission hook is called")
    check(MN.crcca.pilotModeState == nil, "network game: nothing is saved")
end

print("CCA runtime pilotMode hook checks passed: " .. checks)
