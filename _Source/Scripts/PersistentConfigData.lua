-- PersistentConfigData.lua
---@diagnostic disable: lowercase-global, undefined-global

return {
    PdaPages = {
        STATS = 1,
        TARGET = 2,
        SETTINGS = 3,
        PRESETS = 4,
        QUEUE = 5,
        COMMAND = 6,
        COUNT = 6,
    },

    PresetProducerKinds = {
        [1] = { name = "RECYCLER", getter = GetRecyclerHandle, short = "REC" },
        [2] = { name = "FACTORY", getter = GetFactoryHandle, short = "FAC" },
    },

    LEGACY_TEXT_PRESET_SCALES = {
        [1] = 0.85,
        [2] = 1.00,
        [3] = 1.15,
        [4] = 1.30,
    },

    PdaColorPresets = {
        [1] = { name = "DARK GREEN", r = 0.10, g = 0.42, b = 0.10 },
        [2] = { name = "GREEN", r = 0.18, g = 0.92, b = 0.18 },
        [3] = { name = "BLUE", r = 0.35, g = 0.65, b = 1.00 },
        [4] = { name = "WHITE", r = 1.00, g = 1.00, b = 1.00 },
    },

    PdaPanelMaterialFamilies = {
        { key = "DG", r = 0.10, g = 0.42, b = 0.10 },
        { key = "G", r = 0.18, g = 0.92, b = 0.18 },
        { key = "B", r = 0.35, g = 0.65, b = 1.00 },
        { key = "W", r = 1.00, g = 1.00, b = 1.00 },
        { key = "R", r = 1.00, g = 0.35, b = 0.35 },
    },

    ScrapPilotHudLayouts = {
        [1] = { name = "STOCK" },
        [2] = { name = "LEGACY" },
    },

    UnitVerbosityPresets = {
        [1] = { name = "NORMAL" },
        [2] = { name = "DECREASED", throttleMs = 750, queueDepthLimit = 1, queueStaleMs = 1200 },
        [3] = { name = "NONE", muted = true, throttleMs = 60000, queueDepthLimit = 1, queueStaleMs = 0 },
    },

    HeadlightColorPresets = {
        [1] = { name = "WHITE", r = 5.0, g = 5.0, b = 5.0 },
        [2] = { name = "RED", r = 5.0, g = 1.0, b = 1.0 },
        [3] = { name = "GREEN", r = 1.0, g = 5.0, b = 1.0 },
        [4] = { name = "BLUE", r = 1.0, g = 1.0, b = 5.0 },
        [5] = { name = "YELLOW", r = 5.0, g = 5.0, b = 1.0 },
        [6] = { name = "CYAN", r = 1.0, g = 5.0, b = 5.0 },
        [7] = { name = "MAGENTA", r = 5.0, g = 1.0, b = 5.0 },
        [8] = { name = "ORANGE", r = 5.0, g = 2.5, b = 1.0 },
        [9] = { name = "PURPLE", r = 2.5, g = 1.0, b = 5.0 },
        [10] = { name = "TEAL", r = 1.0, g = 5.0, b = 2.5 },
        [11] = { name = "RAINBOW", rainbow = true, feedbackR = 1.0, feedbackG = 0.5, feedbackB = 1.0 },
    },

    BeamModes = {
        [1] = { Inner = 0.2, Outer = 0.4, Multiplier = 2.0 },
        [2] = { Inner = 1.1, Outer = 1.5, Multiplier = 0.8 },
    },

    WEAPON_VALUE_SECTIONS = {
        "WeaponClass", "OrdnanceClass", "CannonClass", "ChargeGunClass", "GunClass", "RocketClass", "MissileClass",
        "MortarClass", "DispenserClass", "LauncherClass", "TargetingGunClass", "RadarLauncherClass", "PopperGunClass",
        "ObjectLobberClass", "RemoteDetonatorClass", "LeaderRoundClass", nil,
    },
    WEAPON_REFERENCE_LABELS = { "ordName", "ordnanceName", "shotClass", "projectileClass", "objectClass" },
    WEAPON_RANGE_LABELS = { "maxRange", "engageRange", "maxDist", "engageDist", "shotRange", "range", "lockRange" },
    WEAPON_DELAY_LABELS = { "shotDelay", "reloadTime", "reloadDelay", "firstDelay" },
    DAMAGE_LABELS = {
        "damage",
        "damage1", "damage2", "damage3", "damage4", "damage5", "damage6", "damage7", "damage8",
        "damageBallistic", "damageConcussion", "damageFlame", "damageImpact", "damageArea", "damageEM",
    },
    DAMAGE_SECTIONS = { "WeaponClass", "OrdnanceClass", "ExplosionClass", "CannonClass", "GunClass", "RocketClass", "MissileClass", "MortarClass", nil },
    EXPLOSION_REFERENCE_LABELS = { "xplVehicle", "xplCar", "xplBuilding", "xplGround", "xplPilot" },
    EXPLOSION_RADIUS_LABELS = { "damageRadius", "explRadius" },
}
