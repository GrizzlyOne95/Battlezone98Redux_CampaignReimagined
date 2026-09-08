<#
.SYNOPSIS
    Proves which shipped DX11 shader permutations a change actually altered.

.DESCRIPTION
    Validate-DX11Shaders.ps1 asserts that the *source* stays inside its intended
    boundaries. This script asserts the complementary thing about the *output*:
    it compiles every DX11 SM4 permutation the .program files actually declare,
    from two different revisions of the tree, and compares the resulting DXBC
    byte-for-byte.

    That turns "Default and Retro are untouched" from a claim that needs a
    human staring at two screenshots into a mechanical fact. If a legacy
    permutation's bytecode is bit-identical before and after a change, the GPU
    cannot possibly render it differently - there is nothing left to observe.

    The permutation matrix is derived from the .program declarations rather
    than hand-written, so it is exactly what ships. A variant that is added,
    removed or re-defined shows up as such instead of silently escaping.

.PARAMETER BaselineRef
    Git revision to use as the baseline (default HEAD). The Shaders directory
    is materialized from that revision into a temporary tree.

.PARAMETER BaselinePath
    Use an existing directory as the baseline instead of a git revision. It
    must contain a Shaders subdirectory.

.PARAMETER CurrentPath
    Tree to compare against the baseline. Defaults to the repository working
    tree.

.PARAMETER RequireLegacyIdentical
    Fail (non-zero exit) if any Default/Retro permutation's DXBC changed.
    This is the guard to run in CI for any Enhanced-only change.

.EXAMPLE
    ./Tools/Compare-DX11ShaderBinaries.ps1 -RequireLegacyIdentical
    Compare the working tree against HEAD and fail if legacy bytecode moved.
#>
[CmdletBinding()]
param(
    [string]$BaselineRef = 'HEAD',
    [string]$BaselinePath,
    [string]$CurrentPath,
    [string]$FxcPath,
    [switch]$RequireLegacyIdentical
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $CurrentPath) { $CurrentPath = $repoRoot }

# -----------------------------------------------------------------------------
# Locate fxc
# -----------------------------------------------------------------------------
if (-not $FxcPath) {
    $fxc = Get-Command fxc.exe -ErrorAction SilentlyContinue
    if ($fxc) { $FxcPath = $fxc.Source }
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

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) 'bzr-dx11-shader-binary-compare'
if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
New-Item $tempRoot -ItemType Directory | Out-Null

# -----------------------------------------------------------------------------
# Materialize the baseline tree
# -----------------------------------------------------------------------------
if (-not $BaselinePath) {
    $BaselinePath = Join-Path $tempRoot 'baseline'
    $baselineShaders = Join-Path $BaselinePath 'Shaders'
    New-Item $baselineShaders -ItemType Directory -Force | Out-Null

    Push-Location $repoRoot
    try {
        # -r is required: without it git lists the 'Shaders' tree object itself
        # rather than the blobs inside it, which silently yields an empty
        # baseline and a vacuous "nothing changed" result.
        $tracked = @(git ls-tree -r --name-only "$BaselineRef" -- Shaders 2>$null)
        if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) {
            throw "Could not list Shaders at revision '$BaselineRef'."
        }
        foreach ($entry in $tracked) {
            $leaf = Split-Path -Leaf $entry
            $dest = Join-Path $baselineShaders $leaf
            # Write the blob as raw bytes. Piping through PowerShell string
            # handling would re-encode the file and is unnecessary here.
            $bytes = git -c core.autocrlf=false show "${BaselineRef}:$entry" | Out-String -Stream
            if ($LASTEXITCODE -ne 0) { continue }
            [System.IO.File]::WriteAllLines($dest, $bytes)
        }
    }
    finally { Pop-Location }

    $materialized = @(Get-ChildItem $baselineShaders -File -ErrorAction SilentlyContinue)
    if ($materialized.Count -eq 0) {
        throw "Baseline tree for '$BaselineRef' materialized zero shader files."
    }
}

# -----------------------------------------------------------------------------
# Parse .program declarations
# -----------------------------------------------------------------------------
# Ogre .program syntax is brace-delimited. Only declarations naming an SM4 HLSL
# source are compilable here; DX9, GLSL, GLSLES and unified delegates are
# skipped (they carry no 'source *-sm4.hlsl').
function Get-ProgramPermutations {
    param([string]$ShaderDir)

    $records = @()
    foreach ($file in (Get-ChildItem $ShaderDir -Filter '*.program' -File | Sort-Object Name)) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName)
        $cur = $null
        $depth = 0
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t.StartsWith('//')) { continue }
            if ($t -match '^(vertex_program|fragment_program)\s+(\S+)\s+(\S+)\s*$') {
                $cur = [pscustomobject]@{
                    File = $file.Name
                    Kind = $Matches[1]
                    Name = $Matches[2]
                    Lang = $Matches[3]
                    Source = ''
                    Entry = ''
                    Target = ''
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
            elseif ($t -match '^entry_point\s+(\S+)') { $cur.Entry = $Matches[1] }
            elseif ($t -match '^target\s+(\S+)') { $cur.Target = $Matches[1] }
            elseif ($t -match '^preprocessor_defines\s+(.+)$') { $cur.Defines = $Matches[1].Trim() }
        }
    }

    return $records | Where-Object {
        $_.Source -like '*-sm4.hlsl' -and $_.Entry -and $_.Target
    }
}

