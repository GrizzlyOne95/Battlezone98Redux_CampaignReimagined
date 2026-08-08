[CmdletBinding()]
param(
    [string]$FxcPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$shaderDir = Join-Path $repoRoot 'Shaders'
$baseShader = Join-Path $shaderDir 'CR_base-sm4.hlsl'
$terrainShader = Join-Path $shaderDir 'CR_terrain-sm4.hlsl'
$uiShader = Join-Path $shaderDir 'CR_ui-sm4.hlsl'
$overlayShader = Join-Path $shaderDir 'CR_overlay-sm4.hlsl'

$stageAShaders = @($baseShader, $terrainShader)

# =============================================================================
# DX11 color-space Stage A source guards
# =============================================================================
# The previous Stage-1 guard forbade sRGB transfer functions outright because no
# runtime capture existed yet. That capture has since been taken: the DX11
# swapchain/backbuffer is ordinary R8G8B8A8_UNORM, the relevant RTVs are
# non-sRGB, no _SRGB resource/SRV/RTV appeared anywhere, and Ogre reported
# "sRGB Gamma Conversion = No".
#
# The prohibition is therefore replaced - not deleted - by assertions that keep
# the Stage A experiment inside its intended boundaries:
#
#   * CR_LINEAR_LIGHT exists and defaults to 0;
#   * it can only activate on the DX11 Enhanced per-pixel path;
#   * only genuine COLOR textures are decoded;
#   * data textures (normal/specular/detail/shadow/IBL/BRDF) are never decoded;
#   * alpha never passes through either transfer function;
#   * exactly one final linear->sRGB encode per applicable Enhanced path,
#     positioned after atmosphere integration;
#   * unrelated shader paths and the materials gain no gamma behavior.
#
# See Docs/DX11_COLOR_SPACE_AUDIT.md.

$sourceFailures = @()

function Add-SourceFailure {
    param([string]$Message)
    $script:sourceFailures += $Message
}

# Identifiers that must never be fed to srgb_to_linear(). These are data or
# hybrid-data sources, not artist-authored display colour.
$forbiddenDecodeTokens = @(
    'normalMap', 'normalTex', 'normalSam',
    'specularMap', 'specularTex', 'specularSam', 'specularTint', 'surfaceF0',
    'detailMap', 'detailTex', 'detailTexNear', 'detailSam', 'detailColor', 'detailMultiplier',
    'shadowMap', 'shadowSam', 'vLightSpacePos', 'pssmSplitPoints',
    'irradianceMap', 'irradiance', 'irradianceSam',
    'prefilteredEnvMap', 'prefilteredEnvironment', 'prefilteredEnvSam',
    'brdfLut', 'brdfLutSam', 'environmentBRDF',
    'vDepth', 'oDepth',
    'fogColour', 'sceneAmbient', 'lightDiffuse', 'lightSpecular'
)

# The complete, intentional Stage A decode allow-list. Anything else that calls
# srgb_to_linear() is a scope regression.
#
# 'vertexTint' is the terrain per-vertex COLOR0 tint. It is on the list because
# it multiplies the decoded albedo directly (lightResult * vertexTint *
# diffuseTex), so it is authored display colour by construction: leaving it
# encoded would multiply a linear albedo by a gamma-space tint. BZCC applies the
# same decode to every vertex-colour layout it ships, terrain included -
# pow(COLOR.rgb, 2.2) in its vertex stage, alpha untouched - which is what
# distinguishes this from vertex colour used as layer weights or another
# numerical channel. Only the rgb float3 is ever decoded; vColor.a stays raw
# because it is the terrain output alpha.
$allowedDecodeTargets = @('diffuseTex.rgb', 'emissiveTex', 'vertexTint')

# Targets that exist in only one shader family. They are required in their owner
# and forbidden everywhere else, so the base shader is not failed for lacking a
# terrain-only input and terrain cannot quietly drop it.
$familyScopedDecodeTargets = @('vertexTint')
$familyScopedDecodeOwners = @{ 'vertexTint' = 'CR_terrain-sm4.hlsl' }

# Any swizzle or member access that includes an alpha/w component.
$alphaComponentPattern = '\.[rgbaxyzw]*[awAW][rgbaxyzw]*\b'

foreach ($shader in $stageAShaders) {
    $name = Split-Path -Leaf $shader
    $rawSource = Get-Content -LiteralPath $shader -Raw

    # Strip // comments before any pattern matching, so prose that merely
    # *describes* a construct (for example the note explaining why pow(x, 2.2)
    # is not used) can never be mistaken for the construct itself. The
    # replacement preserves line breaks, so reported line numbers stay correct.
    # These shaders use // exclusively; assert that stays true.
    if ($rawSource -match '/\*') {
        Add-SourceFailure "$name contains a /* */ block comment; the Stage A source guards only strip // comments."
    }
    $source = $rawSource -replace '(?m)//.*$', ''

    # -- The experiment flag exists and is off by default ---------------------
    if ($source -notmatch '(?m)^\s*#ifndef\s+CR_LINEAR_LIGHT\s*\r?\n\s*#define\s+CR_LINEAR_LIGHT\s+0\s*\r?\n\s*#endif') {
        Add-SourceFailure "$name does not declare CR_LINEAR_LIGHT with a default of 0."
    }

    # -- Activation is scoped to the DX11 Enhanced per-pixel path -------------
    $activationIndex = $source.IndexOf('#define CR_LINEAR_LIGHT_ACTIVE 1')
    $conditionStart = if ($activationIndex -ge 0) {
        $source.Substring(0, $activationIndex).LastIndexOf('#if')
    } else { -1 }

    if ($activationIndex -lt 0 -or $conditionStart -lt 0) {
        Add-SourceFailure "$name does not gate CR_LINEAR_LIGHT_ACTIVE behind a preceding #if condition."
    }
    else {
        # Fold line continuations so the whole logical #if is one string, then
        # confirm nothing but that condition sits between #if and the #define.
        $rawCondition = $source.Substring($conditionStart, $activationIndex - $conditionStart)
        $condition = (($rawCondition -replace '\\\r?\n', ' ') -replace '\s+', ' ').Trim()

        if ($rawCondition -replace '\\\r?\n', ' ' -match '\r?\n\s*\S') {
            Add-SourceFailure "$name has unexpected content between the #if condition and '#define CR_LINEAR_LIGHT_ACTIVE 1'."
        }

        $requiredTerms = @(
            'defined(ENHANCED_MODE)',
            '!defined(VERTEX_LIGHTING)',
            '!defined(OG_RETRO_MODE)',
            '!defined(RETRO_UNLIT_MODE)',
            'CR_LINEAR_LIGHT != 0'
        )
        foreach ($term in $requiredTerms) {
            if ($condition -notlike "*$term*") {
                Add-SourceFailure "$name CR_LINEAR_LIGHT_ACTIVE condition is missing '$term'. Stage A must not reach Default/Retro/vertex-lighting paths."
            }
        }
    }

    if ($source -notmatch '(?m)^\s*#define\s+CR_LINEAR_LIGHT_ACTIVE\s+0\s*$') {
        Add-SourceFailure "$name does not define CR_LINEAR_LIGHT_ACTIVE to 0 for every non-Enhanced permutation."
    }

    # -- The transfer functions are the real piecewise curves -----------------
    if ($source -notmatch '\b0\.04045\b' -or $source -notmatch '\b12\.92\b') {
        Add-SourceFailure "$name is missing the piecewise sRGB->linear breakpoint/slope (0.04045 / 12.92)."
    }
    if ($source -notmatch '\b0\.0031308\b' -or $source -notmatch '\b1\.055\b' -or $source -notmatch '\b0\.055\b') {
        Add-SourceFailure "$name is missing the piecewise linear->sRGB breakpoint/scale (0.0031308 / 1.055 / 0.055)."
    }
    if ($source -match 'pow\s*\([^)]*,\s*2\.2\s*\)' -or $source -match 'pow\s*\([^)]*,\s*1\.0\s*/\s*2\.2\s*\)') {
        Add-SourceFailure "$name uses a pow(x, 2.2) gamma approximation. Stage A requires the piecewise sRGB transfer functions."
    }

    # -- Decode call sites: allow-list, data exclusions, alpha safety ---------
    $decodeSites = [regex]::Matches(
        $source,
        '(?m)^\s*(?<target>[A-Za-z_][A-Za-z0-9_.]*)\s*=\s*srgb_to_linear\s*\(\s*(?<arg>[^;]*?)\s*\)\s*;')

    if ($decodeSites.Count -eq 0) {
        Add-SourceFailure "$name contains no srgb_to_linear() decode site. Stage A must decode diffuse and emissive COLOR."
    }

    $observedTargets = @()
    foreach ($site in $decodeSites) {
        $target = $site.Groups['target'].Value
        $arg = $site.Groups['arg'].Value
        $observedTargets += $target

        if ($allowedDecodeTargets -notcontains $target) {
            Add-SourceFailure "$name decodes '$target', which is not on the Stage A COLOR allow-list ($($allowedDecodeTargets -join ', '))."
        }

        foreach ($token in $forbiddenDecodeTokens) {
            if ($target -match "\b$([regex]::Escape($token))\b" -or $arg -match "\b$([regex]::Escape($token))\b") {
                Add-SourceFailure "$name applies srgb_to_linear() to data source '$token'. Data textures and engine RGB constants must stay untouched in Stage A."
            }
        }

        if ($target -match $alphaComponentPattern -or $arg -match $alphaComponentPattern) {
            Add-SourceFailure "$name passes an alpha/w component through srgb_to_linear() ('$target = srgb_to_linear($arg)'). Alpha is never display-encoded."
        }
    }

    # Every Stage A shader must decode the universal COLOR sources. Targets that
    # only exist in one family (see $familyScopedDecodeTargets) are permitted but
    # not demanded, so the base shader is not failed for lacking a terrain-only
    # input. A family-scoped target still has to pass every other guard above.
    foreach ($required in $allowedDecodeTargets) {
        if ($familyScopedDecodeTargets -contains $required) { continue }
        if ($observedTargets -notcontains $required) {
            Add-SourceFailure "$name is missing the required Stage A decode of '$required'."
        }
    }

    foreach ($scoped in $familyScopedDecodeTargets) {
        $owner = $familyScopedDecodeOwners[$scoped]
        if ($name -eq $owner -and $observedTargets -notcontains $scoped) {
            Add-SourceFailure "$name is missing the required Stage A decode of '$scoped'."
        }
        if ($name -ne $owner -and $observedTargets -contains $scoped) {
            Add-SourceFailure "$name decodes '$scoped', which is scoped to $owner only."
        }
    }

    # -- Encode call site: exactly one, RGB only, after atmosphere ------------
    $encodeSites = [regex]::Matches(
        $source,
        '(?m)^\s*(?<target>[A-Za-z_][A-Za-z0-9_.]*)\s*=\s*linear_to_srgb\s*\(\s*(?<arg>[^;]*?)\s*\)\s*;')

    if ($encodeSites.Count -ne 1) {
        Add-SourceFailure "$name has $($encodeSites.Count) linear_to_srgb() call sites. Stage A requires exactly one final encode."
    }
    else {
        $encode = $encodeSites[0]
        $target = $encode.Groups['target'].Value
        $arg = $encode.Groups['arg'].Value

        if ($target -ne 'oColor.rgb' -or $arg -ne 'oColor.rgb') {
            Add-SourceFailure "$name final encode is '$target = linear_to_srgb($arg)'; expected 'oColor.rgb = linear_to_srgb(oColor.rgb)'."
        }
        if ($target -match $alphaComponentPattern -or $arg -match $alphaComponentPattern) {
            Add-SourceFailure "$name passes an alpha/w component through linear_to_srgb(). Alpha is never display-encoded."
        }

        $atmosphereCall = $source.LastIndexOf('compute_enhanced_atmosphere(')
        if ($atmosphereCall -lt 0) {
            Add-SourceFailure "$name no longer calls compute_enhanced_atmosphere(); the Stage A ordering guard cannot be evaluated."
        }
        elseif ($encode.Index -lt $atmosphereCall) {
            Add-SourceFailure "$name applies the final linear_to_srgb() before atmosphere integration. Atmosphere belongs inside the linear-light region."
        }

        $alphaWrite = [regex]::Match($source, '(?m)^\s*oColor\.a\s*=')
        if ($alphaWrite.Success -and $encode.Index -gt $alphaWrite.Index) {
            Add-SourceFailure "$name writes oColor.a before the final encode; the encode must be the last colour operation."
        }
    }

    # -- Transfer-function uses are guarded ----------------------------------
    # Every reference outside the definitions must sit under CR_LINEAR_LIGHT_ACTIVE.
    $lines = $source -split '\r?\n'
    $guardDepth = 0
    $conditionalStack = New-Object System.Collections.Generic.Stack[bool]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()

        if ($trimmed -match '^#if') {
            $isStageAGuard = $trimmed -match '^#if\s+CR_LINEAR_LIGHT_ACTIVE\s*$'
            $conditionalStack.Push($isStageAGuard)
            if ($isStageAGuard) { $guardDepth++ }
            continue
        }
        if ($trimmed -match '^#endif') {
            if ($conditionalStack.Count -gt 0) {
                if ($conditionalStack.Pop()) { $guardDepth-- }
            }
            continue
        }
        if ($trimmed -match '^#(else|elif)') {
            continue
        }

        if ($line -match '\b(srgb_to_linear|linear_to_srgb)\s*\(' -and $guardDepth -le 0) {
            Add-SourceFailure "$name line $($i + 1) references an sRGB transfer function outside a '#if CR_LINEAR_LIGHT_ACTIVE' guard: $trimmed"
        }
    }

    # -- Ordering: each decode happens at the sample, before any consumption --
    # Assert that nothing reads the sampled variable between the Sample() call
    # and its decode. That is a stronger statement than "the decode is early":
    # it proves no lighting, intensity or detail maths can ever observe the
    # undecoded value.
    $sampleSites = @(
        @{ Variable = 'diffuseTex'; Decode = 'diffuseTex.rgb = srgb_to_linear(' },
        @{ Variable = 'emissiveTex'; Decode = 'emissiveTex = srgb_to_linear(' }
    )

    foreach ($site in $sampleSites) {
        $variable = $site.Variable
        $sampleMatch = [regex]::Match($source, "$variable\s*=\s*\w+Map\.Sample\([^;]*;")
        $decodeIndex = $source.IndexOf($site.Decode)

        if (-not $sampleMatch.Success) {
            Add-SourceFailure "$name has no '$variable = ...Map.Sample(...)' site; the Stage A ordering guard cannot be evaluated."
            continue
        }
        if ($decodeIndex -lt 0) {
            Add-SourceFailure "$name never decodes '$variable'."
            continue
        }

        $sampleEnd = $sampleMatch.Index + $sampleMatch.Length
        if ($decodeIndex -lt $sampleEnd) {
            Add-SourceFailure "$name decodes '$variable' before it is sampled."
            continue
        }

        $between = $source.Substring($sampleEnd, $decodeIndex - $sampleEnd)
        if ($between -match "\b$variable\b") {
            Add-SourceFailure "$name reads '$variable' between the sample and the sRGB decode. The decode must happen at the sample."
        }
    }

    # -- Terrain detail must never be decoded --------------------------------
    if ($name -eq 'CR_terrain-sm4.hlsl') {
        if ($source -match 'detail[A-Za-z]*\s*=\s*srgb_to_linear' -or $source -match 'srgb_to_linear\s*\(\s*detail') {
            Add-SourceFailure "$name decodes the terrain detail map. Detail is 0.5-centred modulation data (x2 => 1.0 neutral); decoding it would collapse the neutral point to ~0.43."
        }
    }
}

