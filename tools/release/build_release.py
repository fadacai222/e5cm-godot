from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _read_release_version() -> tuple[str, str]:
    requested = os.environ.get("E5CM_RELEASE_VERSION", "").strip()
    if not requested:
        project_text = (PROJECT_ROOT / "project.godot").read_text(encoding="utf-8-sig")
        match = re.search(r'(?m)^config/version="([^"]+)"$', project_text)
        if match is None:
            raise RuntimeError("project.godot 缺少 application/config/version")
        requested = match.group(1)
    match = re.fullmatch(r"(?:godot-)?(\d+)\.(\d+)\.(\d+)", requested, re.IGNORECASE)
    if match is None:
        raise RuntimeError(f"无效发行版本：{requested}")
    major, minor, patch = (int(value) for value in match.groups())
    display_version = f"godot-{major}.{minor}.{patch}"
    file_version = os.environ.get("E5CM_FILE_VERSION", "").strip() or \
        f"{major}.{minor}.{patch}.0"
    if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", file_version) is None:
        raise RuntimeError(f"无效 Windows 文件版本：{file_version}")
    return display_version, file_version


VERSION, FILE_VERSION = _read_release_version()
SEED = "20260718-e5cm-release"
MAX_SONGS_PER_MODE = 4
MAX_RANDOM_FOLDER_BYTES = 180 * 1024 * 1024

STAGING_ROOT = PROJECT_ROOT / ".release-staging"
STAGING_SONGS = STAGING_ROOT / "songs"
RELEASE_ROOT = PROJECT_ROOT / "release"
PORTABLE_ROOT = RELEASE_ROOT / "E5CM"
PORTABLE_SONGS = PORTABLE_ROOT / "songs"
INDEX_PATH = PROJECT_ROOT / "assets" / "e5cm_runtime" / "song_index.json"
RELEASE_INDEX_NAME = "release-song-index.json"
SAMPLE_INDEX = STAGING_ROOT / RELEASE_INDEX_NAME
PORTABLE_INDEX = PORTABLE_ROOT / RELEASE_INDEX_NAME
SELECTION_MANIFEST = STAGING_ROOT / "release-song-selection.json"

CHART_EXTENSIONS = {".sm", ".ssc", ".json"}
AUDIO_EXTENSIONS = {".mp3", ".ogg"}
PATH_FIELDS = ("sm", "mp3", "cover", "video")
EXPORT_PRESET_PATH = PROJECT_ROOT / "export_presets.cfg"
PROJECT_SETTINGS_PATH = PROJECT_ROOT / "project.godot"
EXACT_DUPLICATE_EXPORTS = (
    (
        "assets/video/player_select/003.mp4",
        "assets/e5cm_runtime/backmovies/003.mp4",
    ),
    (
        "assets/audio/player_select/ranking.mp3",
        "assets/e5cm_runtime/冷资源/backsound/排行榜.mp3",
    ),
    (
        "assets/fonts/fzhei.ttf",
        "assets/e5cm_runtime/冷资源/字体/方正黑体简体.TTF",
    ),
    (
        "assets/e5cm_runtime/UI-img/游戏界面/箭头/02/key_effect/skin.png",
        "assets/e5cm_runtime/UI-img/游戏界面/箭头/03/key_effect/skin.png",
    ),
)
REQUIRED_CLEAN_EXPORT_EXCLUSIONS = (
    "songs/**",
    "assets/e5cm_runtime/songs/**",
    "assets/e5cm_runtime/song_index.json",
    ".release-staging/**",
    "release/**",
    "tests/**",
    "tools/**",
    "tasks/**",
    "新功能开发计划/**",
    "assets/rewards/avatar_frames.svg",
    "assets/rewards/profile_cards.svg",
    "*.md",
)
REQUIRED_RELEASE_SETTINGS = (
    'config/use_custom_user_dir.release=true',
    'config/custom_user_dir_name.release="E5CM-PlayerData"',
)
ALLOWED_PORTABLE_ROOT_FILES = {
    "E5CM.exe",
    "E5CM.pck",
    "E5CM-Compatibility.bat",
    RELEASE_INDEX_NAME,
    "release-song-selection.json",
    "版本信息.txt",
    "avcodec-60.dll",
    "avfilter-9.dll",
    "avformat-60.dll",
    "avutil-58.dll",
    "libgdffmpeg.windows.template_release.x86_64.dll",
    "swresample-4.dll",
    "swscale-7.dll",
}
FORBIDDEN_PLAYER_DATA_NAMES = {
    "profile.json",
    "records.json",
    "favorites.json",
    "credits.cfg",
    "settings.cfg",
    "rewards_v1.json",
    "analytics_v1.json",
    "challenge_state_v1.json",
    "feature_data",
    "cache",
    "ghosts",
    "shots",
}
REQUIRED_EXPORT_EXCLUSIONS = (
    "addons/ffmpeg/**/~libgdffmpeg*",
    "assets/e5cm_runtime/backmovies/003.mp4",
    "assets/e5cm_runtime/UI-img/游戏界面/箭头/03/key_effect/skin.png",
    "assets/e5cm_runtime/冷资源/**/*.ogg",
    "assets/e5cm_runtime/冷资源/backsound/排行榜.mp3",
    "assets/e5cm_runtime/冷资源/Buttonsound/点击-增益5.mp3",
    "assets/e5cm_runtime/冷资源/Buttonsound/点击-增益5-旧的.mp3",
    "assets/e5cm_runtime/冷资源/字体/方正黑体简体.TTF",
)


