"""Renders the E-Labay logo (the in-app AppLogo widget) as launcher icon sources.

The logo is a white Material "eco" leaf over a faint "recycling" mark on forest
green, drawn from the same Material Icons font Flutter uses. Outputs go to
assets/icon/ and are turned into platform icons by flutter_launcher_icons:

    python tool/generate_icon.py
    dart run flutter_launcher_icons
    git checkout -- ios/Runner.xcodeproj/project.pbxproj

flutter_launcher_icons 0.14.4 wrongly rewrites the Xcode setting
ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS; the last command
discards that unrelated change (the app icon set is already named AppIcon).
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

FOREST_GREEN = (0x1E, 0x6B, 0x3A, 255)
WHITE = (255, 255, 255)
ECO = chr(0xE217)          # Icons.eco
RECYCLING = chr(0xF055A)   # Icons.recycling
SIZE = 1024

FLUTTER_ROOT = os.environ.get("FLUTTER_ROOT", r"C:\src\flutter")
FONT = os.path.join(FLUTTER_ROOT, "bin", "cache", "artifacts", "material_fonts", "materialicons-regular.otf")
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def glyph(img: Image.Image, char: str, size: float, alpha: int) -> None:
    """Draws an icon glyph centred like Flutter's Icon widget."""
    font = ImageFont.truetype(FONT, int(size))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((img.width / 2, img.height / 2), char, font=font, fill=WHITE + (alpha,), anchor="mm")
    img.alpha_composite(layer)


def logo(background, scale: float) -> Image.Image:
    """AppLogo proportions: recycling at 0.78 and leaf at 0.48 of the logo size."""
    img = Image.new("RGBA", (SIZE, SIZE), background)
    logo_size = SIZE * scale
    glyph(img, RECYCLING, logo_size * 0.78, int(255 * 0.22))
    glyph(img, ECO, logo_size * 0.48, 255)
    return img


def main() -> None:
    if not os.path.exists(FONT):
        sys.exit(f"Material Icons font not found at {FONT}; set FLUTTER_ROOT.")
    os.makedirs(OUT, exist_ok=True)
    # Full-bleed square (iOS masks the corners; legacy Android icons).
    logo(FOREST_GREEN, 1.0).convert("RGB").save(os.path.join(OUT, "app_icon.png"))
    # Android adaptive foreground, full size: flutter_launcher_icons insets it by
    # 16% so the artwork lands inside the 66% safe zone.
    logo((0, 0, 0, 0), 1.0).save(os.path.join(OUT, "app_icon_foreground.png"))
    # Android 13+ themed icon: the launcher tints this shape.
    mono = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glyph(mono, RECYCLING, SIZE * 0.78, int(255 * 0.35))
    glyph(mono, ECO, SIZE * 0.48, 255)
    mono.save(os.path.join(OUT, "app_icon_monochrome.png"))
    print("Wrote", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
