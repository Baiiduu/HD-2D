"""Bake small, deterministic brush patches using the existing terrain masks."""
import base64
import json
import math
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "demoWithMeowa/1"
terrain = (PROJECT / "data/four_realms_terrain.tres").read_text(encoding="utf-8")
origin = tuple(map(int, re.search(r"origin = Vector2i\((-?\d+), (-?\d+)\)", terrain).groups()))
size = tuple(map(int, re.search(r"size = Vector2i\((\d+), (\d+)\)", terrain).groups()))
fields = {
    key: list(base64.b64decode(re.search(key + r' = PackedByteArray\("(.*?)"\)', terrain).group(1)))
    for key in ("biomes", "overlays", "heights")
}
CELL = 1.6
RNG = random.Random(10102026)
items = []


def sample(x, z):
    cx, cz = math.floor(x / CELL + 0.5), math.floor(z / CELL + 0.5)
    ix, iz = cx - origin[0], cz - origin[1]
    if not (0 <= ix < size[0] and 0 <= iz < size[1]):
        return None
    index = iz * size[0] + ix
    return cx, cz, fields["biomes"][index], fields["overlays"][index], fields["heights"][index] - 8


def allowed(x, z, category, edge_margin=None):
    here = sample(x, z)
    if here is None:
        return False
    cx, cz, biome, overlay, level = here
    # Keep the road, dirt walking route, water, bridge and ramp clear.
    if overlay != 0 or (category != "pebbles" and biome != 3):
        return False
    # Small stones at paving edges are also allowed in the courtyard and street.
    if category == "pebbles" and biome not in (0, 2, 3):
        return False
    # Keep the entire illustrated base away from water, cliff lips and paths.
    margin = edge_margin if edge_margin is not None else (0.30 if category != "pebbles" else 0.16)
    for dx, dz in ((margin, 0), (-margin, 0), (0, margin), (0, -margin)):
        other = sample(x + dx, z + dz)
        if other is None or other[3] != 0 or other[4] != level:
            return False
    for ax, az in ((0, 1.4), (4.7, 8.5), (6.9, 8.5)):
        if math.hypot(x - ax, z - az) < 0.95:
            return False
    gap = 0.80 if category != "pebbles" else 0.30
    for item in items:
        other_gap = 0.30 if item["asset"].startswith("pebbles") else 0.80
        px, _, pz = item["position"]
        if math.hypot(x - px, z - pz) < (gap + other_gap) * 0.5:
            return False
    return True


WEIGHTS = {
    "grass": [18, 6, 1, 1, 3, 1],
    "flowers": [9, 8, 7, 0.4, 0.4, 0.4],
    "pebbles": [4, 4, 4, 3, 2, 1],
}


def stamp(category, center, radius, count, variants=None, edge_margin=None):
    placed = 0
    choices = variants or list(range(1, 7))
    weights = [WEIGHTS[category][index - 1] for index in choices]
    for _ in range(count * 90):
        angle = RNG.uniform(0, math.tau)
        distance = radius * math.sqrt(RNG.random())
        x = round(center[0] + math.cos(angle) * distance, 4)
        z = round(center[1] + math.sin(angle) * distance, 4)
        if not allowed(x, z, category, edge_margin):
            continue
        level = sample(x, z)[4]
        variant = RNG.choices(choices, weights=weights)[0]
        items.append({
            "asset": f"{category}_{variant:02d}",
            "position": [x, round(level * 0.8 + 0.02, 4), z],
            "density_rank": round(RNG.random(), 5),
        })
        placed += 1
        if placed == count:
            break
    return placed


# Brush centers form several patches, with clear ground between them.
patches = [
    ((2.0, 2.2), 1.05, 2, 1),
    ((2.4, 4.5), 1.25, 3, 2),
    ((2.0, 7.0), 1.35, 2, 1),
    ((6.9, 1.6), 1.1, 3, 1),
    ((7.6, 3.6), 1.35, 4, 2),
    ((7.8, 6.2), 1.4, 3, 1),
    ((9.7, 8.6), 1.1, 2, 1),
    ((10.8, 2.5), 1.45, 4, 2),
    ((11.5, 5.6), 1.6, 4, 2),
]
for center, radius, grass_count, flower_count in patches:
    stamp("flowers", center, radius * 0.72, flower_count)
    stamp("grass", center, radius, grass_count)
for center, radius, count in [
    ((1.3, 3.6), 0.6, 2), ((2.5, 8.4), 0.9, 3),
    ((6.3, 2.8), 1.0, 3), ((6.8, 6.0), 1.0, 2),
    ((9.3, 4.6), 1.1, 3), ((11.5, 7.2), 1.25, 3),
    ((-1.35, 2.7), 0.35, 2), ((-1.4, -1.2), 0.45, 2),
]:
    stamp("pebbles", center, radius, count)

# Extend the same sparse patches across the northern terraces on both sides
# of the stream. Append after the original stamps to keep their positions intact.
upper_patches = [
    ((13.8, -8.0), 1.30, 3, 1),
    ((17.5, -8.6), 1.40, 3, 1),
    ((20.2, -7.1), 1.20, 3, 1),
    ((13.6, -3.4), 1.10, 3, 1),
    ((18.4, -3.2), 1.10, 3, 1),
    ((20.5, -3.2), 1.00, 2, 1),
    ((13.5, -1.6), 0.85, 2, 1),
    ((18.0, -1.5), 0.85, 2, 1),
    ((24.8, -8.0), 1.20, 3, 1),
    ((24.9, -3.0), 1.00, 2, 1),
    ((27.3, -8.8), 0.90, 2, 1),
    ((31.0, -8.5), 1.30, 4, 2),
    ((32.8, -6.4), 1.10, 3, 1),
    ((30.8, -6.0), 1.00, 3, 1),
    ((27.2, -6.3), 0.90, 2, 1),
    ((35.2, -8.2), 0.85, 2, 1),
    ((28.0, -3.0), 1.00, 3, 1),
    ((32.5, -3.0), 1.20, 3, 1),
    ((35.2, -3.2), 0.85, 2, 1),
    ((25.0, -1.5), 0.85, 2, 1),
    ((29.0, -1.5), 0.85, 2, 1),
    ((33.5, -1.5), 0.85, 2, 1),
]
for center, radius, grass_count, flower_count in upper_patches:
    stamp("flowers", center, radius * 0.72, flower_count, edge_margin=0.45)
    stamp("grass", center, radius, grass_count, edge_margin=0.45)

layout = {
    "seed": 10102026,
    "description": "Sparse grass and flower patches near the starting wilderness and across the northeast terraces. Original pebble positions are retained but their layer is disabled in the main scene.",
    "instances": items,
}
path = PROJECT / "data/dressing_layout.json"
path.write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
print("Saved", path)
for category in WEIGHTS:
    print(category, sum(item["asset"].startswith(category) for item in items))
print("total", len(items), "variants", len({item["asset"] for item in items}))
