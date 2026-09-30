-- Small title/status layer. Never disables stock HUD or changes global settings.
local SXOverlay = {}
SXOverlay.__index = SXOverlay
local PREFIX = "SX/Livewire/"
local REQUIRED = { "CreateOverlay", "DestroyOverlay", "CreateOverlayElement",
    "DestroyOverlayElement", "AddOverlay2D", "AddOverlayElementChild", "SetOverlayZOrder",
    "SetOverlayMetricsMode", "SetOverlayPosition", "SetOverlayDimensions", "SetOverlayCaption",
    "SetOverlayTextFont", "SetOverlayTextCharHeight", "SetOverlayTextColor",
    "ShowOverlay", "HideOverlay", "ShowOverlayElement", "RemoveOverlay2D", "RemoveOverlayElementChild" }

function SXOverlay.New(exu)
    return setmetatable({ exu = exu, ready = false, status = "BLOCKED", names = {} }, SXOverlay)
end

function SXOverlay:_Call(name, ...)
    if not self.exu or type(self.exu[name]) ~= "function" then return false end
    local ok, result = pcall(self.exu[name], ...)
    return ok and result ~= false
end

function SXOverlay:Destroy()
    self:_Call("HideOverlay", PREFIX .. "Overlay")
    for _, name in ipairs({ "Title", "Status", "Controls" }) do
        self:_Call("RemoveOverlayElementChild", PREFIX .. "Root", PREFIX .. name)
        self:_Call("DestroyOverlayElement", PREFIX .. name)
    end
    self:_Call("RemoveOverlay2D", PREFIX .. "Overlay", PREFIX .. "Root")
    self:_Call("DestroyOverlayElement", PREFIX .. "Root")
    self:_Call("DestroyOverlay", PREFIX .. "Overlay")
    self.ready, self.width, self.height = false, nil, nil
end

function SXOverlay:Create()
    if not self.exu or self.exu.isStub then return false end
    for _, name in ipairs(REQUIRED) do
        if type(self.exu[name]) ~= "function" then return false end
    end
    self:Destroy()
    local ok = self:_Call("CreateOverlay", PREFIX .. "Overlay")
        and self:_Call("CreateOverlayElement", "Panel", PREFIX .. "Root")
        and self:_Call("AddOverlay2D", PREFIX .. "Overlay", PREFIX .. "Root")
        and self:_Call("SetOverlayZOrder", PREFIX .. "Overlay", 510)
        and self:_Call("SetOverlayMetricsMode", PREFIX .. "Root", 1)
    for _, name in ipairs({ "Title", "Status", "Controls" }) do
        ok = ok and self:_Call("CreateOverlayElement", "TextArea", PREFIX .. name)
            and self:_Call("AddOverlayElementChild", PREFIX .. "Root", PREFIX .. name)
            and self:_Call("SetOverlayMetricsMode", PREFIX .. name, 1)
            and self:_Call("SetOverlayTextFont", PREFIX .. name, "CRBZoneOverlayFont")
            and self:_Call("SetOverlayTextColor", PREFIX .. name, 0.85, 0.95, 1.0, 1.0)
            and self:_Call("ShowOverlayElement", PREFIX .. name)
    end
    if not ok then self:Destroy(); self.status = "BLOCKED"; return false end
    self.ready, self.status = true, "PENDING"
    self:Layout()
    self:_Call("ShowOverlayElement", PREFIX .. "Root")
    self:_Call("ShowOverlay", PREFIX .. "Overlay")
    return true
end

function SXOverlay:Layout()
    if not self.ready then return end
    local width, height = 1280, 720
    if type(self.exu.GetGameResolution) == "function" then
        local ok, w, h = pcall(self.exu.GetGameResolution)
        if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
            width, height = w, h
        end
    end
    if width == self.width and height == self.height then return end
    self.width, self.height = width, height
    local size = math.max(16, math.min(28, height * 0.026))
    local x, y, w = width * 0.08, height * 0.04, width * 0.84
    self:_Call("SetOverlayPosition", PREFIX .. "Root", x, y)
    self:_Call("SetOverlayDimensions", PREFIX .. "Root", w, size * 5)
    for i, name in ipairs({ "Title", "Status", "Controls" }) do
        self:_Call("SetOverlayPosition", PREFIX .. name, 0, (i - 1) * size * 1.45)
        self:_Call("SetOverlayDimensions", PREFIX .. name, w, size * 1.4)
        self:_Call("SetOverlayTextCharHeight", PREFIX .. name, size)
    end
end

function SXOverlay:Update(title, status, controls)
    if not self.ready then return end
    self:Layout()
    self:_Call("SetOverlayCaption", PREFIX .. "Title", title)
    self:_Call("SetOverlayCaption", PREFIX .. "Status", status)
    self:_Call("SetOverlayCaption", PREFIX .. "Controls", controls)
    local hidden = false
    for _, name in ipairs({ "IsGameUiOpen", "IsPauseMenuOpen" }) do
        if type(self.exu[name]) == "function" then
            local ok, open = pcall(self.exu[name])
            hidden = hidden or (ok and open == true)
        end
    end
    self:_Call(hidden and "HideOverlay" or "ShowOverlay", PREFIX .. "Overlay")
end

return SXOverlay
