-- Local-only coordinate labels. Never touch mission objective flags or names.
local M = {}
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < 1e12 end
function M.Project(pos, view, origins, width, height)
    if not pos or not view or not origins or not finite(width) or not finite(height) or width <= 0 or height <= 0 then return end
    for _, key in ipairs({ "right_x", "right_y", "right_z", "up_x", "up_y", "up_z",
        "front_x", "front_y", "front_z", "posit_x", "posit_y", "posit_z" }) do
        if not finite(view[key]) then return end
    end
    for _, key in ipairs({ "Orig_x", "Orig_y", "Const_x", "Const_y" }) do
        if not finite(origins[key]) then return end
    end
    if not finite(pos.x) or not finite(pos.y) or not finite(pos.z) or origins.Const_x == 0 or origins.Const_y == 0 then return end
    -- BZR's row-vector world-to-camera matrix; use its projection constants,
    -- including the signed Y constant, rather than desktop pixel dimensions.
    local x = pos.x * view.right_x + pos.y * view.up_x + pos.z * view.front_x + view.posit_x
    local y = pos.x * view.right_y + pos.y * view.up_y + pos.z * view.front_y + view.posit_y
    local z = pos.x * view.right_z + pos.y * view.up_z + pos.z * view.front_z + view.posit_z
    local distance = math.sqrt(x * x + y * y + z * z)
    local px, py = origins.Orig_x / width, origins.Orig_y / height
    if z > 0.1 then
        px = px + x / z * origins.Const_x / width
        py = py + y / z * origins.Const_y / height
    end
    if z > 0.1 and px >= 0.07 and px <= 0.83 and py >= 0.08 and py <= 0.86 then
        return px, py, "+", distance
    end
    local dx, dy = x * origins.Const_x / width, y * origins.Const_y / height
    if math.abs(dx) + math.abs(dy) < 0.001 then dy = 1 end
    local scale = math.max(math.abs(dx) / 0.38, math.abs(dy) / 0.38)
    px, py = 0.45 + dx / scale, 0.47 + dy / scale
    local arrow = math.abs(dx) > math.abs(dy) and (dx < 0 and "<" or ">") or (dy < 0 and "^" or "v")
    return px, py, z <= 0.1 and "BACK " .. arrow or arrow, distance
end
function M.Create(d)
    local hud, slots = {}, {}
    local nextUpdate = 0
    local colors = { { 1, 0.85, 0.25 }, { 0.25, 0.85, 1 }, { 0.45, 1, 0.35 }, { 1, 0.45, 0.85 } }
    local function call(method, ...)
        local fn = d.exu and d.exu[method]
        if not fn then return false end
        local ok, result = pcall(fn, ...)
        if not ok then return false end
        return result
    end
    local function visible(slot, show)
        if slot.visible == show then return end
        call(show and "ShowOverlay" or "HideOverlay", slot.overlay)
        slot.visible = show
    end
    function hud.Destroy()
        for _, slot in pairs(slots) do
            call("HideOverlay", slot.overlay)
            call("RemoveOverlay2D", slot.overlay, slot.root)
            call("RemoveOverlayElementChild", slot.root, slot.text)
            call("DestroyOverlayElement", slot.text)
            call("DestroyOverlayElement", slot.root)
            call("DestroyOverlay", slot.overlay)
        end
        slots, nextUpdate = {}, 0
    end
    local function create(index)
        local prefix = "cr_coop_ping_" .. index
        local slot = { overlay = prefix, root = prefix .. "_root", text = prefix .. "_text" }
        slots[index] = slot
        if call("CreateOverlay", slot.overlay) == false or call("CreateOverlayElement", "Panel", slot.root) == false or
            call("CreateOverlayElement", "TextArea", slot.text) == false then return end
        call("AddOverlay2D", slot.overlay, slot.root)
        call("AddOverlayElementChild", slot.root, slot.text)
        call("SetOverlayZOrder", slot.overlay, 630)
        call("SetOverlayMetricsMode", slot.root, 0)
        call("SetOverlayDimensions", slot.root, 0.17, 0.065)
        call("SetOverlayMetricsMode", slot.text, 0)
        call("SetOverlayDimensions", slot.text, 0.17, 0.065)
        call("SetOverlayTextFont", slot.text, d.font())
        call("SetOverlayTextCharHeight", slot.text, 0.019)
        local color = colors[index]
        call("SetOverlayColor", slot.text, color[1], color[2], color[3], 1)
        slot.ready = true
        return slot
    end
    function hud.Update(suppressed)
        local c = d.comms()
        if not c or not c.IsActive() then if next(slots) then hud.Destroy() end; return end
        if suppressed then
            for _, slot in pairs(slots) do visible(slot, false) end
            nextUpdate = 0
            return
        end
        local time = d.time()
        if time < nextUpdate then return end
        nextUpdate = time + 0.05
        local view, origins = call("GetCameraViewMatrix"), call("GetCameraOrigins")
        local width, height = d.resolution()
        local ids = {}
        for id in pairs(c.GetPings()) do ids[#ids + 1] = id end
        table.sort(ids)
        for index = 1, 4 do
            local ping = c.GetPings()[ids[index]]
            local slot = slots[index]
            local x, y, arrow, distance = M.Project(ping and ping.position, view, origins, width, height)
            if ping and x then
                slot = slot or create(index)
                if slot and slot.ready then
                    call("SetOverlayPosition", slot.root, x, y)
                    call("SetOverlayCaption", slot.text, string.format("%s %s  %dm\n%s  %ds", arrow,
                        ping.name:sub(1, 16), distance, ping.kind:upper(), math.max(0, math.ceil(ping.expires - time))))
                    visible(slot, true)
                end
            elseif slot then visible(slot, false) end
        end
    end
    return hud
end
return M
