#requires -Version 5.1
param([switch]$Static, [switch]$NoTypingEffects, [switch]$NoDependencyInstall,
    [switch]$NoDragonMotion,
    [string]$SettingsPath, [string]$FontFace)
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== DRACO TERMINAL INSTALLER ===" -ForegroundColor Cyan

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $RepoRoot 'scripts\Draco.Setup.ps1')
Assert-DracoHost
$Root = Join-Path $env:USERPROFILE ".draco-terminal"
$Assets = Join-Path $Root "assets"
$Shaders = Join-Path $Root "shaders"
$BackupRoot = Join-Path $Root "backups"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$Backup = Join-Path $BackupRoot $Stamp

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$StatePath = Join-Path $Root 'install-state.json'
foreach ($Destination in @($Root, $Assets, $Shaders, $Backup, $StatePath)) {
    Assert-DracoRuntimePath $Root $Destination
}
$PreviousState = if (Test-Path -LiteralPath $StatePath) {
    Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
} else { $null }

# Verify bytes before changing settings. PNGs must never be transported as UTF-8.
$Manifest = Get-Content (Join-Path $RepoRoot "assets\manifest.json") -Raw | ConvertFrom-Json
$ExpectedAssets = @('assets/draco-cyber-blue.png', 'assets/draco-icon.png',
    'assets/draco-storm-atlas.png', 'assets/draco-flame-v1.png')
if (@($Manifest.files.PSObject.Properties).Count -ne $ExpectedAssets.Count) { throw 'Invalid asset manifest' }
foreach ($Entry in $Manifest.files.PSObject.Properties) {
    if ($Entry.Name -notin $ExpectedAssets -or $Entry.Value -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Invalid asset manifest entry'
    }
    $AssetPath = Join-Path $RepoRoot $Entry.Name
    if (-not (Test-Path $AssetPath) -or
        (Get-FileHash $AssetPath -Algorithm SHA256).Hash -ne $Entry.Value) {
        throw "DRACO asset is missing or damaged: $($Entry.Name). Run git pull again."
    }
}
Add-Type -AssemblyName System.Drawing
foreach ($AssetName in @("draco-cyber-blue.png", "draco-icon.png")) {
    $Bitmap = [System.Drawing.Bitmap]::FromFile((Join-Path $RepoRoot "assets\$AssetName"))
    try {
        if ($Bitmap.Width -ne $Bitmap.Height -or $Bitmap.Width -lt 128) {
            throw "Invalid DRACO image dimensions: $AssetName"
        }
    } finally { $Bitmap.Dispose() }
}
$Bitmap = [System.Drawing.Bitmap]::FromFile((Join-Path $RepoRoot "assets\draco-storm-atlas.png"))
try {
    if ($Bitmap.Width -ne 3072 -or $Bitmap.Height -ne 640) { throw "Invalid DRACO storm atlas dimensions" }
} finally { $Bitmap.Dispose() }

