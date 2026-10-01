-- Operation Livewire: full single-player cinematic and repeatable native exhibit bays.
local RequireFix = require("RequireFix")
RequireFix.Initialize({ "campaignReimagined", "3686673790" })
local exuOk, exu = pcall(require, "exu")
if not exuOk then exu = nil end
local Director = require("SXDirector")
local Materials = require("SXMaterials")
local Overlay = require("SXOverlay")
local Scenes = require("SXScenes")
local Exhibits = require("SXExhibits")

local VERSION = 2
local handles, results, observations = {}, {}, {}
local initialized, network, autoStart = false, false, true
local clock, prepareAt, prepareDeadline, pulseAt, hudAt = 0, 0, 0, 0, 0
local restoreAfterPrepare, saveJob, uiWasOpen, uiOptions = false, nil, false, nil
local loadNativeOK = true
local title = "OPERATION LIVEWIRE - lunar proving ground"
local materials, overlay, exhibits, director
local cameraActive = false

local function Valid(h) return h ~= nil and type(IsValid) == "function" and IsValid(h) end
local function Alive(h) return Valid(h) and (type(IsAlive) ~= "function" or IsAlive(h)) end
local function Record(key, status, detail)
    detail = tostring(detail or "")
    if results[key] and results[key].status == status and results[key].detail == detail then return end
    results[key] = { status = status, detail = detail }
    print("[SXSHOW] " .. key .. " " .. status .. " " .. detail)
end
local function Resolution()
    if exu and not exu.isStub and type(exu.GetGameResolution) == "function" then
        local ok, w, h = pcall(exu.GetGameResolution)
        if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then return w, h end
    end
    return 1280, 720
end
local function CameraEnd()
    if type(CameraFinish) == "function" then pcall(CameraFinish) end
    cameraActive = false
end
local function Objectives()
    ClearObjectives()
    AddObjective("sxshow_controls", "white", 3600,
        "Operation Livewire: sx tour | sx materials/environment/ai/chunks/filters/control/cockpit/handover. " ..
        "Camera cancel / sx skip returns control. sx list shows all controls.")
    AddObjective("sxshow_observe", "yellow", 3600,
        "Inspect the actual visuals and unit responses. sx confirm <feature> pass/fail records your observation. " ..
        "sx report prints results. sx autosave previews the notification; sx save writes a dedicated checkpoint.")
end

local function Ensure(key)
    if Valid(handles[key]) then return handles[key] end
    local spec = Scenes.Fixtures[key]
    if not spec then return nil end
    local h = GetHandle("sx_" .. key)
    if not Valid(h) then h = BuildObject(spec.odf, spec.team or 1, spec.path) end
    if not Valid(h) then Record("fixture/" .. key, "BLOCKED", spec.odf .. " at " .. spec.path); return nil end
    handles[key] = h
    SetLabel(h, "sx_" .. key)
    if spec.health or spec.odf == "sxanchor" then
        SetMaxHealth(h, spec.health or 100000); SetCurHealth(h, spec.health or 100000)
    end
    if spec.odf == "avfigh" or spec.odf == "avtank" then
        if h ~= GetPlayerHandle() then SetIndependence(h, 0); Stop(h, 1) end
        SetCurAmmo(h, spec.ammo or 0)
        if spec.ammo then SetWeaponMask(h, 1) end
    end
    if spec.name then SetObjectiveName(h, spec.name); SetObjectiveOn(h) end
    return h
end
local function RemoveOwned(key)
    local h = handles[key]
    if Valid(h) and h == GetPlayerHandle() then return true end
    if Valid(h) then
        local ok, result = pcall(RemoveObject, h)
        if not ok or result == false then return false end
    end
    handles[key] = nil
    return true
end
local function RemoveGroup(group)
    local all = true
    for key, spec in pairs(Scenes.Fixtures) do
        if spec.group == group then local removed = RemoveOwned(key); all = removed and all end
    end
    return all
end
local function Restore()
    CameraEnd()
    local a, b = true, true
    if materials then a = materials:Restore() end
    if exhibits then b = exhibits:Restore() end
    if not a or not b then Record("restore", "FAIL", "one or more temporary baselines could not be restored")
    else Record("restore", "PASS", "temporary materials, native settings and bay actors cleaned up") end
    return a and b
end
local function Finish(reason)
    local restored = Restore()
    title = "OPERATION LIVEWIRE - free play"
    local failed = not restored or tostring(reason):match("error$") ~= nil
    Record("tour", failed and "FAIL" or (reason == "complete" and "PASS" or "PENDING"), reason)
    Objectives()
end
local function CurrentScene()
    return director and director.mode == "tour" and Scenes.List[director.index] or nil
