"""Extract selected native views and create nearest-neighbor review comparisons."""
from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw

TASK = Path(__file__).resolve().parent
call_id = sys.argv[1] if len(sys.argv) > 1 else 'CALL030'
REVIEW = TASK / (sys.argv[2] if len(sys.argv) > 2 else 'turn-review')
request_files = list(TASK.glob(call_id + '-*-request.json'))
assert len(request_files) == 1
REQUEST = json.loads(request_files[0].read_text(encoding='utf-8'))
REPORT = json.loads((REVIEW / 'inspection.json').read_text(encoding='utf-8'))
source = Image.open(REQUEST['referenceImages'][0]).convert('RGBA')
size = tuple(REPORT['dimensions'])
original = Image.new('RGBA', size, (195, 195, 195, 255))
original.alpha_composite(source, ((size[0] - source.width) // 2, (size[1] - source.height) // 2))
views = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {'front': 29, 'back': 15, 'right': 7, 'left': 24}
(REVIEW / 'candidates').mkdir(exist_ok=True)
selected = {}
for direction, frame_number in views.items():
    frame = Image.open(REVIEW / f'frame-{frame_number:02d}.png').convert('RGBA')
    frame.save(REVIEW / 'candidates' / f'{direction}.png')
    selected[direction] = frame

def preview(items, name):
    cell_width, cell_height = size[0] + 8, size[1] + 18
    sheet = Image.new('RGB', (cell_width * len(items), cell_height), '#23272f')
    draw = ImageDraw.Draw(sheet)
    for index, (label, frame) in enumerate(items):
        x = index * cell_width + 4
        draw.text((x, 2), label, fill='white')
        sheet.paste(frame, (x, 16))
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.Resampling.NEAREST).save(REVIEW / name)

preview([('Original', original), ('Front 29', selected['front']), ('Back 15', selected['back'])], 'direction-candidates.png')
preview([('Original', original), *[(f'{direction} {views[direction]}', selected[direction]) for direction in views]], 'five-view-candidates.png')
front_index = views['front']
preview([(f'Front {index}', Image.open(REVIEW / f'frame-{index:02d}.png').convert('RGBA')) for index in sorted({(front_index + step) % 32 for step in [-1, 0, 1, 2]})], 'front-angle-review.png')
mapping = {'source_animation': REPORT['source'], 'related_call': call_id,
           'canvas': list(size), 'frame_indices_zero_based': views,
           'processing': 'Native frames only; no resampling, repainting or background removal',
           'art_acceptance': 'pending user review', 'runtime_integrated': False}
(REVIEW / 'candidate-mapping.json').write_text(json.dumps(mapping, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(mapping, ensure_ascii=True))
