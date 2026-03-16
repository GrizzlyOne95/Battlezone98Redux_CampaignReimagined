-- Misn04 Mission Script (Converted from Misn04Mission.cpp)

-- Compatibility for 1.5
SetLabel = SetLabel or SetLabel

-- EXU Initialization
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3659600763" })
local exu = require("exu")
local aiCore = require("aiCore")
local DiffUtils = require("DiffUtils")
local subtit = require("ScriptSubtitles")
local PersistentConfig = require("PersistentConfig")
local Environment = require("Environment")
local autosave = require("AutoSave")
local PlayerPilotMode = require("PlayerPilotMode")


local M

local function NewMissionState()
    return {
        missionstart = false,
        warn = 0,
        safety = 0,
        retreat = false,
        surveysent = false,
        reconsent = false,
        firstwave = false,
        secondwave = false,
        thirdwave = false,
        fourthwave = false,
        fifthwave = false,
        discrelic = false,
        ccatugsent = false,
        attackccabase = false,
        ccabasedestroyed = false,
        fifthwavedestroyed = false,
        missionend = false,
        wavenumber = 1,
        missionwon = false,
        wave1dead = false,
        wave2dead = false,
        wave3dead = false,
        wave4dead = false,
        wave5dead = false,
        wave1arrive = false,
        wave2arrive = false,
        wave3arrive = false,
        wave4arrive = false,
        wave5arrive = false,
        possiblewin = false,
        loopbreak = false,
        basesecure = false,
        newobjective = false,
        relicsecure = false,
        discoverrelic = false,
        missionfail2 = false,
        aud10 = nil,
        aud11 = nil,
        aud12 = nil,
        aud13 = nil,
        aud14 = nil,
        ccahasrelic = false,
        relicseen = false,
        obset = false,
        wave1 = 0,
        wave2 = 99999.0,
        wave3 = 99999.0,
        wave4 = 99999.0,
        wave5 = 99999.0,
        endcindone = 999999.0,
        startendcin = 999999.0,
        ccatug = 999999999999.0,
        notfound = 999999999999999.0,
        build2 = false,
        build3 = false,
        build4 = false,
        build5 = false,
        halfway = false,
        svrec = nil,
        pu1 = nil,
        pu2 = nil,
        pu3 = nil,
        pu4 = nil,
        pu5 = nil,
        pu6 = nil,
        pu7 = nil,
        pu8 = nil,
        navbeacon = nil,
        cheat1 = nil,
        cheat2 = nil,
        cheat3 = nil,
        cheat4 = nil,
        cheat5 = nil,
        cheat6 = nil,
        cheat7 = nil,
        cheat8 = nil,
        cheat9 = nil,
        cheat10 = nil,
        tug = nil,
        svtug = nil,
        tuge1 = nil,
        tuge2 = nil,
        player = nil,
        surv1 = nil,
        surv2 = nil,
        surv3 = nil,
        surv4 = nil,
        cam1 = nil,
        cam2 = nil,
        cam3 = nil,
        basecam = nil,
        reliccam = nil,
        avrec = nil,
        w1u1 = nil,
        w1u2 = nil,
        w1u3 = nil,
        w1u4 = nil,
        w2u1 = nil,
        w2u2 = nil,
        w2u3 = nil,
        w3u1 = nil,
        w3u2 = nil,
        w3u3 = nil,
        w3u4 = nil,
        w4u1 = nil,
        w4u2 = nil,
        w4u3 = nil,
        w4u4 = nil,
        w4u5 = nil,
        w5u1 = nil,
        w5u2 = nil,
        w5u3 = nil,
        w5u4 = nil,
        w5u5 = nil,
        w5u6 = nil,
        spawn1 = nil,
        spawn2 = nil,
        spawn3 = nil,
        relic = nil,
        calipso = nil,
        turret1 = nil,
        turret2 = nil,
        turret3 = nil,
        turret4 = nil,
        aud1 = nil,
        aud2 = nil,
        aud3 = nil,
        aud4 = nil,
        aud20 = nil,
        aud21 = nil,
        aud22 = nil,
        aud23 = nil,
        doneaud20 = false,
        doneaud21 = false,
        doneaud22 = false,
        doneaud23 = false,
        done = false,
        secureloopbreak = false,
        found = false,
        endcinfinish = false,
        loopbreak2 = false,
        investigate = 999999999.0,
        investigator = 0,
        tur1 = 999999999.0,
        tur2 = 999999999.0,
        tur3 = 999999999.0,
        tur4 = 999999999.0,
        tur1sent = false,
        tur2sent = false,
        tur3sent = false,
        tur4sent = false,
        cin1done = false,
        missionfail = false,
        chewedout = false,
        relicmoved = false,
        height = 500,
        cintime1 = 9999999999.0,
        fetch = 0,
        reconcca = 0,
        relicstartpos = 0,
        cheater = false,
        cin_started = false,
        difficulty = 2,
        tugobjective = false,
        ccatugretry = false,
        loading_done = false,
        loadGracePeriod = 0,
        overlayBootTestAt = nil,
        overlayBootTestDone = false,
        overlayDemoReady = false,
        overlayDemoVisible = false,
        overlayDemoToggleLatch = false,
        overlayDemoAutoHideAt = nil,
        overlayDemoStatusNextAt = 0.0,
        overlayDemoTextureMaterial = nil,
        overlayDemoSuppressed = false,
        overlayDemoResumeAfterSuppression = false,
        overlayDemoResumeDuration = 0.0,
        overlayPauseDebugSignature = "",
        overlayPauseDebugDumpLatch = false
    }
end

local function RefreshMissionHandles()
    M.cam1 = GetHandle("apcamr352_camerapod")
    M.cam2 = GetHandle("apcamr350_camerapod")
    M.cam3 = GetHandle("apcamr351_camerapod")
    M.basecam = GetHandle("apcamr-1_camerapod")
    M.svrec = GetHandle("svrecy-1_recycler")
    M.avrec = GetHandle("avrecy-1_recycler")

    if IsValid(M.avrec) then
        SetObjectiveName(M.avrec, "Recycler Montana")
    end
    if IsValid(M.cam1) then SetObjectiveName(M.cam1, "SW Geyser") end
    if IsValid(M.cam2) then SetObjectiveName(M.cam2, "NW Geyser") end
    if IsValid(M.cam3) then SetObjectiveName(M.cam3, "NE Geyser") end
    if IsValid(M.basecam) then SetObjectiveName(M.basecam, "CCA Base") end
end

-- Helper for AI
local function SetupAI()
    DiffUtils.SetupTeams(aiCore.Factions.NSDF, aiCore.Factions.CCA, 2)

    -- Configure Player Team (1) for Scavenger Assist
    -- Configure Player Team (1) for Scavenger Assist
    if aiCore.ActiveTeams and aiCore.ActiveTeams[1] then
        aiCore.ActiveTeams[1]:SetConfig("scavengerAssist", PersistentConfig.Settings.ScavengerAssistEnabled)
        aiCore.ActiveTeams[1]:SetConfig("manageFactories", false)
        aiCore.ActiveTeams[1]:SetConfig("autoRepairWingmen", PersistentConfig.Settings.AutoRepairWingmen)
    end

    -- Configure CCA (Team 2)
    if aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[2] then
        local cca = aiCore.ActiveTeams[2]
        cca:SetCustomStrategy({
            Recycler = {
                "scavenger", "scavenger", "scavenger", "scavenger",
                "constructor",
            },
            Factory = { "tank", "tank", "lighttank", "apc", "turret", "turret", "turret", "turret", "turret", "turret" }
        }, true)

        -- Fully Automate Base and Units
        cca.Config.autoManage = true
        cca.Config.autoBuild = true
        cca.Config.manageFactories = true
        cca.Config.manageConstructor = true
        cca.Config.resourceBoost = true
        cca.resourceBoostTimer = GetTime() + DiffUtils.ScaleTimer(300.0)
        cca.Config.allowProducerRelocation = false
        cca.Config.minScavengers = 4
        cca.Config.requireConstructorFirst = true

        -- High-level Base Planning
        cca:PlanDefensivePerimeter(2, 2) -- 2 powers, 1 tower each (Interleaved)

        -- ExpandBase will automatically handle Barracks, Supply, Comm, Hangar, and HQ over time.
        -- We just need to plan the optimal Silo location since it's terrain-dependent.
        local siloPos = cca:FindOptimalSiloLocation(500, 900)
        if siloPos then
            cca:AddBuilding(aiCore.Units[cca.faction].silo, siloPos, 5)
        end
    end
end

local function PilotModeCanManageHandle(h)
    if not h or not IsValid(h) then
        return false
    end

    return h ~= GetPlayerHandle()
end

-- Variables
M = NewMissionState()
local DEFAULT_TPS = 20
local hardDifficultyObjective = { "hard_diff", "yellow", 8.0, "High Difficulty: Enemy presence intensified." }
local easyDifficultyObjective = { "easy_diff", "blue", 8.0, "Low Difficulty: Enemy presence reduced." }
local OVERLAY_DEMO_IDS = {
    overlay = "misn04_overlay_demo",
    root = "misn04_overlay_demo_root",
    backdrop = "misn04_overlay_demo_backdrop",
    header = "misn04_overlay_demo_header",
    title = "misn04_overlay_demo_title",
    body = "misn04_overlay_demo_body",
    swatchFrame = "misn04_overlay_demo_swatch_frame",
    swatch = "misn04_overlay_demo_swatch",
    strip = "misn04_overlay_demo_strip",
    swatchText = "misn04_overlay_demo_swatch_text",
    footer = "misn04_overlay_demo_footer",
}
local OVERLAY_DEMO_TEXTURE_CANDIDATES = { "HUDcombi", "HUDcomba", "reticle1" }
local OVERLAY_DEMO_SOLID_MATERIAL = "BaseWhiteNoLighting"

