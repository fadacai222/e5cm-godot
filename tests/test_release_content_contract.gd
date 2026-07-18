extends SceneTree

var _failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _native_song_path(value: String) -> String:
	var normalized := value.replace("\\", "/")
	if normalized.begins_with("res://songs/"):
		return ProjectSettings.globalize_path(normalized)
	return normalized


func _count_song_folders() -> int:
	var total := 0
	var root_dir := DirAccess.open("res://songs")
	if root_dir == null:
		return 0
	for top in root_dir.get_directories():
		var top_dir := DirAccess.open("res://songs".path_join(top))
		if top_dir == null:
			continue
		for sub in top_dir.get_directories():
			var sub_dir := DirAccess.open("res://songs".path_join(top).path_join(sub))
			if sub_dir != null:
				total += sub_dir.get_directories().size()
	return total


func _has_import_sidecar(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	for filename in directory.get_files():
		if filename.ends_with(".import"):
			return true
	for child in directory.get_directories():
		if _has_import_sidecar(path.path_join(child)):
			return true
	return false


func _initialize() -> void:
	var raw := FileAccess.get_file_as_string("res://assets/e5cm_runtime/song_index.json")
	var index = JSON.parse_string(raw)
	_check(index is Dictionary, "精选发行索引可解析")
	if not index is Dictionary:
		quit(_failures)
		return

	var songs_by_key: Dictionary = index.get("songsByKey", {})
	_check(int(index.get("songVariantCount", 0)) == 44, "发行索引只包含 44 个精选谱面")
	_check(songs_by_key.size() == 11, "发行版只显示 11 个真实可玩模式")
	_check(not songs_by_key.has("竞速/情侣") and not songs_by_key.has("花式/情侣"),
		"源曲库中的空情侣占位模式不会出现在发行版")

	var missing: Array[String] = []
	for key in songs_by_key:
		var entries: Array = songs_by_key[key]
		var folders := {}
		for raw_entry in entries:
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			folders[str(entry.get("folder", ""))] = true
			for field in ["sm", "mp3", "cover"]:
				var path := str(entry.get(field, ""))
				if path.is_empty() or not FileAccess.file_exists(_native_song_path(path)):
					missing.append("%s %s=%s" % [key, field, path])
		_check(folders.size() >= 1 and folders.size() <= 4,
			"%s 最多保留 4 首歌" % key, str(folders.size()))

	_check(missing.is_empty(), "精选谱面、音频和封面全部存在", str(missing.slice(0, 8)))
	_check(_count_song_folders() == 44, "项目根 songs 只保留 44 个精选歌曲文件夹",
		str(_count_song_folders()))
	_check(not _has_import_sidecar("res://songs"), "精选曲库不携带无用 .import 边车")
	_check(FileAccess.file_exists("res://release/E5CM/E5CM.exe")
		and FileAccess.file_exists("res://release/E5CM/E5CM.pck")
		and FileAccess.file_exists("res://release/E5CM-Setup-0.9.0.exe"),
		"便携版 EXE/PCK 与安装包均已生成")

	print("ALL RELEASE CONTENT CONTRACT TESTS PASSED" if _failures == 0 else
		"%d RELEASE CONTENT CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
