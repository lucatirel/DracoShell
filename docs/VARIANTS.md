# Configurable dragon packs

One installer, prompt and anonymous input runtime serve five public presets.
`lineart` remains the default. The manufacturer artwork is excluded.

| `-Dragon` | Artwork / behavior | Texture |
| --- | --- | --- |
| `lineart` | Cyan outline, subtle motion, front/rear lightning and Enter fire | 3072 × 640 atlas |
| `public` | Still-body cyber dragon with lightning/fire | 3072 × 640 atlas |
| `subtle` | Gentle body/wing/tail motion | 3072 × 640 atlas |
| `armored` | Flight and landing | 4352 × 640 atlas |
| `legacy` | Centered cyan drawing and multi-color ambient lightning | 640 × 640 body |

The three former legacy variations (`legacy-v2`, `legacy-v3`,
`legacy-fx`) were consolidated into one centered, ambient-only pack based on
FX. The old assets and shaders are recoverable in Git history, but are no longer
installable choices. Input-triggered lightning/fire are disabled for `legacy`.

```powershell
powershell -NoProfile -File .\install.ps1 -ListDragons
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Dragon armored
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Dragon subtle -NoDragonMotion
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Dragon public -Static
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Dragon lineart
```

Open a new Windows PowerShell tab after each change. Switching does not require
uninstalling or changing branches. Omitting `-Dragon` returns to `lineart`.
`-SettingsPath`, `-FontFace`, `-NoDependencyInstall` and `-NoTypingEffects` apply
to every preset. `-NoDragonMotion` stops movement on lineart/subtle/armored while
keeping eye/lightning/fire; `-Static` uses the selected body as a native background.
Armored flight requires motion and input effects; `Test-DracoFlight` replays it.

## Catalog and pairing

`config/dragons.json` selects body, icon, shader, texture, hash manifest and
capabilities. Root `assets/` and `shaders/` contain lineart for existing tools;
alternatives live under `presets/<name>/`. Each modern pack keeps its authored
geometry, mouth anchors, atlas and shader. Changing only a PNG would misalign
the effects. Installation checks asset hashes and dimensions before active writes.
Content-addressed runtime shader/texture names force Terminal to reload changes.

New variants need a matching pack, catalog entry and render checks, rather than
a long-lived branch. Pack builders and provenance/animation notes accompany the
modern assets. Python/Pillow are optional development tools, never runtime dependencies.

## Validation and publishing

Windows CI compiles every shader, installs every preset in a disposable profile,
checks matching asset hashes, exercises motion/static/default transitions and
uninstalls. WARP checks cover the four modern packs, including motion opt-outs;
these are offscreen regression tests, not target-GPU latency measurements.
Publication checks reject known excluded artwork and private source commits in
the checkout and reachable history. See [publishing](PUBLISHING.md).

