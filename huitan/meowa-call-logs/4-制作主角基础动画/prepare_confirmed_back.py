"""Remove only the empty V2 padding; never rescale the accepted back pixels."""
from pathlib import Path
import json
from PIL import Image
TASK = Path(__file__).resolve().parent
source = TASK / 'outputs/back-base-clean/back/output.png'
image = Image.open(source).convert('RGBA')
assert image.size == (80, 80)
alpha = image.getchannel('A')
bounds = alpha.getbbox()
assert bounds and all(8 <= value <= 72 for value in bounds)
assert set(alpha.get_flattened_data()) == {0, 255}
cropped = image.crop((8, 8, 72, 72))
cropped.save(TASK / 'direction-baseline/back-base.png')
image.save(TASK / 'direction-baseline/back-transparent.png')
mapping_path = TASK / 'direction-baseline/mapping.json'
mapping = json.loads(mapping_path.read_text(encoding='utf-8'))
mapping['user_confirmation'] = '用户确认原图 front、CALL032 真侧面镜像、CALL030 frame15 背面，并授权制作待机跑动后接入'
mapping['back_preparation'] = {'call':'CALL033','source':str(source),'crop':[8,8,72,72],
    'size':[64,64], 'resampled':False,'bounds_before_crop':bounds}
mapping_path.write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(mapping['back_preparation'],ensure_ascii=False))
