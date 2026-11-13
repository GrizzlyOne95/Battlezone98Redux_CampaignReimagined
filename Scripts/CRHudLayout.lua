-- CRHudLayout: one place that knows where the native HUD is, so CR overlays can ask for a slot that avoids it.
-- Pixels, top-left origin (OVERLAY_METRICS.PIXELS). Pure Lua over EXU getters; every getter is guarded and pcall'd,
-- so a missing or failing getter just falls back to the approximate rects below.
--
--   local x, y = Layout.Reserve("my/id", "top_center", w, h [, priority])   -- stable, no allocation when unchanged
--   Layout.Refresh(GetTime(), exu)   -- once per tick; polls at most 1/s and bumps Layout.GetGeneration() on change
-- Consumers re-call Reserve (cheap) when GetGeneration() differs from the value they last saw.
local Layout = {}

local POLL_SECONDS = 1.0
local W, H, SCALE = 1280, 720, 1
local GAP = 6 -- px between stacked reservations

-- Keep-out rects used when no live source exists, as fractions of the screen {x, y, w, h}.
-- APPROXIMATE, TUNE WITH THE DEBUG OUTLINE (Layout.SetDebug(true)). Not measured from the stock HUD: the repo has
-- no reference rects for these (only the command menu footprint, 193*uiScale px wide, in PersistentConfig's legacy
-- scrap/pilot layout). Values are deliberately generous so docks stay clear of the stock elements.
local FALLBACK = {
    { "command_menu", 0.00, 0.00, 0.11, 0.40 }, -- top-left button stack (live rect used when available)
    { "scrap_pilot", 0.12, 0.00, 0.08, 0.09 },  -- scrap/pilot counters right of the menu (live top-left when available)
    { "hull_ammo", 0.18, 0.90, 0.22, 0.10 },    -- hull/ammo meters (live native rect when available)
    { "radar", 0.00, 0.70, 0.18, 0.30 },        -- bottom-left radar
    { "weapon_plate", 0.80, 0.80, 0.20, 0.20 }, -- bottom-right weapon/ordnance plate
    { "messages", 0.25, 0.00, 0.50, 0.08 },     -- objective / message lines, top centre
    { "timer", 0.45, 0.08, 0.10, 0.04 },        -- mission timer under the messages
    { "target_info", 0.72, 0.00, 0.28, 0.12 },  -- target / selection info, top right
}

-- Docks: origin as a screen fraction, ax = which edge of the reservation sits on the origin x (0 left, 0.5 centre,
-- 1 right). Every dock stacks downwards. cursor is scratch used while laying out.
local DOCKS = {
    left_mid = { fx = 0.01, fy = 0.30, ax = 0.0 },
    right_mid = { fx = 0.99, fy = 0.30, ax = 1.0 },
    top_center = { fx = 0.50, fy = 0.04, ax = 0.5 },
    top_right = { fx = 0.99, fy = 0.14, ax = 1.0 },
    bottom_center = { fx = 0.50, fy = 0.80, ax = 0.5 },
}

local X -- last exu passed in
local rects, rectById = {}, {} -- keep-out rects {id,x,y,w,h}, created once
local res, byId = {}, {}       -- reservations {id,dock,w,h,prio,x,y}, kept sorted by (prio, id)
local generation, lastPoll, built, dirty = 0, nil, false, true
local debugOn, debugCount = false, 0
local DBG = "CR/HudLayout/"

local function call(name, ...)
    if type(X) ~= "table" or type(X[name]) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(X[name], ...)
    if ok then return a, b, c, d end
    return nil
end

local function isNum(v) return type(v) == "number" and v == v end

local function setRect(r, x, y, w, h)
    x, y, w, h = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(w + 0.5), math.floor(h + 0.5)
    if r.x == x and r.y == y and r.w == w and r.h == h then return false end
    r.x, r.y, r.w, r.h = x, y, w, h
    return true
end

local function intersects(x, y, w, h, r)
    return x < r.x + r.w and r.x < x + w and y < r.y + r.h and r.y < y + h
end

local function destroyDebug()
    for i = 1, debugCount do
        call("RemoveOverlayElementChild", DBG .. "Root", DBG .. "T" .. i)
        call("DestroyOverlayElement", DBG .. "T" .. i)
    end
    debugCount = 0
    call("HideOverlay", DBG .. "Overlay")
    call("RemoveOverlay2D", DBG .. "Overlay", DBG .. "Root")
    call("DestroyOverlayElement", DBG .. "Root")
    call("DestroyOverlay", DBG .. "Overlay")
