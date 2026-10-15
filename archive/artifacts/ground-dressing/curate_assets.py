"""Package selected Meowa pixels without resampling or repainting."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent / "demoWithMeowa/1"
DEST = PROJECT / "assets/meowa/dressing"
COMPONENTS = ROOT / "components"
CANVAS = (48, 48)
ANCHOR = (24, 44)
PIXEL_SIZE = 0.0234375


def component(number):
    path = COMPONENTS / f"component_{number:03d}.png"
    return Image.open(path).convert("RGBA"), path


def combine(parts):
    width = max(x + im.width for im, x, y in parts)
    height = max(y + im.height for im, x, y in parts)
    im = Image.new("RGBA", (width, height))
    for part, x, y in parts:
        im.alpha_composite(part, (x, y))
    return im


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--white", type=Path, required=True)
    parser.add_argument("--pink", type=Path, required=True)
    parser.add_argument("--purple", type=Path, required=True)
    args = parser.parse_args()
    assets = []

    def save(category, number, label, image, sources):
        alpha_values = set(image.getchannel("A").get_flattened_data())
        if not alpha_values <= {0, 255}:
            raise ValueError(f"Unexpected partial alpha in {label}: {alpha_values}")
        bbox = image.getbbox()
        if not bbox:
            raise ValueError(f"Empty sprite: {label}")
        native = image.crop(bbox)
        if native.width > 40 or native.height > 40:
            raise ValueError(f"Oversized sprite: {label} {native.size}")
        canvas = Image.new("RGBA", CANVAS)
        x = ANCHOR[0] - native.width // 2
        y = ANCHOR[1] - native.height
        canvas.paste(native, (x, y))
        folder = DEST / category
        folder.mkdir(parents=True, exist_ok=True)
        filename = f"{category[:-1] if category != 'grass' else 'grass'}_{number:02d}.png"
        # Use the conventional English singular for pebble filenames.
        if category == "pebbles":
            filename = f"pebble_{number:02d}.png"
        path = folder / filename
        canvas.save(path)
        assets.append({
            "id": f"{category}_{number:02d}", "name": label,
            "texture": "res://" + path.relative_to(PROJECT).as_posix(),
            "file": path.relative_to(DEST).as_posix(),
            "canvas": list(CANVAS), "visible_size": list(native.size),
            "anchor": list(ANCHOR), "pixel_size": PIXEL_SIZE,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "sources": [str(p.resolve()) for p in sources],
        })

    for number, (label, path) in enumerate([
        ("双朵白色矮花", args.white),
        ("三朵粉色矮花", args.pink),
        ("簇生淡紫矮花", args.purple),
    ], 1):
        save("flowers", number, label, Image.open(path).convert("RGBA"), [path])
    for number, cid, label in [
        (4, 22, "黄色细茎野花"),
        (5, 36, "蓝色双朵野花"),
        (6, 30, "红色野花与花苞"),
    ]:
        im, path = component(cid)
        save("flowers", number, label, im, [path])

    for number, cid, label in [
        (1, 34, "低矮疏草"),
        (2, 8, "展开密草"),
        (3, 9, "细长草叶"),
        (4, 7, "羽叶杂草"),
        (5, 65, "双茎阔叶草"),
        (6, 15, "金黄枯草"),
    ]:
        im, path = component(cid)
        save("grass", number, label, im, [path])

    stones = [component(cid) for cid in [84, 85, 88, 79]]
    for number, ((im, path), label) in enumerate(zip(stones, [
        "暖灰扁石", "小圆灰石", "细扁灰石", "棱角灰石"
    ]), 1):
        save("pebbles", number, label, im, [path])
    pair = combine([(stones[0][0], 0, 3), (stones[1][0], 13, 0)])
    save("pebbles", 5, "两颗碎石", pair, [stones[0][1], stones[1][1]])
    trio = combine([(stones[1][0], 0, 4), (stones[2][0], 11, 5), (stones[3][0], 18, 0)])
    save("pebbles", 6, "三颗碎石", trio, [p for _, p in stones[1:]])

    manifest = {
        "source": "Meowa", "count": len(assets), "canvas": list(CANVAS),
        "anchor": list(ANCHOR), "pixel_size": PIXEL_SIZE,
        "processing": "Native crop and transparent padding; two pebble groups assembled from unchanged source pixels; no resampling or repainting.",
        "assets": assets,
    }
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / "assets.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    font = ImageFont.truetype(str(font_path), 16)
    board = Image.new("RGB", (1008, 670), (31, 37, 43))
    draw = ImageDraw.Draw(board)
    draw.text((24, 14), "Meowa 地编 · 花 / 草 / 小石子 · 原生像素 3× 最近邻预览", fill="#e9e9e9", font=font)
    for i, asset in enumerate(assets):
        row, col = divmod(i, 6)
        x, y = 24 + col * 160, 52 + row * 192
        draw.rectangle((x, y, x + 144, y + 144), fill=(43, 51, 56))
        im = Image.open(DEST / asset["file"]).convert("RGBA")
        zoom = im.resize((144, 144), Image.Resampling.NEAREST)
        board.paste(zoom, (x, y), zoom)
        draw.text((x, y + 146), asset["name"], fill="#e1e5e6", font=font)
        draw.text((x, y + 166), f"{asset['visible_size'][0]}×{asset['visible_size'][1]} px", fill="#a9b7bd", font=font)
    board.save(ROOT / "review.png")
    print(json.dumps({"count": len(assets), "asset_dir": str(DEST), "review": str(ROOT / 'review.png'), "sizes": [a['visible_size'] for a in assets]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
