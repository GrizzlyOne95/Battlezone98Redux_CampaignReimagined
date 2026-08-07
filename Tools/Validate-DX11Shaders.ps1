[CmdletBinding()]
param(
    [string]$FxcPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$baseShader = Join-Path $repoRoot 'Shaders\CR_base-sm4.hlsl'
$terrainShader = Join-Path $repoRoot 'Shaders\CR_terrain-sm4.hlsl'

if (-not $FxcPath) {
    $fxc = Get-Command fxc.exe -ErrorAction SilentlyContinue
    if ($fxc) {
        $FxcPath = $fxc.Source
    }
}

if (-not $FxcPath) {
    $kitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $kitsRoot) {
        $FxcPath = Get-ChildItem $kitsRoot -Filter fxc.exe -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $FxcPath -or -not (Test-Path $FxcPath)) {
    throw 'fxc.exe was not found. Install a Windows SDK or pass -FxcPath explicitly.'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) 'bzr-dx11-shader-validation'
if (Test-Path $tempRoot) {
    Remove-Item $tempRoot -Recurse -Force
}
New-Item $tempRoot -ItemType Directory | Out-Null

$cases = @(
    @{
        Name = 'base-vs-high'
        File = $baseShader
        Entry = 'base_vertex'
        Target = 'vs_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1')
    },
    @{
        Name = 'base-ps-enhanced'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'base-ps-enhanced-shadow'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'SHADOWRECEIVER=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'base-ps-enhanced-pssm'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'SHADOWRECEIVER=1', 'PSSM_ENABLED=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'base-ps-retro'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=8', 'OG_RETRO_MODE=1', 'RETRO_UNLIT_MODE=1')
    },
    @{
        Name = 'terrain-vs-high'
        File = $terrainShader
        Entry = 'terrain_vertex'
        Target = 'vs_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1')
    },
    @{
        Name = 'terrain-ps-enhanced'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'terrain-ps-enhanced-shadow'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'SHADOWRECEIVER=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'terrain-ps-enhanced-pssm'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'SHADOWRECEIVER=1', 'PSSM_ENABLED=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'terrain-ps-retro'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=8', 'DETAILMAP_ENABLED=1', 'OG_RETRO_MODE=1', 'RETRO_UNLIT_MODE=1')
    }
)

$failed = @()

foreach ($case in $cases) {
    $output = Join-Path $tempRoot "$($case.Name).cso"
    $args = @('/nologo', '/Ges', '/WX', '/T', $case.Target, '/E', $case.Entry, '/Fo', $output)

    foreach ($define in $case.Defines) {
        $args += @('/D', $define)
    }

    $args += $case.File

    Write-Host "Compiling $($case.Name)..."
    & $FxcPath @args

    if ($LASTEXITCODE -ne 0) {
        $failed += $case.Name
    }
}

if ($failed.Count -gt 0) {
    throw "DX11 shader validation failed: $($failed -join ', ')"
}

Write-Host "All $($cases.Count) representative DX11 SM4 shader variants compiled successfully."