end

-- Debug only: one text label at the corner of every keep-out ("K:") and reservation ("R:") rect.
local function drawDebug()
    destroyDebug()
    local px = (type(X) == "table" and X.OVERLAY_METRICS and X.OVERLAY_METRICS.PIXELS) or 1
    local ok = call("CreateOverlay", DBG .. "Overlay") ~= false
        and call("CreateOverlayElement", "Panel", DBG .. "Root") ~= false
        and call("AddOverlay2D", DBG .. "Overlay", DBG .. "Root") ~= false
    if not ok then destroyDebug(); return end
    call("SetOverlayZOrder", DBG .. "Overlay", 600)
    call("SetOverlayMetricsMode", DBG .. "Root", px)
    call("SetOverlayPosition", DBG .. "Root", 0, 0)
    call("SetOverlayDimensions", DBG .. "Root", W, H)
    local function label(tag, id, r)
        debugCount = debugCount + 1
        local t = DBG .. "T" .. debugCount
        call("CreateOverlayElement", "TextArea", t)
        call("AddOverlayElementChild", DBG .. "Root", t)
        call("SetOverlayMetricsMode", t, px)
        call("SetOverlayTextFont", t, "CRBZoneOverlayFont")
        call("SetOverlayMaterial", t, "CR_OverlayFont")
        call("SetOverlayPosition", t, r.x, r.y)
        call("SetOverlayDimensions", t, 260, 16)
        call("SetOverlayTextCharHeight", t, 14)
        call("SetOverlayTextColor", t, tag == "K" and 1 or 0.3, tag == "K" and 0.4 or 1, 0.3, 0.95)
        call("SetOverlayCaption", t, string.format("%s:%s %dx%d", tag, id, r.w, r.h))
        call("ShowOverlayElement", t)
    end
    for _, r in ipairs(rects) do label("K", r.id, r) end
    for _, e in ipairs(res) do label("R", e.id, e) end
    call("ShowOverlayElement", DBG .. "Root")
    call("ShowOverlay", DBG .. "Overlay")
end

local function cmp(a, b)
    if a.prio ~= b.prio then return a.prio < b.prio end
    return a.id < b.id
end

-- Place every reservation in (priority, id) order: dock origin, then below the dock's previous item, then pushed
-- past any keep-out or earlier reservation it still touches, then clamped to the screen.
local function layout()
    dirty = false
    table.sort(res, cmp)
    for _, d in pairs(DOCKS) do d.cursor = nil end
    local moved = false
    for i, e in ipairs(res) do
        local d = DOCKS[e.dock]
        local x = d.fx * W - d.ax * e.w
        local y = math.max(d.fy * H, d.cursor or 0)
        for _ = 1, #rects + #res + 2 do
            local pushed = false
            for _, r in ipairs(rects) do
                if intersects(x, y, e.w, e.h, r) then y = r.y + r.h + GAP; pushed = true end
            end
            for j = 1, i - 1 do
                local r = res[j]
                if intersects(x, y, e.w, e.h, r) then y = r.y + r.h + GAP; pushed = true end
            end
            if not pushed then break end
        end
        x = math.floor(math.max(0, math.min(x, W - e.w)) + 0.5)
        y = math.floor(math.max(0, math.min(y, H - e.h)) + 0.5)
        if e.x ~= nil and (e.x ~= x or e.y ~= y) then moved = true end
        e.x, e.y = x, y
        d.cursor = y + e.h + GAP
    end
    if moved then generation = generation + 1 end
    if debugOn then drawDebug() end
end

