-- Regression for two authored dialogue calls in one frame after warm-up.
package.path = "Scripts/?.lua;" .. package.path
local now, created, destroyed, notices, stopped = 0, 0, 0, 0, 0
local shown, caption, failures = false, "", {}
local exu = { OVERLAY_METRICS = { PIXELS = 0 } }
local function success() return true end
for _, name in ipairs({ "CreateOverlayElement", "DestroyOverlayElement", "AddOverlay2D",
    "RemoveOverlay2D", "AddOverlayElementChild", "RemoveOverlayElementChild", "SetOverlayZOrder",
    "SetOverlayMetricsMode", "SetOverlayPosition", "SetOverlayDimensions", "SetOverlayColor",
    "SetOverlayMaterial", "SetOverlayTextCharHeight", "SetOverlayTextFont", "ShowOverlayElement",
    "HideOverlayElement", "SetOverlayParameter", "SetOverlayBorderSize", "SetOverlayBorderMaterial" }) do
    exu[name] = success
end
function exu.CreateOverlay() created = created + 1; return true end
function exu.DestroyOverlay() destroyed = destroyed + 1; return true end
function exu.ShowOverlay() shown = true; return true end
function exu.HideOverlay() shown = false; return true end
function exu.SetOverlayCaption(_, text) caption = text; return true end
package.loaded.exu = exu
package.loaded.bzfile = { Open = function() return {
    Writeln = function(_, line) failures[#failures + 1] = line end,
    Flush = success, Close = success,
} end }
package.loaded.LogPaths = { Path = function(name) return name end }
function GetTime() return now end
function UseItem(name)
    if name == "durations.csv" then return "first.wav,4\nsecond.wav,5" end
    if name:match("%.txt$") then return name end
end
function AudioMessage(name) return name end
function StopAudioMessage() stopped = stopped + 1 end
function IsAudioMessageDone() return false end
function AddObjective() notices = notices + 1 end
function RemoveObjective() end
local subtitles = require("ScriptSubtitles")
subtitles.Initialize()
now = 10 -- the initial renderer warm-up window has expired
subtitles.Play("first.wav")
assert(shown and caption == "first.txt", "first dialogue is visible")
assert(created == 1 and destroyed == 0, "first dialogue creates one renderer")
subtitles.Play("second.wav")
assert(shown and caption == "second.txt", "same-frame replacement remains visible")
assert(created == 1 and destroyed == 0, "replacement reuses the renderer")
assert(stopped == 1, "replacement stops previous audio")
assert(notices == 0 and #failures == 0, "replacement does not report a false overlay failure")
subtitles.Stop()
assert(stopped == 2 and destroyed == 1 and not shown, "explicit Stop destroys the renderer and audio")
subtitles.Stop()
assert(destroyed == 1 and stopped == 2, "repeated cleanup is harmless")
now = 12
subtitles.Play("first.wav")
assert(created == 2 and shown and caption == "first.txt", "playback can restart after cleanup")
print("PASS: subtitle replacement and mission-end cleanup (9 checks)")
