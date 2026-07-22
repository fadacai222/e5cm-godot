extends SceneTree
## 核心资源自包含 + 外置曲库契约：UI/音效在项目内，51GB 歌曲不进入 Godot 导入缓存。

const RUNTIME_ROOT := "res://assets/e5cm_runtime"
const REQUIRED_CORE_FILES := [
	"backmovies/开场动画/001.png",
	"backmovies/游戏中/001原版马到成功.mp4",
	"冷资源/backsound/back_music_ui.mp3",
	"UI-img/游戏界面/血条/blood_bar/skin.json",
	"UI-img/游戏界面/血条/blood_bar/skin.png",
	"song_index.json",
]
const RUNTIME_SOURCE_FILES := [
	"res://autoload/asset_loader.gd",
	"res://autoload/song_library.gd",
	"res://tests/parity/parity_driver.gd",
	"res://tests/test_gameplay_visual_contract.gd",
	"res://tests/test_sm_parser.gd",
]

var _failures := 0


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [message, detail])


func _initialize() -> void:
	var loader = root.get_node_or_null("AssetLoader")
	var owns_loader := false
	if loader == null:
		loader = load("res://autoload/asset_loader.gd").new()
		loader.name = "AssetLoader"
		root.add_child(loader)
		owns_loader = true
	var library = load("res://autoload/song_library.gd").new()
	library.name = "SongLibraryAssetContractTest"
	root.add_child(library)
	await process_frame
	var ui_path := str(loader.abs_path("UI-img"))
	_check(ui_path == RUNTIME_ROOT.path_join("UI-img"),
		"AssetLoader 核心 UI 根目录位于项目内", ui_path)
	_check(DirAccess.open(loader.songs_root()) != null,
		"AssetLoader 可定位项目外或兼容回退曲库", loader.songs_root())
	_check(FileAccess.file_exists(RUNTIME_ROOT.path_join("songs/.gdignore")),
		"项目内 songs 使用 .gdignore，禁止写入 .godot/imported")

	for relative_path in REQUIRED_CORE_FILES:
		var project_path := RUNTIME_ROOT.path_join(relative_path)
		_check(FileAccess.file_exists(project_path),
			"核心运行资源保留在项目内：%s" % relative_path, project_path)

	var startup: Texture2D = loader.tex("backmovies/开场动画/001.png")
	_check(startup != null, "项目内启动图可由 AssetLoader 读取")
	var blood_bar: Dictionary = loader.atlas("UI-img/游戏界面/血条/blood_bar")
	_check(not blood_bar.is_empty(), "项目内血条图集可解析")
	var ui_music: String = loader.sound("音乐_UI")
	_check(ui_music.begins_with(RUNTIME_ROOT) and FileAccess.file_exists(ui_music),
		"项目内 UI BGM 可由 AudioDirector 路径加载", ui_music)
	library._ready()
	var songs: Array = library.get_songs("竞速", "club")
	_check(songs.size() > 10, "静态曲库索引可在不访问原版目录时返回歌曲", str(songs.size()))
	if not songs.is_empty():
		var song: Dictionary = songs[0]
		_check(str(song.get("sm", "")).begins_with(loader.songs_root()),
			"静态曲库索引映射到当前外置曲库根", str(song.get("sm", "")))

	# 索引存在不等于资源存在：逐条通过 AssetLoader 映射后验证外置谱面、音频和封面。
	var index_data = JSON.parse_string(FileAccess.get_file_as_string(
		RUNTIME_ROOT.path_join("song_index.json")))
	var indexed_variants := 0
	var missing_indexed_files := 0
	var missing_samples: Array[String] = []
	if index_data is Dictionary:
		indexed_variants = int(index_data.get("songVariantCount", 0))
		var songs_by_key: Dictionary = index_data.get("songsByKey", {})
		for mode_key in songs_by_key:
			for item in songs_by_key[mode_key]:
				for field in ["sm", "mp3", "cover"]:
					var indexed_path := str((item as Dictionary).get(field, ""))
					if indexed_path.is_empty():
						continue
					var resolved_path: String = str(loader.abs_path(indexed_path))
					if not FileAccess.file_exists(resolved_path):
						missing_indexed_files += 1
						if missing_samples.size() < 8:
							missing_samples.append(resolved_path)
	_check(indexed_variants >= 5900, "静态曲库索引包含完整谱面变体", str(indexed_variants))
	_check(missing_indexed_files == 0,
		"静态曲库索引中的谱面、音频和封面全部真实存在",
		"missing=%d samples=%s" % [missing_indexed_files, missing_samples])

	for source_path in RUNTIME_SOURCE_FILES:
		var source := FileAccess.get_file_as_string(source_path)
		_check(not source.contains("C:/Users/admin/Desktop/E5CM-CG"),
			"运行与回归源码不含原版绝对路径：%s" % source_path, source_path)

	var export_config := FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(export_config.contains("*.sm") and export_config.contains("*.ssc") \
		and export_config.contains("*.json"),
		"导出配置包含动态谱面与图集 JSON 原文件")
	_check(export_config.contains("songs/**") \
		and export_config.contains("assets/e5cm_runtime/songs/**"),
		"导出配置明确排除项目根目录及旧位置的 51GB 曲库")
	_check(export_config.contains("assets/e5cm_runtime/song_index.json"),
		"发行 PCK 不携带开发机完整曲库索引")
	_check((export_config.contains("parity/**") \
			or export_config.contains("parity/resource_migration/**")) \
		and export_config.contains("tests/**") and export_config.contains("tools/**"),
		"导出配置排除迁移证据与开发测试文件")

	root.remove_child(library)
	library.free()
	if owns_loader:
		root.remove_child(loader)
		loader.free()
	print("ALL SELF-CONTAINED ASSET TESTS PASSED" if _failures == 0 else
		"%d SELF-CONTAINED ASSET TEST(S) FAILED" % _failures)
	quit(_failures)
