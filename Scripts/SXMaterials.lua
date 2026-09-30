-- Mission-owned, reversible per-subentity material comparison.
local SXMaterials = {}
SXMaterials.__index = SXMaterials
local REQUIRED = { "GetSubEntityCount", "GetSubEntityMaterial", "MaterialExists",
    "CloneMaterial", "GetMaterialPassColors", "SetMaterialPassColors",
    "SetSubEntityMaterial" }
local GROUP = "General"

local function Call(exu, name, ...)
    if not exu or type(exu[name]) ~= "function" then return false, "missing " .. name end
    return pcall(exu[name], ...)
end

local function CloneName(base)
    local hash = 0
    for i = 1, #base do hash = (hash * 131 + string.byte(base, i)) % 4294967296 end
    return "SX/Livewire/" .. string.format("%08x", hash)
end

function SXMaterials.New(exu, valid)
    return setmetatable({ exu = exu, valid = valid, status = "PENDING",
        detail = "waiting for render entities", active = false, variants = {} }, SXMaterials)
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
    for _, base in ipairs(self.changedBase) do
        if type(base) ~= "string" or base == "" then
            self.status, self.detail = "FAIL", "invalid material baseline"
            return false
        end
        local name = CloneName(base)
        local colorsOk, colors = Call(self.exu, "GetMaterialPassColors", base, 0, 0, GROUP)
        if not colorsOk or type(colors) ~= "table" then
            self.status, self.detail = "BLOCKED", "source pass colors unavailable"
            return false
        end
        local existsOk, exists = Call(self.exu, "MaterialExists", name, GROUP)
        if not existsOk or not exists then
            local cloned, result = Call(self.exu, "CloneMaterial", base, name, GROUP)
            if not cloned or result ~= true then
                self.status, self.detail = "BLOCKED", "clone creation refused"
                return false
            end
        end
        self.variants[base] = { name = name, colors = colors }
    end
    self.ready, self.status, self.detail = true, "PENDING", "baseline captured; awaiting comparison"
    return true
end

function SXMaterials:_SetColors(name, colors, glow)
    local ok, result = Call(self.exu, "SetMaterialPassColors", name, colors, -1, -1, GROUP, glow)
    if not ok or result == false then
        ok, result = Call(self.exu, "SetMaterialPassColors", name, colors, 0, 0, GROUP, glow)
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

function SXMaterials:Apply()
    if not self.ready then return false end
    local names = {}
    for _, base in ipairs(self.changedBase) do
        local variant = self.variants[base]
        local colors = { ambient = { r = 0.10, g = 0.45, b = 0.70, a = 1 },
            diffuse = { r = 0.12, g = 0.65, b = 1.0, a = 1 },
            emissive = { r = 0.02, g = 0.20, b = 0.30, a = 1 } }
        if not self:_SetColors(variant.name, colors, false) then
            self:Restore()
            self.status, self.detail = "FAIL", "service pass colors refused"
            return false
        end
        names[#names + 1] = variant.name
    end
    if not self:_Assign(self.changed, names) or not self:_Matches(self.control, self.controlBase) then
        self:Restore()
        self.status, self.detail = "FAIL", "assignment mismatch or control twin changed"
        return false
    end
    self.active, self.status, self.detail = true, "PASS", "API: service assignments match; control unchanged"
    return true
end

function SXMaterials:Pulse(elapsed)
    if not self.active then return end
    local strength = 0.10 + 0.10 * (0.5 + 0.5 * math.sin(elapsed * math.pi))
    for _, variant in pairs(self.variants) do
        local colors = { emissive = { r = 0.02, g = strength, b = strength * 1.5, a = 1 } }
        if not self:_SetColors(variant.name, colors, true) then
            self.active, self.status, self.detail = false, "FAIL", "emissive update refused"
            self:Restore()
            return
        end
    end
end

function SXMaterials:Restore()
    self.active = false
    if not self.changedBase then return true end
    -- Deleted fixtures have no assignments to restore. Still restore survivors.
    local a = not self.valid(self.changed) or self:_Assign(self.changed, self.changedBase)
    local b = not self.valid(self.control) or self:_Assign(self.control, self.controlBase)
    self.restored = a and b
    if not self.restored then self.status, self.detail = "FAIL", "baseline restoration incomplete" end
    return self.restored
end

return SXMaterials
