
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
# The repo root is canonical source. Development deploy/sync targets the GOG
# working copy only. Steam is verified only after a Workshop upload/download.
$ScriptDir = $PSScriptRoot
$RepoRoot = $ScriptDir

Set-Location $RepoRoot

$SourceDir = $RepoRoot
$CurrentDir = $RepoRoot
$CampaignModId = "3686673790"
$WorkshopAppId = "301650"
$WorkshopPublishedFileId = "3686673790"
$WorkshopLocalRoot = Join-Path $RepoRoot "Local\Workshop"
# Explicit portability overrides may use either layout. Automatic local
# deployment uses the exact GOG testing path below and never falls back to a
# Steam install or Steam's subscribed Workshop download cache.
$RuntimeModParentDirNames = @("mods", "packaged_mods")
$DefaultTestingGameRoot = "C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux"
$DefaultTestingRuntimeDir = Join-Path $DefaultTestingGameRoot "mods\$CampaignModId"
$StructuredRuntimeDirs = @(
    "flags",
    "OverlayFont",
    "chunkMeshes",
    "openshim",
    "BZ_ASSETS_CORE"
)
# Chunk meshes have two source trees: the authored originals and the generated
# interior-capped output from Tools/Cap-ChunkMeshes.py. Exactly one of them is
# deployed, chosen by Get-ChunkMeshesSourceRelativeRoot.
$ChunkMeshesAuthoredRoot = "Assets\chunkMeshes"
$ChunkMeshesCappedRoot = "Assets\chunkMeshes_capped"
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
            [void]$candidates.Add((Join-Path $explicitGameRoot "$parentDir\$CampaignModId"))
        }
    }

    [void]$candidates.Add($DefaultTestingRuntimeDir)

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

    Write-Warning "No GOG testing runtime could be resolved. Expected '$DefaultTestingRuntimeDir'. Set BZR_CAMPAIGN_RUNTIME_DIR only for an intentional non-Steam override."
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
    # The capped tree is generated output, so it is authoritative for deployment
    # whenever it exists: it is what the runtime is meant to run, and mapping the
    # runtime back to it keeps the authored originals pristine as the cap tool's
    # input. Delete Assets\chunkMeshes_capped to fall back to the originals.
    if (Test-Path (Join-Path $SourceDir $ChunkMeshesCappedRoot)) {
        return $ChunkMeshesCappedRoot
    }

    return $ChunkMeshesAuthoredRoot
}

