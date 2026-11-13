-- Regression coverage for CRWire, the Send string chunker. Redux reads a
-- packet string's length as a signed byte, so a Send string over 127 bytes
-- crashes every receiver. CRWire.Pack must keep every string <= 127 bytes and
-- CRWire.Unpack must restore the original arguments exactly.
local CRWire = assert(loadfile("Scripts/CRWire.lua"))()
local unpackArgs = table.unpack or unpack

local function pack(...) return { n = select("#", ...), ... } end

local function assertWireSafe(t, label)
    for i = 1, t.n do
        local v = t[i]
        assert(type(v) ~= "string" or #v <= CRWire.CHUNK,
            label .. ": packed arg " .. i .. " is " .. (type(v) == "string" and #v or 0) .. " bytes")
    end
end

local function roundTrip(label, ...)
    local original = pack(...)
    local wire = pack(CRWire.Pack(...))
    assertWireSafe(wire, label)
    local back = pack(CRWire.Unpack(unpackArgs(wire, 1, wire.n)))
    assert(back.n == original.n, label .. ": arg count " .. back.n .. " ~= " .. original.n)
    for i = 1, original.n do
        assert(back[i] == original[i], label .. ": arg " .. i .. " differs")
    end
    return wire
end

-- Short packets pass through untouched.
local wire = roundTrip("short", 7, "hello", 3.5, nil, true)
assert(wire.n == 5 and wire[2] == "hello", "short packet must not be rewritten")
assert(select("#", CRWire.Pack()) == 0, "empty pack")
assert(select("#", CRWire.Unpack()) == 0, "empty unpack")

-- Boundary lengths.
roundTrip("127", string.rep("a", 127))
wire = roundTrip("128", string.rep("b", 128))
assert(wire[1] == CRWire.MARK .. "2", "128 bytes splits into two chunks")
roundTrip("254", string.rep("c", 254))
roundTrip("255", string.rep("d", 255))
roundTrip("300", string.rep("e", 300))

-- A leading marker byte is escaped even when short.
wire = roundTrip("marker", CRWire.MARK .. "x")
assert(wire[1] == CRWire.MARK .. "1", "leading marker is escaped as one chunk")
roundTrip("bare marker", CRWire.MARK)

-- Mixed arguments, with nils and numbers around several long strings.
local objective = string.rep("Destroy the Soviet relay before it calls reinforcements. ", 4)
roundTrip("mixed", 12, "objective", 30, nil, objective, nil, 0, string.rep("z", 400), "tail", nil)

-- A malformed marker passes through instead of raising.
local bad = pack(CRWire.Unpack(CRWire.MARK .. "9", "only one"))
assert(bad.n == 2 and bad[1] == CRWire.MARK .. "9", "truncated chunk run passes through")
bad = pack(CRWire.Unpack(CRWire.MARK .. "zz", "x"))
assert(bad[1] == CRWire.MARK .. "zz", "non-numeric part count passes through")

-- Check accepts wire-safe arguments and rejects oversized strings.
CRWire.Check("E", 1, string.rep("a", 127), nil)
assert(not pcall(CRWire.Check, "E", string.rep("a", 128)), "Check rejects 128 bytes")

-- Every mission send that carries text must be routed through CRWire.Pack.
local scanned, offenders = 0, {}
local listing = assert(io.popen("ls Scripts"))
for name in listing:lines() do
    local path = "Scripts/" .. name
    local f = name:match("%.lua$") and io.open(path, "rb")
    if f then
        scanned = scanned + 1
        local n = 0
        for line in f:lines() do
            n = n + 1
            local kind = line:match('Send%s*%(%s*[^,]+,%s*"([EC])"%s*,')
            if kind and not line:find("CRWire.Pack", 1, true)
                and not (kind == "C" and line:find('"C".*,%s*""%s*[,)]')) then
                offenders[#offenders + 1] = path .. ":" .. n
            end
        end
        f:close()
    end
end
listing:close()
assert(scanned > 0, "no Scripts/*.lua found; run from the repository root")
assert(#offenders == 0, "E/C Send without CRWire.Pack: " .. table.concat(offenders, ", "))

print("CRWire tests passed (" .. scanned .. " scripts scanned)")
