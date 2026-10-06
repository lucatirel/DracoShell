$esc = [char]27

# A handoff process was already started without -NoLogo. Terminal cannot change
# its launch flags. Clear its startup banner once, at the first interactive
# prompt, after ConsoleHost has printed the native profile timing message.
# Never clear scripted, nested, non-Terminal or explicitly configured launches.
function Test-DracoQuietHandoff {
    param([string[]]$LaunchArguments = [Environment]::GetCommandLineArgs(),
        [string]$TerminalSession = $env:WT_SESSION, [string]$HostName = $Host.Name)
    return ($HostName -eq 'ConsoleHost' -and
        -not [string]::IsNullOrWhiteSpace($TerminalSession) -and
        $LaunchArguments.Count -eq 1 -and
        [IO.Path]::GetFileName($LaunchArguments[0]) -ieq 'powershell.exe')
}

try {
    Import-Module PSReadLine -ErrorAction SilentlyContinue

    Set-PSReadLineOption -Colors @{
        Command   = "$esc[38;2;112;160;255m"
        Parameter = "$esc[38;2;151;174;232m"
        String    = "$esc[38;2;103;232;249m"
        Number    = "$esc[38;2;248;213;126m"
        Variable  = "$esc[38;2;199;210;254m"
        Operator  = "$esc[38;2;112;160;255m"
        Type      = "$esc[38;2;165;213;255m"
        Member    = "$esc[38;2;151;174;232m"
        Keyword   = "$esc[38;2;103;232;249m"
        Comment   = "$esc[38;2;86;98;122m"
        Error     = "$esc[38;2;255;77;109m"
        Default   = "$esc[38;2;221;229;255m"
    }
} catch {}

$DracoConfig = Join-Path $env:USERPROFILE ".draco-terminal\draco.omp.json"
# The supported baseline is newer than both July 2026 prompt-injection fixes.
$DracoPoshVersion = (oh-my-posh version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $DracoPoshVersion -notmatch '^v?(\d+\.\d+\.\d+)' -or
    [version]$Matches[1] -lt [version]'31.4.1') {
    throw 'DRACO requires Oh My Posh 31.4.1+. Update it with winget before loading this profile.'
}
# Initialization code comes only from the locally installed, trusted dependency.
# A failed native command must not feed partial output into the evaluator.
$DracoInit = oh-my-posh init pwsh --config $DracoConfig | Out-String
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($DracoInit)) {
    throw 'Oh My Posh initialization failed; reinstall the dependency or DRACO.'
}
Invoke-Expression $DracoInit

# Cache the expensive renderer, while leaving Oh My Posh/PSReadLine key handling intact.
# A blank Enter does not add history: it must not start a new CLI process each time.
$DracoPoshModule = Get-Module -Name "oh-my-posh-core"
if ($DracoPoshModule) {
    & $DracoPoshModule {
        $script:DracoRenderCache = @{}
        $script:DracoRenderCalls = 0
        if (-not $script:DracoRenderCacheInstalled -and (Test-Path Function:Invoke-Utf8Posh)) {
            $script:DracoOriginalRenderer = ${function:Invoke-Utf8Posh}
            function script:Invoke-Utf8Posh {
                param([string[]]$Arguments = @())
                $Type = if ($Arguments.Count -ge 2 -and $Arguments[0] -eq 'print') { $Arguments[1] } else { '' }
                if ($Type -ne 'primary' -and $Type -ne 'transient') {
                    $script:DracoRenderCalls++
                    return & $script:DracoOriginalRenderer $Arguments
                }
                # Only one entry per prompt type. Refresh after commands, cd, activation,
                # resizing, status changes or a new minute; no TTL churn on held Enter.
                $History = Get-History -Count 1 -ErrorAction SilentlyContinue
                $HistoryId = if ($History) { $History.Id } else { 0 }
                if ($Type -eq 'transient') {
                    # This theme's transient arrow is fixed and does not show status/time.
                    $Key = 'transient'
                } else {
                    $Key = "$PWD|$HistoryId|$env:VIRTUAL_ENV|$env:CONDA_DEFAULT_ENV|$([DateTime]::Now.ToString('HH:mm'))|$($Arguments -join '|')"
                }
                $Cached = $script:DracoRenderCache[$Type]
                if ($Cached -and $Cached.Key -ceq $Key) { return $Cached.Text }
                $script:DracoRenderCalls++
                $Text = & $script:DracoOriginalRenderer $Arguments
                $script:DracoRenderCache[$Type] = @{ Key = $Key; Text = $Text }
                return $Text
            }
            $script:DracoRenderCacheInstalled = $true
        }
    }
}

# Anonymous typing/submit pulses with the original Oh My Posh submit behavior.
$DracoInputProfile = Join-Path $env:USERPROFILE '.draco-terminal\draco-input.ps1'
if (Test-Path $DracoInputProfile) { . $DracoInputProfile }

if ((Test-DracoQuietHandoff) -and -not $script:DracoQuietPromptInstalled) {
    $script:DracoStartupPrompt = ${function:prompt}
    $script:DracoStartupClearPending = $true
    function global:prompt {
        if ($script:DracoStartupClearPending) {
            $script:DracoStartupClearPending = $false
            if (-not (Get-History -Count 1 -ErrorAction SilentlyContinue) -and
                $global:Error.Count -eq 0) {
                try { Clear-Host } catch {}
            }
        }
        & $script:DracoStartupPrompt
    }
    $script:DracoQuietPromptInstalled = $true
}