def log(message: str) -> None:
    print(message, flush=True)


def fail(message: str) -> None:
    raise RuntimeError(message)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_release_asset_policy() -> None:
    if not EXPORT_PRESET_PATH.is_file():
        fail(f"导出配置不存在：{EXPORT_PRESET_PATH}")
    if not PROJECT_SETTINGS_PATH.is_file():
        fail(f"项目配置不存在：{PROJECT_SETTINGS_PATH}")
    preset_text = EXPORT_PRESET_PATH.read_text(encoding="utf-8")
    missing_exclusions = [
        path for path in REQUIRED_EXPORT_EXCLUSIONS if path not in preset_text
    ]
    if missing_exclusions:
        fail("导出配置缺少资源去重项：" + ", ".join(missing_exclusions))
    missing_clean_exclusions = [
        path for path in REQUIRED_CLEAN_EXPORT_EXCLUSIONS if path not in preset_text
    ]
    if missing_clean_exclusions:
        fail("导出配置可能夹带开发/测试资料：" + ", ".join(missing_clean_exclusions))
    if 'custom_features="e5cm_release"' not in preset_text:
        fail("Windows 导出未注入 e5cm_release 正式版标记。")
    project_text = PROJECT_SETTINGS_PATH.read_text(encoding="utf-8-sig")
    missing_release_settings = [
        setting for setting in REQUIRED_RELEASE_SETTINGS if setting not in project_text
    ]
    if missing_release_settings:
        fail("正式版未隔离玩家数据目录：" + ", ".join(missing_release_settings))

    for canonical_relative, duplicate_relative in EXACT_DUPLICATE_EXPORTS:
        canonical = PROJECT_ROOT / canonical_relative
        duplicate = PROJECT_ROOT / duplicate_relative
        if not canonical.is_file() or not duplicate.is_file():
            fail(f"资源去重校验缺文件：{canonical_relative} / {duplicate_relative}")
        canonical_hash = file_sha256(canonical)
        duplicate_hash = file_sha256(duplicate)
        if canonical_hash != duplicate_hash:
            fail(
                "原本重复的发行资源已经分叉，禁止继续排除副本："
                f"{canonical_relative} != {duplicate_relative}"
            )
    log(
        "RELEASE_ASSET_POLICY_VERIFIED "
        f"duplicates={len(EXACT_DUPLICATE_EXPORTS)} clean_export=true isolated_user_data=true"
    )


def verify_clean_portable_layout(root: Path) -> None:
    if not root.is_dir():
        fail(f"发行目录不存在：{root}")
    unexpected: list[str] = []
    forbidden: list[str] = []
    for item in root.iterdir():
        name_lower = item.name.lower()
        if item.is_dir():
            if name_lower != "songs":
                unexpected.append(item.name + "/")
            if name_lower in FORBIDDEN_PLAYER_DATA_NAMES:
                forbidden.append(item.name + "/")
            continue
        if item.name not in ALLOWED_PORTABLE_ROOT_FILES:
            unexpected.append(item.name)
        if name_lower in FORBIDDEN_PLAYER_DATA_NAMES:
            forbidden.append(item.name)
    if forbidden:
        fail("发行目录包含玩家存档/测试资料：" + ", ".join(sorted(forbidden)))
    if unexpected:
        fail("发行目录包含未审核文件：" + ", ".join(sorted(unexpected)))
    log("PORTABLE_LAYOUT_CLEAN player_data=empty root_allowlist=passed")


