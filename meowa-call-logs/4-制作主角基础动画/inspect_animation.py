"""Inspect declared animation outputs. Preview enlargement is nearest-neighbor only."""
from pathlib import Path
import json
import sys
import math
from PIL import Image, ImageSequence, ImageDraw

TASK = Path(__file__).resolve().parent
OUTPUT = TASK / 'outputs' / sys.argv[1]
REVIEW = TASK / sys.argv[2]
REVIEW.mkdir(exist_ok=True)
manifests = list(OUTPUT.rglob('final_outputs.json'))
assert len(manifests) == 1, 'A unique declared final output is required'
manifest_path = manifests[0]
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
sources = list(manifest_path.parent.glob('*.webp'))
assert len(sources) == 1
source = sources[0]
assert source.name in json.dumps(manifest)
animation = Image.open(source)
frames = [frame.convert('RGBA') for frame in ImageSequence.Iterator(animation)]
assert len(frames) == 8
assert animation.size == (80, 80)
durations = []
for index in range(animation.n_frames):
    animation.seek(index)
    durations.append(animation.info.get('duration', 125))
preview = [frame.resize((320, 320), Image.Resampling.NEAREST) for frame in frames]
preview[0].save(REVIEW / 'preview.webp', save_all=True, append_images=preview[1:],
                duration=durations, loop=0, lossless=True)
items = frames
if len(sys.argv) > 3:
    reference = Image.open(TASK / 'direction-baseline' / sys.argv[3]).convert('RGBA')
    if reference.size == (64, 64):
        padded = Image.new('RGBA', (80, 80), '#c3c3c3')
        padded.alpha_composite(reference, (8, 8))
        reference = padded
    assert reference.size == (80, 80)
    items = [reference] + frames
cols = 3 if len(items) == 9 else 4
rows = math.ceil(len(items) / cols)
sheet = Image.new('RGB', (cols * 84, rows * 97), '#23272f')
draw = ImageDraw.Draw(sheet)
for index, frame in enumerate(items):
    x, y = (index % cols) * 84 + 2, (index // cols) * 97
    draw.text((x, y), ('REF' if index == 0 else str(index-1)) if len(items)==9 else str(index), fill='white')
    background = Image.new('RGBA', frame.size, '#c3c3c3')
    background.alpha_composite(frame)
    sheet.paste(background.convert('RGB'), (x, y + 15))
sheet.resize((sheet.width * 4, sheet.height * 4), Image.Resampling.NEAREST).save(REVIEW / 'all-frames.png')
records = []
for index, frame in enumerate(frames):
    alpha = frame.getchannel('A')
    if alpha.getextrema()[0] == 0:
        bounds = alpha.getbbox()
    else:
        corner = frame.getpixel((0, 0))
        points = [(x, y) for y in range(80) for x in range(80)
                  if max(abs(frame.getpixel((x,y))[c]-corner[c]) for c in range(3))>24]
        bounds = (min(x for x,y in points), min(y for x,y in points), max(x for x,y in points)+1, max(y for x,y in points)+1) if points else None
    frame.save(REVIEW / f'frame-{index:02d}.png')
    records.append({'frame':index, 'bounds':bounds, 'alpha_extrema':alpha.getextrema(),
                    'alpha_values':sorted(set(alpha.getdata()))})
report = {'source':str(source), 'canvas':animation.size, 'frames':len(frames),
          'duration_ms':sum(durations), 'frame_details':records, 'art_acceptance':'pending visual review'}
(REVIEW / 'inspection.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
