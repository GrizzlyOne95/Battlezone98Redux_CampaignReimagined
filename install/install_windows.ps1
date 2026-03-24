$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoSlug = "GrizzlyOne95/Battlezone98Redux_CampaignReimagined"
$ref = if ($env:CR_OPENSHIM_REF) { $env:CR_OPENSHIM_REF } else { "main" }
$gamePath = if ($args.Count -ge 1 -and $args[0]) {
    [string]$args[0]
} elseif ($env:CR_OPENSHIM_GAME_PATH) {
    $env:CR_OPENSHIM_GAME_PATH
} elseif ($env:BZR_BATTLEZONE_ROOT) {
    $env:BZR_BATTLEZONE_ROOT
} else {
    ""
}
$dllUrl = if ($env:CR_OPENSHIM_DLL_URL) {
    $env:CR_OPENSHIM_DLL_URL
} else {
    "https://raw.githubusercontent.com/$repoSlug/$ref/_Source/Bin/winmm.dll"
}
$expectedHash = if ($env:CR_OPENSHIM_WINMM_SHA256) {
    $env:CR_OPENSHIM_WINMM_SHA256.ToLowerInvariant()
} else {
    "a9b2566511f9173847e25f9d48783337bd2b52bba863063b3f2b96f5da165d91"
}

function Find-GamePath {
    $candidates = @(
        "C:\Program Files (x86)\Steam\steamapps\common\Battlezone 98 Redux",
        "C:\Program Files\Steam\steamapps\common\Battlezone 98 Redux",
        (Join-Path $env:PROGRAMFILES "Steam\steamapps\common\Battlezone 98 Redux")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate "battlezone98redux.exe"))) {
            return $candidate
        }
    }

    return ""
}

function Assert-Hash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256
    )

    $actual = (Get-FileHash -Algorithm SHA256 -Path $FilePath).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256) {
        throw "Downloaded winmm.dll hash mismatch. Expected $ExpectedSha256 but got $actual"
    }
}

if (-not $gamePath) {
    $gamePath = Find-GamePath
}

if (-not $gamePath) {
    throw "Could not find Battlezone 98 Redux automatically. Set CR_OPENSHIM_GAME_PATH or BZR_BATTLEZONE_ROOT and run again."
}

$exePath = Join-Path $gamePath "battlezone98redux.exe"
if (-not (Test-Path $exePath)) {
    throw "Game executable not found in: $gamePath"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$downloadedDll = Join-Path $tempRoot "winmm.dll"

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Write-Host "Downloading Campaign Reimagined OpenShim winmm.dll from $dllUrl"
    Invoke-WebRequest -Uri $dllUrl -OutFile $downloadedDll
    Assert-Hash -FilePath $downloadedDll -ExpectedSha256 $expectedHash

    $destPath = Join-Path $gamePath "winmm.dll"
    $existingHash = if (Test-Path $destPath) { (Get-FileHash -Algorithm SHA256 -Path $destPath).Hash.ToLowerInvariant() } else { $null }

    if ($existingHash -eq $expectedHash) {
        Write-Host ""
        Write-Host "Install complete." -ForegroundColor Green
        Write-Host "Campaign Reimagined OpenShim is already installed at: $destPath"
        Write-Host "No Steam launch option changes are needed on Windows."
        return
    }

    if (Test-Path $destPath) {
        $backupPath = Join-Path $gamePath "winmm.dll.pre-campaignreimagined-install.bak"
        Write-Host "Backing up existing winmm.dll to $backupPath"
        Copy-Item -Force $destPath $backupPath
    }

    Write-Host "Installing OpenShim to $destPath"
    Copy-Item -Force $downloadedDll $destPath

    Write-Host ""
    Write-Host "Install complete." -ForegroundColor Green
    Write-Host "Installed to: $destPath"
    Write-Host "No Steam launch option changes are needed on Windows."
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tempRoot
}
