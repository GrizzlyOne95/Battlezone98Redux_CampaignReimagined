[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-BraceBlocks {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Keyword
    )

    $blocks = @()
    $matches = [regex]::Matches($Text, "(?m)^\s*$Keyword\b")
    foreach ($match in $matches) {
        $open = $Text.IndexOf('{', $match.Index)
        if ($open -lt 0) { throw "No opening brace after $Keyword at offset $($match.Index)." }
        $depth = 0
        for ($i = $open; $i -lt $Text.Length; ++$i) {
            if ($Text[$i] -eq '{') { ++$depth }
            elseif ($Text[$i] -eq '}') {
                --$depth
                if ($depth -eq 0) {
                    $blocks += $Text.Substring($match.Index, $i - $match.Index + 1)
                    break
                }
            }
        }
        if ($depth -ne 0) { throw "Unbalanced $Keyword block at offset $($match.Index)." }
    }
    return $blocks
}

$cases = @(
    @{
        Path = Join-Path $repoRoot 'Materials/CR_BZBase.material'
        Wrappers = @(
            'CR_BZPassSchemeEnhancedHighPSSM',
            'CR_BZPassSchemeEnhancedHigh',
            'CR_BZPassSchemeEnhancedHighNoShadow'
        )
        ExpectedReferences = @{
            CR_BZPassSchemeEnhancedHighPSSM = 1
            CR_BZPassSchemeEnhancedHigh = 1
            CR_BZPassSchemeEnhancedHighNoShadow = 4
        }
        HighLods = @(0)
    },
    @{
        Path = Join-Path $repoRoot 'Materials/CR_BZTerrainBase.material'
        Wrappers = @(
            'CR_BZTerrainPassSchemeEnhancedHighPSSM',
            'CR_BZTerrainPassSchemeEnhancedHigh',
            'CR_BZTerrainPassSchemeEnhancedHighNoShadow'
        )
        ExpectedReferences = @{
            CR_BZTerrainPassSchemeEnhancedHighPSSM = 1
            CR_BZTerrainPassSchemeEnhancedHigh = 1
            CR_BZTerrainPassSchemeEnhancedHighNoShadow = 4
        }
        HighLods = @(0, 1)
    }
)

foreach ($case in $cases) {
    $text = Get-Content -LiteralPath $case.Path -Raw
    $name = Split-Path -Leaf $case.Path

    foreach ($wrapper in $case.Wrappers) {
        $definition = [regex]::Match(
            $text,
            "(?ms)^\s*abstract\s+pass\s+$([regex]::Escape($wrapper))\b.*?^\s*}\s*$")
        if (-not $definition.Success -or
            $definition.Value -notmatch '(?m)^\s*max_lights\s+24\s*$') {
            throw "$($name): $wrapper must define max_lights 24."
        }

        $referenceCount = [regex]::Matches(
            $text,
            "(?m)^\s*pass\s*:\s*$([regex]::Escape($wrapper))\s*$").Count
        $expected = $case.ExpectedReferences[$wrapper]
        if ($referenceCount -ne $expected) {
            throw "$($name): $wrapper has $referenceCount technique references; expected $expected."
        }
    }

    $techniques = Get-BraceBlocks -Text $text -Keyword 'technique'
    foreach ($technique in $techniques) {
        $schemeMatch = [regex]::Match($technique, '(?m)^\s*scheme\s+(\S+)\s*$')
        if (-not $schemeMatch.Success) { continue }
        $scheme = $schemeMatch.Groups[1].Value
        $usesEnhancedWrapper = $false
        foreach ($wrapper in $case.Wrappers) {
            if ($technique -match "(?m)^\s*pass\s*:\s*$([regex]::Escape($wrapper))\s*$") {
                $usesEnhancedWrapper = $true
                break
            }
        }

        if ($usesEnhancedWrapper -and -not $scheme.StartsWith('en-high')) {
            throw "$($name): non-Enhanced-High scheme '$scheme' references an Enhanced light-budget wrapper."
        }

        if ($scheme.StartsWith('en-high')) {
            $lodMatch = [regex]::Match($technique, '(?m)^\s*lod_index\s+(\d+)\s*$')
            $isHighShaderLod = -not $lodMatch.Success -or
                $case.HighLods -contains [int]$lodMatch.Groups[1].Value
            if ($isHighShaderLod -ne $usesEnhancedWrapper) {
                $lod = if ($lodMatch.Success) { $lodMatch.Groups[1].Value } else { '(implicit)' }
                throw "$($name): scheme '$scheme' lod $lod has incorrect Enhanced budget isolation."
            }
        }
    }

    $maxLightsCount = [regex]::Matches($text, '(?m)^\s*max_lights\s+24\s*$').Count
    if ($maxLightsCount -ne 3) {
        throw "$($name): found $maxLightsCount max_lights 24 directives; expected only the 3 Enhanced wrappers."
    }
}

$programs = @(
    (Join-Path $repoRoot 'Shaders/CR_base.program')
    (Join-Path $repoRoot 'Shaders/CR_terrain.program')
    (Join-Path $repoRoot 'Shaders/CR_static_ibl.program')
)
foreach ($program in $programs) {
    $text = Get-Content -LiteralPath $program -Raw
    if ($text -notmatch 'MAX_LIGHTS=24' -or
        $text -notmatch 'derived_light_diffuse_colour_array\s+24' -or
        $text -notmatch 'light_position_view_space_array\s+24' -or
        $text -notmatch 'light_count') {
        throw "$(Split-Path -Leaf $program): missing a required 24-light Enhanced shader/binding contract."
    }
}

Write-Host 'Enhanced light-budget isolation passed: DX11 Enhanced High=24; Classic/default passes retain Ogre default=8.'
