-- Execute the real input-polling block without bootstrapping engine resources.
local f=assert(io.open("Scripts/PersistentConfig.lua","r"));local source=f:read("*a");f:close()
local block=assert(source:match("(local NetworkPolledGameKeys = .-)\n%-%- Reusable update logic"))
local keys,queued,network={},{},true
local config={Settings={WeaponStatsHud=false},R={QueueGameKey=function(k)queued[#queued+1]=k end}}
local env=setmetatable({PersistentConfig=config,InputState={},exu={GetGameKey=function(k)return keys[k]==true end},
 package={loaded={CRCoop={IsNetworkGame=function()return network end}}}},{__index=_G})
local chunk=assert(loadstring(block));setfenv(chunk,env);chunk()
local checks=0
local function check(v,label)assert(v,label);checks=checks+1 end
local function release()keys={};config._PollNetworkGameKeys(false);queued={} end
for _,key in ipairs({"J","V","Z"})do
 release();keys[key]=true;config._PollNetworkGameKeys(false)
 check(#queued==1 and queued[1]==key,key.." works with closed PDA")
 config._PollNetworkGameKeys(false);check(#queued==1,key.." fires once per press")
end
for _,key in ipairs({"ENTER","UARROW","LBRACKET"})do
 release();keys[key]=true;config._PollNetworkGameKeys(false)
 check(#queued==0,key.." does not queue navigation while closed")
 config.Settings.WeaponStatsHud=true;config._PollNetworkGameKeys(false)
 check(#queued==0,key.." held while opening does not replay")
 release();keys[key]=true;config._PollNetworkGameKeys(false)
 check(#queued==1,key.." works on a fresh press while open")
 config.Settings.WeaponStatsHud=false
end
for _,key in ipairs({"J","V","Z","ENTER"})do
 release();keys[key]=true;config._PollNetworkGameKeys(true)
 check(#queued==0,key.." suppressed in chat")
 config._PollNetworkGameKeys(false);check(#queued==0,key.." held leaving chat does not replay")
end
release();network=false;keys.V=true;config._PollNetworkGameKeys(false)
check(#queued==0,"offline keys remain owned by GameKey")
-- Enter chat: unbound online every frame, restored offline and at mission end.
local chatCalls={}
env.exu.SetChatOnEnter=function(on)chatCalls[#chatCalls+1]=on;return true end
config._UpdateEnterChat(false);check(#chatCalls==0,"offline never touches Enter chat")
network=true;config._UpdateEnterChat(false);config._UpdateEnterChat(false)
check(#chatCalls==2 and chatCalls[2]==false,"online unbinds Enter chat every frame")
config._UpdateEnterChat(true);check(chatCalls[3]==true,"mission end restores Enter chat")
config._UpdateEnterChat(true);check(#chatCalls==3,"restore happens once")
env.exu.SetChatOnEnter=function()error("unsupported")end
config._UpdateEnterChat(false);check(env.InputState.enterChatOff==nil,"failed unbind is not remembered")
env.exu.SetChatOnEnter=nil;config._UpdateEnterChat(false);check(true,"old EXU without SetChatOnEnter is ignored")
print("CoopNetworkInput: "..checks.." checks passed")
