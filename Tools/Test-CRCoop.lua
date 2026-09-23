-- Regression coverage for the CRCoop player registry, leader authority,
-- human-team range, reconnect handshake, and host-migration guard.
local source = arg[1] or "Scripts/CRCoop.lua"

local now = 0.0
local netGame = false
local hosting = false
local localId = 10
local sent = {}
local alliances = {}
local localHandle = { id = "local", valid = true, team = 1 }
local remoteHandle = { id = "remote", valid = true, team = 2 }
local target = { id = "target", valid = true }

IsNetGame = function() return netGame end
IsHosting = function() return hosting end
GetTime = function() return now end
GetPlayerHandle = function() return localHandle end
GetTeamNum = function(h) return h and h.team or -1 end
IsValid = function(h) return h ~= nil and h.valid ~= false end
GetDistance = function(a, b)
    if b ~= target then return 9999 end
    if a == localHandle then return 50 end
    if a == remoteHandle then return 75 end
    return 9999
end
Send = function(to, kind, ...)
    sent[#sent + 1] = { to = to, kind = kind, args = { ... } }
    return true
end
Ally = function(a, b)
    alliances["A:" .. a .. ":" .. b] = true
end
UnAlly = function(a, b)
    alliances["U:" .. a .. ":" .. b] = true
end

local Coop = assert(loadfile(source))()
Coop.Initialize({
    getLocalPlayerId = function() return localId end,
    leaderTeam = 1,
    humanTeamMin = 1,
    humanTeamMax = 4,
})

assert(Coop.IsAuthority(), "single-player must be authoritative")
assert(Coop.IsCampaignLeader(), "single-player must be campaign leader")
assert(Coop.IsHumanTeam(1) and Coop.IsHumanTeam(4), "human team range missing valid slot")
assert(not Coop.IsHumanTeam(5), "enemy team must not be classified as human")
assert(Coop.IsHumanCraft(localHandle), "local player was not recognized")
assert(Coop.AllPlayersNear(target, 100), "single-player proximity changed")

netGame = true
hosting = true
Coop.CreatePlayer(10, "Host", 1)
Coop.CreatePlayer(20, "Client", 2)

assert(Coop.IsAuthority(), "team-1 host must be authoritative")
assert(Coop.IsCampaignLeader(), "team-1 host must be campaign leader")
assert(not Coop.HasAllPlayerHandles(), "remote handle should be required")
assert(not Coop.IsSessionReady(), "session must wait for remote handshake")
assert(not Coop.AllPlayersNear(target, 100), "incomplete registry must not satisfy all-player checks")

Coop.ApplyCoopAlliances(5)
assert(alliances["A:1:2"] and alliances["A:2:1"], "human alliances must be bidirectional")
assert(alliances["U:1:5"] and alliances["U:5:1"], "enemy hostility must be bidirectional")

Coop.Update()
assert(#sent >= 1, "handle broadcast was not sent")
assert(sent[1].to == 0 and sent[1].kind == "H", "handle broadcast format changed")
assert(sent[1].args[1] == localHandle, "local handle was not broadcast")

assert(Coop.Receive(20, "H", remoteHandle), "handle message was not consumed")
assert(Coop.HasAllPlayerHandles(), "complete player registry was not recognized")
assert(Coop.IsHumanCraft(remoteHandle), "remote player was not recognized")
assert(not Coop.IsSessionReady(), "host must wait for client sync request")

assert(Coop.Receive(20, "Q", remoteHandle, 2, 1), "sync request was not consumed")
assert(Coop.IsSessionReady(), "host did not mark client ready")
local ack = sent[#sent]
assert(ack.to == 20 and ack.kind == "K" and ack.args[1] == 1, "host sync acknowledgement changed")
assert(Coop.AllPlayersNear(target, 100), "all-player proximity check failed")

-- A reconnect is a new participant ID and must handshake again.
Coop.DeletePlayer(20)
assert(Coop.HasAllPlayerHandles(), "departed client remained required")
Coop.CreatePlayer(30, "ClientRejoin", 2)
assert(not Coop.HasAllPlayerHandles(), "rejoin incorrectly inherited old handle")
assert(not Coop.IsSessionReady(), "rejoin incorrectly inherited old handshake")
assert(Coop.Receive(30, "H", remoteHandle), "rejoin handle was not consumed")
assert(Coop.Receive(30, "Q", remoteHandle, 2, 1), "rejoin sync request was not consumed")
assert(Coop.IsSessionReady(), "rejoined player did not complete fresh handshake")

Coop.MarkMissionStarted()
Coop.CreatePlayer(40, "LateJoin", 3)
assert(Coop.HasLateJoiners(), "post-start participant was not marked as late join")

-- If Team 1 leaves and the engine migrates host to Team 2, campaign authority
-- must NOT migrate with it.
Coop.DeletePlayer(10)
assert(Coop.HasLeaderDeparted(), "leader departure was not recorded")
localId = 30
localHandle = remoteHandle
hosting = true
assert(not Coop.IsCampaignLeader(), "migrated network host inherited campaign leadership")
assert(not Coop.IsAuthority(), "migrated network host inherited simulation authority")

-- A client retries the handshake until the Team-1 leader acknowledges it.
local clientCoop = assert(loadfile(source))()
sent = {}
localId = 50
localHandle = { id = "client-local", valid = true, team = 2 }
local hostHandle = { id = "host-remote", valid = true, team = 1 }
hosting = false
clientCoop.Initialize({ getLocalPlayerId = function() return localId end })
clientCoop.CreatePlayer(60, "Host", 1)
clientCoop.CreatePlayer(50, "Client", 2)
assert(clientCoop.Receive(60, "H", hostHandle), "client did not consume leader handle")
clientCoop.Update()
local sawRequest = false
for _, msg in ipairs(sent) do
    if msg.kind == "Q" then sawRequest = true end
end
assert(sawRequest, "client did not request leader sync")
assert(not clientCoop.IsSessionReady(), "client became ready without leader ack")
assert(clientCoop.Receive(60, "K", 1), "client did not consume leader ack")
assert(clientCoop.IsSessionReady(), "client did not become ready after leader ack")

io.write("CRCoop checks passed\n")
