from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
ORIGINAL_DIR = ROOT / ".codex-compare" / "original"
GODOT_DIR = (
    Path.home()
    / "AppData"
    / "Roaming"
    / "Godot"
    / "app_userdata"
    / "e5cm-godot"
    / "shots"
)
OUTPUT_DIR = ROOT / "预开发任务资源"
FONT_PATH = ROOT / "assets" / "fonts" / "fzhei.ttf"


@dataclass(frozen=True)
class Pair:
    folder: str
    slug: str
    original: str
    godot: str
    note: str
    original_boxes: tuple[tuple[int, int, int, int], ...] = ()
    godot_boxes: tuple[tuple[int, int, int, int], ...] = ()


PAIRS = (
    Pair(
        "01_投币",
        "coin_idle",
        "00_coin.png",
        "00_coin_insert.png",
        "① 投币文案与快捷键提示分层不同；玩家选择默认高亮需另看下一状态。",
        ((700, 840, 1220, 1035),),
        ((700, 840, 1220, 1035),),
    ),
    Pair(
        "02_登录磁卡",
        "login_select",
        "01_login_select.png",
        "02_login_select.png",
        "① 对照登录选择静态布局；过渡动画需用连续帧单独验证。",
        ((350, 250, 1570, 930),),
        ((350, 250, 1570, 930),),
    ),
    Pair(
        "02_登录磁卡",
        "login_swipe",
        "02_login_swipe.png",
        "03_login_swipe.png",
        "① 对照刷卡提示与卡片位置；两端均为自动测试固定状态。",
        ((330, 180, 1590, 990),),
        ((330, 180, 1590, 990),),
    ),
    Pair(
        "03_个人资料",
        "profile",
        "03_profile.png",
        "04_profile.png",
        "① 信息层级、经验区与底部操作区存在明显结构差异。",
        ((120, 160, 1800, 960),),
        ((120, 160, 1800, 960),),
    ),
    Pair(
        "04_大模式选择",
        "mode_select",
        "04_mode_select.png",
        "06_mode_select.png",
        "① 静态卡片布局可比；原版下落入场与 Godot 淡入缩放需动态证据。",
        ((150, 180, 1770, 930),),
        ((150, 180, 1770, 930),),
    ),
    Pair(
        "05_子模式选择",
        "submode_select",
        "05_submode_select.png",
        "09_submode_select.png",
        "① 当前页静态布局可比；DIY 超过 6 项的可达性由源码与专项测试确认。",
        ((90, 160, 1830, 960),),
        ((90, 160, 1830, 960),),
    ),
    Pair(
        "05_子模式选择",
        "submode_selected",
        "05b_submode_selected.png",
        "10_submode_selected.png",
        "① 选中态构图可比；文案截断规则另由源码确认。",
        ((80, 120, 1840, 1000),),
        ((80, 120, 1840, 1000),),
    ),
    Pair(
        "06_选歌列表",
        "song_select_unmatched_data",
        "06_song_select.png",
        "11_song_select.png",
        "⚠ 曲目/模式状态不一致，只能审查结构缺项，不能用于像素级结论。",
        ((0, 0, 1920, 150), (40, 150, 1880, 1020)),
        ((0, 0, 1920, 150), (40, 150, 1880, 1020)),
    ),
    Pair(
        "07_选歌详情",
        "song_detail_unmatched_data",
        "07_song_detail.png",
        "14_song_detail.png",
        "⚠ 曲目状态不一致，只记录结构差异；后续补同曲同模式证据。",
        ((50, 120, 1870, 1010),),
        ((50, 120, 1870, 1010),),
    ),
)


