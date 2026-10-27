-- Escape from Mars: a short visual insert at the existing transport-liftoff VO.
-- The caller supplies its co-op camera/removal adapters. A preplaced fixture
-- rises on every peer via the acknowledged visual event, as in Mission 16.
-- Defaults are Mission 06's. The caller's api may set label (the fixture's map
-- label) and halfHeight (metres, mid-height origin to nozzle plane) to reuse the
-- same shot for another rocket, as Mission 03's NSDF launch does.
local Film = {}
local DURATION = 11
local FLIGHT = 20

function Film.Stop(state, api)
    local shot = state.launchFilm
    if not shot then return end
    if shot.camera then api.finish() end
    shot.camera = false
    if api.fxStop then api.fxStop() end
    if api.valid(shot.rocket) then api.remove(shot.rocket) end
    state.launchFilm = nil
end

function Film.Begin(state, api, pad)
    if state.launchFilmStarted or state.launchFilmTerminal then return end
    state.launchFilmStarted = true
    if not api.valid(pad) then return end
    local rocket = api.handle(api.label or "cr06_rocket")
    if not api.valid(rocket) then return end
    local pose = api.transform(rocket)
    state.launchFilm = { rocket = rocket, pad = pad, pose = pose,
        baseY = pose.posit_y, started = api.time(), camera = false }
    -- Keep the previous elevated framing if terrain changes obstruct the low
    -- clearing. Query only the height field; never issue AI orders to fixtures.
    if type(api.terrain)=="function" then
        local half = api.halfHeight or 48.5
        for i=1,12 do
            local t=i/12
            local x=pose.posit_x+((pose.right_x or 1)*95+(pose.front_x or 0)*20)*t
            local z=pose.posit_z+((pose.right_z or 0)*95+(pose.front_z or 1)*20)*t
            local y=pose.posit_y-half+(half-20)*t
            if api.terrain(x,z)>y-4 then state.launchFilm.highFallback=true;break end
        end
    end
end

function Film.Update(state, api)
    local shot = state.launchFilm
    if not shot then return end
    local elapsed = math.max(0, api.time() - shot.started)
    if elapsed >= FLIGHT or not api.valid(shot.pad) or not api.valid(shot.rocket) then
        Film.Stop(state, api)
        return
    end
    -- One second on the gantry, then an accelerating vertical climb. Absolute
    -- mission time keeps save/resume and variable frame rates on the same arc.
    if not shot.fxLive and api.fxBegin then
        local origin = {posit_x=shot.pose.posit_x,posit_y=shot.baseY,posit_z=shot.pose.posit_z}
        api.fxBegin(origin, elapsed)
        shot.fxLive = true
    end
    if elapsed >= DURATION then
        if shot.camera then api.finish(); shot.camera = false end
        shot.viewDone = true
    end
    if shot.skipped or shot.viewDone then return end
    if not shot.camera then api.ready(); shot.camera = true end
    -- Sunlit clearing beside the raised deck, around the tower rather than
    -- shooting back toward the sun and putting the ivory hull in silhouette.
    -- A gentle pullback leaves room for the widening eight-engine exhaust.
    local t=math.min(1,elapsed/DURATION)
    t=t*t*(3-2*t)
    if shot.highFallback then
        api.camera(shot.rocket,-6500,12500,7500,shot.rocket)
    else
        api.camera(shot.rocket,math.floor(9500+4500*t),math.floor(-2000-500*t),
                   math.floor(2000+950*t),shot.rocket)
    end
    if api.cancelled() then
        api.finish()
        shot.camera, shot.skipped = false, true
        -- The rocket continues its shared flight after a local offline skip.
        -- In co-op the adapter consumes each peer's skip independently.
    end
end

function Film.Load(state)
    -- Native camera ownership is local state, never a saved camera-stack claim.
    if state.launchFilm then state.launchFilm.camera = false; state.launchFilm.fxLive = false end
end

return Film
