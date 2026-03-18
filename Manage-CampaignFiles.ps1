
# Self-elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($args) { $arguments += " $args" }
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    Exit
}

# Manage-CampaignFiles.ps1
# Script to manage development symlinks and release builds for Battlezone 98 Redux: Campaign Reimagined
# Set location to script directory (elevation changes it to System32)
Set-Location $PSScriptRoot

$SourceDir = "_Source"
$ReleaseDir = "_Release"
$CurrentDir = Get-Location


# Global error trap to keep window open on crash
trap {
    Write-Error $_
    Read-Host "An error occurred. Press Enter to exit..."
    exit 1
}

function Get-AddonDirCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()

    $explicitAddon = Resolve-PathIfRelative $env:BZR_CAMPAIGN_ADDON_DIR
    if ($explicitAddon) {
        [void]$candidates.Add($explicitAddon)
    }

    $explicitGameRoot = Resolve-PathIfRelative $env:BZR_BATTLEZONE_ROOT
    if ($explicitGameRoot) {
        [void]$candidates.Add((Join-Path $explicitGameRoot "addon\campaignReimagined"))
    }

    $defaultRoots = @(
        (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Battlezone 98 Redux"),
        "C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux",
        "C:\GOG Games\Battlezone 98 Redux"
    )

    foreach ($root in $defaultRoots) {
        if ($root) {
            [void]$candidates.Add((Join-Path $root "addon\campaignReimagined"))
        }
    }

    $candidates | Where-Object { $_ } | Select-Object -Unique
}

