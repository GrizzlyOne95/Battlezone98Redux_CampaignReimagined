<#
.SYNOPSIS
    Proves legacy SM4 shader bytecode parity against a Git baseline.

.DESCRIPTION
    Enumerates every direct HLSL SM4 program declaration in Shaders/*.program,
    excluding only declarations that explicitly define CR_MATERIAL_V2. It then
    compiles the same recipe from the current tree and an archived Git baseline
    and compares the resulting DXBC byte-for-byte.

    This is the hard legacy acceptance gate for Enhanced Material V2. It does
    not rely on visual similarity or approximate CPU math.

.EXAMPLE
    ./Tools/Compare-DX11ShaderBinaries.ps1 -BaselineRef main -RequireLegacyIdentical
#>
[CmdletBinding()]
param(
    [string]$BaselineRef = 'main',
    [string]$FxcPath,
    [switch]$RequireLegacyIdentical
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

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
if (-not $FxcPath -or -not (Test-Path -LiteralPath $FxcPath)) {
    throw 'fxc.exe was not found. Install a Windows SDK or pass -FxcPath explicitly.'
}

function Get-ProgramRecipes {
    param([string]$ShaderRoot)

    $recipes = @{}
    foreach ($path in (Get-ChildItem -LiteralPath $ShaderRoot -Filter '*.program' -File | Sort-Object Name)) {
        $lines = [IO.File]::ReadAllLines($path.FullName)
        $current = $null
        $depth = 0
        for ($line = 0; $line -lt $lines.Count; $line++) {
            $text = $lines[$line].Trim()
            if ($text.StartsWith('//')) { continue }
            if ($text -match '^(vertex_program|fragment_program)\s+(\S+)\s+(\S+)\s*$') {
                $current = [ordered]@{
                    Name = $Matches[2]
                    Lang = $Matches[3]
                    Source = ''
                    Target = ''
                    Entry = ''
                    Defines = ''
                }
                $depth = 0
                continue
            }
            if ($null -eq $current) { continue }
            if ($text -eq '{') { $depth++; continue }
            if ($text -eq '}') {
                $depth--
                if ($depth -le 0) {
                    if ($current.Lang -eq 'hlsl' -and
                        $current.Source -like '*-sm4.hlsl' -and
                        $current.Target -match '^[pv]s_4_0$' -and
                        $current.Entry -and
                        $current.Defines -notmatch '(^|,)\s*CR_MATERIAL_V2\s*=') {
                        $normalizedDefines = @(
                            $current.Defines.Split(',', [StringSplitOptions]::RemoveEmptyEntries) |
                                ForEach-Object { $_.Trim() } |
                                Sort-Object
                        )
                        $key = "$($current.Source)|$($current.Target)|$($current.Entry)|$($normalizedDefines -join ',')"
                        $recipes[$key] = [pscustomobject]@{
                            Key = $key
                            Source = $current.Source
                            Target = $current.Target
                            Entry = $current.Entry
                            Defines = $normalizedDefines
                        }
                    }
                    $current = $null
                    $depth = 0
                }
                continue
            }
            if ($text -match '^source\s+(\S+)') { $current.Source = $Matches[1] }
            elseif ($text -match '^target\s+(\S+)') { $current.Target = $Matches[1] }
            elseif ($text -match '^entry_point\s+(\S+)') { $current.Entry = $Matches[1] }
            elseif ($text -match '^preprocessor_defines\s+(.+)$') { $current.Defines = $Matches[1].Trim() }
        }
    }
    return $recipes
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("bzr-dx11-parity-" + [guid]::NewGuid().ToString('N'))
$baselineTree = Join-Path $tempRoot 'baseline'
$currentOutput = Join-Path $tempRoot 'current-dxbc'
$baselineOutput = Join-Path $tempRoot 'baseline-dxbc'
New-Item $baselineTree, $currentOutput, $baselineOutput -ItemType Directory -Force | Out-Null

try {
    $archive = Join-Path $tempRoot 'baseline.zip'
    & git -C $repoRoot archive --format=zip --output=$archive $BaselineRef -- Shaders
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archive)) {
        throw "git archive failed for baseline '$BaselineRef'."
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $baselineTree

    $currentShaderRoot = Join-Path $repoRoot 'Shaders'
    $baselineShaderRoot = Join-Path $baselineTree 'Shaders'
    $currentRecipes = Get-ProgramRecipes $currentShaderRoot
    $baselineRecipes = Get-ProgramRecipes $baselineShaderRoot

    $currentOnly = @($currentRecipes.Keys | Where-Object { -not $baselineRecipes.ContainsKey($_) } | Sort-Object)
    $baselineOnly = @($baselineRecipes.Keys | Where-Object { -not $currentRecipes.ContainsKey($_) } | Sort-Object)
    $failures = @()
    if ($currentOnly.Count -gt 0) {
        $failures += "Legacy compile recipes exist only in the current tree: $($currentOnly -join '; ')"
    }
    if ($baselineOnly.Count -gt 0) {
        $failures += "Legacy compile recipes exist only in baseline '$BaselineRef': $($baselineOnly -join '; ')"
    }

    $compared = 0
    foreach ($key in @($currentRecipes.Keys | Where-Object { $baselineRecipes.ContainsKey($_) } | Sort-Object)) {
        $recipe = $currentRecipes[$key]
        $fileStem = '{0:D3}' -f $compared
        $currentBinary = Join-Path $currentOutput "$fileStem.cso"
        $baselineBinary = Join-Path $baselineOutput "$fileStem.cso"

        foreach ($side in @(
            @{ Root = $currentShaderRoot; Output = $currentBinary; Label = 'current' },
            @{ Root = $baselineShaderRoot; Output = $baselineBinary; Label = "baseline $BaselineRef" }
        )) {
            $sourcePath = Join-Path $side.Root $recipe.Source
            $arguments = @('/nologo', '/Ges', '/WX', '/T', $recipe.Target, '/E', $recipe.Entry, '/Fo', $side.Output)
            foreach ($define in $recipe.Defines) { $arguments += @('/D', $define) }
            $arguments += $sourcePath
            $compilerOutput = & $FxcPath @arguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                $failures += "fxc failed for $($side.Label): $key`n$($compilerOutput -join [Environment]::NewLine)"
                break
            }
        }

        if ((Test-Path -LiteralPath $currentBinary) -and (Test-Path -LiteralPath $baselineBinary)) {
            $currentHash = (Get-FileHash -LiteralPath $currentBinary -Algorithm SHA256).Hash
            $baselineHash = (Get-FileHash -LiteralPath $baselineBinary -Algorithm SHA256).Hash
            if ($currentHash -ne $baselineHash) {
                $failures += "DXBC differs: $key (current $currentHash, baseline $baselineHash)"
            }
            $compared++
        }
    }

    if ($failures.Count -gt 0) {
        $detail = ($failures | ForEach-Object { "  - $_" }) -join [Environment]::NewLine
        $message = "Legacy DX11 shader parity failed against '$BaselineRef':$([Environment]::NewLine)$detail"
        if ($RequireLegacyIdentical) { throw $message }
        Write-Warning $message
    }
    else {
        Write-Host "Legacy DX11 parity passed: $compared unique SM4 recipes produced byte-identical DXBC against '$BaselineRef'."
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
