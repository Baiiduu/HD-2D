"""Install the original sideways loops and the two reviewed Meowa back loops."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image, ImageSequence

ROOT = Path(r'D:\Project\HD-2DMap')
TASK = ROOT / 'meowa-call-logs/4-制作主角基础动画'
ART = Path(__file__).resolve().parent
DEST = ROOT / 'demoWithMeowa/1/assets/meowa/player'
old = json.loads((TASK / 'asset-mapping-before-proportion-fix.json').read_text(encoding='utf-8'))
sources = {name: Path(old[name]['source']) for name in ('idle', 'run')}
for name, directory in (('idle_back', 'idle-frames'), ('run_back', 'run-frames')):
    manifests = list((ART / 'outputs' / directory).rglob('final_outputs.json'))
    assert len(manifests) == 1, f'{name}: expected one final manifest'
    manifest = json.loads(manifests[0].read_text(encoding='utf-8'))
    media = list(manifests[0].parent.glob('*.webp'))
    assert len(media) == 1 and media[0].name in json.dumps(manifest)
    sources[name] = media[0]

ext, animations, records = [], [], {}
texture_id = 0
overview = []
for name, speed in (('idle', 8.0), ('run', 12.0), ('idle_back', 8.0), ('run_back', 12.0)):
    source = sources[name]
    image = Image.open(source)
    assert image.size == (80, 80) and image.n_frames == 8
    source_frames = [frame.convert('RGBA') for frame in ImageSequence.Iterator(image)]
    order = [0, 7] if name == 'idle_back' else list(range(8))
    frames = [source_frames[index] for index in order]
    for frame in frames:
        alpha = frame.getchannel('A')
        assert set(alpha.get_flattened_data()) == {0, 255}
        box = alpha.getbbox()
        assert box and box[0] > 0 and box[1] > 0 and box[2] < 80 and box[3] < 80
    # All four sources must pass before any runtime asset is overwritten.
    overview.append((name, speed, source, frames, order))

DEST.mkdir(parents=True, exist_ok=True)
for name, speed, source, frames, order in overview:
    frame_weight = 4.0 if name == 'idle_back' else 1.0
    if name == 'idle_back':
        frames[0].save(DEST / (name + '.webp'), save_all=True, append_images=frames[1:],
                       duration=500, loop=0, lossless=True)
    else:
        shutil.copyfile(source, DEST / (name + '.webp'))
    entries = []
    for index, frame in enumerate(frames):
        filename = f'{name}_{index:02d}.png'
        frame.save(DEST / filename)
        texture_id += 1
        ext.append(f'[ext_resource type="Texture2D" path="res://assets/meowa/player/{filename}" id="{texture_id}"]')
        entries.append('{"duration": ' + str(frame_weight) + ', "texture": ExtResource("' + str(texture_id) + '")}')
    animations.append('{"frames": [' + ', '.join(entries) + '], "loop": true, "name": &"' + name + '", "speed": ' + str(speed) + '}')
    records[name] = {'source':str(source), 'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'canvas':[80,80], 'frames':len(frames), 'source_frame_order':order,
        'playback_fps':speed, 'frame_duration_weight':frame_weight,
        'processing':'Native frame selection and lossless WebP/PNG; no scaling' if name == 'idle_back' else 'Native WebP byte copy and lossless PNG frame decode; no scaling'}
    if name in old:
        if name in ('idle','run'):
            assert records[name]['sha256'] == old[name]['sha256']

resource = f'[gd_resource type="SpriteFrames" load_steps={texture_id + 1} format=3]\n\n' + '\n'.join(ext)
resource += '\n\n[resource]\nanimations = [' + ',\n'.join(animations) + ']\n'
(DEST / 'animations.tres').write_text(resource, encoding='utf-8')
(DEST / 'sources.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'animations':list(records),'original_sideways_pixels_restored':True,'resampled':False},ensure_ascii=False))
