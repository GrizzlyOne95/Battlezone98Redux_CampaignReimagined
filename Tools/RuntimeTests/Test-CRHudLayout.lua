-- CRHudLayout (Scripts/CRHudLayout.lua) against a fake exu: refresh throttling, generations, keep-out avoidance,
-- deterministic stacking, clamping, missing/failing getters, and the debug overlay switch.
package.path = "Scripts/?.lua;" .. package.path
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function fresh()
    package.loaded.CRHudLayout = nil
    return require("CRHudLayout")
end

local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- fake exu; counts calls and records overlay creation
local function makeExu(o)
    o = o or {}
    local x = { res = { 1920, 1080 }, scale = 1, menu = { 8, 10, 201, 400 }, calls = {}, created = 0 }
    local function counted(name, fn)
        x[name] = function(...)
            x.calls[name] = (x.calls[name] or 0) + 1
            return fn(...)
        end
    end
    counted("GetGameResolution", function()
        if x.resError then error("boom") end
        return x.res[1], x.res[2]
    end)
    counted("GetUIScaling", function() return x.scale end)
    counted("GetCommandMenuRect", function()
        if x.menuError then error("boom") end
        if x.menu then return x.menu[1], x.menu[2], x.menu[3], x.menu[4] end
    end)
    counted("GetScrapPilotHudTopLeft", function() return 250, 12 end)
    x.OVERLAY_METRICS = { PIXELS = 1 }
    for _, n in ipairs({ "CreateOverlay", "CreateOverlayElement" }) do
        x[n] = function() x.created = x.created + 1; return true end
    end
    for _, n in ipairs({ "AddOverlay2D", "SetOverlayZOrder", "SetOverlayMetricsMode", "AddOverlayElementChild",
        "SetOverlayTextFont", "SetOverlayMaterial", "SetOverlayPosition", "SetOverlayDimensions",
        "SetOverlayTextCharHeight", "SetOverlayTextColor", "SetOverlayCaption", "ShowOverlayElement", "ShowOverlay",
        "HideOverlay", "RemoveOverlay2D", "RemoveOverlayElementChild", "DestroyOverlayElement", "DestroyOverlay" }) do
        x[n] = function() return true end
    end
    for k, v in pairs(o) do x[k] = v end
    return x
end

-- 1. First refresh builds; no rebuild inside a second; a poll after a second does not bump when nothing changed.
do
    local L, exu = fresh(), makeExu()
    check(L.GetGeneration() == 0, "generation starts at 0")
    L.Refresh(0, exu)
    local g1 = L.GetGeneration()
    check(g1 > 0, "first refresh builds")
    local w, h = L.GetResolution()
    check(w == 1920 and h == 1080, "resolution cached")
    check(L.GetKeepOut("command_menu"), "command menu keep-out exists")
    exu.res = { 1280, 720 }
    L.Refresh(0.5, exu)
    check(L.GetGeneration() == g1 and exu.calls.GetGameResolution == 1, "no re-poll within 1 s")
    L.Refresh(1.0, exu)
    check(exu.calls.GetGameResolution == 2, "re-poll after 1 s")
    local w2, h2 = L.GetResolution()
    check(w2 == 1280 and h2 == 720 and L.GetGeneration() > g1, "resolution change bumps the generation")
    local g2 = L.GetGeneration()
    L.Refresh(2.5, exu)
    check(L.GetGeneration() == g2, "an unchanged poll does not bump")
    exu.menu = { 8, 10, 201, 500 }
    L.Refresh(4, exu)
    check(L.GetGeneration() > g2, "a changed live rect bumps the generation")
    -- time going backwards (new mission clock) re-polls
    local calls = exu.calls.GetGameResolution
    L.Refresh(0, exu)
    check(exu.calls.GetGameResolution == calls + 1, "clock reset re-polls")
end

-- 2. Reservations avoid keep-outs and each other, at several resolutions.
local docks = { "left_mid", "right_mid", "top_center", "top_right", "bottom_center" }
local function fill(L)
    local n = 0
    for _, d in ipairs(docks) do
        for k = 1, 2 do
            n = n + 1
            L.Reserve("r" .. n, d, 180 + 10 * k, 24 + 4 * k, k % 2)
        end
    end
    return n
end
for _, res in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 2560, 1440 }, { 3840, 2160 } }) do
    local L, exu = fresh(), makeExu({ res = res, scale = res[1] >= 2560 and 2 or 1 })
    L.Refresh(0, exu)
    local n = fill(L)
    local w, h = L.GetResolution()
    local ids = { "command_menu", "scrap_pilot", "hull_ammo", "radar", "weapon_plate", "messages", "timer", "target_info" }
    for i = 1, n do
        local x, y, rw, rh = L.GetReservation("r" .. i)
        check(x >= 0 and y >= 0 and x + rw <= w and y + rh <= h, "r" .. i .. " inside the screen at " .. res[1])
        for _, id in ipairs(ids) do
            local kx, ky, kw, kh = L.GetKeepOut(id)
            check(not overlap(x, y, rw, rh, kx, ky, kw, kh), "r" .. i .. " clear of " .. id .. " at " .. res[1])
        end
        for j = i + 1, n do
            local x2, y2, w2, h2 = L.GetReservation("r" .. j)
            check(not overlap(x, y, rw, rh, x2, y2, w2, h2), "r" .. i .. " and r" .. j .. " do not overlap at " .. res[1])
        end
    end
end

