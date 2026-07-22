extends SceneTree
## 动态舞台五阶段觉醒系统 Gameplay 集成回归。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_stage_awakening_gameplay_20260722.gd

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


func _payload() -> Dictionary:
	var base := "res://assets/e5cm_runtime/songs/竞速/club/SPEED_CLUB#12356_1612#11"
	return {
		"sm": base.path_join("12356_1612 [SPEED_CLUB].sm"),
		"mp3": "", "cover": base.path_join("bann.jpg"),
		"name": "STAGE AWAKENING QA", "star": 11,
		"mode": "竞速", "submode": "club", "sm_key": "qa/stage-awakening.sm",
		"prefer_double": true, "couple": false, "target_charttype": "pump-double",
	}


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

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

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	await process_frame
	await process_frame

	var fx := gameplay.get_node_or_null("StageAwakeningFx")
	var overlay := gameplay.get_node_or_null("StageAwakeningFx/StageAwakeningOverlay") as ColorRect
	_check(fx != null and overlay != null and overlay.material is ShaderMaterial,
		"正式 Gameplay 挂载单 Shader 舞台觉醒层")
	_check(fx != null and fx.z_index == -150,
		"舞台觉醒层不会盖住判定区、HUD 或 READY 黑幕")
	_check(gameplay.has_method("stage_awakening_state_for_test"),
		"Gameplay 暴露舞台运行态验证接口")

	var score = gameplay.get("score")
	var background := gameplay.get_node("GameplayBackground") as TextureRect
	for case in [[50, 1], [100, 2], [200, 3], [300, 4]]:
		score.current_combo = case[0]
		gameplay.call("_update_combo_sprite")
		var state: Dictionary = gameplay.call("stage_awakening_state_for_test")
		_check(int(state.get("stage", -1)) == case[1],
			"正式 Gameplay 的 %d Combo 进入舞台第 %d 档" % [case[0], case[1]], str(state))

	var divine_state: Dictionary = gameplay.call("stage_awakening_state_for_test")
	_check(float(divine_state.get("zoom", 1.0)) > 1.015 \
		and is_equal_approx(background.scale.x, float(divine_state.get("zoom", 1.0))),
		"神域档真实推进当前背景而不缩放判定区", "%s / %s" % [background.scale, divine_state])

	score.current_combo = 0
	gameplay.call("_update_combo_sprite")
	_check(bool(fx.call("is_decaying")) and int(fx.call("get_stage")) == 4,
		"正式 Gameplay 断连后从神域逐档衰减")
	fx.call("_process", float(fx.call("decay_step_seconds_for_test")) + 0.01)
	_check(int(fx.call("get_stage")) == 3 \
		and is_equal_approx(background.scale.x, float(fx.call("get_background_zoom"))),
		"正式背景缩放随降档同步回落")

	score.current_combo = 300
	gameplay.call("_update_combo_sprite")
	settings.performance_mode = true
	settings.apply_performance()
	gameplay.call("_on_setting_changed", "performance_mode")
	var awakening_overlay := fx.get_node("StageAwakeningOverlay") as ColorRect
	_check(int(fx.call("get_stage")) == 0 \
		and is_equal_approx(float(fx.call("get_background_zoom")), 1.0) \
		and not awakening_overlay.visible,
		"运行中切换极简性能模式立即关闭舞台觉醒层并恢复背景缩放")

	settings.background_mode = "图片"
	gameplay.call("_apply_background_mode")
	_check(background.texture != null \
		and is_equal_approx(background.scale.x, 1.0),
		"性能模式中切换图片背景保持无舞台缩放")
	settings.background_mode = "动态背景"
	settings.dynamic_background_mode = "唱片"
	gameplay.call("_apply_background_mode")
	var vinyl = gameplay.get("vinyl")
	_check(vinyl != null and is_equal_approx(vinyl.scale.x, 1.0) \
		and not bool(vinyl.call("particles_enabled_for_test")),
		"性能模式中重建唱片背景仍保持无缩放且粒子关闭")

	gameplay.call("_set_visual_pause", true)
	_check(bool(fx.get("_paused")), "暂停游戏时舞台动画同步暂停")
	gameplay.call("_set_visual_pause", false)
	_check(not bool(fx.get("_paused")), "恢复游戏时舞台动画同步恢复")

	if is_instance_valid(gameplay) and gameplay.get_parent() == root:
		root.remove_child(gameplay)
		gameplay.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.2).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL STAGE AWAKENING GAMEPLAY TESTS PASSED" if _failures == 0 else
		"%d STAGE AWAKENING GAMEPLAY TEST(S) FAILED" % _failures)
	quit(_failures)
