-- CRReactive.lua
-- Campaign Reimagined reactive presentation layer.
--
-- One subsystem owns everything that makes a machine communicate its own state:
-- weapon-specific impact response, persistent damage bands, emissive failure,
-- damage VFX, weapon heat, and the first-person cockpit reaction. Mission
-- scripts register objects and pick profiles; they never reimplement any of it.
--
-- Design rules this file is built to, from the reactive presentation note:
--   * React to real ordnance events, not health polling alone. BulletHit tells
--     us what hit what, with a transform; health polling only tells us that
--     something happened, one frame late.
--   * Never let one craft's material change leak to every other craft sharing
--     the same base material. Sub-entity assignment, not material mutation.
--   * Presentation only. Nothing here changes damage, balance, or AI.
--   * Everything is bounded and everything is released on teardown. An
--     EXU-owned particle system that survives a mission change is a leak into
--     the next mission's scene.

local exu = require("exu")
local Profiles = require("CRReactiveProfiles")

local CRReactive = {}

-- =============================================================================
-- Configuration
-- =============================================================================

CRReactive.Enabled              = true

-- Hard ceilings. The player can only look at so much at once, and an unbounded
-- per-unit particle allocation is how a 60 unit battle turns into a slideshow.
CRReactive.MaxDamageSystems     = 12
CRReactive.MaxImpactSystems     = 8

-- Beyond this distance from the camera a craft gets damage materials but no
-- particles: the plume would be a few pixels and cost the same as a near one.
CRReactive.ParticleRange        = 260.0

-- Health is polled on a rotating slice of the registry rather than all at once.
CRReactive.HealthPollInterval   = 0.25
CRReactive.HealthPollSlice      = 8

CRReactive.Debug                = false

-- =============================================================================
-- Runtime state
-- =============================================================================

CRReactive.Initialized     = false
CRReactive.Objects         = {}    -- handle -> record
CRReactive.ObjectOrder     = {}    -- stable iteration order for the poll slice
CRReactive.PollCursor      = 1
CRReactive.PollTimer       = 0.0
CRReactive.Clock           = 0.0
CRReactive.DamageSystems   = {}    -- systemName -> handle
CRReactive.DamageSystemUse = 0
CRReactive.ImpactPool      = {}    -- index -> { name, busyUntil, created }
CRReactive.ImpactCursor    = 1
CRReactive.PlayerHeat      = {}    -- weaponHeatProfile name -> 0..1
CRReactive.PendingHits     = {}    -- handle -> record, only while a hit state is showing
CRReactive.ChainedHit      = nil
CRReactive.ChainedInit     = nil
CRReactive.HooksInstalled  = false

-- =============================================================================
-- Small helpers
-- =============================================================================

local function Clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function Log(message)
    if not CRReactive.Debug then
        return
    end
    print("CRReactive: " .. tostring(message))
end

