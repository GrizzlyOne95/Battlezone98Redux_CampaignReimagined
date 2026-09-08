-- CRReactiveProfiles.lua
-- Data profiles for the Campaign Reimagined reactive presentation layer.
--
-- Everything here is data. CRReactive.lua owns the behaviour; a mission or a
-- new craft only needs a row in these tables, never a new code path. That is
-- the whole point of the split: hit flashes, damage thresholds, particle
-- attachment and cockpit reactions are implemented once.
--
-- Material and particle names below are the *intended* authored assets. Any
-- name that does not exist at runtime is skipped rather than applied, so this
-- file can name the finished art before the art lands. See
-- docs/CR_REACTIVE_PRESENTATION.md for the asset request list.

local CRReactiveProfiles = {}

-- =============================================================================
-- Ordnance families
--
-- BulletHit gives us the ordnance name with the .odf stripped. Classification is
-- longest-prefix, so "bullet6" (the sniper-class round) can differ from
-- "bullet1" without listing every variant.
-- =============================================================================

CRReactiveProfiles.OrdnanceFamilies = {
    -- machine guns: sharp small sparks, a brief armour flash, no smoke
    ["bullet1"]  = "machinegun",
    ["bullet2"]  = "machinegun",
    ["bullet5"]  = "machinegun",
    ["minigun"]  = "machinegun",

    -- cannons: broader hot bloom, ionised armour response, heavier sparks
    ["bullet6"]  = "cannon",
    ["blast"]    = "cannon",
    ["bolt"]     = "cannon",
    ["snipe"]    = "cannon",
    ["stab"]     = "cannon",

    -- rockets and missiles: large flash, smoke and debris, real cockpit jolt
    ["rocket"]   = "rocket",
    ["heatmsl"]  = "rocket",
    ["imagemsl"] = "rocket",
    ["swarmer"]  = "rocket",
    ["shadow"]   = "rocket",

    -- mortars and explosives
    ["grenade"]  = "mortar",
    ["splint"]   = "mortar",
    ["bounce"]   = "mortar",
    ["mortar"]   = "mortar",
    ["mine"]     = "mortar",

    -- energy: Fury and charge weapons read as discharge, not hot metal
    ["charge"]   = "energy",
    ["arcgun"]   = "energy",
    ["tag"]      = "energy",
    ["fury"]     = "energy",
    ["xbio"]     = "energy",
    ["gauss"]    = "energy",
}

CRReactiveProfiles.DefaultOrdnanceFamily = "cannon"

-- =============================================================================
-- Hit profiles
--
-- One entry per ordnance family. `particle` is a template in
-- Materials/cr_reactive.particle; `material` is a transient state applied to the
-- struck craft and reverted after `hold` seconds. `shake` and `cockpit` drive
-- the first-person response when the struck craft is the player's.
-- =============================================================================

