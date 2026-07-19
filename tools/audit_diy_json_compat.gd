extends SceneTree
## 全量 DIY JSON 兼容审计。只读，不修改歌曲文件。

const SmParserScript := preload("res://core/sm_parser.gd")

var _files: Array[String] = []
var _patch_counts := {}
var _parse_errors := 0
var _non_finite := 0
var _hour_long := 0
var _event_non_finite := 0


func _collect_json_files(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var child := path.path_join(name)
			if dir.current_is_dir():
				_collect_json_files(child)
			elif name.to_lower().ends_with(".json"):
				_files.append(child)
		name = dir.get_next()
	dir.list_dir_end()


func _initialize() -> void:
	var root_path := ProjectSettings.globalize_path("res://songs/diy")
	_collect_json_files(root_path)
	for path in _files:
		var result: Dictionary = SmParserScript.build_json_events(path)
		var error := str(result.get("error", ""))
		if not error.is_empty() and error != "JSON 没有可玩的脚键音符":
			_parse_errors += 1
		var duration := float(result.get("duration", NAN))
		if not is_finite(duration):
			_non_finite += 1
		elif duration > 3600.0:
			_hour_long += 1
		for group in [result.get("events", []), result.get("hand_events", []),
				result.get("fake_events", [])]:
			for event in group:
				if not is_finite(float(event.get("start_sec", NAN))) \
						or not is_finite(float(event.get("end_sec", NAN))):
					_event_non_finite += 1
		for patch in result.get("compat_patches", []):
			_patch_counts[patch] = int(_patch_counts.get(patch, 0)) + 1
	print("DIY_JSON_AUDIT files=%d parse_errors=%d non_finite_duration=%d hour_long=%d non_finite_events=%d" % [
		_files.size(), _parse_errors, _non_finite, _hour_long, _event_non_finite])
	var patch_names: Array = _patch_counts.keys()
	patch_names.sort()
	for patch in patch_names:
		print("  PATCH %s=%d" % [patch, int(_patch_counts[patch])])
	quit(1 if _parse_errors > 0 or _non_finite > 0 or _hour_long > 0 \
		or _event_non_finite > 0 else 0)