-- EXU may predate any of these APIs, or be absent. A missing call degrades the
-- presentation; it must never abort a mission script.
local function Call(name, ...)
    local fn = exu and exu[name]
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        Log("exu." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function AnimationCall(name, ...)
    local api = exu and exu.animation
    local fn = api and api[name]
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        Log("exu.animation." .. name .. " failed: " .. tostring(result))
        return nil
    end
    return result
end

local function StripOdfExtension(name)
    if type(name) ~= "string" then
        return nil
    end
    return (string.gsub(string.lower(name), "%.odf$", ""))
end

local function SafeGetOdf(h)
    if GetOdf == nil then
        return nil
    end
    local ok, name = pcall(GetOdf, h)
    if not ok then
        return nil
    end
    return StripOdfExtension(name)
end

local function SafeGetHealth(h)
    if GetHealth == nil then
        return nil
    end
    local ok, health = pcall(GetHealth, h)
    if not ok or type(health) ~= "number" then
        return nil
    end
    return Clamp01(health)
end

local function MaterialUsable(materialName)
    if materialName == nil then
        return false
    end
    return Call("MaterialExists", materialName) == true
end

-- =============================================================================
-- Impact particle pool
--
-- A fixed pool of EXU-owned systems that are moved to the hit position, told to
-- emit for a fraction of a second, and then parked. This is deliberately not a
-- create-per-hit pattern: creating and destroying an Ogre particle system in a
-- firefight is far more expensive than reusing eight of them.
-- =============================================================================

local function ImpactSystemName(index)
    return "cr_fx_impact_" .. tostring(index)
end

local function AcquireImpactSystem(template)
    local index = CRReactive.ImpactCursor
    CRReactive.ImpactCursor = (index % CRReactive.MaxImpactSystems) + 1

    local slot = CRReactive.ImpactPool[index]
    if slot == nil then
        slot = { name = ImpactSystemName(index), created = false, busyUntil = 0.0, template = nil }
        CRReactive.ImpactPool[index] = slot
    end

    -- The pool entry is created against whatever template first needs it, and
    -- recreated when a different weapon family claims the slot. Ogre has no way
    -- to swap a system's emitters, only its material.
    if slot.created and slot.template ~= template then
        Call("DetachParticleSystem", slot.name)
        Call("DestroyParticleSystem", slot.name)
        slot.created = false
    end

    if not slot.created then
        if Call("CreateParticleSystem", slot.name, template) ~= true then
            return nil
        end
        Call("SetParticleSystemKeepLocalSpace", slot.name, false)
        Call("SetParticleSystemNonVisibleUpdateTimeout", slot.name, 1.0)
        slot.created = true
        slot.template = template
    end

    return slot
end

local function FireImpact(template, position, holdSeconds)
    if template == nil or position == nil then
        return
    end

    local slot = AcquireImpactSystem(template)
    if slot == nil then
        return
    end

    Call("DetachParticleSystem", slot.name)
    Call("SetParticleSystemPosition", slot.name, position)
    Call("SetParticleSystemEmitting", slot.name, true)
    slot.busyUntil = CRReactive.Clock + math.max(0.05, holdSeconds or 0.2)
end

local function UpdateImpactPool()
    for index = 1, CRReactive.MaxImpactSystems do
        local slot = CRReactive.ImpactPool[index]
        if slot ~= nil and slot.created and slot.busyUntil > 0.0 and CRReactive.Clock >= slot.busyUntil then
            Call("SetParticleSystemEmitting", slot.name, false)
            slot.busyUntil = 0.0
        end
    end
end

local function DestroyImpactPool()
    for index = 1, CRReactive.MaxImpactSystems do
        local slot = CRReactive.ImpactPool[index]
        if slot ~= nil and slot.created then
            Call("DetachParticleSystem", slot.name)
            Call("DestroyParticleSystem", slot.name)
            slot.created = false
        end
    end
    CRReactive.ImpactPool = {}
    CRReactive.ImpactCursor = 1
end

-- =============================================================================
-- Per-craft damage VFX
-- =============================================================================

local function DamageSystemName(record, index)
    return "cr_fx_dmg_" .. tostring(record.id) .. "_" .. tostring(index)
end

local function ClearDamageParticles(record)
    if record.particleNames == nil then
        return
    end

    for i = 1, #record.particleNames do
        local systemName = record.particleNames[i]
        Call("DetachParticleSystem", systemName)
        Call("DestroyParticleSystem", systemName)
        if CRReactive.DamageSystems[systemName] ~= nil then
            CRReactive.DamageSystems[systemName] = nil
            CRReactive.DamageSystemUse = math.max(0, CRReactive.DamageSystemUse - 1)
        end
    end
    record.particleNames = nil
end

local function ApplyDamageParticles(record, band)
    ClearDamageParticles(record)

    local specs = band.particles
    if specs == nil or #specs == 0 then
        return
    end

    if CRReactive.DamageSystemUse >= CRReactive.MaxDamageSystems then
        -- Out of budget. The material state still tells the player this craft is
        -- in trouble; the plume is the part we can afford to drop.
        return
    end

    local names = {}
    for i = 1, #specs do
        if CRReactive.DamageSystemUse >= CRReactive.MaxDamageSystems then
            break
        end

        local spec = specs[i]
        local systemName = DamageSystemName(record, i)
        if Call("CreateParticleSystem", systemName, spec.template) == true then
            Call("SetParticleSystemKeepLocalSpace", systemName, false)
            Call("SetParticleSystemNonVisibleUpdateTimeout", systemName, 2.0)

            local offset = spec.offset or record.profile.smokeOffset or { x = 0, y = 1.6, z = 0 }
            -- Attaching to the craft's own scene node is what keeps the plume on
            -- the craft without a per-frame Lua reposition.
            Call("AttachParticleSystemToObject", systemName, record.handle,
                 SetVector(offset.x or 0.0, offset.y or 0.0, offset.z or 0.0))

            names[#names + 1] = systemName
            CRReactive.DamageSystems[systemName] = record.handle
            CRReactive.DamageSystemUse = CRReactive.DamageSystemUse + 1
        end
    end

    record.particleNames = (#names > 0) and names or nil
end

-- =============================================================================
-- Material state
-- =============================================================================

local function CaptureOriginalMaterials(record)
    if record.originalMaterials ~= nil then
        return
    end

    record.originalMaterials = {}
    local groups = record.profile.materialGroups or {}
    for _, indices in pairs(groups) do
        for i = 1, #indices do
            local subIndex = indices[i]
            if record.originalMaterials[subIndex] == nil then
                local name = Call("GetSubEntityMaterial", record.handle, subIndex)
                if type(name) == "string" then
                    record.originalMaterials[subIndex] = name
                end
            end
        end
    end
end

-- Applies a material to one logical group. Sub-entity assignment is per craft,
-- so a damaged tank does not repaint every other tank sharing the base material.
local function ApplyGroupMaterial(record, groupName, materialName)
    local groups = record.profile.materialGroups or {}
    local indices = groups[groupName]
    if indices == nil then
        return false
    end

    CaptureOriginalMaterials(record)

    local applied = false
    for i = 1, #indices do
        local subIndex = indices[i]
        local target = materialName
        if target == nil then
            target = record.originalMaterials[subIndex]
        end
        if target ~= nil and Call("SetSubEntityMaterial", record.handle, subIndex, target) == true then
            applied = true
        end
    end
    return applied
end

local function RestoreAllMaterials(record)
    if record.originalMaterials == nil then
        return
    end

    for subIndex, name in pairs(record.originalMaterials) do
        Call("SetSubEntityMaterial", record.handle, subIndex, name)
    end
    record.hitMaterialUntil = nil
    record.appliedBandMaterial = nil
end

-- =============================================================================
-- Damage bands
-- =============================================================================

local function ResolveBand(damageProfile, health)
    local bands = damageProfile.bands
    for i = 1, #bands do
        if health > bands[i].above then
            return bands[i]
        end
    end
    return bands[#bands]
end

local function EnterBand(record, band)
    if record.band ~= nil and record.band.name == band.name then
        return
    end

    record.band = band
    Log("band " .. tostring(record.odf) .. " -> " .. tostring(band.name))

    -- A transient hit state must not be clobbered by the band swap: whichever
    -- one is showing, the other is remembered and reapplied when it expires.
    record.appliedBandMaterial = MaterialUsable(band.material) and band.material or nil
    if record.hitMaterialUntil == nil then
        ApplyGroupMaterial(record, "hull", record.appliedBandMaterial)
    end

    local nearEnough = true
    if record.playerDistance ~= nil then
        nearEnough = record.playerDistance <= CRReactive.ParticleRange
    end

    if nearEnough then
        ApplyDamageParticles(record, band)
    else
        ClearDamageParticles(record)
    end
end

-- =============================================================================
-- Emissive failure
--
-- Status strips and energy surfaces dim and flicker as damage rises. This is
-- applied through a per-craft cloned material so one failing tank does not make
-- every tank on the map flicker in lockstep. Cloning is bounded to craft that
-- actually have a lamp group and are close enough to read.
-- =============================================================================

local function EmissiveMaterialName(record)
    return "CR_Emissive_" .. tostring(record.id)
end

local function UpdateEmissive(record, damageProfile)
    local groups = record.profile.materialGroups or {}
    if groups.lamps == nil or record.band == nil then
        return
    end

    local policy = damageProfile.emissive and damageProfile.emissive[record.band.name]
    if policy == nil then
        return
    end

    if record.playerDistance ~= nil and record.playerDistance > CRReactive.ParticleRange then
        return
    end

    -- One clone per craft, made on first need and released on unregister.
    if record.emissiveMaterial == nil then
        CaptureOriginalMaterials(record)
        local sourceIndex = groups.lamps[1]
        local source = record.originalMaterials and record.originalMaterials[sourceIndex]
        if source == nil then
            return
        end

        local cloneName = EmissiveMaterialName(record)
        if Call("CloneMaterial", source, cloneName) ~= true and not MaterialUsable(cloneName) then
            record.emissiveUnavailable = true
            return
        end

        record.emissiveMaterial = cloneName
        ApplyGroupMaterial(record, "lamps", cloneName)
    end

    local level = policy.level or 1.0
    if (policy.flicker or 0.0) > 0.0 and (policy.period or 0.0) > 0.0 then
        local wave = 0.5 + (0.5 * math.sin((CRReactive.Clock / policy.period) * 6.2831853))
        -- A little noise so the flicker does not read as a clean sine.
        wave = Clamp01((wave * 0.8) + (math.random() * 0.2))
        level = level * (1.0 - (policy.flicker * (1.0 - wave)))
    end

    if record.lastEmissiveLevel ~= nil and math.abs(record.lastEmissiveLevel - level) < 0.02 then
        return
    end
    record.lastEmissiveLevel = level

    Call("SetMaterialPassColors", record.emissiveMaterial, {
        emissive = { r = level, g = level, b = level },
    })
end

local function ReleaseEmissive(record)
    if record.emissiveMaterial == nil then
        return
    end
    ApplyGroupMaterial(record, "lamps", nil)
    record.emissiveMaterial = nil
    record.lastEmissiveLevel = nil
end

-- =============================================================================
-- Cockpit and HUD response
-- =============================================================================

-- Coarse local direction from the hit transform relative to the struck craft.
-- This is enough to choose left/right/front/rear well before native per-panel
-- hit localisation exists.
local function HitDirection(hitObject, transform)
    if transform == nil or GetPosition == nil then
        return "front"
    end

    local okTarget, target = pcall(GetPosition, hitObject)
    if not okTarget or target == nil then
        return "front"
    end

    local dx = (transform.posit_x or transform.x or target.x) - target.x
    local dz = (transform.posit_z or transform.z or target.z) - target.z

    local okFront, front = pcall(GetFront, hitObject)
    if not okFront or front == nil then
        return "front"
    end

    -- Project the offset onto the craft's own forward and right axes.
    local forward = (dx * front.x) + (dz * front.z)
    local right = (dx * -front.z) + (dz * front.x)

    if math.abs(forward) >= math.abs(right) then
        return forward >= 0.0 and "front" or "rear"
    end
    return right >= 0.0 and "right" or "left"
end

local function PlayCockpit(profileName, animation, weight)
    if profileName == nil or animation == nil then
        return
    end

    local target = AnimationCall("TargetLocalFirstPerson")
    if target == nil then
        return
    end

    AnimationCall("Play", target, animation, { loop = false, restart = true, weight = weight or 1.0 })
end

local function CockpitHitReaction(record, hitSpec, transform)
    local cockpit = Profiles.CockpitProfiles[record.profile.cockpitProfile]
    if cockpit == nil then
        return
    end

    local animation = nil
    if hitSpec.cockpit and hitSpec.cockpit.animation == "hit_heavy" then
        animation = cockpit.heavy
    else
        local direction = HitDirection(record.handle, transform)
        animation = cockpit.directional and cockpit.directional[direction]
    end

    PlayCockpit(record.profile.cockpitProfile, animation,
                hitSpec.cockpit and hitSpec.cockpit.weight or 1.0)
end

-- =============================================================================
-- Registry
-- =============================================================================

local nextRecordId = 1

function CRReactive.Register(h, profileName)
    if not CRReactive.Enabled or h == nil then
        return nil
    end

    if IsValid ~= nil and not IsValid(h) then
        return nil
    end

    if CRReactive.Objects[h] ~= nil then
        return CRReactive.Objects[h]
    end

    local odf = SafeGetOdf(h)
    local profile
    if profileName ~= nil and Profiles.VehicleProfiles[profileName] ~= nil then
        profile = Profiles.VehicleProfiles[profileName]
    else
        profile = Profiles.ForOdf(odf)
    end

    local record = {
        id                 = nextRecordId,
        handle             = h,
        odf                = odf,
        profile            = profile,
        band               = nil,
        health             = SafeGetHealth(h) or 1.0,
        particleNames      = nil,
        originalMaterials  = nil,
        appliedBandMaterial = nil,
        hitMaterialUntil   = nil,
        emissiveMaterial   = nil,
        playerDistance     = nil,
    }
    nextRecordId = nextRecordId + 1

    CRReactive.Objects[h] = record
    CRReactive.ObjectOrder[#CRReactive.ObjectOrder + 1] = h
    return record
end

function CRReactive.Unregister(h)
    local record = CRReactive.Objects[h]
    if record == nil then
        return
    end

    ClearDamageParticles(record)
    ReleaseEmissive(record)
    if IsValid == nil or IsValid(h) then
        RestoreAllMaterials(record)
    end

    CRReactive.Objects[h] = nil
    CRReactive.PendingHits[h] = nil
    for index = #CRReactive.ObjectOrder, 1, -1 do
        if CRReactive.ObjectOrder[index] == h then
            table.remove(CRReactive.ObjectOrder, index)
        end
    end
end

-- Mission scripts already call OnObjectCreated on their other modules; this
-- keeps the same shape so registration is one more line, not a new loop.
function CRReactive.OnObjectCreated(h)
    CRReactive.Register(h)
end

-- =============================================================================
-- Ordnance events
-- =============================================================================

function CRReactive.OnBulletHit(odf, shooter, hitObject, transform, ordnanceHandle)
    if not CRReactive.Enabled or hitObject == nil then
        return
    end

    local record = CRReactive.Objects[hitObject]
    if record == nil then
        record = CRReactive.Register(hitObject)
        if record == nil then
            return
        end
    end

    local family = Profiles.ClassifyOrdnance(odf)
    local hitProfile = Profiles.HitProfiles[record.profile.hitProfile]
    local hitSpec = hitProfile and hitProfile[family]
    if hitSpec == nil then
        return
    end

    -- Impact VFX at the hit transform. The transform is the ordnance's, so its
    -- position is the contact point.
    if transform ~= nil and hitSpec.particle ~= nil then
        local position = SetVector(
            transform.posit_x or transform.x or 0.0,
            transform.posit_y or transform.y or 0.0,
            transform.posit_z or transform.z or 0.0)
        FireImpact(hitSpec.particle, position, hitSpec.burst)
    end

    -- Transient hit state on the struck craft, reverted to the persistent band
    -- material rather than to "no material".
    if hitSpec.material ~= nil and MaterialUsable(hitSpec.material) then
        ApplyGroupMaterial(record, "hull", hitSpec.material)
        record.hitMaterialUntil = CRReactive.Clock + (hitSpec.hold or 0.25)
        CRReactive.PendingHits[hitObject] = record
    end

    -- First-person response only for the craft the player is actually in.
    if GetPlayerHandle ~= nil and hitObject == GetPlayerHandle() then
        CockpitHitReaction(record, hitSpec, transform)
    end
end

function CRReactive.OnBulletInit(odf, shooter, transform)
    if not CRReactive.Enabled or shooter == nil then
        return
    end

    if GetPlayerHandle == nil or shooter ~= GetPlayerHandle() then
        return
    end

    local record = CRReactive.Objects[shooter] or CRReactive.Register(shooter)
    if record == nil then
        return
    end

    -- Weapon heat. Presentation only: it never gates firing.
    local heatProfileName = record.profile.weaponHeatProfile
    local heatProfile = heatProfileName and Profiles.WeaponHeatProfiles[heatProfileName]
    if heatProfile ~= nil then
        local current = CRReactive.PlayerHeat[heatProfileName] or 0.0
        CRReactive.PlayerHeat[heatProfileName] = Clamp01(current + heatProfile.perShot)
    end

    local cockpit = Profiles.CockpitProfiles[record.profile.cockpitProfile]
    if cockpit ~= nil and cockpit.recoil ~= nil then
        local family = Profiles.ClassifyOrdnance(odf)
        PlayCockpit(record.profile.cockpitProfile, cockpit.recoil[family], 1.0)
    end
end

-- exu.BulletHit and exu.BulletInit are single globals, and PhysicsImpact.lua
-- already owns both. Chain rather than replace: whichever module loads second
-- must not silently delete the first one's physics.
local function InstallOrdnanceHooks()
    if CRReactive.HooksInstalled then
        return
    end

    CRReactive.ChainedHit = exu.BulletHit
    exu.BulletHit = function(odf, shooter, hitObject, transform, ordnanceHandle)
        if CRReactive.ChainedHit ~= nil then
            pcall(CRReactive.ChainedHit, odf, shooter, hitObject, transform, ordnanceHandle)
        end
        local ok, err = pcall(CRReactive.OnBulletHit, odf, shooter, hitObject, transform, ordnanceHandle)
        if not ok then
            Log("OnBulletHit failed: " .. tostring(err))
        end
    end

    CRReactive.ChainedInit = exu.BulletInit
    exu.BulletInit = function(odf, shooter, transform)
        if CRReactive.ChainedInit ~= nil then
            pcall(CRReactive.ChainedInit, odf, shooter, transform)
        end
        local ok, err = pcall(CRReactive.OnBulletInit, odf, shooter, transform)
        if not ok then
            Log("OnBulletInit failed: " .. tostring(err))
        end
    end

    CRReactive.HooksInstalled = true
end

-- =============================================================================
-- Update
-- =============================================================================

local function PollRecord(record, playerHandle)
    if IsValid ~= nil and not IsValid(record.handle) then
        return false
    end

    if playerHandle ~= nil and GetDistance ~= nil then
        local ok, distance = pcall(GetDistance, record.handle, playerHandle)
        record.playerDistance = (ok and type(distance) == "number") and distance or nil
    end

    local health = SafeGetHealth(record.handle)
    if health ~= nil then
        record.health = health
        local damageProfile = Profiles.DamageProfiles[record.profile.damageProfile]
        if damageProfile ~= nil then
            EnterBand(record, ResolveBand(damageProfile, health))
            UpdateEmissive(record, damageProfile)
        end
    end

    return true
end

function CRReactive.Update(dt)
    if not CRReactive.Initialized then
        CRReactive.Init()
    end

    if not CRReactive.Enabled then
        return
    end

    dt = tonumber(dt) or 0.0
    CRReactive.Clock = CRReactive.Clock + dt

    UpdateImpactPool()

    -- Transient hit materials expire back to the persistent band state. Only
    -- craft currently showing one are walked, so a large battle does not pay
    -- for a full registry sweep every frame.
    for handle, record in pairs(CRReactive.PendingHits) do
        if record.hitMaterialUntil == nil or CRReactive.Clock >= record.hitMaterialUntil then
            record.hitMaterialUntil = nil
            ApplyGroupMaterial(record, "hull", record.appliedBandMaterial)
            CRReactive.PendingHits[handle] = nil
        end
    end

    -- Weapon heat decays whether or not the player is firing.
    for name, value in pairs(CRReactive.PlayerHeat) do
        local heatProfile = Profiles.WeaponHeatProfiles[name]
        if heatProfile ~= nil then
            CRReactive.PlayerHeat[name] = math.max(0.0, value - (heatProfile.decay * dt))
        end
    end

    CRReactive.PollTimer = CRReactive.PollTimer + dt
    if CRReactive.PollTimer < CRReactive.HealthPollInterval then
        return
    end
    CRReactive.PollTimer = 0.0

    local playerHandle = GetPlayerHandle and GetPlayerHandle() or nil
    local count = #CRReactive.ObjectOrder
    if count == 0 then
        return
    end

    -- Poll a rotating slice so a large battle costs the same per frame as a
    -- small one.
    local dead = {}
    local examined = 0
    while examined < math.min(CRReactive.HealthPollSlice, count) do
        if CRReactive.PollCursor > #CRReactive.ObjectOrder then
            CRReactive.PollCursor = 1
        end

        local handle = CRReactive.ObjectOrder[CRReactive.PollCursor]
        local record = handle and CRReactive.Objects[handle]
        if record == nil then
            table.remove(CRReactive.ObjectOrder, CRReactive.PollCursor)
            if #CRReactive.ObjectOrder == 0 then
                break
            end
        else
            if not PollRecord(record, playerHandle) then
                dead[#dead + 1] = handle
            end
            CRReactive.PollCursor = CRReactive.PollCursor + 1
        end

        examined = examined + 1
    end

    for i = 1, #dead do
        CRReactive.Unregister(dead[i])
    end
end

-- Current normalised heat for a weapon profile, for a HUD widget that only
-- wants to appear when heat is high enough to matter.
function CRReactive.GetWeaponHeat(profileName)
    return CRReactive.PlayerHeat[profileName] or 0.0
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

function CRReactive.Init(options)
    if CRReactive.Initialized then
        return
    end

    options = options or {}
    if options.enabled ~= nil then CRReactive.Enabled = options.enabled and true or false end
    if options.debug ~= nil then CRReactive.Debug = options.debug and true or false end
    if options.maxDamageSystems ~= nil then
        CRReactive.MaxDamageSystems = math.max(0, math.floor(tonumber(options.maxDamageSystems) or 12))
    end
    if options.maxImpactSystems ~= nil then
        CRReactive.MaxImpactSystems = math.max(1, math.floor(tonumber(options.maxImpactSystems) or 8))
    end
    if options.particleRange ~= nil then
        CRReactive.ParticleRange = math.max(0.0, tonumber(options.particleRange) or 260.0)
    end

    CRReactive.Objects = {}
    CRReactive.ObjectOrder = {}
    CRReactive.PollCursor = 1
    CRReactive.PollTimer = 0.0
    CRReactive.Clock = 0.0
    CRReactive.DamageSystems = {}
    CRReactive.DamageSystemUse = 0
    CRReactive.ImpactPool = {}
    CRReactive.ImpactCursor = 1
    CRReactive.PlayerHeat = {}
    CRReactive.PendingHits = {}

    InstallOrdnanceHooks()
    CRReactive.Initialized = true
end

-- Mission teardown. Every EXU-owned particle system and every material override
-- has to be released here: the scene these point into does not survive the
-- mission change, and a stale name blocks the next mission from creating its own.
function CRReactive.Shutdown()
    if not CRReactive.Initialized then
        return
    end

    local handles = {}
    for handle in pairs(CRReactive.Objects) do
        handles[#handles + 1] = handle
    end
    for i = 1, #handles do
        CRReactive.Unregister(handles[i])
    end

    DestroyImpactPool()

    if CRReactive.HooksInstalled then
        exu.BulletHit = CRReactive.ChainedHit
        exu.BulletInit = CRReactive.ChainedInit
        CRReactive.ChainedHit = nil
        CRReactive.ChainedInit = nil
        CRReactive.HooksInstalled = false
    end

    CRReactive.DamageSystems = {}
    CRReactive.DamageSystemUse = 0
    CRReactive.PlayerHeat = {}
    CRReactive.PendingHits = {}
    CRReactive.Initialized = false
end

return CRReactive
