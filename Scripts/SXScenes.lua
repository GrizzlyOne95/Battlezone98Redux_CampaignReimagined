-- Authored tour. Paths are serialized in sxshow.bzn; CameraPath height/speed are
-- centimeters. A scene's `shots` cut between camera setups at the given times. Keep a
-- shot's target fixed or smoothly moving: the native camera aims straight at it each
-- frame, so swapping targets mid-shot snaps the view.
-- `caption` lines are the trailer-facing text; `sx debug` shows raw telemetry instead.
local SXScenes = {}
SXScenes.Features = { "overlay", "materials", "animation", "lighting", "environment", "ai", "chunks",
    "gibs", "filters", "radio", "command", "radar", "hud", "autosave", "options" }

-- Destruction yard: four clusters on the flat 131 m plateau, each framed by its own
-- fixed object camera so every kill lands in shot. Anchors face +z, so `right` is
-- east and `forward` north (centimeters). Kill times are seconds into the shot.
SXScenes.BreakShots = {
    { target = "brk_armor", right = -500, up = 450, forward = -3800, to = { right = -300, up = 380, forward = -3300 },
        caption = "Vehicles break into real pieces",
        kills = { { 1.5, "brk_avtank" }, { 3.0, "brk_svtank" }, { 4.3, "brk_cvtank" },
            { 5.6, "brk_avrckt" }, { 6.9, "brk_svltnk" }, { 8.2, "brk_cvfigh" } } },
    { target = "brk_walk", right = 0, up = 500, forward = -4400, to = { right = 200, up = 450, forward = -3800 },
        caption = "Walkers and APCs",
        kills = { { 1.5, "brk_avapc" }, { 3.0, "brk_avwalk" }, { 4.5, "brk_svapc" }, { 6.0, "brk_svwalk" }, { 7.5, "brk_cvwalk" } } },
    { target = "brk_comm", right = 0, up = 1000, forward = -9000, to = { right = 0, up = 900, forward = -8200 },
        caption = "Multi-piece buildings",
        kills = { { 2.0, "brk_abcomm" }, { 4.5, "brk_sbcomm" }, { 7.0, "brk_cbcomm" } } },
    { target = "brk_base", right = -2400, up = 700, forward = -5200, to = { right = -2100, up = 650, forward = -4600 },
        caption = "Full base destruction",
        kills = { { 1.5, "brk_abtowe" }, { 2.4, "brk_sbtowe" }, { 3.3, "brk_cbtowe" }, { 5.0, "brk_abspow" }, { 7.0, "brk_abhqcp" } } },
}
local breakStarts = { 0, 11, 22, 35 }
SXScenes.Breaks = {}
local breakShots, breakCues = {}, {}
for i, shot in ipairs(SXScenes.BreakShots) do
    local at = breakStarts[i]
    breakShots[i] = { at = at, target = shot.target, right = shot.right, up = shot.up, forward = shot.forward, to = shot.to }
    for k, kill in ipairs(shot.kills) do
        SXScenes.Breaks[#SXScenes.Breaks + 1] = kill[2]
        breakCues[#breakCues + 1] = { at = at + kill[1], id = "break", key = kill[2], caption = k == 1 and shot.caption or nil }
    end
end

-- Four stock pilots stand for the first shot; three soldiers then run a crossing lane
-- and fall at their marks (or when the shot ends). The people are neutral (team 0):
-- on a player team the stock pilot AI runs off to look for a craft.
SXScenes.GibStanders = { "gib_aspilo", "gib_bspilo", "gib_cspilo", "gib_sspilo" }
SXScenes.GibRunners = { "gib_assold", "gib_sssold", "gib_cssold" }

-- Renderer comparison: the same frame under each OpenShim render profile.
local lightingCaptions = {
    retro = "Retro",
    redux = "Redux",
    enhanced = "Enhanced (DX11)",
}
local lightingCues = {}
-- The camera holds still inside each shot so every change is a clean A/B flip.
for _, row in ipairs({ { 0, "retro" }, { 4, "redux" }, { 8, "enhanced" }, { 12.5, "retro" }, { 14.5, "enhanced" },
    { 17, "retro" }, { 21, "redux" }, { 25, "enhanced" }, { 29, "retro" }, { 31, "enhanced" } }) do
    lightingCues[#lightingCues + 1] = { at = row[1], id = "light-" .. row[2], caption = lightingCaptions[row[2]] }
end
lightingCues[#lightingCues + 1] = { at = 33, id = "light-inherit", caption = "Switch any time in Settings" }

-- Material lab: hard livery cuts, quickening, then a held color with a pulsing glow.
local materialCues = { { at = 5, id = "flash", color = "red", caption = "Repaint any unit mid-mission" } }
do
    local colors, t, step = { "gold", "green", "cyan", "blue", "magenta", "red", "gold", "green", "blue", "magenta" }, 5, 1.6
    for _, color in ipairs(colors) do
        t, step = t + step, math.max(0.6, step * 0.86)
        materialCues[#materialCues + 1] = { at = math.floor(t * 10 + 0.5) / 10, id = "flash", color = color }
    end
    materialCues[#materialCues + 1] = { at = 18, id = "flash", color = "cyan" }
    materialCues[#materialCues + 1] = { at = 19, id = "glow", caption = "Scripted glow" }
    materialCues[#materialCues + 1] = { at = 30, id = "flash", color = "magenta" }
    materialCues[#materialCues + 1] = { at = 34, id = "baseline", caption = "Instant restore" }
end

SXScenes.List = {
    { id = "arrival", duration = 25, camera = "path", path = "sx_arrive", target = "changed",
        height = 600, speed = 400, title = "OPERATION LIVEWIRE",
        caption = "OpenShim + EXU for Battlezone 98 Redux", cues = {} },
    -- Two scouts parked side by side 10 m apart, noses north. The look anchor is 30 m
    -- south of them, centered, so the camera sits just north of the pair and looks past
    -- them; the pod itself is a speck behind. Offsets are centimeters in the anchor's
    -- frame (it faces +z like the scouts): forward 4500 = 15 m in front of the scouts.
    { id = "materials", duration = 40, camera = "object", target = "mat_look", title = "LIVE MATERIAL SWAPPING",
        caption = "Two identical scouts",
        shots = { { at = 0, target = "mat_look", right = -500, up = 320, forward = 4300,
                to = { right = -350, up = 260, forward = 3950 } },
            { at = 18, target = "mat_look", right = -300, up = 220, forward = 4100,
                to = { right = -200, up = 200, forward = 3950 } } },
        cues = materialCues },
    -- The radio tank, then the parked scout, each from a front three-quarter view and
    -- held still while the profile flips.
    { id = "lighting", duration = 36, camera = "object", target = "radio", title = "RENDER PROFILES",
        caption = "Retro, Redux, Enhanced",
        shots = { { at = 0, target = "radio", right = -900, up = 350, forward = 1100 },
            { at = 17, target = "control", right = -650, up = 260, forward = 950 } },
        cues = lightingCues },
    -- The outpost from its east side: parked vehicles 10-20 m out, the comm building and
    -- hangar behind them fade into the weather. storm_look sits between those buildings
    -- and faces +z, so `right` is east. Precipitation is camera-attached.
    { id = "environment", duration = 60, camera = "object", target = "storm_look", title = "DYNAMIC, SCRIPTABLE WEATHER",
        caption = "Particle weather",
        shots = { { at = 0, target = "storm_look", right = 8000, up = 500, forward = 0,
                to = { right = 7200, up = 450, forward = 600 } },
            -- Mid-storm the camera rushes in, so the rain streams past as from a cockpit.
            { at = 22, target = "storm_look", right = 9000, up = 600, forward = 400, move = 3.5,
                to = { right = 5000, up = 450, forward = 200 } },
            { at = 29, target = "storm_look", right = 6000, up = 250, forward = -1200,
                to = { right = 5600, up = 240, forward = -800 } },
            { at = 41, target = "storm_look", right = 9500, up = 1200, forward = 2500,
                to = { right = 9000, up = 1000, forward = 1500 } } },
        cues = { { at = 0, id = "weather-start" },
            { at = 3, id = "weather-rain", caption = "Rain" },
            { at = 14, id = "weather-storm", caption = "Storm" },
            { at = 17, id = "weather-strike", caption = "Lightning strikes" },
            { at = 20.5, id = "weather-strike", cloud = true }, { at = 23, id = "weather-strike" },
            { at = 26, id = "weather-strike" },
            { at = 29, id = "weather-snow", caption = "Snow" },
            { at = 41, id = "weather-dust", caption = "Dust storm" },
            { at = 53, id = "weather-clear", caption = "Clear" } } },
    -- Same fighter, same fixed turret, side by side 80 m apart on the AI bench. The
    -- tuned fighter holds standoff range; the stock one closes in. The follow shots
    -- chase each fighter, so the turret's size in frame shows the gap.
    { id = "ai", duration = 60, camera = "object", target = "ai_look", title = "SMARTER AI",
        caption = "Stock (left) vs tuned (right)", liveTelemetry = true,
        shots = { { at = 0, target = "ai_look", right = 0, up = 2000, forward = -7000,
                to = { right = 0, up = 1800, forward = -6000 } },
            { at = 20, target = "ai_tuned", right = 250, up = 450, forward = -1500 },
            { at = 40, target = "ai_stock", right = -250, up = 450, forward = -1500 } },
        cues = { { at = 0, id = "ai-attack" },
            { at = 20, id = "ai-view", caption = "Tuned: holds range, strafes" },
            { at = 40, id = "ai-view", caption = "Stock: closes in" } } },
    { id = "chunks", duration = 48, camera = "object", target = "brk_armor", title = "REAL DESTRUCTION",
        caption = "Every faction", shots = breakShots, cues = breakCues },
    { id = "pilots", duration = 24, camera = "object", target = "gib_look", title = "SKINNED GIBS",
        caption = "Pilots break apart by bone",
        shots = { { at = 0, target = "gib_look", right = 0, up = 150, forward = -450,
                to = { right = 0, up = 140, forward = -380 } },
            { at = 12, target = "gib_look", right = 350, up = 180, forward = -1000 } },
        cues = { { at = 2.0, id = "gib-kill", key = "gib_aspilo" }, { at = 4.2, id = "gib-kill", key = "gib_cspilo" },
            { at = 6.4, id = "gib-kill", key = "gib_bspilo" }, { at = 8.6, id = "gib-kill", key = "gib_sspilo" },
            { at = 12, id = "gib-run", caption = "Posed from the death frame" },
            { at = 21, id = "gib-flush" } } },
    -- Each defense is framed from close in, looking across its lanes. The mine shot
    -- aims at a fixed anchor: the mine itself is gone once it fires.
    { id = "filters", duration = 55, camera = "object", target = "shield", title = "TEAM-AWARE DEFENSES",
        caption = "Shields and mines with team filters",
        shots = { { at = 0, target = "shield", right = 2600, up = 350, forward = -2200 },
            { at = 17, target = "magnet", right = 1500, up = 300, forward = -1000 },
            { at = 31, target = "prox_look", right = 0, up = 400, forward = -1500 } },
        cues = { { at = 2, id = "shield-ally", caption = "Shield: allies pass" },
            { at = 4, id = "shield-enemy", caption = "Shield: enemies bounce" },
            { at = 18, id = "magnet-ally", caption = "Magnet: allies pass" },
            { at = 20, id = "magnet-enemy", caption = "Magnet: enemies pulled in" },
            { at = 33, id = "prox-protected", caption = "Mines: safe for allies" },
            { at = 42, id = "prox-check" },
            { at = 43, id = "prox-targeted", caption = "Mines: enemies only" } } },
    { id = "control", duration = 30, camera = "path", path = "sx_radio_cam", target = "radio",
        height = 300, speed = 160, title = "COMMAND & CONTROL",
        caption = "Unit radio control",
        cues = { { at = 2, id = "radio-normal" },
            { at = 9, id = "command-film", caption = "Custom Hunt order" },
            { at = 15, id = "radio-muted", caption = "Radio muted" },
            { at = 23, id = "radio-throttled", caption = "Radio throttled" } } },
    { id = "cockpit", duration = 45, camera = "gameplay", title = "SCRIPTABLE HUD",
        caption = "Stock HUD, script driven",
        cues = { { at = 0, id = "cockpit-start" }, { at = 6, id = "radar-map", caption = "Bigger radar, longer range" },
            { at = 14, id = "radar-scan", caption = "Faster sweeps" },
            { at = 20, id = "hud-move", caption = "Moved and recolored readouts" },
            { at = 27, id = "hud-values", caption = "Live hull and ammo" },
            { at = 36, id = "cockpit-baseline", caption = "Restored on exit" } } },
    { id = "handover", duration = 30, camera = "gameplay", title = "YOUR TURN",
        caption = "Autosave, new settings, free play",
        cues = { { at = 4, id = "autosave-preview" },
            { at = 12, id = "options", caption = "Esc for the new settings pages" },
            { at = 23, id = "freeplay", caption = "Replay a chapter: sx <chapter>" } } },
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
    ai_look = { odf = "sxanchor", path = "sx_ai_look", group = "ai" },
    ai_stock = { odf = "avfigh", path = "sx_ai_stock", group = "ai", ammo = 1000, health = 50000 },
    ai_tuned = { odf = "avfigh", path = "sx_ai_tuned", group = "ai", ammo = 1000, health = 50000 },
    ai_target_a = { odf = "svturr", path = "sx_ai_target_a", group = "ai", team = 5, health = 50000 },
    ai_target_b = { odf = "svturr", path = "sx_ai_target_b", group = "ai", team = 5, health = 50000 },
    brk_armor = { odf = "sxanchor", path = "sx_brk_armor", group = "chunks" },
    brk_walk = { odf = "sxanchor", path = "sx_brk_walk", group = "chunks" },
    brk_comm = { odf = "sxanchor", path = "sx_brk_comm", group = "chunks" },
    brk_base = { odf = "sxanchor", path = "sx_brk_base", group = "chunks" },
    brk_avtank = { odf = "avtank", path = "sx_brk_avtank", group = "chunks", holdPosition = true },
    brk_svtank = { odf = "svtank", path = "sx_brk_svtank", group = "chunks", holdPosition = true },
    brk_cvtank = { odf = "cvtank", path = "sx_brk_cvtank", group = "chunks", holdPosition = true },
    brk_avrckt = { odf = "avrckt", path = "sx_brk_avrckt", group = "chunks", holdPosition = true },
    brk_svltnk = { odf = "svltnk", path = "sx_brk_svltnk", group = "chunks", holdPosition = true },
    brk_cvfigh = { odf = "cvfigh", path = "sx_brk_cvfigh", group = "chunks", holdPosition = true },
    brk_avapc = { odf = "avapc", path = "sx_brk_avapc", group = "chunks", holdPosition = true },
    brk_avwalk = { odf = "avwalk", path = "sx_brk_avwalk", group = "chunks", holdPosition = true },
    brk_svapc = { odf = "svapc", path = "sx_brk_svapc", group = "chunks", holdPosition = true },
    brk_svwalk = { odf = "svwalk", path = "sx_brk_svwalk", group = "chunks", holdPosition = true },
    brk_cvwalk = { odf = "cvwalk", path = "sx_brk_cvwalk", group = "chunks", holdPosition = true },
    brk_abcomm = { odf = "abcomm", path = "sx_brk_abcomm", group = "chunks" },
    brk_sbcomm = { odf = "sbcomm", path = "sx_brk_sbcomm", group = "chunks" },
    brk_cbcomm = { odf = "cbcomm", path = "sx_brk_cbcomm", group = "chunks" },
    brk_abtowe = { odf = "abtowe", path = "sx_brk_abtowe", group = "chunks" },
    brk_sbtowe = { odf = "sbtowe", path = "sx_brk_sbtowe", group = "chunks" },
    brk_cbtowe = { odf = "cbtowe", path = "sx_brk_cbtowe", group = "chunks" },
    brk_abspow = { odf = "abspow", path = "sx_brk_abspow", group = "chunks" },
    brk_abhqcp = { odf = "abhqcp", path = "sx_brk_abhqcp", group = "chunks" },
    gib_look = { odf = "sxanchor", path = "sx_gib_look", group = "pilots" },
    gib_aspilo = { odf = "aspilo", path = "sx_gib_aspilo", group = "pilots", team = 0 },
    gib_bspilo = { odf = "bspilo", path = "sx_gib_bspilo", group = "pilots", team = 0 },
    gib_cspilo = { odf = "cspilo", path = "sx_gib_cspilo", group = "pilots", team = 0 },
    gib_sspilo = { odf = "sspilo", path = "sx_gib_sspilo", group = "pilots", team = 0 },
    gib_assold = { odf = "assold", path = "sx_gib_assold", group = "pilots", team = 0 },
    gib_sssold = { odf = "sssold", path = "sx_gib_sssold", group = "pilots", team = 0 },
    gib_cssold = { odf = "cssold", path = "sx_gib_cssold", group = "pilots", team = 0 },
    shield = { odf = "sxshield", path = "sx_shield", group = "filters", class = "shieldtower" },
    shield_power = { odf = "abspow", path = "sx_shield_power", group = "filters" },
    shield_ally = { odf = "avfigh", path = "sx_shield_ally", group = "filters", health = 10000 },
    shield_enemy = { odf = "avfigh", path = "sx_shield_enemy", group = "filters", team = 5, health = 10000 },
    magnet = { odf = "sxmag", path = "sx_magnet", group = "filters", class = "magnet" },
    magnet_ally = { odf = "avfigh", path = "sx_magnet_ally", group = "filters", health = 10000 },
    magnet_enemy = { odf = "avfigh", path = "sx_magnet_enemy", group = "filters", team = 5, health = 10000 },
    prox_enemy = { odf = "sxproxe", path = "sx_prox_enemy", group = "filters", class = "proximity" },
    prox_look = { odf = "sxanchor", path = "sx_prox_look", group = "filters" },
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
    gib_assold = "sx_gib_run_1", gib_sssold = "sx_gib_run_2", gib_cssold = "sx_gib_run_3",
}
-- Where each runner falls: the middle of its lane, staggered so they drop in turn.
SXScenes.GibMarks = { gib_assold = "sx_gib_mark_1", gib_sssold = "sx_gib_mark_2", gib_cssold = "sx_gib_mark_3" }

function SXScenes.Find(id)
    for _, scene in ipairs(SXScenes.List) do if scene.id == id then return scene end end
end
return SXScenes
