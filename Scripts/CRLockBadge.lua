-- Small "FIRE CONTROLS LOCKED" line, bottom centre, shown only while a mission actually holds the player's EXU
-- control mask (a refused mask shows nothing: the player can still fire). Display only, never saved: Show/Hide
-- are idempotent and every call is pcall-guarded, so a missing overlay API or font simply shows nothing.
local Badge = {}
local P = "CR/LockBadge/"
local TEXT = "FIRE CONTROLS LOCKED"
local shown = false
local PIXELS = 1 -- exu.OVERLAY_METRICS.PIXELS
local ID = "CR/LockBadge"
local seenGeneration = nil

local function call(exu, name, ...)
    if type(exu) ~= "table" or type(exu[name]) ~= "function" then return false end
    local ok, result = pcall(exu[name], ...)
    return ok and result ~= false
end

local function destroy(exu)
    call(exu, "HideOverlay", P .. "Overlay")
    call(exu, "RemoveOverlayElementChild", P .. "Root", P .. "Text")
    call(exu, "DestroyOverlayElement", P .. "Text")
    call(exu, "RemoveOverlay2D", P .. "Overlay", P .. "Root")
    call(exu, "DestroyOverlayElement", P .. "Root")
    call(exu, "DestroyOverlay", P .. "Overlay")
end

-- Position comes from CRHudLayout (dock bottom_center, 0.80h like the old fixed placement); without it (or if it
-- errors) the old full-width placement is used.
local function place(exu)
    local w, h = 1280, 720
    if type(exu.GetGameResolution) == "function" then
        local ok, rw, rh = pcall(exu.GetGameResolution)
        if ok and type(rw) == "number" and type(rh) == "number" and rw > 0 and rh > 0 then w, h = rw, rh end
    end
    local size = math.max(12, math.min(40, h * 0.026))
    local okL, Layout = pcall(require, "CRHudLayout")
    if okL and type(Layout) == "table" then
        local okR, x, y, bw = pcall(function()
            Layout.Refresh(type(GetTime) == "function" and GetTime() or 0, exu)
            local width = math.ceil(#TEXT * size * 0.62)
            local px, py = Layout.Reserve(ID, "bottom_center", width, math.ceil(size * 1.5))
            seenGeneration = Layout.GetGeneration()
            return px, py, width
        end)
        if okR and x then
            call(exu, "SetOverlayPosition", P .. "Root", x, y)
            call(exu, "SetOverlayDimensions", P .. "Root", bw, size * 1.5)
            call(exu, "SetOverlayPosition", P .. "Text", bw * 0.5, 0)
            call(exu, "SetOverlayDimensions", P .. "Text", bw, size * 1.4)
            call(exu, "SetOverlayTextCharHeight", P .. "Text", size)
            return
        end
    end
    call(exu, "SetOverlayPosition", P .. "Root", 0, h * 0.80)
    call(exu, "SetOverlayDimensions", P .. "Root", w, size * 1.5)
    call(exu, "SetOverlayPosition", P .. "Text", w * 0.5, 0)
    call(exu, "SetOverlayDimensions", P .. "Text", w, size * 1.4)
    call(exu, "SetOverlayTextCharHeight", P .. "Text", size)
end

function Badge.Show(exu)
    if shown or type(exu) ~= "table" or exu.isStub then return shown end
    destroy(exu) -- elements left by an earlier Lua state (load) would make Create fail
    local t = P .. "Text"
    local px = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS) or PIXELS
    local ok = call(exu, "CreateOverlay", P .. "Overlay")
        and call(exu, "CreateOverlayElement", "Panel", P .. "Root")
        and call(exu, "AddOverlay2D", P .. "Overlay", P .. "Root")
        and call(exu, "SetOverlayZOrder", P .. "Overlay", 505)
        and call(exu, "SetOverlayMetricsMode", P .. "Root", px)
        and call(exu, "CreateOverlayElement", "TextArea", t)
        and call(exu, "AddOverlayElementChild", P .. "Root", t)
        and call(exu, "SetOverlayMetricsMode", t, px)
        and call(exu, "SetOverlayTextFont", t, "CRBZoneOverlayFont")
    if not ok then destroy(exu); return false end
    -- D3D11 cannot draw the image font's fixed-function material (see SXOverlay); harmless elsewhere
    call(exu, "SetOverlayMaterial", t, "CR_OverlayFont")
    call(exu, "SetOverlayParameter", t, "alignment", "center")
    place(exu)
    call(exu, "SetOverlayTextColor", t, 1.0, 0.72, 0.25, 0.95)
    call(exu, "SetOverlayCaption", t, TEXT)
    call(exu, "ShowOverlayElement", t)
    call(exu, "ShowOverlayElement", P .. "Root")
    call(exu, "ShowOverlay", P .. "Overlay")
    shown = true
    return true
end

-- Always tears down: after a load the Lua flag is fresh but the engine may still hold the old elements.
function Badge.Hide(exu)
    shown = false
    destroy(exu)
    local okL, Layout = pcall(require, "CRHudLayout")
    if okL and type(Layout) == "table" then pcall(Layout.Release, ID) end
end

-- Per tick: re-place the badge when CRHudLayout's generation changed (resolution, scale or HUD rect change).
function Badge.Update(exu)
    if not shown then return end
    local okL, Layout = pcall(require, "CRHudLayout")
    if not (okL and type(Layout) == "table") then return end
    local okG, gen = pcall(Layout.GetGeneration)
    if okG and gen ~= seenGeneration then place(exu) end
end

function Badge.IsShown() return shown end

return Badge