local function RefreshDifficulty()
    if exu and exu.GetDifficulty then
        local d = exu.GetDifficulty()
        if d ~= nil then
            M.difficulty = d
        end
    end
    if M.difficulty == nil then
        M.difficulty = 2
    end
    return M.difficulty
end

local function ApplyDifficultyObjectives()
    if M.difficulty >= 3 then
        AddObjective(hardDifficultyObjective[1], hardDifficultyObjective[2], hardDifficultyObjective[3], hardDifficultyObjective[4])
    elseif M.difficulty <= 1 then
        AddObjective(easyDifficultyObjective[1], easyDifficultyObjective[2], easyDifficultyObjective[3], easyDifficultyObjective[4])
    end
end

local function ApplyQOL()
    if exu then
        if exu.SetReticleRange then
            exu.SetReticleRange(600)
        end
        if exu.SetOrdnanceVelocInheritance then
            exu.SetOrdnanceVelocInheritance(true)
        end
    end

    if PersistentConfig and PersistentConfig.Initialize then
        PersistentConfig.Initialize()
    end
    if Environment and Environment.Init then
        Environment.Init()
    end
end

local function TurboValue(team)
    if team == 1 then
        return true
    end
    if team ~= 0 and M.difficulty >= 3 then
        return true
    end
end

local function ApplyTurbo(h)
    if not (exu and exu.SetUnitTurbo and IsCraft(h)) then
        return
    end
    local value = TurboValue(GetTeamNum(h))
    if value ~= nil and value ~= false then
        exu.SetUnitTurbo(h, value)
    else
        exu.SetUnitTurbo(h, false)
    end
end

local function ApplyTurboToAll()
    if not (exu and exu.SetUnitTurbo) then
        return
    end
    for h in AllCraft() do
        ApplyTurbo(h)
    end
end

local function UpdateModules(dt)
    if exu and exu.UpdateOrdnance then
        exu.UpdateOrdnance()
    end
    if Environment and Environment.Update then
        Environment.Update(dt)
    end
    if subtit and subtit.Update then
        subtit.Update()
    end
    if PersistentConfig then
        if PersistentConfig.UpdateInputs then PersistentConfig.UpdateInputs() end
        if PersistentConfig.UpdateHeadlights then PersistentConfig.UpdateHeadlights() end
    end
end

local function OverlayCall(fn, ...)
    if type(fn) ~= "function" then
        return false, "missing"
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        print("misn04: overlay demo call failed: " .. tostring(result))
        return false, result
    end
    if result == false then
        return false, "returned false"
    end
    return true, result
end

local function DestroyOverlayDemo()
    if not exu then
        return
    end

    local ids = OVERLAY_DEMO_IDS
    if exu.DestroyOverlayElement then
        pcall(exu.DestroyOverlayElement, ids.footer)
        pcall(exu.DestroyOverlayElement, ids.swatchText)
        pcall(exu.DestroyOverlayElement, ids.strip)
        pcall(exu.DestroyOverlayElement, ids.swatch)
        pcall(exu.DestroyOverlayElement, ids.swatchFrame)
        pcall(exu.DestroyOverlayElement, ids.body)
        pcall(exu.DestroyOverlayElement, ids.title)
        pcall(exu.DestroyOverlayElement, ids.header)
        pcall(exu.DestroyOverlayElement, ids.backdrop)
        pcall(exu.DestroyOverlayElement, ids.root)
    end
    if exu.DestroyOverlay then
        pcall(exu.DestroyOverlay, ids.overlay)
    end
end

local function GetOverlayDemoTextureMaterial()
    if not (exu and exu.MaterialExists) then
        return nil
    end

    for _, materialName in ipairs(OVERLAY_DEMO_TEXTURE_CANDIDATES) do
        local okDefault, existsDefault = pcall(exu.MaterialExists, materialName)
        if okDefault and existsDefault then
            return materialName
        end

        local okModable, existsModable = pcall(exu.MaterialExists, materialName, "Modable")
        if okModable and existsModable then
            return materialName
        end
    end

    return nil
end

local function SetOverlayDemoVisible(visible, duration)
    if not (M.overlayDemoReady and exu) then
        return false
    end

    local ids = OVERLAY_DEMO_IDS
    if visible then
        OverlayCall(exu.ShowOverlay, ids.overlay)
        M.overlayDemoVisible = true
        M.overlayDemoAutoHideAt = GetTime() + math.max(tonumber(duration) or 20.0, 0.5)
    else
        OverlayCall(exu.HideOverlay, ids.overlay)
        M.overlayDemoVisible = false
        M.overlayDemoAutoHideAt = nil
    end

    return true
end

local function NormalizeWrapInput(text)
    text = tostring(text or "")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    return text
end

local function CountOverlayLines(text)
    local normalized = NormalizeWrapInput(text)
    local count = 0
    for _ in (normalized .. "\n"):gmatch("(.-)\n") do
        count = count + 1
    end
    return math.max(count, 1)
end

