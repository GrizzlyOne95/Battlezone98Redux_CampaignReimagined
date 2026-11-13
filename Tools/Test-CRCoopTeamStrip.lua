-- Resolve Scripts/ relative to this file so require() works without LUA_PATH.
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
package.path = toolsDir .. "/../Scripts/?.lua;" .. package.path
local Strip, Pda = require("CRCoopTeamStrip"), require("CRCoopPda")
local Data = require("PersistentConfigData")
local checks = 0
local function check(v, label) assert(v, label); checks = checks + 1 end

-- Fake overlay API: records live elements so leaks are visible.
local live, text, color, shownEl = {}, {}, {}, {}
local exu = { OVERLAY_METRICS = { PIXELS = 1 }, GetGameResolution = function() return 1920, 1080 end }
function exu.CreateOverlay(n) live[n] = true; return true end
function exu.CreateOverlayElement(_, n) assert(not live[n], "duplicate " .. n); live[n] = true; return true end
function exu.DestroyOverlayElement(n) live[n] = nil; text[n], color[n], shownEl[n] = nil, nil, nil; return true end
function exu.DestroyOverlay(n) live[n] = nil; return true end
function exu.SetOverlayCaption(n, c) text[n] = c; return true end
function exu.SetOverlayTextColor(n, r, g, b) color[n] = { r, g, b }; return true end
function exu.ShowOverlayElement(n) shownEl[n] = true; return true end
function exu.HideOverlayElement(n) shownEl[n] = false; return true end
for _, fn in ipairs({ "AddOverlay2D", "SetOverlayZOrder", "SetOverlayMetricsMode", "AddOverlayElementChild",
    "SetOverlayTextFont", "SetOverlayMaterial", "SetOverlayParameter", "SetOverlayPosition", "SetOverlayDimensions",
    "SetOverlayTextCharHeight", "RemoveOverlayElementChild", "RemoveOverlay2D" }) do
    exu[fn] = function() return true end
end
local overlayHidden = false
function exu.HideOverlay() overlayHidden = true; return true end
function exu.ShowOverlay() overlayHidden = false; return true end
local function liveCount() local n = 0 for _ in pairs(live) do n = n + 1 end return n end
local P = "CR/TeamStrip/Text"
local FULL = 6 -- overlay + root + four text lines

-- Fake co-op session: me = 30 (Ann). Describe/IsCritical report what CRCoopComms would.
local active, stripOn, clock = true, true, 0
local me = 30
local players = { [20] = { name = "Ian", team = 1 }, [30] = { name = "Ann", team = 2 },
    [40] = { name = "Bo of a very long name indeed", team = 3 }, [50] = { name = "Cy", team = 4, lateJoin = true },
    [60] = { name = "Foe", team = 9 } }
local words = { [20] = "H80 A50", [40] = "on foot" }
local critical = {}
local comms = { IsActive = function() return active end,
    TeamStripOn = function() return stripOn end,
    SetTeamStrip = function(on) stripOn = on end,
    Describe = function(id) return words[id] or "" end,
    IsCritical = function(id) return critical[id] == true end }
local coop = { GetLocalPlayerId = function() return me end, GetPlayers = function() return players end,
    IsHumanTeam = function(t) return t >= 1 and t <= 4 end }
local strip = Strip.Create({ exu = exu, coop = coop, comms = function() return comms end, time = function() return clock end })
local function tick() clock = clock + 0.3; strip.Update() end

