-- ShaderSwap.lua
-- Demonstrates how to use ExU's SetShader function to swap shaders at runtime.

local ShaderSwap = {}

-- Definition table: [MaterialName] = { VertexShader, FragmentShader }
-- Note: Set VertexShader or FragmentShader to nil to keep the original.
local ShaderReplacements = {
    -- Example: Replace the terrain shaders with our custom CR_ prefixed ones
    -- Note: The material name "BZTerrainBase" is what the game uses. 
    -- If we replaced the material definition file, the game might load ours instead.
    -- But if we want to SWAP at runtime:
    
    -- ["BZTerrainBase"] = { "CR_TerrainHighPSSM_vertex", "CR_TerrainHighPSSM_fragment" },
}

function ShaderSwap.Apply()
    print("ShaderSwap: Applying custom shaders...")
    
    if not exu or not exu.SetShader then
        print("ShaderSwap: ExtraUtilities SetShader function not found!")
        return
    end

    for materialName, shaders in pairs(ShaderReplacements) do
        local vs = shaders[1]
        local ps = shaders[2]
        
        -- Arguments: materialName, techniqueIndex, passIndex, vertexShader, fragmentShader
        -- We default to technique 0, pass 0 for now. 
        -- If complex materials need specific passes, extend the table structure.
        
        -- Calls SetShader(materialName, technique, pass, vs, ps)
        -- Passing nil for vs/ps means "don't change" (handled by C++ logic if we pass nil/null)
        -- However, Lua -> C++ string conversion for nil might be tricky depending on binding.
        -- Our C++ luaL_optstring handles nil as nullptr (default).
        
        exu.SetShader(materialName, 0, 0, vs, ps)
        print(string.format("ShaderSwap: Swapped %s -> VS: %s, PS: %s", materialName, tostring(vs), tostring(ps)))
    end
    
    print("ShaderSwap: Complete.")
end

-- Run immediately if loaded, or call from Mission Setup
ShaderSwap.Apply()

return ShaderSwap
