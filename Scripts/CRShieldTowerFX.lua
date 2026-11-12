-- CRShieldTowerFX: a translucent box over every shield tower showing the push field.
-- Peer-local presentation only: every client reads the same ODF box and draws it,
-- nothing is sent over the network. Drawn only while the tower is powered.
-- Hooked from RuntimeEnhancements (OnObjectCreated / Update / ResetVisualState).
local okExu, exu = pcall(require, "exu")
if not okExu then exu = _G.exu end

local M = {}

M.MESH = "cube_10x10x10.mesh"         -- unit cube (10 m), origin at the centre of the base
M.MESH_SIZE = 10.0
M.MATERIAL = "CR_ShieldTowerField_Green"
M.DEFAULT_POWER_RANGE = 200.0         -- used when a plant ODF has no [PowerPlantClass] powerRadius
M.POWER_INTERVAL = 0.5                -- seconds between power re-evaluations per tower
M.RETRY_INTERVAL = 10.0               -- back-off after a failed build (missing API, bad transform)
M.BOX_DEFAULT = { MinX = -12.0, MaxX = 12.0, MinY = -4.0, MaxY = 24.0, MinZ = -12.0, MaxZ = 12.0 }

local towers = {}       -- handle -> state
local plants = {}       -- handle -> true
local boxCache = {}     -- odf name -> box
local rangeCache = {}   -- odf name -> power radius
local scanned = false

local function now()
    return GetTime and GetTime() or 0.0
end

local function valid(h)
    return h ~= nil and IsValid ~= nil and IsValid(h) and true or false
end

