$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Tokens = $null; $ParseErrors = $null
$Ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $RepoRoot 'profile\draco-profile.ps1'), [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count) { throw 'Startup profile parse error' }
$Predicate = $Ast.Find({ param($Node)
    $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $Node.Name -eq 'Test-DracoQuietHandoff'
}, $true)
. ([scriptblock]::Create($Predicate.Extent.Text))
if (-not (Test-DracoQuietHandoff @('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe') 'fixture' 'ConsoleHost')) {
    throw 'Plain Terminal handoff was not recognized'
}
foreach ($Arguments in @(
    ,@('powershell.exe','-NoLogo'),
    ,@('powershell.exe','-Command','Write-Output keep'),
    ,@('powershell.exe','-File','example.ps1'),
    ,@('powershell.exe','-NonInteractive'),
    ,@('pwsh.exe')
)) {
    if (Test-DracoQuietHandoff $Arguments 'fixture' 'ConsoleHost') { throw 'Explicit/scripted launch would be cleared' }
}
if ((Test-DracoQuietHandoff @('powershell.exe') '' 'ConsoleHost') -or
    (Test-DracoQuietHandoff @('powershell.exe') 'fixture' 'Windows PowerShell ISE Host')) {
    throw 'Non-Terminal host would be cleared'
}

# Execute the real wrapper with output-only test doubles, without loading OMP
# or touching an interactive session. This script runs in its own CI process.
$Wrapper = @($Ast.EndBlock.Statements | Where-Object {
    $_.Extent.Text -match '^if \(\(Test-DracoQuietHandoff\)'
})
if ($Wrapper.Count -ne 1) { throw 'Quiet startup wrapper missing' }
$SavedPrompt = ${function:prompt}
try {
    function Test-DracoQuietHandoff { return $true }
    function Clear-Host { $script:Clears++ }
    function Get-History { if ($script:HasHistory) { [PSCustomObject]@{Id=1} } }
    foreach ($HasHistory in @($false, $true)) {
        $script:HasHistory = $HasHistory
        $script:Clears = 0; $script:Delegates = 0
        $script:DracoQuietPromptInstalled = $false
        function global:prompt { $script:Delegates++; 'fixture-prompt' }
        $global:Error.Clear()
        . ([scriptblock]::Create($Wrapper[0].Extent.Text))
        for ($Index = 0; $Index -lt 3; $Index++) {
            if ((prompt) -cne 'fixture-prompt') { throw 'Original prompt output changed' }
        }
        $Expected = if ($HasHistory) { 0 } else { 1 }
        if ($script:Clears -ne $Expected -or $script:Delegates -ne 3) { throw 'Startup clear repeated or removed command output' }
    }
    $script:HasHistory = $false; $script:Clears = 0
    $script:DracoQuietPromptInstalled = $false
    function global:prompt { 'fixture-prompt' }
    . ([scriptblock]::Create($Wrapper[0].Extent.Text))
    try { throw 'fixture startup error must stay visible' } catch {}
    $null = prompt
    if ($script:Clears -ne 0) { throw 'Startup error was hidden' }
    Write-Host 'Quiet handoff: one-time clear, original prompt, scripted output and startup errors preserved: PASS'
} finally {
    if ($SavedPrompt) { Set-Item Function:global:prompt $SavedPrompt }
}
