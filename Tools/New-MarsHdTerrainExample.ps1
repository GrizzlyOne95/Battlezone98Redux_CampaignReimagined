<# Export editable source tiles, prepare their automatic native mapping, and
   optionally run a reversible preview. Existing tiles are kept for art edits.
   Run with Windows PowerShell 5.1 when using -Preview.
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$OpenShimRepo,
 [string]$SourceBuild,
 [string]$OutputDirectory,
 [ValidateSet(512,1024,2048)][int]$TileSize=1024,
 [string]$GameRoot='C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux',
 [string]$HarnessRepo,
 [switch]$Preview,
 [switch]$MeasureMemory
)
$ErrorActionPreference='Stop'
$cr=Split-Path -Parent $PSScriptRoot
if(-not $OutputDirectory){$OutputDirectory=Join-Path $cr "Local\TerrainHD\MarsHeightMatched$TileSize"}
$output=[IO.Path]::GetFullPath($OutputDirectory)
$metadata=Join-Path $output 'source_tiles.json'
if(Test-Path -LiteralPath $metadata){
 $saved=Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
 if($saved.tileSize -ne $TileSize){throw 'Existing tiles have another size; select another output directory.'}
 Write-Host 'Keeping existing editable tile images; refreshing their runtime manifest.'
 & python "$PSScriptRoot\Build-MarsHdTileSources.py" --bind-existing --output $output
}else{
 if(-not $SourceBuild){$SourceBuild=Join-Path $GameRoot 'output\stock_world_texture_survey_20261014'}
 & python "$PSScriptRoot\Build-MarsHdTileSources.py" --source-build $SourceBuild --output $output --tile-size $TileSize
}
if($LASTEXITCODE -ne 0){throw 'Source pack generation failed'}
& python "$PSScriptRoot\Test-MarsHdTileSources.py" --export $output
if($LASTEXITCODE -ne 0){throw 'Source pack validation failed'}
Write-Host "Ready: $output\cr_mars_hd.json"
Write-Host 'Edit the independent *_d/_n/_s DDS images to customize the art. Rerun this command to preview your edits.'
if($Preview){
 $options=@{OpenShimRepo=$OpenShimRepo;TileDirectory=$output;GameRoot=$GameRoot;Hd=$true;WideView=$true;MeasureMemory=[bool]$MeasureMemory}
 if($HarnessRepo){$options.HarnessRepo=$HarnessRepo}
 & "$PSScriptRoot\Test-MarsHdTerrainLive.ps1" @options
}
