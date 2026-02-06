param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Move", "Link", "Clean", "Build")]
    [string]$Mode = "Link"
)

$SourceDir = "$PSScriptRoot\_Source"
$ReleaseDir = "$PSScriptRoot\_Release"

# Support function to create directory if not exists
function New-ModDirectory {
    param ($Path)
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

# --- MODE: MOVE (One-time migration helper) ---
function Move-Files {
    Write-Host "Moving files to _Source structure..." -ForegroundColor Cyan
    
    New-ModDirectory "$SourceDir\Scripts"
    New-ModDirectory "$SourceDir\ODF"
    New-ModDirectory "$SourceDir\Maps"
    New-ModDirectory "$SourceDir\Text"
    New-ModDirectory "$SourceDir\Bin"
    New-ModDirectory "$SourceDir\Assets"
    New-ModDirectory "$SourceDir\Config"
    
    # Define file type mappings
    $mappings = @{
        "*.lua" = "Scripts"
        "*.odf" = "ODF"
        "*.bzn" = "Maps"
        "*.txt" = "Text"
        "*.dll" = "Bin"
        "*.pdb" = "Bin"
        "*.jpg" = "Assets"
        "*.tga" = "Assets" # Just in case
        "*.bmp" = "Assets" # Just in case
        "*.ini" = "Config"
        "*.csv" = "Config"
    }

    # Files to ignore/keep in root
    $excludes = @("manage_mod.ps1", "README.md", "task.md", "implementation_plan.md", "LICENSE", ".gitignore", ".gitmodules", ".git")
    
    # Get all files in root that are NOT in _Source or _Release and NOT excluded
    $files = Get-ChildItem -Path $PSScriptRoot -File | Where-Object { 
        $_.FullName -notlike "$SourceDir*" -and 
        $_.FullName -notlike "$ReleaseDir*" -and 
        $_.Name -notin $excludes 
    }

    foreach ($file in $files) {
        $destSub = $null
        foreach ($pattern in $mappings.Keys) {
            if ($file.Name -like $pattern) {
                $destSub = $mappings[$pattern]
                break
            }
        }
        
        if ($destSub) {
            $destPath = Join-Path "$SourceDir\$destSub" $file.Name
            Write-Host "Moving $($file.Name) to $destSub..."
            Move-Item -Path $file.FullName -Destination $destPath -Force
        }
        else {
            Write-Warning "Skipping $($file.Name) - No mapping defined."
        }
    }
    Write-Host "Move complete." -ForegroundColor Green
}

# --- MODE: LINK (Dev Setup) ---
function Update-Symlinks {
    Write-Host "Updating Symlinks in Root..." -ForegroundColor Cyan
    
    # Find all files in _Source (recursive)
    $files = Get-ChildItem -Path $SourceDir -Recurse -File
    
    foreach ($file in $files) {
        $targetName = $file.Name 
        $linkPath = Join-Path $PSScriptRoot $targetName
        
        if (Test-Path $linkPath) {
            # Check if it is already a link (Symlink or HardLink)
            # HardLinks are harder to distinguish from normal files in PS without checking inode, 
            # but for our purpose, if it exists, we assume it's fine or we skip.
            # However, if it's a "broken" file or we want to ensure it matches, we might need more checks.
            # For now, simple existence check.
            $attributes = (Get-Item $linkPath).Attributes
            if ($attributes -match "ReparsePoint") {
                # It's a symlink
                continue
            }
            
            # If it's a hardlink, it just looks like a file. 
            # We'll skip existing files to prevent overwriting "real" files if something went wrong, 
            # unless the user runs with a Force flag? For now, safer to warn and skip.
            Write-Warning "File $targetName exists in root. Skipping."
            continue
        }
        
        Write-Host "Linking $targetName"
        try {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $file.FullName -ErrorAction Stop | Out-Null
        }
        catch {
            try {
                # Fallback to HardLink
                New-Item -ItemType HardLink -Path $linkPath -Target $file.FullName -ErrorAction Stop | Out-Null
                Write-Host "  -> Created HardLink (Symlink failed)" -ForegroundColor Gray
            }
            catch {
                Write-Error "Failed to link $targetName. Error: $_"
            }
        }
    }
    Write-Host "Links updated." -ForegroundColor Green
}

# --- MODE: CLEAN (Cleanup) ---
function Clear-ModLinks {
    Write-Host "Cleaning Symlinks/HardLinks from Root..." -ForegroundColor Cyan
    
    # Iterate through _Source to find what should be cleaned
    $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File
    
    foreach ($srcFile in $sourceFiles) {
        $targetName = $srcFile.Name
        $targetPath = Join-Path $PSScriptRoot $targetName
        
        if (Test-Path $targetPath) {
            # Check if it's a directory? No, we only linked files.
            # We can verify it's the same file, but for "Clean", if it exists in Source, 
            # we assume the Root one is a link/copy we want to remove to clean the view.
            Write-Host "Removing: $targetName"
            Remove-Item -Path $targetPath -Force
        }
    }
    Write-Host "Clean complete." -ForegroundColor Green
}

# --- MODE: BUILD (Workshop Release) ---
function Build-Release {
    Write-Host "Building Release to _Release directory..." -ForegroundColor Cyan
    
    if (Test-Path $ReleaseDir) {
        Remove-Item -Path $ReleaseDir -Recurse -Force
    }
    New-ModDirectory $ReleaseDir
    
    # Copy all files from _Source flattened to _Release
    $files = Get-ChildItem -Path $SourceDir -Recurse -File
    
    foreach ($file in $files) {
        $destPath = Join-Path $ReleaseDir $file.Name
        if (Test-Path $destPath) {
            Write-Warning "Conflict detected for $($file.Name). Overwriting."
        }
        Copy-Item -Path $file.FullName -Destination $destPath
    }
    
    # Also copy root files like LICENSE if needed, usually just Source content is enough for mod logic.
    # If there are assets in root that weren't moved (unmapped), you might have missed them.
    
    Write-Host "Release build created at $ReleaseDir" -ForegroundColor Green
}

# --- EXECUTION ---
switch ($Mode) {
    "Move" { Move-Files }
    "Link" { Update-Symlinks }
    "Clean" { Clear-ModLinks }
    "Build" { Build-Release }
    Default { Write-Error "Invalid mode selected." }
}
