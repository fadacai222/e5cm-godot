from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\arial.ttf"),
    ]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a deterministic PNG contact sheet.")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--width", type=int, default=480)
    parser.add_argument("--height", type=int, default=270)
    args = parser.parse_args()

    files = sorted(args.input.glob("*.png"))
    if not files:
        raise SystemExit(f"no PNG files in {args.input}")

    label_h = 36
    rows = math.ceil(len(files) / args.columns)
    sheet = Image.new(
        "RGB",
        (args.columns * args.width, rows * (args.height + label_h)),
        (12, 16, 24),
    )
    draw = ImageDraw.Draw(sheet)
    label_font = font(18)

    for index, path in enumerate(files):
        x = (index % args.columns) * args.width
        y = (index // args.columns) * (args.height + label_h)
        with Image.open(path) as source:
            image = source.convert("RGB")
            image.thumbnail((args.width, args.height), Image.Resampling.LANCZOS)
            px = x + (args.width - image.width) // 2
            py = y + (args.height - image.height) // 2
            sheet.paste(image, (px, py))
        draw.rectangle((x, y + args.height, x + args.width, y + args.height + label_h), fill=(22, 29, 42))
        draw.text((x + 10, y + args.height + 7), path.stem, fill=(235, 240, 250), font=label_font)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output, optimize=True)
    print(f"CONTACT_SHEET={args.output} COUNT={len(files)}")


if __name__ == "__main__":
    main()