function Resolve-AddonDir {
    foreach ($candidate in Get-AddonDirCandidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Ensure-AddonDir {
    $existing = Resolve-AddonDir
    if ($existing) {
        return $existing
    }

    foreach ($candidate in Get-AddonDirCandidates) {
        $parent = Split-Path $candidate -Parent
        if (Test-Path $parent) {
            New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            return $candidate
        }
    }

    Write-Warning "No campaign addon directory could be resolved. Set BZR_CAMPAIGN_ADDON_DIR or BZR_BATTLEZONE_ROOT if this machine uses a different layout."
    return $null
}

function Get-ManagedFlatFiles($pathValue) {
    if (-not (Test-Path $pathValue)) {
        return @()
    }

    Get-ChildItem -Path $pathValue -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ne "desktop.ini" -and
        $_.Name -ne "thumbs.db" -and
        -not $_.Name.StartsWith(".")
    }
}

function Sync-ToSource {
    Write-Host "Syncing files from deployed addon to $SourceDir..." -ForegroundColor Cyan

    $addonDir = Resolve-AddonDir
    if (-not $addonDir) {
        $checked = (Get-AddonDirCandidates | ForEach-Object { "  - $_" }) -join "`n"
        Write-Warning "No deployed addon directory found. Checked:`n$checked"
        return
    }

    # Create _Source directory if it doesn't exist
    if (-not (Test-Path $SourceDir)) {
        New-Item -ItemType Directory -Path $SourceDir -Force | Out-Null
        Write-Host "Created $SourceDir directory." -ForegroundColor Yellow
    }

    # Index existing source files for update (Name -> FullPath)
    $sourceMap = @{}
    if (Test-Path $SourceDir) {
        $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File
        foreach ($file in $sourceFiles) {
            if (-not $sourceMap.ContainsKey($file.Name)) {
                $sourceMap[$file.Name] = $file.FullName
            }
        }
    }

    $addonFiles = Get-ManagedFlatFiles $addonDir
    
    $updated = 0
    $added = 0
    $skipped = 0
    
    foreach ($file in $addonFiles) {
        if ($sourceMap.ContainsKey($file.Name)) {
            # File exists in source - check if deployed version is newer
            $targetPath = $sourceMap[$file.Name]
            $srcItem = Get-Item $targetPath
            
            if ($file.LastWriteTime -gt $srcItem.LastWriteTime) {
                Copy-Item -Path $file.FullName -Destination $targetPath -Force
                Write-Host "Updated: $($file.Name)" -ForegroundColor Yellow
                $updated++
            }
            else {
                $skipped++
            }
        }
        else {
            # New file - determine target subfolder
            $subfolder = Get-TargetSubfolder $file.Name
            $targetDir = if ($subfolder) { Join-Path $SourceDir $subfolder } else { $SourceDir }
            
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            
            $targetPath = Join-Path $targetDir $file.Name
            Copy-Item -Path $file.FullName -Destination $targetPath -Force
            Write-Host "Added: $($file.Name) -> $subfolder" -ForegroundColor Green
            $added++
        }
    }
    
    Write-Host "`nSync complete from ${addonDir}: $added added, $updated updated, $skipped unchanged" -ForegroundColor Cyan
}

function Sync-FromSource {
    Write-Host "Deploying files FROM $SourceDir to the runtime addon..." -ForegroundColor Cyan

    if (-not (Test-Path $SourceDir)) {
        Write-Error "Source directory '$SourceDir' not found!"
        return
    }

    $addonDir = Ensure-AddonDir
    if (-not $addonDir) {
        return
    }

    # Get all files in _Source directory recursively
    $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File
    
    $updated = 0
    $added = 0
    $skipped = 0
    
    foreach ($file in $sourceFiles) {
        $addonPath = Join-Path $addonDir $file.Name
        
        if (Test-Path $addonPath) {
            $addonItem = Get-Item $addonPath
            
            # If source version is newer, copy to the deployed addon
            if ($file.LastWriteTime -gt $addonItem.LastWriteTime) {
                Copy-Item -Path $file.FullName -Destination $addonPath -Force
                Write-Host "Updated: $($file.Name)" -ForegroundColor Yellow
                $updated++
            }
            else {
                $skipped++
            }
        }
        else {
            # New file in source, copy to the deployed addon
            Copy-Item -Path $file.FullName -Destination $addonPath -Force
            Write-Host "Added: $($file.Name)" -ForegroundColor Green
            $added++
        }
    }
    
    Write-Host "`nDeploy complete to ${addonDir}: $added added, $updated updated, $skipped unchanged" -ForegroundColor Cyan
}

function Get-TargetSubfolder($fileName) {
    $ext = [System.IO.Path]::GetExtension($fileName).ToLower()
    
    switch ($ext) {
        ".lua" { return "Scripts" }
        ".odf" { return "ODF" }
        ".bzn" { return "Missions" }
        ".csv" { return "Config" }
        ".ini" { return "Config" }
        ".jpg" { return "Assets" }
        ".tga" { return "Assets" }
        ".bmp" { return "Assets" }
        ".png" { return "Assets" }
        ".txt" {
            if ($fileName.StartsWith("EXU_")) { return "Config" }
            return "Text"
        }
        default { return "" }
    }
}

function Sync-FromAddon {
    Sync-ToSource
}

function Build-Release {
    Write-Host "`nBuilding release to $ReleaseDir (FLATTENED)..." -ForegroundColor Cyan

    if (-not (Test-Path $SourceDir)) {
        Write-Error "Source directory '$SourceDir' not found!"
        return
    }

    # Clean Release Directory
    if (Test-Path $ReleaseDir) {
        Remove-Item $ReleaseDir -Recurse -Force
        Write-Host "Cleaned existing release directory." -ForegroundColor Yellow
    }
    New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null

    # Copy files FLATTENED
    $files = Get-ChildItem -Path $SourceDir -Recurse -File
    foreach ($file in $files) {
        Copy-Item -Path $file.FullName -Destination $ReleaseDir -Force
    }

    Write-Host "Release build complete. Files are in $ReleaseDir" -ForegroundColor Green
}

function Resolve-PathIfRelative($pathValue) {
    if (-not $pathValue) { return $null }
    if ([System.IO.Path]::IsPathRooted($pathValue)) { return $pathValue }
    return (Join-Path $PSScriptRoot $pathValue)
}

function Escape-VdfValue($text) {
    if ($null -eq $text) { return "" }
    return ($text -replace '"', '\"')
}

function Get-PublishConfig {
    $configPath = Join-Path $PSScriptRoot "workshop.config.json"
    if (-not (Test-Path $configPath)) {
        Write-Error "Missing publish config: $configPath (copy workshop.config.example.json to workshop.config.json and fill it in)."
        return $null
    }

    try {
        $cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse workshop.config.json: $_"
        return $null
    }

    if (-not $cfg.AppId) { $cfg | Add-Member -NotePropertyName AppId -NotePropertyValue "301650" }
    if (-not $cfg.ContentFolder) { $cfg | Add-Member -NotePropertyName ContentFolder -NotePropertyValue "_Release" }

    $cfg.ContentFolder = Resolve-PathIfRelative $cfg.ContentFolder
    $cfg.PreviewFile = Resolve-PathIfRelative $cfg.PreviewFile
    $cfg.DescriptionFile = Resolve-PathIfRelative $cfg.DescriptionFile
    $cfg.SteamCmdPath = Resolve-PathIfRelative $cfg.SteamCmdPath

    if (-not $cfg.SteamCmdPath -or -not (Test-Path $cfg.SteamCmdPath)) {
        Write-Error "SteamCmdPath not found. Set SteamCmdPath in workshop.config.json."
        return $null
    }
    if (-not $cfg.SteamUser) {
        Write-Error "SteamUser is required in workshop.config.json."
        return $null
    }
    if (-not $cfg.PublishedFileId) {
        Write-Error "PublishedFileId is required in workshop.config.json."
        return $null
    }

    return $cfg
}

function Invoke-GitPush {
    param(
        [string]$Message
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning "git not found in PATH. Skipping git push."
        return
    }

    $status = git status --porcelain
    if (-not $status) {
        Write-Host "Git working tree clean. Skipping commit/push." -ForegroundColor DarkGray
        return
    }

    if (-not $Message) {
        $Message = "Auto-publish " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    }

    git add -A
    git commit -m $Message
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git commit failed."
        return
    }

    git push
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git push failed."
        return
    }
}

