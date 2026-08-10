<#
.SYNOPSIS
    Mutation fixtures for the Stage A / Enhanced-boundary guards.

.DESCRIPTION
    Validate-DX11Shaders.ps1 passing only proves the tree is currently clean.
    It does not prove the guards would notice if it stopped being clean - a
    guard with a typo'd pattern passes exactly as loudly as a working one.

    This suite copies the shader tree, introduces one specific regression at a
    time, and asserts that the validator rejects it *for the stated reason*.
    Matching on the message matters: a fixture that fails for an unrelated
    reason would otherwise count as a pass and leave the real guard untested.

    Each fixture also proves the mutation is reachable - the unmutated tree
    must pass first, so a fixture cannot silently become a no-op edit.

.EXAMPLE
    ./Tools/Test-DX11ShaderValidator.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $PSScriptRoot 'Validate-DX11Shaders.ps1'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) 'bzr-dx11-validator-fixtures'
if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
New-Item $tempRoot -ItemType Directory | Out-Null

# Run the validator against a throwaway copy of the tree. Only the directories
# the source guards read are copied.
function Invoke-ValidatorOnTree {
    param([string]$TreePath)

    $treeTools = Join-Path $TreePath 'Tools'
    New-Item $treeTools -ItemType Directory -Force | Out-Null
    Copy-Item $validator -Destination $treeTools -Force

    # The validator signals rejection by throwing, so it must be caught here
    # rather than allowed to terminate this suite.
    $output = @()
    $threw = $false
    try {
        $output = & (Join-Path $treeTools 'Validate-DX11Shaders.ps1') -SourceGuardsOnly 2>&1 |
            ForEach-Object { $_.ToString() }
    }
    catch {
        $threw = $true
        $output += $_.Exception.Message
    }

    return [pscustomobject]@{
        Passed = (-not $threw) -and -not ($output -match 'guards failed|boundary failed')
        Output = ($output -join [Environment]::NewLine)
    }
}

function New-TreeCopy {
    param([string]$Label)
    $dest = Join-Path $tempRoot $Label
    New-Item $dest -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $repoRoot 'Shaders') -Destination $dest -Recurse -Force
    $materials = Join-Path $repoRoot 'Materials'
    if (Test-Path $materials) {
        Copy-Item $materials -Destination $dest -Recurse -Force
    }
    return $dest
}

$results = @()
$failures = @()

function Add-Fixture {
    param(
        [string]$Name,
        [string]$ExpectedMessage,
        [scriptblock]$Mutate
    )

    $label = ($Name -replace '[^A-Za-z0-9]', '-')
    $tree = New-TreeCopy -Label $label
    $shaderDir = Join-Path $tree 'Shaders'

    $before = (Get-ChildItem $shaderDir -File | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash) -join ''
    & $Mutate $shaderDir
    $after = (Get-ChildItem $shaderDir -File | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash) -join ''

    if ($before -eq $after) {
        $script:failures += "$Name : the mutation changed nothing. The fixture is not testing anything."
        return
    }

    $run = Invoke-ValidatorOnTree -TreePath $tree

    if ($run.Passed) {
        $script:failures += "$Name : the validator ACCEPTED the mutated tree. The guard does not work."
        return
    }
    if ($run.Output -notmatch [regex]::Escape($ExpectedMessage)) {
        $script:failures += "$Name : rejected, but not for the expected reason. Expected text '$ExpectedMessage'. Got:$([Environment]::NewLine)$($run.Output)"
        return
    }

    $script:results += $Name
}

# -----------------------------------------------------------------------------
# The unmutated tree must pass, otherwise every fixture below is meaningless.
# -----------------------------------------------------------------------------
$cleanTree = New-TreeCopy -Label 'clean'
$cleanRun = Invoke-ValidatorOnTree -TreePath $cleanTree
if (-not $cleanRun.Passed) {
    throw "The unmutated tree does not pass the source guards; fixtures cannot be interpreted.$([Environment]::NewLine)$($cleanRun.Output)"
}
Write-Host 'Baseline: unmutated tree passes the source guards.'

# -----------------------------------------------------------------------------
# Family-scope rule
# -----------------------------------------------------------------------------

