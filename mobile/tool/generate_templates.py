"""상황별 실루엣 템플릿 생성 → assets/templates/templates.json

인체 비율로 몸(타원·캡슐)을 그린 뒤 바깥 윤곽만 추출한다. 좌표계:
- figure: y는 머리끝 0 ~ 바닥 1, x는 몸 중심 0 (단위 = 그림 높이)
- frame: 뷰파인더 기준 0~1

실행 (mobile 폴더에서): uv run --with pillow --with numpy --with scikit-image python tool/generate_templates.py
"""

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from skimage import measure

OUT = Path(__file__).resolve().parent.parent / "assets" / "templates" / "templates.json"
PX = 1400  # 그림 높이 1.0의 픽셀 수
PAD = 500


class Body:
    """몸 부위를 흰색으로 합쳐 그리는 캔버스."""

    def __init__(self) -> None:
        self.im = Image.new("L", (PX + PAD * 2, PX + PAD * 2), 0)
        self.d = ImageDraw.Draw(self.im)

    def _p(self, x: float, y: float) -> tuple[float, float]:
        return (x * PX + self.im.width / 2, y * PX + PAD)

    def oval(self, x: float, y: float, rx: float, ry: float) -> None:
        cx, cy = self._p(x, y)
        self.d.ellipse((cx - rx * PX, cy - ry * PX, cx + rx * PX, cy + ry * PX), fill=255)

    def limb(self, *pts: tuple[float, float, float]) -> None:
        """(x, y, 반지름) 점을 잇는, 굵기가 변하는 팔다리."""
        for (x0, y0, r0), (x1, y1, r1) in zip(pts, pts[1:]):
            n = max(2, int(math.hypot(x1 - x0, y1 - y0) * PX / 3))
            for i in range(n + 1):
                t = i / n
                r = r0 + (r1 - r0) * t
                self.oval(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r, r)

    def poly(self, *pts: tuple[float, float]) -> None:
        self.d.polygon([self._p(*p) for p in pts], fill=255)

    def outline(self, smooth: float = 11, count: int = 120) -> list[tuple[float, float]]:
        """부드럽게 만든 바깥 윤곽을 같은 간격의 점으로 (앱에서 Catmull-Rom 곡선으로 잇는다)."""
        soft = np.asarray(self.im.filter(ImageFilter.GaussianBlur(smooth)), dtype=float)
        contour = max(measure.find_contours(soft, 110), key=len)
        step = np.r_[0, np.cumsum(np.hypot(*np.diff(contour, axis=0).T))]
        at = np.linspace(0, step[-1], count, endpoint=False)
        rows, cols = (np.interp(at, step, contour[:, i]) for i in (0, 1))
        return [((c - self.im.width / 2) / PX, (r - PAD) / PX) for r, c in zip(rows, cols)]


def head(b: Body, x: float, y: float, s: float = 1.0) -> None:
    b.oval(x, y, 0.046 * s, 0.062 * s)
    b.limb((x, y + 0.045 * s, 0.026 * s), (x, y + 0.1 * s, 0.027 * s))


def torso(b: Body, x: float, y: float, s: float = 1.0) -> None:
    """어깨(y) ~ 골반. s는 배율."""
    b.limb((x - 0.082 * s, y + 0.026 * s, 0.034 * s), (x, y, 0.03 * s), (x + 0.082 * s, y + 0.026 * s, 0.034 * s))
    b.poly(
        (x - 0.1 * s, y + 0.03 * s),
        (x + 0.1 * s, y + 0.03 * s),
        (x + 0.066 * s, y + 0.2 * s),
        (x + 0.093 * s, y + 0.33 * s),
        (x - 0.093 * s, y + 0.33 * s),
        (x - 0.066 * s, y + 0.2 * s),
    )


def full_body() -> Body:
    b = Body()
    head(b, 0.0, 0.064)
    torso(b, 0.0, 0.158)
    # 팔: 자연스럽게 내림
    b.limb((-0.088, 0.188, 0.03), (-0.142, 0.335, 0.023), (-0.162, 0.465, 0.017), (-0.164, 0.5, 0.019))
    b.limb((0.088, 0.188, 0.03), (0.142, 0.335, 0.023), (0.162, 0.465, 0.017), (0.164, 0.5, 0.019))
    # 다리: 한쪽은 곧게, 한쪽은 살짝 앞으로
    b.limb((-0.05, 0.48, 0.052), (-0.056, 0.7, 0.038), (-0.062, 0.93, 0.024), (-0.075, 0.975, 0.02))
    b.limb((0.05, 0.48, 0.052), (0.062, 0.7, 0.038), (0.098, 0.93, 0.024), (0.125, 0.975, 0.02))
    return b


def cafe() -> Body:
    """머리끝 ~ 테이블 면(1.0). 팔꿈치를 테이블에 올린 상반신."""
    b = Body()
    s = 2.15
    head(b, 0.0, 0.135, s)
    torso(b, 0.0, 0.345, s)
    b.limb((-0.19, 0.415, 0.066), (-0.275, 0.72, 0.056), (-0.33, 0.95, 0.052), (-0.08, 0.99, 0.042))
    b.limb((0.19, 0.415, 0.066), (0.275, 0.72, 0.056), (0.33, 0.95, 0.052), (0.08, 0.99, 0.042))
    return b


