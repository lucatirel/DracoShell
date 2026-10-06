# Real installer calls in disposable paths; no dependencies are installed.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'scripts\Draco.Setup.ps1')
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$SavedUser = $env:USERPROFILE; $SavedLocal = $env:LOCALAPPDATA; $SavedProfile = $PROFILE
try {
    $env:USERPROFILE = $Fixture
    $env:LOCALAPPDATA = Join-Path $Fixture 'AppData\Local'
    $script:PROFILE = Join-Path $Fixture 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    $SettingsDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal'
    New-Item $SettingsDir -ItemType Directory -Force | Out-Null
    New-Item (Split-Path $PROFILE -Parent) -ItemType Directory -Force | Out-Null
    $Settings = Join-Path $SettingsDir 'settings.json'
    [IO.File]::WriteAllText($PROFILE, '# unrelated user profile mentions .draco-terminal\draco-profile.ps1')
    $ProfileBefore = [IO.File]::ReadAllText($PROFILE)
    [IO.File]::WriteAllText($Settings, '{broken')
    $Rejected = $false
    try { & (Join-Path $RepoRoot 'install.ps1') -NoDependencyInstall -FontFace Consolas } catch { $Rejected = $true }
    if (-not $Rejected -or [IO.File]::ReadAllText($Settings) -cne '{broken' -or
        [IO.File]::ReadAllText($PROFILE) -cne $ProfileBefore -or
        (Test-Path (Join-Path $Fixture '.draco-terminal\draco-profile.ps1'))) { throw 'Invalid settings caused a partial installation' }
    [IO.File]::WriteAllText($Settings, '{"profiles":{"list":[]}}')
    $Rejected = $false
    try { & (Join-Path $RepoRoot 'install.ps1') -NoDependencyInstall -FontFace Consolas } catch { $Rejected = $true }
    if (-not $Rejected -or [IO.File]::ReadAllText($PROFILE) -cne $ProfileBefore) { throw 'Missing target profile caused a partial installation' }

    $Jsonc = @'
{
  // Real Terminal settings can contain comments and trailing commas.
  "profiles": { "list": [{"name":"Windows PowerShell","guid":"{61c54bbd-c2c6-5271-96e7-009a87ff44bf}","commandline":"powershell.exe -NoLogo -NoExit",}], },
  "schemes": [],
  "keybindings": [{"keys":"ctrl+shift+f10","command":"copy"},],
  "custom": "https://example.invalid/a//b/*keep*/?q=,}", /* strip */
}
'@
    [IO.File]::WriteAllText($Settings, $Jsonc)
    $Parsed = ConvertFrom-DracoJson $Jsonc
    if ($Parsed.custom -cne 'https://example.invalid/a//b/*keep*/?q=,}') { throw 'JSONC normalization corrupted a string' }
    if ((Resolve-DracoSettingsPath) -cne $Settings) { throw 'Unpackaged Terminal path not found' }
    function oh-my-posh { $global:LASTEXITCODE = 0; '31.4.1' }
    & (Join-Path $RepoRoot 'install.ps1') -NoDependencyInstall -FontFace Consolas
    $Installed = Get-Content $Settings -Raw | ConvertFrom-Json
    if ($Installed.custom -cne $Parsed.custom -or @($Installed.keybindings).Count -ne 1 -or
        $Installed.keybindings[0].command -ne 'copy') { throw 'Installer overwrote user data or a custom hotkey' }
    $StatePath = Join-Path $Fixture '.draco-terminal\install-state.json'
    $State = Get-Content $StatePath -Raw | ConvertFrom-Json
    if ($State.settingsPath -cne $Settings -or $State.noLogoAdded) { throw 'Installer lost chosen path or ownership of launch arguments' }
    $ConfigPath = Join-Path $Fixture '.draco-terminal\input-effects.json'
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $Dll = Join-Path $Fixture ('.draco-terminal\' + $Config.assembly)
    [IO.File]::WriteAllText($Dll, 'damaged cached assembly')
    & (Join-Path $RepoRoot 'install.ps1') -NoDependencyInstall -FontFace Consolas
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ([IO.File]::ReadAllBytes($Dll)[0] -ne 77 -or
        $Config.assemblyHash -ne (Get-FileHash $Dll -Algorithm SHA256).Hash) { throw 'Installer blessed a damaged cached DLL' }
    & (Join-Path $RepoRoot 'uninstall.ps1')
    $Clean = Get-Content $Settings -Raw | ConvertFrom-Json
    if ([IO.File]::ReadAllText($PROFILE).Trim() -cne $ProfileBefore) { throw 'Reset removed unrelated profile content' }
    if ($Clean.profiles.list[0].commandline -cne 'powershell.exe -NoLogo -NoExit' -or
        @($Clean.keybindings).Count -ne 1 -or $Clean.keybindings[0].command -ne 'copy') {
        throw 'Uninstall removed pre-existing launch options or a custom hotkey'
    }
    $Clean.profiles.list[0] | Add-Member -NotePropertyName font -NotePropertyValue ([PSCustomObject]@{face='Consolas'})
    [IO.File]::WriteAllText($Settings, ($Clean | ConvertTo-Json -Depth 100))
    & (Join-Path $RepoRoot 'uninstall.ps1')
    if ((Get-Content $Settings -Raw | ConvertFrom-Json).profiles.list[0].font.face -ne 'Consolas') { throw 'Repeated reset removed unrelated appearance' }

    # Fresh static setup needs no compiled input helper, and legacy action chords
    # must be preserved even when the modern keybindings collection is empty.
    $Clean = Get-Content $Settings -Raw | ConvertFrom-Json
    $Clean.keybindings = @()
    $Clean | Add-Member -NotePropertyName actions -NotePropertyValue @([PSCustomObject]@{keys='ctrl+shift+f10';command='copy'})
    [IO.File]::WriteAllText($Settings, ($Clean | ConvertTo-Json -Depth 100))
    & (Join-Path $RepoRoot 'install.ps1') -Static -NoDependencyInstall -FontFace Consolas
    if (@(Get-ChildItem (Join-Path $Fixture '.draco-terminal\draco-input-*.dll') -ErrorAction SilentlyContinue).Count -or
        @((Get-Content $Settings -Raw | ConvertFrom-Json).keybindings).Count) { throw 'Static install built a helper or overwrote a legacy chord' }
    & (Join-Path $RepoRoot 'uninstall.ps1')

    # Exercise funding edits only in a disposable miniature checkout.
    $SupportRepo = Join-Path $Fixture 'support-fixture'
    New-Item (Join-Path $SupportRepo 'scripts'), (Join-Path $SupportRepo '.github') -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'scripts\Set-CreatorSupport.ps1') (Join-Path $SupportRepo 'scripts')
    Copy-Item (Join-Path $RepoRoot 'scripts\Draco.Setup.ps1') (Join-Path $SupportRepo 'scripts')
    $SupportReadme = Join-Path $SupportRepo 'README.md'
    $SupportBefore = '<!-- CREATOR-SUPPORT:START -->community<!-- CREATOR-SUPPORT:END -->'
    [IO.File]::WriteAllText($SupportReadme, $SupportBefore)
    foreach ($InvalidUrl in @('http://paypal.me/test', 'https://paypal.me.evil.invalid/test', 'https://paypal.me/test?redirect=other')) {
        $Rejected = $false
        try { & (Join-Path $SupportRepo 'scripts\Set-CreatorSupport.ps1') -PayPalMeUrl $InvalidUrl } catch { $Rejected = $true }
        if (-not $Rejected -or [IO.File]::ReadAllText($SupportReadme) -cne $SupportBefore) { throw 'Unsafe funding URL changed files' }
    }
    & (Join-Path $SupportRepo 'scripts\Set-CreatorSupport.ps1') -PayPalMeUrl 'https://paypal.me/dracofixture'
    if ([IO.File]::ReadAllText($SupportReadme) -notmatch 'https://paypal.me/dracofixture' -or
        [IO.File]::ReadAllText((Join-Path $SupportRepo '.github\FUNDING.yml')) -cne "custom: ['https://paypal.me/dracofixture']`n") {
        throw 'Funding helper did not configure both reviewable files'
    }
    # A junction under the runtime must never redirect writes/deletes elsewhere.
    $Outside = Join-Path $Fixture 'outside'
    New-Item $Outside -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $Outside 'sentinel'), 'preserve')
    $AssetDir = Join-Path $Fixture '.draco-terminal\assets'
    Remove-Item $AssetDir -Recurse -Force
    New-Item -ItemType Junction -Path $AssetDir -Target $Outside | Out-Null
    $RejectedInstall = $false; $RejectedReset = $false
    try { & (Join-Path $RepoRoot 'install.ps1') -NoDependencyInstall -FontFace Consolas } catch { $RejectedInstall = $true }
    try { & (Join-Path $RepoRoot 'uninstall.ps1') } catch { $RejectedReset = $true }
    if (-not $RejectedInstall -or -not $RejectedReset -or
        [IO.File]::ReadAllText((Join-Path $Outside 'sentinel')) -cne 'preserve') { throw 'Runtime junction was followed' }
    # Delete the junction itself, not its target, before fixture cleanup.
    [IO.Directory]::Delete($AssetDir)
    Write-Host 'JSONC, early rejection, custom hotkeys, launch ownership, DLL rebuilding, unpackaged paths and junction rejection: PASS'
} finally {
    $env:USERPROFILE = $SavedUser; $env:LOCALAPPDATA = $SavedLocal; $script:PROFILE = $SavedProfile
    if (Test-Path $Fixture) { Remove-Item $Fixture -Recurse -Force }
}

