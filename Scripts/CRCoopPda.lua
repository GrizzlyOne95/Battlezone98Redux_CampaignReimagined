-- Keyboard-only co-op page for the existing PDA.
local M = {}
local function name(p) return tostring(p and p.name or "Player"):gsub("[%c]", " "):sub(1, 20) end
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
function M.Create(d)
    local ui = { row = 1, response = 1 }
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
        ui.row, ui.response, ui.pingId, ui.requestId, ui.wasActive = 1, 1, nil, nil, false
    end
    function ui.UpdatePage(state)
        local active = ui.IsActive()
        if active and not ui.wasActive then state.pdaPage = d.pages.COOP end
        if not active and state.pdaPage == d.pages.COOP then state.pdaPage = d.pages.VEHICLE end
        ui.wasActive = active
    end
    function ui.PingAim()
        if not ui.IsActive() then return false end
        if not d.exu or not d.exu.GetReticleHit then return false, "This EXU build needs GetReticleHit." end
        local ok, kind, h, pos = pcall(d.exu.GetReticleHit)
        if not ok or not kind then return false, "Aim at an object or nearby ground." end
        return comms().SendPing(kind, h, pos)
    end
    function ui.HandleInput(up, down, left, right, action)
        if not ui.IsActive() then return end
        local c, host = comms(), d.coop.IsAuthority()
        local count = host and 6 or 4
        ui.row = math.min(ui.row, count)
        if up or down then ui.row = ((ui.row - 1 + (up and -1 or 1)) % count) + 1 end
        ui.pingId = choose(c.GetPings(), ui.pingId)
        ui.requestId = choose(c.GetRequests(), ui.requestId)
        local delta = left and -1 or right and 1 or 0
        if ui.row == 3 and (delta ~= 0 or action) then
            ui.pingId = choose(c.GetPings(), ui.pingId, delta ~= 0 and delta or 1)
        elseif ui.row == 5 and (delta ~= 0 or action) then
            ui.requestId = choose(c.GetRequests(), ui.requestId, delta ~= 0 and delta or 1)
        elseif ui.row == 6 and delta ~= 0 then ui.response = ui.response == 1 and 2 or 1
        elseif action then
            local ok, reason
            if ui.row == 1 then ok, reason = ui.PingAim()
            elseif ui.row == 2 then
                if c.GetRequests()[d.coop.GetLocalPlayerId()] then ok, reason = c.CancelRescue()
                else ok, reason = c.RequestRescue() end
            elseif ui.row == 4 then ok, reason = c.TargetPing(ui.pingId)
            elseif ui.row == 6 then ok, reason = c.Respond(ui.requestId, ui.response) end
            if ok == false and reason then d.feedback(reason) end
        end
    end
    function ui.BuildText(header, footer)
        local lines = { header(d.pages.COOP) }
        if not ui.IsActive() then return table.concat(lines, "\n") end
        local c, host = comms(), d.coop.IsAuthority()
        ui.pingId = choose(c.GetPings(), ui.pingId)
        ui.requestId = choose(c.GetRequests(), ui.requestId)
        local ping, request = c.GetPings()[ui.pingId], c.GetRequests()[ui.requestId]
        local own = c.GetRequests()[d.coop.GetLocalPlayerId()]
        local function row(index, text) lines[#lines + 1] = (ui.row == index and "> " or "  ") .. text end
        lines[#lines + 1] = d.coop.IsSessionReady() and "TEAM COMMS" or "TEAM COMMS  |  Synchronizing..."
        row(1, "Ping aimed object / ground")
        row(2, own and "Cancel rescue  |  " .. own.status or "Rescue me  |  Pilot only")
        row(3, "Ping: " .. (ping and name(ping) .. " (" .. ping.kind .. ")" or "NONE"))
        row(4, "Target selected object ping")
        if host then
            row(5, "Rescue: " .. (request and name(request) or "NONE"))
            row(6, "Reply: " .. (ui.response == 1 and "Coming" or "No craft available"))
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "TEAM / RESCUE STATUS"
        local players = d.coop.GetPlayers()
        for _, id in ipairs(ordered(players)) do
            local p = players[id]
            if d.coop.IsHumanTeam(p.team) then
                local status = c.GetRequests()[id]
                lines[#lines + 1] = string.format("T%d %s  |  %s", p.team, name(p),
                    status and status.status or p.lateJoin and "Late join" or p.team == 1 and "Host" or p.ready and "Ready" or "Syncing")
            end
        end
        footer(lines, "--------------------------------", "J Action  |  Arrows Select / Change",
            "[ / ] Page  |  X Close  |  J Quick ping")
        return table.concat(lines, "\n")
    end
    ui.Reset()
    return ui
end
return M