-- Rebuild every keep-out from live sources (fallback fractions otherwise). Returns true if anything changed.
local function rebuild()
    local changed = false
    local rw, rh = call("GetGameResolution")
    if not (isNum(rw) and isNum(rh) and rw > 0 and rh > 0) then rw, rh = W, H end
    local s = call("GetUIScaling")
    if not (isNum(s) and s >= 1) then s = 1 end
    if rw ~= W or rh ~= H or s ~= SCALE then W, H, SCALE, changed = rw, rh, s, true end

    for i, f in ipairs(FALLBACK) do
        local r = rects[i]
        if not r then r = { id = f[1] }; rects[i] = r; rectById[f[1]] = r end
        local x, y, w, h = f[2] * W, f[3] * H, f[4] * W, f[5] * H
        local id = f[1]
        if id == "command_menu" then
            local l, t, rr, b = call("GetCommandMenuRect")
            if isNum(l) and isNum(t) and isNum(rr) and isNum(b) then
                -- the stock frame reaches ~16*scale above and out to ~193*scale (see PersistentConfig legacy layout)
                x, y, w, h = l, t - 16 * s, math.max(rr - l, 193 * s), b - t + 16 * s
            end
        elseif id == "scrap_pilot" then
            local tx, ty = call("GetScrapPilotHudTopLeft")
            if not (isNum(tx) and isNum(ty)) then tx, ty = call("GetScrapHudTopLeft") end
            if isNum(tx) and isNum(ty) then
                -- size is an estimate (two text lines ~48*scale apart); glyphs extend left of the anchor
                x, y, w, h = tx - 20 * s, ty, 150 * s, 84 * s
            end
        elseif id == "hull_ammo" then
            local x0, y0, x1, y1
            for _, meter in ipairs({ "hull", "ammo" }) do
                if call("IsNativeHudLayoutAvailable", meter) == true then
                    local mx, my, mw, mh = call("GetNativeHudMeterRect", meter)
                    if isNum(mx) and isNum(my) and isNum(mw) and isNum(mh) then
                        x0, y0 = math.min(x0 or mx, mx), math.min(y0 or my, my)
                        x1, y1 = math.max(x1 or (mx + mw), mx + mw), math.max(y1 or (my + mh), my + mh)
                    end
                end
            end
            if x0 then x, y, w, h = x0, y0, x1 - x0, y1 - y0 end
        end
        if setRect(r, x, y, w, h) then changed = true end
    end
    return changed
end

function Layout.Refresh(now, exu)
    if exu ~= nil then X = exu end
    now = isNum(now) and now or 0
    if built and lastPoll and now >= lastPoll and now - lastPoll < POLL_SECONDS then return generation end
    lastPoll = now
    local changed = rebuild()
    if changed or not built then
        built = true
        generation = generation + 1
        dirty = true
    end
    if dirty then layout() end
    return generation
end

function Layout.GetGeneration() return generation end
function Layout.GetResolution() return W, H end
function Layout.GetUIScale() return SCALE end

-- Text height in px from a fraction of the screen height, clamped (the CRLockBadge pattern).
function Layout.TextHeight(fraction, lo, hi)
    return math.max(lo or 12, math.min(hi or 40, H * (fraction or 0.026)))
end

-- Returns x, y (integers) or nil for an unknown dock / bad size. Same id + same request is a table lookup.
function Layout.Reserve(id, dock, w, h, priority)
    if type(id) ~= "string" or not DOCKS[dock] or not isNum(w) or not isNum(h) then return nil end
    priority = isNum(priority) and priority or 0
    local e = byId[id]
    if e and e.dock == dock and e.w == w and e.h == h and e.prio == priority and not dirty then return e.x, e.y end
    if not built then Layout.Refresh(0) end
    if not e then
        e = { id = id }
        byId[id] = e
        res[#res + 1] = e
    end
    e.dock, e.w, e.h, e.prio = dock, w, h, priority
    layout()
    return e.x, e.y
end

function Layout.Release(id)
    local e = byId[id]
    if not e then return end
    byId[id] = nil
    for i, v in ipairs(res) do
        if v == e then table.remove(res, i); break end
    end
    layout()
end

-- Read access (tests, debugging).
function Layout.GetReservation(id)
    local e = byId[id]
    if e then return e.x, e.y, e.w, e.h end
end
function Layout.GetKeepOut(id)
    local r = rectById[id]
    if r then return r.x, r.y, r.w, r.h end
end

function Layout.SetDebug(on)
    on = on == true
    if on == debugOn then return end
    debugOn = on
    if on then drawDebug() else destroyDebug() end
end

-- Mission init / teardown: drop reservations and overlays; the next Refresh rebuilds from scratch.
function Layout.Reset(exu)
    if exu ~= nil then X = exu end
    destroyDebug()
    res, byId = {}, {}
    built, lastPoll, dirty = false, nil, true
    generation = generation + 1
end

return Layout
