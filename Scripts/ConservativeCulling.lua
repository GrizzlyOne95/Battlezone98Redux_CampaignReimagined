---@diagnostic disable: lowercase-global, undefined-global
local exu = require("exu")

local ConservativeCulling = {
    Enabled = true,
    HardHideScenery = false,

    UnitShadowDisableDistance = 300.0,
    UnitShadowRestoreDistance = 240.0,
    PropRenderDistance = 260.0,
    SceneryHideDistance = 420.0,
    SceneryRestoreDistance = 340.0,

    BatchInterval = 0.05,
    BatchSize = 48,

    Initialized = false,
    SupportsUnitShadows = false,
    SupportsPropRenderDistance = false,
    SupportsHardHide = false,

    TrackedHandles = {},
    TrackedHandleSet = {},
    StateByHandle = {},
    Cursor = 1,
    BatchAt = 0.0,
}

local INTERACTIVE_NEUTRAL_LABELS = {
    scrap = true,
    person = true,
    wingman = true,
    special_item = true,
    powerup_generic = true,
    camera_pod = true,
    dropoff = true,
    recycler = true,
    factory = true,
    armory = true,
    constructor = true,
    supplydepot = true,
    repairdepot = true,
    powerplant = true,
    barracks = true,
    commtower = true,
    silo = true,
}

local RENDER_DISTANCE_PATTERNS = {
    "sign",
    "rock",
    "tree",
    "plant",
    "bush",
    "shrub",
    "cactus",
    "prop",
    "clutter",
    "ruin",
    "debris",
    "scenery",
}

local HARD_HIDE_PATTERNS = {
    "sign",
    "rock",
    "tree",
    "plant",
    "bush",
    "shrub",
    "cactus",
    "clutter",
    "scenery",
}

local function CleanString(value)
    if type(value) ~= "string" then
        return ""
    end
    value = value:gsub("%z", "")
    return string.lower(value)
end

local function MatchesPattern(value, patterns)
    if value == "" then
        return false
    end

    for _, pattern in ipairs(patterns) do
        if string.find(value, pattern, 1, true) then
            return true
        end
    end

    return false
end

local function GetDistanceToPlayer(player, h)
    if not player or not h or not IsValid(player) or not IsValid(h) then
        return math.huge
    end

    local ok, distance = pcall(GetDistance, player, h)
    if ok and type(distance) == "number" then
        return distance
    end

    return math.huge
end

local function IsNeutralPropCandidate(h, label, odfName)
    if not h or not IsValid(h) then
        return false
    end

    if IsCraft(h) or IsBuilding(h) then
        return false
    end

    if GetTeamNum(h) ~= 0 then
        return false
    end

    if label ~= "" and INTERACTIVE_NEUTRAL_LABELS[label] then
        return false
    end

    if label == "sign" then
        return true
    end

    return MatchesPattern(label, RENDER_DISTANCE_PATTERNS)
        or MatchesPattern(odfName, RENDER_DISTANCE_PATTERNS)
end

local function IsHardHideSceneryCandidate(h, label, odfName)
    if not IsNeutralPropCandidate(h, label, odfName) then
        return false
    end

    return label == "sign"
        or MatchesPattern(label, HARD_HIDE_PATTERNS)
        or MatchesPattern(odfName, HARD_HIDE_PATTERNS)
end

