# Enhanced High light budget: 24 lights per pass.
#
# The budget is a shader contract, not a material directive. Ogre initialises
# every pass to max_lights 8, but SceneManager::renderSingleObject treats that
# default as "no cap": only a pass whose max_lights differs from 8 gets a
# truncated copy of the light list. An ordinary pass is handed the complete
# list, and the program it selects decides how many lights it evaluates
# (see OpenShim Docs/DX11_ENHANCED_DYNAMIC_LIGHT_AUDIT.md).
#
# So the 24 lights reach the screen only while three things stay true, and
# this script checks each of them:
#   1. every Enhanced High technique at a High LOD selects one of CR's
#      static-IBL High fragment programs;
#   2. those programs, and every delegate they can fall back to, compile with
#      MAX_LIGHTS=24 and bind six 24-entry light arrays plus light_count;
#   3. no pass in these materials sets max_lights below 24, which would switch
#      Ogre to the truncating path and silently drop lights.
#
# An earlier version of this test (archived commit 22b313ab) required
# "max_lights 24" wrapper passes. They are not needed and are not restored:
# they add a per-renderable list copy and deliver the same 24 lights.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$budget = 24
$failures = [Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        # Fatal rather than skipped: a guard that passes over a missing subject
        # reports success without having checked anything.
        throw "Required file missing: $path"
    }
    return Get-Content -LiteralPath $path -Raw
}

function Get-BraceBlocks {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern
    )

    $blocks = @()
    foreach ($match in [regex]::Matches($Text, $Pattern)) {
        $open = $Text.IndexOf('{', $match.Index)
        if ($open -lt 0) { throw "No opening brace after '$($match.Value.Trim())'." }
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
        if ($depth -ne 0) { throw "Unbalanced block after '$($match.Value.Trim())'." }
    }
    return $blocks
}

$programSources = @{
    'Shaders/CR_static_ibl.program' = Read-Required 'Shaders/CR_static_ibl.program'
    'openshim/renderer/enhanced/openshim_enhanced_base.program.payload' =
        Read-Required 'openshim/renderer/enhanced/openshim_enhanced_base.program.payload'
    'openshim/renderer/enhanced/openshim_enhanced_terrain.program.payload' =
        Read-Required 'openshim/renderer/enhanced/openshim_enhanced_terrain.program.payload'
}

function Get-ProgramBlock([string]$Name) {
    $pattern = "(?m)^\s*fragment_program\s+$([regex]::Escape($Name))\s+\w+\s*$"
    foreach ($source in $programSources.GetEnumerator()) {
        $blocks = @(Get-BraceBlocks -Text $source.Value -Pattern $pattern)
        if ($blocks.Count -gt 0) { return $blocks[0] }
    }
    return $null
}

$lightArrays = @(
    'derived_light_diffuse_colour_array',
    'derived_light_specular_colour_array',
    'light_attenuation_array',
    'spotlight_params_array',
    'light_position_view_space_array',
    'light_direction_view_space_array'
)

$cases = @(
    @{
        Path = 'Materials/CR_BZBase.material'
        ProgramPrefix = 'CR_BaseIBLHigh'
        HighLods = @(0)
        ExpectedHighTechniques = 7
    },
    @{
        Path = 'Materials/CR_BZTerrainBase.material'
        ProgramPrefix = 'CR_TerrainIBLHigh'
        HighLods = @(0, 1)
        ExpectedHighTechniques = 7
    }
)

$checkedPrograms = @{}
foreach ($case in $cases) {
    $name = $case.Path
    $text = Read-Required $name

    foreach ($match in [regex]::Matches($text, '(?m)^\s*max_lights\s+(\d+)\s*$')) {
        $value = [int]$match.Groups[1].Value
        Assert-True ($value -ge $budget) "$($name): 'max_lights $value' caps a pass below the $budget-light Enhanced budget."
    }

    $highTechniques = 0
    foreach ($technique in (Get-BraceBlocks -Text $text -Pattern '(?m)^\s*technique\s*$')) {
        $schemeMatch = [regex]::Match($technique, '(?m)^\s*scheme\s+(\S+)\s*$')
        if (-not $schemeMatch.Success) { continue }
        $scheme = $schemeMatch.Groups[1].Value
        $lodMatch = [regex]::Match($technique, '(?m)^\s*lod_index\s+(\d+)\s*$')
        $lod = if ($lodMatch.Success) { $lodMatch.Groups[1].Value } else { '(implicit)' }
        $isHighLod = -not $lodMatch.Success -or $case.HighLods -contains [int]$lodMatch.Groups[1].Value

        $programs = @([regex]::Matches($technique, '(?m)^\s*fragment_program_ref\s+(\S+)\s*$') |
            ForEach-Object { $_.Groups[1].Value })
        $highPrograms = @($programs | Where-Object { $_.StartsWith($case.ProgramPrefix) })

        if ($scheme.StartsWith('en-high') -and $isHighLod) {
            ++$highTechniques
            Assert-True ($programs.Count -gt 0 -and $highPrograms.Count -eq $programs.Count) "$($name): scheme '$scheme' lod $lod must select a $($case.ProgramPrefix)* fragment program; found '$($programs -join ', ')'."
            foreach ($program in $highPrograms) { $checkedPrograms[$program] = $true }
        }
        else {
            Assert-True ($highPrograms.Count -eq 0) "$($name): scheme '$scheme' lod $lod selects the $budget-light program '$($highPrograms -join ', ')' outside Enhanced High."
        }
    }

    Assert-True ($highTechniques -eq $case.ExpectedHighTechniques) "$($name): found $highTechniques Enhanced High techniques at a High LOD; expected $($case.ExpectedHighTechniques)."
}

$checkedDelegates = 0
foreach ($program in ($checkedPrograms.Keys | Sort-Object)) {
    $block = Get-ProgramBlock $program
    if (-not $block) {
        Assert-True $false "$program is not declared in CR_static_ibl.program or the committed OpenShim payload."
        continue
    }

    foreach ($array in $lightArrays) {
        Assert-True ($block -match "(?m)^\s*param_named_auto\s+\w+\s+$array\s+$budget\s*$") "$program does not bind $array $budget."
    }
    Assert-True ($block -match '(?m)^\s*param_named_auto\s+\w+\s+light_count\s*$') "$program does not bind light_count."

    $delegates = @([regex]::Matches($block, '(?m)^\s*delegate\s+(\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
    Assert-True ($delegates.Count -gt 0) "$program declares no delegates."
    foreach ($delegate in $delegates) {
        $delegateBlock = Get-ProgramBlock $delegate
        if (-not $delegateBlock) {
            Assert-True $false "$program delegate $delegate is not declared in CR_static_ibl.program or the committed OpenShim payload."
            continue
        }
        ++$checkedDelegates
        Assert-True ($delegateBlock -match "(?m)^\s*preprocessor_defines\s+(?:\S+,)?MAX_LIGHTS=$budget(?:,\S+)?\s*$") "$program delegate $delegate is not compiled with MAX_LIGHTS=$budget."
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" }
    throw "Enhanced light budget check failed with $($failures.Count) problem(s)."
}

Write-Host "Enhanced light budget passed: $($checkedPrograms.Count) Enhanced High programs and $checkedDelegates delegates evaluate $budget lights; no pass caps max_lights below $budget."
