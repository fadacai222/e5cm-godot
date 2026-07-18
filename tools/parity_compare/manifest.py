from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


EXPECTED_RESOLUTION = [1920, 1080]
REQUIRED_FIXTURES = {
    "profile.json",
    "settings.json",
    "favorites.json",
    "records.json",
    "match_state.json",
    "song_fixture.json",
}
REQUIRED_CONTEXT_FIELDS = {
    "players",
    "credit",
    "loginType",
    "profile",
    "nickname",
    "avatar",
    "majorMode",
    "subMode",
    "songRelativePath",
    "songSha256",
    "chartType",
    "level",
    "page",
    "selectedIndex",
    "favorite",
    "filter",
    "round",
    "result",
    "videoTimeSeconds",
    "animation",
}
STATE_ID_PATTERN = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")


class ManifestError(ValueError):
    pass


def _object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ManifestError(f"{path} must be an object")
    return value


def load_and_validate_manifest(path: Path | str) -> dict[str, Any]:
    manifest_path = Path(path)
    try:
        value = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read manifest: {error}") from error
    manifest = _object(value, "manifest")
    if manifest.get("schemaVersion") != 1:
        raise ManifestError("schemaVersion must be 1")
    if manifest.get("resolution") != EXPECTED_RESOLUTION:
        raise ManifestError("manifest resolution must be exactly 1920x1080")
    fixture_files = manifest.get("fixtureFiles")
    if not isinstance(fixture_files, list) or set(fixture_files) != REQUIRED_FIXTURES:
        raise ManifestError("fixtureFiles must list the six shared fixture types")
    fixture_dir = manifest_path.parent / "fixtures"
    missing_files = sorted(name for name in REQUIRED_FIXTURES if not (fixture_dir / name).is_file())
    if missing_files:
        raise ManifestError(f"missing fixture files: {', '.join(missing_files)}")

    states = manifest.get("states")
    if not isinstance(states, list) or not states:
        raise ManifestError("states must be a non-empty array")
    seen: set[str] = set()
    for index, raw_state in enumerate(states):
        state = _object(raw_state, f"states[{index}]")
        state_id = state.get("id")
        if not isinstance(state_id, str) or not STATE_ID_PATTERN.fullmatch(state_id):
            raise ManifestError(f"states[{index}].id is invalid")
        if state_id in seen:
            raise ManifestError(f"duplicate state id: {state_id}")
        seen.add(state_id)
        if state.get("resolution") != EXPECTED_RESOLUTION:
            raise ManifestError(f"{state_id}: resolution must be exactly 1920x1080")
        if state.get("capture") != state_id:
            raise ManifestError(f"{state_id}: capture must equal state id")
        stable_frames = state.get("stableFrames")
        if type(stable_frames) is not int or not 1 <= stable_frames <= 60:
            raise ManifestError(f"{state_id}: stableFrames must be 1..60")
        context = _object(state.get("context"), f"{state_id}.context")
        missing_context = sorted(REQUIRED_CONTEXT_FIELDS - set(context))
        if missing_context:
            raise ManifestError(f"{state_id}: missing context fields: {', '.join(missing_context)}")
        for side in ("original", "godot"):
            driver = _object(state.get(side), f"{state_id}.{side}")
            if not isinstance(driver.get("scene"), str) or not driver["scene"]:
                raise ManifestError(f"{state_id}.{side}.scene is required")
            if not isinstance(driver.get("fixture"), str) or not driver["fixture"]:
                raise ManifestError(f"{state_id}.{side}.fixture is required")
            actions = driver.get("actions")
            if not isinstance(actions, list):
                raise ManifestError(f"{state_id}.{side}.actions must be an array")
            for action_index, action in enumerate(actions):
                item = _object(action, f"{state_id}.{side}.actions[{action_index}]")
                if not isinstance(item.get("name"), str) or not isinstance(item.get("params", {}), dict):
                    raise ManifestError(f"{state_id}.{side}.actions[{action_index}] is invalid")
        wait = _object(state.get("wait"), f"{state_id}.wait")
        if not isinstance(wait.get("path"), str) or wait.get("operator") not in {
            "equals", "notEquals", "contains", "exists", "gt", "gte", "lt", "lte", "in"
        }:
            raise ManifestError(f"{state_id}.wait is invalid")
    return manifest
