"""Prepare one complete drawing sheet, then pack native Meowa pixels and material maps."""
import argparse
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "assets/models/pocket_universe_nursery"
SIZE = 1024
PADDING = 4
PALETTE = {"wall": (183, 195, 200), "edge": (51, 66, 75), "glass": (37, 78, 91),
           "brass": (159, 120, 70), "roof": (159, 175, 183), "cyan": (102, 207, 216)}


def region(rect, kind, label):
    return {"rect": rect, "kind": kind, "label": label}


def layout():
    regions = {}
    for key, x, width, label in [("front", 8, 216, "SOUTH FRONT"), ("right", 240, 204, "EAST RIGHT"),
                                  ("back", 460, 216, "NORTH REAR"), ("left", 692, 204, "WEST LEFT")]:
        regions[key] = region([x, 8, width, 288], "facade", label)
    regions.update({
        "mast": region([920, 8, 32, 280], "metal", "MAST"),
        "pipe": region([968, 8, 16, 280], "brass", "PIPE"),
        "upper_roof": region([8, 312, 288, 256], "roof", "UPPER ROOF"),
        "gallery_roof": region([312, 312, 288, 256], "roof", "GALLERY DECK"),
        "lower_roof": region([616, 312, 288, 256], "roof", "LAB ROOF"),
        "planet": region([8, 584, 280, 144], "planet", "PLANET EQUIRECTANGULAR"),
        "moon": region([8, 744, 64, 32], "planet", "MOON"),
        "orbit": region([88, 744, 120, 8], "light", "ORBIT"),
        "hub": region([320, 592, 40, 40], "device", "GAUGE"),
        "cradle": region([376, 592, 96, 96], "metal", "MAGNETIC CRADLE"),
        "vent_top": region([488, 592, 40, 32], "metal", "TOP VENT"),
        "vent": region([544, 592, 48, 40], "metal", "VENT"),
        "terminal": region([320, 648, 24, 32], "device", "ACCESS"),
        "cap": region([488, 648, 40, 40], "metal", "ROOF CAP"),
        "trim": region([544, 648, 40, 40], "metal", "TRIM"),
        "service_door": region([320, 704, 48, 96], "facade", "SERVICE DOOR"),
        "service_panel": region([384, 704, 40, 56], "metal", "SIDE SERVICE"),
        "rear_vent": region([440, 704, 48, 40], "metal", "REAR VENT"),
        "cabinet": region([528, 704, 64, 64], "metal", "PLANT CABINET"),
        "entry_jamb": region([320, 816, 24, 104], "metal", "DOOR RECESS"),
        "underside": region([360, 816, 64, 64], "metal", "UNDERSIDE"),
        "main_door": region([448, 792, 64, 104], "facade", "MAIN DOOR"),
        "entry_light": region([528, 792, 64, 8], "light", "CANOPY LIGHT"),
        "inner_gallery": region([8, 936, 576, 40], "glass", "INNER OBSERVATION BAND"),
        "inner_upper": region([8, 992, 368, 24], "metal", "INNER UPPER SHELL"),
        "plain_shell": region([616, 584, 128, 128], "shell", "PAINTED SHELL"),
        "equipment": region([760, 584, 128, 128], "metal", "EQUIPMENT PANELS"),
    })
    return {"atlas_size": [SIZE, SIZE], "pixels_per_meter": 80, "padding_pixels": PADDING,
            "uv_origin": "top-left", "body_dimensions_m": [3.6, 3.8, 3.2],
            "facade_y_top_m": 3.6, "regions": regions}


def panel(draw, box, fill, inset=2):
    draw.rectangle(box, fill=PALETTE["edge"])
    x0, y0, x1, y1 = box
    if x1-x0 > inset*2 and y1-y0 > inset*2:
        draw.rectangle((x0+inset, y0+inset, x1-inset, y1-inset), fill=fill)


def windows(draw, x, y, width, height, warm=False):
    panel(draw, (x, y, x+width-1, y+height-1), (111, 112, 88) if warm else PALETTE["glass"])
    for pos in range(x+15, x+width-3, 23):
        draw.line((pos, y+2, pos, y+height-3), fill=(75, 91, 99), width=2)
    draw.line((x+4, y+4, x+width-5, y+4), fill=(103, 146, 153))


