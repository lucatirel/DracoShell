# Keep the public edition free of excluded manufacturer artwork and private history.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Catalog = Get-Content (Join-Path $RepoRoot 'config/dragons.json') -Raw | ConvertFrom-Json
$Names = @($Catalog.presets.PSObject.Properties.Name | Sort-Object)
$Expected = @('armored', 'legacy-fx', 'legacy-v2', 'legacy-v3', 'lineart', 'public', 'subtle')
if ($Catalog.default -cne 'lineart' -or ($Names -join ',') -cne ($Expected -join ',')) {
    throw 'Unexpected public preset catalog'
}
if (Test-Path (Join-Path $RepoRoot 'docs/branch-snapshots.json')) { throw 'Private snapshot file published' }
if (Test-Path (Join-Path $RepoRoot 'scripts/Archive-VariantBranches.ps1')) { throw 'Private cleanup helper published' }
$ExcludedBlobs = @(
    'b309e15b17b26ea34a8d6691366d9b3348095f35',
    '57565dda9f546e8f80a3ca9da680621ce7230b2c',
    '4bf136b8115fdd05124642070112be85615d79b6',
    '97b36d777d79a6e3d2c6057ba4eec2cdde54a76e',
    'c55378f5e805c60daa8db2a6f33ccdb22f4979f9',
    '7af4978f9ce44f1c7761859d3b0a3f79737f92d3',
    'f5de9469cce2e9f460e78ddac89b2bf4ff4a9613',
    'c97b260f7f715849cb2320955dd6d5b712110f11',
    'b94903026ec2f8d16fa7ffeddcde97858b47d5ff'
)
$ExcludedCommits = @(
    'db7c618ead14aa3f58f595a455c5883a2269a394',
    'ca61cb4062f14ded95935ae768b0339d46cbe77b',
    '2e6c67d9c7ebed2ccbef06d6b759db766f74ba2a'
)
Push-Location $RepoRoot
try {
    $Files = @(git ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect public tracked files' }
    foreach ($File in $Files) {
        $Hash = git hash-object -- $File
        if ($LASTEXITCODE -ne 0 -or $Hash -in $ExcludedBlobs) { throw "Excluded artwork: $File" }
    }
    $Objects = @(git rev-list --objects HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect public history' }
    foreach ($Object in $Objects) {
        $Hash = ($Object -split ' ', 2)[0]
        if ($Hash -in $ExcludedBlobs -or $Hash -in $ExcludedCommits) { throw 'Excluded object in public history' }
    }
    Write-Host 'Seven public presets, excluded artwork and private-history boundary: PASS'
} finally { Pop-Location }

