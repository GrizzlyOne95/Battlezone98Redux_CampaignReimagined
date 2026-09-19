-- crsetup.lua
-- Open Community Patch setup/repair utility mission.
-- Phase 3 is intentionally diagnostic-only: it may write a diagnostic log,
-- but it does not stage, copy, replace, delete, or repair game files.
---@diagnostic disable: lowercase-global, undefined-global

local RequireFix = require("RequireFix")
RequireFix.Initialize({"campaignReimagined", "3686673790"})

local Installer = require("OpenShimInstaller")

local DISPLAY_SECONDS = 3600.0
local report = nil

local stateMessages = {
    CURRENT = { "green", "READY: Installed OpenShim files match this Workshop release." },
    INSTALL_REQUIRED = { "yellow", "ACTION NEEDED: OpenShim is not installed beside Battlezone." },
    UPDATE_REQUIRED = { "yellow", "ACTION NEEDED: One or more OpenShim files need an update." },
    RESTART_REQUIRED = { "yellow", "RESTART REQUIRED: An OpenShim update is staged or waiting for game exit." },
    UPDATE_FAILED = { "red", "UPDATE FAILED: A previous OpenShim update did not complete." },
    NEWER_THAN_BUNDLED = { "green", "NO DOWNGRADE: Installed OpenShim is newer than this Workshop bundle." },
    MANIFEST_INVALID = { "red", "BUNDLE ERROR: OpenShimManifest.lua is missing, malformed, or unsupported." },
    PAYLOAD_MISSING = { "red", "BUNDLE ERROR: A required OpenShim payload file is missing." },
    PAYLOAD_HASH_MISMATCH = { "red", "BUNDLE ERROR: A bundled OpenShim payload failed SHA-256 validation." },
    STAGING_UNAVAILABLE = { "red", "INSTALLER ERROR: Hardened OpenShim staging is unavailable." },
    BZFILE_UNAVAILABLE = { "red", "INSTALLER ERROR: bzfile.dll could not be loaded." },
    HELPER_MISSING = { "red", "INSTALLER ERROR: bzfile_replace_helper.exe is missing from the active mod." },
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

local function RenderReport()
    report = Installer.Inspect()

    local logPath, logError = Installer.WriteDiagnosticLog(report)
    if not logPath then
        print("crsetup: failed to write diagnostic log: " .. tostring(logError))
    end

    if ClearObjectives then
        ClearObjectives()
    end

    AddLine("crsetup_title", "green", "OPEN COMMUNITY PATCH - SETUP / REPAIR")

    local stateInfo = stateMessages[report.state] or
        { "yellow", "STATUS: " .. Value(report.state) }
    AddLine("crsetup_state", stateInfo[1], stateInfo[2])

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
        "crsetup_bundle",
        "white",
        "Bundle payloads: winmm=" ..
        Value(report.payloads and report.payloads.winmm and report.payloads.winmm.state) ..
        " net=" .. Value(report.payloads and report.payloads.network and report.payloads.network.state) ..
        " patches=" .. Value(report.payloads and report.payloads.patches and report.payloads.patches.state) ..
        " config=" .. Value(report.payloads and report.payloads.playerConfig and report.payloads.playerConfig.state))

    AddLine(
        "crsetup_log",
        logPath and "green" or "yellow",
        logPath and
            "Diagnostic report written: logs\\openpatch_setup.log" or
            "Diagnostic report could not be written; see BZLogger output.")

    AddLine(
        "crsetup_phase",
        "yellow",
        "Diagnostic-only setup shell: no game files are changed here. Exit this mission when finished.")

    print("crsetup: inspection result=" .. tostring(report.state) ..
        " bundled=" .. Value(bundledVersion) ..
        " installed=" .. Value(installedVersion, "none"))
end

function Start()
    local player = GetPlayerHandle and GetPlayerHandle() or nil
    if player and IsValid and IsValid(player) and SetIndependence then
        SetIndependence(player, 0)
    end

    RenderReport()
end
