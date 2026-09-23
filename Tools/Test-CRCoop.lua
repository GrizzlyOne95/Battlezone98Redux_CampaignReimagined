-- Regression coverage for the CRCoop player registry and authority helpers.
local source = arg[1] or "Scripts/CRCoop.lua"

local now = 0.0
local netGame = false
local hosting = false
local localId = 10
local sent = {}
local localHandle = { id = "local", valid = true }
local remoteHandle = { id = "remote", valid = true }
local target = { id = "target", valid = true }

IsNetGame = function() return netGame end
IsHosting = function() return hosting end
GetTime = function() return now end
GetPlayerHandle = function() return localHandle end
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

local Coop = assert(loadfile(source))()
Coop.Initialize({ getLocalPlayerId = function() return localId end })

assert(Coop.IsAuthority(), "single-player must be authoritative")
assert(Coop.IsHumanCraft(localHandle), "local player was not recognized")
assert(Coop.AllPlayersNear(target, 100), "single-player proximity changed")

netGame = true
hosting = true
Coop.CreatePlayer(10, "Host", 1)
Coop.CreatePlayer(20, "Client", 1)

assert(Coop.IsAuthority(), "host must be authoritative")
assert(not Coop.HasAllPlayerHandles(), "remote handle should be required")
assert(not Coop.AllPlayersNear(target, 100), "incomplete registry must not satisfy all-player checks")

Coop.Update()
assert(#sent == 1, "handle broadcast was not sent")
assert(sent[1].to == 0 and sent[1].kind == "H", "handle broadcast format changed")
assert(sent[1].args[1] == localHandle, "local handle was not broadcast")

assert(Coop.Receive(20, "H", remoteHandle), "handle message was not consumed")
assert(Coop.HasAllPlayerHandles(), "complete player registry was not recognized")
assert(Coop.IsHumanCraft(remoteHandle), "remote player was not recognized")
assert(Coop.AllPlayersNear(target, 100), "all-player proximity check failed")

remoteHandle.valid = false
assert(not Coop.HasAllPlayerHandles(), "invalid remote handle must make registry incomplete")
remoteHandle.valid = true

Coop.DeletePlayer(20)
assert(Coop.HasAllPlayerHandles(), "departed player remained required")

hosting = false
assert(not Coop.IsAuthority(), "client must not be authoritative")

io.write("CRCoop checks passed\n")
