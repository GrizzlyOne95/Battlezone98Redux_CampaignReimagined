-- Test-CRWetGlassWeather.lua
--
-- Drives the real Scripts/CRWetGlass.lua against a recording exu stub and checks the two weather
-- layers that are not plain rain: snow flakes (CRWX_WinSnow, Europa), dust grit (CRWX_WinGrit, Mars) and
-- Venus acid rain (yellow-green CRWX_Acid* drops plus the CRWX_WinEtch haze), on both the screen overlay (F2/F3) and the cockpit glass submesh (F1). Also checks that every
-- overlay material and texture the module can ask for ships.
--
-- Usage, from the repository root:
--
--     lua5.1 Tools/Test-CRWetGlassWeather.lua Scripts
--
-- Prints CRWETGLASS WEATHER OK; prints each failed expectation and exits 1 otherwise.

local scriptDir = ... or "Scripts"
local failures, checks = {}, 0
local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

-- =============================================================================
-- Recording exu
-- =============================================================================

local ov = { panels = {}, shown = {}, overlayShown = false, setLog = {} }   -- name -> { material, uv, visible }
local shell = { enabled = false, material = "CRWX_CockpitGlass", group = nil, textures = {}, windows = {}, colours = {} }
local X = {}
local function sub(name) return X[name] end
X.CreateOverlay = function() return true end
X.DestroyOverlay = function() ov.panels = {}; return true end
X.ShowOverlay = function() ov.overlayShown = true; return true end
X.HideOverlay = function() ov.overlayShown = false; return true end
X.SetOverlayZOrder = function() return true end
X.CreateOverlayElement = function(_, name) ov.panels[name] = { visible = false }; return true end
X.DestroyOverlayElement = function(name) ov.panels[name] = nil; return true end
X.AddOverlay2D = function() return true end
X.ShowOverlayElement = function(name) ov.panels[name].visible = true; return true end
X.HideOverlayElement = function(name) ov.panels[name].visible = false; return true end
X.SetOverlayMetricsMode = function() return true end
X.SetOverlayPosition = function() return true end
X.SetOverlayDimensions = function() return true end
X.SetOverlayMaterial = function(name, m) ov.panels[name].material = m; ov.setLog[#ov.setLog + 1] = m; return true end
X.SetOverlayParameter = function(name, k, v) if k == "uv_coords" then ov.panels[name].uv = v end; return true end
X.GetCameraAspectRatio = function() return 16 / 9 end
X.GetCameraView = function() return 1 end
X.GetSatState = function() return 0 end
X.IsPauseMenuOpen = function() return false end
X.SetMaterialTexture = function(mat, tex, tech, pass, unit) shell.textures[mat .. "#" .. pass] = tex; return true end
X.SetMaterialTextureWindow = function(mat, u0, v0, du, dv, _, pass) shell.windows[mat .. "#" .. pass] = { u0, v0, du, dv }; return true end
X.SetMaterialPassColors = function(mat, c, _, pass) shell.colours[mat .. "#" .. pass] = c.diffuse; return true end
X.SetSubEntityRenderQueueGroup = function(target, mat, group)
    if not shell.enabled then return 0 end
    shell.group = group
    return 1, 0
end
X.SetSubEntityMaterial = function(_, _, mat) shell.material = mat; return true end
X.animation = {
    TargetCockpit = function() return shell.enabled and "cockpit" or nil end,
    GetCapabilities = function() return { glass = true } end,
}
package.loaded["exu"] = X

-- =============================================================================
-- BZ runtime stub
-- =============================================================================

local now = 0
function GetTime() return now end
function GetPlayerHandle() return 1 end
function IsValid() return true end
function IsCraft() return true end
function GetOdf() return "avtank" end
function GetVelocity() return { x = 0, y = 0, z = 0 } end
function GetFront() return { x = 0, y = 0, z = 1 } end

package.path = scriptDir .. "/?.lua;" .. scriptDir .. "\\?.lua;" .. package.path
local glass = dofile(scriptDir .. "/CRWetGlass.lua")

local dt = 1 / 30
local function run(seconds, level)
    for _ = 1, math.floor(seconds / dt) do
        now = now + dt
        glass.Update(level or 0)
    end
end

local function visible(family)
    local list = {}
    for name, p in pairs(ov.panels) do
        if p.visible and p.material and string.find(p.material, "^" .. family .. "_A") then
            list[#list + 1] = { name = name, step = tonumber(string.match(p.material, "_A(%d+)$")), uv = p.uv }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function anyVisibleOther()
    for _, p in pairs(ov.panels) do
        if p.visible and p.material and not (string.find(p.material, "^CRWX_WinSnow_A") or string.find(p.material, "^CRWX_WinGrit_A")) then
            return p.material
        end
    end
    return nil
end

-- =============================================================================
-- Overlay mode: snow
-- =============================================================================

check(not glass.Busy(), "idle glass is not busy")
glass.Weather("snow", 0.3)
check(glass.Busy(), "a snow level makes the glass busy so the caller keeps updating")
run(0.5)
check(#visible("CRWX_WinSnow") == 0, "flakes do not appear at once")
check(glass.Mode() == "overlay", "no cockpit glass without the submesh: overlay mode")
run(14)
local snow = visible("CRWX_WinSnow")
check(#snow == 1, "a light snowfall puts one flake layer on the glass, got " .. #snow)
check(snow[1] and snow[1].step <= 10, "light snow is at most about 60% opacity of a sparse sheet, step " .. tostring(snow[1] and snow[1].step))
check(anyVisibleOther() == nil, "snow brings no rivulets, streaks, beads or cracks, saw " .. tostring(anyVisibleOther()))
-- Peak opacity over a long run never exceeds the cap; layers fade rather than snap.
local maxStep, maxJump, lastStep = 0, 0, 0
for _, p in ipairs(visible("CRWX_WinSnow")) do lastStep = lastStep + p.step end
for _ = 1, math.floor(240 / dt) do
    now = now + dt; glass.Update(0)
    local list = visible("CRWX_WinSnow")
    local total = 0
    for _, p in ipairs(list) do maxStep = math.max(maxStep, p.step); total = total + p.step end
    maxJump = math.max(maxJump, math.abs(total - lastStep)); lastStep = total
end
check(maxStep <= math.floor(0.60 * 16 + 0.5), "a light snow layer never exceeds its peak opacity, step " .. maxStep)
check(maxJump <= 1, "snow fades by single steps, never snaps (jump " .. maxJump .. ")")
glass.Weather("snow", 0.9)
run(60)
check(#visible("CRWX_WinSnow") <= 2, "never more than the two snow layers")
local sawTwo = false
for _ = 1, math.floor(120 / dt) do
    now = now + dt; glass.Update(0)
    if #visible("CRWX_WinSnow") == 2 then sawTwo = true end
end
check(sawTwo, "a heavier level lets the second flake layer join")
-- Level 0: the layers melt away slowly and the glass reports idle.
glass.Weather("snow", 0)
run(1)
check(#visible("CRWX_WinSnow") >= 1, "snow does not vanish the moment the level drops")
run(60)
check(#visible("CRWX_WinSnow") == 0, "snow has melted a minute after the level drops")
check(not glass.Busy(), "melted glass is idle again")
check(not ov.overlayShown, "the overlay hides when nothing is on it")

-- =============================================================================
-- Overlay mode: grit
-- =============================================================================

glass.Weather("grit", 0.1)
run(2)
local grit = visible("CRWX_WinGrit")
check(#grit == 1 and grit[1].step <= 2, "faint grit is one barely-there layer, step " .. tostring(grit[1] and grit[1].step))
glass.Weather("grit", 1.0)
run(2)
grit = visible("CRWX_WinGrit")
check(#grit == 2, "full grit shows both layers, got " .. #grit)
check(grit[1].step <= 8 and grit[2].step <= 8, "grit stays subtle at its strongest, steps " .. grit[1].step .. "/" .. grit[2].step)
check(grit[1].uv ~= grit[2].uv, "the two grit layers have different patterns")
local uv1 = grit[1].uv
run(30)
check(visible("CRWX_WinGrit")[1].uv == uv1, "grit does not move on the glass")
check(anyVisibleOther() == nil, "grit brings no rain layers")
-- A splat still works beside it (the existing damage path).
glass.Splat(0.1, 0.5, 0.4, false)
run(0.5)
check(visible("CRWX_WindDirt")[1] ~= nil, "a grit splat shows on the dirt layer")
run(12)
check(#visible("CRWX_WindDirt") == 0, "the splat clears within seconds")
glass.Weather("grit", 0)
run(1)
check(#visible("CRWX_WinGrit") == 0, "grit follows the caller's level to zero (the caller owns the slow clear)")
check(not glass.Busy(), "idle again")

-- Rain still wins the passes.
glass.Weather("snow", 0.5)
run(30, 1.0)
check(#visible("CRWX_WetBeads") >= 1, "rain still draws with snow wanted")
glass.Weather("snow", 0)
run(80, 0)

-- =============================================================================
-- Overlay mode: acid rain (drops tinted yellow-green, a slow etch haze)
-- =============================================================================

local function visibleFamilies()
    local seen = {}
    for name, p in pairs(ov.panels) do
        if p.visible and p.material then seen[name] = string.match(p.material, "^(CRWX_%a+)_A") end
    end
    return seen
end
local function countFamily(prefix)
    local n = 0
    for _, fam in pairs(visibleFamilies()) do if string.find(fam, "^" .. prefix) then n = n + 1 end end
    return n
end

check(glass.Mode() == "overlay" and not glass.Busy(), "starting acid from an idle overlay glass")
-- Plain rain first, then acid arrives: drops already on the glass keep their colour, new ones are acid.
run(8, 0.6)
check(countFamily("CRWX_WetBeads") >= 1 and countFamily("CRWX_Acid") == 0, "without acid the rain is the plain blue-grey kind")
glass.Weather("acid", 0.6)
local before = visibleFamilies()
local recoloured = false
for _ = 1, math.floor(30 / dt) do
    now = now + dt; glass.Update(0.6)
    local cur = visibleFamilies()
    for name, fam in pairs(cur) do
        if before[name] and before[name] ~= fam then recoloured = true end
    end
    before = cur
end
check(not recoloured, "a drop on the glass never changes family while it shows")
check(countFamily("CRWX_AcidBeads") >= 1 or countFamily("CRWX_AcidRivulet") >= 1, "once acid is on, new drops are the acid variants")
check(countFamily("CRWX_WetBeads") == 0 and countFamily("CRWX_WetRivulet") == 0, "no plain drops remain after a landing cycle")
check(glass.Busy(), "acid keeps the glass busy")
-- The etch builds slowly: nothing in the first seconds, faint after a minute, never past its cap.
glass.Weather("acid", 0)
run(30, 0)
run(1200, 0)
check(not glass.Busy() and #visible("CRWX_WinEtch") == 0, "the glass is clean again before the etch test")
glass.Weather("acid", 1.0)
run(5, 0.35)
check(#visible("CRWX_WinEtch") == 0, "no etch in the first seconds of acid rain")
run(55, 0.35)
local e60 = visible("CRWX_WinEtch")
check(#e60 == 1 and e60[1].step <= 2, "after a minute of heavy acid rain the etch is at most a trace, step " .. tostring(e60[1] and e60[1].step))
local maxEtch, lastEtch, etchJump = 0, 0, 0
for _ = 1, math.floor(300 / dt) do
    now = now + dt; glass.Update(0.35)
    local list = visible("CRWX_WinEtch")
    local s = list[1] and list[1].step or 0
    maxEtch = math.max(maxEtch, s); etchJump = math.max(etchJump, math.abs(s - lastEtch)); lastEtch = s
end
check(maxEtch >= 3 and maxEtch <= math.floor(0.30 * 16 + 0.5), "long exposure etch is subtle (cap about 30%), step " .. maxEtch)
check(etchJump <= 1, "the etch changes by single steps, never snaps")
check(visible("CRWX_WinEtch")[1].uv ~= nil, "the etch has a window on the glass")
local etchUv = visible("CRWX_WinEtch")[1].uv
run(30, 0.35)
check(visible("CRWX_WinEtch")[1].uv == etchUv, "the etch does not move on the glass")
check(countFamily("CRWX_AcidStreak") == 0, "no streaks on a still craft")
-- The rain stops: the etch stays, then clears slowly. The glass stays busy meanwhile.
glass.Weather("acid", 0)
run(60, 0)
check(#visible("CRWX_WinEtch") == 1 and glass.Busy(), "a minute after the rain stops the etch is still there")
run(300, 0)
check(#visible("CRWX_WinEtch") == 1, "five minutes after the rain stops the etch is still faintly there")
run(600, 0)
check(#visible("CRWX_WinEtch") == 0, "the etch has cleared some minutes later")
check(not glass.Busy() and not ov.overlayShown, "a cleared glass is idle and the overlay hides")
-- A short shower leaves almost no etch.
glass.Weather("acid", 0.3)
run(40, 0.3)
glass.Weather("acid", 0)
run(30, 0)
check(#visible("CRWX_WinEtch") == 0 or visible("CRWX_WinEtch")[1].step <= 1, "a short light shower leaves no visible etch")
run(900, 0)
check(not glass.Busy(), "idle again")
-- No acid: the plain rain comes back and no etch ever shows.
run(30, 0.6)
check(countFamily("CRWX_WetBeads") >= 1 and countFamily("CRWX_Acid") == 0 and #visible("CRWX_WinEtch") == 0,
    "with the acid level at 0 the rain is plain again")
run(40, 0)

-- =============================================================================
-- Cockpit glass (F1)
-- =============================================================================

shell.enabled = true
glass.Weather("snow", 0.5)
glass.Weather("grit", 1.0)
run(20)
check(glass.Mode() == "shell", "with the glass submesh the layers move onto the glass")
check(shell.group == 90, "the glass sub-entity sits in its own render queue group")
check(string.match(shell.material, "^CRWX_CockpitGlass_W%d+C0$") ~= nil, "wrap layers only: material " .. shell.material)
local snowPass, gritPass
for key, tex in pairs(shell.textures) do
    if tex == "crwx_winsnow.png" then snowPass = key end
    if tex == "crwx_wingrit.png" then gritPass = key end
end
check(snowPass ~= nil and gritPass ~= nil, "the glass passes point at the snow and grit textures")
local c = snowPass and shell.colours[snowPass]
check(c and c.r > 0.8 and c.a > 0 and c.a <= 0.62, "snow pass is pale and light, colour " .. (c and string.format("%.2f a=%.2f", c.r, c.a) or "nil"))
local gc = gritPass and shell.colours[gritPass]
check(gc and gc.r < 0.6 and gc.a > 0, "grit pass uses the standard glass tint")
glass.Weather("snow", 0); glass.Weather("grit", 0)
run(60)
check(shell.material == "CRWX_CockpitGlass", "with nothing on it the glass is back on the no-op material, got " .. shell.material)
-- Acid rain on the glass: the passes point at the acid textures and the etch texture.
glass.Weather("acid", 1.0)
run(20, 1.0)
local acidTex, etchPass, plainTex = {}, nil, false
for key, tex in pairs(shell.textures) do
    if string.find(tex, "^crwx_acid") then acidTex[tex] = true end
    if tex == "crwx_winetch.png" then etchPass = key end
end
local wrapCount = tonumber(string.match(shell.material, "_W(%d+)C"))
check(next(acidTex) ~= nil, "cockpit-glass passes use the acid drop textures while acid rain falls")
check(wrapCount ~= nil and wrapCount <= 7, "the pass budget is respected, material " .. shell.material)
run(240, 1.0)
for key, tex in pairs(shell.textures) do if tex == "crwx_winetch.png" then etchPass = key end end
check(etchPass ~= nil, "the etch texture reaches a glass pass after some exposure")
glass.Weather("acid", 0)
-- Back to plain rain on the glass after the acid is gone: each pass is re-pointed.
run(900, 0)
shell.textures = {}
glass.Weather("acid", 0)
run(30, 0.8)
local sawPlain, sawAcid = false, false
for _, tex in pairs(shell.textures) do
    if tex == "crwx_wetbeads.png" or tex == "crwx_wetrivulet.png" then sawPlain = true end
    if string.find(tex, "^crwx_acid") then sawAcid = true end
end
check(sawPlain and not sawAcid, "with acid at 0 the glass passes use the plain rain textures again")
run(60, 0)
glass.Weather("grit", 0.8)
run(3)
glass.Stop()
check(shell.material == "CRWX_CockpitGlass", "Stop puts the glass back on the no-op material")
check(not glass.Busy(), "Stop forgets the weather levels")

-- =============================================================================
-- Texture warm-up on the screen overlay
-- =============================================================================

-- A texture loads the first time a panel draws it, and a first draw of crwx_winetch.png beside five other
-- panels broke the DX11 renderer in the live check. So each acid family is shown once, alone, at its faintest
-- step, right after the glass is built.
shell.enabled = false
ov.setLog = {}
local maxShown, shownFrames = 0, 0
for _ = 1, math.floor(2 / dt) do
    now = now + dt; glass.Update(0)
    local n = 0
    for _, p in pairs(ov.panels) do if p.visible then n = n + 1 end end
    maxShown = math.max(maxShown, n)
    if n > 0 then shownFrames = shownFrames + 1 end
end
local warmed = {}
for _, m in ipairs(ov.setLog) do warmed[m] = (warmed[m] or 0) + 1 end
for _, m in ipairs({ "CRWX_WinEtch_A1", "CRWX_AcidStreak_A1", "CRWX_AcidBeads_A1", "CRWX_AcidRivulet_A1" }) do
    check(warmed[m] == 1, m .. " is shown once to load its texture, got " .. tostring(warmed[m]))
end
check(maxShown <= 1, "warm-up shows one panel at a time, saw " .. maxShown)
check(shownFrames <= 10, "warm-up takes a few frames, not " .. shownFrames)
check(not ov.overlayShown and not glass.Busy(), "after the warm-up the glass is empty again")
ov.setLog = {}
run(2, 0)
check(#ov.setLog == 0, "the warm-up happens once")
glass.Stop()

-- =============================================================================
-- What ships
-- =============================================================================

local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local root = scriptDir .. "/.."
local materials = {}
for _, file in ipairs({ "crwx_wetglass.material", "crwx_glassweather.material" }) do
    local text = slurp(root .. "/Materials/" .. file)
    check(text ~= nil, file .. " exists")
    materials[#materials + 1] = text or ""
end
local allMaterials = table.concat(materials, "\n")
local source = slurp(scriptDir .. "/CRWetGlass.lua")
local families = string.match(source, "local FAMILIES = (%b{})")
local n = 0
for family in string.gmatch(families, '"(CRWX_[%w]+)"') do
    n = n + 1
    for step = 1, 16 do
        check(string.find(allMaterials, "material " .. family .. "_A" .. step .. "\r?\n", 1) ~= nil,
            family .. "_A" .. step .. " is defined")
    end
end
check(n == 11, "eleven overlay families, found " .. n)
for tex in string.gmatch(string.match(source, "local LAYER_TEXTURE = (%b{})"), '"(crwx_[%w_]+%.png)"') do
    check(slurp(root .. "/Assets/Textures/" .. tex) ~= nil, tex .. " ships")
end

if #failures > 0 then
    for _, m in ipairs(failures) do print("FAIL: " .. m) end
    print(string.format("%d of %d expectation(s) failed", #failures, checks))
    os.exit(1)
end
print(string.format("CRWETGLASS WEATHER OK (%d checks)", checks))
