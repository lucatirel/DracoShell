# Shared installation helpers; no startup/per-key work uses this file.
function Assert-DracoHost {
    if ($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or
        $PSVersionTable.PSVersion -lt [version]'5.1') {
        throw 'Use Windows PowerShell 5.1: powershell.exe -NoProfile -File .\install.ps1'
    }
}

function ConvertFrom-DracoJson {
    param([Parameter(Mandatory=$true)][string]$Text)
    # Terminal accepts JSONC. Strip comments only outside strings, then trailing
    # commas only outside strings. URLs and quoted punctuation remain untouched.
    $Out = New-Object Text.StringBuilder
    $Quoted = $false; $Escaped = $false; $Line = $false; $Block = $false
    for ($Index = 0; $Index -lt $Text.Length; $Index++) {
        $Char = $Text[$Index]
        $Next = if ($Index + 1 -lt $Text.Length) { $Text[$Index + 1] } else { [char]0 }
        if ($Line) {
            if ($Char -eq "`n" -or $Char -eq "`r") { $Line = $false; [void]$Out.Append($Char) }
            continue
        }
        if ($Block) {
            if ($Char -eq '*' -and $Next -eq '/') { $Block = $false; $Index++ }
            elseif ($Char -eq "`n" -or $Char -eq "`r") { [void]$Out.Append($Char) }
            continue
        }
        if ($Quoted) {
            [void]$Out.Append($Char)
            if ($Escaped) { $Escaped = $false }
            elseif ($Char -eq '\') { $Escaped = $true }
            elseif ($Char -eq '"') { $Quoted = $false }
            continue
        }
        if ($Char -eq '"') { $Quoted = $true }
        elseif ($Char -eq '/' -and $Next -eq '/') { $Line = $true; $Index++; [void]$Out.Append(' '); continue }
        elseif ($Char -eq '/' -and $Next -eq '*') { $Block = $true; $Index++; [void]$Out.Append(' '); continue }
        [void]$Out.Append($Char)
    }
    if ($Block) { throw 'Unterminated JSON comment' }
    $Json = [regex]::Replace($Out.ToString(), '"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
        [Text.RegularExpressions.MatchEvaluator]{ param($Match)
            if ($Match.Value.StartsWith('"')) { $Match.Value } else { '' }
        })
    $Json | ConvertFrom-Json -ErrorAction Stop
}

function Resolve-DracoSettingsPath {
    param([string]$Requested, [string]$Recorded)
    if ($Requested) {
        $Full = [IO.Path]::GetFullPath($Requested)
        if (-not (Test-Path -LiteralPath $Full -PathType Leaf)) { throw "Settings file not found: $Full" }
        return $Full
    }
    if ($Recorded -and (Test-Path -LiteralPath $Recorded -PathType Leaf)) { return $Recorded }
    $Candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Assert-DracoRuntimePath {
    param([Parameter(Mandatory=$true)][string]$Root, [Parameter(Mandatory=$true)][string]$Path)
    $Base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $Current = [IO.Path]::GetFullPath($Path)
    if ($Current -ne $Base -and -not $Current.StartsWith($Base + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime path escaped the DRACO directory'
    }
    while ($Current.Length -ge $Base.Length) {
        if (Test-Path -LiteralPath $Current) {
            if (([IO.File]::GetAttributes($Current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing a linked DRACO runtime path: $Current"
            }
        }
        if ($Current -eq $Base) { break }
        $Current = Split-Path $Current -Parent
    }
}

function Write-DracoAtomicText {
    param([Parameter(Mandatory=$true)][string]$Path, [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory=$true)][Text.Encoding]$Encoding)
    $Temp = Join-Path (Split-Path $Path -Parent) ('.draco-write-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        if (Test-Path -LiteralPath $Path) {
            $Flags = [IO.File]::GetAttributes($Path)
            if (($Flags -band ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) {
                throw "Refusing a read-only or linked destination: $Path"
            }
        }
        [IO.File]::WriteAllText($Temp, $Text, $Encoding)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($Temp, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($Temp, $Path) }
    } finally { if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Force } }
}

function Get-DracoFontFaces {
    Add-Type -AssemblyName System.Drawing
    $Fonts = New-Object System.Drawing.Text.InstalledFontCollection
    try { @($Fonts.Families | ForEach-Object { $_.Name }) }
    finally { $Fonts.Dispose() }
}

function Install-DracoPackage {
    param([string]$Id, [switch]$UserScope)
    $Winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $Winget) { throw "Install App Installer (winget) or install $Id manually; see docs/DEPENDENCIES.md." }
    $PackageArgs = @('install', '--exact', '--id', $Id, '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($UserScope) { $PackageArgs += @('--scope', 'user') }
    & $Winget.Source @PackageArgs
    if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed: $Id (exit $LASTEXITCODE)" }
}