# The regression this exists to catch: terrain's vertex-tint decode gets pasted
# into the base shader, which has no vertex COLOR input at all. It must be
# rejected by the family-scope rule specifically, naming the owning shader -
# not by the generic allow-list message, and not merely by some later guard.
Add-Fixture -Name 'vertexTint decode copied into base shader' `
    -ExpectedMessage "decodes 'vertexTint', which the family-scope rule reserves to CR_terrain-sm4.hlsl" `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_base-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        $anchor = "    emissiveTex = srgb_to_linear(emissiveTex);"
        $inject = $anchor + "`r`n    vertexTint = srgb_to_linear(vertexTint);"
        [IO.File]::WriteAllText($path, $text.Replace($anchor, $inject))
    }

# The other half of the same rule: terrain must not quietly stop decoding it.
Add-Fixture -Name 'terrain drops its required vertexTint decode' `
    -ExpectedMessage "CR_terrain-sm4.hlsl is missing the required Stage A decode of 'vertexTint'" `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            "    vertexTint = srgb_to_linear(vertexTint);",
            "    vertexTint = vertexTint;"))
    }

# The tint must come from the vertex COLOR0 rgb only. Sweeping in .a would put
# the terrain output alpha through a display transfer function.
Add-Fixture -Name 'vertexTint derived from something other than vColor.xyz' `
    -ExpectedMessage 'expected ''vColor.xyz''' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            "    float3 vertexTint = vColor.xyz;",
            "    float3 vertexTint = vColor.xyz * diffuseTex.a;"))
    }

# -----------------------------------------------------------------------------
# Decode-site accounting
# -----------------------------------------------------------------------------

# A decode written as an initializer is invisible to the statement regex, so
# without the accounting check it would bypass the allow-list, the data
# deny-list and the alpha guard all at once. This fixture decodes a normal map -
# the exact thing the deny-list exists to prevent - using that form.
Add-Fixture -Name 'data-source decode hidden in a declaration initializer' `
    -ExpectedMessage 'bypasses the Stage A allow-list' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        $anchor = "    diffuseTex.rgb = srgb_to_linear(diffuseTex.rgb);"
        $inject = $anchor + "`r`n    float3 smuggled = srgb_to_linear(normalTex);"
        [IO.File]::WriteAllText($path, $text.Replace($anchor, $inject))
    }

# -----------------------------------------------------------------------------
# Terrain-normal representation and authored-strength guards
# -----------------------------------------------------------------------------

Add-Fixture -Name 'packed mesh terrain normal drops the saturated sqrt guard' `
    -ExpectedMessage 'must reconstruct the packed mesh terrain normal' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            'sqrt(saturate(1.0 - dot(nNormal, nNormal)))',
            'sqrt(1.0 - dot(nNormal, nNormal))'))
    }

Add-Fixture -Name 'Enhanced terrain normal XY amplification returns' `
    -ExpectedMessage 'modifies the unpacked terrain normal outside the named unpack diagnostic before the TBN transform' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        $anchor = '    float3 normalTex = unpack_terrain_normal(normalSample);'
        $inject = $anchor + "`r`n    normalTex.xy *= 1.45;"
        [IO.File]::WriteAllText($path, $text.Replace($anchor, $inject))
    }

Add-Fixture -Name 'terrain normal diagnostic accidentally enabled by default' `
    -ExpectedMessage 'must default CR_TERRAIN_NORMAL_DEBUG_MODE to 0' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            '#define CR_TERRAIN_NORMAL_DEBUG_MODE 0',
            '#define CR_TERRAIN_NORMAL_DEBUG_MODE 5'))
    }

Add-Fixture -Name 'terrain TBN correction accidentally enabled by default' `
    -ExpectedMessage 'must default CR_TERRAIN_NORMAL_BASIS_MODE to 0' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            '#define CR_TERRAIN_NORMAL_BASIS_MODE 0',
            '#define CR_TERRAIN_NORMAL_BASIS_MODE 2'))
    }

Add-Fixture -Name 'terrain AG unpack loses saturated Z reconstruction' `
    -ExpectedMessage "terrain-normal diagnostic contract is missing 'sqrt(saturate(1.0 - dot(xy, xy)))'" `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            'sqrt(saturate(1.0 - dot(xy, xy)))',
            'sqrt(1.0 - dot(xy, xy))'))
    }

# -----------------------------------------------------------------------------
# Enhanced program boundary
# -----------------------------------------------------------------------------