CRReactiveProfiles.HitProfiles = {
    conventionalArmor = {
        machinegun = {
            particle = "CR/Impact/SparkSmall",
            burst    = 0.20,
            hold     = 0.10,
            material = nil,                 -- too small to justify a state swap
            cockpit  = { animation = "hit_light", weight = 0.5 },
            hudFlash = 0.15,
        },
        cannon = {
            particle = "CR/Impact/BloomHot",
            burst    = 0.30,
            hold     = 0.35,
            material = "CR_Hit/Ionized",
            cockpit  = { animation = "hit_medium", weight = 0.8 },
            hudFlash = 0.35,
        },
        rocket = {
            particle = "CR/Impact/BlastSmoke",
            burst    = 0.45,
            hold     = 0.60,
            material = "CR_Hit/Scorch",
            cockpit  = { animation = "hit_heavy", weight = 1.0 },
            hudFlash = 0.60,
        },
        mortar = {
            particle = "CR/Impact/BlastSmoke",
            burst    = 0.45,
            hold     = 0.50,
            material = "CR_Hit/Scorch",
            cockpit  = { animation = "hit_heavy", weight = 1.0 },
            hudFlash = 0.55,
        },
        energy = {
            particle = "CR/Impact/EnergyDischarge",
            burst    = 0.35,
            hold     = 0.45,
            material = "CR_Hit/Ionized",
            cockpit  = { animation = "hit_medium", weight = 0.7 },
            hudFlash = 0.40,
        },
    },

    -- Fury and biological hulls do not spark like plate steel; they propagate
    -- luminescence through their own energy channels.
    biological = {
        machinegun = {
            particle = "CR/Impact/BioFleck",
            burst    = 0.20,
            hold     = 0.15,
            material = nil,
            cockpit  = { animation = "hit_light", weight = 0.5 },
            hudFlash = 0.15,
        },
        cannon = {
            particle = "CR/Impact/BioRupture",
            burst    = 0.30,
            hold     = 0.40,
            material = "CR_Hit/BioSurge",
            cockpit  = { animation = "hit_medium", weight = 0.8 },
            hudFlash = 0.35,
        },
        rocket = {
            particle = "CR/Impact/BioRupture",
            burst    = 0.45,
            hold     = 0.65,
            material = "CR_Hit/BioSurge",
            cockpit  = { animation = "hit_heavy", weight = 1.0 },
            hudFlash = 0.60,
        },
        mortar = {
            particle = "CR/Impact/BioRupture",
            burst    = 0.45,
            hold     = 0.55,
            material = "CR_Hit/BioSurge",
            cockpit  = { animation = "hit_heavy", weight = 1.0 },
            hudFlash = 0.55,
        },
        energy = {
            particle = "CR/Impact/EnergyDischarge",
            burst    = 0.35,
            hold     = 0.50,
            material = "CR_Hit/BioSurge",
            cockpit  = { animation = "hit_medium", weight = 0.7 },
            hudFlash = 0.40,
        },
    },
}

-- =============================================================================
-- Damage profiles
--
-- Bands are ordered high health to low. A craft enters a band when health drops
-- below `above`; the band it lands in owns the persistent material state and the
-- attached VFX. Only one band is ever applied, so a unit cannot accumulate four
-- smoke plumes on the way down.
--
-- `material` is applied to the sub-entities named by the profile's material
-- group; nil leaves the craft's own material alone.
-- =============================================================================

CRReactiveProfiles.DamageProfiles = {
    conventional = {
        bands = {
            { name = "intact",   above = 0.70, material = nil,                particles = {} },
            { name = "scarred",  above = 0.40, material = "CR_Dmg/Scarred",   particles = {
                { template = "CR/Damage/SparkIntermittent", offset = { x = 0.0, y = 1.4, z = -0.6 } },
            } },
            { name = "failing",  above = 0.20, material = "CR_Dmg/Failing",   particles = {
                { template = "CR/Damage/SmokeThin",         offset = { x = 0.0, y = 1.8, z = -1.2 } },
            } },
            { name = "critical", above = 0.00, material = "CR_Dmg/Critical",  particles = {
                { template = "CR/Damage/SmokeHeavy",        offset = { x = 0.0, y = 1.8, z = -1.2 } },
                { template = "CR/Damage/ArcElectrical",     offset = { x = 0.0, y = 1.2, z = 0.4 } },
            } },
        },
        -- Emissive failure: lamps and status strips dim and flicker as the craft
        -- fails. Values are multipliers on the authored emissive colour.
        emissive = {
            intact   = { level = 1.00, flicker = 0.00, period = 0.0 },
            scarred  = { level = 0.90, flicker = 0.10, period = 2.6 },
            failing  = { level = 0.65, flicker = 0.30, period = 1.4 },
            critical = { level = 0.35, flicker = 0.65, period = 0.5 },
        },
    },

    biological = {
        bands = {
            { name = "intact",   above = 0.70, material = nil,                 particles = {} },
            { name = "scarred",  above = 0.40, material = "CR_Dmg/BioScarred", particles = {
                { template = "CR/Damage/BioFlicker", offset = { x = 0.0, y = 1.6, z = 0.0 } },
            } },
            { name = "failing",  above = 0.20, material = "CR_Dmg/BioFailing", particles = {
                { template = "CR/Damage/BioLeak",    offset = { x = 0.0, y = 1.6, z = -0.8 } },
            } },
            { name = "critical", above = 0.00, material = "CR_Dmg/BioCritical", particles = {
                { template = "CR/Damage/BioLeak",    offset = { x = 0.0, y = 1.6, z = -0.8 } },
                { template = "CR/Damage/BioArc",     offset = { x = 0.0, y = 1.2, z = 0.5 } },
            } },
        },
        emissive = {
            intact   = { level = 1.00, flicker = 0.05, period = 3.2 },
            scarred  = { level = 0.95, flicker = 0.20, period = 2.0 },
            failing  = { level = 0.80, flicker = 0.45, period = 0.9 },
            critical = { level = 0.55, flicker = 0.85, period = 0.35 },
        },
    },
}

