-- Local material presentation. Event callbacks copy a bounded queue; Update
-- owns renderer work. Shared rain uniforms, owned per-object clones for damage,
-- power, heat and two impact marks. No gameplay/AI/network writes.
local exu = require("exu")
local S = { Enabled = true, Wetness = 0, Clock = 0, MaxEvents = 64,
    MaxRecords = 4096, MaxActive = 64, MaxHeated = 8, PollBudget = 4, MaterialBudget = 16,
    records = {}, order = {}, cursor = 1, materials = {}, materialOrder = {}, materialCursor = 1,
    hits = {}, shots = {}, active = {}, activeSet = {}, activeCursor = 1,
    clones = {}, nextId = 0, timer = 0, bindCursor = 1, started = false, gen = 0,
    -- Cockpit glass damage (CRWetGlass) and electrical brownout.
    CrackStages = { { enter = 0.50, leave = 0.55, level = 0.35 }, { enter = 0.25, leave = 0.30, level = 0.80 } },
    BrownoutDrop = 0.05, BrownoutHold = 0.12, BrownoutCooldown = 0.4, MaxCrackSpots = 32,
    crackSpots = {}, crackSpotCount = 0, crackLevel = 0, glassOn = false }

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end
local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, finite(x) and x or lo)) end
local function valid(h) return h ~= nil and call(IsValid, h) == true end
local function vector(x, y, z) return SetVector(x, y, z) end
local function point(t)
    if t == nil then return nil end
    local x, y, z = t.posit_x or t.x, t.posit_y or t.y, t.posit_z or t.z
    if finite(x) and finite(y) and finite(z) then return { x = x, y = y, z = z } end
end
local function target(r) return r.cockpit and {kind = "cockpit", handle = r.handle} or r.handle end
local function own(name) return type(name) == "string" and string.sub(name, 1, 12) == "exu_surface_" end
local function ready()
    for _, name in ipairs({"GetSubEntityCount", "GetSubEntityMaterial", "SetSubEntityMaterial", "CloneSurfaceMaterial",
        "ReleaseSurfaceMaterial", "SetSurfaceMaterial", "SetMaterialShaderVector", "EntityLocalPoint"}) do
        if type(exu[name]) ~= "function" then return false end
    end
    return true
end

-- Reactive surfaces are an Enhanced feature. DX9 and DX11 Stock/Retro keep
-- their stock materials; the profile is re-read each tick so a live switch
-- releases or rebuilds the owned clones.
local function enhanced()
    local profile = call(exu.GetEffectiveRenderProfile)
    return type(profile) == "string" and string.lower(profile) == "enhanced"
end

