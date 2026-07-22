extends SceneTree
## 开发全量索引与发行精选侧车索引必须隔离；未执行打包时只验证构建契约。

const DEV_INDEX := "res://assets/e5cm_runtime/song_index.json"
const RELEASE_ROOT := "res://release/E5CM"
const RELEASE_INDEX := RELEASE_ROOT + "/release-song-index.json"

var _failures := 0


func _check(condition: bool, label: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _release_song_path(value: String) -> String:
	var normalized := value.replace("\\", "/")
	if normalized.begins_with("res://songs/"):
		return RELEASE_ROOT.path_join("songs").path_join(normalized.trim_prefix("res://songs/"))
	return normalized


func _count_song_folders(root_path: String) -> int:
	var total := 0
	var root_dir := DirAccess.open(root_path)
	if root_dir == null:
		return 0
	for top in root_dir.get_directories():
		var top_path := root_path.path_join(top)
		var top_dir := DirAccess.open(top_path)
		if top_dir == null:
			continue
		for sub in top_dir.get_directories():
			var sub_dir := DirAccess.open(top_path.path_join(sub))
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


func _check_runtime_sidecar_mapping(release_songs: String) -> void:
	var loader := root.get_node_or_null("AssetLoader")
	if loader == null:
		_check(false, "发行侧车运行时映射测试可访问 AssetLoader")
		return
	var previous_root := str(loader.call("songs_root"))
	var previous_override := OS.get_environment("E5CM_RELEASE_INDEX_PATH")
	var release_songs_native := ProjectSettings.globalize_path(release_songs).replace("\\", "/")
	OS.set_environment("E5CM_RELEASE_INDEX_PATH", ProjectSettings.globalize_path(RELEASE_INDEX))
	loader.call("set_songs_root_for_test", release_songs_native)
	var library: Node = load("res://autoload/song_library.gd").new()
	root.add_child(library)
	await process_frame
	# _ready() 会从全局 AssetLoader 同步一次根路径；测试随后显式锁定发行根。
	loader.call("set_songs_root_for_test", release_songs_native)
	library.set("songs_root", release_songs_native)
	library.call("_ensure_static_index")
	var static_map: Dictionary = library.get("_static_songs")
	var static_entries: Array = static_map.get("竞速/club", [])
	var folder_match := bool(library.call("_static_index_matches_installed_folders",
		"竞速", "club", static_entries))
	var cache_before: Dictionary = (library.get("_cache") as Dictionary).duplicate()
	var runtime_songs: Array = library.call("get_songs", "竞速", "club")
	var mapped := runtime_songs.size() >= 1 and runtime_songs.size() <= 4
	for raw_song in runtime_songs:
		if not raw_song is Dictionary:
			mapped = false
			continue
		for field in ["sm", "mp3", "cover"]:
			var path := str((raw_song as Dictionary).get(field, "")).replace("\\", "/")
			mapped = mapped and path.begins_with(release_songs_native + "/") \
				and FileAccess.file_exists(path)
	var mapping_detail := "count=%d root=%s index=%s release_sample=%s keys=%s" % [
		runtime_songs.size(), release_songs_native,
		str(library.get("_static_index_native_path")),
		str(library.get("_static_index_is_release_sample")),
		str((library.get("_static_songs") as Dictionary).keys())]
	mapping_detail += " static_entries=%d folder_match=%s songs_root=%s cache_before=%s" % [
		static_entries.size(), str(folder_match), str(library.get("songs_root")),
		str(cache_before.keys())]
	_check(mapped, "SongLibrary 实际优先读取发行侧车并映射到精选 songs", mapping_detail)
	root.remove_child(library)
	library.free()
	loader.call("set_songs_root_for_test", previous_root)
	OS.set_environment("E5CM_RELEASE_INDEX_PATH", previous_override)


func _initialize() -> void:
	var development = JSON.parse_string(FileAccess.get_file_as_string(DEV_INDEX))
	_check(development is Dictionary, "开发完整索引可解析")
	if development is Dictionary:
		_check(int(development.get("songVariantCount", 0)) > 1000,
			"开发索引包含全量谱面", str(development.get("songVariantCount", 0)))
		_check(str(development.get("releaseVersion", "")).is_empty(),
			"开发索引不是发行抽样索引")

	var builder_source := FileAccess.get_file_as_string("res://tools/release/build_release.py")
	_check(builder_source.contains("PORTABLE_INDEX")
			and not builder_source.contains("shutil.copy2(SAMPLE_INDEX, INDEX_PATH)"),
		"打包流程只写发行侧车索引，不覆盖开发索引")

	if not FileAccess.file_exists(RELEASE_INDEX):
		print("  SKIP  尚未生成本次发行侧车索引；发行文件检查由打包烟雾测试覆盖")
		_finish()
		return

	var index = JSON.parse_string(FileAccess.get_file_as_string(RELEASE_INDEX))
	_check(index is Dictionary, "精选发行侧车索引可解析")
	if not index is Dictionary:
		_finish()
		return

	var songs_by_key: Dictionary = index.get("songsByKey", {})
	_check(str(index.get("releaseVersion", "")) == "godot-2.0.3", "发行索引版本与安装包一致")
	_check(int(index.get("songVariantCount", 0)) > 0 \
			and int(index.get("songVariantCount", 0)) <= 44,
		"发行索引最多包含 44 个精选谱面", str(index.get("songVariantCount", 0)))
	_check(songs_by_key.size() == 11, "发行版只显示 11 个真实可玩模式")
	_check(not songs_by_key.has("竞速/情侣") and not songs_by_key.has("花式/情侣"),
		"空情侣占位模式不会出现在发行版")

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
				if path.is_empty() or not FileAccess.file_exists(_release_song_path(path)):
					missing.append("%s %s=%s" % [key, field, path])
		_check(folders.size() >= 1 and folders.size() <= 4,
			"%s 最多保留 4 首歌" % key, str(folders.size()))

	var release_songs := RELEASE_ROOT.path_join("songs")
	_check(missing.is_empty(), "精选谱面、音频和封面全部存在", str(missing.slice(0, 8)))
	_check(_count_song_folders(release_songs) <= 44,
		"发行目录最多包含 44 个精选歌曲文件夹", str(_count_song_folders(release_songs)))
	_check(not _has_import_sidecar(release_songs), "精选曲库不携带无用 .import 边车")
	await _check_runtime_sidecar_mapping(release_songs)
	var executable_exists := FileAccess.file_exists(RELEASE_ROOT + "/E5CM.exe")
	var pck_exists := FileAccess.file_exists(RELEASE_ROOT + "/E5CM.pck")
	var installer_exists := FileAccess.file_exists("res://release/E5CM-Setup-godot-2.0.3.exe")
	if executable_exists or pck_exists:
		_check(executable_exists and pck_exists and installer_exists,
			"进入最终发行阶段后 EXE/PCK 与安装包必须完整")
	else:
		print("  SKIP  当前仅完成发行准备，最终产物由导出/安装烟雾测试覆盖")
	_finish()


func _finish() -> void:
	print("ALL RELEASE CONTENT CONTRACT TESTS PASSED" if _failures == 0 else
		"%d RELEASE CONTENT CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
