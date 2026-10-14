$ErrorActionPreference = 'Stop'
$managerPath = Join-Path $PSScriptRoot '..\Manage-CampaignFiles.ps1'
$managerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $managerPath, [ref]$null, [ref]$null)
$guard = $managerAst.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Assert-NativeMissionText'
}, $true)
Invoke-Expression $guard.Extent.Text

$fixtureDir = Join-Path ([IO.Path]::GetTempPath()) ('CR-BznText-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($fixtureDir)
$script:fixturePath = Join-Path $fixtureDir 'fixture.bzn'
function Get-ManagedSourceFiles { Get-Item -LiteralPath $script:fixturePath }
try {
    $header = "version [1] =`r`n1030`r`nbinarySave [1] =`r`n"
    $cases = @(
        @{ Name = 'CRLF text'; Data = $header + "false`r`nTerrainName = test`r`n"; Reject = $false },
        @{ Name = 'LF text'; Data = ($header + "false`r`nTerrainName = test`r`n").Replace("`r`n", "`n"); Reject = $true },
        @{ Name = 'mixed text'; Data = $header + "false`r`nTerrainName = test`n"; Reject = $true },
        @{ Name = 'binary payload'; Data = $header + "true`r`n" + [char]0 + [char]10 + [char]255; Reject = $false }
    )
    foreach ($case in $cases) {
        [IO.File]::WriteAllBytes($script:fixturePath, [Text.Encoding]::Latin1.GetBytes($case.Data))
        $rejected = $false
        try { Assert-NativeMissionText } catch { $rejected = $true }
        if ($rejected -ne $case.Reject) { throw "Wrong BZN format verdict: $($case.Name)" }
        Write-Output "$($case.Name): pass"
    }
} finally {
    Remove-Item -LiteralPath $script:fixturePath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixtureDir
}
