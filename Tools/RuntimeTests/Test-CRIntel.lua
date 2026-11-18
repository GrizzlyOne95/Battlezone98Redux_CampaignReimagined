-- Test-CRIntel.lua: PDA INTEL page content, layout and expanded reader.
-- Run: lua5.1 Tools/RuntimeTests/Test-CRIntel.lua
local toolsDir = (arg and arg[0] or ""):match([=[^(.*)[/\][^/\]*$]=]) or "."
local root = toolsDir .. "/../.."
package.path = root .. "/Scripts/?.lua;" .. package.path
local Intel = require("CRIntel")
local Data = require("PersistentConfigData")
local Pda = require("CRCoopPda")

local checks = 0
local function check(v, label) assert(v, label); checks = checks + 1 end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end
local descriptions = root .. "/Missions/Descriptions/"

-- Mission stem -------------------------------------------------------------
check(Intel.MissionStem("misn2bcr.bzn") == "misn2bcr", "plain stem")
check(Intel.MissionStem("Missions\\MISN2BCR.BZN\0junk") == "misn2bcr", "path, case and NUL stripped")
check(Intel.MissionStem(nil) == "", "nil stem")

-- PNG header ---------------------------------------------------------------
local png = readFile(descriptions .. "misn2bcr_2.png")
check(png ~= nil, "misn2bcr_2.png readable")
local w, h = Intel.PngSize(png)
check(w == 512 and h == 512, "misn2bcr_2.png is 512x512")
check(Intel.PngSize("not a png at all, just text....") == nil, "non-PNG rejected")
check(Intel.PngSize(nil) == nil, "nil rejected")

-- Text normalisation -------------------------------------------------------
check(Intel.NormalizeText("A\r\nB  \r\n\r\n") == "A\nB", "CRLF and trailing blanks removed")

-- Image fitting keeps aspect ratio and centres -----------------------------
local fit = Intel.FitImage(700, 515, 400, 600)
check(fit.width == 400 and math.abs(fit.height - 294) <= 1, "wide image fits width")
check(fit.x == 0 and fit.y == math.floor((600 - fit.height) / 2), "wide image centred vertically")
fit = Intel.FitImage(512, 512, 800, 300)
check(fit.width == 300 and fit.height == 300 and fit.x == 250, "square image fits height, centred")
check(Intel.FitImage(0, 10, 100, 100) == nil, "bad size rejected")

-- Layout ---------------------------------------------------------------------
local function inside(L, x, y, wd, ht)
    return x >= 0 and y >= 0 and x + wd <= L.panelW and y + ht <= L.panelH
end
local L = Intel.Layout({ screenW = 1920, screenH = 1080 })
check(L.panelW == 1344 and L.panelH == 810, "70% x 75% at 1080p")
check(L.panelX == 288 and L.panelY == 135, "centred at 1080p")
check(L.imageW == nil, "no image slot without an image")
check(inside(L, L.textX, L.textY, L.textW, L.textH), "text inside panel")
check(L.charHeight > 16, "reader font larger than the PDA's base")

L = Intel.Layout({ screenW = 1920, screenH = 1080, image = { width = 512, height = 512 } })
check(L.imageW == L.imageH, "square image stays square")
check(L.textX > L.imageX + L.imageW, "text to the right of the image")
check(inside(L, L.imageX, L.imageY, L.imageW, L.imageH), "image inside panel")
check(inside(L, L.textX, L.textY, L.textW, L.textH), "text inside panel beside image")

L = Intel.Layout({ screenW = 1920, screenH = 1080, image = { width = 700, height = 515 } })
check(math.abs(L.imageW / L.imageH - 700 / 515) < 0.01, "briefing-size image keeps aspect")

L = Intel.Layout({ screenW = 3440, screenH = 1440 })
check(L.panelW <= math.floor(1440 * 1.55), "ultrawide width capped")
check(L.panelX == math.floor((3440 - L.panelW) / 2), "ultrawide centred")

L = Intel.Layout({ screenW = 800, screenH = 600, image = { width = 512, height = 512 } })
check(L.textY > L.imageY + L.imageH, "narrow screen stacks image above text")
check(inside(L, L.imageX, L.imageY, L.imageW, L.imageH), "stacked image inside panel")

L = Intel.Layout({ screenW = 3840, screenH = 2160, fontScale = 1.3 })
check(L.charHeight <= 40 and L.visibleLines >= 10, "4K large font still shows a page of text")

