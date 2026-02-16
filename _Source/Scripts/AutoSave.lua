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
    local BinaryFieldType = { DATA_VOID = 0, DATA_BOOL = 1, DATA_CHAR = 2, DATA_SHORT = 3, DATA_LONG = 4, DATA_FLOAT = 5, DATA_DOUBLE = 6, DATA_ID = 7, DATA_PTR = 8, DATA_VEC3D = 9, DATA_VEC2D = 10, DATA_MAT3DOLD = 11, DATA_MAT3D = 12, DATA_STRING = 13, DATA_QUAT = 14 }

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

    function BZNTokenBinary:IsBinary() return true end

    function BZNTokenBinary:GetCount() return #self.data end -- Simplified

    function BZNTokenBinary:GetBoolean(i) return self.data:byte((i or 0) + 1) ~= 0 end

    function BZNTokenBinary:GetInt32(i)
        local o = (i or 0) * 4 + 1; local b1, b2, b3, b4 = self.data:byte(o, o + 3)
        return (b4 or 0) * 0x1000000 + (b3 or 0) * 0x10000 + (b2 or 0) * 0x100 + (b1 or 0)
    end

    function BZNTokenBinary:GetUInt32(i) return self:GetInt32(i) end

    function BZNTokenBinary:GetUInt32H(i) return self:GetInt32(i) end

    function BZNTokenBinary:GetInt16(i)
        local o = (i or 0) * 2 + 1; local b1, b2 = self.data:byte(o, o + 1); return b2 * 0x100 + b1
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

    function BZNTokenBinary:Validate(n, t) return not self.type or self.type == t end

    local BZNTokenString = {}
    BZNTokenString.__index = BZNTokenString
    function BZNTokenString.new(n, v) return setmetatable({ name = n, values = v }, BZNTokenString) end

    function BZNTokenString:IsBinary() return false end

    function BZNTokenString:GetCount() return #self.values end

    function BZNTokenString:GetBoolean(i)
        local v = self.values[(i or 0) + 1]; return v == "1" or v == "true"
    end

    function BZNTokenString:GetInt32(i) return tonumber(self.values[(i or 0) + 1]) or 0 end

    function BZNTokenString:GetUInt32(i) return self:GetInt32(i) end

    function BZNTokenString:GetUInt32H(i)
        local v = self.values[(i or 0) + 1]
        if v:sub(1, 1) == '-' then return tonumber(v:sub(2), 16) end
        return tonumber(v, 16) or 0
    end

    function BZNTokenString:GetSingle(i) return tonumber(self.values[(i or 0) + 1]) or 0 end

    function BZNTokenString:GetString(i) return self.values[(i or 0) + 1] end

    function BZNTokenString:IsValidationOnly() return false end

    function BZNTokenString:Validate(n, t) return self.name == n end

    local BZNTokenNestedString = {}
    BZNTokenNestedString.__index = BZNTokenNestedString
    function BZNTokenNestedString.new(n, v) return setmetatable({ name = n, values = v }, BZNTokenNestedString) end

    function BZNTokenNestedString:IsBinary() return false end

    function BZNTokenNestedString:GetVector3D(i)
        local s = self.values[(i or 0) + 1]
        return SetVector(s[1]:GetSingle(), s[2]:GetSingle(), s[3]:GetSingle())
    end

    function BZNTokenNestedString:GetVector2D(i)
        local s = self.values[(i or 0) + 1]
        return SetVector(s[1]:GetSingle(), 0, s[2]:GetSingle())
    end

    function BZNTokenNestedString:GetEuler(i)
        local s = self.values[(i or 0) + 1]
        return {
            mass = s[1]:GetSingle(),
            mass_inv = s[2]:GetSingle(),
            v_mag = s[3]:GetSingle(),
            v_mag_inv = s[4]
                :GetSingle(),
            I = s[5]:GetSingle(),
            I_inv = s[6]:GetSingle(),
            v = s[7]:GetVector3D(),
            omega = s[8]:GetVector3D(),
            Accel =
                s[9]:GetVector3D()
        }
    end

    function BZNTokenNestedString:IsValidationOnly() return false end

    function BZNTokenNestedString:Validate(n, t) return self.name == n end

    local BZNTokenValidation = {}
    BZNTokenValidation.__index = BZNTokenValidation
    function BZNTokenValidation.new(n) return setmetatable({ name = n }, BZNTokenValidation) end

    function BZNTokenValidation:IsBinary() return false end

    function BZNTokenValidation:IsValidationOnly() return true end

    function BZNTokenValidation:Validate(n, t) return self.name == n end

    local BZNTokenNull = {}
    BZNTokenNull.__index = BZNTokenNull
    function BZNTokenNull.new() return setmetatable({}, BZNTokenNull) end

    function BZNTokenNull:IsBinary() return false end

    function BZNTokenNull:IsValidationOnly() return false end

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
                complex_map = { points = 2, pos = 3, v = 3, omega = 3, Accel = 3, euler = 9, dropMat = 12, transform = 12, startMat = 12, saveMatrix = 12, buildMatrix = 12, bumpers = 3, Att = 4 },
                nullToken =
                    BZNTokenNull.new()
            },
            Tokenizer)
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
        elseif line[3] == "=" then -- Array
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
        self:ReadToken() -- what
        t = self:ReadToken()
        if t then r.who = t:GetInt32() end
        t = self:ReadToken()
        if t then r.where = t:GetUInt32H() end
        t = self:ReadToken()
        if t then r.param = t:GetUInt32() end
        return r
    end

    function Tokenizer:GetEuler()
        if self:inBinary() then
            local e = {}
            e.mass = self:ReadToken():GetSingle()
            e.mass_inv = self:ReadToken():GetSingle()
            e.v_mag = self:ReadToken():GetSingle()
            e.v_mag_inv = self:ReadToken():GetSingle()
            e.I = self:ReadToken():GetSingle()
            e.I_inv = self:ReadToken():GetSingle()
            e.v = self:ReadToken():GetVector3D()
            e.omega = self:ReadToken():GetVector3D()
            e.Accel = self:ReadToken():GetVector3D()
            return e
        else
            return self:ReadToken():GetEuler()
        end
    end

    local ClassReaders = {}
    ClassReaders.gameobject = function(go, r, ext)
        local o = ext or {}
        o.illumination = r:ReadToken():GetSingle()
        o.pos = r:ReadToken():GetVector3D()
        o.euler = r:GetEuler()
        o.seqNo = r:ReadToken():GetUInt32()
        if r.version > 1030 then o.name = r:ReadToken():GetString() end
        if (r.version >= 1046 and r.version < 2000) or r.version >= 2010 then r:ReadToken() end -- isCritical
        if r.version == 1001 or r.version == 1011 or r.version == 1012 or r.version == 1017 then
            r:ReadToken(); r:ReadToken(); r:ReadToken(); r:ReadToken()
        end
        o.isObjective = r:ReadToken():GetBoolean()
        o.isSelected = r:ReadToken():GetBoolean()
        o.isVisible = r:ReadToken():GetUInt32H()
        o.seen = r:ReadToken():GetUInt32H()
        if r.version < 1033 then for i = 1, 6 do r:ReadToken() end end
        o.healthRatio = r:ReadToken():GetSingle()
        o.curHealth = r:ReadToken():GetUInt32()
        o.maxHealth = r:ReadToken():GetUInt32()
        if r.version < 1015 then
            r:ReadToken(); r:ReadToken(); r:ReadToken()
        end
        o.ammoRatio = r:ReadToken():GetSingle()
        o.curAmmo = r:ReadToken():GetInt32()
        o.maxAmmo = r:ReadToken():GetInt32()
        if r.version == 1001 or r.version == 1011 or r.version == 1012 then o.curCmd = r:GetAiCmdInfo() end
        o.nextCmd = r:GetAiCmdInfo()
        if r.version == 1001 or r.version == 1011 or r.version == 1012 then
            r:ReadToken()
        elseif r.version ~= 1017 and r.version ~= 1018 then
            o.aiProcess = r:ReadToken():GetBoolean()
        end
        if r.version > 1007 then o.isCargo = r:ReadToken():GetBoolean() end
        if r.version > 1016 then o.independence = r:ReadToken():GetUInt32() end
        if r.version > 1016 then
            if r.version < 1030 then r:ReadToken() else o.curPilot = r:ReadToken():GetString() end
        end
        if r.version > 1031 then o.perceivedTeam = r:ReadToken():GetInt32() else o.perceivedTeam = -1 end
        return o
    end

    ClassReaders.powerup = function(go, r, ext) return ClassReaders.gameobject(go, r, ext or {}) end
    ClassReaders.ammopack = ClassReaders.powerup
    ClassReaders.repairkit = ClassReaders.powerup
    ClassReaders.camerapod = ClassReaders.powerup
    ClassReaders.daywrecker = ClassReaders.powerup
    ClassReaders.wpnpower = ClassReaders.powerup
    ClassReaders.scrap = ClassReaders.gameobject
    ClassReaders.scrapsilo = function(go, r, ext)
        local o = ext or {}
        if r.version > 1020 then o.undefptr = r:ReadToken():GetUInt32H() end
        return ClassReaders.gameobject(go, r, o)
    end
    ClassReaders.spawnpnt = ClassReaders.gameobject

    ClassReaders.craft = function(go, r, ext)
        local o = ext or {}
        if r.version < 1019 then
            if r.version > 1001 then
                for i = 1, 7 do r:ReadToken() end
            else
                r:ReadToken(); r:ReadToken()
            end
        end
        if r.version > 1027 then o.abandoned = r:ReadToken():GetInt32() end
        if r.version >= 2000 then
            if r.version < 2002 then r:ReadToken() end
            r:ReadToken(); r:ReadToken(); r:ReadToken()
        end
        return ClassReaders.gameobject(go, r, o)
    end
    ClassReaders.turret = ClassReaders.craft

    ClassReaders.hover = function(go, r, ext)
        if r.version > 1001 and r.version < 1026 then for i = 1, 20 do r:ReadToken() end end
        return ClassReaders.craft(go, r, ext or {})
    end
    ClassReaders.apc = function(go, r, ext)
        local o = ext or {}
        o.soldierCount = r:ReadToken():GetInt32()
        o.state = r:ReadToken():GetUInt32()
        return ClassReaders.hover(go, r, o)
    end
    ClassReaders.minelayer = ClassReaders.hover
    ClassReaders.sav = ClassReaders.hover
    ClassReaders.scavenger = function(go, r, ext)
        local o = ext or {}
        if (r.version >= 1039 and r.version < 2000) or r.version > 2004 then o.scrapHeld = r:ReadToken():GetUInt32() end
        return ClassReaders.hover(go, r, o)
    end
    ClassReaders.tug = function(go, r, ext)
        local o = ext or {}
        local t = r:ReadToken() -- undefptr
        o.undefptr = t:GetUInt32H()
        return ClassReaders.hover(go, r, o)
    end
    ClassReaders.turrettank = function(go, r, ext)
        local o = ext or {}
        if r.version > 1000 then
            if r.version ~= 1042 then
                r:ReadToken(); r:ReadToken(); r:ReadToken(); r:ReadToken()
            end
            r:ReadToken(); r:ReadToken()
            if r.version ~= 1042 then r:ReadToken() end
        end
        return ClassReaders.hover(go, r, o)
    end
    ClassReaders.howitzer = function(go, r, ext)
        if r.version < 1020 then return ClassReaders.hover(go, r, ext or {}) end
        return ClassReaders.turrettank(go, r, ext or {})
    end
    ClassReaders.wingman = ClassReaders.hover

    ClassReaders.walker = function(go, r, ext)
        if r.version > 1001 and r.version < 1026 then for i = 1, 21 do r:ReadToken() end end
        return ClassReaders.craft(go, r, ext or {})
    end

    ClassReaders.person = function(go, r, ext)
        local o = ext or {}
        o.nextScream = r:ReadToken():GetSingle()
        return ClassReaders.craft(go, r, o)
    end

    ClassReaders.producer = function(go, r, ext)
        local o = ext or {}
        if r.version < 1011 then r:ReadToken() end
        if r.version ~= 1042 then
            r:ReadToken(); r:ReadToken()
        end
        r:ReadToken(); r:ReadToken(); r:ReadToken(); r:ReadToken()
        if r.version >= 1006 then
            r:ReadToken(); r:ReadToken()
            if r.version <= 1026 then for i = 1, 4 do r:ReadToken() end end
        end
        if r.version <= 1010 then return ClassReaders.craft(go, r, o) end
        return ClassReaders.hover(go, r, o)
    end
    ClassReaders.armory = ClassReaders.producer
    ClassReaders.factory = ClassReaders.producer
    ClassReaders.recycler = function(go, r, ext)
        local o = ext or {}
        r:ReadToken()
        return ClassReaders.producer(go, r, o)
    end
    ClassReaders.constructionrig = function(go, r, ext)
        local o = ext or {}
        if r.version > 1030 then
            r:ReadToken(); r:ReadToken()
            if r.version >= 2001 then r:ReadToken() end
        end
        return ClassReaders.producer(go, r, o)
    end

    ClassReaders.i76building = function(go, r, ext)
        local o = ext or {}
        o.tempBuilding = false
        return ClassReaders.gameobject(go, r, o)
    end
    ClassReaders.barracks = ClassReaders.i76building
    ClassReaders.commtower = ClassReaders.i76building
    ClassReaders.geyser = ClassReaders.i76building
    ClassReaders.mine = ClassReaders.i76building
    ClassReaders.flare = ClassReaders.mine
    ClassReaders.magnet = ClassReaders.mine
    ClassReaders.proximity = ClassReaders.mine
    ClassReaders.weaponmine = ClassReaders.mine
    ClassReaders.powerplant = ClassReaders.i76building
    ClassReaders.scrapfield = ClassReaders.i76building
    ClassReaders.shieldtower = ClassReaders.i76building
    ClassReaders.spraybomb = ClassReaders.i76building
    ClassReaders.supplydepot = ClassReaders.i76building
    ClassReaders.i76building2 = ClassReaders.i76building
    ClassReaders.repairdepot = ClassReaders.i76building
    ClassReaders.artifact = ClassReaders.i76building

    ClassReaders.torpedo = function(go, r, ext)
        if r.version < 1031 then
            if r.version < 1019 then
                for i = 1, 7 do r:ReadToken() end
            elseif r.version > 1027 then
                r:ReadToken()
            end
            return ClassReaders.gameobject(go, r, ext or {})
        end
        return ClassReaders.powerup(go, r, ext or {})
    end

    ClassReaders.portal = function(go, r, ext)
        if r.version >= 2004 then for i = 1, 4 do r:ReadToken() end end
        return ClassReaders.gameobject(go, r, ext or {})
    end

    BZN_Open = function(name)
        local filedata = UseItem(name)
        if not filedata then return nil end
        local reader = Tokenizer.new(filedata)
        local bzn = { AiPaths = {} }

        local tok = reader:ReadToken()
        if not tok or not tok:Validate("version") then return nil end
        bzn.version = tok:GetInt32(); reader.version = bzn.version
        if bzn.version > 1022 then
            reader:ReadToken()                             -- binarySave
            if reader:ReadToken():GetBoolean() then reader.binary_offset = reader.pos end
            reader:ReadToken()                             -- msn_filename
        end
        reader:ReadToken()                                 -- seq_count
        if bzn.version >= 1016 then reader:ReadToken() end -- missionSave
        if bzn.version ~= 1001 then bzn.TerrainName = reader:ReadToken():GetString() end
        if bzn.version == 1011 or bzn.version == 1012 then reader:ReadToken() end

        -- Hydrate
        local tok_count = reader:ReadToken()
        local count = tok_count and tok_count:GetInt32() or 0
        for i = 1, count do
            local obj = {}
            if not reader:inBinary() then reader:ReadToken() end -- [GameObject]
            local tok_prj = reader:ReadToken()
            obj.PrjID = tok_prj and tok_prj:GetString() or ""
            if bzn.version == 1001 then obj.PrjID = obj.PrjID:gsub("%z.*", "") end
            local classlabel = GetClassLabelFromODF(obj.PrjID .. ".odf")
            reader:ReadToken();
            local tok_seq = reader:ReadToken()
            obj.seqNo = tok_seq and tok_seq:GetUInt16() or 0
            reader:ReadToken();
            local tok_pos = reader:ReadToken()
            obj.pos = tok_pos and tok_pos:GetVector3D() or SetVector(0, 0, 0)
            reader:ReadToken();
            local tok_team = reader:ReadToken()
            obj.team = tok_team and tok_team:GetUInt32() or 0
            reader:ReadToken();
            local tok_label = reader:ReadToken()
            obj.label = tok_label and tok_label:GetString() or ""
            reader:ReadToken();
            local tok_user = reader:ReadToken()
            obj.isUser = tok_user and (tok_user:GetUInt32() ~= 0) or false
            reader:ReadToken() -- obj_addr
            if bzn.version > 1001 then
                reader:ReadToken();
                local tok_trans = reader:ReadToken()
                obj.transform = tok_trans and tok_trans:GetMatrixOld() or SetMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
            end

            if classlabel and ClassReaders[classlabel] then
                ClassReaders[classlabel](obj, reader)
            else
                -- Fallback: try to skip or error? For AutoSave we can't easily skip unknown binary data.
                -- Assuming standard classes. If unknown, we might crash here.
                -- But we only need to reach AiPaths.
                error("Unknown class: " .. tostring(classlabel))
            end
        end

        reader:ReadToken() -- Mission Name
        reader:ReadToken() -- sObject
        if bzn.version == 1044 then reader:ReadToken() end

        if not reader:inBinary() then reader:ReadToken() end -- [AiMission]
        if bzn.version == 1001 or bzn.version == 1011 or bzn.version == 1012 then reader:ReadToken() end
        if bzn.version == 1011 or bzn.version == 1012 then for i = 1, 8 do reader:ReadToken() end end

        if not reader:inBinary() then reader:ReadToken() end -- [AOIs]
        local tok_aois = reader:ReadToken()
        local countAOIs = tok_aois and tok_aois:GetInt32() or 0
        for i = 1, countAOIs do
            if not reader:inBinary() then reader:ReadToken() end
            for j = 1, 6 do reader:ReadToken() end
        end

        if not reader:inBinary() then reader:ReadToken() end -- [AiPaths]
        local tok_paths = reader:ReadToken()
        local countPaths = tok_paths and tok_paths:GetInt32() or 0
        for i = 1, countPaths do
            local p = {}
            if not reader:inBinary() then reader:ReadToken() end -- [AiPath]
            reader:ReadToken()                                   -- old_ptr
            local tok_sz = reader:ReadToken()
            local sz = tok_sz and tok_sz:GetInt32() or 0
            if sz > 0 then
                local tok_plabel = reader:ReadToken()
                p.label = tok_plabel and tok_plabel:GetString() or ""
            end
            local tok_pc = reader:ReadToken()
            local pc = tok_pc and tok_pc:GetInt32() or 0
            if pc > 0 then
                p.points = {}
                reader:ReadToken() -- points
                for j = 1, pc do
                    local tok_pt = reader:ReadToken()
                    p.points[j] = tok_pt and tok_pt:GetVector2D() or SetVector(0, 0, 0)
                end
            end
            local tok_ptype = reader:ReadToken()
            p.pathType = tok_ptype and tok_ptype:GetUInt32H() or 0
            table.insert(bzn.AiPaths, p)
        end

        return bzn
    end
