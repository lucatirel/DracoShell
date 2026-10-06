param([switch]$SkipInstaller)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

# Parse with the actual Windows PowerShell 5.1 parser.
Get-ChildItem $RepoRoot -Filter *.ps1 -Recurse | ForEach-Object {
    $Tokens = $null; $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$Tokens, [ref]$Errors) | Out-Null
    if ($Errors.Count) { throw ($Errors | Out-String) }
}
Get-ChildItem $RepoRoot -Filter *.json -Recurse | ForEach-Object {
    Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null
}

# Decode the actual committed PNG bytes and verify their hashes and transparency.
Add-Type -AssemblyName System.Drawing
$Manifest = Get-Content (Join-Path $RepoRoot "assets\manifest.json") -Raw | ConvertFrom-Json
foreach ($Entry in $Manifest.files.PSObject.Properties) {
    $Path = Join-Path $RepoRoot $Entry.Name
    if ((Get-FileHash $Path -Algorithm SHA256).Hash -ne $Entry.Value) { throw "Asset checksum failed: $Path" }
    $Bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        if ($Entry.Name -eq "assets/draco-storm-atlas.png") {
            if ($Bitmap.Width -ne 3072 -or $Bitmap.Height -ne 640) { throw "Invalid atlas layout" }
            # Decode all twelve masks, not just the first tile. Every shape must
            # carry a visible core; all four tile payloads must be different.
            $TileSignatures = @()
            for ($Tile = 0; $Tile -lt 4; $Tile++) {
                $ChannelMax = @(0, 0, 0)
                $Signature = New-Object System.Text.StringBuilder
                for ($Y = 0; $Y -lt 640; $Y += 4) {
                    for ($X = 640 + $Tile * 256; $X -lt 896 + $Tile * 256; $X += 4) {
                        $Pixel = $Bitmap.GetPixel($X, $Y)
                        $ChannelMax[0] = [Math]::Max($ChannelMax[0], $Pixel.R)
                        $ChannelMax[1] = [Math]::Max($ChannelMax[1], $Pixel.G)
                        $ChannelMax[2] = [Math]::Max($ChannelMax[2], $Pixel.B)
                        [void]$Signature.Append([char]($Pixel.R + 256))
                        [void]$Signature.Append([char]($Pixel.G + 256))
                        [void]$Signature.Append([char]($Pixel.B + 256))
                    }
                }
                if (@($ChannelMax | Where-Object { $_ -lt 128 }).Count) { throw "Missing lightning channel in tile $Tile" }
                $TileSignatures += $Signature.ToString()
            }
            if (@($TileSignatures | Select-Object -Unique).Count -ne 4) { throw "Repeated storm tile" }
            $RouteMax = @(0, 0, 0); $MinProgress = 255; $MaxProgress = 0
            for ($Y = 0; $Y -lt 640; $Y += 2) {
                for ($X = 1664; $X -lt 2304; $X += 2) {
                    $Pixel = $Bitmap.GetPixel($X, $Y)
                    $RouteMax[0] = [Math]::Max($RouteMax[0], $Pixel.R)
                    $RouteMax[1] = [Math]::Max($RouteMax[1], $Pixel.G)
                    $RouteMax[2] = [Math]::Max($RouteMax[2], $Pixel.B)
                    if ([Math]::Max($Pixel.R, [Math]::Max($Pixel.G, $Pixel.B)) -gt 128) {
                        $MinProgress = [Math]::Min($MinProgress, $Pixel.A)
                        $MaxProgress = [Math]::Max($MaxProgress, $Pixel.A)
                    }
                }
            }
            if (@($RouteMax | Where-Object { $_ -lt 128 }).Count -or $MinProgress -gt 85 -or $MaxProgress -lt 220) {
                throw "Missing electrical route or travel coordinates"
            }
        } elseif ($Entry.Name -eq "assets/draco-flame-v1.png") {
            if ($Bitmap.Width -ne 768 -or $Bitmap.Height -ne 640) { throw "Invalid fire tile" }
        } elseif ($Bitmap.Width -ne $Bitmap.Height) { throw "Non-square dragon asset: $Path" }
        if ($Entry.Name -eq "assets/draco-cyber-blue.png") {
            $RedPixels = 0
            for ($Y = 0; $Y -lt 640; $Y += 2) {
                for ($X = 0; $X -lt 640; $X += 2) {
                    $Pixel = $Bitmap.GetPixel($X, $Y)
                    if ($Pixel.A -gt 128 -and $Pixel.R -gt 128 -and $Pixel.R -gt $Pixel.B * 2) { $RedPixels++ }
                }
            }
            if ($RedPixels -lt 3) { throw "Red eye emission mask is missing" }
        }
        # Downscaled outline icons can be entirely antialiased. Inspect every
        # icon pixel and require visible coverage, rather than a fully opaque fill.
        $IsIcon = $Entry.Name -eq "assets/draco-icon.png"
        $SampleStep = if ($IsIcon) { 1 } else { 8 }
        $VisibleAlphaMinimum = if ($IsIcon) { 32 } else { 255 }
        $Transparent = $false; $Visible = $false
        for ($Y = 0; $Y -lt $Bitmap.Height; $Y += $SampleStep) {
            for ($X = 0; $X -lt $Bitmap.Width; $X += $SampleStep) {
                $A = $Bitmap.GetPixel($X, $Y).A
                if ($A -eq 0) { $Transparent = $true }
                if ($A -ge $VisibleAlphaMinimum) { $Visible = $true }
            }
        }
        if (-not $Transparent -or -not $Visible) { throw "Missing visible artwork or transparency: $Path" }
    } finally { $Bitmap.Dispose() }
}

