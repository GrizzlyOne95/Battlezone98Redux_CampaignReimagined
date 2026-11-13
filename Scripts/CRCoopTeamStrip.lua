-- Always-on co-op team strip: one small text line per teammate (never yourself), up to four,
-- "NAME  H 80  A 50", "NAME  on foot" or "NAME  NEEDS A RIDE", drawn at the left edge below the
-- top-left message/objective area and above the bottom-left cockpit radar. It only reads what
-- CRCoopComms already receives every 2 s (Describe/IsCritical), so there is no new networking.
-- Display only, never saved: Update is throttled, shows nothing outside co-op or with nobody to
-- list, and Destroy removes every overlay element (called on mission start/end and co-op teardown).
-- Every EXU call is pcall-guarded, so a missing overlay API or font simply shows nothing.
local M = {}
local P = "CR/TeamStrip/"
local MAX_LINES, PERIOD = 4, 0.25
local PIXELS = 1 -- exu.OVERLAY_METRICS.PIXELS
local NORMAL, CRITICAL = { 0.75, 0.92, 1.0, 0.95 }, { 1.0, 0.35, 0.25, 1.0 }

local LAYOUT_ID = "CR/TeamStrip"

-- CRHudLayout keeps the strip clear of native HUD rects (dock left_mid); nil when it is unavailable.
local function layoutModule()
    local ok, L = pcall(require, "CRHudLayout")
    return ok and type(L) == "table" and L or nil
end

local function name(p) return tostring(p and p.name or "Player"):gsub("[%c]", " "):sub(1, 16) end

function M.Create(d)
    local strip, built, nextUpdate, shown, hidden = {}, false, 0, {}, false
    local seenGeneration
    local function call(fn, ...)
        local exu = d.exu
        if type(exu) ~= "table" or type(exu[fn]) ~= "function" then return false end
        local ok, result = pcall(exu[fn], ...)
        return ok and result ~= false
    end
    local function textId(i) return P .. "Text" .. i end
    local function destroy()
        call("HideOverlay", P .. "Overlay")
        for i = MAX_LINES, 1, -1 do
            call("RemoveOverlayElementChild", P .. "Root", textId(i))
            call("DestroyOverlayElement", textId(i))
        end
        call("RemoveOverlay2D", P .. "Overlay", P .. "Root")
        call("DestroyOverlayElement", P .. "Root")
        call("DestroyOverlay", P .. "Overlay")
    end
    local function build()
        local exu = d.exu
        if type(exu) ~= "table" or exu.isStub then return false end
        destroy() -- elements left by an earlier Lua state (load) would make Create fail
        local w, h = 1280, 720
        if type(exu.GetGameResolution) == "function" then
            local ok, rw, rh = pcall(exu.GetGameResolution)
            if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then w, h = rw, rh end
        end
        local size = math.max(12, math.min(32, h * 0.022))
        local px = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS) or PIXELS
        local ok = call("CreateOverlay", P .. "Overlay")
            and call("CreateOverlayElement", "Panel", P .. "Root")
            and call("AddOverlay2D", P .. "Overlay", P .. "Root")
            and call("SetOverlayZOrder", P .. "Overlay", 504)
            and call("SetOverlayMetricsMode", P .. "Root", px)
        if ok then
            local x, y = w * 0.012, h * 0.38
            local L = layoutModule()
            if L then
                local okR, rx, ry = pcall(L.Reserve, LAYOUT_ID, "left_mid", math.ceil(w * 0.3),
                    math.ceil(size * 1.45 * MAX_LINES))
                if okR and rx then x, y = rx, ry end
                local okG, gen = pcall(L.GetGeneration)
                seenGeneration = okG and gen or nil
            end
            call("SetOverlayPosition", P .. "Root", x, y)
            call("SetOverlayDimensions", P .. "Root", w * 0.3, size * 1.45 * MAX_LINES)
            for i = 1, MAX_LINES do
                local t = textId(i)
                ok = call("CreateOverlayElement", "TextArea", t)
                    and call("AddOverlayElementChild", P .. "Root", t)
                    and call("SetOverlayMetricsMode", t, px)
                    and call("SetOverlayTextFont", t, "CRBZoneOverlayFont")
                if not ok then break end
                -- D3D11 cannot draw the image font's fixed-function material (see SXOverlay); harmless elsewhere
                call("SetOverlayMaterial", t, "CR_OverlayFont")
                call("SetOverlayParameter", t, "alignment", "left")
                call("SetOverlayPosition", t, 0, (i - 1) * size * 1.45)
                call("SetOverlayDimensions", t, w * 0.3, size * 1.4)
                call("SetOverlayTextCharHeight", t, size)
            end
        end
        if not ok then destroy(); return false end
        call("ShowOverlayElement", P .. "Root")
        call("ShowOverlay", P .. "Overlay")
        built, shown = true, {}
        return true
    end
    -- Always tears down by name: after a load or restart the engine can still hold the previous
    -- Lua state's overlay while this module's flags are fresh (same rule as CRLockBadge.Hide).
    function strip.Destroy()
        destroy()
        built, shown, nextUpdate, hidden = false, {}, 0, false
        seenGeneration = nil
        local L = layoutModule()
        if L then pcall(L.Release, LAYOUT_ID) end
    end
    -- Teammates as the PDA lists them: other human-team players that are not late joiners.
    function strip.Lines()
        local c = d.comms()
        if not c or not c.IsActive() then return {} end
        if c.TeamStripOn and not c.TeamStripOn() then return {} end
        local coop, lines, ids = d.coop, {}, {}
        local me, players = coop.GetLocalPlayerId(), coop.GetPlayers()
        for id, p in pairs(players) do
            if id ~= me and coop.IsHumanTeam(p.team) and not p.lateJoin then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            if #lines >= MAX_LINES then break end
            local word = c.Describe(id)
            local hp, ammo = word:match("^H(%d+) A(%d+)")
            if hp then word = string.format("H %s  A %s", hp, ammo) end
            if word == "" then word = "..." end
            lines[#lines + 1] = { text = name(players[id]) .. "  " .. word, critical = c.IsCritical(id) == true }
        end
        return lines
    end
    -- suppressed: pause menu, Escape or a cinematic is up; hide until it clears.
    function strip.Update(suppressed)
        if suppressed then
            if built and not hidden then call("HideOverlay", P .. "Overlay"); hidden = true end
            return
        end
        if hidden then call("ShowOverlay", P .. "Overlay"); hidden = false end
        local now = d.time()
        if now < nextUpdate then return end
        nextUpdate = now + PERIOD
        local lines = strip.Lines()
        if #lines == 0 then
            if built then strip.Destroy() end
            return
        end
        if built then
            -- Resolution, UI scale or a HUD rect changed: rebuild at the new size and position.
            local L = layoutModule()
            local okG, gen = false, nil
            if L then okG, gen = pcall(L.GetGeneration) end
            if okG and gen ~= seenGeneration then strip.Destroy() end
        end
        if not built and not build() then return end
        for i = 1, MAX_LINES do
            local line, t = lines[i], textId(i)
            local key = line and (line.text .. (line.critical and "!" or "")) or false
            if shown[i] ~= key then
                shown[i] = key
                if line then
                    local col = line.critical and CRITICAL or NORMAL
                    call("SetOverlayTextColor", t, col[1], col[2], col[3], col[4])
                    call("SetOverlayCaption", t, line.text)
                    call("ShowOverlayElement", t)
                else
                    call("HideOverlayElement", t)
                end
            end
        end
    end
    function strip.IsShown() return built end
    return strip
end
return M
