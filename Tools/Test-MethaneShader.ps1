param(
    [string]$FxcPath
)
# Compile and cross-check the Titan liquid-methane surface shader
# (Shaders/cr_methane.hlsl, Shaders/cr_methane.program, Materials/cr_methane.material),
# the approach of ISDF Chronicles' tools/surfacecheck.py:
#
#   - every HLSL delegate in cr_methane.program compiles for its own target with
#     its own defines (vs_4_0/ps_4_0 with SM4=1 for DX11, vs_3_0/ps_3_0 for DX9),
#     warnings as errors;
#   - every default_params entry of a unified program names a constant that EVERY
#     delegate keeps (Ogre reports a param for a stripped constant as an error and
#     drops the technique, silently in game);
#   - every constant a delegate keeps has a default or is set by the material
#     (it would otherwise read zero);
#   - every param_named in the material's passes is a constant its program keeps,
#     and every $variable the material uses is set.
#
# There is no GLSL twin by design (OpenGL falls through to the material's invisible
# technique). Run from the repository root:  .\Tools\Test-MethaneShader.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$programPath = Join-Path $root 'Shaders\cr_methane.program'
$materialPath = Join-Path $root 'Materials\cr_methane.material'
$shaderDir = Join-Path $root 'Shaders'

if (-not $FxcPath) {
    $cmd = Get-Command fxc.exe -ErrorAction SilentlyContinue
    if ($cmd) { $FxcPath = $cmd.Source }
}
if (-not $FxcPath) {
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path $kits) {
        $FxcPath = Get-ChildItem $kits -Filter fxc.exe -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
}
if (-not $FxcPath -or -not (Test-Path $FxcPath)) { throw 'fxc.exe was not found. Install a Windows SDK or pass -FxcPath.' }

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$message) { $failures.Add($message); Write-Host "FAIL $message" }

function Get-Blocks([string]$text, [string]$keyword) {
    $clean = ($text -replace '//[^\n]*', '') -replace "`r`n", "`n"
    $blocks = @{}
    foreach ($m in [regex]::Matches($clean, "(?m)^$keyword\s+(\S+)([^\n{]*)\s*\{")) {
        $depth = 0
        for ($j = $m.Index + $m.Length - 1; $j -lt $clean.Length; $j++) {
            if ($clean[$j] -eq '{') { $depth++ } elseif ($clean[$j] -eq '}') { $depth-- }
            if ($depth -eq 0) {
                $blocks[$m.Groups[1].Value] = @{ Lang = $m.Groups[2].Value.Trim(); Body = $clean.Substring($m.Index + $m.Length, $j - $m.Index - $m.Length) }
                break
            }
        }
    }
    return $blocks
}

function Get-Field([string]$body, [string]$key) {
    $m = [regex]::Match($body, "(?m)^\s*$key\s+(\S+)")
    if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}

