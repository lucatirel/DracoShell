# Original public-edition dragon

Generated on 2026-10-06 with built-in ImageGen from a text-only brief. No reference
image was used. The original design is a winged, four-legged armored storm dragon,
with an angular tail, asymmetric silhouette, electric blue/violet contours and
a crimson eye. The body differs from the private personal-edition artwork.

The original PNG is resized by `scripts/build-assets.py` to a 640 × 640 RGBA sprite
and a 128 × 128 icon. The same script generates twelve cached lightning masks,
three contour routes and a single 3072 × 640 atlas. Contour anchors follow this
edition's wings, neck, armor and tail. Mouth coordinates in the shader are
(0.94, 0.45), matching the new head. The red eye mask is derived from pixel colors.
The flame tile is the project's separately generated breath illustration.

## Generation brief

Original cyber storm dragon, square transparent canvas; full body, four clawed
legs, two angular swept-back wings, lean armored chest, S-shaped neck, long hooked
tail curling left. Right-facing open mouth, forked horns, sawtooth jaw, crimson
red eye. Sparse luminous blue/cyan contours with violet accents and dark armor.
Transparent negative space; no flame, scenery, circular badge, letters or logos.
No reference image and no manufacturer mascot reproduction.

## Rebuild

```powershell
python presets/public/scripts/build-assets.py
# To deploy a replacement square transparent PNG and rebuild the icon:
python presets/public/scripts/build-assets.py --source path/to/original-dragon.png
```

Python/Pillow are development tools only. The installer consumes committed PNGs
and verifies SHA-256 hashes in `manifest.json`. Runtime does not generate images.

| Atlas range | Content |
| --- | --- |
| x=0..639 | Original dragon |
| x=640..1663 | Twelve lightning variants in four RGB tiles |
| x=1664..2303 | Three electrical routes; alpha encodes progress 64..255 |
| x=2304..3071 | Transparent fire tile |

The icon, body, routes and combined atlas have no inherited manufacturer art.
Project assets use the MIT terms in [LICENSE](../../../LICENSE), to the extent of the
project owner's rights. External fonts and software keep their own licenses.

