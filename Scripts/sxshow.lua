-- Operation Livewire: arrival/material vertical slice, single player only.
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3686673790" })
local exuOk, exu = pcall(require, "exu")
if not exuOk then exu = nil end
local Director = require("SXDirector")
local Materials = require("SXMaterials")
local Overlay = require("SXOverlay")

local VERSION = 1
local control, changed, convoy = nil, nil, nil
local materials, overlay, director
local initialized, network, autoStart = false, false, true
local clock, prepareAt, prepareDeadline, pulseAt, hudAt = 0, 0, 0, 0, 0
local visual, title = "PENDING", "OPERATION LIVEWIRE - arrival/material prototype"
local results = {}
local restoreAfterPrepare = false
local scenes = {
    { id = "arrival", duration = 25, path = "sx_arrive", height = 650, speed = 650,
        cues = { { at = 0, id = "arrival" } } },
    { id = "materials", duration = 40, path = "sx_mat_a", height = 350, speed = 150,
        cues = { { at = 6, id = "service" }, { at = 30, id = "restore" } } },
}

local function Valid(h)
    return h ~= nil and type(IsValid) == "function" and IsValid(h)
end

local function Record(key, status, detail)
    results[key] = { status = status, detail = tostring(detail or "") }
    print("[SXSHOW] " .. key .. " " .. status .. " " .. tostring(detail or ""))
end

local function CameraEnd()
    if type(CameraFinish) == "function" then pcall(CameraFinish) end
end

local function Objectives()
    ClearObjectives()
    AddObjective("sxshow_help", "white", 3600,
        "Livewire prototype: two scouts compare original and live service materials. " ..
        "Console: sx tour | sx service | sx baseline | sx reset | sx report")
    AddObjective("sxshow_observe", "yellow", 3600,
        "Visual check: inspect the cyan scout, then use sx visual pass or sx visual fail. " ..
        "Camera cancel returns control. sx skip also ends the film.")
end

local function Build(odf, label, path)
    local h = BuildObject(odf, 1, path)
    if not Valid(h) then return nil end
    SetLabel(h, label)
    SetIndependence(h, 0)
    SetCurAmmo(h, 0)
    Stop(h, 1)
    return h
end

local function Finish(reason)
    CameraEnd()
    if materials then
        local restored = materials:Restore()
        if materials.ready then Record("restore", restored and "PASS" or "FAIL", "original assignments") end
    end
    title = "OPERATION LIVEWIRE - free play"
    Record("tour", reason == "complete" and "PASS" or "PENDING", reason)
    Objectives()
end

local function Initialize()
    if initialized then return end
    initialized = true
    network = type(IsNetGame) == "function" and IsNetGame()
    overlay, materials = Overlay.New(exu), Materials.New(exu, Valid)
    if network then
        autoStart = false
        Record("mission", "SKIP", "arrival/material prototype is single player only")
        AddObjective("sxshow_sp", "yellow", 3600, "Operation Livewire prototype requires single player.")
        return
    end
    -- The map is a copy of the setup world with hostile objects removed.
    -- Only these three prefixed handles are owned by the showcase script.
    control = Valid(control) and control or GetHandle("sx_control")
    changed = Valid(changed) and changed or GetHandle("sx_changed")
    convoy = Valid(convoy) and convoy or GetHandle("sx_convoy")
    if not Valid(control) then control = Build("avfigh", "sx_control", "sx_control") end
    if not Valid(changed) then changed = Build("avfigh", "sx_changed", "sx_changed") end
    if not Valid(convoy) then convoy = Build("avfigh", "sx_convoy", "sx_convoy") end
    if Valid(convoy) then Goto(convoy, "sx_convoy_route", 1) end
    overlay:Create()
    Record("overlay", overlay.status, overlay.ready and "awaiting visual confirmation" or "native overlay unavailable")
    director = Director.New(scenes, {
        enter = function(scene)
            if not Valid(changed) or not Valid(control) then return false end
            if type(CameraReady) ~= "function" or type(CameraPath) ~= "function"
                or type(CameraFinish) ~= "function" or type(CameraCancelled) ~= "function" then return false end
            if scene.id == "arrival" then
                title = "OPERATION LIVEWIRE - outpost arrival"
            else title = "MATERIAL LAB - baseline scouts; cyan service variant follows" end
            CameraReady()
        end,
        leave = function() CameraEnd() end,
        finish = Finish,
        tick = function(scene)
            if not Valid(changed) then return false end
            CameraPath(scene.path, scene.height, scene.speed, changed)
        end,
        cue = function(_, cue)
            if cue.id == "service" then
                if materials.ready then
                    materials:Apply()
                    Record("materials", materials.status, materials.detail)
                else Record("materials", "BLOCKED", materials.detail) end
            elseif cue.id == "restore" then
                if materials.ready then
                    local ok = materials:Restore()
                    Record("restore", ok and "PASS" or "FAIL", "film baseline return")
                end
            end
        end,
    })
    prepareDeadline, prepareAt = clock + 5, clock
    Objectives()
end

function Start()
    -- Render entities/fixtures are initialized from the first live Update.
end

