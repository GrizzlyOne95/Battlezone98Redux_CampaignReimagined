[CmdletBinding()]
param(
    [string]$FxcPath,

    # Run only the source-level and .program-level guards and skip the fxc
    # compile/preprocess matrix. The guards are what the mutation fixtures in
    # Test-DX11ShaderValidator.ps1 exercise, and running 88 compilations per
    # fixture would make that suite unusable.
    [switch]$SourceGuardsOnly
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

# Identifiers that must never be fed directly to srgb_to_linear(). These are
# data/hybrid sources or raw engine constants. Fog is first copied into the
# explicitly classified authoredFog colour target below.
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

# The intentional Stage A decode allow-list, split by scope.
#
# Universal targets exist in every Stage A shader and are required in all of
# them.
$universalDecodeTargets = @('diffuseTex.rgb', 'emissiveTex', 'authoredFog')

# Family-scoped targets exist in exactly one shader family. Each is required in
# its owning shader and rejected in every other Stage A shader. The allow-list
# is therefore evaluated per file rather than globally: a family-scoped target
# is never "generally allowed and separately policed", it is simply not on the
# allow-list of any shader that does not own it. That keeps one rule - this
# table - authoritative for both halves of the constraint, so deleting it
# cannot leave a target silently permitted everywhere.
#
# 'vertexTint' is the terrain per-vertex COLOR0 tint. It is decodable because it
# multiplies the decoded albedo directly (lightResult * vertexTint *
# diffuseTex), so it is authored display colour by construction: leaving it
# encoded would multiply a linear albedo by a gamma-space tint. BZCC applies the
# same decode to every vertex-colour layout it ships, terrain included -
# pow(COLOR.rgb, 2.2) in its vertex stage, alpha untouched - which is what
# distinguishes this from vertex colour used as layer weights or another
# numerical channel. Only the rgb float3 is ever decoded; vColor.a stays raw
# because it is the terrain output alpha. The base shader has no vertex COLOR
# input at all, so a 'vertexTint' decode appearing there is by definition a
# copy-paste of terrain code into the wrong family.
$familyScopedDecodeOwners = @{ 'vertexTint' = 'CR_terrain-sm4.hlsl' }

# Any swizzle or member access that includes an alpha/w component.
$alphaComponentPattern = '\.[rgbaxyzw]*[awAW][rgbaxyzw]*\b'

# Each family-scoped owner must actually be one of the Stage A shaders,
# otherwise a typo would make its target mandatory nowhere and permitted
# nowhere - a rule that silently checks nothing while appearing to.
$stageAShaderNames = @($stageAShaders | ForEach-Object { Split-Path -Leaf $_ })
foreach ($scoped in $familyScopedDecodeOwners.Keys) {
    $owner = $familyScopedDecodeOwners[$scoped]
    if ($stageAShaderNames -notcontains $owner) {
        Add-SourceFailure "The family-scope rule assigns '$scoped' to '$owner', which is not one of the Stage A shaders ($($stageAShaderNames -join ', '))."
    }
}

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

    # -- Radial fog: same default, same activation scope ---------------------
    # Enhanced-only compile-time features are held to one standard: default off
    # in the shader, and activation gated on exactly the Enhanced per-pixel
    # condition. Anything else and the .program files become the only thing
    # keeping the feature off the legacy renderer.
    if ($source -notmatch '(?m)^\s*#ifndef\s+CR_RADIAL_FOG\s*\r?\n\s*#define\s+CR_RADIAL_FOG\s+0\s*\r?\n\s*#endif') {
        Add-SourceFailure "$name does not declare CR_RADIAL_FOG with a default of 0."
    }

    $fogActivationIndex = $source.IndexOf('#define CR_RADIAL_FOG_ACTIVE 1')
    $fogConditionStart = if ($fogActivationIndex -ge 0) {
        $source.Substring(0, $fogActivationIndex).LastIndexOf('#if')
    } else { -1 }

    if ($fogActivationIndex -lt 0 -or $fogConditionStart -lt 0) {
        Add-SourceFailure "$name does not gate CR_RADIAL_FOG_ACTIVE behind a preceding #if condition."
    }
    else {
        $rawFogCondition = $source.Substring($fogConditionStart, $fogActivationIndex - $fogConditionStart)
        $fogCondition = (($rawFogCondition -replace '\\\r?\n', ' ') -replace '\s+', ' ').Trim()

        if ($rawFogCondition -replace '\\\r?\n', ' ' -match '\r?\n\s*\S') {
            Add-SourceFailure "$name has unexpected content between the #if condition and '#define CR_RADIAL_FOG_ACTIVE 1'."
        }

        $fogRequiredTerms = @(
            'defined(ENHANCED_MODE)',
            '!defined(VERTEX_LIGHTING)',
            '!defined(OG_RETRO_MODE)',
            '!defined(RETRO_UNLIT_MODE)',
            'CR_RADIAL_FOG != 0'
        )
        foreach ($term in $fogRequiredTerms) {
            if ($fogCondition -notlike "*$term*") {
                Add-SourceFailure "$name CR_RADIAL_FOG_ACTIVE condition is missing '$term'. Radial fog must not reach Default/Retro/vertex-lighting paths."
            }
        }
    }

    if ($source -notmatch '(?m)^\s*#define\s+CR_RADIAL_FOG_ACTIVE\s+0\s*$') {
        Add-SourceFailure "$name does not define CR_RADIAL_FOG_ACTIVE to 0 for every non-Enhanced permutation."
    }

    # The legacy depth-based fog must survive untouched. It is the only fog the
    # Default, Retro and vertex-lighting delegates ever run, and it is
    # deliberately NOT radial - it consumes clip-space vDepth.
    if ($source -notmatch 'fogValue\s*=\s*saturate\(\(vDepth\s*-\s*fogParams\.y\)\s*\*\s*fogParams\.w\);') {
        Add-SourceFailure "$name no longer contains the legacy depth-based fog 'saturate((vDepth - fogParams.y) * fogParams.w)'. Default/Retro fog must not become radial."
    }

    # The radial factor must be fed the view-space distance, never vDepth.
    # Passing clip-space depth here would compile and look almost right while
    # silently reintroducing the planar fog shell this replaces.
    # The lookbehind skips the function's own definition, whose first parameter
    # is 'float viewDistance' rather than an argument.
    $fogCallSites = [regex]::Matches($source, '(?<!float\s)compute_radial_fog_factor\s*\(\s*(?<arg>[^,]+),')
    foreach ($site in $fogCallSites) {
        $arg = $site.Groups['arg'].Value.Trim()
        if ($arg -ne 'viewDistance') {
            Add-SourceFailure "$name calls compute_radial_fog_factor() with '$arg'; expected 'viewDistance' (the length of the view-space position). Radial fog must never be driven by clip-space depth."
        }
    }

    if ($source -notmatch '(?m)^\s*#define\s+CR_LINEAR_LIGHT_ACTIVE\s+0\s*$') {
        Add-SourceFailure "$name does not define CR_LINEAR_LIGHT_ACTIVE to 0 for every non-Enhanced permutation."
    }

    # -- Environment-sensitive terrain diffuse IBL --------------------------
    # This correction belongs only to terrain diffuse irradiance. Copying it to
    # the base shader would alter objects/buildings, while applying it to the
    # shared IBL intensity would also alter specular response.
    if ($name -eq 'CR_terrain-sm4.hlsl') {
        if ($source -notmatch 'CR_TERRAIN_IBL_REFERENCE_FOG_RANGE\s*=\s*160\.0\s*;' -or
            $source -notmatch 'CR_TERRAIN_IBL_AIRLESS_FLOOR\s*=\s*0\.15\s*;') {
            Add-SourceFailure "$name is missing the qualified terrain diffuse-IBL atmosphere calibration (160.0 reference range / 0.15 airless floor)."
        }
        if ($source -notmatch 'atmosphereSupport\s*=\s*saturate\(abs\(fogParams\.w\)\s*\*\s*CR_TERRAIN_IBL_REFERENCE_FOG_RANGE\)\s*\*\s*validFogRange\s*;') {
            Add-SourceFailure "$name no longer derives terrain diffuse-IBL support continuously from the authored fog inverse range."
        }
        if ($source -notmatch 'irradiance\s*\*\s*diffuseEnergy\s*\*\s*CR_IBL_DIFFUSE_INTENSITY\s*\*\s*terrainDiffuseIblStrength') {
            Add-SourceFailure "$name no longer applies atmosphere support specifically to terrain diffuse irradiance."
        }
    }
    elseif ($source -match 'terrain_ibl_diffuse_strength|CR_TERRAIN_IBL_') {
        Add-SourceFailure "$name contains terrain-only diffuse-IBL atmosphere scaling. Base/object IBL must remain unchanged."
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
    # The effective allow-list for this file is the universal set plus only the
    # family-scoped targets this file owns. Everything the file does not own is
    # off its allow-list, and the rejection below names the family-scope rule as
    # the reason.
    $ownedScopedTargets = @(
        $familyScopedDecodeOwners.Keys | Where-Object { $familyScopedDecodeOwners[$_] -eq $name })
    $allowedDecodeTargets = @($universalDecodeTargets) + $ownedScopedTargets

    $decodeSites = [regex]::Matches(
        $source,
        '(?m)^\s*(?<target>[A-Za-z_][A-Za-z0-9_.]*)\s*=\s*srgb_to_linear\s*\(\s*(?<arg>[^;]*?)\s*\)\s*;')

    if ($decodeSites.Count -eq 0) {
        Add-SourceFailure "$name contains no srgb_to_linear() decode site. Stage A must decode diffuse and emissive COLOR."
    }

    # Every srgb_to_linear() use in the file must be one of the plain
    # 'target = srgb_to_linear(arg);' statements matched above, plus the single
    # definition. A decode written any other way - as an initializer
    # ('float3 x = srgb_to_linear(normalTex);'), nested inside a larger
    # expression, or as a call argument - would otherwise slip past the
    # allow-list, the data deny-list and the alpha check simultaneously, because
    # those checks only ever see what the statement regex matched.
    $decodeDefinitions = [regex]::Matches($source, '(?m)^\s*float3\s+srgb_to_linear\s*\(').Count
    if ($decodeDefinitions -ne 1) {
        Add-SourceFailure "$name declares $decodeDefinitions srgb_to_linear() definitions; expected exactly 1."
    }
    $decodeCallCount = [regex]::Matches($source, '\bsrgb_to_linear\s*\(').Count
    $accountedDecodes = $decodeSites.Count + $decodeDefinitions
    if ($decodeCallCount -ne $accountedDecodes) {
        Add-SourceFailure "$name has $decodeCallCount srgb_to_linear() occurrences but only $accountedDecodes are accounted for ($($decodeSites.Count) plain decode statements + $decodeDefinitions definition). A decode written as an initializer or nested in an expression bypasses the Stage A allow-list."
    }

    $observedTargets = @()
    foreach ($site in $decodeSites) {
        $target = $site.Groups['target'].Value
        $arg = $site.Groups['arg'].Value
        $observedTargets += $target

        if ($allowedDecodeTargets -notcontains $target) {
            if ($familyScopedDecodeOwners.ContainsKey($target)) {
                Add-SourceFailure "$name decodes '$target', which the family-scope rule reserves to $($familyScopedDecodeOwners[$target]). Stage A targets that exist in only one shader family must not be copied into another."
            }
            else {
                Add-SourceFailure "$name decodes '$target', which is not on the Stage A COLOR allow-list ($($allowedDecodeTargets -join ', '))."
            }
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

    # Everything on this file's effective allow-list is also mandatory for it:
    # the universal COLOR sources in every Stage A shader, plus the family-scoped
    # targets this file owns. The base shader is therefore not failed for lacking
    # a terrain-only input, and terrain cannot quietly drop one.
    foreach ($required in $allowedDecodeTargets) {
        if ($observedTargets -notcontains $required) {
            Add-SourceFailure "$name is missing the required Stage A decode of '$required'."
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

        # -- Terrain normals preserve their two distinct encodings -----------
        # The mesh normal is packed as signed X/Z in BLENDINDICES.zw and must
        # guard the reconstructed vertical component against quantization that
        # puts XY just outside the unit circle. This is separate from the t2
        # normal map: BZR's terrain atlas is full RGB DXT1/BC1, not BC5/DXT5nm,
        # so the sampled B channel is authored Z and must not be reconstructed.
        $packedNormalSites = [regex]::Matches(
            $source,
            'float3\s+iNormal\s*=\s*float3\(\s*nNormal\.x\s*,\s*sqrt\(\s*saturate\(\s*1\.0\s*-\s*dot\(\s*nNormal\s*,\s*nNormal\s*\)\s*\)\s*\)\s*,\s*nNormal\.y\s*\)\s*;')
        if ($packedNormalSites.Count -ne 1) {
            Add-SourceFailure "$name must reconstruct the packed mesh terrain normal with exactly one guarded 'sqrt(saturate(1.0 - dot(nNormal, nNormal)))' site."
        }

        # The sampled map must remain RGB-only numerical data at authored
        # strength, followed directly by the existing safe post-TBN normalize.
        # The production defaults must remain stock RGB/no-flip/no-overlay.
        # Alternate packing and visualization modes are compile-time diagnostics
        # selected explicitly for a test run, never silent production changes.
        foreach ($diagnosticDefault in @(
            @{ Name = 'CR_TERRAIN_NORMAL_UNPACK_MODE'; Value = '0' },
            @{ Name = 'CR_TERRAIN_NORMAL_FLIP_GREEN'; Value = '0' },
            @{ Name = 'CR_TERRAIN_NORMAL_BASIS_MODE'; Value = '0' },
            @{ Name = 'CR_TERRAIN_NORMAL_DEBUG_MODE'; Value = '0' }
        )) {
            $defaultPattern = '(?m)^\s*#define\s+' + [regex]::Escape($diagnosticDefault.Name) +
                '\s+' + [regex]::Escape($diagnosticDefault.Value) + '\s*$'
            if ($source -notmatch $defaultPattern) {
                Add-SourceFailure "$name must default $($diagnosticDefault.Name) to $($diagnosticDefault.Value); terrain-normal diagnostics must be opt-in."
            }
        }

        # Require all three explicitly named unpack contracts. This makes RG,
        # AG/DXT5nm and green-flip A/B runs reproducible while preserving the
        # full-RGB stock path as mode 0.
        $requiredNormalDiagnosticTokens = @(
            '#if CR_TERRAIN_NORMAL_UNPACK_MODE == 1',
            'packedNormal.rg * 2.0 - 1.0',
            '#elif CR_TERRAIN_NORMAL_UNPACK_MODE == 2',
            'packedNormal.ag * 2.0 - 1.0',
            'sqrt(saturate(1.0 - dot(xy, xy)))',
            'packedNormal.rgb * 2.0 - 1.0',
            '#if CR_TERRAIN_NORMAL_FLIP_GREEN != 0',
            'normal.y = -normal.y;',
            '#if CR_TERRAIN_NORMAL_BASIS_MODE == 1',
            '#elif CR_TERRAIN_NORMAL_BASIS_MODE == 2',
            'T -= N * dot(T, N);',
            'float handedness = (dot(orthogonalB, sourceB) < 0.0) ? -1.0 : 1.0;',
            '#if CR_TERRAIN_NORMAL_BASIS_MODE == 3',
            '#elif CR_TERRAIN_NORMAL_BASIS_MODE == 4',
            'float3 viewNormal = geometryNormal;',
            'float3 viewNormal = safe_normalize(normalTex);'
        )
        foreach ($token in $requiredNormalDiagnosticTokens) {
            if (-not $source.Contains($token)) {
                Add-SourceFailure "$name terrain-normal diagnostic contract is missing '$token'."
            }
        }

        foreach ($debugToken in @(
            'terrainNormalDebug = normalSample.rgb;',
            'terrainNormalDebug = normalSample.aaa;',
            'terrainNormalDebug = saturate(normalTex * 0.5 + 0.5);',
            'terrainNormalDebug = saturate(viewNormal * 0.5 + 0.5);',
            'saturate(dot(viewNormal, debugPixelToLight))',
            'terrainNormalDebug = saturate(geometryNormal * 0.5 + 0.5);',
            'terrainNormalDebug = saturate(safe_normalize(tbn[0]) * 0.5 + 0.5);',
            'terrainNormalDebug = saturate(safe_normalize(tbn[1]) * 0.5 + 0.5);',
            'dot(debugTangent, debugBasisNormal)',
            'dot(debugBitangent, debugBasisNormal)',
            'dot(debugTangent, debugBitangent)',
            'float debugDeterminant = abs(dot(cross(debugTangent, debugBitangent), debugBasisNormal));',
            'float normalDeviation = 1.0 - saturate(dot(mappedViewNormal, geometryNormal));'
        )) {
            if (-not $source.Contains($debugToken)) {
                Add-SourceFailure "$name terrain-normal visualization contract is missing '$debugToken'."
            }
        }

        $normalSample = [regex]::Match(
            $source,
            'float4\s+normalSample\s*=\s*normalMap\.Sample\(\s*normalSam\s*,\s*vTexCoord\s*\)\s*;')
        $normalUnpackPattern = [regex]::new(
            'float3\s+normalTex\s*=\s*unpack_terrain_normal\(\s*normalSample\s*\)\s*;')
        $normalUnpack = $normalUnpackPattern.Match(
            $source,
            $(if ($normalSample.Success) { $normalSample.Index + $normalSample.Length } else { 0 }))
        $normalTransformPattern = [regex]::new(
            'float3\s+mappedViewNormal\s*=\s*safe_normalize\(\s*mul\(\s*normalTex\s*,\s*tbn\s*\)\s*\)\s*;')
        $normalTransform = $normalTransformPattern.Match(
            $source,
            $(if ($normalUnpack.Success) { $normalUnpack.Index + $normalUnpack.Length } else { 0 }))

        if (-not $normalSample.Success) {
            Add-SourceFailure "$name must capture the complete terrain normal sample as float4 so RGB, RG, AG and alpha diagnostics all observe the same fetch."
        }
        elseif (-not $normalUnpack.Success) {
            Add-SourceFailure "$name must pass normalSample through unpack_terrain_normal before the TBN transform."
        }
        elseif (-not $normalTransform.Success) {
            Add-SourceFailure "$name must safe-normalize mappedViewNormal immediately after the terrain TBN transform."
        }
        else {
            $unpackEnd = $normalUnpack.Index + $normalUnpack.Length
            $between = $source.Substring($unpackEnd, $normalTransform.Index - $unpackEnd)
            if ($between -match '\bnormalTex\b') {
                Add-SourceFailure "$name modifies the unpacked terrain normal outside the named unpack diagnostic before the TBN transform."
            }
        }

        # -- The terrain vertex tint is decoded at its source ----------------
        # Same ordering standard the sampled textures are held to: prove the
        # tint is derived from the vertex COLOR0 rgb, prove nothing reads it
        # between that derivation and the decode, and prove the alpha channel
        # is not swept in with it. Interpolated vertex colour has no Sample()
        # call to anchor to, so the anchor is the declaration instead.
        $tintDecl = [regex]::Match($source, '(?m)^\s*float3\s+vertexTint\s*=\s*(?<src>[^;]+);')
        $tintDecodeIndex = $source.IndexOf('vertexTint = srgb_to_linear(')

        if (-not $tintDecl.Success) {
            Add-SourceFailure "$name has no 'float3 vertexTint = ...;' declaration; the terrain tint ordering guard cannot be evaluated."
        }
        elseif ($tintDecl.Groups['src'].Value.Trim() -ne 'vColor.xyz') {
            Add-SourceFailure "$name derives vertexTint from '$($tintDecl.Groups['src'].Value.Trim())'; expected 'vColor.xyz'. Only the vertex COLOR0 rgb is authored display colour - the alpha channel is the terrain output alpha."
        }
        elseif ($tintDecodeIndex -lt 0) {
            Add-SourceFailure "$name never decodes 'vertexTint'."
        }
        else {
            $declEnd = $tintDecl.Index + $tintDecl.Length
            if ($tintDecodeIndex -lt $declEnd) {
                Add-SourceFailure "$name decodes 'vertexTint' before it is declared."
            }
            else {
                $between = $source.Substring($declEnd, $tintDecodeIndex - $declEnd)
                if ($between -match '\bvertexTint\b') {
                    Add-SourceFailure "$name reads 'vertexTint' between its declaration and the sRGB decode. The decode must happen at the source, before any consumption."
                }
            }
        }
    }
}

# -- Shared helpers are genuinely shared ---------------------------------------
# These two shaders have no #include - nothing in the Shaders tree does, and
# introducing one would make the mod depend on Ogre's HLSL include resolution at
# runtime. The established convention is instead that the shared region is
# duplicated verbatim and kept in sync by hand.
#
# "By hand" is exactly what rots, so assert it. A helper that is supposed to be
# one implementation must be byte-identical in both files; if someone tunes the
# fog curve in one shader only, terrain and objects would fog differently and
# the seam would be visible along every building base.
$sharedHelperBlocks = @(
    @{ Name = 'compute_radial_fog_factor'; Start = 'float compute_radial_fog_factor('; End = 'float compute_height_density(' },
    @{ Name = 'srgb_to_linear / linear_to_srgb'; Start = 'float3 srgb_to_linear('; End = 'float3 linear_to_srgb(' }
)

foreach ($block in $sharedHelperBlocks) {
    $extracted = @{}
    foreach ($shader in $stageAShaders) {
        $name = Split-Path -Leaf $shader
        $text = Get-Content -LiteralPath $shader -Raw
        $startIndex = $text.IndexOf($block.Start)
        $endIndex = if ($startIndex -ge 0) { $text.IndexOf($block.End, $startIndex) } else { -1 }
        if ($startIndex -lt 0 -or $endIndex -lt 0) {
            Add-SourceFailure "$name does not contain the shared helper block '$($block.Name)'; the shared-helper identity guard cannot be evaluated."
            continue
        }
        # Compare on normalized line endings so a CRLF/LF difference between the
        # two files is not reported as a behavioural divergence.
        $extracted[$name] = ($text.Substring($startIndex, $endIndex - $startIndex) -replace '\r\n', "`n")
    }

    if ($extracted.Count -eq $stageAShaders.Count) {
        $distinct = @($extracted.Values | Sort-Object -Unique)
        if ($distinct.Count -ne 1) {
            $names = ($extracted.Keys | Sort-Object) -join ' and '
            Add-SourceFailure "The shared helper '$($block.Name)' differs between $names. It is duplicated verbatim precisely because these shaders cannot #include; the two copies must stay byte-identical."
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
    if ($otherSource -match '\b(compute_radial_fog_factor|CR_RADIAL_FOG)\b') {
        Add-SourceFailure "$($other.Name) references radial-fog symbols. Radial fog is confined to the two DX11 Enhanced world shaders; the DX9/GL, UI, sky and overlay paths keep their existing fog."
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

# Every Enhanced-only compile-time flag obeys the same boundary, so they are
# policed by one loop rather than by copies that can drift apart. Adding a
# future Enhanced-only experiment means adding one entry here.
$enhancedOnlyFlags = @(
    @{ Name = 'CR_LINEAR_LIGHT'; Feature = 'Stage A' },
    @{ Name = 'CR_RADIAL_FOG'; Feature = 'radial fog' }
)

foreach ($rec in $programRecords) {
    $defines = $rec.Defines
    $where = "$($rec.File):$($rec.Line) $($rec.Name)"

    $isSm4 = $rec.Source -like '*-sm4.hlsl'
    $isRetro = $defines -match '(^|,)\s*(OG_RETRO_MODE|RETRO_UNLIT_MODE)\b'
    $isVertexLit = $defines -match '(^|,)\s*VERTEX_LIGHTING\b'
    $isEnhanced = $defines -match '(^|,)\s*ENHANCED_MODE\b'
    $isEnhancedFragment = $isSm4 -and $rec.Kind -ne 'vertex_program' -and
                          $isEnhanced -and -not $isVertexLit -and -not $isRetro

    foreach ($flag in $enhancedOnlyFlags) {
        $name = $flag.Name
        $feature = $flag.Feature
        $hasFlag = $defines -match "(^|,)\s*$name\s*="
        $hasFlagOne = $defines -match "(^|,)\s*$name\s*=\s*1\s*(,|`$)"

        if ($hasFlag -and -not $hasFlagOne) {
            $programFailures += "$where declares $name with a value other than 1. $feature is on/off only."
        }

        if (-not $isSm4) {
            if ($hasFlag) {
                $programFailures += "$where is not a DX11 SM4 program (source '$($rec.Source)') but defines $name. $feature must not leak into DX9/GLSL/GLSLES/unified declarations."
            }
            continue
        }
        if ($rec.Kind -eq 'vertex_program') {
            if ($hasFlag) {
                $programFailures += "$where is a vertex program but defines $name. $feature is scoped to the per-pixel path."
            }
            continue
        }
        if ($isRetro) {
            if ($hasFlag) {
                $programFailures += "$where is a DX11 Retro program but defines $name. Retro must remain on the legacy path."
            }
            continue
        }
        if ($isEnhancedFragment) {
            if (-not $hasFlagOne) {
                $programFailures += "$where is a DX11 Enhanced SM4 fragment program but does not define $name=1. Enhanced must opt into $feature."
            }
            continue
        }
        if ($hasFlag) {
            $programFailures += "$where is a DX11 Default/stock-compatible SM4 program but defines $name. Default must remain on the legacy path."
        }
    }

    if (-not $isSm4 -or $rec.Kind -eq 'vertex_program') { continue }
    if ($isEnhancedFragment) { $enhancedSm4Count++ } else { $legacySm4Count++ }
}

if ($enhancedSm4Count -eq 0) {
    $programFailures += 'No DX11 Enhanced SM4 fragment programs were discovered. The classifier no longer matches the .program structure.'
}

if ($programFailures.Count -gt 0) {
    $detail = ($programFailures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "DX11 Enhanced program-definition boundary failed:$([Environment]::NewLine)$detail"
}

Write-Host "DX11 Enhanced program boundary passed ($enhancedSm4Count Enhanced SM4 fragment programs opted into $($enhancedOnlyFlags.Count) Enhanced-only flags, $legacySm4Count Default/Retro SM4 fragment programs held on the legacy path, $($programRecords.Count) program declarations scanned)."

if ($SourceGuardsOnly) {
    Write-Host 'Source-guard-only run requested; skipping the fxc compile/preprocess matrix.'
    return
}

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
# CR_LINEAR_LIGHT x CR_RADIAL_FOG sweep
# -----------------------------------------------------------------------------
# Every base/terrain pixel case above is compiled across the full cross product
# of the two Enhanced-only flags. The cross product matters rather than one
# flag at a time: both features rewrite the same fragment tail, and the encode
# has to remain a single call sited after atmosphere no matter which
# combination of the two is enabled.
#
# Variants that differ only in vertex/tangent plumbing are mathematically
# unaffected by either flag, so the sweep is restricted to the pixel entry
# points plus the retro/vertex-lighting representatives that prove
# non-activation.
$sweepCases = @()
foreach ($case in $cases) {
    if ($case.File -ne $baseShader -and $case.File -ne $terrainShader) { continue }
    if ($case.Target -ne 'ps_4_0') { continue }

    foreach ($linearLight in @(0, 1)) {
    foreach ($radialFog in @(0, 1)) {
        $sweep = @{
            Name = "$($case.Name)-ll$linearLight-rf$radialFog"
            File = $case.File
            Entry = $case.Entry
            Target = $case.Target
            Defines = @($case.Defines) + @("CR_LINEAR_LIGHT=$linearLight", "CR_RADIAL_FOG=$radialFog")
            LinearLight = $linearLight
            RadialFog = $radialFog
        }
        $sweepCases += $sweep
    }
    }
}

# -----------------------------------------------------------------------------
# Terrain-normal diagnostic sweep
# -----------------------------------------------------------------------------
# Compile every RGB/RG/AG x green orientation x original visualization
# combination, plus focused basis-mode and basis-visualization coverage, on the
# maximal Enhanced terrain permutation. These modes are runtime diagnosis tools,
# so a typo in an alternate branch must fail CI even though production defaults
# remain RGB/no-flip/stock-basis/debug-off.
$normalDiagnosticCases = @()
$normalDiagnosticBaseDefines = @(
    'MAX_LIGHTS=24', 'DETAILMAP_ENABLED=1', 'NORMALMAP_ENABLED=1',
    'SPECULARMAP_ENABLED=1', 'EMISSIVEMAP_ENABLED=1', 'ENHANCED_MODE=1',
    'IBL_ENABLED=1', 'SHADOWRECEIVER=1', 'PSSM_ENABLED=1', 'PCF_SIZE=4',
    'CR_LINEAR_LIGHT=1', 'CR_RADIAL_FOG=1'
)
foreach ($unpackMode in @(0, 1, 2)) {
foreach ($flipGreen in @(0, 1)) {
foreach ($debugMode in @(0, 1, 2, 3, 4, 5)) {
    $normalDiagnosticCases += @{
        Name = "terrain-normal-diag-u$unpackMode-g$flipGreen-d$debugMode"
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = $normalDiagnosticBaseDefines + @(
            "CR_TERRAIN_NORMAL_UNPACK_MODE=$unpackMode",
            "CR_TERRAIN_NORMAL_FLIP_GREEN=$flipGreen",
            'CR_TERRAIN_NORMAL_BASIS_MODE=0',
            "CR_TERRAIN_NORMAL_DEBUG_MODE=$debugMode"
        )
    }
}
}
}

# Exercise each basis behavior through normal rendering, final-normal display,
# and NdotL. GeometryOnly and TangentAsView are isolation controls; modes 1/2
# are candidate derivative-basis corrections that remain diagnostic by default.
foreach ($basisMode in @(1, 2, 3, 4)) {
foreach ($debugMode in @(0, 4, 5)) {
    $normalDiagnosticCases += @{
        Name = "terrain-normal-basis-b$basisMode-d$debugMode"
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = $normalDiagnosticBaseDefines + @(
            'CR_TERRAIN_NORMAL_UNPACK_MODE=0',
            'CR_TERRAIN_NORMAL_FLIP_GREEN=0',
            "CR_TERRAIN_NORMAL_BASIS_MODE=$basisMode",
            "CR_TERRAIN_NORMAL_DEBUG_MODE=$debugMode"
        )
    }
}
}

# Basis-axis/quality views need to compile against stock, per-axis-normalized,
# and orthonormalized derivative frames. The bypass modes still construct the
# same TBN, so repeating all six visualizations there adds no coverage.
foreach ($basisMode in @(0, 1, 2)) {
foreach ($debugMode in @(6, 7, 8, 9, 10, 11)) {
    $normalDiagnosticCases += @{
        Name = "terrain-normal-basis-view-b$basisMode-d$debugMode"
        File = $terrainShader
        Entry = 'terrain_fragment'
        Target = 'ps_4_0'
        Defines = $normalDiagnosticBaseDefines + @(
            'CR_TERRAIN_NORMAL_UNPACK_MODE=0',
            'CR_TERRAIN_NORMAL_FLIP_GREEN=0',
            "CR_TERRAIN_NORMAL_BASIS_MODE=$basisMode",
            "CR_TERRAIN_NORMAL_DEBUG_MODE=$debugMode"
        )
    }
}
}

$failed = @()

foreach ($case in @($cases) + @($normalDiagnosticCases)) {
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

    # 1 definition + 1 call for the encode; 1 definition + diffuse + authored
    # fog (+ emissive) for the decode. Terrain adds one more: the per-vertex
    # COLOR0 tint, which multiplies the decoded albedo and is therefore authored
    # display colour. The base shader has no vertex COLOR input, so it never
    # gains this call.
    $isTerrainSource = (Split-Path -Leaf $case.File) -eq 'CR_terrain-sm4.hlsl'

    $expectedEncode = if ($shouldActivate) { 2 } else { 0 }
    $expectedDecode = 0
    if ($shouldActivate) {
        $expectedDecode = if ($hasEmissive) { 4 } else { 3 }
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

    # -- Radial fog activates on exactly the same permutations ---------------
    $fogShouldActivate = ($case.RadialFog -eq 1) -and $isEnhanced -and (-not $isVertexLit) -and (-not $isRetro)

    # The whole atmosphere helper region sits inside '#if defined(ENHANCED_MODE)',
    # so for Default and Retro permutations neither fog model exists at all -
    # they run the legacy depth fog asserted below and nothing else.
    $atmosphereHelpersPresent = [bool]$isEnhanced

    $fogDefinitions = [regex]::Matches($text, 'float\s+compute_radial_fog_factor\s*\(').Count
    $fogCalls = [regex]::Matches($text, '\bcompute_radial_fog_factor\s*\(').Count - $fogDefinitions
    $opticalDepthCalls = [regex]::Matches($text, '\bcompute_distance_optical_depth\s*\(').Count

    if (-not $atmosphereHelpersPresent) {
        if ($fogDefinitions -ne 0 -or $fogCalls -ne 0 -or $opticalDepthCalls -ne 0) {
            $preprocessFailures += "$($case.Name): a non-Enhanced permutation must contain no atmosphere fog helpers at all (found $fogDefinitions radial definitions, $fogCalls radial calls, $opticalDepthCalls optical-depth occurrences)."
        }
    }
    else {
        if ($fogDefinitions -ne 1) {
            $preprocessFailures += "$($case.Name): expected exactly 1 compute_radial_fog_factor definition after preprocessing, found $fogDefinitions."
        }

        if ($fogShouldActivate) {
            if ($fogCalls -ne 1) {
                $preprocessFailures += "$($case.Name): expected exactly 1 compute_radial_fog_factor call, found $fogCalls."
            }
            # The exponential model must be compiled out, not merely bypassed:
            # only its own definition may remain, with no call site.
            if ($opticalDepthCalls -ne 1) {
                $preprocessFailures += "$($case.Name): radial fog is active but compute_distance_optical_depth still appears $opticalDepthCalls times (expected 1, the definition alone). The two fog models must not both run."
            }
        }
        else {
            if ($fogCalls -ne 0) {
                $preprocessFailures += "$($case.Name): radial fog must be inactive here but is called $fogCalls times."
            }
            # definition + the surviving call inside compute_enhanced_atmosphere
            if ($opticalDepthCalls -ne 2) {
                $preprocessFailures += "$($case.Name): radial fog is inactive, so the exponential optical-depth path must remain (expected 2 compute_distance_optical_depth occurrences, found $opticalDepthCalls)."
            }
        }
    }

    # The legacy depth-based fog belongs to every non-Enhanced permutation and
    # must never be replaced by the radial factor.
    $legacyFogSites = [regex]::Matches($text, 'saturate\s*\(\s*\(\s*vDepth\s*-\s*fogParams\s*\.\s*y\s*\)\s*\*\s*fogParams\s*\.\s*w\s*\)').Count
    if (-not $isEnhanced -or $isVertexLit -or $isRetro) {
        if ($legacyFogSites -ne 1) {
            $preprocessFailures += "$($case.Name): expected the legacy depth-based fog to survive in this non-Enhanced permutation, found $legacyFogSites occurrences."
        }
        if ($fogCalls -ne 0) {
            $preprocessFailures += "$($case.Name): a non-Enhanced permutation must never call compute_radial_fog_factor."
        }
    }
}

if ($failed.Count -gt 0) {
    throw "DX11 shader validation failed: $($failed -join ', ')"
}

if ($preprocessFailures.Count -gt 0) {
    $detail = ($preprocessFailures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "DX11 color-space Stage A preprocessor guards failed:$([Environment]::NewLine)$detail"
}

Write-Host "Stage A and radial-fog preprocessor guards passed across $($sweepCases.Count) CR_LINEAR_LIGHT x CR_RADIAL_FOG permutations."
Write-Host "Terrain-normal diagnostics compiled across $($normalDiagnosticCases.Count) unpack, orientation, basis, and visualization permutations."
Write-Host "All $($cases.Count + $normalDiagnosticCases.Count + $sweepCases.Count) DX11 SM4 shader compilations succeeded."