def directory_size(path: Path) -> int:
    total = 0
    for root, _, files in os.walk(path):
        for filename in files:
            try:
                total += (Path(root) / filename).stat().st_size
            except OSError:
                pass
    return total


def deterministic_key(relative_path: str) -> str:
    return hashlib.sha256(f"{SEED}|{relative_path}".encode("utf-8")).hexdigest()


def is_release_playable(song_dir: Path) -> bool:
    try:
        files = [item for item in song_dir.iterdir() if item.is_file()]
    except OSError:
        return False
    has_chart = any(item.suffix.lower() in CHART_EXTENSIONS for item in files)
    has_audio = any(item.suffix.lower() in AUDIO_EXTENSIONS for item in files)
    return has_chart and has_audio


def locate_full_song_library() -> Path:
    project_songs = PROJECT_ROOT / "songs"
    if project_songs.is_dir():
        song_folder_count = sum(
            1
            for top in project_songs.iterdir()
            if top.is_dir()
            for sub in top.iterdir()
            if sub.is_dir()
            for song in sub.iterdir()
            if song.is_dir()
        )
        if song_folder_count > 100:
            return project_songs
    fail("找不到完整曲库：项目 songs 不存在或看起来不是全量曲库。")


def enumerate_mode_leaves(song_root: Path) -> list[Path]:
    leaves: list[Path] = []
    for top in sorted((item for item in song_root.iterdir() if item.is_dir()), key=lambda p: p.name):
        for sub in sorted((item for item in top.iterdir() if item.is_dir()), key=lambda p: p.name):
            leaves.append(sub)
    if not leaves:
        fail(f"曲库没有可用模式目录：{song_root}")
    return leaves


def choose_songs(song_root: Path) -> dict[str, dict[str, Any]]:
    selection: dict[str, dict[str, Any]] = {}
    for leaf in enumerate_mode_leaves(song_root):
        relative_leaf = leaf.relative_to(song_root).as_posix()
        candidates: list[Path] = []
        for song_dir in sorted((item for item in leaf.iterdir() if item.is_dir()), key=lambda p: p.name):
            if is_release_playable(song_dir):
                candidates.append(song_dir)
        if not candidates:
            selection[relative_leaf] = {
                "availablePlayableFolders": 0,
                "selectedCount": 0,
                "selected": [],
                "excludedReason": "源曲库只有占位或缺少可播放音频/谱面",
            }
            continue

        # 先按稳定随机键排序，再只计算实际候选的目录大小；避免为了抽 4 首遍历整套 51GB 曲库。
        candidates.sort(key=lambda path: deterministic_key(path.relative_to(song_root).as_posix()))
        chosen: list[tuple[Path, int]] = []
        oversized: list[tuple[Path, int]] = []
        for song_dir in candidates:
            size = directory_size(song_dir)
            if size <= MAX_RANDOM_FOLDER_BYTES:
                chosen.append((song_dir, size))
                if len(chosen) >= MAX_SONGS_PER_MODE:
                    break
            else:
                oversized.append((song_dir, size))
        if len(chosen) < MAX_SONGS_PER_MODE:
            chosen.extend(oversized[: MAX_SONGS_PER_MODE - len(chosen)])
        selection[relative_leaf] = {
            "availablePlayableFolders": len(candidates),
            "selectedCount": len(chosen),
            "selected": [
                {
                    "folder": song_dir.name,
                    "relativePath": song_dir.relative_to(song_root).as_posix(),
                    "bytes": size,
                }
                for song_dir, size in chosen
            ],
        }
    return selection


def copy_selected_songs(song_root: Path, selection: dict[str, dict[str, Any]], destination: Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / ".gdignore").touch()
    for relative_leaf, payload in selection.items():
        if not payload["selected"]:
            continue
        target_leaf = destination / Path(relative_leaf)
        target_leaf.mkdir(parents=True, exist_ok=True)
        for item in payload["selected"]:
            source = song_root / Path(item["relativePath"])
            target = destination / Path(item["relativePath"])
            shutil.copytree(source, target, ignore=shutil.ignore_patterns("*.import"))


def locate_full_index() -> Path:
    if INDEX_PATH.is_file():
        try:
            data = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
            if int(data.get("songVariantCount", 0)) > 1000 \
                    and not str(data.get("releaseVersion", "")):
                return INDEX_PATH
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"完整 song_index.json 无法解析：{exc}")
    fail("找不到完整开发 song_index.json，请先运行 tools/build_song_index.gd 重建。")


