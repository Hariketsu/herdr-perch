# Generate the app icon from the pixel ram in Sources/PerchApp/Views/PixelRam.swift.
# Design: light grey rounded square, dark grey ram (icon prototype option 6, 2026-10-23).
#
#   Resources/AppIcon.icns   macOS 15 and earlier. Every size is drawn natively with whole-pixel
#                            cells (no downscaling), and 16px uses a hand-made 10×10 ram.
#   Resources/AppIcon.icon   Icon Composer document for macOS 26 (Liquid Glass): grey fill plus
#                            ram layers with glass off, so the pixels stay crisp; dark appearance
#                            swaps in a dark fill and a light grey ram. Compiled here only to check
#                            it; the app does not ship it yet (2026-10-23). actool always adds its own
#                            flattened legacy renditions to Assets.car, and with CFBundleIconName set
#                            macOS 15 prefers those to AppIcon.icns, losing the hand-tuned 16/32px.
#                            To ship it: copy the compiled Assets.car into the app's Resources and add
#                            CFBundleIconName = AppIcon to Info.plist (scripts/bundle.sh).
#
# Usage: uv run --with pillow python scripts/make-icon.py   (needs Xcode for iconutil, actool, ictool)
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SPRITE = ROOT / "Sources/PerchApp/Views/PixelRam.swift"
RESOURCES = ROOT / "Resources"
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

TOP, BOTTOM = (0xF4, 0xF4, 0xF5), (0xD4, 0xD4, 0xD8)
TONES = {"W": "#3F3F46", "L": "#8E8E96", "H": "#71717A", "S": "#63636B", "R": "#4A4A52"}
# macOS 26 dark appearance: dark fill, so the ram turns light grey.
DARK_TONES = {"W": "#A1A1AA", "L": "#E4E4E7", "H": "#C4C4CA", "S": "#B2B2B9", "R": "#8E8E96"}

# Ram cell in pixels per icon size; 1024 → 30 gives a 600×570 ram in the 824 body.
CELLS = {32: 1, 64: 2, 128: 4, 256: 7, 512: 15, 1024: 30}

# 16px: the 20×19 ram does not fit a 13px body, so a 10×10 one, drawn by hand
# (ear leaf, gap between head and horn, C-shaped horn with its hook, one-pixel eye).
SMALL = [
    ".....HHHH.",
    "...W.HHHHH",
    "..W..H..HH",
    "..WW....HH",
    ".W.WWW..HH",
    "WWWWWW.HHH",
    "WWWWWW.HH.",
    ".WWWWWWW..",
    "....WWWW..",
    ".....WWW..",
]


def sprite():
    source = SPRITE.read_text()
    block = source[source.index("static let grid = ["):]
    grid = re.findall(r'"([.WLHSR]{20})"', block[: block.index("]")])
    face = re.search(r"private static let prompt = \[(.*?)\]", source).group(1)
    holes = {(int(r), int(c)) for r, c in re.findall(r"\((\d+), (\d+)\)", face)}
    assert len(grid) == 19 and holes, "PixelRam.swift layout changed"
    return grid, holes


def draw_ram(image, grid, holes, cell, origin, tones=TONES):
    draw = ImageDraw.Draw(image)
    for r, row in enumerate(grid):
        for c, ch in enumerate(row):
            if ch == "." or (r, c) in holes:
                continue
            x, y = origin[0] + c * cell, origin[1] + r * cell
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=tones[ch])


