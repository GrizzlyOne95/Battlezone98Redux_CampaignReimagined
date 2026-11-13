-- Co-op partner bars: two small horizontal bars (hull on top, ammo below) floating above each human
-- teammate's current vehicle or pilot, up to four, like the native target bars but without a reticle.
-- Hidden while the teammate is off screen, behind the camera, beyond MAX_RANGE, or is the local
-- player's current target (the native bars already show then). Values are the live GetHealth/GetAmmo
-- of the teammate's local copy; the CRCoopComms broadcast (hp/ammo 0-100) is only the fallback.
-- Display only, never saved; Destroy removes every overlay element. Every EXU call is pcall-guarded.
-- Panels use existing shipped materials with baked colours (D3D11 ignores SetOverlayColor on panels):
-- CRPdaBackdrop_DG_A20 track, CRPdaBorder_G_A20 hull, CRPdaBorder_R_A20 low hull, CRPdaBorder_B_A20 ammo.
local M = {}
local P = "CR/PartnerBars/"
local MAX_BARS, MAX_RANGE, LIFT, REFRESH, LOW_HULL = 4, 400, 6, 0.5, 0.25
local PIXELS = 1 -- exu.OVERLAY_METRICS.PIXELS
local TRACK, HULL, HULL_LOW, AMMO = "CRPdaBackdrop_DG_A20", "CRPdaBorder_G_A20", "CRPdaBorder_R_A20", "CRPdaBorder_B_A20"

local PARTS = { "Track", "Hull", "Ammo" }

local function fraction(v) return type(v) == "number" and math.max(0, math.min(1, v)) or nil end

