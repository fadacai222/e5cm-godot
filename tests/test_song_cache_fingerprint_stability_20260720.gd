extends SceneTree
## 启动曲库缓存回归：已有持久化缓存时不得再次遍历全部歌曲文件夹。

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _write_song(folder_path: String, title: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder_path))
	var chart := FileAccess.open(folder_path.path_join("chart.json"), FileAccess.WRITE)
	chart.store_string(JSON.stringify({
		"title": title,
		"artist": "启动缓存测试",
		"bpms": [{"lineNo": 0, "bpmVal": 128.0}],
		"boards": [{"lineDatas": [{"lineNo": 96, "arrows": [
			{"aType": 1, "player": 1, "length": 0},
		]}]}],
	}))
	chart.close()


func _remove_song(folder_path: String) -> void:
	var chart_path := folder_path.path_join("chart.json")
	if FileAccess.file_exists(chart_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(chart_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder_path))


func _initialize() -> void:
	var token := str(Time.get_ticks_usec())
	var root_path := "user://qa_startup_song_cache_%s" % token
	var submode := "community_%s" % token
	var base := root_path.path_join("diy").path_join(submode)
	var folders := [base.path_join("A#3"), base.path_join("B#4"), base.path_join("C#5")]
	for i in folders.size():
		_write_song(str(folders[i]), "启动缓存歌曲 %d" % i)

	var library = load("res://autoload/song_library.gd").new()
	library._ready()
	library.use_static_index = false
	library.songs_root = root_path
	library.invalidate_cache("DIY", submode)
	library.reset_scan_song_dir_calls_for_test()
	library.reset_song_folder_signature_calls_for_test()

	var first: Array = library.get_songs("DIY", submode)
	_check(first.size() == 3 and library.scan_song_dir_calls_for_test() == 3,
		"首次载入正常建立三首歌曲缓存",
		"songs=%d scans=%d" % [first.size(), library.scan_song_dir_calls_for_test()])

	library.clear_memory_cache_for_test()
	library.reset_scan_song_dir_calls_for_test()
	library.reset_song_folder_signature_calls_for_test()
	var restored: Array = await library.get_songs_async("DIY", submode)
	_check(restored.size() == 3, "二次启动从持久化缓存恢复完整曲库")
	_check(library.scan_song_dir_calls_for_test() == 0,
		"二次启动不重新解析任何歌曲文件夹",
		"scans=%d" % library.scan_song_dir_calls_for_test())
	_check(library.song_folder_signature_calls_for_test() == 0,
		"二次启动不再枚举歌曲目录计算文件签名",
		"signature_checks=%d" % library.song_folder_signature_calls_for_test())

	# 新增歌曲目录会改变子模式目录时间，仍应自动失效并做增量扫描。
	OS.delay_msec(1100)
	var folder_d := base.path_join("D#6")
	_write_song(folder_d, "新增歌曲 D")
	library.clear_memory_cache_for_test()
	library.reset_scan_song_dir_calls_for_test()
	library.reset_song_folder_signature_calls_for_test()
	var changed: Array = await library.get_songs_async("DIY", submode)
	_check(changed.size() == 4 and library.scan_song_dir_calls_for_test() == 1,
		"新增歌曲目录后自动增量更新且只解析新增项",
		"songs=%d scans=%d" % [changed.size(), library.scan_song_dir_calls_for_test()])

	library.invalidate_cache("DIY", submode)
	library.free()
	for folder in folders:
		_remove_song(str(folder))
	_remove_song(folder_d)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path.path_join("diy")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path))

	print("ALL STARTUP SONG CACHE TESTS PASSED" if _failures == 0 else
		"%d STARTUP SONG CACHE TEST(S) FAILED" % _failures)
	quit(_failures)