-- Fake game: files, keys, EXU overlay log -----------------------------------
local files = {}
local function useItem(name) return files[string.lower(name)] end
local mission = "misn2bcr.bzn"
local keys = {}
local calls = {}
local function rec(name) return function(...) calls[#calls + 1] = { name, ... }; return true end end
local exu = setmetatable({
    HasOverlayElement = function() return true end,
    MaterialExists = function() return false end,
    GetGameKey = function(k) return keys[k] == true end,
}, { __index = function(t, name) local f = rec(name); rawset(t, name, f); return f end })
local function called(name, a, b, c, d, e)
    for _, call in ipairs(calls) do
        if call[1] == name and (a == nil or call[2] == a) and (b == nil or call[3] == b)
            and (c == nil or call[4] == c) and (d == nil or call[5] == d) and (e == nil or call[6] == e) then
            return call
        end
    end
end
local function lastCall(name, a)
    for i = #calls, 1, -1 do
        if calls[i][1] == name and (a == nil or calls[i][2] == a) then return calls[i] end
    end
end

-- The real misn2bcr briefing: page 1 text, page 2 text and image.
files["misn2bcr.des"] = readFile(descriptions .. "misn2bcr.des")
files["misn2bcr_2.des"] = readFile(descriptions .. "misn2bcr_2.des")
files["misn2bcr_2.png"] = png
files["misn2bcr_4.des"] = "ignored: page 3 is missing"
check(files["misn2bcr.des"] and files["misn2bcr_2.des"], "misn2bcr briefing pages readable")

local ui = Intel.Create({ exu = exu, useItem = useItem, missionFile = function() return mission end,
    screen = function() return 1920, 1080 end,
    theme = function() return { fontScale = 1.0, header = "HDR", border = "BRD", metrics = "PIXELS" } end })

check(ui.HasIntel(), "misn2bcr has intel")
check(ui.Count() == 2, "pages stop at the first gap")
check(ui.pages[1].image == nil, "page 1 has no image")
check(ui.pages[2].image and ui.pages[2].image.width == 512, "page 2 image found with its size")
check(not ui.pages[1].text:find("\r"), "CR stripped from page text")

local function header(page) return "**BATTLEZONE PDA  1/6**\nINTEL\n" end
local function footer(lines, a, b, c) lines[#lines + 1] = ""; lines[#lines + 1] = a; lines[#lines + 1] = b
    lines[#lines + 1] = c end
local text = ui.BuildPdaText(header, footer, Data.PdaPages.INTEL)
check(text:find("BRIEFING PAGE 1/2", 1, true), "preview shows page counter")
check(text:find("NSDF UPDATE", 1, true), "preview shows page 1 text")
check(text:find("Enter Expand", 1, true), "preview hints Enter")

-- Left/Right turn pages in the preview without expanding.
check(ui.HandlePdaInput({ right = true }) == true and ui.Page() == 2, "right turns to page 2")
check(not ui.IsExpanded(), "turning pages does not expand")
text = ui.BuildPdaText(header, footer, Data.PdaPages.INTEL)
check(text:find("BRIEFING PAGE 2/2  [IMAGE]", 1, true), "preview flags the image page")
check(ui.HandlePdaInput({ right = true }) == false and ui.Page() == 2, "no wrap past the last page")

-- Enter expands; Tab held at that moment does not count as a press.
keys.TAB = true
check(ui.HandlePdaInput({ enter = true }) and ui.IsExpanded(), "enter expands")
check(called("CreateOverlay", "cr_intel_overlay"), "reader overlay created")
check(called("SetOverlayZOrder", "cr_intel_overlay", 648), "reader above the PDA")
check(called("ShowOverlay", "cr_intel_overlay"), "reader shown")
check(called("CloneMaterial", "CRIntelImage", "CRIntel_misn2bcr_2"), "image material cloned per page")
check(called("SetMaterialTexture", "CRIntel_misn2bcr_2", "misn2bcr_2.png", 0, 0, 0), "D3D11 technique textured")
check(called("SetMaterialTexture", "CRIntel_misn2bcr_2", "misn2bcr_2.png", 1, 0, 0), "DX9 technique textured")
check(called("SetOverlayMaterial", "cr_intel_image", "CRIntel_misn2bcr_2"), "image panel uses the clone")
local dims = lastCall("SetOverlayDimensions", "cr_intel_image")
check(dims and dims[3] == dims[4] and dims[3] > 200, "image drawn square and large")
local title = lastCall("SetOverlayCaption", "cr_intel_title")
check(title and title[3]:find("PAGE 2/2", 1, true), "reader title shows page")
local body = lastCall("SetOverlayCaption", "cr_intel_text")
check(body and body[3]:find("bio-metal", 1, true), "reader shows page 2 text")

ui.Sync(true, false)
check(ui.IsExpanded(), "held Tab ignored")
keys.TAB = false
ui.Sync(true, false)
check(ui.IsExpanded(), "Tab release keeps reader open")

-- Steady frames do not re-push the overlay.
local before = #calls
ui.Sync(true, false)
ui.Sync(true, false)
check(#calls == before, "unchanged frames skip overlay updates")

-- Tab closes.
keys.TAB = true
ui.Sync(true, false)
check(not ui.IsExpanded(), "Tab closes the reader")
check(lastCall("HideOverlay", "cr_intel_overlay"), "reader hidden on Tab")
keys.TAB = false

-- Anything that takes the PDA off INTEL closes it.
ui.HandlePdaInput({ enter = true })
check(ui.IsExpanded(), "re-expanded")
ui.Sync(false, false)
check(not ui.IsExpanded(), "leaving INTEL closes the reader")

-- Typing in chat leaves it open and ignores Tab.
ui.HandlePdaInput({ enter = true })
keys.TAB = true
ui.Sync(true, true)
check(ui.IsExpanded(), "Tab typed in chat ignored")
keys.TAB = false
ui.HandlePdaInput({ enter = true })
check(not ui.IsExpanded(), "Enter closes the reader")

-- Scrolling a long page: Up/Down by line, PgDn by a screen, clamped.
files["misn2bcr.des"] = string.rep("Line of briefing text that goes on.\n", 120)
ui.Reset()
check(ui.Count() == 2, "reloaded after reset")
ui.HandlePdaInput({ enter = true })
check(ui.maxScroll and ui.maxScroll > 0, "long page scrolls")
ui.HandlePdaInput({ down = true })
check(ui.scroll == 1, "down scrolls one line")
ui.HandlePdaInput({ up = true })
ui.HandlePdaInput({ up = true })
check(ui.scroll == 0, "scroll clamps at top")
keys.PAGEDOWN = true
ui.Sync(true, false)
check(ui.scroll == ui.visibleLines - 1, "PgDn jumps a screen")
keys.PAGEDOWN = false
for _ = 1, 40 do keys.PAGEDOWN = not keys.PAGEDOWN; ui.Sync(true, false) end
check(ui.scroll == ui.maxScroll, "scroll clamps at bottom")
local foot = lastCall("SetOverlayCaption", "cr_intel_footer")
check(foot and foot[3]:find("Lines", 1, true), "footer shows line position")
ui.HandlePdaInput({ right = true })
check(ui.Page() == 2 and ui.scroll == 0, "turning page resets scroll")
keys.PAGEDOWN = false

-- Destroy (PDA rebuild, mission end) closes and frees the reader.
ui.Destroy()
check(not ui.IsExpanded() and called("DestroyOverlay", "cr_intel_overlay"), "destroy frees the overlay")

-- Image material failure falls back to text only.
calls = {}
local noClone = setmetatable({ HasOverlayElement = function() return true end,
    CloneMaterial = function() return false end, GetGameKey = function() return false end },
    { __index = exu })
local ui2 = Intel.Create({ exu = noClone, useItem = useItem, missionFile = function() return mission end,
    screen = function() return 1920, 1080 end, theme = function() return {} end })
ui2.HandlePdaInput({ right = true })
ui2.HandlePdaInput({ enter = true })
check(ui2.IsExpanded() and called("HideOverlayElement", "cr_intel_image"), "no material: image hidden, text shown")

-- Mission without briefing files: no intel, no page.
mission = "nothing.bzn"
check(not ui.HasIntel(), "mission change reloads; no files means no intel")
check(ui.HandlePdaInput({ enter = true }) == false and not ui.IsExpanded(), "nothing to expand")

-- No EXU at all: content still loads, reader just does not open.
local bare = Intel.Create({ useItem = useItem, missionFile = function() return "misn2bcr.bzn" end })
check(bare.HasIntel(), "content loads without EXU")
check(bare.Expand() == false and not bare.IsExpanded(), "reader needs EXU overlays")

-- PDA page order: INTEL listed only when the mission has intel ---------------
local hasIntel = true
local active = false
local coop = { GetComms = function() return { IsActive = function() return active end } end }
local pda = Pda.Create({ coop = coop, pages = Data.PdaPages, intel = function() return hasIntel end })
local order = pda.PageOrder()
check(order[1] == Data.PdaPages.INTEL and #order == 6, "single player: INTEL first, then the five pages")
active = true
order = pda.PageOrder()
check(order[3] == Data.PdaPages.INTEL and #order == 8, "co-op: INTEL after the co-op pages")
check(pda.CyclePage(Data.PdaPages.INTEL, 1) == Data.PdaPages.CRAFT, "] from INTEL goes to CRAFT")
hasIntel = false
active = false
order = pda.PageOrder()
check(#order == 5, "no intel: INTEL not listed")
local state = { pdaPage = Data.PdaPages.INTEL }
pda.UpdatePage(state)
check(state.pdaPage == Data.PdaPages.CRAFT, "INTEL page left when intel disappears")
check(Data.PdaPages.COUNT == Data.PdaPages.INTEL, "COUNT covers INTEL")

print(string.format("CRIntel: %d checks passed", checks))
