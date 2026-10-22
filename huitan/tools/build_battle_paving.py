"""Bake native V2 paving into the existing continuous map's battle footprint.

Only previously unpainted core cells are resurfaced. Terrain heights, overlays,
dimensions, home paint and gameplay scenes are preserved. Modules retain native
pixels by default; optional material enlargement uses integer nearest-neighbor
sampling. The combined structural height generates normals.
"""
from pathlib import Path
import argparse
import base64
import json
import re
import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
PPM = 40
PAINT_ID = 11
WORLD_RECT = [-15.2, 29.6, 30.4, 30.4]
POCKET_CENTERS = [(-7,21),(7,21),(-7,35),(7,35)]


def build(output, terrain_path, apply=False, material_scale=1):
    source = PROJECT / 'assets/ground/paving_smooth_v2'
    contract = json.loads((source/'tileset.json').read_text(encoding='utf-8'))
    assert contract['pixels_per_meter'] == PPM and contract['stone_pixels'] == 16
    assert material_scale in (1, 2, 4)
    channels = ['albedo','height','orm_dry','orm_wet']
    atlases = {key: Image.open(source/f'paving_atlas_{key}.png').copy() for key in channels}
    modules = {}
    for name,(x,y,w,h) in contract['modules'].items():
        modules[name] = {key:image.crop((x,y,x+w,y+h)) for key,image in atlases.items()}
    size = round(WORLD_RECT[2]*PPM)
    image_set = {'albedo':Image.new('RGBA',(size,size),(119,124,126,255)),
                 'height':Image.new('L',(size,size),255),
                 'orm_dry':Image.new('RGB',(size,size),(255,145,0)),
                 'orm_wet':Image.new('RGB',(size,size),(255,52,0))}
    placements = []

    def place(name,x,y,clip_width=None,clip_height=None):
        module = modules[name]
        if clip_width is not None or clip_height is not None:
            width,height = module['albedo'].size
            bounds = (0,0,clip_width or width,clip_height or height)
            module = {key:image.crop(bounds) for key,image in module.items()}
        mask = module['albedo'].getchannel('A')
        for key in channels:
            image_set[key].paste(module[key],(x,y),mask)
        placements.append({'module':name,'pixel_origin':[x,y]})

    # Keep all ordinary stones whole between the 8px border bands.
    starts = list(range(8,296,16))+list(range(304,912,16))+list(range(920,1208,16))
    rng = np.random.default_rng(913)
    ids = np.full((len(starts),len(starts)),-1,dtype=int)
    for row,y in enumerate(starts):
        for col,x in enumerate(starts):
            forbidden = {ids[row,col-1] if col else -1,ids[row-1,col] if row else -1}
            variant = int(rng.choice([i for i in range(16) if i not in forbidden]))
            ids[row,col] = variant
            place(f'stone_{variant:02d}',x,y)
    bands = [0,296,912,size-8]
    for p in bands:
        for along in range(0,size,32):
            place('band_horizontal',along,p)
            place('band_vertical',p,along)
        for along in [144,592,1040]:
            place('band_diamond_horizontal',along,p)
            place('band_diamond_vertical',p,along)
    for x in bands:
        for y in bands:
            place('band_cross',x,y)
    # Frame the grass pockets from the paved side; the pockets themselves remain
    # untouched terrain cells and keep their existing grass eligibility.
    for cx,cz in POCKET_CENTERS:
        x = round(((cx-1)*1.6-.8-WORLD_RECT[0])*PPM)
        y = round(((cz-1)*1.6-.8-WORLD_RECT[1])*PPM)
        span = 192
        for along in range(0,span+8,32):
            remaining = min(32,span+8-along)
            place('band_horizontal',x-8+along,y-8,clip_width=remaining)
            place('band_horizontal',x-8+along,y+span,clip_width=remaining)
            place('band_vertical',x-8,y-8+along,clip_height=remaining)
            place('band_vertical',x+span,y-8+along,clip_height=remaining)
        for dx,dy in [(-8,-8),(span,-8),(-8,span),(span,span)]:
            place('band_cross',x+dx,y+dy)
    for x,y in [(456,264),(744,264),(456,936),(744,936),(264,584),(936,584)]:
        place('stone_inlay_00',x,y)
    center = size//2
    place('center_octagon',center-72,center-72)
    place('center_arrow_left',center-96,center-24)
    place('center_arrow_right',center+72,center-24)

    # Enlarge the entire composition, including borders, ornaments and all maps.
    # World coverage grows equally to keep the file density at 40 pixels/metre.
    world_rect = list(WORLD_RECT)
    if material_scale != 1:
        size *= material_scale
        image_set = {key:image.resize((size,size),Image.Resampling.NEAREST)
                     for key,image in image_set.items()}
        world_rect = [WORLD_RECT[0]+WORLD_RECT[2]*(1-material_scale)/2,
                      WORLD_RECT[1]+WORLD_RECT[3]*(1-material_scale)/2,
                      WORLD_RECT[2]*material_scale,WORLD_RECT[3]*material_scale]
        for item in placements:
            item['pixel_origin'] = [p*material_scale for p in item['pixel_origin']]

    height = np.asarray(image_set['height']).astype(np.float32)/255*.004
    padded = np.pad(height,1,mode='edge')
    sx = (padded[1:-1,2:]-padded[1:-1,:-2])/(2/PPM)
    sy = (padded[2:,1:-1]-padded[:-2,1:-1])/(2/PPM)
    normal = np.stack([-sx,sy,np.ones_like(height)],axis=2)
    normal /= np.linalg.norm(normal,axis=2,keepdims=True)
    image_set['normal_gl'] = Image.fromarray(np.rint((normal*.5+.5)*255).astype('uint8'))
    assert np.asarray(image_set['albedo'])[:,:,3].min() == 255
    assert np.asarray(image_set['orm_dry'])[:,:,2].max() == 0
    output.mkdir(parents=True,exist_ok=True)
    for key,image in image_set.items():
        image.save(output/f'battle_{key}.png')

    # Preserve serialization and every array except the selected paint bytes.
    data_text = terrain_path.read_text(encoding='utf-8')
    origin = tuple(map(int,re.search(r'origin = Vector2i\((-?\d+), (-?\d+)\)',data_text).groups()))
    dimensions = tuple(map(int,re.search(r'size = Vector2i\((\d+), (\d+)\)',data_text).groups()))
    match = re.search(r'paints = PackedByteArray\("([^"\n]*)"\)',data_text)
    paints = bytearray(base64.b64decode(match.group(1)))
    assert len(paints) == dimensions[0]*dimensions[1]
    before = paints.copy()
    pockets = {(cx+dx,cz+dz) for cx,cz in POCKET_CENTERS for dx in (-1,0,1) for dz in (-1,0,1)}
    painted = []
    skipped = []
    for z in range(19,38):
        for x in range(-9,10):
            if (x,z) in pockets:
                continue
            index = (z-origin[1])*dimensions[0]+x-origin[0]
            if paints[index] not in (0,PAINT_ID):
                skipped.append([x,z])
                continue
            paints[index] = PAINT_ID
            painted.append([x,z])
    if apply:
        encoded = base64.b64encode(paints).decode('ascii')
        updated = data_text[:match.start(1)]+encoded+data_text[match.end(1):]
        with terrain_path.open('w',encoding='utf-8',newline='') as stream:
            stream.write(updated)
    summary = {'world_rect':world_rect,'pixels_per_meter':PPM,'size_pixels':[size,size],
               'paint_id':PAINT_ID,'painted_cells':len(painted),'grass_pocket_cells':len(pockets),
               'preserved_existing_paint_cells':skipped,'map_saved':apply,
               'height_range_m':[0,.004],'normal_convention':'OpenGL','metallic':0}
    if material_scale != 1:
        summary.update(material_scale=material_scale,stone_pixels=16*material_scale,
                       stone_meters=.4*material_scale,sampling='nearest')
    (output/'layout.json').write_text(json.dumps({**summary,'grass_pocket_centers_cells':POCKET_CENTERS,
        'module_placements':placements},indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=PROJECT/'assets/ground/battle_paving')
    parser.add_argument('--terrain',type=Path,default=PROJECT/'data/world/world_terrain.tres')
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--material-scale',type=int,choices=(1,2,4),default=1,
                        help='Enlarge all modules equally; 4 makes 64px / 1.6m stones.')
    args = parser.parse_args()
    build(args.output,args.terrain,args.apply,args.material_scale)
