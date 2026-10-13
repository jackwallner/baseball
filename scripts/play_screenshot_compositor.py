#!/usr/bin/env python3
"""Composite raw Android captures into Google Play screenshots and the feature graphic.

Same headlines and panels as the App Store set (fastlane/screenshots/en-US):
a large two-line headline over alternating midnight and cream gradients, with
the real capture below. Play rejects anything longer than 2:1, so frames are
1080x1920. Reads android/play-assets/raw/ (1080x1920 captures of the debug
build's live baseball feed) and writes android/play-assets/screenshots/
and android/play-assets/feature-graphic.png.

Capture recipe: `adb shell am start -n com.jackwallner.baseball/.MainActivity
--ez forcePro true --ei tab <n>` with System UI demo
mode on, then `adb exec-out screencap -p`.

Usage: python3 scripts/play_screenshot_compositor.py
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "android" / "play-assets"
RAW = ASSETS / "raw"
OUT = ASSETS / "screenshots"
ICON = ROOT / "StatScout" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
SFNS = "/System/Library/Fonts/SFNS.ttf"

W, H = 1080, 1920
DARK = ((15, 33, 82), (22, 45, 93))
LIGHT = ((240, 240, 243), (221, 226, 237))
CREAM_TEXT = (255, 255, 255)
INK = (26, 26, 28)
BEZEL = (15, 20, 32)


@dataclass
class Shot:
    raw: str
    out: str
    headline: tuple[str, str]
    dark: bool


SHOTS = [
    Shot("01_league_leaders.png", "01-know-who-leads-the-league", ("Know who leads", "the league"), True),
    Shot("02_player_profile.png", "02-know-what-makes-a-player-elite", ("Know what makes", "a player elite"), False),
    Shot("03_trends.png", "03-see-who-is-heating-up-right-now", ("See who is heating", "up right now"), True),
    Shot("04_player_comparison.png", "04-settle-the-debate-side-by-side", ("Settle the debate", "side by side"), False),
    Shot("05_team.png", "05-scout-your-team-in-one-view", ("Scout your team", "in one view"), True),
    Shot("06_year_history.png", "06-see-how-a-season-changed", ("See how a", "season changed"), False),
]


def sans(size: int, weight: int = 600) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(SFNS, size)
    try:
        # Axes: Width, Optical Size, GRAD, Weight.
        font.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])
    except (OSError, ValueError):
        pass
    return font


def gradient(size: tuple[int, int], stops: tuple[tuple, tuple]) -> Image.Image:
    width, height = size
    img = Image.new("RGB", size)
    draw = ImageDraw.Draw(img)
    top, bottom = stops
    for y in range(height):
        t = y / height
        draw.line([(0, y), (width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (img.width - 1, img.height - 1)], radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def render(shot: Shot) -> Path:
    canvas = gradient((W, H), DARK if shot.dark else LIGHT)
    draw = ImageDraw.Draw(canvas)
    # 118 px on this 1080 canvas matches the 140 px ASC header minimum at 1320.
    head = sans(118, 700)
    for i, line in enumerate(shot.headline):
        if head.getlength(line) > W - 64:
            raise ValueError(f"{line!r} is too wide for one header line")
        draw.text((W / 2, 132 + i * 130), line, font=head, fill=CREAM_TEXT if shot.dark else INK, anchor="mm")

    raw = Image.open(RAW / shot.raw).convert("RGB")
    if raw.size != (1080, 1920):
        raise ValueError(f"{shot.raw} is {raw.size}, expected 1080x1920")
    top, bezel = 366, 16
    screen_h = H - top - 60 - 2 * bezel
    screen_w = round(screen_h * raw.width / raw.height)
    screen = rounded(raw.resize((screen_w, screen_h), Image.LANCZOS), 26)
    frame_w, frame_h = screen_w + 2 * bezel, screen_h + 2 * bezel
    left = (W - frame_w) // 2

    shadow = Image.new("RGBA", (frame_w + 160, frame_h + 160), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([(80, 96), (frame_w + 80, frame_h + 96)], radius=42, fill=(0, 0, 0, 120 if shot.dark else 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.paste(shadow, (left - 80, top - 80), shadow)
    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([(0, 0), (frame_w - 1, frame_h - 1)], radius=42, fill=BEZEL)
    canvas.paste(frame, (left, top), frame)
    canvas.paste(screen, (left + bezel, top + bezel), screen)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{shot.out}.png"
    canvas.save(path, "PNG")
    return path


def feature_graphic() -> Path:
    fw, fh = 1024, 500
    img = gradient((fw, fh), DARK)
    draw = ImageDraw.Draw(img)
    icon = rounded(Image.open(ICON).convert("RGB").resize((132, 132), Image.LANCZOS), 30)
    img.paste(icon, (64, 82), icon)
    draw.text((64, 250), "StatScout", font=sans(76, 700), fill=CREAM_TEXT)
    tagline = sans(32, 500)
    draw.text((66, 352), "Statcast percentiles and", font=tagline, fill=(196, 210, 199))
    draw.text((66, 394), "advanced stats.", font=tagline, fill=(196, 210, 199))

    board = Image.open(RAW / "01_league_leaders.png").convert("RGB").crop((0, 790, 1080, 1538))
    board = rounded(board.resize((round(board.width * 340 / board.height), 340), Image.LANCZOS), 26)
    img.paste(board, (fw - board.width - 32, (fh - board.height) // 2), board)
    path = ASSETS / "feature-graphic.png"
    img.save(path, "PNG")
    return path


def main() -> None:
    for shot in SHOTS:
        print(render(shot))
    print(feature_graphic())


if __name__ == "__main__":
    main()
