-- Captured, mission-local overrides. Save data contains names/values, never callbacks.
local SXState = {}
SXState.__index = SXState
local unpackValues = unpack or table.unpack

local function Pack(...) return { n = select("#", ...), ... } end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = Copy(v) end
    return result
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" then return math.abs(a - b) <= 0.0001 end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function SXState.New(exu, valid)
    return setmetatable({ exu = exu, valid = valid, entries = {}, order = {} }, SXState)
end

function SXState:Call(scope, name, args)
    local owner = scope == "stock" and _G or self.exu
    if not owner or (scope ~= "stock" and owner.isStub) or type(owner[name]) ~= "function" then
        return false, "missing " .. name
    end
    return pcall(owner[name], unpackValues(args or {}, 1, (args and args.n) or #(args or {})))
end

function SXState:Capture(id, group, getter, setter, options)
    if self.entries[id] then return true end
    options = options or {}
    local owner = options.scope == "stock" and _G or self.exu
    if not owner or type(owner[setter]) ~= "function" then return false end
    local read = Pack(self:Call(options.scope, getter, options.args))
    if not read[1] or read.n < 2 then return false end
    local values = { n = read.n - 1 }
    for i = 2, read.n do
        if read[i] == nil then return false end
        values[i - 1] = Copy(read[i])
    end
    self.entries[id] = { group = group, scope = options.scope, getter = getter,
        setter = setter, args = Copy(options.args or {}), values = values,
        preserveExternal = options.preserveExternal == true, handle = options.handle == true, changed = false }
    self.order[#self.order + 1] = id
    return true
end

function SXState:Write(id, group, getter, setter, values, options)
    if not self:Capture(id, group, getter, setter, options) then return false end
    local entry = self.entries[id]
    local args = Copy(entry.args)
    local prefix = args.n or #args
    for i, value in ipairs(values) do args[prefix + i] = value end
    args.n = prefix + (values.n or #values)
    entry.changed, entry.expected = true, Copy(values)
    entry.expected.n = entry.expected.n or #values
    local ok, result = self:Call(entry.scope, setter, args)
    if not ok or result == false then return false end
    local read = Pack(self:Call(entry.scope, getter, entry.args))
    if not read[1] then return false end
    local actual = { n = read.n - 1 }
    for i = 2, read.n do actual[i - 1] = read[i] end
    return Equal(entry.expected, actual)
end

function SXState:Restore(group)
    local all = true
    for i = #self.order, 1, -1 do
        local id, entry = self.order[i], self.entries[self.order[i]]
        if entry and (group == nil or entry.group == group) then
            local restore, done = true, true
            if entry.handle and self.valid and not self.valid(entry.args[1]) then restore = false end
            if restore and entry.preserveExternal and entry.changed and entry.expected then
                local read = Pack(self:Call(entry.scope, entry.getter, entry.args))
                if read[1] then
                    local actual = { n = read.n - 1 }
                    for k = 2, read.n do actual[k - 1] = read[k] end
                    -- A real options change after our last write takes precedence.
                    restore = Equal(entry.expected, actual)
                else done = false end
            end
            if restore and done then
                local args = Copy(entry.args)
                local prefix = args.n or #args
                for k = 1, entry.values.n do args[prefix + k] = entry.values[k] end
                args.n = prefix + entry.values.n
                local ok, result = self:Call(entry.scope, entry.setter, args)
                done = ok and result ~= false
                if done then
                    local read = Pack(self:Call(entry.scope, entry.getter, entry.args))
                    local actual = { n = read.n - 1 }
                    for k = 2, read.n do actual[k - 1] = read[k] end
                    done = read[1] and Equal(entry.values, actual)
                end
            end
            if done then self.entries[id] = nil; table.remove(self.order, i)
            else all = false end
        end
    end
    return all
end

function SXState:Snapshot() return { entries = Copy(self.entries), order = Copy(self.order) } end
function SXState:Discard(group)
    for i = #self.order, 1, -1 do
        local id = self.order[i]
        if self.entries[id] and self.entries[id].group == group then
            self.entries[id] = nil; table.remove(self.order, i)
        end
    end
end
function SXState:Load(snapshot)
    self.entries = snapshot and Copy(snapshot.entries) or {}
    self.order = snapshot and Copy(snapshot.order) or {}
end

SXState.Copy, SXState.Equal = Copy, Equal
return SXState
