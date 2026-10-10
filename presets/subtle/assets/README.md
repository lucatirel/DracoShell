# Original minimal public dragon

Generated on 2026-10-06 with built-in ImageGen from a text-only brief. No
reference image or manufacturer mascot was supplied. This redesign replaces
micro-scales and armor with broad smooth shapes, dark navy fills, cyan contours,
swept horns, a large bat wing, a long curved tail and a crimson eye.

The runtime body is 640 x 640 RGBA; the icon is 128 x 128. The storm atlas remains
3072 x 640. `scripts/build-assets.py` deterministically rebuilds twelve lightning
masks, three contour routes and the combined atlas. The routes follow the new
wing ribs, neck and tail. The shader animates the body by a smooth deformation;
eye extraction and contours use the same rest coordinates. The new mouth anchor
is `(0.913, 0.330)`. The existing illustrated fire tile is unchanged.

## Generation brief

Original full-body dragon mascot for a dark terminal; transparent square canvas.
Masterfully designed minimalist emblem legible at 256 pixels. Bold continuous
sweeping shapes, broad smooth silhouette, no scales, micro-texture or armor.
Lean S-shaped neck, sharp right-facing head, two swept-back horns, small crimson
eye, slightly open jaw. Large blade-shaped bat wings with simple cyan ribs,
crouched torso and separated legs, an elegant whip-tail curling lower-left.
Limited navy/cyan/electric-blue palette and a restrained violet wing accent.
No circle, shield, typography, background, lightning or fire. Design for small
head, wing, chest and tail motions. No manufacturer reference or reproduction.

## Rebuild

```powershell
python presets/subtle/scripts/build-assets.py
# Replace the body and icon from a new transparent square source:
python presets/subtle/scripts/build-assets.py --source path/to/original-dragon.png
```

Coordinates and route anchors are specific to this artwork; a different pose
requires updating them in the builder and shader together. Python/Pillow are
optional development tools. Setup consumes the committed PNGs and verifies
SHA-256 hashes in `manifest.json`; runtime does not generate images.

| Atlas range | Content |
| --- | --- |
| x=0..639 | Minimal dragon |
| x=640..1663 | Twelve lightning variants in four RGB tiles |
| x=1664..2303 | Three electrical routes; alpha encodes progress 64..255 |
| x=2304..3071 | Transparent fire tile |

Project assets use the MIT terms in [LICENSE](../../../LICENSE), to the extent of the
project owner's rights. External fonts and software retain their own licenses.

