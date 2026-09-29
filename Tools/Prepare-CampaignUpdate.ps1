#requires -Version 7.0
<#
.SYNOPSIS
Builds/checks the native dependencies, deploys to the GOG test copy and freezes
Workshop, manual and native packages. Does not commit, tag or upload.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ChangeNote,
    [string]$Version = (Get-Date -Format 'yyyy.MM.dd-HHmmss'),
    [string]$OutputDir,
    [switch]$ReuseNative,
    [switch]$NoDeploy,
    [switch]$NoSmoke,
    [switch]$PlanOnly
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest
$campaign = Split-Path -Parent $PSScriptRoot
$manager = Join-Path $campaign 'Manage-CampaignFiles.ps1'
$steps = [Collections.Generic.List[object]]::new()
$stepNumber = 0
$failure = $null
$nativeRebuilt = $false
$gogDeployed = $false
$gogRuntimePassed = $false
$configPath = if ($env:BZR_RELEASE_CONFIG) { $env:BZR_RELEASE_CONFIG } else { Join-Path $campaign 'Local\release.config.json' }
if ($env:BZR_RELEASE_CONFIG -and -not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Explicit release config does not exist: $configPath" }
$config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
function Get-Setting([string]$Name, [string]$EnvironmentName, [string]$Fallback) {
    # An explicit preparation config must not be displaced by permanent prototype
    # environment settings. Blank fields retain the ordinary BZR_* overrides.
    if ($config.PSObject.Properties[$Name] -and $config.$Name) { return [string]$config.$Name }
    if ($EnvironmentName -and [Environment]::GetEnvironmentVariable($EnvironmentName)) { return [Environment]::GetEnvironmentVariable($EnvironmentName) }
    return $Fallback
}
$siblings = Split-Path -Parent $campaign
$shim = Get-Setting OpenShimRepo BZR_OPENSHIM_REPO (Join-Path $siblings 'BZR-OpenShim')
$bzfile = Get-Setting BzfileRepo BZR_BZFILE_REPO (Join-Path $siblings 'bzfile')
$exu = Get-Setting ExuRepo BZR_EXU_REPO (Join-Path $siblings 'ExtraUtilities')
$game = Get-Setting GameRoot BZR_BATTLEZONE_ROOT 'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux'
if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$') { throw 'Version may contain letters, numbers, dot, underscore or hyphen.' }
if (-not $OutputDir) { $OutputDir = Join-Path $campaign ('Local\Releases\' + $Version) }
$output = [IO.Path]::GetFullPath($OutputDir)
if (Test-Path -LiteralPath $output) { throw 'Choose a new version/output directory. Previous preparation runs are never overwritten.' }
if ($output -match '(?i)[\\/]steamapps[\\/]workshop[\\/]') { throw 'Release output must not be in the Steam Workshop cache.' }
if ($NoDeploy) { $NoSmoke = $true }
$repos = [ordered]@{Campaign=$campaign; OpenShim=$shim; Bzfile=$bzfile; EXU=$exu}
$origins = @{Campaign='Battlezone98Redux_CampaignReimagined'; OpenShim='Battlezone98Redux_Shim'; Bzfile='bzfile'; EXU='ExtraUtilities'}
$source = [ordered]@{}
foreach ($name in @($repos.Keys)) {
    $repo = (Resolve-Path -LiteralPath $repos[$name]).Path
    $repos[$name] = $repo
    $origin = (& git -C $repo remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -notmatch ('(?i)github\.com[:/]GrizzlyOne95/' + [regex]::Escape($origins[$name]) + '(?:\.git)?$')) { throw "Unexpected $name origin: $origin" }
    $source[$name] = [ordered]@{Repo=$repo; Origin=$origin; Branch=(& git -C $repo branch --show-current).Trim(); Commit=(& git -C $repo rev-parse HEAD).Trim()}
}
$shim = $repos.OpenShim; $bzfile = $repos.Bzfile; $exu = $repos.EXU
if ($game -match '(?i)[\\/]steamapps[\\/]') { throw 'This preparation action deploys to GOG. Keep Steam download testing separate.' }
$env:BZR_OPENSHIM_REPO = $shim
$env:BZR_BZFILE_REPO = $bzfile
$env:BZR_EXU_REPO = $exu
$env:BZR_BATTLEZONE_ROOT = $game
$env:BZR_CAMPAIGN_RUNTIME_DIR = Join-Path $game 'mods\3686673790'
$plan = [ordered]@{
    Version=$Version; OutputDir=$output; Sources=$source;
    NativeBuild=$(if($ReuseNative){'reuse existing Release binaries'}else{'incremental Win32 Release builds: OpenShim, bzfile, EXU'});
    Checks=@('OpenShim config/network/CTest/shaders/loader', 'bzfile Lua API and five-file install/rollback', 'EXU hardening/generated headers/host tests', 'CR Lua 5.1/contracts/programs/DX11 shaders');
    DeployTo=$(if($NoDeploy){$null}else{$game}); Smoke=$(if($NoSmoke){@()}else{@('misn02b DX9','misn02b DX11','crsetup DX9')});
    Packages=@('Workshop content and VDF','Workshop ZIP','Manual/ModDB ZIP','OpenShim Suite ZIP','bzfile ZIP','EXU ZIP','checksums and receipts');
    Publishes=$false
}
if ($PlanOnly) { $plan | ConvertTo-Json -Depth 8; exit 0 }
Write-Host "Preparing $Version. Selected sources (explicit release config fields take precedence over inherited environment settings):"
foreach ($name in $repos.Keys) { Write-Host ("  {0}: {1} [{2} {3}]" -f $name,$repos[$name],$source[$name].Branch,$source[$name].Commit.Substring(0,8)) }
if (-not $NoDeploy -and $env:BZR_LAUNCH_LOCK_HELD) { throw 'Run preparation from a standalone shell outside an existing BZR harness session.' }
if (-not $NoDeploy -and (Get-Process battlezone98redux -ErrorAction SilentlyContinue)) { throw 'Close Battlezone normally before preparation; no running game is stopped by this command.' }
if (-not $NoDeploy -and -not (Test-Path -LiteralPath (Join-Path $game 'battlezone98redux.exe') -PathType Leaf)) { throw "Configured GOG test executable does not exist: $game" }
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$python = (Get-Command python -ErrorAction Stop).Source
$cmake = (Get-Command cmake -ErrorAction Stop).Source
$ctest = (Get-Command ctest -ErrorAction Stop).Source
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio 2022 / Build Tools with Desktop development with C++.' }
$vs = (& $vswhere -latest -products '*' -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if (-not $vs) { throw 'Visual Studio 2022 x86 C++ tools were not found.' }
$msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
$exuToolset = Get-Setting ExuVCToolsVersion '' ''
if (-not $exuToolset) {
    $toolsets = @(Get-ChildItem -LiteralPath (Join-Path $vs 'VC\Tools\MSVC') -Directory | Where-Object {[version]$_.Name -ge [version]'14.44'} | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1 -ExpandProperty Name)
    if ($toolsets.Count) { $exuToolset = $toolsets[0] }
}
if (-not $exuToolset -or -not (Test-Path -LiteralPath (Join-Path $vs "VC\Tools\MSVC\$exuToolset\bin\Hostx64\x86\cl.exe"))) { throw 'EXU needs MSVC 14.44 or later; set ExuVCToolsVersion in Local/release.config.json if needed.' }
$lua = Get-Setting LuaExe BZR_LUA_EXE 'lua'
$luac = Get-Setting LuacExe BZR_LUAC_EXE 'luac'
$luaCommand = Get-Command $lua -ErrorAction SilentlyContinue
$luacCommand = Get-Command $luac -ErrorAction SilentlyContinue
$useWsl = $true
if ($luaCommand -and $luacCommand) {
    $luaVersion = (& $luaCommand.Source -v 2>&1 | Out-String)
    $luacVersion = (& $luacCommand.Source -v 2>&1 | Out-String)
    if ($luaVersion -match 'Lua 5\.1\.' -and $luacVersion -match 'Lua 5\.1\.') { $useWsl = $false; $lua=$luaCommand.Source; $luac=$luacCommand.Source }
}
if ($useWsl) {
    $wslCommand = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wslCommand) { throw 'Provide Lua 5.1 LuaExe/LuacExe in release.config.json, or install lua5.1 in WSL. Lua 5.4 is not a valid substitute.' }
    $wsl = $wslCommand.Source
    $probe = (& $wsl --exec lua5.1 -v 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $probe -notmatch 'Lua 5\.1\.') { throw 'WSL Lua 5.1 was not found. Install lua5.1 in your default distro or configure Windows Lua 5.1 paths.' }
    $linuxCampaign = (& $wsl --exec wslpath -u $campaign).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot map the campaign checkout into WSL.' }
}
New-Item -ItemType Directory -Path (Join-Path $output 'Logs') | Out-Null
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'plan.json') -Encoding UTF8
function Invoke-Check([string]$Name, [string]$Program, [string[]]$Arguments, [string]$Directory=$campaign) {
    $script:stepNumber++
    $log = Join-Path $output ('Logs\{0:d2}-{1}.log' -f $script:stepNumber,($Name -replace '[^A-Za-z0-9_-]','-'))
    Write-Host "`n[$script:stepNumber] $Name" -ForegroundColor Cyan
    $started = [DateTime]::UtcNow
    Push-Location $Directory
    try {
        & $Program @Arguments 2>&1 | Tee-Object -FilePath $log | Out-Host
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    $steps.Add([ordered]@{Name=$Name; ExitCode=$code; Log=[IO.Path]::GetRelativePath($output,$log); StartedAtUtc=$started.ToString('o'); FinishedAtUtc=[DateTime]::UtcNow.ToString('o')})
    if ($code -ne 0) { throw "$Name failed (exit $code). See $log" }
}
function Invoke-PsCheck([string]$Name, [string]$Path, [string[]]$Arguments=@(), [string]$Directory=$campaign) {
    Invoke-Check $Name $pwsh (@('-NoProfile','-File',$Path)+$Arguments) $Directory
}
function Invoke-LuaCheck([string]$Name, [string]$RelativePath) {
    # Each test owns its default source argument; some expect a file, others a directory.
    if ($useWsl) { Invoke-Check $Name $wsl @('--cd',$linuxCampaign,'--exec','lua5.1',$RelativePath) }
    else { Invoke-Check $Name $lua @($RelativePath) }
}
try {
    Invoke-PsCheck 'OpenShim network baseline' (Join-Path $shim 'tools\validate-network-baseline.ps1') @() $shim
    Invoke-PsCheck 'OpenShim reference headers' (Join-Path $shim 'setup-dev.ps1') @() $shim
    Invoke-PsCheck 'OpenShim INI policy' (Join-Path $shim 'scripts\run_ini_tests.ps1') @() $shim
    Invoke-PsCheck 'OpenShim profiler contracts' (Join-Path $shim 'scripts\run_ogre_profiler_tests.ps1') @() $shim
    Invoke-Check 'OpenShim configure host tests' $cmake @('-S','tests','-B','build/tests','-A','Win32') $shim
    Invoke-Check 'OpenShim build host tests' $cmake @('--build','build/tests','--config','Release') $shim
    Invoke-Check 'OpenShim CTest' $ctest @('--test-dir','build/tests','-C','Release','--output-on-failure') $shim
    $kitsBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $fxc = Get-ChildItem -LiteralPath $kitsBin -Filter fxc.exe -File -Recurse |
        Where-Object {$_.FullName -match '\\x86\\fxc\.exe$'} | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $fxc) { throw 'Windows SDK x86 fxc.exe was not found.' }
    foreach ($variant in @(@{Entry='VSMain';Profile='vs_5_0'},@{Entry='PSMain';Profile='ps_5_0'})) {
        Invoke-Check ('OpenShim FXAA '+$variant.Entry) $fxc.FullName @('/nologo','/Ges','/O3','/I',(Join-Path $shim 'reverse_engineering\prerelease_2016\removed_files'),'/T',$variant.Profile,'/E',$variant.Entry,'/Fo',(Join-Path $output ('Logs\fxaa-'+$variant.Entry+'.cso')),(Join-Path $shim 'shaders\dx11_enhanced_fxaa.hlsl')) $shim
    }
    Invoke-PsCheck 'OpenShim Enhanced shaders' (Join-Path $shim 'scripts\Test-EnhancedShaderCompile.ps1') @() $shim
    Invoke-PsCheck 'OpenShim Enhanced PSSM' (Join-Path $shim 'scripts\Test-EnhancedPssmV2.ps1') @() $shim
    foreach ($item in @('validate_hardening.py','generate_bzr_build_profile.py','generate_engine_addresses.py','test_bzr_qualification.py')) {
        $arguments = @('tools/'+$item)
        if ($item.StartsWith('generate_')) { $arguments += '--check' }
        Invoke-Check ('EXU '+$item) $python $arguments $exu
    }
    if (-not $ReuseNative) {
        Invoke-Check 'Build OpenShim Release Win32' $msbuild @('BZROpenShim.sln','/m','/t:Build','/p:Configuration=Release','/p:Platform=Win32','/verbosity:minimal') $shim
        Invoke-Check 'Build bzfile Release x86' $msbuild @('bzfile.sln','/m','/t:Build','/p:Configuration=Release','/p:Platform=x86','/verbosity:minimal') $bzfile
        Invoke-Check 'Build EXU Release x86' $msbuild @('ExtraUtilities.sln','/m','/t:Build','/p:Configuration=Release','/p:Platform=x86',"/p:VCToolsVersion=$exuToolset",'/verbosity:minimal') $exu
        $nativeRebuilt = $true
    }
    Invoke-PsCheck 'OpenShim native load chain' (Join-Path $shim 'scripts\Test-PackageShape.ps1') @('-Root',$shim,'-Layout','Build','-ExpectedVersion',(Get-Item (Join-Path $shim 'bin\Release\winmm.dll')).VersionInfo.FileVersion) $shim
    Invoke-Check 'OpenShim loader lifecycle' (Join-Path $shim 'bin\Release\BZLoaderHostTest.exe') @() (Join-Path $shim 'bin\Release')
    Invoke-PsCheck 'OpenShim uninstall fixtures' (Join-Path $shim 'tests\uninstall_windows_tests.ps1') @() $shim
    Invoke-PsCheck 'OpenShim verifier fixtures' (Join-Path $shim 'tests\verify_windows_tests.ps1') @() $shim
    Invoke-Check 'Build bzfile real Lua host' $msbuild @('tests\lua_host\bzfile_lua_host.vcxproj','/p:Configuration=Release','/p:Platform=Win32','/verbosity:minimal') $bzfile
    Invoke-PsCheck 'bzfile Lua API' (Join-Path $bzfile 'tests\Test-LuaHost.ps1') @() $bzfile
    Invoke-PsCheck 'bzfile replacement rollback' (Join-Path $bzfile 'tests\Test-ReplaceHelper.ps1') @('-HelperPath','Release\bzfile_replace_helper.exe') $bzfile
    Invoke-PsCheck 'bzfile exact suite fresh and upgrade' (Join-Path $bzfile 'tests\Test-SuiteStaging.ps1') @('-ShimRoot',$shim) $bzfile
    Invoke-Check 'Build EXU hardening smoke' $msbuild @('tests\HardeningSmoke.vcxproj','/p:Configuration=Release','/p:Platform=Win32',"/p:VCToolsVersion=$exuToolset",'/verbosity:minimal') $exu
    Invoke-Check 'EXU hardening smoke' (Join-Path $exu 'tests\bin\Release\HardeningSmoke.exe') @() $exu
    Invoke-Check 'EXU MSVC host tests' (Join-Path $exu 'tests\host\run_msvc.cmd') @() $exu
    # Refresh the six cached binaries and installer manifest before CR checks.
    if (-not (Test-Path -LiteralPath (Join-Path $campaign 'workshop.config.json'))) { Invoke-PsCheck 'Initialize Workshop dry-run config' $manager @('-workshop-init') }
    Invoke-PsCheck 'Stage Workshop dry run' $manager @('-workshop-build',$ChangeNote)
    foreach ($item in @('Validate-CampaignRepository.py','Import-GoombaTranscripts.py','Test-Misn03CoopContract.py','Test-SetupMissionShell.py')) {
        $arguments = @('Tools/'+$item)
        if ($item -eq 'Import-GoombaTranscripts.py') { $arguments += '--check' }
        Invoke-Check ('CR '+$item) $python $arguments
    }
    $luaFiles = @(Get-ChildItem (Join-Path $campaign 'Scripts'),(Join-Path $campaign 'Missions') -Filter '*.lua' -File -Recurse | ForEach-Object {[IO.Path]::GetRelativePath($campaign,$_.FullName).Replace('\','/')})
    if ($useWsl) { Invoke-Check 'CR Lua 5.1 syntax' $wsl (@('--cd',$linuxCampaign,'--exec','luac5.1','-p')+$luaFiles) }
    else { Invoke-Check 'CR Lua 5.1 syntax' $luac (@('-p')+$luaFiles) }
    foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Test-*.lua' -File | Sort-Object Name) { Invoke-LuaCheck ('CR '+$file.BaseName) ('Tools/'+$file.Name) }
    foreach ($item in @('Test-ProgramReferences.ps1','Validate-DX11Shaders.ps1','Test-DX11ShaderValidator.ps1','Test-EnhancedPssmV2.ps1')) { Invoke-PsCheck ('CR '+$item) (Join-Path $PSScriptRoot $item) }
    if (-not $NoDeploy) {
        # Serialize native and campaign deployment against other harness launches.
        # Import lock helpers without changing ogre.cfg during a deployment-only run.
        $GameRoot=$null
        . (Join-Path $shim 'reverse_engineering\BZRHarness.ps1')
        try {
            if (Get-Process battlezone98redux -ErrorAction SilentlyContinue) { throw 'A game started during preparation. Close it normally before deploying.' }
            Invoke-PsCheck 'Deploy complete native chain to GOG' (Join-Path $shim 'scripts\Deploy-OpenShim.ps1') @('-GameDir',$game) $shim
            Invoke-PsCheck 'Deploy and verify GOG campaign' $manager @('-deploy')
            $gogDeployed = $true
        } finally {
            Exit-BZRLaunchLock -Mutex $global:BZRAutoLock
            # Child smoke processes must acquire their own lock after deployment.
            [Environment]::SetEnvironmentVariable('BZR_LAUNCH_LOCK_HELD',$null)
        }
    }
    if (-not $NoSmoke) {
        foreach ($renderer in @('dx9','dx11')) {
            Invoke-PsCheck ('GOG campaign '+$renderer) (Join-Path $shim 'reverse_engineering\test_campaign_reimagined.ps1') @('-Label',('campaign-'+$renderer),'-EvidenceDirectory',(Join-Path $output 'Runtime'),'-GameRoot',$game,'-Renderer',$renderer)
        }
        Invoke-PsCheck 'GOG Setup transaction' (Join-Path $shim 'reverse_engineering\test_campaign_reimagined.ps1') @('-Label','setup-dx9','-EvidenceDirectory',(Join-Path $output 'Runtime'),'-GameRoot',$game,'-Renderer','dx9','-Mission','crsetup.bzn','-SetupOnly')
        $setupLog = Get-Content -LiteralPath (Join-Path $output 'Runtime\setup-dx9\openpatch_setup.log') -Raw
        if ($setupLog -notmatch '(?im)^ACTION_SUCCESS=true\s*$') { throw 'Setup reported failure; see Runtime/setup-dx9/openpatch_setup.log.' }
        if ($setupLog -match '(?im)^ACTION=update_staged\s*$') {
            $status = Get-Content -LiteralPath (Join-Path $output 'Runtime\setup-dx9\openshim_update.status') -Raw
            if ($status -notmatch '(?m)^state=complete\s*$') { throw 'The Setup replacement helper did not complete successfully.' }
        }
        Invoke-PsCheck 'Verify GOG campaign after smoke restoration' $manager @('-verify')
        $gogRuntimePassed = $true
    }
    Invoke-PsCheck 'Freeze and verify all release packages' (Join-Path $PSScriptRoot 'Prepare-ReleaseCandidate.ps1') @('-OutputDir',(Join-Path $output 'Packages'),'-Version',$Version,'-ChangeNote',$ChangeNote,'-OpenShimRepo',$shim,'-BzfileRepo',$bzfile,'-ExuRepo',$exu,'-AllowDirty')
    Invoke-PsCheck 'Validate manual upload handoff' (Join-Path $output 'Packages\Manual\Invoke-ModDbHandoff.ps1') @('-ReleaseDir',(Join-Path $output 'Packages\Manual'),'-ValidateOnly')
} catch { $failure=$_.Exception.Message; Write-Host $failure -ForegroundColor Red }
finally {
    foreach ($name in $repos.Keys) { $source[$name]['DirtyFiles'] = @(& git -C $repos[$name] status --porcelain=v1 --untracked-files=normal) }
    [ordered]@{
        SchemaVersion=1; Version=$Version; Status=$(if($failure){'failed'}else{'prepared-candidate'});
        Failure=$failure; Sources=$source; Steps=@($steps.ToArray()); NativeRebuilt=$nativeRebuilt;
        GogDeployed=$gogDeployed; GogRuntimePassed=$gogRuntimePassed;
        PackageDirectory='Packages'; WorkshopUploaded=$false; PublicReleaseQualified=$false;
        RemainingGates=@('review/commit/push working source and cache changes','qualified published OpenShim release and checksum','Steam/Proton/Wine qualification','authorized Workshop upload, Roadmap sync and subscribed download smoke');
        FinishedAtUtc=[DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $output 'preparation_receipt.json') -Encoding UTF8
}
if ($failure) { exit 1 }
Write-Host "`nPreparation passed: $output" -ForegroundColor Green
Write-Host 'Review preparation_receipt.json, Packages/candidate_receipt.json and source diffs before publication.'
Write-Host 'No commit, tag, release or Workshop upload was performed.'
