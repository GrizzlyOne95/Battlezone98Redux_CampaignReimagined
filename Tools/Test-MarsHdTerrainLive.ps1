<# Reversible Windows/GOG DX11 example using CR's unmodified misn04 terrain.
   Run with Windows PowerShell 5.1 (the capture helper uses System.Drawing).
   First run captures native IDs; bind them with Build-MarsHdTileSources.py,
   then run again with -Hd. Source maps and the installed addon are preserved.
#>
param(
 [Parameter(Mandatory=$true)][string]$OpenShimRepo,
 [Parameter(Mandatory=$true)][string]$TileDirectory,
 [string]$HarnessRepo,
 [string]$GameRoot='C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux',
 [string]$ResourceDirectory,
 [switch]$Hd
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $OpenShimRepo).Path
if(-not $HarnessRepo){$HarnessRepo=$repo}
$harness=Join-Path (Resolve-Path -LiteralPath $HarnessRepo).Path 'reverse_engineering'
$cr=Split-Path -Parent $PSScriptRoot
$tiles=(Resolve-Path -LiteralPath $TileDirectory).Path
$game=(Resolve-Path -LiteralPath $GameRoot).Path
if($Hd -and -not (Test-Path -LiteralPath "$tiles\cr_mars_hd.json")){throw 'Bind the exported tiles to a fresh native capture first.'}
$out=Join-Path $cr ('Local\TerrainHD\run-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $out -Force | Out-Null
. "$harness\BZRHarness.ps1"
. "$harness\BZRWindowInput.ps1"
$lock=Enter-BZRLaunchLock -TimeoutSeconds 2
$proc=$null; $ogre=$null; $saved=New-Object System.Collections.Generic.List[object]
if(-not $ResourceDirectory){$ResourceDirectory=Join-Path $game 'addon\stock_terrain_hd'}
$testResources=(Resolve-Path -LiteralPath $ResourceDirectory).Path
function Save-File([string]$path) {
 if (@($saved | Where-Object {$_.path -eq $path}).Count) {return}
 $backup=Join-Path $out ('backup-'+$saved.Count)
 $exists=Test-Path -LiteralPath $path -PathType Leaf
 $hash=''
 if($exists){Copy-Item -LiteralPath $path -Destination $backup; $hash=(Get-FileHash -LiteralPath $path).Hash}
 $saved.Add([pscustomobject]@{path=$path;backup=$backup;exists=$exists;hash=$hash})
 $saved | ConvertTo-Json | Set-Content "$out\restoration.json"
}
try {
 Assert-BZRSafeToLaunch
 if(Get-ChildItem Env:OPENSHIM_TERRAIN* | Where-Object {$_.Value}){throw 'Use a fresh shell without terrain experiment environment overrides.'}
 $env:BZR_FORCE_WINDOWED='1'
 $ogre=Set-BZROgreWindowed -GameRoot $game -VideoMode '1280 x 720 @ 32-bit colour'
 foreach($name in @('winmm.dll','bzloader.dll','plugins\openshim.dll','scripts\patches.json','openshim\OpenShimAssets.ini','openshim.ini','career_stats.cfg')){Save-File "$game\$name"}
 foreach($item in Get-ChildItem "$repo\resources\renderer\enhanced" -File){Save-File "$game\openshim\renderer\enhanced\$($item.Name)"}
 foreach($item in Get-ChildItem "$repo\resources\ui\custom_widgets" -Filter '*.png' -File){Save-File "$game\BZ_ASSETS_CORE\common\ui\CustomWidgets\$($item.Name)"}
 # A newer installed script can invalidate this branch's exact payload probe.
 # Preserve it, isolate the complete test payload, then restore it after exit.
 foreach($item in Get-ChildItem "$game\openshim\renderer\enhanced" -File){
  if($item.Extension -in @('.program','.material') -and -not (Test-Path -LiteralPath "$repo\resources\renderer\enhanced\$($item.Name)")){
   Save-File $item.FullName
   Remove-Item -LiteralPath $item.FullName
  }
 }
 foreach($item in Get-ChildItem "$cr\Missions\misn04.*" -File){Save-File "$game\addon\$($item.Name)"; Copy-Item $item.FullName "$game\addon\$($item.Name)" -Force}
 foreach($relative in @('Materials\CR_BZTerrainBase.material','Shaders\CR_static_ibl.program','Tools\Examples\MarsHdTerrain\crhd_mars_example.material')){
  $name=Split-Path -Leaf $relative
  Save-File "$testResources\$name"
  Copy-Item -LiteralPath "$cr\$relative" -Destination "$testResources\$name" -Force
 }
 Save-File "$game\addon\crhd_mars_example.csv"
 Copy-Item -LiteralPath "$tiles\native_layout.csv" -Destination "$game\addon\crhd_mars_example.csv" -Force
 $trn=[IO.File]::ReadAllText("$game\addon\misn04.trn") -replace '(?m)^MaterialName\s*=.*$','MaterialName = crhd_mars_example'
 [IO.File]::WriteAllText("$game\addon\misn04.trn",$trn)
 Save-File "$game\addon\misn04.lua"
 @'
local t=0
local ready=false
function Start() print('[MARS-HD] CR misn04 terrain bench') end
function Update(dt)
 t=t+(dt or 0)
 local p=GetPlayerHandle()
 if not p or not IsValid(p) then return end
 SetCurHealth(p,100000)
 if not ready then CameraReady(); ready=true; print('[MARS-HD] camera ready') end
 CameraObject(p,600,400,800,p)
end
function CreateObject(h) end
function AddObject(h) end
function DeleteObject(h) end
'@ | Set-Content "$game\addon\misn04.lua" -Encoding ASCII
 & "$repo\scripts\Deploy-OpenShim.ps1" -GameDir $game
 $ini=[IO.File]::ReadAllText("$game\openshim.ini") -replace '(?m)^TerrainHdEnabled\s*=.*$','TerrainHdEnabled = 0'
 if($Hd){
  $ini=$ini -replace '(?m)^TerrainHdEnabled\s*=.*$','TerrainHdEnabled = 1'
  $ini=[regex]::Replace($ini,'(?m)^TerrainHdManifest\s*=.*$',('TerrainHdManifest = '+"$tiles\cr_mars_hd.json"))
 }
 [IO.File]::WriteAllText("$game\openshim.ini",$ini)
 $env:OPENSHIM_TERRAIN_HD_EXPORT="$out\native.json"
 $env:OPENSHIM_TERRAIN_TESSELLATION_TEST='1'
 $env:OPENSHIM_TERRAIN_TESSELLATION_FACTOR='1'
 if($Hd){
  foreach($item in Get-ChildItem $tiles -Filter '*.dds' -File){Save-File "$game\openshim\renderer\enhanced\$($item.Name)"; Copy-Item $item.FullName "$game\openshim\renderer\enhanced\$($item.Name)" -Force}
  $env:OPENSHIM_TERRAIN_HD='1'; $env:OPENSHIM_TERRAIN_HD_MANIFEST="$tiles\cr_mars_hd.json"
 }
 Assert-BZRSafeToLaunch
 $proc=Start-BZRGameProcess -FilePath "$game\battlezone98redux.exe" -ArgumentList 'misn04.bzn /nointro /renderer:dx11' -WorkingDirectory $game -PassThru
 Write-Host "PID=$($proc.Id) HD=$Hd OUT=$out"
 Start-Sleep -Seconds 20
 $window=[BZRWin.Native]::MainWindow($proc.Id)
 [BZRWin.Native]::Key($window,0x20)
 Start-Sleep -Seconds 20
 [BZRWin.Native]::Capture($window,"$out\trial.png")
 Write-Host 'CAPTURED'
}
finally {
 if($proc){Stop-BZRGame -Id $proc.Id -TimeoutSeconds 15}
 foreach($name in @('openshim.log','exu.log','BZLogger.txt','BZOgreLogfile.log')){if(Test-Path "$game\logs\$name"){Copy-Item "$game\logs\$name" "$out\$name" -Force}}
 foreach($entry in $saved){
  if($entry.exists){Copy-Item -LiteralPath $entry.backup -Destination $entry.path -Force
   if((Get-FileHash -LiteralPath $entry.path).Hash -ne $entry.hash){throw "RESTORE HASH FAILURE $($entry.path)"}
  } elseif(Test-Path -LiteralPath $entry.path){Remove-Item -LiteralPath $entry.path}
 }
 if($null-ne$ogre){Restore-BZROgreConfig -GameRoot $game -Original $ogre}
 Exit-BZRLaunchLock $lock
 Write-Host "RESTORED $($saved.Count) files. Evidence: $out"
}
if(-not (Test-Path -LiteralPath "$out\native.json")){throw "Native capture unavailable; inspect $out"}
if(-not $Hd){
 & python "$cr\Tools\Build-MarsHdTileSources.py" --bind-existing --output $tiles --capture "$out\native.json" --atlas-csv "$tiles\native_layout.csv"
 if($LASTEXITCODE -ne 0){throw 'Native source-tile binding failed'}
}
if($Hd){
 $records=@(Get-Content "$out\openshim.log" | Where-Object {$_ -match ("\[pid:"+$proc.Id+" ")})
 $proof=@($records | Where-Object {$_ -match 'GPU statistics.*hdTiles=1.*hdMaterialMask=3' -and $_ -match 'psInvocations=([0-9]+)' -and [uint64]$Matches[1] -ge 1024})
 if(-not $proof.Count){throw "Missing actual diffuse/normal/specular array draw proof; inspect $out"}
 if(-not ($records -match 'shared native material restored passes=[1-9]')){throw 'Native material restoration unproven'}
 $restoredStreams=@($records | Where-Object {$_ -match 'native streams restored meshes=([0-9]+) tracked=([0-9]+)' -and [int]$Matches[1] -gt 0 -and $Matches[1] -eq $Matches[2]})
 if(-not $restoredStreams.Count){throw 'Complete native stream restoration unproven'}
}