function Get-InactiveChunkMeshesSourceRelativeRoots() {
    $activeRoot = Get-ChunkMeshesSourceRelativeRoot
    return @($ChunkMeshesAuthoredRoot, $ChunkMeshesCappedRoot) | Where-Object {
        -not $_.Equals($activeRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Write-ActiveChunkMeshesRoot() {
    $activeRoot = Get-ChunkMeshesSourceRelativeRoot
    if ($activeRoot.Equals($ChunkMeshesCappedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Chunk meshes: $activeRoot (generated caps; regenerate with Tools/Cap-ChunkMeshes.py)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "Chunk meshes: $activeRoot (authored originals; no capped tree present)" -ForegroundColor DarkGray
    }
}

function TryMapSourceRelativePathToRuntimeRelativePath($sourceRelativePath) {
    if (-not $sourceRelativePath) {
        return $null
    }

    $normalized = $sourceRelativePath -replace '/', '\'

    # Both chunk trees land in the same runtime folder. Which .mesh files actually
    # get here is decided by Is-ExcludedSourceRelativePath; the companion
    # material/skeleton/geo/texture assets live only in the authored tree and must
    # keep deploying from it even when the capped tree supplies the meshes.
    foreach ($chunkMeshesSourceRoot in @($ChunkMeshesAuthoredRoot, $ChunkMeshesCappedRoot)) {
        if ($normalized.Equals($chunkMeshesSourceRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith($chunkMeshesSourceRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            $suffix = $normalized.Substring($chunkMeshesSourceRoot.Length).TrimStart('\')
            if ($suffix) {
                return "chunkMeshes\$suffix"
            }

            return "chunkMeshes"
        }
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

        # Meshes round-trip to whichever tree is deployed; companion assets only
        # ever exist in the authored tree, so send them home rather than seeding
        # a partial copy inside the generated capped tree.
        $chunkMeshesSourceRoot = if ($suffix -and $suffix.EndsWith(".mesh", [System.StringComparison]::OrdinalIgnoreCase)) {
            Get-ChunkMeshesSourceRelativeRoot
        }
        else {
            $ChunkMeshesAuthoredRoot
        }

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

    # Only one chunk tree supplies meshes; the other is authoring input. Both map
    # onto the same runtime folder, so without this the two trees would fight over
    # every chunkMeshes\*.mesh path. Meshes only: the companion material, skeleton,
    # geo and texture assets live solely in the authored tree and must keep
    # deploying from it regardless of which tree is active.
    if ($leafName -match '(?i)\.mesh$') {
        foreach ($inactiveChunkRoot in Get-InactiveChunkMeshesSourceRelativeRoots) {
            if ($relativePath.StartsWith($inactiveChunkRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
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

# Every shipping binary is refreshed from its sibling repository's build output,
# so the bundled copy under Bin\ is always the authoritative one. A runtime copy
# must never sync back over it, and a deploy must always push it out.
$SourceAuthoritativeFlatFileNames = @(
    "winmm.dll",
    "exu.dll",
    "bzfile.dll",
    "bzfile_replace_helper.exe"
)

function Is-SourceAuthoritativeFlatFile($fileName) {
    if (-not $fileName) {
        return $false
    }

    foreach ($authoritativeName in $SourceAuthoritativeFlatFileNames) {
        if ($fileName.Equals($authoritativeName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
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
        # The shim registers <mod>\chunkMeshes as an Ogre resource root and scans it
        # recursively, and Ogre indexes meshes by bare filename. A sibling copy of
        # the tree inside the mod would therefore register 1500+ duplicate resource
        # names. Capped meshes must land on the stock paths, never beside them.
        if ($mappedRuntimeRelativePath -match '(?i)(^|\\)chunkMeshes_') {
            throw ("Refusing to deploy '$sourceRelativePath' to '$mappedRuntimeRelativePath': " +
                "chunk meshes must replace the stock chunkMeshes tree in place, not sit " +
                "beside it, or Ogre will see duplicate mesh resource names.")
        }

        return $mappedRuntimeRelativePath
    }

    return [System.IO.Path]::GetFileName($sourceFileFullName)
}

function Get-DeployRelativePathsFromSourcePath($sourceFileFullName) {
    return @(Get-DeployRelativePathFromSourcePath $sourceFileFullName)
}

# A build output older than this is probably not the build being shipped. This
# only warns: bzfile in particular can legitimately go months without a rebuild.
$ShippingBinaryStaleWarningDays = 120

function Resolve-SiblingRepoRoot($environmentVariableName, $defaultRelativePath) {
    $configuredPath = [Environment]::GetEnvironmentVariable($environmentVariableName)
    if ($configuredPath) {
        return Resolve-PathIfRelative $configuredPath
    }

    return Join-Path ([Environment]::GetFolderPath("MyDocuments")) $defaultRelativePath
}

# The four binaries Campaign Reimagined ships, and the sibling build output each
# one comes from. Bin\ is a cache of these outputs, never an independent source.
function Get-ShippingBinaryPlan {
    $definitions = @(
        @{ Project = "OpenShim"; Variable = "BZR_OPENSHIM_REPO"; Default = "GIT\BZR-OpenShim"; BuildRelativePath = "bin\Release\winmm.dll" },
        @{ Project = "EXU"; Variable = "BZR_EXU_REPO"; Default = "GIT\ExtraUtilities"; BuildRelativePath = "Release\exu.dll" },
        @{ Project = "bzfile"; Variable = "BZR_BZFILE_REPO"; Default = "GIT\bzfile"; BuildRelativePath = "Release\bzfile.dll" },
        @{ Project = "bzfile"; Variable = "BZR_BZFILE_REPO"; Default = "GIT\bzfile"; BuildRelativePath = "Release\bzfile_replace_helper.exe" }
    )

    return @($definitions | ForEach-Object {
        $repoRoot = Resolve-SiblingRepoRoot $_.Variable $_.Default
        $buildPath = Join-Path $repoRoot $_.BuildRelativePath
        $fileName = [System.IO.Path]::GetFileName($buildPath)
        $bundledPath = Join-Path $SourceDir (Join-Path "Bin" $fileName)

        [pscustomobject]@{
            Project = $_.Project
            EnvironmentVariable = $_.Variable
            RepoRoot = $repoRoot
            FileName = $fileName
            BuildPath = $buildPath
            BundledPath = $bundledPath
            SymbolBuildPath = [System.IO.Path]::ChangeExtension($buildPath, ".pdb")
            SymbolBundledPath = [System.IO.Path]::ChangeExtension($bundledPath, ".pdb")
        }
    })
}

function Copy-BundledFileIfDifferent($sourcePath, $destinationPath, $description) {
    $needsCopy = -not (Test-Path -LiteralPath $destinationPath)
    if (-not $needsCopy) {
        $needsCopy = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
    }
    if (-not $needsCopy) {
        return $false
    }

    [System.IO.Directory]::CreateDirectory((Split-Path $destinationPath -Parent)) | Out-Null
    [System.IO.File]::Copy($sourcePath, $destinationPath, $true)
    Write-Host "Refreshed bundled $description from $sourcePath" -ForegroundColor Yellow
    return $true
}

function Sync-ShippingBinaries {
    $plan = Get-ShippingBinaryPlan

    # Fail before copying anything, so a half-refreshed Bin\ is never left behind.
    foreach ($binary in $plan) {
        if (-not (Test-Path -LiteralPath $binary.BuildPath)) {
            throw ("Cannot refresh bundled '$($binary.FileName)' because the $($binary.Project) build " +
                "output '$($binary.BuildPath)' does not exist. Build $($binary.Project), or point " +
                "`$env:$($binary.EnvironmentVariable) at the repository that produces it.")
        }
    }

    foreach ($binary in $plan) {
        [void](Copy-BundledFileIfDifferent `
            $binary.BuildPath $binary.BundledPath "$($binary.Project) $($binary.FileName)")

        # Bin\*.pdb never reaches the Workshop payload, but a .pdb that does not
        # describe the .dll beside it misleads every later crash symbolization.
        if (Test-Path -LiteralPath $binary.SymbolBundledPath) {
            if (-not (Test-Path -LiteralPath $binary.SymbolBuildPath)) {
                throw ("Bundled symbols '$($binary.SymbolBundledPath)' cannot be matched to the current " +
                    "$($binary.Project) build because '$($binary.SymbolBuildPath)' does not exist.")
            }

            [void](Copy-BundledFileIfDifferent `
                $binary.SymbolBuildPath $binary.SymbolBundledPath `
                "$($binary.Project) symbols for $($binary.FileName)")
        }

        $buildAgeDays = ([DateTime]::Now - (Get-Item -LiteralPath $binary.BuildPath).LastWriteTime).TotalDays
        if ($buildAgeDays -gt $ShippingBinaryStaleWarningDays) {
            Write-Warning ("$($binary.Project) build output '$($binary.BuildPath)' is " +
                "$([int]$buildAgeDays) days old; confirm it is the build you intend to ship.")
        }
    }

    return $plan
}

# Proves the staged payload carries the current build of every shipping binary,
# so a stale ship is impossible rather than merely unlikely.
function Assert-StagedShippingBinaries($contentFolder) {
    foreach ($binary in (Get-ShippingBinaryPlan)) {
        $stagedPath = Join-Path $contentFolder $binary.FileName
        if (-not (Test-Path -LiteralPath $stagedPath)) {
            throw "Workshop staging is missing shipping binary '$($binary.FileName)'."
        }

        $buildHash = Get-Sha256Hex $binary.BuildPath
        $stagedHash = Get-Sha256Hex $stagedPath
        if (-not $buildHash -or $buildHash -ne $stagedHash) {
            throw ("Workshop staging would ship a stale '$($binary.FileName)': staged $stagedHash does " +
                "not match the $($binary.Project) build output $buildHash at '$($binary.BuildPath)'.")
        }

        Write-Host "  $($binary.FileName): $stagedHash ($($binary.Project))" -ForegroundColor DarkGray
    }
}

function Update-OpenShimManifest {
    Sync-ShippingBinaries | Out-Null

    $shimPath = Join-Path $SourceDir "Bin\winmm.dll"
    $openShimRepo = Resolve-SiblingRepoRoot "BZR_OPENSHIM_REPO" "GIT\BZR-OpenShim"
    $playerConfigSourcePath = Join-Path $openShimRepo "openshim.ini"
    $networkSourcePath = Join-Path $openShimRepo "net.ini"
    $patchesSourcePath = Join-Path $openShimRepo "scripts\patches.json"
    $rendererSourceDir = Join-Path $openShimRepo "resources\renderer\enhanced"
    $uiSourceDir = Join-Path $openShimRepo "resources\ui\custom_widgets"
    $payloadDir = Join-Path $SourceDir "InstallerPayload"
    $playerConfigPayloadPath = Join-Path $payloadDir "openshim.ini.payload"
    $networkPayloadPath = Join-Path $payloadDir "openshim_net.ini.payload"
    $patchesPayloadPath = Join-Path $payloadDir "openshim_patches.json.payload"
    $rendererPayloadDir = Join-Path $SourceDir "openshim\renderer\enhanced"
    $uiPayloadDir = Join-Path $SourceDir "BZ_ASSETS_CORE\common\ui\CustomWidgets"
    $manifestPath = Join-Path $SourceDir "Scripts\OpenShimManifest.lua"
    $uiFileNames = @("uiline.png", "uiplate.png", "uibtn.png", "uibtnhv.png")

    $requiredPaths = @(
        $playerConfigSourcePath,
        $networkSourcePath,
        $patchesSourcePath,
        (Join-Path $rendererSourceDir "resources.version")
    )
    $requiredPaths += $uiFileNames | ForEach-Object { Join-Path $uiSourceDir $_ }
    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Cannot generate OpenShim suite manifest because '$requiredPath' does not exist."
        }
    }

    [System.IO.Directory]::CreateDirectory($payloadDir) | Out-Null
    [System.IO.File]::Copy($playerConfigSourcePath, $playerConfigPayloadPath, $true)
    [System.IO.File]::Copy($networkSourcePath, $networkPayloadPath, $true)
    [System.IO.File]::Copy($patchesSourcePath, $patchesPayloadPath, $true)

    [System.IO.Directory]::CreateDirectory($rendererPayloadDir) | Out-Null
    foreach ($rendererFile in Get-ChildItem -LiteralPath $rendererSourceDir -File) {
        [System.IO.File]::Copy(
            $rendererFile.FullName,
            (Join-Path $rendererPayloadDir $rendererFile.Name),
            $true)
    }

    [System.IO.Directory]::CreateDirectory($uiPayloadDir) | Out-Null
    foreach ($uiFileName in $uiFileNames) {
        [System.IO.File]::Copy(
            (Join-Path $uiSourceDir $uiFileName),
            (Join-Path $uiPayloadDir $uiFileName),
            $true)
    }

    $shimItem = Get-Item -LiteralPath $shimPath
    $playerConfigItem = Get-Item -LiteralPath $playerConfigPayloadPath
    $networkItem = Get-Item -LiteralPath $networkPayloadPath
    $patchesItem = Get-Item -LiteralPath $patchesPayloadPath
    $shimHash = (Get-FileHash -LiteralPath $shimPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $playerConfigHash = (Get-FileHash -LiteralPath $playerConfigPayloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
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
        "        playerConfig = { source = `"openshim.ini.payload`", destination = `"openshim.ini`", sha256 = `"$playerConfigHash`", size = $($playerConfigItem.Length), overwrite = true },"
        "    },"
        "}"
        ""
    ) -join "`r`n"

    [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
    Write-Host "OpenShim suite manifest: version=$shimVersion winmm=$shimHash ini=$playerConfigHash net=$networkHash patches=$patchesHash" -ForegroundColor DarkGray
}

function Sync-ToSource {
    Write-Host "Syncing files from the GOG working runtime to $SourceDir..." -ForegroundColor Cyan
    Write-ActiveChunkMeshesRoot

    $runtimeDir = Resolve-RuntimeModDir
    if (-not $runtimeDir) {
        $checked = (Get-RuntimeModDirCandidates | ForEach-Object { "  - $_" }) -join "`n"
        Write-Warning "No GOG working runtime found. Checked:`n$checked"
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
    Write-Host "Deploying files FROM $SourceDir to the GOG working runtime..." -ForegroundColor Cyan
    Write-ActiveChunkMeshesRoot

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
    Write-Warning "Build-Release is deprecated. Deploying the GOG working runtime instead."
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

# Prepares free-text (description, changenote) for a KeyValues quoted value.
#
# SteamCMD's KeyValues parser does NOT process escape sequences in this file.
# Writing \" does not produce a quote -- the backslash is literal and the quote
# still closes the value, after which the parser hits the closing brace and
# fails with "got } in key in file workshopitem". Backslash escaping is wrong
# for the same reason: \\ would show up as two backslashes in the published
# text, and single backslashes (as in a Windows path) already pass through
# untouched, which is why the contentfolder value works.
#
# Raw newlines inside a quoted value ARE legal and are preserved, so multi-line
# descriptions need no transformation. The one character that cannot survive is
# a literal double quote; those become apostrophes, which keeps the file plain
# ASCII and renders sensibly in BBCode. Callers are told when it happens so the
# substitution is never silent.
function Escape-VdfText($text) {
    if ($null -eq $text) { return "" }

    $quoteCount = ([regex]::Matches($text, '"')).Count
    if ($quoteCount -gt 0) {
        Write-Host ("Note: replaced $quoteCount double quote(s) with apostrophes; " +
            "SteamCMD's VDF parser cannot represent them.") -ForegroundColor DarkYellow
    }

    return ($text -replace '"', "'")
}

# Steam rejects descriptions past this length.
$script:WorkshopDescriptionMaxLength = 8000

# Resolves the description text that should be sent with an upload, from either
# DescriptionFile or an inline Description. Returns $null when neither is set.
# Throws when a configured file is missing or unusable, because silently
# uploading without the description is exactly the failure this replaced.
function Get-WorkshopDescriptionText {
    param($Config)

    if ($Config.DescriptionFile) {
        if (-not (Test-Path -LiteralPath $Config.DescriptionFile)) {
            throw "DescriptionFile not found: $($Config.DescriptionFile)"
        }

        $text = Get-Content -LiteralPath $Config.DescriptionFile -Raw
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "DescriptionFile is empty: $($Config.DescriptionFile)"
        }

        return $text.TrimEnd()
    }

    if ($Config.Description) {
        return [string]$Config.Description
    }

    return $null
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
        "openshim.ini.payload",
        "openshim\renderer\enhanced\resources.version",
        "BZ_ASSETS_CORE\common\ui\CustomWidgets\uiline.png",
        "BZ_ASSETS_CORE\common\ui\CustomWidgets\uiplate.png",
        "BZ_ASSETS_CORE\common\ui\CustomWidgets\uibtn.png",
        "BZ_ASSETS_CORE\common\ui\CustomWidgets\uibtnhv.png",
        "RequireFix.lua",
        "ScriptSubtitles.lua",
        "OpenShimManifest.lua",
        "PersistentConfig.lua",
        "RuntimeEnhancements.lua",
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

    Write-Host "Verifying staged shipping binaries against their sibling builds..." -ForegroundColor Cyan
    Assert-StagedShippingBinaries $contentFolder

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

    # Explicit $null test, not a truthiness test: public is visibility 0, and
    # `if (0)` is false in PowerShell, so a configured 0 used to be dropped and
    # no visibility key was written at all.
    #
    # That mattered more than it looks. An upload that does not state a
    # visibility leaves the item hidden, and a hidden item rejects the NEXT
    # upload at the commit step with nothing but "Failed to update workshop item
    # (Access Denied)". Pinning it here makes each publish reassert the intended
    # visibility instead of silently taking the item off the Workshop.
    # 0 = public, 1 = friends only, 2 = private, 3 = unlisted.
    if ($null -ne $Config.Visibility -and "$($Config.Visibility)".Trim() -ne "") {
        $lines += "  `"visibility`" `"$([string]$Config.Visibility)`""
        Write-Host "Visibility: publishing as $($Config.Visibility) (0=public, 1=friends, 2=private, 3=unlisted)." -ForegroundColor DarkGray
    }
    else {
        Write-Host ("Warning: no Visibility configured. SteamCMD leaves the item HIDDEN after " +
            "upload, which makes the next upload fail with Access Denied. Set Visibility in " +
            "workshop.config.json.") -ForegroundColor Yellow
    }
    if ($Config.Title) { $lines += "  `"title`" `"$([string](Escape-VdfValue $Config.Title))`"" }
    # "description" is the only description key workshop_build_item understands.
    # This used to emit "descriptionfile" with a path whenever DescriptionFile
    # was configured, which SteamCMD does not recognise: it discarded the key,
    # reported "Committing update...Success.", updated the content, and left the
    # description untouched. Read the file and inline it instead.
    $descriptionText = Get-WorkshopDescriptionText -Config $Config
    if ($descriptionText) {
        if ($descriptionText.Length -gt $script:WorkshopDescriptionMaxLength) {
            throw ("Description is $($descriptionText.Length) characters; Steam allows " +
                "$script:WorkshopDescriptionMaxLength. Shorten it before uploading.")
        }

        $lines += "  `"description`" `"$([string](Escape-VdfText $descriptionText))`""
        Write-Host ("Description: including $($descriptionText.Length) characters" +
            $(if ($Config.DescriptionFile) { " from $($Config.DescriptionFile)" } else { "" })) -ForegroundColor DarkGray
    }
    else {
        Write-Host "Description: none configured; leaving the published description unchanged." -ForegroundColor DarkGray
    }

    if ($ChangeNote) { $lines += "  `"changenote`" `"$([string](Escape-VdfText $ChangeNote))`"" }

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
        Write-Error "ContentFolder not found: $($cfg.ContentFolder). Build the validated Workshop staging payload first."
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
    Write-Host "  - GOG working deploy target = $runtimeDirDisplay" -ForegroundColor DarkGray
    Write-Host "  - Steam = final verification after Workshop upload/download" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "1. Sync To Source (Pull GOG working runtime -> source tree)"
    Write-Host "2. Deploy GOG Test Mod (Flatten source tree -> GOG mods install)"
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