def rewrite_song_path(value: Any) -> Any:
    if not isinstance(value, str) or not value:
        return value
    normalized = value.replace("\\", "/")
    prefixes = (
        "res://assets/e5cm_runtime/songs/",
        "res://songs/",
    )
    for prefix in prefixes:
        if normalized.startswith(prefix):
            return "res://songs/" + normalized[len(prefix) :]
    marker = "/songs/"
    if marker in normalized:
        return "res://songs/" + normalized.split(marker, 1)[1]
    return normalized


def build_release_index(selection: dict[str, dict[str, Any]]) -> dict[str, Any]:
    full_index_path = locate_full_index()
    full_index = json.loads(full_index_path.read_text(encoding="utf-8"))
    full_songs_by_key = full_index.get("songsByKey", {})
    release_songs_by_key: dict[str, list[dict[str, Any]]] = {}
    submodes_by_mode: dict[str, list[str]] = {}
    total_variants = 0

    for relative_leaf, payload in selection.items():
        if not payload["selected"]:
            continue
        top, submode = relative_leaf.split("/", 1)
        mode = "DIY" if top.lower() == "diy" else top
        key = f"{mode}/{submode}"
        selected_folders = {str(item["folder"]) for item in payload["selected"]}
        raw_entries = full_songs_by_key.get(key)
        if not isinstance(raw_entries, list):
            fail(f"完整索引缺少模式键：{key}")
        entries: list[dict[str, Any]] = []
        for raw_entry in raw_entries:
            if not isinstance(raw_entry, dict) or str(raw_entry.get("folder", "")) not in selected_folders:
                continue
            entry = dict(raw_entry)
            for field in PATH_FIELDS:
                if field in entry:
                    entry[field] = rewrite_song_path(entry[field])
            entries.append(entry)
        missing = selected_folders - {str(entry.get("folder", "")) for entry in entries}
        if missing:
            fail(f"精选歌曲没有出现在静态索引 {key}：{sorted(missing)}")
        release_songs_by_key[key] = entries
        submodes_by_mode.setdefault(mode, []).append(submode)
        total_variants += len(entries)

    for mode in submodes_by_mode:
        submodes_by_mode[mode] = sorted(submodes_by_mode[mode])

    release_index = {
        "schemaVersion": 1,
        "generatedAtUnix": int(time.time()),
        "runtimeRoot": "res://songs",
        "releaseVersion": VERSION,
        "releaseSeed": SEED,
        "submodesByMode": submodes_by_mode,
        "songsByKey": release_songs_by_key,
        "songVariantCount": total_variants,
    }
    return release_index


def build_release_index_with_godot() -> dict[str, Any]:
    godot = os.environ.get("E5CM_GODOT_CONSOLE", "").strip()
    if not godot:
        godot = str(PROJECT_ROOT.parent / "Godot_v4.6.2-stable_win64_console.exe")
    if not Path(godot).is_file():
        fail(f"未找到 Godot 控制台：{godot}")
    env = os.environ.copy()
    env["E5CM_RELEASE_SONGS_ROOT"] = str(STAGING_SONGS)
    env["E5CM_RELEASE_INDEX_PATH"] = str(SAMPLE_INDEX)
    env["E5CM_RELEASE_VERSION"] = VERSION
    env["PYTHONUTF8"] = "1"
    subprocess.run(
        [
            godot,
            "--headless",
            "--path",
            str(PROJECT_ROOT),
            "--script",
            "res://tools/release/build_selected_song_index.gd",
        ],
        check=True,
        env=env,
        cwd=PROJECT_ROOT,
    )
    if not SAMPLE_INDEX.is_file():
        fail("Godot 没有生成精选发行索引。")
    return json.loads(SAMPLE_INDEX.read_text(encoding="utf-8"))


def verify_release_index(index: dict[str, Any], songs_root: Path) -> None:
    missing: list[str] = []
    for entries in index.get("songsByKey", {}).values():
        for entry in entries:
            for field in ("sm", "mp3", "cover"):
                value = str(entry.get(field, ""))
                if not value:
                    continue
                if not value.startswith("res://songs/"):
                    missing.append(f"非发行路径：{value}")
                    continue
                target = songs_root / Path(value.removeprefix("res://songs/"))
                if not target.is_file():
                    missing.append(value)
    if missing:
        fail("发行索引存在缺失资源：\n" + "\n".join(missing[:30]))