local function odfName(h)
    local ok, name = pcall(function() return GetOdf and GetOdf(h) or nil end)
    if not ok or type(name) ~= "string" then return nil end
    name = name:gsub("%z.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

local function openOdf(name)
    if not (OpenODF and GetODFFloat) then return nil end
    local ok, odf = pcall(OpenODF, name:lower():find("%.odf$") and name or (name .. ".odf"))
    if ok then return odf end
    return nil
end

local function classLabel(h)
    local ok, label = pcall(function() return GetClassLabel and GetClassLabel(h) or nil end)
    if ok and type(label) == "string" then return label:lower() end
    return nil
end

local function readBox(name)
    if boxCache[name] then return boxCache[name] end
    local box = {}
    local odf = openOdf(name)
    for key, default in pairs(M.BOX_DEFAULT) do
        local value = default
        if odf then
            local ok, v = pcall(GetODFFloat, odf, "ShieldTowerClass", "shield" .. key, default)
            if ok and tonumber(v) then value = tonumber(v) end
        end
        box[key] = value
    end
    boxCache[name] = box
    return box
end

local function readRange(name)
    if rangeCache[name] then return rangeCache[name] end
    local range = M.DEFAULT_POWER_RANGE
    local odf = openOdf(name)
    if odf then
        local ok, v = pcall(GetODFFloat, odf, "PowerPlantClass", "powerRadius", range)
        if ok and tonumber(v) and tonumber(v) > 0 then range = tonumber(v) end
    end
    rangeCache[name] = range
    return range
end

local function position(h)
    local ok, p = pcall(GetPosition, h)
    -- GetPosition returns a VECTOR userdata, not a table
    if ok and p ~= nil and p.x then return p.x, p.y or 0.0, p.z or 0.0 end
    return nil
end

local function allied(a, b)
    local ta = GetTeamNum and GetTeamNum(a)
    local tb = GetTeamNum and GetTeamNum(b)
    if ta == nil or tb == nil then return false end
    if ta == tb then return true end
    if IsTeamAllied then
        local ok, r = pcall(IsTeamAllied, ta, tb)
        if ok and r then return true end
    end
    return false
end

-- Stand-in used when exu.IsPowered is missing or returns nil: an own or allied
-- power plant within its powerRadius (200 m when the ODF has none).
local function fallbackPowered(tower)
    local tx, ty, tz = position(tower.handle)
    if not tx then return false end
    for plant in pairs(plants) do
        if not valid(plant) then
            plants[plant] = nil
        elseif allied(tower.handle, plant) then
            local px, py, pz = position(plant)
            if px then
                local range = readRange(odfName(plant) or "")
                local dx, dy, dz = px - tx, py - ty, pz - tz
                if dx * dx + dy * dy + dz * dz <= range * range then return true end
            end
        end
    end
    return false
end

local function isPowered(tower)
    if type(exu) == "table" and type(exu.IsPowered) == "function" then
        local ok, r = pcall(exu.IsPowered, tower.handle)
        if ok and type(r) == "boolean" then return r end
    end
    return fallbackPowered(tower)
end

local function destroyGeometry(tower)
    if tower.built and type(exu) == "table" and type(exu.DestroyStaticGeometry) == "function" then
        pcall(exu.DestroyStaticGeometry, tower.name)
    end
    tower.built = false
end

local function build(tower)
    if not (type(exu) == "table" and type(exu.CreateStaticGeometry) == "function") then return end
    local box = tower.box
    local size = { x = box.MaxX - box.MinX, y = box.MaxY - box.MinY, z = box.MaxZ - box.MinZ }
    local ok, t = pcall(GetTransform, tower.handle)
    if not ok or t == nil then return end  -- MAT_3D is userdata
    local lx, ly, lz = (box.MinX + box.MaxX) * 0.5, box.MinY, (box.MinZ + box.MaxZ) * 0.5
    local wx = (t.posit_x or 0) + (t.right_x or 1) * lx + (t.up_x or 0) * ly + (t.front_x or 0) * lz
    local wy = (t.posit_y or 0) + (t.right_y or 0) * lx + (t.up_y or 1) * ly + (t.front_y or 0) * lz
    local wz = (t.posit_z or 0) + (t.right_z or 0) * lx + (t.up_z or 0) * ly + (t.front_z or 1) * lz
    -- the mesh origin sits at the centre of the cube's base, so wy is the box floor
    local yaw = math.atan2(t.front_x or 0, t.front_z or 1)
    local material = M.MATERIAL
    local origin = { x = wx, y = wy + size.y * 0.5, z = wz }
    local instances = { { position = { x = wx, y = wy, z = wz }, yaw = yaw,
        scale = { x = size.x / M.MESH_SIZE, y = size.y / M.MESH_SIZE, z = size.z / M.MESH_SIZE } } }
    local extent = math.max(size.x, size.y, size.z) + 16.0
    destroyGeometry(tower)
    local okCall, info = pcall(exu.CreateStaticGeometry, tower.name, M.MESH, material, instances,
        { origin = origin, regionDimensions = { x = extent, y = extent, z = extent },
          renderingDistance = 0.0, castShadows = false, visible = true })
    tower.built = okCall and info ~= nil and info ~= false
end

function M.Track(h)
    if towers[h] or not valid(h) then return end
    local label = classLabel(h)
    if label == "powerplant" then
        plants[h] = true
        return
    end
    if label ~= "shieldtower" then return end
    local name = odfName(h)
    if not name then return end
    towers[h] = { handle = h, odf = name, box = readBox(name), name = "CR_ShieldTowerFX_" .. tostring(h),
        nextCheck = 0.0, built = false }
end

local function scanExisting()
    scanned = true
    if type(AllObjects) ~= "function" then return end
    pcall(function()
        for h in AllObjects() do M.Track(h) end
    end)
end

function M.Reset()
    for _, tower in pairs(towers) do destroyGeometry(tower) end
    towers = {}
    plants = {}
    scanned = false
end

function M.Update()
    if not scanned then scanExisting() end
    local t = now()
    for h, tower in pairs(towers) do
        if not valid(h) then
            destroyGeometry(tower)
            towers[h] = nil
        elseif t >= tower.nextCheck then
            tower.nextCheck = t + M.POWER_INTERVAL
            if not isPowered(tower) then
                destroyGeometry(tower)
            elseif not tower.built then
                build(tower)
                if not tower.built then tower.nextCheck = t + M.RETRY_INTERVAL end
            end
        end
    end
end

function M.Describe()
    local n = 0
    for _ in pairs(towers) do n = n + 1 end
    return { towers = n }
end

return M
