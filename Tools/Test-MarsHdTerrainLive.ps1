<# Reversible Windows/GOG DX11 example using CR's Mars, Moon or Venus terrain.
   Run with Windows PowerShell 5.1 (the capture helper uses System.Drawing).
   New-MarsHdTerrainExample.ps1 or Build-MoonHdTerrain.py prepares the pack.
   Source maps and the installed addon are preserved.
#>
param(
 [Parameter(Mandatory=$true)][string]$OpenShimRepo,
 [Parameter(Mandatory=$true)][string]$TileDirectory,
 [string]$HarnessRepo,
 [string]$GameRoot='C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux',
 [string]$ResourceDirectory,
 [string]$ExuDll,
 [string]$DetailTexture,
 [ValidateSet('mars','moon','venus','io','europa','titan','achilles','ganymede','elysium')][string]$World='mars',
 [ValidateSet('Enhanced','Redux','Retro')][string]$RenderProfile='Enhanced',
 [switch]$MeasureMemory,
 [switch]$ProfileCycle,
 [ValidateRange(1,4)][int]$ProfileCycles=1,
 [switch]$WideView,
 [switch]$BaseView,
 [switch]$GroundView,
 [switch]$MicroRelief,
 [switch]$SettingsOnly,
 [switch]$BindCapture,
 [switch]$Hd
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $OpenShimRepo).Path
if(-not $HarnessRepo){$HarnessRepo=$repo}
$harness=Join-Path (Resolve-Path -LiteralPath $HarnessRepo).Path 'reverse_engineering'
$cr=Split-Path -Parent $PSScriptRoot
$tiles=(Resolve-Path -LiteralPath $TileDirectory).Path
$game=(Resolve-Path -LiteralPath $GameRoot).Path
$mission=switch($World){'moon'{'misn03'}'venus'{'misn08'}'io'{'misn10'}'europa'{'misn12'}'titan'{'misn14'}'achilles'{'misn17'}'ganymede'{'evolve_3'}'elysium'{'evolve_1'}default{'misn04'}}
$isBundle=Test-Path -LiteralPath (Join-Path $tiles 'terrain_hd_tiles.json')
$hdMapMask=if($isBundle){7}else{3}
$example="crhd_$($World)_example"
if($World -eq 'moon'){$example='mn_detail_atlas'}
if($World -eq 'venus'){$example='ve_detail_atlas'}
if($isBundle){$stem=@{moon='mn';mars='ma';venus='ve';io='io';europa='eu';titan='ti';achilles='ac';ganymede='ga';elysium='el'}[$World];$example=$stem+'_detail_atlas'}
$exampleFolder=if($World -eq 'moon'){'MoonHdTerrain'}else{'MarsHdTerrain'}
$manifestPath=if($isBundle){Join-Path $tiles 'terrain_hd_tiles.json'}else{Join-Path $tiles 'cr_mars_hd.json'}
$layoutPath=if($isBundle){Join-Path $tiles 'layout.csv'}else{Join-Path $tiles 'native_layout.csv'}
$textureDirectory=if($isBundle){Join-Path $tiles 'resources'}else{$tiles}
if($BindCapture -and $isBundle){throw 'Toolbox packs use rectangle mapping; capture binding is unnecessary.'}
if($Hd -and -not (Test-Path -LiteralPath $manifestPath)){throw 'Prepare the source tile bundle before previewing.'}
if($ProfileCycle -and (-not $Hd -or $RenderProfile -ne 'Enhanced')){throw 'ProfileCycle needs -Hd and an Enhanced starting profile'}
if($SettingsOnly -and (-not $Hd -or -not $MicroRelief -or $ProfileCycle)){throw 'SettingsOnly requires -Hd -MicroRelief without profile cycling'}
if($ProfileCycle){
 if(-not $ExuDll){$ExuDll=Join-Path $game 'mods\3686673790\exu.dll'}
 $ExuDll=(Resolve-Path -LiteralPath $ExuDll).Path.Replace('\','/')
 if($ExuDll.Contains(']]')){throw 'Unsupported Lua probe DLL path'}
}
$out=Join-Path $cr ('Local\TerrainHD\run-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $out -Force | Out-Null
if($isBundle){
 # Preview current CR art direction even when reusing an older texture bundle.
 $pack=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
 $tuning=Get-Content -LiteralPath "$cr\Config\cr_terrain_hd.json" -Raw | ConvertFrom-Json
 foreach($material in $pack.materials.PSObject.Properties){
  $authored=$tuning.materials.PSObject.Properties[$material.Name]
  if($null-ne$authored -and $authored.Value.diffuseResource -ceq $material.Value.diffuseResource){
   $material.Value | Add-Member -NotePropertyName microReliefScale -NotePropertyValue $authored.Value.microReliefScale -Force
  }
  if($material.Value.heightTexture){
   $heightSource=[IO.Path]::GetFullPath((Join-Path $tiles $material.Value.heightTexture))
   if(-not $heightSource.StartsWith($tiles+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Height path escapes the texture bundle'}
   $heightName=Split-Path -Leaf $heightSource
   Copy-Item -LiteralPath $heightSource -Destination (Join-Path $out $heightName)
   $material.Value.heightTexture=$heightName
  }
 }
 $manifestPath=Join-Path $out 'terrain_hd_tiles.json'
 $pack | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}
# This helper owns reversible ogre.cfg changes below. Suppress the harness's
# separate automatic windowed backup when invoked repeatedly in one shell;
# still let it recover an orphan, and still launch with BZR_FORCE_WINDOWED=1.
$inheritedWindowed=$env:BZR_FORCE_WINDOWED
try {
 $env:BZR_FORCE_WINDOWED=$null
 . "$harness\BZRHarness.ps1"
} finally {$env:BZR_FORCE_WINDOWED=$inheritedWindowed}
. "$harness\BZRWindowInput.ps1"
. "$PSScriptRoot\Get-BzrProcessMemory.ps1"
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
 $missionDirectory=Join-Path $cr 'Missions'
 if($World -in @('ganymede','elysium')){
  $missionDirectory=Join-Path $out 'stock-map'
  & python "$PSScriptRoot\Prepare-HdTerrainArchivePreview.py" --game $game --mission $mission --out $missionDirectory
  if($LASTEXITCODE -ne 0){throw 'Stock map preview extraction failed'}
 }
 foreach($item in Get-ChildItem "$missionDirectory\$mission.*" -File){Save-File "$game\addon\$($item.Name)"; Copy-Item $item.FullName "$game\addon\$($item.Name)" -Force}
 if($isBundle){
  $fixtureOptions=@('--source',"$missionDirectory\$mission.bzn",'--out',"$game\addon\$mission.bzn")
  if($BaseView){$baseSettings=Get-Content "$PSScriptRoot\TerrainHD\base_emissives.json" -Raw | ConvertFrom-Json;$fixtureOptions+=@('--base-type',[string]$baseSettings.worlds.$World.type)}
  elseif($GroundView){$fixtureOptions+=@('--base-type','0')}
  & python "$PSScriptRoot\Build-HdTerrainPreview.py" @fixtureOptions
  if($LASTEXITCODE -ne 0){throw 'Terrain camera fixture generation failed'}
 }
 $previewScripts=@('Materials\CR_BZTerrainBase.material','Shaders\CR_static_ibl.program',"Tools\Examples\$exampleFolder\$example.material")
 if($isBundle){
  $previewScripts=@('Materials\CR_BZTerrainBase.material','Shaders\CR_static_ibl.program',"Materials\$example.material")
  $previewScripts += 'Materials\CR_sky_events.material'
  $previewScripts += @(Get-ChildItem "$cr\Shaders" -Filter 'CR_sky*' -File | ForEach-Object {'Shaders\'+$_.Name})
 }
 foreach($relative in $previewScripts){
  $name=Split-Path -Leaf $relative
  Save-File "$testResources\$name"
  Copy-Item -LiteralPath "$cr\$relative" -Destination "$testResources\$name" -Force
 }
 if($DetailTexture){
  $detail=(Resolve-Path -LiteralPath $DetailTexture).Path
  $detailName=Split-Path -Leaf $detail
  if($detailName -notmatch '^[A-Za-z0-9_]+\.dds$'){throw 'DetailTexture requires a simple DDS resource filename'}
  Save-File "$testResources\$detailName"
  Copy-Item -LiteralPath $detail -Destination "$testResources\$detailName" -Force
  $materialPath=Join-Path $testResources "$example.material"
  $material=[IO.File]::ReadAllText($materialPath)
  if($material -notmatch 'set_texture_alias\s+DetailMap\s+\S+'){throw 'Preview material has no DetailMap alias'}
  [IO.File]::WriteAllText($materialPath,([regex]::Replace($material,'(set_texture_alias\s+DetailMap\s+)\S+',('${1}'+$detailName))))
 }
 # CR wrappers can be parsed before the separate OpenShim resource group is
 # registered. Make their exact shader/IBL dependencies visible in this CLI
 # fixture's registered group too, without duplicating program declarations.
 foreach($item in Get-ChildItem "$repo\resources\renderer\enhanced" -File | Where-Object {$_.Extension -in @('.hlsl','.glsl','.dds')}){
  Save-File "$testResources\$($item.Name)"
  Copy-Item -LiteralPath $item.FullName -Destination "$testResources\$($item.Name)" -Force
 }
 Save-File "$game\addon\$example.csv"
 Copy-Item -LiteralPath $layoutPath -Destination "$game\addon\$example.csv" -Force
 Save-File "$testResources\$example.csv"
 Copy-Item -LiteralPath $layoutPath -Destination "$testResources\$example.csv" -Force
 $trn=[IO.File]::ReadAllText("$game\addon\$mission.trn") -replace '(?m)^MaterialName\s*=.*$',("MaterialName = "+$example)
 [IO.File]::WriteAllText("$game\addon\$mission.trn",$trn)
 Save-File "$game\addon\$mission.lua"
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
'@ | Set-Content "$game\addon\$mission.lua" -Encoding ASCII
 $driver=[IO.File]::ReadAllText("$game\addon\$mission.lua").Replace('MARS-HD',($World.ToUpper()+'-HD')).Replace('misn04',$mission)
 [IO.File]::WriteAllText("$game\addon\$mission.lua",$driver)
 if($WideView){
  $driver=[IO.File]::ReadAllText("$game\addon\$mission.lua").Replace('CameraObject(p,600,400,800,p)','CameraObject(p,3000,2200,-3000,p)')
  [IO.File]::WriteAllText("$game\addon\$mission.lua",$driver)
 }
 if($GroundView){
  $driver=[IO.File]::ReadAllText("$game\addon\$mission.lua").Replace('CameraObject(p,600,400,800,p)','CameraObject(p,1800,900,-1800,p)')
  [IO.File]::WriteAllText("$game\addon\$mission.lua",$driver)
 }
 if($ProfileCycle){
  # Optional integration probe uses the already installed EXU API. Ordinary
  # authored packs/previews have no EXU requirement.
  $cycleDriver=@'
local originalStart=Start
local originalUpdate=Update
local profiles=nil
local cycleStage=0
function Start()
 originalStart()
 local loader,message=package.loadlib([[__EXU_DLL__]],'luaopen_exu')
 assert(loader,message)
 loader()
 profiles=rawget(_G,'exu')
 assert(profiles and profiles.RequestRenderProfile,'EXU profile probe API unavailable')
 print('[MARS-HD] profile cycle armed')
end
function Update(dt)
 originalUpdate(dt)
 local now=GetTime()
 if cycleStage<__CYCLE_STAGES__ and now>=12*(cycleStage+1) then
  local profile=cycleStage%2==0 and 'redux' or 'enhanced'
  assert(profiles.RequestRenderProfile(profile),'Profile request declined')
  print('[MARS-HD] requested '..profile..' at '..now)
  cycleStage=cycleStage+1
 end
end
'@
  $cycleDriver.Replace('__EXU_DLL__',$ExuDll).Replace('__CYCLE_STAGES__',[string]($ProfileCycles*2)) | Add-Content "$game\addon\$mission.lua" -Encoding ASCII
 }
 & "$repo\scripts\Deploy-OpenShim.ps1" -GameDir $game
 $ini=[IO.File]::ReadAllText("$game\openshim.ini") -replace '(?m)^TerrainHdEnabled\s*=.*$','TerrainHdEnabled = 0'
 $ini=[regex]::Replace($ini,'(?m)^RenderProfile\s*=.*$',('RenderProfile = '+$RenderProfile))
 if($MicroRelief){$ini=$ini -replace '(?m)^TerrainMicroRelief\s*=.*$','TerrainMicroRelief = 1'}
 if($SettingsOnly){$ini=$ini -replace '(?m)^TerrainRenderProbe\s*=.*$','TerrainRenderProbe = 0'}
 if($Hd){
  $ini=$ini -replace '(?m)^TerrainHdEnabled\s*=.*$','TerrainHdEnabled = 1'
  $ini=[regex]::Replace($ini,'(?m)^TerrainHdManifest\s*=.*$',('TerrainHdManifest = '+$manifestPath))
 }
 [IO.File]::WriteAllText("$game\openshim.ini",$ini)
 $env:OPENSHIM_TERRAIN_HD_EXPORT="$out\native.json"
 if(-not $SettingsOnly){
  $env:OPENSHIM_TERRAIN_TESSELLATION_TEST='1'
  $env:OPENSHIM_TERRAIN_TESSELLATION_FACTOR='1'
 }
 if($MicroRelief -and -not $SettingsOnly){
  $env:OPENSHIM_TERRAIN_MICRO_RELIEF_TEST='1'
  $env:OPENSHIM_TERRAIN_TESSELLATION_FACTOR='4'
  if($isBundle -and ($pack.materials.PSObject.Properties.Value | Where-Object {$_.heightTexture})){$env:OPENSHIM_TERRAIN_HEIGHT_REQUIRE='1'}
 }
 if($Hd){
  foreach($item in Get-ChildItem $textureDirectory -Filter '*.dds' -File){Save-File "$game\openshim\renderer\enhanced\$($item.Name)"; Copy-Item $item.FullName "$game\openshim\renderer\enhanced\$($item.Name)" -Force}
  if(-not $SettingsOnly){
   $env:OPENSHIM_TERRAIN_HD='1'; $env:OPENSHIM_TERRAIN_HD_MANIFEST=$manifestPath
   $env:OPENSHIM_TERRAIN_HD_REQUIRE_MATERIAL_MAPS='1'
  }
 }
 Assert-BZRSafeToLaunch
 $proc=Start-BZRGameProcess -FilePath "$game\battlezone98redux.exe" -ArgumentList "$mission.bzn /nointro /renderer:dx11" -WorkingDirectory $game -PassThru
 Write-Host "PID=$($proc.Id) HD=$Hd OUT=$out"
 Start-Sleep -Seconds 20
 $window=[BZRWin.Native]::MainWindow($proc.Id)
 [BZRWin.Native]::Key($window,0x20)
 if($ProfileCycle){
  Start-Sleep -Seconds 8
  if($MeasureMemory){Get-BzrProcessMemory -ProcessId $proc.Id | ConvertTo-Json | Set-Content "$out\initial-enhanced-memory.json"}
  Start-Sleep -Seconds 9
  [BZRWin.Native]::Capture($window,"$out\fallback.png")
  if($MeasureMemory){Get-BzrProcessMemory -ProcessId $proc.Id | ConvertTo-Json | Set-Content "$out\fallback-memory.json"}
  foreach($cycleIndex in 1..$ProfileCycles){
   Start-Sleep -Seconds 12
   if($MeasureMemory){Get-BzrProcessMemory -ProcessId $proc.Id | ConvertTo-Json | Set-Content "$out\cycle-$cycleIndex-enhanced-memory.json"}
   if($cycleIndex -lt $ProfileCycles){
    Start-Sleep -Seconds 12
    if($MeasureMemory){Get-BzrProcessMemory -ProcessId $proc.Id | ConvertTo-Json | Set-Content "$out\cycle-$cycleIndex-redux-memory.json"}
   }
  }
  Start-Sleep -Seconds 8
 }else{Start-Sleep -Seconds 20}
 [BZRWin.Native]::Capture($window,"$out\trial.png")
 if($MeasureMemory){
  $samples=@()
  foreach($sampleIndex in 1..5){
   $processMemory=Get-BzrProcessMemory -ProcessId $proc.Id
   $gpu=@();$gpuError=$null
   try {
    $counters=Get-Counter @('\GPU Process Memory(*)\Dedicated Usage','\GPU Process Memory(*)\Shared Usage','\GPU Process Memory(*)\Total Committed') -ErrorAction Stop
    $gpu=@($counters.CounterSamples | Where-Object {$_.InstanceName -like ("pid_"+$proc.Id+"_*") -and $_.Status -eq 0})
   } catch {$gpuError=$_.Exception.Message}
   $row=[ordered]@{gpuError=$gpuError}
   foreach($property in $processMemory.PSObject.Properties){$row[$property.Name]=$property.Value}
   foreach($metric in @(@('dedicatedBytes','dedicated usage'),@('sharedBytes','shared usage'),@('gpuCommittedBytes','total committed'))){
    $values=@($gpu | Where-Object {$_.Path.EndsWith('\'+$metric[1])})
    $row[$metric[0]]=if($values.Count){($values | Measure-Object CookedValue -Sum).Sum}else{$null}
   }
   $samples += [pscustomobject]$row
   Start-Sleep -Milliseconds 300
  }
  $memory=[ordered]@{pid=$proc.Id;hdRequested=[bool]$Hd;profile=$RenderProfile;wideView=[bool]$WideView;samples=$samples;median=[ordered]@{}}
  foreach($metric in @('privateBytes','peakPrivateBytes','workingSetBytes','peakWorkingSetBytes','virtualBytes','peakVirtualBytes','vaCommittedBytes','vaReservedBytes','vaFreeBytes','vaLargestFreeBytes','dedicatedBytes','sharedBytes','gpuCommittedBytes')){
   $values=@($samples | ForEach-Object {$_.$metric} | Where-Object {$null -ne $_} | Sort-Object)
   $memory.median[$metric]=if($values.Count){$values[[int][Math]::Floor($values.Count/2)]}else{$null}
  }
  $memory | ConvertTo-Json -Depth 6 | Set-Content "$out\memory.json"
  Write-Host ('MEMORY '+($memory.median | ConvertTo-Json -Compress))
 }
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
if(-not $Hd -and $BindCapture){
 & python "$cr\Tools\Build-MarsHdTileSources.py" --bind-existing --output $tiles --capture "$out\native.json" --atlas-csv "$tiles\native_layout.csv"
 if($LASTEXITCODE -ne 0){throw 'Native source-tile binding failed'}
}
if($Hd -and $RenderProfile -ne 'Enhanced'){
 $records=@(Get-Content "$out\openshim.log" | Where-Object {$_ -match ("\[pid:"+$proc.Id+" ")})
 if(-not ($records -match 'stock atlas retained: effective DX11 Enhanced profile required')){throw 'Profile fallback unproven'}
 if($records -match '\[TERRAIN-HD\] array ready|\[TERRAIN-HD\] shared native material installed'){throw 'HD arrays allocated outside Enhanced'}
}
if($Hd -and $RenderProfile -eq 'Enhanced'){
 $records=@(Get-Content "$out\openshim.log" | Where-Object {$_ -match ("\[pid:"+$proc.Id+" ")})
 $proof=@($records | Where-Object {$_ -match ("GPU statistics.*hdTiles=1.*hdMaterialMask="+$hdMapMask+'\b') -and $_ -match 'psInvocations=([0-9]+)' -and [uint64]$Matches[1] -ge 1024})
 if(-not $SettingsOnly -and -not $proof.Count){throw "Missing actual diffuse/normal/specular array draw proof; inspect $out"}
 if($SettingsOnly){
  if(-not ($records -match 'domain binding requested by terrain feature settings')){throw 'Ordinary terrain settings did not start height binding'}
  if($records -match 'GPU statistics observer requested'){throw 'SettingsOnly unexpectedly enabled diagnostic tessellation'}
 }
 if(-not ($records -match 'shared native material restored passes=[1-9]')){throw 'Native material restoration unproven'}
 $restoredStreams=@($records | Where-Object {$_ -match 'native streams restored meshes=([0-9]+) tracked=([0-9]+)' -and [int]$Matches[1] -gt 0 -and $Matches[1] -eq $Matches[2]})
 if(-not $restoredStreams.Count){throw 'Complete native stream restoration unproven'}
 if($MicroRelief){
  $pack=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $materialName=($example.ToUpper())
  $scale=$pack.materials.$materialName.microReliefScale
  if($null-eq$scale){$scale=1.0}
  $amplitude=[Math]::Min(1.0,0.25*[double]$scale)
  $formatted=$amplitude.ToString('F3',[Globalization.CultureInfo]::InvariantCulture)
  if(-not ($records -match ('\[TERRAIN-TESS\] shared native material installed.*displacement='+[regex]::Escape($formatted)+'\b'))){throw 'Scaled native domain displacement unproven'}
  if($amplitude -gt 0 -and -not ($records -match ('micro-relief render bounds padded.*amplitude='+[regex]::Escape($formatted)+'\b'))){throw 'Matching scaled render bounds unproven'}
  if($pack.materials.$materialName.heightTexture){
   if(-not $SettingsOnly -and -not ($proof -match 'heightTexture=1')){throw 'Native domain texture binding and rasterization unproven'}
   $release=@($records | Where-Object {$_ -match '\[TERRAIN-HEIGHT\] released.*binds=(\d+) restores=(\d+)' -and [int]$Matches[1] -gt 0 -and $Matches[1] -eq $Matches[2]})
   if(-not $release.Count){throw 'Domain texture binding restoration unproven'}
  }
 }
 if($ProfileCycle){
  if(-not ($records -match 'profile fallback restored stock atlas')){throw 'Live profile fallback unproven'}
  if(-not ($records -match 'Enhanced resumed; native tile discovery rearmed')){throw 'Live profile resume unproven'}
  if(@($records | Where-Object {$_ -match '\[TERRAIN-HD\] shared native material installed'}).Count -ne ($ProfileCycles+1)){throw 'HD material did not reinstall for every profile resume'}
  if($MeasureMemory -and $ProfileCycles -gt 1){
   $cycleMemory=@(1..$ProfileCycles | ForEach-Object {Get-Content "$out\cycle-$_-enhanced-memory.json" -Raw | ConvertFrom-Json})
   $growth=$cycleMemory[-1].privateBytes-$cycleMemory[0].privateBytes
   Write-Host ('PROFILE_CYCLE_PRIVATE_GROWTH_BYTES='+$growth)
   # Allow normal allocator/driver noise, while rejecting the original ~90 MiB
   # per-cycle retained handoffs. This is a short regression, not a leak proof.
   if($growth -gt 32MB){throw 'Profile cycles accumulated more than 32 MiB private commit'}
   $firstOff=Get-Content "$out\fallback-memory.json" -Raw | ConvertFrom-Json
   $lastOff=Get-Content "$out\cycle-$($ProfileCycles-1)-redux-memory.json" -Raw | ConvertFrom-Json
   $offGrowth=$lastOff.privateBytes-$firstOff.privateBytes
   Write-Host ('PROFILE_CYCLE_ATLAS_PRIVATE_GROWTH_BYTES='+$offGrowth)
   if($offGrowth -gt 16MB){throw 'Atlas fallback cycles retained more than 16 MiB private commit'}
  }
 }
}
