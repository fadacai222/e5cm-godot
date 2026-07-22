from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PROJECT_SETTINGS = PROJECT_ROOT / "project.godot"
EXPORT_PRESETS = PROJECT_ROOT / "export_presets.cfg"
INNO_SCRIPT = PROJECT_ROOT / "packaging" / "E5CM.iss"

VERSION_PATTERN = re.compile(r"^(?:godot-)?(\d+)\.(\d+)\.(\d+)$", re.IGNORECASE)
PROJECT_VERSION_PATTERN = re.compile(r'(?m)^config/version="([^"]+)"$')
FILE_VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+\.\d+$")

# 运行时、界面和契约测试中若意外写死了旧版本，也随发行版本一起同步。
# 历史任务、README 和 release 产物不改，避免篡改历史记录或旧安装包。
TEXT_SYNC_ROOTS = (
    PROJECT_ROOT / "scenes",
    PROJECT_ROOT / "ui",
    PROJECT_ROOT / "autoload",
    PROJECT_ROOT / "core",
    PROJECT_ROOT / "fx",
    PROJECT_ROOT / "tests",
)
TEXT_SYNC_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg", ".json", ".txt"}


def fail(message: str) -> None:
    raise RuntimeError(message)


def normalize_version(raw: str) -> tuple[str, str]:
    value = raw.strip()
    match = VERSION_PATTERN.fullmatch(value)
    if match is None:
        fail("版本号格式必须是 2.0.2 或 godot-2.0.2（三段纯数字）")
    major, minor, patch = match.groups()
    display_version = f"godot-{int(major)}.{int(minor)}.{int(patch)}"
    file_version = f"{int(major)}.{int(minor)}.{int(patch)}.0"
    return display_version, file_version


def read_text(path: Path) -> tuple[str, bool]:
    raw = path.read_bytes()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    return raw.decode("utf-8-sig"), has_bom


def write_text(path: Path, text: str, has_bom: bool) -> None:
    payload = text.encode("utf-8")
    if has_bom:
        payload = b"\xef\xbb\xbf" + payload
    path.write_bytes(payload)


def replace_exact(path: Path, pattern: re.Pattern[str], replacement: str, label: str) -> bool:
    text, has_bom = read_text(path)
    updated, count = pattern.subn(replacement, text)
    if count != 1:
        fail(f"{label} 应唯一匹配 1 处，实际为 {count}：{path}")
    if updated == text:
        return False
    write_text(path, updated, has_bom)
    return True


def current_version() -> tuple[str, str]:
    text, _ = read_text(PROJECT_SETTINGS)
    match = PROJECT_VERSION_PATTERN.search(text)
    if match is None:
        fail("project.godot 缺少 application/config/version")
    return normalize_version(match.group(1))


def iter_runtime_text_files() -> list[Path]:
    files: list[Path] = []
    for root in TEXT_SYNC_ROOTS:
        if not root.is_dir():
            continue
        files.extend(
            path
            for path in root.rglob("*")
            if path.is_file() and path.suffix.lower() in TEXT_SYNC_SUFFIXES
        )
    return sorted(set(files))


def replace_runtime_literals(old_display: str, new_display: str,
                             old_file: str, new_file: str) -> list[str]:
    if old_display == new_display and old_file == new_file:
        return []
    changed: list[str] = []
    for path in iter_runtime_text_files():
        text, has_bom = read_text(path)
        updated = text.replace(old_display, new_display).replace(old_file, new_file)
        if updated == text:
            continue
        write_text(path, updated, has_bom)
        changed.append(path.relative_to(PROJECT_ROOT).as_posix())
    return changed


