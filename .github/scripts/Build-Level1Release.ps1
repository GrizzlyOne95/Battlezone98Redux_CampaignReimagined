param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$ChangeNote,

    [ValidateSet("Full Version", "Patch")]
    [string]$ModDbReleaseType = "Full Version",

    [string]$CampaignCommit = "",
    [string]$OpenShimCommit = "",
    [string]$DriveFolderUrl = "https://drive.google.com/drive/folders/1vORbih4z8QKXTdwwzHfS_-81-izYW0uv"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$') {
    throw "Version '$Version' contains unsupported characters. Use letters, numbers, dot, underscore, or hyphen."
}

$bundle = [System.IO.Path]::GetFullPath($BundleDir)
$output = [System.IO.Path]::GetFullPath($OutputDir)
$content = Join-Path $bundle "content"
$manifest = Join-Path $bundle "content_manifest.sha256"
$changelog = Join-Path $bundle "CHANGELOG.md"

foreach ($required in @($content, $manifest)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Release bundle is missing required path '$required'."
    }
}

# Re-verify the immutable payload before wrapping it for ModDB/manual distribution.
$contentRoot = [System.IO.Path]::GetFullPath($content).TrimEnd('\', '/') + '\'
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }
    if ($line -notmatch '^([0-9a-fA-F]{64})  ([0-9]+)  (.+)$') {
        throw "Malformed manifest line: $line"
    }

    $expectedHash = $matches[1].ToLowerInvariant()
    $expectedLength = [Int64]$matches[2]
    $relativePath = $matches[3]
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $content $relativePath))

    if (-not $fullPath.StartsWith($contentRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escaped the content root: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Manifest file is missing: $relativePath"
    }

    $item = Get-Item -LiteralPath $fullPath
    if ($item.Length -ne $expectedLength) {
        throw "Size mismatch for '$relativePath'."
    }

    $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "SHA256 mismatch for '$relativePath'."
    }
}

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

$stage = Join-Path $output "_moddb_stage"
$modRoot = Join-Path $stage "mods\3686673790"
New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
Copy-Item -Path (Join-Path $content '*') -Destination $modRoot -Recurse -Force

$installText = @"
Campaign Reimagined $Version
Battlezone 98 Redux

INSTALLATION
1. Close Battlezone 98 Redux.
2. Extract this ZIP directly into the Battlezone 98 Redux installation directory.
3. Confirm the resulting path is: mods\3686673790\
4. Start Battlezone 98 Redux and launch Campaign Reimagined.

This archive contains the same manifest-validated campaign payload used by the Steam Workshop release workflow. Campaign Reimagined includes native OpenShim integration; restart the game when prompted if the native DLL is installed or updated.

Steam Workshop item: 3686673790
Campaign commit: $CampaignCommit
OpenShim commit: $OpenShimCommit
"@
Set-Content -LiteralPath (Join-Path $stage "INSTALL.txt") -Value $installText -Encoding UTF8

if (Test-Path -LiteralPath $changelog) {
    Copy-Item -LiteralPath $changelog -Destination (Join-Path $stage "CHANGELOG.md") -Force
}

$zipName = "CampaignReimagined-$Version-ModDB.zip"
$zipPath = Join-Path $output $zipName
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force

$zipItem = Get-Item -LiteralPath $zipPath
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumName = "$zipName.sha256"
Set-Content -LiteralPath (Join-Path $output $checksumName) -Value "$zipHash  $zipName" -Encoding ASCII

$description = @"
Campaign Reimagined $Version

Campaign Reimagined is an unofficial overhaul and community patch for Battlezone 98 Redux, combining rewritten campaign logic, shared Lua gameplay systems, replacement maps and assets, renderer content, and native OpenShim integration.

Release type: $ModDbReleaseType
Version: $Version

CHANGE NOTES
$ChangeNote

INSTALLATION
Extract the archive into the Battlezone 98 Redux installation directory so the campaign is installed under mods\3686673790. Close the game before updating. Restart the game when prompted if Campaign Reimagined updates the native OpenShim DLL.

This ModDB-ready archive is generated from the same manifest-validated content used for the Steam Workshop publication. It is prepared automatically, but Level 1 publishing intentionally leaves the final ModDB web-form submission to a human uploader.
"@
Set-Content -LiteralPath (Join-Path $output "moddb_description.txt") -Value $description -Encoding UTF8

$metadata = [ordered]@{
    SchemaVersion = 1
    Product = "Campaign Reimagined"
    Game = "Battlezone 98 Redux"
    Version = $Version
    ModDbReleaseType = $ModDbReleaseType
    SuggestedTitle = "Campaign Reimagined $Version"
    ChangeNote = $ChangeNote
    FileName = $zipName
    FileSizeBytes = $zipItem.Length
    FileSha256 = $zipHash
    SteamAppId = "301650"
    SteamWorkshopPublishedFileId = "3686673790"
    CampaignCommit = $CampaignCommit
    OpenShimCommit = $OpenShimCommit
    DriveArchiveFolderUrl = $DriveFolderUrl
    PreparedAtUtc = [DateTime]::UtcNow.ToString("o")
    FinalModDbSubmissionRequired = $true
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output "moddb_submission.json") -Encoding UTF8

$receipt = [ordered]@{
    Version = $Version
    CampaignCommit = $CampaignCommit
    OpenShimCommit = $OpenShimCommit
    ReleaseZip = $zipName
    ReleaseZipSha256 = $zipHash
    ReleaseZipSizeBytes = $zipItem.Length
    SteamWorkshopPublishedFileId = "3686673790"
    ModDb = [ordered]@{
        Status = "prepared"
        FinalSubmissionRequired = $true
        ReleaseType = $ModDbReleaseType
    }
    Drive = [ordered]@{
        Status = "prepared-for-archive"
        FolderUrl = $DriveFolderUrl
    }
    PreparedAtUtc = [DateTime]::UtcNow.ToString("o")
}
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output "release_receipt.json") -Encoding UTF8

Remove-Item -LiteralPath $stage -Recurse -Force

Write-Host "Prepared Level 1 release package: $zipPath"
Write-Host "SHA256: $zipHash"
