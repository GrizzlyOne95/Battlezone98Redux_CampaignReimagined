-- MaterialTracker.lua
-- Terrain Material Query System for Battlezone 98 Redux
-- Parses binary .mat files and provides fast material lookups at world coordinates

-- Import utility for string cleansing (null-padding bug fix)
local utility = utility or {}
utility.CleanString = utility.CleanString or function(s)
    if s == nil then return "" end
    -- Remove null padding from engine strings (GetOdf, GetClassLabel, etc.)
    return string.match(s, "^([^%z]*)")
end

local MaterialTracker = {}

-- Module state
MaterialTracker.isLoaded = false
MaterialTracker.materialData = nil
MaterialTracker.mapWidth = 0
MaterialTracker.mapHeight = 0
MaterialTracker.zonesPerRow = 0
MaterialTracker.zonesPerCol = 0
MaterialTracker.trnFilename = ""
MaterialTracker.matFilename = ""
MaterialTracker.lavaMaterialIndex = nil  -- Material index that represents lava

-- Constants
local ZONE_SIZE = 64        -- 64x64 tiles per zone
local TILE_SIZE = 2         -- 2 world units per tile
local ZONE_WORLD_SIZE = ZONE_SIZE * TILE_SIZE  -- 128 world units per zone

---
--- Public API
---

-- Check if material data is loaded
function MaterialTracker.IsLoaded()
    return MaterialTracker.isLoaded
end

-- Check if a material index is lava
function MaterialTracker.IsLavaMaterial(materialIndex)
    return MaterialTracker.lavaMaterialIndex and materialIndex == MaterialTracker.lavaMaterialIndex
end

-- Get the lava material index
function MaterialTracker.GetLavaMaterialIndex()
    return MaterialTracker.lavaMaterialIndex
end

-- Initialize and cache material data
-- Returns true on success, false on failure
function MaterialTracker.Init()
    MaterialTracker.isLoaded = false
    
    -- Get terrain filename (clean null-padding)
    MaterialTracker.trnFilename = utility.CleanString(GetMapTRNFilename())
    if not MaterialTracker.trnFilename or MaterialTracker.trnFilename == "" then
        print("MaterialTracker: Failed to get TRN filename")
        return false
    end
    
    -- Extract map dimensions from TRN
    if not MaterialTracker._ParseMapDimensions() then
        print("MaterialTracker: Failed to parse map dimensions")
        return false
    end
    
    -- Derive .mat filename (replace .trn extension with .mat)
    MaterialTracker.matFilename = string.gsub(MaterialTracker.trnFilename, "%.trn$", ".mat")
    
    -- Load and parse .mat file
    if not MaterialTracker._LoadMaterialFile() then
        print("MaterialTracker: Failed to load .mat file: " .. MaterialTracker.matFilename)
        return false
    end
    
    MaterialTracker.isLoaded = true
    print("MaterialTracker: Initialized successfully")
    print("  Map: " .. MaterialTracker.trnFilename)
    print("  Size: " .. MaterialTracker.mapWidth .. "x" .. MaterialTracker.mapHeight)
    print("  Zones: " .. MaterialTracker.zonesPerRow .. "x" .. MaterialTracker.zonesPerCol)
    
    return true
end

-- Get base material index at world coordinates
-- Returns material index (0-15) or nil if out of bounds
function MaterialTracker.GetMaterialAt(x, z)
    if not MaterialTracker.isLoaded then return nil end
    
    local info = MaterialTracker._GetMaterialEntry(x, z)
    if not info then return nil end
    
    return info.base
end

-- Get full material information at world coordinates
-- Returns table with base, next, cap, flip, rotation, variant or nil if out of bounds
function MaterialTracker.GetMaterialInfo(x, z)
    if not MaterialTracker.isLoaded then return nil end
    
    return MaterialTracker._GetMaterialEntry(x, z)
end

---
--- Internal Implementation
---

-- Parse map dimensions from TRN file
function MaterialTracker._ParseMapDimensions()
    local odf = OpenODF(MaterialTracker.trnFilename)
    if not odf then return false end
    
    -- Try to get map size from TRN
    -- Standard BZ maps are typically 512, 1024, or 2048
    MaterialTracker.mapWidth = GetODFInt(odf, "TerrainClass", "terrainWidth", 0)
    MaterialTracker.mapHeight = GetODFInt(odf, "TerrainClass", "terrainLength", 0)
    
    if MaterialTracker.mapWidth == 0 or MaterialTracker.mapHeight == 0 then
        -- Fallback: assume standard 1024x1024
        MaterialTracker.mapWidth = 1024
        MaterialTracker.mapHeight = 1024
        print("MaterialTracker: Using default map size 1024x1024")
    end
    
    -- Parse lava material index from TRN
    MaterialTracker.lavaMaterialIndex = GetODFInt(odf, "NormalView", "Lava", -1)
    if MaterialTracker.lavaMaterialIndex >= 0 then
        print("MaterialTracker: Lava material index: " .. MaterialTracker.lavaMaterialIndex)
    end
    
    -- Calculate zone count
    MaterialTracker.zonesPerRow = math.ceil(MaterialTracker.mapWidth / ZONE_WORLD_SIZE)
    MaterialTracker.zonesPerCol = math.ceil(MaterialTracker.mapHeight / ZONE_WORLD_SIZE)
    
    return true