# Resolve and parse all active settings BEFORE installing or changing profiles.
$SettingsPath = Resolve-DracoSettingsPath $SettingsPath $PreviousState.settingsPath
if (-not $SettingsPath) {
    if ($NoDependencyInstall) { throw 'Windows Terminal settings not found; open Terminal once or pass -SettingsPath.' }
    Install-DracoPackage 'Microsoft.WindowsTerminal'
    throw 'Windows Terminal installed. Open it once to create settings, then rerun install.ps1.'
}
$SettingsBefore = [IO.File]::ReadAllText($SettingsPath)
$Settings = ConvertFrom-DracoJson $SettingsBefore
$TerminalProfile = @($Settings.profiles.list | Where-Object {
    $_.guid -eq '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}' -or
    $_.name -eq 'Windows PowerShell' -or
    ($_.commandline -and $_.commandline -match 'WindowsPowerShell.*powershell.exe')
}) | Select-Object -First 1
if (-not $TerminalProfile) { throw 'Windows PowerShell profile not found in Terminal; no active files changed.' }
foreach ($ActivePath in @($SettingsPath, $PROFILE, $StatePath)) {
    if (Test-Path -LiteralPath $ActivePath) {
        if (([IO.File]::GetAttributes($ActivePath) -band
            ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) {
            throw "Active file is read-only or linked: $ActivePath"
        }
    }
}
# Inject loader into the user's profile, idempotently.
$ProfileDir = Split-Path $PROFILE -Parent
$Existing = if (Test-Path $PROFILE) { Get-Content $PROFILE -Raw } else { "" }
$StartMarkers = [regex]::Matches($Existing, '(?m)^# >>> DRACO TERMINAL >>>\s*$').Count
$EndMarkers = [regex]::Matches($Existing, '(?m)^# <<< DRACO TERMINAL <<<\s*$').Count
if ($StartMarkers -ne $EndMarkers) { throw 'Incomplete DRACO profile markers; run CLEAN-RESET.cmd before reinstalling.' }
$Existing = [regex]::Replace($Existing, '(?ms)^# >>> DRACO TERMINAL >>>.*?^# <<< DRACO TERMINAL <<<[ \t]*\r?\n?', '')
$Loader = @'

# >>> DRACO TERMINAL >>>
. "$env:USERPROFILE\.draco-terminal\draco-profile.ps1"
# <<< DRACO TERMINAL <<<
'@
$ProfileOut = $Existing.TrimEnd() + "`r`n" + $Loader
$ProfileTokens = $null; $ProfileErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($ProfileOut, [ref]$ProfileTokens, [ref]$ProfileErrors) | Out-Null
if ($ProfileErrors.Count) { throw 'Existing PowerShell profile has parse errors; active files were not changed.' }


$ReadLine = Get-Module -ListAvailable PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
if (-not $ReadLine -or $ReadLine.Version -lt [version]'2.0') {
    throw 'PSReadLine 2.0+ required. Run: Install-Module PSReadLine -MinimumVersion 2.0 -Scope CurrentUser; then open a new tab.'
}
# Packaged Terminal versions can be checked directly; custom/portable paths are
# supported explicitly and require the owner to use Terminal 1.21 or newer.
$PackageName = if ($SettingsPath -match 'Microsoft.WindowsTerminalPreview_') {
    'Microsoft.WindowsTerminalPreview'
} elseif ($SettingsPath -match 'Microsoft.WindowsTerminal_') { 'Microsoft.WindowsTerminal' } else { $null }
if (-not $Static -and $PackageName -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
    $TerminalPackage = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($TerminalPackage -and [version]$TerminalPackage.Version -lt [version]'1.21') {
        throw 'Animated DRACO needs Terminal 1.21+. Update Terminal or use -Static; see docs/DEPENDENCIES.md.'
    }
}

# Never download and evaluate an installation script. Delegate package integrity
# and source selection to winget; use existing installations without upgrading.
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    if ($NoDependencyInstall) { throw 'Oh My Posh missing; install it or omit -NoDependencyInstall.' }
    Install-DracoPackage 'JanDeDobbeleer.OhMyPosh' -UserScope
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        throw 'Oh My Posh installed but PATH has not refreshed. Open a new tab and rerun the installer.'
    }
}
$PoshVersion = (oh-my-posh version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $PoshVersion -notmatch '^v?(\d+\.\d+\.\d+)') { throw 'Cannot verify Oh My Posh version.' }
if ([version]$Matches[1] -lt [version]'31.4.1') {
    throw 'Oh My Posh 31.4.1+ required; run: winget upgrade --exact --id JanDeDobbeleer.OhMyPosh --source winget'
}
$FontNames = @(Get-DracoFontFaces)
if (-not $FontFace) {
    $FontFace = @('MesloLGM Nerd Font', 'MesloLGM Nerd Font Mono', 'MesloLGM NF', 'MesloLGM NFM') |
        Where-Object { $_ -in $FontNames } | Select-Object -First 1
    if (-not $FontFace) {
        if ($NoDependencyInstall) { throw 'Meslo Nerd Font missing; install it or pass an installed -FontFace.' }
        oh-my-posh font install meslo
        if ($LASTEXITCODE -ne 0) { throw 'Meslo font installation failed; no active files changed.' }
        $FontNames = @(Get-DracoFontFaces)
        $FontFace = @('MesloLGM Nerd Font', 'MesloLGM Nerd Font Mono', 'MesloLGM NF', 'MesloLGM NFM') |
            Where-Object { $_ -in $FontNames } | Select-Object -First 1
        if (-not $FontFace) { throw 'Font not visible yet. Restart Terminal and rerun the installer.' }
    }
} elseif ($FontFace -notin $FontNames) { throw "Font is not installed: $FontFace" }

