local exu = require("exu")

-- Swap the player's vehicle material shortly after mission start.
function Start()
    local player = GetPlayerHandle()
    local subCount = exu.GetSubMaterialCount(player)
    print("SubEntity count:", subCount)

    -- Apply one material across all submeshes.
    local ok = exu.SetMaterial(player, "bz98redux/shader_vehicle")
    if not ok then
        print("exu.SetMaterial failed: render entity not found for handle")
    else
        print("Entity material is now:", exu.GetMaterial(player))
    end

    -- Optionally override one submesh afterwards.
    -- Example: sub-entity 0 gets a different material.
    if (subCount or 0) > 0 then
        exu.SetSubMaterial(player, 0, "bz98redux/shader_glass")
        print("SubEntity 0 material is now:", exu.GetSubMaterial(player, 0))
    end
end
