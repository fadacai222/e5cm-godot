extends SceneTree
## 人工差异清单回归：SPACE 直接暂停/继续谱面，不打开 ESC 菜单。

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


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [message, detail])


func _space_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	return event


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("SettingsStore").show_ready_animation = false
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SceneRouter").payload = {}

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	await process_frame
	await process_frame
	var conductor = gameplay.get("conductor")
	var esc_menu = gameplay.get("esc_menu")
	_check(conductor != null and not conductor.is_paused(), "谱面初始不是暂停状态")

	gameplay.call("_unhandled_input", _space_event())
	await process_frame
	_check(conductor.is_paused(), "第一次按 SPACE 暂停谱面")
	_check(not esc_menu.is_open(), "SPACE 暂停不打开 ESC 设置菜单")
	var video = gameplay.get("bg_video")
	_check(video == null or video.paused, "SPACE 暂停同步暂停游戏背景视频")
	var stage_spectrum = gameplay.get("stage_spectrum")
	_check(stage_spectrum == null or stage_spectrum.get("paused") == true,
		"SPACE 暂停同步冻结 Stage 频谱")
	var vinyl = gameplay.get("vinyl")
	_check(vinyl == null or vinyl.get("paused") == true, "SPACE 暂停同步冻结唱片动画")
	var overdrive_energy = gameplay.get("hp_overdrive_energy")
	_check(overdrive_energy == null or overdrive_energy.get("_paused") == true,
		"SPACE 暂停同步冻结暴走血条独立能量层")

	gameplay.call("_unhandled_input", _space_event())
	await process_frame
	_check(not conductor.is_paused(), "第二次按 SPACE 继续谱面")
	_check(video == null or not video.paused, "SPACE 继续同步恢复游戏背景视频")
	_check(stage_spectrum == null or stage_spectrum.get("paused") == false,
		"SPACE 继续同步恢复 Stage 频谱")
	_check(vinyl == null or vinyl.get("paused") == false, "SPACE 继续同步恢复唱片动画")
	_check(overdrive_energy == null or overdrive_energy.get("_paused") == false,
		"SPACE 继续同步恢复暴走血条独立能量层")

	conductor.stop()
	gameplay.call("_stop_gameplay_video")
	var music := gameplay.get_node("MusicPlayer") as AudioStreamPlayer
	music.stop()
	music.stream = null
	root.remove_child(gameplay)
	gameplay.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL GAMEPLAY SPACE PAUSE TESTS PASSED" if _failures == 0 else
		"%d GAMEPLAY SPACE PAUSE TEST(S) FAILED" % _failures)
	quit(_failures)
