# PSReadLine already receives the key to perform normal editing. The adapter
# forwards its opaque arguments unchanged to SelfInsert. Only Click(), with NO
# arguments, reaches the effects component: never inspect KeyChar or the line.
function Get-DracoPoshSubmitHandler {
    $Posh = Get-Module -Name 'oh-my-posh-core'
    if (-not $Posh) { return }
    # PSReadLine exposes the handler's name, not its scriptblock. Ask OMP's
    # existing factory for its own handler, temporarily capturing registration.
    # No bindings are written during capture, including Ctrl+C/user shortcuts.
    $Capture = @{ Original = $null }
    & $Posh {
        param($Capture)
        if (Test-Path Function:Set-PSReadLineKeyHandler) { return }
        $script:DracoSubmitCapture = $Capture
        function script:Set-PSReadLineKeyHandler {
            param($Key, $BriefDescription, $ScriptBlock, $ViMode)
            if ($BriefDescription -eq 'OhMyPoshEnterKeyHandler') {
                $script:DracoSubmitCapture.Original = $ScriptBlock
            }
        }
        try { Enable-KeyHandlers }
        finally {
            Remove-Item Function:Set-PSReadLineKeyHandler
            Remove-Variable DracoSubmitCapture -Scope Script
        }
    } $Capture
    $Capture.Original
}

