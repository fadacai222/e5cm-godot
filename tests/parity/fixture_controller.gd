extends RefCounted
## 把六类共享 fixture 注入内存，并在退出时恢复运行态与 user:// 文件。

const USER_FILES := [
	"user://credits.cfg",
	"user://profile.json",
	"user://records.json",
	"user://favorites.json",
	"user://settings.cfg",
]
const FIXTURE_NAMES := [
	"profile.json",
	"settings.json",
	"favorites.json",
	"records.json",
	"match_state.json",
	"song_fixture.json",
]

var _file_snapshots := {}
var _runtime_snapshot := {}
var _active := false


func begin(context: Dictionary) -> Dictionary:
	if _active:
		push_error("parity fixtures are already active")
		return {}
	_active = true
	_snapshot_user_files()
	_runtime_snapshot = {
		"credits": GameState.credits,
		"persist_credits": GameState.persist_credits,
		"player_count": GameState.player_count,
		"big_mode": GameState.big_mode,
		"sub_mode": GameState.sub_mode,
		"profile": ProfileStore.profile.duplicate(true),
		"records": ProfileStore.records.duplicate(true),
		"favorites": ProfileStore.favorites.duplicate(true),
		"profile_persist": ProfileStore.persist_enabled,
		"settings_persist": SettingsStore.persist_enabled,
		"autoplay": SettingsStore.autoplay,
	}
	GameState.persist_credits = false
	ProfileStore.persist_enabled = false
	SettingsStore.persist_enabled = false

	var profile := _load_json("profile.json")
	var records := _load_json("records.json")
	var favorites := _load_json("favorites.json")
	var settings := _load_json("settings.json")
	ProfileStore.profile = profile.duplicate(true)
	ProfileStore.records = (records.get("items", {}) as Dictionary).duplicate(true)
	ProfileStore.favorites = (favorites.get("items", []) as Array).duplicate(true)
	SettingsStore.autoplay = bool(settings.get("autoplay", true))
	SettingsStore.scroll_speed = float(settings.get("scrollSpeed", 4.0))
	SettingsStore.chart_offset_ms = int(settings.get("chartOffsetMs", 0))
	SettingsStore.bgm_volume = int(settings.get("bgmVolume", 10))
	SettingsStore.muted = bool(settings.get("muted", false))
	SettingsStore.hit_sound = bool(settings.get("hitSound", true))
	SettingsStore.max_fps = int(settings.get("maxFps", 60))
	GameState.credits = int(context.get("credit", 0))
	GameState.player_count = clampi(int(context.get("players", 1)), 1, 2)
	GameState.big_mode = str(context.get("majorMode", "") or "")
	GameState.sub_mode = str(context.get("subMode", "") or "")
	return fixture_digests()


func restore() -> void:
	if not _active:
		return
	_active = false
	if not _runtime_snapshot.is_empty():
		GameState.credits = int(_runtime_snapshot.get("credits", 0))
		GameState.persist_credits = bool(_runtime_snapshot.get("persist_credits", true))
		GameState.player_count = int(_runtime_snapshot.get("player_count", 1))
		GameState.big_mode = str(_runtime_snapshot.get("big_mode", ""))
		GameState.sub_mode = str(_runtime_snapshot.get("sub_mode", ""))
		ProfileStore.profile = (_runtime_snapshot.get("profile", {}) as Dictionary).duplicate(true)
		ProfileStore.records = (_runtime_snapshot.get("records", {}) as Dictionary).duplicate(true)
		ProfileStore.favorites = (_runtime_snapshot.get("favorites", []) as Array).duplicate(true)
		ProfileStore.persist_enabled = bool(_runtime_snapshot.get("profile_persist", true))
		SettingsStore.persist_enabled = bool(_runtime_snapshot.get("settings_persist", true))
		SettingsStore.autoplay = bool(_runtime_snapshot.get("autoplay", false))
		_runtime_snapshot.clear()
	_restore_user_files()


func fixture_digests() -> Dictionary:
	var result := {}
	for name in FIXTURE_NAMES:
		result[name] = FileAccess.get_sha256("res://parity/fixtures/%s" % name)
	return result


func _load_json(name: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://parity/fixtures/%s" % name))
	return parsed if parsed is Dictionary else {}


func _snapshot_user_files() -> void:
	_file_snapshots.clear()
	for path in USER_FILES:
		_file_snapshots[path] = {
			"exists": FileAccess.file_exists(path),
			"bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray(),
		}


func _restore_user_files() -> void:
	for path in USER_FILES:
		var snapshot: Dictionary = _file_snapshots.get(path, {})
		if bool(snapshot.get("exists", false)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_buffer(snapshot.get("bytes", PackedByteArray()))
				file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_file_snapshots.clear()
