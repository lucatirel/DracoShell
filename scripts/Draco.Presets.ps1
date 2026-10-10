# Data-only presets pair each image with its own shader and geometry.
function Resolve-DracoPresetPath {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -notmatch '^[a-zA-Z0-9_./-]+$' -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        '..' -in ($RelativePath -split '/')) { throw 'Invalid preset path' }
    $Path = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    $Prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $Path.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing preset file: $RelativePath" }
    return $Path
}

function Get-DracoPreset {
    param([string]$RepoRoot, [string]$Name = 'lineart')
    $Catalog = Get-Content -LiteralPath (Join-Path $RepoRoot 'config/dragons.json') -Raw | ConvertFrom-Json
    if ($Catalog.version -ne 1 -or $Catalog.default -ne 'lineart') { throw 'Invalid dragon catalog' }
    $Entry = $Catalog.presets.PSObject.Properties[$Name]
    if (-not $Entry) { throw "Unknown dragon '$Name'. Use -ListDragons." }
    $Preset = $Entry.Value
    if ($Preset.root -ne '.' -and $Preset.root -cne "presets/$Name") { throw 'Invalid preset root' }
    $PresetRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot $Preset.root))
    $Preset | Add-Member -NotePropertyName name -NotePropertyValue $Name
    $Preset | Add-Member -NotePropertyName directory -NotePropertyValue $PresetRoot
    foreach ($Key in @('staticImage', 'image', 'shader', 'manifest')) {
        $Resolved = Resolve-DracoPresetPath $PresetRoot $Preset.$Key
        $Preset | Add-Member -NotePropertyName ($Key + 'Path') -NotePropertyValue $Resolved
    }
    $Icon = if ($Preset.icon) { Resolve-DracoPresetPath $PresetRoot $Preset.icon }
        else { Resolve-DracoPresetPath $RepoRoot 'assets/draco-icon.png' }
    $Preset | Add-Member -NotePropertyName iconPath -NotePropertyValue $Icon
    return $Preset
}

function Assert-DracoPresetAssets {
    param($Preset)
    $Manifest = Get-Content -LiteralPath $Preset.manifestPath -Raw | ConvertFrom-Json
    $Expected = if ($Preset.inputEffects) {
        @('assets/draco-cyber-blue.png', 'assets/draco-icon.png',
          'assets/draco-storm-atlas.png', 'assets/draco-flame-v1.png')
    } else { @('assets/draco-watermark.png') }
    if (@($Manifest.files.PSObject.Properties).Count -ne $Expected.Count) { throw 'Invalid asset manifest' }
    foreach ($Entry in $Manifest.files.PSObject.Properties) {
        if ($Entry.Name -cnotin $Expected -or $Entry.Value -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'Invalid asset manifest entry'
        }
        $Path = Resolve-DracoPresetPath $Preset.directory $Entry.Name
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Entry.Value) {
            throw "DRACO asset is missing or damaged: $($Entry.Name). Run git pull again."
        }
    }
    Add-Type -AssemblyName System.Drawing
    foreach ($Path in @($Preset.staticImagePath, $Preset.iconPath, $Preset.imagePath) | Select-Object -Unique) {
        $Bitmap = [System.Drawing.Bitmap]::FromFile($Path)
        try {
            if ($Bitmap.Width -le 0 -or $Bitmap.Height -le 0) { throw 'Invalid dragon image' }
            if ($Preset.inputEffects -and $Path -eq $Preset.imagePath -and
                ($Bitmap.Width -ne $Preset.imageWidth -or $Bitmap.Height -ne $Preset.imageHeight)) {
                throw 'Invalid DRACO storm atlas dimensions'
            }
            if ($Preset.inputEffects -and $Path -ne $Preset.imagePath -and
                ($Bitmap.Width -ne $Bitmap.Height -or $Bitmap.Width -lt 128)) {
                throw 'Invalid DRACO image dimensions'
            }
        } finally { $Bitmap.Dispose() }
    }
}

function Get-DracoPresetShader {
    param($Preset, [switch]$NoDragonMotion)
    $Text = [IO.File]::ReadAllText($Preset.shaderPath)
    if ($NoDragonMotion -and $Preset.motion) { return "#define DRACO_MOTION 0.0f`n" + $Text }
    return $Text
}

