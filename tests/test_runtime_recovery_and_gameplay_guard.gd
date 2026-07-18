extends SceneTree
## 桌面长任务资源恢复 + 缺失谱面防止直接跳结算。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SceneRouter", "res://autoload/scene_router.gd"],
]

var _failures := 0
var _created: Array[Node] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("GameState").persist_credits = false

	var loader := root.get_node("AssetLoader")
	_check(loader.has_method("runtime_root") and loader.has_method("songs_root"),
		"AssetLoader 分别暴露核心资源根与外置曲库根")
	var runtime_root := str(loader.call("runtime_root")) if loader.has_method("runtime_root") else ""
	var songs_root := str(loader.call("songs_root")) if loader.has_method("songs_root") else ""
	_check(not runtime_root.is_empty() and not songs_root.is_empty() \
		and DirAccess.open(songs_root) != null,
		"运行时能找到真实外置曲库目录", songs_root)

	var baseline = JSON.parse_string(FileAccess.get_file_as_string(
		"res://parity/fixtures/sm_parser_baseline.json"))
	var recovered_cases := 0
	if baseline is Array:
		for entry in baseline:
			var recovered := str(loader.call("abs_path", str(entry.get("sm", ""))))
			if FileAccess.file_exists(recovered):
				recovered_cases += 1
	_check(baseline is Array and recovered_cases == baseline.size(),
		"全部 SM 基准谱面可从恢复资源根读取",
		"%d/%d songs_root=%s" % [recovered_cases, baseline.size() if baseline is Array else 0, songs_root])

	var library := root.get_node("SongLibrary")
	var songs: Array = library.get_songs("竞速", "club")
	var playable := 0
	var cover_song: Dictionary = {}
	for raw_song in songs:
		var song: Dictionary = raw_song
		if FileAccess.file_exists(str(song.get("sm", ""))) \
				and FileAccess.file_exists(str(song.get("mp3", ""))):
			playable += 1
			if cover_song.is_empty() and FileAccess.file_exists(str(song.get("cover", ""))):
				cover_song = song
	_check(playable > 20, "竞速 club 列表返回真实可玩的歌曲而非空气索引",
		"playable=%d total=%d" % [playable, songs.size()])
	_check(not cover_song.is_empty() \
		and loader.call("tex", str(cover_song.get("cover", ""))) != null,
		"歌曲封面可从恢复资源根加载",
		str(cover_song.get("cover", "")))

	root.get_node("GameState").big_mode = "竞速"
	root.get_node("GameState").sub_mode = "club"
	root.get_node("SceneRouter").payload = {}
	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	root.add_child(song_select)
	for _frame in 300:
		await process_frame
		var overlay := song_select.get_node_or_null("SongLoadingOverlay") as Control
		if overlay != null and not overlay.visible:
			break
	var card_cover := song_select.get_node_or_null("SongCard0/CoverClip/Cover") as TextureRect
	_check(card_cover != null and card_cover.texture != null,
		"选歌页真实卡片显示歌曲封面")
	var preview := song_select.get_node_or_null("PreviewPlayer") as AudioStreamPlayer
	if preview != null:
		preview.stop()
		preview.stream = null
	root.remove_child(song_select)
	song_select.free()

	var playable_payload := {
		"sm": cover_song.get("sm", ""), "mp3": cover_song.get("mp3", ""),
		"cover": cover_song.get("cover", ""), "name": cover_song.get("name", ""),
		"star": cover_song.get("star", 1), "mode": "竞速", "submode": "club",
		"sm_key": cover_song.get("sm_key", ""), "prefer_double": true,
		"couple": false, "target_charttype": cover_song.get("charttype", ""),
	}
	root.get_node("SceneRouter").payload = playable_payload.duplicate(true)
	var loading := (load("res://scenes/loading/loading.tscn") as PackedScene).instantiate() as Control
	root.add_child(loading)
	await process_frame
	_check(bool(loading.get("_payload_ready")),
		"加载页接受恢复目录中的真实歌曲", str(loading.get("_load_error")))
	var loading_cover := loading.get_node_or_null("Cover") as TextureRect
	_check(loading_cover != null and loading_cover.texture != null,
		"加载页显示真实歌曲封面")
	root.remove_child(loading)
	loading.free()

	root.get_node("SceneRouter").payload = playable_payload.duplicate(true)
	var playable_gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(playable_gameplay)
	await process_frame
	await process_frame
	var playable_field = playable_gameplay.get("note_field")
	_check(bool(playable_gameplay.get("_chart_ready")),
		"真实歌曲谱面被标记为可开始", str(playable_gameplay.get("_load_error")))
	_check(float(playable_gameplay.get("chart_duration")) > 10.0,
		"真实歌曲具有有效谱面时长", str(playable_gameplay.get("chart_duration")))
	_check((playable_gameplay.get_node("MusicPlayer") as AudioStreamPlayer).stream != null,
		"真实歌曲 MP3 成功加载")
	_check(playable_field != null and (playable_field.get("_render_notes") as Array).size() > 0,
		"真实歌曲音符已进入渲染器")
	root.remove_child(playable_gameplay)
	playable_gameplay.free()

	# 缺失谱面必须停留在错误状态，不能以 0 秒谱面启动并自动进入结算。
	var missing_payload := {
		"sm": "res://assets/e5cm_runtime/songs/__missing__/missing.sm",
		"mp3": "res://assets/e5cm_runtime/songs/__missing__/missing.mp3",
		"cover": "res://assets/e5cm_runtime/songs/__missing__/missing.jpg",
		"name": "缺失资源测试", "star": 1, "mode": "竞速", "submode": "club",
		"sm_key": "songs/__missing__/missing.sm", "prefer_double": false,
	}
	root.get_node("SceneRouter").payload = missing_payload.duplicate(true)
	var bad_loading := (load("res://scenes/loading/loading.tscn") as PackedScene).instantiate() as Control
	root.add_child(bad_loading)
	await process_frame
	_check(not bool(bad_loading.get("_payload_ready"))
		and not str(bad_loading.get("_load_error")).is_empty(),
		"加载页拦截缺失的谱面/音频")
	var loading_error := bad_loading.get_node_or_null("LoadingError") as Control
	_check(loading_error != null and loading_error.visible,
		"加载页显示可见错误而不是继续倒计时")
	bad_loading.call("_go")
	_check(not bool(bad_loading.get("_done")),
		"加载失败时禁止进入 Gameplay")
	root.remove_child(bad_loading)
	bad_loading.free()

	root.get_node("SceneRouter").payload = missing_payload.duplicate(true)
	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	await process_frame
	_check(gameplay.get("_chart_ready") == false,
		"缺失谱面不会被标记为可开始")
	_check(not str(gameplay.get("_load_error")).is_empty(),
		"缺失谱面给出明确加载错误")
	var error_view := gameplay.get_node_or_null("GameplayLoadError") as Control
	_check(error_view != null and error_view.visible,
		"Gameplay 显示加载失败提示而不是直接跳结算")
	_check(not bool(gameplay.get("_ended")),
		"加载失败状态不会伪造一局结算")
	root.remove_child(gameplay)
	gameplay.free()

	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame

	print("ALL RUNTIME RECOVERY/GAMEPLAY GUARD TESTS PASSED" if _failures == 0 else
		"%d RUNTIME RECOVERY/GAMEPLAY GUARD TEST(S) FAILED" % _failures)
	quit(_failures)