function Write-WorkshopVdf {
    param(
        $Config,
        [string]$ChangeNote
    )

    $vdfPath = Join-Path $PSScriptRoot "workshop_build.vdf"
    $lines = @()
    $lines += '"workshopitem"'
    $lines += '{'
    $lines += "  `"appid`" `"$([string]$Config.AppId)`""
    $lines += "  `"publishedfileid`" `"$([string]$Config.PublishedFileId)`""
    $lines += "  `"contentfolder`" `"$([string](Escape-VdfValue $Config.ContentFolder))`""

    if ($Config.PreviewFile) { $lines += "  `"previewfile`" `"$([string](Escape-VdfValue $Config.PreviewFile))`"" }
    if ($Config.Visibility) { $lines += "  `"visibility`" `"$([string]$Config.Visibility)`"" }
    if ($Config.Title) { $lines += "  `"title`" `"$([string](Escape-VdfValue $Config.Title))`"" }
    if ($Config.DescriptionFile) {
        $lines += "  `"descriptionfile`" `"$([string](Escape-VdfValue $Config.DescriptionFile))`""
    }
    elseif ($Config.Description) {
        $lines += "  `"description`" `"$([string](Escape-VdfValue $Config.Description))`""
    }
    if ($ChangeNote) { $lines += "  `"changenote`" `"$([string](Escape-VdfValue $ChangeNote))`"" }

    $lines += "}"

    Set-Content -Path $vdfPath -Value $lines -Encoding ASCII
    return $vdfPath
}

function Invoke-WorkshopUpload {
    param(
        [string]$ChangeNote
    )

    $cfg = Get-PublishConfig
    if (-not $cfg) { return }

    if (-not (Test-Path $cfg.ContentFolder)) {
        Write-Error "ContentFolder not found: $($cfg.ContentFolder). Build the release first."
        return
    }

    $vdfPath = Write-WorkshopVdf -Config $cfg -ChangeNote $ChangeNote

    $args = @("+login", $cfg.SteamUser)
    if ($cfg.SteamPass) { $args += $cfg.SteamPass }
    $args += "+workshop_build_item"
    $args += $vdfPath
    $args += "+quit"

    Write-Host "Uploading to Steam Workshop..." -ForegroundColor Cyan
    & $cfg.SteamCmdPath @args
}

function Publish-All {
    param(
        [string]$Message
    )

    Build-Release
    Invoke-GitPush -Message $Message
    Invoke-WorkshopUpload -ChangeNote $Message
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Campaign Reimagined - Mod Manager" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Current Workflow:" -ForegroundColor Yellow
    Write-Host "  - _Source = Canonical source tree (edit here)" -ForegroundColor DarkGray
    Write-Host "  - Addon folder = Runtime deploy target" -ForegroundColor DarkGray
    Write-Host "  - _Release = Build output" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "1. Sync To Source (Pull deployed addon -> _Source)"
    Write-Host "2. Sync From Source (Flatten _Source -> deployed addon)"
    Write-Host "3. Build Release (Build _Source -> _Release)"
    Write-Host "4. Sync from Addon only (same as option 1)"
    Write-Host "5. Publish (Build + Git push + Workshop upload)"
    Write-Host "Q. Quit"
    Write-Host ""
    
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" { Sync-ToSource; Pause; Show-Menu }
        "2" { Sync-FromSource; Pause; Show-Menu }
        "3" { Build-Release; Pause; Show-Menu }
        "4" { Sync-FromAddon; Pause; Show-Menu }
        "5" { Publish-All; Pause; Show-Menu }
        "Q" { exit }
        "q" { exit }
        default { Write-Host "Invalid option." -ForegroundColor Red; Pause; Show-Menu }
    }
}

# Check for args to run non-interactively
if ($args[0] -eq "-sync") {
    Sync-ToSource
}
elseif ($args[0] -eq "-fromsource") {
    Sync-FromSource
}
elseif ($args[0] -eq "-release") {
    Build-Release
}
elseif ($args[0] -eq "-addon") {
    Sync-FromAddon
}
elseif ($args[0] -eq "-publish") {
    $message = $null
    if ($args.Count -gt 1) {
        $message = ($args[1..($args.Count - 1)] -join " ")
    }
    Publish-All -Message $message
}
else {
    Show-Menu
}
