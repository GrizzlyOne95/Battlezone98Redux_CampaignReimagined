
# Only live-install operations require elevation. Workshop builds/uploads use
# an isolated staging directory and should not trigger a UAC prompt.
$requestedAction = if ($args.Count -gt 0) { [string]$args[0] } else { "" }
$elevatedActions = @("", "-deploy", "-fromsource", "-release")
$requiresElevation = $elevatedActions -contains $requestedAction.ToLowerInvariant()
if ($requiresElevation -and
    -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
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
$WorkshopAppId = "301650"
$WorkshopPublishedFileId = "3686673790"
$WorkshopLocalRoot = Join-Path $RepoRoot "Local\Workshop"
# Battlezone installs the flat mod payload under one of these parent folders,
# depending on the storefront/layout. GOG Galaxy uses "mods", the classic
# packaged-mod layout uses "packaged_mods". Order = resolution priority.
$RuntimeModParentDirNames = @("mods", "packaged_mods")
$StructuredRuntimeDirs = @("flags", "OverlayFont", "chunkMeshes")
$SourceExcludedRelativePaths = @(
    ".git",
    "docs",
    "Local",
    "References"
)
$SourceExcludedRootFiles = @(
    ".gitignore",
    "AGENTS.md",
    "CHANGELOG.md",
    "Config\net.ini",
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

    if ($leafName.StartsWith("openshim_suite_", [System.StringComparison]::OrdinalIgnoreCase) -and
        $leafName.Contains(".pending.")) {
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
        foreach ($parentDir in $RuntimeModParentDirNames) {
            [void]$candidates.Add((Join-Path $explicitGameRoot "$parentDir\$DefaultPackagedModId"))
        }
    }

    # The GOG install (and other game-root mod folders) is the live runtime we
    # play-test against, so it takes priority over the subscribed Steam
    # Workshop payload — sync/deploy must target the files Redux actually
    # loads on this machine, not the Workshop mirror.
    $defaultRoots = @(
        "C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux",
        (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Battlezone 98 Redux"),
        "C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux",
        "C:\GOG Games\Battlezone 98 Redux"
    )

    foreach ($root in $defaultRoots) {
        if ($root) {
            foreach ($parentDir in $RuntimeModParentDirNames) {
                [void]$candidates.Add((Join-Path $root "$parentDir\$DefaultPackagedModId"))
            }
        }
    }

    # Steam keeps subscribed Workshop payloads outside the game directory.
    # Last-resort fallback only: it is a download cache, not the live install.
    $steamWorkshopRuntime = Join-Path ${env:ProgramFiles(x86)} `
        "Steam\steamapps\workshop\content\$WorkshopAppId\$WorkshopPublishedFileId"
    [void]$candidates.Add($steamWorkshopRuntime)

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

function Get-ChunkMeshesSourceRelativeRoot() {
    return "Assets\chunkMeshes"
}

function TryMapSourceRelativePathToRuntimeRelativePath($sourceRelativePath) {
    if (-not $sourceRelativePath) {
        return $null
    }

    $normalized = $sourceRelativePath -replace '/', '\'
    $chunkMeshesSourceRoot = Get-ChunkMeshesSourceRelativeRoot

    if ($normalized.Equals($chunkMeshesSourceRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith($chunkMeshesSourceRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $suffix = $normalized.Substring($chunkMeshesSourceRoot.Length).TrimStart('\')
        if ($suffix) {
            return "chunkMeshes\$suffix"
        }

        return "chunkMeshes"
    }

    if (Is-StructuredRuntimeRelativePath $normalized) {
        return $normalized
    }

    return $null
}

function TryMapRuntimeRelativePathToSourceRelativePath($runtimeRelativePath) {
    if (-not $runtimeRelativePath) {
        return $null
    }

    $normalized = $runtimeRelativePath -replace '/', '\'
    if ($normalized.Equals("chunkMeshes", [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalized.StartsWith("chunkMeshes\", [System.StringComparison]::OrdinalIgnoreCase)) {
        $suffix = $normalized.Substring("chunkMeshes".Length).TrimStart('\')
        $chunkMeshesSourceRoot = Get-ChunkMeshesSourceRelativeRoot
        if ($suffix) {
            return "$chunkMeshesSourceRoot\$suffix"
        }

        return $chunkMeshesSourceRoot
    }

    if (Is-StructuredRuntimeRelativePath $normalized) {
        return $normalized
    }

    return $null
}

function Is-ExcludedSourceRelativePath($relativePath) {
    if (-not $relativePath) {
        return $false
    }

    $leafName = [System.IO.Path]::GetFileName($relativePath)
    if ($leafName -match '(?i)\.bak(?:[._-]|$)|\.pending(?:\.|$)|\.previous$') {
        return $true
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

function Get-ManagedSourceFiles {
    if (-not (Test-Path $SourceDir)) {
        return @()
    }

    Get-ChildItem -Path $SourceDir -Recurse -File | Where-Object {
        $relativePath = Get-RelativePathFromBase $SourceDir $_.FullName
        -not (Is-ExcludedSourceRelativePath $relativePath) -and
        $_.Extension -ne ".pdb"
    }
}

function Get-DeployRelativePathFromSourcePath($sourceFileFullName) {
    $sourceRelativePath = Get-RelativePathFromBase $SourceDir $sourceFileFullName
    $mappedRuntimeRelativePath = TryMapSourceRelativePathToRuntimeRelativePath $sourceRelativePath
    if ($mappedRuntimeRelativePath) {
        return $mappedRuntimeRelativePath
    }

    return [System.IO.Path]::GetFileName($sourceFileFullName)
}

function Get-DeployRelativePathsFromSourcePath($sourceFileFullName) {
    return @(Get-DeployRelativePathFromSourcePath $sourceFileFullName)
}

function Update-OpenShimManifest {
    $shimPath = Join-Path $SourceDir "Bin\winmm.dll"
    $openShimRepo = if ($env:BZR_OPENSHIM_REPO) {
        Resolve-PathIfRelative $env:BZR_OPENSHIM_REPO
    }
    else {
        Join-Path ([Environment]::GetFolderPath("MyDocuments")) "GIT\BZR-OpenShim"
    }
    $shimBuildPath = Join-Path $openShimRepo "bin\Release\winmm.dll"
    $networkSourcePath = Join-Path $openShimRepo "net.ini"
    $patchesSourcePath = Join-Path $openShimRepo "scripts\patches.json"
    $payloadDir = Join-Path $SourceDir "InstallerPayload"
    $networkPayloadPath = Join-Path $payloadDir "openshim_net.ini.payload"
    $patchesPayloadPath = Join-Path $payloadDir "openshim_patches.json.payload"
    $manifestPath = Join-Path $SourceDir "Scripts\OpenShimManifest.lua"

    foreach ($requiredPath in @($shimBuildPath, $networkSourcePath, $patchesSourcePath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Cannot generate OpenShim suite manifest because '$requiredPath' does not exist."
        }
    }

    $refreshShim = -not (Test-Path -LiteralPath $shimPath)
    if (-not $refreshShim) {
        $buildHash = (Get-FileHash -LiteralPath $shimBuildPath -Algorithm SHA256).Hash
        $bundledHash = (Get-FileHash -LiteralPath $shimPath -Algorithm SHA256).Hash
        $refreshShim = $buildHash -ne $bundledHash
    }
    if ($refreshShim) {
        [System.IO.Directory]::CreateDirectory((Split-Path $shimPath -Parent)) | Out-Null
        [System.IO.File]::Copy($shimBuildPath, $shimPath, $true)
        Write-Host "Refreshed bundled OpenShim from $shimBuildPath" -ForegroundColor Yellow
    }

    [System.IO.Directory]::CreateDirectory($payloadDir) | Out-Null
    [System.IO.File]::Copy($networkSourcePath, $networkPayloadPath, $true)
    [System.IO.File]::Copy($patchesSourcePath, $patchesPayloadPath, $true)

    $shimItem = Get-Item -LiteralPath $shimPath
    $networkItem = Get-Item -LiteralPath $networkPayloadPath
    $patchesItem = Get-Item -LiteralPath $patchesPayloadPath
    $shimHash = (Get-FileHash -LiteralPath $shimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $networkHash = (Get-FileHash -LiteralPath $networkPayloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $patchesHash = (Get-FileHash -LiteralPath $patchesPayloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $shimVersion = $shimItem.VersionInfo.FileVersion
    if (-not $shimVersion) {
        throw "Cannot generate OpenShim manifest because winmm.dll has no file version."
    }

    $manifest = @(
        "-- Generated by Manage-CampaignFiles.ps1 from the managed OpenShim suite."
        "-- Do not edit payload metadata by hand."
        "return {"
        "    formatVersion = 2,"
        "    version = `"$shimVersion`","
        "    sha256 = `"$shimHash`","
        "    size = $($shimItem.Length),"
        "    architecture = `"x86`","
        "    payloads = {"
        "        winmm = { source = `"winmm.dll`", destination = `"winmm.dll`", sha256 = `"$shimHash`", size = $($shimItem.Length), version = `"$shimVersion`", architecture = `"x86`" },"
        "        network = { source = `"openshim_net.ini.payload`", destination = `"net.ini`", sha256 = `"$networkHash`", size = $($networkItem.Length) },"
        "        patches = { source = `"openshim_patches.json.payload`", destination = `"scripts\\patches.json`", sha256 = `"$patchesHash`", size = $($patchesItem.Length) },"
        "    },"
        "}"
        ""
    ) -join "`r`n"

    [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
    Write-Host "OpenShim suite manifest: version=$shimVersion winmm=$shimHash net=$networkHash patches=$patchesHash" -ForegroundColor DarkGray
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
        if (-not $runtimeRelativePath) {
            continue
        }

        # Runtime-only artifacts (deploy backups, pending swaps) never belong
        # in the source tree.
        if ($file.Name -match '(?i)\.bak(?:[._-]|$)|\.pending(?:\.|$)|\.previous$') {
            $skipped++
            continue
        }

        if ($runtimeRelativePath -and (Is-StructuredRuntimeRelativePath $runtimeRelativePath)) {
            $sourceRelativePath = TryMapRuntimeRelativePathToSourceRelativePath $runtimeRelativePath
            $targetPath = if ($sourceRelativePath) {
                Join-Path $SourceDir $sourceRelativePath
            }
            else {
                Join-Path $SourceDir $runtimeRelativePath
            }
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

    $runtimeDir = Ensure-RuntimeModDir
    if (-not $runtimeDir) {
        return
    }

    Update-OpenShimManifest
    $sourceFiles = Get-ManagedSourceFiles
    $desiredRuntimePaths = @{}
    foreach ($file in $sourceFiles) {
        foreach ($deployRelativePath in Get-DeployRelativePathsFromSourcePath $file.FullName) {
            $desiredRuntimePaths[$deployRelativePath] = $true
        }
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
        foreach ($deployRelativePath in Get-DeployRelativePathsFromSourcePath $file.FullName) {
            $runtimePath = Join-Path $runtimeDir $deployRelativePath
            $runtimePathParent = Split-Path $runtimePath -Parent
            if (-not (Test-Path $runtimePathParent)) {
                New-Item -ItemType Directory -Path $runtimePathParent -Force | Out-Null
            }

            $displayPath = if ($deployRelativePath -eq $file.Name) { $file.Name } else { $deployRelativePath }

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
                    Write-Host "Updated: $displayPath (authoritative source sync)" -ForegroundColor Yellow
                    $updated++
                }
                # If source version is newer, copy to the deployed runtime
                elseif ($file.LastWriteTime -gt $runtimeItem.LastWriteTime) {
                    Copy-Item -Path $file.FullName -Destination $runtimePath -Force
                    Write-Host "Updated: $displayPath" -ForegroundColor Yellow
                    $updated++
                }
                else {
                    $skipped++
                }
            }
            else {
                # New file in source, copy to the deployed runtime
                Copy-Item -Path $file.FullName -Destination $runtimePath -Force
                Write-Host "Added: $displayPath" -ForegroundColor Green
                $added++
            }
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

function Test-PathInsideDirectory {
    param(
        [string]$Candidate,
        [string]$Root
    )

    if (-not $Candidate -or -not $Root) { return $false }
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') +
        [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Find-SteamCmd {
    $candidates = @(
        "C:\steamcmd\steamcmd.exe",
        "C:\SteamCMD\steamcmd.exe",
        "C:\Program Files (x86)\Steam\steamcmd.exe",
        (Join-Path $env:LOCALAPPDATA "SteamCMD\steamcmd.exe"),
        (Join-Path $env:USERPROFILE "steamcmd\steamcmd.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    $command = Get-Command steamcmd.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Get-PublishConfig {
    param(
        [switch]$RequireSteamCmd,
        [switch]$RequireSteamUser
    )

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

    if (-not $cfg.AppId) { $cfg | Add-Member -NotePropertyName AppId -NotePropertyValue $WorkshopAppId }
    if (-not $cfg.PublishedFileId) {
        $cfg | Add-Member -NotePropertyName PublishedFileId -NotePropertyValue $WorkshopPublishedFileId
    }
    if (-not $cfg.ContentFolder) {
        $cfg | Add-Member -NotePropertyName ContentFolder -NotePropertyValue "Local\Workshop\content"
    }

    $cfg.ContentFolder = Resolve-PathIfRelative $cfg.ContentFolder
    $cfg.PreviewFile = Resolve-PathIfRelative $cfg.PreviewFile
    $cfg.DescriptionFile = Resolve-PathIfRelative $cfg.DescriptionFile
    $cfg.SteamCmdPath = Resolve-PathIfRelative $cfg.SteamCmdPath

    if ([string]$cfg.AppId -ne $WorkshopAppId -or
        [string]$cfg.PublishedFileId -ne $WorkshopPublishedFileId) {
        Write-Error "Workshop target lock failed. This repository may only update app $WorkshopAppId item $WorkshopPublishedFileId."
        return $null
    }

    if (-not (Test-PathInsideDirectory -Candidate $cfg.ContentFolder -Root $WorkshopLocalRoot)) {
        Write-Error "ContentFolder must be inside '$WorkshopLocalRoot' so clean staging is safe."
        return $null
    }

    if (-not $cfg.SteamCmdPath) {
        $resolvedSteamCmd = Find-SteamCmd
        if ($resolvedSteamCmd) {
            if ($cfg.PSObject.Properties["SteamCmdPath"]) {
                $cfg.SteamCmdPath = $resolvedSteamCmd
            }
            else {
                $cfg | Add-Member -NotePropertyName SteamCmdPath -NotePropertyValue $resolvedSteamCmd
            }
        }
    }
    if ($RequireSteamCmd -and
        (-not $cfg.SteamCmdPath -or -not (Test-Path -LiteralPath $cfg.SteamCmdPath))) {
        Write-Error "SteamCMD was not found. Set SteamCmdPath in workshop.config.json."
        return $null
    }

    if (-not $cfg.SteamUser -and $env:STEAM_USERNAME) {
        if ($cfg.PSObject.Properties["SteamUser"]) {
            $cfg.SteamUser = $env:STEAM_USERNAME
        }
        else {
            $cfg | Add-Member -NotePropertyName SteamUser -NotePropertyValue $env:STEAM_USERNAME
        }
    }
    if ($RequireSteamUser -and -not $cfg.SteamUser) {
        Write-Error "Set SteamUser in the ignored workshop.config.json or define STEAM_USERNAME."
        return $null
    }
    if ($cfg.SteamPass) {
        Write-Error "SteamPass must not be stored in workshop.config.json. Use -workshop-auth once and let SteamCMD cache authentication."
        return $null
    }

    return $cfg
}

function Build-WorkshopContent {
    param(
        $Config
    )

    if (-not $Config) {
        $Config = Get-PublishConfig
    }
    if (-not $Config) { return $null }

    $contentFolder = [System.IO.Path]::GetFullPath([string]$Config.ContentFolder)
    if (-not (Test-PathInsideDirectory -Candidate $contentFolder -Root $WorkshopLocalRoot)) {
        throw "Refusing to clean Workshop staging outside '$WorkshopLocalRoot': $contentFolder"
    }

    Update-OpenShimManifest

    if (Test-Path -LiteralPath $contentFolder) {
        Remove-Item -LiteralPath $contentFolder -Recurse -Force
    }
    [System.IO.Directory]::CreateDirectory($contentFolder) | Out-Null

    $destinationSources = @{}
    $copied = 0
    foreach ($file in @(Get-ManagedSourceFiles)) {
        foreach ($deployRelativePath in @(Get-DeployRelativePathsFromSourcePath $file.FullName)) {
            if ($destinationSources.ContainsKey($deployRelativePath)) {
                $existingSource = $destinationSources[$deployRelativePath]
                if (Test-FilesMatchByHash $existingSource $file.FullName) {
                    Write-Host "Deduplicated identical flat file: $deployRelativePath" -ForegroundColor DarkGray
                    continue
                }
                throw "Workshop flattening collision for '$deployRelativePath': '$existingSource' and '$($file.FullName)'"
            }

            $destinationSources[$deployRelativePath] = $file.FullName
            $destinationPath = Join-Path $contentFolder $deployRelativePath
            $destinationParent = Split-Path $destinationPath -Parent
            [System.IO.Directory]::CreateDirectory($destinationParent) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destinationPath -Force
            $copied++
        }
    }

    $requiredFiles = @(
        "winmm.dll",
        "bzfile.dll",
        "bzfile_replace_helper.exe",
        "exu.dll",
        "openshim_net.ini.payload",
        "openshim_patches.json.payload",
        "RequireFix.lua",
        "ScriptSubtitles.lua",
        "OpenShimManifest.lua",
        "PersistentConfig.lua",
        "RuntimeEnhancements.lua",
        "ReactiveReticle.lua",
        "misn01.lua",
        "misn02b.lua",
        "misn03.lua",
        "misn04.lua"
    )
    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $contentFolder $relativePath))) {
            throw "Workshop staging is missing required file '$relativePath'."
        }
    }

    $stagedFiles = @(Get-ChildItem -LiteralPath $contentFolder -File -Recurse)
    $forbiddenFiles = @($stagedFiles | Where-Object {
        $_.Extension -in @(".pdb", ".log", ".status") -or
        $_.Name -ieq "net.ini" -or
        $_.Name -match '(?i)\.bak(?:[._-]|$)|\.pending(\.|$)|\.previous$|^workshop_build\.vdf$|^\.git'
    })
    if ($forbiddenFiles.Count -gt 0) {
        $names = ($forbiddenFiles.FullName -join [Environment]::NewLine)
        throw "Workshop staging contains forbidden local/debug files:$([Environment]::NewLine)$names"
    }

    $contentManifestPath = Join-Path $WorkshopLocalRoot "content_manifest.sha256"
    [System.IO.Directory]::CreateDirectory($WorkshopLocalRoot) | Out-Null
    $manifestLines = foreach ($file in ($stagedFiles | Sort-Object FullName)) {
        $relativePath = Get-RelativePathFromBase $contentFolder $file.FullName
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($file.Length)  $relativePath"
    }
    [System.IO.File]::WriteAllLines(
        $contentManifestPath,
        $manifestLines,
        [System.Text.UTF8Encoding]::new($false))

    $totalBytes = ($stagedFiles | Measure-Object -Property Length -Sum).Sum
    Write-Host "Workshop staging ready: $($stagedFiles.Count) files, $totalBytes bytes" -ForegroundColor Cyan
    Write-Host "  Content:  $contentFolder" -ForegroundColor DarkGray
    Write-Host "  Manifest: $contentManifestPath" -ForegroundColor DarkGray

    return [pscustomobject]@{
        ContentFolder = $contentFolder
        ManifestPath = $contentManifestPath
        FileCount = $stagedFiles.Count
        TotalBytes = $totalBytes
        CopiedCount = $copied
    }
}

function Write-WorkshopVdf {
    param(
        $Config,
        [string]$ChangeNote
    )

    [System.IO.Directory]::CreateDirectory($WorkshopLocalRoot) | Out-Null
    $vdfPath = Join-Path $WorkshopLocalRoot "workshop_build.vdf"
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
        [string]$ChangeNote,
        $Config
    )

    $cfg = $Config
    if (-not $cfg) {
        $cfg = Get-PublishConfig -RequireSteamCmd -RequireSteamUser
    }
    if (-not $cfg) { return }

    if (-not (Test-Path $cfg.ContentFolder)) {
        Write-Error "ContentFolder not found: $($cfg.ContentFolder). Deploy the packaged mod runtime first."
        return
    }

    $vdfPath = Write-WorkshopVdf -Config $cfg -ChangeNote $ChangeNote

    $steamArgs = @(
        "+@ShutdownOnFailedCommand", "1",
        "+login", [string]$cfg.SteamUser,
        "+workshop_build_item", $vdfPath,
        "+quit"
    )

    [System.IO.Directory]::CreateDirectory($WorkshopLocalRoot) | Out-Null
    $uploadLog = Join-Path $WorkshopLocalRoot ("steamcmd_upload_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    Write-Host "Uploading app $WorkshopAppId item $WorkshopPublishedFileId to Steam Workshop..." -ForegroundColor Cyan
    $output = @(& $cfg.SteamCmdPath @steamArgs 2>&1)
    $exitCode = $LASTEXITCODE
    $output | Tee-Object -FilePath $uploadLog | ForEach-Object { Write-Host $_ }

    $outputText = $output -join "`n"
    if ($exitCode -ne 0 -or $outputText -match '(?i)(ERROR!|FAILED\s*\()') {
        throw "SteamCMD Workshop upload failed with exit code $exitCode. See '$uploadLog'."
    }

    $receipt = [ordered]@{
        AppId = $WorkshopAppId
        PublishedFileId = $WorkshopPublishedFileId
        UploadedAt = (Get-Date).ToString("o")
        ChangeNote = $ChangeNote
        ContentFolder = [string]$cfg.ContentFolder
        ContentManifest = (Join-Path $WorkshopLocalRoot "content_manifest.sha256")
        SteamCmdLog = $uploadLog
    }
    $receipt | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $WorkshopLocalRoot "last_upload.json") -Encoding UTF8
    Write-Host "Workshop upload command completed for item $WorkshopPublishedFileId." -ForegroundColor Green
}

function Initialize-WorkshopAuth {
    $cfg = Get-PublishConfig -RequireSteamCmd -RequireSteamUser
    if (-not $cfg) { return }

    Write-Host "Starting interactive SteamCMD authentication for '$($cfg.SteamUser)'." -ForegroundColor Cyan
    Write-Host "SteamCMD may request your password and Steam Guard code; neither is stored in this repository." -ForegroundColor Yellow
    & $cfg.SteamCmdPath "+login" ([string]$cfg.SteamUser) "+quit"
    if ($LASTEXITCODE -ne 0) {
        throw "SteamCMD authentication bootstrap failed with exit code $LASTEXITCODE."
    }
}

function Build-WorkshopPackage {
    param(
        [string]$Message
    )

    $cfg = Get-PublishConfig
    if (-not $cfg) { return }
    if (-not $Message) {
        $Message = "Campaign Reimagined update " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    }

    $build = Build-WorkshopContent -Config $cfg
    if (-not $build) { return }
    $vdfPath = Write-WorkshopVdf -Config $cfg -ChangeNote $Message
    Write-Host "Workshop dry run complete. Upload VDF: $vdfPath" -ForegroundColor Green
    return $build
}

function Publish-All {
    param(
        [string]$Message
    )

    $cfg = Get-PublishConfig -RequireSteamCmd -RequireSteamUser
    if (-not $cfg) { return }
    if (-not $Message) {
        $Message = "Campaign Reimagined update " + (Get-Date -Format "yyyy-MM-dd HH:mm")
    }

    $build = Build-WorkshopContent -Config $cfg
    if (-not $build) { return }
    Invoke-WorkshopUpload -ChangeNote $Message -Config $cfg
}

function Show-Menu {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Campaign Reimagined - Mod Manager" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    $runtimeDirDisplay = Resolve-RuntimeModDir
    if (-not $runtimeDirDisplay) { $runtimeDirDisplay = "<not found - will resolve on deploy>" }

    Write-Host "Current Workflow:" -ForegroundColor Yellow
    Write-Host "  - Repo root = Canonical source tree (edit here)" -ForegroundColor DarkGray
    Write-Host "  - Runtime deploy target = $runtimeDirDisplay" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "1. Sync To Source (Pull packaged mod runtime -> source tree)"
    Write-Host "2. Deploy Packaged Mod (Flatten source tree -> mod install)"
    Write-Host "3. Workshop Upload (clean staging + validation + upload)"
    Write-Host "4. Sync from Runtime only (same as option 1)"
    Write-Host "5. Workshop Dry Run (clean staging + VDF only)"
    Write-Host "6. SteamCMD Authentication Bootstrap"
    Write-Host "Q. Quit"
    Write-Host ""
    
    $choice = Read-Host "Select an option"
    
    switch ($choice) {
        "1" { Sync-ToSource; Pause; Show-Menu }
        "2" { Deploy-PackagedMod; Pause; Show-Menu }
        "3" { Publish-All; Pause; Show-Menu }
        "4" { Sync-FromRuntime; Pause; Show-Menu }
        "5" { Build-WorkshopPackage; Pause; Show-Menu }
        "6" { Initialize-WorkshopAuth; Pause; Show-Menu }
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
elseif ($args[0] -eq "-workshop-build") {
    $message = $null
    if ($args.Count -gt 1) {
        $message = ($args[1..($args.Count - 1)] -join " ")
    }
    Build-WorkshopPackage -Message $message
}
elseif ($args[0] -eq "-workshop-auth") {
    Initialize-WorkshopAuth
}
elseif ($args[0] -eq "-workshop-upload") {
    $message = $null
    if ($args.Count -gt 1) {
        $message = ($args[1..($args.Count - 1)] -join " ")
    }
    Publish-All -Message $message
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
