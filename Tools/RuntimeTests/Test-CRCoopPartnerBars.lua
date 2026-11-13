-- Resolve Scripts/ relative to this file so require() works without LUA_PATH.
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
package.path = toolsDir .. "/../../Scripts/?.lua;" .. package.path
local Bars = require("CRCoopPartnerBars")
local checks = 0
local function check(v, label) assert(v, label); checks = checks + 1 end

-- Fake overlay API: records live elements, visibility, size and position so leaks are visible.
local live, shownEl, size, pos, mat = {}, {}, {}, {}, {}
local overlayHidden = false
local exu = { OVERLAY_METRICS = { PIXELS = 1 }, GetGameResolution = function() return 1000, 1000 end }
function exu.CreateOverlay(n) live[n] = true; return true end
function exu.CreateOverlayElement(_, n) assert(not live[n], "duplicate " .. n); live[n] = true; return true end
function exu.DestroyOverlayElement(n) live[n], shownEl[n], size[n], pos[n] = nil, nil, nil, nil; return true end
function exu.DestroyOverlay(n) live[n] = nil; return true end
function exu.ShowOverlayElement(n) shownEl[n] = true; return true end
function exu.HideOverlayElement(n) shownEl[n] = false; return true end
function exu.SetOverlayDimensions(n, w, h) size[n] = { w, h }; return true end
function exu.SetOverlayPosition(n, x, y) pos[n] = { x, y }; return true end
function exu.SetOverlayMaterial(n, m) mat[n] = m; return true end
function exu.HideOverlay() overlayHidden = true; return true end
function exu.ShowOverlay() overlayHidden = false; return true end
for _, fn in ipairs({ "AddOverlay2D", "SetOverlayZOrder", "SetOverlayMetricsMode", "AddOverlayElementChild",
    "RemoveOverlayElementChild", "RemoveOverlay2D" }) do exu[fn] = function() return true end end
local function liveCount() local n = 0 for _ in pairs(live) do n = n + 1 end return n end

-- Fake projection: position() tags the vector's x with the handle so the fakes can find the object.
local objects = {}
local function position(h) return { x = h, y = 10, z = 0 } end
function exu.IsPointInView(pt) return objects[pt.x].inView end
function exu.WorldToScreen(pt) local o = objects[pt.x]; return o.sx, o.sy, o.depth end

local active, clock, target = true, 0, nil
local me = 30
local players = { [20] = { name = "Ian", team = 1, handle = 201 }, [30] = { name = "Ann", team = 2, handle = 301 },
    [40] = { name = "Bo", team = 3, handle = 401 }, [50] = { name = "Cy", team = 4, handle = 501, lateJoin = true },
    [60] = { name = "Foe", team = 9, handle = 601 } }
local statuses = { [20] = { hp = 80, ammo = 50 }, [40] = { hp = 10, ammo = 20 } }
local barsOn = true
local comms = { IsActive = function() return active end, GetStatus = function(id) return statuses[id] end,
    PartnerBarsOn = function() return barsOn end }
local coop = { GetLocalPlayerId = function() return me end, GetPlayers = function() return players end,
    IsHumanTeam = function(t) return t >= 1 and t <= 4 end }
local health, ammo = {}, {}
local bars = Bars.Create({ exu = exu, coop = coop, comms = function() return comms end, time = function() return clock end,
    valid = function(h) return objects[h] ~= nil end, position = position,
    health = function(h) return health[h] end, ammo = function(h) return ammo[h] end,
    target = function() return target end })
local function tick() clock = clock + 0.6; bars.Update(false) end
local P = "CR/PartnerBars/"
-- 1000x1000: barW = 70, barH = 6.
local function reset()
    objects = { [201] = { inView = true, sx = 500, sy = 400, depth = 50 }, [401] = { inView = true, sx = 200, sy = 300, depth = 80 } }
    health, ammo, target = {}, {}, nil
end