local function TrackHandle(h)
    if not h or not IsValid(h) or ConservativeCulling.TrackedHandleSet[h] then
        return
    end

    local label = CleanString(GetClassLabel and GetClassLabel(h) or "")
    local odfName = CleanString(GetOdf and GetOdf(h) or "")

    local state = {
        handle = h,
        kind = "object",
        originalCastShadows = exu.GetEntityCastShadows and exu.GetEntityCastShadows(h),
        shadowsSuppressed = false,
    }

    if IsNeutralPropCandidate(h, label, odfName) then
        state = {
            handle = h,
            kind = IsHardHideSceneryCandidate(h, label, odfName) and "scenery" or "prop",
            originalCastShadows = exu.GetEntityCastShadows and exu.GetEntityCastShadows(h),
            shadowsSuppressed = false,
            originalRenderingDistance = exu.GetEntityRenderingDistance and exu.GetEntityRenderingDistance(h),
            originalVisible = exu.GetEntityVisible and exu.GetEntityVisible(h),
            renderDistanceApplied = false,
            hidden = false,
        }
    end

    if not state then
        return
    end

    ConservativeCulling.TrackedHandleSet[h] = true
    ConservativeCulling.TrackedHandles[#ConservativeCulling.TrackedHandles + 1] = h
    ConservativeCulling.StateByHandle[h] = state

    if state.kind ~= "unit"
        and ConservativeCulling.SupportsPropRenderDistance
        and state.originalRenderingDistance ~= nil
        and (state.originalRenderingDistance <= 0.0 or state.originalRenderingDistance > ConservativeCulling.PropRenderDistance)
    then
        exu.SetEntityRenderingDistance(h, ConservativeCulling.PropRenderDistance)
        state.renderDistanceApplied = true
    end
end

local function RefreshTrackedHandles()
    local compactedHandles = {}
    local compactedSet = {}
    for _, h in ipairs(ConservativeCulling.TrackedHandles) do
        if h and IsValid(h) and ConservativeCulling.StateByHandle[h] then
            compactedHandles[#compactedHandles + 1] = h
            compactedSet[h] = true
        else
            ConservativeCulling.StateByHandle[h] = nil
        end
    end
    ConservativeCulling.TrackedHandles = compactedHandles
    ConservativeCulling.TrackedHandleSet = compactedSet

    if not AllObjects then
        return
    end

    for h in AllObjects() do
        TrackHandle(h)
    end

    ConservativeCulling.Cursor = 1
end

local function UpdateShadowState(state, player)
    if not ConservativeCulling.SupportsUnitShadows then
        return
    end

    local h = state.handle
    if not IsValid(h) then
        return
    end

    local distance = GetDistanceToPlayer(player, h)
    if distance >= ConservativeCulling.UnitShadowDisableDistance and not state.shadowsSuppressed then
        exu.SetEntityCastShadows(h, false)
        state.shadowsSuppressed = true
    elseif distance <= ConservativeCulling.UnitShadowRestoreDistance and state.shadowsSuppressed then
        exu.SetEntityCastShadows(h, state.originalCastShadows ~= false)
        state.shadowsSuppressed = false
    end
end

local function UpdateSceneryState(state, player)
    if not (ConservativeCulling.SupportsHardHide and ConservativeCulling.HardHideScenery) then
        return
    end

    local h = state.handle
    if not IsValid(h) then
        return
    end

    local distance = GetDistanceToPlayer(player, h)
    if distance >= ConservativeCulling.SceneryHideDistance and not state.hidden then
        exu.SetEntityVisible(h, false)
        state.hidden = true
    elseif distance <= ConservativeCulling.SceneryRestoreDistance and state.hidden then
        exu.SetEntityVisible(h, state.originalVisible ~= false)
        state.hidden = false
    end
end

function ConservativeCulling.Initialize()
    if ConservativeCulling.Initialized then
        return
    end

    ConservativeCulling.Initialized = true
    ConservativeCulling.SupportsUnitShadows = ConservativeCulling.Enabled
        and exu
        and not exu.isStub
        and exu.SetEntityCastShadows
        and exu.GetEntityCastShadows

    ConservativeCulling.SupportsPropRenderDistance = ConservativeCulling.Enabled
        and exu
        and not exu.isStub
        and exu.SetEntityRenderingDistance
        and exu.GetEntityRenderingDistance

    ConservativeCulling.SupportsHardHide = ConservativeCulling.Enabled
        and exu
        and not exu.isStub
        and exu.SetEntityVisible
        and exu.GetEntityVisible

    if not (ConservativeCulling.SupportsUnitShadows
            or ConservativeCulling.SupportsPropRenderDistance
            or ConservativeCulling.SupportsHardHide)
    then
        return
    end

    RefreshTrackedHandles()
end

function ConservativeCulling.OnObjectCreated(h)
    ConservativeCulling.Initialize()
    if not ConservativeCulling.Enabled then
        return
    end

    TrackHandle(h)
end

function ConservativeCulling.Update()
    ConservativeCulling.Initialize()
    if not ConservativeCulling.Enabled then
        return
    end

    local player = GetPlayerHandle and GetPlayerHandle() or nil
    local now = GetTime and GetTime() or 0.0

    if now < (ConservativeCulling.BatchAt or 0.0) then
        return
    end
    ConservativeCulling.BatchAt = now + ConservativeCulling.BatchInterval

    local handles = ConservativeCulling.TrackedHandles
    local cursor = ConservativeCulling.Cursor or 1
    local processed = 0

    while cursor <= #handles and processed < ConservativeCulling.BatchSize do
        local h = handles[cursor]
        local state = h and ConservativeCulling.StateByHandle[h] or nil

        if not h or not state or not IsValid(h) then
            ConservativeCulling.StateByHandle[h] = nil
        else
            UpdateShadowState(state, player)
            if state.kind == "scenery" then
                UpdateSceneryState(state, player)
            end
        end

        cursor = cursor + 1
        processed = processed + 1
    end

    if cursor > #handles then
        ConservativeCulling.Cursor = 1
    else
        ConservativeCulling.Cursor = cursor
    end
end

return ConservativeCulling
