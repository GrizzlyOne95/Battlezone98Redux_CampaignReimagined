--[[
    PhysicsImpact.lua (v1.5.0)
    Adds data-driven recoil, knockback, and camera shake to weapons.

    This module centralizes physical weapon behaviors.
    It maps effects to Ordnance names via a tuning table.
--]]

---@diagnostic disable: undefined-global
---@class exu
local exu = require("exu")

local PhysicsImpact = {
    -- Global tuning multipliers (reduced for less intrusive feel)
    GlobalRecoil = 0.3,
    GlobalKnockback = 0.5,
    GlobalShake = 0.15,

    -- The master table for fine-tuning
    -- recoil, knockback, shake: multipliers for forces
    Weapons = {
        -- HEAVY CANNONS (keep super heavy)
        ["blast"]    = { recoil = 12.0, knockback = 18.0, shake = 1.5 }, -- gblast
        ["blastb"]   = { recoil = 14.0, knockback = 20.0, shake = 1.8 }, -- gblastb
        ["blastg"]   = { recoil = 10.0, knockback = 15.0, shake = 1.3 }, -- gblastg
        ["bolt"]     = { recoil = 3.0, knockback = 5.0, shake = 0.6 },
        ["snipe"]    = { recoil = 15.0, knockback = 20.0, shake = 2.0 },

        -- MACHINE GUNS (barely perceptible now)
        ["bullet1"]  = { recoil = 0.05, knockback = 0.1, shake = 0.02 },
        ["bullet1a"] = { recoil = 0.08, knockback = 0.15, shake = 0.03 },
        ["bullet1b"] = { recoil = 0.05, knockback = 0.1, shake = 0.02 },
        ["bullet1g"] = { recoil = 0.05, knockback = 0.1, shake = 0.02 },
        ["bullet2"]  = { recoil = 0.1, knockback = 0.2, shake = 0.04 },
        ["bullet5"]  = { recoil = 0.1, knockback = 0.2, shake = 0.04 },
        ["bullet6"]  = { recoil = 0.15, knockback = 0.25, shake = 0.03 },
        ["bullet6a"] = { recoil = 0.15, knockback = 0.25, shake = 0.03 },

        -- ROCKETS / MISSILES (moderate - impactful but not crazy)
        ["rocket"]   = { recoil = 4.0, knockback = 8.0, shake = 0.6 },
        ["rocket2"]  = { recoil = 5.0, knockback = 10.0, shake = 0.8 },
        ["rocket3"]  = { recoil = 3.5, knockback = 7.0, shake = 0.5 },
        ["heatmsl"]  = { recoil = 2.5, knockback = 6.0, shake = 0.4 },
        ["imagemsl"] = { recoil = 1.5, knockback = 4.0, shake = 0.3 },
        ["swarmer"]  = { recoil = 0.8, knockback = 1.5, shake = 0.15 },

        -- MORTARS / GRENADES (keep heavy)
        ["grenade"]  = { recoil = 15.0, knockback = 25.0, shake = 2.5 },
        ["splintbm"] = { recoil = 8.0, knockback = 4.0, shake = 1.0 },
        ["splinter"] = { recoil = 0.0, knockback = 4.0, shake = 0.0 },
        ["bouncebm"] = { recoil = 18.0, knockback = 30.0, shake = 3.0 },

        -- CHARGE WEAPONS (scale with charge level)
        ["charge1"]  = { recoil = 0.5, knockback = 1.0, shake = 0.1 },
        ["charge2"]  = { recoil = 1.5, knockback = 3.0, shake = 0.3 },
        ["charge3"]  = { recoil = 3.0, knockback = 6.0, shake = 0.6 },
        ["charge4"]  = { recoil = 5.0, knockback = 10.0, shake = 1.0 },
        ["charge5"]  = { recoil = 8.0, knockback = 15.0, shake = 1.5 },
        ["charge6"]  = { recoil = 12.0, knockback = 22.0, shake = 2.2 },

        -- SPECIAL
        ["flashch"]  = { recoil = 0.0, knockback = 0.1, shake = 0.0 },
        ["seismic"]  = { recoil = 5, knockback = 50.0, shake = 5.0 },
    },

    Cache = {},
    StockPath = nil
}

