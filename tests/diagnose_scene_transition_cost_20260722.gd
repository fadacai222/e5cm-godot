extends SceneTree
## 诊断场景资源切换本身耗时，不包含 SceneRouter 的人为淡入淡出和按钮转场。

const CASES := [
	["login", "res://scenes/login/login.tscn"],
	["profile", "res://scenes/profile/profile.tscn"],
	["mode_select", "res://scenes/mode_select/mode_select.tscn"],
	["submode_select", "res://scenes/submode_select/submode_select.tscn"],
	["song_select", "res://scenes/song_select/song_select.tscn"],
	["training_setup", "res://scenes/training_setup/training_setup.tscn"],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var game_state := root.get_node("GameState")
	var scene_router := root.get_node("SceneRouter")
	game_state.big_mode = "花式"
	game_state.sub_mode = "club"
	game_state.player_count = 1
	for pass_index in 2:
		for item in CASES:
			var label := str(item[0])
			var path := str(item[1])
			scene_router.payload = {}
			var started := Time.get_ticks_usec()
			var err := change_scene_to_file(path)
			var returned := Time.get_ticks_usec()
			if err != OK:
				print("SCENE_PROFILE pass=%d %s ERROR=%s" % [pass_index + 1, label, error_string(err)])
				continue
			await scene_changed
			var changed := Time.get_ticks_usec()
			await process_frame
			var first_frame := Time.get_ticks_usec()
			print("SCENE_PROFILE pass=%d %s call_ms=%.3f changed_ms=%.3f first_frame_ms=%.3f" % [
				pass_index + 1,
				label,
				float(returned - started) / 1000.0,
				float(changed - started) / 1000.0,
				float(first_frame - started) / 1000.0,
			])
	quit(0)
