# User-selected cyan line-art dragon

The default `lineart` preset uses the image supplied by the project owner on 2026-10-06:
a cyan outline dragon on black, with a red eye. The runtime sprite is prepared
from that image without redrawing it. Black becomes transparency, unused canvas
is cropped and the drawing is centered on a square without stretching it.
Antialiased RGB is preserved when composited over black.

The body is 640 x 640 RGBA; the icon is 128 x 128. The cached storm atlas is
3072 x 640, approximately 0.68 MiB compressed and 7.5 MiB decoded. The mouth
anchor is `(0.881, 0.357)`. Electrical routes follow the wing, neck and tail.
The existing illustrated fire tile is unchanged.

Only the atlas sprite alpha contains a filled depth silhouette. The standalone
body and icon remain outline-only. Premultiplied line RGB is preserved while
enclosed body/wing regions hide rear bolts. Foreground lanes remain visible.

## Rebuild

```powershell
python scripts/build-assets.py
# Import another black-background line drawing (then update mouth/routes):
python scripts/build-assets.py --source path/to/dragon.png --lineart
```

Python/Pillow are development tools only. Installation consumes the committed
PNGs and verifies their SHA-256 hashes in `manifest.json`. No image conversion,
blur or animation frame generation runs in the user's shell.

| Atlas range | Content |
| --- | --- |
| x=0..639 | Cyan line drawing |
| x=640..1663 | Twelve lightning variants in four RGB tiles |
| x=1664..2303 | Three electrical routes; alpha encodes progress 64..255 |
| x=2304..3071 | Transparent fire tile |

Project assets use the MIT terms in [LICENSE](../LICENSE), to the extent of the
project owner's rights. External fonts and software retain their own licenses.


Alternative modern packs keep matching body/icon/atlas files under `presets/`.
The three historical ambient shaders reuse this public body, rather than the
manufacturer-derived crops. See [preset catalog](../docs/VARIANTS.md).