local function SplitOverlayToken(token, maxCharsPerLine)
    local parts = {}
    token = tostring(token or "")
    maxCharsPerLine = math.max(tonumber(maxCharsPerLine) or 12, 4)

    while #token > maxCharsPerLine do
        local take = math.max(maxCharsPerLine - 1, 1)
        parts[#parts + 1] = token:sub(1, take) .. "-"
        token = token:sub(take + 1)
    end

    if token ~= "" then
        parts[#parts + 1] = token
    end
    if #parts == 0 then
        parts[1] = ""
    end
    return parts
end

local function WrapOverlayText(text, maxCharsPerLine)
    text = NormalizeWrapInput(text)
    maxCharsPerLine = math.max(tonumber(maxCharsPerLine) or 32, 8)

    local wrappedLines = {}
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        if paragraph == "" then
            wrappedLines[#wrappedLines + 1] = ""
        else
            local current = ""
            for word in paragraph:gmatch("%S+") do
                local pieces = SplitOverlayToken(word, maxCharsPerLine)
                for _, piece in ipairs(pieces) do
                    if current == "" then
                        current = piece
                    elseif (#current + 1 + #piece) <= maxCharsPerLine then
                        current = current .. " " .. piece
                    else
                        wrappedLines[#wrappedLines + 1] = current
                        current = piece
                    end
                end
            end
            if current ~= "" then
                wrappedLines[#wrappedLines + 1] = current
            end
        end
    end

    return table.concat(wrappedLines, "\n")
end

local function EstimateOverlayCharsPerLine(widthPixels, charHeightPixels, widthFactor, horizontalPadding)
    widthPixels = math.max(tonumber(widthPixels) or 0, 16)
    charHeightPixels = math.max(tonumber(charHeightPixels) or 0, 1)
    widthFactor = math.max(tonumber(widthFactor) or 1.0, 0.55)
    horizontalPadding = math.max(tonumber(horizontalPadding) or 0, 0)

    local usableWidth = math.max(widthPixels - (horizontalPadding * 2), charHeightPixels * 4)
    return math.max(8, math.floor(usableWidth / (charHeightPixels * widthFactor)))
end

local function WrapOverlayTextToPixels(text, widthPixels, charHeightPixels, widthFactor, horizontalPadding)
    local maxCharsPerLine = EstimateOverlayCharsPerLine(widthPixels, charHeightPixels, widthFactor, horizontalPadding)
    return WrapOverlayText(text, maxCharsPerLine)
end

local function GetOverlayTextBlockHeight(charHeightPixels, lineCount, lineSpacing)
    charHeightPixels = math.max(tonumber(charHeightPixels) or 0, 1)
    lineCount = math.max(tonumber(lineCount) or 0, 1)
    lineSpacing = math.max(tonumber(lineSpacing) or 1.18, 1.0)
    return math.max(charHeightPixels + 4, math.floor(charHeightPixels * lineSpacing * lineCount + 6))
end

local function GetOverlayDemoScreenMetrics()
    local screenW, screenH
    if exu and exu.GetScreenResolution then
        local ok, w, h = pcall(exu.GetScreenResolution)
        if ok then
            screenW = tonumber(w)
            screenH = tonumber(h)
        end
    end
    if (not screenW or not screenH) and exu and exu.GetGameResolution then
        local ok, w, h = pcall(exu.GetGameResolution)
        if ok then
            screenW = tonumber(w)
            screenH = tonumber(h)
        end
    end

    if not screenW or not screenH or screenW <= 0 or screenH <= 0 then
        return nil, nil
    end

    return screenW, screenH
end

local function GetOverlayDemoRootPosition(rootWidth, rootHeight)
    local screenW, screenH = GetOverlayDemoScreenMetrics()
    if not screenW or not screenH then
        return 140, 360
    end

    rootWidth = math.max(tonumber(rootWidth) or 0, 0)
    rootHeight = math.max(tonumber(rootHeight) or 0, 0)

    local x = math.floor(math.max(96, screenW * 0.07))
    local y = math.floor(math.max(260, screenH * 0.36))
    x = math.min(x, math.max(24, screenW - rootWidth - 24))
    y = math.min(y, math.max(24, screenH - rootHeight - 24))
    return x, y
end

local function GetPauseDebugState()
    if not (exu and exu.GetPauseMenuDebugState) then
        return nil
    end

    local ok, state = pcall(exu.GetPauseMenuDebugState)
    if not ok or type(state) ~= "table" then
        return nil
    end

    return state
end

local function GetPauseDebugSignature(state)
    if type(state) ~= "table" then
        return "unavailable"
    end

    return table.concat({
        tostring(state.ok),
        tostring(state.pauseOpen),
        tostring(state.singleplayerPauseOpen),
        tostring(state.multiplayerPauseOpen),
        tostring(state.cursorVisible),
        tostring(state.currentScreenMatchesPauseRoot),
        tostring(state.uiCurrentScreen),
        tostring(state.uiWrapperActive),
        tostring(state.uiCurrentScreenType),
        tostring(state.uiCurrentScreenTypeName),
        tostring(state.multiplayerPauseFlag),
    }, "|")
end

local function LogPauseDebugState(reason, state)
    if type(state) ~= "table" then
        print("misn04: pause debug unavailable (" .. tostring(reason or "unknown") .. ")")
        return
    end

    print(string.format(
        "misn04: pause debug [%s] ok=%s pause=%s sp=%s mp=%s cursor=%s matchRoot=%s screen=0x%08X wrapper=%s type=%s(%s) mpFlag=%s spRoot=0x%08X mpRoot=0x%08X",
        tostring(reason or "state"),
        tostring(state.ok),
        tostring(state.pauseOpen),
        tostring(state.singleplayerPauseOpen),
        tostring(state.multiplayerPauseOpen),
        tostring(state.cursorVisible),
        tostring(state.currentScreenMatchesPauseRoot),
        tonumber(state.uiCurrentScreen) or 0,
        tostring(state.uiWrapperActive),
        tostring(state.uiCurrentScreenType),
        tostring(state.uiCurrentScreenTypeName),
        tostring(state.multiplayerPauseFlag),
        tonumber(state.singleplayerPauseRoot) or 0,
        tonumber(state.multiplayerPauseRoot) or 0
    ))
end

local function UpdatePauseDebugTracing()
    local state = GetPauseDebugState()
    local signature = GetPauseDebugSignature(state)
    if signature ~= (M.overlayPauseDebugSignature or "") then
        M.overlayPauseDebugSignature = signature
        LogPauseDebugState("transition", state)
    end

    if exu and exu.GetGameKey then
        local dumpDown = exu.GetGameKey("F10") and true or false
        if dumpDown and not M.overlayPauseDebugDumpLatch then
            LogPauseDebugState("manual-f10", state)
        end
        M.overlayPauseDebugDumpLatch = dumpDown
    end
end

local function BuildOverlayDemoLayout()
    local textureMaterial = M.overlayDemoTextureMaterial
    local materialName = textureMaterial or "solid fallback"
    local theme = { r = 0.18, g = 0.92, b = 0.18 }
    local pale = { r = 0.86, g = 1.00, b = 0.86 }
    local rootWidth = 628
    local bodyCharHeight = 15
    local swatchCharHeight = 12
    local footerCharHeight = 12
    local titleCharHeight = 20
    local bodyX, bodyY, bodyWidth = 22, 60, 382
    local swatchFrameX, swatchFrameY, swatchFrameWidth = 424, 18, 184
    local swatchInset = 8
    local swatchWidth = swatchFrameWidth - (swatchInset * 2)
    local swatchHeight = 88
    local swatchTextWidth = swatchWidth

    local bodyRaw = table.concat({
        "PAGE   [STATS] TARGET SETTINGS PRESETS QUEUE COMMAND",
        "MODE   OGRE OVERLAY HUD PROTOTYPE",
        "STATE  WRAP + AUTO SIZE + SAFE CLAMP",
        "QUEUE  GAMEPLAY HUD ONLY",
        string.format("CLOCK  %.1fs   DIFF %s", GetTime(), tostring(M.difficulty or "?")),
        "GOAL   PDA + SUBTITLE MIGRATION TARGET",
    }, "\n")
    local swatchRaw
    if textureMaterial then
        swatchRaw = table.concat({
            "SENSOR FEED",
            materialName,
            "UV CROP",
        }, "\n")
    else
        swatchRaw = table.concat({
            "SENSOR FEED",
            "TEXTURE OFFLINE",
            "SOLID",
        }, "\n")
    end
    local footerRaw = "F9 TOGGLE DEMO   |   F10 DUMP UI STATE   |   TARGET PDA / SUBTITLES"

    local bodyText = WrapOverlayTextToPixels(bodyRaw, bodyWidth, bodyCharHeight, 1.18, 0)
    local swatchText = WrapOverlayTextToPixels(swatchRaw, swatchTextWidth, swatchCharHeight, 1.16, 0)
    local footerText = WrapOverlayTextToPixels(footerRaw, rootWidth - 44, footerCharHeight, 1.12, 0)

    local bodyHeight = math.max(132, GetOverlayTextBlockHeight(bodyCharHeight, CountOverlayLines(bodyText), 1.28))
    local swatchTextHeight = GetOverlayTextBlockHeight(swatchCharHeight, CountOverlayLines(swatchText), 1.22)
    local swatchFrameHeight = swatchInset + swatchHeight + 12 + swatchTextHeight + swatchInset
    local stripY = math.max(bodyY + bodyHeight, swatchFrameY + swatchFrameHeight) + 14
    local footerHeight = GetOverlayTextBlockHeight(footerCharHeight, CountOverlayLines(footerText), 1.20)
    local footerY = stripY + 18
    local rootHeight = footerY + footerHeight + 18
    local rootX, rootY = GetOverlayDemoRootPosition(rootWidth, rootHeight)

    return {
        materialName = materialName,
        textureMaterial = textureMaterial,
        theme = theme,
        pale = pale,
        rootX = rootX,
        rootY = rootY,
        rootWidth = rootWidth,
        rootHeight = rootHeight,
        titleText = "BATTLEZONE PDA",
        titleX = 22,
        titleY = 14,
        titleWidth = rootWidth - 44,
        titleHeight = 24,
        titleCharHeight = titleCharHeight,
        headerX = 12,
        headerY = 12,
        headerWidth = rootWidth - 24,
        headerHeight = 30,
        bodyText = bodyText,
        bodyX = bodyX,
        bodyY = bodyY,
        bodyWidth = bodyWidth,
        bodyHeight = bodyHeight,
        bodyCharHeight = bodyCharHeight,
        swatchFrameX = swatchFrameX,
        swatchFrameY = swatchFrameY,
        swatchFrameWidth = swatchFrameWidth,
        swatchFrameHeight = swatchFrameHeight,
        swatchX = swatchInset,
        swatchY = swatchInset,
        swatchWidth = swatchWidth,
        swatchHeight = swatchHeight,
        swatchText = swatchText,
        swatchTextX = swatchInset,
        swatchTextY = swatchInset + swatchHeight + 10,
        swatchTextWidth = swatchTextWidth,
        swatchTextHeight = swatchTextHeight,
        swatchCharHeight = swatchCharHeight,
        stripX = 20,
        stripY = stripY,
        stripWidth = rootWidth - 40,
        stripHeight = 12,
        footerText = footerText,
        footerX = 22,
        footerY = footerY,
        footerWidth = rootWidth - 44,
        footerHeight = footerHeight,
        footerCharHeight = footerCharHeight,
    }
end

local function RefreshOverlayDemoCaptions()
    if not (M.overlayDemoReady and exu and exu.SetOverlayCaption) then
        return
    end

    local ids = OVERLAY_DEMO_IDS
    local layout = BuildOverlayDemoLayout()

    exu.SetOverlayPosition(ids.root, layout.rootX, layout.rootY)
    exu.SetOverlayDimensions(ids.root, layout.rootWidth, layout.rootHeight)

    exu.SetOverlayDimensions(ids.backdrop, layout.rootWidth - 8, layout.rootHeight - 8)

    exu.SetOverlayPosition(ids.header, layout.headerX, layout.headerY)
    exu.SetOverlayDimensions(ids.header, layout.headerWidth, layout.headerHeight)

    exu.SetOverlayPosition(ids.title, layout.titleX, layout.titleY)
    exu.SetOverlayDimensions(ids.title, layout.titleWidth, layout.titleHeight)
    exu.SetOverlayCaption(ids.title, layout.titleText)

    exu.SetOverlayPosition(ids.body, layout.bodyX, layout.bodyY)
    exu.SetOverlayDimensions(ids.body, layout.bodyWidth, layout.bodyHeight)
    exu.SetOverlayCaption(ids.body, layout.bodyText)

    exu.SetOverlayPosition(ids.swatchFrame, layout.swatchFrameX, layout.swatchFrameY)
    exu.SetOverlayDimensions(ids.swatchFrame, layout.swatchFrameWidth, layout.swatchFrameHeight)

    exu.SetOverlayPosition(ids.swatch, layout.swatchX, layout.swatchY)
    exu.SetOverlayDimensions(ids.swatch, layout.swatchWidth, layout.swatchHeight)

    exu.SetOverlayPosition(ids.swatchText, layout.swatchTextX, layout.swatchTextY)
    exu.SetOverlayDimensions(ids.swatchText, layout.swatchTextWidth, layout.swatchTextHeight)
    exu.SetOverlayCaption(ids.swatchText, layout.swatchText)

    exu.SetOverlayPosition(ids.strip, layout.stripX, layout.stripY)
    exu.SetOverlayDimensions(ids.strip, layout.stripWidth, layout.stripHeight)

    exu.SetOverlayPosition(ids.footer, layout.footerX, layout.footerY)
    exu.SetOverlayDimensions(ids.footer, layout.footerWidth, layout.footerHeight)
    exu.SetOverlayCaption(ids.footer, layout.footerText)
end

local function TryCreateOverlayDemo()
    if M.overlayDemoReady then
        return true
    end

    local requiredApi = {
        "CreateOverlay",
        "CreateOverlayElement",
        "AddOverlay2D",
        "AddOverlayElementChild",
        "SetOverlayMetricsMode",
        "SetOverlayPosition",
        "SetOverlayDimensions",
        "SetOverlayMaterial",
        "SetOverlayColor",
        "SetOverlayCaption",
        "SetOverlayTextCharHeight",
        "SetOverlayTextColor",
        "SetOverlayTextFont",
        "SetOverlayParameter",
        "SetOverlayZOrder",
        "ShowOverlay",
        "HideOverlay",
    }
    local missingApi = {}
    if type(exu) ~= "table" then
        missingApi[#missingApi + 1] = "exu"
    else
        for _, apiName in ipairs(requiredApi) do
            if type(exu[apiName]) ~= "function" then
                missingApi[#missingApi + 1] = apiName
            end
        end
    end

    if #missingApi > 0 then
        print("misn04: overlay demo unavailable; missing EXU API = " .. table.concat(missingApi, ", "))
        return false
    end

    DestroyOverlayDemo()

    local ids = OVERLAY_DEMO_IDS
    local metricsMode = (exu.OVERLAY_METRICS and exu.OVERLAY_METRICS.PIXELS) or 1
    local fontName = (PersistentConfig and PersistentConfig.ExperimentalOverlayFont) or "CRBZoneOverlayFont"
    local textureMaterial = GetOverlayDemoTextureMaterial()
    local ok = true

    local function MustCall(fn, ...)
        if not ok then
            return false
        end

        local success = OverlayCall(fn, ...)
        if not success then
            ok = false
            return false
        end
        return true
    end

    local function OptionalCall(fn, ...)
        if not ok then
            return false
        end

        local success = OverlayCall(fn, ...)
        return success
    end

    MustCall(exu.CreateOverlay, ids.overlay)
    MustCall(exu.CreateOverlayElement, "BorderPanel", ids.root)
    MustCall(exu.CreateOverlayElement, "Panel", ids.backdrop)
    MustCall(exu.CreateOverlayElement, "Panel", ids.header)
    MustCall(exu.CreateOverlayElement, "TextArea", ids.title)
    MustCall(exu.CreateOverlayElement, "TextArea", ids.body)
    MustCall(exu.CreateOverlayElement, "BorderPanel", ids.swatchFrame)
    MustCall(exu.CreateOverlayElement, "Panel", ids.swatch)
    MustCall(exu.CreateOverlayElement, "Panel", ids.strip)
    MustCall(exu.CreateOverlayElement, "TextArea", ids.swatchText)
    MustCall(exu.CreateOverlayElement, "TextArea", ids.footer)

    MustCall(exu.AddOverlay2D, ids.overlay, ids.root)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.backdrop)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.header)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.title)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.body)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.swatchFrame)
    MustCall(exu.AddOverlayElementChild, ids.swatchFrame, ids.swatch)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.strip)
    MustCall(exu.AddOverlayElementChild, ids.swatchFrame, ids.swatchText)
    MustCall(exu.AddOverlayElementChild, ids.root, ids.footer)
    MustCall(exu.SetOverlayZOrder, ids.overlay, 642)

    local elementNames = {
        ids.root, ids.backdrop, ids.header, ids.title, ids.body, ids.swatchFrame,
        ids.swatch, ids.strip, ids.swatchText, ids.footer,
    }
    for _, elementName in ipairs(elementNames) do
        MustCall(exu.SetOverlayMetricsMode, elementName, metricsMode)
    end

    M.overlayDemoTextureMaterial = textureMaterial
    local layout = BuildOverlayDemoLayout()

    MustCall(exu.SetOverlayPosition, ids.root, layout.rootX, layout.rootY)
    MustCall(exu.SetOverlayDimensions, ids.root, layout.rootWidth, layout.rootHeight)
    MustCall(exu.SetOverlayColor, ids.root, 0.82, 1.00, 0.82, 0.98)
    MustCall(exu.SetOverlayParameter, ids.root, "transparent", true)
    MustCall(exu.SetOverlayParameter, ids.root, "border_material", OVERLAY_DEMO_SOLID_MATERIAL)
    MustCall(exu.SetOverlayParameter, ids.root, "border_size", "2 2 2 2")

    MustCall(exu.SetOverlayPosition, ids.backdrop, 4, 4)
    MustCall(exu.SetOverlayDimensions, ids.backdrop, layout.rootWidth - 8, layout.rootHeight - 8)
    MustCall(exu.SetOverlayColor, ids.backdrop, 0.01, 0.06, 0.02, 0.86)

    MustCall(exu.SetOverlayPosition, ids.header, layout.headerX, layout.headerY)
    MustCall(exu.SetOverlayDimensions, ids.header, layout.headerWidth, layout.headerHeight)
    if textureMaterial then
        MustCall(exu.SetOverlayMaterial, ids.header, textureMaterial)
    end
    MustCall(exu.SetOverlayColor, ids.header, 0.06, 0.24, 0.08, 0.76)
    if textureMaterial then
        MustCall(exu.SetOverlayParameter, ids.header, "uv_coords", "0.02 0.05 0.94 0.22")
    end

    MustCall(exu.SetOverlayPosition, ids.title, layout.titleX, layout.titleY)
    MustCall(exu.SetOverlayDimensions, ids.title, layout.titleWidth, layout.titleHeight)
    MustCall(exu.SetOverlayTextCharHeight, ids.title, layout.titleCharHeight)
    OptionalCall(exu.SetOverlayTextFont, ids.title, fontName)
    MustCall(exu.SetOverlayParameter, ids.title, "alignment", "left")
    MustCall(exu.SetOverlayParameter, ids.title, "colour_top", "0.94 1.0 0.94 1.0")
    MustCall(exu.SetOverlayParameter, ids.title, "colour_bottom", "0.52 1.0 0.52 1.0")

    MustCall(exu.SetOverlayPosition, ids.body, layout.bodyX, layout.bodyY)
    MustCall(exu.SetOverlayDimensions, ids.body, layout.bodyWidth, layout.bodyHeight)
    MustCall(exu.SetOverlayTextCharHeight, ids.body, layout.bodyCharHeight)
    OptionalCall(exu.SetOverlayTextFont, ids.body, fontName)
    MustCall(exu.SetOverlayParameter, ids.body, "alignment", "left")
    MustCall(exu.SetOverlayTextColor, ids.body, 0.88, 1.00, 0.88, 1.0)

    MustCall(exu.SetOverlayPosition, ids.swatchFrame, layout.swatchFrameX, layout.swatchFrameY)
    MustCall(exu.SetOverlayDimensions, ids.swatchFrame, layout.swatchFrameWidth, layout.swatchFrameHeight)
    MustCall(exu.SetOverlayColor, ids.swatchFrame, 0.74, 1.00, 0.74, 0.94)
    MustCall(exu.SetOverlayParameter, ids.swatchFrame, "transparent", true)
    MustCall(exu.SetOverlayParameter, ids.swatchFrame, "border_material", OVERLAY_DEMO_SOLID_MATERIAL)
    MustCall(exu.SetOverlayParameter, ids.swatchFrame, "border_size", "2 2 2 2")

    MustCall(exu.SetOverlayPosition, ids.swatch, layout.swatchX, layout.swatchY)
    MustCall(exu.SetOverlayDimensions, ids.swatch, layout.swatchWidth, layout.swatchHeight)
    if textureMaterial then
        MustCall(exu.SetOverlayMaterial, ids.swatch, textureMaterial)
    end
    MustCall(exu.SetOverlayColor, ids.swatch, 0.18, 0.72, 0.22, 0.82)
    if textureMaterial then
        MustCall(exu.SetOverlayParameter, ids.swatch, "uv_coords", "0.12 0.06 0.88 0.54")
    end

    MustCall(exu.SetOverlayPosition, ids.swatchText, layout.swatchTextX, layout.swatchTextY)
    MustCall(exu.SetOverlayDimensions, ids.swatchText, layout.swatchTextWidth, layout.swatchTextHeight)
    MustCall(exu.SetOverlayTextCharHeight, ids.swatchText, layout.swatchCharHeight)
    OptionalCall(exu.SetOverlayTextFont, ids.swatchText, fontName)
    MustCall(exu.SetOverlayParameter, ids.swatchText, "alignment", "center")
    MustCall(exu.SetOverlayParameter, ids.swatchText, "colour_top", "0.92 1.0 0.92 1.0")
    MustCall(exu.SetOverlayParameter, ids.swatchText, "colour_bottom", "0.50 1.0 0.50 1.0")

    MustCall(exu.SetOverlayPosition, ids.strip, layout.stripX, layout.stripY)
    MustCall(exu.SetOverlayDimensions, ids.strip, layout.stripWidth, layout.stripHeight)
    if textureMaterial then
        MustCall(exu.SetOverlayMaterial, ids.strip, textureMaterial)
    end
    MustCall(exu.SetOverlayColor, ids.strip, 0.24, 0.94, 0.28, 0.52)
    if textureMaterial then
        MustCall(exu.SetOverlayParameter, ids.strip, "tiling", "0 7 1")
        MustCall(exu.SetOverlayParameter, ids.strip, "uv_coords", "0.00 0.00 1.00 0.12")
    end

    MustCall(exu.SetOverlayPosition, ids.footer, layout.footerX, layout.footerY)
    MustCall(exu.SetOverlayDimensions, ids.footer, layout.footerWidth, layout.footerHeight)
    MustCall(exu.SetOverlayTextCharHeight, ids.footer, layout.footerCharHeight)
    OptionalCall(exu.SetOverlayTextFont, ids.footer, fontName)
    MustCall(exu.SetOverlayParameter, ids.footer, "alignment", "left")
    MustCall(exu.SetOverlayParameter, ids.footer, "colour_top", "0.86 1.0 0.86 1.0")
    MustCall(exu.SetOverlayParameter, ids.footer, "colour_bottom", "0.42 0.92 0.42 1.0")

    if not ok then
        DestroyOverlayDemo()
        return false
    end

    M.overlayDemoReady = true
    M.overlayDemoVisible = false
    M.overlayDemoStatusNextAt = 0.0
    RefreshOverlayDemoCaptions()
    SetOverlayDemoVisible(false)
    return true
end

local function UpdateOverlayDemo()
    UpdatePauseDebugTracing()

    local suppressOverlay = false
    if exu and exu.IsPauseMenuOpen then
        local ok, pauseOpen = pcall(exu.IsPauseMenuOpen)
        if ok and pauseOpen then
            suppressOverlay = true
        end
    end
    if not suppressOverlay and exu and exu.GetViewportOverlaysEnabled then
        local ok, overlaysEnabled = pcall(exu.GetViewportOverlaysEnabled)
        if ok and overlaysEnabled == false then
            suppressOverlay = true
        end
    end

    if suppressOverlay then
        if M.overlayDemoVisible then
            M.overlayDemoResumeAfterSuppression = true
            M.overlayDemoResumeDuration = math.max((tonumber(M.overlayDemoAutoHideAt) or GetTime()) - GetTime(), 0.5)
            SetOverlayDemoVisible(false)
        end
        M.overlayDemoSuppressed = true
        return
    end

    if M.overlayDemoSuppressed then
        M.overlayDemoSuppressed = false
        if M.overlayDemoResumeAfterSuppression then
            SetOverlayDemoVisible(true, math.max(tonumber(M.overlayDemoResumeDuration) or 5.0, 0.5))
        end
        M.overlayDemoResumeAfterSuppression = false
        M.overlayDemoResumeDuration = 0.0
    end

    if exu and exu.GetGameKey then
        local toggleDown = exu.GetGameKey("F9") and true or false
        if toggleDown and not M.overlayDemoToggleLatch then
            if TryCreateOverlayDemo() then
                SetOverlayDemoVisible(not M.overlayDemoVisible, 20.0)
            end
        end
        M.overlayDemoToggleLatch = toggleDown
    end

    if M.overlayDemoReady and GetTime() >= (tonumber(M.overlayDemoStatusNextAt) or 0.0) then
        RefreshOverlayDemoCaptions()
        M.overlayDemoStatusNextAt = GetTime() + 0.25
    end

    if M.overlayDemoVisible and tonumber(M.overlayDemoAutoHideAt) and GetTime() >= M.overlayDemoAutoHideAt then
        SetOverlayDemoVisible(false)
    end
end

local function RunOverlayBootTest()
    if M.overlayBootTestDone then
        return
    end

    M.overlayBootTestDone = true
    if M.overlayDemoReady then
        SetOverlayDemoVisible(false)
        DestroyOverlayDemo()
    end
end

-- Helper for Difficulty-Scaled Tug Arrival
local function GetTugDelay()
    local baseDelay = 180.0 -- Medium (Default)
    if M.difficulty >= 4 then
        return 0.0          -- Very Hard: Immediate
    elseif M.difficulty == 3 then
        baseDelay = 60.0    -- Hard
    elseif M.difficulty == 1 then
        baseDelay = 300.0   -- Easy
    elseif M.difficulty == 0 then
        baseDelay = 450.0   -- Very Easy
    end
    return DiffUtils.ScaleTimer(baseDelay)
end

-- Helper for Difficulty-Scaled Tug Retry
local function GetTugRetryDelay()
    local baseDelay = 120.0 -- Medium (Default)
    if M.difficulty >= 4 then
        baseDelay = 45.0    -- Very Hard
    elseif M.difficulty == 3 then
        baseDelay = 75.0    -- Hard
    elseif M.difficulty == 1 then
        baseDelay = 180.0   -- Easy
    elseif M.difficulty == 0 then
        baseDelay = 240.0   -- Very Easy
    end
    return DiffUtils.ScaleTimer(baseDelay)
end

function Start()
    DestroyOverlayDemo()
    M = NewMissionState()
    M.TPS = M.TPS or DEFAULT_TPS

    -- One-time initialization logic
    M.relicstartpos = math.random(0, 3)

    SetScrap(1, DiffUtils.ScaleRes(40))
    SetPilot(1, 10)
    RefreshDifficulty()
    ApplyDifficultyObjectives()
    ApplyQOL()
    SetupAI()
    aiCore.Bootstrap()
    ApplyTurboToAll()
    PlayerPilotMode.Initialize({
        profile = {
            autoManage = true,
            autoRescue = true,
            stickToPlayer = true,
            manageFactories = true,
            autoBuild = true,
            autoTugs = false,
        },
        shouldManageHandle = PilotModeCanManageHandle,
    })
    if Environment and Environment.Update then
        Environment.Update(0.0)
    end
    M.overlayBootTestAt = GetTime() + 1.0
    M.loading_done = true
end

-- Save/Load removed from here, moving logic to bottom functions

function AddObject(h)
    local team = GetTeamNum(h)
    local nearBase = false

    -- Filter logic for AI
    if team == 2 then
        -- Only add if near base
        if M.svrec and IsAlive(M.svrec) and GetDistance(h, M.svrec) < 400.0 then
            nearBase = true
        elseif GetDistance(h, "cca_base") < 400.0 then
            nearBase = true
        end

        if nearBase then
            aiCore.AddObject(h)
        end
    elseif team == 1 then
        PlayerPilotMode.AddObject(h)
    end

    if PersistentConfig and PersistentConfig.OnObjectCreated then
        PersistentConfig.OnObjectCreated(h)
    end
    if Environment and Environment.OnObjectCreated then
        Environment.OnObjectCreated(h)
    end
    ApplyTurbo(h)

    -- Capture Player Tug for Audio (Corrected to avhaul per C++)
    if team == 1 and IsOdf(h, "avhaul") then
        M.found = true
        M.tug = h
    end
end

function DeleteObject(h)
    -- No specific logic in C++, just standard.
end

local function AudioDone(msg)
    return (not msg) or IsAudioMessageDone(msg)
end

local function StopAudio(msg)
    if msg then StopAudioMessage(msg) end
end

local function GetRelicVariantIndex()
    local idx = (M.relicstartpos or 0) + 1
    if idx < 1 then idx = 1 end
    if idx > 4 then idx = 4 end
    return idx
end

local function GetRelicStartPath()
    return "relicstart" .. tostring(GetRelicVariantIndex())
end

local function GetRelicPatrolPaths()
    local idx = tostring(GetRelicVariantIndex())
    return "relicpatrolpath" .. idx .. "a", "relicpatrolpath" .. idx .. "b"
end

local function GetRelicCamSpawn()
    return "reliccam" .. tostring(GetRelicVariantIndex())
end

local function GetRelicCinemaPath()
    return "reliccin" .. tostring(GetRelicVariantIndex())
end

local function SpawnNear(spawn, minRadius, maxRadius)
    local center = GetPosition(spawn)
    return GetPositionNear(center, minRadius, maxRadius) or center
end

local function RetreatIfAlive(h, path)
    if h and IsAlive(h) then
        Retreat(h, path, GetTeamNum(h) == 1 and 0 or 1)
    end
end

function Update()
    if GetTime() < (M.loadGracePeriod or 0) then
        return
    end
    if not M.loading_done then
        RefreshMissionHandles()
        RefreshDifficulty()
        ApplyDifficultyObjectives()
        ApplyQOL()
        PlayerPilotMode.Initialize({
            profile = {
                autoManage = true,
                autoRescue = true,
                stickToPlayer = true,
                manageFactories = true,
                autoBuild = true,
                autoTugs = false,
            },
            shouldManageHandle = PilotModeCanManageHandle,
        })
        SetupAI()
        aiCore.Bootstrap()
        ApplyTurboToAll()
        if Environment and Environment.Update then
            Environment.Update(0.0)
        end
        M.loading_done = true
    end
    M.player = GetPlayerHandle()
    PlayerPilotMode.SetCargoJob("misn04_relic", {
        enabled = M.discoverrelic and not M.relicsecure,
        target = M.relic,
        dropoff = M.avrec,
        preferredCarrier = M.tug,
        autoProduceTug = true,
        reissueInterval = 0.75,
        dropoffRadius = 85.0,
        tugBuildRetryDelay = 10.0,
        tugBuildSuccessDelay = 25.0,
    })
    PlayerPilotMode.Update()
    aiCore.Update()
    if autosave and autosave.Update then
        autosave.Update(1.0 / M.TPS)
    end
    UpdateModules(1.0 / M.TPS)
    RunOverlayBootTest()
    UpdateOverlayDemo()

    if (not M.missionstart) then
        M.wave1 = GetTime() + DiffUtils.ScaleTimer(30.0) + math.random(-5, 10)
        M.fetch = GetTime() + DiffUtils.ScaleTimer(240.0)
        subtit.Play("misn0401.wav")
        RefreshMissionHandles()
        M.relic = BuildObject("obdata", 0, SpawnNear("relicstart1", 0, 10))
        M.pu1 = GetHandle("svfigh-1_wingman")
        -- pu2 commented out in C++
        M.pu3 = GetHandle("svfigh282_wingman")
        -- pu4, pu5 commented out
        M.pu6 = GetHandle("svfigh279_wingman")
        -- pu7 commented out
        M.pu8 = GetHandle("svfigh278_wingman")

        Patrol(M.pu1, "innerpatrol", 0)
        Patrol(M.pu3, "innerpatrol", 0)
        Patrol(M.pu6, "outerpatrol", 0)
        Patrol(M.pu8, "outerpatrol", 0)

        AddObjective("misn0401.otf", "white")
        AddObjective("misn0400.otf", "white")

        M.missionstart = true
        M.cheater = false
        M.tur1 = GetTime() + 30.0
        M.tur2 = GetTime() + 45.0
        M.tur3 = GetTime() + 60.0
        M.tur4 = GetTime() + 75.0
        M.investigate = GetTime() + 3.0
    end

    if M.cam1 and IsAlive(M.cam1) then AddHealth(M.cam1, 1000) end
    if M.cam2 and IsAlive(M.cam2) then AddHealth(M.cam2, 1000) end
    if M.cam3 and IsAlive(M.cam3) then AddHealth(M.cam3, 1000) end

    if M.relic and IsAlive(M.relic) and not M.relicmoved then
        SetPosition(M.relic, GetRelicStartPath())
        M.relicmoved = true
    end

    if not M.reconsent and not M.cheater and IsAlive(M.player) and IsAlive(M.relic) and GetDistance(M.player, M.relic) < 600.0 then
        local pathA, pathB = GetRelicPatrolPaths()
        M.cheat1 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        M.cheat2 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        M.cheat3 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        M.cheat4 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        M.cheat5 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        M.cheat6 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))

        Patrol(M.cheat1, pathA); SetIndependence(M.cheat1, 1)
        Patrol(M.cheat2, pathA); SetIndependence(M.cheat2, 1)
        Patrol(M.cheat3, pathA); SetIndependence(M.cheat3, 1)
        Patrol(M.cheat4, pathB); SetIndependence(M.cheat4, 1)
        Patrol(M.cheat5, pathB); SetIndependence(M.cheat5, 1)
        Patrol(M.cheat6, pathB); SetIndependence(M.cheat6, 1)

        M.surveysent = true
        M.cheater = true
        M.reconcca = GetTime()
    end

    if M.fetch < GetTime() and not M.surveysent and IsAlive(M.relic) then
        local pathA, pathB = GetRelicPatrolPaths()
        M.surv1 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        M.surv2 = BuildObject("svfigh", 2, SpawnNear(M.relic, 5, 40))
        Patrol(M.surv1, pathA); SetIndependence(M.surv1, 1)
        Patrol(M.surv2, pathB); SetIndependence(M.surv2, 1)
        M.surveysent = true
        M.reconcca = GetTime() + 60.0
    end

    if not M.tur1sent and M.tur1 < GetTime() and IsAlive(M.svrec) then
        M.turret1 = BuildObject("svturr", 2, SpawnNear(M.svrec, 5, 25))
        Goto(M.turret1, "turret1")
        M.tur1sent = true
    end
    if not M.tur2sent and M.tur2 < GetTime() and IsAlive(M.svrec) then
        M.turret2 = BuildObject("svturr", 2, SpawnNear(M.svrec, 5, 25))
        Goto(M.turret2, "turret2")
        M.tur2sent = true
    end
    if not M.tur3sent and M.tur3 < GetTime() and IsAlive(M.svrec) then
        M.turret3 = BuildObject("svturr", 2, SpawnNear(M.svrec, 5, 25))
        Goto(M.turret3, "turret3")
        M.tur3sent = true
    end
    if not M.tur4sent and M.tur4 < GetTime() and IsAlive(M.svrec) then
        M.turret4 = BuildObject("svturr", 2, SpawnNear(M.svrec, 5, 25))
        Goto(M.turret4, "turret4")
        M.tur4sent = true
    end

    if M.reconcca < GetTime() and not M.reconsent and M.surveysent then
        M.aud4 = subtit.Play("misn0406.wav")
        M.reliccam = BuildObject("apcamr", 1, SpawnNear(GetRelicCamSpawn(), 0, 10))
        M.reconsent = true
        M.obset = true
        M.notfound = GetTime() + 90.0
    end

    if M.obset and AudioDone(M.aud4) and IsAlive(M.reliccam) then
        SetObjectiveName(M.reliccam, "Investigate CCA")
        SetObjectiveOn(M.reliccam)
        M.newobjective = true
        M.obset = false
    end

    if M.found and not M.halfway and M.tug and IsAlive(M.tug) and HasCargo(M.tug) then
        subtit.Play("misn0419.wav")
        M.halfway = true
        if M.relic and IsAlive(M.relic) then
            SetObjectiveOff(M.relic)
        end
        SetObjectiveOn(M.tug)
        M.tugobjective = true
        if M.tuge1 and IsAlive(M.tuge1) then Attack(M.tuge1, M.tug) end
        if M.tuge2 and IsAlive(M.tuge2) then Attack(M.tuge2, M.tug) end
    end

    if M.tugobjective and not M.relicsecure and (not (M.tug and IsAlive(M.tug))) then
        if M.relic and IsAlive(M.relic) then
            SetObjectiveOn(M.relic)
        end
        if M.tug then
            SetObjectiveOff(M.tug)
        end
        M.tugobjective = false
    end

    if M.reconsent and IsAlive(M.relic) and IsAlive(M.avrec) and GetDistance(M.relic, M.avrec) < 100.0 and not M.relicsecure then
        M.aud23 = subtit.Play("misn0420.wav")
        M.relicsecure = true
        M.newobjective = true
    end

    if M.ccatug < GetTime() and not M.ccatugsent and IsAlive(M.svrec) and IsAlive(M.relic) and not M.relicsecure then
        M.svtug = BuildObject("svhaul", 2, SpawnNear(M.svrec, 5, 40))
        M.tuge1 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
        M.tuge2 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
        Pickup(M.svtug, M.relic)
        Follow(M.tuge1, M.svtug)
        Follow(M.tuge2, M.svtug)
        M.ccatugsent = true
        M.ccatugretry = false
    end

    if M.ccatugsent and not M.ccahasrelic and IsAlive(M.svtug) then
        local playerHasRelic = M.tug and IsAlive(M.tug) and HasCargo(M.tug)
        if HasCargo(M.svtug) and not playerHasRelic then
            M.ccahasrelic = true
            Goto(M.svtug, "dropoff")
            subtit.Play("misn0427.wav")
            SetObjectiveOn(M.svtug)
            SetObjectiveName(M.svtug, "CCA Tug")
        end
    end

    if M.ccatugsent and not M.ccahasrelic and not M.relicsecure and IsAlive(M.svrec) and IsAlive(M.relic) then
        if not (M.svtug and IsAlive(M.svtug)) and not M.ccatugretry then
            M.ccatug = GetTime() + GetTugRetryDelay()
            M.ccatugsent = false
            M.ccatugretry = true
        end
    end

    if M.ccahasrelic and IsAlive(M.svtug) and GetDistance(M.svtug, M.svrec) < 60.0 and not M.missionfail2 then
        M.aud10 = subtit.Play("misn0431.wav")
        M.aud11 = subtit.Queue("misn0432.wav")
        M.aud12 = subtit.Queue("misn0433.wav")
        M.aud13 = subtit.Queue("misn0434.wav")
        M.missionfail2 = true
        CameraReady()
    end

    if M.missionfail2 and not M.done then
        CameraPath("ccareliccam", 3000, 1000, M.svtug)
        if (AudioDone(M.aud10) and AudioDone(M.aud11) and AudioDone(M.aud12) and AudioDone(M.aud13)) or CameraCancelled() then
            CameraFinish()
            StopAudio(M.aud10)
            StopAudio(M.aud11)
            StopAudio(M.aud12)
            StopAudio(M.aud13)
            FailMission(GetTime(), "misn04l1.des")
            M.done = true
        end
    end

    if not M.discoverrelic and M.reconsent and M.notfound < GetTime() and not M.ccahasrelic and M.warn < 4 then
        subtit.Play("misn0429.wav")
        M.notfound = GetTime() + 85.0
        M.warn = M.warn + 1
    end

    if M.warn == 4 and M.notfound < GetTime() and not M.missionfail then
        M.aud14 = subtit.Play("misn0694.wav")
        M.missionfail = true
    end
    if M.missionfail and M.warn == 4 and AudioDone(M.aud14) then
        FailMission(GetTime(), "misn04l4.des")
        M.warn = 0
    end

    if not M.discoverrelic and M.investigate < GetTime() and IsAlive(M.relic) then
        M.investigator = CountUnitsNearObject(M.relic, 400.0, 1, nil)
        if M.reliccam and IsAlive(M.reliccam) then
            M.investigator = M.investigator - 1
        end
    end

    if not M.discoverrelic and M.investigator >= 1 then
        M.aud2 = subtit.Play("misn0408.wav")
        M.aud3 = subtit.Queue("misn0409.wav")
        M.relicseen = true
        M.newobjective = true
        M.ccatug = GetTime() + GetTugDelay()
        M.discoverrelic = true
        if M.reliccam and IsAlive(M.reliccam) then
            SetObjectiveOff(M.reliccam)
        end
        if M.relic and IsAlive(M.relic) then
            SetObjectiveOn(M.relic)
        end
        CameraReady()
        M.cintime1 = GetTime() + 23.0
    end

    if M.discoverrelic and not M.cin1done then
        if (AudioDone(M.aud2) and AudioDone(M.aud3)) or CameraCancelled() then
            CameraFinish()
            StopAudio(M.aud2)
            StopAudio(M.aud3)
            M.cin1done = true
        end
    end

    if M.discoverrelic and not M.cin1done and M.cintime1 > GetTime() and IsAlive(M.relic) then
        CameraPath(GetRelicCinemaPath(), 500, 400, M.relic)
    end

    if M.newobjective then
        ClearObjectives()
        AddObjective("misn0401.otf", M.basesecure and "green" or "white")

        if M.relicseen then
            AddObjective("misn0403.otf", M.relicsecure and "green" or "white")
        end

        if M.reconsent then
            AddObjective("misn0405.otf", M.discoverrelic and "green" or "white")
        end

        M.newobjective = false
    end

    if (not M.cheater) then
        -- Wave 1
        if M.wavenumber == 1 and M.wave1 < GetTime() then
            M.w1u1 = BuildObject("svfigh", 2, SpawnNear("wave1", 5, 40))
            M.w1u2 = BuildObject("svfigh", 2, SpawnNear("wave1", 5, 40))
            Attack(M.w1u1, M.avrec, 1); SetIndependence(M.w1u1, 1)
            Attack(M.w1u2, M.avrec, 1); SetIndependence(M.w1u2, 1)
            if M.difficulty >= 3 then
                M.w1u3 = BuildObject("svfigh", 2, SpawnNear("wave1", 5, 40))
                Attack(M.w1u3, M.avrec, 1); SetIndependence(M.w1u3, 1)
            end
            if M.difficulty >= 4 then
                M.w1u4 = BuildObject("svfigh", 2, SpawnNear("wave1", 5, 40))
                Attack(M.w1u4, M.avrec, 1); SetIndependence(M.w1u4, 1)
            end
            M.wavenumber = 2
            M.wave1arrive = false
        end
        if M.wavenumber == 2 and not M.wave1arrive and IsAlive(M.avrec) then
            if (M.w1u1 and IsAlive(M.w1u1) and GetDistance(M.avrec, M.w1u1) < 300) or
                (M.w1u2 and IsAlive(M.w1u2) and GetDistance(M.avrec, M.w1u2) < 300) or
                (M.w1u3 and IsAlive(M.w1u3) and GetDistance(M.avrec, M.w1u3) < 300) or
                (M.w1u4 and IsAlive(M.w1u4) and GetDistance(M.avrec, M.w1u4) < 300) then
                subtit.Play("misn0402.wav")
                M.wave1arrive = true
                M.wave1dead = true
            end
        end
        if M.wavenumber == 2 and not M.build2 and
            not (M.w1u1 and IsAlive(M.w1u1)) and
            not (M.w1u2 and IsAlive(M.w1u2)) and
            not (M.w1u3 and IsAlive(M.w1u3)) and
            not (M.w1u4 and IsAlive(M.w1u4)) then
            M.wave2 = GetTime() + DiffUtils.ScaleTimer(60.0)
            M.build2 = true
            M.wave1dead = true
        end

        -- Wave 2
        if M.wave2 < GetTime() and IsAlive(M.svrec) and not M.secondwave then
            M.w2u1 = BuildObject("svtank", 2, SpawnNear("spawn2new", 5, 40))
            M.w2u2 = BuildObject("svfigh", 2, SpawnNear("spawn2new", 5, 40))
            Goto(M.w2u1, M.avrec, 1); SetIndependence(M.w2u1, 1)
            Goto(M.w2u2, M.avrec, 1); SetIndependence(M.w2u2, 1)
            if M.difficulty >= 3 then -- Hard+: extra fighter
                M.w2u3 = BuildObject("svfigh", 2, SpawnNear("spawn2new", 5, 40))
                Goto(M.w2u3, M.avrec, 1); SetIndependence(M.w2u3, 1)
            end
            M.wavenumber = 3
            M.wave2arrive = false
            M.wave2 = 99999.0
            M.secondwave = true
        end
        if M.wavenumber == 3 and not M.wave2arrive and IsAlive(M.avrec) then
            if (M.w2u1 and IsAlive(M.w2u1) and GetDistance(M.avrec, M.w2u1) < 300) or
                (M.w2u2 and IsAlive(M.w2u2) and GetDistance(M.avrec, M.w2u2) < 300) or
                (M.w2u3 and IsAlive(M.w2u3) and GetDistance(M.avrec, M.w2u3) < 300) then
                subtit.Play("misn0404.wav")
                M.wave2arrive = true
            end
        end
        if M.wavenumber == 3 and not M.build3 then
            if (not (M.w2u1 and IsAlive(M.w2u1))) and
                (not (M.w2u2 and IsAlive(M.w2u2))) and
                (not (M.w2u3 and IsAlive(M.w2u3))) then
                M.wave3 = GetTime() + DiffUtils.ScaleTimer(74.0)
                M.build3 = true
                M.wave2dead = true
            end
        end

        -- Wave 3
        if M.wave3 < GetTime() and IsAlive(M.svrec) and not M.thirdwave then
            M.w3u1 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
            M.w3u2 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
            M.w3u3 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
            Goto(M.w3u1, M.avrec, 1); SetIndependence(M.w3u1, 1)
            Goto(M.w3u2, M.avrec, 1); SetIndependence(M.w3u2, 1)
            Goto(M.w3u3, M.avrec, 1); SetIndependence(M.w3u3, 1)
            if M.difficulty >= 3 then -- Hard+: extra tank
                M.w3u4 = BuildObject("svtank", 2, SpawnNear(M.svrec, 5, 40))
                Goto(M.w3u4, M.avrec, 1); SetIndependence(M.w3u4, 1)
            end
            M.wavenumber = 4
            M.wave3arrive = false
            M.wave3 = 99999.0
            M.thirdwave = true
        end
        if M.wavenumber == 4 and not M.wave3arrive and IsAlive(M.avrec) then
            if (M.w3u1 and IsAlive(M.w3u1) and GetDistance(M.avrec, M.w3u1) < 300) or
                (M.w3u2 and IsAlive(M.w3u2) and GetDistance(M.avrec, M.w3u2) < 300) or
                (M.w3u3 and IsAlive(M.w3u3) and GetDistance(M.avrec, M.w3u3) < 300) or
                (M.w3u4 and IsAlive(M.w3u4) and GetDistance(M.avrec, M.w3u4) < 300) then
                subtit.Play("misn0410.wav")
                M.wave3arrive = true
            end
        end
        if M.wavenumber == 4 and not M.build4 then
            if (not (M.w3u1 and IsAlive(M.w3u1))) and
                (not (M.w3u2 and IsAlive(M.w3u2))) and
                (not (M.w3u3 and IsAlive(M.w3u3))) and
                (not (M.w3u4 and IsAlive(M.w3u4))) then
                M.wave4 = GetTime() + DiffUtils.ScaleTimer(60.0)
                M.build4 = true
                M.wave3dead = true
            end
        end

        -- Wave 4
        if M.wave4 < GetTime() and IsAlive(M.svrec) and not M.fourthwave then
            M.w4u1 = BuildObject("svtank", 2, SpawnNear("spawnotherside", 5, 40))
            M.w4u2 = BuildObject("svfigh", 2, SpawnNear("spawnotherside", 5, 40))
            M.w4u3 = BuildObject("svfigh", 2, SpawnNear("spawnotherside", 5, 40))
            Goto(M.w4u1, M.avrec, 1); SetIndependence(M.w4u1, 1)
            Goto(M.w4u2, M.avrec, 1); SetIndependence(M.w4u2, 1)
            Goto(M.w4u3, M.avrec, 1); SetIndependence(M.w4u3, 1)
            if M.difficulty >= 3 then -- Hard+: extra tank
                M.w4u4 = BuildObject("svtank", 2, SpawnNear("spawnotherside", 5, 40))
                Goto(M.w4u4, M.avrec, 1); SetIndependence(M.w4u4, 1)
            end
            if M.difficulty >= 4 then -- Very Hard: extra fighter
                M.w4u5 = BuildObject("svfigh", 2, SpawnNear("spawnotherside", 5, 40))
                Goto(M.w4u5, M.avrec, 1); SetIndependence(M.w4u5, 1)
            end
            M.wavenumber = 5
            M.wave4arrive = false
            M.wave4 = 99999.0
            M.fourthwave = true
        end
        if M.wavenumber == 5 and not M.wave4arrive and IsAlive(M.avrec) then
            if (M.w4u1 and IsAlive(M.w4u1) and GetDistance(M.avrec, M.w4u1) < 300) or
                (M.w4u2 and IsAlive(M.w4u2) and GetDistance(M.avrec, M.w4u2) < 300) or
                (M.w4u3 and IsAlive(M.w4u3) and GetDistance(M.avrec, M.w4u3) < 300) or
                (M.w4u4 and IsAlive(M.w4u4) and GetDistance(M.avrec, M.w4u4) < 300) or
                (M.w4u5 and IsAlive(M.w4u5) and GetDistance(M.avrec, M.w4u5) < 300) then
                subtit.Play("misn0412.wav")
                M.wave4arrive = true
            end
        end
        if M.wavenumber == 5 and not M.build5 then
            if (not (M.w4u1 and IsAlive(M.w4u1))) and
                (not (M.w4u2 and IsAlive(M.w4u2))) and
                (not (M.w4u3 and IsAlive(M.w4u3))) and
                (not (M.w4u4 and IsAlive(M.w4u4))) and
                (not (M.w4u5 and IsAlive(M.w4u5))) then
                M.wave5 = GetTime() + DiffUtils.ScaleTimer(30.0)
                M.build5 = true
                M.wave4dead = true
            end
        end

        -- Wave 5
        if M.wave5 < GetTime() and IsAlive(M.svrec) and not M.fifthwave then
            M.w5u1 = BuildObject("svtank", 2, SpawnNear(M.svrec, 5, 40))
            M.w5u2 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
            M.w5u3 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
            M.w5u4 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
            Goto(M.w5u1, M.avrec, 1); SetIndependence(M.w5u1, 1)
            Goto(M.w5u2, M.avrec, 1); SetIndependence(M.w5u2, 1)
            Goto(M.w5u3, M.avrec, 1); SetIndependence(M.w5u3, 1)
            Goto(M.w5u4, M.avrec, 1); SetIndependence(M.w5u4, 1)
            if M.difficulty >= 3 then -- Hard+: extra tank
                M.w5u5 = BuildObject("svtank", 2, SpawnNear(M.svrec, 5, 40))
                Goto(M.w5u5, M.avrec, 1); SetIndependence(M.w5u5, 1)
            end
            if M.difficulty >= 4 then -- Very Hard: extra fighter
                M.w5u6 = BuildObject("svfigh", 2, SpawnNear(M.svrec, 5, 40))
                Goto(M.w5u6, M.avrec, 1); SetIndependence(M.w5u6, 1)
            end
            M.wavenumber = 6
            M.wave5arrive = false
            M.wave5 = 99999.0
            M.fifthwave = true
        end
        if M.wavenumber == 6 and not M.wave5arrive and IsAlive(M.avrec) then
            if (M.w5u1 and IsAlive(M.w5u1) and GetDistance(M.avrec, M.w5u1) < 300) or
                (M.w5u2 and IsAlive(M.w5u2) and GetDistance(M.avrec, M.w5u2) < 300) or
                (M.w5u3 and IsAlive(M.w5u3) and GetDistance(M.avrec, M.w5u3) < 300) or
                (M.w5u4 and IsAlive(M.w5u4) and GetDistance(M.avrec, M.w5u4) < 300) or
                (M.w5u5 and IsAlive(M.w5u5) and GetDistance(M.avrec, M.w5u5) < 300) or
                (M.w5u6 and IsAlive(M.w5u6) and GetDistance(M.avrec, M.w5u6) < 300) then
                subtit.Play("misn0414.wav")
                M.wave5arrive = true
            end
        end
        if M.wavenumber == 6 and not M.wave5dead then
            if (not (M.w5u1 and IsAlive(M.w5u1))) and
                (not (M.w5u2 and IsAlive(M.w5u2))) and
                (not (M.w5u3 and IsAlive(M.w5u3))) and
                (not (M.w5u4 and IsAlive(M.w5u4))) and
                (not (M.w5u5 and IsAlive(M.w5u5))) and
                (not (M.w5u6 and IsAlive(M.w5u6))) then
                M.wave5dead = true
            end
        end
    end

    if not M.attackccabase and IsAlive(M.player) and IsAlive(M.svrec) and GetDistance(M.player, M.svrec) < 300.0 then
        subtit.Play("misn0423.wav")
        M.attackccabase = true
    end

    if M.wave1dead and
        not (M.w1u1 and IsAlive(M.w1u1)) and
        not (M.w1u2 and IsAlive(M.w1u2)) and
        not (M.w1u3 and IsAlive(M.w1u3)) and
        not (M.w1u4 and IsAlive(M.w1u4)) then
        subtit.Play("misn0403.wav")
        M.wave1dead = false
    end
    if M.wave2dead then
        subtit.Play("misn0405.wav")
        M.wave2dead = false
    end
    if M.wave3dead then
        subtit.Play("misn0411.wav")
        M.wave3dead = false
    end
    if M.wave4dead then
        subtit.Play("misn0413.wav")
        M.wave4dead = false
    end

    local allWavesDead = not (M.w1u1 and IsAlive(M.w1u1)) and
        not (M.w1u2 and IsAlive(M.w1u2)) and
        not (M.w1u3 and IsAlive(M.w1u3)) and
        not (M.w1u4 and IsAlive(M.w1u4)) and
        not (M.w2u1 and IsAlive(M.w2u1)) and
        not (M.w2u2 and IsAlive(M.w2u2)) and
        not (M.w2u3 and IsAlive(M.w2u3)) and
        not (M.w3u1 and IsAlive(M.w3u1)) and
        not (M.w3u2 and IsAlive(M.w3u2)) and
        not (M.w3u3 and IsAlive(M.w3u3)) and
        not (M.w3u4 and IsAlive(M.w3u4)) and
        not (M.w4u1 and IsAlive(M.w4u1)) and
        not (M.w4u2 and IsAlive(M.w4u2)) and
        not (M.w4u3 and IsAlive(M.w4u3)) and
        not (M.w4u4 and IsAlive(M.w4u4)) and
        not (M.w4u5 and IsAlive(M.w4u5)) and
        not (M.w5u1 and IsAlive(M.w5u1)) and
        not (M.w5u2 and IsAlive(M.w5u2)) and
        not (M.w5u3 and IsAlive(M.w5u3)) and
        not (M.w5u4 and IsAlive(M.w5u4)) and
        not (M.w5u5 and IsAlive(M.w5u5)) and
        not (M.w5u6 and IsAlive(M.w5u6))

    if not M.loopbreak and not M.possiblewin and not M.missionwon and not IsAlive(M.svrec) then
        subtit.Play("misn0417.wav")
        M.possiblewin = true
        M.chewedout = true
        if not allWavesDead then
            subtit.Play("misn0418.wav")
            M.loopbreak = true
        end
    end

    if not M.basesecure and not IsAlive(M.svrec) and allWavesDead then
        M.basesecure = true
        M.newobjective = true
    end

    if M.relicsecure and M.basesecure then
        M.missionwon = true
    end

    if M.missionwon and not M.endmission and AudioDone(M.aud20) and AudioDone(M.aud21) and AudioDone(M.aud22) and AudioDone(M.aud23) then
        if not M.cin_started then
            CameraReady()
            M.cin_started = true
            M.startendcin = GetTime() + 20.0
        end

        if CameraReady() and not M.endcinfinish then
            CameraPath("endcin", 100, 200, M.player or M.avrec)
            M.endcinfinish = true
        end

        if (M.endcinfinish and (GetTime() > M.startendcin or CameraCancelled())) or
            (not M.endcinfinish and GetTime() > M.startendcin) then
            CameraFinish()
            M.endmission = true
            SucceedMission(GetTime(), "misn04w1.des")
        end
    end

    if not M.missionwon and not IsAlive(M.avrec) and not M.missionfail then
        subtit.Play("misn0421.wav")
        subtit.Play("misn0422.wav")
        M.missionfail = true
        FailMission(GetTime() + 20.0, "misn04l3.des")
    end

    local finalWaveCleared = M.wavenumber == 6 and
        not (M.w5u1 and IsAlive(M.w5u1)) and
        not (M.w5u2 and IsAlive(M.w5u2)) and
        not (M.w5u3 and IsAlive(M.w5u3)) and
        not (M.w5u4 and IsAlive(M.w5u4)) and
        not (M.w5u5 and IsAlive(M.w5u5)) and
        not (M.w5u6 and IsAlive(M.w5u6))

    if not M.basesecure and not M.secureloopbreak and finalWaveCleared and IsAlive(M.svrec) then
        if not M.retreat then
            RetreatIfAlive(M.tuge1, "retreatpoint")
            RetreatIfAlive(M.tuge2, "retreatpoint28")
            RetreatIfAlive(M.pu1, "retreatpoint27")
            RetreatIfAlive(M.pu2, "retreatpoint26")
            RetreatIfAlive(M.pu3, "retreatpoint25")
            RetreatIfAlive(M.pu4, "retreatpoint24")
            RetreatIfAlive(M.pu5, "retreatpoint23")
            RetreatIfAlive(M.pu6, "retreatpoint22")
            RetreatIfAlive(M.pu7, "retreatpoint21")
            RetreatIfAlive(M.pu8, "retreatpoint20")
            RetreatIfAlive(M.cheat1, "retreatpoint19")
            RetreatIfAlive(M.cheat2, "retreatpoint18")
            RetreatIfAlive(M.cheat3, "retreatpoint17")
            RetreatIfAlive(M.cheat4, "retreatpoint16")
            RetreatIfAlive(M.cheat5, "retreatpoint15")
            RetreatIfAlive(M.cheat6, "retreatpoint14")
            RetreatIfAlive(M.cheat7, "retreatpoint13")
            RetreatIfAlive(M.cheat8, "retreatpoint12")
            RetreatIfAlive(M.cheat9, "retreatpoint11")
            RetreatIfAlive(M.cheat10, "retreatpoint10")
            RetreatIfAlive(M.surv1, "retreatpoint9")
            RetreatIfAlive(M.surv2, "retreatpoint8")
            RetreatIfAlive(M.surv3, "retreatpoint7")
            RetreatIfAlive(M.surv4, "retreatpoint6")
            RetreatIfAlive(M.turret1, "retreatpoint2")
            RetreatIfAlive(M.turret2, "retreatpoint3")
            RetreatIfAlive(M.turret3, "retreatpoint4")
            RetreatIfAlive(M.turret4, "retreatpoint5")
            M.retreat = true
        end

        M.aud21 = subtit.Play("misn0415.wav")
        M.aud22 = subtit.Play("misn0416.wav")
        M.basesecure = true
        M.newobjective = true
        M.secureloopbreak = true
    end

    if not IsAlive(M.relic) and not M.missionfail then
        FailMission(GetTime() + 20.0, "misn04l2.des")
        subtit.Play("misn0431.wav")
        subtit.Play("misn0432.wav")
        subtit.Play("misn0433.wav")
        subtit.Play("misn0434.wav")
        M.missionfail = true
    end

    if not M.basesecure and not M.secureloopbreak and finalWaveCleared and not IsAlive(M.svrec) and M.chewedout then
        M.aud20 = subtit.Play("misn0425.wav")
        M.basesecure = true
        M.newobjective = true
        M.secureloopbreak = true
    end
end

function Save()
    return M
end

function Load(...)
    DestroyOverlayDemo()
    local missionData = ...
    M = missionData or M
    M.loading_done = false
    M.overlayDemoReady = false
    M.overlayDemoVisible = false
    M.overlayDemoToggleLatch = false
    M.overlayDemoAutoHideAt = nil
    M.overlayDemoStatusNextAt = 0.0
    M.overlayDemoTextureMaterial = nil
    M.overlayDemoSuppressed = false
    M.overlayDemoResumeAfterSuppression = false
    M.overlayDemoResumeDuration = 0.0
    M.overlayPauseDebugSignature = ""
    M.overlayPauseDebugDumpLatch = false
    M.overlayBootTestDone = false
    M.overlayBootTestAt = GetTime() + 1.0
    M.loadGracePeriod = GetTime() + 2.0
end