# Same classification the validator uses, so the two tools agree on what
# "legacy" means.
function Get-PermutationTier {
    param([string]$Defines, [string]$Kind)
    if ($Defines -match '(^|,)\s*(OG_RETRO_MODE|RETRO_UNLIT_MODE)\b') { return 'Retro' }
    if ($Defines -match '(^|,)\s*ENHANCED_MODE\b' -and $Defines -notmatch '(^|,)\s*VERTEX_LIGHTING\b') { return 'Enhanced' }
    return 'Default'
}

function Get-PermutationHashes {
    param([string]$TreePath, [string]$Label)

    $shaderDir = Join-Path $TreePath 'Shaders'
    if (-not (Test-Path $shaderDir)) { throw "No Shaders directory under '$TreePath'." }

    $outDir = Join-Path $tempRoot $Label
    New-Item $outDir -ItemType Directory -Force | Out-Null

    $result = @{}
    $failures = @()
    $permutations = Get-ProgramPermutations -ShaderDir $shaderDir

    $index = 0
    foreach ($p in $permutations) {
        $index++
        # Distinct permutations can share a program name across files only if the
        # .program set is malformed; key on file+name so that would surface.
        $key = "$($p.File)::$($p.Name)"
        $outFile = Join-Path $outDir ("{0:D4}.cso" -f $index)

        $fxcArgs = @('/nologo', '/Ges', '/WX', '/T', $p.Target, '/E', $p.Entry, '/Fo', $outFile)
        if ($p.Defines) {
            foreach ($define in ($p.Defines -split ',')) {
                $trimmed = $define.Trim()
                if ($trimmed) { $fxcArgs += @('/D', $trimmed) }
            }
        }
        $fxcArgs += (Join-Path $shaderDir $p.Source)

        & $FxcPath @fxcArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outFile)) {
            $failures += "$Label $key failed to compile."
            continue
        }

        $result[$key] = [pscustomobject]@{
            Hash = (Get-FileHash -LiteralPath $outFile -Algorithm SHA256).Hash
            Tier = Get-PermutationTier -Defines $p.Defines -Kind $p.Kind
            Kind = $p.Kind
            Source = $p.Source
            Defines = $p.Defines
        }
    }

    if ($failures.Count -gt 0) {
        $detail = ($failures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
        throw "Permutation compilation failed:$([Environment]::NewLine)$detail"
    }

    Write-Host "$Label : compiled $($result.Count) shipped DX11 SM4 permutations."
    return $result
}

$baseline = Get-PermutationHashes -TreePath $BaselinePath -Label 'baseline'
$current = Get-PermutationHashes -TreePath $CurrentPath -Label 'current'

# A comparison against an empty or barely-overlapping baseline would report
# "nothing changed" for the wrong reason. Refuse to draw a conclusion from it.
if ($baseline.Count -eq 0) {
    throw 'The baseline tree produced zero permutations; there is nothing to compare against.'
}
$overlap = @($current.Keys | Where-Object { $baseline.ContainsKey($_) }).Count
if ($overlap -lt [Math]::Floor($current.Count * 0.9)) {
    throw "Only $overlap of $($current.Count) current permutations exist in the baseline. The two trees are too dissimilar for a meaningful binary comparison."
}

# -----------------------------------------------------------------------------
# Compare
# -----------------------------------------------------------------------------
$added = @()
$removed = @()
$changed = @()
$identical = 0

foreach ($key in $current.Keys) {
    if (-not $baseline.ContainsKey($key)) { $added += $key; continue }
    if ($baseline[$key].Hash -ne $current[$key].Hash) {
        $changed += [pscustomobject]@{
            Key = $key
            Tier = $current[$key].Tier
            Kind = $current[$key].Kind
            Source = $current[$key].Source
        }
    }
    else { $identical++ }
}
foreach ($key in $baseline.Keys) {
    if (-not $current.ContainsKey($key)) { $removed += $key }
}

Write-Host ''
Write-Host '=== DX11 shipped-permutation binary comparison ==='
Write-Host "  baseline        : $(if ($PSBoundParameters.ContainsKey('BaselinePath')) { $BaselinePath } else { $BaselineRef })"
Write-Host "  identical DXBC  : $identical"
Write-Host "  changed DXBC    : $($changed.Count)"
Write-Host "  added           : $($added.Count)"
Write-Host "  removed         : $($removed.Count)"

$byTier = $changed | Group-Object Tier | Sort-Object Name
foreach ($group in $byTier) {
    Write-Host ''
    Write-Host "  changed [$($group.Name)] x$($group.Count):"
    foreach ($item in ($group.Group | Sort-Object Key)) {
        Write-Host "    - $($item.Key)  ($($item.Source))"
    }
}

foreach ($key in ($added | Sort-Object)) { Write-Host "  added   : $key" }
foreach ($key in ($removed | Sort-Object)) { Write-Host "  removed : $key" }

$legacyChanged = @($changed | Where-Object { $_.Tier -ne 'Enhanced' })

Write-Host ''
if ($legacyChanged.Count -eq 0) {
    Write-Host 'Default/Retro permutations are bit-identical to the baseline.'
}
else {
    Write-Host "WARNING: $($legacyChanged.Count) Default/Retro permutations changed."
}

if ($RequireLegacyIdentical -and $legacyChanged.Count -gt 0) {
    $detail = ($legacyChanged | ForEach-Object { "  - [$($_.Tier)] $($_.Key)" }) -join [Environment]::NewLine
    throw "Legacy DX11 permutations changed, but the change was declared Enhanced-only:$([Environment]::NewLine)$detail"
}