-- 3. Deterministic regardless of insertion order; stable and allocation-free when unchanged.
do
    local specs = { { "a", "top_center", 200, 30, 0 }, { "b", "top_center", 120, 20, 0 }, { "c", "top_center", 150, 28, -1 },
        { "d", "left_mid", 90, 40, 2 }, { "e", "left_mid", 90, 40, 2 } }
    local function run(order)
        local L, exu = fresh(), makeExu()
        L.Refresh(0, exu)
        for _, i in ipairs(order) do L.Reserve(unpack(specs[i])) end
        local out = {}
        for _, s in ipairs(specs) do
            local x, y = L.GetReservation(s[1])
            out[s[1]] = x .. "," .. y
        end
        return out, L
    end
    local a = run({ 1, 2, 3, 4, 5 })
    local b = run({ 5, 4, 3, 2, 1 })
    local c, L = run({ 3, 1, 5, 2, 4 })
    for k, v in pairs(a) do check(v == b[k] and v == c[k], "same slot for " .. k .. " in any order") end
    local cx, cy = L.GetReservation("c")
    local ax, ay = L.GetReservation("a")
    check(cy < ay, "lower priority number stacks first")
    local x1, y1 = L.Reserve("a", "top_center", 200, 30, 0)
    check(x1 == ax and y1 == ay, "re-reserving is stable")
    local gen = L.GetGeneration()
    collectgarbage(); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do L.Reserve("a", "top_center", 200, 30, 0) end
    local grew = collectgarbage("count") - before
    collectgarbage("restart")
    check(grew < 1, "re-reserving the same request allocates nothing (" .. grew .. " KB)")
    check(L.GetGeneration() == gen, "re-reserving does not bump the generation")
    L.Release("c")
    check(L.GetReservation("c") == nil, "Release drops the reservation")
    local _, ay2 = L.GetReservation("a")
    check(ay2 < ay, "later items close the gap after a release")
    check(L.Reserve("z", "nowhere", 10, 10) == nil, "unknown dock is refused")
    check(L.Reserve("z", "top_center", "x", 10) == nil, "bad size is refused")
end

-- 4. Clamping: oversize and edge docks stay on screen.
do
    local L, exu = fresh(), makeExu()
    L.Refresh(0, exu)
    local x, y = L.Reserve("wide", "right_mid", 5000, 40)
    check(x == 0, "wider than the screen clamps to x 0")
    local bx, by = L.Reserve("tall", "bottom_center", 100, 900)
    local _, h = L.GetResolution()
    check(by + 900 <= h and bx >= 0, "tall bottom item clamps to the screen")
end

-- 5. Missing and failing getters.
do
    local L, exu = fresh(), makeExu({ menu = false })
    L.Refresh(0, exu)
    local x, y, w, h = L.GetKeepOut("command_menu")
    check(x == 0 and y == 0 and w > 0 and h > 0, "nil command menu falls back to the fractional rect")
    local x1, y1 = L.Reserve("m", "left_mid", 100, 30)
    check(x1 and y1 and y1 >= y + h, "left_mid clears the fallback menu")

    local L2, exu2 = fresh(), makeExu({ menuError = true, resError = true })
    L2.Refresh(0, exu2)
    local w2, h2 = L2.GetResolution()
    check(w2 > 0 and h2 > 0 and L2.GetKeepOut("command_menu"), "erroring getters fall back, no throw")
    check(L2.Reserve("m", "top_center", 100, 30), "reserve works after getter errors")

    local L3 = fresh()
    L3.Refresh(0, {})
    check(L3.GetGeneration() > 0 and L3.GetKeepOut("radar"), "an exu with no getters still builds")
    local L4 = fresh()
    L4.Refresh(0, nil)
    check(L4.GetKeepOut("radar"), "no exu at all still builds")
    check(L4.TextHeight(0.026) >= 12 and L4.TextHeight(5, 12, 40) == 40, "text height clamps")
end

-- 6. Live scrap/pilot and native meters replace their fallbacks.
do
    local L, exu = fresh(), makeExu({
        IsNativeHudLayoutAvailable = function() return true end,
        GetNativeHudMeterRect = function(m) if m == "hull" then return 100, 1000, 200, 20 end return 400, 1000, 200, 20 end,
    })
    L.Refresh(0, exu)
    local hx, hy, hw, hh = L.GetKeepOut("hull_ammo")
    check(hx == 100 and hy == 1000 and hw == 500 and hh == 20, "native meters union into hull_ammo")
    local sx, sy = L.GetKeepOut("scrap_pilot")
    check(sx == 230 and sy == 12, "live scrap/pilot top-left is used")
end

-- 7. Debug off creates no overlays; on creates them; off again removes the labels.
do
    local L, exu = fresh(), makeExu()
    L.Refresh(0, exu)
    L.Reserve("a", "top_center", 100, 20)
    L.Refresh(5, exu)
    check(exu.created == 0, "debug off creates no overlays")
    L.SetDebug(true)
    check(exu.created > 0, "debug on creates overlay elements")
    local made = exu.created
    L.SetDebug(false)
    L.Reserve("b", "left_mid", 50, 20)
    check(exu.created == made, "debug off again creates nothing more")
end

-- 8. Reset drops reservations and rebuilds.
do
    local L, exu = fresh(), makeExu()
    L.Refresh(0, exu)
    L.Reserve("a", "top_center", 100, 20)
    local g = L.GetGeneration()
    L.Reset(exu)
    check(L.GetReservation("a") == nil and L.GetGeneration() > g, "Reset clears reservations and bumps the generation")
    L.Refresh(0, exu)
    check(L.GetKeepOut("radar"), "rebuilds after Reset")
end

print("Test-CRHudLayout OK (" .. checks .. " checks)")