def generate_brand_icon() -> None:
    source = PROJECT_ROOT / "assets" / "ui" / "player_select" / "logo.png"
    branding = PROJECT_ROOT / "assets" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    png_target = branding / "e5cm_icon.png"
    ico_target = branding / "e5cm.ico"
    if png_target.is_file() and ico_target.is_file():
        return
    magick = shutil.which("magick.exe") or shutil.which("magick")
    if not magick:
        fail("未找到 ImageMagick magick.exe，无法生成缺失的游戏 Logo 图标。")
    common = [
        magick,
        str(source),
        "-background",
        "none",
        "-gravity",
        "center",
        "-extent",
        "1162x1162",
    ]
    if not png_target.is_file():
        subprocess.run(common + ["-resize", "512x512", str(png_target)], check=True)
    if not ico_target.is_file():
        subprocess.run(
            common
            + [
                "-resize",
                "256x256",
                "-define",
                "icon:auto-resize=256,128,64,48,32,16",
                str(ico_target),
            ],
            check=True,
        )


def prepare() -> None:
    verify_release_asset_policy()
    song_root = locate_full_song_library()
    log(f"FULL_SONGS={song_root}")
    if STAGING_ROOT.exists():
        shutil.rmtree(STAGING_ROOT)
    STAGING_ROOT.mkdir(parents=True, exist_ok=True)
    if PORTABLE_ROOT.exists():
        shutil.rmtree(PORTABLE_ROOT)
    PORTABLE_ROOT.mkdir(parents=True, exist_ok=True)

    selection = choose_songs(song_root)
    copy_selected_songs(song_root, selection, STAGING_SONGS)
    release_index = build_release_index_with_godot()
    verify_release_index(release_index, STAGING_SONGS)

    total_selected = sum(int(item["selectedCount"]) for item in selection.values())
    total_bytes = sum(
        int(song["bytes"])
        for item in selection.values()
        for song in item["selected"]
    )
    manifest = {
        "releaseVersion": VERSION,
        "fileVersion": FILE_VERSION,
        "selectionSeed": SEED,
        "maxSongsPerPlayableMode": MAX_SONGS_PER_MODE,
        "playableModeCount": sum(1 for item in selection.values() if item["selectedCount"] > 0),
        "selectedSongFolderCount": total_selected,
        "selectedBytes": total_bytes,
        "note": "少于 4 首的模式会全部保留，不复制同一歌曲凑数。",
        "modes": selection,
    }
    SELECTION_MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    SAMPLE_INDEX.write_text(json.dumps(release_index, ensure_ascii=False), encoding="utf-8")

    # 精选索引只作为 EXE 同目录的发行侧车文件，绝不覆盖开发用完整索引。
    shutil.copy2(SAMPLE_INDEX, PORTABLE_INDEX)
    generate_brand_icon()

    shutil.copytree(STAGING_SONGS, PORTABLE_SONGS)
    shutil.copy2(SELECTION_MANIFEST, PORTABLE_ROOT / "release-song-selection.json")
    (PORTABLE_ROOT / "版本信息.txt").write_text(
        f"E5CM {VERSION}\n每个可玩模式随机保留最多 4 首歌曲。\n"
        f"抽样种子：{SEED}\n歌曲文件夹：{total_selected}\n"
        "老显卡、虚拟机或远程桌面启动失败时，可运行 E5CM-Compatibility.bat。\n",
        encoding="utf-8",
    )
    (PORTABLE_ROOT / "E5CM-Compatibility.bat").write_bytes(
        b'@echo off\r\nstart "" "%~dp0E5CM.exe" --rendering-method gl_compatibility\r\n'
    )
    playable_mode_count = sum(1 for item in selection.values() if item["selectedCount"] > 0)
    excluded_modes = [key for key, item in selection.items() if item["selectedCount"] == 0]
    log(f"PLAYABLE_MODES={playable_mode_count}")
    log(f"EXCLUDED_EMPTY_MODES={excluded_modes}")
    log(f"SELECTED_SONG_FOLDERS={total_selected}")
    log(f"SELECTED_BYTES={total_bytes}")
    log(f"SONG_VARIANTS={release_index['songVariantCount']}")
    log(f"PORTABLE_ROOT={PORTABLE_ROOT}")


def restore_index() -> None:
    """向旧打包脚本保持兼容；新流程从不替换开发索引。"""
    full_index = locate_full_index()
    log(f"开发用完整曲库索引保持不变：{full_index}")


