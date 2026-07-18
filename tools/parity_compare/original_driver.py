from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image

from .manifest import load_and_validate_manifest


SCENE_NAMES = {
    "投币": "coin",
    "登陆磁卡": "login",
    "个人资料": "profile",
    "大模式": "mode_select",
    "子模式": "submode_select",
    "选歌": "song_select",
    "加载页": "loading",
    "谱面播放器": "gameplay",
    "结算": "settlement",
}


class OriginalDriverError(RuntimeError):
    pass


def canonical_state(raw: dict[str, Any], state_id: str) -> dict[str, Any]:
    raw_scene = raw.get("scene") if isinstance(raw.get("scene"), dict) else {}
    raw_scene_state = raw.get("sceneState") if isinstance(raw.get("sceneState"), dict) else {}
    credits = raw.get("credits")
    credit = credits.get("coins", 0) if isinstance(credits, dict) else raw.get("credit", 0)
    players_value = raw.get("players")
    if isinstance(players_value, dict):
        players = players_value.get("count", 0)
        login_type = players_value.get("loginType", "")
    else:
        players = players_value or 0
        login_type = raw.get("loginType", "")
    mode = raw.get("mode") if isinstance(raw.get("mode"), dict) else {}
    scene_name = str(raw_scene.get("name", ""))
    scene = {"name": SCENE_NAMES.get(scene_name, scene_name)}
    scene.update(raw_scene_state)
    return {
        "stateId": state_id,
        "global": {
            "credit": int(credit or 0),
            "players": int(players or 0),
            "loginType": str(login_type or ""),
            "majorMode": str(mode.get("major", raw.get("majorMode", "")) or ""),
            "subMode": str(mode.get("sub", raw.get("subMode", "")) or ""),
        },
        "scene": scene,
    }


def _request(session: dict[str, Any], path: str, *, method: str = "GET", body: Any = None) -> dict[str, Any]:
    encoded = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        f"http://127.0.0.1:{session['port']}{path}",
        data=encoded,
        method=method,
        headers={
            "X-E5CM-Test-Token": session["token"],
            "Content-Type": "application/json; charset=utf-8",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=65.0) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        result = json.loads(error.read().decode("utf-8"))
    if not result.get("ok"):
        safe_error = result.get("error", {})
        raise OriginalDriverError(f"API request failed {path}: {safe_error}")
    return result.get("data") or {}


def _command(session: dict[str, Any], action: str, params: dict[str, Any], fixture_mode: bool) -> Any:
    return _request(
        session,
        "/v1/commands",
        method="POST",
        body={
            "commandId": f"parity:{uuid.uuid4().hex}",
            "action": action,
            "params": params,
            "fixtureMode": fixture_mode,
            "wait": {"timeoutMs": 10_000},
        },
    )


def _value_at_path(value: Any, path: str) -> Any:
    current = value
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def _condition(actual: Any, operator: str, expected: Any) -> bool:
    if operator == "equals":
        return actual == expected
    if operator == "notEquals":
        return actual != expected
    if operator == "contains":
        return expected in actual if isinstance(actual, (str, list, dict)) else False
    if operator == "exists":
        return actual is not None
    if operator == "gt":
        return actual is not None and actual > expected
    if operator == "gte":
        return actual is not None and actual >= expected
    if operator == "lt":
        return actual is not None and actual < expected
    if operator == "lte":
        return actual is not None and actual <= expected
    if operator == "in":
        return isinstance(expected, list) and actual in expected
    return False


def _fixture_digests(manifest_path: Path) -> dict[str, str]:
    root = manifest_path.parent / "fixtures"
    return {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        for name in json.loads(manifest_path.read_text(encoding="utf-8"))["fixtureFiles"]
    }


