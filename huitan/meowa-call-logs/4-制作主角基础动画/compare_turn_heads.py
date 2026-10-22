"""Display original, rejected and revised heads at integer nearest-neighbor scale."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

TASK = Path(__file__).resolve().parent
REVIEW = TASK / 'turn-head-review'
request = json.loads((TASK / 'CALL031-V2头型修正-request.json').read_text(encoding='utf-8'))
mapping = json.loads((REVIEW / 'candidate-mapping.json').read_text(encoding='utf-8'))
width, height = mapping['canvas']
source = Image.open(request['referenceImages'][0]).convert('RGBA')
original = Image.new('RGBA', (width, height), (195, 195, 195, 255))
original.alpha_composite(source, ((width - source.width) // 2, (height - source.height) // 2))
rejected = Image.open(TASK / 'turn-review' / 'candidates' / 'front.png').convert('RGBA')
revised = Image.open(REVIEW / 'candidates' / 'front.png').convert('RGBA')
items = [('Original', original), ('Rejected', rejected), ('Revised', revised)]

def make_preview(items, cell_width, cell_height, scale, filename):
    sheet = Image.new('RGB', (len(items) * cell_width, cell_height + 18), '#23272f')
    draw = ImageDraw.Draw(sheet)
    for index, (label, frame) in enumerate(items):
        x = index * cell_width + 2
        draw.text((x, 1), label, fill='white')
        sheet.paste(frame, (x, 16))
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST).save(REVIEW / filename)

make_preview(items, width + 4, height, 4, 'body-comparison.png')
make_preview([(label, frame.crop((20, 8, 60, 35))) for label, frame in items], 44, 27, 6, 'head-comparison.png')
print('Saved head-comparison.png and body-comparison.png')
