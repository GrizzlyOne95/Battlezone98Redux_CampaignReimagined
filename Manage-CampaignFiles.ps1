
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

function Sync-ToSource {
    # First, pull any newer files from addon directory
    Sync-FromAddon
    
    Write-Host "Syncing files from root to $SourceDir..." -ForegroundColor Cyan

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

    # Get all files in root directory
    $rootFiles = Get-ChildItem -Path $CurrentDir -File
    
    $updated = 0
    $added = 0
    $skipped = 0
    
    foreach ($file in $rootFiles) {
        # Skip script itself and system files
        if ($file.Name -eq "Manage-CampaignFiles.ps1") { continue }
        if ($file.Name.StartsWith(".")) { continue }
        if ($file.Name -eq "desktop.ini" -or $file.Name -eq "thumbs.db") { continue }

        if ($sourceMap.ContainsKey($file.Name)) {
            # File exists in source - check if root version is newer
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
    
    Write-Host "`nSync complete: $added added, $updated updated, $skipped unchanged" -ForegroundColor Cyan
}

function Sync-FromSource {
    Write-Host "Syncing files FROM $SourceDir to root..." -ForegroundColor Cyan

    if (-not (Test-Path $SourceDir)) {
        Write-Error "Source directory '$SourceDir' not found!"
        return
    }

    # Get all files in _Source directory recursively
    $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File
    
    $updated = 0
    $added = 0
    $skipped = 0
    
    foreach ($file in $sourceFiles) {
        $rootPath = Join-Path $CurrentDir $file.Name
        
        if (Test-Path $rootPath) {
            $rootItem = Get-Item $rootPath
            
            # If source version is newer, copy to root
            if ($file.LastWriteTime -gt $rootItem.LastWriteTime) {
                Copy-Item -Path $file.FullName -Destination $rootPath -Force
                Write-Host "Updated: $($file.Name)" -ForegroundColor Yellow
                $updated++
            }
            else {
                $skipped++
            }
        }
        else {
            # New file in source, copy to root
            Copy-Item -Path $file.FullName -Destination $rootPath -Force
            Write-Host "Added: $($file.Name)" -ForegroundColor Green
            $added++
        }
    }
    
    Write-Host "`nSync complete: $added added, $updated updated, $skipped unchanged" -ForegroundColor Cyan
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
    Write-Host "`nChecking for newer files in parent addon directory..." -ForegroundColor Cyan
    
    # Get parent addon directory
    $addonDir = Split-Path $CurrentDir -Parent
    
    if (-not (Test-Path $addonDir)) {
        Write-Warning "Parent addon directory not found: $addonDir"
        return
    }
    
    # Get all files in addon directory (exclude subdirectories)
    $addonFiles = Get-ChildItem -Path $addonDir -File -ErrorAction SilentlyContinue | Where-Object {
        # Exclude system files
        $_.Name -ne "desktop.ini" -and 
        $_.Name -ne "thumbs.db" -and 
        -not $_.Name.StartsWith(".")
    }
    
    if (-not $addonFiles) {
        Write-Host "No files found in addon directory." -ForegroundColor DarkGray
        return
    }
    
    $updatedRoot = 0
    $updatedSource = 0
    $skipped = 0
    
    foreach ($addonFile in $addonFiles) {
        $rootPath = Join-Path $CurrentDir $addonFile.Name
        $rootUpdated = $false
        $sourceUpdated = $false
        
        # Check if file exists in root directory
        if (Test-Path $rootPath) {
            $rootItem = Get-Item $rootPath
            
            # If addon version is newer, copy to root
            if ($addonFile.LastWriteTime -gt $rootItem.LastWriteTime) {
                Copy-Item -Path $addonFile.FullName -Destination $rootPath -Force
                Write-Host "  Root: $($addonFile.Name)" -ForegroundColor Yellow
                $updatedRoot++
                $rootUpdated = $true
            }
        }
        else {
            # File doesn't exist in root, copy it
            Copy-Item -Path $addonFile.FullName -Destination $rootPath -Force
            Write-Host "  Root: $($addonFile.Name) [NEW]" -ForegroundColor Green
            $updatedRoot++
            $rootUpdated = $true
        }
        
        # Check if file exists in _Source directory
        if (Test-Path $SourceDir) {
            $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File | Where-Object { $_.Name -eq $addonFile.Name }
            
            foreach ($sourceFile in $sourceFiles) {
                if ($addonFile.LastWriteTime -gt $sourceFile.LastWriteTime) {
                    Copy-Item -Path $addonFile.FullName -Destination $sourceFile.FullName -Force
                    if (-not $sourceUpdated) {
                        Write-Host "  Source: $($addonFile.Name)" -ForegroundColor Magenta
                        $updatedSource++
                        $sourceUpdated = $true
                    }
                }
            }
        }
        
        if (-not $rootUpdated -and -not $sourceUpdated) {
            $skipped++
        }
    }
    
    Write-Host "Addon sync complete: $updatedRoot to root, $updatedSource to source, $skipped unchanged`n" -ForegroundColor Cyan
}

function Build-Release {
    param(
        [switch]$SkipSync
    )

    # Sync to source first to ensure it's up to date!
    if (-not $SkipSync) {
        Sync-ToSource
    }

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

    Sync-ToSource
    Build-Release -SkipSync
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
    Write-Host "  - Addon folder = Game loads from here" -ForegroundColor DarkGray
    Write-Host "  - Root folder = Working directory (edit here)" -ForegroundColor DarkGray
    Write-Host "  - _Source = Organized backup" -ForegroundColor DarkGray
    Write-Host "  - _Release = Build output" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "1. Sync To Source (Pull addon -> root/source, then root -> _Source)"
    Write-Host "2. Sync From Source (Flatten _Source -> root for Git updates)"
    Write-Host "3. Build Release (Sync To Source + Build to _Release)"
    Write-Host "4. Sync from Addon only (Pull changes from parent directory)"
    Write-Host "5. Publish (Sync + Build + Git push + Workshop upload)"
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