-- Lines from fake statuses: teammates only, no self, no late joiner, no other team, sorted, name cut to 16.
tick()
local lines = strip.Lines()
check(#lines == 2, "two teammates listed")
check(lines[1].text == "Ian  H 80  A 50" and not lines[1].critical, "hull/ammo line")
check(lines[2].text == "Bo of a very lon  on foot", "on-foot line, name truncated")
check(text[P .. 1] == "Ian  H 80  A 50" and text[P .. 2] == "Bo of a very lon  on foot", "captions drawn")
check(shownEl[P .. 1] and shownEl[P .. 2], "used lines shown")
check(liveCount() == FULL, "overlay elements created")
local normal = color[P .. 1]
-- Critical colour differs from normal.
words[20] = "H20 A50 !"; critical[20] = true
tick()
check(text[P .. 1] == "Ian  H 20  A 50", "critical text has no trailing bang")
check(color[P .. 1][1] > 0.9 and color[P .. 1][3] < 0.5 and color[P .. 1][3] ~= normal[3], "critical is red")
check(color[P .. 2][1] == normal[1] and color[P .. 2][3] == normal[3], "other line stays normal")
-- Needs-a-ride and empty status.
words[40] = "NEEDS A RIDE"; words[20] = ""; critical[20] = false
tick()
check(text[P .. 2] == "Bo of a very lon  NEEDS A RIDE", "needs-a-ride text")
check(text[P .. 1] == "Ian  ...", "no status yet")
-- Throttle: a change inside the period is not drawn yet.
words[40] = "on foot"
strip.Update()
check(text[P .. 2] == "Bo of a very lon  NEEDS A RIDE", "update is throttled")
tick()
check(text[P .. 2] == "Bo of a very lon  on foot", "drawn on the next period")
-- Pause/cinematic suppression destroys; the next normal tick rebuilds.
strip.Update(true)
check(overlayHidden and liveCount() == FULL, "suppressed hides the overlay without destroying it")
tick()
check(not overlayHidden and text[P .. 2] == "Bo of a very lon  on foot", "shown again after suppression")
-- Reload: a fresh module instance must still remove the previous state's overlay by name.
check(liveCount() == FULL, "overlay up before reload")
Strip.Create({ exu = exu, coop = coop, comms = function() return comms end, time = function() return clock end }).Destroy()
check(liveCount() == 0, "fresh instance Destroy clears the leftover overlay")
strip.Destroy() -- the old Lua state is gone after a real reload; start clean
tick()
-- A teammate leaving hides their line.
local bo = players[40]; players[40] = nil; tick()
check(shownEl[P .. 2] == false, "unused line hidden")
players[40] = bo
-- Toggle off hides and destroys.
stripOn = false; tick()
check(liveCount() == 0 and not strip.IsShown(), "toggle off destroys the overlay")
stripOn = true; tick()
check(liveCount() == FULL and strip.IsShown(), "toggle on shows again")
-- No teammates: hidden.
local others = players
players = { [30] = others[30] }; tick()
check(liveCount() == 0, "hidden with no teammates")
players = others; tick()
check(liveCount() == FULL, "shown when a teammate joins")
-- Not in co-op: hidden.
active = false; tick()
check(liveCount() == 0, "hidden outside co-op")
active = true; tick()
check(liveCount() == FULL, "shown again in co-op")
-- Teardown (mission end / load / co-op teardown) destroys everything, and is idempotent.
strip.Destroy(); strip.Destroy()
check(liveCount() == 0 and not strip.IsShown(), "destroy leaves no overlay behind")
tick()
check(liveCount() == FULL, "can be shown again after teardown")
-- A stale element from an earlier Lua state does not stop the rebuild.
strip.Destroy(); live["CR/TeamStrip/Root"] = true
tick()
check(strip.IsShown() and liveCount() == FULL, "stale elements are cleared before creating")
-- Missing overlay API shows nothing and never throws.
local bare = Strip.Create({ exu = {}, coop = coop, comms = function() return comms end, time = function() return clock end })
clock = clock + 1; bare.Update()
check(not bare.IsShown(), "missing overlay API shows nothing")
-- Only four lines.
players = { [30] = others[30] }
for id = 1, 6 do players[id * 100] = { name = "P" .. id, team = 1 } end
check(#strip.Lines() == 4, "capped at four lines")

-- CRHudLayout: the strip reserves dock left_mid (clear of the command menu) and moves when the resolution changes.
strip.Destroy()
local Layout = require("CRHudLayout")
local rootPos
exu.SetOverlayPosition = function(n, x, y) if n == "CR/TeamStrip/Root" then rootPos = { x, y } end return true end
local resW, resH = 1920, 1080
exu.GetGameResolution = function() return resW, resH end
active, stripOn = true, true
Layout.Reset(exu); Layout.Refresh(100, exu)
tick()
check(rootPos ~= nil, "strip placed through the layout")
local _, my, _, mh = Layout.GetKeepOut("command_menu")
check(my and rootPos[2] >= my + mh, "strip sits below the command menu keep-out")
local firstY = rootPos[2]
resW, resH = 1280, 720
Layout.Refresh(102, exu)
tick()
check(rootPos[2] ~= firstY and rootPos[2] < 720, "strip re-placed after a resolution change")
check(liveCount() == FULL, "re-place leaks no overlay elements")
strip.Destroy()
check(Layout.GetReservation("CR/TeamStrip") == nil, "Destroy releases the reservation")

-- PDA row: TEAM STRIP toggles through the comms service.
local pdaComms = { IsActive = function() return true end, GetPings = function() return {} end,
    GetRequests = function() return {} end, IsOnFoot = function() return false end,
    CanGive = function() return false end, Describe = function() return "" end,
    MarkersOn = function() return true end, SetMarkers = function() end,
    HostMarkerOn = function() return false end, SetHostMarker = function() end,
    TeamStripOn = function() return stripOn end, SetTeamStrip = function(on) stripOn = on end,
    CallForHelp = function() return true end, CancelRescue = function() return true end }
local ui = Pda.Create({ coop = { GetComms = function() return pdaComms end, IsAuthority = function() return false end,
    GetLocalPlayerId = function() return 30 end, GetPlayers = function() return {} end,
    IsHumanTeam = function() return true end, IsSessionReady = function() return true end },
    pages = Data.PdaPages, feedback = error, time = function() return 0 end, selected = function() return {} end })
stripOn = true
local function render() return ui.BuildText(function() return "==COOP==" end, function() end) end
check(render():find("TEAM STRIP ON", 1, true), "PDA shows TEAM STRIP ON")
for _, a in ipairs(ui.Actions()) do if a.key == "strip" then a.run() end end
check(stripOn == false and render():find("TEAM STRIP OFF", 1, true), "PDA row toggles the strip")

print("CRCoopTeamStrip: " .. checks .. " checks passed")