end

local AutoSave = {}
local HandleToID = {} -- Mapping from Handle to SaveID

-- Helper to clean strings
local function CleanString(str)
    if not str then return "" end
    return str:gsub("%z.*", "")
end

-- Helper to convert string to hex
local function StringToHex(str)
    return (str:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function FloatStr(v)
    if v == 0 then return "0" end
    if v > 1e29 then return "1e+030" end
    if v < -1e29 then return "-1e+030" end
    return tostring(v)
end


-- Configuration
AutoSave.Config = {
    enabled = false,
    autoSaveInterval = 300, -- Auto-save every 5 minutes
    currentSlot = 1,        -- Which save slot to use (1-10)
    saveOnObjective = false -- Auto-save when objectives complete
}

-- State
AutoSave.timer = 290.0 -- Set to 290 so it fires shortly after the 10s safe window (total ~20s)
AutoSave.lastSaveTime = 0.0
AutoSave.ActiveObjectives = {}

-- Passive Tracking Hooks
local function TrackObjective(h, state)
    if IsValid(h) then
        if state then
            AutoSave.ActiveObjectives[h] = true
        else
            AutoSave.ActiveObjectives[h] = nil
        end
    end
end

if not _G.oldSetObjectiveOn then
    _G.oldSetObjectiveOn = _G.SetObjectiveOn
    _G.SetObjectiveOn = function(h, color)
        TrackObjective(h, true)
        if _G.oldSetObjectiveOn then return _G.oldSetObjectiveOn(h, color) end
    end
end

if not _G.oldSetObjectiveOff then
    _G.oldSetObjectiveOff = _G.SetObjectiveOff
    _G.SetObjectiveOff = function(h)
        TrackObjective(h, false)
        if _G.oldSetObjectiveOff then return _G.oldSetObjectiveOff(h) end
    end
end

if not _G.oldAddObjective then
    _G.oldAddObjective = _G.AddObjective
    _G.AddObjective = function(h, color, priority)
        TrackObjective(h, true)
        if _G.oldAddObjective then return _G.oldAddObjective(h, color, priority) end
    end
end

if not _G.oldClearObjectives then
    _G.oldClearObjectives = _G.ClearObjectives
    _G.ClearObjectives = function()
        AutoSave.ActiveObjectives = {}
        if _G.oldClearObjectives then return _G.oldClearObjectives() end
    end
end

---
--- Public API
---

-- Create a save file in the specified slot (1-10)
function AutoSave.CreateSave(slotNumber, saveDescription)
    slotNumber = slotNumber or AutoSave.Config.currentSlot
    if slotNumber < 1 or slotNumber > 10 then
        print("AutoSave: Invalid slot number " .. slotNumber)
        return false
    end

    local saveDir = bzfile.GetWorkingDirectory() .. "\\Save"
    local filename = saveDir .. "\\game" .. slotNumber .. ".sav"

    print("AutoSave: [V4-FINAL-FIX] Generating save file: " .. filename)

    print("AutoSave: Collecting objectives from tracked list...")
    AutoSave.CurrentObjectives = {}
    local count = 0
    for h, _ in pairs(AutoSave.ActiveObjectives) do
        if IsValid(h) then
            count = count + 1
            AutoSave.CurrentObjectives[h] = true
        end
    end
    print("AutoSave: Found " .. count .. " active objectives.")

    -- Selection is omitted for engine stability
    AutoSave.CurrentSelected = {}

    print("AutoSave: Opening file for writing: " .. filename)
    local file = bzfile.Open(filename, "w", "trunc")
    if not file then
        print("AutoSave: Failed to open file for writing: " .. filename)
        return false
    end

    print("AutoSave: Writing contents...")
    -- Write save file content
    AutoSave._WriteSaveFile(file, saveDescription)

    -- Close file
    file:Close()

    print("AutoSave: Save complete!")
    AutoSave.lastSaveTime = GetTime()
    return true
end

-- Enable auto-save with specified interval (seconds)
function AutoSave.EnableAutoSave(interval)
    AutoSave.Config.enabled = true
    AutoSave.Config.autoSaveInterval = interval or 300
    print("AutoSave: Enabled (interval: " .. AutoSave.Config.autoSaveInterval .. "s)")
end

function AutoSave.DisableAutoSave()
    AutoSave.Config.enabled = false
    print("AutoSave: Disabled")
end

-- Set which save slot to use
function AutoSave.SetSlot(slotNumber)
    if slotNumber >= 1 and slotNumber <= 10 then
        AutoSave.Config.currentSlot = slotNumber
    end
end

-- Update function (call from mission Update())
function AutoSave.Update()
    -- Check PersistentConfig first, fallback to internal config
    local enabled = AutoSave.Config.enabled
    local config = package.loaded["PersistentConfig"]
    if config and config.Settings then
        enabled = config.Settings.enableAutoSave
    end

    if not enabled then return end

    -- Safety: Do not autosave in the first 10 seconds of a mission to avoid engine load locks
    if GetTime() < 10.0 then return end

    AutoSave.timer = AutoSave.timer + GetTimeStep()
    if AutoSave.timer >= AutoSave.Config.autoSaveInterval then
        AutoSave.CreateSave()
        AutoSave.timer = 0.0
    end
end

-- Helper to get classLabel from ODF
local function GetClassLabel(obj)
    local odf = GetOdf(obj)
    if not odf then return nil end
    local odfh = OpenODF(odf)
    if not odfh then return nil end
    local label, found = GetODFString(odfh, "GameObjectClass", "classLabel")
    return found and label:lower() or nil
end

-- Global state to save (defaults to matching mission M table)
AutoSave.SaveTable = nil

-- Recursive Lua value writer
-- Recursive Lua value writer with robust cycle detection
local function WriteLuaValue(file, val, visited)
    visited = visited or {}
    local vType = type(val)

    if vType == "table" then
        if visited[val] then
            file:Writeln("type [1] =")
            file:Writeln("0") -- DATA_VOID for cycles
            return
        end
        visited[val] = true

        local count = 0
        for k in pairs(val) do
            -- Exclude common high-recursion/engine keys
            if k ~= "teamObj" and k ~= "parent" and k ~= "_G" and k ~= "package" then
                count = count + 1
            end
        end

        file:Writeln("type [1] =")
        file:Writeln("5")
        file:Writeln("count [1] =")
        file:Writeln(tostring(count))

        for k, v in pairs(val) do
            if k ~= "teamObj" and k ~= "parent" and k ~= "_G" and k ~= "package" then
                WriteLuaValue(file, k, visited)
                WriteLuaValue(file, v, visited)
            end
        end
    elseif vType == "boolean" then
        file:Writeln("type [1] =")
        file:Writeln("1")
        file:Writeln("b [1] =")
        file:Writeln(val and "true" or "false")
    elseif vType == "number" then
        file:Writeln("type [1] =")
        file:Writeln("3")
        file:Writeln("f [1] =")
        file:Writeln(FloatStr(val))
    elseif vType == "userdata" then
        local id = HandleToID and HandleToID[val] or 0
        file:Writeln("type [1] =")
        file:Writeln("2")
        file:Writeln("h [1] =")
        file:Writeln(tostring(id))
    elseif vType == "string" then
        file:Writeln("type [1] =")
        file:Writeln("4")
        file:Writeln("l [1] =")
        file:Writeln(tostring(#val))
        file:Writeln("s = " .. val)
    else
        file:Writeln("type [1] =")
        file:Writeln("0")
    end
end

---
--- Internal Writers
---

local function WriteProp(file, key, value, isArray)
    if isArray then
        file:Writeln(key .. " [1] =")
        file:Writeln(tostring(value))
    else
        file:Writeln(key .. " = " .. tostring(value))
    end
end


function AutoSave._WriteSaveFile(file, saveDescription)
    -- Assign IDs
    local idCounter = 1
    for obj in AllObjects() do
        HandleToID[obj] = idCounter
        idCounter = idCounter + 1
    end

    -- Header
    WriteProp(file, "version", "2016", true)
    WriteProp(file, "binarySave", "false", true)
    file:Writeln("msn_filename = " .. GetMissionFilename())
    WriteProp(file, "seq_count", idCounter + 1000, true)
    WriteProp(file, "missionSave", "false", true)
    WriteProp(file, "runType", "0", true)

    local desc = saveDescription or ("AutoSave " .. tostring(math.floor(GetTime())))
    file:Writeln("saveGameDesc = " .. StringToHex(desc) .. "00")

    local playerHandle = GetPlayerHandle()
    local nationMap = { a = "usa", s = "cca", b = "bdog", c = "cra" }
    local playerSide = "usa"
    if IsValid(playerHandle) then
        local nat = GetNation(playerHandle)
        if nat and nationMap[nat] then playerSide = nationMap[nat] end
    end
    file:Writeln("nPlayerSide = " .. playerSide)
    WriteProp(file, "nMissionStatus", "0", true)
    WriteProp(file, "nOldMissionMode", "1", true)
    local terrain = GetMapTRNFilename() or ""
    terrain = terrain:gsub("%.trn$", "")
    file:Writeln("TerrainName = " .. terrain)
    WriteProp(file, "start_time", GetTime(), true)
    WriteProp(file, "size", idCounter - 1, true)

    -- Iterate through all game objects
    for obj in AllObjects() do
        AutoSave._WriteGameObject(file, obj)
    end

    -- Team Globals (Resources) - No header in sav
    AutoSave._WriteTeamGlobals(file)

    -- Mission State (LuaMission) - No header in sav
    AutoSave._WriteLuaMission(file)

    -- AI Sections - With headers
    AutoSave._WriteAiMission(file)
    AutoSave._WriteAOIs(file)
    AutoSave._WriteAiPaths(file)
    AutoSave._WriteAiTasks(file)
    AutoSave._WriteMissionFooter(file)
end

function AutoSave._WriteLuaMission(file)
    -- We'll write the LuaMission state if SaveTable is provided
    -- Priority: AutoSave.SaveTable > Global Save() function > Global M table
    local state = AutoSave.SaveTable

    if not state then
        if Save and type(Save) == "function" then
            -- Mission uses custom Save() function (like misn02b.lua)
            -- Save() returns (missionData, aiData)
            local missionData, aiData = Save()
            state = { missionData, aiData }
        else
            -- Default to global M table if it exists
            state = _G.M or {}
        end
    end

    -- If state is a single table and not a list of tables to be saved,
    -- wrap it in a list so we can iterate.
    -- We assume if it has a count > 0 and the first element is a table, it's a multi-save.
    local tables = {}
    if type(state) == "table" and state[1] ~= nil then
        tables = state
    else
        tables = { state }
    end

    file:Writeln("name = LuaMission")
    file:Writeln("sObject = 00000063")      -- Engine assigned ID
    WriteProp(file, "started", "true", true)
    WriteProp(file, "count", #tables, true) -- Number of script objects

    for _, tbl in ipairs(tables) do
        WriteLuaValue(file, tbl)
    end
end

function AutoSave._WriteTeamGlobals(file)
    for i = 0, 15 do
        WriteProp(file, "curScrap", GetScrap(i) or 0, true)
        WriteProp(file, "maxScrap", GetMaxScrap(i) or 0, true)
        WriteProp(file, "curPilot", GetPilot(i) or 0, true)
        WriteProp(file, "maxPilot", GetMaxPilot(i) or 0, true)

        local allies = 0
        for j = 0, 15 do
            if i == j or (IsTeamAllied and IsTeamAllied(i, j)) then
                allies = allies + (2 ^ j)
            end
        end
        WriteProp(file, "dwAllies", allies, true)
    end
end

function AutoSave._WriteGameObject(file, obj)
    if not IsValid(obj) then return end

    local id = HandleToID[obj] or 0
    local odf = CleanString(GetOdf(obj))
    local team = GetTeamNum(obj)
    local pos = GetPosition(obj)
    local label = GetLabel(obj) or ""

    file:Writeln("[GameObject]")
    WriteProp(file, "PrjID", odf, true)
    WriteProp(file, "seqno", id, true)

    -- Primary Position
    if pos then
        file:Writeln("pos [1] =")
        file:Writeln("  x [1] =")
        file:Writeln(tostring(pos.x))
        file:Writeln("  y [1] =")
        file:Writeln(tostring(pos.y))
        file:Writeln("  z [1] =")
        file:Writeln(tostring(pos.z))
    end

    WriteProp(file, "team", team, true)
    file:Writeln("label = " .. label)
    WriteProp(file, "isUser", (obj == GetPlayerHandle() and "1" or "0"), true)
    file:Writeln("obj_addr = " .. string.format("%08x", id))

    -- Transform Section
    AutoSave._WriteTransform(file, obj)

    WriteProp(file, "tempBuilding", "false", true)
    WriteProp(file, "illumination", "1", true)

    -- Second Position (Physics Pos)
    if pos then
        file:Writeln("pos [1] =")
        file:Writeln("  x [1] =")
        file:Writeln(tostring(pos.x))
        file:Writeln("  y [1] =")
        file:Writeln(tostring(pos.y))
        file:Writeln("  z [1] =")
        file:Writeln(tostring(pos.z))
    end

    -- Euler / Physics Section
    AutoSave._WritePhysics(file, obj)

    WriteProp(file, "seqNo", id, true)
    file:Writeln("name = ")

    WriteProp(file, "isCritical", (IsCritical(obj) and "true" or "false"), true)
    WriteProp(file, "isObjective", (AutoSave.CurrentObjectives[obj] and "true" or "false"), true)
    WriteProp(file, "isSelected", (AutoSave.CurrentSelected[obj] and "true" or "false"), true)
    WriteProp(file, "isVisible", "2", true)
    WriteProp(file, "seen", "2", true)

    -- Timers, Health, Ammo
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

    AutoSave._WriteHealthAmmo(file, obj)

    -- AI State / Priorities
    AutoSave._WriteAIState(file, obj)

    file:Writeln("undefptr = 00000002")
    WriteProp(file, "isCargo", "false", true)
    WriteProp(file, "independence", "1", true)

    -- Pilot Information
    local pilot = GetPilotClass(obj)
    WriteProp(file, "curPilot", (pilot and CleanString(pilot) or ""), true)
    WriteProp(file, "perceivedTeam", GetPerceivedTeam(obj), true)

    for w = 0, 4 do
        local wClass = GetWeaponClass(obj, w)
        WriteProp(file, "wpnID", (wClass and CleanString(wClass) or ""), true)
    end

    WriteProp(file, "enabled", "f", true)
    WriteProp(file, "selected", (obj == GetPlayerHandle() and "1" or "0"), true)
end

function AutoSave._WriteTransform(file, obj)
    local transform = GetTransform(obj)
    if transform then
        file:Writeln("transform [1] =")
        -- Orientation Matrix
        file:Writeln("  right_x [1] =")
        file:Writeln(tostring(transform.right.x))
        file:Writeln("  right_y [1] =")
        file:Writeln(tostring(transform.right.y))
        file:Writeln("  right_z [1] =")
        file:Writeln(tostring(transform.right.z))
        file:Writeln("  up_x [1] =")
        file:Writeln(tostring(transform.up.x))
        file:Writeln("  up_y [1] =")
        file:Writeln(tostring(transform.up.y))
        file:Writeln("  up_z [1] =")
        file:Writeln(tostring(transform.up.z))
        file:Writeln("  front_x [1] =")
        file:Writeln(tostring(transform.front.x))
        file:Writeln("  front_y [1] =")
        file:Writeln(tostring(transform.front.y))
        file:Writeln("  front_z [1] =")
        file:Writeln(tostring(transform.front.z))
        -- Origin Position
        file:Writeln("  posit_x [1] =")
        file:Writeln(tostring(transform.posit.x))
        file:Writeln("  posit_y [1] =")
        file:Writeln(tostring(transform.posit.y))
        file:Writeln("  posit_z [1] =")
        file:Writeln(tostring(transform.posit.z))
    end
end

function AutoSave._WritePhysics(file, obj)
    local vel = GetVelocity(obj)
    local omega = GetOmega(obj)
    local v_mag = math.sqrt(vel.x ^ 2 + vel.y ^ 2 + vel.z ^ 2)
    local mass = 1750 -- Default mass
    if exu and exu.GetMass then
        local m = exu.GetMass(obj)
        if m and m > 0 then mass = m end
    end
    -- Geyser special case
    local odf = CleanString(GetOdf(obj)):lower()
    if odf:find("geizr") or odf:find("geyser") then
        mass = 0
    end

    file:Writeln("euler =")
    file:Writeln(" mass [1] =")
    file:Writeln(tostring(mass))
    file:Writeln(" mass_inv [1] =")
    file:Writeln(FloatStr(mass > 0 and 1 / mass or 1e+030))
    file:Writeln(" v_mag [1] =")
    file:Writeln(FloatStr(v_mag))
    file:Writeln(" v_mag_inv [1] =")
    file:Writeln(FloatStr(v_mag > 0 and 1 / v_mag or 1e+030))
    file:Writeln(" I [1] =")
    file:Writeln("1")
    file:Writeln(" k_i [1] =")
    file:Writeln("0")

    file:Writeln(" v [1] =")
    file:Writeln("  x [1] =")
    file:Writeln(tostring(vel.x))
    file:Writeln("  y [1] =")
    file:Writeln(tostring(vel.y))
    file:Writeln("  z [1] =")
    file:Writeln(tostring(vel.z))

    file:Writeln(" omega [1] =")
    file:Writeln("  x [1] =")
    file:Writeln(tostring(omega.x))
    file:Writeln("  y [1] =")
    file:Writeln(tostring(omega.y))
    file:Writeln("  z [1] =")
    file:Writeln(tostring(omega.z))

    file:Writeln(" Accel [1] =")
    file:Writeln("  x [1] =")
    file:Writeln("-4.31602e+008")
    file:Writeln("  y [1] =")
    file:Writeln("-4.31602e+008")
    file:Writeln("  z [1] =")
    file:Writeln("-4.31602e+008")
end

function AutoSave._WriteHealthAmmo(file, obj)
    -- Health
    local curHealth = GetCurHealth(obj)
    local maxHealth = GetMaxHealth(obj)
    if curHealth and maxHealth then
        WriteProp(file, "healthRatio", (maxHealth > 0 and curHealth / maxHealth or 0), true)
        WriteProp(file, "curHealth", curHealth, true)
        WriteProp(file, "maxHealth", maxHealth, true)
    end

    -- Ammo
    local curAmmo = GetCurAmmo(obj)
    local maxAmmo = GetMaxAmmo(obj)
    if curAmmo and maxAmmo then
        WriteProp(file, "ammoRatio", (maxAmmo > 0 and curAmmo / maxAmmo or 0), true)
        WriteProp(file, "curAmmo", curAmmo, true)
        WriteProp(file, "maxAmmo", maxAmmo, true)
    end
end

function AutoSave._WriteAIState(file, obj)
    local cmd = GetCurrentCommand(obj) or 0
    for i = 1, 2 do
        WriteProp(file, "priority", "0", true)
        file:Writeln("what = " .. string.format("%08x", cmd))
        WriteProp(file, "who", "0", true)
        file:Writeln("where = 00000000")
        WriteProp(file, "param", "", true)
    end
end

function AutoSave._WriteAiMission(file)
    -- This section includes Engine AI task assignments
    file:Writeln("[AiMission]")
    WriteProp(file, "size", "0", true) -- We don't replicate individual task objects yet
end

function AutoSave._WriteAOIs(file)
    file:Writeln("[AOIs]")
    WriteProp(file, "size", "0", true)
end

function AutoSave._WriteAiPaths(file)
    local mapName = GetMissionFilename()
    local bznData = BZN_Open(mapName)

    if bznData and bznData.AiPaths then
        file:Writeln("[AiPaths]")
        WriteProp(file, "count", #bznData.AiPaths, true)

        for _, path in ipairs(bznData.AiPaths) do
            file:Writeln("[AiPath]")
            file:Writeln("old_ptr = 0")

            if path.label then
                WriteProp(file, "size", string.len(path.label) + 1, true)
                file:Writeln("label = " .. path.label)
            else
                WriteProp(file, "size", "0", true)
            end

            local pointCount = path.points and #path.points or 0
            WriteProp(file, "pointCount", pointCount, true)

            if pointCount > 0 then
                file:Writeln("points [" .. pointCount .. "] =")
                for _, pt in ipairs(path.points) do
                    file:Writeln("  x [1] =")
                    file:Writeln(tostring(pt.x))
                    file:Writeln("  z [1] =")
                    file:Writeln(tostring(pt.z))
                end
            end

            local pType = path.pathType
            if path.label and GetPathType then
                pType = GetPathType(path.label)
            end
            file:Writeln("pathType = " .. string.format("%08x", pType))
        end
    else
        file:Writeln("[AiPaths]")
        WriteProp(file, "count", "0", true)
    end
end

function AutoSave._WriteAiTasks(file)
    file:Writeln("[AiTasks]")
    WriteProp(file, "count", "0", true)
end

function AutoSave._WriteMissionFooter(file)
    -- This section includes message queues, AIP assignments, and objective states
    file:Writeln("size [1] =")
    file:Writeln("0") -- Message queue size
    file:Writeln("seqNo [1] =")
    file:Writeln("0")
    file:Writeln("msg = ")
    file:Writeln("lastMsg = ")

    file:Writeln("aip_team_count [1] =")
    file:Writeln("1") -- Assume at least team 2 has an AIP if it's a mission
    file:Writeln("team [1] =")
    file:Writeln("2")
    file:Writeln("aipName = ") -- AIP filename without extension

    WriteProp(file, "difficultySetting", "1", true)

    -- Camera State Deduction:
    -- cameraReady is true if a cinematic camera is active.
    -- We deduce this by checking if a pan is in progress (not PanDone).
    -- Or if the mission explicitly tracks it in M.camera_ready.
    local state = AutoSave.SaveTable or _G.M or {}
    local isCinematic = (state.camera_ready == true) or (state.cinematic == true)
    if not isCinematic then
        -- PanDone() returns false if a CameraPath is moving.
        if PanDone and not PanDone() then
            isCinematic = true
        end
    end

    WriteProp(file, "cameraReady", (isCinematic and "true" or "false"), true)
    WriteProp(file, "cameraCallCount", "0", true)
    WriteProp(file, "quakeMag", "0", true)
    WriteProp(file, "frac", "0", true)
    WriteProp(file, "timer", "0", true)

    file:Writeln("warn [1] =")
    file:Writeln("-2147483648")
    file:Writeln("alert [1] =")
    file:Writeln("-2147483648")

    WriteProp(file, "countdown", "true", true)
    WriteProp(file, "active", "false", true)
    WriteProp(file, "show", "false", true)

    -- Objectives
    local objCount = 0
    for _ in pairs(AutoSave.CurrentObjectives) do objCount = objCount + 1 end
    WriteProp(file, "objectiveCount", objCount, true)

    -- In a real save, these match the OTF names and colors
    -- For now we leave placeholders if count > 0
    for obj in pairs(AutoSave.CurrentObjectives) do
        file:Writeln("name = mission.otf")
        file:Writeln("color [1] =")
        file:Writeln("-1") -- White
    end

    WriteProp(file, "objectiveLast", FloatStr(GetTime()), true)

    -- Groups (Group keys 0-9)
    file:Writeln("groupNum = 00000000000000000000000000000000000000000000000000000000000000000000000000000000")
    file:Writeln(
        "groupList = 00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
end

return AutoSave
