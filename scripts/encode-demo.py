#!/usr/bin/env python3
"""Encode the optional production-shader demo; ffmpeg is a developer tool only."""
import argparse
from pathlib import Path
import shutil
import subprocess

WIDTH, HEIGHT, FPS, FRAMES = 800, 450, 20, 120


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path, help="Raw RGBA output from validate-render.exe")
    parser.add_argument("--output", type=Path, default=Path("docs/media"))
    args = parser.parse_args()
    source = args.capture.resolve(strict=True)
    if not source.is_file() or source.stat().st_size != WIDTH * HEIGHT * 4 * FRAMES:
        parser.error("Expected exactly 120 RGBA frames of 800 x 450 pixels")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("Install ffmpeg to encode demo media")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    base = [ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-protocol_whitelist", "file,pipe", "-f", "rawvideo", "-pixel_format", "rgba",
            "-video_size", f"{WIDTH}x{HEIGHT}", "-framerate", str(FPS), "-i", str(source)]
    subprocess.run(base + ["-an", "-c:v", "libx264", "-preset", "slow", "-crf", "21",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-map_metadata", "-1",
        str(output / "draco-demo.mp4")], check=True, timeout=120)
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-protocol_whitelist", "file,pipe", "-i", str(output / "draco-demo.mp4"),
        "-filter_complex",
        "fps=12,scale=640:-1:flags=lanczos,split[a][b];"
        "[a]palettegen=max_colors=64:stats_mode=diff[p];"
        "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle",
        "-loop", "0", "-map_metadata", "-1", str(output / "draco-demo.gif")],
        check=True, timeout=120)
    for name in ("draco-demo.gif", "draco-demo.mp4"):
        path = output / name
        print(f"{name}: {path.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()

