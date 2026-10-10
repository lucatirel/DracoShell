#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$Renderer,
    [Parameter(Mandatory=$true)][string]$Font,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $RepoRoot 'scripts/Draco.Presets.ps1')
Add-Type -AssemblyName System.Drawing
$Output = [IO.Path]::GetFullPath($Output)
New-Item $Output -ItemType Directory -Force | Out-Null
$Fixture = Join-Path $env:RUNNER_TEMP 'DracoShell'
New-Item $Fixture -ItemType Directory -Force | Out-Null
git -C $Fixture init --initial-branch=main | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Gallery git fixture failed' }
git -C $Fixture -c user.name=Draco -c user.email=draco@example.invalid commit --allow-empty -m preview | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Gallery git commit failed' }
$SavedVenv = $env:VIRTUAL_ENV
$SavedEncoding = [Console]::OutputEncoding
$Fonts = New-Object System.Drawing.Text.PrivateFontCollection
$Fonts.AddFontFile([IO.Path]::GetFullPath($Font))
$Face = New-Object System.Drawing.Font($Fonts.Families[0], 17, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$Format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
$Format.FormatFlags = $Format.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces
$Bitmap = New-Object System.Drawing.Bitmap(1280,720)
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$Graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#050816'))
$Cell = $Graphics.MeasureString('M',$Face,100,$Format).Width
$script:GalleryX = 24.0
$script:GalleryY = 38.0
$script:GalleryForeground = '#C7D2FE'
$script:GalleryBackground = $null

function Draw-GalleryAnsi([string]$Text) {
    # Parse the real Oh My Posh SGR colors; render its glyphs with the actual Nerd Font.
    $Escape = [char]27
    for ($i=0; $i -lt $Text.Length; $i++) {
        $Ch = $Text[$i]
        if ($Ch -eq $Escape -and $i+1 -lt $Text.Length -and $Text[$i+1] -eq '[') {
            $End = $i+2
            while ($End -lt $Text.Length -and [int]$Text[$End] -notin 64..126) { $End++ }
            if ($End -ge $Text.Length) { break }
            if ($Text[$End] -eq 'm') {
                $Values = @($Text.Substring($i+2,$End-$i-2) -split ';' | ForEach-Object { if ($_ -eq '') { 0 } else { [int]$_ } })
                for ($j=0; $j -lt $Values.Count; $j++) {
                    $Value=$Values[$j]
                    if ($Value -eq 0) { $script:GalleryForeground='#C7D2FE'; $script:GalleryBackground=$null }
                    elseif ($Value -eq 39) { $script:GalleryForeground='#C7D2FE' }
                    elseif ($Value -eq 49) { $script:GalleryBackground=$null }
                    elseif (($Value -eq 38 -or $Value -eq 48) -and $j+4 -lt $Values.Count -and $Values[$j+1] -eq 2) {
                        $Color = '#{0:X2}{1:X2}{2:X2}' -f $Values[$j+2],$Values[$j+3],$Values[$j+4]
                        if ($Value -eq 38) { $script:GalleryForeground=$Color } else { $script:GalleryBackground=$Color }
                        $j+=4
                    }
                }
            }
            $i=$End; continue
        }
        if ($Ch -eq $Escape -and $i+1 -lt $Text.Length -and $Text[$i+1] -eq ']') {
            $End=$i+2
            while ($End -lt $Text.Length -and [int]$Text[$End] -ne 7 -and $Text[$End] -ne $Escape) { $End++ }
            $i=$End
            if ($End -lt $Text.Length -and $Text[$End] -eq $Escape) { $i++ }
            continue
        }
        if ([int]$Ch -eq 13) { $script:GalleryX=24.0; continue }
        if ([int]$Ch -eq 10) { $script:GalleryX=24.0; $script:GalleryY+=28; continue }
        if ([int]$Ch -lt 32) { continue }
        if ($script:GalleryBackground) {
            $Brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($script:GalleryBackground))
            try { $Graphics.FillRectangle($Brush,[single]$script:GalleryX,[single]$script:GalleryY,[single]($Cell+0.5),[single]25) }
            finally { $Brush.Dispose() }
        }
        $Brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($script:GalleryForeground))
        try { $Graphics.DrawString([string]$Ch,$Face,$Brush,[single]$script:GalleryX,[single]$script:GalleryY,$Format) }
        finally { $Brush.Dispose() }
        $script:GalleryX+=$Cell
    }
}
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $env:VIRTUAL_ENV = Join-Path $Fixture '.venv'
    $Prompt = (& $Executable print primary --config (Join-Path $RepoRoot 'config/draco.omp.json') --shell generic --pwd $Fixture --terminal-width 120 | Out-String).TrimEnd()
    if ($LASTEXITCODE -ne 0 -or $Prompt -notmatch 'main' -or $Prompt -notmatch 'PY') { throw 'Actual Oh My Posh prompt missing Git/venv context' }
    $Esc=[char]27
    Draw-GalleryAnsi ($Prompt + "`n")
    # The command is attached to the second prompt line.
    $script:GalleryY-=28
    $script:GalleryX=24+$Cell*4
    Draw-GalleryAnsi ("${Esc}[38;2;103;232;249mGet-ChildItem${Esc}[0m -Directory | ${Esc}[38;2;103;232;249mSelect-Object${Esc}[0m -First 5 Mode, Name`n`n")
    $Rows = Get-ChildItem $RepoRoot -Directory | Select-Object -First 5 Mode,Name | Format-Table -AutoSize | Out-String
    Draw-GalleryAnsi $Rows.TrimEnd()
    Draw-GalleryAnsi ("`n`n"+$Prompt)
    $script:GalleryX=24+$Cell*4
    Draw-GalleryAnsi ("${Esc}[38;2;103;232;249mgit${Esc}[0m status --short --branch`n")
    $Branch = (& git -C $Fixture status --short --branch | Out-String).TrimEnd()
    if ($LASTEXITCODE -ne 0) { throw 'Gallery git output failed' }
    Draw-GalleryAnsi ("${Esc}[38;2;125;243;209m"+$Branch+"${Esc}[0m`n`n"+$Prompt)
    if ($script:GalleryY -gt 660) { throw 'Gallery text clipped the terminal pane' }
    $Terminal = Join-Path $Output 'terminal-input.png'
    $Bitmap.Save($Terminal,[System.Drawing.Imaging.ImageFormat]::Png)
    [IO.File]::WriteAllText((Join-Path $Output 'prompt.ansi.txt'),$Prompt,(New-Object System.Text.UTF8Encoding($false)))
    $Catalog = Get-Content (Join-Path $RepoRoot 'config/dragons.json') -Raw | ConvertFrom-Json
    $Captures=@()
    foreach ($Name in $Catalog.presets.PSObject.Properties.Name) {
        $Preset=Get-DracoPreset $RepoRoot $Name
        Assert-DracoPresetAssets $Preset
        $Path=Join-Path $Output ("terminal-"+$Name+".png")
        & $Renderer $Preset.shaderPath $Preset.imagePath $Terminal $Path ([int][bool]$Preset.inputEffects)
        if ($LASTEXITCODE -ne 0) { throw "Capture failed: $Name" }
        $Check=[System.Drawing.Bitmap]::FromFile($Path)
        try { if ($Check.Width -ne 1280 -or $Check.Height -ne 720) { throw 'Bad gallery dimensions' } }
        finally { $Check.Dispose() }
        $Captures+=@{preset=$Name;file=[IO.Path]::GetFileName($Path);shaderHash=(Get-FileHash $Preset.shaderPath).Hash;imageHash=(Get-FileHash $Preset.imagePath).Hash}
    }
    if ($Captures.Count -ne 7) { throw 'Incomplete public gallery' }
    @{revision=$env:GITHUB_SHA;renderer='Windows Direct3D WARP';prompt='Oh My Posh 31.4.1 / committed draco.omp.json';font='MesloLGM Nerd Font';width=1280;height=720;captures=$Captures} |
        ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Output 'gallery-provenance.json') -Encoding UTF8
    Write-Host 'Seven actual shader captures with real Oh My Posh glyphs: PASS'
} finally {
    $env:VIRTUAL_ENV=$SavedVenv
    [Console]::OutputEncoding=$SavedEncoding
    $Graphics.Dispose();$Bitmap.Dispose();$Format.Dispose();$Face.Dispose();$Fonts.Dispose()
}