def sync_version(raw_version: str) -> dict[str, object]:
    new_display, new_file = normalize_version(raw_version)
    old_display, old_file = current_version()
    changed: list[str] = []

    if replace_exact(
        PROJECT_SETTINGS,
        PROJECT_VERSION_PATTERN,
        f'config/version="{new_display}"',
        "project.godot 游戏版本",
    ):
        changed.append("project.godot")

    file_pattern = re.compile(r'(?m)^application/file_version="[^"]+"$')
    product_pattern = re.compile(r'(?m)^application/product_version="[^"]+"$')
    if replace_exact(
        EXPORT_PRESETS,
        file_pattern,
        f'application/file_version="{new_file}"',
        "Windows 文件版本",
    ):
        changed.append("export_presets.cfg:file_version")
    if replace_exact(
        EXPORT_PRESETS,
        product_pattern,
        f'application/product_version="{new_file}"',
        "Windows 产品版本",
    ):
        changed.append("export_presets.cfg:product_version")

    app_pattern = re.compile(r'(?m)^#define MyAppVersion "[^"]+"$')
    inno_file_pattern = re.compile(r'(?m)^#define MyAppFileVersion "[^"]+"$')
    if replace_exact(
        INNO_SCRIPT,
        app_pattern,
        f'#define MyAppVersion "{new_display}"',
        "Inno Setup 显示版本",
    ):
        changed.append("packaging/E5CM.iss:MyAppVersion")
    if replace_exact(
        INNO_SCRIPT,
        inno_file_pattern,
        f'#define MyAppFileVersion "{new_file}"',
        "Inno Setup 文件版本",
    ):
        changed.append("packaging/E5CM.iss:MyAppFileVersion")

    changed.extend(replace_runtime_literals(old_display, new_display, old_file, new_file))
    verify_version(new_display, new_file)
    return {
        "previousVersion": old_display,
        "version": new_display,
        "fileVersion": new_file,
        "changed": changed,
    }


def verify_version(expected_display: str, expected_file: str) -> dict[str, object]:
    if not FILE_VERSION_PATTERN.fullmatch(expected_file):
        fail(f"Windows 文件版本无效：{expected_file}")
    actual_display, actual_file = current_version()
    if actual_display != expected_display or actual_file != expected_file:
        fail(
            f"project.godot 版本不一致：actual={actual_display}/{actual_file} "
            f"expected={expected_display}/{expected_file}"
        )

    checks = {
        "project.godot": f'config/version="{expected_display}"',
        "export_presets.cfg:file": f'application/file_version="{expected_file}"',
        "export_presets.cfg:product": f'application/product_version="{expected_file}"',
        "packaging/E5CM.iss:display": f'#define MyAppVersion "{expected_display}"',
        "packaging/E5CM.iss:file": f'#define MyAppFileVersion "{expected_file}"',
    }
    contents = {
        "project.godot": read_text(PROJECT_SETTINGS)[0],
        "export_presets.cfg:file": read_text(EXPORT_PRESETS)[0],
        "export_presets.cfg:product": read_text(EXPORT_PRESETS)[0],
        "packaging/E5CM.iss:display": read_text(INNO_SCRIPT)[0],
        "packaging/E5CM.iss:file": read_text(INNO_SCRIPT)[0],
    }
    missing = [name for name, needle in checks.items() if needle not in contents[name]]
    if missing:
        fail("以下版本元数据未同步：" + ", ".join(missing))
    return {"version": expected_display, "fileVersion": expected_file, "verified": True}


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="E5CM 发行版本统一管理")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("show")
    normalize_parser = subparsers.add_parser("normalize")
    normalize_parser.add_argument("--version", required=True)
    sync_parser = subparsers.add_parser("sync")
    sync_parser.add_argument("--version", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--version")

    args = parser.parse_args()
    try:
        if args.command == "show":
            display, file_version = current_version()
            emit({"version": display, "fileVersion": file_version})
        elif args.command == "normalize":
            display, file_version = normalize_version(args.version)
            emit({"version": display, "fileVersion": file_version})
        elif args.command == "sync":
            emit(sync_version(args.version))
        elif args.command == "verify":
            if args.version:
                display, file_version = normalize_version(args.version)
            else:
                display, file_version = current_version()
            emit(verify_version(display, file_version))
        return 0
    except Exception as exc:  # noqa: BLE001 - command must surface all release failures.
        print(f"VERSION_ERROR: {exc}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
