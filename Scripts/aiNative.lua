-- aiNative.lua
-- Bridge between Lua AI strategy (aiCore) and native per-unit AI tuning
-- provided by ExtraUtilities (exu.dll) + BZR OpenShim (winmm.dll).
--
-- Native knobs ride the OpenShim CalcRange / retarget detours (no new code
-- patches are required for these to work):
--   engageRange    - floor (meters) on the AI fire range (UnitTask rangeSq):
--                    the unit ends its attack run and opens fire at this
--                    distance instead of driving closer
--   weaponRangeMin - floor (meters) on the native "too close" band (UnitTask
--                    closeSq): inside it units hold fire, back away and kite;
--                    natively clamped to 90% of the final fire range
--   retargetPeriod - seconds between forced enemy re-acquisition scans
--   kiteDesiredRange - movement equilibrium while the firing-state retreat is active
--   kiteEnterRange   - begin firing-state retreat at or inside this distance
--   kiteExitRange    - stop retreat at or beyond this distance (hysteresis)
--   kitePreserveLos  - suppress reverse movement if its projected position
--                      would lose terrain line-of-sight to the target
--   kiteStrafe       - lateral steering strength (0..1) during retreat
--   kiteSwitchPeriod - seconds between alternating lateral retreat sides
--
-- Per-unit values win over ODF-level engageRangeAI/weaponRangeMinAI tuning
-- and apply regardless of exu.SetAiOdfGameplayTuningEnabled.
--
-- IMPORTANT: the native override map is keyed by object pointer, which does
-- not survive a save/load cycle. Policies must be re-pushed after Load();
-- aiCore does this by recomputing policies (see aiCore.ApplyNativeTactics).

local aiNative = {}

aiNative.Debug = false

local function GetExu()
    return rawget(_G, "exu")
end

function aiNative.IsAvailable()
    local exu = GetExu()
    return (exu ~= nil) and (exu.SetAiUnitTuning ~= nil)
end

-- [handle] = { engageRange = m|nil, weaponRangeMin = m|nil, retargetPeriod = s|nil }
-- Runtime-only mirror; not saved. Rebuilt after load by aiCore.
aiNative.policies = aiNative.policies or {}

local function PushPolicy(h, policy)
    local exu = GetExu()
    if not exu or not exu.SetAiUnitTuning then return false end
    local ok, result = pcall(exu.SetAiUnitTuning, h, {
        engageRange = policy.engageRange,
        weaponRangeMin = policy.weaponRangeMin,
        retargetPeriod = policy.retargetPeriod,
        kiteDesiredRange = policy.kiteDesiredRange,
        kiteEnterRange = policy.kiteEnterRange,
        kiteExitRange = policy.kiteExitRange,
        kitePreserveLos = policy.kitePreserveLos,
        kiteStrafe = policy.kiteStrafe,
        kiteSwitchPeriod = policy.kiteSwitchPeriod,
    })
    if not ok and aiNative.Debug then
        print("aiNative: SetAiUnitTuning failed: " .. tostring(result))
    end
    return ok and result == true
end

-- Apply (or replace) the native tuning policy for one unit.
-- policy: { engageRange = m, weaponRangeMin = m, retargetPeriod = s }
-- Passing an empty/nil-field policy clears the unit.
function aiNative.ApplyUnitPolicy(h, policy)
    if not IsValid(h) then return false end
    if type(policy) ~= "table" then return false end

    local stored = {
        engageRange = tonumber(policy.engageRange),
        weaponRangeMin = tonumber(policy.weaponRangeMin),
        retargetPeriod = tonumber(policy.retargetPeriod),
        kiteDesiredRange = tonumber(policy.kiteDesiredRange),
        kiteEnterRange = tonumber(policy.kiteEnterRange),
        kiteExitRange = tonumber(policy.kiteExitRange),
        kitePreserveLos = policy.kitePreserveLos == true,
        kiteStrafe = tonumber(policy.kiteStrafe),
        kiteSwitchPeriod = tonumber(policy.kiteSwitchPeriod),
        healthBand = policy.healthBand,
        healthThreshold = tonumber(policy.healthThreshold),
    }
    if not stored.engageRange and not stored.weaponRangeMin and not stored.retargetPeriod
        and not stored.kiteDesiredRange and not stored.kiteEnterRange
        and not stored.kiteExitRange then
        return aiNative.ClearUnit(h)
    end

    local applied = PushPolicy(h, stored)
    if applied then
        aiNative.policies[h] = stored
    else
        -- Do not let a transient bridge/hook failure suppress the discovery
        -- sweep's next retry for this unit.
        aiNative.policies[h] = nil
    end
    return applied
end

function aiNative.GetUnitPolicy(h)
    return aiNative.policies[h]
end

function aiNative.ClearUnit(h)
    aiNative.policies[h] = nil
    local exu = GetExu()
    if exu and exu.ClearAiUnitTuning then
        pcall(exu.ClearAiUnitTuning, h)
    end
    return true
