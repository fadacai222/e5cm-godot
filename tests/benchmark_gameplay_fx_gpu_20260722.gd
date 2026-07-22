extends SceneTree
## 完整 Gameplay GPU 组合基准：基础、舞台觉醒、百连旧特效、二者叠加。
## 非 headless 运行：Godot_v4.6.2-stable_win64_console.exe --path . --script res://tests/benchmark_gameplay_fx_gpu_20260722.gd

const SAMPLE_SECONDS := 1.8
var _results := {}


func _payload() -> Dictionary:
	var base := "res://assets/e5cm_runtime/songs/竞速/club/SPEED_CLUB#12356_1612#11"
	return {
		"sm": base.path_join("12356_1612 [SPEED_CLUB].sm"),
		"mp3": "", "cover": base.path_join("bann.jpg"),
		"name": "GAMEPLAY FX GPU QA", "star": 11,
		"mode": "竞速", "submode": "club", "sm_key": "qa/gameplay-fx-gpu.sm",
		"prefer_double": true, "couple": false, "target_charttype": "pump-double",
	}


func _initialize() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var settings = root.get_node("SettingsStore")
	settings.persist_enabled = false
	settings.show_ready_animation = false
	settings.autoplay = true
	settings.performance_mode = false
	settings.background_mode = "动态背景"
	settings.dynamic_background_mode = "唱片"
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SceneRouter").payload = _payload()

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	for _i in 8:
		await process_frame

	var awakening = gameplay.get("stage_awakening_fx")
	var milestone = gameplay.get("combo_milestone_fx")
	var field = gameplay.get("note_field")
	gameplay.call("_set_visual_pause", true)

	awakening.call("reset_immediate")
	milestone.call("stop_effect")
	field.call("set_combo_gold_fx_level", 0)
	field.call("set_combo_lane_fx_enabled", false)
	await _measure("base")

	awakening.call("set_combo", 300, false)
	awakening.call("set_paused", true)
	await _measure("awakening")

	awakening.call("reset_immediate")
	milestone.call("play_milestone", 300, false)
	milestone.call("set_paused", true)
	await _measure("milestone")

	awakening.call("set_combo", 300, false)
	awakening.call("set_paused", true)
	await _measure("combined")

	print("GAMEPLAY_FX_GPU base=%.1f awakening=%.1f milestone=%.1f combined=%.1f" % [
		float(_results.get("base", 0.0)), float(_results.get("awakening", 0.0)),
		float(_results.get("milestone", 0.0)), float(_results.get("combined", 0.0))])
	var audio_director := root.get_node("AudioDirector")
	if audio_director.has_method("release_for_shutdown"):
		audio_director.release_for_shutdown()
	quit(0)


func _measure(label: String) -> void:
	await create_timer(0.35).timeout
	var frames := 0
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < SAMPLE_SECONDS:
		await process_frame
		frames += 1
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var fps := float(frames) / maxf(elapsed, 0.001)
	_results[label] = fps
	print("  GAMEPLAY_GPU %s %.1f FPS" % [label, fps])
