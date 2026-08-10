<#
.SYNOPSIS
    Selects a DX11 terrain-normal diagnostic in the GOG test runtime.

.DESCRIPTION
    Always starts from the canonical CR terrain shader, changes only guarded
    compile-time diagnostic defaults in the deployed runtime copy, and refuses
    Steam Workshop cache targets. Relaunch Battlezone after every selection.

.EXAMPLE
    .\Tools\Set-TerrainNormalDiagnostic.ps1 -Basis Orthonormal -View None

.EXAMPLE
    .\Tools\Set-TerrainNormalDiagnostic.ps1 -Basis Stock -View BasisOrthogonality

.EXAMPLE
    .\Tools\Set-TerrainNormalDiagnostic.ps1 -Unpack RGB -Basis Stock -View None
#>
[CmdletBinding()]
param(
    [ValidateSet('RGB', 'RG', 'AG')]
    [string]$Unpack = 'RGB',

    [switch]$FlipGreen,

    [ValidateSet('Stock', 'NormalizeAxes', 'Orthonormal', 'GeometryOnly', 'TangentAsView')]
    [string]$Basis = 'Stock',

    [ValidateSet(
        'None', 'SampleRGB', 'SampleAlpha', 'TangentNormal', 'LightingNormal',
        'NdotL', 'GeometryNormal', 'TangentAxis', 'BitangentAxis',
        'BasisOrthogonality', 'BasisCondition', 'NormalDeviation')]
    [string]$View = 'None',

    [string]$RuntimeDir = 'C:\Program Files (x86)\GOG Galaxy\Games\Battlezone 98 Redux\mods\3686673790'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runtimeFull = [IO.Path]::GetFullPath($RuntimeDir).TrimEnd('\')
if ($runtimeFull -match '(?i)\\steamapps\\workshop\\') {
    throw "Refusing to write a development diagnostic into Steam's Workshop cache: $runtimeFull"
}
if (-not (Test-Path -LiteralPath $runtimeFull -PathType Container)) {
    throw "Runtime directory does not exist: $runtimeFull"
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceShader = Join-Path $repoRoot 'Shaders\CR_terrain-sm4.hlsl'
$runtimeShader = Join-Path $runtimeFull 'CR_terrain-sm4.hlsl'
if (-not (Test-Path -LiteralPath $sourceShader -PathType Leaf)) {
    throw "Canonical terrain shader does not exist: $sourceShader"
}
if (-not (Test-Path -LiteralPath $runtimeShader -PathType Leaf)) {
    throw "Deployed terrain shader does not exist: $runtimeShader"
}

$unpackModes = @{ RGB = 0; RG = 1; AG = 2 }
$basisModes = @{
    Stock = 0
    NormalizeAxes = 1
    Orthonormal = 2
    GeometryOnly = 3
    TangentAsView = 4
}
$debugModes = @{
    None = 0
    SampleRGB = 1
    SampleAlpha = 2
    TangentNormal = 3
    LightingNormal = 4
    NdotL = 5
    GeometryNormal = 6
    TangentAxis = 7
    BitangentAxis = 8
    BasisOrthogonality = 9
    BasisCondition = 10
    NormalDeviation = 11
}

# Always begin from the canonical shader so switching diagnostic modes cannot
# accumulate an earlier runtime-only edit. Only the four guarded defaults are
# changed in the deployed GOG copy.
$text = [IO.File]::ReadAllText($sourceShader)
$values = @{
    CR_TERRAIN_NORMAL_UNPACK_MODE = $unpackModes[$Unpack]
    CR_TERRAIN_NORMAL_FLIP_GREEN = $(if ($FlipGreen) { 1 } else { 0 })
    CR_TERRAIN_NORMAL_BASIS_MODE = $basisModes[$Basis]
    CR_TERRAIN_NORMAL_DEBUG_MODE = $debugModes[$View]
}

foreach ($name in $values.Keys) {
    $pattern = '(?m)^(\s*#define\s+' + [regex]::Escape($name) + '\s+)0(\s*)$'
    $replacement = '${1}' + [string]$values[$name] + '${2}'
    $updated = [regex]::Replace($text, $pattern, $replacement, 1)
    if ($updated -eq $text -and $values[$name] -ne 0) {
        throw "Could not set $name in canonical shader; expected an opt-in default of zero."
    }
    $text = $updated
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($runtimeShader, $text, $utf8NoBom)

$hash = (Get-FileHash -LiteralPath $runtimeShader -Algorithm SHA256).Hash
[pscustomobject]@{
    RuntimeShader = $runtimeShader
    Unpack = $Unpack
    FlipGreen = [bool]$FlipGreen
    Basis = $Basis
    View = $View
    SHA256 = $hash
}
