# Dependencies and portability

DRACO targets Windows PowerShell 5.1 in Windows Terminal. Paths are resolved from
the current user's environment/profile; the theme needs no manufacturer software, CUDA or
discrete GPU. Windows 11 x64 is the live target; CI uses Windows x64 / PowerShell
5.1. Other architectures, PowerShell 7 and Linux/macOS are not validated.

## Required for installation/runtime

| Dependency | Baseline | Setup behavior |
| --- | --- | --- |
| Windows desktop and .NET Framework | Windows PowerShell 5.1, Desktop edition | Host is checked; Framework ships with this shell |
| Windows Terminal | 1.21+ for the shader image texture | Installs missing Terminal through winget; open it once before rerunning setup |
| Oh My Posh | 31.4.1+; latest maintained release recommended | Installs if missing; checks version; never silently upgrades an existing installation |
| PSReadLine | 2.0+ | Checks the available module; gives an explicit update command when missing/old |
| Meslo Nerd Font | Installed font family | Checks actual installed families; installs through `oh-my-posh font install meslo` if missing |
| winget (App Installer) | Available on PATH when packages are needed | Gives a manual fallback if missing; never downloads/evaluates a remote install script |
| Git | For cloning/updating and prompt Git metadata | Install separately, or use a source archive without Git metadata |
| Local script policy | Allows reviewed local profile scripts | Not modified by DRACO |

Terminal 1.21 introduced `experimental.pixelShaderImagePath`. Packaged Stable and
Preview versions are checked when available. For an unpackaged/custom path, check
Terminal's About page yourself before enabling animation; `-Static` avoids the
shader requirement. The installer validates the chosen target profile before
writing active settings.

## Manual dependency commands

Run in a normal Windows PowerShell shell as needed:

```powershell
winget install --exact --id Microsoft.WindowsTerminal --source winget
winget install --exact --id JanDeDobbeleer.OhMyPosh --source winget --scope user
winget install --exact --id Git.Git --source winget
```

Open Terminal once and a new PowerShell tab after PATH changes, then:

```powershell
oh-my-posh font install meslo
# Only if PSReadLine is missing or older than 2.0:
Install-Module PSReadLine -MinimumVersion 2.0 -Scope CurrentUser
```

A PSReadLine installation can ask you to trust PSGallery/NuGet. Review that source
prompt; DRACO does not change repository trust or bypass organization policies.
The dependency tools use their own official download sources and integrity checks.
DRACO profile/settings changes use the current user; external package installers
may request elevation according to their own manifests and machine policy.

To update an existing prompt dependency explicitly:

```powershell
winget upgrade --exact --id JanDeDobbeleer.OhMyPosh --source winget
```

The known July 2026 Oh My Posh prompt-injection advisories affect versions through
29.35.0 and were fixed in 29.35.1. DRACO's 31.4.1 baseline is above that fix; its
profile checks the baseline again at startup. Keep the dependency updated for
subsequent fixes. See [the security review](SECURITY_REVIEW.md).

## Existing / offline dependencies

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoDependencyInstall
```

This prevents DRACO from invoking package/font installation. All runtime assets
are committed, and the helper is compiled locally from source using Framework's
C# provider. No Visual Studio installation or remote build service is required.
Dependency executables may have their own update/network behavior.

For another installed font, pass `-FontFace` with the exact installed family name.
Nerd Font glyphs are needed for all prompt icons; a regular font can omit icons.

## Terminal settings locations

Auto-detection checks these paths in order:

1. Stable: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
2. Preview: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json`
3. Unpackaged: `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json`

If several editions are installed, use `-SettingsPath` to choose explicitly.
Portable distributions and redirected settings use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -SettingsPath "D:\Terminal\settings\settings.json"
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -SettingsPath "D:\Terminal\settings\settings.json"
```

The installer records the selected path for later updates/reset. JSON comments
and trailing commas are accepted; serialization preserves data but normalizes
formatting and removes comments. Backups retain the original file. Existing
settings/profile destinations must be writable regular files. Junctions/symlinks
inside `.draco-terminal` are rejected to prevent redirected runtime writes/deletes.

## PowerShell policy

The sample `-ExecutionPolicy Bypass` applies only to the installer process. It does
not make your next shell load an unsigned profile. Check the normal shell's policy:

```powershell
Get-ExecutionPolicy -List
```

If your personal PC blocks local profiles, a deliberate current-user choice is:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

DRACO does not run that command for you. Do not override enterprise Group Policy,
AppLocker or WDAC. Downloaded archives can carry a web-origin mark; after reviewing
the source, remove that mark from the reviewed extracted files if needed. A Git
checkout normally avoids archive-origin marking. Execution policy is not a
substitute for trusting and reviewing scripts.

## Optional development/media tools

| Task | Tools |
| --- | --- |
| Rebuild atlas | Python 3.10+ and pinned Pillow from `requirements-dev.txt` |
| Extract a README frame | Python/Pillow plus ffmpeg on PATH |
| Compile render/ConPTY regression executables | Visual Studio C++ Build Tools, Windows SDK, Direct3D 11/WIC |
| Production shader validation | Windows `d3dcompiler_47.dll` and Windows PowerShell 5.1 |
| Prompt regression tests | Oh My Posh executable; CI pins 31.4.1 and verifies SHA-256 |

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe scripts/build-assets.py
.\.venv\Scripts\python.exe scripts/capture-readme.py recording.mp4 docs/media/terminal-capture.jpg
```

Keep Python/Pillow/ffmpeg patched, especially when decoding externally supplied
media. The capture helper only accepts a local file, disables ffmpeg network
protocols and uses argument-list execution without a shell. These tools are never
called by the theme's runtime or normal installer.

## Primary references

- [Windows Terminal install and settings paths](https://learn.microsoft.com/en-us/windows/terminal/install)
- [Windows Terminal 1.21 shader-image support](https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-21-release/)
- [Oh My Posh Windows installation](https://ohmyposh.dev/docs/installation/windows)
- [Oh My Posh fonts](https://ohmyposh.dev/docs/installation/fonts)
- [Pillow package and Python requirements](https://pypi.org/project/pillow/)

README animation encoding uses `scripts/encode-demo.py` with Python 3.10+ and
ffmpeg/libx264. Raw frames come from the optional Direct3D test renderer capture;
see [demo reproduction](media/README.md#reproduce). These tools are not runtime
dependencies.

