#requires -Version 5.1
param([Parameter(Mandatory=$true)]
    [ValidatePattern('^https://paypal\.me/[A-Za-z0-9][A-Za-z0-9._-]{0,99}/?$')]
    [string]$PayPalMeUrl)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Draco.Setup.ps1')
Assert-DracoHost
$ReadmePath = Join-Path $RepoRoot 'README.md'
$Readme = [IO.File]::ReadAllText($ReadmePath)
$Pattern = '(?s)<!-- CREATOR-SUPPORT:START -->.*?<!-- CREATOR-SUPPORT:END -->'
if ([regex]::Matches($Readme, $Pattern).Count -ne 1) { throw 'README support block missing or duplicated.' }
$Block = @"
<!-- CREATOR-SUPPORT:START -->
[![Support via PayPal](https://img.shields.io/badge/Support-PayPal-0070ba?logo=paypal&logoColor=white)]($PayPalMeUrl)

If DRACO makes your terminal a better place to work, you can support its creator
via [PayPal]($PayPalMeUrl). Support is optional; the theme has no paid features.
<!-- CREATOR-SUPPORT:END -->
"@
$NewReadme = [regex]::Replace($Readme, $Pattern, [Text.RegularExpressions.MatchEvaluator]{ param($Match) $Block })
$Encoding = New-Object Text.UTF8Encoding($false)
Write-DracoAtomicText $ReadmePath $NewReadme $Encoding
Write-DracoAtomicText (Join-Path $RepoRoot '.github\FUNDING.yml') ("custom: ['$PayPalMeUrl']`n") $Encoding
Write-Host 'README PayPal button and GitHub Sponsor link configured locally. Review the diff before committing.' -ForegroundColor Green

