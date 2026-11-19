"""스토어 등록용 이미지 생성.

입력: build/store_screenshots/*.png (integration_test/store_screenshots_test.dart 결과, 1320x2868)
출력: store/ios/*.png (App Store iPhone 6.3", 1206x2622 — App Store Connect 기본 요구 크기)
      store/android/*.png (Play 휴대전화 스크린샷 1080x1920, 그래픽 이미지 1024x500, 아이콘 512x512)

실행 (mobile 폴더에서): uv run --with pillow python tool/store_assets.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "build" / "store_screenshots"
OUT_IOS = ROOT / "store" / "ios"
OUT_ANDROID = ROOT / "store" / "android"
ICON = ROOT / "assets" / "branding" / "icon.png"

# 앱 아이콘과 같은 그라데이션 (왼쪽 위 → 오른쪽 아래)
GRAD_FROM = (255, 90, 122)
GRAD_TO = (255, 153, 90)

FONT = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
FONT_BOLD = 6  # AppleSDGothicNeo.ttc 안의 Bold
FONT_MEDIUM = 2  # Medium

# (스크린샷, 제목, 부제)
SLIDES = [
    ("01_perfect_match", "누가 찍어도\n원하는 구도 그대로", "실루엣에 맞으면 \"지금 찍으세요!\""),
    ("02_presets", "찍고 싶은 구도를\n골라만 주세요", "전신샷·카페 컷 레퍼런스 프리셋"),
    ("03_angle_guide", "폰 각도까지\n하나하나 알려줘요", "위·아래로 몇 도 기울일지 실시간 안내"),
]


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size, index=FONT_BOLD if bold else FONT_MEDIUM)


def gradient(width: int, height: int) -> Image.Image:
    """대각선 그라데이션 (작게 그린 뒤 확대해 계단 현상 없이 빠르게)."""
    small = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            small.putpixel((x, y), tuple(round(a + (b - a) * t) for a, b in zip(GRAD_FROM, GRAD_TO)))
    return small.resize((width, height), Image.BICUBIC)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def slide(shot: Path, title: str, subtitle: str, width: int, height: int) -> Image.Image:
    """위쪽에 문구, 아래쪽에 앱 화면(둥근 모서리 + 그림자)을 배치. 화면 아래는 잘려도 된다."""
    canvas = gradient(width, height).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    s = width / 1320  # 기준 폭 1320 대비 배율

    title_font = font(round(108 * s))
    sub_font = font(round(52 * s), bold=False)
    y = round(150 * s)
    draw.multiline_text(
        (width / 2, y), title, font=title_font, fill="white", anchor="ma", align="center", spacing=round(26 * s)
    )
    title_h = draw.multiline_textbbox((width / 2, y), title, font=title_font, anchor="ma", spacing=round(26 * s))[3]
    draw.text((width / 2, title_h + round(44 * s)), subtitle, font=sub_font, fill=(255, 255, 255, 230), anchor="ma")

    phone_w = round(width * 0.80)
    screen = Image.open(shot).convert("RGB")
    screen = screen.resize((phone_w, round(screen.height * phone_w / screen.width)), Image.LANCZOS)
    screen = rounded(screen, round(70 * s))
    top = title_h + round(170 * s)
    left = (width - phone_w) // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left, top + round(20 * s), left + phone_w, top + screen.height), round(70 * s), fill=(120, 20, 40, 110)
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(round(40 * s))))
    # 흰 테두리로 기기 느낌
    border = round(14 * s)
    frame = Image.new("RGBA", (phone_w + border * 2, screen.height + border * 2), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, *frame.size), round(70 * s) + border, fill="white")
    canvas.alpha_composite(frame, (left - border, top - border))
    canvas.alpha_composite(screen, (left, top))
    return canvas.convert("RGB")


def feature_graphic() -> Image.Image:
    """Play 그래픽 이미지 1024x500: 아이콘 + 앱 이름 + 한 줄 소개."""
    canvas = gradient(1024, 500).convert("RGBA")
    icon = Image.open(ICON).convert("RGBA").resize((260, 260), Image.LANCZOS)
    icon = rounded(icon, 58)
    ring = Image.new("RGBA", (276, 276), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle((0, 0, 276, 276), 66, fill=(255, 255, 255, 235))
    canvas.alpha_composite(ring, (82, 112))
    canvas.alpha_composite(icon, (90, 120))
    draw = ImageDraw.Draw(canvas)
    draw.text((420, 150), "라익찍스", font=font(104), fill="white")
    draw.text((424, 285), "딱 이대로 찍어주는", font=font(44, bold=False), fill=(255, 255, 255, 235))
    draw.text((424, 342), "완벽 구도 카메라", font=font(44, bold=False), fill=(255, 255, 255, 235))
    return canvas.convert("RGB")


def main() -> None:
    OUT_IOS.mkdir(parents=True, exist_ok=True)
    OUT_ANDROID.mkdir(parents=True, exist_ok=True)
    for name, title, subtitle in SLIDES:
        shot = SHOTS / f"{name}.png"
        slide(shot, title, subtitle, 1206, 2622).save(OUT_IOS / f"{name}.png", optimize=True)
        slide(shot, title, subtitle, 1080, 1920).save(OUT_ANDROID / f"{name}.png", optimize=True)
    feature_graphic().save(OUT_ANDROID / "feature_graphic.png", optimize=True)
    Image.open(ICON).convert("RGB").resize((512, 512), Image.LANCZOS).save(OUT_ANDROID / "icon_512.png", optimize=True)
    for p in sorted([*OUT_IOS.glob("*.png"), *OUT_ANDROID.glob("*.png")]):
        with Image.open(p) as im:
            print(f"{p.relative_to(ROOT)}  {im.width}x{im.height}  {p.stat().st_size // 1024}KB")


if __name__ == "__main__":
    main()
