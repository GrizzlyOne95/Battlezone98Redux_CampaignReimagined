[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('V1', 'V2')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$programFiles = @(
    'Shaders\CR_base.program',
    'Shaders\CR_terrain.program',
    'Shaders\CR_static_ibl.program'
)

$programNames = @(
    'CR_BaseENHighPSSMV2_vertexHLSL4',
    'CR_BaseENHighPSSM_fragmentHLSL4',
    'CR_TerrainENHighPSSMV2_vertexHLSL4',
    'CR_TerrainENHighPSSM_fragmentHLSL4',
    'CR_BaseIBLHighPSSM_fragmentHLSL4',
    'CR_TerrainIBLHighPSSM_fragmentHLSL4'
)

foreach ($relative in $programFiles) {
    $path = Join-Path $repoRoot $relative
    $original = [IO.File]::ReadAllText($path)
    $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $hadFinalNewline = $original.EndsWith($newline)
    $splitLines = $original -split '\r?\n'
    if ($hadFinalNewline -and $splitLines.Count -gt 0 -and $splitLines[-1] -eq '') {
        $splitLines = $splitLines[0..($splitLines.Count - 2)]
    }
    $lines = [Collections.Generic.List[string]]::new([string[]]$splitLines)
    $currentProgram = $null
    $updated = 0
    for ($index = 0; $index -lt $lines.Count; ++$index) {
        if ($lines[$index] -match '^\s*(?:vertex|fragment)_program\s+(\S+)\s+') {
            $currentProgram = $Matches[1]
            continue
        }
        if ($currentProgram -and $programNames -contains $currentProgram -and
            $lines[$index] -match '^(?<prefix>\s*preprocessor_defines\s+)(?<defines>.*)$') {
            $defines = $Matches['defines'] -replace ',CR_ENHANCED_PSSM_V2=1', ''
            if ($Version -eq 'V2') { $defines += ',CR_ENHANCED_PSSM_V2=1' }
            $lines[$index] = $Matches['prefix'] + $defines
            ++$updated
            $currentProgram = $null
        }
    }
    $updatedText = $lines -join $newline
    if ($hadFinalNewline) { $updatedText += $newline }
    [IO.File]::WriteAllText($path, $updatedText, [Text.UTF8Encoding]::new($false))
}

$materialSwitches = @(
    @{
        Path = 'Materials\CR_BZBase.material'
        V1 = 'pass : BZPassSchemeHighPSSM'
        V2 = 'pass : BZPassSchemeENHighPSSMV2'
    },
    @{
        Path = 'Materials\CR_BZTerrainBase.material'
        V1 = 'pass : BZTerrainPassSchemeHighPSSM'
        V2 = 'pass : BZTerrainPassSchemeENHighPSSMV2'
    }
)
foreach ($switch in $materialSwitches) {
    $path = Join-Path $repoRoot $switch.Path
    $text = [IO.File]::ReadAllText($path)
    $old = if ($Version -eq 'V2') { $switch.V1 } else { $switch.V2 }
    $new = if ($Version -eq 'V2') { $switch.V2 } else { $switch.V1 }
    $primaryPrefix = '(?ms)(//\s+CR_ENHANCED_PSSM_PRIMARY\s+technique\s*\{.*?scheme\s+en-high-pssm\s+lod_index\s+0\s+)'
    $activeScheme = $primaryPrefix + [regex]::Escape($old)
    $count = [regex]::Matches($text, $activeScheme).Count
    if ($count -ne 1) {
        # Idempotent invocation is valid only when the requested state already
        # appears exactly once in the active Enhanced lod-0 technique.
        $already = $primaryPrefix + [regex]::Escape($new)
        if ([regex]::Matches($text, $already).Count -ne 1) {
            throw "$($switch.Path) did not contain one recognizable Enhanced PSSM pass switch."
        }
    }
    else {
        $text = [regex]::Replace($text, $activeScheme, "`$1$new", 1)
        [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    }
}

Write-Host "DX11 Enhanced High PSSM source selection is now $Version. Re-run shader validation before deployment."
