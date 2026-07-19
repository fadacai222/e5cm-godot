extends SceneTree
## Combo 50/100 阶梯特效与满血 5 秒粒子延迟回归。
## 运行：godot --headless --path . --script res://tests/test_combo_hp_staging_20260719.gd

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
var _lane_signal_values: Array[bool] = []


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
		"name": "COMBO HP STAGING QA", "star": 11,
		"mode": "竞速", "submode": "club", "sm_key": "qa/combo-hp-staging.sm",
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
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false

	var fx = load("res://fx/combo_milestone_fx.gd").new()
	root.add_child(fx)
	await process_frame
	var has_combo_staging: bool = fx.has_method("effect_stage_for_combo") \
		and fx.has_method("play_arrow_stage") \
		and fx.has_method("lane_fx_enabled_for_test") \
		and fx.has_method("milestone_visual_active_for_test") \
		and fx.has_signal("lane_fx_changed")
	_check(has_combo_staging, "ComboMilestoneFx 提供 50/100 独立阶段接口")
	if has_combo_staging:
		_check(int(fx.call("effect_stage_for_combo", 49)) == 0 \
			and int(fx.call("effect_stage_for_combo", 50)) == 50 \
			and int(fx.call("effect_stage_for_combo", 99)) == 50 \
			and int(fx.call("effect_stage_for_combo", 100)) == 100 \
			and int(fx.call("effect_stage_for_combo", 247)) == 200 \
			and int(fx.call("effect_stage_for_combo", 999)) == 900,
			"Combo 阶段映射为 0→50→100→每百连强化")
		fx.connect("lane_fx_changed", func(enabled: bool): _lane_signal_values.append(enabled))
		fx.call("play_arrow_stage", 50, false)
		_check(bool(fx.call("is_active")) \
			and int(fx.call("milestone_level_for_test")) == 1 \
			and not bool(fx.call("lane_fx_enabled_for_test")) \
			and not bool(fx.call("milestone_visual_active_for_test")),
			"50 Combo 只建立第一档箭头预热，不开启轨道与百连全局演出")
		fx.call("play_milestone", 100, false)
		_check(bool(fx.call("lane_fx_enabled_for_test")) \
			and bool(fx.call("milestone_visual_active_for_test")) \
			and _lane_signal_values == [true],
			"100 Combo 才开启轨道层与百连全局演出", str(_lane_signal_values))
		fx.call("stop_effect")
		fx.call("play_arrow_stage", 50, false)
		fx.call("start_decay")
		var decay_step := float(fx.call("decay_level_hold_seconds_for_test"))
		var decay_fade := float(fx.call("decay_final_fade_seconds_for_test"))
		fx.call("_process", decay_step + decay_fade * 0.5)
		_check(bool(fx.call("is_active")) \
			and float(fx.call("decay_visibility_for_test")) > 0.0 \
			and float(fx.call("decay_visibility_for_test")) < 1.0,
			"50 Combo 断连后箭头预热阶段同样平滑淡出")
		fx.call("_process", decay_fade + 0.05)
		_check(not bool(fx.call("is_active")) \
			and int(fx.call("milestone_level_for_test")) == 0,
			"50 Combo 预热淡出完成后彻底释放")

	var note_field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(note_field)
	note_field.call("setup", 5, 4.0, false)
	var has_lane_switch: bool = note_field.has_method("set_combo_lane_fx_enabled") \
		and note_field.has_method("is_combo_lane_fx_enabled")
	_check(has_lane_switch, "NoteField 将箭头金化和轨道粒子拆成独立开关")
	if has_lane_switch:
		note_field.call("set_combo_gold_fx_level", 1)
		note_field.call("set_combo_lane_fx_enabled", false)
		_check(bool(note_field.call("is_combo_gold_fx_enabled")) \
			and not bool(note_field.call("is_combo_lane_fx_enabled")) \
			and not bool(note_field.call("combo_lane_fx_visible_for_test")),
			"50 Combo 箭头/Key/Hold 已金化但轨道粒子保持隐藏")
		note_field.call("set_combo_lane_fx_enabled", true)
		_check(bool(note_field.call("is_combo_lane_fx_enabled")) \
			and bool(note_field.call("combo_lane_fx_visible_for_test")),
			"100 Combo 开启轨道描边、流光和粒子")

	root.get_node("SceneRouter").payload = _payload()
	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	await process_frame
	await process_frame
	var hp_system = gameplay.get("hp")
	var hp_full := gameplay.get_node_or_null("LegacyTopHud/HpFullFx") as TextureRect
	var hp_energy := gameplay.get_node_or_null("LegacyTopHud/HpOverdriveEnergy") as Node2D
	var has_hp_staging: bool = gameplay.has_method("hp_overdrive_particle_delay_for_test") \
		and gameplay.has_method("hp_overdrive_full_hold_for_test") \
		and gameplay.has_method("hp_overdrive_energy_active_for_test") \
		and gameplay.has_method("_reset_hp_overdrive_stage")
	_check(has_hp_staging, "Gameplay 提供连续满血 5 秒粒子延迟状态机")
	if has_hp_staging and hp_system != null:
		gameplay.call("_reset_hp_overdrive_stage")
		hp_system.set("hp", 1200)
		gameplay.call("_update_hud")
		gameplay.call("_update_dynamic_hud", 2.0, 4.99)
		_check(hp_full != null and hp_full.visible \
			and hp_energy != null and not hp_energy.visible \
			and not bool(gameplay.call("hp_overdrive_energy_active_for_test")),
			"满血前 4.99 秒主血条已向右滚动但外溢粒子不出现")
		gameplay.call("_update_dynamic_hud", 2.02, 0.02)
		_check(hp_energy != null and hp_energy.visible \
			and bool(gameplay.call("hp_overdrive_energy_active_for_test")) \
			and absf(float(gameplay.call("hp_overdrive_particle_delay_for_test")) - 5.0) < 0.001,
			"连续满血达到 5 秒后开启外溢粒子")

		hp_system.set("hp", 1199)
		gameplay.call("_update_hud")
		gameplay.call("_update_dynamic_hud", 2.04, 0.02)
		_check(not bool(gameplay.call("hp_overdrive_energy_active_for_test")) \
			and is_zero_approx(float(gameplay.call("hp_overdrive_full_hold_for_test"))) \
			and hp_energy != null and not hp_energy.visible,
			"掉血后立即隐藏粒子并清零连续满血计时")

		hp_system.set("hp", 1200)
		gameplay.call("_update_hud")
		gameplay.call("_set_visual_pause", true)
		gameplay.call("_update_dynamic_hud", 2.04, 8.0)
		_check(is_zero_approx(float(gameplay.call("hp_overdrive_full_hold_for_test"))) \
			and not bool(gameplay.call("hp_overdrive_energy_active_for_test")),
			"暂停期间不累计满血保持时间")
		gameplay.call("_set_visual_pause", false)

	for node in [gameplay, note_field, fx]:
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.2).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL COMBO/HP STAGING TESTS PASSED" if _failures == 0 else
		"%d COMBO/HP STAGING TEST(S) FAILED" % _failures)
	quit(_failures)