# -- No other shader path gains sRGB transfer behavior ------------------------
# Only shader source is scanned. The .program scripts are deliberately left out
# so an A/B tester may flip the experiment on through preprocessor_defines
# without tripping a guard; the shader sources themselves still enforce that
# CR_LINEAR_LIGHT can only activate on the Enhanced per-pixel path.
$otherShaders = Get-ChildItem -LiteralPath $shaderDir -File |
    Where-Object { $_.Extension -in @('.hlsl', '.glsl') } |
    Where-Object { $stageAShaders -notcontains $_.FullName }

foreach ($other in $otherShaders) {
    $otherSource = Get-Content -LiteralPath $other.FullName -Raw
    if ($otherSource -match '\b(srgb_to_linear|linear_to_srgb|CR_LINEAR_LIGHT)\b') {
        Add-SourceFailure "$($other.Name) references Stage A colour-space symbols. Default, Retro, DX9/GL, UI and overlay paths must not gain sRGB transfer behavior."
    }
}

# -- Hardware gamma stays off; the experiment is shader-side only -------------
$stageAMaterials = @(
    (Join-Path $repoRoot 'Materials\CR_BZBase.material'),
    (Join-Path $repoRoot 'Materials\CR_BZTerrainBase.material')
)

foreach ($material in $stageAMaterials) {
    if (-not (Test-Path -LiteralPath $material)) { continue }
    $materialSource = Get-Content -LiteralPath $material -Raw
    if ($materialSource -match '(?m)^\s*gamma\b') {
        Add-SourceFailure "$(Split-Path -Leaf $material) declares hardware 'gamma' on a texture unit. Stage A is intentionally 'hardware gamma OFF + explicit shader-side conversion'."
    }
}