end
local function SceneTarget(scene)
    return Alive(handles[scene.target]) and handles[scene.target] or
        (Alive(handles.changed) and handles.changed or GetPlayerHandle())
end

local function Initialize()
    if initialized then return end
    initialized = true
    network = type(IsNetGame) == "function" and IsNetGame()
    overlay, materials = Overlay.New(exu), Materials.New(exu, Valid)
    if network then
        autoStart = false
        overlay:Create()
        Record("mission", "SKIP", "network: local overlay only; no cameras, save, tuning or world mutations")
        AddObjective("sxshow_sp", "yellow", 3600, "Livewire proving ground is single player. Local overlay only in network games.")
        return
    end
    for key, spec in pairs(Scenes.Fixtures) do if spec.keep then Ensure(key) end end
    if Alive(handles.convoy) then Goto(handles.convoy, Scenes.Routes.convoy, 1) end
    overlay:Create()
    Record("overlay", overlay.ready and "PENDING" or "BLOCKED", "titles, telemetry, instrument labels and notification; observe in game")
    exhibits = Exhibits.New(exu, { valid = Valid, alive = Alive, ensure = Ensure, handles = handles,
        record = Record, removeGroup = RemoveGroup, resolution = Resolution, overlay = overlay, clock = function() return clock end })
    director = Director.New(Scenes.List, {
        enter = function(scene)
            title = scene.title
            exhibits:Begin(scene)
            if scene.camera == "gameplay" then CameraEnd(); return true end
            if type(CameraReady) ~= "function" or type(CameraPath) ~= "function"
                or type(CameraObject) ~= "function" or type(CameraCancelled) ~= "function" then
                Record("camera", "BLOCKED", "native cinematic API unavailable"); return false
            end
            if not Valid(SceneTarget(scene)) then Record("camera", "BLOCKED", "camera target unavailable"); return false end
            CameraReady(); cameraActive = true
        end,
        leave = function(scene) CameraEnd(); return exhibits:Leave(scene) end,
        finish = Finish,
        tick = function(scene)
            if scene.camera == "gameplay" then return true end
            local target = SceneTarget(scene)
            if not Valid(target) then return false end
            if scene.camera == "path" then CameraPath(scene.path, scene.height, scene.speed, target)
            else
                CameraObject(target, exhibits.aiSide and 4500 or scene.right, scene.up, scene.forward, target)
            end
        end,
        cue = function(scene, cue)
            if cue.id == "service" then
                if materials.ready then materials:Apply(); Record("materials", materials.status, materials.detail)
                else Record("materials", "BLOCKED", materials.detail) end
                exhibits.message = "Material lab - cyan service variant; control twin unchanged"
            elseif cue.id == "animate" then
                local ok = materials:Animate(true)
                Record("animation", ok and "PENDING" or "BLOCKED", "clone-owned UV scroll plus emissive pulse; observe shader output")
                exhibits.message = "Material lab - scrolling texture and pulsing emissive color"
            elseif cue.id == "baseline" then
                local ok = materials:Restore()
                Record("restore/materials", materials.ready and (ok and "PASS" or "FAIL") or "BLOCKED", "original subentity names")
                exhibits.message = "Material lab - original assignments restored"
            else exhibits:Cue(scene, cue) end
        end,
    })
    prepareDeadline, prepareAt = clock + 5, clock
    Objectives()
end

local function StartTour(id)
    if saveJob then Record("save/native", "PENDING", "finish the queued checkpoint before replaying"); return false end
    if id and not Scenes.Find(id) then return false end
    director:Finish("replay")
    if not Restore() then Record("tour", "BLOCKED", "restore the prior overrides before replaying"); return false end
    observations = {}
    for key in pairs(results) do if key:match("^visual/") then results[key] = nil end end
    if not id then results = {}; Record("overlay", overlay.ready and "PENDING" or "BLOCKED", "new full tour") end
    local ok = director:Start(id)
    if not ok then Record("tour", "BLOCKED", director.error or "camera unavailable") end
    return ok
end
local function OptionsSnapshot()
    local width, height = Resolution()
    return { width = width, height = height,
        scale = exhibits:Read("GetUIScaling"), music = exhibits:Read("GetMusicVolume") }
end

