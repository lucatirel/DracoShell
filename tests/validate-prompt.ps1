param([Parameter(Mandatory=$true)][string]$Executable, [switch]$Isolated)
$ErrorActionPreference = "Stop"
if (-not $Isolated) {
    # Prompt initialization changes shell state. Keep it in a disposable PS 5.1 host,
    # also when a developer runs this test from their own interactive terminal.
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Executable $Executable -Isolated
    if ($LASTEXITCODE -ne 0) { throw "Isolated prompt validation failed" }
    return
}
$RepoRoot = Split-Path $PSScriptRoot -Parent
$FixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$Fixture = Join-Path $FixtureRoot "draco-prompt-fixture"
$SavedEncoding = [Console]::OutputEncoding
$SavedVenv = $env:VIRTUAL_ENV
$SavedConda = $env:CONDA_DEFAULT_ENV
$SavedUser = $env:USERPROFILE
$SavedPath = $env:PATH
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    New-Item $Fixture -ItemType Directory -Force | Out-Null
    git -C $Fixture init --initial-branch=draco-canonical-dev | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Prompt fixture git init failed" }
    git -C $Fixture -c user.name=DRACO -c user.email=draco@example.invalid commit --allow-empty -m fixture | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Prompt fixture git commit failed" }
    $env:VIRTUAL_ENV = Join-Path $Fixture ".venv"
    $ExpectedInput = [string][char]0x2570 + [char]0x2500 + [char]0x276F
    $env:CONDA_DEFAULT_ENV = ''
    foreach ($Width in @(40, 70, 90, 100, 120, 180)) {
        $Rendered = (& $Executable print primary --config (Join-Path $RepoRoot "config\draco.omp.json") --shell generic --pwd $Fixture --terminal-width $Width --plain | Out-String).TrimEnd()
        if ($LASTEXITCODE -ne 0 -or $Rendered -match 'error|invalid template') { throw "Prompt rendering failed at width $Width" }
        $Lines = @($Rendered -split '\r?\n')
        if ($Lines.Count -ne 2 -or $Lines[0] -notmatch [regex]::Escape(([Environment]::UserName).Substring(0, [Math]::Min(8, [Environment]::UserName.Length))) -or $Lines[1].Trim() -ne $ExpectedInput) {
            throw "Input did not start on its own second line at width $Width`: $Rendered"
        }
        # Nerd Font icons can occupy two cells; leave a small cell-width allowance.
        if ($Lines[0].Length -gt $Width-2) { throw "Prompt metadata too wide at $Width`: $Rendered" }
        if ($Lines[0] -notmatch 'PY \.venv') { throw "Active venv invisible at width $Width`: $Rendered" }
        if ($Width -ge 100 -and $Lines[0] -notmatch 'draco-canonical-dev') { throw "Git branch missing" }
        if ($Width -lt 100 -and $Lines[0] -match 'draco-canonical-dev') { throw "Narrow prompt did not compact" }
        if ($Width -ge 120 -and $Lines[0] -notmatch '\d{2}:\d{2}') { throw "Prompt clock missing" }
        if ($Width -lt 120 -and $Lines[0] -match '\d{2}:\d{2}') { throw "Narrow prompt clock was not hidden" }
    }
    $Transient = (& $Executable print transient --config (Join-Path $RepoRoot "config\draco.omp.json") --shell generic --plain | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $Transient -ne [string][char]0x276F) { throw "Transient prompt rendering failed" }
    Write-Host "Actual prompt at 40/70/90/100/120/180 columns with visible venv: PASS"

    # Load the real interactive profile and exercise its cached CLI boundary.
    # The repeated calls emulate blank Enter, without a changing history entry.
    $env:USERPROFILE = $FixtureRoot
    $Runtime = Join-Path $FixtureRoot '.draco-terminal'
    New-Item $Runtime -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'config\draco.omp.json') (Join-Path $Runtime 'draco.omp.json')
    $env:PATH = (Split-Path $Executable -Parent) + ';' + $env:PATH
    . (Join-Path $RepoRoot 'profile\draco-profile.ps1')
    $PoshModule = Get-Module -Name 'oh-my-posh-core'
    if (-not $PoshModule) { throw "Interactive prompt module did not initialize" }
    # Exercise the adapter AFTER real OMP initialization: OMP owns Enter here.
    # Stock-PSReadLine-only tests miss the actual user configuration.
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $RepoRoot 'input\InputPulse.cs')))
    . (Join-Path $RepoRoot 'profile\draco-input.ps1')
    $BeforeEnter = (Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Enter').Function
    if ($BeforeEnter -ne 'OhMyPoshEnterKeyHandler') { throw 'Real OMP Enter fixture missing' }
    $BeforeCancel = @(Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Ctrl+c') | ConvertTo-Json
    Enable-DracoTypingEffects
    $InputStatus = Get-DracoTypingStatus
    if ($InputStatus.EnterHandler -ne 'DracoSubmit' -or $InputStatus.SubmitBindings -lt 1 -or
        -not $script:DracoSubmitScripts.ContainsKey('Enter')) { throw 'OMP Enter never reached fire adapter' }
    if ((& $PoshModule { Test-Path Function:Set-PSReadLineKeyHandler })) { throw 'Temporary capture shim leaked' }
    Disable-DracoTypingEffects
    if ((Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Enter').Function -ne $BeforeEnter -or
        (@(Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Ctrl+c') | ConvertTo-Json) -cne $BeforeCancel) {
        throw 'OMP Enter or Ctrl+C behavior was not preserved'
    }
    Enable-DracoTypingEffects
    if ((Get-DracoTypingStatus).EnterHandler -ne 'DracoSubmit') { throw 'OMP Enter re-enable failed' }
    Disable-DracoTypingEffects
    Write-Host 'Real OMP Enter adapter, original handler restoration and untouched Ctrl+C: PASS'
    $ConfigPath = Join-Path $Runtime 'draco.omp.json'
    $PrimaryArgs = @('print','primary','--config',$ConfigPath,'--shell','generic','--pwd',$Fixture,'--terminal-width','100','--plain')
    $TransientArgs = @('print','transient','--config',$ConfigPath,'--shell','generic','--plain')
    & $PoshModule { $script:DracoRenderCache = @{}; $script:DracoRenderCalls = 0 }
    $First = & $PoshModule { param($a) Invoke-Utf8Posh $a } $PrimaryArgs
    $null = & $PoshModule { param($a) Invoke-Utf8Posh $a } $TransientArgs
    $Timer = [Diagnostics.Stopwatch]::StartNew()
    for ($Index = 0; $Index -lt 200; $Index++) {
        $Next = & $PoshModule { param($a) Invoke-Utf8Posh $a } $PrimaryArgs
        $null = & $PoshModule { param($a) Invoke-Utf8Posh $a } $TransientArgs
        if ($First -cne $Next) { throw "Repeated prompt changed unexpectedly" }
    }
    $Timer.Stop()
    $Calls = & $PoshModule { $script:DracoRenderCalls }
    # One extra primary refresh is legitimate if the test crosses a clock minute.
    if ($Calls -lt 2 -or $Calls -gt 3) { throw "Held Enter still launches render processes: $Calls" }
    if ($Timer.ElapsedMilliseconds -gt 4000) { throw "Cached prompt too slow" }
    Write-Host "Held-Enter renderer: 400 cached renders, $Calls initial CLI calls, $($Timer.ElapsedMilliseconds) ms: PASS"

    $null = prompt
    $Before = & $PoshModule { $script:DracoRenderCalls }
    $PromptTimer = [Diagnostics.Stopwatch]::StartNew()
    for ($Index = 0; $Index -lt 200; $Index++) { $null = prompt }
    $PromptTimer.Stop()
    $Additional = (& $PoshModule { $script:DracoRenderCalls }) - $Before
    if ($Additional -gt 1 -or $PromptTimer.ElapsedMilliseconds -gt 6000) { throw "Full prompt repeats still slow or launching CLI" }
    Write-Host "Full interactive prompt: 200 empty-history repeats, $Additional additional CLI calls, $($PromptTimer.ElapsedMilliseconds) ms: PASS"

    $env:VIRTUAL_ENV = Join-Path $Fixture '.env-analysis'
    $Activated = & $PoshModule { param($a) Invoke-Utf8Posh $a } $PrimaryArgs
    if ($Activated -notmatch 'PY \.env-analysis') { throw "Venv activation left stale cached metadata" }
    $env:VIRTUAL_ENV = ''; $env:CONDA_DEFAULT_ENV = 'ml'
    $Conda = & $PoshModule { param($a) Invoke-Utf8Posh $a } $PrimaryArgs
    if ($Conda -notmatch 'PY ml') { throw "Conda environment missing" }
    $env:CONDA_DEFAULT_ENV = ''
    $Deactivated = & $PoshModule { param($a) Invoke-Utf8Posh $a } $PrimaryArgs
    if ($Deactivated -match '\bPY\b') { throw "Deactivated environment still displayed" }
    $ChangedWidthArgs = @($PrimaryArgs); $ChangedWidthArgs[9] = '40'
    $Narrow = & $PoshModule { param($a) Invoke-Utf8Posh $a } $ChangedWidthArgs
    if ($Narrow -match 'draco-canonical-dev') { throw "Resize did not invalidate the cache" }
    Write-Host "Prompt cache activation/deactivation/conda/resize refresh: PASS"
} finally {
    [Console]::OutputEncoding = $SavedEncoding
    $env:VIRTUAL_ENV = $SavedVenv
    $env:CONDA_DEFAULT_ENV = $SavedConda
    $env:USERPROFILE = $SavedUser
    $env:PATH = $SavedPath
    if (Test-Path $FixtureRoot) { Remove-Item $FixtureRoot -Recurse -Force }
}

