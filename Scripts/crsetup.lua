-- crsetup.lua
-- Open Community Patch setup/repair utility mission.
---@diagnostic disable: lowercase-global, undefined-global

local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})

local Installer = require("OpenShimInstaller")

local DISPLAY_SECONDS = 3600.0
local report = nil
local actionResult = nil

local stateMessages = {
    CURRENT = { "green", "READY: Open Community Patch files are current." },
    INSTALL_REQUIRED = { "yellow", "INSTALL REQUIRED: OpenShim is not installed beside Battlezone." },
    UPDATE_REQUIRED = { "yellow", "UPDATE REQUIRED: One or more OpenShim files are out of date." },
    RESTART_REQUIRED = { "yellow", "RESTART REQUIRED: OpenShim is staged and waiting for Battlezone to exit." },
    UPDATE_FAILED = { "red", "UPDATE FAILED: The replacement helper reported a failure." },
    NEWER_THAN_BUNDLED = { "green", "NO DOWNGRADE: Your installed OpenShim is newer than this Workshop bundle." },
    MANIFEST_INVALID = { "red", "BUNDLE ERROR: OpenShimManifest.lua is missing, malformed, or unsupported." },
    PAYLOAD_MISSING = { "red", "BUNDLE ERROR: A required OpenShim payload file is missing." },
    PAYLOAD_HASH_MISMATCH = { "red", "BUNDLE ERROR: A bundled OpenShim payload failed SHA-256 validation." },
    STAGING_UNAVAILABLE = { "red", "INSTALLER ERROR: Hardened OpenShim staging is unavailable." },
    BZFILE_UNAVAILABLE = { "red", "INSTALLER ERROR: bzfile.dll could not be loaded." },
    HELPER_MISSING = { "red", "INSTALLER ERROR: bzfile_replace_helper.exe is missing from the active mod." },
}

local actionMessages = {
    none = "No changes were needed.",
    already_staged = "An existing staged update was detected; no duplicate staging was attempted.",
    install_staged = "OpenShim installation was staged for verified replacement when Battlezone exits.",
    update_staged = "OpenShim update was staged for verified replacement when Battlezone exits.",
    config_installed = "The default openshim.ini was installed; the core OpenShim files were already current.",
    config_failed = "Could not install the default openshim.ini.",
    stage_failed = "OpenShim staging failed before the replacement helper could complete setup.",
    stage_failed_after_launch = "The replacement helper launched but reported an immediate failure.",
    blocked = "Setup refused to change files because the current diagnostic state is unsafe to repair automatically.",
}

local function Value(value, fallback)
    if value == nil or value == "" then
        return fallback or "UNKNOWN"
    end
    return tostring(value)
end

local function AddLine(id, color, text)
    if AddObjective then
        AddObjective(id, color or "white", DISPLAY_SECONDS, text)
    end
end

local function ComponentText(label, entry)
    if not entry then
        return label .. ": UNKNOWN"
    end
    return label .. ": " .. Value(entry.state)
end

local function AttachActionToReport(currentReport, result)
    if not currentReport or not result then return end
    currentReport.action = result.action
    currentReport.actionSuccess = result.success
    currentReport.actionRestartRequired = result.restartRequired
    currentReport.actionDetail = result.detail
    currentReport.actionPlayerConfig = result.playerConfigAction
    currentReport.actionStageState = result.stageState
end

local function RenderReport(logPath, logError)
    if ClearObjectives then
        ClearObjectives()
    end

    AddLine("crsetup_title", "green", "OPEN COMMUNITY PATCH - SETUP / REPAIR")

    local stateInfo = stateMessages[report.state] or
        { "yellow", "STATUS: " .. Value(report.state) }
    AddLine("crsetup_state", stateInfo[1], stateInfo[2])

    local actionText = actionMessages[actionResult and actionResult.action or "none"] or
        Value(actionResult and actionResult.detail, "Setup completed.")
    local actionColor = actionResult and actionResult.success and "green" or "yellow"
    if actionResult and not actionResult.success then actionColor = "red" end
    AddLine("crsetup_action", actionColor, "Action: " .. actionText)

    local bundledVersion = report.manifest and report.manifest.version or nil
    local installedVersion = report.installed and report.installed.winmm and
        report.installed.winmm.version or nil
    AddLine(
        "crsetup_versions",
        "white",
        "Bundled OpenShim: " .. Value(bundledVersion) ..
        "    Installed: " .. Value(installedVersion, "NOT INSTALLED"))

    AddLine(
        "crsetup_core",
        "white",
        ComponentText("winmm.dll", report.installed and report.installed.winmm) ..
        "    " .. ComponentText("net.ini", report.installed and report.installed.network))

    AddLine(
        "crsetup_support",
        "white",
        ComponentText("patches.json", report.installed and report.installed.patches) ..
        "    " .. ComponentText("openshim.ini", report.installed and report.installed.playerConfig))

    local helperState = report.helper and report.helper.exists and "PRESENT" or "MISSING"
    local updaterState = report.updateStatus and report.updateStatus.state or "NONE"
    AddLine(
        "crsetup_helper",
        report.helper and report.helper.exists and "green" or "red",
        "Replacement helper: " .. helperState .. "    Update status: " .. Value(updaterState, "NONE"))

    AddLine(
        "crsetup_log",
        logPath and "green" or "yellow",
        logPath and
            "Diagnostic report written: logs\\openpatch_setup.log" or
            ("Diagnostic report could not be written: " .. Value(logError, "unknown error")))

    if actionResult and actionResult.restartRequired then
        AddLine(
            "crsetup_next",
            "yellow",
            "NEXT STEP: Completely exit Battlezone. Do not only return to the menu. Relaunch after it closes.")
    elseif actionResult and actionResult.success then
        AddLine(
            "crsetup_next",
            "green",
            "Setup is complete. You may return to the menu and play normally.")
    else
        AddLine(
            "crsetup_next",
            "red",
            "Setup could not complete. Review this screen and logs\\openpatch_setup.log.")
    end
end

local function FinishMission()
    local missionTime = (GetTime and GetTime() or 0.0) + 1.0

    if actionResult and actionResult.restartRequired then
        if SucceedMission then
            SucceedMission(missionTime, "crsetrr.des")
        end
        return
    end

    if actionResult and actionResult.success then
        if SucceedMission then
            SucceedMission(missionTime, "crsetok.des")
        end
        return
    end

    if FailMission then
        FailMission(missionTime, "crsetfl.des")
    end
end

function Start()
    local player = GetPlayerHandle and GetPlayerHandle() or nil
    if player and IsValid and IsValid(player) and SetIndependence then
        SetIndependence(player, 0)
    end

    local before = Installer.Inspect()
    actionResult = Installer.Apply(before)
    report = actionResult.after or before

    AttachActionToReport(report, actionResult)
    local logPath, logError = Installer.WriteDiagnosticLog(report)

    RenderReport(logPath, logError)

    local bundledVersion = report.manifest and report.manifest.version or nil
    local installedVersion = report.installed and report.installed.winmm and
        report.installed.winmm.version or nil
    print("crsetup: result=" .. tostring(report.state) ..
        " action=" .. tostring(actionResult.action) ..
        " success=" .. tostring(actionResult.success) ..
        " restartRequired=" .. tostring(actionResult.restartRequired) ..
        " bundled=" .. Value(bundledVersion) ..
        " installed=" .. Value(installedVersion, "none") ..
        " detail=" .. Value(actionResult.detail, ""))

    FinishMission()
end
