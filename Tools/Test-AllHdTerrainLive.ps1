<# Sequential, serialized HD previews; each child owns restoration and shutdown. #>
param(
 [Parameter(Mandatory=$true)][string]$OpenShimRepo,
 [string]$HarnessRepo,
 [string]$GameRoot='C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux',
 [string[]]$Worlds=@('moon','mars','venus','io','europa','titan','achilles','ganymede','elysium'),
 [switch]$AtlasBaseline,
 [switch]$ReduxGate
)
$ErrorActionPreference='Stop'
$cr=Split-Path -Parent $PSScriptRoot
foreach($world in $Worlds){
 if($world -notin @('moon','mars','venus','io','europa','titan','achilles','ganymede','elysium')){throw 'Unknown world'}
 $title=(Get-Culture).TextInfo.ToTitleCase($world)
 $options=@('-NoProfile','-File',"$PSScriptRoot\Test-MarsHdTerrainLive.ps1",'-World',$world,
            '-OpenShimRepo',$OpenShimRepo,'-GameRoot',$GameRoot,'-TileDirectory',"$cr\Local\TerrainHD\$($title)Hd1024",
            '-WideView','-BaseView','-MeasureMemory')
 if($HarnessRepo){$options+=@('-HarnessRepo',$HarnessRepo)}
 if(-not $AtlasBaseline){$options+='-Hd'}
 if($ReduxGate){$options+=@('-RenderProfile','Redux')}
 & powershell.exe @options
 if($LASTEXITCODE -ne 0){throw "Terrain preview failed: $world"}
}
