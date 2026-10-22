"""Compare native pixel scale; no runtime image transformations."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageSequence

TASK = Path(__file__).resolve().parent
PROJECT = TASK.parents[1] / 'demoWithMeowa' / '1'
entries = [
    ('front-pose', 'front-run-pose', 'run_front'),
    ('back-pose-retry', 'back-run-pose', 'run_back'),
]
records = {}
for standing, pose, run in entries:
    original = Image.open(next((TASK/'outputs'/standing).rglob('remove_bg.png'))).convert('RGBA')
    start = Image.open(next((TASK/'outputs'/pose).rglob('remove_bg.png'))).convert('RGBA')
    action = Image.open(PROJECT/'assets'/'meowa'/'player'/(run+'.webp'))
    frames = [f.convert('RGBA') for f in ImageSequence.Iterator(action)]
    # Add transparent padding to still images to match the original animation canvas.
    images = []
    for image in [original, start]:
        padded = Image.new('RGBA', (80,80))
        padded.paste(image,(8,8))
        images.append(padded)
    images.extend(frames)
    preview = Image.new('RGB',(1600,700),(34,39,49))
    draw = ImageDraw.Draw(preview)
    metrics = []
    for index, image in enumerate(images):
        yellow = [(x,y) for y in range(80) for x in range(80)
                  for r,g,b,a in [image.getpixel((x,y))]
                  if a > 0 and r > 110 and g > 90 and g > b*1.5]
        collar_y = min(y for x,y in yellow)
        head = image.crop((0,0,80,collar_y)).getbbox()
        metrics.append({'label': 'standing' if index==0 else 'edited-start' if index==1 else f'frame-{index-2}',
                        'bounds':image.getbbox(),'head_top_region':head,'first_yellow_y':collar_y})
        x,y=(index%5)*320,(index//5)*350
        preview.paste(image.resize((320,320),Image.Resampling.NEAREST),(x,y+25),image.resize((320,320),Image.Resampling.NEAREST))
        draw.text((x+10,y+7),metrics[-1]['label'],fill='white')
    preview.save(TASK/(run+'-proportions.png'))
    records[run] = metrics
(TASK/'proportion-review.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print(json.dumps(records))
