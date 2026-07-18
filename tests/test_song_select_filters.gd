extends SceneTree
## 选歌筛选 UI 接线测试。
## 运行：godot --headless --path . --script res://tests/test_song_select_filters.gd

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


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


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

	var game_state := root.get_node("GameState")
	game_state.big_mode = "竞速"
	game_state.sub_mode = "club"
	game_state.credits = 6
	root.get_node("SceneRouter").payload = {"filter_style": "双踏板", "filter_star": 8}

	var inst: Node = load("res://scenes/song_select/song_select.tscn").instantiate()
	root.add_child(inst)
	for i in 3:
		await process_frame

	var panel := inst.get_node_or_null("FilterPanel")
	_check(panel != null, "筛选面板已接入选歌场景")
	_check(str(inst.get("filter_style")) == "双踏板" and int(inst.get("filter_star")) == 8,
		"从载荷恢复玩法和星级筛选")
	var shown_songs: Array = inst.get("songs")
	_check(not shown_songs.is_empty(), "恢复筛选后仍有匹配歌曲")
	_check(shown_songs.all(func(song):
		return str(song.get("style", "")) == "双踏板" and int(song.get("star", 0)) == 8),
		"列表实际应用组合筛选")

	if panel != null and inst.has_method("_on_slot_filter"):
		inst.call("_on_slot_filter")
		_check(bool(panel.call("is_open")), "歌曲分类按钮打开筛选面板")

	var preview := inst.get_node_or_null("PreviewPlayer") as AudioStreamPlayer
	if preview != null:
		preview.stop()
		preview.stream = null
	root.remove_child(inst)
	inst.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	if _failures == 0:
		print("ALL SONG SELECT FILTER TESTS PASSED")
	quit(_failures)