end

function aiNative.ClearAll()
    aiNative.policies = {}
    local exu = GetExu()
    if exu and exu.ClearAllAiUnitTuning then
        pcall(exu.ClearAllAiUnitTuning)
    end
end

-- Re-push every stored policy for still-valid handles and drop stale ones.
-- Use when the native map may be stale but Lua policies are still correct.
function aiNative.Reapply()
    local exu = GetExu()
    if exu and exu.ClearAllAiUnitTuning then
        pcall(exu.ClearAllAiUnitTuning)
    end

    local stale = {}
    for h, policy in pairs(aiNative.policies) do
        if IsValid(h) then
            PushPolicy(h, policy)
        else
            stale[#stale + 1] = h
        end
    end
    for _, h in ipairs(stale) do
        aiNative.policies[h] = nil
    end
end

----------------------------------------------------------------------------------
-- Native target-selection callback
--
-- Rides EXU's ChooseAttackTarget vtable-slot hooks (RTTI + slot verified at
-- install). The handler fires whenever a wingman-family AI unit scans for an
-- enemy on its own:
--   handler(unitHandle, candidateHandle|nil, rangeLimit|nil)
--     return nil    -> keep the engine's pick
--     return false  -> veto (no target this scan)
--     return handle -> override with this target (validated natively)
-- Pass nil to remove the handler and disable dispatch.
----------------------------------------------------------------------------------

function aiNative.SetTargetSelectHandler(handler)
    local exu = GetExu()
    if not exu or not exu.SetAiTargetSelectEnabled then return false end
    if handler ~= nil and type(handler) ~= "function" then return false end
    rawset(exu, "AiTargetSelect", handler)
    local ok = pcall(exu.SetAiTargetSelectEnabled, handler ~= nil)
    return ok and (handler == nil or (exu.GetAiTargetSelectEnabled and exu.GetAiTargetSelectEnabled() == true)) or false
end

-- Adjust each candidate's native comparison score without replacing the
-- engine's search. handler(unit, candidate, baseDistance, stockLane) returns:
--   nil/invalid -> stock distance, number -> adjusted score, false -> reject.
-- Lower scores win within the engine's existing eligibility/category lanes.
function aiNative.SetTargetScoreHandler(handler)
    local exu = GetExu()
    if not exu or not exu.SetAiTargetScoringEnabled then return false end
    if handler ~= nil and type(handler) ~= "function" then return false end
    rawset(exu, "AiTargetScore", handler)
    local ok, result = pcall(exu.SetAiTargetScoringEnabled, handler ~= nil)
    if not ok or result ~= true then return false end
    return handler == nil or (exu.GetAiTargetScoringEnabled
        and exu.GetAiTargetScoringEnabled() == true) or false
end

----------------------------------------------------------------------------------
-- Task-state watching (polled)
--
-- Emulates an OnAiStateChange callback by polling exu.GetAiTaskState for
-- watched units at aiNative.watchInterval. A native transition detour can
-- replace the poll later without changing callers: the callback signature
-- stays (h, info, oldTypeName, oldState).
----------------------------------------------------------------------------------

aiNative.watch = aiNative.watch or {}
aiNative.watchInterval = 0.5
aiNative._nextWatchAt = 0.0

function aiNative.WatchTaskState(h, callback)
    if not IsValid(h) or type(callback) ~= "function" then return false end
    local exu = GetExu()
    if not exu or not exu.GetAiTaskState then return false end
    aiNative.watch[h] = { callback = callback, lastType = nil, lastState = nil }
    return true
end

function aiNative.UnwatchTaskState(h)
    aiNative.watch[h] = nil
end

-- Call once per mission Update().
function aiNative.Update()
    local now = GetTime()
    if now < (aiNative._nextWatchAt or 0.0) then return end
    aiNative._nextWatchAt = now + (aiNative.watchInterval or 0.5)

    local exu = GetExu()
    if not exu or not exu.GetAiTaskState then return end

    local stale = {}
    for h, entry in pairs(aiNative.watch) do
        if not IsValid(h) then
            stale[#stale + 1] = h
        else
            local ok, info = pcall(exu.GetAiTaskState, h)
            if ok and type(info) == "table" then
                local newType = info.typeName
                local newState = info.curState
                if entry.lastType ~= newType or entry.lastState ~= newState then
                    local oldType, oldState = entry.lastType, entry.lastState
                    entry.lastType = newType
                    entry.lastState = newState
                    local cbOk, err = pcall(entry.callback, h, info, oldType, oldState)
                    if not cbOk and aiNative.Debug then
                        print("aiNative: watch callback error: " .. tostring(err))
                    end
                end
            end
        end
    end
    for _, h in ipairs(stale) do
        aiNative.watch[h] = nil
    end
end

return aiNative
