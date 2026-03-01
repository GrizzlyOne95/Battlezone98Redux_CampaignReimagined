-- AutoSave.lua
---@diagnostic disable: lowercase-global, undefined-global, undefined-field
-- Programmatic Save File Synthesis for Battlezone 98 Redux
-- Generates .sav files using bzfile I/O to enable true auto-save

local bzfile = require("bzfile")
local exu = require("exu")
local bit = require("bit")

-- BZN Parser Integration
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
            return 0.0 -- NaN/Inf handled as 0 for safety
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

    function BZNTokenString:GetString(i)
        return self.values[(i or 0) + 1] or ""
    end

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
            v =
                SetVector(0, 0, 0),
            omega = SetVector(0, 0, 0),
            Accel = SetVector(0, 0, 0)
        }
    end

    function BZNTokenNull:Validate(n, t) return false end

    local Tokenizer = {}
    Tokenizer.__index = Tokenizer
    function Tokenizer.new(d)
        return setmetatable(
            {
                data = d,
                pos = 1,
                type_size = 2,
                size_size = 2,
                complex_map = { points = 2, pos = 3, v = 3, omega = 3, Accel = 3, euler = 9, transform = 12 },
                nullToken =
                    BZNTokenNull.new()
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
            rawLine = rawLine:gsub("=",
                " = ")
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
                    values[1][i] = self:ReadStringValueToken(self:ReadStringLine():match(
                        "^%s*(.*)$"))
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
                local values = {}
                for i = 1, count do
                    values[i] = {}
                    for j = 1, countIndented do
                        values[i][j] = self:ReadStringValueToken(self:ReadStringLine():match(
                            "^%s*(.*)$"))
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

    function Tokenizer:GetAiCmdInfo()
        local r = {}
        local t = self:ReadToken()
        if not t then return r end
        r.priority = t:GetUInt32()
        self:ReadToken()
        t = self:ReadToken()
        if t then r.who = t:GetInt32() end
        t = self:ReadToken()
        if t then r.where = t:GetUInt32H() end
        t = self:ReadToken()
        if t then r.param = t:GetUInt32() end
        return r
    end

    local ClassReaders = {}
    ClassReaders.gameobject = function(go, r, ext)
        local o = ext or {}
        o.illumination = r:ReadToken():GetSingle()
        o.pos = r:ReadToken():GetVector3D()
        local e = {}
        e.mass = r:ReadToken():GetSingle()
        e.mass_inv = r:ReadToken():GetSingle()
        e.v_mag = r:ReadToken():GetSingle()
        e.v_mag_inv = r:ReadToken():GetSingle()
        e.I = r:ReadToken():GetSingle()
        e.I_inv = r:ReadToken():GetSingle()
        e.v = r:ReadToken():GetVector3D()
        e.omega = r:ReadToken():GetVector3D()
        e.Accel = r:ReadToken():GetVector3D()
        o.euler = e
        o.seqNo = r:ReadToken():GetUInt32()
        if r.version > 1030 then o.name = r:ReadToken():GetString() end
        if (r.version >= 1046 and r.version < 2000) or r.version >= 2010 then r:ReadToken() end
        o.isObjective = r:ReadToken():GetBoolean()
        o.isSelected = r:ReadToken():GetBoolean()
        o.isVisible = r:ReadToken():GetUInt32H()
        o.seen = r:ReadToken():GetUInt32H()
        o.healthRatio = r:ReadToken():GetSingle()
        o.curHealth = r:ReadToken():GetUInt32()
        o.maxHealth = r:ReadToken():GetUInt32()
        o.ammoRatio = r:ReadToken():GetSingle()
        o.curAmmo = r:ReadToken():GetInt32()
        o.maxAmmo = r:ReadToken():GetInt32()
        o.nextCmd = r:GetAiCmdInfo()
        o.aiProcess = r:ReadToken():GetBoolean()
        if r.version > 1007 then o.isCargo = r:ReadToken():GetBoolean() end
        if r.version > 1016 then o.independence = r:ReadToken():GetUInt32() end
        if r.version > 1016 then o.curPilot = r:ReadToken():GetString() end
        if r.version > 1031 then o.perceivedTeam = r:ReadToken():GetInt32() end
        return o
    end
    ClassReaders.geyser = ClassReaders.gameobject

    BZN_Open = function(name)
        local filedata = UseItem(name)
        if not filedata then
            print("AutoSave: Could not load template file: " .. tostring(name)); return nil
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
                        p.points = {}; reader:ReadToken(); for j = 1, pc do p.points[j] = reader:ReadToken():GetVector2D() end
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

local AutoSave = {}
AutoSave.ActiveObjectives = {}
AutoSave.Config = { enabled = true, autoSaveInterval = 300, currentSlot = 1 }
AutoSave.timer = 0
AutoSave.seqCount = 499 -- Default to match game9.sav reference

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
        file:Writeln(prefix .. tostring(value))
    elseif type(value) == "string" then
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "4")
        file:Writeln(prefix .. "l [1] =")
        file:Writeln(prefix .. tostring(#value))
        file:Writeln(prefix .. "s = " .. value)
    elseif type(value) == "table" then
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        file:Writeln(prefix .. "type [1] =")
        file:Writeln(prefix .. "5")
        file:Writeln(prefix .. "count [1] =")
        file:Writeln(prefix .. tostring(count))
        for k, v in pairs(value) do
            AutoSave._WriteLuaValue(file, nil, k, indent)
            AutoSave._WriteLuaValue(file, nil, v, indent)
        end
    end
end

function AutoSave._ToHex(str)
    if not str then return "" end
    local hex = ""
    for i = 1, #str do
        hex = hex .. string.format("%02x", str:byte(i))
    end
    -- Add padding if necessary to match save9 style? No, just the string is enough.
    return hex
end

function AutoSave._GetPlayerSide()
    local h = GetPlayerHandle()
    if h then
        local odf = GetOdf(h):lower()
        if odf:find("^av") or odf:find("^ab") then return "usa" end
        if odf:find("^sv") or odf:find("^sb") then return "soviet" end
        if odf:find("^cv") or odf:find("^cb") then return "blackdog" end
    end
    return "usa" -- Fallback
end

function AutoSave.CreateSave(slot, desc)
    local filename = bzfile.GetWorkingDirectory() .. "\\Save\\game" .. (slot or AutoSave.Config.currentSlot) .. ".sav"
    local file = bzfile.Open(filename, "w", "trunc")
    if not file then return false end
    AutoSave._WriteSaveFile(file, desc)
    file:Close()
    return true
end

function AutoSave.Update(dtime)
    if not AutoSave.Config.enabled then return end
    -- If dtime is nil, default to 0.05 (20 TPS)
    dtime = dtime or 0.05
    AutoSave.timer = AutoSave.timer + dtime
    if AutoSave.timer >= AutoSave.Config.autoSaveInterval then
        local missionName = GetMissionFilename():gsub("%.bzn$", "")
        local missionTime = math.floor(GetTime())
        AutoSave.CreateSave(nil, string.format("%s AutoSave %ds", missionName, missionTime))
        AutoSave.timer = 0
    end
end

function AutoSave._WriteSaveFile(file, desc)
    local missionFilename = GetMissionFilename()
    local terrainName = missionFilename:gsub("%.bzn$", "")
    local currentTime = GetTime()
    local playerHandle = GetPlayerHandle()

    -- Scan for counts and max seqno
    local objCount = 0
    local maxSeqNo = 0
    for h in AllObjects() do
        if IsValid(h) then
            objCount = objCount + 1
            local id = tonumber(tostring(h), 16)
            if id and id > maxSeqNo then maxSeqNo = id end
        end
    end

    file:Writeln("version [1] =")
    file:Writeln("2016")
    file:Writeln("binarySave [1] =")
    file:Writeln("false")
    file:Writeln("msn_filename = " .. missionFilename)
    file:Writeln("seq_count [1] =")
    file:Writeln(tostring(maxSeqNo + 1))
    file:Writeln("missionSave [1] =")
    file:Writeln("false")
    file:Writeln("runType [1] =")
    file:Writeln("0")
    file:Writeln("saveGameDesc = " .. AutoSave._ToHex(desc or (terrainName .. " AutoSave")))
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

    for h in AllObjects() do
        if IsValid(h) then
            file:Writeln("[GameObject]")
            file:Writeln("PrjID [1] =")
            local odf = GetOdf(h):gsub("[%z%s]+$", ""):gsub("%.odf$", "")
            file:Writeln((h == playerHandle) and "player" or odf)
            file:Writeln("seqno [1] =")
            file:Writeln(tostring(tonumber(tostring(h), 16)))

            local pos = GetPosition(h)
            file:Writeln("pos [1] =")
            file:Writeln("  x [1] ="); file:Writeln(tostring(pos.x))
            file:Writeln("  y [1] ="); file:Writeln(tostring(pos.y))
            file:Writeln("  z [1] ="); file:Writeln(tostring(pos.z))

            file:Writeln("team [1] =")
            file:Writeln(tostring(GetTeamNum(h)))
            file:Writeln("label = " .. (GetLabel(h) or ""))
            file:Writeln("isUser [1] =")
            file:Writeln((h == playerHandle) and "1" or "0")
            file:Writeln("obj_addr = " .. tostring(h))

            local t = GetTransform(h)
            file:Writeln("transform [1] =")
            file:Writeln("  right_x [1] ="); file:Writeln(tostring(t.right.x))
            file:Writeln("  right_y [1] ="); file:Writeln(tostring(t.right.y))
            file:Writeln("  right_z [1] ="); file:Writeln(tostring(t.right.z))
            file:Writeln("  up_x [1] ="); file:Writeln(tostring(t.up.x))
            file:Writeln("  up_y [1] ="); file:Writeln(tostring(t.up.y))
            file:Writeln("  up_z [1] ="); file:Writeln(tostring(t.up.z))
            file:Writeln("  front_x [1] ="); file:Writeln(tostring(t.front.x))
            file:Writeln("  front_y [1] ="); file:Writeln(tostring(t.front.y))
            file:Writeln("  front_z [1] ="); file:Writeln(tostring(t.front.z))
            file:Writeln("  posit_x [1] ="); file:Writeln(tostring(t.posit.x))
            file:Writeln("  posit_y [1] ="); file:Writeln(tostring(t.posit.y))
            file:Writeln("  posit_z [1] ="); file:Writeln(tostring(t.posit.z))

            file:Writeln("abandoned [1] =")
            file:Writeln("0")
            file:Writeln("cloakState = 00000000")
            file:Writeln("cloakTransBeginTime [1] =")
            file:Writeln("0")
            file:Writeln("cloakTransEndTime [1] =")
            file:Writeln("0")
            file:Writeln("illumination [1] =")
            file:Writeln("1")

            file:Writeln("euler =")
            local m = (exu and exu.GetMass and exu.GetMass(h)) or 1500
            file:Writeln(" mass [1] ="); file:Writeln(tostring(m))
            file:Writeln(" mass_inv [1] ="); file:Writeln(tostring(m > 0 and 1 / m or 0))
            local v = GetVelocity(h)
            local vm = math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2)
            file:Writeln(" v_mag [1] ="); file:Writeln(tostring(vm))
            file:Writeln(" v_mag_inv [1] ="); file:Writeln(vm > 0 and tostring(1 / vm) or "1e+030")
            file:Writeln(" I [1] ="); file:Writeln("1")
            file:Writeln(" k_i [1] ="); file:Writeln("1")
            file:Writeln(" v [1] =")
            file:Writeln("  x [1] ="); file:Writeln(tostring(v.x))
            file:Writeln("  y [1] ="); file:Writeln(tostring(v.y))
            file:Writeln("  z [1] ="); file:Writeln(tostring(v.z))
            file:Writeln(" omega [1] =")
            local omega = GetOmega(h)
            file:Writeln("  x [1] ="); file:Writeln(tostring(omega.x))
            file:Writeln("  y [1] ="); file:Writeln(tostring(omega.y))
            file:Writeln("  z [1] ="); file:Writeln(tostring(omega.z))
            file:Writeln(" Accel [1] =")
            file:Writeln("  x [1] ="); file:Writeln("0")
            file:Writeln("  y [1] ="); file:Writeln("0")
            file:Writeln("  z [1] ="); file:Writeln("0")

            file:Writeln("seqNo [1] =")
            file:Writeln(tostring(tonumber(tostring(h), 16)))
            file:Writeln("name = ")
            file:Writeln("isCritical [1] =")
            file:Writeln("false")
            file:Writeln("isObjective [1] =")
            file:Writeln("false")
            file:Writeln("isSelected [1] =")
            file:Writeln("false")
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

            local curH, maxH = GetCurHealth(h) or 0, GetMaxHealth(h) or 1
            file:Writeln("healthRatio [1] ="); file:Writeln(tostring(curH / (maxH > 0 and maxH or 1)))
            file:Writeln("curHealth [1] ="); file:Writeln(tostring(curH))
            file:Writeln("maxHealth [1] ="); file:Writeln(tostring(maxH))
            local curA, maxA = GetCurAmmo(h) or 0, GetMaxAmmo(h) or 1
            file:Writeln("ammoRatio [1] ="); file:Writeln(tostring(curA / (maxA > 0 and maxA or 1)))
            file:Writeln("curAmmo [1] ="); file:Writeln(tostring(curA))
            file:Writeln("maxAmmo [1] ="); file:Writeln(tostring(maxA))

            -- Command Blocks (2 per object)
            for k = 1, 2 do
                file:Writeln("priority [1] ="); file:Writeln("0")
                file:Writeln("what = 00000000")
                file:Writeln("who [1] ="); file:Writeln("0")
                file:Writeln("where = 00000000")
                file:Writeln("param [1] =")
                file:Writeln("")
            end

            file:Writeln("undefptr = 00000000")
            file:Writeln("isCargo [1] =")
            file:Writeln("false")
            file:Writeln("independence [1] =")
            file:Writeln("1")
            file:Writeln("curPilot = " .. ((h == playerHandle) and "aspilo" or ""))
            file:Writeln("perceivedTeam [1] =")
            file:Writeln(tostring(GetTeamNum(h)))
            for j = 1, 5 do
                file:Writeln("wpnID [1] =")
                file:Writeln("")
            end
            file:Writeln("enabled [1] =")
            file:Writeln((h == playerHandle) and "1" or "0")
            file:Writeln("selected [1] =")
            file:Writeln((h == playerHandle) and "1" or "0")
        end
    end

    -- Teams Section
    for t = 0, 14 do
        file:Writeln("curScrap [1] ="); file:Writeln("0")
        file:Writeln("maxScrap [1] ="); file:Writeln("0")
        file:Writeln("curPilot [1] ="); file:Writeln("0")
        file:Writeln("maxPilot [1] ="); file:Writeln("0")
        file:Writeln("dwAllies [1] ="); file:Writeln("1")
    end

    -- Lua State Section
    file:Writeln("name = LuaMission")
    file:Writeln("sObject = 00000000")
    file:Writeln("started [1] =")
    file:Writeln("true")

    local missionState = {}
    if _G.M then
        table.insert(missionState, _G.M)
        if _G.aiCore and _G.aiCore.Save then
            table.insert(missionState, _G.aiCore.Save())
        else
            table.insert(missionState, {})
        end
    end
    AutoSave._WriteLuaValue(file, nil, missionState, 0)

    -- Missing headers
    file:Writeln("[AOIs]")
    file:Writeln("count [1] ="); file:Writeln("0")
    file:Writeln("[AiTasks]")
    file:Writeln("count [1] ="); file:Writeln("0")

    -- Footer
    file:Writeln("size [1] ="); file:Writeln("1")
    file:Writeln("seqNo [1] ="); file:Writeln("1")
    file:Writeln("msg = " .. AutoSave._ToHex("misn0401.wav"))
    file:Writeln("lastMsg = " .. AutoSave._ToHex("misn0401.wav"))
    file:Writeln("aip_team_count [1] ="); file:Writeln("0")
    file:Writeln("difficultySetting [1] ="); file:Writeln(tostring((exu and exu.GetDifficulty and exu.GetDifficulty()) or 4))
    file:Writeln("cameraReady [1] ="); file:Writeln("false")
    file:Writeln("cameraCallCount [1] ="); file:Writeln("0")
    file:Writeln("quakeMag [1] ="); file:Writeln("0")
    file:Writeln("frac [1] ="); file:Writeln("0")
    file:Writeln("timer [1] ="); file:Writeln("0")
    file:Writeln("warn [1] ="); file:Writeln("-2147483648")
    file:Writeln("alert [1] ="); file:Writeln("-2147483648")
    file:Writeln("countdown [1] =")
    file:Writeln("true")
    file:Writeln("active [1] =")
    file:Writeln("false")
    file:Writeln("show [1] =")
    file:Writeln("false")
    file:Writeln("objectiveCount [1] ="); file:Writeln("0")
    file:Writeln("objectiveLast [1] ="); file:Writeln("0")
    file:Writeln("groupNum = 00000000000000000000000000000000000000000000000000000000000000000000000000000000")
    file:Writeln(
        "groupList = 000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
end

_G.AutoSave = AutoSave
return AutoSave
