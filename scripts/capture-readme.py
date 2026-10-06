"""Extract a real, unretouched Terminal frame; prefer visible fire and lightning.

Requires ffmpeg on PATH and Pillow. No recordings are committed by this helper.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile
from PIL import Image


def capture(video: Path, output: Path) -> None:
    video = video.resolve(strict=True)
    if not video.is_file():
        raise ValueError('Input must be a local recording file')
    with tempfile.TemporaryDirectory(prefix='draco-capture-') as folder:
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-protocol_whitelist', 'file,pipe', '-i', str(video), '-t', '30',
                        '-vf', 'fps=12', str(Path(folder) / '%04d.png')], check=True)
        best, best_score = None, -1
        for frame in sorted(Path(folder).glob('*.png')):
            with Image.open(frame) as image:
                # Score a tiny analysis copy. The saved frame retains its original
                # dimensions and content; no compositing, retouching or overlays.
                analysis = image.convert('RGB').resize((160, 100))
                score = 0.0
                for y in range(100):
                    for x in range(160):
                        red, green, blue = analysis.getpixel((x, y))
                        if x > 88 and blue > 65 and blue > red * 1.3 and green > red * 1.1:
                            score += 3.0
                        if red > 130 and red > blue * 2:
                            score += 6.0
                if score > best_score:
                    best, best_score = frame, score
        if best is None:
            raise ValueError('No frames decoded from the recording')
        output.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(best) as image:
            image.convert('RGB').save(output, quality=95)
        print(f'Saved {output} from frame {best.stem} (~{(int(best.stem)-1)/12:.2f}s)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('video', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    capture(args.video, args.output)

