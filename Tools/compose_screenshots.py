"""Frames raw 1320x2868 simulator captures as App Store screenshots.

Usage: python3 Tools/compose_screenshots.py <raw-dir> <out-dir>  (needs Pillow)

Raw captures are named 01-list-light.png, 02-detail-light.png, 03-form-light.png,
04-groups-light.png, 05-import-light.png and 01-list-dark.png: the app with
`--uitest --demo` on an iPhone 17 Pro Max, US locale, status bar overridden to 9:41.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW, OUT = sys.argv[1], sys.argv[2]
W, H = 1320, 2868
FONT = "/System/Library/Fonts/SFNS.ttf"

THEMES = {
    "light": dict(top=(255, 247, 240), bottom=(255, 226, 204), text=(29, 29, 31), accent=(191, 68, 0), sub=(110, 110, 115), bezel=(28, 28, 30)),
    "dark": dict(top=(18, 18, 18), bottom=(52, 26, 10), text=(255, 255, 255), accent=(255, 122, 28), sub=(174, 174, 178), bezel=(58, 58, 60)),
}

SLIDES = [
    ("01-list-light", "light", "Never miss", "a birthday again", "Birthdays and anniversaries in one simple list"),
    ("02-detail-light", "light", "Ages, countdowns", "and milestones", "Add the year and Dates does the maths"),
    ("03-form-light", "light", "Reminders when", "they’re useful", "A week ahead, three days before, or on the day"),
    ("04-groups-light", "light", "Close family gets", "more notice", "Set reminders once for each group"),
    ("05-import-light", "light", "Bring your", "birthdays with you", "Import from Contacts or a spreadsheet"),
    ("01-list-dark", "dark", "Private", "by design", "No account. No ads. No tracking."),
]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def gradient(top, bottom):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def centred(d, y, text, f, fill):
    w = d.textlength(text, font=f)
    d.text(((W - w) / 2, y), text, font=f, fill=fill)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


for i, (name, theme, line1, line2, sub) in enumerate(SLIDES, 1):
    t = THEMES[theme]
    img = gradient(t["top"], t["bottom"])
    d = ImageDraw.Draw(img)

    head = font(112, "Bold")
    centred(d, 190, line1, head, t["text"])
    centred(d, 190 + 132, line2, head, t["accent"])
    centred(d, 190 + 132 * 2 + 30, sub, font(50, "Regular"), t["sub"])

    # The phone: the screenshot inside a thin bezel, with a soft shadow.
    shot = Image.open(f"{RAW}/{name}.png").convert("RGB")
    sw = 940
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel = 22
    pw, ph = sw + 2 * bezel, sh + 2 * bezel
    px, py = (W - pw) // 2, H - ph - 110
    screen_radius, phone_radius = 128, 128 + bezel

    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([px, py + 30, px + pw, py + ph + 30], phone_radius, fill=110 if theme == "light" else 200)
    shadow = shadow.filter(ImageFilter.GaussianBlur(60))
    img.paste(Image.new("RGB", (W, H), (60, 30, 10) if theme == "light" else (0, 0, 0)), (0, 0), shadow)

    phone = Image.new("RGB", (pw, ph), t["bezel"])
    phone.paste(shot, (bezel, bezel), rounded_mask((sw, sh), screen_radius))
    img.paste(phone, (px, py), rounded_mask((pw, ph), phone_radius))

    img.save(f"{OUT}/{i:02d}-{name.split('-', 1)[1]}-6.9in.png")
    print(f"{OUT}/{i:02d}-{name.split('-', 1)[1]}-6.9in.png")
