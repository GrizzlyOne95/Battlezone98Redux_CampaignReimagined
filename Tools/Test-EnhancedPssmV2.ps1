# Enhanced PSSM v2: the material-pairing half.
#
# This used to be a whole-stack guard: cascade maths, shader isolation, and an
# fxc compile matrix, all on top of CR's own copy of the Enhanced base and
# terrain shaders. Commit 400a7a6 retired that copy and moved those shaders to
# OpenShim, which is correct -- OpenShim owns the generic Enhanced renderer and
# CR owns the art direction -- but this script was left pointing at four files
# that no longer exist, and it failed on the first line that read one.
#
# It went unnoticed because the workflow that runs it only triggers on Shaders/
# or Materials/ changes, and nothing had touched either path since. So PSSM v2
# had no coverage anywhere from 2026-09-13 until a material change went looking.
#
# The shader half now lives in OpenShim as scripts/Test-EnhancedPssmV2.ps1 --
# the cascade model, the isolation assertions and the compile/cost matrix, all
# against the payload that actually holds the code. What stays here is the part
# that was always CR's: whether CR's materials pair the v2 pass with the right
# scheme and still preserve the DX9 renderer fallback beside it.
#
# That pairing is worth guarding separately. The shaders can be perfect and the
# feature still not reach the screen, because selecting it is a material
# decision -- and a material that silently drops its DX9 fallback does not fail
# on a DX11 machine, which is the machine it would be tested on.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failures.Add($Message) }
}

$materialCases = @(
    @{ Name='Materials\CR_BZBase.material'; V2='BZPassSchemeENHighPSSMV2'; V1='BZPassSchemeHighPSSM' },
    @{ Name='Materials\CR_BZTerrainBase.material'; V2='BZTerrainPassSchemeENHighPSSMV2'; V1='BZTerrainPassSchemeHighPSSM' }
)

foreach ($case in $materialCases) {
    $path = Join-Path $repoRoot $case.Name
    if (-not (Test-Path -LiteralPath $path)) {
        # Fatal rather than skipped: silently passing over a missing subject is
        # exactly how this script spent weeks reporting nothing.
        throw "Material missing: $path"
    }

    $material = Get-Content $path -Raw

    Assert-True ([regex]::Matches($material, 'compare_test\s+on').Count -eq 3) "$($case.Name) must enable comparison sampling on exactly three v2 cascade units."

    $primary = '(?ms)//\s+CR_ENHANCED_PSSM_PRIMARY\s+technique\s*\{.*?scheme\s+en-high-pssm\s+lod_index\s+0\s+pass\s*:\s*' + [regex]::Escape($case.V2)
    Assert-True ($material -match $primary) "$($case.Name) does not select its v2 pass as the primary Enhanced lod-0 technique."

    $fallback = '(?ms)(?:Renderer fallback|fallback for that backend).*?technique\s*\{.*?scheme\s+en-high-pssm\s+lod_index\s+0\s+pass\s*:\s*' + [regex]::Escape($case.V1)
    Assert-True ($material -match $fallback) "$($case.Name) does not preserve its original DX9 renderer fallback pass."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    throw "Enhanced PSSM v2 material validation failed with $($failures.Count) error(s)."
}

Write-Host "Enhanced PSSM v2 material pairing: PASS ($($materialCases.Count) materials)"
Write-Host 'Shader maths, isolation and compile cost are validated in OpenShim by scripts/Test-EnhancedPssmV2.ps1.'
