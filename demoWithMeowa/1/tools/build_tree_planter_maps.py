"""Pack native Meowa planter regions without resampling their artwork."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'assets/meowa/buildings/tree_planter'
REGIONS = ((16, 32, 192, 64), (16, 96, 192, 128), (224, 32, 352, 64),
           (112, 176, 176, 240), (224, 112, 240, 144))


def main():
    source = Image.open(ROOT / 'source/city_material_master.png').convert('RGB')
    if source.size != (512, 512):
        raise ValueError(f'Expected the inspected native 512px source, got {source.size}')
    atlas = Image.new('RGB', source.size, '#303840')
    for left, top, right, bottom in REGIONS:
        crop = source.crop((left, top, right, bottom))
        # Extrude only outside each UV region. Every authored texel stays intact.
        for offset in range(1, 9):
            atlas.paste(crop.crop((0, 0, crop.width, 1)), (left, top-offset))
            atlas.paste(crop.crop((0, crop.height-1, crop.width, crop.height)), (left, bottom+offset-1))
            atlas.paste(crop.crop((0, 0, 1, crop.height)), (left-offset, top))
            atlas.paste(crop.crop((crop.width-1, 0, crop.width, crop.height)), (right+offset-1, top))
        atlas.paste(crop, (left, top))
    atlas.save(ROOT / 'city_panels.png')
    cap = source.crop((16, 176, 80, 240))
    # The source layout has a one-pixel frame; extend the actual stone up to it.
    cap.paste(cap.crop((1, 0, 2, 64)), (0, 0))
    cap.paste(cap.crop((62, 0, 63, 64)), (63, 0))
    cap.paste(cap.crop((0, 1, 64, 2)), (0, 0))
    cap.paste(cap.crop((0, 62, 64, 63)), (0, 63))
    cap.save(ROOT / 'city_cap.png')
    print('Packed city_panels.png (512x512), city_cap.png (64x64); native pixels preserved')


if __name__ == '__main__':
    main()