end

-- Load and parse binary .mat file
function MaterialTracker._LoadMaterialFile()
    -- Read binary file
    local fileData = UseItem(MaterialTracker.matFilename)
    if not fileData or fileData == "" then
        return false
    end
    
    -- Calculate expected size
    local totalZones = MaterialTracker.zonesPerRow * MaterialTracker.zonesPerCol
    local expectedSize = totalZones * ZONE_SIZE * ZONE_SIZE * 2  -- 2 bytes per entry
    local actualSize = string.len(fileData)
    
    print("MaterialTracker: .mat file size: " .. actualSize .. " bytes (expected ~" .. expectedSize .. ")")
    
    -- Parse all material entries into cached table
    MaterialTracker.materialData = {}
    
    for zoneRow = 0, MaterialTracker.zonesPerCol - 1 do
        for zoneCol = 0, MaterialTracker.zonesPerRow - 1 do
            local zoneIndex = zoneRow * MaterialTracker.zonesPerRow + zoneCol
            
            for localZ = 0, ZONE_SIZE - 1 do
                for localX = 0, ZONE_SIZE - 1 do
                    local entryIndex = zoneIndex * ZONE_SIZE * ZONE_SIZE + localZ * ZONE_SIZE + localX
                    local byteOffset = entryIndex * 2 + 1  -- Lua strings are 1-indexed
                    
                    if byteOffset + 1 <= actualSize then
                        -- Read 16-bit little-endian value
                        local byte1 = string.byte(fileData, byteOffset)      -- LSB
                        local byte2 = string.byte(fileData, byteOffset + 1)  -- MSB
                        
                        -- Decode bitfield
                        local variant = bit.band(byte1, 0x03)                     -- bits 0-1
                        local rotation = bit.rshift(bit.band(byte1, 0x30), 4)     -- bits 4-5
                        local flip = bit.band(byte1, 0x40) ~= 0                   -- bit 6
                        local cap = bit.band(byte1, 0x80) ~= 0                    -- bit 7
                        local next = bit.band(byte2, 0x0F)                        -- bits 8-11
                        local base = bit.rshift(bit.band(byte2, 0xF0), 4)         -- bits 12-15
                        
                        -- Calculate world coordinates for this entry
                        local worldX = zoneCol * ZONE_WORLD_SIZE + localX * TILE_SIZE
                        local worldZ = zoneRow * ZONE_WORLD_SIZE + localZ * TILE_SIZE
                        
                        -- Create key from world coordinates (quantized to tile origins)
                        local key = worldX .. "," .. worldZ
                        
                        -- Cache decoded entry
                        MaterialTracker.materialData[key] = {
                            base = base,
                            next = next,
                            cap = cap,
                            flip = flip,
                            rotation = rotation,
                            variant = variant
                        }
                    end
                end
            end
        end
    end
    
    return true
end

-- Get material entry at world coordinates
function MaterialTracker._GetMaterialEntry(x, z)
    if not MaterialTracker.materialData then return nil end
    
    -- Quantize coordinates to tile origin (southwest corner)
    local tileX = math.floor(x / TILE_SIZE) * TILE_SIZE
    local tileZ = math.floor(z / TILE_SIZE) * TILE_SIZE
    
    -- Bounds check
    if tileX < 0 or tileZ < 0 or tileX >= MaterialTracker.mapWidth or tileZ >= MaterialTracker.mapHeight then
        return nil
    end
    
    -- Lookup cached entry
    local key = tileX .. "," .. tileZ
    return MaterialTracker.materialData[key]
end

---
--- Debug/Utility Functions
---

-- Print material info at coordinates
function MaterialTracker.DebugPrintMaterialAt(x, z)
    local info = MaterialTracker.GetMaterialInfo(x, z)
    if not info then
        print("MaterialTracker: No material data at (" .. x .. ", " .. z .. ")")
        return
    end
    
    print("Material at (" .. x .. ", " .. z .. "):")
    print("  Base: " .. info.base)
    print("  Next: " .. info.next)
    print("  Cap: " .. tostring(info.cap))
    print("  Flip: " .. tostring(info.flip))
    print("  Rotation: " .. info.rotation)
    print("  Variant: " .. info.variant)
end

-- Get statistics about loaded data
function MaterialTracker.GetStats()
    if not MaterialTracker.isLoaded then
        return "MaterialTracker: Not initialized"
    end
    
    local entryCount = 0
    for _ in pairs(MaterialTracker.materialData or {}) do
        entryCount = entryCount + 1
    end
    
    return "MaterialTracker Stats:\n" ..
           "  Loaded: " .. tostring(MaterialTracker.isLoaded) .. "\n" ..
           "  Map: " .. MaterialTracker.mapWidth .. "x" .. MaterialTracker.mapHeight .. "\n" ..
           "  Zones: " .. MaterialTracker.zonesPerRow .. "x" .. MaterialTracker.zonesPerCol .. "\n" ..
           "  Cached Entries: " .. entryCount
end

return MaterialTracker
