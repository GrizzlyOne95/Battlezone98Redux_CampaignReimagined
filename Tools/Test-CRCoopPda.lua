local Pda, Hud = require("CRCoopPda"), require("CRCoopPingHud")
local Data = require("PersistentConfigData")
local active, calls, checks = false, {}, 0
local function check(v, label) assert(v, label); checks = checks + 1 end
local ping = { name = "Host", kind = "object", position = { x = 0, y = 0, z = 100 }, expires = 10 }
local comms = { IsActive = function() return active end, GetPings = function() return { [10] = ping } end,
    GetRequests = function() return {} end,
    SendPing = function(kind, h, pos) calls[#calls + 1] = kind; return true end,
    TargetPing = function(id) calls[#calls + 1] = id; return true end,
    RequestRescue = function() calls[#calls + 1] = "rescue"; return true end }
local coop = { GetComms = function() return comms end, IsAuthority = function() return false end,
    GetLocalPlayerId = function() return 20 end, GetPlayers = function() return {} end,
    IsSessionReady = function() return true end }
local ui = Pda.Create({ coop = coop, pages = Data.PdaPages, exu = { GetReticleHit = function() return "terrain", nil, { x = 1, y = 2, z = 3 } end }, feedback = error })
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
check(calls[2] == "rescue", "J rescue")
ui.row = 4; ui.HandleInput(false, false, false, false, true)
check(calls[3] == 10, "explicit selected object target")
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
check(mark == "BACK v", "behind marker")
check(not Hud.Project(ping.position, nil, origins, 1280, 720), "camera missing")
check(not Hud.Project({ x = 0/0, y = 0, z = 0 }, view, origins, 1280, 720), "NaN projection")
print("CRCoopPda/Hud: " .. checks .. " checks passed")
