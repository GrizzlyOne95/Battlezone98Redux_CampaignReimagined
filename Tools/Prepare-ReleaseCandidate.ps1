#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDir,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ChangeNote,
    [Parameter(Mandatory)][string]$OpenShimRepo,
    [Parameter(Mandatory)][string]$BzfileRepo,
    [Parameter(Mandatory)][string]$ExuRepo,
    [string]$BundleDir = 'Local\Workshop',
    [switch]$AllowDirty
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Assert-CampaignArchive {
    param([string]$ArchivePath, [string]$ManifestPath, [string]$Prefix = '')
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $files = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.EndsWith('/')) { continue }
            if ($Prefix -and -not $name.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
                if ($name -notin @('INSTALL.txt', 'CHANGELOG.md')) { throw "Unexpected archive file: $name" }
                continue
            }
            $relative = $name.Substring($Prefix.Length)
            if (-not $files.TryAdd($relative, $entry)) { throw "Duplicate archive file: $relative" }
        }
        $count = 0
        foreach ($line in Get-Content -LiteralPath $ManifestPath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -notmatch '^([0-9a-fA-F]{64})  ([0-9]+)  (.+)$') { throw "Malformed manifest: $line" }
            $expectedHash = $matches[1].ToLowerInvariant()
            $expectedLength = [long]$matches[2]
            $name = $matches[3].Replace('\', '/')
            if (-not $files.ContainsKey($name)) { throw "Archive is missing $name" }
            $entry = $files[$name]
            if ($entry.Length -ne $expectedLength) { throw "Archive size mismatch: $name" }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ($hash -ne $expectedHash) { throw "Archive SHA256 mismatch: $name" }
            [void]$files.Remove($name)
            $count++
        }
        if ($files.Count) { throw "Archive contains $($files.Count) unmanifested files." }
        Write-Host "Verified $count files in $(Split-Path $ArchivePath -Leaf)"
    }
    finally { $zip.Dispose() }
}
$campaign = Split-Path -Parent $PSScriptRoot
$output = [IO.Path]::GetFullPath($OutputDir)
$bundle = (Resolve-Path -LiteralPath $BundleDir).Path
if (Test-Path -LiteralPath $output) { throw 'Choose a new output directory; frozen candidates are never overwritten.' }
$sourceStates = [ordered]@{}
foreach ($pair in @(@{Name='Campaign';Path=$campaign},@{Name='OpenShim';Path=$OpenShimRepo},@{Name='Bzfile';Path=$BzfileRepo},@{Name='EXU';Path=$ExuRepo})) {
    $repo = $pair.Path
    & git -C $repo diff --quiet
    $dirty = $LASTEXITCODE -ne 0
    & git -C $repo diff --cached --quiet
    $dirty = $dirty -or $LASTEXITCODE -ne 0
    if ($dirty -and -not $AllowDirty) { throw "Commit tracked source changes before freezing, or use -AllowDirty for an explicitly marked working candidate: $repo" }
    $sourceStates[$pair.Name] = [ordered]@{TrackedDirty=$dirty; Files=@(& git -C $repo status --porcelain=v1 --untracked-files=normal)}
}
foreach ($required in @('content', 'content_manifest.sha256', 'workshop_build.vdf')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Missing staged input: $required" }
}
$identities = [ordered]@{
    Campaign = (& git -C $campaign rev-parse HEAD).Trim()
    OpenShim = (& git -C $OpenShimRepo rev-parse HEAD).Trim()
    Bzfile = (& git -C $BzfileRepo rev-parse HEAD).Trim()
    EXU = (& git -C $ExuRepo rev-parse HEAD).Trim()
}
$runtimeFiles = @(
    @{Source=Join-Path $OpenShimRepo 'bin\Release\winmm.dll'; Bundle='winmm.dll'},
    @{Source=Join-Path $OpenShimRepo 'bin\Release\bzloader.dll'; Bundle='bzloader.dll'},
    @{Source=Join-Path $OpenShimRepo 'bin\Release\plugins\openshim.dll'; Bundle='openshim.dll'},
    @{Source=Join-Path $BzfileRepo 'Release\bzfile.dll'; Bundle='bzfile.dll'},
    @{Source=Join-Path $BzfileRepo 'Release\bzfile_replace_helper.exe'; Bundle='bzfile_replace_helper.exe'},
    @{Source=Join-Path $ExuRepo 'Release\exu.dll'; Bundle='exu.dll'}
)
$runtime = @(foreach ($file in $runtimeFiles) {
    $hash = (Get-FileHash -LiteralPath $file.Source).Hash.ToLowerInvariant()
    if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $bundle ('content\' + $file.Bundle))).Hash.ToLowerInvariant()) {
        throw "Staged $($file.Bundle) differs from its source build."
    }
    [ordered]@{File=$file.Bundle; Sha256=$hash; Version=(Get-Item -LiteralPath $file.Source).VersionInfo.FileVersion}
})
New-Item -ItemType Directory -Path $output | Out-Null
$workshop = Join-Path $output 'Workshop'
Copy-Item -LiteralPath $bundle -Destination $workshop -Recurse
Copy-Item -LiteralPath (Join-Path $campaign 'CHANGELOG.md') -Destination $workshop
[IO.File]::WriteAllText((Join-Path $output 'CHANGE_NOTE.txt'), $ChangeNote + "`n", [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $OpenShimRepo 'Docs\STEAM_ROADMAP_BBCODE.txt') -Destination (Join-Path $output 'ROADMAP_BBCODE.txt')
# Point the frozen VDF at the frozen content, including its own thumbnail.
$vdf = Join-Path $workshop 'workshop_build.vdf'
$vdfText = [IO.File]::ReadAllText($vdf)
$contentPath = (Join-Path $workshop 'content') -replace '\\', '/'
$vdfText = $vdfText -replace '("contentfolder"\s+")[^"]*(")', ('${1}' + $contentPath + '${2}')
$vdfText = $vdfText -replace '("previewfile"\s+")[^"]*(")', ('${1}' + $contentPath + '/campaignReimagined.jpg${2}')
[IO.File]::WriteAllText($vdf, $vdfText, [Text.UTF8Encoding]::new($false))
$manual = Join-Path $output 'Manual'
& (Join-Path $campaign '.github\scripts\Build-Level1Release.ps1') -BundleDir $workshop -OutputDir $manual `
    -Version $Version -ChangeNote $ChangeNote -CampaignCommit $identities.Campaign -OpenShimCommit $identities.OpenShim
if ($LASTEXITCODE -ne 0) { throw 'Manual package preparation failed.' }
$native = Join-Path $output 'Native'
$suite = Join-Path $native 'OpenShim-Suite'
foreach ($directory in @('bin\Release\plugins','scripts','resources\renderer','resources\ui','resources\openshim','upload')) {
    New-Item -ItemType Directory -Path (Join-Path $suite $directory) -Force | Out-Null
}
foreach ($name in @('winmm.dll','winmm.pdb','bzloader.dll','bzloader.pdb','plugins\openshim.dll','plugins\openshim.pdb')) {
    Copy-Item -LiteralPath (Join-Path $OpenShimRepo ('bin\Release\' + $name)) -Destination (Join-Path $suite ('bin\Release\' + $name))
}
foreach ($name in @('openshim.ini','openshim.ini.example','net.ini','scripts\patches.json','resources\openshim\OpenShimAssets.ini')) {
    Copy-Item -LiteralPath (Join-Path $OpenShimRepo $name) -Destination (Join-Path $suite $name)
}
foreach ($name in @('resources\renderer\enhanced','resources\ui\custom_widgets')) {
    Copy-Item -LiteralPath (Join-Path $OpenShimRepo $name) -Destination (Join-Path $suite $name) -Recurse
}
foreach ($name in @('openshim_wrap.ps1','openshim_wrap.bat','openshim_wrap.sh')) {
    Copy-Item -LiteralPath (Join-Path $OpenShimRepo ('upload\' + $name)) -Destination (Join-Path $suite ('upload\' + $name))
}
[ordered]@{FormatVersion=1; Tag='candidate/' + $Version; Commit=$identities.OpenShim; Architecture='x86'; BuiltAtUtc=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $suite 'release_metadata.json') -Encoding UTF8
$sums = @(foreach ($file in Get-ChildItem -LiteralPath (Join-Path $suite 'bin') -File -Recurse) {
    (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() + '  ' + $file.Name
})
foreach ($name in @('openshim.ini','openshim.ini.example','net.ini','scripts\patches.json')) {
    $sums += (Get-FileHash -LiteralPath (Join-Path $suite $name)).Hash.ToLowerInvariant() + '  ' + (Split-Path $name -Leaf)
}
[IO.File]::WriteAllText((Join-Path $suite 'SHA256SUMS.txt'), ($sums -join "`n") + "`n", [Text.Encoding]::ASCII)
& (Join-Path $OpenShimRepo 'scripts\Test-PackageShape.ps1') -Root $suite -Layout Suite -ExpectedVersion $runtime[0].Version -ExpectedCommit $identities.OpenShim
Compress-Archive -Path (Join-Path $suite '*') -DestinationPath (Join-Path $native 'OpenShim-Suite.zip') -CompressionLevel Optimal
foreach ($dependency in @(@{Name='bzfile'; Repo=$BzfileRepo; Files=@('bzfile.dll','bzfile.pdb','bzfile_replace_helper.exe','bzfile_replace_helper.pdb')}, @{Name='EXU'; Repo=$ExuRepo; Files=@('exu.dll','exu.pdb')})) {
    $stage = Join-Path $native $dependency.Name
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($name in $dependency.Files) { Copy-Item -LiteralPath (Join-Path $dependency.Repo ('Release\' + $name)) -Destination $stage }
    Copy-Item -LiteralPath (Join-Path $dependency.Repo 'README.md') -Destination $stage
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $native ($dependency.Name + '-native.zip')) -CompressionLevel Optimal
}
foreach ($package in @(@{Name='OpenShim-Suite';Stage=$suite;Archive='OpenShim-Suite.zip'},@{Name='bzfile';Stage=(Join-Path $native 'bzfile');Archive='bzfile-native.zip'},@{Name='EXU';Stage=(Join-Path $native 'EXU');Archive='EXU-native.zip'})) {
    $manifestPath = Join-Path $native ($package.Name + '.files.sha256')
    $lines = @(foreach ($file in Get-ChildItem -LiteralPath $package.Stage -File -Recurse | Sort-Object FullName) {
        (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() + '  ' + $file.Length + '  ' + [IO.Path]::GetRelativePath($package.Stage,$file.FullName).Replace('\','/')
    })
    [IO.File]::WriteAllText($manifestPath,($lines -join "`n") + "`n",[Text.UTF8Encoding]::new($false))
    Assert-CampaignArchive -ArchivePath (Join-Path $native $package.Archive) -ManifestPath $manifestPath
}
# Validate the actual archived chain and metadata, not only the pre-ZIP tree.
$extractedSuite = Join-Path $output 'Verification\OpenShim-Suite'
Expand-Archive -LiteralPath (Join-Path $native 'OpenShim-Suite.zip') -DestinationPath $extractedSuite
& (Join-Path $OpenShimRepo 'scripts\Test-PackageShape.ps1') -Root $extractedSuite -Layout Suite -ExpectedVersion $runtime[0].Version -ExpectedCommit $identities.OpenShim
Compress-Archive -Path (Join-Path $workshop 'content\*') -DestinationPath (Join-Path $output ('CampaignReimagined-' + $Version + '-Workshop.zip')) -CompressionLevel Optimal
Assert-CampaignArchive -ArchivePath (Join-Path $output ('CampaignReimagined-' + $Version + '-Workshop.zip')) -ManifestPath (Join-Path $workshop 'content_manifest.sha256')
Assert-CampaignArchive -ArchivePath (Join-Path $manual ('CampaignReimagined-' + $Version + '-ModDB.zip')) -ManifestPath (Join-Path $workshop 'content_manifest.sha256') -Prefix 'mods/3686673790/'
$archives = @(foreach ($file in Get-ChildItem -LiteralPath $output -Filter '*.zip' -Recurse -File) {
    $hash = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($file.FullName + '.sha256'), $hash + '  ' + $file.Name + "`n", [Text.Encoding]::ASCII)
    [ordered]@{File=[IO.Path]::GetRelativePath($output,$file.FullName); Bytes=$file.Length; Sha256=$hash}
})
[ordered]@{
    SchemaVersion=2; Version=$Version; Status='prepared-candidate'; Commits=$identities; SourceStates=$sourceStates;
    Runtime=$runtime; Archives=$archives; FileCount=@(Get-ChildItem -LiteralPath (Join-Path $workshop 'content') -File -Recurse).Count;
    ManifestSha256=(Get-FileHash -LiteralPath (Join-Path $workshop 'content_manifest.sha256')).Hash.ToLowerInvariant();
    CampaignArchivesVerified=$true; NativeArchivesVerified=$true; PubliclyPublished=$false; PreparedAtUtc=[DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'candidate_receipt.json') -Encoding UTF8
Write-Host "Frozen candidate packages: $output"
