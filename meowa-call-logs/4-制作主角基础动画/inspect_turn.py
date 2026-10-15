"""Inspect declared V2 outputs without editing source pixels or removing background."""
from pathlib import Path
import json
import sys
from PIL import Image, ImageSequence, ImageDraw

TASK = Path(__file__).resolve().parent
OUTPUT = TASK / 'outputs' / (sys.argv[1] if len(sys.argv) > 1 else 'turn-v2')
REVIEW = TASK / (sys.argv[2] if len(sys.argv) > 2 else 'turn-review')
REVIEW.mkdir(exist_ok=True)
manifests = list(OUTPUT.rglob('final_outputs.json'))
assert len(manifests) == 1, 'A unique declared final output is required'
manifest_path = manifests[0]
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
candidates = list(manifest_path.parent.glob('*.webp'))
assert len(candidates) == 1, 'Select the declared turn animation explicitly'
source = candidates[0]
assert source.name in json.dumps(manifest), 'Animation is not declared as final media'
animation = Image.open(source)
frames = [frame.convert('RGBA') for frame in ImageSequence.Iterator(animation)]
assert len(frames) == 32, f'Expected 32 frames, got {len(frames)}'
durations = []
for index in range(animation.n_frames):
    animation.seek(index)
    durations.append(animation.info.get('duration', 125))
preview_frames = [frame.resize((frame.width * 4, frame.height * 4), Image.Resampling.NEAREST) for frame in frames]
preview_frames[0].save(REVIEW / 'turn-preview.webp', save_all=True,
                       append_images=preview_frames[1:], duration=durations,
                       loop=0, lossless=True)
width, height = animation.size
sheet = Image.new('RGB', (8 * (width + 4), 4 * (height + 17)), '#23272f')
draw = ImageDraw.Draw(sheet)
records = []
for index, frame in enumerate(frames):
    assert frame.size == animation.size
    corner = frame.getpixel((0, 0))
    points = [(x, y) for y in range(height) for x in range(width)
              if frame.getpixel((x, y))[3] > 0
              and max(abs(frame.getpixel((x, y))[c] - corner[c]) for c in range(3)) > 24]
    bounds = [min(x for x, y in points), min(y for x, y in points),
              max(x for x, y in points) + 1, max(y for x, y in points) + 1] if points else None
    frame.save(REVIEW / f'frame-{index:02d}.png')
    x, y = (index % 8) * (width + 4) + 2, (index // 8) * (height + 17)
    draw.text((x, y), str(index).zfill(2), fill='white')
    sheet.paste(frame, (x, y + 15))
    records.append({'frame': index, 'corner_rgba': corner, 'approximate_bounds': bounds,
                    'note': 'Threshold-based inspection only; no background pixels edited'})
sheet.resize((sheet.width * 4, sheet.height * 4), Image.Resampling.NEAREST).save(REVIEW / 'all-frames.png')
report = {'source': str(source), 'dimensions': animation.size, 'frame_count': len(frames),
          'duration_ms': sum(durations),
          'frames': records, 'art_acceptance': 'pending visual review'}
(REVIEW / 'inspection.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'source': str(source), 'canvas': animation.size, 'frames': len(frames),
                  'preview': str(REVIEW / 'all-frames.png')}, ensure_ascii=True))