local function GetStats(odfName)
    if PhysicsImpact.Weapons[odfName] then return PhysicsImpact.Weapons[odfName] end
    if PhysicsImpact.Cache[odfName] then return PhysicsImpact.Cache[odfName] end

    -- Fallback to ODF parsing if path is provided
    if not PhysicsImpact.StockPath then
        return { recoil = 1.0, knockback = 1.0, shake = 0.2 } -- Generic fallback
    end

    local totalDamage = 0
    local speed = 100

    local calculated = { recoil = 1, knockback = 1, shake = 0.2 }
    local f = io.open(PhysicsImpact.StockPath .. odfName .. ".odf", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w%d_]+)%s*=%s*([^%s;]+)")
            if k then
                if k:find("^damage") then
                    totalDamage = totalDamage + (tonumber(v) or 0)
                elseif k == "shotSpeed" then
                    speed = tonumber(v) or speed
                end
            end
        end
        f:close()
    else
        -- Absolute fallback if file missing
        totalDamage = 50
    end

    local speedFactor = math.log10(speed + 1)

    -- Recalculate based on parsed values
    calculated = {
        recoil = (totalDamage * speedFactor) * 0.02,
        knockback = (totalDamage * speedFactor) * 0.05,
        shake = (totalDamage * speedFactor) * 0.005
    }

    PhysicsImpact.Cache[odfName] = calculated
    return calculated
end

function exu.BulletInit(odf, shooter, transform)
    if not IsValid(shooter) then return end

    local stats = GetStats(odf)
    if stats.recoil <= 0 and stats.shake <= 0 then return end

    local front = SetVector(transform.front_x, transform.front_y, transform.front_z)
    local dir = Normalize(front)

    -- Linear Recoil (Opposite to firing direction)
    local recoilVal = stats.recoil * PhysicsImpact.GlobalRecoil
    if recoilVal > 0 then
        local vel = GetVelocity(shooter)
        SetVelocity(shooter, vel - (dir * recoilVal))
    end

    -- Rotational Shake (Refined player-specific logic)
    local shakeVal = stats.shake * PhysicsImpact.GlobalShake
    if shakeVal > 0 then
        local omega = GetOmega(shooter)
        if shooter == GetPlayerHandle() then
            -- More intense/natural shake for the player camera
            local pitch = math.random(5, 30) * 0.1 * shakeVal
            local yaw = math.random(-25, 25) * 0.01 * shakeVal
            SetOmega(shooter, SetVector(omega.x + pitch, omega.y + yaw, omega.z))
        else
            -- Subtle random jitter for AI/external observers
            local pitch = (math.random() * 2 - 1) * shakeVal * 0.5
            local yaw = (math.random() * 2 - 1) * shakeVal * 0.25
            SetOmega(shooter, SetVector(omega.x + pitch, omega.y + yaw, omega.z))
        end
    end
end

function exu.BulletHit(odf, shooter, hitObject, transform, ordnanceHandle)
    local stats = GetStats(odf)

    -- 1. KNOCKBACK (Physics)
    if IsValid(hitObject) and stats.knockback > 0 then
        local front = SetVector(transform.front_x, transform.front_y, transform.front_z)
        local dir = Normalize(front)
        local vel = GetVelocity(hitObject)
        SetVelocity(hitObject, vel + (dir * stats.knockback * PhysicsImpact.GlobalKnockback))
    end
end

local count = 0
for _ in pairs(PhysicsImpact.Weapons) do count = count + 1 end
print("PhysicsImpact v1.5 loaded with " .. tostring(count) .. " tuned ordnances.")
return PhysicsImpact
