"""Build a static storm atlas; Python/Pillow are development-only dependencies.

The shader samples cached, antialiased fractal branches instead of rebuilding
lightning for every pixel/frame. Twelve variants occupy four RGB tiles; a final
tile stores three electrical contour routes with travel progress in alpha.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DRAGON_SIZE = 640
STORM_WIDTH = 256
STORM_TILES = 4
ARC_OFFSET = DRAGON_SIZE + STORM_WIDTH * STORM_TILES
FIRE_OFFSET = ARC_OFFSET + DRAGON_SIZE
FIRE_WIDTH = 768
SUPERSAMPLE = 3


def save_png(image, path):
    # Readers must see either the complete old asset or the complete new one.
    with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".png", delete=False) as file:
        temp = Path(file.name)
    try:
        image.save(temp, format="PNG", optimize=True)
        with Image.open(temp) as check:
            check.load()
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def subdivide(a, b, rng, depth):
    if depth == 0:
        return [a, b]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    offset = rng.uniform(-0.17, 0.17) * length
    mid = ((a[0] + b[0]) * 0.5 - dy / length * offset,
           (a[1] + b[1]) * 0.5 + dx / length * offset)
    return subdivide(a, mid, rng, depth - 1)[:-1] + subdivide(mid, b, rng, depth - 1)


def storm_mask(seed, style=0):
    rng = random.Random(seed)
    width, height = STORM_WIDTH * SUPERSAMPLE, DRAGON_SIZE * SUPERSAMPLE
    ink = Image.new("L", (width, height))
    draw = ImageDraw.Draw(ink)

    def stroke(points, strength=1.0, thickness=1.0):
        for i, (a, b) in enumerate(zip(points, points[1:])):
            progress = i / max(len(points) - 1, 1)
            # Uneven, tapered streamers; no uniform neon zigzag lines.
            taper = max(0.2, 1.0 - progress * 0.70)
            line_width = max(1, round(SUPERSAMPLE * thickness * taper))
            draw.line([a, b], fill=round(255 * strength * (0.60 + 0.40 * taper)), width=line_width)

    # Different lean, leader bends, fork count and attachment positions, rather
    # than twelve resamplings of one fixed tree. Keep the accepted vertical span.
    begin = (width * rng.uniform(0.32, 0.68), height * 0.055)
    end = (width * rng.uniform(0.28, 0.72), height * 0.94)
    if style % 3 == 1:
        bend = (width * rng.uniform(0.25, 0.75), height * rng.uniform(0.36, 0.62))
        trunk = subdivide(begin, bend, rng, 6)[:-1] + subdivide(bend, end, rng, 6)
    else:
        trunk = subdivide(begin, end, rng, 7)
    stroke(trunk, thickness=1.3)
    branch_count = 3 + style % 5
    indices = sorted(rng.sample(range(17, 107), branch_count))
    for ordinal, index in enumerate(indices):
        direction = -1 if (ordinal + style) % 2 == 0 else 1
        start = trunk[index]
        end = (max(width * 0.07, min(width * 0.93,
                    start[0] + direction * width * rng.uniform(0.16, 0.40))),
               min(height * 0.94, start[1] + height * rng.uniform(0.055, 0.23)))
        branch = subdivide(start, end, rng, 5)
        stroke(branch, strength=0.72, thickness=0.90)
        fork_start = branch[14]
        fork_end = (fork_start[0] - direction * width * 0.10,
                    min(height * 0.96, fork_start[1] + height * 0.065))
        stroke(subdivide(fork_start, fork_end, rng, 3), strength=0.40, thickness=0.55)

    ink = ink.resize((STORM_WIDTH, DRAGON_SIZE), Image.Resampling.LANCZOS)
    # All blur happens ONCE here, never in the live terminal shader.
    small_glow = ink.filter(ImageFilter.GaussianBlur(1.2)).point(lambda p: round(p * 0.52))
    large_glow = ink.filter(ImageFilter.GaussianBlur(4.0)).point(lambda p: round(p * 0.22))
    return ImageChops.add(ImageChops.add(ink, small_glow), large_glow)


def contour_routes(dragon):
    # Routes refer to the original public-edition 640px art. Snap each route to the strongest
    # nearby blue stroke at build time; no contour detection in the live shader.
    routes = [
        (0, [(60,160),(110,75),(190,30),(250,55),(330,130)]),
        (0, [(115,190),(220,90),(370,65),(420,125)]),
        (1, [(340,185),(380,210),(460,215),(500,235)]),
        (1, [(460,295),(440,335),(470,410),(535,465)]),
        (2, [(160,345),(85,430),(50,530),(95,580),(205,610)]),
        (2, [(235,305),(275,370),(310,440),(375,500)]),
        (2, [(370,430),(400,470),(425,520),(460,560)]),
    ]
    masks = [Image.new('L', dragon.size) for _ in range(3)]
    progress = Image.new('L', dragon.size, 64)
    draws = [ImageDraw.Draw(mask) for mask in masks]
    travel = ImageDraw.Draw(progress)
    pixels = dragon.load()
    for channel, anchors in routes:
        # Catmull-Rom curve, then a short nearest-stroke search to follow the art.
        padded = [anchors[0], *anchors, anchors[-1]]
        points = []
        for p0, p1, p2, p3 in zip(padded, padded[1:], padded[2:], padded[3:]):
            steps = max(2, round(math.dist(p1, p2) / 2))
            for step in range(steps):
                t = step / steps
                xy = tuple(0.5 * (2*p1[k] + (-p0[k]+p2[k])*t +
                    (2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t*t +
                    (-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t*t*t) for k in (0,1))
                x, y = map(round, xy)
                candidates = []
                for cy in range(max(0,y-7),min(640,y+8)):
                    for cx in range(max(0,x-7),min(640,x+8)):
                        r,g,b,a = pixels[cx,cy]
                        score = max(g, b*0.7)/255 * a/255 - math.hypot(cx-x,cy-y)*0.018
                        if r > max(g,b): score = -1 # Never include the red eye.
                        candidates.append((score,cx,cy))
                _, sx, sy = max(candidates)
                points.append((sx,sy))
        for i, (a,b) in enumerate(zip(points,points[1:])):
            draws[channel].line([a,b],fill=255,width=2)
            travel.line([a,b],fill=64+round(191*i/max(1,len(points)-2)),width=10)
    # Alpha encodes progress in [64,255], so premultiplied WIC loading never
    # erases the start of a route. The shader unpremultiplies this data tile.
    # Short electric filaments with a tight cached halo, no star-shaped particles.
    masks = [ImageChops.add(mask, mask.filter(ImageFilter.GaussianBlur(1.0)).point(
        lambda p: round(p*0.55))) for mask in masks]
    return Image.merge('RGBA', (*masks, progress))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Generated dragon PNG to deploy")
    args = parser.parse_args()
    assets = ROOT / "assets"
    dragon_path = assets / "draco-cyber-blue.png"
    with Image.open(args.source or dragon_path) as source:
        if source.width != source.height:
            raise ValueError("The generated dragon must be square; do not distort it")
        dragon = source.convert("RGBA").resize((DRAGON_SIZE, DRAGON_SIZE), Image.Resampling.LANCZOS)
    if args.source:
        save_png(dragon, dragon_path)
        save_png(dragon.resize((128, 128), Image.Resampling.LANCZOS), assets / "draco-icon.png")

    variants = [storm_mask(41 + i*137, i) for i in range(STORM_TILES*3)]
    atlas = Image.new("RGBA", (FIRE_OFFSET + FIRE_WIDTH, DRAGON_SIZE))
    atlas.paste(dragon, (0, 0))
    for tile in range(STORM_TILES):
        lightning = Image.merge("RGBA", (*variants[tile*3:tile*3+3],
                                Image.new("L", variants[0].size, 255)))
        atlas.paste(lightning, (DRAGON_SIZE + tile*STORM_WIDTH, 0))
    atlas.paste(contour_routes(dragon), (ARC_OFFSET, 0))
    with Image.open(assets / "draco-flame-v1.png") as flame:
        if flame.size != (FIRE_WIDTH, DRAGON_SIZE) or flame.mode != "RGBA":
            raise ValueError("Fire texture must be a transparent 768 x 640 RGBA PNG")
        atlas.paste(flame, (FIRE_OFFSET, 0))
    save_png(atlas, assets / "draco-storm-atlas.png")
    names = ["assets/draco-cyber-blue.png", "assets/draco-icon.png", "assets/draco-storm-atlas.png", "assets/draco-flame-v1.png"]
    manifest = {"files": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in names}}
    (assets / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    for name in names:
        print(f"{name}: {(ROOT / name).stat().st_size:,} bytes")


if __name__ == "__main__":
    main()


