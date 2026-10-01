-- Authored 6:30 tour. Paths are serialized in sxshow.bzn; offsets are centimeters.
local SXScenes = {}
SXScenes.Features = { "overlay", "materials", "animation", "environment", "ai", "chunks",
    "filters", "radio", "command", "radar", "hud", "autosave", "options", "music" }
SXScenes.List = {
    { id = "arrival", duration = 25, camera = "path", path = "sx_arrive", target = "changed",
        height = 650, speed = 650, title = "OPERATION LIVEWIRE - lunar proving ground",
        cues = { { at = 3, id = "music-start" } } },
    { id = "materials", duration = 40, camera = "path", path = "sx_mat_a", target = "changed",
        height = 350, speed = 150, title = "MATERIAL LAB - identical scouts; one live variant",
        cues = { { at = 6, id = "service" }, { at = 14, id = "animate" }, { at = 30, id = "baseline" } } },
    { id = "environment", duration = 55, camera = "path", path = "sx_weather", target = "weather_anchor",
        height = 800, speed = 180, title = "ATMOSPHERE - clear, warm light, dust front, clear",
        cues = { { at = 0, id = "weather-start" }, { at = 6, id = "weather-warm" },
            { at = 18, id = "weather-storm" }, { at = 40, id = "weather-clear" } } },
    { id = "ai", duration = 60, camera = "object", target = "ai_anchor", right = -5000, up = 6000, forward = -13000,
        title = "AI ARENA - stock behavior beside tuned standoff and strafe",
        cues = { { at = 0, id = "ai-attack" }, { at = 12, id = "ai-tune" }, { at = 35, id = "ai-cut" } } },
    { id = "chunks", duration = 35, camera = "path", path = "sx_break", target = "break_anchor",
        height = 600, speed = 140, title = "DESTRUCTION - real craft and building deaths",
        cues = { { at = 6, id = "break-craft" }, { at = 18, id = "break-building" } } },
    { id = "filters", duration = 55, camera = "object", target = "filter_anchor", right = -2000, up = 8000, forward = -15000,
        title = "TEAM FILTERS - shield, magnet, and two proximity lanes",
        cues = { { at = 5, id = "shield-ally" }, { at = 11, id = "shield-enemy" },
            { at = 20, id = "magnet-ally" }, { at = 25, id = "magnet-enemy" },
            { at = 33, id = "prox-protected" }, { at = 42, id = "prox-check" }, { at = 43, id = "prox-targeted" } } },
    { id = "control", duration = 45, camera = "path", path = "sx_radio_cam", target = "radio",
        height = 450, speed = 170, title = "CONTROL TOWER - radio policy and the real Hunt slot",
        cues = { { at = 2, id = "radio-normal" }, { at = 9, id = "command-film" },
            { at = 15, id = "radio-muted" }, { at = 23, id = "radio-throttled" },
            { at = 29, id = "music-pause" }, { at = 33, id = "music-resume" },
            { at = 37, id = "music-change" }, { at = 43, id = "music-stop" } } },
    { id = "cockpit", duration = 45, camera = "gameplay", title = "COCKPIT - native radar and live stock readouts",
        cues = { { at = 0, id = "cockpit-start" }, { at = 6, id = "radar-map" },
            { at = 14, id = "radar-scan" }, { at = 20, id = "hud-move" },
            { at = 27, id = "hud-values" }, { at = 36, id = "cockpit-baseline" } } },
    { id = "handover", duration = 30, camera = "gameplay", title = "CHECKPOINT - autosave notification and live options",
        cues = { { at = 1, id = "music-restart" }, { at = 4, id = "autosave-preview" },
            { at = 12, id = "options" }, { at = 23, id = "freeplay" } } },
}

-- Only these prefixed objects belong to this mission. Temporary actors are removed
-- after their bay; stable navigation/camera markers and the scouts survive for free play.
SXScenes.Fixtures = {
    control = { odf = "avfigh", path = "sx_control", keep = true },
    changed = { odf = "avfigh", path = "sx_changed", keep = true },
    convoy = { odf = "avfigh", path = "sx_convoy", keep = true },
    weather_anchor = { odf = "sxanchor", path = "sx_weather_anchor", keep = true, name = "Atmosphere overlook" },
    ai_anchor = { odf = "sxanchor", path = "sx_ai_anchor", keep = true, name = "AI arena" },
    break_anchor = { odf = "sxanchor", path = "sx_break_anchor", keep = true, name = "Destruction yard" },
    filter_anchor = { odf = "sxanchor", path = "sx_filter_anchor", keep = true, name = "Team filter range" },
    ai_stock = { odf = "avtank", path = "sx_ai_stock", group = "ai", ammo = 1000 },
    ai_tuned = { odf = "avtank", path = "sx_ai_tuned", group = "ai", ammo = 1000 },
    ai_target_a = { odf = "avtank", path = "sx_ai_target_a", group = "ai", team = 5, health = 50000 },
    ai_target_b = { odf = "avtank", path = "sx_ai_target_b", group = "ai", team = 5, health = 50000 },
    break_craft = { odf = "avfigh", path = "sx_break_craft", group = "chunks" },
    break_building = { odf = "abbarr", path = "sx_break_building", group = "chunks" },
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
