extends SceneTree
## RTX 5090 实机动态 Gameplay 基准：真实 MP3 + 300 Combo + 满血暴走。
## 每个状态创建全新 Gameplay，避免歌曲密度和临时节点随时间变化污染对比。
## 非 headless 运行：Godot_v4.6.2-stable_win64_console.exe --path . --script res://tests/benchmark_gameplay_effect_controls_20260722.gd

const SAMPLE_SECONDS := 2.2
var _results := {}


func _payload() -> Dictionary:
	var base := "res://songs/diy/破解原版曲包/12356_1612"
	return {
		"sm": base.path_join("12356_1612.sm"),
		"mp3": base.path_join("12356_1612.mp3"),
		"cover": base.path_join("bann.jpg"),
		"name": "EFFECT CONTROL BENCHMARK", "star": 11,
		"mode": "diy", "submode": "破解原版曲包", "sm_key": "qa/effect-control-benchmark.sm",
		"prefer_double": true, "couple": false, "target_charttype": "pump-double",
	}


func _initialize() -> void:
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

	await _measure_case(settings, "all_on", false, true, true, true, true)
	await _measure_case(settings, "performance", true, true, true, true, true)
	await _measure_case(settings, "all_four_off", false, false, false, false, false)

	print("GAMEPLAY_EFFECT_CONTROL_BENCHMARK %s" % JSON.stringify(_results))
	var audio_director := root.get_node("AudioDirector")
	if audio_director.has_method("release_for_shutdown"):
		audio_director.release_for_shutdown()
	quit(0)


func _measure_case(settings: Node, label: String, performance_mode: bool,
		combo_lane: bool, overdrive: bool, spectrum: bool, avatar: bool) -> void:
	settings.performance_mode = performance_mode
	settings.combo_lane_particles_enabled = combo_lane
	settings.hp_overdrive_fx_enabled = overdrive
	settings.spectrum_animation_enabled = spectrum
	settings.avatar_frame_animation_enabled = avatar
	root.get_node("SceneRouter").payload = _payload()

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	for _i in 18:
		await process_frame
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var score = gameplay.get("score")
	var hp = gameplay.get("hp")
	var field = gameplay.get("note_field")
	score.current_combo = 300
	hp.hp = 1200
	gameplay.call("_update_combo_sprite")
	gameplay.call("_update_hud")
	await create_timer(0.55).timeout

	var frames := 0
	var draw_calls := 0.0
	var primitives := 0.0
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < SAMPLE_SECONDS:
		await process_frame
		frames += 1
		draw_calls += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives += float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var fps := float(frames) / maxf(elapsed, 0.001)
	_results[label] = snappedf(fps, 0.1)
	print("  EFFECT_BENCH %-14s %.1f FPS notes=%d draws=%.0f primitives=%.0f" % [
		label, fps, field.get("_render_notes").size(),
		draw_calls / maxf(frames, 1), primitives / maxf(frames, 1)])

	root.remove_child(gameplay)
	gameplay.free()
	await create_timer(0.25).timeout
