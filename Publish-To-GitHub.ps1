# Read-only publishing preflight. See docs/PUBLISHING.md for release steps.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $RepoRoot
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Install Git first.' }
    $Top = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Run from an existing DRACO Git checkout.' }
    if ([IO.Path]::GetFullPath($Top).TrimEnd('\', '/') -ne [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')) {
        throw 'DRACO must be the repository root, not a folder in another repository.'
    }
    $Origin = git remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $Origin -notmatch '^(https://github\.com/|git@github\.com:)lucatirel/DracoShell(?:\.git)?$') {
        throw 'Unexpected origin. Expected lucatirel/DracoShell.'
    }
    $Dirty = git status --porcelain --untracked-files=normal
    if ($LASTEXITCODE -ne 0 -or $Dirty) { throw 'Review and commit local changes before release preparation.' }
    Write-Host 'Clean DRACO checkout. No files staged, branches renamed or changes published.' -ForegroundColor Green
    Write-Host 'Complete the artwork/history review and release steps in docs/PUBLISHING.md.' -ForegroundColor Yellow
} finally { Pop-Location }