GODOT_ONLY = (
    ("01_投币", "01_coin_player_select.png"),
    ("03_个人资料", "05_profile_nickname_editor.png"),
    ("06_选歌列表", "12_song_settings.png"),
    ("06_选歌列表", "13_song_filter.png"),
    ("08_加载与谱面", "15_loading.png"),
    ("08_加载与谱面", "16_gameplay_ready_start.png"),
    ("08_加载与谱面", "17_gameplay_ready_go.png"),
    ("08_加载与谱面", "18_gameplay_active.png"),
    ("08_加载与谱面", "19_gameplay_autoplay.png"),
    ("08_加载与谱面", "20_gameplay_esc_menu.png"),
    ("08_加载与谱面", "21_gameplay_autoplay2.png"),
    ("09_结算", "22_settlement_phase1_counting.png"),
    ("09_结算", "23_settlement_phase1_grade.png"),
    ("09_结算", "24_settlement_phase2_exp.png"),
)


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_PATH), size)


def open_native(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGB")
    if image.size != (1920, 1080):
        raise ValueError(f"证据不是 1920x1080: {path} -> {image.size}")
    return image


def draw_numbered_boxes(
    draw: ImageDraw.ImageDraw,
    boxes: tuple[tuple[int, int, int, int], ...],
    x_offset: int,
    y_offset: int,
) -> None:
    for number, (x1, y1, x2, y2) in enumerate(boxes, start=1):
        shifted = (x1 + x_offset, y1 + y_offset, x2 + x_offset, y2 + y_offset)
        draw.rectangle(shifted, outline=(255, 55, 55), width=7)
        center = (x1 + x_offset + 23, y1 + y_offset + 23)
        draw.ellipse(
            (center[0] - 21, center[1] - 21, center[0] + 21, center[1] + 21),
            fill=(210, 0, 0),
            outline=(255, 255, 255),
            width=3,
        )
        label = str(number)
        box = draw.textbbox((0, 0), label, font=font(28))
        draw.text(
            (center[0] - (box[2] - box[0]) / 2, center[1] - (box[3] - box[1]) / 2 - 2),
            label,
            font=font(28),
            fill=(255, 255, 255),
        )


def build_pair(pair: Pair) -> Path:
    scene_dir = OUTPUT_DIR / pair.folder
    raw_dir = scene_dir / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    original_path = ORIGINAL_DIR / pair.original
    godot_path = GODOT_DIR / pair.godot
    if not original_path.exists() or not godot_path.exists():
        raise FileNotFoundError(f"缺少证据: {original_path} / {godot_path}")

    shutil.copy2(original_path, raw_dir / f"original_{pair.original}")
    shutil.copy2(godot_path, raw_dir / f"godot_{pair.godot}")

    original = open_native(original_path)
    godot = open_native(godot_path)
    canvas = Image.new("RGB", (3840, 1235), (18, 20, 25))
    canvas.paste(original, (0, 80))
    canvas.paste(godot, (1920, 80))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, 1919, 79), fill=(37, 43, 54))
    draw.rectangle((1920, 0, 3839, 79), fill=(25, 62, 78))
    draw.text((36, 19), "原版 Python/Pygame · 1920×1080", font=font(36), fill="white")
    draw.text((1956, 19), "Godot 重构版 · 1920×1080", font=font(36), fill="white")
    draw_numbered_boxes(draw, pair.original_boxes, 0, 80)
    draw_numbered_boxes(draw, pair.godot_boxes, 1920, 80)
    draw.rectangle((0, 1160, 3839, 1234), fill=(32, 34, 40))
    note_color = (255, 210, 80) if pair.note.startswith("⚠") else (255, 235, 235)
    draw.text((36, 1176), pair.note, font=font(30), fill=note_color)

    output = scene_dir / f"对照_{pair.slug}.png"
    canvas.save(output, optimize=True)
    return output


def copy_godot_only() -> None:
    for folder, name in GODOT_ONLY:
        source = GODOT_DIR / name
        if not source.exists():
            raise FileNotFoundError(source)
        target_dir = OUTPUT_DIR / folder / "godot_only"
        target_dir.mkdir(parents=True, exist_ok=True)
        open_native(source)
        shutil.copy2(source, target_dir / name)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    outputs = [build_pair(pair) for pair in PAIRS]
    copy_godot_only()
    print(f"OK: {len(outputs)} paired evidence images; {len(GODOT_ONLY)} Godot-only images")


if __name__ == "__main__":
    main()
