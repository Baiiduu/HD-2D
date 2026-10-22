"""Assemble the repaired Meowa modules over the existing south battle footprint.

Copies native pixels only. Transparent ornaments reveal the same underlying
paving; terrain cells, collision and hand-painted data are never rewritten.
"""
from pathlib import Path
import argparse
import json

import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / 'assets/meowa/city_plaza/fixed'
WORLD_RECT = [-15.2, 29.6, 30.4, 30.4]
PPM = 40
SIZE = 1216
PATTERN_CLEARANCE = 32


def material_maps(albedo, wrap=False):
    """Conservative relief/occlusion from the assembled, opaque surface."""
    rgb = np.asarray(albedo.convert('RGB')).astype(np.float32) / 255
    luma = rgb @ np.array([.2126, .7152, .0722], dtype=np.float32)
    # Light stone faces sit slightly above the dark joints; no displaced geometry.
    height = np.clip((luma - .15) / .43, 0, 1) * .004
    height_pad = np.pad(height, 1, mode='wrap' if wrap else 'edge')
    sx = (height_pad[1:-1, 2:] - height_pad[1:-1, :-2]) * PPM / 2
    sy = (height_pad[2:, 1:-1] - height_pad[:-2, 1:-1]) * PPM / 2
    normal = np.stack([-sx, sy, np.ones_like(height)], axis=2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    normal = Image.fromarray(np.rint((normal * .5 + .5) * 255).astype('uint8'))
    joint = 1 - np.clip((luma - .17) / .23, 0, 1)
    ao = np.rint(255 - joint * 24).astype('uint8')
    dry = np.rint(199 + joint * 31).astype('uint8')
    wet = np.rint(76 + joint * 122).astype('uint8')
    zero = np.zeros_like(ao)
    return normal, Image.fromarray(np.stack([ao, dry, zero], axis=2)), Image.fromarray(np.stack([ao, wet, zero], axis=2))


def build(output, wear_density=.07, pattern_density=.025, seed=13102026):
    names = {2:'02-stone.png', 3:'03-worn.png', 4:'04-pattern.png',
             5:'05-horizontal.png', 6:'06-cross.png', 7:'07-corner.png',
             9:'09-vertical.png', 10:'10-arrow.png', 1:'octagon_cutout.png'}
    modules = {key:Image.open(SOURCE/name).convert('RGBA') for key,name in names.items()}
    assert all(modules[key].size == (96,96) for key in (2,3,4,5,6,7,9))
    assert 0 <= wear_density <= 1 and 0 <= pattern_density <= 1 - wear_density
    low, high = 12, SIZE-13
    inner = [288,928]
    centre = SIZE//2

    def pattern_allowed(x,y):
        # Keep the entire native pattern tile one stone away from every band.
        if min(x,y) < low+13+PATTERN_CLEARANCE or max(x+96,y+96) > high-12-PATTERN_CLEARANCE:
            return False
        for band in inner:
            start, end = band-12-PATTERN_CLEARANCE, band+13+PATTERN_CLEARANCE
            if (x < end and x+96 > start) or (y < end and y+96 > start):
                return False
        # The centre octagon and both arrows also need undecorated base stones.
        return not (x < centre+160 and x+96 > centre-160
                    and y < centre+92 and y+96 > centre-92)

    surface = Image.new('RGBA', (SIZE,SIZE))
    patterns = []
    base_tiles = []
    rng = np.random.default_rng(seed)
    for y in range(0,SIZE,96):
        for x in range(0,SIZE,96):
            value = rng.random()
            key = 3 if value < wear_density else 4 if value < wear_density+pattern_density else 2
            if key == 4:
                if pattern_allowed(x,y): patterns.append([x,y])
                else: key = 2
            surface.paste(modules[key], (x,y))
            base_tiles.append([x,y,key+10])

    def place(image,x,y):
        # Pillow clips at the outer edge; source dimensions and pixels stay intact.
        surface.alpha_composite(image,(int(x),int(y)))

    # Shared end-port profiles keep the band body continuous at arbitrary spans.
    horizontal = modules[5].crop((0,36,1,61))
    vertical = modules[9].crop((36,0,61,1))

    def line(x0,y0,x1,y1):
        if y0 == y1:
            for x in range(x0,x1+1): place(horizontal,x,y0-12)
        else:
            for y in range(y0,y1+1): place(vertical,x0-12,y)

    def cross(x,y): place(modules[6],x-48,y-48)

    # Retain the former battle square's broad framing, snapped to the brick grid.
    for x in inner:
        line(x,low,x,high)
    for y in inner:
        line(low,y,high,y)
    for x in inner:
        for y in inner: cross(x,y)

    def frame(x0,y0,x1,y1):
        line(x0,y0,x1,y0); line(x0,y1,x1,y1)
        line(x0,y0,x0,y1); line(x1,y0,x1,y1)
        corner = modules[7]
        # Native corner opens upward/right; rotate to each rectangular corner.
        for x,y,rotation in [(x0,y1,None),(x0,y0,Image.Transpose.ROTATE_270),
                             (x1,y0,Image.Transpose.ROTATE_180),(x1,y1,Image.Transpose.ROTATE_90)]:
            image = corner if rotation is None else corner.transpose(rotation)
            # Odd-width ports rotate one pixel about a 96px canvas centre.
            dx = 1 if rotation in (Image.Transpose.ROTATE_90,Image.Transpose.ROTATE_180) else 0
            dy = 1 if rotation in (Image.Transpose.ROTATE_180,Image.Transpose.ROTATE_270) else 0
            place(image,x-48+dx,y-48+dy)

    frame(low,low,high,high)

    # Add straight-line plaques without introducing the rejected independent #8.
    plaque = modules[5].crop((36,36,61,61))
    for x in inner:
        for y in (96,608,1120): place(plaque,x-12,y-12)
    for y in inner:
        for x in (96,608,1120): place(plaque,x-12,y-12)

    octagon = modules[1]
    place(octagon,centre-octagon.width//2,centre-octagon.height//2)
    arrow = modules[10]
    bbox = arrow.getchannel('A').getbbox()
    right = centre+56+8-bbox[0]
    place(arrow,right,centre-arrow.height//2)
    left_arrow = arrow.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    left_box = left_arrow.getchannel('A').getbbox()
    place(left_arrow,centre-56-8-left_box[2],centre-arrow.height//2)

    assert surface.getchannel('A').getextrema() == (255,255)
    normal,dry,wet = material_maps(surface)
    output.mkdir(parents=True,exist_ok=True)
    for name,image in [('ground',surface),('normal',normal),('orm_dry',dry),('orm_wet',wet)]:
        image.save(output/f'{name}.png')
    preview = modules[2].crop((0,0,64,64))
    preview.save(output/'preview.png')
    material_maps(preview,True)[0].save(output/'preview_normal.png')
    summary = {'world_rect':WORLD_RECT,'pixels_per_meter':PPM,'size_pixels':[SIZE,SIZE],
               'paint_id':11,'stone_pixels':32,'stone_meters':.8,'tile_pixels':96,
               'wear_density':wear_density,'pattern_density':pattern_density,'seed':seed,
               'pattern_clearance_pixels':PATTERN_CLEARANCE,'pattern_tiles':patterns,
               'base_tiles':base_tiles,
               'used_modules':sorted(modules),'independent_diamond_enabled':False}
    (output/'layout.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=SOURCE/'battle')
    parser.add_argument('--wear-density',type=float,default=.07)
    parser.add_argument('--pattern-density',type=float,default=.025)
    parser.add_argument('--seed',type=int,default=13102026)
    args = parser.parse_args()
    build(args.output,args.wear_density,args.pattern_density,args.seed)