reset(); health[201], ammo[201] = 0.5, 0.25
tick()
check(liveCount() == 2 + 4 * 3, "overlay, root and 4 x 3 panels created once")
check(shownEl[P .. "Hull1"] and shownEl[P .. "Ammo1"] and shownEl[P .. "Track1"], "on-screen teammate shown")
check(shownEl[P .. "Hull2"], "second teammate shown (sorted ids 20, 40)")
check(not shownEl[P .. "Hull3"], "late joiner and other team get no bar")
check(size[P .. "Hull1"][1] == 35 and size[P .. "Ammo1"][1] == 18, "live health/ammo drive widths")
check(mat[P .. "Hull1"] == "CRPdaBorder_G_A20", "healthy hull is green")
check(pos[P .. "Hull1"][1] == 465 and pos[P .. "Hull1"][2] < 400, "bars centred above the point")
-- Fallback to the broadcast values when the live read is unavailable.
check(size[P .. "Hull2"][1] == 7 and size[P .. "Ammo2"][1] == 14, "fallback to broadcast hp/ammo")
check(mat[P .. "Hull2"] == "CRPdaBorder_R_A20", "low hull turns red")

-- No change under 1 px: count position calls while the point jitters by half a pixel.
local calls = 0
local origPos = exu.SetOverlayPosition
exu.SetOverlayPosition = function(...) calls = calls + 1; return origPos(...) end
objects[201].sx = 500.4; tick()
check(calls == 0, "sub-pixel move sends nothing")
objects[201].sx = 520; tick()
check(calls == 3 and pos[P .. "Hull1"][1] == 485, "moved bar repositions once")
exu.SetOverlayPosition = origPos

-- Hide cases.
objects[201].sx = nil; tick() -- WorldToScreen returns nil (no rendered frame yet)
check(shownEl[P .. "Hull1"] == false, "no projection hides")
objects[201].sx = 500; objects[201].depth = -5; tick()
check(shownEl[P .. "Hull1"] == false, "behind the camera hides")
objects[201].depth = 401; tick()
check(shownEl[P .. "Hull1"] == false, "too far hides")
objects[201].depth = 400; objects[201].sx = 1200; tick()
check(shownEl[P .. "Hull1"] == false, "outside the screen rectangle hides")
objects[201].sx = 500; tick()
check(shownEl[P .. "Hull1"] == true, "visible again")
target = 201; tick()
check(shownEl[P .. "Hull1"] == false and shownEl[P .. "Hull2"] == true, "targeted teammate hides, others stay")
target = nil; objects[201] = nil; tick()
check(shownEl[P .. "Hull1"] == false, "invalid handle hides")
reset()

-- Suppression hides the overlay and resumes.
tick()
bars.Update(true)
check(overlayHidden, "suppressed hides")
bars.Update(false)
check(not overlayHidden, "resumes")

-- Inactive co-op or nobody to list tears everything down.
active = false; tick()
check(liveCount() == 0, "inactive session destroys elements")
active = true; tick()
check(liveCount() > 0, "rebuilt when active again")
-- PDA PARTNER BARS OFF tears down; ON brings them back.
barsOn = false; tick()
check(liveCount() == 0, "toggle off destroys elements")
barsOn = true; tick()
check(liveCount() > 0, "toggle on rebuilds")
bars.Destroy()
check(liveCount() == 0 and next(shownEl) == nil, "no leaks after Destroy")
bars.Destroy()
check(liveCount() == 0, "Destroy is idempotent")

-- A stub or missing overlay API never throws and draws nothing.
local quiet = Bars.Create({ exu = { isStub = true }, coop = coop, comms = function() return comms end,
    time = function() return clock end, valid = function() return true end, position = position,
    health = function() end, ammo = function() end, target = function() end })
clock = clock + 1; quiet.Update(false); quiet.Destroy()
check(not quiet.IsShown(), "stub exu shows nothing")
print("CRCoopPartnerBars: " .. checks .. " checks passed")
