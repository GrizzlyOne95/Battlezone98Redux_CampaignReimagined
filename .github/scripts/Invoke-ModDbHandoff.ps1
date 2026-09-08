[CmdletBinding()]
param(
    [string]$ReleaseDir = $PSScriptRoot,
    [string]$BrowserPath = "",
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-OperaPath {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolved = [System.IO.Path]::GetFullPath($ExplicitPath)
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "Configured browser executable does not exist: '$resolved'."
        }
        return $resolved
    }

    $runningOpera = Get-Process -Name "opera" -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path -PathType Leaf) } |
        Select-Object -First 1 -ExpandProperty Path
    if ($runningOpera) {
        return $runningOpera
    }

    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "Opera GX\opera.exe"
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "Opera GX\opera.exe"
    }
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "Programs\Opera GX\opera.exe"
        $candidates += Join-Path $env:LOCALAPPDATA "Programs\Opera\opera.exe"
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    return $null
}

$releaseRoot = [System.IO.Path]::GetFullPath($ReleaseDir)
$metadataPath = Join-Path $releaseRoot "moddb_submission.json"
$descriptionPath = Join-Path $releaseRoot "moddb_description.txt"

foreach ($required in @($metadataPath, $descriptionPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Mod DB handoff is missing required file '$required'."
    }
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
foreach ($property in @("SuggestedTitle", "Version", "ModDbReleaseType", "FileName", "FileSizeBytes", "FileSha256", "ModDbUploadUrl")) {
    if (-not $metadata.PSObject.Properties.Name.Contains($property) -or
        [string]::IsNullOrWhiteSpace([string]$metadata.$property)) {
        throw "Mod DB metadata is missing required property '$property'."
    }
}

$uploadUri = $null
if (-not [Uri]::TryCreate([string]$metadata.ModDbUploadUrl, [UriKind]::Absolute, [ref]$uploadUri) -or
    $uploadUri.Scheme -ne "https" -or
    $uploadUri.Host -ne "www.moddb.com") {
    throw "Refusing to open an untrusted Mod DB upload URL: '$($metadata.ModDbUploadUrl)'."
}

$fileName = [string]$metadata.FileName
if ([System.IO.Path]::IsPathRooted($fileName) -or
    [System.IO.Path]::GetFileName($fileName) -ne $fileName) {
    throw "Mod DB metadata contains an unsafe archive file name: '$fileName'."
}
if ([string]$metadata.FileSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "Mod DB metadata contains an invalid SHA256 value."
}

$zipPath = Join-Path $releaseRoot $fileName
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Mod DB release archive is missing: '$zipPath'."
}

$zipItem = Get-Item -LiteralPath $zipPath
if ($zipItem.Length -ne [Int64]$metadata.FileSizeBytes) {
    throw "Mod DB release archive size does not match moddb_submission.json."
}

$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedHash = ([string]$metadata.FileSha256).ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw "Mod DB release archive SHA256 does not match moddb_submission.json."
}

$description = Get-Content -LiteralPath $descriptionPath -Raw
$handoffText = @"
Title: $($metadata.SuggestedTitle)
Version: $($metadata.Version)
Category: $($metadata.ModDbReleaseType)
File: $($metadata.FileName)
SHA256: $expectedHash

$description
"@

Write-Host "Validated Mod DB release archive: $zipPath" -ForegroundColor Green
Write-Host "Title: $($metadata.SuggestedTitle)"
Write-Host "Category: $($metadata.ModDbReleaseType)"
Write-Host "Upload page: $uploadUri"

if ($ValidateOnly) {
    Write-Host "Validation-only mode: browser, Explorer, and clipboard were not changed."
    return
}

Set-Clipboard -Value $handoffText
Write-Host "Copied the submission details and description to the clipboard."

# These windows are intentionally visible: this script is a human-reviewed handoff,
# not an unattended upload or final public submission.
Start-Process -FilePath "explorer.exe" -ArgumentList @("/select,`"$zipPath`"")

$operaPath = Resolve-OperaPath -ExplicitPath $BrowserPath
if ($operaPath) {
    Start-Process -FilePath $operaPath -ArgumentList @($uploadUri.AbsoluteUri)
    Write-Host "Opened the trusted Mod DB page in Opera: $operaPath"
}
else {
    Start-Process -FilePath $uploadUri.AbsoluteUri
    Write-Warning "Opera was not found; opened the trusted Mod DB page in the default browser."
}

Write-Host "Choose Add file, upload the selected ZIP, paste the clipboard text, review every field, and submit manually."