New-Item -ItemType Directory -Force -Path $Root, $Assets, $Shaders, $Backup, $ProfileDir | Out-Null
Copy-Item $SettingsPath (Join-Path $Backup "settings.json") -Force
if (Test-Path $PROFILE) { Copy-Item $PROFILE (Join-Path $Backup "Microsoft.PowerShell_profile.ps1") -Force }

foreach ($Name in @('draco.omp.json', 'draco-profile.ps1', 'draco-input.ps1', 'input-effects.json',
    'assets\draco-cyber-blue.png', 'assets\draco-icon.png')) {
    Assert-DracoRuntimePath $Root (Join-Path $Root $Name)
}
Copy-Item (Join-Path $RepoRoot "config\draco.omp.json") (Join-Path $Root "draco.omp.json") -Force
Copy-Item (Join-Path $RepoRoot "profile\draco-profile.ps1") (Join-Path $Root "draco-profile.ps1") -Force
Copy-Item (Join-Path $RepoRoot "assets\draco-cyber-blue.png") (Join-Path $Assets "draco-cyber-blue.png") -Force
Copy-Item (Join-Path $RepoRoot "assets\draco-icon.png") (Join-Path $Assets "draco-icon.png") -Force
$AtlasTag = (Get-FileHash (Join-Path $RepoRoot "assets\draco-storm-atlas.png") -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$AtlasFile = Join-Path $Assets "draco-storm-atlas-$AtlasTag.png"
Assert-DracoRuntimePath $Root $AtlasFile
Copy-Item (Join-Path $RepoRoot "assets\draco-storm-atlas.png") $AtlasFile -Force
# Compile the tiny pulse helper once at installation, not on every tab/key.
$InputSource = Join-Path $RepoRoot 'input\InputPulse.cs'
$InputTag = (Get-FileHash $InputSource -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
$InputAssembly = "draco-input-$InputTag.dll"
$InputAssemblyPath = Join-Path $Root $InputAssembly
if (-not $Static -and -not $NoTypingEffects) {
    # Rebuild from reviewed source on every install. Never bless a stale/corrupted
    # DLL merely by copying its current disk hash into the new trust configuration.
    $TempAssembly = Join-Path $Root ('draco-input-build-' + [Guid]::NewGuid().ToString('N') + '.dll')
    Assert-DracoRuntimePath $Root $InputAssemblyPath
    Add-Type -AssemblyName Microsoft.CSharp
    $Compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
    try {
        $Parameters = New-Object System.CodeDom.Compiler.CompilerParameters
        $Parameters.GenerateExecutable = $false
        $Parameters.GenerateInMemory = $false
        $Parameters.OutputAssembly = $TempAssembly
        $Parameters.CompilerOptions = '/optimize+'
        [void]$Parameters.ReferencedAssemblies.Add('System.dll')
        $Result = $Compiler.CompileAssemblyFromSource($Parameters, [IO.File]::ReadAllText($InputSource))
        if ($Result.Errors.HasErrors) { throw ($Result.Errors | Out-String) }
        Move-Item -LiteralPath $TempAssembly -Destination $InputAssemblyPath -Force
    } finally {
        $Compiler.Dispose()
        if (Test-Path -LiteralPath $TempAssembly) { Remove-Item -LiteralPath $TempAssembly -Force }
    }
}
Copy-Item (Join-Path $RepoRoot 'profile\draco-input.ps1') (Join-Path $Root 'draco-input.ps1') -Force
$InputConfig = @{ enabled = (-not $Static -and -not $NoTypingEffects); assembly = $InputAssembly;
    assemblyHash = if (Test-Path -LiteralPath $InputAssemblyPath) { (Get-FileHash $InputAssemblyPath -Algorithm SHA256).Hash } else { $null } }
Write-DracoAtomicText (Join-Path $Root 'input-effects.json') ($InputConfig | ConvertTo-Json) $Utf8NoBom
# A new filename forces Terminal to reload both the shader and image after updates.
$ShaderSource = [IO.File]::ReadAllText((Join-Path $RepoRoot "shaders\draco-storm.hlsl"))
if ($NoDragonMotion) {
    $ShaderSource = $ShaderSource.Replace('#define DRACO_MOTION 1.0f', '#define DRACO_MOTION 0.0f')
}
$ShaderHasher = [Security.Cryptography.SHA256]::Create()
try {
    $ShaderHash = $ShaderHasher.ComputeHash($Utf8NoBom.GetBytes($ShaderSource))
    $ShaderTag = ([BitConverter]::ToString($ShaderHash) -replace '-', '').Substring(0, 12).ToLowerInvariant()
} finally { $ShaderHasher.Dispose() }
$ShaderFile = Join-Path $Shaders "draco-storm-$ShaderTag.hlsl"
Assert-DracoRuntimePath $Root $ShaderFile
Write-DracoAtomicText $ShaderFile $ShaderSource $Utf8NoBom

# Windows PowerShell 5.1 likes a BOM for Unicode .ps1 files.
$ProfileText = [System.IO.File]::ReadAllText((Join-Path $Root "draco-profile.ps1"))
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText((Join-Path $Root "draco-profile.ps1"), $ProfileText, $Utf8Bom)


function Set-Prop {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
}

# Suppress the shell's banner/profile-load timing while still loading profiles.
# Preserve existing arguments and add the option immediately after the executable.
$OriginalCommand = [string]$TerminalProfile.commandline
$LaunchCommand = if ($TerminalProfile.commandline) { [string]$TerminalProfile.commandline }
    else { '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' }
if ($LaunchCommand -notmatch '(?i)(?:^|\s)-NoLogo(?:\s|$)') {
    $LaunchCommand = [regex]::Replace($LaunchCommand,
        '(?i)^(\s*(?:"[^"]*powershell(?:\.exe)?"|[^\s"]*powershell(?:\.exe)?))(?=\s|$)', '$1 -NoLogo')
}
$NoLogoAdded = $OriginalCommand -notmatch '(?i)(?:^|\s)-NoLogo(?:\s|$)' -and
    $LaunchCommand -match '(?i)(?:^|\s)-NoLogo(?:\s|$)'
if ($PreviousState -and $PreviousState.settingsPath -eq $SettingsPath) {
    $NoLogoAdded = [bool]$PreviousState.noLogoAdded
}
Set-Prop $TerminalProfile 'commandline' $LaunchCommand

$Scheme = [PSCustomObject]@{
    name = "DRACO Voidblue"
    background = "#050816"; foreground = "#C7D2FE"
    black = "#050816"; red = "#FF4D6D"; green = "#5EEAD4"; yellow = "#F8D57E"
    blue = "#4D7CFE"; purple = "#A78BFA"; cyan = "#4CC9F0"; white = "#DDE5FF"
    brightBlack = "#56627A"; brightRed = "#FF6B81"; brightGreen = "#7DF3D1"; brightYellow = "#FFE29A"
    brightBlue = "#70A0FF"; brightPurple = "#C084FC"; brightCyan = "#67E8F9"; brightWhite = "#F8FAFF"
    cursorColor = "#67E8F9"; selectionBackground = "#243B6B"
}
Set-Prop $Settings "schemes" (@($Settings.schemes | Where-Object { $_.name -ne "DRACO Voidblue" }) + $Scheme)

Set-Prop $TerminalProfile "font" ([PSCustomObject]@{ face=$FontFace; size=12; weight="normal" })
Set-Prop $TerminalProfile "colorScheme" "DRACO Voidblue"
Set-Prop $TerminalProfile "background" "#050816"
Set-Prop $TerminalProfile "foreground" "#C7D2FE"
Set-Prop $TerminalProfile "opacity" 100
Set-Prop $TerminalProfile "useAcrylic" $false
Set-Prop $TerminalProfile "cursorShape" "filledBox"
Set-Prop $TerminalProfile "cursorColor" "#67E8F9"
Set-Prop $TerminalProfile "padding" "10, 6, 10, 6"
# Override stale/inherited backgrounds which used to show unrelated artwork/text.
Set-Prop $TerminalProfile "backgroundImage" "none"
Set-Prop $TerminalProfile "backgroundImageOpacity" 0.30
Set-Prop $TerminalProfile "backgroundImageStretchMode" "uniform"
Set-Prop $TerminalProfile "backgroundImageAlignment" "right"
Set-Prop $TerminalProfile "icon" (Join-Path $Assets "draco-icon.png")
if ($Static) {
    Set-Prop $TerminalProfile "backgroundImage" (Join-Path $Assets "draco-cyber-blue.png")
    Set-Prop $TerminalProfile "experimental.pixelShaderPath" ""
    Set-Prop $TerminalProfile "experimental.pixelShaderImagePath" ""
} else {
    Set-Prop $TerminalProfile "experimental.pixelShaderPath" $ShaderFile
    Set-Prop $TerminalProfile "experimental.pixelShaderImagePath" $AtlasFile
}
Set-Prop $TerminalProfile "experimental.retroTerminalEffect" $false
# Remove appearance overrides left by older DRACO installs for unfocused panes.
if ($TerminalProfile.PSObject.Properties["unfocusedAppearance"] -and $null -ne $TerminalProfile.unfocusedAppearance) {
    foreach ($Name in @("backgroundImage", "backgroundImageOpacity", "backgroundImageStretchMode", "backgroundImageAlignment", "experimental.pixelShaderPath", "experimental.pixelShaderImagePath", "opacity", "useAcrylic")) {
        $TerminalProfile.unfocusedAppearance.PSObject.Properties.Remove($Name)
    }
}

# Windows Terminal console handoff (for example launching powershell.exe from a
# pinned taskbar/Start shortcut) matches the incoming command line against known
# profiles. The visible DRACO profile intentionally adds -NoLogo, so a plain
# powershell.exe handoff would otherwise fall back to profiles.defaults and lose
# the shader. Keep a hidden, appearance-identical profile with the stock command
# line solely for that handoff match. It never appears in the new-tab menu.
$HandoffGuid = '{d54b6c75-3f6d-4e32-b87f-41e5d37c0a9e}'
$HandoffProfile = ($TerminalProfile | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
Set-Prop $HandoffProfile 'guid' $HandoffGuid
Set-Prop $HandoffProfile 'name' 'DRACO Windows PowerShell Handoff'
Set-Prop $HandoffProfile 'commandline' '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe'
Set-Prop $HandoffProfile 'hidden' $true
if ($HandoffProfile.PSObject.Properties['source']) {
    $HandoffProfile.PSObject.Properties.Remove('source')
}
$Settings.profiles.list = @(
    @($Settings.profiles.list | Where-Object { $_.guid -ne $HandoffGuid }) + $HandoffProfile
)

if ($null -eq $Settings.keybindings) { Set-Prop $Settings "keybindings" @() }
# Keep user shortcuts. Install the toggle only when its chord is free.
$Bindings = @($Settings.keybindings | Where-Object {
    -not ($_.id -eq 'Terminal.ToggleShaderEffects' -and $_.keys -eq 'ctrl+shift+f10')
})
$ToggleAvailable = -not @(@($Bindings) + @($Settings.actions) | Where-Object { 'ctrl+shift+f10' -in @($_.keys) }).Count
if ($ToggleAvailable) { $Bindings += [PSCustomObject]@{ id='Terminal.ToggleShaderEffects'; keys='ctrl+shift+f10' } }
else { Write-Host 'Custom Ctrl+Shift+F10 binding preserved; use the Terminal command palette to toggle effects.' -ForegroundColor Yellow }
$Settings.keybindings = $Bindings

$SettingsOut = $Settings | ConvertTo-Json -Depth 100
if ([IO.File]::ReadAllText($SettingsPath) -cne $SettingsBefore) { throw 'Terminal settings changed during installation; rerun.' }
Write-DracoAtomicText $SettingsPath $SettingsOut $Utf8NoBom
try { Write-DracoAtomicText $PROFILE $ProfileOut $Utf8Bom }
catch {
    # Roll back our first active write without discarding concurrent user edits.
    if ([IO.File]::ReadAllText($SettingsPath) -ceq $SettingsOut) {
        Write-DracoAtomicText $SettingsPath $SettingsBefore $Utf8NoBom
    }
    throw
}
$InstallState = @{ settingsPath=$SettingsPath; noLogoAdded=$NoLogoAdded; fontFace=$FontFace }
Write-DracoAtomicText $StatePath ($InstallState | ConvertTo-Json) $Utf8NoBom

Write-Host ""
Write-Host "DRACO installed." -ForegroundColor Green
Write-Host "Open a NEW Windows PowerShell tab. Existing download tabs can stay open." -ForegroundColor Yellow
if ($Static) { Write-Host "Static mode: native dragon background, no animated shader." -ForegroundColor Cyan }
else { Write-Host "Ctrl+Shift+F10 toggles the animated shader. Eye is lit at timer zero; lightning repeats within 6 seconds." -ForegroundColor Cyan }
if (-not $Static -and -not $NoTypingEffects) { Write-Host "Green typing bolts enabled. Disable-DracoTypingEffects stops them in the current tab." -ForegroundColor Green }
Write-Host "Settings: $SettingsPath | Font: $FontFace" -ForegroundColor DarkGray
Write-Host "Backup: $Backup" -ForegroundColor DarkGray
