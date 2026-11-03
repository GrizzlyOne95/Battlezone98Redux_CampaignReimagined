---@diagnostic disable: lowercase-global, undefined-global
-- Single-player difficulty for the NSDF missions (misn06..misn14, misn17, misn18), on top of Scripts/DiffUtils.lua.
-- Offline only: a network game, or a host without DiffUtils, is left exactly as the mission wrote it.
--   scrap/pilots  player  = DiffUtils.ScaleRes(amount), clamped to capacity (a fill to capacity stays a fill)
--                 enemy   = max(amount, DiffUtils.ScaleEnemy(amount)), so easier settings never lower a top-up
--   combat spawns Hard/Very Hard add (enemy multiplier - 1) extras per scripted hostile unit on average (Hard 0.5,
--                 randomly rounded per unit; Very Hard 1), built where the original is and mirroring every order the
--                 mission later gives it. Easier settings never remove units. Timers are not scaled.
-- A mission wraps the natives it uses with lexical locals (Resource, Build, Mirror), so its DLL-port body is untouched.
local D = {}

local okDiff, DiffUtils = pcall(require, "DiffUtils")
if not okDiff or type(DiffUtils) ~= "table" then DiffUtils = nil end

-- Scripted hostile combat units. Buildings, scrap, navs, haulers, scavengers, pilots, walkers and one-off named craft are
-- deliberately absent.
D.COMBAT = { svfigh = true, svtank = true, svltnk = true, hvsav = true, hvsat = true }

local function NetworkGame()
    local ok, CRCoop = pcall(require, "CRCoop")
    return ok and type(CRCoop) == "table" and type(CRCoop.IsNetworkGame) == "function" and CRCoop.IsNetworkGame() or false
end

function D.Active()
    return DiffUtils ~= nil and not NetworkGame()
end

-- Extras for one hostile unit: floor(enemy - 1), plus one more with the fractional chance (Hard 0.5, Very Hard 1).
function D.Extras()
    if not D.Active() then return 0 end
    local surplus = DiffUtils.Get().enemy - 1
    if surplus <= 0 then return 0 end
    local n = math.floor(surplus)
    if math.random() < surplus - n then n = n + 1 end
    return n
end

-- Player amount for a set (or top-up) call; max is the team's capacity when known.
function D.PlayerAmount(amount, max, additive)
    if not D.Active() or type(amount) ~= "number" then return amount end
    if additive then
        return amount > 0 and DiffUtils.ScaleRes(amount) or amount
    end
    if max and amount >= max then return amount end
    local scaled = DiffUtils.ScaleRes(amount)
    if max then scaled = math.min(scaled, max) end
    return scaled
end

function D.EnemyAmount(amount)
    if not D.Active() or type(amount) ~= "number" or amount <= 0 then return amount end
    return math.max(amount, DiffUtils.ScaleEnemy(amount))
end

-- Wraps SetScrap/SetPilot (additive false) or AddScrap/AddPilot (additive true). Team 1 is the player; hostile is a
-- set of enemy team numbers. Other teams and negative costs pass through.
function D.Resource(native, getMax, hostile, additive)
    return function(team, amount, ...)
        if team == 1 then
            local max = (not additive) and getMax and getMax(team) or nil
            return native(team, D.PlayerAmount(amount, max, additive), ...)
        elseif hostile[team] then
            return native(team, D.EnemyAmount(amount), ...)
        end
        return native(team, amount, ...)
    end
end

local extrasOf = {}

-- Wraps BuildObject: a hostile combat unit comes with its extras, remembered for Mirror.
function D.Build(native, hostile, odfs)
    odfs = odfs or D.COMBAT
    return function(odf, team, where, ...)
        local h = native(odf, team, where, ...)
        if h ~= nil and h ~= 0 and hostile[team] and odfs[odf] then
            local list
            for _ = 1, D.Extras() do
                local extra = native(odf, team, where, ...)
                if extra ~= nil and extra ~= 0 then
                    list = list or {}
                    list[#list + 1] = extra
                end
            end
            extrasOf[h] = list
            -- Fallback leadership for verbs a mission does not wrap (and after a load, when extrasOf is empty).
            local follow = list and rawget(_G, "Follow")
            if follow then
                for _, extra in ipairs(list) do follow(extra, h) end
            end
        elseif h ~= nil and h ~= 0 then
            extrasOf[h] = nil -- a reused handle must not inherit a stale list
        end
        return h
    end
end

-- Wraps order verbs (Attack, Goto, ...): whatever the unit is told, its extras are told too.
function D.Mirror(...)
    local wrapped = {}
    for i = 1, select("#", ...) do
        local native = select(i, ...)
        wrapped[i] = function(h, ...)
            local list = extrasOf[h]
            if list then
                local alive = rawget(_G, "IsAlive")
                for _, extra in ipairs(list) do
                    if not alive or alive(extra) then native(extra, ...) end
                end
            end
            return native(h, ...)
        end
    end
    return unpack(wrapped, 1, select("#", ...))
end

-- Wraps RemoveObject: the extras go with their unit.
function D.Remove(native)
    return function(h, ...)
        local list = extrasOf[h]
        if list then
            extrasOf[h] = nil
            for _, extra in ipairs(list) do native(extra, ...) end
        end
        return native(h, ...)
    end
end

-- SetTeamNum / SetPerceivedTeam need no wrapper of their own: Mirror(SetTeamNum, SetPerceivedTeam) re-issues them.

return D
