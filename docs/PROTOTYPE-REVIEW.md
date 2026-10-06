# Prototype review - 6 October 2026

Prepared from `lucatirel/draco-powershell`, branch `draco-public`, at
`c7135dfa83b7ad3d2846d9d054fd6f3cce7f940b`. This prototype lives on the new branch
`draco-public-animated`. The existing `draco-public`, personal and stable branches
are unchanged.

## Try the downloaded package

Extract the ZIP to a new folder and open Windows PowerShell 5.1 there. The PNGs
and atlas are already built; Python and ffmpeg are not required for installation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Open a new tab, wait for idle motion, type normally and press Enter. Observe the
head, wing and tail; check that the flame starts at the mouth and text stays
readable. Compare a still body with the same effects:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -NoDragonMotion
```

Normal installation restores motion. For an entirely static background use
`-Static`. To remove the prototype run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The installer affects the current user's Windows PowerShell/Terminal settings
and creates recovery backups, as in the existing project. Installing this local
package replaces the currently installed Draco appearance; it does not change
the Git repository or its branches.

## Validation completed locally

- All four PNGs decode with transparency and match their SHA-256 manifest.
- Atlas rebuild and Python development-script parsing completed.
- A mechanical GLSL translation compiled and rendered with EGL/Mesa.
- Review renders at 640x360, 400x600 and 400x300 preserved bright text and marker
  cleanup, rendered motion and its opt-out, and retained typing/fire effects at
  positive and negative clocks.
- Review renders verify fire expansion, widening and mouth-first shutdown.

## Windows validation completed

[Run 37396328402](https://github.com/lucatirel/DracoShell/actions/runs/37396328402)
passed for implementation commit `2bb709d9e9428a7ed8b28e3c41833a362165bcb0`.
Windows PowerShell 5.1 parsing, both Direct3D ps_4_0 motion variants,
setup/reset, quiet startup, input transport, security boundaries and the real
Oh My Posh prompt checks passed. The production WARP renderer verified moving
wing/tail silhouettes, the still-body opt-out, fire propagation/shutdown,
concurrent typing lightning, marker cleanup and text preservation at three pane
shapes and signed clocks. The README preview now uses that Windows capture.

Typing latency and target GPU usage still require a live comparison on the
user's PC.
