# Safe local entrypoint for Manage-CampaignFiles.ps1 Workshop operations.
#
# GitHub Actions workflows live under .github/, while the legacy campaign
# publisher recursively scans the repository and flattens ordinary source files
# into the Workshop payload. Until .github is natively excluded by the manager,
# this wrapper temporarily moves that directory outside the repo while the
# manager runs, then restores it even if the child process fails.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PublisherArgs
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$manager = Join-Path $repoRoot "Manage-CampaignFiles.ps1"
$githubDir = Join-Path $repoRoot ".github"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "bzr-campaign-workshop-" + [guid]::NewGuid().ToString("N")
)
$tempGithub = Join-Path $tempRoot ".github"
$movedGithub = $false

if (-not (Test-Path -LiteralPath $manager)) {
    throw "Campaign publisher not found: $manager"
}

try {
    if (Test-Path -LiteralPath $githubDir) {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Move-Item -LiteralPath $githubDir -Destination $tempGithub
        $movedGithub = $true
    }

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $manager `
        @PublisherArgs

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Manage-CampaignFiles.ps1 exited with code $exitCode."
    }
}
finally {
    if ($movedGithub -and (Test-Path -LiteralPath $tempGithub)) {
        if (Test-Path -LiteralPath $githubDir) {
            Remove-Item -LiteralPath $githubDir -Recurse -Force
        }
        Move-Item -LiteralPath $tempGithub -Destination $githubDir
    }

    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
