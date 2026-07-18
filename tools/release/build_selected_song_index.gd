extends SceneTree
## 根据精选发行曲库重新生成静态索引，禁止依赖旧全量索引。

const MODES := ["花式", "竞速", "DIY"]
const PATH_FIELDS := ["sm", "mp3", "cover", "video"]


func _release_path(path: String, songs_root: String) -> String:
	var normalized := path.replace("\\", "/")
	var normalized_root := songs_root.replace("\\", "/").trim_suffix("/")
	if normalized == normalized_root:
		return "res://songs"
	if normalized.begins_with(normalized_root + "/"):
		return "res://songs/" + normalized.substr(normalized_root.length() + 1)
	if normalized.begins_with("res://songs/"):
		return normalized
	return normalized


func _initialize() -> void:
	var songs_root := OS.get_environment("E5CM_RELEASE_SONGS_ROOT").strip_edges()
	var output_path := OS.get_environment("E5CM_RELEASE_INDEX_PATH").strip_edges()
	var release_version := OS.get_environment("E5CM_RELEASE_VERSION").strip_edges()
	if songs_root.is_empty() or output_path.is_empty() or release_version.is_empty():
		push_error("E5CM_RELEASE_SONGS_ROOT / E5CM_RELEASE_INDEX_PATH / E5CM_RELEASE_VERSION 未设置")
		quit(2)
		return
	if DirAccess.open(songs_root) == null:
		push_error("精选曲库目录不存在：%s" % songs_root)
		quit(3)
		return

	var library = load("res://autoload/song_library.gd").new()
	library.use_static_index = false
	library.songs_root = songs_root.replace("\\", "/").trim_suffix("/")
	var songs_by_key := {}
	var submodes_by_mode := {}
	var total_variants := 0

	for mode in MODES:
		var submodes: Array = library.list_submodes(mode)
		submodes_by_mode[mode] = submodes
		for submode_value in submodes:
			var submode := str(submode_value)
			var raw_songs: Array = library.get_songs(mode, submode)
			var release_songs: Array = []
			for raw_song in raw_songs:
				if not raw_song is Dictionary:
					continue
				var song: Dictionary = raw_song.duplicate(true)
				for field in PATH_FIELDS:
					if song.has(field):
						song[field] = _release_path(str(song[field]), library.songs_root)
				release_songs.append(song)
			songs_by_key[mode + "/" + submode] = release_songs
			total_variants += release_songs.size()

	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("无法写入发行索引：%s" % output_path)
		library.free()
		quit(4)
		return
	output.store_string(JSON.stringify({
		"schemaVersion": 1,
		"generatedAtUnix": int(Time.get_unix_time_from_system()),
		"runtimeRoot": "res://songs",
		"releaseVersion": release_version,
		"releaseSeed": "20260718-e5cm-release",
		"submodesByMode": submodes_by_mode,
		"songsByKey": songs_by_key,
		"songVariantCount": total_variants,
	}))
	output.close()
	print("RELEASE_SONG_INDEX_MODES=%d VARIANTS=%d PATH=%s" % [
		MODES.size(), total_variants, output_path])
	library.free()
	quit(0)
