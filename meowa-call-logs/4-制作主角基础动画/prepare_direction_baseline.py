"""Archive selected reference pixels and display front/back direction definitions."""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw

TASK = Path(__file__).resolve().parent
request = json.loads((TASK / 'CALL030-V2转身重试-request.json').read_text(encoding='utf-8'))
OUTPUT = TASK / 'direction-baseline'
OUTPUT.mkdir(exist_ok=True)
front_path = Path(request['referenceImages'][0])
back_path = TASK / 'turn-review' / 'frame-15.png'
shutil.copyfile(front_path, OUTPUT / 'front.png')
shutil.copyfile(back_path, OUTPUT / 'back.png')
front = Image.open(front_path).convert('RGBA')
back = Image.open(back_path).convert('RGBA')
front_preview = Image.new('RGBA', back.size, (195, 195, 195, 255))
front_preview.alpha_composite(front, ((back.width - front.width) // 2, (back.height - front.height) // 2))
sheet = Image.new('RGB', (176, 98), '#23272f')
draw = ImageDraw.Draw(sheet)
for index, (label, frame) in enumerate([('Front original', front_preview), ('Back 15', back)]):
    x = index * 88 + 4
    draw.text((x, 1), label, fill='white')
    sheet.paste(frame, (x, 16))
sheet.resize((704, 392), Image.Resampling.NEAREST).save(OUTPUT / 'front-back-preview.png')
mapping = {'front': {'source': str(front_path), 'canvas': list(front.size), 'view': 'original three-quarter front'},
           'back': {'source': str(back_path), 'related_call': 'CALL030', 'zero_based_frame': 15, 'canvas': list(back.size)},
           'side': {'status': 'to prepare one side, then mirror'},
           'runtime_integrated': False, 'reference_pixels_changed': False}
(OUTPUT / 'mapping.json').write_text(json.dumps(mapping, ensure_ascii=False, indent=2), encoding='utf-8')
print('Archived original front and V2 Back15 without changing pixels')
