# Verified Windows production-shader preview

The GIF and MP4 show the committed cyan line-art edition, rendered from its actual
HLSL and atlas on Windows Direct3D WARP. This is an offscreen production-shader
capture with simulated anonymous activity, not a recording of Windows Terminal,
user commands or typing latency.

- Source revision: `580a6ed4bf512d1e9400ea9d7f5b2fdce4a639ae`.
- Source validation: Windows workflow `37481325434` in the private development repository (2026-10-06).
- Public validation: [Windows checks passed](https://github.com/lucatirel/DracoShell/actions/runs/37489460291) for `05f67e176e5e929a09325d1b6e2bf5a2a40c2021`. This repository runs the same checks on every push to `main`.
- Capture artifact: `draco-shader-demo`, ID `11421965211`.
- Capture: 800 x 450 RGBA, 120 frames at 20 fps.
- MP4: full-resolution H.264. GIF: 640 pixels wide, 12 fps, 64-color palette.

The capture shows gentle body motion, ambient storms, simulated green typing
lightning with narrow cores, front/rear occlusion, and red-orange Enter fire. It replaces the prior Mesa/GLSL local review.

The Windows workflow passed parsing, JSON/asset integrity, Direct3D ps_4_0 shader
compilation, setup and reset, quiet startup, anonymous input and transport,
security architecture checks, real Oh My Posh prompt checks, and pixel regression
checks at 640 x 360, 400 x 600 and 400 x 300 panes. Moving and fixed-body modes,
foreground text preservation, fire propagation/shutdown and simultaneous green
lightning were checked with positive and negative shader clocks.

Reproduce by letting the Windows workflow capture this branch, downloading its
`draco-shader-demo` artifact and running:

```powershell
python scripts/encode-demo.py path/to/draco-demo-800x450-20fps.rgba
```

Python/Pillow and ffmpeg are developer tools only. The installed theme does not
require them. The capture is not a benchmark of interactive GPU usage or power.