Add-Fixture -Name 'Stage A leaks onto a Retro program' `
    -ExpectedMessage 'is a DX11 Retro program but defines CR_LINEAR_LIGHT' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain.program'
        $text = [IO.File]::ReadAllText($path)
        # Target an SM4 Retro program specifically. The first Retro declaration
        # in the file is a GLSLES one, and mutating that would be caught by the
        # separate "not a DX11 SM4 program" rule instead - a real guard, but not
        # the one this fixture exists to exercise.
        #
        # These files are CRLF, and .NET's multiline '$' anchors before '\n'
        # only - never before the '\r'. Use an explicit lookahead instead.
        $rx = [regex]::new(
            '(?s)(fragment_program\s+CR_TerrainOGHighNoShadow_fragmentHLSL4\s+hlsl.*?preprocessor_defines\s+[^\r\n]*)(?=\r?\n)')
        [IO.File]::WriteAllText($path, $rx.Replace($text, '$1,CR_LINEAR_LIGHT=1', 1))
    }

Add-Fixture -Name 'an Enhanced program opts out of Stage A' `
    -ExpectedMessage 'does not define CR_LINEAR_LIGHT=1' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain.program'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            ',CR_LINEAR_LIGHT=1,CR_RADIAL_FOG=1',
            ',CR_RADIAL_FOG=1'))
    }

Add-Fixture -Name 'an Enhanced program opts out of radial fog' `
    -ExpectedMessage 'does not define CR_RADIAL_FOG=1' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain.program'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            ',CR_LINEAR_LIGHT=1,CR_RADIAL_FOG=1',
            ',CR_LINEAR_LIGHT=1'))
    }

Add-Fixture -Name 'radial fog leaks onto a Retro program' `
    -ExpectedMessage 'is a DX11 Retro program but defines CR_RADIAL_FOG' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain.program'
        $text = [IO.File]::ReadAllText($path)
        $rx = [regex]::new(
            '(?s)(fragment_program\s+CR_TerrainOGHighNoShadow_fragmentHLSL4\s+hlsl.*?preprocessor_defines\s+[^\r\n]*)(?=\r?\n)')
        [IO.File]::WriteAllText($path, $rx.Replace($text, '$1,CR_RADIAL_FOG=1', 1))
    }

# -----------------------------------------------------------------------------
# Shared-helper identity
# -----------------------------------------------------------------------------

# The fog helper is duplicated verbatim in both world shaders because nothing in
# this tree can #include. Tuning the curve in one file only would make terrain
# and objects fog differently, with a visible seam at every building base.
Add-Fixture -Name 'shared fog helper tuned in one shader only' `
    -ExpectedMessage "The shared helper 'compute_radial_fog_factor' differs between" `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            'return (t * t * (3.0 - 2.0 * t)) * configured;',
            'return (t * t * (3.0 - 2.5 * t)) * configured;'))
    }

# -----------------------------------------------------------------------------
# Radial fog must be driven by view-space distance, never clip-space depth
# -----------------------------------------------------------------------------

Add-Fixture -Name 'radial fog fed clip-space depth instead of view distance' `
    -ExpectedMessage 'Radial fog must never be driven by clip-space depth' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_base-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            'compute_radial_fog_factor(viewDistance, fogParams, densityScale)',
            'compute_radial_fog_factor(vDepth, fogParams, densityScale)'))
    }

# -----------------------------------------------------------------------------
# The legacy depth fog must survive
# -----------------------------------------------------------------------------

Add-Fixture -Name 'legacy depth-based fog replaced by the radial factor' `
    -ExpectedMessage 'Default/Retro fog must not become radial' `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_terrain-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            'float fogValue = saturate((vDepth - fogParams.y) * fogParams.w);',
            'float fogValue = saturate((length(vViewPosition) - fogParams.y) * fogParams.w);'))
    }

# -----------------------------------------------------------------------------
# Activation scope
# -----------------------------------------------------------------------------

Add-Fixture -Name 'activation condition stops excluding Retro' `
    -ExpectedMessage "is missing '!defined(OG_RETRO_MODE)'" `
    -Mutate {
        param($dir)
        $path = Join-Path $dir 'CR_base-sm4.hlsl'
        $text = [IO.File]::ReadAllText($path)
        [IO.File]::WriteAllText($path, $text.Replace(
            ' && !defined(OG_RETRO_MODE)', ''))
    }

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
Write-Host ''
foreach ($name in $results) { Write-Host "  PASS  $name" }

if ($failures.Count -gt 0) {
    Write-Host ''
    $detail = ($failures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
    throw "DX11 validator mutation fixtures failed:$([Environment]::NewLine)$detail"
}

Write-Host ''
Write-Host "All $($results.Count) DX11 validator mutation fixtures were correctly rejected."
