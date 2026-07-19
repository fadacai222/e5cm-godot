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
			"sm": "missing.json",
			"sm_key": "songs/花式/学习/Alpha#1/missing.json",
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
