# Real installs in a disposable user profile: validate pack pairing and transitions.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'tests/validate.ps1') -SkipInstaller
. (Join-Path $RepoRoot 'scripts/Draco.Presets.ps1')
$Catalog = Get-Content (Join-Path $RepoRoot 'config/dragons.json') -Raw | ConvertFrom-Json
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$SavedUser = $env:USERPROFILE; $SavedLocal = $env:LOCALAPPDATA; $SavedProfile = $PROFILE
try {
    $env:USERPROFILE = $Fixture
    $env:LOCALAPPDATA = Join-Path $Fixture 'AppData/Local'
    $script:PROFILE = Join-Path $Fixture 'Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1'
    $Settings = Join-Path $Fixture 'settings.json'
    New-Item $Fixture -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllText($Settings, '{"profiles":{"list":[{"name":"Windows PowerShell","commandline":"powershell.exe -NoExit"}]},"schemes":[],"custom":"preserve"}')
    function oh-my-posh { $global:LASTEXITCODE = 0; '31.4.1' }
    foreach ($Name in $Catalog.presets.PSObject.Properties.Name) {
        $Preset = Get-DracoPreset $RepoRoot $Name
        Assert-DracoPresetAssets $Preset
        [DracoShaderValidator]::Validate((Get-DracoPresetShader $Preset))
        [DracoShaderValidator]::Validate((Get-DracoPresetShader $Preset -NoDragonMotion))
        & (Join-Path $RepoRoot 'install.ps1') -Dragon $Name -SettingsPath $Settings -NoDependencyInstall -FontFace Consolas
        $State = Get-Content (Join-Path $Fixture '.draco-terminal/install-state.json') -Raw | ConvertFrom-Json
        $Config = Get-Content (Join-Path $Fixture '.draco-terminal/input-effects.json') -Raw | ConvertFrom-Json
        $Active = Get-Content $Settings -Raw | ConvertFrom-Json
        $ActiveTerminalProfile = $Active.profiles.list[0]
        if ($State.dragon -cne $Name -or $Active.custom -cne 'preserve' -or
            $Config.enabled -ne $Preset.inputEffects -or $Config.flight -ne $Preset.flight) { throw "Wrong preset state: $Name" }
        if ((Get-FileHash $ActiveTerminalProfile.'experimental.pixelShaderImagePath').Hash -ne (Get-FileHash $Preset.imagePath).Hash -or
            (Get-FileHash $ActiveTerminalProfile.'experimental.pixelShaderPath').Hash -ne (Get-FileHash $Preset.shaderPath).Hash -or
            (Get-FileHash $ActiveTerminalProfile.icon).Hash -ne (Get-FileHash $Preset.iconPath).Hash) { throw "Mismatched preset pack: $Name" }
        $OriginalShaderPath = $ActiveTerminalProfile.'experimental.pixelShaderPath'
        & (Join-Path $RepoRoot 'install.ps1') -Dragon $Name -NoDragonMotion -SettingsPath $Settings -NoDependencyInstall -FontFace Consolas
        $NoMotion = (Get-Content $Settings -Raw | ConvertFrom-Json).profiles.list[0]
        if ($Preset.motion -and $OriginalShaderPath -ceq $NoMotion.'experimental.pixelShaderPath') { throw "Shader was not reloaded: $Name" }
        if ((Get-Content (Join-Path $Fixture '.draco-terminal/input-effects.json') -Raw | ConvertFrom-Json).flight) { throw 'Motion opt-out retained flight' }
        & (Join-Path $RepoRoot 'install.ps1') -Dragon $Name -Static -SettingsPath $Settings -NoDependencyInstall -FontFace Consolas
        $StaticProfile = (Get-Content $Settings -Raw | ConvertFrom-Json).profiles.list[0]
        if ($StaticProfile.'experimental.pixelShaderPath' -ne '' -or
            (Get-FileHash $StaticProfile.backgroundImage).Hash -ne (Get-FileHash $Preset.staticImagePath).Hash -or
            (Get-Content (Join-Path $Fixture '.draco-terminal/input-effects.json') -Raw | ConvertFrom-Json).enabled) { throw "Wrong static pack: $Name" }
    }
    # A bare install must return from the last variant to the exact lineart pack.
    & (Join-Path $RepoRoot 'install.ps1') -SettingsPath $Settings -NoDependencyInstall -FontFace Consolas
    $Default = (Get-Content $Settings -Raw | ConvertFrom-Json).profiles.list[0]
    if ((Get-FileHash $Default.'experimental.pixelShaderPath').Hash -ne
        (Get-FileHash (Join-Path $RepoRoot 'shaders/draco-storm.hlsl')).Hash -or
        (Get-Content (Join-Path $Fixture '.draco-terminal/install-state.json') -Raw | ConvertFrom-Json).dragon -cne 'lineart') { throw 'Default lineart pack changed' }
    $Before = [IO.File]::ReadAllText($Settings)
    $Rejected = $false
    try { & (Join-Path $RepoRoot 'install.ps1') -Dragon '../unknown' -SettingsPath $Settings -NoDependencyInstall -FontFace Consolas }
    catch { $Rejected = $true }
    if (-not $Rejected -or [IO.File]::ReadAllText($Settings) -cne $Before) { throw 'Unknown preset changed active settings' }
    # Hash and traversal rejection are exercised on a disposable graphics pack.
    $Pack = Join-Path $Fixture 'damaged-pack'
    New-Item (Join-Path $Pack 'assets') -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'assets/*') (Join-Path $Pack 'assets') -Recurse
    $Damaged = Get-DracoPreset $RepoRoot 'lineart'
    $Damaged.directory = $Pack; $Damaged.manifestPath = Join-Path $Pack 'assets/manifest.json'
    [IO.File]::WriteAllText((Join-Path $Pack 'assets/draco-cyber-blue.png'), 'damaged')
    $Rejected = $false
    try { Assert-DracoPresetAssets $Damaged } catch { $Rejected = $true }
    if (-not $Rejected) { throw 'Damaged graphics pack accepted' }
    $Rejected = $false
    try { Resolve-DracoPresetPath $RepoRoot '../branch-snapshots.json' } catch { $Rejected = $true }
    if (-not $Rejected) { throw 'Preset path traversal accepted' }
    & (Join-Path $RepoRoot 'uninstall.ps1')
    if (@((Get-Content $Settings -Raw | ConvertFrom-Json).profiles.list).Count -ne 1 -or
        (Test-Path (Join-Path $Fixture '.draco-terminal/input-effects.json'))) { throw 'Reset left preset runtime active' }
    Write-Host 'All seven public packs, motion/static transitions, lineart default and rejection checks: PASS'
} finally {
    $env:USERPROFILE = $SavedUser; $env:LOCALAPPDATA = $SavedLocal; $script:PROFILE = $SavedProfile
    if (Test-Path $Fixture) { Remove-Item $Fixture -Recurse -Force }
}

