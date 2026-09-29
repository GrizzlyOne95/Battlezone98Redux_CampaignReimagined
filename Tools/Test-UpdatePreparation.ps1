#requires -Version 7.0
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$root=Split-Path -Parent $PSScriptRoot
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('cr-preparation-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$saved=@{}
foreach($name in @('BZR_OPENSHIM_REPO','BZR_BZFILE_REPO','BZR_EXU_REPO','BZR_RELEASE_CONFIG')){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}
try {
    foreach($pair in @(@{Name='OpenShim';Env='BZR_OPENSHIM_REPO';Origin='Battlezone98Redux_Shim'},@{Name='bzfile';Env='BZR_BZFILE_REPO';Origin='bzfile'},@{Name='EXU';Env='BZR_EXU_REPO';Origin='ExtraUtilities'})){
        $repo=Join-Path $scratch $pair.Name
        New-Item -ItemType Directory -Path $repo | Out-Null
        & git -C $repo init -q
        & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm 'Fixture source identity'
        & git -C $repo remote add origin ('https://github.com/GrizzlyOne95/'+$pair.Origin+'.git')
        if($LASTEXITCODE -ne 0){throw 'Cannot create source identity fixture.'}
        [Environment]::SetEnvironmentVariable($pair.Env,$repo)
    }
    $fixtureConfig=[ordered]@{OpenShimRepo=$env:BZR_OPENSHIM_REPO;BzfileRepo=$env:BZR_BZFILE_REPO;ExuRepo=$env:BZR_EXU_REPO}
    & git -C $fixtureConfig.BzfileRepo checkout --detach -q
    if($LASTEXITCODE -ne 0){throw 'Cannot create detached source fixture.'}
    $env:BZR_RELEASE_CONFIG=Join-Path $scratch 'release.config.json'
    $fixtureConfig | ConvertTo-Json | Set-Content -LiteralPath $env:BZR_RELEASE_CONFIG -Encoding utf8
    # A permanent/prototype environment override cannot displace explicit release sources.
    $env:BZR_OPENSHIM_REPO=$root
    $manager=Join-Path $root 'Manage-CampaignFiles.ps1'
    $pwsh=(Get-Command pwsh).Source
    $output=Join-Path $scratch 'output with spaces'
    $json=& $pwsh -NoProfile -File $manager -prepare-update 'Fix a small Lua bug' -version fixture-rc1 -reuse-native -no-deploy -output $output -plan 2>&1
    if($LASTEXITCODE -ne 0){throw ($json|Out-String)}
    $plan=($json|Out-String)|ConvertFrom-Json
    if($plan.Sources.OpenShim.Repo -ne $fixtureConfig.OpenShimRepo){throw 'Inherited environment displaced the configured release source.'}
    if($plan.Sources.Bzfile.Branch -ne 'detached'){throw 'Detached source identity was lost.'}
    if($plan.Version -ne 'fixture-rc1' -or $plan.OutputDir -ne $output -or $plan.NativeBuild -notmatch '^reuse' -or $plan.Smoke.Count -ne 0 -or $plan.Publishes -ne $false){throw 'Preparation CLI lost an option or selected publication.'}
    if(Test-Path -LiteralPath $output){throw 'A plan-only command wrote its output directory.'}
    foreach($case in @(@('-prepare-update'),@('-prepare-update','note','-version'),@('-prepare-update','note','-bogus'),@('-prepare-update','note','-version','../bad','-plan'))){
        $result=& $pwsh -NoProfile -File $manager @case 2>&1
        if($LASTEXITCODE -eq 0){throw "Invalid CLI arguments succeeded: $($case -join ' ')"}
    }
    New-Item -ItemType Directory -Path $output | Out-Null
    [IO.File]::WriteAllText((Join-Path $output 'keep.txt'),'previous candidate')
    $result=& $pwsh -NoProfile -File $manager -prepare-update note -output $output -plan 2>&1
    if($LASTEXITCODE -eq 0 -or [IO.File]::ReadAllText((Join-Path $output 'keep.txt')) -ne 'previous candidate'){throw 'Existing candidate protection failed.'}
    & git -C $fixtureConfig.OpenShimRepo remote set-url origin 'https://github.com/example/wrong.git'
    $result=& $pwsh -NoProfile -File $manager -prepare-update note -plan 2>&1
    if($LASTEXITCODE -eq 0 -or ($result|Out-String) -notmatch 'Unexpected OpenShim origin'){throw 'Wrong dependency origin was accepted.'}
    Write-Host 'Preparation CLI contracts passed: options, plan/no writes, fail-closed arguments, existing output preservation, dependency identity.'
} finally {
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name])}
    # Scratch remains available for a failed-fixture investigation; no real checkout is removed.
}
