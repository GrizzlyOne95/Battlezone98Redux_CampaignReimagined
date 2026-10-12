-- Authored tour. Paths are serialized in sxshow.bzn; CameraPath height/speed are
-- centimeters. A scene's `shots` cut between camera setups at the given times. Keep a
-- shot's target fixed or smoothly moving: the native camera aims straight at it each
-- frame, so swapping targets mid-shot snaps the view.
-- `caption` lines are the trailer-facing text; `sx debug` shows raw telemetry instead.
local SXScenes = {}
SXScenes.Features = { "overlay", "materials", "animation", "environment", "ai", "chunks",
    "filters", "radio", "command", "radar", "hud", "autosave", "options", "music" }

-- Ten craft from all three factions, then three barracks, in kill order. The dolly
-- runs north at 8.5 m/s from z 98400, 25 m beside the row, aimed at a fixed marker past
-- the far end; each victim dies 50 m ahead of the camera, about 27 degrees off center.
SXScenes.Breaks = { "break_1", "break_2", "break_3", "break_4", "break_5", "break_6",
    "break_7", "break_8", "break_9", "break_10", "break_b1", "break_b2", "break_b3" }
local breakAhead = { 70, 90, 110, 130, 150, 170, 190, 210, 230, 250, 290, 325, 360 } -- m past z 98400
local breakCues = {}
for i, key in ipairs(SXScenes.Breaks) do
    breakCues[i] = { at = math.floor((breakAhead[i] - 50) / 8.5 * 10 + 0.5) / 10, id = "break", key = key }
end
breakCues[1].caption = "Every hull breaks into its own real fragments"
breakCues[5].caption = "American, Soviet and Chinese armor - each shatters its own way"
breakCues[8].caption = "Even the walkers come apart limb by limb"
breakCues[11].caption = "And the buildings fall piece by piece"