def sitting() -> Body:
    """머리끝 ~ 엉덩이(1.0). 한 팔은 뒤를 짚고 한 팔은 무릎 쪽으로."""
    b = Body()
    s = 2.0
    head(b, 0.02, 0.125, s)
    torso(b, 0.0, 0.32, s)
    b.limb((-0.17, 0.385, 0.06), (-0.3, 0.66, 0.048), (-0.4, 0.95, 0.036), (-0.42, 0.985, 0.04))
    b.limb((0.17, 0.385, 0.06), (0.3, 0.64, 0.048), (0.42, 0.84, 0.036), (0.45, 0.87, 0.04))
    b.oval(0.0, 0.93, 0.2, 0.075)
    return b


def points(pts: list[tuple[float, float]], cut_below: float | None = None) -> tuple[list[list[float]], bool]:
    """반올림한 윤곽. cut_below보다 아래는 잘라 열린 선으로 만든다."""
    if cut_below is None:
        return [[round(x, 4), round(y, 4)] for x, y in pts], True
    n = len(pts)
    start = next(i for i in range(n) if pts[i - 1][1] >= cut_below > pts[i][1])
    run = []
    for k in range(n):
        x, y = pts[(start + k) % n]
        if y >= cut_below:
            break
        run.append([round(x, 4), round(y, 4)])
    return run, False


def frame(x: float, y: float) -> dict:
    return {"space": "frame", "x": x, "y": y}


def fig(x: float, y: float) -> dict:
    return {"space": "figure", "x": x, "y": y}


def line(style: str, *pts: dict, label: str | None = None) -> dict:
    return {"style": style, "label": label, "points": list(pts)}


def template(
    id_: str, category: str, title: str, tip: str, guide: list[str], angle: tuple, figure: dict, guides: list
) -> dict:
    lo, hi, roll = angle
    return {
        "id": id_,
        "category": category,
        "title": title,
        "tip": tip,
        "guide": guide,
        "angle": {"elevation_min": lo, "elevation_max": hi, "roll_tolerance": roll},
        "figure": figure,
        "guides": guides,
    }


def figure(
    body: Body,
    height: float,
    anchor: tuple[float, float],
    joints: dict[str, tuple[float, float]],
    span: str,
    cut_below: float | None = None,
) -> dict:
    """joints: 실시간 인물과 비교할 기준점(figure 좌표). span: 머리끝과 함께 인물 크기를 재는 기준점."""
    outline, closed = points(body.outline(), cut_below)
    return {
        "height": height,
        "anchor": list(anchor),
        "closed": closed,
        "joints": {k: list(v) for k, v in joints.items()},
        "span": span,
        "outline": outline,
    }


STANDING = {"head": (0.0, 0.0), "shoulders": (0.0, 0.185), "hips": (0.0, 0.48), "feet": (0.0, 0.99)}
CAFE = {"head": (0.0, 0.0), "shoulders": (0.0, 0.4)}
SITTING = {"head": (0.02, 0.0), "shoulders": (0.0, 0.375), "hips": (0.0, 0.92)}


def main() -> None:
    items = [
        template(
            "tpl-full-body",
            "full_body",
            "전신",
            "발끝을 아래 선에 맞추면 다리가 길어 보여요",
            ["폰을 허리 높이로 낮춰요", "카메라를 살짝 위로 (5~10°)", "발끝을 아래 굵은 선에 맞춰요"],
            (5, 10, 3),
            figure(full_body(), 0.8, (0.5, 0.925), STANDING, "feet"),
            [],
        ),
        template(
            "tpl-cafe",
            "cafe",
            "카페·반신",
            "아래 1/3에 테이블과 음식을 담아요",
            ["맞은편에서 눈높이로", "카메라를 살짝 아래로 (0~10°)", "테이블 선에 테이블 끝을 맞춰요"],
            (-10, 0, 3),
            figure(cafe(), 0.55, (0.5, 0.667), CAFE, "shoulders", cut_below=0.965),
            [line("bold", frame(0.0, 0.667), frame(1.0, 0.667), label="테이블·음식")],
        ),
        template(
            "tpl-landscape",
            "landscape",
            "풍경+인물",
            "인물은 작게, 풍경은 넓게 담아요",
            ["폰을 수평으로 세워요", "지평선을 가운데 선에 맞춰요", "인물을 실루엣 자리에 세워요"],
            (-3, 3, 2),
            figure(full_body(), 0.34, (1 / 3, 0.8), STANDING, "feet"),
            [
                line("bold", frame(0.0, 0.5), frame(1.0, 0.5), label="지평선"),
            ],
        ),
        template(
            "tpl-sitting",
            "sitting",
            "앉은 포즈",
            "다리를 모서리 쪽으로 뻗으면 길어 보여요",
            ["폰을 앉은 사람 가슴 높이로", "카메라를 살짝 위로 (0~5°)", "다리를 대각선 선을 따라 뻗어요"],
            (0, 5, 3),
            figure(sitting(), 0.46, (0.38, 0.66), SITTING, "hips", cut_below=0.955),
            [
                line("dashed", fig(0.2, 0.93), frame(0.97, 0.86)),
                line("dashed", fig(-0.14, 1.02), frame(0.86, 0.97), label="다리"),
            ],
        ),
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"version": 1, "items": items}, ensure_ascii=False, indent=1) + "\n")
    for it in items:
        print(it["id"], len(it["figure"]["outline"]), "점", "닫힘" if it["figure"]["closed"] else "열림")


if __name__ == "__main__":
    main()
