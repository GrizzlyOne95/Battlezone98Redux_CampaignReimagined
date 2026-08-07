
# Self-elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($args) { $arguments += " $args" }
    Start-Process powershell -Verb RunAs -ArgumentList $arguments
    Exit
}

# Manage-CampaignFiles.ps1
# Script to manage source/deploy workflow for Battlezone 98 Redux: Campaign Reimagined
# The repo root is the canonical source tree. The packaged mod install is the runtime target.
$ScriptDir = $PSScriptRoot
$RepoRoot = $ScriptDir

Set-Location $RepoRoot

$SourceDir = $RepoRoot
$CurrentDir = $RepoRoot
$DefaultPackagedModId = "3686673790"
$StructuredRuntimeDirs = @("flags", "OverlayFont")
$SourceExcludedRelativePaths = @(
    ".git",
    "docs",
    "Local"
)
$SourceExcludedRootFiles = @(
    ".gitignore",
    "AGENTS.md",
    "CHANGELOG.md",
    "LICENSE.md",
    "Manage-CampaignFiles.ps1",
    "NOTICE.md",
    "README.md",
    "workshop_build.vdf",
    "workshop.config.json",
    "workshop.config.example.json"
)

function Is-PreservedRuntimeRelativePath($relativePath) {
    if (-not $relativePath) {
        return $false
    }

    $normalized = $relativePath -replace '/', '\'
    $leafName = [System.IO.Path]::GetFileName($normalized)

    if ($normalized.Equals("bzfile_replace_helper.exe", [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.Equals("bzfile_replace_helper.pdb", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($leafName.Equals("winmm.dll.pending", [System.StringComparison]::OrdinalIgnoreCase) -or
        $leafName.EndsWith("_replace.log", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($normalized.StartsWith("OverlayFont\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $overlayRelative = $normalized.Substring("OverlayFont\".Length)
        if ($overlayRelative.Contains("\")) {
            return $true
        }
    }

    return $false
}


# Global error trap to keep window open on crash
trap {
    Write-Error $_
    Read-Host "An error occurred. Press Enter to exit..."
    exit 1
}

function Get-RuntimeModDirCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()

    $explicitRuntime = Resolve-PathIfRelative $env:BZR_CAMPAIGN_RUNTIME_DIR
    if ($explicitRuntime) {
        [void]$candidates.Add($explicitRuntime)
    }

    # Backward compatibility with the old environment variable name.
    $explicitAddon = Resolve-PathIfRelative $env:BZR_CAMPAIGN_ADDON_DIR
    if ($explicitAddon) {
        [void]$candidates.Add($explicitAddon)
    }

    $explicitGameRoot = Resolve-PathIfRelative $env:BZR_BATTLEZONE_ROOT
    if ($explicitGameRoot) {
        [void]$candidates.Add((Join-Path $explicitGameRoot "mods\$DefaultPackagedModId"))
    }

    $defaultRoots = @(
        (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Battlezone 98 Redux"),
        "C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux",
        "C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"
    )

    foreach ($root in $defaultRoots) {
        if ($root) {
            [void]$candidates.Add((Join-Path $root "mods\$DefaultPackagedModId"))
        }
    }

    $candidates | Where-Object { $_ } | Select-Object -Unique
}

function Resolve-RuntimeModDir {
    foreach ($candidate in Get-RuntimeModDirCandidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Ensure-RuntimeModDir {
    $existing = Resolve-RuntimeModDir
    if ($existing) {
        return $existing
    }

    foreach ($candidate in Get-RuntimeModDirCandidates) {
        $parent = Split-Path $candidate -Parent
        if (Test-Path $parent) {
            New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            return $candidate
        }
    }

    Write-Warning "No packaged mod runtime directory could be resolved. Set BZR_CAMPAIGN_RUNTIME_DIR or BZR_BATTLEZONE_ROOT if this machine uses a different layout."
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

function Get-StructuredRuntimeFiles($pathValue) {
    if (-not (Test-Path $pathValue)) {
        return @()
    }

    foreach ($dirName in $StructuredRuntimeDirs) {
        $dirPath = Join-Path $pathValue $dirName
        if (Test-Path $dirPath) {
            Get-ChildItem -Path $dirPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -ne "desktop.ini" -and
                $_.Name -ne "thumbs.db" -and
                -not $_.Name.StartsWith(".")
            }
        }
    }
}

function Get-RelativePathFromBase($basePath, $fullPath) {
    $resolvedBase = (Resolve-Path $basePath).Path
    if ($fullPath.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($resolvedBase.Length).TrimStart('\')
    }

    return $null
}

function Is-StructuredRuntimeRelativePath($relativePath) {
    foreach ($dirName in $StructuredRuntimeDirs) {
        if ($relativePath.Equals($dirName, [System.StringComparison]::OrdinalIgnoreCase) -or
            $relativePath.StartsWith($dirName + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Is-ExcludedSourceRelativePath($relativePath) {
    if (-not $relativePath) {
        return $false
    }

    foreach ($dirName in $SourceExcludedRelativePaths) {
        if ($relativePath.Equals($dirName, [System.StringComparison]::OrdinalIgnoreCase) -or
            $relativePath.StartsWith($dirName + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($fileName in $SourceExcludedRootFiles) {
        if ($relativePath.Equals($fileName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Is-SourceAuthoritativeFlatFile($fileName) {
    return $fileName -and $fileName.Equals("winmm.dll", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-Sha256Hex($path) {
    if (-not (Test-Path $path)) {
        return $null
    }

    try {
        return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    }
    catch {
        Write-Warning "Hash check failed for '$path': $_"
        return $null
    }
}

function Test-FilesMatchByHash($leftPath, $rightPath) {
    $leftHash = Get-Sha256Hex $leftPath
    $rightHash = Get-Sha256Hex $rightPath

    if ($leftHash -and $rightHash) {
        return $leftHash -eq $rightHash
    }

    return $null
}

# -------------------------------------------------------------------------
# OpenShim suite promoter
# Keeps the three shipped suite payloads (winmm.dll, openshim_net.ini.payload,
# openshim_patches.json.payload) and Scripts\OpenShimManifest.lua in lockstep,
# then installs the suite into game roots with hash verification.  Every copy
# is compare-first (skip when hashes already match) and verify-after (fail
# loudly when the written bytes differ from the source).
# -------------------------------------------------------------------------

function Get-OpenShimSourcePaths {
    $shimRepo = $env:BZR_OPENSHIM_REPO
    if (-not $shimRepo) { $shimRepo = "C:\Users\iestu\Documents\GIT\BZR-OpenShim" }
    [pscustomobject]@{
        ShimRepo = $shimRepo
        Winmm    = Join-Path $shimRepo "bin\Release\winmm.dll"
        Patches  = Join-Path $shimRepo "scripts\patches.json"
    }
}

# Copy $source over $destination only when the hashes differ, then verify the
# written file hashes back to the source. Returns $true on success (including
# the already-current case), $false on any failure.
function Copy-FileVerified($sourcePath, $destinationPath, $label) {
    if (-not (Test-Path $sourcePath)) {
        Write-Warning "${label}: source missing: $sourcePath"
        return $false
    }

    $sourceHash = Get-Sha256Hex $sourcePath
    if (-not $sourceHash) {
        Write-Warning "${label}: could not hash source: $sourcePath"
        return $false
    }

    if ((Test-Path $destinationPath) -and ((Get-Sha256Hex $destinationPath) -eq $sourceHash)) {
        Write-Host "${label}: already current ($destinationPath)" -ForegroundColor DarkGray
        return $true
    }

    $destinationParent = Split-Path $destinationPath -Parent
    if ($destinationParent -and -not (Test-Path $destinationParent)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    $writtenHash = Get-Sha256Hex $destinationPath
    if ($writtenHash -ne $sourceHash) {
        Write-Warning "${label}: post-copy hash mismatch at $destinationPath (expected $sourceHash, got $writtenHash)"
        return $false
    }

    Write-Host "${label}: updated ($destinationPath)" -ForegroundColor Yellow
    return $true
}

# Regenerate Scripts\OpenShimManifest.lua from the payload files actually
# present in the mod source tree so the in-game updater's hash checks always
# describe the bytes we ship.
function Write-OpenShimManifest {
    $winmmPath = Join-Path $RepoRoot "winmm.dll"
    $netPath = Join-Path $RepoRoot "openshim_net.ini.payload"
    $patchesPath = Join-Path $RepoRoot "openshim_patches.json.payload"
    $manifestPath = Join-Path $RepoRoot "Scripts\OpenShimManifest.lua"

    foreach ($required in @($winmmPath, $netPath, $patchesPath)) {
        if (-not (Test-Path $required)) {
            Write-Warning "OpenShim manifest: required payload missing: $required"
            return $false
        }
    }

    $winmmHash = Get-Sha256Hex $winmmPath
    $netHash = Get-Sha256Hex $netPath
    $patchesHash = Get-Sha256Hex $patchesPath
    if (-not ($winmmHash -and $netHash -and $patchesHash)) {
        Write-Warning "OpenShim manifest: could not hash one or more payloads."
        return $false
    }

    $winmmItem = Get-Item $winmmPath
    $version = $winmmItem.VersionInfo.FileVersion
    if (-not $version) {
        Write-Warning "OpenShim manifest: winmm.dll has no FileVersion resource."
        return $false
    }
    $version = $version.Trim()

    $netSize = (Get-Item $netPath).Length
    $patchesSize = (Get-Item $patchesPath).Length
    $winmmSize = $winmmItem.Length

    $manifest = @"
-- Generated by Manage-CampaignFiles.ps1 from the managed OpenShim suite.
-- Do not edit payload metadata by hand.
return {
    formatVersion = 2,
    version = "$version",
    sha256 = "$winmmHash",
    size = $winmmSize,
    architecture = "x86",
    payloads = {
        winmm = { source = "winmm.dll", destination = "winmm.dll", sha256 = "$winmmHash", size = $winmmSize, version = "$version", architecture = "x86" },
        network = { source = "openshim_net.ini.payload", destination = "net.ini", sha256 = "$netHash", size = $netSize },
        patches = { source = "openshim_patches.json.payload", destination = "scripts\\patches.json", sha256 = "$patchesHash", size = $patchesSize },
    },
}
"@

    # BOM-less UTF-8: the game's Lua loader chokes on a BOM, and Windows
    # PowerShell 5 Set-Content -Encoding UTF8 would write one.
    [System.IO.File]::WriteAllText($manifestPath, ($manifest -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "OpenShim manifest regenerated: version $version winmm $winmmHash" -ForegroundColor Green
    return $true
}

# Import the freshly built shim + patches payload from the OpenShim repo into
# the mod source tree, then regenerate the manifest so it matches the files.
function Update-OpenShimSuite {
    Write-Host "Updating the OpenShim suite from the shim repo..." -ForegroundColor Cyan
    $sources = Get-OpenShimSourcePaths

    $ok = $true
    $ok = (Copy-FileVerified $sources.Winmm (Join-Path $RepoRoot "winmm.dll") "winmm.dll (repo import)") -and $ok
    $ok = (Copy-FileVerified $sources.Patches (Join-Path $RepoRoot "openshim_patches.json.payload") "patches payload (repo import)") -and $ok
    if (-not $ok) {
        Write-Warning "OpenShim suite import failed; manifest NOT regenerated."
        return $false
    }

    if (-not (Write-OpenShimManifest)) {
        return $false
    }

    Write-Host "OpenShim suite is consistent in the source tree." -ForegroundColor Green
    return $true
}

# Install the suite payloads directly into every reachable game root so a
# freshly deployed machine does not need one crash-prone launch on the old
# shim before the in-game updater promotes the new one.
function Install-OpenShimToGameRoots {
    $gameRoots = @(
        "C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux",
        "C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"
    ) | Where-Object { Test-Path $_ }

    if (-not $gameRoots) {
        Write-Warning "No game roots found; skipping direct install."
        return
    }

    $running = Get-Process battlezone98redux -ErrorAction SilentlyContinue
    if ($running) {
        Write-Warning "Battlezone is running (pid $($running.Id -join ', ')); winmm.dll is locked. Close the game and rerun."
        return
    }

    foreach ($root in $gameRoots) {
        Write-Host "Installing OpenShim suite to: $root" -ForegroundColor Cyan
        [void](Copy-FileVerified (Join-Path $RepoRoot "winmm.dll") (Join-Path $root "winmm.dll") "winmm.dll")
        [void](Copy-FileVerified (Join-Path $RepoRoot "openshim_net.ini.payload") (Join-Path $root "net.ini") "net.ini")
        [void](Copy-FileVerified (Join-Path $RepoRoot "openshim_patches.json.payload") (Join-Path $root "scripts\patches.json") "scripts\patches.json")
    }
}

function Get-ManagedSourceFiles {
    if (-not (Test-Path $SourceDir)) {
        return @()
    }

    Get-ChildItem -Path $SourceDir -Recurse -File | Where-Object {
        $relativePath = Get-RelativePathFromBase $SourceDir $_.FullName
        -not (Is-ExcludedSourceRelativePath $relativePath)
    }
}

function Get-DeployRelativePathFromSourcePath($sourceFileFullName) {
    $sourceRelativePath = Get-RelativePathFromBase $SourceDir $sourceFileFullName
    if ($sourceRelativePath -and (Is-StructuredRuntimeRelativePath $sourceRelativePath)) {
        return $sourceRelativePath
    }

    return [System.IO.Path]::GetFileName($sourceFileFullName)
}

function Sync-ToSource {
    Write-Host "Syncing files from packaged mod runtime to $SourceDir..." -ForegroundColor Cyan

    $runtimeDir = Resolve-RuntimeModDir
    if (-not $runtimeDir) {
        $checked = (Get-RuntimeModDirCandidates | ForEach-Object { "  - $_" }) -join "`n"
        Write-Warning "No packaged mod runtime directory found. Checked:`n$checked"
        return
    }

    # Index existing source files for update (Name -> FullPath)
    $sourceMap = @{}
    if (Test-Path $SourceDir) {
        $sourceFiles = Get-ManagedSourceFiles
        foreach ($file in $sourceFiles) {
            if (-not $sourceMap.ContainsKey($file.Name)) {
                $sourceMap[$file.Name] = $file.FullName
            }
        }
    }

    $runtimeFiles = @(
        Get-ManagedFlatFiles $runtimeDir
        Get-StructuredRuntimeFiles $runtimeDir
    )
    
    $updated = 0
    $added = 0
    $skipped = 0
    
    foreach ($file in $runtimeFiles) {
        $runtimeRelativePath = Get-RelativePathFromBase $runtimeDir $file.FullName

        if ($runtimeRelativePath -and (Is-StructuredRuntimeRelativePath $runtimeRelativePath)) {
            $targetPath = Join-Path $SourceDir $runtimeRelativePath
            $targetDir = Split-Path $targetPath -Parent

            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            if (Test-Path $targetPath) {
                $srcItem = Get-Item $targetPath
                if ($file.LastWriteTime -gt $srcItem.LastWriteTime) {
                    Copy-Item -Path $file.FullName -Destination $targetPath -Force
                    Write-Host "Updated: $runtimeRelativePath" -ForegroundColor Yellow
                    $updated++
                }
                else {
                    $skipped++
                }
            }
            else {
                Copy-Item -Path $file.FullName -Destination $targetPath -Force
                Write-Host "Added: $runtimeRelativePath" -ForegroundColor Green
                $added++
            }
        }
        elseif ($sourceMap.ContainsKey($file.Name)) {
            # File exists in source - check if deployed version is newer
            $targetPath = $sourceMap[$file.Name]
            $srcItem = Get-Item $targetPath

            if (Is-SourceAuthoritativeFlatFile $file.Name) {
                $skipped++
            }
            elseif ($file.LastWriteTime -gt $srcItem.LastWriteTime) {
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
    
    Write-Host "`nSync complete from ${runtimeDir}: $added added, $updated updated, $skipped unchanged" -ForegroundColor Cyan
}

function Deploy-PackagedMod {
    Write-Host "Deploying files FROM $SourceDir to the packaged mod runtime..." -ForegroundColor Cyan

    if (-not (Test-Path $SourceDir)) {
        Write-Error "Source directory '$SourceDir' not found!"
        return
    }

    # Keep the shipped OpenShim suite and its manifest in lockstep before the
    # files fan out to the runtime mod dir. A stale manifest makes the in-game
    # updater either refuse the payload or promote bytes we no longer ship.
    if (-not (Update-OpenShimSuite)) {
        Write-Error "OpenShim suite is inconsistent; aborting deploy so a mismatched manifest is never shipped."
        return
    }

    $runtimeDir = Ensure-RuntimeModDir
    if (-not $runtimeDir) {
        return
    }

    $sourceFiles = Get-ManagedSourceFiles
    $desiredRuntimePaths = @{}
    foreach ($file in $sourceFiles) {
        $desiredRuntimePaths[(Get-DeployRelativePathFromSourcePath $file.FullName)] = $true
    }

    $runtimeFiles = @(
        Get-ManagedFlatFiles $runtimeDir
        Get-StructuredRuntimeFiles $runtimeDir
    )

    foreach ($runtimeFile in $runtimeFiles) {
        $runtimeRelativePath = Get-RelativePathFromBase $runtimeDir $runtimeFile.FullName
        if ($runtimeRelativePath -and -not $desiredRuntimePaths.ContainsKey($runtimeRelativePath)) {
            if (Is-PreservedRuntimeRelativePath $runtimeRelativePath) {
                Write-Host "Preserved runtime-only file: $runtimeRelativePath" -ForegroundColor DarkGray
            }
            else {
                Remove-Item -LiteralPath $runtimeFile.FullName -Force
                Write-Host "Removed stale runtime file: $runtimeRelativePath" -ForegroundColor DarkYellow
            }
        }
    }
    
    $updated = 0
    $added = 0
    $skipped = 0
    
    foreach ($file in $sourceFiles) {
        $deployRelativePath = Get-DeployRelativePathFromSourcePath $file.FullName

        $runtimePath = Join-Path $runtimeDir $deployRelativePath
        $runtimePathParent = Split-Path $runtimePath -Parent
        if (-not (Test-Path $runtimePathParent)) {
            New-Item -ItemType Directory -Path $runtimePathParent -Force | Out-Null
        }
        
        if (Test-Path $runtimePath) {
            $runtimeItem = Get-Item $runtimePath

            $hashMatch = $null
            if (Is-SourceAuthoritativeFlatFile $file.Name) {
                $hashMatch = Test-FilesMatchByHash $file.FullName $runtimePath
            }

            # winmm.dll is source-authoritative: if the bytes differ, push the
            # shipped copy even when the deployed runtime file has a newer
            # timestamp from a manual shim swap.
            if ((Is-SourceAuthoritativeFlatFile $file.Name) -and ($hashMatch -ne $true)) {
                Copy-Item -Path $file.FullName -Destination $runtimePath -Force
                Write-Host "Updated: $($file.Name) (authoritative source sync)" -ForegroundColor Yellow
                $updated++
            }
            # If source version is newer, copy to the deployed runtime
            elseif ($file.LastWriteTime -gt $runtimeItem.LastWriteTime) {
                Copy-Item -Path $file.FullName -Destination $runtimePath -Force
                Write-Host "Updated: $($file.Name)" -ForegroundColor Yellow
                $updated++
            }
            else {
                $skipped++
            }
        }
        else {
            # New file in source, copy to the deployed runtime
            Copy-Item -Path $file.FullName -Destination $runtimePath -Force
            Write-Host "Added: $($file.Name)" -ForegroundColor Green
            $added++
        }
    }
    
    Write-Host "`nDeploy complete to ${runtimeDir}: $added added, $updated updated, $skipped unchanged" -ForegroundColor Cyan
}

function Get-TargetSubfolder($fileName) {
    $normalizedName = $fileName.ToLowerInvariant()
    switch -Regex ($normalizedName) {
        '^bzogrelogfile\.log$' { return "Local/Logs" }
        '^winmm_shim\.log$' { return "Local/Logs" }
        '^[^\\]+_replace\.log$' { return "Local/Logs" }
        '^winmm\.dll$' { return "Bin" }
        '^winmm\.dll\.pending$' { return "Local/Bin" }
        '^bzfile_replace_helper\.exe$' { return "Bin" }
        '^bzfile_replace_helper\.pdb$' { return "Local/Bin" }
        '^n64\.code-workspace$' { return "Local/Workspace" }
        '^cpp_lua_mission_flow_report\.md$' { return "Local/Reports" }
        '^bzplyr\.def$' { return "Local/Config" }
        '^exu_backup_.*\.(dll|pdb)$' { return "Local/Bin" }
        '^exu\.pdb$' { return "Local/Bin" }
        '^exu-og\.dll$' { return "Local/Bin" }
        '^subtitles(-og)?\.dll$' { return "Local/Bin" }
        '^subtitles\.pdb$' { return "Local/Bin" }
        '^exu_callconv_test\.cod$' { return "Local/Tests" }
        '^bzlogger\.txt$' { return "Local/Logs" }
    }

    $ext = [System.IO.Path]::GetExtension($fileName).ToLower()
    
    switch ($ext) {
        ".lua" { return "Scripts" }
        ".odf" { return "ODF" }
        ".bzn" { return "Missions" }
        ".csv" { return "Config" }
        ".ini" { return "Config" }
        ".ttf" { return "OverlayFont" }
        ".otf" { return "OverlayFont" }
        ".fontdef" { return "OverlayFont" }
        ".material" { return "Materials" }
        ".program" { return "Shaders" }
        ".shader" { return "Shaders" }
        ".fx" { return "Shaders" }
        ".hlsl" { return "Shaders" }
        ".glsl" { return "Shaders" }
        ".cg" { return "Shaders" }
        ".act" { return "Assets/ACT" }
        ".dds" { return "Assets/Textures" }
        ".mesh" { return "Assets/ModelFixes" }
        ".skeleton" { return "Assets/ModelFixes" }
        ".jpg" { return "Assets" }
        ".tga" { return "Assets" }
        ".bmp" { return "Assets" }
        ".png" { return "Assets" }
        ".lgt" { return "Local/Missions" }
        ".trn" { return "Local/Missions" }
        ".hg2" { return "Local/Missions" }
        ".log" { return "Local/Logs" }
        ".code-workspace" { return "Local/Workspace" }
        ".cod" { return "Local/Tests" }
        ".txt" {
            if ($fileName.StartsWith("EXU_")) { return "Config" }
            return "Text"
        }
        default { return "" }
    }
}

function Sync-FromSource {
    Deploy-PackagedMod
}

function Sync-FromRuntime {
    Sync-ToSource
}

function Build-Release {
    Write-Warning "Build-Release is deprecated. Deploying the packaged mod runtime instead."
    Deploy-PackagedMod
}

function Resolve-PathIfRelative($pathValue) {
    if (-not $pathValue) { return $null }
    if ([System.IO.Path]::IsPathRooted($pathValue)) { return $pathValue }
    return (Join-Path $RepoRoot $pathValue)
}

function Escape-VdfValue($text) {
    if ($null -eq $text) { return "" }
    return ($text -replace '"', '\"')
}

function Get-PublishConfig {
    $configPath = Join-Path $RepoRoot "workshop.config.json"
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
    if (-not $cfg.ContentFolder) {
        $runtimeDir = Ensure-RuntimeModDir
        if (-not $runtimeDir) {
            return $null
        }

        $cfg | Add-Member -NotePropertyName ContentFolder -NotePropertyValue $runtimeDir
    }

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

    $vdfPath = Join-Path $RepoRoot "workshop_build.vdf"
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
        Write-Error "ContentFolder not found: $($cfg.ContentFolder). Deploy the packaged mod runtime first."
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

    Deploy-PackagedMod
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
    Write-Host "  - Repo root = Canonical source tree (edit here)" -ForegroundColor DarkGray
    Write-Host "  - packaged_mods\$DefaultPackagedModId = Runtime deploy target" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "1. Sync To Source (Pull packaged mod runtime -> source tree)"
    Write-Host "2. Deploy Packaged Mod (Flatten source tree -> packaged_mods\$DefaultPackagedModId)"
    Write-Host "3. Publish (Deploy + Git push + Workshop upload)"
    Write-Host "4. Sync from Runtime only (same as option 1)"
    Write-Host "5. Update OpenShim suite (import shim build + regenerate manifest)"
    Write-Host "6. Install OpenShim suite to game roots (hash-verified)"
    Write-Host "Q. Quit"
    Write-Host ""

    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Sync-ToSource; Pause; Show-Menu }
        "2" { Deploy-PackagedMod; Pause; Show-Menu }
        "3" { Publish-All; Pause; Show-Menu }
        "4" { Sync-FromRuntime; Pause; Show-Menu }
        "5" { Update-OpenShimSuite; Pause; Show-Menu }
        "6" { if (Update-OpenShimSuite) { Install-OpenShimToGameRoots }; Pause; Show-Menu }
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
    Deploy-PackagedMod
}
elseif ($args[0] -eq "-deploy") {
    Deploy-PackagedMod
}
elseif ($args[0] -eq "-release") {
    Deploy-PackagedMod
}
elseif ($args[0] -eq "-addon") {
    Sync-FromRuntime
}
elseif ($args[0] -eq "-openshim") {
    Update-OpenShimSuite
}
elseif ($args[0] -eq "-installroot") {
    if (Update-OpenShimSuite) { Install-OpenShimToGameRoots }
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