local function wetMaterial(name)
    if type(name) ~= "string" or name == "" or own(name) or S.materials[name] or #S.materialOrder >= 4096 then return end
    S.materials[name] = {}; S.materialOrder[#S.materialOrder + 1] = name
end

local function write(slot, name, a, b, c, d)
    local old = slot.values[name]
    if old and math.abs(old[1]-a) < 0.001 and math.abs(old[2]-b) < 0.001 and
        math.abs(old[3]-c) < 0.001 and math.abs(old[4]-d) < 0.001 then return end
    local changed = call(exu.SetMaterialShaderVector, slot.assigned, name, a, b, c, d)
    if finite(changed) and changed > 0 then slot.values[name] = {a,b,c,d} end
end

local function release(r)
    for _, slot in ipairs(r.slots or {}) do
        -- Another owner (team colour, model replacement, etc.) wins. Never
        -- restore a stale source over its assignment.
        if valid(r.handle) and call(exu.GetSubEntityMaterial, target(r), slot.index) == slot.assigned then
            call(exu.SetSubEntityMaterial, target(r), slot.index, slot.source)
        end
        for _, name in ipairs({slot.normal, slot.off}) do
            if name then call(exu.ReleaseSurfaceMaterial, name); S.clones[name] = nil end
        end
    end
    r.slots, r.count, r.bindIndex = {}, nil, 0
end

local function activate(r)
    if S.activeSet[r] then return end
    if #S.active >= S.MaxActive then
        local oldest
        for i, old in ipairs(S.active) do
            if not next(old.heat) and (not oldest or (old.touched or 0) < (S.active[oldest].touched or 0)) then oldest = i end
        end
        if not oldest then return end
        local old = table.remove(S.active, oldest)
        release(old); old.marks = {}; old.needs = false; S.activeSet[old] = nil
    end
    S.activeSet[r] = true; S.active[#S.active + 1] = r
    r.needs = true
    r.touched = S.Clock
end

function S.Register(h)
    if not S.Enabled or not ready() or h == nil or S.records[h] then return end
    if #S.order >= S.MaxRecords then return end
    S.nextId = S.nextId + 1
    local r = {handle = h, id = S.nextId, slots = {}, bindIndex = 0, heat = {}, marks = {}, damage = 0}
    S.records[h] = r; S.order[#S.order + 1] = h
end

function S.Unregister(h)
    local r = S.records[h]
    if r then release(r); r.dead = true; S.activeSet[r] = nil end
    S.records[h] = nil
    if S.cockpit and S.cockpit.handle == h then release(S.cockpit); S.cockpit = nil end
end

local function discover(r)
    if S.Clock < (r.discoverAt or 0) then return end
    local count = call(exu.GetSubEntityCount, target(r))
    if not finite(count) or count < 1 or count > 64 then r.discoverAt = S.Clock + 1; return end
    local index = r.discover or 0
    if index >= count then index = 0 end
    for _ = 1, math.min(2, count-index) do
        wetMaterial(call(exu.GetSubEntityMaterial, target(r), index))
        index = index + 1
    end
    r.discover = index
    if index >= count then r.discoverAt = S.Clock + 2 end
    if r.tower == nil then r.tower = not r.cockpit and call(GetClassLabel, r.handle) == "turret" end
    if r.tower then activate(r) end
end

local function bindOne(r)
    if not r.needs or S.Clock < (r.retry or 0) then return end
    local count = call(exu.GetSubEntityCount, target(r))
    if not finite(count) or count < 1 or count > 64 then r.retry = S.Clock + 1; return end
    if r.count and r.count ~= count then release(r) end
    r.count = count
    local index = r.bindIndex or 0
    if index >= math.min(count, r.cockpit and 16 or 8) then
        if S.Clock < (r.recheckAt or 0) then return end
        r.recheckAt=S.Clock+2;index=0;r.bindIndex=0
    end
    r.unsupported=r.unsupported or {}
    if S.Clock<(r.unsupported[index] or 0) then r.bindIndex=index+1;return end
    local source = call(exu.GetSubEntityMaterial, target(r), index)
    if own(source) then r.bindIndex=index+1;return end
    if type(source) ~= "string" or source == "" then r.retry = S.Clock + 1; return end
    wetMaterial(source)
    local name = "exu_surface_cr_" .. tostring(r.id) .. "_" .. tostring(index) .. (r.cockpit and "_cockpit" or "")
    if call(exu.CloneSurfaceMaterial, source, name) ~= true then r.retry = S.Clock + 1; return end
    S.clones[name] = true
    -- Only the owned clone's glow pass gets the Enhanced program; the shared
    -- CR_BZBase glow pass keeps CR_Textured_fragment for Stock/Retro.
    call(exu.SetSurfaceFragmentProgram, name, "glow", "CR_TexturedEnhanced_fragment")
    -- Do not replace unsupported stock/particle programs with inert clones.
    local supported = call(exu.SetMaterialShaderVector,name,"surfaceState",0,0,0,0)
    if not finite(supported) or supported < 1 then
        call(exu.ReleaseSurfaceMaterial,name); S.clones[name]=nil; r.bindIndex=index+1;r.unsupported[index]=S.Clock+2; return
    end
    if call(exu.SetSurfaceMaterial, target(r), index, name) ~= true then
        call(exu.ReleaseSurfaceMaterial, name); S.clones[name] = nil; r.retry = S.Clock + 1; return
    end
    local slot = {index = index, source = source, normal = name, assigned = name, values = {}}
    r.slots[#r.slots + 1] = slot; r.bindIndex = index + 1
end

local function radiusMark(position, radius)
    return {position.x, position.y, position.z, radius}
end

local function inRange(h)
    local player = call(GetPlayerHandle)
    if not valid(player) then return false end
    local distance = call(GetDistance, h, player)
    return finite(distance) and distance <= 260
end

local function enqueue(queue, h, transform, odf)
    if #queue >= S.MaxEvents then return end
    local p = point(transform)
    if h ~= nil and p then queue[#queue + 1] = {handle = h, position = p, odf = odf} end
end

function S.NotifyHit(odf, _, hit, transform) enqueue(S.hits, hit, transform, odf) end
function S.NotifyShot(odf, shooter, transform) enqueue(S.shots, shooter, transform, odf) end

local function drain(queue, shot)
    for _ = 1, math.min(2, #queue) do
        local event = table.remove(queue, 1)
        if valid(event.handle) and inRange(event.handle) then
            S.Register(event.handle)
            local r = S.records[event.handle]
            if r then
                if shot then
                    -- Match an actual native firing mount, not a guessed mesh
                    -- slot or a whole-hull tint. Deferred until factory commit.
                    local best, bestDistance
                    for slot = 0, 4 do
                        local muzzle = call(exu.GetWeaponMuzzlePosition, event.handle, slot)
                        if muzzle then
                            local dx, dy, dz = muzzle.x-event.position.x, muzzle.y-event.position.y, muzzle.z-event.position.z
                            local d = dx*dx + dy*dy + dz*dz
                            if not bestDistance or d < bestDistance then best, bestDistance = slot, d end
                        end
                    end
                    if best and bestDistance <= 16 then
                        local heated = 0
                        for _, active in ipairs(S.active) do if next(active.heat) then heated=heated+1 end end
                        local heat = r.heat[best] or {energy = 0, display = 0}
                        local mounts=0; for _ in pairs(r.heat) do mounts=mounts+1 end
                        if (next(r.heat) or heated<S.MaxHeated) and (r.heat[best] or mounts<2) then
                            heat.energy = math.min(0.65, heat.energy + 0.055)
                            r.heat[best] = heat; activate(r); r.touched=S.Clock
                        end
                    end
                else
                    local localPoint = call(exu.EntityLocalPoint, event.handle, vector(event.position.x,event.position.y,event.position.z))
                    if localPoint then
                        if #r.marks >= 2 then table.remove(r.marks, 1) end
                        r.marks[#r.marks + 1] = {anchor = radiusMark(localPoint, 0.65), untilTime = S.Clock + 16}
                        activate(r); r.touched=S.Clock; r.lowHealth=call(GetHealth,r.handle)
                    end
                end
            end
        end
    end
end

-- A real hull loss of at least BrownoutDrop in one tick dips the cockpit's
-- emission (surfaceState.w, the same channel that powers a tower off) for a
-- moment: it eases down in about a tenth of a second and back over about a
-- second. Repair, a new craft and the first sample never trigger it.
local function brownout(r, health, dt)
    local drop = finite(r.lastHull) and r.lastHull-health or 0
    if drop >= S.BrownoutDrop and S.Clock >= (r.brownReady or 0) then
        r.brownDepth = clamp(0.25+drop*2.5, 0.25, 0.6)
        r.brownUntil, r.brownReady = S.Clock+S.BrownoutHold, S.Clock+S.BrownoutCooldown
    end
    r.lastHull = health
    local want = S.Clock < (r.brownUntil or 0) and r.brownDepth or 0
    local now = r.brown or 0
    r.brown = want+(now-want)*math.exp(-dt*(want > now and 18 or 2.5))
    if r.brown < 0.002 then r.brown = 0 end
end

local function updateRecord(r, dt)
    if not valid(r.handle) then S.Unregister(r.handle); return false end
    local health = call(GetHealth, r.handle)
    if finite(health) then
        health = clamp(health,0,1)
        if finite(r.lowHealth) and health > r.lowHealth + 0.04 then r.marks = {}; r.lowHealth=health end
        r.lowHealth = math.min(r.lowHealth or health, health)
        r.health = health
        local desired = r.cockpit and (1-health) or 0
        r.damage = desired + (r.damage-desired)*math.exp(-dt*5)
        if r.cockpit then brownout(r, health, dt) end
    end
    if r.tower then
        local powered = call(exu.IsGunTowerPowered, r.handle)
        if type(powered) == "boolean" then r.powerOff = not powered end
    end
    local anchors, peak = {}, 0
    for slot, heat in pairs(r.heat) do
        heat.energy = math.max(0, heat.energy-dt*0.16)
        heat.display = heat.energy+(heat.display-heat.energy)*math.exp(-dt*6)
        if heat.display < 0.002 then r.heat[slot] = nil
        else
            local world = call(exu.GetWeaponMuzzlePosition, r.handle, slot)
            local localPoint = world and call(exu.EntityLocalPoint,r.handle,world)
            if localPoint and #anchors < 2 then anchors[#anchors+1] = radiusMark(localPoint,0.42); peak = math.max(peak,heat.display) end
        end
    end
    for i=#r.marks,1,-1 do if r.marks[i].untilTime <= S.Clock then table.remove(r.marks,i) end end
    local empty = {0,0,0,0}
    local hit0, hit1 = r.marks[1], r.marks[2]
    for _, slot in ipairs(r.slots) do
        local current = call(exu.GetSubEntityMaterial,target(r),slot.index)
        if current ~= slot.assigned then release(r); r.retry = S.Clock + 0.2; return true end
        local wanted = slot.normal
        if r.powerOff then
            if not slot.off then
                local off = slot.normal .. "_off"
                if call(exu.CloneSurfaceMaterial,slot.source,off) == true then
                    S.clones[off] = true; slot.off = off
                    call(exu.SetSurfaceTexture,off,"EmissiveMap","black.png")
                end
            end
            wanted = slot.off or slot.normal
        end
        if slot.assigned ~= wanted and call(exu.SetSurfaceMaterial,target(r),slot.index,wanted) == true then
            slot.assigned = wanted; slot.values = {}
        end
        write(slot,"surfaceState", r.cockpit and 0 or S.Wetness, r.damage, peak, r.cockpit and (r.brown or 0) or (r.powerOff and 1 or 0))
        write(slot,"surfaceMode",0,r.cockpit and 1 or 0,r.cockpit and S.Clock or 0,0)
        local a,b = hit0 and hit0.anchor or empty,hit1 and hit1.anchor or empty
        write(slot,"surfaceImpact0",a[1],a[2],a[3],a[4]); write(slot,"surfaceImpact1",b[1],b[2],b[3],b[4])
        write(slot,"surfaceImpactWeights",hit0 and clamp((hit0.untilTime-S.Clock)/4,0,1) or 0,
            hit1 and clamp((hit1.untilTime-S.Clock)/4,0,1) or 0,0,0)
        a,b = anchors[1] or empty,anchors[2] or empty
        write(slot,"surfaceMuzzle0",a[1],a[2],a[3],a[4]); write(slot,"surfaceMuzzle1",b[1],b[2],b[3],b[4])
    end
    return true
end

-- Cockpit glass cracks by hull stage, after the ISDF Chronicles cockpit
-- damage preset: a faint star below 50% hull, a strong one below 25%, with
-- hysteresis so damage and repair do not chatter, at a fixed spot per craft.
-- CRWetGlass draws and fades it (on the fitted cockpit glass in F1, else the
-- screen overlay); it only needs Update calls while Busy(). Calls are
-- edge-triggered so a mission's own SetCrack (CRStorm18) is not fought.
local glassModule
local function glass()
    if glassModule == nil then
        local ok, m = pcall(require, "CRWetGlass")
        glassModule = (ok and type(m) == "table" and type(m.SetCrack) == "function" and
            type(m.Update) == "function" and type(m.Busy) == "function") and m or false
    end
    return glassModule or nil
end

local function crackSpot(h)
    local spot = S.crackSpots[h]
    if spot then return spot end
    if S.crackSpotCount >= S.MaxCrackSpots then S.crackSpots, S.crackSpotCount = {}, 0 end
    local text, hash = tostring(h), 0
    for i = 1, #text do hash = (hash*31+text:byte(i)) % 1000003 end
    local x = 0.30+0.40*((hash*0.6180339887) % 1)
    if math.abs(x-0.5) < 0.08 then x = x < 0.5 and 0.42 or 0.58 end -- keep the reticle clear
    spot = { x = x, y = 0.26+0.18*((hash*0.7548776662) % 1) }
    S.crackSpots[h], S.crackSpotCount = spot, S.crackSpotCount+1
    return spot
end

local function setCrack(level, spot)
    if level <= 0 and S.crackLevel <= 0 then return end
    if level == S.crackLevel and (level <= 0 or spot == S.crackAt) then return end
    local g = glass(); if not g then return end
    call(g.SetCrack, level, spot and spot.x, spot and spot.y)
    S.crackLevel, S.crackAt, S.glassOn = level, spot, true
end

-- Every frame, even while disabled or outside Enhanced, until a cleared crack
-- has faded: CRWetGlass only animates while someone calls Update.
local function driveGlass()
    if not S.glassOn then return end
    local g = glass()
    if not g then S.glassOn = false; return end
    call(g.Update, 0)
    if S.crackLevel <= 0 and call(g.Busy) ~= true then S.glassOn = false end
end

local function cockpitGlass(r)
    if not r or not finite(r.health) then setCrack(0); return end
    local hp, st, stage = r.health, S.CrackStages, r.stage
    if stage == nil then stage = hp < st[2].enter and 2 or hp < st[1].enter and 1 or 0
    elseif stage < 2 and hp < st[2].enter then stage = 2
    elseif stage < 1 and hp < st[1].enter then stage = 1
    elseif stage == 2 and hp > st[2].leave then stage = hp > st[1].leave and 0 or 1
    elseif stage == 1 and hp > st[1].leave then stage = 0 end
    r.stage = stage
    setCrack(stage > 0 and st[stage].level or 0, crackSpot(r.handle))
end

local function cockpit()
    local h = call(GetPlayerHandle)
    local visible = valid(h) and call(IsCraft,h) == true and call(exu.GetCameraView) == 1 and call(exu.GetSatState) ~= 1
    if S.cockpit and (not visible or S.cockpit.handle ~= h) then release(S.cockpit); S.cockpit = nil end
    if visible and not S.cockpit then
        S.nextId = S.nextId+1
        S.cockpit = {handle=h,id=S.nextId,cockpit=true,needs=true,slots={},bindIndex=0,marks={},heat={},damage=0}
    end
end

-- exu.BulletHit/BulletInit are single globals and other modules replace or
-- chain them. We wrap whatever is installed now, and Update re-wraps (chaining
-- the current function) if the global stops being our latest wrapper. `busy`
-- makes a wrapper nested inside another of ours pass through, so a callback
-- that replaced the global but still chains an older wrapper notifies once.
local function wrapCallback(field, notify, busy)
    local prev, gen = exu[field], S.gen
    local function wrapper(...)
        if S.gen ~= gen or S[busy] then return call(prev, ...) end
        S[busy] = true
        local a, b = call(prev, ...)
        S[busy] = false
        if S.started and S.Enabled then notify(...) end
        return a, b
    end
    S[field .. "Prev"], S[field .. "Wrapper"] = prev, wrapper
    exu[field] = wrapper
end

local function wrapCallbacks()
    if S.BulletHitWrapper == nil or exu.BulletHit ~= S.BulletHitWrapper then wrapCallback("BulletHit", S.NotifyHit, "hitBusy") end
    if S.BulletInitWrapper == nil or exu.BulletInit ~= S.BulletInitWrapper then wrapCallback("BulletInit", S.NotifyShot, "shotBusy") end
end

function S.Start()
    if S.started or not ready() then return end
    S.started = true
    wrapCallbacks()
    call(exu.SetReactiveChunksEnabled,true)
end

function S.Update(dt)
    driveGlass()
    if not S.Enabled or not ready() then return end
    if not enhanced() then
        if S.started then S.Suspend() end
        return
    end
    S.Start()
    wrapCallbacks()
    dt = clamp(dt,0,0.25); if dt <= 0 then return end
    S.Clock = S.Clock+dt
    local weather = package.loaded.CRWeather
    local rain = weather and call(weather.GetSurfaceWetness) or 0
    rain = clamp(rain,0,1)
    local tau = rain > S.Wetness and 2.5 or 10
    S.Wetness = rain+(S.Wetness-rain)*math.exp(-dt/tau)
    S.timer = S.timer+dt
    if S.timer < 0.05 then return end
    local step = S.timer; S.timer = 0
    drain(S.hits,false); drain(S.shots,true)
    cockpit()
    for _=1,math.min(S.PollBudget,#S.order) do
        if S.cursor > #S.order then S.cursor=1 end
        local h=S.order[S.cursor];local r=S.records[h]
        if r and valid(h) then discover(r);S.cursor=S.cursor+1
        else S.Unregister(h);table.remove(S.order,S.cursor) end
    end
    for _=1,math.min(S.MaterialBudget,#S.materialOrder) do
        if S.materialCursor > #S.materialOrder then S.materialCursor=1 end
        local name=S.materialOrder[S.materialCursor];local state=S.materials[name]
        if S.Clock >= (state.retry or 0) and (not state.wet or math.abs(state.wet-S.Wetness)>0.001) then
            local changed=call(exu.SetMaterialShaderVector,name,"surfaceState",S.Wetness,0,0,0,-1,-1,"Autodetect")
            if finite(changed) and changed > 0 then state.wet=S.Wetness
            else state.retry=S.Clock+2 end
        end
        S.materialCursor=S.materialCursor+1
    end
    -- Hot mounts update at 20 Hz (at most eight craft); cold records get
    -- four bounded slices per tick. Only ONE world clone is created per tick.
    if #S.active>0 then
        if S.bindCursor>#S.active then S.bindCursor=1 end
        local r=S.active[S.bindCursor]
        if not r.dead and S.activeSet[r] then bindOne(r) end
        S.bindCursor=S.bindCursor+1
    end
    for _,r in ipairs(S.active) do
        if not r.dead and S.activeSet[r] and next(r.heat) then
            updateRecord(r,S.Clock-(r.lastUpdate or S.Clock-step));r.lastUpdate=S.Clock
        end
    end
    for _=1,math.min(4,#S.active) do
        if S.activeCursor>#S.active then S.activeCursor=1 end
        local r=S.active[S.activeCursor]
        if r.dead or not S.activeSet[r] then table.remove(S.active,S.activeCursor)
        else
            if r.lastUpdate~=S.Clock then updateRecord(r,S.Clock-(r.lastUpdate or S.Clock-step));r.lastUpdate=S.Clock end
            if not r.tower and not next(r.heat) and #r.marks==0 then
                release(r);r.needs=false;S.activeSet[r]=nil
            end
            S.activeCursor=S.activeCursor+1
        end
    end
    if S.cockpit then bindOne(S.cockpit);updateRecord(S.cockpit,step) end
    cockpitGlass(S.cockpit)
end

function S.ResetScene()
    for _,r in pairs(S.records) do release(r) end
    if S.cockpit then release(S.cockpit) end
    for name in pairs(S.materials) do call(exu.SetMaterialShaderVector,name,"surfaceState",0,0,0,0,-1,-1,"Autodetect") end
    S.records,S.order,S.materials,S.materialOrder,S.active,S.activeSet = {},{},{},{},{},{}
    S.hits,S.shots,S.clones = {},{},{}
    S.cockpit=nil;S.cursor=1;S.materialCursor=1;S.activeCursor=1;S.bindCursor=1;S.Wetness=0;S.timer=0
    setCrack(0);S.crackSpots,S.crackSpotCount={},0
end

-- Player setting. Off restores every owned material, releases clones, unhooks
-- the callbacks and stops all work (Register/Update are no-ops while off).
-- Returns true when the state changed.
function S.SetEnabled(enabled)
    enabled = enabled ~= false
    if S.Enabled == enabled then return false end
    S.Enabled = enabled
    if not enabled then S.Shutdown() end
    return true
end

-- Leaving Enhanced: restore every owned material and unhook, but keep the
-- registered craft so returning to Enhanced resumes without a rebuild.
function S.Suspend()
    for _,r in pairs(S.records) do release(r); r.needs=false; r.marks={}; r.heat={}; r.discover=nil; r.discoverAt=nil end
    if S.cockpit then release(S.cockpit) end
    for name in pairs(S.materials) do call(exu.SetMaterialShaderVector,name,"surfaceState",0,0,0,0,-1,-1,"Autodetect") end
    S.materials,S.materialOrder,S.active,S.activeSet = {},{},{},{}
    S.hits,S.shots,S.clones = {},{},{}
    S.cockpit=nil;S.materialCursor=1;S.activeCursor=1;S.bindCursor=1;S.Wetness=0;S.timer=0
    setCrack(0)
    S.Unhook()
end

function S.Unhook()
    -- Restore only if nothing was layered over us; otherwise our stale wrapper
    -- stays in someone's chain and passes through (generation check).
    if exu.BulletHit==S.BulletHitWrapper then exu.BulletHit=S.BulletHitPrev end
    if exu.BulletInit==S.BulletInitWrapper then exu.BulletInit=S.BulletInitPrev end
    S.BulletHitWrapper,S.BulletInitWrapper,S.BulletHitPrev,S.BulletInitPrev=nil,nil,nil,nil
    S.gen=S.gen+1;S.hitBusy,S.shotBusy=false,false
    S.started=false
    call(exu.SetReactiveChunksEnabled,false)
end

function S.Shutdown()
    S.ResetScene()
    S.Unhook()
end

return S
