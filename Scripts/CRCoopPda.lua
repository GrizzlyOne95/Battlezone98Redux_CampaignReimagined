-- Keyboard-only co-op page for the existing PDA.
-- The page lists only the actions that work right now, one per row, in plain
-- words. Guests get at most three rows; the host also gets reply rows for
-- each pending ride request.
local M = {}
local function name(p) return tostring(p and p.name or "Player"):gsub("[%c]", " "):sub(1, 20) end
-- Request statuses are protocol values (pinned by Test-CRCoopComms); only the
-- displayed wording lives here.
local RIDE_STATUS = {
    Requested = "NEEDS A RIDE",
    ["Help on the way"] = "Ride coming",
    ["No craft available"] = "No ride available",
}
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
-- Teammates' target marks; pings are keyed by sender, so skip our own.
local function objectMarks(pings, me)
    local marks = {}
    for id, ping in pairs(pings) do if id ~= me and ping.kind == "object" then marks[id] = ping end end
    return marks
end
function M.Create(d)
    local ui = { row = 1 }
    local function comms() return d.coop.GetComms() end
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
        ui.row, ui.selected, ui.pingId, ui.wasActive = 1, nil, nil, false
    end
    function ui.UpdatePage(state)
        local active = ui.IsActive()
        if active and not ui.wasActive then state.pdaPage = d.pages.COOP end
        if not active and state.pdaPage == d.pages.COOP then state.pdaPage = d.pages.VEHICLE end
        ui.wasActive = active
    end
    function ui.PingAim()
        if not ui.IsActive() then return false end
        if not d.exu or not d.exu.GetReticleHit then return false, "Marking needs a newer EXU." end
        local ok, kind, h, pos = pcall(d.exu.GetReticleHit)
        if not ok or not kind then return false, "Aim at something first." end
        return comms().SendPing(kind, h, pos)
    end
    -- Rows that can be used right now. Keys keep the cursor on the same action
    -- when rows appear or disappear underneath it.
    function ui.Actions()
        local c, me = comms(), d.coop.GetLocalPlayerId()
        local list = { { key = "mark", text = "MARK what I'm aiming at", run = ui.PingAim } }
        local marks = objectMarks(c.GetPings(), me)
        ui.pingId = choose(marks, ui.pingId)
        if ui.pingId then
            local ids, at = ordered(marks), 1
            for i, id in ipairs(ids) do if id == ui.pingId then at = i end end
            list[#list + 1] = { key = "target",
                text = "TARGET " .. name(marks[ui.pingId]) .. "'s mark" ..
                    (#ids > 1 and string.format("   < %d of %d >", at, #ids) or ""),
                run = function() return c.TargetPing(ui.pingId) end,
                cycle = function(delta) ui.pingId = choose(marks, ui.pingId, delta) end }
        end
        local requests = c.GetRequests()
        if requests[me] then
            list[#list + 1] = { key = "ride", text = "CANCEL my ride request", run = c.CancelRescue }
        elseif not d.onFoot or d.onFoot() then
            list[#list + 1] = { key = "ride", text = "CALL for a ride", run = c.RequestRescue }
        end
        if d.coop.IsAuthority() then
            for _, id in ipairs(ordered(requests)) do
                local who = name(requests[id])
                if id ~= me then
                    list[#list + 1] = { key = "yes" .. id, text = "SEND HELP to " .. who,
                        run = function() return c.Respond(id, 1) end }
                    list[#list + 1] = { key = "no" .. id, text = "TELL " .. who .. ": no ride right now",
                        run = function() return c.Respond(id, 2) end }
                end
            end
        end
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
        local c, me = comms(), d.coop.GetLocalPlayerId()
        if not d.coop.IsSessionReady() then
            lines[#lines + 1] = "Waiting for everyone to load..."
            lines[#lines + 1] = ""
        end
        local list = ui.Actions()
        local i = current(list)
        for index, action in ipairs(list) do
            lines[#lines + 1] = (index == i and "> " or "   ") .. action.text
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "TEAM"
        local players, requests = d.coop.GetPlayers(), c.GetRequests()
        for _, id in ipairs(ordered(players)) do
            local p = players[id]
            if d.coop.IsHumanTeam(p.team) then
                local label = name(p) .. (p.team == 1 and " (host)" or "") .. (id == me and " (you)" or "")
                local request = requests[id]
                local status = request and (RIDE_STATUS[request.status] or request.status)
                    or p.lateJoin and "Joined late"
                    or (p.team == 1 or p.ready) and "Ready" or "Loading..."
                lines[#lines + 1] = "   " .. label .. "  -  " .. status
            end
        end
        footer(lines, "--------------------------------",
            list[i].cycle and "J = do it    Up/Down = choose    Left/Right = next mark"
                or "J = do it    Up/Down = choose",
            "[ / ] = other pages    X = close")
        return table.concat(lines, "\n")
    end
    ui.Reset()
    return ui
end
return M
