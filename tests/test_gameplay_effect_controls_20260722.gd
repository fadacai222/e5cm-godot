extends SceneTree
## ESC 特效控制与 Gameplay 实时停算回归。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_gameplay_effect_controls_20260722.gd

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _frame_anim_count(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path == "res://fx/frame_anim.gd" \
				and not child.is_queued_for_deletion():
			count += 1
	return count


func _payload() -> Dictionary:
	var base := "res://assets/e5cm_runtime/songs/竞速/club/SPEED_CLUB#12356_1612#11"
	return {
		"sm": base.path_join("12356_1612 [SPEED_CLUB].sm"),
		"mp3": "", "cover": base.path_join("bann.jpg"),
		"name": "EFFECT CONTROL QA", "star": 11,
		"mode": "竞速", "submode": "club", "sm_key": "qa/effect-control.sm",
		"prefer_double": true, "couple": false, "target_charttype": "pump-double",
	}


func _initialize() -> void:
	# 等 Autoload 完成 _ready/load_settings，再覆盖为测试专用状态，避免用户配置污染。
	await process_frame
	var settings = root.get_node("SettingsStore")
	settings.persist_enabled = false
	settings.show_ready_animation = false
	settings.autoplay = true
	settings.background_mode = "动态背景"
	settings.dynamic_background_mode = "唱片"
	settings.performance_mode = false
	settings.combo_lane_particles_enabled = true
	settings.combo_arrow_overlay_enabled = true
	settings.hp_overdrive_fx_enabled = true
	settings.spectrum_animation_enabled = true
	settings.avatar_frame_animation_enabled = true
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SceneRouter").payload = _payload()

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	for _i in 4:
		await process_frame

	var vinyl = gameplay.get("vinyl")
	var gpu_particle_node := vinyl.get_node_or_null("VinylGpuParticles") as GPUParticles2D \
		if vinyl != null else null
	if vinyl != null:
		vinyl.call("on_combo", 300)
	_check(vinyl != null and vinyl.has_method("particle_backend_for_test") \
		and str(vinyl.call("particle_backend_for_test")) == "gpu" \
		and gpu_particle_node != null and gpu_particle_node.amount == 324,
		"唱片满档 324 粒子使用单个 GPU 粒子系统，不再每帧逐圆 CPU 绘制",
		"node=%s amount=%s" % [gpu_particle_node, gpu_particle_node.amount if gpu_particle_node else -1])

	var menu = gameplay.get("esc_menu")
	# 避免 SceneTree 脚本在项目 Autoload 注册前静态编译 EscMenu 全部依赖。
	const DISPLAY_TAB_INDEX := 2
	const EFFECT_TAB_INDEX := 6
	menu.call("_set_tab", DISPLAY_TAB_INDEX)
	var display_rows: Array = menu.get("_row_defs")
	_check(display_rows.all(func(row): return str(row[0]) != "极简性能模式"),
		"极简性能模式不再放在游戏 / 分辨率设置页",
		str(display_rows))
	menu.call("_set_tab", EFFECT_TAB_INDEX)
	_check(menu.call("active_tab_for_test") == EFFECT_TAB_INDEX,
		"ESC 菜单存在独立特效控制页")
	var effect_rows: Array = menu.get("_row_defs")
	_check(effect_rows.size() == 6 and str(effect_rows[0][0]) == "极简性能模式",
		"特效控制页首项为极简性能总开关，并包含五个独立特效开关",
		str(effect_rows))

	var score = gameplay.get("score")
	var field = gameplay.get("note_field")
	score.current_combo = 100
	gameplay.call("_update_combo_sprite")
	var combo_digits = gameplay.get("combo_digits") as Control
	var first_digit_id := combo_digits.get_child(0).get_instance_id() \
		if combo_digits != null and combo_digits.get_child_count() > 0 else 0
	gameplay.call("_update_combo_sprite")
	var repeated_digit_id := combo_digits.get_child(0).get_instance_id() \
		if combo_digits != null and combo_digits.get_child_count() > 0 else -1
	_check(first_digit_id != 0 and first_digit_id == repeated_digit_id,
		"Combo 数值未变化时复用数字节点，不再每帧删除重建",
		"before=%d after=%d" % [first_digit_id, repeated_digit_id])
	score.current_combo = 101
	gameplay.call("_update_combo_sprite")
	var changed_digit_id := combo_digits.get_child(0).get_instance_id() \
		if combo_digits != null and combo_digits.get_child_count() > 0 else -1
	_check(first_digit_id != 0 and first_digit_id == changed_digit_id,
		"Combo 数值变化时继续复用数字节点池，只更新纹理与布局",
		"before=%d changed=%d" % [first_digit_id, changed_digit_id])
	_check(field.call("combo_lane_fx_visible_for_test"),
		"默认开启时 100 Combo 显示轨道描边粒子")
	var milestone = gameplay.get("combo_milestone_fx")
	settings.combo_arrow_overlay_enabled = false
	gameplay.call("_on_setting_changed", "combo_arrow_overlay")
	_check(not field.call("is_combo_gold_fx_enabled") \
		and field.call("combo_lane_fx_visible_for_test") and milestone.call("is_active"),
		"关闭箭头 Combo 叠加层只停用箭头/Key/Hold 金化，不连带关闭轨道与里程碑")
	settings.combo_arrow_overlay_enabled = true
	gameplay.call("_on_setting_changed", "combo_arrow_overlay")
	_check(field.call("is_combo_gold_fx_enabled"),
		"重新开启箭头叠加层会按当前 Combo 档位即时恢复")
	settings.combo_lane_particles_enabled = false
	gameplay.call("_on_setting_changed", "combo_lane_particles")
	_check(not field.call("combo_lane_fx_visible_for_test"),
		"关闭轨道描边粒子后立即停用")
	score.current_combo = 200
	gameplay.call("_update_combo_sprite")
	_check(not field.call("combo_lane_fx_visible_for_test"),
		"关闭后后续 Combo 里程碑不会重新开启轨道粒子")

	var hp = gameplay.get("hp")
	hp.hp = 1200
	gameplay.call("_update_hud")
	_check(gameplay.get_node("LegacyTopHud/HpFullFx").visible,
		"默认开启时满血显示暴走血条层")
	settings.hp_overdrive_fx_enabled = false
	gameplay.call("_on_setting_changed", "hp_overdrive_fx")
	gameplay.call("_update_hud")
	_check(not gameplay.get_node("LegacyTopHud/HpFullFx").visible \
		and not gameplay.get_node("LegacyTopHud/HpOverdriveEnergy").visible,
		"关闭暴走血条后基础满血状态不再运行附加特效")

	var stage_spectrum = gameplay.get("stage_spectrum")
	_check(stage_spectrum.visible and stage_spectrum.is_processing(),
		"默认开启时圆环频谱可见并处理")
	settings.spectrum_animation_enabled = false
	gameplay.call("_on_setting_changed", "spectrum_animation")
	_check(not stage_spectrum.visible and not stage_spectrum.is_processing(),
		"关闭频谱后停止绘制与每帧 FFT 处理")

	var avatar_fx = gameplay.get("avatar_frame_fx")
	var vip_particles = gameplay.get("vip_particles")
	settings.avatar_frame_animation_enabled = false
	gameplay.call("_on_setting_changed", "avatar_frame_animation")
	var frozen_texture = avatar_fx.texture
	var frozen_vip_texture = vip_particles.texture if vip_particles != null else null
	gameplay.call("_update_dynamic_hud", 0.1, 0.016)
	gameplay.call("_update_dynamic_hud", 1.1, 0.016)
	_check(avatar_fx.texture == frozen_texture \
		and (vip_particles == null or vip_particles.texture == frozen_vip_texture),
		"关闭头像序列帧后冻结头像框与 VIP 粒子层，不再逐帧替换纹理")

	# 极简性能模式是运行时总开关，但不能覆盖或改写用户的五项独立设置。
	settings.combo_lane_particles_enabled = true
	settings.combo_arrow_overlay_enabled = true
	settings.hp_overdrive_fx_enabled = true
	settings.spectrum_animation_enabled = true
	settings.avatar_frame_animation_enabled = true
	settings.performance_mode = false
	gameplay.call("_on_setting_changed", "combo_lane_particles")
	gameplay.call("_on_setting_changed", "hp_overdrive_fx")
	gameplay.call("_on_setting_changed", "spectrum_animation")
	gameplay.call("_on_setting_changed", "avatar_frame_animation")
	score.current_combo = 300
	gameplay.call("_update_combo_sprite")
	gameplay.call("_update_hud")
	var awakening = gameplay.get("stage_awakening_fx")
	field.call("spawn_hit_effect", 0)
	var hit_fx_before_performance := _frame_anim_count(field)
	var click_fx := root.get_node("ClickFx")
	click_fx.set("_last_spawn_ms", -1000)
	click_fx.call("_spawn", Vector2(960, 540))
	var click_fx_before_performance := _frame_anim_count(click_fx)
	_check(field.call("is_combo_gold_fx_enabled") and milestone.call("is_active") \
		and int(awakening.call("get_stage")) == 4 and gpu_particle_node != null \
		and gpu_particle_node.emitting and hit_fx_before_performance > 0 \
		and click_fx_before_performance > 0,
		"进入性能模式前满 Combo、唱片、击中和全局点击特效均在运行")

	settings.performance_mode = true
	settings.apply_performance()
	gameplay.call("_on_setting_changed", "performance_mode")
	gameplay.call("_update_hud")
	_check(not field.call("is_combo_gold_fx_enabled") \
		and not field.call("combo_lane_fx_visible_for_test") \
		and not milestone.call("is_active") \
		and int(awakening.call("get_stage")) == 0,
		"极简性能模式立即关闭满 Combo 箭头叠加层、轨道层和舞台觉醒层")
	_check(gpu_particle_node != null and not gpu_particle_node.emitting \
		and not gpu_particle_node.visible \
		and not gameplay.get_node("LegacyTopHud/HpFullFx").visible \
		and not stage_spectrum.visible and not stage_spectrum.is_processing(),
		"极简性能模式立即关闭唱片粒子、暴走血条与频谱计算")
	_check(_frame_anim_count(field) == 0 and _frame_anim_count(click_fx) == 0,
		"极简性能模式清理正在播放的击中与全局点击序列帧特效")
	field.call("spawn_hit_effect", 0)
	click_fx.set("_last_spawn_ms", -1000)
	click_fx.call("_spawn", Vector2(960, 540))
	_check(_frame_anim_count(field) == 0 and _frame_anim_count(click_fx) == 0,
		"极简性能模式开启期间禁止新建击中与全局点击粒子序列帧")
	score.current_combo = 301
	gameplay.call("_update_combo_sprite")
	_check(not field.call("is_combo_gold_fx_enabled") and not milestone.call("is_active"),
		"极简性能模式开启期间后续 Combo 不会重新拉起箭头和全屏叠加层")
	_check(settings.combo_lane_particles_enabled and settings.combo_arrow_overlay_enabled \
		and settings.hp_overdrive_fx_enabled and settings.spectrum_animation_enabled \
		and settings.avatar_frame_animation_enabled,
		"极简性能模式只做运行时覆盖，不改写五项独立设置")

	settings.performance_mode = false
	settings.apply_performance()
	gameplay.call("_on_setting_changed", "performance_mode")
	gameplay.call("_update_hud")
	_check(field.call("is_combo_gold_fx_enabled") and milestone.call("is_active") \
		and int(awakening.call("get_stage")) == 4 and gpu_particle_node != null \
		and gpu_particle_node.emitting and stage_spectrum.visible \
		and stage_spectrum.is_processing() \
		and (vip_particles == null or vip_particles.visible),
		"关闭极简性能模式后按当前 Combo 和独立设置恢复特效")

	if is_instance_valid(gameplay) and gameplay.get_parent() == root:
		root.remove_child(gameplay)
		gameplay.free()
	if root.get_node("AudioDirector").has_method("release_for_shutdown"):
		root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.15).timeout
	print("ALL GAMEPLAY EFFECT CONTROL TESTS PASSED" if _failures == 0 else
		"%d GAMEPLAY EFFECT CONTROL TEST(S) FAILED" % _failures)
	quit(_failures)