def plate(size):
    """Rounded body with gradient, hairline and drop shadow, drawn 4× and downscaled."""
    s = 4
    canvas = size * s
    f = canvas / 1024
    body = tuple(round(v * f) for v in (100, 100, 924, 924))
    radius = round(185 * f)
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).rounded_rectangle(body, radius, fill=255)

    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow.putalpha(mask.point(lambda a: a * 0.28))
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(1, 14 * f)))
    image.alpha_composite(shadow, (0, round(12 * f)))

    gradient = Image.new("RGBA", (canvas, canvas))
    draw = ImageDraw.Draw(gradient)
    for y in range(canvas):
        t = min(1, max(0, (y - body[1]) / (body[3] - body[1])))
        draw.line([(0, y), (canvas, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    layer.paste(gradient, mask=mask)
    image.alpha_composite(layer)
    ImageDraw.Draw(image).rounded_rectangle(body, radius, outline=(0, 0, 0, 15), width=max(1, round(2 * f)))
    return image.resize((size, size), Image.LANCZOS)


def legacy_icon(size, grid, holes):
    image = plate(size)
    f = size / 1024
    if size == 16:
        draw_ram(image, SMALL, set(), 1, (3, 3), {"W": TONES["W"], "H": TONES["H"]})
    else:
        cell = CELLS[size]
        # Optical centre of the body is a little below the middle.
        draw_ram(image, grid, holes, cell, (round(512 * f - 10 * cell), round(531 * f - 9.5 * cell)))
    return image


def write_icns(grid, holes, tmp):
    iconset = tmp / "AppIcon.iconset"
    iconset.mkdir()
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "" if scale == 1 else "@2x"
            legacy_icon(points * scale, grid, holes).save(iconset / f"icon_{points}x{points}{suffix}.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES / "AppIcon.icns")], check=True)


def srgb(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def write_icon_document(grid, holes):
    """Icon Composer document: the system draws the squircle, fill and lighting; the ram
    layers keep glass off so the pixels are not smeared by refraction."""
    document = RESOURCES / "AppIcon.icon"
    shutil.rmtree(document, ignore_errors=True)
    (document / "Assets").mkdir(parents=True)
    cell = 36  # full-bleed canvas: the 600/824 proportion of the legacy icon
    origin = (512 - 10 * cell, 530 - round(9.5 * cell))
    # One white mask per tone, coloured by the layer fill: fills can be specialised per
    # appearance, so dark mode recolours the ram. As in files Icon Composer writes, the
    # default goes first in "fill-specializations"; a separate "fill" key disables them.
    layers = []
    for tone in "WLHSR":
        mask = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        only = [re.sub(f"[^{tone}]", ".", row) for row in grid]
        draw_ram(mask, only, holes, cell, origin, {tone: "#FFFFFF"})
        mask.save(document / "Assets" / f"ram-{tone}.png")
        layers.append({
            "image-name": f"ram-{tone}.png", "name": f"ram-{tone}", "glass": False, "hidden": False,
            "fill-specializations": [
                {"value": {"solid": srgb(TONES[tone])}},
                {"appearance": "dark", "value": {"solid": srgb(DARK_TONES[tone])}},
            ],
        })
    icon = {
        "fill-specializations": [
            {"value": {"automatic-gradient": "extended-srgb:0.89412,0.89412,0.90588,1.00000"}},
            {"appearance": "dark", "value": {"automatic-gradient": "extended-srgb:0.15294,0.15294,0.16471,1.00000"}},
        ],
        "groups": [{
            "layers": layers,
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": False, "value": 0.5},
        }],
        "supported-platforms": {"squares": "shared"},
    }
    (document / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
    return document


def check_compiles(document, tmp):
    out = tmp / "compiled"
    out.mkdir()
    subprocess.run([
        "xcrun", "actool", str(document), "--compile", str(out), "--app-icon", "AppIcon",
        "--include-all-app-icons", "--target-device", "mac", "--platform", "macosx",
        "--minimum-deployment-target", "26.0", "--output-partial-info-plist", str(tmp / "partial.plist"),
        "--output-format", "human-readable-text", "--errors", "--warnings",
    ], check=True)
    assert (out / "Assets.car").exists(), "actool produced no Assets.car"


def previews(document):
    """macOS 26 renditions for review, in the temp directory."""
    paths = []
    for rendition in ("Default", "Dark", "ClearLight", "TintedDark"):
        path = Path(tempfile.gettempdir()) / f"perch-appicon-{rendition}.png"
        subprocess.run([ICTOOL, str(document), "--export-image", "--output-file", str(path), "--platform", "macOS",
                        "--rendition", rendition, "--width", "512", "--height", "512", "--scale", "1"], check=True)
        paths.append(path)
    return paths


def main():
    grid, holes = sprite()
    RESOURCES.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as name:
        tmp = Path(name)
        write_icns(grid, holes, tmp)
        document = write_icon_document(grid, holes)
        check_compiles(document, tmp)
    for path in [RESOURCES / "AppIcon.icns", document, *previews(document)]:
        print(path)


if __name__ == "__main__":
    main()
