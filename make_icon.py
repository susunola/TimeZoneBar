#!/usr/bin/env python3
"""Generate the TimeZoneBar app icon (AppIcon.icns) using only the standard library.

Design: blue rounded square with a white clock (dial, hour hand, minute hand, center dot).
Rendering: SIZE=1024 with 2x2 supersampling for anti-aliasing.
Usage: python3 make_icon.py [output directory, defaults to Resources]
"""
import math
import os
import struct
import subprocess
import sys
import zlib

SIZE = 1024
R = 180                      # Corner radius
BLUE = (0, 122, 255, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def in_rounded_rect(x, y):
    if R < x < SIZE - R or R < y < SIZE - R:
        return True
    for cx, cy in ((R, R), (SIZE - R, R), (R, SIZE - R), (SIZE - R, SIZE - R)):
        if (x - cx) ** 2 + (y - cy) ** 2 <= R * R:
            return True
    return False


def dist_seg(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    c1 = vx * wx + vy * wy
    if c1 <= 0:
        return math.hypot(px - ax, py - ay)
    c2 = vx * vx + vy * vy
    if c2 <= c1:
        return math.hypot(px - bx, py - by)
    t = c1 / c2
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def color_at(x, y):
    if not in_rounded_rect(x, y):
        return CLEAR
    c = BLUE
    cx = cy = SIZE / 2
    d = math.hypot(x - cx, y - cy)
    if 244 <= d <= 300:                    # Dial stroke
        c = WHITE
    if dist_seg(x, y, cx, cy, cx, 240) <= 28:   # Minute hand
        c = WHITE
    if dist_seg(x, y, cx, cy, 430, 300) <= 30:  # Hour hand
        c = WHITE
    if d <= 42:                            # Center dot
        c = WHITE
    return c


def render():
    rows = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            acc = [0, 0, 0, 0]
            for oy in (0.25, 0.75):
                for ox in (0.25, 0.75):
                    r, g, b, a = color_at(px + ox, py + oy)
                    acc[0] += r
                    acc[1] += g
                    acc[2] += b
                    acc[3] += a
            row.append(tuple(int(v / 4) for v in acc))
        rows.append(row)
        if (py + 1) % 256 == 0:
            print(f"  render {py + 1}/{SIZE}", flush=True)
    return rows


def write_png(path, pixels):
    raw = b""
    for row in pixels:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "Resources"
    os.makedirs(out_dir, exist_ok=True)
    master = os.path.join(out_dir, "icon_master.png")
    print("Rendering the 1024x1024 master image…", flush=True)
    write_png(master, render())

    iconset = os.path.join(out_dir, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    for name, px in sizes.items():
        subprocess.run(["sips", "-z", str(px), str(px), master, "--out",
                        os.path.join(iconset, name)],
                       check=True, capture_output=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o",
                    os.path.join(out_dir, "AppIcon.icns")], check=True)
    print("Done:", os.path.join(out_dir, "AppIcon.icns"), flush=True)


if __name__ == "__main__":
    main()
