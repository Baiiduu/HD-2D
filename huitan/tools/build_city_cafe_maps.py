"""Pack native Meowa pixels and build restrained, noise-free material channels.

No resampling or changes to the source art. Each UV island is processed alone;
relief comes from connected frame/pipe shapes, never from plaster grain.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / 'assets/models/city_cafe'


def blur(values, radius):
    image = Image.fromarray(np.rint(np.clip(values, 0, 1) * 255).astype(np.uint8))
    return np.asarray(image.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255


def neighbours(mask):
    p = np.pad(mask.astype(np.uint8), 1, mode='edge')
    return sum(p[y:y+mask.shape[0], x:x+mask.shape[1]].astype(np.int16)
               for y in range(3) for x in range(3))


def material_maps(rgb, kind):
    color = rgb.astype(np.float32) / 255
    lum = color @ [.2126, .7152, .0722]
    chroma = color.max(axis=2) - color.min(axis=2)
    dark = (lum < .31) & (chroma < .24)
    dark &= neighbours(dark) >= 3
    glass = ((color[..., 0] - color[..., 2] > .13)
             & (color[..., 1] - color[..., 2] > .045)
             & (color[..., 0] - color[..., 1] < .22)
             & (lum > .28))
    height = np.zeros(lum.shape, np.float32)
    rough = np.full(lum.shape, .94, np.float32)
    metal = np.zeros(lum.shape, np.float32)
    ao = np.ones(lum.shape, np.float32)
    if kind == 'facade':
        height[dark] = .38
        height[glass] = -.08
        rough[dark] = .72
        rough[glass] = .48
        metal[dark] = .18
        # Keep the wall clean: only coherent hardware receives slight occlusion.
        ao[dark] = .97
    elif kind == 'metal':
        height[dark] = -.18
        rough[:] = .70
        metal[:] = .28
    elif kind == 'roof':
        # Roof joints are already drawn in the albedo; avoid amplifying them.
        rough[:] = .96
    elif kind in ('cloth', 'sign'):
        rough[:] = .91
    elif kind == 'glass':
        rough[:] = .30
        metal[:] = .12
    elif kind == 'stone':
        rough[:] = .95
    h = blur(height * .5 + .5, .65) * 2 - 1
    pad = np.pad(h, 1, mode='edge')
    nx = (pad[1:-1, :-2] - pad[1:-1, 2:]) * .55
    ny = (pad[2:, 1:-1] - pad[:-2, 1:-1]) * .55
    vector = np.stack((nx, ny, np.ones_like(nx)), axis=-1)
    vector /= np.linalg.norm(vector, axis=-1, keepdims=True)
    normal = np.rint((vector * .5 + .5) * 255).astype(np.uint8)
    orm = np.rint(np.stack((ao, rough, metal), axis=-1) * 255).astype(np.uint8)
    return normal, orm


def padded_paste(target, patch, rect, padding):
    x, y, w, h = rect
    assert patch.shape[:2] == (h, w)
    expanded = np.pad(patch, ((padding, padding), (padding, padding), (0, 0)), mode='edge')
    target[y-padding:y+h+padding, x-padding:x+w+padding] = expanded


def main():
    layout = json.loads((ROOT / 'cafe_uv_layout.json').read_text(encoding='utf-8'))
    w, h = layout['atlas_size']
    p = layout['padding_pixels']
    albedo = np.full((h, w, 3), (188, 178, 168), dtype=np.uint8)
    normal = np.full((h, w, 3), (128, 128, 255), dtype=np.uint8)
    orm = np.full((h, w, 3), (255, 240, 0), dtype=np.uint8)
    occupancy = np.zeros((h, w), bool)
    sources = {}
    hashes = {}
    regions = {**layout['regions'], **layout.get('roof_regions', {})}
    for info in regions.values():
        key = info['source']
        if key not in sources:
            path = ROOT / 'source' / (key + '.png')
            hashes[path] = hashlib.sha256(path.read_bytes()).digest()
            sources[key] = np.asarray(Image.open(path).convert('RGB'))
        x0, y0, x1, y1 = info['source_box']
        sx, sy, sw, sh = info['rect']
        source = sources[key]
        if info['tile']:
            patch = source[np.arange(y0, y1)[:, None] % source.shape[0],
                           np.arange(x0, x1)[None, :] % source.shape[1]]
        else:
            assert 0 <= x0 < x1 <= source.shape[1] and 0 <= y0 < y1 <= source.shape[0]
            patch = source[y0:y1, x0:x1].copy()
        assert sx >= p and sy >= p and sx+sw+p <= w and sy+sh+p <= h
        area = occupancy[sy-p:sy+sh+p, sx-p:sx+sw+p]
        assert not area.any(), 'UV islands overlap including padding'
        area[:] = True
        n, packed = material_maps(patch, info['kind'])
        for target, pixels in ((albedo, patch), (normal, n), (orm, packed)):
            padded_paste(target, pixels, info['rect'], p)
        assert np.array_equal(albedo[sy:sy+sh, sx:sx+sw], patch)
    out = ROOT / 'textures'
    out.mkdir(exist_ok=True)
    for name, pixels in [('albedo', albedo), ('normal', normal), ('orm', orm)]:
        Image.fromarray(pixels).save(out / f'cafe_{name}.png')
    assert all(hashlib.sha256(path.read_bytes()).digest() == digest for path, digest in hashes.items())
    print(f'Cafe: {len(regions)} native UV regions; 3 textures {w}x{h}; source hashes unchanged')


if __name__ == '__main__':
    main()
