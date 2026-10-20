"""Rebuild shared and globe ORM maps without modifying native Meowa color texels."""
import json
from pathlib import Path

from PIL import Image, ImageFilter


def globe_motion_masks(color, pixels):
    width, height = color.size
    gold = Image.new('L', color.size)
    gold.putdata([255 if r > 45 and g > 25 and r > b * 1.3 else 0 for r, g, b in pixels])
    bright = bytearray(r > 175 and g > 115 and r > b * 1.35 for r, g, b in pixels)
    phase = Image.new('L', color.size)
    # Bright star cores form small islands. The larger crescent stays steady;
    # dim constellation lines remain steady outside each core's small halo.
    for start in range(len(bright)):
        if not bright[start]: continue
        bright[start] = 0
        island, pending = [], [start]
        while pending:
            index = pending.pop()
            island.append(index)
            x, y = index % width, index // width
            for ny in range(max(0, y - 1), min(height, y + 2)):
                for nx in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = ny * width + nx
                    if bright[neighbor]:
                        bright[neighbor] = 0
                        pending.append(neighbor)
        xs, ys = [i % width for i in island], [i // width for i in island]
        if 2 <= len(island) <= 220 and max(xs) - min(xs) < 30 and max(ys) - min(ys) < 30:
            seed = 32 + (sum(xs) // len(xs) * 73 + sum(ys) // len(ys) * 151) % 224
            for index in island: phase.putpixel((index % width, index // width), seed)
    phase = phase.filter(ImageFilter.MaxFilter(9))
    # The material limits deformation to 0.02 UV: at most 20 horizontal texels.
    # This 22-texel guard also pins the gold halos and prevents moving star ghosts.
    guarded = gold.filter(ImageFilter.MaxFilter(45))
    return list(phase.getdata()), list(gold.getdata()), list(guarded.getdata())


def build_globe_orm(root, layout):
    surface = layout['globe_surface']
    color = Image.open(root / surface['albedo']).convert('RGB')
    assert list(color.size) == surface['size'], 'Keep the native globe crop'
    properties = Image.new('RGBA', color.size)
    colors = list(color.getdata())
    phases, gold, guarded = globe_motion_masks(color, colors)
    pixels = []
    for index, (red, green, blue) in enumerate(colors):
        # Enamel-like color keeps the globe distinct from its metal orbit rails.
        emission = 0.0
        if red > 135 and green > 80 and red > blue * 1.35:
            emission = 0.65  # Sparse gold stars and crescent.
        elif green > 65 and blue > 85 and green > red * 1.3:
            emission = max(0.0, (max(green, blue) - 65) / 190) * 0.48
        elif blue > 85 and blue > green * 1.25 and red > 35:
            emission = max(0.0, (blue - 85) / 170) * 0.25
        phase = phases[index] if gold[index] else 0
        flow = min(1.0, max(0.0, (max(green, blue) - 65) / 110)) if blue > red * 1.15 else 0.0
        if guarded[index]: flow = 0.0
        # Globe-only packing: R star phase, G roughness, B safe flow mask, A emission.
        pixels.append((phase, 160, round(flow * 255), round(emission * 255)))
    properties.putdata(pixels)
    properties.save(root / surface['orm'])


def main():
    root = Path(__file__).resolve().parents[1] / 'assets/models/cyber_armillary'
    layout = json.loads((root / 'uv_layout.json').read_text(encoding='utf-8'))
    albedo = Image.open(root / 'albedo.png').convert('RGB')
    assert albedo.size == (512, 512), 'Do not resize the native atlas'
    orm = Image.new('RGBA', albedo.size, (255, 220, 0, 0))
    for key, (x, y, width, height) in layout['regions'].items():
        roughness, metallic = 170, 120
        if key in ('base_top', 'deck_face'):
            # Approved recessed titanium panels: broad, restrained reflections.
            roughness, metallic = 165, 190
        elif key == 'stone_edge':
            # Keep the existing atlas region name; this rim is now metal.
            roughness, metallic = 55, 235
        if key in ('silver', 'rail'):
            roughness, metallic = 155, 160
        for py in range(y, y + height):
            for px in range(x, x + width):
                red, green, blue = albedo.getpixel((px, py))
                emission = key in ('cyan', 'amber')
                if key == 'panel':
                    emission = blue > 110 and green > red * 1.3 and blue > red * 1.4
                orm.putpixel((px, py), (255, roughness, metallic, 255 if emission else 0))
    orm.save(root / 'orm.png')
    build_globe_orm(root, layout)
    print('Cyber armillary: neutral AO, material roughness/metallic, emission in alpha; color atlas unchanged.')


if __name__ == '__main__':
    main()
