-- Resolve Scripts/ relative to this file so require() works without LUA_PATH.
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
package.path = toolsDir .. "/../Scripts/?.lua;" .. package.path
local Pda, Hud = require("CRCoopPda"), require("CRCoopPingHud")
local Data = require("PersistentConfigData")
local active, calls, checks = false, {}, 0
local me, host, now = 30, false, 0
local requests, onFoot, selection, markers = {}, { [30] = true }, {}, true
local bo = { name = "bo craft" }
local aimed = { "terrain", nil, { x = 1, y = 2, z = 3 } }
local players = { [20] = { name = "Ian", team = 1, ready = true }, [30] = { name = "Ann", team = 2, ready = true },
    [40] = { name = "Bo", team = 3, ready = true, handle = bo } }
local function check(v, label) assert(v, label); checks = checks + 1 end
local ping = { name = "Ian", kind = "object", position = { x = 0, y = 0, z = 100 }, expires = 10 }
local function log(text) calls[#calls + 1] = text; return true end
local comms = { IsActive = function() return active end, GetPings = function() return { [20] = ping } end,
    GetRequests = function() return requests end,
    IsOnFoot = function(id) return onFoot[id] == true end,
    CanGive = function(h) return h.mine == true end,
    Describe = function(id) return requests[id] and "NEEDS A RIDE" or onFoot[id] and "on foot" or "H90 A80" end,
    MarkersOn = function() return markers end,
    SetMarkers = function(on) markers = on; return log("markers " .. tostring(on)) end,
    Respond = function(id, value) return log("respond " .. id .. " " .. value) end,
    SendPing = function(kind) return log(kind) end,
    TargetPing = function(id) return log("target " .. id) end,
    CallForHelp = function() return log("help") end,
    CancelRescue = function() return log("cancel") end,
    Dispatch = function(h, id) return log("dispatch " .. h.name .. " " .. id) end,
    Give = function(h, id) return log("give " .. h.name .. " " .. id) end,
    Recall = function() return log("recall") end }
local coop = { GetComms = function() return comms end, IsAuthority = function() return host end,
    GetLocalPlayerId = function() return me end, GetPlayers = function() return players end,
    IsHumanTeam = function(team) return team >= 1 and team <= 4 end,
    IsSessionReady = function() return true end }
local ui = Pda.Create({ coop = coop, pages = Data.PdaPages, feedback = error,
    exu = { GetReticleHit = function() return aimed[1], aimed[2], aimed[3] end },
    time = function() return now end, selected = function() return selection end })
local state = { pdaPage = 1 }
check(#ui.PageOrder() == 8, "eight solo pages")
check(ui.CyclePage(8, 1) == 1, "solo wrap skips co-op")
active = true; ui.UpdatePage(state)
check(state.pdaPage == 9 and ui.PageNumber(9) == 1, "co-op opens first")
state.pdaPage = 3; ui.UpdatePage(state)
check(state.pdaPage == 3, "notifications do not force page")
check(ui.CyclePage(9, 1) == 10 and ui.CyclePage(10, 1) == 1 and ui.CyclePage(1, -1) == 10,
    "diagnostics is the second co-op page")
check(ui.PageNumber(10) == 2 and #ui.PageOrder() == 10, "diagnostics page number")
local function render()
    return ui.BuildText(function() return "==COOP==" end, function(lines, ...)
        for _, line in ipairs({ ... }) do lines[#lines + 1] = line end
    end)
end
local function rows(text)
    local n = 0
    -- Action rows run from the header to the first blank line.
    for line in (text:match("^[^\n]*\n(.-)\n\n") or ""):gmatch("[^\n]+") do n = n + 1 end
    return n
end
-- Guest on foot: three rows, no host rows.
local text = render()
check(text:find("> CALL RIDE (V)", 1, true) and text:find("  TARGET Ian\n", 1, true), "guest rows")
check(rows(text) == 3 and text:find("MARKERS ON", 1, true), "guest sees three rows")
check(not text:find("SEND", 1, true) and not text:find("RECALL", 1, true) and not text:find("GIVE", 1, true), "no host rows")
check(text:find("Ann*  on foot", 1, true) and text:find("Ian^  H90 A80", 1, true), "team list")
check(text:find("V help", 1, true) and text:find("Bksp do", 1, true) and text:find("J ping", 1, true), "guest footer")
ui.HandleInput(false, false, false, false, true)
check(calls[#calls] == "help", "J calls for help")
ui.HandleInput(false, true, false, false, true)
check(calls[#calls] == "target 20", "J targets the teammate's mark")
ui.HandleInput(false, true, false, false, true)
check(calls[#calls] == "markers false", "J toggles markers")
check(ui.PingAim() and calls[#calls] == "terrain", "J pings")
check(ui.HelpKey() and calls[#calls] == "help", "V calls for help")
onFoot[30] = false
check(render():find("CALL SUPPLY (V)", 1, true), "in a vehicle the call is for supplies")
requests = { [30] = { name = "Ann", kind = 2, status = "Requested" } }
check(render():find("CANCEL HELP", 1, true), "open call can be cancelled")
requests = {}
-- Giving selected units cycles through teammates.
selection = { { name = "tank", mine = true }, { name = "enemy" } }
text = render()
check(text:find("GIVE (Z) 1 > Ian <1/2>", 1, true), "give row counts only own units")
ui.selected = "give"; ui.HandleInput(false, false, false, true, false)
check(render():find("GIVE (Z) 1 > Bo <2/2>", 1, true), "Right picks the next teammate")
ui.HandleInput(false, false, false, false, true)
check(calls[#calls] == "give tank 40", "Backspace gives")
local ok, why = ui.GiveKey()
check(not ok and why == "Aim at a teammate first.", "Z needs an aimed teammate")
aimed = { "object", bo }; calls[#calls + 1] = "-"
check(ui.GiveKey() and calls[#calls] == "give tank 40", "Z gives to the aimed teammate")
aimed = { "terrain", nil, { x = 1, y = 2, z = 3 } }
-- Host: send ride, reply, give, recall, markers.
me, host, selection = 20, true, { { name = "sabre", mine = true } }
onFoot = { [40] = true }
requests = { [40] = { name = "Bo", kind = 1, status = "Requested" } }
ui.selected = nil; ui.row = 1
text = render()
check(text:find("> SEND RIDE (V) > Bo\n", 1, true) and text:find("Bo RIDE: <YES>", 1, true), "host rows")
check(text:find("RECALL ALL TO ME", 1, true) and not text:find("CALL RIDE", 1, true), "host has recall, no help call")
check(text:find("V send ride", 1, true) and not text:find("V help", 1, true), "host footer")
check(ui.HelpKey() and calls[#calls] == "dispatch sabre 40", "V with a vehicle selected sends it")
ui.HandleInput(false, true, false, false, false); ui.HandleInput(false, false, true, false, true)
check(calls[#calls] == "respond 40 2", "Left flips the reply to NO")
ui.selected = "recall"; ui.HandleInput(false, false, false, false, true)
check(calls[#calls] ~= "recall" and render():find("RECALL ALL? BKSP AGAIN", 1, true), "recall asks first")
ui.HandleInput(false, false, false, false, true)
check(calls[#calls] == "recall", "second J recalls")
ui.HandleInput(false, false, false, false, true); now = 5; ui.HandleInput(false, false, false, false, true)
check(calls[#calls] ~= "recall" or calls[#calls - 1] ~= "recall", "confirmation expires")
selection = {}
ok, why = ui.HelpKey()
check(not ok and why == "Select one of your vehicles first.", "host V needs a selected vehicle")
me, host, onFoot, requests = 30, false, { [30] = true }, {}
active = false; ui.UpdatePage(state)
state.pdaPage = 9; ui.UpdatePage(state)
check(state.pdaPage == 1, "solo clears co-op page")
state.pdaPage = 10; ui.UpdatePage(state)
check(state.pdaPage == 1, "solo clears diagnostics page")
-- Object pings use the stock objective marker; existing objectives only flash.
do
    local clock, pings, active = 0, {}, true
    local enemy, mission, unknown = { name = "enemy" }, { name = "mission" }, { name = "unknown" }
    local state = { [enemy] = { on = false, name = "Grizzly" }, [mission] = { on = true, name = "Relic" },
        [unknown] = { on = nil, name = "Scout" } }
    local log, spawned = {}, {}
    local hud = Hud.Create({
        time = function() return clock end,
        comms = function() return { IsActive = function() return active end, GetPings = function() return pings end } end,
        objective = {
            isOn = function(h) return state[h].on end,
            valid = function() return true end,
            on = function(h) state[h].on = true; log[#log + 1] = h.name .. " on" end,
            off = function(h) state[h].on = false; log[#log + 1] = h.name .. " off" end,
            name = function(h, text) state[h].name = text end,
            getName = function(h) return state[h].name end,
            spawn = function(pos)
                local h = { name = "marker", pos = pos }
                state[h] = { on = false, name = "Ping" }
                spawned[#spawned + 1] = h
                return h
            end,
            remove = function(h) state[h].removed = true end,
        },
    })
    pings = { [20] = { name = "Ann", kind = "object", handle = enemy, seq = 1, position = { x = 0, y = 0, z = 9 } },
        [30] = { name = "Bo", kind = "object", handle = mission, seq = 1, position = { x = 0, y = 0, z = 9 } },
        [40] = { name = "Cy", kind = "object", handle = unknown, seq = 1, position = { x = 0, y = 0, z = 9 } } }
    hud.Update(false)
    check(state[enemy].on and state[enemy].name == "Ann: TARGET PING", "plain unit gets a named marker")
    check(state[mission].name == "Bo: TARGET PING", "existing objective renamed while pinged")
    check(state[unknown].on == nil, "unknown objective state is left alone")
    local offs = 0
    for _ = 1, 10 do
        clock = clock + 0.21; hud.Update(false)
    end
    for _, line in ipairs(log) do if line == "mission off" then offs = offs + 1 end end
    check(offs >= 2 and state[mission].on, "existing objective flashes and ends on")
    pings = { [30] = pings[30] }
    clock = clock + 0.1; hud.Update(false)
    check(not state[enemy].on and state[enemy].name == "Grizzly", "ping end restores the plain unit")
    pings = {}
    clock = clock + 0.1; hud.Update(false)
    check(state[mission].on and state[mission].name == "Relic", "existing objective stays on, name restored")
    -- Terrain: one invisible local marker per ping, removed when it ends or is replaced.
    pings = { [20] = { name = "Ann", kind = "terrain", seq = 2, position = { x = 5, y = 0, z = 6 } } }
    clock = clock + 0.1; hud.Update(false)
    local marker = spawned[1]
    check(#spawned == 1 and state[marker].on and state[marker].name == "Ann: TERRAIN PING", "terrain ping gets a marker")
    check(marker.pos.x == 5 and marker.pos.z == 6, "marker at the ping")
    clock = clock + 0.1; hud.Update(false)
    check(#spawned == 1, "one marker per ping")
    pings[20] = { name = "Ann", kind = "terrain", seq = 3, position = { x = 9, y = 0, z = 9 } }
    clock = clock + 0.1; hud.Update(false)
    check(state[marker].removed and #spawned == 2, "a new ping replaces the old marker")
    pings = {}
    clock = clock + 0.1; hud.Update(false)
    check(state[spawned[2]].removed, "marker removed when the ping ends")
end
print("CRCoopPda/Hud: " .. checks .. " checks passed")
