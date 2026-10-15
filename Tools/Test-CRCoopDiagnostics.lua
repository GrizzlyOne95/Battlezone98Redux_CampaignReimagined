-- Lua 5.1: real observer/state model and PDA view, with controllable traffic.
package.path = "Scripts/?.lua;" .. package.path
local Model, Pda, Data = require("CRCoopDiagnostics"), require("CRCoopPda"), require("PersistentConfigData")
local now, ready, departed, phase, checks = 0, false, false, 1, 0
local appAge
local players = { [1] = { name = "Host", team = 1, handle = {} },
    [2] = { name = "Guest\nName", team = 2, handle = {} }, [9] = { team = 5 } }
local function check(value, label) assert(value, label); checks = checks + 1 end
local valid = function(h) return h ~= nil and not h.invalid end
local model = Model.Create({ time = function() return now end, players = function() return players end,
    localId = function() return 1 end, humanTeam = function(t) return t and t >= 1 and t <= 4 end,
    valid = valid, protocol = 1, phase = function() return phase end, ready = function() return ready end,
    leaderTeam = function() return 1 end, leaderDeparted = function() return departed end,
    delivery = function() return { peers = { [2] = { receiveAge = appAge } } } end })
local function peer() return model.Snapshot().players[2] end
check(peer().status == "Syncing" and peer().heartbeatAge == nil, "no invented initial sync")
check(not model.Snapshot().players[9], "AI team excluded")
model.Sent(0); model.Sent(2); model.Received(99, true, 1, true, 1)
check(peer().sent == 2 and peer().received == 0, "known peer control attempts only")
model.Received(2, true, 1, false, 1)
check(peer().status == "Syncing" and peer().admitted == false, "false admission is preserved")
ready = true; model.Received(2, true, 1, true, 1)
check(peer().status == "Synced" and peer().heartbeatAge == 0, "admitted peer and matching phase")
now = 3
check(peer().status == "No recent traffic", "quiet boundary")
model.Received(2) -- A phase/ack is not a fresh heartbeat.
check(peer().status == "Heartbeat delayed" and peer().receiveAge == 0,
    "other control traffic is distinguished from a stale heartbeat")
now = 10
check(peer().status == "No recent traffic", "latest accepted control defines traffic age")
now = 13
check(peer().status == "Traffic stalled", "stalled boundary overrides retained admission")
appAge = 0
check(peer().status == "Heartbeat delayed", "application traffic prevents a false transport-stalled claim")
appAge = nil
model.Received(2, true, 1, true, 1)
check(peer().status == "Synced", "traffic recovery is immediate")
model.Received(2, true, 1, true, 0)
check(peer().status == "Phase differs", "behind phase")
model.Received(2, true, 1, true, 2)
check(peer().status == "Phase differs", "ahead phase does not count as sync")
model.Received(2, true)
check(peer().status == "Readiness unknown" and peer().protocol == nil, "legacy heartbeat clears old metadata")
model.Received(2, true, 99, true, 1)
check(peer().status == "Protocol mismatch", "unsupported protocol is visible")
players[2].lateJoin = true
check(peer().status == "Restart required", "late join")
players[2].lateJoin = false; departed = true
check(peer().status == "Host left", "host departure")
departed = false; model.Received(2, true, 1, true, 1)
players[2].handle.invalid = true
check(peer().status == "Player unavailable", "dead/missing player handle")
players[2].handle.invalid = false
local copy = peer(); copy.sent = 999
check(peer().sent == 2, "read-only snapshot")
model.Forget(2)
check(peer().status == "Syncing" and peer().received == 0, "reused network id cannot retain health")
model.Received(2, true, 1, true, 1); model.Reset()
check(peer().heartbeatAge == nil and peer().sent == 0, "mission reset")

local nativeCalls, unavailable, samples = 0, false, 10
local comms = { IsActive = function() return true end,
    GetNetworkDiagnostics = function() return { peers = { [2] = { pending = 2, retries = 3, expired = 1, acknowledged = 4 } } } end }
local coop = { GetComms = function() return comms end, GetPlayers = function() return players end,
    GetNetworkDiagnostics = model.Snapshot }
local ui = Pda.Create({ coop = coop, pages = Data.PdaPages, time = function() return now end,
    exu = { GetPlayerNetworkStats = function(id)
        nativeCalls = nativeCalls + 1
        if unavailable then error("unsupported") end
        return { id = id, team = players[id].team, kills = 2, deaths = 1, pingMs = 42, lossPercent = 10, pingSamples = samples }
    end } })
local function render()
    return ui.BuildDiagnosticsText(function() return "Coop Diagnostics" end,
        function(lines, ...) for _, s in ipairs({...}) do lines[#lines+1] = s end end)
end
model.Received(2, true, 1, true, 1)
local text = render()
check(text:find("42ms / 10%% loss") and text:find("local / n/a",1,true), "native remote metrics and no fake local zeros")
check(not text:find("Guest\nName",1,true), "native/control names cannot inject rows")
local calls = nativeCalls; render()
check(calls == nativeCalls, "native reader sampled once per second")
ui.HandleDiagnosticsInput(false,true); text = render()
check(text:find("Action pending 2 | retry 3",1,true) and text:find("Ack 4 | expired 1",1,true), "per-peer application delivery diagnostics")
check(text:find("Kills/deaths 2/1",1,true), "native score snapshot included")
samples = 0; now = now + 1; text = render()
check(text:find("waiting for ping samples",1,true) and not text:find("42ms",1,true), "unmeasured link does not show healthy zeros")
unavailable = true; now = now + 1; text = render()
check(text:find("net stats unavailable",1,true) and not text:find("Kills/deaths",1,true), "failed refresh clears cached native values")
players[2] = nil; ui.HandleDiagnosticsInput(false,true); text = render()
check(not text:find("Guest Name",1,true), "departed peer removed")
unavailable = false
players[2] = { name = "Two", team = 2, handle = {} }
players[3] = { name = "Three", team = 3, handle = {} }
players[4] = { name = "Four", team = 4, handle = {} }
now = now + 1; text = render()
check(text:find("Two",1,true) and text:find("Three",1,true) and text:find("Four",1,true), "all four human slots fit the view model")
check(not text:find("Team 5",1,true), "AI does not enter the selectable diagnostics roster")
print("CRCoopDiagnostics: " .. checks .. " checks passed")
