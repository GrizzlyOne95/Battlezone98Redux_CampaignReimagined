-- Resolve Scripts/ relative to this file so require() works without LUA_PATH.
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
package.path = toolsDir .. "/../Scripts/?.lua;" .. package.path
local Pda, Hud = require("CRCoopPda"), require("CRCoopPingHud")
local Data = require("PersistentConfigData")
local active, calls, checks = false, {}, 0
local requests, host, onFoot = {}, false, true
local players = { [20] = { name = "Host", team = 1, ready = true }, [30] = { name = "Ann", team = 2, ready = true } }
local function check(v, label) assert(v, label); checks = checks + 1 end
local ping = { name = "Host", kind = "object", position = { x = 0, y = 0, z = 100 }, expires = 10 }
local comms = { IsActive = function() return active end, GetPings = function() return { [10] = ping } end,
    GetRequests = function() return requests end,
    Respond = function(id, value) calls[#calls + 1] = "respond " .. id .. " " .. value; return true end,
    SendPing = function(kind, h, pos) calls[#calls + 1] = kind; return true end,
    TargetPing = function(id) calls[#calls + 1] = id; return true end,
    RequestRescue = function() calls[#calls + 1] = "rescue"; return true end }
local coop = { GetComms = function() return comms end, IsAuthority = function() return host end,
    GetLocalPlayerId = function() return 20 end, GetPlayers = function() return players end,
    IsHumanTeam = function(team) return team >= 1 and team <= 4 end,
    IsSessionReady = function() return true end }
local ui = Pda.Create({ coop = coop, pages = Data.PdaPages, exu = { GetReticleHit = function() return "terrain", nil, { x = 1, y = 2, z = 3 } end }, feedback = error,
    onFoot = function() return onFoot end })
local state = { pdaPage = 1 }
check(#ui.PageOrder() == 8, "eight solo pages")
check(ui.CyclePage(8, 1) == 1, "solo wrap skips co-op")
active = true; ui.UpdatePage(state)
check(state.pdaPage == 9 and ui.PageNumber(9) == 1, "co-op opens first")
state.pdaPage = 3; ui.UpdatePage(state)
check(state.pdaPage == 3, "notifications do not force page")
check(ui.CyclePage(9, 1) == 1 and ui.CyclePage(1, -1) == 9, "co-op navigation")
ui.HandleInput(false, false, false, false, true)
check(calls[1] == "terrain", "J ping")
ui.HandleInput(false, true, false, false, true)
check(calls[2] == 10, "J targets the teammate's mark")
ui.HandleInput(false, true, false, false, true)
check(calls[3] == "rescue", "J calls for a ride")
local function render()
    return ui.BuildText(function() return "CO-OP" end, function(lines, ...)
        for _, line in ipairs({ ... }) do lines[#lines + 1] = line end
    end)
end
local text = render()
check(text:find("> CALL for a ride", 1, true), "cursor stays on the ride row")
check(text:find("TARGET Host's mark", 1, true) and not text:find("of 2", 1, true), "single mark has no cycle hint")
check(not text:find("SEND HELP", 1, true) and not text:find("Left/Right", 1, true), "guest sees no host rows")
onFoot = false; text = render()
check(not text:find("ride", 1, true) and text:find("> TARGET", 1, true), "ride row hides in a vehicle")
requests = { [30] = { name = "Ann", status = "Requested" } }; host = true; text = render()
check(text:find("SEND HELP to Ann", 1, true) and text:find("TELL Ann: no ride", 1, true), "host reply rows")
check(text:find("Ann  -  NEEDS A RIDE", 1, true) and text:find("Host (host) (you)  -  Ready", 1, true), "plain team status")
ui.HandleInput(false, true, false, false, true)
check(calls[4] == "respond 30 1", "host sends help")
requests, host, onFoot = {}, false, true
active = false; ui.UpdatePage(state)
state.pdaPage = 9; ui.UpdatePage(state)
check(state.pdaPage == 1, "solo clears co-op page")
local view = { right_x = 1, right_y = 0, right_z = 0, up_x = 0, up_y = 1, up_z = 0,
    front_x = 0, front_y = 0, front_z = 1, posit_x = 0, posit_y = 0, posit_z = 0 }
local origins = { Orig_x = 640, Orig_y = 360, Const_x = 640, Const_y = -640 }
local x, y, mark, distance = Hud.Project(ping.position, view, origins, 1280, 720)
check(x == 0.5 and y == 0.5 and mark == "+" and distance == 100, "front projection")
x, y, mark = Hud.Project({ x = 1000, y = 0, z = 10 }, view, origins, 1280, 720)
check(x <= 0.830001 and mark == ">", "edge arrow")
x, y, mark = Hud.Project({ x = 0, y = 0, z = -100 }, view, origins, 1280, 720)
check(mark == "BEHIND v", "behind marker")
check(not Hud.Project(ping.position, nil, origins, 1280, 720), "camera missing")
check(not Hud.Project({ x = 0/0, y = 0, z = 0 }, view, origins, 1280, 720), "NaN projection")
print("CRCoopPda/Hud: " .. checks .. " checks passed")