function Start() end -- Wait for the first live frame and render entities.
function Update(dt)
    Initialize()
    if network then
        overlay:Update("OPERATION LIVEWIRE - network presentation", "Local overlay; SP exhibit bays disabled",
            "No synchronized world changes", clock, "Multiplayer qualification remains separate")
        return
    end
    local uiOpen = false
    for _, name in ipairs({ "IsGameUiOpen", "IsPauseMenuOpen" }) do
        if exu and not exu.isStub and type(exu[name]) == "function" then
            local ok, open = pcall(exu[name]); uiOpen = uiOpen or (ok and open == true)
        end
    end
    if uiOpen then
        if not uiWasOpen then uiOptions = OptionsSnapshot(); Record("options/ui", "PASS", "native UI detected; custom overlay and film clock paused") end
        uiWasOpen = true
        overlay:Update(title, "Tour paused for native UI", "Return to gameplay to continue", clock, "")
        return
    elseif uiWasOpen then
        local current = OptionsSnapshot()
        if uiOptions and (current.width ~= uiOptions.width or current.height ~= uiOptions.height
            or current.scale ~= uiOptions.scale or current.music ~= uiOptions.music) then
            Record("options/readback", "PASS", "native option/resolution change observed; overlay reflows")
        end
        uiWasOpen, uiOptions = false, nil
    end
    dt = tonumber(dt) or 0
    if dt ~= dt or dt < 0 or dt == math.huge then dt = 0 end
    clock = clock + dt
    if not materials.ready and materials.status == "PENDING" and clock >= prepareAt then
        prepareAt = clock + 0.25
        if materials:Prepare(handles.control, handles.changed) then
            Record("materials", "PENDING", "captured original assignments")
            if restoreAfterPrepare then
                local restored = materials:Restore()
                Record("load", restored and loadNativeOK and "PASS" or "FAIL", "delayed render-entity restoration")
                restoreAfterPrepare = false
            end
        elseif clock >= prepareDeadline then
            materials.status = "BLOCKED"; Record("materials", "BLOCKED", materials.detail)
            if restoreAfterPrepare then Record("load", "BLOCKED", "render entities did not become ready"); restoreAfterPrepare = false end
        end
    end
    if autoStart and (materials.ready or materials.status == "BLOCKED" or clock >= prepareDeadline) then
        autoStart = false; StartTour()
    end
    if cameraActive and type(CameraCancelled) == "function" and CameraCancelled() then director:Finish("cancelled") end
    director:Update(dt)
    exhibits:Update(dt, CurrentScene())
    if clock >= pulseAt then
        local prior = materials.status
        materials:Pulse(clock); pulseAt = clock + 0.10
        if prior ~= materials.status then Record("materials", materials.status, materials.detail) end
    end
    if saveJob and clock >= saveJob.at then
        saveJob = nil -- A snapshot must never serialize/replay a pending save request.
        local ok, accepted, detail = exhibits:Call("SaveGame", "Save\\sxshow.sav", 0, "Operation Livewire checkpoint")
        Record("save/native", ok and accepted == true and "PASS" or "BLOCKED", detail or "native save unavailable")
        overlay:Notify(ok and accepted == true and "Showcase checkpoint saved" or "Checkpoint save unavailable", 4, clock, false)
    end
    if clock >= hudAt then
        hudAt = clock + 0.10
        local scene = CurrentScene()
        local progress = scene and string.format("%s - %.0f / %.0fs", scene.id, director.elapsed, scene.duration) or "Free play"
        overlay:Update(title, exhibits.message, "Camera cancel / sx skip | sx list | sx report", clock,
            exhibits.telemetry ~= "" and exhibits.telemetry or progress)
    end
end

