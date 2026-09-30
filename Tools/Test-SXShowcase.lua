-- Run with Lua 5.1+: lua Tools/Test-SXShowcase.lua Scripts
-- Pure host fakes exercise lifecycle/rollback; no native visual claim is made.
local scriptRoot = arg[1] or "Scripts"
package.path = scriptRoot .. "/?.lua;" .. package.path
local unpackValues = unpack or table.unpack
local Director = require("SXDirector")
local Materials = require("SXMaterials")
local Overlay = require("SXOverlay")
local total = 0
local function Check(value, message)
    assert(value, message)
    total = total + 1
end
local function Copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = Copy(v) end
    return r
end

-- Cues cross thresholds once, including a hitch across both scenes.
local events, finishes, ticks = {}, {}, 0
local d = Director.New({
    { id = "a", duration = 3, cues = { { at = 0, id = "zero" }, { at = 2, id = "two" } } },
    { id = "b", duration = 4, cues = { { at = 1, id = "b-one" } } },
}, { cue = function(_, c) events[#events + 1] = c.id end,
    tick = function() ticks = ticks + 1 end,
    finish = function(reason) finishes[#finishes + 1] = reason end })
Check(d:Start(), "director start")
d:Update(0); d:Update(-1); d:Update(0/0); d:Update(math.huge)
Check(#events == 0, "invalid/paused steps do not fire cues")
d:Update(7)
Check(table.concat(events, ",") == "zero,two,b-one", "hitch processes all crossed cues once")
Check(d.mode == "freeplay" and finishes[1] == "complete", "bounded handover")
d:Update(7)
Check(#events == 3 and ticks == 2, "completed director stays inactive")
Check(d:Start("b"), "selected scene replay")
Check(not d:Start("missing") and d.mode == "tour", "invalid request preserves active tour")
d:Finish("cancelled"); d:Update(99)
Check(#events == 3 and #finishes == 2, "cancel does not execute remaining cues")
local broken = Director.New({ { id = "bad", duration = 2, cues = { { at = 1 } } } },
    { cue = function() error("fixture failure") end })
broken:Start(); broken:Update(1)
Check(broken.mode == "freeplay" and broken.error:match("fixture failure"), "callback error ends safely")

local function FakeExu(world)
    local x = { cloneCount = 0, graphReady = true, showing = false, uiOpen = false,
        width = 1280, height = 720, nodes = {}, sourceColors = { emissive = { r = 0, g = 0, b = 0 } } }
    function x.GetSubEntityCount(h) return x.graphReady and world[h] and #world[h].names or nil end
    function x.GetSubEntityMaterial(h, i) return x.graphReady and world[h] and world[h].names[i + 1] or nil end
    function x.GetMaterialPassColors() return Copy(x.sourceColors) end
    local clones = {}
    function x.MaterialExists(name) return clones[name] == true end
    function x.CloneMaterial(_, name) clones[name] = true; x.cloneCount = x.cloneCount + 1; return true end
    function x.SetMaterialPassColors(name, colors, technique)
        if x.rejectColors then return false end
        if x.legacyColors and technique == -1 then error("old API") end
        x.lastColors = Copy(colors)
        return true
    end
    function x.SetSubEntityMaterial(h, i, name)
        if x.rejectService and name:match("^SX/") and i == 1 then return false end
        world[h].names[i + 1] = name -- Deliberately returns nil, as a void setter can.
    end
    function x.CreateOverlay() x.created = true; return true end
    function x.DestroyOverlay() x.created = false end
    function x.CreateOverlayElement(_, name) x.nodes[name] = true; return true end
    function x.DestroyOverlayElement(name) x.nodes[name] = nil end
    function x.ShowOverlay() x.showing = true end
    function x.HideOverlay() x.showing = false end
    function x.SetOverlayTextFont() return not x.rejectFont end
    function x.GetGameResolution() return x.width, x.height end
    function x.IsGameUiOpen() return x.uiOpen end
    function x.IsPauseMenuOpen() return x.uiOpen end
    for _, name in ipairs({ "AddOverlay2D", "AddOverlayElementChild", "SetOverlayZOrder",
        "SetOverlayMetricsMode", "SetOverlayPosition", "SetOverlayDimensions", "SetOverlayCaption",
        "SetOverlayTextCharHeight", "SetOverlayTextColor", "ShowOverlayElement",
        "RemoveOverlay2D", "RemoveOverlayElementChild" }) do x[name] = function() end end
    return x
end

local world = { [1] = { names = { "body", "glass" } }, [2] = { names = { "body", "glass" } } }
local x = FakeExu(world)
local valid = function(h) return world[h] ~= nil end
local m = Materials.New(x, valid)
Check(m:Prepare(1, 2), "material baseline")
Check(m:Apply() and m.status == "PASS", "void assignment setters verified by readback")
Check(world[1].names[1] == "body" and world[2].names[1]:match("^SX/"), "control twin is untouched")
Check(x.sourceColors.emissive.g == 0, "shared source colors unchanged")
Check(m:Restore() and world[2].names[1] == "body", "baseline restore")
local firstCloneCount = x.cloneCount
for _ = 1, 3 do m:Prepare(1, 2); m:Apply(); m:Restore() end
Check(x.cloneCount == firstCloneCount, "replays reuse a bounded clone namespace")
x.rejectService = true
Check(not m:Apply() and world[2].names[1] == "body" and world[2].names[2] == "glass",
    "partial assignment failure rolls back")
x.rejectService, x.legacyColors = false, true
Check(m:Apply(), "legacy pass-index fallback")
x.rejectColors = true; m:Pulse(1)
Check(not m.active and m.status == "FAIL" and world[2].names[1] == "body", "pulse failure restores originals")
x.rejectColors = false
m:Apply()
local savedA, savedB = Copy(m.controlBase), Copy(m.changedBase)
local loaded = Materials.New(x, valid)
loaded.controlBase, loaded.changedBase = savedA, savedB
x.graphReady = false
Check(not loaded:Prepare(1, 2), "load can precede render graph")
x.graphReady = true
Check(loaded:Prepare(1, 2) and loaded:Restore() and world[2].names[1] == "body",
    "deferred load retains saved original materials")
world[2] = nil
Check(loaded:Restore(), "deleted fixture does not prevent restoring survivor/reset")
Check(not Materials.New({ isStub = true }, valid):Available(), "stub EXU never counts as supported")
Check(not Materials.New({}, valid):Available(), "missing material APIs blocked")

local o = Overlay.New(x)
Check(o:Create() and x.showing, "overlay created")
x.width, x.height = 1920, 1080
o:Update("title", "status", "help")
Check(o.width == 1920 and o.height == 1080, "resolution change relayout")
x.uiOpen = true; o:Update("title", "status", "help")
Check(not x.showing, "native menu suppresses custom overlay")
x.uiOpen = false; o:Update("title", "status", "help")
Check(x.showing, "overlay resumes after native menu")
o:Destroy()
Check(not x.created and next(x.nodes) == nil, "overlay cleanup")
Check(o:Create() and o.width == 1920 and o.height == 1080, "recreated overlay receives layout")
o:Destroy()
x.rejectFont = true
Check(not o:Create() and not x.created and next(x.nodes) == nil, "partial overlay failure cleaned up")

-- Full mission integration with serializable fake handles and native callbacks.
world = {}
x = FakeExu(world)
package.loaded.exu = nil
package.preload.exu = function() return x end
package.preload.RequireFix = function() return { Initialize = function() end } end
local nextHandle, cameraCalls, readyCalls, finishCalls = 0, 0, 0, 0
local cancelled, net = false, false
function IsValid(h) return world[h] ~= nil end
function IsNetGame() return net end
function BuildObject(_, _, path)
    nextHandle = nextHandle + 1
    world[nextHandle] = { names = { "body", "glass" }, path = path }
    return nextHandle
end
function SetLabel(h, label) world[h].label = label end
function GetHandle(label) for h, obj in pairs(world) do if obj.label == label then return h end end end
function GetPlayerHandle() return 99999 end
function SetIndependence() end
function SetCurAmmo() end
function Stop() end
function Goto() end
function RemoveObject(h) world[h] = nil; DeleteObject(h) end
function ClearObjectives() end
function AddObjective() end
function DisplayMessage() end
function CameraReady() readyCalls = readyCalls + 1 end
function CameraPath() cameraCalls = cameraCalls + 1 end
function CameraFinish() finishCalls = finishCalls + 1 end
function CameraCancelled() return cancelled end
local function Mission() dofile(scriptRoot .. "/sxshow.lua"); Start() end
Mission(); Update(0)
Check(nextHandle == 3 and readyCalls == 1, "first live update builds exactly three owned fixtures")
x.uiOpen = true; Update(100)
local paused = { Save() }
Check(paused[8].elapsed == 0, "pause freezes scene clock even with nonzero timestep")
x.uiOpen = false; Update(25); Update(6)
local changedHandle = GetHandle("sx_changed")
Check(world[changedHandle].names[1]:match("^SX/"), "film material cue changes real fixture")
Check(Command("unrelated", "") == false, "unrelated console commands remain unhandled")
Command("sx", "visual pass")
local saved = { Save() }
local beforeLoadReady = readyCalls
x.graphReady = false
Load(unpackValues(saved))
Check(readyCalls == beforeLoadReady, "load never restarts cinematic")
x.graphReady = true; Update(0.25)
Check(world[changedHandle].names[1] == "body", "mission deferred-load restores originals")
local afterLoad = { Save() }
Check(afterLoad[8].mode == "freeplay" and afterLoad[2].load.status == "PASS", "load reaches safe free play")
Check(afterLoad[2].visual.status == "PENDING", "saved visual observation is not reused after load")
Command("sx", "service")
x.rejectColors = true; Update(0.25); x.rejectColors = false
local failedPulse = { Save() }
Check(failedPulse[2].materials.status == "FAIL" and world[changedHandle].names[1] == "body",
    "mission report reflects pulse failure and rollback")
Command("sx", "service"); Command("sx", "visual pass"); Command("sx", "materials")
local replay = { Save() }
Check(replay[2].visual.status == "PENDING", "new replay requires a new visual observation")
Command("sx", "skip")
x.graphReady = false; Load(unpackValues(saved)); Update(5)
local expired = { Save() }
Check(expired[2].load.status == "BLOCKED", "load readiness timeout is reported honestly")
x.graphReady = true
Command("sx", "baseline")
Command("sx", "tour"); Update(1)
cancelled = true; Update(1); cancelled = false
local skip = { Save() }
Check(skip[8].mode == "freeplay" and world[changedHandle].names[1] == "body", "native cancel restores assignments")
RemoveObject(changedHandle)
Command("sx", "reset"); Update(0)
local count = 0; for _ in pairs(world) do count = count + 1 end
Check(count == 3, "deleted fixture can be reset without duplicating survivors")
local clones = x.cloneCount
for _ = 1, 3 do Command("sx", "reset"); Update(0) end
count = 0; for _ in pairs(world) do count = count + 1 end
Check(count == 3 and x.cloneCount == clones, "repeated reset has bounded objects/materials")
net = true
local beforeNet = nextHandle
Mission(); Update(10); Command("sx", "service")
Check(nextHandle == beforeNet, "network mode does not spawn/tune presentation fixtures")
Check(finishCalls > 0 and cameraCalls > 0, "native camera callbacks actually exercised")
net = false
package.loaded.exu = { isStub = true }
Mission(); Update(1); Update(65)
local unsupported = { Save() }
Check(unsupported[2].materials.status == "BLOCKED" and unsupported[8].mode == "freeplay",
    "stub EXU degrades to the stock camera tour without claiming material support")
print(string.format("SXShowcase: %d checks passed (%s host; native runtime unverified)", total, _VERSION))
