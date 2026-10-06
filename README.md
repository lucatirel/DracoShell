[![DracoShell Windows shader preview](docs/media/draco-demo.gif)](docs/media/draco-demo.mp4)

# DracoShell

**Lightning as you type. Fire when you hit Enter.**

An animated Windows Terminal theme for Windows PowerShell. A cyan line-art dragon with subtle motion,
crimson breath, electric storms and a compact prompt that keeps your work readable.
Built by [Luca Tirel](https://github.com/lucatirel). Public edition with an original cyber dragon.

[Install](#install) · [Controls](#controls) · [Compatibility](docs/DEPENDENCIES.md) ·
[Watch the MP4](docs/media/draco-demo.mp4) · [Support the creator](#support-the-creator)

[![Windows checks](https://github.com/lucatirel/DracoShell/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/lucatirel/DracoShell/actions/workflows/validate.yml)
[![Code: MIT](https://img.shields.io/badge/code-MIT-67e8f9)](LICENSE)
[![Windows PowerShell 5.1](https://img.shields.io/badge/Windows_PowerShell-5.1-4d7cfe)](docs/DEPENDENCIES.md)

*Preview rendered from the production HLSL on Windows Direct3D WARP, with
simulated anonymous activity. Windows Direct3D checks passed for the source revision; see [capture provenance](docs/media/README.md).*

## Wake the dragon

| Your terminal | DRACO's response |
| --- | --- |
| Hit **Enter** | Red-orange breath propagates from the mouth, then burns out at the tips |
| **Type** | Green lightning strikes across the pane |
| Let it **idle** | Cyan, violet and magenta storms cross in front or disappear behind the dragon |
| Watch **Draco** | Gentle breathing and small wing, head and tail movements |
| **Resize or split** | The scene follows the pane, leaving room for the breath |
| Get **work done** | Protected bright text and a two-line prompt with directory, Git and Python context |

## Built to stay lightweight

**One cached graphics atlas. No process launched per keystroke.**

The shader reuses a single 3072 × 640 atlas: approximately **0.68 MiB on disk** and
**7.5 MiB decoded** for that texture. Fire sampling runs inside the active breath
region. There is no live blur, ray marching or fractal construction. Anonymous
input notifications use a bounded mailbox and never wait for console output;
the bridge timer stops when effects drain. Repeated empty Enter presses reuse
cached prompt renders.

These are architecture facts, not a claim about total Terminal memory or a GPU
benchmark. [How it works](docs/ARCHITECTURE.md). A static mode is available too.

The dragon moves through a small smooth deformation on the GPU. The crimson eye,
blue contour discharges and breath origin follow the same pose. There is one body
texture sample, five bounded arithmetic inversion steps and no sprite-frame
sequence, animation worker or added runtime dependency. [Motion and limits](docs/ANIMATION.md).

## Install

Use **Windows PowerShell 5.1**. Review the scripts, then clone and install:

```powershell
git clone https://github.com/lucatirel/DracoShell.git
if ($LASTEXITCODE -ne 0) { throw "Clone failed" }
Set-Location .\DracoShell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
if ($LASTEXITCODE -ne 0) { throw "Installation failed" }
```

**Open a new Windows PowerShell tab.** The installer checks dependencies, installs
missing Oh My Posh through winget and missing Meslo fonts through its official font
installer. If Terminal is missing, setup installs it and asks you to open it once
before rerunning. Existing dependencies are not silently upgraded.

Git missing? Run `winget install --exact --id Git.Git --source winget`, then open a
new shell. A source archive also works. 

Setup targets your Windows PowerShell Terminal profile and current-user shell
profile, saves runtime files under `~/.draco-terminal`, and creates recovery
backups. Other Terminal profiles and custom shortcuts are preserved. Execution
policy is not changed; see [setup and policy guidance](docs/DEPENDENCIES.md#powershell-policy).

| Component | Supported baseline |
| --- | --- |
| System | Windows desktop; Windows 11 x64 is the target setup |
| Shell | Windows PowerShell 5.1 / .NET Framework, Desktop edition |
| Terminal | Windows Terminal 1.21+ for animation |
| Prompt / editor | Oh My Posh 31.4.1+ / PSReadLine 2.0+ |
| Font | Installed Meslo Nerd Font, or an installed alternative via `-FontFace` |
| Automatic downloads | winget / App Installer, internet access |

[Full prerequisites and manual install commands](docs/DEPENDENCIES.md).
No Python, CUDA, Visual Studio or discrete NVIDIA GPU is required at runtime.
PowerShell 7, Linux/macOS and other terminal emulators are not validated targets.

<details>
<summary><strong>Update, static mode and portable settings</strong></summary>

Update an existing checkout:

```powershell
# Run from your DracoShell checkout.
git fetch origin
if ($LASTEXITCODE -ne 0) { throw "Fetch failed" }
git switch main
if ($LASTEXITCODE -ne 0) { throw "Branch switch failed" }
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw "Update failed" }
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
if ($LASTEXITCODE -ne 0) { throw "Installation failed" }
```

Choose a mode:

```powershell
# Ambient animation only:
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoTypingEffects

# Static dragon background:
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Static

# Still dragon, keeping the red eye, lightning and Enter fire:
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoDragonMotion

# Existing dependencies, with an installed alternate font:
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoDependencyInstall -FontFace "CaskaydiaCove Nerd Font"
```

Use the exact installed font family. Rerun the normal installer to restore effects.
For portable/custom Terminal settings, pass `-SettingsPath "C:\path\to\settings.json"`;
the path is recorded for reset.

</details>

Plain taskbar launches get a one-time screen clear at the first prompt, after
PowerShell prints its startup timing. This applies only to argument-free
`powershell.exe` in Windows Terminal; startup errors prevent the clear. Normal
tabs use `-NoLogo`. Scripted launches and later command output are preserved.

## Controls

| Action | Result |
| --- | --- |
| `Enter` | One 900 ms breath |
| Normal character insertion | Green pane-wide lightning |
| `Ctrl+Shift+F10` | Toggle shader effects, if the chord is free |
| `Test-DracoFireEffects` | Trigger one flame |
| `Test-DracoTypingEffects` | Test the green lightning effect |
| `Get-DracoTypingStatus` | Show counters and startup errors |
| `Disable-DracoTypingEffects` / `Enable-DracoTypingEffects` | Stop / restart input effects in this tab |

Vi mode, IME, paste, history recall and custom editing handlers do not produce a
separate effect for every inserted character.

## Anonymous effects

The graphics bridge receives only argument-free `Click()` and `Fire()` events:
**no characters or commands, no global keyboard hooks, no clipboard reads,
no input logging and no network calls**. The normal shell/editor retain their
own editing, history and prompt behavior.

[Security policy](SECURITY.md) · [Source review](docs/SECURITY_REVIEW.md).
Windows CI checks setup/reset safety, DLL integrity, nonblocking notifications,
real Oh My Posh integration and Direct3D shader behavior across pane shapes.
The review is scoped and does not certify zero vulnerabilities.

## Remove / recover

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

For a broken startup profile, run `CLEAN-RESET.cmd`. Reset removes DRACO settings,
loaders and executable runtime files, keeping backups and an inactive graphics cache.
The PNG/HLSL files stay at their existing paths so Terminal can finish its
asynchronous settings reload without a missing-shader warning. Close all Terminal
windows and reopen PowerShell after reset. Appearance returns to Terminal defaults;
restore your installation backup for the exact previous appearance. Git, fonts and
Oh My Posh stay installed. Keep recovery backups out of Git: they can contain
private settings.

## Support the creator

Created by [Luca Tirel](https://github.com/lucatirel).

<!-- CREATOR-SUPPORT:START -->
If DRACO earns a place in your daily setup, give the repository a star, share a
Terminal capture, or contribute an improvement. Screenshots and recordings make
it easier to find the next visual or performance fix.
<!-- CREATOR-SUPPORT:END -->

[Contribute](CONTRIBUTING.md) · [Report a bug](https://github.com/lucatirel/DracoShell/issues) ·
[Creator support setup](docs/SUPPORT.md)

## Credits and license

Built with Windows Terminal, Oh My Posh, PSReadLine and Nerd Fonts.
This edition uses the cyan line drawing selected and supplied by the project
owner. See the asset notes for its preparation and runtime format.

**Code, documentation and original project artwork: [MIT](LICENSE).**
[Asset provenance and build process](assets/README.md) ·
[Dependency licenses](THIRD_PARTY_NOTICES.md).