def draw_facade(image, key, info):
    x, y, width, height = info["rect"]
    patch = Image.new("RGB", (width, height), PALETTE["wall"])
    d = ImageDraw.Draw(patch)
    # Physical levels in a single elevation rectangle: all four sides share these rows.
    for level in [1.45, 1.56, 1.64, 1.96, 2.05, 3.08, 3.2, 3.56]:
        row = round((3.6-level)*80)
        d.line((0, row, width-1, row), fill=PALETTE["edge"])
    # The gap has no receiving shell; flat dark neutral avoids baking a second planet.
    d.rectangle((0, 45, width-1, 122), fill=(42, 54, 63))
    windows(d, 2, 29, width-4, 12)
    windows(d, 2, 126, width-4, 29, warm=key == "right")
    for pos in range(20, width, 42):
        d.line((pos, 2, pos, 27), fill=(103, 120, 130))
    if key == "front":
        windows(d, 5, 194, 42, 66)
        windows(d, width-47, 194, 42, 66, True)
        panel(d, (width//2-34, 182, width//2+34, 287), PALETTE["glass"])
        d.line((width//2, 184, width//2, 285), fill=PALETTE["wall"], width=2)
        panel(d, (width//2-32, 174, width//2+32, 178), (233, 184, 101), 1)
    elif key == "back":
        windows(d, 5, 188, width-10, 32)
        panel(d, (width-78, 192, width-30, 287), (66, 83, 92))
        panel(d, (18, 232, 75, 272), (103, 119, 128))
    elif key == "left":
        windows(d, 8, 193, width-16, 68)
        panel(d, (18, 268, 80, 281), (76, 92, 100))
    else:
        windows(d, 10, 194, 56, 67, True)
        panel(d, (87, 220, 148, 277), (118, 132, 140))
        d.rectangle((width-27, 182, width-16, 284), fill=PALETTE["brass"])
    d.line((0, 282, width-1, 282), fill=(92, 110, 121), width=3)
    image.paste(patch, (x, y))


def draw_roof(image, key, info):
    x, y, width, height = info["rect"]
    patch = Image.new("RGB", (width, height), PALETTE["roof"])
    d = ImageDraw.Draw(patch)
    for radius in [0.99, 0.94, 0.66, 0.62]:
        rx, ry = width*radius/2-2, height*radius/2-2
        d.ellipse((width/2-rx, height/2-ry, width/2+rx, height/2+ry), outline=(83, 104, 116), width=2)
    for angle in range(0, 360, 30):
        a = math.radians(angle)
        d.line((width/2+math.sin(a)*width*.34, height/2+math.cos(a)*height*.34,
                width/2+math.sin(a)*width*.47, height/2+math.cos(a)*height*.47), fill=(108, 128, 140))
    if key == "upper_roof":
        panel(d, (63, 27, 90, 47), (70, 89, 102))
        panel(d, (127, 17, 148, 38), (70, 89, 102))
        d.ellipse((194, 29, 220, 55), fill=(102, 113, 112), outline=PALETTE["brass"], width=3)
        d.line((238, 38, 253, 63), fill=PALETTE["brass"], width=4)
    elif key == "gallery_roof":
        d.ellipse((52, 44, 236, 212), outline=(156, 135, 93), width=2)
    else:
        d.ellipse((95, 79, 193, 177), fill=(58, 83, 98), outline=PALETTE["brass"], width=3)
        d.line((34, 124, 66, 124), fill=(91, 112, 124), width=3)
    image.paste(patch, (x, y))


def prepare():
    (ROOT / "source").mkdir(parents=True, exist_ok=True)
    (ROOT / "textures").mkdir(exist_ok=True)
    (ROOT / "source/.gdignore").touch()
    data = layout()
    occupancy = np.zeros((SIZE, SIZE), bool)
    image = Image.new("RGB", (SIZE, SIZE), (27, 34, 42))
    d = ImageDraw.Draw(image)
    for key, info in data["regions"].items():
        x, y, w, h = info["rect"]
        assert x >= PADDING and y >= PADDING and x+w+PADDING <= SIZE and y+h+PADDING <= SIZE
        area = occupancy[y-PADDING:y+h+PADDING, x-PADDING:x+w+PADDING]
        assert not area.any(), key
        area[:] = True
        fill = PALETTE["wall"] if info["kind"] in ["facade", "shell"] else PALETTE["roof"]
        d.rectangle((x, y, x+w-1, y+h-1), fill=fill)
        d.text((x, max(0, y-8)), info["label"], fill=(183, 191, 201))
        if key in ["front", "right", "back", "left"]: draw_facade(image, key, info)
        elif key.endswith("roof"): draw_roof(image, key, info)
        elif key in ["main_door", "service_door"]:
            panel(d, (x, y, x+w-1, y+h-1), PALETTE["glass"])
            if key == "main_door":
                d.line((x+w//2, y+2, x+w//2, y+h-3), fill=PALETTE["wall"], width=2)
                for offset in [-5, 5]: d.rectangle((x+w//2+offset, y+h//2, x+w//2+offset+1, y+h//2+9), fill=PALETTE["brass"])
            else: d.rectangle((x+6, y+8, x+w-7, y+23), fill=(40, 53, 64))
        elif key == "planet":
            d.rectangle((x, y, x+w-1, y+h-1), fill=(30, 75, 140))
            for points in [[(12, 37), (46, 25), (67, 35), (90, 28), (112, 52), (83, 69), (52, 65), (45, 88), (22, 65)],
                           [(161, 64), (189, 42), (220, 57), (241, 50), (269, 80), (243, 103), (207, 102), (201, 126), (175, 113)]]:
                d.polygon([(x+a, y+b) for a, b in points], fill=(94, 164, 176))
            for start in [15, 101, 186]:
                d.line((x+start, y+23, x+start+47, y+16), fill=(184, 218, 222), width=3)
        elif key == "moon":
            d.rectangle((x, y, x+w-1, y+h-1), fill=(153, 180, 190))
            d.ellipse((x+8, y+7, x+18, y+18), outline=(112, 141, 157), width=2)
        elif key == "hub":
            d.ellipse((x+1, y+1, x+w-2, y+h-2), fill=PALETTE["brass"], outline=PALETTE["edge"], width=2)
            d.ellipse((x+7, y+7, x+w-8, y+h-8), fill=PALETTE["glass"], outline=PALETTE["cyan"], width=2)
        elif key in ["cap", "cradle"]:
            d.ellipse((x+1, y+1, x+w-2, y+h-2), fill=(83, 107, 120), outline=PALETTE["brass"], width=3)
            d.ellipse((x+7, y+7, x+w-8, y+h-8), outline=PALETTE["cyan"], width=2)
        elif "vent" in key:
            panel(d, (x, y, x+w-1, y+h-1), (75, 96, 107))
            for row in range(y+5, y+h-4, 4): d.line((x+4, row, x+w-5, row), fill=PALETTE["edge"], width=2)
        elif key in ["orbit", "entry_light"]:
            d.rectangle((x, y, x+w-1, y+h-1), fill=PALETTE["cyan"] if key == "orbit" else (238, 192, 109))
        elif key == "pipe":
            d.rectangle((x, y, x+w-1, y+h-1), fill=PALETTE["brass"])
            for row in range(y+8, y+h, 38): d.line((x, row, x+w-1, row), fill=PALETTE["edge"], width=2)
        elif key.startswith("inner_"):
            windows(d, x, y, w, h, False)
        elif key == "mast":
            panel(d, (x, y, x+w-1, y+h-1), (89, 105, 113))
            for row in range(y+20, y+h, 38): panel(d, (x+4, row, x+w-5, row+17), PALETTE["glass"], 1)
        else:
            panel(d, (x, y, x+w-1, y+h-1), fill)
    (ROOT / "pocket_universe_uv_layout.json").write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    image.save(ROOT / "source/drawing_layout.png")
    print("Prepared 1024 atlas with", len(data["regions"]), "regions at ~80px/m")


def finish(source):
    data = json.loads((ROOT / "pocket_universe_uv_layout.json").read_text(encoding="utf-8"))
    original = Image.open(source).convert("RGBA")
    assert original.getchannel("A").getextrema() == (255, 255), "Opaque atlas must not contain holes"
    image = original.convert("RGB")
    assert image.size == (SIZE, SIZE), "Keep native pixels; output canvas must match the drawing sheet"
    image.save(ROOT / "source/style_master.png")
    rgb = np.asarray(image)
    albedo = np.full((SIZE, SIZE, 3), PALETTE["wall"], np.uint8)
    normal = np.full((SIZE, SIZE, 3), [128, 128, 255], np.uint8)
    orm = np.full((SIZE, SIZE, 3), [255, 230, 0], np.uint8)
    emission = np.zeros((SIZE, SIZE, 3), np.uint8)
    for key, info in data["regions"].items():
        x, y, w, h = info["rect"]
        patch = rgb[y:y+h, x:x+w].copy()
        color = patch.astype(np.float32)/255
        luminance = color @ [.2126, .7152, .0722]
        chroma = np.ptp(color, axis=2)
        dark = (luminance < .34) & (chroma < .22)
        smooth = (color[..., 2] > color[..., 0]*1.12) & (color[..., 1] > color[..., 0]*1.06)
        rough = np.full((h, w), .88, np.float32)
        metal = np.full((h, w), .08, np.float32)
        ao = np.ones((h, w), np.float32)
        height = np.zeros((h, w), np.float32)
        kind = info["kind"]
        if kind in ["metal", "brass", "device"]:
            rough[:] = .65 if kind == "brass" else .74
            metal[:] = .52 if kind == "brass" else .28
        if kind in ["facade", "glass", "device"]:
            rough[smooth] = .38
            metal[smooth] = .06
            p = np.pad(dark.astype(np.int16), 1, mode="edge")
            neighbours = sum(p[j:j+h, i:i+w] for j in range(3) for i in range(3))
            coherent = dark & (neighbours >= 5)
            height[coherent] = .10
            ao[coherent] = .985
        if kind in ["planet", "light"]:
            rough[:] = .82 if kind == "planet" else .5
            metal[:] = 0
            height[:] = 0
        # Small coherent frame relief only; no luminance-derived cloud/crack relief.
        blurred = np.asarray(Image.fromarray(np.rint(height*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(.65)), np.float32)/255
        p = np.pad(blurred, 1, mode="edge")
        nx = (p[1:-1, :-2]-p[1:-1, 2:])*.5
        ny = (p[2:, 1:-1]-p[:-2, 1:-1])*.5
        vectors = np.stack([nx, ny, np.ones_like(nx)], axis=-1)
        vectors /= np.linalg.norm(vectors, axis=-1, keepdims=True)
        n = np.rint((vectors*.5+.5)*255).astype(np.uint8)
        packed = np.rint(np.stack([ao, rough, metal], axis=-1)*255).astype(np.uint8)
        glow = np.zeros((h, w), np.float32)
        if kind == "light": glow[:] = .8
        if key in ["hub", "terminal", "mast"]:
            glow[(color[..., 2] > .55) & (color[..., 1] > .55) & (color[..., 0] < .65)] = .4
        light = np.rint(patch.astype(np.float32)*glow[..., None]).astype(np.uint8)
        for target, pixels in [(albedo, patch), (normal, n), (orm, packed), (emission, light)]:
            target[y-PADDING:y+h+PADDING, x-PADDING:x+w+PADDING] = np.pad(pixels, ((PADDING,PADDING),(PADDING,PADDING),(0,0)), mode="edge")
        assert np.array_equal(albedo[y:y+h, x:x+w], patch)
    for name, pixels in [("albedo", albedo), ("normal", normal), ("orm", orm), ("emission", emission)]:
        Image.fromarray(pixels).save(ROOT / f"textures/pocket_universe_{name}.png")
    for path in (ROOT / "textures").glob("*.png.import"):
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"(?m)^compress/mode=\d+$", "compress/mode=0", text)
        text = text.replace("mipmaps/generate=true", "mipmaps/generate=false")
        path.write_text(text, encoding="utf-8")
    print("Packed native source pixels; albedo + mild OpenGL normal + ORM + local emission, all 1024x1024")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    finish(args.source) if args.source else prepare()