-- =============================================================================
-- Weapon heat profiles
--
-- Heat accumulates per shot and decays over time. The normalised value drives
-- an emissive multiplier on the weapon material group. Heat is presentation
-- only: it never gates firing, so weapon balance is untouched.
-- =============================================================================

CRReactiveProfiles.WeaponHeatProfiles = {
    blastCannon = {
        perShot   = 0.22,
        decay     = 0.30,   -- units per second
        threshold = 0.25,   -- below this nothing is drawn
        glow      = { r = 1.00, g = 0.34, b = 0.06 },
    },
    machineGun = {
        perShot   = 0.06,
        decay     = 0.45,
        threshold = 0.35,
        glow      = { r = 1.00, g = 0.45, b = 0.12 },
    },
    mortar = {
        perShot   = 0.55,
        decay     = 0.22,
        threshold = 0.20,
        glow      = { r = 1.00, g = 0.28, b = 0.04 },
    },
    -- Alien channels intensify and destabilise instead of imitating hot metal.
    alienChannel = {
        perShot   = 0.30,
        decay     = 0.28,
        threshold = 0.15,
        glow      = { r = 0.25, g = 0.90, b = 1.00 },
    },
}

-- =============================================================================
-- Vehicle profiles
--
-- materialGroups maps a logical group to sub-entity indices on the craft's mesh.
-- Those indices are mesh specific and currently a best guess: index 0 is the
-- hull on every stock BZ craft, and anything beyond that has to be confirmed
-- per mesh. An index the mesh does not have is skipped, so an over-long list is
-- harmless.
-- =============================================================================

