# How DRACO runs

| Component | Responsibility | Trust boundary |
| --- | --- | --- |
| `install.ps1`, `scripts/Draco.Setup.ps1`, `scripts/Draco.Presets.ps1` | Dependency checks, validated setup, backup and atomic writes | Reviewed local checkout and current-user files |
| `profile/draco-profile.ps1` | PSReadLine colors, local Oh My Posh initialization and prompt cache | Trusted installed prompt executable/config |
| `profile/draco-input.ps1` | Preserve/delegate editor handlers; emit zero-argument events | Editor arguments are forwarded unchanged, never inspected for graphics |
| `input/InputPulse.cs` | Bounded anonymous timing, asynchronous wakeup and fixed output marker | No input reads, character payloads, network or file logging |
| `shaders/draco-storm.hlsl` | Decode fixed marker, draw cached effects and protect text | GPU receives the normal rendered Terminal texture |
| `scripts/build-assets.py` | Generate deterministic storm/routes and pack PNG atlas | Optional local development tool |
| `uninstall.ps1`, `CLEAN-RESET.cmd` | Remove DRACO loaders/settings/files; keep recovery copies | Same current-user paths and recorded settings target |

## Preset selection

The data-only `config/dragons.json` catalog selects a matching graphics pack.
The public default is lineart, stored at the root for compatibility. Three other
modern packs keep their authored atlases/shaders under `presets/`; three legacy
ambient shaders use the public lineart body texture and disable the input bridge.
Installation verifies pack hashes/geometry before active writes and records the
selection in `install-state.json`. See [all packs](VARIANTS.md).

## Anonymous bridge

PSReadLine runs its normal insertion/submit action and sends `Click()` or `Fire()`
without parameters. Counts/timestamps enter a bounded atomic mailbox; those
editor calls do not wait for console output. One background worker wakes a timer
when idle. The timer checks every 16 ms during active effects, skips overlapping
callbacks, and stops once requests/effects drain. Both the mailbox and typing gate
cap waiting clicks at eight. Enter replaces a single flame timestamp, with no
flame backlog.

`cell-v4-fire` changes only the background attribute of the fixed top-left output
cell using DECCARA. It preserves the character, foreground and cursor. Green
encodes anonymous typing activity; blue encodes twenty age stages during the
900 ms breath. Two exact shader loads at fixed coordinates decode the marker and
hide its background. The shader does not inspect the input line or caret.

## Cached graphics

One 3072 × 640 RGBA atlas occupies about 7.5 MiB uncompressed on the GPU:

- Dragon artwork: x=0..639.
- Twelve storm masks in four RGB tiles: x=640..1663.
- Electrical contour routes and progress: x=1664..2303.
- Illustrated fire: x=2304..3071.

Three independently placed lightning lanes cover the pane in pixel space.
Dragon proportions and breath clearance follow the current resolution. Fire
sampling is bounded to the active breath region: one outline sample and two
crossfading flow phases carry filaments outward, deform tongues and tear tips.
A delayed shutdown mask extinguishes the throat before the outgoing tail. Solid
dragon pixels shield the snout/fangs; the terminal background mask protects bright
text. There is no live blur, fractal generation, ray marching or per-key process.

Terminal loads the atlas as premultiplied RGB. Fire and cyan body lines use that RGB directly; the
route data tile is deliberately unpremultiplied before decoding its channels.
Half-pixel insets and bounded UVs prevent atlas-tile bleed.

## Living dragon

The cyan line-art body is a single 640px transparent sprite. A smooth
spatial deformation flexes the wing and tail, expands the chest and tilts the
head. Signed-clock-safe cycles produce a shared pose; Enter adds a small forward shift.
Five fixed-point arithmetic steps map posed pixels back into the sprite. Body,
red-eye extraction, heat reflection and contour routes all use these rest UVs.
The breath origin and tangent use the forward deformation of the same mouth
anchor, `(0.881, 0.357)`. A padded destination rectangle retains moving tips;
out-of-sprite coordinates are rejected before atlas sampling.

For lineart motion there is no additional texture, input event, animation thread
or dependency. The armored pack instead uses a layered 4352 × 640 atlas and
a bounded anonymous `Flight()` event. Flight runs only when that preset has
motion and input effects enabled; it is disabled by `-NoDragonMotion`.
`-NoDragonMotion` installs a separate content-addressed shader with a zero pose;
the existing animated eye, storms and fire remain enabled. `-Static` still removes
the shader entirely. Runtime GPU cost must be measured on the target machine;
the existing decoded atlas size stays 7.5 MiB. See [animation limits](ANIMATION.md).

## Prompt and validation

The prompt delegates Oh My Posh's own editor integration. Primary/transient renders
are cached with invalidation after commands, path/environment/width/status/time
changes. The cache uses the normal shell history entry ID, not command text; it
is separate from the graphics bridge and does not disable shell history.

CI compiles the production `ps_4_0` shader and renders it through Direct3D WARP at
640×360, 400×600 and 400×300 with positive/negative clocks. It checks text/marker
preservation, lightning coverage, flame expansion, moving internal colors and
mouth-first shutdown. It also exercises native output via ConPTY, blocked-output
editor notifications, installation failure paths and actual Oh My Posh handlers.
CI tests are behavior checks, not live target-GPU benchmarks.



## Lightning depth and typing cores

The atlas body tile stores a filled occlusion silhouette in alpha, computed once
at asset-build time from closed outline regions. Its premultiplied RGB preserves
the cyan drawing. No mask detection or flood fill runs inside the terminal.
Three cached lightning lanes are assigned stable front/back depth per strike;
rear lanes are blocked by the moving silhouette and front lanes pass over it.
The split reuses existing samples and adds no texture or timer. Green typing
uses a squared intensity core to suppress broad halos without changing the
geometry, with a lower peak than the previous full-strength green effect.

