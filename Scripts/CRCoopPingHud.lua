-- Co-op pings as stock objective markers, local to each player's machine.
-- Terrain ping: an invisible local-only marker object (ODF crping) with the
-- marker on, named "<who>: TERRAIN PING", removed when the ping ends or is
-- replaced. Object ping: the unit is renamed "<who>: TARGET PING" until the
-- ping ends, then gets its old name back. If it was not an objective it gets
-- the marker and loses it again; if it already was (a mission objective, a
-- teammate marker) it flashes and is never switched off. Without
-- exu.IsObjectiveOn that state is unknown, so the unit is left alone. A ping
-- on your own craft is not marked: you cannot see a marker on yourself, and
-- the name would replace yours. Its chat line says you were marked.
local M = {}
local FLASH_TIME, FLASH_STEP = 1.2, 0.2
function M.Create(d)
    local hud, marks = {}, {}
    local function objective(name, ...)
        local fn = d.objective and d.objective[name]
        if not fn then return nil end
        local ok, result = pcall(fn, ...)
        if ok then return result end
    end
    local function unmark(id)
        local mark = marks[id]
        marks[id] = nil
        if mark and mark.spawned then
            if objective("valid", mark.handle) then objective("remove", mark.handle) end
        elseif mark and mark.renamed and objective("valid", mark.handle) then
            if mark.ours then objective("off", mark.handle) end
            objective("name", mark.handle, mark.oldName)
        end
    end
    function hud.Destroy()
        for id in pairs(marks) do unmark(id) end
    end
    function hud.Update()
        local c = d.comms()
        if not c or not c.IsActive() then
            if next(marks) then hud.Destroy() end
            return
        end
        local pings, time = c.GetPings(), d.time()
        local own = d.self and d.self()
        for id, mark in pairs(marks) do
            local ping = pings[id]
            if not ping or ping.seq ~= mark.seq or (not mark.spawned and ping.handle ~= mark.handle) then
                unmark(id)
            end
        end
        for id, ping in pairs(pings) do
            if marks[id] then
                -- already handled
            elseif ping.kind == "terrain" then
                local h = objective("spawn", ping.position)
                marks[id] = { handle = h, seq = ping.seq, spawned = h ~= nil }
                if h ~= nil then
                    objective("name", h, ping.name:sub(1, 16) .. ": TERRAIN PING")
                    objective("on", h)
                end
            elseif ping.kind == "object" and ping.handle and ping.handle == own then
                marks[id] = { handle = ping.handle, seq = ping.seq }
            elseif ping.kind == "object" and ping.handle then
                local on = objective("isOn", ping.handle)
                local mark = { handle = ping.handle, seq = ping.seq }
                marks[id] = mark
                if on ~= nil then
                    mark.renamed, mark.ours = true, on == false
                    mark.oldName = objective("getName", ping.handle)
                    objective("name", ping.handle, ping.name:sub(1, 16) .. ": TARGET PING")
                    if on then
                        mark.flashUntil, mark.nextFlash, mark.lit = time + FLASH_TIME, time, true
                    else
                        objective("on", ping.handle)
                    end
                end
            end
        end
        for _, mark in pairs(marks) do
            if mark.flashUntil and objective("valid", mark.handle) then
                if time >= mark.flashUntil then
                    objective("on", mark.handle)
                    mark.flashUntil = nil
                elseif time >= mark.nextFlash then
                    mark.lit = not mark.lit
                    mark.nextFlash = time + FLASH_STEP
                    objective(mark.lit and "on" or "off", mark.handle)
                end
            end
        end
    end
    return hud
end
return M
