# Original armored public dragon

Generated on 2026-10-06 with built-in ImageGen from a text-only brief. No
manufacturer artwork or earlier dragon image was used as a reference.
The brief requested a black, furious, heavy armored western dragon with an
enormous barrel chest, thick neck, large obsidian plates, crocodilian skull,
red eye and thick reptilian legs/talons. No feline or slender anatomy.

The output is a two-component transparent sheet: wingless body on the left and
a matching detached bat wing on the right. Deterministic cropping/downsampling
packs the authored pieces as `rig/body.png` and `rig/wing.png`, each 640 x 640.
The body is rendered under two instances of the wing in the live shader.
The static sprite and 128px icon are composites of those same pieces.

The wing attaches at shoulder (0.57,0.58), with source pivot (0.925,0.920).
The body mouth anchor is (0.940,0.705). Body, wing, eye and fire use coordinated
transforms. The existing illustrated fire tile is unchanged.

## Generation brief

Two matching transparent game rig sprites, separated by an alpha gutter.
Left: complete wingless black western dragon, strict right-facing side view,
menacing low landing stance, thick powerlifter neck, barrel chest, broad shoulders,
four heavy reptilian limbs and a thick armored tail. Wedge-shaped crocodilian
head, armored brow, snarling fangs, tiny crimson eye and swept heavy horns.
Ten to sixteen huge obsidian armor plates, bold graphite facets, sparse cyan
edge highlights. No cat, panther, slender serpent or cute silhouette.
Right: one detached open bat wing, lower-right root, upper-left leading edge,
three sharp fingers and broad dark navy membranes with cyan ribs. Matching
materials; transparent background; no text, labels, environment, fire or lightning.

## Rebuild

```powershell
python presets/armored/scripts/build-assets.py
# Deploy a new matching two-component sheet:
python presets/armored/scripts/build-assets.py --rig-source path/to/dragon-rig.png
```

The new-source crop is specific to this sheet (gutter at 62.4% of its width).
Changing source geometry requires reviewing shoulder and mouth anchors too.
Python/Pillow are optional development tools. The installer consumes committed
PNGs and verifies the four runtime asset hashes in `manifest.json`.

| Atlas range | Content |
| --- | --- |
| x=0..639 | Precomposed static armored dragon |
| x=640..1663 | Twelve lightning variants in four RGB tiles |
| x=1664..2303 | Three body electrical routes; alpha encodes progress 64..255 |
| x=2304..3071 | Existing transparent fire tile |
| x=3072..3711 | Wingless body |
| x=3712..4351 | Detached wing used for far and near instances |

Project assets use [MIT](../LICENSE) to the extent of the project owner's rights.
External fonts and software retain their own licenses.