function Enable-DracoTypingEffects {
    if (-not ('Draco.InputPulse' -as [type])) { throw 'DRACO pulse component is not loaded' }
    if (-not $script:DracoInputBindingsInstalled) {
        # Do not alter vi command-mode bindings or custom user shortcuts.
        if ((Get-PSReadLineOption).EditMode -eq 'Vi') { return }
        $Bound = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
        foreach ($Handler in Get-PSReadLineKeyHandler -Bound) {
            if ($Handler.Key) { $Bound[$Handler.Key] = $Handler.Function }
        }
        $Chords = @()
        # Fixed insertion bindings, independent of what the user enters. Printable
        # chords are case-sensitive in PSReadLine: Shift+x can normalize to x.
        # Literal upper/lower bindings preserve each custom shortcut separately.
        $Names = @('Spacebar') + @(33..126 | ForEach-Object { [string][char]$_ }) +
            @(192..255 | ForEach-Object { [string][char]$_ }) + @([string][char]8364)
        foreach ($Chord in $Names) {
            if (-not $Bound.ContainsKey($Chord) -or $Bound[$Chord] -eq 'SelfInsert') {
                try {
                    Set-PSReadLineKeyHandler -Key $Chord -BriefDescription DracoSelfInsert -ScriptBlock {
                        param($key, $arg)
                        [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
                        [Draco.InputPulse]::Click()
                    } -ErrorAction Stop
                    $Chords += $Chord
                } catch { }
            }
        }
        # Wrap only stock submit actions. Never retrieve the input buffer, inspect
        # keys or commands, or overwrite user-defined Enter shortcuts.
        $script:DracoSubmitBindings = @{}
        $script:DracoSubmitScripts = @{}
        foreach ($SubmitChord in @('Enter', 'Ctrl+m')) {
            if ($Bound.ContainsKey($SubmitChord) -and $Bound[$SubmitChord] -eq 'OhMyPoshEnterKeyHandler') {
                $OriginalSubmit = Get-DracoPoshSubmitHandler
                if ($OriginalSubmit) {
                    $SubmitHandler = {
                        param($key, $arg)
                        # Repaint/accept first, then emit the anonymous pulse so
                        # the original transient redraw cannot erase its marker.
                        & $OriginalSubmit $key $arg
                        try { [Draco.InputPulse]::Fire() } catch { }
                    }.GetNewClosure()
                    Set-PSReadLineKeyHandler -Key $SubmitChord -BriefDescription DracoSubmit -ScriptBlock $SubmitHandler
                    $script:DracoSubmitScripts[$SubmitChord] = $OriginalSubmit
                    $script:DracoSubmitBindings[$SubmitChord] = 'OhMyPoshEnterKeyHandler'
                }
                continue
            }
            if ($Bound.ContainsKey($SubmitChord) -and
                $Bound[$SubmitChord] -in @('AcceptLine', 'ValidateAndAcceptLine')) {
                $SubmitAction = $Bound[$SubmitChord]
                $SubmitHandler = {
                    param($key, $arg)
                    # A graphics/output failure must never prevent submission.
                    if ($SubmitAction -eq 'ValidateAndAcceptLine') {
                        [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine($key, $arg)
                    } else {
                        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($key, $arg)
                    }
                    try { [Draco.InputPulse]::Fire() } catch { }
                }.GetNewClosure()
                Set-PSReadLineKeyHandler -Key $SubmitChord -BriefDescription DracoSubmit -ScriptBlock $SubmitHandler
                $script:DracoSubmitBindings[$SubmitChord] = $SubmitAction
            }
        }
        $script:DracoInputBindingsInstalled = $true
        $script:DracoInputChords = $Chords
    }
    [Draco.InputPulse]::Start()
}

function Disable-DracoTypingEffects {
    if ('Draco.InputPulse' -as [type]) { [Draco.InputPulse]::Stop() }
    if ($script:DracoInputBindingsInstalled) {
        # Restore only our own bindings; preserve custom changes made afterwards.
        foreach ($Handler in Get-PSReadLineKeyHandler -Bound) {
            if ($Handler.Function -eq 'DracoSelfInsert') {
                Set-PSReadLineKeyHandler -Key $Handler.Key -Function SelfInsert
            }
            if ($Handler.Function -eq 'DracoSubmit' -and $script:DracoSubmitBindings.ContainsKey($Handler.Key)) {
                if ($script:DracoSubmitScripts.ContainsKey($Handler.Key)) {
                    Set-PSReadLineKeyHandler -Key $Handler.Key -BriefDescription $script:DracoSubmitBindings[$Handler.Key] -ScriptBlock $script:DracoSubmitScripts[$Handler.Key]
                } else {
                    Set-PSReadLineKeyHandler -Key $Handler.Key -Function $script:DracoSubmitBindings[$Handler.Key]
                }
            }
        }
        $script:DracoInputBindingsInstalled = $false
        $script:DracoInputChords = @()
    }
}

function Get-DracoTypingStatus {
    if (-not ('Draco.InputPulse' -as [type])) {
        return [PSCustomObject]@{ Enabled = $false; Bindings = 0; Received = 0; Emitted = 0; OutputError = 0; StartupError = $script:DracoInputStartupError }
    }
    [PSCustomObject]@{
        Enabled = [Draco.InputPulse]::Enabled
        Bindings = @($script:DracoInputChords).Count
        Received = [Draco.InputPulse]::Received
        Emitted = [Draco.InputPulse]::Emitted
        Fires = [Draco.InputPulse]::Fires
        SubmitBindings = @($script:DracoSubmitBindings.Keys).Count
        EnterHandler = (Get-PSReadLineKeyHandler -Bound | Where-Object Key -eq 'Enter' | Select-Object -First 1).Function
        OutputError = [Draco.InputPulse]::OutputError
        StartupError = $script:DracoInputStartupError
        Protocol = [Draco.InputPulse]::Protocol
        Transport = @('Unavailable', 'Native', 'Managed')[[Draco.InputPulse]::Transport]
    }
}

function Test-DracoFireEffects {
    Enable-DracoTypingEffects
    [Draco.InputPulse]::Reset()
    [Draco.InputPulse]::Fire()
    Start-Sleep -Milliseconds 1100
    Get-DracoTypingStatus
}

function Test-DracoTypingEffects {
    param([switch]$Transport, [ValidateRange(1, 10)][int]$Seconds = 4)
    Enable-DracoTypingEffects
    [Draco.InputPulse]::Reset()
    try {
        if ($Transport) {
            Write-Host 'DRACO transport test: top-left background cell GREEN for four seconds.' -ForegroundColor Green
        } else {
            Write-Host 'DRACO visual test: GREEN lightning held on, then two separate flashes.' -ForegroundColor Green
        }
        [Draco.InputPulse]::ShowDiagnostic([bool]$Transport)
        Start-Sleep -Seconds $Seconds
    } finally { [Draco.InputPulse]::Reset() }
    if (-not $Transport) {
        Start-Sleep -Milliseconds 250
        [Draco.InputPulse]::Click()
        [Draco.InputPulse]::Click()
        Start-Sleep -Milliseconds 650
    }
    Get-DracoTypingStatus
}

$DracoInputConfigPath = Join-Path $env:USERPROFILE '.draco-terminal\input-effects.json'
$script:DracoInputStartupError = $null
if (Test-Path $DracoInputConfigPath) {
    try {
        $DracoInputConfig = Get-Content $DracoInputConfigPath -Raw | ConvertFrom-Json
        if ($DracoInputConfig.enabled) {
            if ($DracoInputConfig.assembly -cnotmatch '^draco-input-[a-f0-9]{12}\.dll$') {
                throw 'Invalid local DRACO assembly filename; reinstall DRACO'
            }
            if (-not ('Draco.InputPulse' -as [type])) {
                $AssemblyPath = Join-Path $env:USERPROFILE ('.draco-terminal\' + $DracoInputConfig.assembly)
                # Hash the exact byte array passed to Assembly.Load, eliminating
                # the separate hash/read window. No binary is executed here yet.
                $AssemblyBytes = [IO.File]::ReadAllBytes($AssemblyPath)
                $Hasher = [Security.Cryptography.SHA256]::Create()
                try { $ByteHash = [BitConverter]::ToString($Hasher.ComputeHash($AssemblyBytes)).Replace('-', '') }
                finally { $Hasher.Dispose() }
                if ($DracoInputConfig.assemblyHash -notmatch '^[a-fA-F0-9]{64}$' -or
                    $ByteHash -ne $DracoInputConfig.assemblyHash) {
                    throw 'Local DRACO assembly integrity check failed; reinstall DRACO'
                }
                [void][Reflection.Assembly]::Load($AssemblyBytes)
            }
            Enable-DracoTypingEffects
            if (-not [Draco.InputPulse]::Enabled -or @($script:DracoInputChords).Count -lt 26) {
                throw 'No insertion bindings enabled (vi mode or incompatible editor)'
            }
        }
    } catch {
        # Quiet startup; diagnostic details remain available on explicit request.
        $script:DracoInputStartupError = $_.Exception.Message
    }
}

