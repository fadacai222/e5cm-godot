extends SceneTree
## 外置曲库与按需缓存回归：歌曲不得进入 Godot 导入缓存，返回选歌必须复用内存列表。

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var loader = root.get_node_or_null("AssetLoader")
	var owns_loader := false
	if loader == null:
		loader = load("res://autoload/asset_loader.gd").new()
		loader.name = "AssetLoader"
		root.add_child(loader)
		owns_loader = true
	await process_frame
	var original_songs_root := str(loader.call("songs_root")) if loader.has_method("songs_root") else ""
	var expected_project_songs := ProjectSettings.globalize_path("res://songs").replace("\\", "/").trim_suffix("/")
	_check(original_songs_root == expected_project_songs,
		"默认曲库指向项目根目录 songs", original_songs_root)

	var external_root := "user://qa_external_song_library"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(external_root))
	var fixture := external_root.path_join("fixture.sm")
	var fixture_file := FileAccess.open(fixture, FileAccess.WRITE)
	fixture_file.store_string("#TITLE:外置曲库测试;\n#ARTIST:测试歌手;")
	fixture_file.close()

	_check(loader.has_method("songs_root") \
		and loader.has_method("set_songs_root_for_test") \
		and loader.has_method("is_song_path"),
		"AssetLoader 提供独立于核心资源根的外置曲库接口")
	if loader.has_method("set_songs_root_for_test"):
		loader.set_songs_root_for_test(external_root)
		var mapped := str(loader.abs_path("songs/fixture.sm"))
		_check(mapped == external_root.path_join("fixture.sm") \
			and loader.is_song_path(mapped),
			"songs/... 路径映射到项目外曲库，而不是 res:// 导入目录", mapped)
		_check(str(loader.abs_path("UI-img")).begins_with("res://assets/e5cm_runtime"),
			"UI、音效等核心资源仍留在项目内")

	_check(FileAccess.file_exists("res://songs/.gdignore"),
		"项目根目录 songs 使用 .gdignore，禁止 Godot 再复制到 .godot/imported")
	var export_config := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(export_config.contains("songs/**"),
		"Windows 导出明确排除项目根目录完整曲库")
	_check(loader.has_method("song_texture_cache_limit_for_test") \
		and int(loader.call("song_texture_cache_limit_for_test")) <= 32,
		"歌曲封面仅使用有上限的内存 LRU，不无限缓存翻过的全部歌曲")
	var fake_song_cache := {}
	var fake_song_lru: Array[String] = []
	for i in 30:
		var fake_path := external_root.path_join("cover_%02d.png" % i)
		fake_song_cache[fake_path] = null
		fake_song_lru.append(fake_path)
	loader.set("_song_tex_cache", fake_song_cache)
	loader.set("_song_tex_lru", fake_song_lru)
	loader.trim_song_texture_cache()
	_check((loader.get("_song_tex_cache") as Dictionary).size() \
			<= int(loader.song_texture_cache_limit_for_test()),
		"封面 LRU 实际淘汰超出上限的旧页面纹理",
		str((loader.get("_song_tex_cache") as Dictionary).size()))
	loader.clear_song_texture_cache()

	var library = load("res://autoload/song_library.gd").new()
	library.name = "SongLibraryExternalCacheTest"
	root.add_child(library)
	await process_frame
	_check(str(library.songs_root) == external_root,
		"SongLibrary 使用 AssetLoader 选定的项目外曲库根", str(library.songs_root))
	_check(library.has_method("has_cached_songs") \
		and library.has_method("get_cached_songs"),
		"SongLibrary 提供选歌场景即时复用内存列表的接口")
	if library.has_method("has_cached_songs"):
		library.set("_cache", {"竞速/club": [{"name": "内存歌曲", "sm_key": "cached"}]})
		_check(bool(library.has_cached_songs("竞速", "club")) \
			and (library.get_cached_songs("竞速", "club") as Array).size() == 1,
			"返回选歌时直接复用 Autoload 内存缓存，不重新扫描或显示加载层")

	# 搜索侧车必须连显示元数据一起保存；下次启动不允许为了歌手字段再逐首读谱面。
	var source := [{
		"name": "缓存标题", "artist": "缓存歌手", "subtitle": "副标题",
		"folder": "fixture", "sm_key": "fixture-key", "sm": fixture,
	}]
	var payload: Dictionary = library.call("_build_search_index_payload", source, "qa", false)
	var restored := [{
		"name": "旧标题", "artist": "", "subtitle": "", "folder": "fixture",
		"sm_key": "fixture-key", "sm": fixture,
	}]
	var attached := bool(library.call("_attach_search_payload", restored, "qa", payload))
	_check(attached \
		and str((restored[0] as Dictionary).get("name", "")) == "缓存标题" \
		and str((restored[0] as Dictionary).get("artist", "")) == "缓存歌手",
		"搜索索引侧车恢复标题和歌手，进选歌不再重新读取全部谱面")

	root.remove_child(library)
	library.free()
	if loader.has_method("set_songs_root_for_test"):
		loader.set_songs_root_for_test(original_songs_root)
	if owns_loader:
		root.remove_child(loader)
		loader.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(external_root))

	print("ALL EXTERNAL SONG LIBRARY CACHE TESTS PASSED" if _failures == 0 else
		"%d EXTERNAL SONG LIBRARY CACHE TEST(S) FAILED" % _failures)
	quit(_failures)
