
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
# Authoring-only trees. These are development inputs -- CI definitions, the
# scripts that generate assets, and the shipping lock itself -- not mod content.
$SourceExcludedRelativePaths = @(
    ".git",
    ".github",
    # Legacy byte-identical copies; BZ_ASSETS_CORE is the runtime source.
    "Assets\CustomWidgets",
    "docs",
    "Local",
    "References",
    "Shipping",
    "Tools"
)
$SourceExcludedRootFiles = @(
    ".gitignore",
    "AGENTS.md",
    "CHANGELOG.md",
    "Config\net.ini",
    "LICENSE.md",
    "Manage-CampaignFiles.ps1",
    "NOTICE.md",
    # Runtime copies can be left at the repository root by older deploy flows.
    # InstallerPayload/Bin are authoritative; ignoring these avoids collisions
    # when rebuilding the shipping lock from a working tree with legacy files.
    "openshim_net.ini.payload",
    "openshim_patches.json.payload",
    "README.md",
    "winmm.dll",
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

# Every file in the repo that deploy *could* ship. This is a candidate set, not
# the shipping set: what actually ships is the intersection with the shipping
# lock (see Get-ShippingLock). Committing a file no longer puts it in players'
# installs by itself.
function Get-ManagedSourceFilesUnfiltered {
    if (-not (Test-Path $SourceDir)) {
        return @()
    }

    Get-ChildItem -Path $SourceDir -Recurse -File | Where-Object {
        $relativePath = Get-RelativePathFromBase $SourceDir $_.FullName
        -not (Is-ExcludedSourceRelativePath $relativePath) -and
        $_.Extension -ne ".pdb"
    }
}

$ShippingLockRelativePath = "Shipping\shipping.lock.json"

function Get-ShippingLockPath {
    return (Join-Path $SourceDir $ShippingLockRelativePath)
}

# The shipping lock is the explicit list of what this mod installs. It records
# membership only -- source path and the runtime path it lands on -- never
# content hashes, so editing a texture or a mission script needs no ceremony.
# Adding or removing a *file* does, and shows up as a reviewable diff. That is
# the whole point: an unrelated commit cannot quietly grow the install.
function Get-ShippingLock {
    $lockPath = Get-ShippingLockPath
    if (-not (Test-Path -LiteralPath $lockPath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Shipping lock '$lockPath' is unreadable: $_"
    }

    $bySource = @{}
    foreach ($entry in @($raw.files)) {
        $bySource[$entry.source] = $entry.runtime
    }

    return [pscustomobject]@{
        Path     = $lockPath
        BySource = $bySource
        Count    = $bySource.Count
    }
}

# Resolve the candidate set against the lock and report the ways they disagree.
# Unblessed files are skipped rather than shipped, and files the lock names but
# the repo no longer has are called out instead of silently vanishing.
function Resolve-ShippingSet {
    $candidates = @(Get-ManagedSourceFilesUnfiltered)
    $lock = Get-ShippingLock

    if (-not $lock) {
        return [pscustomobject]@{
            Files = $candidates; Unblessed = @(); Missing = @(); HasLock = $false
        }
    }

    $shipped = New-Object System.Collections.Generic.List[object]
    $unblessed = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($file in $candidates) {
        $relativePath = Get-RelativePathFromBase $SourceDir $file.FullName
        if ($lock.BySource.ContainsKey($relativePath)) {
            $shipped.Add($file)
            $seen[$relativePath] = $true
        }
        else {
            $unblessed.Add($relativePath)
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in $lock.BySource.Keys) {
        if (-not $seen.ContainsKey($relativePath)) {
            $missing.Add($relativePath)
        }
    }

    return [pscustomobject]@{
        Files     = $shipped.ToArray()
        Unblessed = ($unblessed | Sort-Object)
        Missing   = ($missing | Sort-Object)
        HasLock   = $true
    }
}

function Write-ShippingSetReport($resolved) {
    if (-not $resolved.HasLock) {
        Write-Host ("No shipping lock at $ShippingLockRelativePath - shipping every candidate file. " +
            "Run -bless to create one.") -ForegroundColor Yellow
        return
    }

    if ($resolved.Unblessed.Count -gt 0) {
        Write-Host ""
        Write-Host ("NOT SHIPPED - $($resolved.Unblessed.Count) file(s) are in the repo but not in " +
            "the shipping lock:") -ForegroundColor Yellow
        foreach ($relativePath in $resolved.Unblessed) {
            Write-Host "    $relativePath" -ForegroundColor DarkYellow
        }
        Write-Host "  Review them, then run -bless to add them to the lock." -ForegroundColor Yellow
    }

    if ($resolved.Missing.Count -gt 0) {
        Write-Host ""
        Write-Host ("LOCKED BUT ABSENT - $($resolved.Missing.Count) file(s) are in the shipping lock " +
            "but not in the repo:") -ForegroundColor Red
        foreach ($relativePath in $resolved.Missing) {
            Write-Host "    $relativePath" -ForegroundColor Red
        }
        Write-Host "  Restore them, or run -bless to drop them from the lock." -ForegroundColor Red
    }
}

function Get-ManagedSourceFiles {
    $resolved = Resolve-ShippingSet
    Write-ShippingSetReport $resolved
    return $resolved.Files
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

# The opt-in session log uploader. Campaign Reimagined ships a copy so a
# Workshop subscriber on the test crew does not have to fetch it from GitHub
# separately, but openshim\support\ is a cache of the OpenShim repository's
# upload\ directory, never an independent source -- same rule as Bin\.
#
# Shipping these files activates nothing. The wrapper only ever runs if it is
# in the Steam launch options, and it only ever uploads if a webhook has been
# configured locally. Neither is done by installing the mod, and no webhook is
# in this repository or in the payload.
function Sync-SupportWrapper {
    $openShimRepo = Resolve-SiblingRepoRoot "BZR_OPENSHIM_REPO" "GIT\BZR-OpenShim"
    $sourceDirUpload = Join-Path $openShimRepo "upload"
    $destDir = Join-Path $SourceDir "openshim\support"
    $wrapperFiles = @("openshim_wrap.ps1", "openshim_wrap.bat", "openshim_wrap.sh")

    # Fail before copying anything, so a half-refreshed support folder is never
    # left behind for the payload to pick up.
    foreach ($name in $wrapperFiles) {
        $src = Join-Path $sourceDirUpload $name
        if (-not (Test-Path -LiteralPath $src)) {
            throw ("Cannot refresh the bundled support wrapper because '$src' does not exist. " +
                "Point `$env:BZR_OPENSHIM_REPO at the OpenShim repository that provides upload\.")
        }
    }

    foreach ($name in $wrapperFiles) {
        [void](Copy-BundledFileIfDifferent `
            (Join-Path $sourceDirUpload $name) (Join-Path $destDir $name) "OpenShim support wrapper $name")
    }

    # openshim\ is generated and untracked, so the reader-facing README cannot
    # live there. Its source of truth is Docs\, which is tracked but excluded
    # from the payload; this copy is what subscribers actually get.
    $readmeSource = Join-Path $SourceDir "Docs\openshim_support_README.txt"
    if (-not (Test-Path -LiteralPath $readmeSource)) {
        throw "Cannot stage the support wrapper without its README: '$readmeSource' is missing."
    }
    [void](Copy-BundledFileIfDifferent $readmeSource (Join-Path $destDir "README.txt") "OpenShim support README")

    # A webhook must never reach the payload. upload.conf is where the wrapper
    # stores one locally, so refuse to ship anything by that name.
    $leaked = Get-ChildItem -Path $destDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "upload.conf" }
    if ($leaked) {
        throw "Refusing to stage '$($leaked[0].FullName)': a saved webhook must never ship."
    }

    # Match a real webhook (numeric id + token), not the bare /api/webhooks/
    # prefix: the wrapper legitimately contains that prefix in its own URL
    # validation regex and in a help string.
    foreach ($f in (Get-ChildItem -Path $destDir -Recurse -File -ErrorAction SilentlyContinue)) {
        if (Select-String -LiteralPath $f.FullName -Pattern 'discord(app)?\.com/api/webhooks/[0-9]{5,}/[A-Za-z0-9_-]{20,}' -Quiet) {
            throw "Refusing to stage '$($f.FullName)': it contains a Discord webhook URL."
        }
    }
}
function Update-OpenShimManifest {
    Sync-ShippingBinaries | Out-Null
    Sync-SupportWrapper

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
        "        playerConfig = { source = `"openshim.ini.payload`", destination = `"openshim.ini`", sha256 = `"$playerConfigHash`", size = $($playerConfigItem.Length), overwrite = false },"
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
                # Compare by content, never by timestamp. A modification time
                # records when a file was written locally -- a fresh checkout, a
                # Drive sync, a deploy from the wrong tree -- not which copy is
                # correct. The old "source is newer" rule silently refused to
                # repair an install that had been written from a stale clone,
                # because those wrong files carried the newer timestamps.
                $hashMatch = Test-FilesMatchByHash $file.FullName $runtimePath

                if ($hashMatch -ne $true) {
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
#
# Publishing a description is opt-in. The live Workshop description is edited
# by hand on Steam between releases, and an upload that always sent this file
# would silently revert those edits -- a content push and a description
# rewrite are different intentions and should not travel together. Set
# PublishDescription to true in workshop.config.json only when you actually
# mean to replace what is live.
function Get-WorkshopDescriptionText {
    param($Config)

    if (-not $Config.PublishDescription) {
        return $null
    }

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
        Write-Error ("Missing publish config: $configPath`n" +
            "  Run:  .\Manage-CampaignFiles.ps1 -workshop-init`n" +
            "  then set SteamUser in workshop.config.json (or define STEAM_USERNAME).`n" +
            "  The file is per-machine and gitignored, so a fresh clone never has one.")
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
    if ($null -eq $cfg.PublishDescription) {
        $cfg | Add-Member -NotePropertyName PublishDescription -NotePropertyValue $false
    }
    $cfg.PublishDescription = [bool]$cfg.PublishDescription
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
        "openshim\support\openshim_wrap.ps1",
        "openshim\support\openshim_wrap.bat",
        "openshim\support\openshim_wrap.sh",
        "openshim\support\README.txt",
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
    elseif ($Config.DescriptionFile -or $Config.Description) {
        Write-Host ("Description: NOT published; the live Steam description is left exactly as it is. " +
            "A description is configured but PublishDescription is false, which is the default so a " +
            "content push never reverts hand edits made on Steam. Set PublishDescription to true when " +
            "you intend to replace it.") -ForegroundColor DarkGray
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

# Regenerate the shipping lock from what is in the repo right now, and show what
# that changes about the install. This is the deliberate, reviewable step that
# admits a new file into players' installs -- or drops one.
function Invoke-BlessShipping {
    Write-Host "Rebuilding the shipping lock from $SourceDir ..." -ForegroundColor Cyan

    $previous = Get-ShippingLock
    $entries = @{}
    $collisions = @{}

    foreach ($file in @(Get-ManagedSourceFilesUnfiltered)) {
        $sourceRelative = Get-RelativePathFromBase $SourceDir $file.FullName
        foreach ($runtimeRelative in Get-DeployRelativePathsFromSourcePath $file.FullName) {
            if (-not $collisions.ContainsKey($runtimeRelative)) {
                $collisions[$runtimeRelative] = New-Object System.Collections.Generic.List[string]
            }
            $collisions[$runtimeRelative].Add($sourceRelative)
            $entries[$sourceRelative] = $runtimeRelative
        }
    }

    # Deploy flattens most of the tree to a bare filename, so two source files
    # sharing a basename land on one runtime path and whichever is copied last
    # silently wins. Refuse to bless that rather than encode it.
    $clashes = @($collisions.Keys | Where-Object { $collisions[$_].Count -gt 1 } | Sort-Object)
    if ($clashes.Count -gt 0) {
        Write-Host ""
        Write-Host "Refusing to bless: $($clashes.Count) runtime path(s) claimed by more than one source file." -ForegroundColor Red
        foreach ($runtimeRelative in $clashes) {
            Write-Host "    $runtimeRelative" -ForegroundColor Red
            foreach ($sourceRelative in $collisions[$runtimeRelative]) {
                Write-Host "        <- $sourceRelative" -ForegroundColor DarkYellow
            }
        }
        Write-Host "  Rename or remove one side of each pair, then bless again." -ForegroundColor Red
        return $false
    }

    $ordered = @($entries.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{ source = $_; runtime = $entries[$_] }
    })

    $lockPath = Get-ShippingLockPath
    $lockDir = Split-Path $lockPath -Parent
    if (-not (Test-Path -LiteralPath $lockDir)) {
        New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
    }

    $payload = [ordered]@{
        comment   = "Explicit list of what Campaign Reimagined installs. Membership only, no hashes: editing a shipped file is free, adding or removing one is a reviewable diff. Regenerate with Manage-CampaignFiles.ps1 -bless."
        generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        count     = $ordered.Count
        files     = $ordered
    }
    ($payload | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $lockPath -Encoding UTF8

    if ($previous) {
        $before = [System.Collections.Generic.HashSet[string]]::new([string[]]@($previous.BySource.Keys))
        $after = [System.Collections.Generic.HashSet[string]]::new([string[]]@($entries.Keys))
        $added = @($entries.Keys | Where-Object { -not $before.Contains($_) } | Sort-Object)
        $removed = @($previous.BySource.Keys | Where-Object { -not $after.Contains($_) } | Sort-Object)

        Write-Host ""
        Write-Host "Shipping lock: $($previous.Count) -> $($ordered.Count) files" -ForegroundColor Cyan
        foreach ($relativePath in $added) {
            Write-Host "    + $relativePath" -ForegroundColor Green
        }
        foreach ($relativePath in $removed) {
            Write-Host "    - $relativePath" -ForegroundColor DarkYellow
        }
        if ($added.Count -eq 0 -and $removed.Count -eq 0) {
            Write-Host "    (no membership change)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host ""
        Write-Host "Created $ShippingLockRelativePath with $($ordered.Count) files." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Review the diff of $ShippingLockRelativePath before committing." -ForegroundColor Cyan
    return $true
}

# Read-only comparison of the installed runtime against the lock. Answers "is my
# install clean?" without writing anything, which -deploy cannot do.
function Invoke-VerifyInstall {
    $runtimeDir = Resolve-RuntimeModDir
    if (-not $runtimeDir) {
        Write-Host "No runtime mod directory found. Expected '$DefaultTestingRuntimeDir'." -ForegroundColor Red
        return $false
    }

    Write-Host "Verifying $runtimeDir against the shipping lock..." -ForegroundColor Cyan
    $resolved = Resolve-ShippingSet
    Write-ShippingSetReport $resolved

    $expected = @{}
    $absent = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]

    foreach ($file in $resolved.Files) {
        foreach ($runtimeRelative in Get-DeployRelativePathsFromSourcePath $file.FullName) {
            $expected[$runtimeRelative] = $true
            $runtimePath = Join-Path $runtimeDir $runtimeRelative
            if (-not (Test-Path -LiteralPath $runtimePath)) {
                $absent.Add($runtimeRelative)
                continue
            }
            if ((Test-FilesMatchByHash $file.FullName $runtimePath) -eq $false) {
                $changed.Add($runtimeRelative)
            }
        }
    }

    $extra = New-Object System.Collections.Generic.List[string]
    foreach ($runtimeFile in @(Get-ManagedFlatFiles $runtimeDir; Get-StructuredRuntimeFiles $runtimeDir)) {
        $runtimeRelative = Get-RelativePathFromBase $runtimeDir $runtimeFile.FullName
        if (-not $runtimeRelative) { continue }
        if ($expected.ContainsKey($runtimeRelative)) { continue }
        if (Is-PreservedRuntimeRelativePath $runtimeRelative) { continue }
        $extra.Add($runtimeRelative)
    }

    Write-Host ""
    Write-Host "  shipped files expected : $($expected.Count)" -ForegroundColor Cyan
    Write-Host "  missing from install   : $($absent.Count)"   -ForegroundColor $(if ($absent.Count) { "Red" } else { "Green" })
    Write-Host "  content differs        : $($changed.Count)"  -ForegroundColor $(if ($changed.Count) { "Yellow" } else { "Green" })
    Write-Host "  unexpected in install  : $($extra.Count)"    -ForegroundColor $(if ($extra.Count) { "Yellow" } else { "Green" })

    if ($absent.Count) {
        Write-Host ""
        Write-Host "MISSING:" -ForegroundColor Red
        foreach ($p in ($absent | Sort-Object)) { Write-Host "    $p" -ForegroundColor Red }
    }
    if ($changed.Count) {
        Write-Host ""
        Write-Host "DIFFERENT (install does not match repo):" -ForegroundColor Yellow
        foreach ($p in ($changed | Sort-Object)) { Write-Host "    $p" -ForegroundColor DarkYellow }
    }
    if ($extra.Count) {
        Write-Host ""
        Write-Host "UNEXPECTED (in install, not shipped by this repo):" -ForegroundColor Yellow
        foreach ($p in ($extra | Sort-Object)) { Write-Host "    $p" -ForegroundColor DarkYellow }
    }

    $clean = ($absent.Count -eq 0 -and $changed.Count -eq 0 -and $extra.Count -eq 0 -and
              $resolved.Unblessed.Count -eq 0 -and $resolved.Missing.Count -eq 0)
    Write-Host ""
    if ($clean) {
        Write-Host "Install matches the shipping lock." -ForegroundColor Green
    }
    else {
        Write-Host "Install does NOT match the shipping lock." -ForegroundColor Yellow
    }
    return $clean
}

# Every action this script dispatches on below. Kept beside the dispatch
# chain so a newly added action also appears in the unrecognized-action
# message instead of going missing from it.
$KnownActions = @(
    "-sync",
    "-fromsource",
    "-deploy",
    "-release",
    "-bless",
    "-verify",
    "-addon",
    "-workshop-build",
    "-workshop-auth",
    "-workshop-init",
    "-workshop-upload",
    "-publish"
)

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
elseif ($args[0] -eq "-bless") {
    if (-not (Invoke-BlessShipping)) { exit 1 }
}
elseif ($args[0] -eq "-verify") {
    if (-not (Invoke-VerifyInstall)) { exit 1 }
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
elseif ($args[0] -eq "-workshop-init") {
    # workshop.config.json is per-machine and gitignored, so every fresh clone
    # hits the same wall: the publish actions abort on a missing file with no
    # obvious next step. Scaffold it from the tracked example and say exactly
    # what still has to be filled in.
    $target = Join-Path $RepoRoot "workshop.config.json"
    $example = Join-Path $RepoRoot "workshop.config.example.json"
    if (Test-Path -LiteralPath $target) {
        Write-Host "workshop.config.json already exists; leaving it alone." -ForegroundColor Yellow
    }
    elseif (-not (Test-Path -LiteralPath $example)) {
        Write-Error "workshop.config.example.json is missing; cannot scaffold."
        exit 1
    }
    else {
        Copy-Item -LiteralPath $example -Destination $target
        Write-Host "Created workshop.config.json from the example." -ForegroundColor Green
    }
    $cfg = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
    if (-not $cfg.SteamUser -and -not $env:STEAM_USERNAME) {
        Write-Host ("Still required: SteamUser (the Steam account that can update item " +
            "$WorkshopPublishedFileId), either in workshop.config.json or as STEAM_USERNAME.") -ForegroundColor Yellow
    }
    Write-Host "PublishDescription is $([bool]$cfg.PublishDescription); leave it false unless this run is meant to replace the live Steam description." -ForegroundColor DarkGray
    Write-Host "Then: -workshop-auth (once per machine), -workshop-build (dry run), -workshop-upload `"<change note>`"." -ForegroundColor DarkGray
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
elseif ($args.Count -eq 0) {
    # The genuine interactive case: no action was asked for at all.
    Show-Menu
}
else {
    # An unrecognized action used to fall through to the interactive menu,
    # which made a broken invocation indistinguishable from a successful
    # one: the menu banner scrolled past, the script exited 0, and nothing
    # was staged or uploaded. A wrapper that swallows the action reaches
    # here too. Say exactly what arrived and fail loudly.
    Write-Host ""
    Write-Host "Unrecognized action: '$($args[0])'" -ForegroundColor Red
    Write-Host "Received $($args.Count) argument(s):" -ForegroundColor Red
    for ($i = 0; $i -lt $args.Count; $i++) {
        Write-Host "  [$i] <$($args[$i])>" -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "Supported actions:" -ForegroundColor Yellow
    foreach ($known in $KnownActions) {
        Write-Host "  $known" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Run this script with no arguments for the interactive menu." -ForegroundColor DarkGray
    Write-Host ("If you invoked it through a wrapper, the wrapper may have consumed the " +
        "action itself; the action must reach this script as `$args[0].") -ForegroundColor DarkGray
    exit 2
}
