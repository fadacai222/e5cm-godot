extends SceneTree
## 为导出包生成稳定曲库索引，避免运行时依赖 DirAccess 枚举导入资源。

const OUTPUT_PATH := "res://assets/e5cm_runtime/song_index.json"
const MODES := ["花式", "竞速", "DIY"]


func _initialize() -> void:
	var library = load("res://autoload/song_library.gd").new()
	library.use_static_index = false
	library._ready()
	var songs_by_key := {}
	var submodes_by_mode := {}
	var total_songs := 0

	for mode in MODES:
		var submodes: Array = library.list_submodes(mode)
		submodes_by_mode[mode] = submodes
		for submode_value in submodes:
			var submode := str(submode_value)
			var songs: Array = library.get_songs(mode, submode)
			songs_by_key[mode + "/" + submode] = songs
			total_songs += songs.size()

	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write song index: %s" % OUTPUT_PATH)
		library.free()
		quit(1)
		return
	output.store_string(JSON.stringify({
		"schemaVersion": 1,
		"generatedAtUnix": int(Time.get_unix_time_from_system()),
		"runtimeRoot": library.RUNTIME_ROOT,
		"submodesByMode": submodes_by_mode,
		"songsByKey": songs_by_key,
		"songVariantCount": total_songs,
	}))
	output.close()
	print("SONG_INDEX_MODES=%d SONG_VARIANTS=%d PATH=%s" % [
		MODES.size(), total_songs, OUTPUT_PATH])
	library.free()
	quit(0)
