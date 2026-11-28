-- CRPilotBranch: shared pieces of the N64 Pilot Mode branches (Battlezone 64,
-- byte g_800B93D5), used by the scripted PlayerPilotMode adapters
-- (adapter.scripted = true). Ported from Battlezone_Z64Tools
-- redux_lua/bz64pilot.lua; the per-mission branches live in each misnNNcr.
--
-- On the cart the option does two things:
--   * the engine's unit-command interface returns early (8015C2A8), so the
--     player cannot order units: Lock() re-issues each team-1 craft's current
--     order at priority 1, which the player cannot override;
--   * each mission script gives the orders the player would have given
--     (deploy, build queue, turret spots, wingmen follow, supply pods).
-- The HUD counters and voice reports the engine also hides have no Lua switch.

local P = {}

local SWEEP = 0.5
local LOCKABLE = {
    "NONE", "SELECT", "STOP", "ATTACK", "FOLLOW", "FORMATION", "PICKUP",
    "GET_REPAIR", "GET_RELOAD", "GET_WEAPON", "DEFEND", "RESCUE", "RECYCLE",
    "SCAVENGE", "HUNT", "GET_IN",
}

local lockable

local function alive(h) return h ~= nil and IsAlive(h) end
P.alive = alive

local function lockTable()
    if lockable then return lockable end
    lockable = {}
    for _, name in ipairs(LOCKABLE) do
        local cmd = AiCommand and AiCommand[name]
        if cmd ~= nil then lockable[cmd] = true end
    end
    return lockable
end

-- Fresh per-mission branch state; store it in the mission's save table.
function P.NewState()
    return { nextSweep = 0, resend = {}, lastPlayer = nil, followAt = 0,
             supply = P.NewSupply() }
end

-- Command lock. Orders with a target position (go, patrol, drop off, build)
-- can't be read back from Lua, so those are left alone. `skip(h)` true keeps
-- a handle out (scripted units the mission still drives itself).
function P.Lock(S, now, skip)
    if now < (S.nextSweep or 0) then return end
    S.nextSweep = now + SWEEP
    local player = GetPlayerHandle()
    if not alive(player) then return end
    local team = GetTeamNum(player)
    local ok = lockTable()
    for h in AllCraft() do
        if h ~= player and GetTeamNum(h) == team and (not skip or not skip(h)) then
            local cmd = GetCurrentCommand(h)
            if ok[cmd] then
                if cmd == AiCommand.SELECT then cmd = AiCommand.NONE end
                SetCommand(h, cmd, 1, GetCurrentWho(h))
            end
        end
    end
end

-- Undo the lock when the mode turns off: re-issue each locked order at
-- priority 0 so the player can command the unit again. The next Lock sweep
-- runs at once, so a quick off/on toggle re-locks on the next frame.
function P.Release(S)
    if S then S.nextSweep = 0 end
    local player = GetPlayerHandle()
    if not alive(player) then return end
    local team = GetTeamNum(player)
    local ok = lockTable()
    for h in AllCraft() do
        if h ~= player and GetTeamNum(h) == team then
            local cmd = GetCurrentCommand(h)
            if ok[cmd] then
                if cmd == AiCommand.SELECT then cmd = AiCommand.NONE end
                SetCommand(h, cmd, 0, GetCurrentWho(h))
            end
        end
    end
end

