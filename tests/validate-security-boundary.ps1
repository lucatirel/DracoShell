$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

# Security regression guardrail.
# This test intentionally protects architectural boundaries, not just behavior:
# DRACO startup/effects must stay local, output-only and free of new persistence.

$PowerShellRuntimeFiles = @(
    'install.ps1',
    'uninstall.ps1',
    'scripts\Draco.Setup.ps1',
    'scripts\Draco.Presets.ps1',
    'profile\draco-profile.ps1',
    'profile\draco-input.ps1'
)

$ForbiddenCommands = @(
    'Invoke-WebRequest',
    'Invoke-RestMethod',
    'Start-BitsTransfer',
    'Start-Process',
    'Set-ExecutionPolicy',
    'Register-ScheduledTask',
    'New-ScheduledTask',
    'New-ScheduledTaskAction',
    'New-ScheduledTaskTrigger',
    'New-Service',
    'Set-Service'
)

$InvokeExpressionSites = @()

foreach ($RelativePath in $PowerShellRuntimeFiles) {
    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing runtime file: $RelativePath"
    }

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path, [ref]$Tokens, [ref]$Errors)

    if ($Errors.Count) {
        throw "PowerShell parse failure in $RelativePath"
    }

    $Commands = @($Ast.FindAll({
        param($Node)
        $Node -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    foreach ($Command in $Commands) {
        $Name = $Command.GetCommandName()
        if (-not $Name) { continue }

        if ($Name -in $ForbiddenCommands) {
            throw "Security boundary regression: $Name introduced in $RelativePath"
        }

        if ($Name -eq 'Invoke-Expression' -or $Name -eq 'iex') {
            $InvokeExpressionSites += [PSCustomObject]@{
                File = $RelativePath
                Text = $Command.Extent.Text
            }
        }
    }

    $Raw = [IO.File]::ReadAllText($Path)

    # Direct .NET networking/process launch can bypass command-name checks.
    if ($Raw -match '(?i)System\.Net\.|Net\.WebClient|Net\.Http\.HttpClient|Net\.Sockets\.|Process\s*::\s*Start|Microsoft\.Win32\.Registry') {
        throw "Security boundary regression: direct network/process/registry API in $RelativePath"
    }

    # Persistence outside the existing PowerShell profile loader is not part of DRACO.
    if ($Raw -match '(?i)\\CurrentVersion\\Run(?:Once)?\b|schtasks(?:\.exe)?\b|sc(?:\.exe)?\s+create\b') {
        throw "Security boundary regression: additional persistence mechanism in $RelativePath"
    }
}

# The single evaluator is the documented Oh My Posh initialization boundary.
if ($InvokeExpressionSites.Count -ne 1 -or
    $InvokeExpressionSites[0].File -ne 'profile\draco-profile.ps1' -or
    $InvokeExpressionSites[0].Text -notmatch '^Invoke-Expression\s+\$DracoInit$') {
    throw 'Security boundary regression: unexpected dynamic PowerShell evaluation'
}

$Profile = [IO.File]::ReadAllText((Join-Path $RepoRoot 'profile\draco-profile.ps1'))
if ($Profile -notmatch '(?s)oh-my-posh init pwsh.*?\$LASTEXITCODE.*?Invoke-Expression\s+\$DracoInit') {
    throw 'Oh My Posh initialization is no longer validated before evaluation'
}

$InputSource = [IO.File]::ReadAllText((Join-Path $RepoRoot 'input\InputPulse.cs'))
# Ignore explanatory comments so statements such as "never STD_INPUT_HANDLE"
# do not trip the guardrail; keep strings and executable code visible.
$InputCode = [regex]::Replace($InputSource, '(?ms)/\*.*?\*/|//[^\r\n]*', '')
$ForbiddenInputMarkers = @(
    'STD_INPUT_HANDLE',
    'GetStdHandle(-10)',
    'ReadConsole',
    'ReadConsoleInput',
    'GetAsyncKeyState',
    'GetKeyState',
    'SetWindowsHookEx',
    'ToUnicode',
    'user32.dll',
    'wininet.dll',
    'winhttp.dll',
    'ws2_32.dll',
    'System.Net.',
    'WebClient',
    'HttpClient',
    'TcpClient',
    'UdpClient',
    'System.Net.Sockets',
    'Clipboard',
    'Console.Read',
    'File.Write',
    'File.Append',
    'StreamWriter',
    'Process.Start'
)
foreach ($Marker in $ForbiddenInputMarkers) {
    if ($InputCode.IndexOf($Marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Input privacy boundary regression: $Marker found in InputPulse.cs"
    }
}

# Lock the native DLL surface to the reviewed output-only transport.
$Imports = [regex]::Matches(
    $InputSource,
    '\[DllImport\("(?<dll>[^"]+)"[^\]]*\)\]\s*(?:private|internal|public)\s+static\s+extern\s+[^\s]+\s+(?<name>\w+)'
)
$AllowedImports = @(
    'kernel32.dll|GetStdHandle',
    'kernel32.dll|GetConsoleMode',
    'kernel32.dll|SetConsoleMode',
    'kernel32.dll|WriteConsoleW'
)
$ObservedImports = @($Imports | ForEach-Object {
    $_.Groups['dll'].Value.ToLowerInvariant() + '|' + $_.Groups['name'].Value
})
if ($ObservedImports.Count -ne $AllowedImports.Count) {
    throw 'Input privacy boundary regression: native import count changed'
}
foreach ($Expected in $AllowedImports) {
    if ($Expected -notin $ObservedImports) {
        throw "Input privacy boundary regression: native import allowlist changed ($Expected)"
    }
}

# Emergency reset must remain profile-independent and local-only.
$CleanReset = [IO.File]::ReadAllText((Join-Path $RepoRoot 'CLEAN-RESET.cmd'))
if ($CleanReset -notmatch '(?i)powershell\.exe.*-NoProfile.*-File\s+"%~dp0uninstall\.ps1"' -or
    $CleanReset -match '(?i)https?://|\\\\[^\\]') {
    throw 'Emergency reset boundary changed: expected local -NoProfile uninstall only'
}

Write-Host 'Security architecture guardrails: PASS'
Write-Host '  - no runtime networking/process spawning or persistent execution-policy changes'
Write-Host '  - one validated Oh My Posh evaluation boundary'
Write-Host '  - output-only anonymous input bridge'
Write-Host '  - no extra persistence mechanism'
Write-Host '  - emergency reset remains local and -NoProfile'


