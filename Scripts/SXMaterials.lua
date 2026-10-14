-- Mission-owned, reversible per-subentity livery swap for the material lab.
-- The hull subentity of the "changed" scout cycles through authored SX_tint_<color>
-- materials (Materials/sxtint.material). Their tint lives in the emissive map, so it
-- reads at night and in every material scheme; pass colors or UV transforms alone do
-- not reach the Enhanced/CR object shaders. The control twin is never touched.
local SXMaterials = {}
SXMaterials.__index = SXMaterials
local REQUIRED = { "GetSubEntityCount", "GetSubEntityMaterial", "MaterialExists",
    "SetSubEntityMaterial", "SetMaterialPassColors" }
local GROUP = "General"
SXMaterials.HULL = "avfigh00"
SXMaterials.Colors = { "red", "gold", "green", "cyan", "blue", "magenta" }
SXMaterials.FLASH_GLOW = 1.8
local function TintName(color) return "SX_tint_" .. color end

local function Call(exu, name, ...)
    if not exu or type(exu[name]) ~= "function" then return false, "missing " .. name end
    return pcall(exu[name], ...)
end

function SXMaterials.New(exu, valid)
    return setmetatable({ exu = exu, valid = valid, status = "PENDING",
        detail = "waiting for render entities", active = false }, SXMaterials)
end

function SXMaterials:Available()
    if not self.exu or self.exu.isStub then return false, "native EXU unavailable" end
    for _, name in ipairs(REQUIRED) do
        if type(self.exu[name]) ~= "function" then return false, "missing " .. name end
    end
    return true
end

function SXMaterials:_Read(h)
    if not self.valid(h) then return nil, "fixture no longer valid" end
    local ok, count = Call(self.exu, "GetSubEntityCount", h)
    if not ok or type(count) ~= "number" or count < 1 or count > 64
        or count ~= math.floor(count) then return nil, "render entity not ready" end
    local names = {}
    for i = 0, count - 1 do
        local read, name = Call(self.exu, "GetSubEntityMaterial", h, i)
        if not read or type(name) ~= "string" or name == "" then
            return nil, "material inventory not ready"
        end
        names[#names + 1] = name
    end
    return names
end

function SXMaterials:Prepare(control, changed, controlBase, changedBase)
    local available, why = self:Available()
    if not available then self.status, self.detail = "BLOCKED", why; return false end
    self.control, self.changed = control, changed
    local a, aError = self:_Read(control)
    local b, bError = self:_Read(changed)
    if not a or not b then self.detail = aError or bError; return false end
    -- Saved baselines are strings; handles are restored separately by LuaMission.
    self.controlBase, self.changedBase = controlBase or self.controlBase or a,
        changedBase or self.changedBase or b
    if #self.controlBase ~= #a or #self.changedBase ~= #b then
        self.status, self.detail = "FAIL", "saved material inventory differs"
        return false
    end
    self.hull = {}
    for i, base in ipairs(self.changedBase) do
        if type(base) ~= "string" or base == "" then
            self.status, self.detail = "FAIL", "invalid material baseline"
            return false
        end
        if base == SXMaterials.HULL then self.hull[#self.hull + 1] = i end
    end
    if #self.hull == 0 then
        self.status, self.detail = "BLOCKED", "scout hull material " .. SXMaterials.HULL .. " not found"
        return false
    end
    for _, color in ipairs(SXMaterials.Colors) do
        local ok, exists = Call(self.exu, "MaterialExists", TintName(color), GROUP)
        if not ok or not exists then
            self.status, self.detail = "BLOCKED", TintName(color) .. " not loaded (sxtint.material)"
            return false
        end
    end
    self.ready, self.status, self.detail = true, "PENDING", "baseline captured; awaiting comparison"
    return true
end

function SXMaterials:_Glow(name, strength)
    local colors = { emissive = { r = strength, g = strength, b = strength, a = 1 } }
    local ok, result = Call(self.exu, "SetMaterialPassColors", name, colors, -1, -1, GROUP, true)
    if not ok or result == false then
        ok, result = Call(self.exu, "SetMaterialPassColors", name, colors, 0, 0, GROUP, true)
    end
    return ok and result ~= false
end

function SXMaterials:_Assign(h, names)
    if not self.valid(h) then return false end
    local all = true
    for i, name in ipairs(names) do
        local ok, result = Call(self.exu, "SetSubEntityMaterial", h, i - 1, name, GROUP)
        local read, actual = Call(self.exu, "GetSubEntityMaterial", h, i - 1)
        all = all and ok and result ~= false and read and actual == name
    end
    return all
end

function SXMaterials:_Matches(h, names)
    local current = self:_Read(h)
    if not current or #current ~= #names then return false end
    for i, name in ipairs(names) do if current[i] ~= name then return false end end
    return true
end

-- Repaint the changed scout's hull. `color` is one of SXMaterials.Colors.
function SXMaterials:Flash(color)
    if not self.ready then return false end
    local tint = TintName(color or "cyan")
    local names = {}
    for i, base in ipairs(self.changedBase) do names[i] = base end
    for _, i in ipairs(self.hull) do names[i] = tint end
    if not self:_Assign(self.changed, names) or not self:_Matches(self.control, self.controlBase) then
        self:Restore()
        self.status, self.detail = "FAIL", "assignment mismatch or control twin changed"
        return false
    end
    if self.tint and self.tint ~= tint then self:_Glow(self.tint, 1) end
    -- A held livery glows at 1.8x so the colour carries at film distance; the pulse
    -- takes over when glow is on.
    if not self.glow then self:_Glow(tint, SXMaterials.FLASH_GLOW) end
    self.tint, self.active = tint, true
    self.status, self.detail = "PASS", "API: hull livery " .. color .. " assigned; control unchanged"
    return true
end
-- Operator `sx service`: the cyan livery with its glow running.
function SXMaterials:Apply() return self:Flash("cyan") and self:SetGlow(true) end

-- Pulsing glow on the current livery: emissive intensity 1x..3x, mission-driven.
function SXMaterials:SetGlow(enabled)
    if enabled and not self.active then return false end
    self.glow = enabled and true or false
    if not enabled and self.tint then return self:_Glow(self.tint, 1) end
    return true
end

function SXMaterials:Pulse(elapsed)
    if not self.active or not self.glow then return end
    local strength = 1 + 2 * (0.5 + 0.5 * math.sin(elapsed * math.pi * 1.5))
    if not self:_Glow(self.tint, strength) then
        self.active, self.status, self.detail = false, "FAIL", "emissive update refused"
        self:Restore()
    end
end

function SXMaterials:Restore()
    local glow = true
    if self.tint then glow = self:_Glow(self.tint, 1) end
    self.active, self.glow, self.tint = false, false, nil
    if not self.changedBase then return true end
    -- Deleted fixtures have no assignments to restore. Still restore survivors.
    local a = not self.valid(self.changed) or self:_Assign(self.changed, self.changedBase)
    local b = not self.valid(self.control) or self:_Assign(self.control, self.controlBase)
    self.restored = a and b and glow
    if not self.restored then self.status, self.detail = "FAIL", "baseline restoration incomplete" end
    return self.restored
end

return SXMaterials