# Use the same Direct3D shader model as Windows Terminal (not a GLSL substitute).
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DracoShaderValidator {
    [ComImport, Guid("8BA5FB08-5195-40e2-AC58-0D989C3A0102"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IBlob {
        [PreserveSig] IntPtr GetBufferPointer();
        [PreserveSig] UIntPtr GetBufferSize();
    }
    [DllImport("d3dcompiler_47.dll", CallingConvention=CallingConvention.StdCall, CharSet=CharSet.Ansi)]
    private static extern int D3DCompile(byte[] data, UIntPtr size, string source,
        IntPtr defines, IntPtr include, string entry, string target, uint flags1,
        uint flags2, out IBlob code, out IBlob errors);
    public static void Validate(string source) {
        byte[] data = Encoding.UTF8.GetBytes(source);
        IBlob code = null, errors = null;
        try {
            int hr = D3DCompile(data, (UIntPtr)data.Length, "draco-storm.hlsl",
                IntPtr.Zero, IntPtr.Zero, "main", "ps_4_0", 2048, 0, out code, out errors);
            if (hr < 0) {
                string message = errors == null ? "No compiler diagnostics" :
                    Marshal.PtrToStringAnsi(errors.GetBufferPointer(), (int)errors.GetBufferSize().ToUInt64());
                throw new Exception("D3DCompile failed: " + message);
            }
        } finally {
            if (code != null) Marshal.ReleaseComObject(code);
            if (errors != null) Marshal.ReleaseComObject(errors);
        }
    }
}
'@
[DracoShaderValidator]::Validate([IO.File]::ReadAllText((Join-Path $RepoRoot "shaders\draco-storm.hlsl")))
Write-Host "PowerShell, JSON, PNG hashes/alpha and Direct3D ps_4_0: PASS"

# Run the scalar HLSL timing functions themselves as C# (same float arithmetic).
# Older Terminal builds can supply negative performance-clock values for minutes.
$ShaderText = [IO.File]::ReadAllText((Join-Path $RepoRoot "shaders\draco-storm.hlsl"))
$TimingMatch = [regex]::Match($ShaderText, '(?s)// BEGIN DRACO TIMING[^\n]*\n(.*?)// END DRACO TIMING')
if (-not $TimingMatch.Success) { throw "Shader timing functions missing" }
$TimingFunctions = [regex]::Replace($TimingMatch.Groups[1].Value, '(?m)^float (\w+)\(', 'public static float $1(')
$TimingHarness = @'
using System;
public static class DracoTimingValidator {
    static float floor(float x) { return (float)Math.Floor(x); }
    static float frac(float x) { return x - (float)Math.Floor(x); }
    static float max(float x, float y) { return Math.Max(x, y); }
    static float min(float x, float y) { return Math.Min(x, y); }
    static float smoothstep(float a, float b, float x) {
        float t = Math.Min(1f, Math.Max(0f, (x-a)/(b-a)));
        return t*t*(3f-2f*t);
    }
    TIMING_FUNCTIONS
    LAYOUT_FUNCTIONS
    public static void Validate() {
        if (eyeEmission(0f) < 0.99f) throw new Exception("Eye dark at shader startup");
        if (stormFlash(0.205f, stormStart(0f)) < 0.99f)
            throw new Exception("First lightning delayed at shader startup");
        // Check an entire signed clock range, plus long-running clocks and phase edges.
        for (int index = 0; index < 436; index++) {
            float startTime = index < 431 ? index-215f :
                new float[] {-10000f, -5.9f, -0.001f, 1000f, 10000f}[index-431];
            float brightestEye = 0f, darkestEye = 1f, brightestBolt = 0f;
            for (int frame = 0; frame <= 360; frame++) {
                float time = startTime + frame/60f;
                float eye = eyeEmission(time);
                float epoch = (float)Math.Floor(time/stormPeriod());
                float bolt = stormFlash(cycleTime(time, stormPeriod()), stormStart(epoch));
                if (float.IsNaN(eye) || float.IsNaN(bolt) || eye < 0f || eye > 1f || bolt < 0f || bolt > 1f)
                    throw new Exception("Invalid animation output");
                brightestEye = Math.Max(brightestEye, eye);
                darkestEye = Math.Min(darkestEye, eye);
                brightestBolt = Math.Max(brightestBolt, bolt);
            }
            if (brightestEye < 0.95f || darkestEye > 0.01f || brightestBolt < 0.5f)
                throw new Exception("Animation froze at timer " + startTime);
        }
        if (dragonWidth(0.8f) < 0.60f || Math.Abs(dragonWidth(1.6f)-0.46f) > 0.001f)
            throw new Exception("Half-screen boost or landscape layout regressed");
        if (mouthDischargeMask(0.875f,0.5f) != 0f || mouthDischargeMask(0.5f,0.55f) != 1f)
            throw new Exception("Mouth discharge exclusion failed");
        if (typingSignal(5f/255f,8f/255f,22f/255f) != 0f ||
            typingSignal(5f/255f,56f/255f,22f/255f) != 1f ||
            typingSignal(0f,0f,0f) != 0f ||
            typingSignal(0f,176f/255f,64f/255f) != 0f)
            throw new Exception("Anonymous keyboard signal decoding failed");
        if (flameSignal(5f/255f,8f/255f,89f/255f)!=1f ||
            flameSignal(5f/255f,56f/255f,89f/255f)!=1f ||
            flameSignal(5f/255f,56f/255f,22f/255f)!=0f ||
            typingSignal(5f/255f,56f/255f,89f/255f)!=1f)
            throw new Exception("Anonymous fire/typing signal overlap failed");
        // Twelve distinct primary forms per block, also for signed timer epochs.
        for (int block = -300; block <= 300; block++) {
            for (int lane = 0; lane < 3; lane++) {
                bool[] seen = new bool[12];
                for (int slot = 0; slot < 12; slot++) {
                    float pattern = stormPattern(block*12f+slot, lane);
                    int index = (int)pattern;
                    if (index < 0 || index >= 12 || pattern != index || seen[index])
                        throw new Exception("Repeating or invalid lightning selection");
                    seen[index] = true;
                }
            }
        }
        for (int second = -215; second <= 215; second++) {
            float brightest = 0f;
            for (int frame = 0; frame <= 120; frame++) {
                float power = dischargePower(dischargePhase(second+frame/60f));
                if (float.IsNaN(power) || power < 0f || power > 1f)
                    throw new Exception("Invalid electrical discharge");
                brightest = Math.Max(brightest, power);
            }
            if (brightest < 0.95f) throw new Exception("Electrical discharge froze");
        }
        float previous = 1f;
        for (int index = 20; index <= 400; index++) {
            float aspect = index/100f;
            float width = dragonWidth(aspect), height = width*aspect;
            float skyWidth = height*1.1f*0.4f/aspect;
            float left = Math.Max(0.012f, 0.76f-width-skyWidth*1.02f);
            if (width <= 0f || width > previous+0.00001f || height > 0.8601f || left < 0f)
                throw new Exception("Invalid responsive layout");
            previous = width;
        }
    }
}
'@
$LayoutMatch = [regex]::Match($ShaderText, '(?s)// BEGIN DRACO LAYOUT[^\n]*\n(.*?)// END DRACO LAYOUT')
if (-not $LayoutMatch.Success) { throw "Shader layout function missing" }
$LayoutFunctions = [regex]::Replace($LayoutMatch.Groups[1].Value, '(?m)^float (\w+)\(', 'public static float $1(')
Add-Type -TypeDefinition $TimingHarness.Replace('TIMING_FUNCTIONS', $TimingFunctions).Replace('LAYOUT_FUNCTIONS', $LayoutFunctions)
[DracoTimingValidator]::Validate()
Write-Host "Shader startup and negative/positive animation clocks: PASS"
Write-Host "Portrait/landscape dragon size and storm bounds: PASS"

if ($SkipInstaller) { return }

# Exercise migration, repeat installs and static mode in a disposable user fixture.
$Fixture = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$SavedUser = $env:USERPROFILE; $SavedLocal = $env:LOCALAPPDATA; $SavedProfile = $PROFILE
try {
    $env:USERPROFILE = $Fixture
    $env:LOCALAPPDATA = Join-Path $Fixture "AppData\Local"
    $script:PROFILE = Join-Path $Fixture "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    $SettingsDir = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    New-Item $SettingsDir -ItemType Directory -Force | Out-Null
    $SettingsPath = Join-Path $SettingsDir "settings.json"
    @'
{"profiles":{"list":[{"guid":"{61c54bbd-c2c6-5271-96e7-009a87ff44bf}","name":"Windows PowerShell","commandline":"powershell.exe -NoExit","startingDirectory":"D:\\git","backgroundImage":"old-corrupt.jpg","unfocusedAppearance":null}]},"schemes":[{"name":"User Scheme"}]}
'@ | Set-Content $SettingsPath -Encoding UTF8
    function oh-my-posh { $global:LASTEXITCODE = 0; '31.4.1' }
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall
    $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    $TerminalProfile = $Settings.profiles.list[0]
    if ($TerminalProfile.backgroundImage -ne "none" -or $TerminalProfile.useAcrylic -or $TerminalProfile.opacity -ne 100) { throw "Lightweight migration failed" }
    if ($TerminalProfile.startingDirectory -ne 'D:\git') { throw "User directory was changed" }
    if ($TerminalProfile.commandline -notmatch '\s-NoLogo(?:\s|$)' -or
        $TerminalProfile.commandline -match '(?i)-NoProfile' -or
        $TerminalProfile.commandline -notmatch '\s-NoExit(?:\s|$)' -or
        [regex]::Matches($TerminalProfile.commandline, '(?i)-NoLogo').Count -ne 1) {
        throw 'Quiet launch lost profiles or duplicated NoLogo'
    }
    $HandoffProfiles = @($Settings.profiles.list | Where-Object guid -eq '{d54b6c75-3f6d-4e32-b87f-41e5d37c0a9e}')
    if ($HandoffProfiles.Count -ne 1) { throw 'Missing or duplicate DRACO handoff profile' }
    $HandoffProfile = $HandoffProfiles[0]
    if (-not $HandoffProfile.hidden -or
        $HandoffProfile.commandline -cne '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -or
        $HandoffProfile.'experimental.pixelShaderPath' -cne $TerminalProfile.'experimental.pixelShaderPath' -or
        $HandoffProfile.'experimental.pixelShaderImagePath' -cne $TerminalProfile.'experimental.pixelShaderImagePath' -or
        $HandoffProfile.colorScheme -cne $TerminalProfile.colorScheme) {
        throw 'Initial PowerShell handoff profile does not mirror DRACO appearance'
    }
    if (-not (Test-Path $TerminalProfile.'experimental.pixelShaderImagePath') -or -not (Test-Path $TerminalProfile.'experimental.pixelShaderPath')) { throw "Missing runtime files" }
    if ($TerminalProfile.'experimental.pixelShaderImagePath' -notmatch 'draco-storm-atlas-') { throw "Animated mode did not bind the storm atlas" }
    if (@($Settings.schemes | Where-Object name -eq "User Scheme").Count -ne 1) { throw "User scheme was lost" }
    if ([regex]::Matches([IO.File]::ReadAllText($PROFILE), '# >>> DRACO TERMINAL >>>').Count -ne 1) { throw "Duplicate profile loader" }
    $InputConfig = Get-Content (Join-Path $Fixture '.draco-terminal\input-effects.json') -Raw | ConvertFrom-Json
    if (-not $InputConfig.enabled -or -not (Test-Path (Join-Path $Fixture ('.draco-terminal\' + $InputConfig.assembly)))) { throw 'Missing compiled typing bridge' }
    if ($InputConfig.assemblyHash -ne (Get-FileHash (Join-Path $Fixture ('.draco-terminal\' + $InputConfig.assembly)) -Algorithm SHA256).Hash) {
        throw 'Installer did not record the compiled assembly integrity hash'
    }
    # New hosts have no preloaded bridge: verify fail-closed before Assembly.Load.
    $ConfigPath = Join-Path $Fixture '.draco-terminal\input-effects.json'
    $SavedConfig = [IO.File]::ReadAllText($ConfigPath)
    $InputLoader = Join-Path $RepoRoot 'profile\draco-input.ps1'
    $StartupOutput = powershell -NoLogo -NoProfile -Command ". '$InputLoader'; if (-not [Draco.InputPulse]::Enabled) { throw 'Bridge failed to start' }; [Console]::Write('DRACO-READY')" 2>&1 | Out-String
    $VisibleStartup = [regex]::Replace($StartupOutput, '\x1b\[[0-9;$]+r', '').Trim()
    if ($VisibleStartup -cne 'DRACO-READY') { throw 'Healthy bridge startup emitted visible text or failed' }
    Write-Host 'Quiet healthy startup with the bridge enabled: PASS'
    try {
        $InputConfig.assemblyHash = '0' * 64
        $InputConfig | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8
        $LoadOutput = powershell -NoProfile -Command ". '$InputLoader'; (Get-DracoTypingStatus).StartupError" 2>&1 | Out-String
        if ($LoadOutput -notmatch 'integrity check failed') { throw 'Altered assembly hash was not rejected' }
        $InputConfig.assembly = '..\outside.dll'
        $InputConfig | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8
        $LoadOutput = powershell -NoProfile -Command ". '$InputLoader'; (Get-DracoTypingStatus).StartupError" 2>&1 | Out-String
        if ($LoadOutput -notmatch 'Invalid local DRACO assembly filename') { throw 'Assembly traversal path was not rejected' }
    } finally { [IO.File]::WriteAllText($ConfigPath, $SavedConfig) }
    Write-Host 'Assembly integrity and path traversal rejection in fresh hosts: PASS'
    $MovingShaderPath = $TerminalProfile.'experimental.pixelShaderPath'
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall -NoDragonMotion
    $StillSettings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    $StillShaderPath = $StillSettings.profiles.list[0].'experimental.pixelShaderPath'
    if ($StillShaderPath -eq $MovingShaderPath -or
        [IO.File]::ReadAllText($StillShaderPath) -notmatch '#define DRACO_MOTION 0\.0f' -or
        -not (Get-Content $ConfigPath -Raw | ConvertFrom-Json).enabled) {
        throw 'NoDragonMotion did not install a distinct still-body shader with input effects'
    }
    [DracoShaderValidator]::Validate([IO.File]::ReadAllText($StillShaderPath))
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall
    $MovingSettings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    if ($MovingSettings.profiles.list[0].'experimental.pixelShaderPath' -ne $MovingShaderPath -or
        [IO.File]::ReadAllText($MovingShaderPath) -notmatch '#define DRACO_MOTION 1\.0f') {
        throw 'Reinstall did not restore body motion'
    }
    Write-Host 'Still body with live effects, shader compilation and motion restoration: PASS'
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall -NoTypingEffects
    if ((Get-Content (Join-Path $Fixture '.draco-terminal\input-effects.json') -Raw | ConvertFrom-Json).enabled) { throw 'NoTypingEffects did not disable bridge' }
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall -Static
    $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    if ((Get-Content (Join-Path $Fixture '.draco-terminal\input-effects.json') -Raw | ConvertFrom-Json).enabled) { throw 'Static mode enabled typing bridge' }
    if ($Settings.profiles.list[0].'experimental.pixelShaderPath' -ne "") { throw "Static mode shader is still enabled" }
    & (Join-Path $RepoRoot "install.ps1") -FontFace Consolas -NoDependencyInstall
    $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    if ($Settings.profiles.list[0].backgroundImage -ne "none") { throw "Static to animated migration failed" }
    & (Join-Path $RepoRoot "uninstall.ps1")
    if (Test-Path $PROFILE) {
        if ([IO.File]::ReadAllText($PROFILE) -match 'DRACO TERMINAL') { throw "Uninstall left the loader behind" }
    }
    $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    if ($Settings.profiles.list[0].PSObject.Properties['experimental.pixelShaderPath']) { throw "Uninstall left shader enabled" }
    if (@($Settings.profiles.list | Where-Object guid -eq '{d54b6c75-3f6d-4e32-b87f-41e5d37c0a9e}').Count) { throw 'Uninstall left hidden DRACO handoff profile' }
    if ($Settings.profiles.list[0].commandline -cne 'powershell.exe -NoExit') { throw 'Uninstall lost original launch arguments' }
    # Settings reloads are asynchronous: render resources must remain readable
    # after reset, with every active setting/loader reference removed above.
    if (-not (Test-Path $TerminalProfile.'experimental.pixelShaderImagePath') -or
        -not (Test-Path $TerminalProfile.'experimental.pixelShaderPath') -or
        -not (Test-Path (Join-Path $Fixture '.draco-terminal\assets\draco-cyber-blue.png'))) {
        throw 'Uninstall deleted resources still in use by an existing renderer'
    }
    if (@(Get-ChildItem (Join-Path $Fixture '.draco-terminal\draco-input-*.dll') -ErrorAction SilentlyContinue).Count -or (Test-Path (Join-Path $Fixture '.draco-terminal\input-effects.json'))) { throw 'Uninstall left typing runtime' }
    Write-Host "Installer migration, idempotency, settings preservation and static/animated modes: PASS"
    Write-Host "Uninstall profile/runtime cleanup: PASS"
    # A write failure on VALID settings must not quarantine/regenerate them.
    $SettingsBefore = [IO.File]::ReadAllText($SettingsPath)
    [IO.File]::SetAttributes($SettingsPath, [IO.FileAttributes]::ReadOnly)
    $Rejected = $false
    try { & (Join-Path $RepoRoot 'uninstall.ps1') }
    catch { $Rejected = $true }
    finally { if (Test-Path $SettingsPath) { [IO.File]::SetAttributes($SettingsPath, [IO.FileAttributes]::Normal) } }
    if (-not $Rejected -or -not (Test-Path $SettingsPath) -or
        [IO.File]::ReadAllText($SettingsPath) -cne $SettingsBefore) { throw 'Uninstall quarantined or changed valid unwritable settings' }
    Write-Host 'Uninstall preserves valid settings on write failure: PASS'
} finally {
    $env:USERPROFILE = $SavedUser; $env:LOCALAPPDATA = $SavedLocal; $script:PROFILE = $SavedProfile
    if (Test-Path $Fixture) { Remove-Item $Fixture -Recurse -Force }
}
