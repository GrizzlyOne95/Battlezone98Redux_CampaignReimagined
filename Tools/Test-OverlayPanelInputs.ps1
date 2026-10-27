# Match CR_UI's selected DX11 vertex shader against Ogre Panel/BorderPanel
# geometry: POSITION0 + TEXCOORD0, with no vertex colour. Shader compilation
# alone cannot catch a material binding a valid shader to the wrong geometry.
[CmdletBinding()]
param([string]$MaterialPath, [string]$FxcPath, [switch]$VerifyRegression)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot
if (-not $MaterialPath) { $MaterialPath = Join-Path $repoRoot 'Materials/CR_ui.material' }
$material = [IO.File]::ReadAllText($MaterialPath)
$firstVertex = [regex]::Match($material, '\bvertex_program_ref\s+(\w+)')
if (-not $firstVertex.Success) { throw 'CR_UI has no vertex program' }
$vertexName = $firstVertex.Groups[1].Value
$declaration = $null
foreach ($program in Get-ChildItem (Join-Path $repoRoot 'Shaders') -Filter '*.program') {
    $match = [regex]::Match([IO.File]::ReadAllText($program.FullName),
        '(?s)\bvertex_program\s+' + [regex]::Escape($vertexName) + '\s+hlsl\s*\{(?<body>.*?)\}')
    if ($match.Success) { $declaration = $match.Groups['body'].Value; break }
}
if (-not $declaration) { throw "First CR_UI technique must bind an explicit DX11 HLSL program: $vertexName" }
$source = [regex]::Match($declaration, '\bsource\s+(\S+)').Groups[1].Value
$entry = [regex]::Match($declaration, '\bentry_point\s+(\w+)').Groups[1].Value
$target = [regex]::Match($declaration, '\btarget\s+(\w+)').Groups[1].Value
if (-not $FxcPath) {
    $FxcPath = Get-ChildItem (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin') -Filter fxc.exe -Recurse -File |
        Where-Object FullName -Match '\\x64\\' | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $FxcPath) { throw 'Windows SDK fxc.exe is required' }
$output = Join-Path ([IO.Path]::GetTempPath()) ('cr-panel-inputs-' + [guid]::NewGuid().ToString('N') + '.cso')
try {
    & $FxcPath /nologo /T $target /E $entry /Fo $output (Join-Path $repoRoot "Shaders/$source") | Out-Host
    if ($LASTEXITCODE) { throw "Panel vertex shader did not compile: $vertexName" }
    $dump = (& $FxcPath /nologo /dumpbin $output) -join "`n"
    if ($LASTEXITCODE) { throw 'Could not reflect panel shader' }
    $signature = [regex]::Match($dump, '(?s)Input signature:(?<input>.*?)Output signature:').Groups['input'].Value
    $inputs = @([regex]::Matches($signature, '(?m)^//\s+(?<semantic>\w+)\s+(?<index>\d+)\s+') |
        ForEach-Object { $_.Groups['semantic'].Value + $_.Groups['index'].Value })
    if ($inputs.Count -ne 2 -or @($inputs | Where-Object { $_ -notin @('POSITION0', 'TEXCOORD0') }).Count) {
        throw "CR_UI vertex inputs exceed Panel/BorderPanel geometry: $($inputs -join ', ')"
    }
    Write-Host "PASS: $vertexName inputs [$($inputs -join ', ')] fit Panel/BorderPanel geometry"
    if ($VerifyRegression) {
        $fixture = $output + '.material'
        try {
            [IO.File]::WriteAllText($fixture, $material.Replace($vertexName, 'CR_UI_vertexHLSL4'))
            $rejected = $false
            try { & $PSCommandPath -MaterialPath $fixture -FxcPath $FxcPath }
            catch {
                if ($_.Exception.Message -notlike '*vertex inputs exceed Panel/BorderPanel*') { throw }
                $rejected = $true
            }
            if (-not $rejected) { throw 'The COLOR0 shader regression was accepted' }
            Write-Host 'PASS: a valid UI shader requiring COLOR0 is rejected on panel geometry'
        } finally { Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue }
    }
} finally { Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue }
