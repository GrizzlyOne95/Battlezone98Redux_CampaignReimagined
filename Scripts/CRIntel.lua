-- CRIntel.lua
---@diagnostic disable: lowercase-global, undefined-global
--
-- Mission intel for the PDA INTEL page, in single player and co-op.
--
-- Content is the mission's own briefing, read from the game filesystem with
-- the stock UseItem(filename) call, so the briefing screen and the PDA share
-- one source:
--   <stem>.des            page 1 (the stock briefing text)
--   <stem>_2.des .. _9    later pages (OpenShim's multi-page briefing names)
--   <stem>_N.png          optional image for page N (N >= 2)
-- Pages stop at the first missing <stem>_N.des, as on the briefing screen.
--
-- The PDA shows a short preview. Enter opens an expanded reader in the
-- centre of the screen; Enter or Tab closes it, and so does anything that
-- takes the PDA off the INTEL page (page switch, X, the Escape menu, a
-- cinematic, mission end). Client-local UI: nothing here is networked.

local M = { MAX_PAGES = 9, IMAGE_BASE_MATERIAL = "CRIntelImage", BACKDROP_MATERIAL = "CRIntelBackdrop" }

local PNG_SIGNATURE = "\137PNG\r\n\26\n"

local function clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

--- "Missions\\MISN2BCR.bzn\0junk" -> "misn2bcr". Empty string when unknown.
function M.MissionStem(filename)
    if type(filename) ~= "string" then return "" end
    local name = filename:gsub("%z.*", "")
    name = name:match("([^/\\]*)$") or name
    name = name:match("^([^%.]*)") or name
    return string.lower(name)
end

--- Width and height from a PNG's IHDR chunk, or nil.
function M.PngSize(bytes)
    if type(bytes) ~= "string" or #bytes < 24 or bytes:sub(1, 8) ~= PNG_SIGNATURE or bytes:sub(13, 16) ~= "IHDR" then
        return nil
    end
    local function u32(i)
        local a, b, c, d = bytes:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    local width, height = u32(17), u32(21)
    if width <= 0 or height <= 0 or width > 16384 or height > 16384 then return nil end
    return width, height
end

--- Briefing text as the overlay wants it: no CR, NUL or trailing blanks.
function M.NormalizeText(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("%z", ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "    ")
    text = text:gsub("[ ]+\n", "\n"):gsub("^\n+", ""):gsub("%s+$", "")
    return text
end

--- Largest size with the image's aspect ratio that fits the box, centred.
function M.FitImage(imageW, imageH, boxW, boxH)
    imageW, imageH = tonumber(imageW) or 0, tonumber(imageH) or 0
    if imageW <= 0 or imageH <= 0 or boxW <= 0 or boxH <= 0 then return nil end
    local scale = math.min(boxW / imageW, boxH / imageH)
    local w = math.max(1, math.floor(imageW * scale + 0.5))
    local h = math.max(1, math.floor(imageH * scale + 0.5))
    return {
        x = math.floor((boxW - w) / 2),
        y = math.floor((boxH - h) / 2),
        width = w,
        height = h,
    }
end

-- Plain word wrap by character count; the PDA's pixel-based wrapper is used
-- in game (deps.wrap) so both panels break lines the same way.
function M.WrapByChars(text, maxChars)
    maxChars = math.max(math.floor(tonumber(maxChars) or 40), 8)
    local out = {}
    for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if paragraph == "" then
            out[#out + 1] = ""
        else
            local current = ""
            for word in paragraph:gmatch("%S+") do
                while #word > maxChars do
                    if current ~= "" then out[#out + 1] = current; current = "" end
                    out[#out + 1] = word:sub(1, maxChars - 1) .. "-"
                    word = word:sub(maxChars)
                end
                if current == "" then
                    current = word
                elseif #current + 1 + #word <= maxChars then
                    current = current .. " " .. word
                else
                    out[#out + 1] = current
                    current = word
                end
            end
            if current ~= "" then out[#out + 1] = current end
        end
    end
    return table.concat(out, "\n")
end

local function splitLines(text)
    local lines = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    return lines
end

--- Pixel layout of the expanded reader. Pure: everything comes from opts.
-- opts: screenW, screenH, fontScale (PDA font scale, 1.0 default),
--       image = { width, height } or nil.
function M.Layout(opts)
    local screenW = math.max(tonumber(opts.screenW) or 1920, 320)
    local screenH = math.max(tonumber(opts.screenH) or 1080, 240)
    local fontScale = clamp(opts.fontScale or 1.0, 0.6, 2.0)
    local screenScale = clamp(screenH / 1080.0, 0.75, 2.0)

    local margin = math.max(16, math.floor(screenH * 0.03))
    -- About 70% x 75% of the screen, but no wider than 1.55x its height so
    -- ultrawide screens get a readable column instead of a letterbox strip.
    local panelW = math.floor(math.min(screenW * 0.70, screenH * 1.55))
    panelW = math.floor(clamp(panelW, math.min(480, screenW - margin * 2), screenW - margin * 2))
    local panelH = math.floor(clamp(screenH * 0.75, math.min(300, screenH - margin * 2), screenH - margin * 2))
    local panelX = math.floor((screenW - panelW) / 2)
    local panelY = math.floor((screenH - panelH) / 2)

    local charHeight = math.floor(clamp(17.0 * fontScale * screenScale + 0.5, 14, 40))
    local titleCharHeight = math.floor(charHeight * 1.20 + 0.5)
    local footerCharHeight = math.max(12, math.floor(charHeight * 0.78 + 0.5))
    local border = math.max(2, math.floor(charHeight * 0.12))
    local pad = math.max(12, math.floor(charHeight * 0.85))
    local gap = math.max(10, math.floor(charHeight * 0.9))

    local headerH = titleCharHeight + pad
    local footerH = math.floor(footerCharHeight * 1.2) + math.floor(pad * 0.6)
    local bodyX = border + pad
    local bodyY = border + headerH + math.floor(pad * 0.75)
    local bodyW = panelW - (border + pad) * 2
    local bodyH = panelH - bodyY - footerH - border - math.floor(pad * 0.5)
    bodyH = math.max(bodyH, charHeight * 3)

    local layout = {
        panelX = panelX, panelY = panelY, panelW = panelW, panelH = panelH,
        border = border, pad = pad,
        headerH = headerH,
        titleX = border + pad, titleY = border + math.floor(pad * 0.5),
        titleW = panelW - (border + pad) * 2, titleCharHeight = titleCharHeight,
        footerX = border + pad, footerY = panelH - border - footerH + math.floor(pad * 0.2),
        footerW = panelW - (border + pad) * 2, footerH = footerH, footerCharHeight = footerCharHeight,
        charHeight = charHeight,
        lineHeight = math.floor(charHeight * 1.12 + 0.5),
        textX = bodyX, textY = bodyY, textW = bodyW, textH = bodyH,
    }

    local image = opts.image
    if image and (tonumber(image.width) or 0) > 0 and (tonumber(image.height) or 0) > 0 then
        local box
        -- Side by side needs ~40 characters left for text beside a 42% image
        -- column (0.58 * 48 / 0.68 ~= 41); narrower screens stack.
        if bodyW >= charHeight * 48 then
            -- Side by side: image column on the left, text on the right.
            local boxW = math.floor(bodyW * 0.42)
            box = { x = bodyX, y = bodyY, width = boxW, height = bodyH }
            layout.textX = bodyX + boxW + gap
            layout.textW = bodyW - boxW - gap
        else
            -- Narrow screens: image above the text.
            local boxH = math.floor(bodyH * 0.45)
            box = { x = bodyX, y = bodyY, width = bodyW, height = boxH }
            layout.textY = bodyY + boxH + gap
            layout.textH = math.max(bodyH - boxH - gap, charHeight * 2)
        end
        local fit = M.FitImage(image.width, image.height, box.width, box.height)
        if fit then
            layout.imageX = box.x + fit.x
            layout.imageY = box.y + fit.y
            layout.imageW = fit.width
            layout.imageH = fit.height
        else
            layout.textX, layout.textY, layout.textW, layout.textH = bodyX, bodyY, bodyW, bodyH
        end
    end

    layout.visibleLines = math.max(1, math.floor(layout.textH / layout.lineHeight))
    return layout
end

local IDS = {
    overlay = "cr_intel_overlay",
    root = "cr_intel_root",
    frame = "cr_intel_frame",
    backdrop = "cr_intel_backdrop",
    header = "cr_intel_header",
    image = "cr_intel_image",
    title = "cr_intel_title",
    text = "cr_intel_text",
    footer = "cr_intel_footer",
}
M.IDS = IDS
local PANEL_IDS = { IDS.frame, IDS.backdrop, IDS.header, IDS.image }
local TEXT_IDS = { IDS.title, IDS.text, IDS.footer }
local CHILD_IDS = { IDS.frame, IDS.backdrop, IDS.header, IDS.image, IDS.title, IDS.text, IDS.footer }

--- deps:
--   exu            EXU module (overlay, material and key calls), may be nil
--   useItem(name)  returns a game file's contents or nil (stock UseItem)
--   missionFile()  current mission filename (stock GetMissionFilename)
--   screen()       width, height in pixels
--   theme()        { fontScale, font, useCustomFont, metrics, colors, header, border, spaceWidth(charHeight) }
--   wrap(text, widthPx, charHeightPx) -> wrapped text (optional)
--   log(text)      optional
--   sound(name)    optional UI sound
function M.Create(deps)
    deps = deps or {}
    local ui = {
        stem = nil, pages = {}, page = 1, scroll = 0,
        expanded = false, created = false, failed = false,
        keysDown = {}, signature = nil, imageMaterials = {},
    }

    local function log(text)
        if deps.log then pcall(deps.log, "CRIntel: " .. tostring(text)) end
    end
    local function sound(name)
        if deps.sound then pcall(deps.sound, name) end
    end
    local function exu() return deps.exu end

    local function read(name)
        if type(deps.useItem) ~= "function" then return nil end
        local ok, data = pcall(deps.useItem, name)
        if ok and type(data) == "string" and data ~= "" then return data end
        return nil
    end

    local function currentStem()
        if type(deps.missionFile) ~= "function" then return "" end
        local ok, name = pcall(deps.missionFile)
        return ok and M.MissionStem(name) or ""
    end

    --- (Re)load when the mission changes. Returns the page list.
    function ui.Load(force)
        local stem = currentStem()
        if not force and stem == ui.stem then return ui.pages end
        ui.Collapse("mission changed")
        ui.stem, ui.pages, ui.page, ui.scroll, ui.imageMaterials = stem, {}, 1, 0, {}
        if stem == "" then return ui.pages end
        for n = 1, M.MAX_PAGES do
            local base = (n == 1) and stem or string.format("%s_%d", stem, n)
            local text = M.NormalizeText(read(base .. ".des"))
            if text == "" then break end
            local page = { text = text }
            if n >= 2 then
                local png = base .. ".png"
                local width, height = M.PngSize(read(png))
                if width then page.image = { file = png, width = width, height = height } end
            end
            ui.pages[#ui.pages + 1] = page
        end
        log(string.format("%s: %d page(s)", stem, #ui.pages))
        return ui.pages
    end

    function ui.Reset()
        ui.Collapse("reset")
        ui.stem, ui.pages, ui.page, ui.scroll, ui.imageMaterials = nil, {}, 1, 0, {}
    end

    function ui.HasIntel() return #ui.Load() > 0 end
    function ui.Count() return #ui.Load() end
    function ui.Page() return ui.page end
    function ui.IsExpanded() return ui.expanded end

    local function turnPage(delta)
        local count = #ui.pages
        if count <= 1 then return false end
        local nextPage = clamp(ui.page + delta, 1, count)
        if nextPage == ui.page then return false end
        ui.page, ui.scroll = nextPage, 0
        sound(delta < 0 and "mnu_back.wav" or "mnu_next.wav")
        return true
    end

    ---------------------------------------------------------------------
    -- PDA preview
    ---------------------------------------------------------------------

    --- PDA page text: header, page counter, the first lines, footer.
    function ui.BuildPdaText(buildHeader, appendFooter, pageId)
        local lines = { buildHeader(pageId) }
        ui.Load()
        local page = ui.pages[ui.page]
        if not page then
            lines[#lines + 1] = "No mission intel."
            appendFooter(lines, "--------------------------------", "[ / ] Switch Page", "X Toggle PDA")
            return table.concat(lines, "\n")
        end
        lines[#lines + 1] = string.format("BRIEFING PAGE %d/%d%s", ui.page, #ui.pages,
            page.image and "  [IMAGE]" or "")
        lines[#lines + 1] = ""
        local preview = splitLines(page.text)
        local maxLines, maxChars, used = 9, 480, 0
        for i = 1, math.min(#preview, maxLines) do
            local line = preview[i]
            if used + #line > maxChars then
                lines[#lines + 1] = line:sub(1, math.max(maxChars - used, 0)) .. "..."
                used = maxChars
                break
            end
            lines[#lines + 1] = line
            used = used + #line
        end
        if #preview > maxLines and used < maxChars then lines[#lines + 1] = "..." end
        appendFooter(lines, "--------------------------------", "Enter Expand  Left/Right Briefing Page",
            "[ / ] Switch Page  X Toggle PDA")
        return table.concat(lines, "\n")
    end

    --- Arrow keys and Enter while the PDA shows INTEL. Returns true when the
    -- PDA preview needs a refresh.
    function ui.HandlePdaInput(keys)
        keys = keys or {}
        ui.Load()
        if #ui.pages == 0 then return false end
        local changed = false
        if keys.enter then
            if ui.expanded then ui.Collapse("enter") else ui.Expand() end
            changed = true
        end
        if keys.left then changed = turnPage(-1) or changed end
        if keys.right then changed = turnPage(1) or changed end
        if ui.expanded then
            if keys.up then ui.Scroll(-1) end
            if keys.down then ui.Scroll(1) end
        end
        if changed then ui.Render() end
        return changed
    end

    ---------------------------------------------------------------------
    -- Expanded reader
    ---------------------------------------------------------------------

    local function canUseOverlay()
        local e = exu()
        return not ui.failed and e and e.CreateOverlay and e.CreateOverlayElement and e.AddOverlay2D
            and e.AddOverlayElementChild and e.ShowOverlay and e.HideOverlay and e.SetOverlayPosition
            and e.SetOverlayDimensions and e.SetOverlayMaterial and e.SetOverlayCaption
            and e.SetOverlayTextCharHeight and e.SetOverlayParameter and e.ShowOverlayElement
            and e.HideOverlayElement and true or false
    end

    local function safeCaller()
        local ok = true
        local function call(fn, ...)
            if not ok or type(fn) ~= "function" then return nil end
            local success, result = pcall(fn, ...)
            if not success then
                ok = false
                log("overlay call failed: " .. tostring(result))
                return nil
            end
            return result
        end
        return call, function() return ok end
    end

    function ui.Destroy()
        local e = exu()
        ui.expanded, ui.signature = false, nil
        if not ui.created or not e then ui.created = false; return end
        if e.HideOverlay then pcall(e.HideOverlay, IDS.overlay) end
        if e.RemoveOverlayElementChild then
            for _, id in ipairs(CHILD_IDS) do pcall(e.RemoveOverlayElementChild, IDS.root, id) end
        end
        if e.RemoveOverlay2D then pcall(e.RemoveOverlay2D, IDS.overlay, IDS.root) end
        if e.DestroyOverlayElement then
            for i = #CHILD_IDS, 1, -1 do pcall(e.DestroyOverlayElement, CHILD_IDS[i]) end
            pcall(e.DestroyOverlayElement, IDS.root)
        end
        if e.DestroyOverlay then pcall(e.DestroyOverlay, IDS.overlay) end
        ui.created = false
    end

    local function create(theme)
        if ui.created then
            local e = exu()
            if not (e and e.HasOverlayElement) then return true end
            local ok, has = pcall(e.HasOverlayElement, IDS.frame)
            if ok and has == true then return true end
            ui.created = false
        end
        if not canUseOverlay() then return false end
        local e = exu()
        local call, succeeded = safeCaller()
        call(e.CreateOverlay, IDS.overlay)
        call(e.CreateOverlayElement, "Panel", IDS.root)
        for _, id in ipairs(PANEL_IDS) do
            call(e.CreateOverlayElement, id == IDS.frame and "BorderPanel" or "Panel", id)
        end
        for _, id in ipairs(TEXT_IDS) do call(e.CreateOverlayElement, "TextArea", id) end
        call(e.AddOverlay2D, IDS.overlay, IDS.root)
        for _, id in ipairs(CHILD_IDS) do call(e.AddOverlayElementChild, IDS.root, id) end
        -- Above the PDA (645) and its feedback line (646); EXU clamps at 650.
        call(e.SetOverlayZOrder, IDS.overlay, 648)
        if theme.metrics ~= nil and e.SetOverlayMetricsMode then
            call(e.SetOverlayMetricsMode, IDS.root, theme.metrics)
            for _, id in ipairs(CHILD_IDS) do call(e.SetOverlayMetricsMode, id, theme.metrics) end
        end
        call(e.SetOverlayMaterial, IDS.root, "CR_UI")
        call(e.SetOverlayParameter, IDS.root, "transparent", "true")
        call(e.SetOverlayMaterial, IDS.frame, "CR_UI")
        call(e.SetOverlayParameter, IDS.frame, "transparent", "true")
        call(e.SetOverlayMaterial, IDS.backdrop, M.BACKDROP_MATERIAL)
        call(e.SetOverlayParameter, IDS.title, "alignment", "left")
        call(e.SetOverlayParameter, IDS.text, "alignment", "left")
        call(e.SetOverlayParameter, IDS.footer, "alignment", "left")
        if theme.useCustomFont and theme.font and e.SetOverlayTextFont then
            for _, id in ipairs(TEXT_IDS) do call(e.SetOverlayTextFont, id, theme.font) end
            -- Same rebind as the PDA: D3D11 needs the shader-backed atlas.
            for _, id in ipairs(TEXT_IDS) do call(e.SetOverlayMaterial, id, "CR_OverlayFont") end
        end
        for _, id in ipairs(TEXT_IDS) do call(e.SetOverlayCaption, id, "") end
        call(e.ShowOverlayElement, IDS.root)
        for _, id in ipairs(CHILD_IDS) do call(e.ShowOverlayElement, id) end
        call(e.HideOverlay, IDS.overlay)
        if not succeeded() then
            ui.failed = true
            ui.Destroy()
            log("expanded reader unavailable")
            return false
        end
        ui.created = true
        return true
    end

    --- Material showing page n's image, built once from CRIntelImage.
    local function imageMaterial(n, page)
        if not page.image then return nil end
        local cached = ui.imageMaterials[n]
        if cached ~= nil then return cached or nil end
        local e = exu()
        local name = string.format("CRIntel_%s_%d", ui.stem or "", n)
        local ok = e and type(e.CloneMaterial) == "function" and type(e.SetMaterialTexture) == "function"
        if ok then
            local existsOk, exists = false, false
            if type(e.MaterialExists) == "function" then existsOk, exists = pcall(e.MaterialExists, name) end
            if not (existsOk and exists == true) then
                local cloneOk, cloned = pcall(e.CloneMaterial, M.IMAGE_BASE_MATERIAL, name)
                ok = cloneOk and cloned ~= false and cloned ~= nil
            end
        end
        if ok then
            -- Technique 0 is the D3D11 programmable path, 1 the DX9/GL fallback.
            local setOk, set = pcall(e.SetMaterialTexture, name, page.image.file, 0, 0, 0)
            ok = setOk and set ~= false
            if ok then pcall(e.SetMaterialTexture, name, page.image.file, 1, 0, 0) end
        end
        if not ok then log("no image material for " .. tostring(page.image.file)) end
        ui.imageMaterials[n] = ok and name or false
        return ok and name or nil
    end

    local function wrap(text, widthPx, charHeight)
        if type(deps.wrap) == "function" then
            local ok, wrapped = pcall(deps.wrap, text, widthPx, charHeight)
            if ok and type(wrapped) == "string" then return wrapped end
        end
        return M.WrapByChars(text, math.floor(widthPx / (charHeight * 0.68)))
    end

    local function themeOf()
        local theme = {}
        if type(deps.theme) == "function" then
            local ok, value = pcall(deps.theme)
            if ok and type(value) == "table" then theme = value end
        end
        theme.colors = theme.colors or {}
        return theme
    end

    local function color(c, fallback)
        c = c or fallback or { r = 1, g = 1, b = 1, a = 1 }
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end

    --- Push the current page to the expanded overlay. No-op unless expanded.
    function ui.Render()
        if not ui.expanded then return false end
        local page = ui.pages[ui.page]
        if not page then ui.Collapse("no page"); return false end
        local theme = themeOf()
        if not create(theme) then ui.expanded = false; return false end
        local e = exu()

        local screenW, screenH = 1920, 1080
        if type(deps.screen) == "function" then
            local ok, w, h = pcall(deps.screen)
            if ok and tonumber(w) and tonumber(h) then screenW, screenH = w, h end
        end
        local material = imageMaterial(ui.page, page)
        local layout = M.Layout({ screenW = screenW, screenH = screenH, fontScale = theme.fontScale,
            image = material and page.image or nil })

        -- Checked before wrapping: Sync calls this every frame.
        local signature = table.concat({ screenW, screenH, ui.stem or "", ui.page, ui.scroll,
            tostring(material), tostring(theme.header), tostring(theme.border), tostring(theme.fontScale),
            string.format("%.3f,%.3f,%.3f", color(theme.colors.text)) }, "|")
        if signature == ui.signature then return true end

        local lines = splitLines(wrap(page.text, layout.textW, layout.charHeight))
        local maxScroll = math.max(#lines - layout.visibleLines, 0)
        ui.scroll = clamp(ui.scroll, 0, maxScroll)
        ui.maxScroll = maxScroll
        ui.visibleLines = layout.visibleLines
        local visible = {}
        for i = ui.scroll + 1, math.min(ui.scroll + layout.visibleLines, #lines) do visible[#visible + 1] = lines[i] end

        local title = string.format("MISSION INTEL   PAGE %d/%d", ui.page, #ui.pages)
        local footer = "Left/Right Page   Up/Down Scroll   PgUp/PgDn Jump   Tab/Enter Close"
        if maxScroll > 0 then
            footer = string.format("%s   Lines %d-%d of %d", footer, ui.scroll + 1,
                ui.scroll + #visible, #lines)
        end
        local caption = table.concat(visible, "\n")

        local call, succeeded = safeCaller()
        local function space(charHeight)
            if type(theme.spaceWidth) == "function" then
                local ok, value = pcall(theme.spaceWidth, charHeight)
                if ok and value then return tostring(value) end
            end
            return tostring(math.max(4, math.floor(charHeight * 0.70 + 0.5)))
        end
        local function placeText(id, x, y, w, h, charHeight, text, c)
            call(e.SetOverlayPosition, id, x, y)
            call(e.SetOverlayDimensions, id, w, h)
            call(e.SetOverlayTextCharHeight, id, charHeight)
            call(e.SetOverlayParameter, id, "space_width", space(charHeight))
            if e.SetOverlayTextColor then
                call(e.SetOverlayTextColor, id, color(c))
            elseif e.SetOverlayColor then
                call(e.SetOverlayColor, id, color(c))
            end
            call(e.SetOverlayCaption, id, text)
        end

        local L = layout
        local borderSize = string.format("%d %d %d %d", L.border, L.border, L.border, L.border)
        call(e.SetOverlayPosition, IDS.root, L.panelX, L.panelY)
        call(e.SetOverlayDimensions, IDS.root, L.panelW, L.panelH)
        call(e.SetOverlayPosition, IDS.frame, 0, 0)
        call(e.SetOverlayDimensions, IDS.frame, L.panelW, L.panelH)
        call(e.SetOverlayParameter, IDS.frame, "border_size", borderSize)
        if theme.border then call(e.SetOverlayParameter, IDS.frame, "border_material", theme.border) end
        call(e.SetOverlayPosition, IDS.backdrop, L.border, L.border)
        call(e.SetOverlayDimensions, IDS.backdrop, L.panelW - L.border * 2, L.panelH - L.border * 2)
        call(e.SetOverlayPosition, IDS.header, L.border, L.border)
        call(e.SetOverlayDimensions, IDS.header, L.panelW - L.border * 2, L.headerH)
        if theme.header then call(e.SetOverlayMaterial, IDS.header, theme.header) end

        if material and L.imageW then
            call(e.SetOverlayMaterial, IDS.image, material)
            call(e.SetOverlayPosition, IDS.image, L.imageX, L.imageY)
            call(e.SetOverlayDimensions, IDS.image, L.imageW, L.imageH)
            if e.SetOverlayColor then call(e.SetOverlayColor, IDS.image, 1.0, 1.0, 1.0, 1.0) end
            call(e.ShowOverlayElement, IDS.image)
        else
            call(e.HideOverlayElement, IDS.image)
        end

        placeText(IDS.title, L.titleX, L.titleY, L.titleW, L.titleCharHeight + 4, L.titleCharHeight, title,
            theme.colors.title)
        placeText(IDS.text, L.textX, L.textY, L.textW, L.textH, L.charHeight, caption, theme.colors.text)
        placeText(IDS.footer, L.footerX, L.footerY, L.footerW, L.footerH, L.footerCharHeight, footer,
            theme.colors.footer)
        call(e.ShowOverlay, IDS.overlay)

        if not succeeded() then
            ui.signature = nil
            ui.Collapse("render failed")
            return false
        end
        ui.signature = signature
        return true
    end

    function ui.Expand()
        ui.Load()
        if #ui.pages == 0 then return false end
        ui.expanded, ui.scroll, ui.signature = true, 0, nil
        -- Keys already held when the reader opens must not count as presses.
        ui.keysDown = {}
        local e = exu()
        if e and type(e.GetGameKey) == "function" then
            for _, key in ipairs({ "TAB", "PAGEUP", "PAGEDOWN" }) do
                local ok, down = pcall(e.GetGameKey, key)
                ui.keysDown[key] = ok and down == true
            end
        end
        sound("mnu_next.wav")
        if not ui.Render() then return false end
        log("expanded page " .. ui.page)
        return true
    end

    function ui.Collapse(reason)
        if not ui.expanded then return false end
        ui.expanded, ui.signature = false, nil
        local e = exu()
        if ui.created and e and e.HideOverlay then pcall(e.HideOverlay, IDS.overlay) end
        log("collapsed (" .. tostring(reason or "") .. ")")
        return true
    end

    function ui.Scroll(lines)
        if not ui.expanded then return false end
        local before = ui.scroll
        ui.scroll = clamp(ui.scroll + lines, 0, ui.maxScroll or 0)
        if ui.scroll ~= before then ui.Render(); return true end
        return false
    end

    local function edge(key)
        local e = exu()
        if not (e and type(e.GetGameKey) == "function") then return false end
        local ok, down = pcall(e.GetGameKey, key)
        down = ok and down == true
        local pressed = down and not ui.keysDown[key]
        ui.keysDown[key] = down
        return pressed
    end

    --- Every frame. active: the PDA is open on INTEL with nothing covering it.
    -- typing: a chat/text editor has focus.
    function ui.Sync(active, typing)
        if not ui.expanded then return end
        if not active then ui.Collapse("left INTEL"); return end
        if typing then return end
        -- Raw polling, as the network key poller does: works in single player
        -- and co-op, and only while the reader is open.
        if edge("TAB") then ui.Collapse("tab"); sound("mnu_back.wav"); return end
        local jump = math.max((ui.visibleLines or 10) - 1, 1)
        if edge("PAGEUP") then ui.Scroll(-jump) end
        if edge("PAGEDOWN") then ui.Scroll(jump) end
        -- Resolution, colour or font changes re-render; unchanged frames are
        -- skipped by the signature.
        ui.Render()
    end

    return ui
end

return M