function Update(dt)
    Initialize()
    if network then return end
    local uiOpen = false
    for _, name in ipairs({ "IsGameUiOpen", "IsPauseMenuOpen" }) do
        if exu and type(exu[name]) == "function" then
            local ok, open = pcall(exu[name])
            uiOpen = uiOpen or (ok and open == true)
        end
    end
    if uiOpen then
        overlay:Update(title, "Tour paused for native UI", "Return to gameplay to continue")
        return
    end
    dt = tonumber(dt) or 0
    if dt ~= dt or dt < 0 or dt == math.huge then dt = 0 end
    clock = clock + dt
    if not materials.ready and materials.status == "PENDING" and clock >= prepareAt then
        prepareAt = clock + 0.25
        if materials:Prepare(control, changed) then
            Record("materials", "PENDING", "captured original assignments")
            if restoreAfterPrepare then
                local restored = materials:Restore()
                Record("load", restored and "PASS" or "FAIL", "delayed render-entity restoration")
                restoreAfterPrepare = false
            end
        elseif clock >= prepareDeadline then
            materials.status = "BLOCKED"
            Record("materials", "BLOCKED", materials.detail)
            if restoreAfterPrepare then
                Record("load", "BLOCKED", "render entities did not become ready")
                restoreAfterPrepare = false
            end
        end
    end
    if autoStart and (materials.ready or materials.status == "BLOCKED" or clock >= prepareDeadline) then
        autoStart = false
        if not director:Start() then Record("tour", "BLOCKED", director.error or "camera/fixture unavailable") end
    end
    if director.mode == "tour" and CameraCancelled() then director:Finish("cancelled") end
    director:Update(dt)
    if clock >= pulseAt then
        local prior = materials.status
        materials:Pulse(clock)
        pulseAt = clock + 0.10
        if materials.status ~= prior then Record("materials", materials.status, materials.detail) end
    end
    if clock >= hudAt then
        hudAt = clock + 0.10
        local state = director:Snapshot()
        overlay:Update(title,
            string.format("%s %.1fs | Materials %s | Visual %s", state.scene, state.elapsed, materials.status, visual),
            "Camera cancel / sx skip | sx service | sx baseline | sx tour | sx report")
    end
end

function Command(command, arguments)
    if string.lower(tostring(command)) ~= "sx" then return false end
    Initialize()
    if network then return true end
    local action = string.lower(tostring(arguments or "")):match("^%s*(.-)%s*$")
    if action == "skip" then director:Finish("operator-skip")
    elseif action == "tour" or action == "materials" then
        materials:Restore()
        visual = "PENDING"
        results.visual = { status = "PENDING", detail = "observe this replay" }
        director:Start(action == "materials" and "materials" or nil)
    elseif action == "service" then
        director:Finish("operator-service")
        materials:Apply()
        Record("materials", materials.status, materials.detail)
    elseif action == "baseline" then
        director:Finish("operator-baseline")
        local ok = materials:Restore()
        Record("restore", materials.ready and (ok and "PASS" or "FAIL") or "BLOCKED", "operator baseline")
    elseif action == "reset" then
        director:Finish("operator-reset")
        local safe = materials:Restore()
        if not safe then Record("reset", "FAIL", "restore failed; fixtures retained"); return true end
        local function RemoveOwned(h)
            if Valid(h) and h ~= GetPlayerHandle() then RemoveObject(h) end
        end
        RemoveOwned(control)
        RemoveOwned(changed)
        RemoveOwned(convoy)
        overlay:Destroy()
        control, changed, convoy = nil, nil, nil
        initialized, autoStart, visual = false, true, "PENDING"
        restoreAfterPrepare = false
        results = {}
    elseif action == "visual pass" or action == "visual fail" then
        if materials.active then
            visual = action == "visual pass" and "PASS" or "FAIL"
            Record("visual", visual, "operator observed live service material")
        else Record("visual", "PENDING", "use sx service before observing") end
    elseif action == "report" then
        for _, key in ipairs({ "mission", "overlay", "materials", "restore", "visual", "tour", "load", "reset" }) do
            local result = results[key]
            if result then print("[SXSHOW] " .. key .. " " .. result.status .. " " .. result.detail) end
        end
        print("[SXSHOW] current materials " .. materials.status .. " " .. materials.detail)
    else DisplayMessage("Livewire: sx tour/materials/skip/service/baseline/reset/report/visual pass/visual fail") end
    return true
end

function DeleteObject(h)
    if h == changed or h == control then
        if materials then
            materials.ready, materials.active, materials.status = false, false, "BLOCKED"
            materials.detail = "fixture removed; use sx reset"
        end
        if director then director:Finish("fixture-deleted") end
        Record("materials", "BLOCKED", "fixture removed; use sx reset")
    end
end

function Save()
    return VERSION, results, control, changed, convoy,
        materials and materials.controlBase or nil, materials and materials.changedBase or nil,
        director and director:Snapshot() or nil
end

function Load(version, savedResults, savedControl, savedChanged, savedConvoy, controlBase, changedBase, snapshot)
    -- Never resume camera progress or replay spawn/destruction cues from a save.
    if version ~= VERSION then return end
    CameraEnd()
    if materials then materials:Restore() end
    if overlay then overlay:Destroy() end
    control, changed, convoy = savedControl, savedChanged, savedConvoy
    initialized, autoStart, visual = false, false, "PENDING"
    results = type(savedResults) == "table" and savedResults or {}
    results.visual = { status = "PENDING", detail = "observe again after loading" }
    Initialize()
    if network then return end
    director.mode = "freeplay"
    title = "OPERATION LIVEWIRE - checkpoint restored to free play"
    -- Keep the saved originals even when render entities are not ready yet.
    materials.controlBase, materials.changedBase = controlBase, changedBase
    local ok = materials:Prepare(control, changed, controlBase, changedBase)
    if ok then ok = materials:Restore() end
    restoreAfterPrepare = not materials.ready and materials.status == "PENDING"
    local status = ok and "PASS" or (restoreAfterPrepare and "PENDING" or materials.status)
    Record("load", status, snapshot and "safe handover; prior camera not replayed" or "safe handover")
end
