<#
.SYNOPSIS
    Every program a CR material asks for must be declared somewhere.

.DESCRIPTION
    CR's Enhanced base and terrain programs are declared by OpenShim's payload
    now, not by CR. That split is invisible to Ogre -- program names live in
    one flat namespace, so a material referencing a name nothing declares does
    not error at parse time. Ogre logs a line, drops the technique, falls back
    to whatever else the scheme can resolve, and the map renders: darker, or
    unlit, or with the stock shader. The mod still "works".

    So the reference graph is checked directly. Every vertex_program_ref,
    fragment_program_ref, shadow_caster_*_program_ref and unified `delegate`
    in CR's materials and program scripts is resolved against the union of
    what CR declares and what the OpenShim payload declares.

    This is what makes deleting CR's duplicate shaders a provable change
    rather than a hopeful one.

.EXAMPLE
    ./Tools/Test-ProgramReferences.ps1
#>
[CmdletBinding()]
param(
    [string]$OpenShimRepo
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $OpenShimRepo) { $OpenShimRepo = $env:BZR_OPENSHIM_REPO }
if (-not $OpenShimRepo) {
    $OpenShimRepo = Join-Path (Split-Path -Parent $repoRoot) 'BZR-OpenShim'
}
$openShimPayload = Join-Path $OpenShimRepo 'resources\renderer\enhanced'
if (-not (Test-Path -LiteralPath $openShimPayload)) {
    throw ("Cannot find OpenShim's Enhanced payload at '$openShimPayload'. " +
           "CR's Enhanced programs are declared there. " +
           "Set BZR_OPENSHIM_REPO to an OpenShim checkout.")
}

$programDirs = @(
    (Join-Path $repoRoot 'Shaders'),
    $openShimPayload
)

# Ogre lets a .material declare programs as well as reference them -- the
# depth-shadowmap family is declared inline in CR_DepthShadowmap.material --
# so both extensions are swept for declarations, not just .program scripts.
$declarationDirs = $programDirs + @(Join-Path $repoRoot 'Materials')

$declared = New-Object 'System.Collections.Generic.HashSet[string]'
$declaringFiles = 0
foreach ($dir in $declarationDirs) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $dir -File |
            Where-Object { $_.Extension -in @('.program', '.material') })) {
        $declaringFiles++
        foreach ($m in [regex]::Matches(
                [IO.File]::ReadAllText($file.FullName),
                '(?m)^\s*(?:vertex_program|fragment_program)\s+(\S+)\s+\S+')) {
            [void]$declared.Add($m.Groups[1].Value)
        }
    }
}

# Ogre ships its own program names too -- CR's materials legitimately reference
# stock ones. Only names in a namespace this repository owns are checked; a
# stock name is not ours to resolve.
$ownedPrefixes = @('CR_', 'OSE_')
$ownedSourcePrefixes = @('CR_', 'openshim_')

$referenceSites = @()
foreach ($dir in @((Join-Path $repoRoot 'Materials'), (Join-Path $repoRoot 'Shaders'))) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $referenceSites += Get-ChildItem -LiteralPath $dir -File |
        Where-Object { $_.Extension -in @('.material', '.program') }
}

$refPattern = '(?m)^\s*(?:(?:vertex|fragment|shadow_caster_vertex|shadow_caster_fragment)_program_ref|delegate)\s+(\S+)'

$dangling = @()
$checked = 0
foreach ($site in $referenceSites) {
    $text = [IO.File]::ReadAllText($site.FullName)
    $lineStarts = $null
    foreach ($m in [regex]::Matches($text, $refPattern)) {
        $name = $m.Groups[1].Value
        if (-not ($ownedPrefixes | Where-Object { $name.StartsWith($_) })) { continue }
        $checked++
        if ($declared.Contains($name)) { continue }
        if (-not $lineStarts) {
            $lineStarts = @(0) + ([regex]::Matches($text, "`n") | ForEach-Object { $_.Index + 1 })
        }
        $line = ($lineStarts | Where-Object { $_ -le $m.Index }).Count
        $dangling += "{0}:{1} references '{2}', which nothing declares" -f $site.Name, $line, $name
    }
}

# A `source` line naming a file that is not there fails the same silent way.
$missingSources = @()
foreach ($site in ($referenceSites | Where-Object { $_.Extension -eq '.program' })) {
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($site.FullName),
                                    '(?m)^\s*source\s+(\S+)')) {
        $source = $m.Groups[1].Value
        # Stock engine sources (sky-vertex.glsles and friends) ship with the
        # game and are correctly referenced unprefixed. Same rule as above:
        # only names in a namespace this repository owns are ours to resolve.
        if (-not ($ownedSourcePrefixes | Where-Object { $source.StartsWith($_) })) { continue }
        $found = $programDirs | Where-Object {
            Test-Path -LiteralPath (Join-Path $_ $source)
        }
        if (-not $found) {
            $missingSources += "{0} declares 'source {1}', which is in neither Shaders nor the OpenShim payload" -f $site.Name, $source
        }
    }
}

Write-Host ("declared : {0} program name(s) from {1} script(s)" -f $declared.Count, $declaringFiles)
Write-Host ("checked  : {0} owned reference(s) across {1} file(s)" -f $checked, $referenceSites.Count)

$problems = @($dangling) + @($missingSources)
if ($problems.Count -gt 0) {
    Write-Host ""
    foreach ($p in ($problems | Sort-Object -Unique)) {
        Write-Host "DANGLING: $p" -ForegroundColor Red
    }
    throw "$($problems.Count) unresolved program reference(s)."
}

Write-Host "every owned program reference resolves" -ForegroundColor Green
exit 0
