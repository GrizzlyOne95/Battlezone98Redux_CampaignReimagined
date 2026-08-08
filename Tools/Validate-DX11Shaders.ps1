[CmdletBinding()]
param(
    [string]$FxcPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$baseShader = Join-Path $repoRoot 'Shaders\CR_base-sm4.hlsl'
$terrainShader = Join-Path $repoRoot 'Shaders\CR_terrain-sm4.hlsl'
$uiShader = Join-Path $repoRoot 'Shaders\CR_ui-sm4.hlsl'
$overlayShader = Join-Path $repoRoot 'Shaders\CR_overlay-sm4.hlsl'

# DX11 color-space audit Stage 1 is diagnostic-only. Do not let an sRGB
# transfer helper or experiment define silently land before an actual BZR DX11
# capture proves the live resource/SRV/RTV state. When that runtime gate is
# satisfied, update these guards in the same commit that adds the explicit
# Enhanced-only experiment and its validation cases.
$stageOneForbiddenPatterns = @(
    '\bsrgb_to_linear\b',
    '\blinear_to_srgb\b',
    '\bCR_LINEAR_LIGHT\b',
    '\bCR_LINEAR_LIGHT_DECODE_'
)

foreach ($shader in @($baseShader, $terrainShader)) {
    $source = Get-Content -LiteralPath $shader -Raw
    foreach ($pattern in $stageOneForbiddenPatterns) {
        if ($source -match $pattern) {
            throw "DX11 color-space audit Stage 1 forbids '$pattern' in $shader until runtime UNORM/SRV evidence is recorded."
        }
    }
}

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
        Name = 'ui-vs-sm4'
        File = $uiShader
        Entry = 'ui_vertex'
        Target = 'vs_4_0'
        Defines = @()
    },
    @{
        Name = 'ui-ps-sm4'
        File = $uiShader
        Entry = 'ui_fragment'
        Target = 'ps_4_0'
        Defines = @()
    },
    @{
        Name = 'overlay-ps-tint'
        File = $overlayShader
        Entry = 'overlay_tint_fragment'
        Target = 'ps_4_0'
        Defines = @()
    },
    @{
        Name = 'base-vs-high-cotangent'
        File = $baseShader
        Entry = 'base_vertex'
        Target = 'vs_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1')
    },
    @{
        Name = 'base-vs-high-tangent'
        File = $baseShader
        Entry = 'base_vertex'
        Target = 'vs_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'VERTEX_TANGENTS=1')
    },
    @{
        Name = 'base-ps-lowest-emissive'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('VERTEX_LIGHTING=1', 'MAX_LIGHTS=1', 'EMISSIVEMAP_ENABLED=1')
    },
    @{
        Name = 'base-ps-low-emissive'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1')
    },
    @{
        Name = 'base-ps-medium-emissive'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=8', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1')
    },
    @{
        Name = 'base-ps-enhanced'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'base-ps-enhanced-tangent'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'VERTEX_TANGENTS=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'base-ps-enhanced-minimal'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'base-ps-enhanced-specular-no-map'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=1', 'SPECULAR_ENABLED=1', 'ENHANCED_MODE=1')
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
        Name = 'base-ps-ibl-noshadow'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1')
    },
    @{
        Name = 'base-ps-ibl-shadow'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1', 'SHADOWRECEIVER=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'base-ps-ibl-pssm'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1', 'SHADOWRECEIVER=1', 'PSSM_ENABLED=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'base-ps-atmos-debug-colour'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1', 'SHADOWRECEIVER=1', 'PSSM_ENABLED=1', 'PCF_SIZE=4', 'CR_ATMOS_DEBUG_MODE=4')
    },
    @{
        Name = 'base-ps-retro'
        File = $baseShader
        Entry = 'base_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=8', 'OG_RETRO_MODE=1', 'RETRO_UNLIT_MODE=1')
    },
    @{
        Name = 'terrain-vs-high-cotangent'
        File = $terrainShader
        Entry = 'terrain_vertex'
        Target = 'vs_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1')
    },
    @{
        Name = 'terrain-vs-high-tangent'
        File = $terrainShader
        Entry = 'terrain_vertex'
        Target = 'vs_4_0'
        Defines = @('MAX_LIGHTS=24', 'NORMALMAP_ENABLED=1', 'VERTEX_TANGENTS=1')
    },
    @{
        Name = 'terrain-ps-lowest-emissive'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('VERTEX_LIGHTING=1', 'MAX_LIGHTS=1', 'DETAILMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1')
    },
    @{
        Name = 'terrain-ps-low-emissive'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=1', 'DETAILMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1')
    },
    @{
        Name = 'terrain-ps-medium-emissive'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=8', 'DETAILMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1')
    },
    @{
        Name = 'terrain-ps-enhanced'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'terrain-ps-enhanced-tangent'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'VERTEX_TANGENTS=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1')
    },
    @{
        Name = 'terrain-ps-enhanced-minimal'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=1', 'DETAILMAP_ENABLED=1', 'ENHANCED_MODE=1')
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
        Name = 'terrain-ps-ibl-noshadow'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1')
    },
    @{
        Name = 'terrain-ps-ibl-shadow'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1', 'SHADOWRECEIVER=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'terrain-ps-ibl-pssm'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1', 'SHADOWRECEIVER=1', 'PSSM_ENABLED=1', 'PCF_SIZE=4')
    },
    @{
        Name = 'terrain-ps-atmos-debug-height'
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = @('MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1', 'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1', 'IBL_ENABLED=1', 'CR_ATMOS_DEBUG_MODE=2')
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

Write-Host "Stage-1 DX11 color-space source guards passed."
Write-Host "All $($cases.Count) representative DX11 SM4 shader variants compiled successfully."