-- Unit registration. Claim(S, h) is true the first time a handle reaches a
-- mission's PilotAddObject and false after, so registration (slot fills,
-- counters, placement orders) runs once per unit. Adopt(S, addObject) passes
-- every existing team-1 object except the player through addObject; the
-- scripted adapter's enable hook calls it when the mode turns on, which also
-- covers a PDA toggle mid-mission. The claimed list lives in the branch state,
-- so it survives a save; dead handles are pruned on each Adopt.
function P.Claim(S, h)
    S.claimed = S.claimed or {}
    if #S.claimed >= 64 then -- drop dead handles
        local kept = {}
        for _, k in ipairs(S.claimed) do
            if IsValid(k) then kept[#kept + 1] = k end
        end
        S.claimed = kept
    end
    for _, k in ipairs(S.claimed) do
        if k == h then return false end
    end
    S.claimed[#S.claimed + 1] = h
    return true
end

function P.Adopt(S, addObject)
    local kept = {}
    for _, k in ipairs(S.claimed or {}) do
        if IsValid(k) then kept[#kept + 1] = k end
    end
    S.claimed = kept
    local player = GetPlayerHandle()
    for h in AllObjects() do
        -- One unit's failed order must not stop the rest being adopted.
        if h ~= player and GetTeamNum(h) == 1 then pcall(addObject, h) end
    end
end

-- A producer can take a new build order: deployed and not building.
function P.Ready(h)
    return alive(h) and IsDeployed(h) and not IsBusy(h)
end

-- Producer re-send: an undeployed producer not on its way gets Goto(target)
-- again after `delay` s (60 N64 frames, 6 s). Goto on a geyser deploys a
-- recycler/factory on arrival.
function P.Resend(S, key, h, target, now, delay)
    if not alive(h) or IsDeployed(h) or target == nil then S.resend[key] = nil; return end
    if GetCurrentCommand(h) == AiCommand.GO then S.resend[key] = nil; return end
    local due = S.resend[key]
    if not due then S.resend[key] = now + (delay or 6); return end
    if now >= due then
        Goto(h, target, 1)
        S.resend[key] = nil
    end
end

-- Wingmen follow: on a craft change and every `period` s (30 on the cart).
function P.FollowPlayer(S, units, player, now, period)
    if not alive(player) then return end
    if S.lastPlayer == nil then S.lastPlayer = player; S.followAt = now + (period or 30); return end
    if S.lastPlayer ~= player or now >= (S.followAt or 0) then
        for _, h in ipairs(units) do
            if alive(h) then Follow(h, player, 1) end
        end
        S.lastPlayer = player
        S.followAt = now + (period or 30)
    end
end

-- Repair and ammo pods for the player. When the player's craft drops below
-- 75% health or ammo and no pod of that kind stands, the producer builds one;
-- the request re-arms once a new pod of that kind appears (NoteSupply).
function P.NewSupply()
    return { repairArmed = true, ammoArmed = true, wantRepair = 0, wantAmmo = 0 }
end

function P.NoteSupply(S, h, repairOdf, ammoOdf)
    local sup = S.supply
    if IsOdf(h, ammoOdf or "apammo") then
        if not alive(sup.ammo) then sup.ammo = h; sup.ammoArmed = true end
    elseif IsOdf(h, repairOdf or "aprepa") then
        if not alive(sup.repair) then sup.repair = h; sup.repairArmed = true end
    end
end

function P.WatchSupply(S, player)
    local sup = S.supply
    if not alive(player) then return end
    if GetHealth(player) < 0.75 and not alive(sup.repair) and sup.repairArmed then sup.wantRepair = 1 end
    if GetAmmo(player) < 0.75 and not alive(sup.ammo) and sup.ammoArmed then sup.wantAmmo = 1 end
end

-- Repair first, then ammo. True while a request holds the producer: the
-- branches skip the rest of their build queue that frame.
function P.BuildSupply(S, producer, repairOdf, ammoOdf)
    local sup = S.supply
    if sup.wantRepair > 0 then
        if P.Ready(producer) and GetScrap(1) > 0 then
            Build(producer, repairOdf or "aprepa", 1)
            sup.repairArmed = false
            sup.wantRepair = sup.wantRepair - 1
        end
        return true
    end
    if sup.wantAmmo > 0 then
        if P.Ready(producer) and GetScrap(1) > 0 then
            Build(producer, ammoOdf or "apammo", 1)
            sup.ammoArmed = false
            sup.wantAmmo = sup.wantAmmo - 1
        end
        return true
    end
    return false
end

-- Build `odf` when the producer is ready and scrap covers `cost`. Returns
-- true so a queue can `return P.TryBuild(...)` (first unmet item wins).
function P.TryBuild(producer, odf, cost)
    if P.Ready(producer) and GetScrap(1) >= (cost or 0) then
        Build(producer, odf, 1)
    end
    return true
end

return P