$programText = Get-Content -Raw $programPath
$programs = @{}
foreach ($kind in 'vertex_program', 'fragment_program') {
    $blocks = Get-Blocks $programText $kind
    foreach ($name in $blocks.Keys) {
        $b = $blocks[$name]
        $programs[$name] = @{
            Stage = $kind; Lang = $b.Lang; Body = $b.Body
            Source = Get-Field $b.Body 'source'; Target = Get-Field $b.Body 'target'
            Entry = Get-Field $b.Body 'entry_point'; Defines = Get-Field $b.Body 'preprocessor_defines'
            Delegates = @([regex]::Matches($b.Body, '(?m)^\s*delegate\s+(\S+)') | ForEach-Object { $_.Groups[1].Value })
            Params = @([regex]::Matches($b.Body, '(?m)^\s*param_named(?:_auto)?\s+(\w+)') | ForEach-Object { $_.Groups[1].Value })
        }
    }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("cr_methane_check_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$kept = @{}
$samplers = 'rippleMap', 'wetMask'
try {
    foreach ($name in ($programs.Keys | Sort-Object)) {
        $p = $programs[$name]
        if ($p.Lang -ne 'hlsl') { continue }
        $listing = Join-Path $work "$name.asm"
        $args = @('/nologo', '/WX', '/T', $p.Target, '/E', $p.Entry, '/Fc', $listing, '/Fo', (Join-Path $work "$name.o"))
        if ($p.Defines) { foreach ($d in $p.Defines.Split(',')) { if ($d) { $args += @('/D', $d) } } }
        $args += (Join-Path $shaderDir $p.Source)
        $out = & $FxcPath @args 2>&1
        if ($LASTEXITCODE -ne 0) { Fail "$name ($($p.Target)) does not compile:`n$($out -join "`n")"; continue }
        $asm = Get-Content -Raw $listing
        $names = New-Object System.Collections.Generic.HashSet[string]
        if ($p.Target -like '*_4_0') {
            # cbuffer $Globals members: "//   float4 name;  // Offset: ..." (also float4x4, arrays).
            # A member the shader never reads is listed with an [unused] tag.
            foreach ($m in [regex]::Matches($asm, '(?m)^//\s+(?:float|float[234]|float4x4|int)\s+(\w+)(?:\[\d+\])?;.*$')) {
                if ($m.Value -notmatch '\[unused\]') { [void]$names.Add($m.Groups[1].Value) }
            }
        } else {
            # D3D9 constant table: "//   name   c12   1" / "//   name   s0   1"
            foreach ($m in [regex]::Matches($asm, '(?m)^//\s+(\w+)\s+[cs]\d+\s+\d+\s*$')) { [void]$names.Add($m.Groups[1].Value) }
        }
        $kept[$name] = $names
        Write-Host ("compiled {0,-30} {1}  {2} constants" -f $name, $p.Target, $names.Count)
    }

    $materialText = Get-Content -Raw $materialPath
    $vars = @{}
    foreach ($m in [regex]::Matches($materialText, '(?m)^\s*set\s+\$(\w+)\s+"([^"]*)"')) { $vars[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($m in [regex]::Matches(($materialText -replace '//[^\n]*', ''), '\$(\w+)')) {
        if (-not $vars.ContainsKey($m.Groups[1].Value)) { Fail "material uses `$$($m.Groups[1].Value) but never sets it" }
    }
    $materialParams = @{}
    foreach ($m in [regex]::Matches($materialText, '(?s)fragment_program_ref\s+(\S+)\s*\{(.*?)\}')) {
        $materialParams[$m.Groups[1].Value] = @([regex]::Matches($m.Groups[2].Value, '(?m)^\s*param_named\s+(\w+)') | ForEach-Object { $_.Groups[1].Value })
    }

    foreach ($name in ($programs.Keys | Sort-Object)) {
        $p = $programs[$name]
        if ($p.Lang -ne 'unified') { continue }
        if ($p.Delegates.Count -lt 2) { Fail "$name should delegate to an SM4 and an SM3 program" }
        foreach ($delegate in $p.Delegates) {
            if (-not $kept.ContainsKey($delegate)) { Fail "$name delegate $delegate was not compiled"; continue }
            foreach ($param in $p.Params) {
                if (-not $kept[$delegate].Contains($param)) { Fail "$name default_params names $param, which $delegate strips" }
            }
            $fromMaterial = @($materialParams[$name])
            foreach ($constant in $kept[$delegate]) {
                if ($samplers -contains $constant) { continue }
                if (($p.Params -notcontains $constant) -and ($fromMaterial -notcontains $constant)) {
                    Fail "$delegate keeps $constant but nothing sets it (it would read zero)"
                }
            }
        }
        foreach ($param in @($materialParams[$name])) {
            if ($param -and $p.Params -notcontains $param) { Fail "material sets $param, which $name does not declare" }
        }
    }
    foreach ($ref in [regex]::Matches($materialText, '(?m)^\s*(?:vertex|fragment)_program_ref\s+(CR_Methane\S*)')) {
        if (-not $programs.ContainsKey($ref.Groups[1].Value)) { Fail "material references undeclared program $($ref.Groups[1].Value)" }
    }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "METHANE SHADER FAILED ($($failures.Count))"
    exit 1
}
Write-Host 'METHANE SHADER OK'
