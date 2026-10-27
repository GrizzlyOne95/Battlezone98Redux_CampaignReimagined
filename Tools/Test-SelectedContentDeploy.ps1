#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = Split-Path -Parent $PSScriptRoot
$savedRuntime = $env:BZR_CAMPAIGN_RUNTIME_DIR
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('cr-content-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $env:BZR_CAMPAIGN_RUNTIME_DIR = $scratch
    $sentinel = Join-Path $scratch 'unrelated.txt'
    [IO.File]::WriteAllText($sentinel, 'keep me')
    $manager = Join-Path $root 'Manage-CampaignFiles.ps1'
    $pwsh = (Get-Command pwsh).Source
    & $pwsh -NoProfile -File $manager -deploy-files 'Assets/ACT/moon.act' 'ODF/avpsav.odf'
    if ($LASTEXITCODE -ne 0) { throw 'Selected deploy failed.' }
    foreach ($pair in @(@('Assets/ACT/moon.act','moon.act'), @('ODF/avpsav.odf','avpsav.odf'))) {
        if ((Get-FileHash (Join-Path $root $pair[0])).Hash -ne (Get-FileHash (Join-Path $scratch $pair[1])).Hash) {
            throw "Wrong deployed bytes: $($pair[1])"
        }
    }
    [IO.File]::WriteAllText((Join-Path $scratch 'moon.act'), 'previous candidate')
    foreach ($paths in @(@('Assets/ACT/moon.act','Bin/winmm.dll'), @('../escape.act'), @('Assets/ACT/unlisted.act'), @())) {
        & $pwsh -NoProfile -File $manager -deploy-files @paths 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { throw 'An invalid selected deploy succeeded.' }
        if ([IO.File]::ReadAllText((Join-Path $scratch 'moon.act')) -ne 'previous candidate') {
            throw 'An invalid batch partially changed runtime content.'
        }
    }
    if ([IO.File]::ReadAllText($sentinel) -ne 'keep me') { throw 'Unrelated runtime file changed.' }
    if ((Get-ChildItem $scratch -File).Count -ne 3) { throw 'Selected deploy wrote unrelated files.' }
    Write-Host 'Selected content deployment passed: exact bytes, no cleanup/native writes, whole-batch preflight.'
}
finally {
    $env:BZR_CAMPAIGN_RUNTIME_DIR = $savedRuntime
}
exit 0
