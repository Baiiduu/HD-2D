"""Extract declared Meowa frame outputs without rescaling or painting pixels."""
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageSequence

TASK = Path(__file__).resolve().parent
PROJECT = TASK.parents[1] / "demoWithMeowa" / "1"
DEST = PROJECT / "assets" / "meowa" / "player"
DEST.mkdir(parents=True, exist_ok=True)
records = {}
resource_lines = []
animation_lines = []
texture_id = 0
selection_file = TASK / "selected-animations.json"
selection = json.loads(selection_file.read_text(encoding="utf-8")) if selection_file.exists() else {}
for name, speed in (("idle", 8.0), ("run", 12.0), ("idle_front", 8.0), ("run_front", 12.0), ("idle_back", 8.0), ("run_back", 12.0)):
    selected = selection.get(name, {})
    manifest_path = next((TASK / "outputs" / selected.get("directory", name)).rglob("final_outputs.json"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    is_sheet = selected.get("source_kind") == "horizontal_sheet"
    if is_sheet:
        source = manifest_path.parent / "sprite_sheet.png"
        image = Image.open(source).convert("RGBA")
        assert image.size == (640, 80), "Eight native 80px cells are required"
        source_order = selected.get("frame_order", list(range(8)))
        assert len(source_order) == 8 and all(0 <= index < 8 for index in source_order)
        input_frames = [image.crop((index * 80, 0, (index + 1) * 80, 80)) for index in source_order]
        input_frames[0].save(DEST / (name + ".webp"), save_all=True, append_images=input_frames[1:], duration=100, loop=0, lossless=True)
    else:
        candidates = list(manifest_path.parent.glob("*.webp"))
        assert len(candidates) == 1, "Choose an explicit declared animation output"
        source = candidates[0]
        shutil.copyfile(source, DEST / (name + ".webp"))
        image = Image.open(source)
        assert image.size == (80, 80) and image.n_frames == 8
        input_frames = [frame.convert("RGBA") for frame in ImageSequence.Iterator(image)]
    assert source.name in json.dumps(manifest), "Source must be a declared final output"
    frames = []
    bounds = []
    sheet = Image.new("RGBA", (80 * 4, 80 * 2))
    for index, frame in enumerate(input_frames):
        rgba = frame.convert("RGBA")
        assert rgba.getchannel("A").getextrema() == (0, 255)
        box = rgba.getbbox()
        assert box and box[0] > 0 and box[1] > 0 and box[2] < 80 and box[3] < 80
        bounds.append(box)
        filename = f"{name}_{index:02d}.png"
        rgba.save(DEST / filename)
        sheet.paste(rgba, ((index % 4) * 80, (index // 4) * 80))
        texture_id += 1
        resource_lines.append(f'[ext_resource type="Texture2D" path="res://assets/meowa/player/{filename}" id="{texture_id}"]')
        frames.append('{"duration": 1.0, "texture": ExtResource("' + str(texture_id) + '")}')
    sheet.resize((1280, 640), Image.Resampling.NEAREST).save(TASK / (name + "-review.png"))
    animation_lines.append('{"frames": [' + ', '.join(frames) + '], "loop": true, "name": &"' + name + '", "speed": ' + str(speed) + '}')
    records[name] = {"source": str(source), "source_kind": "horizontal_sheet" if is_sheet else "animation", "related_call": selected.get("related_call"), "source_frame_order": source_order if is_sheet else list(range(8)), "runtime": str(DEST / (name + ".webp")), "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "canvas": [80, 80], "frames": 8, "bounds": bounds, "playback_fps": speed, "runtime_processing": "native PNG sheet cells; preview WebP assembled losslessly" if is_sheet else "WebP byte copy; PNG decoded losslessly"}
resource = f'[gd_resource type="SpriteFrames" load_steps={texture_id + 1} format=3]\n\n' + '\n'.join(resource_lines) + '\n\n[resource]\nanimations = [' + ',\n'.join(animation_lines) + ']\n'
(DEST / "animations.tres").write_text(resource, encoding="utf-8")
(TASK / "asset-mapping.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(records, ensure_ascii=True))
