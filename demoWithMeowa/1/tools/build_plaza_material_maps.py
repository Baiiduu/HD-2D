"""Derive aligned AO and roughness data from the repaired native plaza pixels."""
from pathlib import Path
import argparse
import hashlib
import re

import numpy as np
from PIL import Image

SOURCE = Path(__file__).resolve().parents[1] / 'assets/meowa/city_plaza/fixed'
NAMES = ['02-stone', '03-worn', '04-pattern', '05-horizontal', '06-cross',
         '07-corner', '08-diamond', '09-vertical', '10-arrow', 'octagon_cutout']


def maps(rgba, name, ao_depth):
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    valid = rgba[..., 3] >= 128
    luma = rgb @ np.array([.2126, .7152, .0722], dtype=np.float32)
    repeat = name in NAMES[:3]
    padded = np.pad(luma, 3, mode='wrap' if repeat else 'edge')
    alpha = np.pad(valid, 3, mode='wrap' if repeat else 'edge')
    height, width = valid.shape
    near, broad = [], []
    for radius in (1, 2, 3):
        for dx, dy in ((-radius, 0), (radius, 0), (0, -radius), (0, radius),
                       (-radius, -radius), (radius, radius), (-radius, radius), (radius, -radius)):
            neighbour = padded[3+dy:3+dy+height, 3+dx:3+dx+width]
            eligible = alpha[3+dy:3+dy+height, 3+dx:3+dx+width]
            sample = np.where(eligible, neighbour, luma)
            broad.append(sample)
            if radius == 1:
                near.append(sample)
    # Local recesses only: a broad dark material is not itself an occluded cavity.
    local_top = np.maximum.reduce(near)
    surrounding = np.mean(broad, axis=0)
    cavity = np.clip((local_top - luma - .025) / .18, 0, 1)
    hollow = np.clip((surrounding - luma - .012) / .14, 0, 1)
    recess = np.clip(cavity * .78 + hollow * .22, 0, 1)
    wear = .055 if name == '03-worn' else .0
    face = .68 if name in NAMES[:3] else .65
    variation = np.clip(luma - surrounding, -.15, .15) * .15
    ao = 1.0 - ao_depth * recess
    dry = np.clip(face + variation + .17 * recess + wear, .58, .94)
    wet = np.clip(.22 + variation * .3 + .43 * recess + wear * 1.8, .18, .82)
    results = []
    for values in (ao, dry, wet):
        values = np.where(valid, values, 1.0)
        gray = np.rint(values * 255).astype(np.uint8)
        output = np.empty_like(rgba)
        output[..., :3] = gray[..., None]
        output[..., 3] = rgba[..., 3]
        results.append(Image.fromarray(output))
    return results


def import_settings(path):
    relative = 'res://' + path.relative_to(SOURCE.parents[3]).as_posix()
    digest = hashlib.md5(relative.encode()).hexdigest()
    cache = f'res://.godot/imported/{path.name}-{digest}.ctex'
    import_path = path.with_suffix('.png.import')
    existing = import_path.read_text(encoding='utf-8') if import_path.exists() else ''
    uid = re.search(r'^uid="[^"]+"$', existing, re.M)
    uid_line = uid[0]+'\n' if uid else ''
    text = (f'[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n{uid_line}path="{cache}"\n\n'
            f'[deps]\nsource_file="{relative}"\ndest_files=["{cache}"]\n\n[params]\n'
            'compress/mode=0\ncompress/normal_map=0\ncompress/channel_pack=0\n'
            'mipmaps/generate=false\nprocess/fix_alpha_border=false\n'
            'process/premult_alpha=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n')
    import_path.write_text(text, encoding='utf-8')


def build(output, ao_depth):
    hashes = {name: hashlib.sha256((SOURCE / f'{name}.png').read_bytes()).digest() for name in NAMES}
    for name in NAMES:
        rgba = np.array(Image.open(SOURCE / f'{name}.png').convert('RGBA'))
        images = maps(rgba, name, ao_depth)
        for folder, image in zip(('ao', 'roughness', 'roughness_wet'), images):
            destination = output / folder / f'{name}.png'
            destination.parent.mkdir(parents=True, exist_ok=True)
            image.save(destination)
            if output == SOURCE:
                import_settings(destination)
            assert image.size == (rgba.shape[1], rgba.shape[0])
            assert np.array_equal(np.array(image)[..., 3], rgba[..., 3])
        valid = rgba[..., 3] >= 128
        ranges = [tuple(int(x) for x in (np.array(image)[..., 0][valid].min(),
                                        np.array(image)[..., 0][valid].max())) for image in images]
        print(f'{name}: {images[0].size}, AO/dry/wet ranges {ranges}; alpha preserved')
    assert all(hashlib.sha256((SOURCE / f'{name}.png').read_bytes()).digest() == hashes[name] for name in NAMES)
    print('30 native material maps prepared; all source albedo bytes unchanged')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=SOURCE)
    parser.add_argument('--ao-depth', type=float, default=.28)
    args = parser.parse_args()
    assert 0 <= args.ao_depth <= 1
    build(args.output, args.ao_depth)
