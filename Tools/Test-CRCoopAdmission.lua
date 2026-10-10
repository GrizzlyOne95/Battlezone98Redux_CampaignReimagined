-- Replay the observed Receive(Q) -> Initialize -> guest stops retrying race.
local source = arg[1] or "Scripts/CRCoop.lua"
local now, net, hosting, id = 0, true, true, 1
local host = {team=1, valid=true}
local guest = {team=2, valid=true}
local handle = host
local sent = {}
IsNetGame = function() return net end
IsHosting = function() return hosting end
GetTime = function() return now end
GetPlayerHandle = function() return handle end
GetTeamNum = function(h) return h.team end
IsValid = function(h) return h and h.valid end
Send = function(to,kind,...) sent[#sent+1]={to=to,kind=kind,args={...}} end

local leader = assert(loadfile(source))()
leader.CreatePlayer(1,"Host",1)
leader.CreatePlayer(2,"Guest",2)
assert(leader.Receive(2,"Q",guest,2,1))
assert(#sent==0, "pre-Initialize Q acknowledged state that Start will erase")
assert(not leader.IsSessionReady(), "host ready before initialization")
leader.Update()
assert(#sent==0, "pre-Initialize Update transmitted admission state")
leader.Initialize({getLocalPlayerId=function() return id end})
assert(not leader.IsSessionReady(), "Initialize retained an early handshake")
assert(leader.Receive(2,"Q",guest,2,1))
assert(leader.IsSessionReady(), "post-Initialize retry failed to admit guest")
assert(sent[#sent].kind=="K" and sent[#sent].to==2, "post-Initialize ack missing")

-- A guest ignores early ACK/phase state and keeps requesting a fresh handshake.
hosting, id, handle, sent = false, 2, guest, {}
local client = assert(loadfile(source))()
client.CreatePlayer(1,"Host",1)
client.CreatePlayer(2,"Guest",2)
client.Receive(1,"K",1,7)
client.Receive(1,"P",8)
client.Initialize({getLocalPlayerId=function() return id end})
client.Receive(1,"H",host)
assert(not client.IsSessionReady() and client.GetMissionPhase()==0, "early admission survived Initialize")
client.Update()
assert(sent[#sent].kind=="Q", "guest did not request a fresh handshake")
client.Receive(1,"K",1,0)
assert(client.IsSessionReady(), "valid fresh host ack rejected")
sent={};now=2;client.Update()
for _,msg in ipairs(sent) do assert(msg.kind~="Q", "acknowledged client still retries Q") end

-- Reinitialization still removes prior mission admission/phase/handles.
client.Receive(1,"P",5)
client.MarkMissionStarted()
client.Initialize({getLocalPlayerId=function() return id end})
assert(not client.IsSessionReady() and client.GetMissionPhase()==0, "prior mission readiness carried forward")
client.Receive(1,"H",host)
client.Receive(1,"K",99,0)
assert(not client.IsSessionReady(), "wrong protocol acknowledged")
client.CreatePlayer(3,"Other",3)
client.Receive(3,"K",1,4)
assert(not client.IsSessionReady() and client.GetMissionPhase()==0, "non-leader acknowledged")
client.DeletePlayer(3)
client.Receive(1,"K",1,0)
assert(client.IsSessionReady(), "reinitialized guest cannot recover")

net=false
local single = assert(loadfile(source))()
assert(single.IsSessionReady(), "single-player readiness changed")
io.write("CRCoop admission lifecycle checks passed\n")