function Command(command, arguments)
    if string.lower(tostring(command)) ~= "sx" then return false end
    Initialize()
    if network then return true end
    local action = string.lower(tostring(arguments or "")):match("^%s*(.-)%s*$")
    local chapter = Scenes.Find(action)
    if action == "skip" then autoStart = false; director:Finish("operator-skip"); Restore()
    elseif action == "tour" or chapter then autoStart = false; StartTour(chapter and chapter.id or nil)
    elseif action == "service" then
        autoStart = false; director:Finish("operator-service")
        if not Restore() then return true end
        materials:Apply(); Record("materials", materials.status, materials.detail)
        title, exhibits.message = "MATERIAL LAB - free play", "Live service variant; sx baseline restores originals"
    elseif action == "baseline" then
        autoStart = false; director:Finish("operator-baseline"); Restore()
    elseif action == "autosave" then
        overlay:Notify("Autosaving...", 4, clock, true)
        Record("autosave", overlay.ready and "PENDING" or "BLOCKED", "notification preview only")
    elseif action == "save" then
        autoStart = false; director:Finish("operator-save")
        if Restore() and not saveJob then
            saveJob = { at = clock + 0.25 }; overlay:Notify("Autosaving...", 4, clock, false)
        end
    elseif action == "options" then
        autoStart = false; director:Finish("operator-options"); Restore(); exhibits:Options()
        DisplayMessage("Livewire: press Esc and open the real Options / OpenShim Settings pages.")
    elseif action == "reset" then
        saveJob, autoStart = nil, false
        director:Finish("operator-reset")
        if not Restore() then Record("reset", "FAIL", "restore failed; fixtures retained"); return true end
        local safe = true
        for key in pairs(Scenes.Fixtures) do local removed = RemoveOwned(key); safe = removed and safe end
        if not safe then Record("reset", "FAIL", "owned fixture removal failed"); return true end
        overlay:Destroy()
        handles, results, observations = {}, {}, {}
        initialized, autoStart, restoreAfterPrepare = false, true, false
    elseif action == "report" then
        local keys = {}; for key in pairs(results) do keys[#keys + 1] = key end; table.sort(keys)
        for _, key in ipairs(keys) do local r = results[key]; print("[SXSHOW] " .. key .. " " .. r.status .. " " .. r.detail) end
        for _, feature in ipairs(Scenes.Features) do print("[SXSHOW] visual/" .. feature .. " " .. (observations[feature] or "PENDING")) end
    elseif action == "caps" then
        for _, effect in ipairs({ "ssao", "depth_haze", "soft_particles" }) do
            local ok, requested, supported, effective, reason = exhibits:Call("GetRenderEffectStatus", effect)
            print("[SXSHOW] effect " .. effect .. " requested=" .. tostring(requested) .. " supported=" .. tostring(supported)
                .. " effective=" .. tostring(effective) .. " reason=" .. tostring(ok and reason or "unavailable"))
        end
    elseif action:match("^confirm ") or action:match("^visual ") then
        local feature, value = action:match("^confirm (%S+) (%S+)$")
        if not feature then
            value = action:match("^visual (%S+)$")
            feature = CurrentScene() and CurrentScene().id or "materials"
            if feature == "arrival" then feature = "overlay" elseif feature == "control" then feature = "command" elseif feature == "cockpit" then feature = "hud" end
        end
        local known = false; for _, f in ipairs(Scenes.Features) do if f == feature then known = true end end
        if known and (value == "pass" or value == "fail") and results[feature] and results[feature].status ~= "BLOCKED" then
            observations[feature] = string.upper(value); Record("visual/" .. feature, observations[feature], "operator observation")
        else DisplayMessage("Livewire: run the exhibit, then sx confirm <feature> pass/fail. Blocked features cannot be passed.") end
    else
        DisplayMessage("Livewire: sx tour/materials/environment/ai/chunks/filters/control/cockpit/handover | skip/service/baseline/reset/report/caps/autosave/save/options")
    end
    hudAt = clock -- Flush command notifications on the next live frame.
    return true
end

function DeleteObject(h)
    if h == handles.changed or h == handles.control then
        if materials then materials.ready, materials.active, materials.status = false, false, "BLOCKED"; materials.detail = "material fixture removed; sx reset" end
        if director then director:Finish("material-fixture-deleted") end
        Record("materials", "BLOCKED", "material fixture removed; sx reset")
    end
    -- Other fixture deaths are expected in destruction/filter bays. Keep their
    -- invalid handles until the bay's cleanup; never respawn them from this callback.
end

function Save()
    return VERSION, { results = results, observations = observations, handles = handles,
        controlBase = materials and materials.controlBase, changedBase = materials and materials.changedBase,
        native = exhibits and exhibits:Snapshot(), scene = director and director:Snapshot() }
end
function Load(version, saved, oldControl, oldChanged, oldConvoy, controlBase, changedBase, snapshot)
    if version == 1 then
        saved = { results = saved, handles = { control = oldControl, changed = oldChanged, convoy = oldConvoy },
            controlBase = controlBase, changedBase = changedBase, scene = snapshot }
    elseif version ~= VERSION then return end
    if type(saved) ~= "table" then return end
    CameraEnd()
    if materials then materials:Restore() end
    if exhibits then exhibits:Restore() end
    if overlay then overlay:Destroy() end
    handles = type(saved.handles) == "table" and saved.handles or {}
    results, observations = saved.results or {}, {}
    for key in pairs(results) do if key:match("^visual/") then results[key] = nil end end
    initialized, autoStart, saveJob, uiWasOpen = false, false, nil, false
    Initialize()
    if network then return end
    exhibits:Load(saved.native)
    local nativeRestored = exhibits:Restore()
    loadNativeOK = nativeRestored
    director.mode, title = "freeplay", "OPERATION LIVEWIRE - checkpoint restored to free play"
    materials.controlBase, materials.changedBase = saved.controlBase, saved.changedBase
    local ready = materials:Prepare(handles.control, handles.changed, saved.controlBase, saved.changedBase)
    local materialRestored = ready and materials:Restore()
    restoreAfterPrepare = not materials.ready and materials.status == "PENDING"
    Record("load", not nativeRestored and "FAIL" or (materialRestored and "PASS" or (restoreAfterPrepare and "PENDING" or materials.status)),
        "safe handover; camera/destruction/save cues never resumed")
end
