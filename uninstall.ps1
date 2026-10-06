#requires -Version 5.1
param([string]$SettingsPath)
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== DRACO CLEAN RESET ===" -ForegroundColor Cyan

if (Get-Command Disable-DracoTypingEffects -CommandType Function -ErrorAction SilentlyContinue) {
    Disable-DracoTypingEffects
} elseif ('Draco.InputPulse' -as [type]) { [Draco.InputPulse]::Stop() }
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $RepoRoot 'scripts\Draco.Setup.ps1')
Assert-DracoHost
$Root = Join-Path $env:USERPROFILE ".draco-terminal"
$StatePath = Join-Path $Root 'install-state.json'
foreach ($Path in @($Root, $StatePath, (Join-Path $Root 'assets'), (Join-Path $Root 'shaders'), (Join-Path $Root 'emergency-backups'))) {
    Assert-DracoRuntimePath $Root $Path
}
$InstallState = if (Test-Path -LiteralPath $StatePath) { Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json } else { $null }
$Emergency = Join-Path $Root "emergency-backups"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$ThisBackup = Join-Path $Emergency $Stamp
Assert-DracoRuntimePath $Root $ThisBackup
New-Item -ItemType Directory -Force -Path $ThisBackup | Out-Null

$SettingsPath = Resolve-DracoSettingsPath $SettingsPath $InstallState.settingsPath
if (Test-Path -LiteralPath $PROFILE) {
    if (([IO.File]::GetAttributes($PROFILE) -band
        ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) {
        throw 'PowerShell profile is read-only or linked; no active files changed.'
    }
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom   = New-Object System.Text.UTF8Encoding($true)

function Remove-Prop {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        $Object.PSObject.Properties.Remove($Name)
    }
}

# ------------------------------------------------------------------
# 1. WINDOWS TERMINAL: remove ONLY DRACO changes.
#    If settings.json is damaged, quarantine it so Terminal can rebuild.
# ------------------------------------------------------------------
if ($SettingsPath) {
    Copy-Item $SettingsPath (Join-Path $ThisBackup "settings.before-clean.json") -Force
    $SettingsJson = Get-Content $SettingsPath -Raw
    try {
        $Settings = ConvertFrom-DracoJson $SettingsJson

        $TerminalProfile = @(
            $Settings.profiles.list | Where-Object {
                $_.guid -eq "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}" -or
                $_.name -eq "Windows PowerShell" -or
                ($_.commandline -and $_.commandline -match "WindowsPowerShell.*powershell.exe")
            }
        )[0]

        $IsDracoProfile = $TerminalProfile -and (
            $TerminalProfile.colorScheme -eq 'DRACO Voidblue' -or
            $TerminalProfile.'experimental.pixelShaderPath' -like (Join-Path $Root 'shaders\*') -or
            $TerminalProfile.icon -eq (Join-Path $Root 'assets\draco-icon.png'))
        if ($IsDracoProfile) {
            @(
                "experimental.pixelShaderPath",
                "experimental.pixelShaderImagePath",
                "experimental.retroTerminalEffect",
                "backgroundImage",
                "backgroundImageOpacity",
                "backgroundImageStretchMode",
                "backgroundImageAlignment",
                "icon",
                "font",
                "colorScheme",
                "background",
                "foreground",
                "opacity",
                "useAcrylic",
                "cursorShape",
                "cursorColor",
                "padding",
                "tabColor"
            ) | ForEach-Object { Remove-Prop $TerminalProfile $_ }

            if ($TerminalProfile.PSObject.Properties["commandline"] -and
                $TerminalProfile.commandline -match "-NoLogo" -and
                ((-not $InstallState) -or ($InstallState.settingsPath -eq $SettingsPath -and $InstallState.noLogoAdded))) {
                $TerminalProfile.commandline = [regex]::Replace(
                    $TerminalProfile.commandline, '(?i)\s-NoLogo(?=\s|$)', '')
            }
        }

        # Remove the hidden first-window handoff profile created by DRACO.
        if ($Settings.profiles -and $Settings.profiles.PSObject.Properties['list']) {
            $Settings.profiles.list = @(
                $Settings.profiles.list | Where-Object {
                    $_.guid -ne '{d54b6c75-3f6d-4e32-b87f-41e5d37c0a9e}'
                }
            )
        }

        if ($Settings.PSObject.Properties["schemes"]) {
            $Settings.schemes = @(
                $Settings.schemes | Where-Object { $_.name -ne "DRACO Voidblue" }
            )
        }

        if ($Settings.PSObject.Properties["keybindings"]) {
            $Settings.keybindings = @(
                $Settings.keybindings | Where-Object {
                    -not (
                        ($_.id -eq 'Terminal.ToggleShaderEffects' -and $_.keys -eq 'ctrl+shift+f10')
                    )
                }
            )
        }

        Write-DracoAtomicText $SettingsPath ($Settings | ConvertTo-Json -Depth 100) $Utf8NoBom

        Write-Host "Windows Terminal: DRACO settings removed." -ForegroundColor Green
    }
    catch {
        # Quarantine malformed JSON only. A permissions/write failure must never
        # move a valid settings file or cause Terminal to regenerate all settings.
        $InvalidJson = $false
        try { ConvertFrom-DracoJson $SettingsJson | Out-Null }
        catch { $InvalidJson = $true }
        if (-not $InvalidJson) { throw }
        $Broken = Join-Path (Split-Path $SettingsPath -Parent) ("settings.DRACO-BROKEN-" + $Stamp + ".json")
        Move-Item $SettingsPath $Broken -Force
        Write-Host "settings.json was invalid and has been quarantined:" -ForegroundColor Yellow
        Write-Host $Broken -ForegroundColor DarkYellow
        Write-Host "Windows Terminal will regenerate clean settings." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------
# 2. POWERSHELL PROFILE: remove DRACO loader, preserve anything else.
# ------------------------------------------------------------------
if (Test-Path $PROFILE) {
    Copy-Item $PROFILE (Join-Path $ThisBackup "Microsoft.PowerShell_profile.before-clean.ps1") -Force

    $Text = Get-Content $PROFILE -Raw
    $Text = [regex]::Replace(
        $Text,
        '(?ms)^\s*# >>> DRACO TERMINAL >>>.*?^\s*# <<< DRACO TERMINAL <<<\s*',
        ''
    )

    # Remove orphaned loader lines even if the marker block was malformed or partially removed.
    $Lines = $Text -split "\r?\n"
    $Lines = @($Lines | Where-Object {
        $_ -notmatch '^\s*\.\s+["''](?:\$env:USERPROFILE|\$HOME|[A-Za-z]:[^"'']*)\\\.draco-terminal\\draco-profile\.ps1["'']\s*;?\s*(?:#.*)?$' -and
        $_ -notmatch '^\s*#\s*(>>>|<<<)\s*DRACO TERMINAL'
    })
    $Text = ($Lines -join "`r`n").Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Remove-Item $PROFILE -Force
        Write-Host "PowerShell profile: empty DRACO-only profile removed." -ForegroundColor Green
    }
    else {
        Write-DracoAtomicText $PROFILE ($Text + "`r`n") $Utf8Bom
        Write-Host "PowerShell profile: DRACO loader removed." -ForegroundColor Green
    }
}

# ------------------------------------------------------------------
# 3. RUNTIME FILES: remove executable startup/input state.
#    Terminal reloads settings asynchronously. Keep inert PNG/HLSL cache files
#    at their original paths so existing renderers never reload a missing file.
#    No profile references them after reset; backups remain recoverable.
# ------------------------------------------------------------------
$ActiveFiles = @(
    (Join-Path $Root "draco.omp.json"),
    (Join-Path $Root "draco-profile.ps1"),
    (Join-Path $Root "draco-input.ps1"),
    (Join-Path $Root "input-effects.json"),
    $StatePath
)
$ActiveFiles += @(Get-ChildItem (Join-Path $Root "draco-input-*.dll") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)

foreach ($File in $ActiveFiles) {
    if (Test-Path -LiteralPath $File) {
        Assert-DracoRuntimePath $Root $File
        Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "CLEAN RESET COMPLETE." -ForegroundColor Green
Write-Host "Backup saved to: $ThisBackup" -ForegroundColor DarkGray
Write-Host "Graphics cache kept for safe Terminal reload (inactive)." -ForegroundColor DarkGray
Write-Host "Close ALL Windows Terminal windows, then reopen PowerShell to verify the clean state." -ForegroundColor Yellow