function M.Create(d)
    local bars, built, hidden, nextRefresh, retryAt = {}, false, false, 0, 0
    local ids, count, pt = {}, 0, { x = 0, y = 0, z = 0 }
    local vis, px, py, hw, aw, low = {}, {}, {}, {}, {}, {}
    local w, h, barW, barH = 1280, 720, 80, 4
    local function call(fn, ...)
        local exu = d.exu
        if type(exu) ~= "table" or type(exu[fn]) ~= "function" then return false end
        local ok, result = pcall(exu[fn], ...)
        return ok and result ~= false
    end
    local function id(i, part) return P .. part .. i end
    local function destroy()
        call("HideOverlay", P .. "Overlay")
        for i = MAX_BARS, 1, -1 do
            for _, part in ipairs(PARTS) do
                call("RemoveOverlayElementChild", P .. "Root", id(i, part))
                call("DestroyOverlayElement", id(i, part))
            end
        end
        call("RemoveOverlay2D", P .. "Overlay", P .. "Root")
        call("DestroyOverlayElement", P .. "Root")
        call("DestroyOverlay", P .. "Overlay")
    end
    local function build()
        local exu = d.exu
        if type(exu) ~= "table" or exu.isStub then return false end
        destroy() -- elements left by an earlier Lua state (load) would make Create fail
        if type(exu.GetGameResolution) == "function" then
            local ok, rw, rh = pcall(exu.GetGameResolution)
            if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then w, h = rw, rh end
        end
        barW, barH = math.floor(h * 0.07), math.max(3, math.floor(h * 0.006))
        local px1 = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS) or PIXELS
        local ok = call("CreateOverlay", P .. "Overlay")
            and call("CreateOverlayElement", "Panel", P .. "Root")
            and call("AddOverlay2D", P .. "Overlay", P .. "Root")
            and call("SetOverlayZOrder", P .. "Overlay", 503)
            and call("SetOverlayMetricsMode", P .. "Root", px1)
        if ok then
            call("SetOverlayPosition", P .. "Root", 0, 0)
            call("SetOverlayDimensions", P .. "Root", w, h)
            for i = 1, MAX_BARS do
                for _, part in ipairs(PARTS) do
                    local e = id(i, part)
                    ok = call("CreateOverlayElement", "Panel", e)
                        and call("AddOverlayElementChild", P .. "Root", e)
                        and call("SetOverlayMetricsMode", e, px1)
                        and call("SetOverlayMaterial", e, part == "Track" and TRACK or part == "Hull" and HULL or AMMO)
                    if not ok then break end
                    call("HideOverlayElement", e)
                end
                if not ok then break end
                vis[i], px[i], py[i], hw[i], aw[i], low[i] = false, -9999, -9999, -1, -1, false
                call("SetOverlayDimensions", id(i, "Track"), barW + 2, barH * 2 + 3)
            end
        end
        if not ok then destroy(); return false end
        call("ShowOverlayElement", P .. "Root")
        call("ShowOverlay", P .. "Overlay")
        built = true
        return true
    end
    function bars.Destroy()
        destroy()
        built, hidden, nextRefresh, count = false, false, 0, 0
    end
    -- Teammates as the PDA lists them (same rule as CRCoopTeamStrip.Lines), refreshed twice a second.
    local function refresh(now)
        nextRefresh = now + REFRESH
        count = 0
        local c = d.comms()
        if not c or not c.IsActive() then return end
        if c.PartnerBarsOn and not c.PartnerBarsOn() then return end
        local coop = d.coop
        local me = coop.GetLocalPlayerId()
        for pid, p in pairs(coop.GetPlayers()) do
            if pid ~= me and coop.IsHumanTeam(p.team) and not p.lateJoin then
                local n = count + 1
                while n > 1 and ids[n - 1] > pid do ids[n] = ids[n - 1]; n = n - 1 end
                ids[n] = pid; count = count + 1
            end
        end
        if count > MAX_BARS then count = MAX_BARS end
    end
    local function show(i, flag)
        if vis[i] == flag then return end
        vis[i] = flag
        for _, part in ipairs(PARTS) do
            call(flag and "ShowOverlayElement" or "HideOverlayElement", id(i, part))
        end
    end
    -- Screen x, y (pixels) just above the teammate, or nil when it should not be drawn.
    local function project(handle)
        local pos = d.position(handle)
        if type(pos) ~= "table" then return nil end
        pt.x, pt.y, pt.z = pos.x, pos.y + LIFT, pos.z
        local exu = d.exu
        local ok, x, y, depth = pcall(exu.WorldToScreen, pt)
        if not ok or type(x) ~= "number" or type(y) ~= "number" or type(depth) ~= "number" then return nil end
        if depth <= 0 or depth > MAX_RANGE or x < 0 or x > w or y < 0 or y > h then return nil end
        return x, y
    end
    -- suppressed: pause menu, Escape or a cinematic is up; hide until it clears.
    function bars.Update(suppressed)
        if suppressed then
            if built and not hidden then call("HideOverlay", P .. "Overlay"); hidden = true end
            return
        end
        if hidden then call("ShowOverlay", P .. "Overlay"); hidden = false end
        local now = d.time()
        if now >= nextRefresh then
            refresh(now)
            if count == 0 and built then bars.Destroy(); return end
        end
        if count == 0 then return end
        if not built then
            -- A failed build (name clash, missing API) retries every 2 s, not every frame.
            if now < retryAt then return end
            if not build() then retryAt = now + 2; return end
        end
        local comms, players, target = d.comms(), d.coop.GetPlayers(), d.target()
        for i = 1, MAX_BARS do
            local pid, p = ids[i], nil
            local handle, x, y
            if i <= count then
                p = players[pid]
                handle = p and p.handle
                if handle and handle ~= target and d.valid(handle) then x, y = project(handle) end
            end
            if not x then
                show(i, false)
            else
                local st = comms and comms.GetStatus(pid)
                local hull = fraction(d.health(handle)) or (st and st.hp / 100) or 0
                local ammo = fraction(d.ammo(handle)) or (st and st.ammo / 100) or 0
                local bx, by = math.floor(x - barW / 2 + 0.5), math.floor(y - barH * 2 - 3 + 0.5)
                local hwNew, awNew = math.floor(hull * barW + 0.5), math.floor(ammo * barW + 0.5)
                local isLow = hull <= LOW_HULL
                local moved = math.abs(bx - px[i]) >= 1 or math.abs(by - py[i]) >= 1
                if moved then
                    px[i], py[i] = bx, by
                    call("SetOverlayPosition", id(i, "Track"), bx - 1, by - 1)
                    call("SetOverlayPosition", id(i, "Hull"), bx, by)
                    call("SetOverlayPosition", id(i, "Ammo"), bx, by + barH + 1)
                end
                if hwNew ~= hw[i] then hw[i] = hwNew; call("SetOverlayDimensions", id(i, "Hull"), hwNew, barH) end
                if awNew ~= aw[i] then aw[i] = awNew; call("SetOverlayDimensions", id(i, "Ammo"), awNew, barH) end
                if isLow ~= low[i] then low[i] = isLow; call("SetOverlayMaterial", id(i, "Hull"), isLow and HULL_LOW or HULL) end
                show(i, true)
            end
        end
    end
    function bars.IsShown() return built end
    return bars
end
return M
