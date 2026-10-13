"""Build conservative lighting data from unchanged source pixels; no albedo edits.

Run with Python + NumPy + Pillow. Atlas tiles are processed independently, and
transparent neighbours never become height discontinuities. Maps use OpenGL Y+.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/surface_normals"


def smooth(values, radius, wrap=False):
    result = values.copy()
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (radius, radius)
        padded = np.pad(result, pad, mode="wrap" if wrap else "edge")
        result = sum(np.take(padded, range(i, i + values.shape[axis]), axis=axis)
                     for i in range(radius * 2 + 1)) / (radius * 2 + 1)
    return result


def normal_tile(rgba, kind, wrap):
    rgb = rgba[..., :3].astype(np.float32) / 255
    alpha = rgba[..., 3].astype(np.float32) / 255
    linear = np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)
    luma = np.sqrt(np.maximum(linear @ [.2126, .7152, .0722], 0))
    radius = 1 if kind in ("character", "foliage") else max(1, rgba.shape[1] // 64)
    weight = smooth(alpha, radius, wrap)
    height = smooth(luma * alpha, radius, wrap) / np.maximum(weight, .001)
    if kind == "character":
        # Broad silhouette volume with much weaker painted clothing detail.
        height = smooth(alpha, 2) * .75 + height * .12
        amplitude = 2.2
    elif kind == "foliage":
        amplitude = 1.3
    else:
        amplitude = {"grass": .008, "stone": .045, "roof": .055,
                     "plaster": .006, "wood": .018, "cliff": .025}.get(kind, .01)
        amplitude *= rgba.shape[1] / 1.6
    pad = np.pad(height, 1, mode="wrap" if wrap else "edge")
    apad = np.pad(alpha, 1, mode="wrap" if wrap else "edge")
    centre = pad[1:-1, 1:-1]
    left = np.where(apad[1:-1, :-2] >= .5, pad[1:-1, :-2], centre)
    right = np.where(apad[1:-1, 2:] >= .5, pad[1:-1, 2:], centre)
    above = np.where(apad[:-2, 1:-1] >= .5, pad[:-2, 1:-1], centre)
    below = np.where(apad[2:, 1:-1] >= .5, pad[2:, 1:-1], centre)
    nx, ny = (left - right) * amplitude * .5, (below - above) * amplitude * .5
    length = np.sqrt(nx * nx + ny * ny)
    limit = .5 if kind == "character" else .35
    scale = np.maximum(1, length / limit)
    vectors = np.stack((nx / scale, ny / scale, np.ones_like(nx)), axis=-1)
    vectors /= np.linalg.norm(vectors, axis=-1, keepdims=True)
    vectors[alpha < .5] = (0, 0, 1)
    result = np.empty_like(rgba)
    result[..., :3] = np.rint((vectors * .5 + .5) * 255).astype(np.uint8)
    result[..., 3] = rgba[..., 3]
    return result


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    jobs = {}
    for name, kind in (("grass", "grass"), ("cobble", "stone"), ("path", "stone"),
                       ("plaster", "plaster"), ("roof", "roof")):
        jobs[f"assets/meowa/pixel_sample/{name}.png"] = (f"pixel_{name}", kind, (4, 4) if name == "path" else (1, 1))
    for name in ("brick", "stone", "wood", "plaster", "roof"):
        jobs[f"assets/meowa/home/{name}.png"] = (f"home_{name}", "stone" if name in ("brick", "stone") else name, (1, 1))
    for name in ("canvas", "leather"):
        jobs[f"assets/meowa/training/{name}.png"] = (f"training_{name}", "plaster", (1, 1))
    cliff = next((ROOT / "assets/ground/generated/cliff").glob("*/texture.png"))
    jobs[cliff.relative_to(ROOT).as_posix()] = ("cliff", "cliff", (1, 1))
    for path in (ROOT / "assets/meowa/player").glob("*.png"):
        jobs[path.relative_to(ROOT).as_posix()] = (f"player_{path.stem}", "character", (1, 1))
    for path in (ROOT / "assets/meowa/player/dodge").glob("dodge_*.png"):
        jobs[path.relative_to(ROOT).as_posix()] = (f"player_{path.stem}", "character", (1, 1))
    jobs["assets/meowa/player/dodge/sheet.png"] = ("player_dodge_sheet", "character", (4, 2))
    for path in (ROOT / "assets/meowa/dressing").glob("*/*.png"):
        if path.parent.name in ("grass", "flowers"):
            jobs[path.relative_to(ROOT).as_posix()] = (f"foliage_{path.stem}", "foliage", (1, 1))
    manifest = {}
    for relative, (name, kind, grid) in jobs.items():
        source = ROOT / relative
        if not source.exists():
            continue
        rgba = np.asarray(Image.open(source).convert("RGBA"))
        normal = np.empty_like(rgba)
        tw, th = rgba.shape[1] // grid[0], rgba.shape[0] // grid[1]
        for y in range(grid[1]):
            for x in range(grid[0]):
                tile = rgba[y * th:(y + 1) * th, x * tw:(x + 1) * tw]
                normal[y * th:(y + 1) * th, x * tw:(x + 1) * tw] = normal_tile(tile, kind, kind not in ("character", "foliage") and grid == (1, 1))
        filename = name + ".png"
        Image.fromarray(normal).save(OUT / filename)
        # Lossless normal data, mipmapped for surfaces; sprite data stays nearest.
        import_path = OUT / (filename + ".import")
        digest = hashlib.md5(("res://assets/surface_normals/" + filename).encode()).hexdigest()
        import_path.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n'
                               f'path="res://.godot/imported/{filename}-{digest}.ctex"\n\n[deps]\n'
                               f'source_file="res://assets/surface_normals/{filename}"\n'
                               f'dest_files=["res://.godot/imported/{filename}-{digest}.ctex"]\n\n[params]\n'
                               'compress/mode=0\ncompress/normal_map=0\ncompress/channel_pack=0\n'
                               f'mipmaps/generate={str(kind not in ("character", "foliage")).lower()}\n'
                               'process/fix_alpha_border=false\nprocess/normal_map_invert_y=false\n', encoding="utf-8")
        manifest["res://" + relative] = {"normal": "res://assets/surface_normals/" + filename,
                                        "kind": kind, "grid": grid,
                                        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {len(manifest)} normal maps; source pixels unchanged")


if __name__ == "__main__":
    build()
