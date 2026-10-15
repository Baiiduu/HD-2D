"""Show the original front, one generated side and its mirror, and V2 Back15."""
from pathlib import Path
import json
import shutil
import hashlib
from PIL import Image, ImageDraw

TASK = Path(__file__).resolve().parent
OUTPUT = TASK / 'direction-baseline'
manifests = list((TASK / 'outputs' / 'side-view').rglob('final_outputs.json'))
assert len(manifests) == 1
manifest = json.loads(manifests[0].read_text(encoding='utf-8'))
media = [item for item in manifest['outputs'] if item.get('type') == 'media']
assert len(media) == 1
side_path = Path(media[0]['path'])
shutil.copyfile(side_path, OUTPUT / 'side.png')
images = {name: Image.open(OUTPUT / f'{name}.png').convert('RGBA') for name in ['front', 'side', 'back']}
images['left'] = images['side'].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
sheet = Image.new('RGB', (176, 196), '#23272f')
draw = ImageDraw.Draw(sheet)
items = [('Front original', 'front'), ('Right new', 'side'), ('Back 15', 'back'), ('Left mirror', 'left')]
records = {}
for index, (label, name) in enumerate(items):
    frame = images[name]
    x, y = (index % 2) * 88 + 4, (index // 2) * 98
    draw.text((x, y + 1), label, fill='white')
    canvas = Image.new('RGBA', (80, 80), (195, 195, 195, 255))
    assert frame.width <= 80 and frame.height <= 80
    canvas.alpha_composite(frame, ((80 - frame.width) // 2, (80 - frame.height) // 2))
    sheet.paste(canvas, (x, y + 16))
    if name != 'back':
        bounds = frame.getbbox()
        records[name] = {'canvas': list(frame.size), 'alpha_bounds': bounds,
                         'alpha_extrema': frame.getchannel('A').getextrema()}
sheet.resize((704, 784), Image.Resampling.NEAREST).save(OUTPUT / 'four-view-preview.png')
mapping = json.loads((OUTPUT / 'mapping.json').read_text(encoding='utf-8'))
mapping['side'] = {'source': str(side_path), 'related_call': 'CALL032', 'canvas': list(images['side'].size),
                   'left_uses_runtime_flip_h': True, 'sha256': hashlib.sha256(side_path.read_bytes()).hexdigest(),
                   'status': 'prepared; art review pending'}
mapping['front']['status'] = 'user proposed original as front'
mapping['back']['status'] = 'user selected Back15; background removal pending'
(OUTPUT / 'mapping.json').write_text(json.dumps(mapping, ensure_ascii=False, indent=2), encoding='utf-8')
(OUTPUT / 'pixel-inspection.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(records, ensure_ascii=True))