def verify_portable() -> None:
    verify_clean_portable_layout(PORTABLE_ROOT)
    manifest_path = PORTABLE_ROOT / "release-song-selection.json"
    if not manifest_path.is_file():
        fail("发行目录缺少 release-song-selection.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for relative_leaf, payload in manifest["modes"].items():
        leaf = PORTABLE_SONGS / Path(relative_leaf)
        actual = sorted(item.name for item in leaf.iterdir() if item.is_dir()) if leaf.is_dir() else []
        expected = sorted(str(item["folder"]) for item in payload["selected"])
        if actual != expected:
            fail(f"发行曲库不一致 {relative_leaf}: actual={actual} expected={expected}")
        if len(actual) > MAX_SONGS_PER_MODE:
            fail(f"模式超过 4 首：{relative_leaf}={len(actual)}")
    if not (PORTABLE_ROOT / "E5CM.exe").is_file():
        fail("发行目录缺少 E5CM.exe")
    if not (PORTABLE_ROOT / "E5CM.pck").is_file():
        fail("发行目录缺少 E5CM.pck")
    if not PORTABLE_INDEX.is_file():
        fail(f"发行目录缺少 {RELEASE_INDEX_NAME}")
    if not (PORTABLE_ROOT / "E5CM-Compatibility.bat").is_file():
        fail("发行目录缺少 OpenGL 兼容模式启动入口")
    release_index = json.loads(PORTABLE_INDEX.read_text(encoding="utf-8"))
    verify_release_index(release_index, PORTABLE_SONGS)
    log("PORTABLE_RELEASE_VERIFIED")


def prune_obsolete_installers() -> None:
    """只保留当前版本安装包；兼容清理旧版无版本号命名。"""
    installer = RELEASE_ROOT / f"E5CM-Setup-{VERSION}.exe"
    if not installer.is_file():
        fail(f"当前安装包不存在，拒绝清理旧产物：{installer}")
    for old_installer in RELEASE_ROOT.glob("E5CM-Setup*.exe"):
        if old_installer != installer:
            old_installer.unlink()
            log(f"REMOVED_OBSOLETE_INSTALLER={old_installer}")


def finalize() -> None:
    """完成发行清理，但绝不移动或替换开发用完整曲库。"""
    verify_portable()
    installer = RELEASE_ROOT / f"E5CM-Setup-{VERSION}.exe"
    smoke_marker = STAGING_ROOT / "installer-smoke-passed.txt"
    if not installer.is_file():
        fail(f"安装包不存在：{installer}")
    if not smoke_marker.is_file():
        fail("安装包烟测标记不存在，禁止完成发行清理。")

    prune_obsolete_installers()

    project_songs = PROJECT_ROOT / "songs"
    if not project_songs.is_dir():
        fail("完整开发曲库 songs 不存在，拒绝完成发行清理。")
    song_folder_count = sum(
        1
        for top in project_songs.iterdir()
        if top.is_dir()
        for sub in top.iterdir()
        if sub.is_dir()
        for song in sub.iterdir()
        if song.is_dir()
    )
    if song_folder_count <= 100:
        fail(
            "项目 songs 看起来已被精选曲库替换，拒绝完成发行清理："
            f"song_folder_count={song_folder_count}"
        )

    # 新流程从不替换开发索引；完成前仍验证它是完整索引。
    locate_full_index()

    # 只清理本次构建产生的隐藏暂存；兼容清理旧流程遗留的备份目录。
    for transient in [STAGING_ROOT, PROJECT_ROOT / ".release-backup"]:
        if transient.is_dir():
            shutil.rmtree(transient)
    log(f"FULL_SONGS_UNCHANGED={project_songs}")
    log(f"FULL_SONG_FOLDER_COUNT={song_folder_count}")
    log("PROJECT_CLEANUP_FINALIZED")


def main() -> int:
    parser = argparse.ArgumentParser(description="E5CM release builder")
    parser.add_argument(
        "command",
        choices=("audit-assets", "prepare", "restore-index", "verify", "prune-installers", "finalize"),
    )
    args = parser.parse_args()
    try:
        if args.command == "audit-assets":
            verify_release_asset_policy()
        elif args.command == "prepare":
            prepare()
        elif args.command == "restore-index":
            restore_index()
        elif args.command == "verify":
            verify_portable()
        elif args.command == "prune-installers":
            prune_obsolete_installers()
        elif args.command == "finalize":
            finalize()
        return 0
    except Exception as exc:  # noqa: BLE001 - release script must report all failures clearly.
        print(f"RELEASE_ERROR: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