def run_state(
    *, original_root: Path, manifest_path: Path, state_id: str, output_root: Path, session_file: Path
) -> dict[str, Any]:
    manifest = load_and_validate_manifest(manifest_path)
    state = next((item for item in manifest["states"] if item["id"] == state_id), None)
    if state is None:
        raise OriginalDriverError(f"unknown state id: {state_id}")
    session = json.loads(session_file.read_text(encoding="utf-8"))
    if session.get("host") != "127.0.0.1" or not isinstance(session.get("token"), str):
        raise OriginalDriverError("invalid local session file")

    initial_state = _request(session, "/v1/state")
    renderer = str((initial_state.get("display") or {}).get("renderer", ""))
    if renderer != "CPU-Software":
        raise OriginalDriverError(
            "original capture session must start with E5CM_RENDER_BACKEND=software"
        )
    _command(
        session,
        "display.set",
        {"width": 1920, "height": 1080, "fullscreen": False},
        False,
    )
    driver = state["original"]
    _command(
        session,
        "scene.goto",
        {"scene": driver["scene"], "fixture": driver["fixture"], "transition": False},
        True,
    )
    for item in driver["actions"]:
        _command(
            session,
            "scene.action",
            {"name": item["name"], "params": item.get("params", {})},
            bool(item.get("fixtureMode", False)),
        )

    wait = state["wait"]
    stable_required = int(state["stableFrames"])
    stable_count = 0
    last_fingerprint = ""
    last_frame = -1
    raw_state: dict[str, Any] = {}
    exported: dict[str, Any] = {}
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline:
        raw_state = _request(session, "/v1/state")
        exported = canonical_state(raw_state, state_id)
        frame = int((raw_state.get("runtime") or {}).get("frame", last_frame + 1))
        stability_paths = state.get("stabilityPaths") or [wait["path"]]
        fingerprint = json.dumps(
            {str(path): _value_at_path(exported, str(path)) for path in stability_paths},
            ensure_ascii=False,
            sort_keys=True,
        )
        matched = _condition(_value_at_path(exported, wait["path"]), wait["operator"], wait.get("expected"))
        if matched and frame != last_frame:
            stable_count = stable_count + 1 if fingerprint == last_fingerprint else 1
            last_fingerprint = fingerprint
            last_frame = frame
        elif not matched:
            stable_count = 0
        if stable_count >= stable_required:
            break
        time.sleep(0.01)
    if stable_count < stable_required:
        raise OriginalDriverError(f"state did not become stable: {state_id}")

    capture = _request(session, "/v1/captures", method="POST", body={"name": state_id})
    if [capture.get("width"), capture.get("height")] != [1920, 1080]:
        raise OriginalDriverError(f"capture is not 1920x1080: {capture}")
    artifact = original_root / "userdata" / "cache" / "ai-test" / "artifacts" / capture["path"]
    if not artifact.is_file() or Image.open(artifact).size != (1920, 1080):
        raise OriginalDriverError("capture artifact is missing or has invalid PNG dimensions")

    output_root = output_root.resolve()
    output_dir = (output_root / state_id).resolve()
    if output_root not in output_dir.parents:
        raise OriginalDriverError("output directory escapes output root")
    output_dir.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(artifact, output_dir / "frame.png")
    fixture_digests = _fixture_digests(manifest_path)
    exported["fixtureDigests"] = fixture_digests
    (output_dir / "state.json").write_text(
        json.dumps({"canonical": exported, "raw": raw_state}, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (output_dir / "capture.json").write_text(
        json.dumps(capture, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    try:
        commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=original_root, text=True, encoding="utf-8"
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "unknown"
    metadata = {
        "stateId": state_id,
        "sourceProject": "E5CM-CG",
        "sourceCommit": commit,
        "width": 1920,
        "height": 1080,
        "sha256": hashlib.sha256((output_dir / "frame.png").read_bytes()).hexdigest(),
        "scene": driver["scene"],
        "fixture": driver["fixture"],
        "fixtureDigests": fixture_digests,
        "frame": int((raw_state.get("runtime") or {}).get("frame", 0)),
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "renderer": str((raw_state.get("display") or {}).get("renderer", "")),
        "fullscreen": bool((raw_state.get("display") or {}).get("fullscreen", False)),
        "animation": state["context"].get("animation"),
    }
    (output_dir / "metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    report = {
        "stateId": state_id,
        "status": "passed",
        "stableFrames": stable_count,
        "wait": wait,
        "captureSha256": metadata["sha256"],
    }
    (output_dir / "run-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Capture one original E5CM state through the AI interface")
    parser.add_argument("--original-root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--state-id", required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--session-file", type=Path)
    args = parser.parse_args()
    session_file = args.session_file or args.original_root / "userdata" / "cache" / "ai-test" / "session.json"
    report = run_state(
        original_root=args.original_root,
        manifest_path=args.manifest,
        state_id=args.state_id,
        output_root=args.output_root,
        session_file=session_file,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
