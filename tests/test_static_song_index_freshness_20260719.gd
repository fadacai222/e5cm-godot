extends SceneTree
## 回归：发行包“每模式 4 首”的抽样索引不得遮住后来放回 songs 的完整曲库。

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _write_json_song(root_path: String, folder: String, title: String) -> void:
	var song_dir := root_path.path_join("花式").path_join("学习").path_join(folder)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(song_dir))
	var output := FileAccess.open(song_dir.path_join(title + ".json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({
		"title": title,
		"bpm": 128.0,
		"boards": [{"lineDatas": []}],
	}))
	output.close()


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _configure_release_sample(library: Node, songs_root: String) -> void:
	library.songs_root = songs_root
	library.use_static_index = true
	library.set("_static_index_loaded", true)
	library.set("_static_index_is_release_sample", true)
	library.set("_static_songs", {
		"花式/学习": [{
			"folder": "Alpha#1",
			"name": "抽样索引中的唯一歌曲",
			"sm": songs_root.path_join("花式/学习/Alpha#1/Alpha.json"),
			"sm_key": "songs/花式/学习/Alpha#1/Alpha.json",
		}],
	})


func _initialize() -> void:
	var fixture_root := "user://qa_static_sample_freshness_%s" % Time.get_ticks_usec()
	_write_json_song(fixture_root, "Alpha#1", "Alpha")
	_write_json_song(fixture_root, "Beta#2", "Beta")

	var sync_library: Node = load("res://autoload/song_library.gd").new()
	sync_library._ready()
	_configure_release_sample(sync_library, fixture_root)
	var sync_songs: Array = sync_library.get_songs("花式", "学习")
	_check(sync_songs.size() == 2,
		"同步加载发现完整 songs 比发行抽样索引更多时改扫真实目录",
		"songs=%d" % sync_songs.size())
	sync_library.free()

	var async_library: Node = load("res://autoload/song_library.gd").new()
	root.add_child(async_library)
	await process_frame
	_configure_release_sample(async_library, fixture_root)
	var async_songs: Array = await async_library.get_songs_async("花式", "学习")
	_check(async_songs.size() == 2,
		"渐进加载同样不会被 4 首发行抽样索引截断",
		"songs=%d" % async_songs.size())
	root.remove_child(async_library)
	async_library.free()

	var release_fixture_root := fixture_root.path_join("release_only")
	_write_json_song(release_fixture_root, "Alpha#1", "Alpha")
	var release_library: Node = load("res://autoload/song_library.gd").new()
	release_library._ready()
	_configure_release_sample(release_library, release_fixture_root)
	release_library.reset_scan_song_dir_calls_for_test()
	var release_songs: Array = release_library.get_songs("花式", "学习")
	_check(release_songs.size() == 1 \
			and str((release_songs[0] as Dictionary).get("name", "")) == "抽样索引中的唯一歌曲" \
			and release_library.scan_song_dir_calls_for_test() == 0,
		"安装目录与发行抽样索引一致时仍直接使用静态索引",
		"songs=%d scans=%d" % [release_songs.size(), release_library.scan_song_dir_calls_for_test()])
	release_library.free()

	var replacement_fixture_root := fixture_root.path_join("release_replaced")
	_write_json_song(replacement_fixture_root, "Beta#2", "Beta")
	var replacement_library: Node = load("res://autoload/song_library.gd").new()
	replacement_library._ready()
	_configure_release_sample(replacement_library, replacement_fixture_root)
	var replacement_songs: Array = replacement_library.get_songs("花式", "学习")
	_check(replacement_songs.size() == 1 \
			and str((replacement_songs[0] as Dictionary).get("name", "")) == "Beta",
		"歌曲目录数量相同但名称不同也必须扫描真实 songs",
		"songs=%s" % replacement_songs)
	replacement_library.free()

	var hot_fixture_root := fixture_root.path_join("release_hot_add")
	_write_json_song(hot_fixture_root, "Alpha#1", "Alpha")
	var hot_library: Node = load("res://autoload/song_library.gd").new()
	hot_library._ready()
	_configure_release_sample(hot_library, hot_fixture_root)
	var hot_before: Array = hot_library.get_songs("花式", "学习")
	OS.delay_msec(1100)
	_write_json_song(hot_fixture_root, "Beta#2", "Beta")
	var hot_after: Array = hot_library.get_songs("花式", "学习")
	_check(hot_before.size() == 1 and hot_after.size() == 2,
		"游戏运行中拖入新歌曲后内存缓存自动失效",
		"before=%d after=%d" % [hot_before.size(), hot_after.size()])
	hot_library.free()

	var sidecar_path := fixture_root.path_join("release-song-index.json")
	var sidecar_file := FileAccess.open(sidecar_path, FileAccess.WRITE)
	sidecar_file.store_string(JSON.stringify({
		"schemaVersion": 1,
		"releaseVersion": "godot-2.0.3",
		"releaseSeed": "qa",
		"submodesByMode": {"花式": ["学习"]},
		"songsByKey": {"花式/学习": [{
			"folder": "Alpha#1", "name": "侧车精选歌曲",
			"sm": "res://songs/花式/学习/Alpha#1/Alpha.json",
			"sm_key": "songs/花式/学习/Alpha#1/Alpha.json",
		}]},
		"songVariantCount": 1,
	}))
	sidecar_file.close()
	var previous_override := OS.get_environment("E5CM_RELEASE_INDEX_PATH")
	OS.set_environment("E5CM_RELEASE_INDEX_PATH", ProjectSettings.globalize_path(sidecar_path))
	var sidecar_library: Node = load("res://autoload/song_library.gd").new()
	sidecar_library._ready()
	sidecar_library.songs_root = release_fixture_root
	var sidecar_songs: Array = sidecar_library.get_songs("花式", "学习")
	_check(sidecar_songs.size() == 1 \
			and str((sidecar_songs[0] as Dictionary).get("name", "")) == "侧车精选歌曲",
		"发行版优先读取 EXE 同目录侧车索引且不改写开发索引",
		"songs=%s index=%s" % [sidecar_songs, sidecar_library.get("_static_index_native_path")])
	sidecar_library.free()
	OS.set_environment("E5CM_RELEASE_INDEX_PATH", previous_override)

	var missing_sidecar_root := fixture_root.path_join("release_missing_sidecar")
	_write_json_song(missing_sidecar_root, "OnlyInstalled#1", "Only Installed")
	var missing_sidecar_path := fixture_root.path_join("does-not-exist-release-song-index.json")
	OS.set_environment("E5CM_RELEASE_INDEX_PATH", ProjectSettings.globalize_path(missing_sidecar_path))
	var missing_sidecar_library: Node = load("res://autoload/song_library.gd").new()
	missing_sidecar_library._ready()
	missing_sidecar_library.songs_root = missing_sidecar_root
	missing_sidecar_library.set("_force_standalone_for_test", true)
	missing_sidecar_library.reset_scan_song_dir_calls_for_test()
	var missing_sidecar_songs: Array = missing_sidecar_library.get_songs("花式", "学习")
	_check(missing_sidecar_songs.size() == 1 \
			and str((missing_sidecar_songs[0] as Dictionary).get("name", "")) == "Only Installed" \
			and str(missing_sidecar_library.get("_static_index_native_path")).is_empty() \
			and missing_sidecar_library.scan_song_dir_calls_for_test() == 1,
		"正式版侧车丢失时扫描实际 songs 而不是回退开发机完整索引",
		"songs=%d index=%s scans=%d" % [missing_sidecar_songs.size(),
			missing_sidecar_library.get("_static_index_native_path"),
			missing_sidecar_library.scan_song_dir_calls_for_test()])
	missing_sidecar_library.free()
	OS.set_environment("E5CM_RELEASE_INDEX_PATH", previous_override)

	var project_library: Node = load("res://autoload/song_library.gd").new()
	project_library._ready()
	var project_learning_songs: Array = project_library.get_songs("花式", "学习")
	_check(project_learning_songs.size() > 4,
		"项目完整 songs/花式/学习 不再被 4 首发行索引截断",
		"songs=%d" % project_learning_songs.size())
	project_library.free()

	_remove_tree(fixture_root)
	print("ALL STATIC SONG INDEX FRESHNESS TESTS PASSED" if _failures == 0 else
		"%d STATIC SONG INDEX FRESHNESS TEST(S) FAILED" % _failures)
	quit(_failures)
