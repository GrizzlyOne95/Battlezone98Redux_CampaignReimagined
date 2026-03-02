-- AutoSave.lua
---@diagnostic disable: lowercase-global, undefined-global, undefined-field
-- Programmatic Save File Synthesis for Battlezone 98 Redux
-- Generates .sav files using bzfile I/O to enable true auto-save

local bzfile = require("bzfile")
local exu = require("exu")
local bit = require("bit")

-- ---------------------------------------------------------------------------
-- BZN Parser Integration (reads AiPaths from the mission BZN file)
-- ---------------------------------------------------------------------------
local BZN_Open
do
    local function GetClassLabelFromODF(odfname)
        local odf = OpenODF(odfname)
        if not odf then return nil end
        local label, found = GetODFString(odf, "GameObjectClass", "classLabel")
        if found then return label end
        return nil
    end

    local function parseFloatLE(str, offset)
        offset = (offset or 0) + 1
        if offset + 3 > #str then return 0 end
        local b1, b2, b3, b4 = str:byte(offset, offset + 3)
        local sign = bit.band(bit.rshift(b4, 7), 0x1)
        local exponent = bit.bor(bit.lshift(bit.band(b4, 0x7F), 1), bit.rshift(b3, 7))
        local mantissa = bit.bor(bit.lshift(bit.band(b3, 0x7F), 16), bit.lshift(bit.band(b2, 0xFF), 8),
            bit.band(b1, 0xFF))
        if exponent == 0 then
            return 0.0
        elseif exponent == 255 then
            return 0.0
        else
            return ((-1) ^ sign) * (1 + mantissa / 2 ^ 23) * 2 ^ (exponent - 127)
        end
    end

    local function splitMax(str, sep, max)
        local result = {}
        local start = 1
        local splits = 0
        max = max or math.huge
        while splits < max - 1 do
            local s, e = string.find(str, sep, start, true)
            if not s then break end
            table.insert(result, string.sub(str, start, s - 1))
            start = e + 1
            splits = splits + 1
        end
        table.insert(result, string.sub(str, start))
        return result
    end

    local function SmartStringSplit(input, count)
        if not input then return {} end
        local trimmed = input:match("^%s*(.*)$")
        local leadingSpaceCount = #input - #trimmed
        local retVal = splitMax(trimmed, " ", count)
        retVal[1] = string.rep(" ", leadingSpaceCount) .. retVal[1]
        return retVal
    end

    local BZNTokenBinary = {}
    BZNTokenBinary.__index = BZNTokenBinary
    function BZNTokenBinary.new(t, d) return setmetatable({ type = t, data = d }, BZNTokenBinary) end

    function BZNTokenBinary:Validate(n, t) return not self.type or self.type == t end

    function BZNTokenBinary:GetBoolean(i) return self.data:byte((i or 0) + 1) ~= 0 end

    function BZNTokenBinary:GetInt32(i)
        local o = (i or 0) * 4 + 1; local b1, b2, b3, b4 = self.data:byte(o, o + 3)
        if not b1 then return 0 end
        return (b4 or 0) * 0x1000000 + (b3 or 0) * 0x10000 + (b2 or 0) * 0x100 + (b1 or 0)
    end

    function BZNTokenBinary:GetUInt32(i) return self:GetInt32(i) end

    function BZNTokenBinary:GetUInt32H(i) return self:GetInt32(i) end

    function BZNTokenBinary:GetInt16(i)
        local o = (i or 0) * 2 + 1; local b1, b2 = self.data:byte(o, o + 1); if not b1 then return 0 end; return b2 *
            0x100 + b1
    end

    function BZNTokenBinary:GetUInt16(i) return self:GetInt16(i) end

    function BZNTokenBinary:GetSingle(i) return parseFloatLE(self.data, (i or 0) * 4) end

    function BZNTokenBinary:GetString(i)
        local nul = self.data:find("\0", 1, true)
        return nul and self.data:sub(1, nul - 1) or self.data
    end

    function BZNTokenBinary:GetVector3D(i)
        local b = (i or 0) * 3
        return SetVector(self:GetSingle(b), self:GetSingle(b + 1), self:GetSingle(b + 2))
    end

    function BZNTokenBinary:GetVector2D(i)
        local b = (i or 0) * 2
        return SetVector(self:GetSingle(b), 0, self:GetSingle(b + 1))
    end

    function BZNTokenBinary:GetMatrixOld(i)
        local b = (i or 0) * 4
        local r, u, f, p = self:GetVector3D(b), self:GetVector3D(b + 1), self:GetVector3D(b + 2), self:GetVector3D(b + 3)
        return SetMatrix(r.x, r.y, r.z, u.x, u.y, u.z, f.x, f.y, f.z, p.x, p.y, p.z)
    end

    function BZNTokenBinary:GetEuler(i) return BZNTokenNull.new():GetEuler() end

    local BZNTokenString = {}
    BZNTokenString.__index = BZNTokenString
    function BZNTokenString.new(n, v) return setmetatable({ name = n, values = v }, BZNTokenString) end

    function BZNTokenString:Validate(n, t) return self.name == n end

    function BZNTokenString:IsBinary() return false end

    function BZNTokenString:GetCount() return #self.values end

    function BZNTokenString:GetBoolean(i)
        local v = self.values[(i or 0) + 1]; return v == "1" or v == "true"
    end

    function BZNTokenString:GetInt32(i) return tonumber(self.values[(i or 0) + 1]) or 0 end

    function BZNTokenString:GetUInt32(i) return self:GetInt32(i) end

    function BZNTokenString:GetInt16(i) return tonumber(self.values[(i or 0) + 1]) or 0 end

    function BZNTokenString:GetUInt16(i) return self:GetInt16(i) end

    function BZNTokenString:GetUInt32H(i)
        local v = self.values[(i or 0) + 1]
        if not v then return 0 end
        if v:sub(1, 1) == '-' then return tonumber(v:sub(2), 16) or 0 end
        return tonumber(v, 16) or 0
    end

    function BZNTokenString:GetSingle(i) return tonumber(self.values[(i or 0) + 1]) or 0 end

    function BZNTokenString:GetString(i) return self.values[(i or 0) + 1] or "" end

    function BZNTokenString:GetVector3D(i) return SetVector(self:GetSingle(i), 0, 0) end

    function BZNTokenString:GetVector2D(i) return SetVector(self:GetSingle(i), 0, 0) end

    function BZNTokenString:GetMatrixOld(i) return SetMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0) end

    function BZNTokenString:GetEuler(i) return BZNTokenNull.new():GetEuler() end

    local BZNTokenNestedString = {}
    BZNTokenNestedString.__index = BZNTokenNestedString
    function BZNTokenNestedString.new(n, v) return setmetatable({ name = n, values = v }, BZNTokenNestedString) end

    function BZNTokenNestedString:Validate(n, t) return self.name == n end

    function BZNTokenNestedString:IsBinary() return false end

    function BZNTokenNestedString:GetCount() return #self.values end

    function BZNTokenNestedString:GetBoolean(i) return false end

    function BZNTokenNestedString:GetInt32(i) return 0 end

    function BZNTokenNestedString:GetUInt32(i) return 0 end

    function BZNTokenNestedString:GetUInt32H(i) return 0 end

    function BZNTokenNestedString:GetInt16(i) return 0 end

    function BZNTokenNestedString:GetUInt16(i) return 0 end

    function BZNTokenNestedString:GetSingle(i) return 0 end

    function BZNTokenNestedString:GetString(i) return "" end

    function BZNTokenNestedString:GetVector3D(i)
        local s = self.values[(i or 0) + 1]
        if not s then return SetVector(0, 0, 0) end
        return SetVector(s[1] and s[1]:GetSingle() or 0, s[2] and s[2]:GetSingle() or 0, s[3] and s[3]:GetSingle() or 0)
    end

    function BZNTokenNestedString:GetVector2D(i)
        local s = self.values[(i or 0) + 1]
        if not s then return SetVector(0, 0, 0) end
        return SetVector(s[1] and s[1]:GetSingle() or 0, 0, s[2] and s[2]:GetSingle() or 0)
    end

    function BZNTokenNestedString:GetEuler(i)
        local s = self.values[(i or 0) + 1]
        if not s then return BZNTokenNull.new():GetEuler() end
        return {
            mass = s[1] and s[1]:GetSingle() or 0,
            mass_inv = s[2] and s[2]:GetSingle() or 0,
            v_mag = s[3] and s[3]:GetSingle() or 0,
            v_mag_inv = s[4] and s[4]:GetSingle() or 0,
            I = s[5] and s[5]:GetSingle() or 0,
            I_inv = s[6] and s[6]:GetSingle() or 0,
            v = s[7] and s[7]:GetVector3D() or SetVector(0, 0, 0),
            omega = s[8] and s[8]:GetVector3D() or SetVector(0, 0, 0),
            Accel = s[9] and s[9]:GetVector3D() or SetVector(0, 0, 0)
        }
    end

    function BZNTokenNestedString:GetMatrixOld(i)
        local s = self.values[(i or 0) + 1]
        if s and #s >= 12 then
            local function gs(idx) return s[idx] and s[idx]:GetSingle() or 0 end
            return SetMatrix(gs(1), gs(2), gs(3), gs(4), gs(5), gs(6), gs(7), gs(8), gs(9), gs(10), gs(11), gs(12))
        end
        return SetMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
    end

    local BZNTokenValidation = {}
    BZNTokenValidation.__index = BZNTokenValidation
    function BZNTokenValidation.new(n) return setmetatable({ name = n }, BZNTokenValidation) end

    function BZNTokenValidation:Validate(n, t) return self.name == n end

    function BZNTokenValidation:IsBinary() return false end

    function BZNTokenValidation:GetBoolean() return false end

    function BZNTokenValidation:GetInt32() return 0 end

    function BZNTokenValidation:GetUInt32() return 0 end

    function BZNTokenValidation:GetUInt32H() return 0 end

    function BZNTokenValidation:GetInt16() return 0 end

    function BZNTokenValidation:GetUInt16() return 0 end

    function BZNTokenValidation:GetSingle() return 0 end

    function BZNTokenValidation:GetString() return "" end

    function BZNTokenValidation:GetVector3D() return SetVector(0, 0, 0) end

    function BZNTokenValidation:GetVector2D() return SetVector(0, 0, 0) end

    function BZNTokenValidation:GetMatrixOld() return SetMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0) end

    function BZNTokenValidation:GetEuler() return BZNTokenNull.new():GetEuler() end

    local BZNTokenNull = {}
    BZNTokenNull.__index = BZNTokenNull
    function BZNTokenNull.new() return setmetatable({}, BZNTokenNull) end

    function BZNTokenNull:IsBinary() return false end

    function BZNTokenNull:GetBoolean() return false end

    function BZNTokenNull:GetInt32() return 0 end

    function BZNTokenNull:GetUInt32() return 0 end

    function BZNTokenNull:GetUInt32H() return 0 end

    function BZNTokenNull:GetInt16() return 0 end

    function BZNTokenNull:GetUInt16() return 0 end

    function BZNTokenNull:GetSingle() return 0 end

    function BZNTokenNull:GetString() return "" end

    function BZNTokenNull:GetVector3D() return SetVector(0, 0, 0) end

    function BZNTokenNull:GetVector2D() return SetVector(0, 0, 0) end

    function BZNTokenNull:GetMatrixOld() return SetMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0) end

    function BZNTokenNull:GetEuler()
        return {
            mass = 0,
            mass_inv = 0,
            v_mag = 0,
            v_mag_inv = 0,
            I = 0,
            I_inv = 0,
            v = SetVector(0, 0, 0),
            omega = SetVector(0, 0, 0),
            Accel = SetVector(0, 0, 0)
        }
    end

    function BZNTokenNull:Validate(n, t) return false end

    local Tokenizer = {}
    Tokenizer.__index = Tokenizer
    function Tokenizer.new(d)
        return setmetatable({
            data = d,
            pos = 1,
            type_size = 2,
            size_size = 2,
            complex_map = { points = 2, pos = 3, v = 3, omega = 3, Accel = 3, euler = 9, transform = 12 },
            nullToken = BZNTokenNull.new()
        }, Tokenizer)
    end

    function Tokenizer:atEnd() return self.pos > #self.data end

    function Tokenizer:inBinary() return self.binary_offset and self.pos >= self.binary_offset end

    function Tokenizer:ReadStringLine()
        if self:atEnd() then return "" end
        local s, e = self.data:find("[\r\n]+", self.pos)
        local line = self.data:sub(self.pos, (s or #self.data + 1) - 1)
        self.pos = e and e + 1 or #self.data + 1
        return line
    end

    function Tokenizer:ReadStringValueToken(rawLine)
        if not rawLine:match(" =$") and not rawLine:find(" = ") and rawLine:find("=") then
            rawLine = rawLine:gsub("=", " = ")
        end
        local line = SmartStringSplit(rawLine, 4)
        if line[2] == "=" then
            line = splitMax(rawLine, " ", 3)
            local name = line[1]
            local countIndented = 0
            local offsetStart = self.pos
            local indent = 0
            while true do
                local nextLine = self:ReadStringLine()
                if nextLine:match("^ +") and nextLine:find("=") then
                    local _, i = nextLine:find("^ +")
                    if i then
                        if indent == 0 then indent = i end
                        if i == indent then
                            countIndented = countIndented + 1
                        else
                            self.pos = offsetStart; break
                        end
                    else
                        self.pos = offsetStart; break
                    end
                else
                    self.pos = offsetStart; break
                end
            end
            if countIndented == 0 and self.complex_map[name] then countIndented = self.complex_map[name] end
            if countIndented > 0 then
                local values = { {} }
                for i = 1, countIndented do
                    values[1][i] = self:ReadStringValueToken(self:ReadStringLine():match("^%s*(.*)$"))
                end
                return BZNTokenNestedString.new(name, values)
            else
                local val = line[3] or ""
                return BZNTokenString.new(name, { val:match('^"(.-)"$') or val })
            end
        elseif line[3] == "=" then
            local name = line[1]
            local count = tonumber(line[2]:match("%[(%d+)%]")) or 0
            if count == 0 then return BZNTokenString.new(name, {}) end
            local countIndented = 0
            local offsetStart = self.pos
            local indent = 0
            countIndented = self.complex_map[name] or countIndented
            if countIndented > 0 then
                local values = {}
                for i = 1, count do
                    values[i] = {}
                    for j = 1, countIndented do
                        values[i][j] = self:ReadStringValueToken(self:ReadStringLine():match("^%s*(.*)$"))
                    end
                end
                return BZNTokenNestedString.new(name, values)
            else
                local values = {}
                for i = 1, count do values[i] = self:ReadStringLine():match("^%s*(.*)$") end
                return BZNTokenString.new(name, values)
            end
        end
        return self.nullToken
    end

    function Tokenizer:ReadStringToken()
        while not self:atEnd() do
            local line = self:ReadStringLine()
            if #line > 0 then
                if line:sub(1, 1) == "[" then return BZNTokenValidation.new(line:sub(2, -2)) end
                return self:ReadStringValueToken(line)
            end
        end
        return self.nullToken
    end

    function Tokenizer:ReadBinaryToken()
        if self:atEnd() then return self.nullToken end
        local t = self.data:byte(self.pos); self.pos = self.pos + self.type_size
        local s = self.data:byte(self.pos) + bit.lshift(self.data:byte(self.pos + 1), 8); self.pos = self.pos +
            self.size_size
        local v = self.data:sub(self.pos, self.pos + s - 1); self.pos = self.pos + s
        return BZNTokenBinary.new(t, v)
    end

    function Tokenizer:ReadToken() return self:inBinary() and self:ReadBinaryToken() or self:ReadStringToken() end

    BZN_Open = function(name)
        local filedata = UseItem(name)
        if not filedata then
            print("AutoSave: Could not load BZN file: " .. tostring(name)); return nil
        end
        local reader = Tokenizer.new(filedata)
        local bzn = { AiPaths = {} }
        local tok = reader:ReadToken()
        if not tok or not tok:Validate("version") then return nil end
        bzn.version = tok:GetInt32(); reader.version = bzn.version
        while not reader:atEnd() do
            local tok = reader:ReadToken()
            if tok:Validate("AiPaths") then
                local tok_count = reader:ReadToken()
                local countPaths = tok_count:GetInt32()
                for i = 1, countPaths do
                    local p = {}
                    if not reader:inBinary() then reader:ReadToken() end -- Skip [AiPath]
                    reader:ReadToken()                                   -- old_ptr
                    local tok_sz = reader:ReadToken()
                    if tok_sz:GetInt32() > 0 then p.label = reader:ReadToken():GetString() end
                    local tok_pc = reader:ReadToken()
                    local pc = tok_pc:GetInt32()
                    if pc > 0 then
                        p.points = {}
                        local tok_pts = reader:ReadToken()
                        for j = 1, pc do p.points[j] = tok_pts:GetVector2D(j - 1) end
                    end
                    p.pathType = reader:ReadToken():GetUInt32H()
                    table.insert(bzn.AiPaths, p)
                end
                break
            end
        end
        return bzn
    end
end

-- ---------------------------------------------------------------------------
-- AutoSave Module
-- ---------------------------------------------------------------------------
local AutoSave = {}
AutoSave.ActiveObjectives = {}
AutoSave.Config = { enabled = true, autoSaveInterval = 300, currentSlot = 1 }
AutoSave.timer = 0

-- ---------------------------------------------------------------------------
-- Helper: Convert a string to hex, with optional null-terminator padding
-- null_extra = number of extra \0 bytes to append (for msg/lastMsg fields)
-- ---------------------------------------------------------------------------
function AutoSave._ToHex(str, null_extra)
    if not str then return "" end
    local s = str .. "\0" .. string.rep("\0", null_extra or 0)
    local hex = ""
    for i = 1, #s do
        hex = hex .. string.format("%02x", s:byte(i))
    end
    return hex
end

-- ---------------------------------------------------------------------------
-- Helper to convert integers to 8-character hex strings
-- ---------------------------------------------------------------------------
local function ToHex(val)
    return string.format("%08X", val or 0)
end

-- ---------------------------------------------------------------------------
-- Helper: Convert raw handle to 8-char uppercase hex string
-- ---------------------------------------------------------------------------
local function HandleToHex(h)
    if not h then return "00000000" end
    local n = tonumber(tostring(h), 16) or 0
    local hex = string.format("%X", n)
    return string.rep("0", 8 - #hex) .. hex
end

-- ---------------------------------------------------------------------------
-- Helper: Convert raw handle to signed 32-bit decimal integer (for himHandle)
-- ---------------------------------------------------------------------------
local function HandleToSignedDec(h)
    if not h or not IsValid(h) then return "0" end
    local v = tonumber(tostring(h), 16) or 0
    if v > 0x7FFFFFFF then v = v - 0x100000000 end
    return tostring(v)
end

-- ---------------------------------------------------------------------------
-- Helper: Compute alliance bitmask for a team
-- ---------------------------------------------------------------------------
local function GetAllyMask(team)
    local mask = 0
    for i = 0, 15 do
        if IsTeamAllied(team, i) then
            mask = mask + bit.lshift(1, i)
        end
    end
    return mask
end

-- ---------------------------------------------------------------------------
-- Helper: Safe number-to-string that avoids Lua platform-specific inf/nan
-- ---------------------------------------------------------------------------
local function NumToStr(n)
    if not n then return "0" end
    if n ~= n then return "0" end -- NaN
    if n == math.huge then return "1e+030" end
    if n == -math.huge then return "-1e+030" end
    -- Use 6 decimal places for floating point values; this matches the
    -- typical output of the engine's ASCII save and saves space/precision.
    local s = string.format("%.6g", n)
    -- Ensure "1e+030" or "0" format as needed
    if n > 1e20 then return "1e+030" end -- Covers math.huge, but also very large numbers
    if n == 0 then return "0" end
    return s
end

-- ---------------------------------------------------------------------------
-- Helper: Determine if a value should be serialized (skip handles/functions)
-- ---------------------------------------------------------------------------
local function IsSerializable(v)
    local t = type(v)
    return t == "boolean" or t == "number" or t == "string" or t == "table" or t == "userdata"
    -- Nil is naturally excluded by pairs() iteration.
    -- Handles are included and serialized as type 2.
end

-- ---------------------------------------------------------------------------
-- _WriteLuaValue: Serialize a Lua value to the save file format.
-- Called recursively for nested tables.
-- ---------------------------------------------------------------------------
function AutoSave._WriteLuaValue(file, name, value, indent)
    local prefix = string.rep("  ", indent or 0)
    if type(value) == "boolean" then
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "1")
        file:Writeln(prefix .. "b [1] =")
        file:Writeln(prefix .. tostring(value))
    elseif type(value) == "number" then
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "3")
        file:Writeln(prefix .. "f [1] =")
        file:Writeln(prefix .. NumToStr(value))
    elseif type(value) == "string" then
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "4")
        file:Writeln(prefix .. "l [1] =")
        file:Writeln(prefix .. tostring(#value))
        file:Writeln(prefix .. "s = " .. value)
    elseif type(value) == "table" then
        -- Pre-count only serializable key-value pairs
        local count = 0
        for k, v in pairs(value) do
            if IsSerializable(k) and IsSerializable(v) then
                count = count + 1
            end
        end
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "5")
        file:Writeln(prefix .. "count [1] =")
        file:Writeln(prefix .. tostring(count))
        for k, v in pairs(value) do
            if IsSerializable(k) and IsSerializable(v) then
                AutoSave._WriteLuaValue(file, nil, k, 0)
                AutoSave._WriteLuaValue(file, nil, v, 0)
            end
        end
    elseif type(value) == "userdata" then
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "2")
        file:Writeln(prefix .. "h [1] =")
        file:Writeln(prefix .. HandleToSignedDec(value))
    end
    -- functions are silently skipped.
