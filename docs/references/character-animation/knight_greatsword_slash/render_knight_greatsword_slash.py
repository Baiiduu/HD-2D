"""Render an independent comic-style greatsword slash with a depth buffer.

Only writes its own deliverables. No Godot scenes or project settings are used.
Requires numpy and Pillow. Run with --output <directory>.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


SIZE = 640
AA = 2
RES = SIZE * AA
COUNT = 24
CAMERA_Z = 7.0
FOCAL = 558.0 * AA
ORIGIN = np.array([SIZE * 0.475, SIZE * 0.515], dtype=np.float32) * AA
BLADE_LENGTH = 3.45
INK = (26, 35, 49)

U = np.array([-0.724, 0.690, 0.0], dtype=np.float64)
U /= np.linalg.norm(U)
W = np.array([0.180, 0.200, 0.963], dtype=np.float64)
W -= U * np.dot(U, W)
W /= np.linalg.norm(W)
PLANE_NORMAL = np.cross(U, W)
PLANE_NORMAL /= np.linalg.norm(PLANE_NORMAL)
LIGHT = np.array([-0.42, 0.74, 0.76], dtype=np.float32)
LIGHT /= np.linalg.norm(LIGHT)

MATERIALS = {
    "steel": ((91, 128, 155), (175, 211, 230), (225, 243, 249)),
    "steel_bright": ((126, 162, 186), (208, 231, 241), (248, 253, 253)),
    "steel_edge": ((58, 94, 124), (118, 162, 188), (191, 222, 238)),
    "ridge": ((162, 194, 213), (235, 249, 251), (255, 255, 250)),
    "gold": ((113, 74, 41), (211, 157, 68), (255, 216, 121)),
    "gold_light": ((151, 100, 48), (239, 191, 95), (255, 235, 166)),
    "leather": ((47, 32, 40), (101, 48, 53), (155, 76, 68)),
    "wrap": ((74, 43, 47), (164, 98, 74), (211, 148, 104)),
    "gem": ((67, 25, 45), (157, 44, 64), (237, 101, 97)),
}

KEY_T = [0.0, 0.16, 0.24, 0.34, 0.44, 0.54, 0.72, 0.84, 1.0]
KEY_A = [-0.44, -0.64, -0.54, 0.18, 1.58, 2.44, 2.91, 2.94, 2.94]
KEY_V = [0.0, 0.0, 2.0, 12.0, 12.0, 5.2, 0.55, 0.0, 0.0]


def angle_at(t: float) -> float:
    t = max(0.0, min(1.0, t))
    k = min(int(np.searchsorted(KEY_T, t, side="right")) - 1, len(KEY_T) - 2)
    k = max(k, 0)
    dt = KEY_T[k + 1] - KEY_T[k]
    s = (t - KEY_T[k]) / dt
    return (
        (2 * s**3 - 3 * s**2 + 1) * KEY_A[k]
        + (s**3 - 2 * s**2 + s) * dt * KEY_V[k]
        + (-2 * s**3 + 3 * s**2) * KEY_A[k + 1]
        + (s**3 - s**2) * dt * KEY_V[k + 1]
    )


def angular_speed(t: float) -> float:
    return (angle_at(t + 0.0005) - angle_at(t - 0.0005)) / 0.001


def pose(t: float) -> tuple[np.ndarray, np.ndarray]:
    a = angle_at(t)
    length_axis = U * math.cos(a) + W * math.sin(a)
    width_axis = PLANE_NORMAL.copy()
    normal_axis = np.cross(width_axis, length_axis)
    # A small controlled wrist roll exposes the bevels without bending the sword.
    roll = 0.13 + 0.17 * math.sin(a + 0.4)
    width_axis = width_axis * math.cos(roll) + normal_axis * math.sin(roll)
    normal_axis = np.cross(width_axis, length_axis)
    rotation = np.column_stack((width_axis, length_axis, normal_axis))
    progress = max(0.0, min(1.0, (t - 0.22) / 0.58))
    progress = progress * progress * (3.0 - 2.0 * progress)
    pivot = np.array([-0.05 + 0.16 * progress, 0.0 - 0.13 * progress, 0.02])
    return rotation, pivot


def world(points, t: float) -> np.ndarray:
    rotation, pivot = pose(t)
    return np.asarray(points, dtype=np.float64) @ rotation.T + pivot


def project(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    d = CAMERA_Z - points[:, 2]
    xy = points[:, :2] * (FOCAL / d[:, None])
    xy[:, 1] *= -1
    return (xy + ORIGIN).astype(np.float32), d.astype(np.float32)


def triangle_fragments(points: np.ndarray, depth: np.ndarray):
    xmin = max(0, int(math.floor(float(points[:, 0].min()))))
    xmax = min(RES - 1, int(math.ceil(float(points[:, 0].max()))))
    ymin = max(0, int(math.floor(float(points[:, 1].min()))))
    ymax = min(RES - 1, int(math.ceil(float(points[:, 1].max()))))
    if xmin > xmax or ymin > ymax:
        return None
    x0, y0 = points[0]
    x1, y1 = points[1]
    x2, y2 = points[2]
    area = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if abs(float(area)) < 0.01:
        return None
    yy, xx = np.mgrid[ymin : ymax + 1, xmin : xmax + 1].astype(np.float32)
    xx += 0.5
    yy += 0.5
    b0 = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / area
    b1 = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / area
    b2 = 1.0 - b0 - b1
    inside = (b0 >= 0.0) & (b1 >= 0.0) & (b2 >= 0.0)
    if not np.any(inside):
        return None
    yy_i, xx_i = np.nonzero(inside)
    inv_d = b0[inside] / depth[0] + b1[inside] / depth[1] + b2[inside] / depth[2]
    return yy_i + ymin, xx_i + xmin, 1.0 / inv_d


class Sword:
    def __init__(self):
        self.faces = []
        self.build()

    def face(self, points, material):
        self.faces.append((np.array(points, dtype=np.float32), material))

    def cylinder(self, bottom, top, radius, material, sides=8):
        rings = []
        for y in (bottom, top):
            rings.append(
                [(radius * math.cos(i * math.tau / sides), y,
                  radius * math.sin(i * math.tau / sides)) for i in range(sides)]
            )
        for i in range(sides):
            j = (i + 1) % sides
            self.face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], material)
        self.face(rings[0][::-1], material)
        self.face(rings[1], material)

    def build(self):
        # A diamond-section blade. All animation frames use these exact vertices.
        sections = [
            (0.10, 0.265, 0.086), (0.43, 0.265, 0.088),
            (0.49, 0.235, 0.088), (2.52, 0.208, 0.075),
            (3.00, 0.155, 0.055), (BLADE_LENGTH, 0.0, 0.0),
        ]
        for (y0, w0, h0), (y1, w1, h1) in zip(sections, sections[1:]):
            self.face([(-w0, y0, 0), (0, y0, h0), (0, y1, h1), (-w1, y1, 0)], "steel")
            self.face([(0, y0, h0), (w0, y0, 0), (w1, y1, 0), (0, y1, h1)], "steel_bright")
            self.face([(w0, y0, 0), (0, y0, -h0), (0, y1, -h1), (w1, y1, 0)], "steel_edge")
            self.face([(0, y0, -h0), (-w0, y0, 0), (-w1, y1, 0), (0, y1, -h1)], "steel")
            if w1 > 0:
                self.face([(-0.012, y0, h0 + 0.001), (0.012, y0, h0 + 0.001),
                           (0.012, y1, h1 + 0.001), (-0.012, y1, h1 + 0.001)], "ridge")
        # Swept, bevelled brass crossguard.
        guard = [(-0.84, -0.17), (-0.72, -0.02), (-0.32, 0.07), (-0.18, 0.14),
                 (0.18, 0.14), (0.32, 0.07), (0.72, -0.02), (0.84, -0.17),
                 (0.76, -0.26), (0.48, -0.14), (0.22, -0.10), (-0.22, -0.10),
                 (-0.48, -0.14), (-0.76, -0.26)]
        inset = [(x * 0.91, (y + 0.06) * 0.67 - 0.06) for x, y in guard]
        for side in (-1, 1):
            self.face([(x, y, side * 0.155) for x, y in inset], "gold_light")
            for i in range(len(guard)):
                j = (i + 1) % len(guard)
                self.face([(guard[i][0], guard[i][1], side * 0.09),
                           (guard[j][0], guard[j][1], side * 0.09),
                           (inset[j][0], inset[j][1], side * 0.155),
                           (inset[i][0], inset[i][1], side * 0.155)], "gold")
        for i in range(len(guard)):
            j = (i + 1) % len(guard)
            self.face([(guard[i][0], guard[i][1], -0.09), (guard[j][0], guard[j][1], -0.09),
                       (guard[j][0], guard[j][1], 0.09), (guard[i][0], guard[i][1], 0.09)], "gold")
        self.cylinder(-1.18, -0.19, 0.115, "leather")
        self.cylinder(-0.33, -0.15, 0.147, "gold")
        self.cylinder(-1.23, -1.12, 0.142, "gold")
        # Physical leather wrap strips, so they also obey the depth buffer.
        steps = 128
        for i in range(steps):
            a0, a1 = i / steps * math.tau * 4.4, (i + 1) / steps * math.tau * 4.4
            y0, y1 = -0.34 - i / steps * 0.76, -0.34 - (i + 1) / steps * 0.76
            self.face([(0.117 * math.cos(a0), y0, 0.117 * math.sin(a0)),
                       (0.117 * math.cos(a1), y1, 0.117 * math.sin(a1)),
                       (0.117 * math.cos(a1), y1 - 0.031, 0.117 * math.sin(a1)),
                       (0.117 * math.cos(a0), y0 - 0.031, 0.117 * math.sin(a0))], "wrap")
        # Faceted pommel, shaped from a stack of rigid octagons.
        rings = [(-1.21, 0.11), (-1.31, 0.20), (-1.46, 0.145), (-1.53, 0.0)]
        for (y0, r0), (y1, r1) in zip(rings, rings[1:]):
            for i in range(8):
                a0, a1 = i / 8 * math.tau, (i + 1) / 8 * math.tau
                self.face([(r0 * math.cos(a0), y0, r0 * math.sin(a0)),
                           (r0 * math.cos(a1), y0, r0 * math.sin(a1)),
                           (r1 * math.cos(a1), y1, r1 * math.sin(a1)),
                           (r1 * math.cos(a0), y1, r1 * math.sin(a0))], "gold_light")
        for side in (-1, 1):
            z = side * 0.158
            rim = [(-0.095, -0.025, z), (0, 0.075, z), (0.095, -0.025, z), (0, -0.13, z)]
            peak = (0, -0.025, side * 0.215)
            for i in range(4):
                self.face([rim[i], rim[(i + 1) % 4], peak], "gem")


def shade(points: np.ndarray, material: str):
    normal = np.cross(points[1] - points[0], points[2] - points[0])
    n = float(np.linalg.norm(normal))
    if n < 1e-8:
        return None
    normal /= n
    view = np.array([0, 0, CAMERA_Z]) - points.mean(axis=0)
    if np.dot(normal, view) < 0:
        normal *= -1
    light = float(np.dot(normal, LIGHT))
    band = 2 if light > 0.63 else 1 if light > 0.12 else 0
    return np.array(MATERIALS[material][band], dtype=np.float32) / 255, normal


def render_sword(sword: Sword, t: float):
    depth = np.full((RES, RES), np.inf, dtype=np.float32)
    rgb = np.zeros((RES, RES, 3), dtype=np.float32)
    normals = np.zeros((RES, RES, 3), dtype=np.float32)
    for local, material in sword.faces:
        transformed = world(local, t)
        lighting = shade(transformed, material)
        if lighting is None:
            continue
        color, normal = lighting
        xy, d = project(transformed)
        for j in range(1, len(local) - 1):
            idx = [0, j, j + 1]
            result = triangle_fragments(xy[idx], d[idx])
            if result is None:
                continue
            yy, xx, zd = result
            keep = zd < depth[yy, xx]
            yy, xx, zd = yy[keep], xx[keep], zd[keep]
            depth[yy, xx] = zd
            rgb[yy, xx] = color
            normals[yy, xx] = normal
    opaque = np.isfinite(depth)
    # Hard creases get a fine ink line; planar triangulation remains invisible.
    creases = np.zeros((RES, RES), dtype=bool)
    for axis in (0, 1):
        neighbor = np.roll(opaque, 1, axis=axis)
        dots = np.sum(normals * np.roll(normals, 1, axis=axis), axis=2)
        dd = np.abs(np.nan_to_num(depth, posinf=100) - np.roll(np.nan_to_num(depth, posinf=100), 1, axis=axis))
        creases |= opaque & neighbor & (dots < 0.49) & (dd < 0.14)
    rgb[creases] = np.array(INK) / 255
    mask = Image.fromarray(opaque.astype(np.uint8) * 255)
    expanded = np.asarray(mask.filter(ImageFilter.MaxFilter(2 * (AA + 1) + 1))) > 0
    # Expand depth together with the outline, so a rear trail cannot cover the ink.
    outline_depth = depth.copy()
    encoded = np.where(opaque, np.clip((depth - 3) / 8 * 250, 0, 250), 255).astype(np.uint8)
    dilated_depth = np.asarray(Image.fromarray(encoded).filter(ImageFilter.MinFilter(2 * (AA + 1) + 1)))
    outline_depth[expanded & ~opaque] = dilated_depth[expanded & ~opaque] / 250.0 * 8 + 3
    color = np.zeros((RES, RES, 4), dtype=np.float32)
    color[expanded, :3] = np.array(INK) / 255
    color[expanded, 3] = 1
    color[opaque, :3] = rgb[opaque]
    return color, outline_depth


def trail_point(t: float, radius: float):
    return world([(0.0, BLADE_LENGTH * radius, 0.035)], t)[0]


def trail_geometry(t: float):
    pieces = []
    life = 0.190
    times = np.linspace(max(0.24, t - life), t, 35)
    if t <= 0.25:
        return pieces
    bands = [
        (0.32, 0.57, (130, 206, 234), 0.12),
        (0.57, 0.77, (117, 210, 237), 0.24),
        (0.77, 0.955, (160, 234, 248), 0.50),
        (0.955, 1.005, (244, 254, 255), 0.90),
        (1.005, 1.014, (47, 111, 149), 0.76),
    ]
    for a, b in zip(times, times[1:]):
        if b <= a:
            continue
        age = (t - (a + b) * 0.5) / life
        speed = abs(angular_speed((a + b) * 0.5))
        strength = min(1.0, speed / 7.0) * max(0.0, 1 - age) ** 0.85
        if strength < 0.012:
            continue
        for inner, outer, color, opacity in bands:
            pts = np.array([trail_point(a, inner), trail_point(a, outer),
                            trail_point(b, outer), trail_point(b, inner)])
            pieces.append((pts, color, opacity * strength))
        # Broken outer speed accents follow the same spatial arc.
        if 0.10 < age < 0.88 and (int(a * 300) % 11) < 7 and speed > 5:
            pts = np.array([trail_point(a, 1.065), trail_point(a, 1.073),
                            trail_point(b, 1.073), trail_point(b, 1.065)])
            pieces.append((pts, (49, 79, 109), 0.52 * strength))
    # Painter ordering only affects the translucent trail itself. Sword occlusion
    # is tested separately for every fragment against the actual depth buffer.
    pieces.sort(key=lambda p: float(p[0][:, 2].mean()))
    return pieces


def composite_at(layer: np.ndarray, yy, xx, rgb, opacity: float):
    old = layer[yy, xx]
    inv = 1.0 - opacity
    layer[yy, xx, :3] = np.array(rgb, dtype=np.float32) / 255 * opacity + old[:, :3] * inv
    layer[yy, xx, 3] = opacity + old[:, 3] * inv


def render_trail(t: float, sword_depth: np.ndarray):
    rear = np.zeros((RES, RES, 4), dtype=np.float32)
    front = np.zeros_like(rear)
    counts = [0, 0]
    for points, color, opacity in trail_geometry(t):
        xy, d = project(points)
        for idx in ([0, 1, 2], [0, 2, 3]):
            result = triangle_fragments(xy[idx], d[idx])
            if result is None:
                continue
            yy, xx, zd = result
            near = zd < sword_depth[yy, xx] - 0.009
            counts[0] += int(np.sum((~near) & np.isfinite(sword_depth[yy, xx])))
            counts[1] += int(np.sum(near & np.isfinite(sword_depth[yy, xx])))
            composite_at(rear, yy[~near], xx[~near], color, opacity)
            composite_at(front, yy[near], xx[near], color, opacity)
    return rear, front, counts


def over(back: np.ndarray, front: np.ndarray):
    return front + back * (1.0 - front[:, :, 3:4])


def to_image(premult: np.ndarray):
    alpha = premult[:, :, 3:4]
    rgb = np.divide(premult[:, :, :3], alpha, out=np.zeros_like(premult[:, :, :3]), where=alpha > 1e-5)
    rgba = np.concatenate([rgb, alpha], axis=2)
    img = Image.fromarray(np.round(np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def font(size: int, bold=False):
    path = Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def background():
    img = Image.new("RGBA", (SIZE, SIZE), (244, 245, 240, 255))
    draw = ImageDraw.Draw(img)
    # Quiet comic halftone stays outside the action area.
    for x in range(24, SIZE - 12, 13):
        for y in range(85, SIZE - 24, 13):
            if (x < 120 and y > 465) or (x > 535 and y < 190):
                draw.ellipse((x, y, x + 1, y + 1), fill=(206, 216, 214, 255))
    draw.text((30, 25), "骑士双手剑", font=font(23, True), fill=(37, 53, 69))
    draw.text((31, 59), "空间斜砍  /  DIAGONAL CUT", font=font(10), fill=(94, 113, 126))
    draw.line((30, SIZE - 39, SIZE - 30, SIZE - 39), fill=(205, 213, 211), width=1)
    draw.text((31, SIZE - 28), "漫画描边 · 空间透视 · 分层拖影", font=font(11), fill=(94, 113, 126))
    return img


def make_preview(frame: Image.Image, index: int):
    img = Image.alpha_composite(background(), frame)
    draw = ImageDraw.Draw(img)
    draw.text((SIZE - 83, 32), f"{index + 1:02d} / {COUNT}", font=font(12), fill=(94, 113, 126))
    return img.convert("RGB")


def make_contact_sheet(frames: list[Image.Image], output: Path):
    chosen = [0, 7, 9, 10, 13, 19]
    labels = ["01  蓄势 · 剑尖在后", "08  加速 · 向前转出", "10  主斩 · 掠向镜头",
              "11  透视缩短 · 护手遮挡", "14  斜切 · 剑身重新展开", "20  收势 · 拖影消散"]
    tile, gap = 420, 18
    canvas = Image.new("RGB", (tile * 3 + gap * 4, tile * 2 + gap * 3 + 112), (235, 239, 235))
    draw = ImageDraw.Draw(canvas)
    draw.text((gap + 6, 20), "骑士双手剑 / 空间斜砍", font=font(28, True), fill=(32, 49, 64))
    draw.text((gap + 7, 66), "同一剑体、固定镜头；长度变化来自透视，前后关系由深度决定。", font=font(16), fill=(87, 106, 116))
    for k, (idx, label) in enumerate(zip(chosen, labels)):
        x, y = gap + (k % 3) * (tile + gap), 112 + gap + (k // 3) * (tile + gap)
        draw.rounded_rectangle((x, y, x + tile, y + tile), radius=12, fill=(250, 251, 246))
        thumb = frames[idx].resize((tile, tile), Image.Resampling.LANCZOS)
        canvas.paste(thumb, (x, y), thumb)
        draw.text((x + 17, y + 15), label, font=font(17, True), fill=(43, 62, 79))
    canvas.save(output)


def validate(frames, lengths, occlusion):
    bounds = [frame.getchannel("A").getbbox() for frame in frames]
    for idx, bbox in enumerate(bounds):
        assert bbox is not None, f"Empty frame {idx + 1}"
        assert bbox[0] > 3 and bbox[1] > 3 and bbox[2] < SIZE - 3 and bbox[3] < SIZE - 3, (idx + 1, bbox)
    assert min(lengths) / max(lengths) < 0.48, "Foreshortening is insufficient"
    assert sum(p[0] for p in occlusion) > 0 and sum(p[1] for p in occlusion) > 0, "Both trail depth relations are required"
    for t in np.linspace(0, 1, 101):
        rotation, _ = pose(float(t))
        assert np.allclose(rotation.T @ rotation, np.eye(3), atol=1e-7)
        assert np.isclose(np.linalg.norm(world([(0, 0, 0), (0, BLADE_LENGTH, 0)], float(t))[1]
                                         - world([(0, 0, 0)], float(t))[0]), BLADE_LENGTH)
    print(f"Validated: {len(frames)} RGBA frames; projected blade {min(lengths):.1f}–{max(lengths):.1f} px; "
          f"trail/sword rear/front fragments {sum(p[0] for p in occlusion)}/{sum(p[1] for p in occlusion)}.", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    frame_dir = args.output / "frames"
    frame_dir.mkdir(exist_ok=True)
    sword = Sword()
    frames, previews, lengths, occlusion = [], [], [], []
    for idx in range(COUNT):
        t = idx / (COUNT - 1)
        body, depth = render_sword(sword, t)
        rear, front, counts = render_trail(t, depth)
        frame = to_image(over(over(rear, body), front))
        frame.save(frame_dir / f"slash_{idx + 1:02d}.png")
        frames.append(frame)
        previews.append(make_preview(frame, idx))
        xy, _ = project(world([(0, 0, 0), (0, BLADE_LENGTH, 0)], t))
        lengths.append(float(np.linalg.norm(xy[1] - xy[0]) / AA))
        occlusion.append(counts)
        print(f"Rendered {idx + 1:02d}/{COUNT}: angle={math.degrees(angle_at(t)):.1f}°; "
              f"projected blade={lengths[-1]:.1f}px", flush=True)
    validate(frames, lengths, occlusion)
    # 24 unique drawings. GIF's centisecond clock requires 40/50 ms cadence.
    durations = [40, 40, 40, 50, 40, 40] * 4
    # A longer final hold lets the single strike read before the loop restarts.
    durations[-1] += 360
    previews[0].save(args.output / "knight_greatsword_slash.gif", save_all=True,
                     append_images=previews[1:], duration=durations, loop=0,
                     disposal=2, optimize=False)
    previews[0].save(args.output / "knight_greatsword_slash_slow.gif", save_all=True,
                     append_images=previews[1:], duration=[d * 2 for d in durations], loop=0,
                     disposal=2, optimize=False)
    frames[0].save(args.output / "knight_greatsword_slash.png", save_all=True,
                   append_images=frames[1:], duration=durations, loop=0,
                   disposal=0, blend=0)
    atlas = Image.new("RGBA", (SIZE * 6, SIZE * 4), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        atlas.paste(frame, ((i % 6) * SIZE, (i // 6) * SIZE))
    atlas.save(args.output / "knight_greatsword_slash_sheet.png")
    make_contact_sheet(frames, args.output / "keyframes.png")
    with zipfile.ZipFile(args.output / "transparent_frames.zip", "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(frame_dir.glob("slash_*.png")):
            bundle.write(path, f"frames/{path.name}")
    gif = Image.open(args.output / "knight_greatsword_slash.gif")
    apng = Image.open(args.output / "knight_greatsword_slash.png")
    # APNG losslessly combines identical hold drawings into longer durations.
    assert gif.n_frames == COUNT and 1 < apng.n_frames <= COUNT
    for animation in (gif, apng):
        total = 0
        for i in range(animation.n_frames):
            animation.seek(i)
            total += animation.info.get("duration", 0)
        assert abs(total - sum(durations)) < 1, (animation.filename, total)
    assert all(Image.open(p).mode == "RGBA" for p in frame_dir.glob("*.png"))
    print(f"Deliverables saved to {args.output.resolve()}", flush=True)


if __name__ == "__main__":
    main()