CRReactiveProfiles.VehicleProfiles = {
    -- NSDF
    avtank = {
        materialGroups   = { hull = { 0 }, weapon = { 1 }, lamps = { 2 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "nsdfTankCockpit",
        weaponHeatProfile = "blastCannon",
        smokeOffset      = { x = 0.0, y = 1.8, z = -1.4 },
    },
    avfigh = {
        materialGroups   = { hull = { 0 }, weapon = { 1 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "nsdfScoutCockpit",
        weaponHeatProfile = "machineGun",
        smokeOffset      = { x = 0.0, y = 1.4, z = -1.0 },
    },
    avltnk = {
        materialGroups   = { hull = { 0 }, weapon = { 1 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "nsdfTankCockpit",
        weaponHeatProfile = "blastCannon",
        smokeOffset      = { x = 0.0, y = 1.6, z = -1.2 },
    },
    avartl = {
        materialGroups   = { hull = { 0 }, weapon = { 1 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "nsdfTankCockpit",
        weaponHeatProfile = "mortar",
        smokeOffset      = { x = 0.0, y = 1.8, z = -1.6 },
    },

    -- CCA
    svtank = {
        materialGroups   = { hull = { 0 }, weapon = { 1 }, lamps = { 2 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "ccaTankCockpit",
        weaponHeatProfile = "blastCannon",
        smokeOffset      = { x = 0.0, y = 1.8, z = -1.4 },
    },
    svfigh = {
        materialGroups   = { hull = { 0 }, weapon = { 1 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "ccaScoutCockpit",
        weaponHeatProfile = "machineGun",
        smokeOffset      = { x = 0.0, y = 1.4, z = -1.0 },
    },
    svltnk = {
        materialGroups   = { hull = { 0 }, weapon = { 1 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "ccaTankCockpit",
        weaponHeatProfile = "blastCannon",
        smokeOffset      = { x = 0.0, y = 1.6, z = -1.2 },
    },
    svwalk = {
        materialGroups   = { hull = { 0 }, weapon = { 1 } },
        hitProfile       = "conventionalArmor",
        damageProfile    = "conventional",
        cockpitProfile   = "ccaTankCockpit",
        weaponHeatProfile = "blastCannon",
        smokeOffset      = { x = 0.0, y = 3.2, z = -1.0 },
    },

    -- Fury / biological
    xbio = {
        materialGroups   = { hull = { 0 } },
        hitProfile       = "biological",
        damageProfile    = "biological",
        cockpitProfile   = nil,
        weaponHeatProfile = "alienChannel",
        smokeOffset      = { x = 0.0, y = 1.8, z = 0.0 },
    },
}

-- Anything not listed above still gets impact response and damage bands; it
-- just uses the conventional language and no cockpit or heat treatment.
CRReactiveProfiles.DefaultVehicleProfile = {
    materialGroups    = { hull = { 0 } },
    hitProfile        = "conventionalArmor",
    damageProfile     = "conventional",
    cockpitProfile    = nil,
    weaponHeatProfile = nil,
    smokeOffset       = { x = 0.0, y = 1.6, z = -1.0 },
}

-- =============================================================================
-- Cockpit profiles
--
-- Animation names are looked up on the local first-person entity through
-- exu.animation. A craft whose viewmodel has no such animation is simply not
-- animated -- the impact particles and HUD response still happen.
-- =============================================================================

CRReactiveProfiles.CockpitProfiles = {
    nsdfTankCockpit = {
        directional = {
            front = "hit_front",
            rear  = "hit_rear",
            left  = "hit_left",
            right = "hit_right",
        },
        heavy  = "hit_heavy",
        recoil = {
            cannon = "recoil_cannon",
            mortar = "recoil_mortar",
            rocket = "recoil_rocket",
        },
        critical = "cockpit_critical",
    },
    nsdfScoutCockpit = {
        directional = {
            front = "hit_front",
            rear  = "hit_rear",
            left  = "hit_left",
            right = "hit_right",
        },
        heavy  = "hit_heavy",
        recoil = { cannon = "recoil_cannon" },
        critical = "cockpit_critical",
    },
    ccaTankCockpit = {
        directional = {
            front = "hit_front",
            rear  = "hit_rear",
            left  = "hit_left",
            right = "hit_right",
        },
        heavy  = "hit_heavy",
        recoil = {
            cannon = "recoil_cannon",
            mortar = "recoil_mortar",
            rocket = "recoil_rocket",
        },
        critical = "cockpit_critical",
    },
    ccaScoutCockpit = {
        directional = {
            front = "hit_front",
            rear  = "hit_rear",
            left  = "hit_left",
            right = "hit_right",
        },
        heavy  = "hit_heavy",
        recoil = { cannon = "recoil_cannon" },
        critical = "cockpit_critical",
    },
}

-- =============================================================================
-- Lookup helpers
-- =============================================================================

function CRReactiveProfiles.ClassifyOrdnance(odfName)
    if type(odfName) ~= "string" then
        return CRReactiveProfiles.DefaultOrdnanceFamily
    end

    local name = string.lower(odfName)
    local bestPrefix, bestFamily = nil, nil
    for prefix, family in pairs(CRReactiveProfiles.OrdnanceFamilies) do
        if string.sub(name, 1, string.len(prefix)) == prefix then
            if bestPrefix == nil or string.len(prefix) > string.len(bestPrefix) then
                bestPrefix, bestFamily = prefix, family
            end
        end
    end

    return bestFamily or CRReactiveProfiles.DefaultOrdnanceFamily
end

-- Craft ODF names carry a variant suffix (avtank5, svtank_x). Match on the
-- longest declared profile key that the ODF name starts with.
function CRReactiveProfiles.ForOdf(odfName)
    if type(odfName) ~= "string" then
        return CRReactiveProfiles.DefaultVehicleProfile
    end

    local name = string.lower(odfName)
    local bestKey, bestProfile = nil, nil
    for key, profile in pairs(CRReactiveProfiles.VehicleProfiles) do
        if string.sub(name, 1, string.len(key)) == key then
            if bestKey == nil or string.len(key) > string.len(bestKey) then
                bestKey, bestProfile = key, profile
            end
        end
    end

    return bestProfile or CRReactiveProfiles.DefaultVehicleProfile
end

return CRReactiveProfiles
