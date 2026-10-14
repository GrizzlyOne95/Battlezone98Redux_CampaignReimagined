-- Keyboard-only co-op page for the existing PDA.
-- Only actions that work right now are listed, one short row each. Guests
-- see at most four rows; the host also gets send-ride, reply and recall rows.
-- Outside the page, J pings (or, for the host with a vehicle selected and a
-- guest on foot, sends that vehicle) and V calls for help.
-- V, because every other free letter is a stock binding (H is hop out).
local M = {}
local RECALL_CONFIRM = 3
local function name(p) return tostring(p and p.name or "Player"):gsub("[%c]", " "):sub(1, 16) end
local function ordered(records)
    local ids = {}
    for id in pairs(records) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end
local function choose(records, selected, delta)
    local ids = ordered(records)
    if #ids == 0 then return nil end
    local index = 1
    for i, id in ipairs(ids) do if id == selected then index = i; break end end
    return ids[((index - 1 + (delta or 0)) % #ids) + 1]
end
local function counter(records, selected)
    local ids = ordered(records)
    if #ids < 2 then return "" end
    for i, id in ipairs(ids) do if id == selected then return string.format(" <%d/%d>", i, #ids) end end
    return ""
end
function M.Create(d)
    local ui = { row = 1 }
    local function comms() return d.coop.GetComms() end
    local function now() return d.time and d.time() or 0 end
    function ui.IsActive()
        local c = comms()
        return c and c.IsActive() or false
    end
    function ui.PageOrder()
        local pages = ui.IsActive() and { d.pages.COOP } or {}
        for page = 1, d.pages.SETTINGS do pages[#pages + 1] = page end
        return pages
    end
    function ui.PageNumber(page)
        local pages = ui.PageOrder()
        for i, value in ipairs(pages) do if value == page then return i, #pages end end
        return 1, #pages
    end
    function ui.CyclePage(page, delta)
        local pages = ui.PageOrder()
        local index = ui.PageNumber(page)
        return pages[((index - 1 + delta) % #pages) + 1]
    end
    function ui.Reset()
        ui.row, ui.selected, ui.pingId, ui.giveTo, ui.sendTo, ui.recallAt = 1, nil, nil, nil, nil, nil
        ui.replies, ui.wasActive = {}, false
    end
    function ui.UpdatePage(state)
        local active = ui.IsActive()
        if active and not ui.wasActive then state.pdaPage = d.pages.COOP end
        if not active and state.pdaPage == d.pages.COOP then state.pdaPage = d.pages.VEHICLE end
        ui.wasActive = active
    end
    local function selected()
        local ok, list = pcall(d.selected or function() return {} end)
        return ok and type(list) == "table" and list or {}
    end
    local function givable(c)
        local units = {}
        for _, h in ipairs(selected()) do if c.CanGive(h) then units[#units + 1] = h end end
        return units
    end
    -- Other players who can receive a unit, and guests on foot.
    local function teammates()
        local out, me, players = {}, d.coop.GetLocalPlayerId(), d.coop.GetPlayers()
        for id, p in pairs(players) do
            if id ~= me and d.coop.IsHumanTeam(p.team) and not p.lateJoin then out[id] = p end
        end
        return out
    end
    local function stranded(c)
        local out = {}
        for id, p in pairs(teammates()) do if c.IsOnFoot(id) then out[id] = p end end
        return out
    end
    -- Whoever asked for a ride first; otherwise the first guest on foot.
    local function bestStranded(c)
        local requests, best = c.GetRequests(), nil
        for _, id in ipairs(ordered(stranded(c))) do
            if requests[id] and requests[id].kind == 1 then return id end
            best = best or id
        end
        return best
    end
    function ui.PingAim()
        if not ui.IsActive() then return false end
        if not d.exu or not d.exu.GetReticleHit then return false, "Marking needs a newer EXU." end
        local ok, kind, h, pos = pcall(d.exu.GetReticleHit)
        if not ok or not kind then return false, "Aim at something first." end
        return comms().SendPing(kind, h, pos)
    end
    -- J outside the page: the host with a vehicle selected and a guest on foot
    -- sends that vehicle; otherwise J marks whatever the reticle is on.
    function ui.QuickAction()
        if not ui.IsActive() then return false end
        local c = comms()
        if d.coop.IsAuthority() then
            local units, target = givable(c), bestStranded(c)
            if units[1] and target then return c.Dispatch(units[1], target) end
        end
        return ui.PingAim()
    end
    function ui.CallHelp()
        if not ui.IsActive() then return false end
        return comms().CallForHelp()
    end
    -- Rows that can be used right now. Keys keep the cursor on the same action
    -- when rows appear or disappear underneath it.
    function ui.Actions()
        local c, me, host = comms(), d.coop.GetLocalPlayerId(), d.coop.IsAuthority()
        local requests, list = c.GetRequests(), {}
        local function add(action) list[#list + 1] = action end
        local units = givable(c)
        if host then
            local strandedNow = stranded(c)
            ui.sendTo = strandedNow[ui.sendTo] and ui.sendTo or bestStranded(c)
            if units[1] and ui.sendTo then
                add({ key = "send", text = "SEND RIDE > " .. name(strandedNow[ui.sendTo]) .. counter(strandedNow, ui.sendTo),
                    run = function() return c.Dispatch(units[1], ui.sendTo) end,
                    cycle = function(delta) ui.sendTo = choose(strandedNow, ui.sendTo, delta) end })
            end
            for _, id in ipairs(ordered(requests)) do
                local request = requests[id]
                if id ~= me and request.status == "Requested" then
                    local yes = ui.replies[id] ~= 2
                    add({ key = "reply" .. id,
                        text = name(request) .. (request.kind == 2 and " SUPPLY: " or " RIDE: ") .. (yes and "<YES>" or "<NO>"),
                        run = function() return c.Respond(id, ui.replies[id] == 2 and 2 or 1) end,
                        cycle = function() ui.replies[id] = ui.replies[id] == 2 and 1 or 2 end })
                end
            end
        else
            local text = requests[me] and "CANCEL HELP" or c.IsOnFoot(me) and "CALL RIDE (V)" or "CALL SUPPLY (V)"
            add({ key = "help", text = text,
                run = function() if requests[me] then return c.CancelRescue() end return c.CallForHelp() end })
        end
        local marks = {}
        for id, ping in pairs(c.GetPings()) do if id ~= me and ping.kind == "object" then marks[id] = ping end end
        ui.pingId = choose(marks, ui.pingId)
        if ui.pingId then
            add({ key = "target", text = "TARGET " .. name(marks[ui.pingId]) .. counter(marks, ui.pingId),
                run = function() return c.TargetPing(ui.pingId) end,
                cycle = function(delta) ui.pingId = choose(marks, ui.pingId, delta) end })
        end
        local mates = teammates()
        ui.giveTo = choose(mates, ui.giveTo)
        if units[1] and ui.giveTo then
            add({ key = "give", text = "GIVE " .. #units .. " > " .. name(mates[ui.giveTo]) .. counter(mates, ui.giveTo),
                run = function()
                    local sent, reason = 0, nil
                    for _, h in ipairs(units) do
                        local ok, why = c.Give(h, ui.giveTo)
                        if ok then sent = sent + 1 else reason = why end
                    end
                    if sent == 0 then return false, reason end
                    return true
                end,
                cycle = function(delta) ui.giveTo = choose(mates, ui.giveTo, delta) end })
        end
        if host then
            local armed = ui.recallAt and now() < ui.recallAt
            add({ key = "recall", text = armed and "RECALL ALL? J AGAIN" or "RECALL ALL TO ME",
                run = function()
                    if not (ui.recallAt and now() < ui.recallAt) then
                        ui.recallAt = now() + RECALL_CONFIRM
                        return true
                    end
                    ui.recallAt = nil
                    return c.Recall()
                end })
        end
        add({ key = "markers", text = "MARKERS " .. (c.MarkersOn() and "ON" or "OFF"),
            run = function() c.SetMarkers(not c.MarkersOn()); return true end })
        return list
    end
    local function current(list)
        for i, action in ipairs(list) do
            if action.key == ui.selected then ui.row = i; return i end
        end
        ui.row = math.max(1, math.min(ui.row or 1, #list))
        ui.selected = list[ui.row].key
        return ui.row
    end
    function ui.HandleInput(up, down, left, right, action)
        if not ui.IsActive() then return end
        local list = ui.Actions()
        local i = current(list)
        if up or down then
            i = ((i - 1 + (up and -1 or 1)) % #list) + 1
            ui.row, ui.selected = i, list[i].key
        end
        local chosen = list[i]
        if (left or right) and chosen.cycle then chosen.cycle(left and -1 or 1) end
        if action then
            local ok, reason = chosen.run()
            if ok == false and reason then d.feedback(reason) end
        end
    end
    function ui.BuildText(header, footer)
        local lines = { header(d.pages.COOP) }
        if not ui.IsActive() then return table.concat(lines, "\n") end
        local c, me, host = comms(), d.coop.GetLocalPlayerId(), d.coop.IsAuthority()
        if not d.coop.IsSessionReady() then lines[#lines + 1] = "(loading...)" end
        local list = ui.Actions()
        local i = current(list)
        for index, action in ipairs(list) do
            lines[#lines + 1] = (index == i and "> " or "  ") .. action.text
        end
        lines[#lines + 1] = ""
        local players = d.coop.GetPlayers()
        for _, id in ipairs(ordered(players)) do
            local p = players[id]
            if d.coop.IsHumanTeam(p.team) then
                local tag = id == me and "*" or p.team == 1 and "^" or ""
                local word = p.lateJoin and "late" or c.Describe(id)
                lines[#lines + 1] = "  " .. name(p) .. tag .. (word ~= "" and "  " .. word or "")
            end
        end
        footer(lines, "J do   Arrows pick" .. (host and "" or "   V help"), "[ ] page   X close", "* you   ^ host")
        return table.concat(lines, "\n")
    end
    ui.Reset()
    return ui
end
return M