if ($sourceFailures.Count -gt 0) {
    $detail = ($sourceFailures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "DX11 color-space Stage A source guards failed:$([Environment]::NewLine)$detail"
}

Write-Host "Stage A DX11 color-space source guards passed ($($stageAShaders.Count) shaders, $($otherShaders.Count) unrelated shader files scanned)."

# =============================================================================
# Program-definition rendering-mode boundary
# =============================================================================
# The HLSL default for CR_LINEAR_LIGHT stays 0, so what actually opts a variant
# into Stage A is its .program 'preprocessor_defines'. That makes the .program
# files - not the shader source - the place where the DX11 Enhanced boundary can
# drift. These guards assert the boundary directly:
#
#   * every DX11 Enhanced SM4 fragment program defines CR_LINEAR_LIGHT=1;
#   * Retro SM4 programs never do;
#   * Default/stock-compatible SM4 programs never do;
#   * DX9, GLSL, GLSLES and unified delegate declarations never do;
#   * vertex programs never do (Stage A is a per-pixel path);
#   * where the define is present its value is exactly 1.
#
# Classification is derived from each declaration's own source/kind/defines so
# that reordering or adding programs cannot silently defeat the check.

function Get-OgreProgramRecords {
    param([string]$Path)
    $programLines = [System.IO.File]::ReadAllLines($Path)
    $records = @()
    $cur = $null
    $depth = 0
    for ($i = 0; $i -lt $programLines.Count; $i++) {
        $t = $programLines[$i].Trim()
        if ($t.StartsWith('//')) { continue }
        if ($t -match '^(vertex_program|fragment_program)\s+(\S+)\s+(\S+)\s*$') {
            $cur = [pscustomobject]@{
                File = Split-Path -Leaf $Path
                Line = $i + 1
                Kind = $Matches[1]
                Name = $Matches[2]
                Lang = $Matches[3]
                Source = ''
                Defines = ''
            }
            $depth = 0
            continue
        }
        if ($null -eq $cur) { continue }
        if ($t -eq '{') { $depth++; continue }
        if ($t -eq '}') {
            $depth--
            if ($depth -le 0) { $records += $cur; $cur = $null; $depth = 0 }
            continue
        }
        if ($t -match '^source\s+(\S+)') { $cur.Source = $Matches[1] }
        elseif ($t -match '^preprocessor_defines\s+(.+)$') { $cur.Defines = $Matches[1].Trim() }
    }
    return $records
}

$programFailures = @()
$programRecords = @()
foreach ($programFile in (Get-ChildItem $shaderDir -Filter '*.program' -File | Sort-Object Name)) {
    $programRecords += Get-OgreProgramRecords -Path $programFile.FullName
}

$enhancedSm4Count = 0
$legacySm4Count = 0

foreach ($rec in $programRecords) {
    $defines = $rec.Defines
    $where = "$($rec.File):$($rec.Line) $($rec.Name)"

    $hasLinear = $defines -match '(^|,)\s*CR_LINEAR_LIGHT\s*='
    $hasLinearOne = $defines -match '(^|,)\s*CR_LINEAR_LIGHT\s*=\s*1\s*(,|$)'

    if ($hasLinear -and -not $hasLinearOne) {
        $programFailures += "$where declares CR_LINEAR_LIGHT with a value other than 1. Stage A is on/off only."
    }

    $isSm4 = $rec.Source -like '*-sm4.hlsl'
    $isRetro = $defines -match '(^|,)\s*(OG_RETRO_MODE|RETRO_UNLIT_MODE)\b'
    $isVertexLit = $defines -match '(^|,)\s*VERTEX_LIGHTING\b'
    $isEnhanced = $defines -match '(^|,)\s*ENHANCED_MODE\b'

    if (-not $isSm4) {
        if ($hasLinear) {
            $programFailures += "$where is not a DX11 SM4 program (source '$($rec.Source)') but defines CR_LINEAR_LIGHT. Stage A must not leak into DX9/GLSL/GLSLES/unified declarations."
        }
        continue
    }

    if ($rec.Kind -eq 'vertex_program') {
        if ($hasLinear) {
            $programFailures += "$where is a vertex program but defines CR_LINEAR_LIGHT. Stage A is scoped to the per-pixel path."
        }
        continue
    }

    if ($isRetro) {
        if ($hasLinear) {
            $programFailures += "$where is a DX11 Retro program but defines CR_LINEAR_LIGHT. Retro must remain on the legacy path."
        }
        $legacySm4Count++
        continue
    }

    if ($isEnhanced -and -not $isVertexLit) {
        if (-not $hasLinearOne) {
            $programFailures += "$where is a DX11 Enhanced SM4 fragment program but does not define CR_LINEAR_LIGHT=1. Enhanced must opt into Stage A."
        }
        $enhancedSm4Count++
        continue
    }

    if ($hasLinear) {
        $programFailures += "$where is a DX11 Default/stock-compatible SM4 program but defines CR_LINEAR_LIGHT. Default must remain on the legacy path."
    }
    $legacySm4Count++
}

if ($enhancedSm4Count -eq 0) {
    $programFailures += 'No DX11 Enhanced SM4 fragment programs were discovered. The classifier no longer matches the .program structure.'
}

if ($programFailures.Count -gt 0) {
    $detail = ($programFailures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "DX11 Enhanced program-definition boundary failed:$([Environment]::NewLine)$detail"
}

Write-Host "DX11 Enhanced program boundary passed ($enhancedSm4Count Enhanced SM4 fragment programs opted into Stage A, $legacySm4Count Default/Retro SM4 fragment programs held on the legacy path, $($programRecords.Count) program declarations scanned)."

# =============================================================================
# Shader compile / preprocess matrix
# =============================================================================

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

# -----------------------------------------------------------------------------
# CR_LINEAR_LIGHT sweep
# -----------------------------------------------------------------------------
# Every base/terrain case above is compiled twice: once with CR_LINEAR_LIGHT=0
# (which must remain the untouched baseline) and once with CR_LINEAR_LIGHT=1.
# Variants that differ only in vertex/tangent plumbing are mathematically
# unaffected by Stage A, so the sweep is restricted to the pixel entry points
# plus the retro/vertex-lighting representatives that prove non-activation.
$sweepCases = @()
foreach ($case in $cases) {
    if ($case.File -ne $baseShader -and $case.File -ne $terrainShader) { continue }
    if ($case.Target -ne 'ps_4_0') { continue }

    foreach ($linearLight in @(0, 1)) {
        $sweep = @{
            Name = "$($case.Name)-ll$linearLight"
            File = $case.File
            Entry = $case.Entry
            Target = $case.Target
            Defines = @($case.Defines) + @("CR_LINEAR_LIGHT=$linearLight")
            LinearLight = $linearLight
        }
        $sweepCases += $sweep
    }
}

$failed = @()

foreach ($case in $cases) {
    $output = Join-Path $tempRoot "$($case.Name).cso"
    $fxcArgs = @('/nologo', '/Ges', '/WX', '/T', $case.Target, '/E', $case.Entry, '/Fo', $output)

    foreach ($define in $case.Defines) {
        $fxcArgs += @('/D', $define)
    }

    $fxcArgs += $case.File

    Write-Host "Compiling $($case.Name)..."
    & $FxcPath @fxcArgs

    if ($LASTEXITCODE -ne 0) {
        $failed += $case.Name
    }
}

# -----------------------------------------------------------------------------
# Preprocessor-level Stage A assertions across the sweep
# -----------------------------------------------------------------------------
# Compiling proves the permutations are valid HLSL. Preprocessing proves the
# transfer functions appear in exactly the permutations they are supposed to,
# exactly the number of times they are supposed to, in the right order.
$preprocessFailures = @()

foreach ($case in $sweepCases) {
    $output = Join-Path $tempRoot "$($case.Name).cso"
    $fxcArgs = @('/nologo', '/Ges', '/WX', '/T', $case.Target, '/E', $case.Entry, '/Fo', $output)
    foreach ($define in $case.Defines) {
        $fxcArgs += @('/D', $define)
    }
    $fxcArgs += $case.File

    Write-Host "Compiling $($case.Name)..."
    & $FxcPath @fxcArgs
    if ($LASTEXITCODE -ne 0) {
        $failed += $case.Name
        continue
    }

    $preprocessed = Join-Path $tempRoot "$($case.Name).i"
    $ppArgs = @('/nologo', '/P', $preprocessed)
    foreach ($define in $case.Defines) {
        $ppArgs += @('/D', $define)
    }
    $ppArgs += $case.File

    & $FxcPath @ppArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $preprocessed)) {
        $preprocessFailures += "$($case.Name): fxc /P preprocessing failed."
        continue
    }

    $text = Get-Content -LiteralPath $preprocessed -Raw

    $isEnhanced = $case.Defines -match '^ENHANCED_MODE'
    $isVertexLit = $case.Defines -match '^VERTEX_LIGHTING'
    $isRetro = ($case.Defines -match '^OG_RETRO_MODE') -or ($case.Defines -match '^RETRO_UNLIT_MODE')
    $hasEmissive = $case.Defines -match '^EMISSIVEMAP_ENABLED'

    $shouldActivate = ($case.LinearLight -eq 1) -and $isEnhanced -and (-not $isVertexLit) -and (-not $isRetro)

    # 1 definition + 1 call for the encode; 1 definition + diffuse (+ emissive)
    # for the decode. Terrain adds one more: the per-vertex COLOR0 tint, which
    # multiplies the decoded albedo and is therefore authored display colour.
    # The base shader has no vertex COLOR input, so it never gains this call.
    $isTerrainSource = (Split-Path -Leaf $case.File) -eq 'CR_terrain-sm4.hlsl'

    $expectedEncode = if ($shouldActivate) { 2 } else { 0 }
    $expectedDecode = 0
    if ($shouldActivate) {
        $expectedDecode = if ($hasEmissive) { 3 } else { 2 }
        if ($isTerrainSource) { $expectedDecode += 1 }
    }

    $encodeCount = [regex]::Matches($text, '\blinear_to_srgb\s*\(').Count
    $decodeCount = [regex]::Matches($text, '\bsrgb_to_linear\s*\(').Count

    if ($encodeCount -ne $expectedEncode) {
        $preprocessFailures += "$($case.Name): expected $expectedEncode linear_to_srgb occurrences after preprocessing, found $encodeCount."
    }
    if ($decodeCount -ne $expectedDecode) {
        $preprocessFailures += "$($case.Name): expected $expectedDecode srgb_to_linear occurrences after preprocessing, found $decodeCount."
    }

    if ($shouldActivate) {
        # fxc /P re-emits the token stream with spaces between tokens
        # ("oColor . rgb"), so these positional checks must be whitespace
        # insensitive rather than literal substring searches.
        $encodeMatches = [regex]::Matches($text, 'linear_to_srgb\s*\(\s*oColor\s*\.\s*rgb\s*\)')
        $atmosphereMatches = [regex]::Matches($text, 'compute_enhanced_atmosphere\s*\(')

        if ($encodeMatches.Count -ne 1) {
            $preprocessFailures += "$($case.Name): expected exactly one 'oColor.rgb = linear_to_srgb(oColor.rgb)' call after preprocessing, found $($encodeMatches.Count)."
        }
        elseif ($atmosphereMatches.Count -gt 0) {
            $encodeCall = $encodeMatches[0].Index
            $atmosphereCall = $atmosphereMatches[$atmosphereMatches.Count - 1].Index
            if ($encodeCall -lt $atmosphereCall) {
                $preprocessFailures += "$($case.Name): the final encode precedes atmosphere integration."
            }
        }
    }
    elseif ($case.LinearLight -eq 0 -and ($encodeCount -ne 0 -or $decodeCount -ne 0)) {
        $preprocessFailures += "$($case.Name): CR_LINEAR_LIGHT=0 must preprocess to the untouched baseline."
    }
}

if ($failed.Count -gt 0) {
    throw "DX11 shader validation failed: $($failed -join ', ')"
}

if ($preprocessFailures.Count -gt 0) {
    $detail = ($preprocessFailures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "DX11 color-space Stage A preprocessor guards failed:$([Environment]::NewLine)$detail"
}

Write-Host "Stage A preprocessor guards passed across $($sweepCases.Count) CR_LINEAR_LIGHT permutations."
Write-Host "All $($cases.Count + $sweepCases.Count) DX11 SM4 shader compilations succeeded."