end

-- ---------------------------------------------------------------------------
-- _GetPlayerSide
-- ---------------------------------------------------------------------------
function AutoSave._GetPlayerSide()
    local h = GetPlayerHandle()
    if h then
        local odf = GetOdf(h):lower()
        if odf:find("^av") or odf:find("^ab") then return "usa" end
        if odf:find("^sv") or odf:find("^sb") then return "soviet" end
        if odf:find("^cv") or odf:find("^cb") then return "blackdog" end
    end
    return "usa"
end

-- ---------------------------------------------------------------------------
-- CreateSave: Write a save file to the given slot
-- Backs up any existing save to game<slot>.bak before overwriting.
-- ---------------------------------------------------------------------------
function AutoSave.CreateSave(slot, desc)
    local slotNum = slot or AutoSave.Config.currentSlot
    local saveDir = bzfile.GetWorkingDirectory() .. "\\Save\\"
    local filename = saveDir .. "game" .. slotNum .. ".sav"
    local backupname = saveDir .. "game" .. slotNum .. ".bak"

    -- Backup existing save before overwriting it, but only if no .bak exists yet
    -- (preserves the original manual save; never overwrites a previous backup)
    local bakCheck = bzfile.Open(backupname, "r")
    if bakCheck then
        bakCheck:Close()
        print("AutoSave: backup already exists, skipping backup of " .. filename)
    else
        local existing = bzfile.Open(filename, "r")
        if existing then
            local data = existing:Read()
            existing:Close()
            if data and #data > 0 then
                local bak = bzfile.Open(backupname, "w", "trunc")
                if bak then
                    bak:Write(data)
                    bak:Close()
                    print("AutoSave: backed up existing save to " .. backupname)
                else
                    print("AutoSave: WARNING - could not open backup file for writing: " .. backupname)
                end
            end
        end
    end

    local file = bzfile.Open(filename, "w", "trunc")
    if not file then return false end
    AutoSave._WriteSaveFile(file, desc)
    file:Close()
    return true
