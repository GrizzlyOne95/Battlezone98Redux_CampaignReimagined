<# Serialized material/lighting/horizon review. Every child restores its files. #>
param(
 [Parameter(Mandatory=$true)][string]$OpenShimRepo,
 [Parameter(Mandatory=$true)][string]$CandidateRoot,
 [string[]]$Worlds=@('mars','venus','io','europa','titan','ganymede','achilles','elysium','moon')
)
$ErrorActionPreference='Stop'
$cr=Split-Path -Parent $PSScriptRoot
$root=(Resolve-Path -LiteralPath $CandidateRoot).Path
$index=Join-Path $root 'live_review.json'
$evidence=if(Test-Path -LiteralPath $index){@(Get-Content -LiteralPath $index -Raw | ConvertFrom-Json)}else{@()}
$types=@{moon=0;mars=0;venus=3;io=3;europa=0;titan=3;ganymede=1;achilles=0;elysium=0}
foreach($world in $Worlds){
 if(-not $types.ContainsKey($world)){throw 'Unknown world'}
 $bundle=Join-Path $root ((Get-Culture).TextInfo.ToTitleCase($world)+'Hd1024')
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\Test-MarsHdTerrainLive.ps1",'-OpenShimRepo',$OpenShimRepo,
              '-TileDirectory',$bundle,'-World',$world,'-Hd','-MicroRelief','-GroundView','-SettingsOnly','-MeasureMemory','-WorldArt','-SurfaceType',[string]$types[$world])
 if($world -eq 'achilles'){$arguments+='-CloudDeck'}
 if($world -eq 'moon'){$arguments+=@('-DetailTexture',(Join-Path $bundle 'resources\crhd_moon_regolith_detail.dds'))}
 $transcript=(& powershell.exe @arguments 2>&1 | Tee-Object -Variable childOutput | Out-String)
 Write-Output $transcript
 if($LASTEXITCODE -ne 0){throw "World art preview failed: $world"}
 $match=[regex]::Match($transcript,'RESTORED (\d+) files\. Evidence: (.+)')
 if(-not $match.Success){throw "No restoration evidence: $world"}
 $evidence = @($evidence | Where-Object {$_.world -ne $world}) + [pscustomobject]@{world=$world;path=$match.Groups[2].Value.Trim();restoredFiles=[int]$match.Groups[1].Value}
 ConvertTo-Json -InputObject @($evidence) -Depth 5 | Set-Content -LiteralPath $index -Encoding UTF8
}
