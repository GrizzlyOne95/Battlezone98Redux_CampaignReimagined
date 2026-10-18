-- Packet string chunking for Lua Send. Redux decodes a packet string's length
-- as a signed byte, so any string over 127 bytes crashes every receiver
-- (access violation at exe+0x430A0E). Pack splits such strings (and strings
-- that already begin with MARK) into MARK..parts followed by <=127-byte chunks;
-- Unpack reassembles them. Pure encoding: callers still call Send themselves.
local CRWire = { CHUNK = 127, MARK = "\2" }
local unpackArgs = table.unpack or unpack
local CHUNK, MARK = CRWire.CHUNK, CRWire.MARK

local function NeedsChunk(v)
    return type(v) == "string" and (#v > CHUNK or v:sub(1, 1) == MARK)
end

function CRWire.Pack(...)
    local n = select("#", ...)
    local any = false
    for i = 1, n do
        if NeedsChunk((select(i, ...))) then any = true; break end
    end
    if not any then return ... end
    local out, m = {}, 0
    for i = 1, n do
        local v = select(i, ...)
        if NeedsChunk(v) then
            local parts = math.max(1, math.ceil(#v / CHUNK))
            m = m + 1; out[m] = MARK .. parts
            for p = 1, parts do m = m + 1; out[m] = v:sub((p - 1) * CHUNK + 1, p * CHUNK) end
        else
            m = m + 1; out[m] = v
        end
    end
    return unpackArgs(out, 1, m)
end

function CRWire.Unpack(...)
    local n = select("#", ...)
    local any = false
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "string" and v:sub(1, 1) == MARK then any = true; break end
    end
    if not any then return ... end
    local out, m, i = {}, 0, 1
    while i <= n do
        local v = select(i, ...)
        local parts = type(v) == "string" and v:sub(1, 1) == MARK and tonumber(v:sub(2))
        local buf
        if parts and parts >= 1 and parts == math.floor(parts) and i + parts <= n then
            buf = {}
            for p = 1, parts do
                local c = select(i + p, ...)
                if type(c) ~= "string" then buf = nil; break end
                buf[p] = c
            end
        end
        if buf then
            m = m + 1; out[m] = table.concat(buf); i = i + parts + 1
        else
            m = m + 1; out[m] = v; i = i + 1
        end
    end
    return unpackArgs(out, 1, m)
end

-- Raises when any string argument would overflow the signed length byte.
-- Test harnesses call this from their Send stubs.
function CRWire.Check(kind, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and #v > CHUNK then
            error(string.format("Send %s arg %d is %d bytes (max %d)", tostring(kind), i, #v, CHUNK), 2)
        end
    end
end

return CRWire
