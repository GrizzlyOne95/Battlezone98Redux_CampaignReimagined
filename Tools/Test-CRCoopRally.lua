-- Test the real registry/respawn adapter against Redux's string-path behavior.
package.path = "Scripts/?.lua;" .. package.path
local now, nativeLives, player = 0, 999, nil
local factory = {pos={x=1400,y=75,z=100800}, alive=true, team=0}
local path = {x=400,y=25,z=900}
function IsNetGame() return true end
function IsHosting() return true end
function GetTime() return now end
function GetPlayerHandle() return player end
function GetTeamNum(h) return h.team end
function IsValid(h) return type(h) == "table" and h.pos ~= nil end
function IsAlive(h) return h.alive end
function GetHandle(label) return label == "lemnos" and factory or nil end
function GetPosition(h)
    if h == "rally_path" then return path end
    if type(h) == "string" then return {x=0,y=0,z=0} end
    return h.pos
end
function AllCraft() return function() return nil end end
function GetPositionNear(p) return {x=p.x+40,y=p.y,z=p.z} end
function GetTerrainHeightAndNormal() return 25 end
function SetPosition(h, p) h.pos = p end
function SetVector(x,y,z) return {x=x,y=y,z=z} end
function SetVelocity() end
function Send() end
function DisplayMessage() end
package.loaded.exu = {GetLives=function() return nativeLives end, SetLives=function(n) nativeLives=n end}
package.loaded.CRCoopComms = {Create=function() return {Reset=function() end, Update=function() end} end}
local coop = dofile("Scripts/CRCoop.lua")
coop.CreatePlayer(1,"Host",1)
local function testRally(where, expected)
    now = 0
    player = {pos={x=1000,y=0,z=1000},alive=true,team=1}
    coop.Initialize({getLocalPlayerId=function() return 1 end, rallyPoints={[1]=where}})
    coop.SetMissionPhase(1)
    local service = coop.GetRespawn()
    for i=1,20 do now=i; service.Update() end
    player.alive = false; nativeLives = nativeLives - 1
    service.Update()
    player = {pos={x=0,y=50,z=0},alive=true,team=1}
    now = now + 1; service.Update()
    assert(service.lastRespawn.how == "rally")
    assert(player.pos.x == expected.x+40 and player.pos.z == expected.z,
        "object labels must resolve to a handle; genuine paths must stay paths")
end
testRally("lemnos", factory.pos)
testRally("rally_path", path)
print("CRCoop object-label and path rally placement passed")
