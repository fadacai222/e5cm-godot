extends SceneTree
## DIY/社区曲库增量缓存：目录变化时只解析新增/变更歌曲文件夹。

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _write_song(folder_path: String, title: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder_path))
	var chart_path := folder_path.path_join("chart.json")
	var file := FileAccess.open(chart_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"title": title,
		"artist": "增量测试歌手",
		"bpms": [{"lineNo": 0, "bpmVal": 128.0}],
		"boards": [{"lineDatas": [{"lineNo": 96, "arrows": [
			{"aType": 1, "player": 1, "length": 0},
		]}]}],
	}))
	file.close()


func _remove_song(folder_path: String) -> void:
	var chart_path := folder_path.path_join("chart.json")
	if FileAccess.file_exists(chart_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(chart_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder_path))


func _initialize() -> void:
	var token := str(Time.get_ticks_usec())
	var root_path := "user://qa_incremental_songs_%s" % token
	var submode := "community_%s" % token
	var base := root_path.path_join("diy").path_join(submode)
	var folder_a := base.path_join("A#3")
	var folder_b := base.path_join("B#4")
	var folder_c := base.path_join("C#5")
	_write_song(folder_a, "歌曲 A")
	_write_song(folder_b, "歌曲 B")

	var library = load("res://autoload/song_library.gd").new()
	library._ready()
	library.use_static_index = false
	library.songs_root = root_path
	library.invalidate_cache("DIY", submode)
	library.reset_scan_song_dir_calls_for_test()

	var first: Array = library.get_songs("DIY", submode)
	_check(first.size() == 2 and library.scan_song_dir_calls_for_test() == 2,
		"首次建立缓存解析两个歌曲文件夹",
		"songs=%d scans=%d" % [first.size(), library.scan_song_dir_calls_for_test()])

	library.clear_memory_cache_for_test()
	library.reset_scan_song_dir_calls_for_test()
	var cached: Array = library.get_songs("DIY", submode)
	_check(cached.size() == 2 and library.scan_song_dir_calls_for_test() == 0,
		"目录未变化时直接读取磁盘侧车，不解析任何歌曲文件夹",
		"songs=%d scans=%d" % [cached.size(), library.scan_song_dir_calls_for_test()])

	# FileAccess 目录修改时间为秒级；跨一秒后新增目录，确保缓存失效条件可验证。
	OS.delay_msec(1100)
	_write_song(folder_c, "歌曲 C")
	library.clear_memory_cache_for_test()
	library.reset_scan_song_dir_calls_for_test()
	var added: Array = library.get_songs("DIY", submode)
	_check(added.size() == 3 and library.scan_song_dir_calls_for_test() == 1,
		"新增歌曲时只解析新增文件夹，其余歌曲复用缓存",
		"songs=%d scans=%d" % [added.size(), library.scan_song_dir_calls_for_test()])

	OS.delay_msec(1100)
	_remove_song(folder_b)
	library.clear_memory_cache_for_test()
	library.reset_scan_song_dir_calls_for_test()
	var removed: Array = library.get_songs("DIY", submode)
	_check(removed.size() == 2 and library.scan_song_dir_calls_for_test() == 0,
		"删除歌曲时移除旧条目，未变化文件夹无需重新解析",
		"songs=%d scans=%d" % [removed.size(), library.scan_song_dir_calls_for_test()])

	library.invalidate_cache("DIY", submode)
	library.free()
	_remove_song(folder_a)
	_remove_song(folder_c)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path.path_join("diy")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path))

	print("ALL INCREMENTAL SONG CACHE TESTS PASSED" if _failures == 0 else
		"%d INCREMENTAL SONG CACHE TEST(S) FAILED" % _failures)
	quit(_failures)