-- Material lab: hard livery cuts, quickening, then a held color with a pulsing glow.
local materialCues = { { at = 5, id = "flash", color = "red", caption = "Full repaints, swapped live - no restart, no new model" } }
do
    local colors, t, step = { "gold", "green", "cyan", "blue", "magenta", "red", "gold", "green", "blue", "magenta" }, 5, 1.6
    for _, color in ipairs(colors) do
        t, step = t + step, math.max(0.6, step * 0.86)
        materialCues[#materialCues + 1] = { at = math.floor(t * 10 + 0.5) / 10, id = "flash", color = color }
    end
    materialCues[#materialCues + 1] = { at = 18, id = "flash", color = "cyan" }
    materialCues[#materialCues + 1] = { at = 19, id = "glow", caption = "Glow driven frame by frame from mission script" }
    materialCues[#materialCues + 1] = { at = 30, id = "flash", color = "magenta" }
    materialCues[#materialCues + 1] = { at = 34, id = "baseline", caption = "...and back to stock in an instant" }
end

SXScenes.List = {
    { id = "arrival", duration = 25, camera = "path", path = "sx_arrive", target = "changed",
        height = 600, speed = 400, title = "OPERATION LIVEWIRE",
        caption = "OpenShim + EXU: a living proving ground inside Battlezone 98 Redux",
        cues = { { at = 3, id = "music-start" } } },
    -- Two scouts parked side by side 10 m apart, noses north. The look anchor is 30 m
    -- south of them, centered, so the camera sits just north of the pair and looks past
    -- them; the pod itself is a speck behind. Offsets are centimeters in the anchor's
    -- frame (it faces +z like the scouts): forward 4500 = 15 m in front of the scouts.
    { id = "materials", duration = 40, camera = "object", target = "mat_look", title = "LIVE MATERIALS",
        caption = "Two identical scouts. Watch the near one.",
        shots = { { at = 0, target = "mat_look", right = -500, up = 320, forward = 4300,
                to = { right = -350, up = 260, forward = 3950 } },
            { at = 18, target = "mat_look", right = -300, up = 220, forward = 4100,
                to = { right = -200, up = 200, forward = 3950 } } },
        cues = materialCues },
    -- The outpost from its east side: parked vehicles 10-20 m out, the comm building and
    -- hangar behind them fade into the weather. storm_look sits between those buildings
    -- and faces +z, so `right` is east. Precipitation is camera-attached.
    { id = "environment", duration = 60, camera = "object", target = "storm_look", title = "LIVE WEATHER",
        caption = "Real particle weather, scripted mid-mission",
        shots = { { at = 0, target = "storm_look", right = 8000, up = 500, forward = 0,
                to = { right = 7200, up = 450, forward = 600 } },
            { at = 29, target = "storm_look", right = 6000, up = 250, forward = -1200,
                to = { right = 5600, up = 240, forward = -800 } },
            { at = 41, target = "storm_look", right = 9500, up = 1200, forward = 2500,
                to = { right = 9000, up = 1000, forward = 1500 } } },
        cues = { { at = 0, id = "weather-start" },
            { at = 3, id = "weather-rain", caption = "Rain rolls in - particles, splashes and wet light" },
            { at = 14, id = "weather-storm", caption = "...building to a storm" },
            { at = 17, id = "weather-strike", caption = "Lightning that hits the ground" },
            { at = 20.5, id = "weather-strike", cloud = true }, { at = 23, id = "weather-strike" },
            { at = 26, id = "weather-strike" },
            { at = 29, id = "weather-snow", caption = "Snow on the same range, no reload" },
            { at = 41, id = "weather-dust", caption = "A dust storm driven by live wind" },
            { at = 53, id = "weather-clear", caption = "...then back to a still lunar night" } } },
    { id = "ai", duration = 60, camera = "object", target = "ai_tuned", title = "SMARTER AI",
        caption = "Two identical tanks. One fights stock - one has been retuned.",
        shots = { { at = 0, path = "sx_ai_chase", target = "ai_tuned", right = 1600, up = 600, forward = -2400 },
            { at = 21, path = "sx_ai_front", target = "ai_tuned", right = -1800, up = 700, forward = 2000 },
            { at = 41, path = "sx_ai_side", target = "ai_stock", right = 1600, up = 600, forward = -2400 } },
        cues = { { at = 0, id = "ai-attack" },
            { at = 12, id = "ai-tune", caption = "The retuned tank backs off and weaves, holding its range" },
            { at = 41, id = "ai-cut", caption = "The stock tank just charges straight in" } } },
    { id = "chunks", duration = 45, camera = "path", path = "sx_break", target = "break_look",
        height = 300, speed = 850, title = "REAL DESTRUCTION",
        caption = "Thirteen kills down the line", cues = breakCues },
    { id = "filters", duration = 55, camera = "path", target = "shield_enemy", title = "FRIEND OR FOE",
        caption = "Defenses that know which side you are on",
        shots = { { at = 0, path = "sx_fil_shield", target = "shield_enemy", height = 300, speed = 250 },
            { at = 17, path = "sx_fil_magnet", target = "magnet_enemy", height = 300, speed = 280 },
            { at = 31, path = "sx_fil_prox", target = "pe_enemy", height = 400, speed = 180 } },
        cues = { { at = 2, id = "shield-ally", caption = "A friendly scout races through the shield..." },
            { at = 4, id = "shield-enemy", caption = "...and the enemy chasing it is thrown back" },
            { at = 18, id = "magnet-ally", caption = "Friendly traffic sails past the magnet mine..." },
            { at = 20, id = "magnet-enemy", caption = "...while the pursuer is dragged in and pinned" },
            { at = 33, id = "prox-protected", caption = "Mines that let their own side drive straight over..." },
            { at = 42, id = "prox-check" },
            { at = 43, id = "prox-targeted", caption = "...and go off under anyone else" } } },
    { id = "control", duration = 45, camera = "path", path = "sx_radio_cam", target = "radio",
        height = 300, speed = 160, title = "COMMAND & CONTROL",
        caption = "Unit radio chatter you can mute, throttle and reroute",
        cues = { { at = 2, id = "radio-normal" },
            { at = 9, id = "command-film", caption = "The Hunt order, rewired to run a custom route" },
            { at = 15, id = "radio-muted", caption = "Radio silence on demand" },
            { at = 23, id = "radio-throttled", caption = "...or just less chatter" },
            { at = 29, id = "music-pause", caption = "Full control of the soundtrack, too" }, { at = 33, id = "music-resume" },
            { at = 37, id = "music-change" }, { at = 43, id = "music-stop" } } },
    { id = "cockpit", duration = 45, camera = "gameplay", title = "YOUR COCKPIT, REWIRED",
        caption = "The stock HUD, driven live from script",
        cues = { { at = 0, id = "cockpit-start" }, { at = 6, id = "radar-map", caption = "Bigger radar, longer range" },
            { at = 14, id = "radar-scan", caption = "Faster sweeps" },
            { at = 20, id = "hud-move", caption = "Readouts moved and recolored" },
            { at = 27, id = "hud-values", caption = "Hull and ammo respond in real time" },
            { at = 36, id = "cockpit-baseline", caption = "Everything snaps back when the scene ends" } } },
    { id = "handover", duration = 30, camera = "gameplay", title = "YOUR TURN",
        caption = "Autosave, live options, and the whole range is yours",
        cues = { { at = 1, id = "music-restart" }, { at = 4, id = "autosave-preview" },
            { at = 12, id = "options", caption = "Press Esc - the new settings pages are live" },
            { at = 23, id = "freeplay", caption = "Replay any bay with sx <chapter>" } } },
}

-- Only these prefixed objects belong to this mission. Temporary actors are removed
-- after their bay; stable navigation/camera markers and the scouts survive for free play.
SXScenes.Fixtures = {
    control = { odf = "avfigh", path = "sx_control", keep = true },
    changed = { odf = "avfigh", path = "sx_changed", keep = true },
    mat_look = { odf = "sxanchor", path = "sx_mat_look", keep = true },
    convoy = { odf = "avfigh", path = "sx_convoy", keep = true },
    weather_anchor = { odf = "sxanchor", path = "sx_weather_anchor", keep = true, name = "Atmosphere overlook" },
    storm_look = { odf = "sxanchor", path = "sx_storm_look", keep = true },
    ai_anchor = { odf = "sxanchor", path = "sx_ai_anchor", keep = true, name = "AI arena" },
    break_anchor = { odf = "sxanchor", path = "sx_break_anchor", keep = true, name = "Destruction yard" },
    filter_anchor = { odf = "sxanchor", path = "sx_filter_anchor", keep = true, name = "Team filter range" },
    ai_stock = { odf = "avtank", path = "sx_ai_stock", group = "ai", ammo = 1000, health = 50000 },
    ai_tuned = { odf = "avtank", path = "sx_ai_tuned", group = "ai", ammo = 1000, health = 50000 },
    ai_target_a = { odf = "svfigh", path = "sx_ai_target_a", group = "ai", team = 5, health = 50000, ammo = 1000 },
    ai_target_b = { odf = "svfigh", path = "sx_ai_target_b", group = "ai", team = 5, health = 50000, ammo = 1000 },
    break_1 = { odf = "avtank", path = "sx_break_1", group = "chunks", holdPosition = true },
    break_2 = { odf = "svfigh", path = "sx_break_2", group = "chunks", holdPosition = true },
    break_3 = { odf = "avrckt", path = "sx_break_3", group = "chunks", holdPosition = true },
    break_4 = { odf = "cvtank", path = "sx_break_4", group = "chunks", holdPosition = true },
    break_5 = { odf = "avapc", path = "sx_break_5", group = "chunks", holdPosition = true },
    break_6 = { odf = "svtank", path = "sx_break_6", group = "chunks", holdPosition = true },
    break_7 = { odf = "avltnk", path = "sx_break_7", group = "chunks", holdPosition = true },
    break_8 = { odf = "cvwalk", path = "sx_break_8", group = "chunks", holdPosition = true },
    break_9 = { odf = "svwalk", path = "sx_break_9", group = "chunks", holdPosition = true },
    break_10 = { odf = "avwalk", path = "sx_break_10", group = "chunks", holdPosition = true },
    break_b1 = { odf = "abbarr", path = "sx_break_b1", group = "chunks" },
    break_b2 = { odf = "sbbarr", path = "sx_break_b2", group = "chunks" },
    break_b3 = { odf = "cbbarr", path = "sx_break_b3", group = "chunks" },
    break_look = { odf = "sxanchor", path = "sx_break_look", group = "chunks" },
    shield = { odf = "sxshield", path = "sx_shield", group = "filters", class = "shieldtower" },
    shield_power = { odf = "abspow", path = "sx_shield_power", group = "filters" },
    shield_ally = { odf = "avfigh", path = "sx_shield_ally", group = "filters", health = 10000 },
    shield_enemy = { odf = "avfigh", path = "sx_shield_enemy", group = "filters", team = 5, health = 10000 },
    magnet = { odf = "sxmag", path = "sx_magnet", group = "filters", class = "magnet" },
    magnet_ally = { odf = "avfigh", path = "sx_magnet_ally", group = "filters", health = 10000 },
    magnet_enemy = { odf = "avfigh", path = "sx_magnet_enemy", group = "filters", team = 5, health = 10000 },
    prox_enemy = { odf = "sxproxe", path = "sx_prox_enemy", group = "filters", class = "proximity" },
    pe_ally = { odf = "avfigh", path = "sx_pe_ally", group = "filters", health = 10000 },
    pe_enemy = { odf = "avfigh", path = "sx_pe_enemy", group = "filters", team = 5, health = 10000 },
    prox_ally = { odf = "sxproxa", path = "sx_prox_ally", group = "filters", class = "proximity" },
    pa_ally = { odf = "avfigh", path = "sx_pa_ally", group = "filters", health = 10000 },
    pa_enemy = { odf = "avfigh", path = "sx_pa_enemy", group = "filters", team = 5, health = 10000 },
    radio = { odf = "avtank", path = "sx_radio", keep = true, name = "Command / radio station" },
}

SXScenes.Routes = {
    convoy = "sx_convoy_route", radio = "sx_radio_route", radio_return = "sx_radio_return",
    shield_ally = "sx_shield_ally_run", shield_enemy = "sx_shield_enemy_run",
    magnet_ally = "sx_magnet_ally_run", magnet_enemy = "sx_magnet_enemy_run",
    pe_ally = "sx_pe_ally_run", pe_enemy = "sx_pe_enemy_run",
    pa_ally = "sx_pa_ally_run", pa_enemy = "sx_pa_enemy_run",
}

function SXScenes.Find(id)
    for _, scene in ipairs(SXScenes.List) do if scene.id == id then return scene end end
end
return SXScenes
