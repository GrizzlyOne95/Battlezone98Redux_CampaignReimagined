-- Escape from Mars: a short visual insert at the existing transport-liftoff VO.
-- The caller supplies its co-op camera/removal adapters. A preplaced fixture
-- rises on every peer via the acknowledged visual event, as in Mission 16.
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
    local rocket = api.handle("cr06_rocket")
    if not api.valid(rocket) then return end
    local pose = api.transform(rocket)
    state.launchFilm = { rocket = rocket, pad = pad, pose = pose,
        baseY = pose.posit_y, started = api.time(), camera = false }
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
    -- The rebuilt fixture faces the clear approach corridor. This lower
    -- engine-side view shows the dorsal lamps and clustered ignition.
    api.camera(shot.rocket, 8000, -1500, 9000, shot.rocket)
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