end

-- ---------------------------------------------------------------------------
-- Update: Called every game tick; triggers periodic autosaves
-- ---------------------------------------------------------------------------
function AutoSave.Update(dtime)
    if not AutoSave.Config.enabled then return end
    local now = GetTime()
    if not AutoSave._lastSaveTime then AutoSave._lastSaveTime = now end
    if (now - AutoSave._lastSaveTime) >= AutoSave.Config.autoSaveInterval then
        local missionName = GetMissionFilename():gsub("%.bzn$", "")
        local missionTime = math.floor(now)
        print("AutoSave: saving at " .. missionTime .. "s")
        AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime))
        AutoSave._lastSaveTime = now
    end
end

-- ---------------------------------------------------------------------------
-- _WriteSaveFile: Core save file writer
-- ---------------------------------------------------------------------------
function AutoSave._WriteSaveFile(file, desc)
    local missionFilename = GetMissionFilename()
    local terrainName     = missionFilename:gsub("%.bzn$", "")
    local currentTime     = GetTime()
    local playerHandle    = GetPlayerHandle()

    -- -----------------------------------------------------------------------
    -- Path Data (required for ID calculation)
    -- -----------------------------------------------------------------------
    local bznData         = BZN_Open(missionFilename)
    local aiPaths         = (bznData and bznData.AiPaths) or {}

    -- -----------------------------------------------------------------------
    -- Pass 1: Enumerate all valid objects and assign sequential seqnos.
    -- seqno is a monotonically increasing engine counter (not the raw handle).
    -- We assign 1-based sequential IDs; the player gets seqno 1.
    -- -----------------------------------------------------------------------
    local orderedHandles  = {}
    local seqnoMap        = {} -- handle string -> integer seqno
    local seqCounter      = 0

    -- Player first (always seqno = 1 in reference saves)
    if playerHandle and IsValid(playerHandle) then
        seqCounter = seqCounter + 1
        local hs = tostring(playerHandle)
        seqnoMap[hs] = seqCounter
        orderedHandles[#orderedHandles + 1] = playerHandle
    end

    for h in AllObjects() do
        if IsValid(h) and h ~= playerHandle then
            seqCounter = seqCounter + 1
            local hs = tostring(h)
            seqnoMap[hs] = seqCounter
            orderedHandles[#orderedHandles + 1] = h
        end
    end

    local objCount = #orderedHandles

    -- -----------------------------------------------------------------------
    -- Sequential ID Assignment (Interleaved)
    -- -----------------------------------------------------------------------
    local globalID = 1
    local objAddrMap = {}
    local processMap = {} -- h -> processID
    local missionList = {}

    local function GetProcessName(h)
        if h == playerHandle then return "UserProcess" end
        local odf = string.lower(GetOdf(h))
        if odf:find("svmuf") then return "MUFEnemy" end
        if odf:find("avmuf") then return "MUFFriend" end
        if odf:find("avrecy") then return "RecyclerFriend" end
        if odf:find("svrecy") then return "RecyclerEnemy" end
        if odf:find("svturr") then return "TurretTankEnemy" end
        if odf:find("svfigh") or odf:find("avfigh") then
            return GetTeamNum(h) == 1 and "ScoutFriend" or "ScoutEnemy"
        end
        if odf:find("svscav") then return "ScavengerEnemy" end
        if odf:find("pilo") then
            return GetTeamNum(h) == 1 and "SoldierFriend" or "SoldierEnemy"
        end
        return nil
    end

    for _, h in ipairs(orderedHandles) do
        objAddrMap[h] = globalID
        globalID = globalID + 1

        local pName = GetProcessName(h)
        if pName then
            processMap[h] = globalID
            table.insert(missionList, { name = pName, sObject = globalID, fOwner = objAddrMap[h], h = h })
            globalID = globalID + 1
        end
    end

    -- Assign mission ID
    local missionID = globalID
    globalID = globalID + 2 -- Skip 2 (likely AiMission + Mission?)

    -- Assign task IDs
    local taskMap = {}
    local taskObjects = {}
    for _, h in ipairs(orderedHandles) do
        if h ~= playerHandle and IsValid(h) then
            if IsCraft(h) or IsPerson(h) then
                table.insert(taskObjects, h)
                taskMap[h] = globalID
                globalID = globalID + 1
            end
        end
    end

    local pathIDStart = globalID

    -- -----------------------------------------------------------------------
    -- Header
    -- -----------------------------------------------------------------------
    file:Writeln("version [1] =")
    file:Writeln("2016")
    file:Writeln("binarySave [1] =")
    file:Writeln("false")
    file:Writeln("msn_filename = " .. missionFilename)
    file:Writeln("seq_count [1] =")
    file:Writeln(tostring(math.max(globalID + #taskObjects + #aiPaths, 504)))
    file:Writeln("missionSave [1] =")
    file:Writeln("false")
    file:Writeln("runType [1] =")
    file:Writeln("0")
    file:Writeln("saveGameDesc = " .. AutoSave._ToHex(desc or (terrainName .. " AutoSave"), 1))
    file:Writeln("nPlayerSide = " .. AutoSave._GetPlayerSide())
    file:Writeln("nMissionStatus [1] =")
    file:Writeln("0")
    file:Writeln("nOldMissionMode [1] =")
    file:Writeln("0")
    file:Writeln("TerrainName = " .. terrainName)
    file:Writeln("start_time [1] =")
    file:Writeln(string.format("%.3f", currentTime))
    file:Writeln("size [1] =")
    file:Writeln(tostring(objCount))

    -- -----------------------------------------------------------------------
    -- [GameObject] section
    -- -----------------------------------------------------------------------
    for _, h in ipairs(orderedHandles) do
        local isPlayer = (h == playerHandle)
        local obj_addr = objAddrMap[h]
        local seqno    = seqnoMap[tostring(h)] or 0
        local pos      = GetPosition(h)
        local team     = GetTeamNum(h)

        file:Writeln("[GameObject]")
        file:Writeln("PrjID [1] =")
        file:Writeln(GetOdf(h))
        file:Writeln("seqno [1] =")
        file:Writeln(tostring(seqno))
        file:Writeln("pos [1] =")
        file:Writeln("  x [1] ="); file:Writeln(NumToStr(pos.x))
        file:Writeln("  y [1] ="); file:Writeln(NumToStr(pos.y))
        file:Writeln("  z [1] ="); file:Writeln(NumToStr(pos.z))
        file:Writeln("team [1] =")
        file:Writeln(tostring(team))
        file:Writeln("label = " .. (GetLabel(h) or ""))
        file:Writeln("isUser [1] =")
        file:Writeln(isPlayer and "1" or "0")
        -- obj_addr should be the sequential ID (hex)
        file:Writeln(string.format("obj_addr = %08X", obj_addr))

        -- Transform matrix
        local t = GetTransform(h)
        file:Writeln("transform [1] =")
        file:Writeln("  right_x [1] ="); file:Writeln(NumToStr(t.right_x))
        file:Writeln("  right_y [1] ="); file:Writeln(NumToStr(t.right_y))
        file:Writeln("  right_z [1] ="); file:Writeln(NumToStr(t.right_z))
        file:Writeln("  up_x [1] ="); file:Writeln(NumToStr(t.up_x))
        file:Writeln("  up_y [1] ="); file:Writeln(NumToStr(t.up_y))
        file:Writeln("  up_z [1] ="); file:Writeln(NumToStr(t.up_z))
        file:Writeln("  front_x [1] ="); file:Writeln(NumToStr(t.front_x))
        file:Writeln("  front_y [1] ="); file:Writeln(NumToStr(t.front_y))
        file:Writeln("  front_z [1] ="); file:Writeln(NumToStr(t.front_z))
        file:Writeln("  posit_x [1] ="); file:Writeln(NumToStr(t.posit_x))
        file:Writeln("  posit_y [1] ="); file:Writeln(NumToStr(t.posit_y))
        file:Writeln("  posit_z [1] ="); file:Writeln(NumToStr(t.posit_z))

        -- Logic for Craft vs Building fields
        local isCraft = IsCraft(h) or IsPerson(h)
        local isBuilding = not isCraft
        local odf = string.lower(GetOdf(h) or "")
        local isFactory = odf:find("svmuf") or odf:find("avmuf")

        -- Cache ODF for factory to read deploy times
        local factoryODF = nil
        if isFactory then
            factoryODF = OpenODF(odf)
        end

        if isFactory then
            local timeDeploy = factoryODF and GetODFFloat(factoryODF, nil, "timeDeploy", 5) or 5
            local timeUndeploy = factoryODF and GetODFFloat(factoryODF, nil, "timeUndeploy", 5) or 5
            file:Writeln("timeDeploy [1] ="); file:Writeln(NumToStr(timeDeploy))
            file:Writeln("timeUndeploy [1] ="); file:Writeln(NumToStr(timeUndeploy))
        elseif isCraft then
            file:Writeln("abandoned [1] =")
            file:Writeln("0")
            file:Writeln("cloakState = 00000000")
            file:Writeln("cloakTransBeginTime [1] =")
            file:Writeln("0")
            file:Writeln("cloakTransEndTime [1] =")
            file:Writeln("0")
        else
            -- Buildings have tempBuilding instead of craft fields
            file:Writeln("tempBuilding [1] =")
            file:Writeln("false")
        end

        -- illumination: factories should be 0, scrap should be 0, craft should be 1
        local isScrap = odf:find("sscr")
        if isFactory then
            file:Writeln("illumination [1] =")
            file:Writeln("0")
        elseif isScrap then
            file:Writeln("illumination [1] =")
            file:Writeln("0")
        else
            file:Writeln("illumination [1] =")
            file:Writeln("1")
        end

        -- FIX #2: Second pos block (physics centre-of-mass position)
        -- Slightly offset from the visual transform position; we use the
        -- same value since we cannot read the physics CoM from Lua.
        file:Writeln("pos [1] =")
        file:Writeln("  x [1] ="); file:Writeln(NumToStr(t.posit_x))
        file:Writeln("  y [1] ="); file:Writeln(NumToStr(t.posit_y))
        file:Writeln("  z [1] ="); file:Writeln(NumToStr(t.posit_z))

        -- Euler physics block
        local m         = (exu and exu.GetMass and exu.GetMass(h)) or 1500
        local mass_inv  = (m > 0 and (1 / m) or 1e+030)
        local v         = GetVelocity(h) or SetVector(0, 0, 0)
        local vm        = math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2)
        local v_mag_inv = (vm > 0 and (1 / vm) or 1e+030)
        local omega     = GetOmega(h) or SetVector(0, 0, 0)
        file:Writeln("euler =")
        file:Writeln(" mass [1] ="); file:Writeln(NumToStr(m))
        file:Writeln(" mass_inv [1] ="); file:Writeln(NumToStr(mass_inv))
        file:Writeln(" v_mag [1] ="); file:Writeln(NumToStr(vm))
        file:Writeln(" v_mag_inv [1] ="); file:Writeln(NumToStr(v_mag_inv))
        file:Writeln(" I [1] ="); file:Writeln("1")
        file:Writeln(" k_i [1] ="); file:Writeln(NumToStr(m))
        file:Writeln(" v [1] =")
        file:Writeln("  x [1] ="); file:Writeln(NumToStr(v.x))
        file:Writeln("  y [1] ="); file:Writeln(NumToStr(v.y))
        file:Writeln("  z [1] ="); file:Writeln(NumToStr(v.z))
        file:Writeln(" omega [1] =")
        file:Writeln("  x [1] ="); file:Writeln(NumToStr(omega.x))
        file:Writeln("  y [1] ="); file:Writeln(NumToStr(omega.y))
        file:Writeln("  z [1] ="); file:Writeln(NumToStr(omega.z))
        file:Writeln(" Accel [1] =")
        file:Writeln("  x [1] ="); file:Writeln("0")
        file:Writeln("  y [1] ="); file:Writeln("0")
        file:Writeln("  z [1] ="); file:Writeln("0")

        -- Factory-specific fields
        if isFactory then
            file:Writeln("state = 02000000")
            -- delayTimer: time since factory started (random small value)
            file:Writeln("delayTimer [1] ="); file:Writeln(NumToStr(math.random() * 0.1))
            -- nextRepair: when next repair happens (future time)
            file:Writeln("nextRepair [1] ="); file:Writeln(NumToStr(currentTime + 999))
            -- buildClass: get from ODF's classToBuild
            local classToBuild = factoryODF and GetODFString(factoryODF, nil, "classToBuild", "") or ""
            file:Writeln("buildClass [1] ="); file:Writeln(classToBuild or "")
            -- buildDoneTime: if building something, when it completes
            file:Writeln("buildDoneTime [1] ="); file:Writeln(NumToStr(currentTime + 999))
        end

        file:Writeln("seqNo [1] =")
        file:Writeln(tostring(seqno))
        file:Writeln("name = ")
        file:Writeln("isCritical [1] =")
        file:Writeln(tostring(IsCritical and IsCritical(h) or false))
        file:Writeln("isObjective [1] =")
        file:Writeln("false")
        file:Writeln("isSelected [1] =")
        file:Writeln(tostring(IsSelected and IsSelected(h) or false))
        file:Writeln("isVisible [1] =")
        file:Writeln("2")
        file:Writeln("seen [1] =")
        file:Writeln("2")
        file:Writeln("playerShot [1] =")
        file:Writeln("-1e+030")
        file:Writeln("playerCollide [1] =")
        file:Writeln("-1e+030")
        file:Writeln("friendShot [1] =")
        file:Writeln("-1e+030")
        file:Writeln("friendCollide [1] =")
        file:Writeln("-1e+030")
        file:Writeln("enemyShot [1] =")
        file:Writeln("-1e+030")
        file:Writeln("groundCollide [1] =")
        file:Writeln("0")

        local curH = GetCurHealth(h) or 0
        local maxH = GetMaxHealth(h) or 1
        local curA = GetCurAmmo(h) or 0
        local maxA = GetMaxAmmo(h) or 1
        file:Writeln("healthRatio [1] ="); file:Writeln(NumToStr(curH / (maxH > 0 and maxH or 1)))
        file:Writeln("curHealth [1] ="); file:Writeln(tostring(curH))
        file:Writeln("maxHealth [1] ="); file:Writeln(tostring(maxH))
        file:Writeln("ammoRatio [1] ="); file:Writeln(NumToStr(curA / (maxA > 0 and maxA or 1)))
        file:Writeln("curAmmo [1] ="); file:Writeln(tostring(curA))
        file:Writeln("maxAmmo [1] ="); file:Writeln(tostring(maxA))

        -- Two command blocks (current and next)
        for _ = 1, 2 do
            file:Writeln("priority [1] ="); file:Writeln("0")
            file:Writeln("what = 00000000")
            file:Writeln("who [1] ="); file:Writeln("0")
            file:Writeln("where = 00000000")
            file:Writeln("param [1] =")
            file:Writeln("")
        end

        file:Writeln("undefptr = " .. ToHex(idMap[h] or 0))
        file:Writeln("isCargo [1] =")
        file:Writeln("false")
        file:Writeln("independence [1] =")
        file:Writeln("1")
        -- FIX #9: curPilot needs [1] = header and newline
        file:Writeln("curPilot [1] =")
        file:Writeln(isPlayer and "asuser" or "")
        file:Writeln("perceivedTeam [1] =")
        file:Writeln(tostring(GetPerceivedTeam and GetPerceivedTeam(h) or GetTeamNum(h)))

        -- Five weapon slots
        for slot = 0, 4 do
            local wpn = GetWeaponClass and GetWeaponClass(h, slot) or ""
            file:Writeln("wpnID [1] =")
            file:Writeln(wpn or "")
        end

        -- enabled is a hex-encoded bitmask of enabled weapons
        local mask = 0
        if IsCraft(h) then
            for i = 0, 4 do
                local w = GetWeaponClass(h, i)
                if w and #w > 0 then mask = bit.bor(mask, bit.lshift(1, i)) end
            end
        end
        file:Writeln("enabled [1] =")
        file:Writeln(string.format("%x", mask))
        file:Writeln("selected [1] =")
        file:Writeln(isPlayer and "1" or "0")
    end

    -- -----------------------------------------------------------------------
    -- Teams section (0..14)
    -- -----------------------------------------------------------------------
    -- Teams section (0..15)
    -- -----------------------------------------------------------------------
    for t = 0, 15 do
        file:Writeln("curScrap [1] ="); file:Writeln(tostring(GetScrap(t) or 0))
        file:Writeln("maxScrap [1] ="); file:Writeln(tostring(GetMaxScrap(t) or 0))
        file:Writeln("curPilot [1] ="); file:Writeln(tostring(GetPilot(t) or 0))
        file:Writeln("maxPilot [1] ="); file:Writeln(tostring(GetMaxPilot(t) or 0))
        -- dwAllies must include the team's own bit (1 << t)
        local teamMask = GetAllyMask(t) or 0
        file:Writeln("dwAllies [1] ="); file:Writeln(tostring(bit.bor(bit.lshift(1, (t < 16 and t or 0)), teamMask)))
    end

    -- -----------------------------------------------------------------------
    -- Lua Mission State
    -- -----------------------------------------------------------------------
    file:Writeln("name = LuaMission")
    file:Writeln("sObject = " .. ToHex(missionID))
    file:Writeln("started [1] =")
    file:Writeln("true")

    local saveResults = {}
    if type(_G.Save) == "function" then
        local ok, results = pcall(function() return { _G.Save() } end)
        if ok and results then
            saveResults = results
        else
            print("AutoSave: _G.Save() failed: " .. tostring(results))
        end
    end

    file:Writeln("count [1] =")
    file:Writeln(tostring(#saveResults))
    for _, v in ipairs(saveResults) do
        AutoSave._WriteLuaValue(file, nil, v, 0)
    end

    -- -----------------------------------------------------------------------
    -- [AiMission] section
    -- -----------------------------------------------------------------------
    file:Writeln("[AiMission]")
    file:Writeln("size [1] =")
    file:Writeln(tostring(#missionList))
    for _, m in ipairs(missionList) do
        file:Writeln("name = " .. m.name)
        file:Writeln("sObject = " .. ToHex(m.sObject))
        if m.name == "UserProcess" then
            file:Writeln("cycle [1] ="); file:Writeln("0")
            file:Writeln("selectList = 01000000000000000000000000000000000000000000000000000000000000000000000000000000")
            file:Writeln("selectNext = 01000000000000000000000000000000000000000000000000000000000000000000000000000000")
        elseif m.name == "MUFEnemy" or m.name == "MUFFriend" then
            file:Writeln("curState = 02000000")
            file:Writeln("nextState = 02000000")
            file:Writeln("craft = " .. ToHex(m.fOwner))
            file:Writeln("release [1] ="); file:Writeln("false")
            file:Writeln("where = 00000000")
            file:Writeln("whoHandle [1] ="); file:Writeln("0")
            file:Writeln("lastHit [1] ="); file:Writeln("0")
            file:Writeln("task = " .. ToHex(taskMap[m.h] or 0))
            file:Writeln("classtobuild [1] ="); file:Writeln("")
        elseif m.name == "RecyclerFriend" or m.name == "RecyclerEnemy" then
            file:Writeln("undefptr = 00000000")
            file:Writeln("fWhat = 00000000")
            file:Writeln("lastHit [1] ="); file:Writeln("0")
            file:Writeln("attacked [1] ="); file:Writeln("0")
            file:Writeln("waitToSetup [1] ="); file:Writeln("0")
            file:Writeln("curState = 03000000")
            file:Writeln("nextState = 03000000")
            file:Writeln("craft = " .. ToHex(m.fOwner))
            file:Writeln("release [1] ="); file:Writeln("false")
            file:Writeln("where = 00000000")
            file:Writeln("whoHandle [1] ="); file:Writeln("0")
            file:Writeln("lastHit [1] ="); file:Writeln("0")
            file:Writeln("task = " .. ToHex(taskMap[m.h] or 0))
            file:Writeln("classtobuild [1] ="); file:Writeln("")
        elseif m.name == "ScavengerEnemy" then
            file:Writeln("oldhealth [1] ="); file:Writeln("0")
            file:Writeln("curState [1] ="); file:Writeln("4")
            file:Writeln("nextState [1] ="); file:Writeln("9")
            file:Writeln("whoHandle [1] ="); file:Writeln("0")
            file:Writeln("craft = " .. ToHex(m.fOwner))
            file:Writeln("where [1] =")
            file:Writeln("  x [1] ="); file:Writeln("0")
            file:Writeln("  y [1] ="); file:Writeln("0")
            file:Writeln("  z [1] ="); file:Writeln("0")
            file:Writeln("lastScrap [1] =")
            file:Writeln("  x [1] ="); file:Writeln("0")
            file:Writeln("  y [1] ="); file:Writeln("-1")
            file:Writeln("  z [1] ="); file:Writeln("0")
            file:Writeln("wait_time [1] ="); file:Writeln("1e+030")
            file:Writeln("recycle [1] ="); file:Writeln("true")
            file:Writeln("team [1] ="); file:Writeln(tostring(GetTeamNum(m.h)))
            file:Writeln("task = " .. ToHex(taskMap[m.h] or 0))
        elseif m.name == "TurretTankEnemy" or m.name == "ScoutEnemy" or m.name == "ScoutFriend" or
            m.name == "SoldierEnemy" or m.name == "SoldierFriend" then
            if m.name == "ScoutEnemy" or m.name == "ScoutFriend" or m.name == "SoldierEnemy" or m.name == "SoldierFriend" then
                file:Writeln("isFriend [1] ="); file:Writeln((m.name == "ScoutFriend" or m.name == "SoldierFriend") and
                    "true" or "false")
                file:Writeln("engageRange [1] ="); file:Writeln("40000")
                file:Writeln("followRange [1] ="); file:Writeln("15625")
                file:Writeln("weaponRange [1] ="); file:Writeln("40000")
                file:Writeln("madTime [1] ="); file:Writeln("30")
            else
                file:Writeln("waitDeploy [1] ="); file:Writeln("false")
                file:Writeln("waitDeployTime [1] ="); file:Writeln("0")
                file:Writeln("nextAttackTime [1] ="); file:Writeln("0")
            end
            file:Writeln("attackUser [1] ="); file:Writeln("false")
            file:Writeln("independence [1] ="); file:Writeln("1")
            file:Writeln("curState [1] ="); file:Writeln(m.name:find("Soldier") and "7" or "3")
            file:Writeln("nextState [1] ="); file:Writeln("0")
            file:Writeln("saveState [1] ="); file:Writeln("0")
            file:Writeln("saveWho [1] ="); file:Writeln("0")
            file:Writeln("nextEnemyCheck [1] ="); file:Writeln("0")
            file:Writeln("me = " .. ToHex(m.fOwner))
            file:Writeln("task = " .. ToHex(taskMap[m.h] or 0))
            file:Writeln("whoHandle [1] ="); file:Writeln("0")
            file:Writeln("where = 00000000")
            file:Writeln("release [1] ="); file:Writeln("false")
            file:Writeln("exact [1] ="); file:Writeln("true")
            file:Writeln("whatClass [1] ="); file:Writeln("")
            file:Writeln("isInTransition [1] ="); file:Writeln("false")
            file:Writeln("wasInTransition [1] ="); file:Writeln("false")
            file:Writeln("waitStart [1] ="); file:Writeln(m.name:find("Soldier") and "0.041" or "0.004")
            file:Writeln("waitDeploy [1] ="); file:Writeln("false")
            file:Writeln("waitDeployTime [1] ="); file:Writeln("0")
            file:Writeln("timeOut [1] ="); file:Writeln("0")
        end
        file:Writeln("fMission = " .. ToHex(missionID))
        file:Writeln("fOwner = " .. ToHex(m.fOwner))
        file:Writeln("exited [1] ="); file:Writeln("0")
    end

    -- Mission object trailer
    file:Writeln("done [1] ="); file:Writeln("false")
    file:Writeln("shutdownTime [1] ="); file:Writeln("0")
    file:Writeln("failed [1] ="); file:Writeln("false")
    file:Writeln("resultName =")
    -- -----------------------------------------------------------------------
    -- [AOIs] section
    -- FIX #4: Use "size [1] =" not "count [1] ="
    -- -----------------------------------------------------------------------
    file:Writeln("[AOIs]")
    file:Writeln("size [1] =")
    file:Writeln("0")

    -- -----------------------------------------------------------------------
    -- [AiPaths] section: read from the BZN file and reproduce verbatim.
    -- This is essential for path-following and scripting (BuildObject to path,
    -- Goto to path, etc.) to work correctly after loading.
    -- -----------------------------------------------------------------------
    -- aiPaths is defined at the top of the function

    file:Writeln("[AiPaths]")
    file:Writeln("count [1] =")
    file:Writeln(tostring(#aiPaths))

    for i, p in ipairs(aiPaths) do
        local pts = p.points or {}
        local pathSeqNo = pathIDStart + i - 1

        file:Writeln("[AiPath]")
        file:Writeln("old_ptr = " .. ToHex(pathSeqNo))

        if p.label and #p.label > 0 then
            file:Writeln("size [1] =")
            file:Writeln(tostring(#p.label))
            file:Writeln("label = " .. p.label)
        else
            file:Writeln("size [1] =")
            file:Writeln("0")
        end

        local pts = p.points or {}
        file:Writeln("pointCount [1] =")
        file:Writeln(tostring(#pts))
        if #pts > 0 then
            file:Writeln("points [" .. tostring(#pts) .. "] =")
            for _, pt in ipairs(pts) do
                -- Points are 2D (x, z); y is terrain-following at runtime
                file:Writeln("  x [1] ="); file:Writeln(NumToStr(pt.x))
                file:Writeln("  z [1] ="); file:Writeln(NumToStr(pt.z))
            end
        end

        -- pathType as 8-char hex (from BZN)
        file:Writeln(string.format("pathType = %08X", p.pathType or 0))
    end

    -- -----------------------------------------------------------------------
    -- [AiTasks] section
    -- We enumerate vehicles/persons (non-player) and write one task per unit.
    -- GetCurrentCommand() maps to the appropriate task name; safe defaults are
    -- used for fields we cannot determine from Lua (plan paths, steer params).
    -- -----------------------------------------------------------------------
    local AiCmd = AiCommand or {}

    -- Gather AI task candidates: alive vehicles and persons, non-player
    -- taskObjects is already defined and populated above.

    file:Writeln("[AiTasks]")
    file:Writeln("count [1] =")
    file:Writeln(tostring(#taskObjects))

    for i, h in ipairs(taskObjects) do
        local cmd                                      = GetCurrentCommand and GetCurrentCommand(h) or 0
        local who                                      = GetCurrentWho and GetCurrentWho(h) or nil
        local hpos                                     = GetPosition(h)
        local meHex                                    = HandleToHex(h)
        local sObjHex                                  = ToHex(taskMap[h])

        -- Determine task type and per-task defaults from the current command
        local taskName, curState, nextState, blastDist = "SitTask", 6, -1, 75
        local isAttack                                 = false

        if cmd == (AiCmd.ATTACK or 4) then
            taskName  = "SoldierAttack"
            curState  = 2
            nextState = 2
            blastDist = 40
            isAttack  = true
        elseif cmd == (AiCmd.GO or 3) or cmd == (AiCmd.PATROL or 22) or
            cmd == (AiCmd.HUNT or 20) or cmd == (AiCmd.SCAVENGE or 19) then
            -- Use SitTask as a safe fallback; on load the mission script /
            -- aiCore.Bootstrap() will re-assign appropriate commands.
            taskName  = "SitTask"
            curState  = 6
            nextState = -1
            blastDist = 75
        end

        -- himHandle: target as signed 32-bit decimal (0 if no valid target)
        local himHandleVal = "0"
        local attackTargetHex = "00000000"
        if isAttack and who and IsValid(who) then
            himHandleVal    = HandleToSignedDec(who)
            attackTargetHex = HandleToHex(who)
        end

        file:Writeln("name = " .. taskName)
        file:Writeln("sObject = " .. sObjHex)
        file:Writeln("curState [1] =")
        file:Writeln(tostring(curState))
        file:Writeln("nextState [1] =")
        file:Writeln(tostring(nextState))
        file:Writeln("me = " .. meHex)
        file:Writeln("himHandle [1] =")
        file:Writeln(himHandleVal)
        file:Writeln("wasInTransition [1] =")
        file:Writeln("false")
        file:Writeln("saveState [1] =")
        file:Writeln("13")
        file:Writeln("saveHandle [1] =")
        file:Writeln("0")
        file:Writeln("gotoPoint [1] =")
        file:Writeln("  x [1] ="); file:Writeln(NumToStr(hpos.x))
        file:Writeln("  y [1] ="); file:Writeln(NumToStr(hpos.y))
        file:Writeln("  z [1] ="); file:Writeln(NumToStr(hpos.z))
        file:Writeln("plan = 00000000")
        file:Writeln("planPoint [1] =")
        file:Writeln("0")
        file:Writeln("braccelFactor [1] =")
        file:Writeln("0.05")
        file:Writeln("steerFactor [1] =")
        file:Writeln("3")
        file:Writeln("strafeFactor [1] =")
        file:Writeln("0.05")
        file:Writeln("avoidSkip [1] =")
        file:Writeln("0")
        file:Writeln("nextStuck [1] =")
        file:Writeln("0")
        file:Writeln("lastStuck [1] =")
        file:Writeln("  x [1] ="); file:Writeln("0")
        file:Writeln("  y [1] ="); file:Writeln("0")
        file:Writeln("  z [1] ="); file:Writeln("0")
        file:Writeln("stuckState [1] =")
        file:Writeln("0")
        file:Writeln("pitch [1] =")
        file:Writeln("0")
        file:Writeln("blastDist [1] =")
        file:Writeln(tostring(blastDist))
        file:Writeln("fireConeX [1] =")
        file:Writeln("0")
        file:Writeln("fireConeY [1] =")
        file:Writeln("0")
        file:Writeln("switchDist [1] =")
        file:Writeln("10")
        file:Writeln("attackStart [1] =")
        file:Writeln("0")
        file:Writeln("attackTarget = " .. attackTargetHex)
        file:Writeln("noHitTime [1] =")
        file:Writeln("0")
        file:Writeln("followDx [1] =")
        file:Writeln("0")
        file:Writeln("followDz [1] =")
        file:Writeln("0")
        file:Writeln("lastStopped [1] =")
        file:Writeln("0")
        file:Writeln("followTarget = 00000000")
        file:Writeln("timeOut [1] =")
        file:Writeln("0")
    end

    -- -----------------------------------------------------------------------
    -- Footer (LuaMission engine state)
    -- FIX #5: msg and lastMsg get null-terminator padding matching the engine.
    -- The engine writes msg with 2 trailing \0 bytes and lastMsg with 4.
    -- -----------------------------------------------------------------------
    local msnWav = terrainName .. "01.wav" -- e.g. "misn040[1].wav"
    -- Use terrainName + "01.wav" as a reasonable default voice file name.
    -- The engine uses the most recently played audio message for these fields;
    -- since we can't query that from Lua, the default is acceptable.

    file:Writeln("size [1] =")
    file:Writeln("1")
    file:Writeln("seqNo [1] =")
    file:Writeln("1")
    file:Writeln("msg = " .. AutoSave._ToHex(msnWav, 1))
    file:Writeln("lastMsg = " .. AutoSave._ToHex(msnWav, 3))
    file:Writeln("aip_team_count [1] =")
    file:Writeln("0")
    file:Writeln("difficultySetting [1] =")
    file:Writeln(tostring((exu and exu.GetDifficulty and exu.GetDifficulty()) or 4))
    file:Writeln("cameraReady [1] =")
    file:Writeln("false")
    file:Writeln("cameraCallCount [1] =")
    file:Writeln("0")
    file:Writeln("quakeMag [1] =")
    file:Writeln("0")
    file:Writeln("frac [1] =")
    file:Writeln("0")
    file:Writeln("timer [1] =")
    file:Writeln("0")
    file:Writeln("warn [1] =")
    file:Writeln("-2147483648")
    file:Writeln("alert [1] =")
    file:Writeln("-2147483648")
    file:Writeln("countdown [1] =")
    file:Writeln("true")
    file:Writeln("active [1] =")
    file:Writeln("false")
    file:Writeln("show [1] =")
    file:Writeln("false")
    file:Writeln("objectiveCount [1] =")
    file:Writeln("0")
    file:Writeln("objectiveLast [1] =")
    file:Writeln("0")
    file:Writeln("groupNum = 00000000000000000000000000000000000000000000000000000000000000000000000000000000")
    file:Writeln("groupList = " ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" ..
        "00000000000000000000000000000000000000000000000000000000000000000000000000000")
end

_G.AutoSave = AutoSave
return AutoSave
