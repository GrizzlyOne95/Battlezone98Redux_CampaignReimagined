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
    for _, name in ipairs({ "Title", "Status", "Telemetry", "Controls", "Notification", "ScrapSlot", "PilotSlot" }) do
        self:_Call("RemoveOverlayElementChild", PREFIX .. "Root", PREFIX .. name)
        self:_Call("DestroyOverlayElement", PREFIX .. name)
    end
    self:_Call("RemoveOverlay2D", PREFIX .. "Overlay", PREFIX .. "Root")
    self:_Call("DestroyOverlayElement", PREFIX .. "Root")
    self:_Call("DestroyOverlay", PREFIX .. "Overlay")
    self.ready, self.width, self.height, self.notice = false, nil, nil, nil
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
    for _, name in ipairs({ "Title", "Status", "Telemetry", "Controls", "Notification", "ScrapSlot", "PilotSlot" }) do
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
    self:Slots(false)
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
    local size = math.max(16, math.min(48, height * 0.026))
    local x, y, w = width * 0.08, height * 0.04, width * 0.84
    self:_Call("SetOverlayPosition", PREFIX .. "Root", x, y)
    self:_Call("SetOverlayDimensions", PREFIX .. "Root", w, height * 0.70)
    for i, name in ipairs({ "Title", "Status", "Telemetry", "Controls" }) do
        self:_Call("SetOverlayPosition", PREFIX .. name, 0, (i - 1) * size * 1.45)
        self:_Call("SetOverlayDimensions", PREFIX .. name, w, size * 1.4)
        self:_Call("SetOverlayTextCharHeight", PREFIX .. name, size)
    end
    self:_Call("SetOverlayPosition", PREFIX .. "Notification", width * 0.58, height * 0.15)
    self:_Call("SetOverlayDimensions", PREFIX .. "Notification", width * 0.30, size * 2.8)
    self:_Call("SetOverlayTextCharHeight", PREFIX .. "Notification", size)
    for _, row in ipairs({ { "ScrapSlot", 0.68 }, { "PilotSlot", 0.82 } }) do
        self:_Call("SetOverlayPosition", PREFIX .. row[1], width * (row[2] - 0.08), height * 0.55)
        self:_Call("SetOverlayDimensions", PREFIX .. row[1], width * 0.15, size * 1.4)
        self:_Call("SetOverlayTextCharHeight", PREFIX .. row[1], size)
    end
end

function SXOverlay:Notify(message, duration, clock, preview)
    self.notice, self.noticeUntil, self.noticePreview = message, clock + duration, preview == true
end

function SXOverlay:Slots(enabled)
    self.slots = enabled == true
    self:_Call("SetOverlayCaption", PREFIX .. "ScrapSlot", self.slots and "[ SCRAP ]" or "")
    self:_Call("SetOverlayCaption", PREFIX .. "PilotSlot", self.slots and "[ PILOTS ]" or "")
end

function SXOverlay:Update(title, status, controls, clock, telemetry)
    if not self.ready then return end
    self:Layout()
    self:_Call("SetOverlayCaption", PREFIX .. "Title", title)
    self:_Call("SetOverlayCaption", PREFIX .. "Status", status)
    self:_Call("SetOverlayCaption", PREFIX .. "Telemetry", telemetry or "")
    self:_Call("SetOverlayCaption", PREFIX .. "Controls", controls)
    clock = clock or 0
    local notice = ""
    if self.notice and clock < self.noticeUntil then
        local spinner = ({ "|", "/", "-", "\\" })[math.floor(clock * 4) % 4 + 1]
        notice = "[ " .. spinner .. " ] " .. self.notice .. (self.noticePreview and "\nNotification preview" or "")
    end
    self:_Call("SetOverlayCaption", PREFIX .. "Notification", notice)
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
