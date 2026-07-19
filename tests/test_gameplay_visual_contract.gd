extends SceneTree
## 游戏场景人工差异回归：验证真实运行几何、动画状态和渲染结果，禁止只查“节点存在”。

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


func _near_rect(control: Control, expected: Rect2, tolerance := 2.0) -> bool:
	if control == null:
		return false
	var actual := control.get_rect()
	return actual.position.distance_to(expected.position) <= tolerance \
		and actual.size.distance_to(expected.size) <= tolerance


func _payload() -> Dictionary:
	var base := "res://assets/e5cm_runtime/songs/竞速/club/SPEED_CLUB#12356_1612#11"
	return {
		"sm": base.path_join("12356_1612 [SPEED_CLUB].sm"),
		"mp3": "", "cover": base.path_join("bann.jpg"), "name": "12356_1612 [SPEED_CLUB]", "star": 11,
		"mode": "竞速", "submode": "club", "sm_key": "qa/gameplay.sm",
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
	settings.show_ready_animation = true
	settings.autoplay = true
	settings.arrow_skin = "原版默认"
	settings.background_mode = "动态背景"
	settings.dynamic_background_mode = "唱片"
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("ProfileStore").profile["昵称"] = "像素校准员"
	root.get_node("SceneRouter").payload = _payload()

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(gameplay)
	await process_frame
	await process_frame

	# 9.1 READY/GO：慢速 8.15s 分层动画，实际覆盖 1920×1080。
	var ready = gameplay.get("ready_anim") as Control
	_check(ready != null and ready.size == Vector2(1920, 1080),
		"准备动画根层实际覆盖 1920×1080", str(ready.size) if ready else "null")
	_check(ready != null and ready.has_method("total_duration") \
		and absf(float(ready.call("total_duration")) - 8.15) < 0.03,
		"准备动画使用放慢后的 8.15 秒完整时间轴")
	_check(ready != null and ready.has_method("seek_for_test"), "准备动画支持确定性关键帧采样")
	if ready != null and ready.has_method("seek_for_test"):
		var ready_front := ready.get_node_or_null("Guide/ReadyFront") as CanvasItem
		var go_front := ready.get_node_or_null("Guide/GoFront") as CanvasItem
		var guide := ready.get_node_or_null("Guide") as Control
		var note_field := gameplay.get("note_field") as Node2D
		var background := gameplay.get_node("GameplayBackground") as TextureRect
		var background_dim := gameplay.get_node("BackgroundDim") as ColorRect
		var note_region := gameplay.get_node("NoteFieldRegion") as Control
		var intro_hud := gameplay.get_node("LegacyTopHud") as Control

		ready.call("seek_for_test", 0.0)
		gameplay.call("_update_ready_reveal")
		_check(background_dim.color.a >= 0.99 and intro_hud.modulate.a == 0.0
			and note_field.modulate.a == 0.0,
			"切入 Gameplay 首帧保持全黑且 HUD/判定区不闪现")
		_check(ready.get_node_or_null("SceneDim") == null
			and background.z_index < background_dim.z_index
			and background_dim.z_index < note_region.z_index
			and note_region.z_index < intro_hud.z_index,
			"黑幕固定在背景上方、判定区和血条下方")

		ready.call("seek_for_test", 1.45)
		gameplay.call("_update_ready_reveal")
		_check(absf(background_dim.color.a) <= 0.001,
			"背景先完整满亮度出现")
		ready.call("seek_for_test", 2.45)
		gameplay.call("_update_ready_reveal")
		_check(absf(background_dim.color.a - 0.70) <= 0.01,
			"底层黑幕随后缓慢加深到 70%")

		ready.call("seek_for_test", 2.55)
		gameplay.call("_update_ready_reveal")
		_check(note_field.modulate == Color.WHITE and note_field.scale == Vector2.ONE,
			"判定区到点直接满亮度显示，不再缩放淡入")
		ready.call("seek_for_test", 3.30)
		gameplay.call("_update_ready_reveal")
		_check(intro_hud.modulate == Color.WHITE and intro_hud.position.y > -260.0,
			"顶部血条组满亮度从屏幕外缓慢下落")

		ready.call("seek_for_test", 4.05)
		_check(guide != null and guide.position.x <= -1910.0,
			"ARE YOU READY 动画组从左侧屏幕外开始入场")
		ready.call("seek_for_test", 4.85)
		_check(guide != null and absf(guide.position.x) <= 1.0,
			"准备动画组平稳进入画面")
		ready.call("seek_for_test", 5.40)
		_check(ready_front != null and ready_front.visible and ready_front.modulate.a > 0.75
			and go_front != null and not go_front.visible,
			"ARE YOU READY 清晰显示并保留停顿")
		ready.call("seek_for_test", 6.80)
		_check(go_front != null and go_front.visible and go_front.modulate.a > 0.75,
			"停顿后 GAME START 关键帧真实可见")
		ready.call("seek_for_test", 7.65)
		_check(guide != null and guide.position.x > 0.0 and go_front.visible,
			"GAME START 随整组向右退场")
		ready.call("seek_for_test", 8.15)
		gameplay.call("_update_ready_reveal")
		_check(background_dim.modulate == Color.WHITE,
			"准备动画结束时恢复游戏内背景亮度设置")
	var conductor = gameplay.get("conductor")
	_check(conductor != null and absf(float(conductor.get("lead_in_sec")) - 8.15) < 0.03,
		"音乐起播倒计时与慢速准备动画同步", str(conductor.get("lead_in_sec")) if conductor else "null")

	# 9.3 左上头像：原版圆形裁切、正确层级、动态框/VIP装饰和昵称尺寸。
	var hud := gameplay.get_node("LegacyTopHud") as Control
	var avatar := hud.get_node_or_null("Avatar") as TextureRect
	var avatar_frame := hud.get_node_or_null("AvatarFrame") as TextureRect
	var avatar_fx := hud.get_node_or_null("AvatarFrameFx") as TextureRect
	var vip_icon := hud.get_node_or_null("VipIcon") as TextureRect
	var vip_particles := hud.get_node_or_null("VipParticles") as TextureRect
	var nickname := hud.get_node_or_null("Nickname") as Label
	_check(_near_rect(avatar, Rect2(196, 17, 137, 137), 3.0),
		"头像使用原版内圆区位置与正方形尺寸", str(avatar.get_rect()) if avatar else "null")
	_check(avatar != null and avatar.material is ShaderMaterial,
		"头像使用圆形像素遮罩而非方形 clip_contents")
	var avatar_material := avatar.material as ShaderMaterial if avatar != null else null
	_check(avatar_material != null and avatar_material.shader != null
		and avatar_material.shader.resource_path == "res://fx/circular_avatar_mask.gdshader"
		and avatar.modulate == Color.WHITE and avatar.self_modulate == Color.WHITE,
		"Gameplay 头像使用统一原色遮罩，不再二次乘色发暗",
		avatar_material.shader.resource_path if avatar_material != null and avatar_material.shader != null else "null")
	_check(avatar_frame != null and avatar_frame.z_index > avatar.z_index,
		"头像框覆盖头像边缘但不遮住头像中心")
	_check(avatar_fx != null and avatar_fx.texture != null and avatar_fx.visible,
		"头像框 30 帧动效真实加载")
	_check(vip_icon != null and vip_icon.texture != null and vip_particles != null,
		"头像区域包含 V/VIP 图标与粒子动效")
	_check(nickname != null and nickname.position.distance_to(Vector2(438, 113)) < 2.0 \
		and nickname.get_theme_font_size("font_size") == 31 \
		and nickname.get_theme_constant("outline_size") == 0 \
		and not nickname.clip_text,
		"昵称使用原版位置、31px 无描边样式且不硬裁切",
		"%s / font=%d outline=%d" % [
			nickname.position,
			nickname.get_theme_font_size("font_size"),
			nickname.get_theme_constant("outline_size"),
		] if nickname else "null")
	_check(gameplay.has_method("_apply_gameplay_nickname"),
		"Gameplay 提供按真实字形宽度适配昵称的方法")
	if gameplay.has_method("_apply_gameplay_nickname"):
		var nickname_cases := [
			{"text": "良", "expect_base": true},
			{"text": "像素校准员", "expect_base": true},
			{"text": "超长昵称验证一二三四五六七八九十", "expect_base": false},
		]
		for nickname_case in nickname_cases:
			gameplay.call("_apply_gameplay_nickname", nickname_case["text"])
			await process_frame
			var nickname_font := nickname.get_theme_font("font")
			var nickname_size := nickname.get_theme_font_size("font_size")
			var nickname_width := nickname_font.get_string_size(
				nickname.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nickname_size).x
			_check(nickname.text == nickname_case["text"] and nickname_width <= 270.0,
				"昵称“%s”完整保留且不侵入分数区域" % nickname_case["text"],
				"text=%s width=%.1f font=%d" % [nickname.text, nickname_width, nickname_size])
			_check(nickname_size == 31 if nickname_case["expect_base"] else nickname_size < 31,
				"昵称“%s”使用正确的基础/缩小字号" % nickname_case["text"],
				"font=%d" % nickname_size)
		gameplay.call("_apply_gameplay_nickname", "像素校准员")

	# 9.4 血条：长度、波浪位移和暴走层。
	var hp_fill := hud.get_node_or_null("HpFill") as TextureRect
	var hp_full := hud.get_node_or_null("HpFullFx") as TextureRect
	var hp_energy := hud.get_node_or_null("HpOverdriveEnergy") as Node2D
	var hp_system = gameplay.get("hp")
	gameplay.call("_update_hud")
	_check(hp_system != null and int(hp_system.get("hp")) == 700 \
		and int(hp_system.call("visible_hp")) == 500 \
		and is_equal_approx(float(hp_system.call("visible_ratio")), 0.5),
		"开局总 HP 700 扣除隐藏 200 后显示 50%",
		"total=%s visible=%s ratio=%s" % [hp_system.get("hp"), hp_system.call("visible_hp"), hp_system.call("visible_ratio")] if hp_system else "null")
	_check(hp_fill != null and hp_fill.position.distance_to(Vector2(283, 26)) < 6.0 \
		and absf(hp_fill.size.y - 76.0) < 3.0 and float(gameplay.get("_hp_fill_full_w")) > 1340.0,
		"血条容器采用原版内部有效区域与完整长度", "%s / full=%s" % [hp_fill.get_rect(), gameplay.get("_hp_fill_full_w")] if hp_fill else "null")
	_check(hp_fill != null and absf(hp_fill.size.x - float(gameplay.get("_hp_fill_full_w")) * 0.5) < 2.0,
		"开局血条可见宽度与 50% HP 状态一致",
		"actual=%s expected=%s" % [hp_fill.size.x, float(gameplay.get("_hp_fill_full_w")) * 0.5] if hp_fill else "null")
	_check(hp_full != null and hp_full.size.distance_to(Vector2(1249, 67)) < 3.0,
		"暴走血条使用原版完整有效区域尺寸", str(hp_full.get_rect()) if hp_full else "null")
	_check(hp_full != null and hp_full.material is ShaderMaterial,
		"暴走血条使用可无缝平铺的滚动材质")
	_check(hp_energy != null and hp_energy.has_method("set_energy_state") \
		and int(hp_energy.get("spark_count")) >= 32 \
		and float(hp_energy.get("overflow_padding")) >= 24.0,
		"暴走血条包含独立加法能量层、外溢光束与密集火花",
		"node=%s sparks=%s padding=%s" % [
			hp_energy, hp_energy.get("spark_count") if hp_energy else -1,
			hp_energy.get("overflow_padding") if hp_energy else -1,
		])
	_check(gameplay.has_method("_hp_overdrive_offset"),
		"暴走血条提供确定性的单向滚动偏移")
	if gameplay.has_method("_hp_overdrive_offset"):
		var overdrive_0 := float(gameplay.call("_hp_overdrive_offset", 0.0))
		var overdrive_1 := float(gameplay.call("_hp_overdrive_offset", 0.2))
		var overdrive_2 := float(gameplay.call("_hp_overdrive_offset", 0.4))
		_check(is_zero_approx(overdrive_0) \
			and absf(overdrive_1 - 60.0) < 0.2 \
			and absf(overdrive_2 - 120.0) < 0.2,
			"暴走素材按原版 300px/s 持续向右，不使用往返 sin 动画",
			"%s / %s / %s" % [overdrive_0, overdrive_1, overdrive_2])
		var overdrive_material := hp_full.material as ShaderMaterial
		gameplay.call("_update_dynamic_hud", 0.4, 0.0)
		var phase_before_pause := float(overdrive_material.get_shader_parameter("phase_pixels"))
		gameplay.call("_set_visual_pause", true)
		gameplay.call("_update_dynamic_hud", 0.4, 0.0)
		var phase_during_pause := float(overdrive_material.get_shader_parameter("phase_pixels"))
		gameplay.call("_set_visual_pause", false)
		_check(absf(phase_before_pause - 120.0) < 0.2 \
			and is_equal_approx(phase_before_pause, phase_during_pause),
			"暴走滚动随谱面时间推进，暂停时保持同一相位",
			"before=%s paused=%s" % [phase_before_pause, phase_during_pause])
	_check(gameplay.has_method("hp_overdrive_particle_delay_for_test") \
		and gameplay.has_method("hp_overdrive_energy_active_for_test") \
		and gameplay.has_method("_reset_hp_overdrive_stage"),
		"暴走血条提供连续满血 5 秒后的第二阶段粒子状态机")
	if hp_system != null and hp_energy != null:
		hp_system.set("hp", 1200)
		gameplay.call("_reset_hp_overdrive_stage")
		gameplay.call("_update_hud")
		gameplay.call("_update_dynamic_hud", 1.0, 4.99)
		_check(hp_full.visible and not hp_energy.visible \
			and not bool(gameplay.call("hp_overdrive_energy_active_for_test")),
			"满血第一阶段立即显示并向右滚动主血条，前 4.99 秒不出现外溢粒子")
		gameplay.call("_update_dynamic_hud", 1.02, 0.02)
		_check(hp_energy.visible \
			and bool(gameplay.call("hp_overdrive_energy_active_for_test")) \
			and absf(float(gameplay.call("hp_overdrive_particle_delay_for_test")) - 5.0) < 0.001,
			"连续保持满血 5 秒后进入第二阶段并开启外溢粒子动画")
		hp_system.set("hp", 700)
		gameplay.call("_update_hud")
		gameplay.call("_update_dynamic_hud", 1.04, 0.0)
	_check(gameplay.has_method("_hp_wave_offset"), "血条具有确定性的左右波浪函数")
	if gameplay.has_method("_hp_wave_offset"):
		var wave_a := float(gameplay.call("_hp_wave_offset", 0.0))
		var wave_b := float(gameplay.call("_hp_wave_offset", 0.4))
		_check(absf(wave_a - wave_b) > 0.2 and absf(wave_a) <= 5.1 and absf(wave_b) <= 5.1,
			"血条以原版 5px 幅度动态左右跳动", "%s / %s" % [wave_a, wave_b])

	# 9.5/9.6 分数、Stage、唱片/频谱/歌名动态层级。
	var score_label := hud.get_node_or_null("Score") as Label
	var percent_label := hud.get_node_or_null("Percent") as Label
	var stage_board := hud.get_node_or_null("StageBoard") as TextureRect
	var stage_text := hud.get_node_or_null("StageText") as TextureRect
	var stage_spectrum := hud.get_node_or_null("StageSpectrum") as Node2D
	var auto_badge := hud.get_node_or_null("Autoplay") as Label
	var song_title := hud.get_node_or_null("SongTitle") as Label
	var stars := hud.get_node_or_null("Stars") as Label
	var countdown := hud.get_node_or_null("Countdown") as Label
	var score_system = gameplay.get("score")
	_check(score_label != null and absf(score_label.position.y - 102.0) < 2.0 \
		and absf(score_label.position.x + score_label.size.x - 852.0) < 2.0,
		"分数右边界和基线按原版 1280×720 布局换算",
		"%s / right=%s" % [score_label.position, score_label.position.x + score_label.size.x] if score_label else "null")
	_check(score_label != null and not score_label.clip_text,
		"分数禁止使用 clip_text 截断高位数字")
	_check(percent_label != null \
		and percent_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and percent_label.get_theme_constant("outline_size") >= 4 \
		and not percent_label.get_theme_color("font_color").is_equal_approx(Color.WHITE),
		"分数右侧百分比使用青粉高亮配色、居中与独立描边，不再是普通白字",
		"align=%s outline=%s color=%s" % [percent_label.horizontal_alignment,
			percent_label.get_theme_constant("outline_size"),
			percent_label.get_theme_color("font_color")] if percent_label else "null")
	_check(score_label != null and score_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT \
		and score_label.get_theme_font_size("font_size") == 28 \
		and score_label.get_theme_constant("outline_size") == 2,
		"分数使用原版右对齐、28px 粗体视觉尺寸和 2px 粉色描边",
		"align=%s font=%s outline=%s" % [
			score_label.horizontal_alignment,
			score_label.get_theme_font_size("font_size"),
			score_label.get_theme_constant("outline_size"),
		] if score_label else "null")
	for score_value in [0, 45000, 987654, 1350000]:
		score_system.current_score = score_value
		gameplay.call("_update_hud")
		await process_frame
		var score_font := score_label.get_theme_font("font")
		var score_width := score_font.get_string_size(
			score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			score_label.get_theme_font_size("font_size")
		).x + float(score_label.get_theme_constant("outline_size") * 2)
		_check(score_label.size.x >= score_width,
			"分数 %d 完整容纳，不裁切" % score_value,
			"container=%.1f text=%.1f" % [score_label.size.x, score_width])
	var score_design_rect := Rect2(score_label.position, score_label.size) if score_label else Rect2()
	var stage_text_design_rect := Rect2(stage_text.position, stage_text.size) if stage_text else Rect2()
	_check(stage_text != null and not score_design_rect.intersects(stage_text_design_rect),
		"分数与 STAGE 字样的设计矩形不重叠", "%s / %s" % [score_design_rect, stage_text_design_rect])
	_check(stage_board != null and stage_board.position.distance_to(Vector2(1440, -85)) < 3.0 \
		and stage_board.size.distance_to(Vector2(264, 251)) < 3.0,
		"右侧 Stage 信息组整体左移并保持唱片尺寸",
		"%s / %s" % [stage_board.position, stage_board.size] if stage_board else "null")
	var hp_tail_rect := Rect2(1500, 2, 202, 131)
	_check(stage_board != null and Rect2(stage_board.position, stage_board.size).intersects(hp_tail_rect),
		"Stage 唱片覆盖血条尾部，而不是悬在屏幕最右侧",
		str(Rect2(stage_board.position, stage_board.size)) if stage_board else "null")
	_check(stage_spectrum != null and stage_spectrum.position.distance_to(Vector2(1572, 40.5)) < 1.0 \
		and absf(float(stage_spectrum.get("inner_radius")) - 104.0) < 2.0 \
		and absf(float(stage_spectrum.get("max_len")) - 44.0) < 1.0 \
		and bool(stage_spectrum.call("has_edge_profile")),
		"Stage 频谱贴合唱片轮廓并扩展到 44px 鼓点外延",
		"%s / inner=%s max=%s" % [
			stage_spectrum.position,
			stage_spectrum.get("inner_radius"),
			stage_spectrum.get("max_len"),
		] if stage_spectrum else "null")
	_check(song_title != null and song_title.z_index == 83 \
		and song_title.position.distance_to(Vector2(1494, 9)) < 3.0 \
		and song_title.get_theme_font_size("font_size") == 18 \
		and song_title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"歌曲名位于唱片频谱中心并使用原版位置/字号",
		"z=%s rect=%s font=%s" % [
			song_title.z_index, song_title.get_rect(), song_title.get_theme_font_size("font_size")
		] if song_title else "null")
	_check(stars != null and stars.z_index == 83 and stars.text == "11★" \
		and stars.position.distance_to(Vector2(1543, 94)) < 3.0 \
		and stars.get_theme_font_size("font_size") == 22,
		"星级位于唱片板上层，顺序为数值后置星号",
		"z=%s text=%s font=%s" % [stars.z_index, stars.text, stars.get_theme_font_size("font_size")] if stars else "null")
	_check(countdown != null and countdown.z_index == 83 \
		and countdown.position.distance_to(Vector2(1512, 37)) < 3.0 \
		and countdown.get_theme_font_size("font_size") == 31,
		"倒计时位于唱片板上层并使用原版位置/字号",
		"z=%s rect=%s font=%s" % [
			countdown.z_index, countdown.get_rect(), countdown.get_theme_font_size("font_size")
		] if countdown else "null")
	_check(stage_board != null and stage_spectrum != null \
		and stage_spectrum.z_index < stage_board.z_index \
		and stage_board.z_index < song_title.z_index \
		and stage_board.z_index < stars.z_index \
		and stage_board.z_index < countdown.z_index,
		"右侧 HUD 层级固定为频谱 < 唱片板 < 歌名/星级/倒计时")
	var auto_design_rect := Rect2(auto_badge.position, auto_badge.size) if auto_badge else Rect2()
	var board_design_rect := Rect2(stage_board.position, stage_board.size) if stage_board else Rect2()
	_check(auto_badge != null and auto_badge.visible and auto_badge.text == "AUTO PLAY" \
		and auto_badge.z_index > stage_board.z_index \
		and not auto_design_rect.intersects(board_design_rect),
		"AUTO 标记位于唱片板下方独立高层，不再被右上唱片遮挡",
		"auto=%s z=%s board=%s" % [auto_design_rect, auto_badge.z_index, board_design_rect] if auto_badge else "null")
	var shortcut_hint := gameplay.get_node_or_null("GameplayShortcutHint") as Label
	var technical_crew := gameplay.get_node_or_null("TechnicalCrewFx") as Control
	var milestone_fx := gameplay.get_node_or_null("ComboMilestoneFx") as Control
	_check(shortcut_hint != null and shortcut_hint.visible \
		and shortcut_hint.text.contains("F6") and shortcut_hint.text.contains("F7") \
		and shortcut_hint.get_theme_color("font_color").is_equal_approx(Color.WHITE),
		"Gameplay 右侧以白字显示 F6 自动播放 / F7 击中音效快捷键")
	_check(technical_crew == null,
		"删除误解需求产生的技术组动画，自动播放只驱动中央计数组")
	var note_field = gameplay.get("note_field")
	_check(milestone_fx != null and milestone_fx.has_method("play_milestone") \
		and milestone_fx.has_method("is_active") \
		and milestone_fx.has_method("track_rect_for_test") \
		and milestone_fx.has_method("uses_fullscreen_flash_for_test") \
		and milestone_fx.has_method("uses_fullscreen_gold_bloom_for_test") \
		and milestone_fx.has_method("global_gold_intensity_for_test"),
		"Gameplay 挂载轨道爆发与全屏 UI 金色 Bloom 里程碑演出层")
	if milestone_fx != null:
		milestone_fx.call("play_milestone", 100, false)
		await process_frame
		var milestone_number := milestone_fx.get_node_or_null("MilestoneNumberGold") as Label
		var milestone_caption := milestone_fx.get_node_or_null("MilestoneCaption") as Label
		var number_rect := Rect2(milestone_number.position, milestone_number.size) \
			if milestone_number != null else Rect2()
		var track_rect: Rect2 = milestone_fx.call("track_rect_for_test") \
			if milestone_fx.has_method("track_rect_for_test") else Rect2()
		_check(bool(milestone_fx.call("is_active")) and milestone_fx.visible,
			"100 Combo 可触发持续到断连的演出而不创建第二套计数组")
		_check(milestone_number != null and milestone_number.text == "100" \
			and milestone_caption != null and milestone_caption.text == "COMBO" \
			and number_rect.end.x <= 190.0 and number_rect.end.y <= 150.0,
			"100 Combo 数字收纳到左上角，不遮挡主轨道视线", str(number_rect))
		var fullscreen_gold := milestone_fx.get_node_or_null("FullscreenGoldBloom") as ColorRect
		var fullscreen_gold_material := fullscreen_gold.material as ShaderMaterial \
			if fullscreen_gold != null else null
		_check(not bool(milestone_fx.call("uses_fullscreen_flash_for_test")) \
			and bool(milestone_fx.call("uses_fullscreen_gold_bloom_for_test")) \
			and track_rect.size.x > 500.0 and track_rect.size.y > 600.0,
			"百连不使用纯白遮眼闪屏，但会让全画面 UI/箭头边缘进入金色 Bloom", str(track_rect))
		_check(fullscreen_gold != null and fullscreen_gold.visible \
			and fullscreen_gold_material != null \
			and float(milestone_fx.call("global_gold_intensity_for_test")) >= 0.75,
			"百连触发全屏屏幕纹理金色描边/闪耀，覆盖 HUD、Combo、箭头和命中特效")
		_check(milestone_fx.has_method("uses_side_guides_for_test") \
			and not bool(milestone_fx.call("uses_side_guides_for_test")) \
			and int(milestone_fx.call("gold_particle_count_for_test")) == 0,
			"左右空区导向带、扫描栅格和侧边粒子已删除，避免额外掉帧")
		milestone_fx.call("stop_effect")
	_check(note_field != null and note_field.has_method("set_combo_gold_fx_level") \
		and note_field.has_method("set_combo_lane_fx_enabled") \
		and note_field.has_method("is_combo_gold_fx_enabled") \
		and note_field.has_method("is_combo_lane_fx_enabled"),
		"NoteField 将 Tap/Hold/Key 金化与轨道粒子拆成独立阶段接口")
	if note_field != null and note_field.has_method("set_combo_gold_fx_level"):
		score_system.current_combo = 49
		gameplay.call("_update_hud")
		score_system.current_combo = 50
		gameplay.call("_update_hud")
		_check(bool(note_field.call("is_combo_gold_fx_enabled")) \
			and not bool(note_field.call("is_combo_lane_fx_enabled")) \
			and not bool(note_field.call("combo_lane_fx_visible_for_test")) \
			and bool(milestone_fx.call("is_active")) \
			and not bool(milestone_fx.call("milestone_visual_active_for_test")),
			"真实跨越 50 Combo 时只启动 Tap/Hold/Key 金色材质，不提前爆出轨道与全局演出")
		score_system.current_combo = 100
		gameplay.call("_update_hud")
		_check(bool(note_field.call("is_combo_gold_fx_enabled")) \
			and bool(note_field.call("is_combo_lane_fx_enabled")) \
			and bool(note_field.call("combo_lane_fx_visible_for_test")) \
			and bool(milestone_fx.call("milestone_visual_active_for_test")),
			"真实跨越 100 Combo 时在箭头金化基础上开启轨道粒子与全局金光")
		score_system.current_combo = 200
		gameplay.call("_update_hud")
		_check(int(milestone_fx.call("milestone_level_for_test")) == 2 \
			and int(note_field.call("combo_gold_fx_level_for_test")) == 2,
			"跨越 200 Combo 后全局亮度和箭头金化同步升级")
		score_system.current_combo = 0
		gameplay.call("_update_hud")
		_check(bool(milestone_fx.call("is_active")) \
			and bool(milestone_fx.call("is_decaying")) \
			and int(note_field.call("combo_gold_fx_level_for_test")) == 2,
			"失误后先保留当前百连档位，不瞬间撤走全部特效")
		var decay_step := float(milestone_fx.call("decay_level_hold_seconds_for_test"))
		var decay_fade := float(milestone_fx.call("decay_final_fade_seconds_for_test"))
		milestone_fx.call("_process", decay_step + 0.01)
		_check(int(milestone_fx.call("milestone_level_for_test")) == 1 \
			and int(note_field.call("combo_gold_fx_level_for_test")) == 1,
			"全局 Bloom、Tap/Hold/Key 与七轨粒子同步逐级降档")
		milestone_fx.call("_process", decay_step + decay_fade * 0.5)
		_check(float(note_field.call("combo_gold_fx_visibility_for_test")) > 0.0 \
			and float(note_field.call("combo_gold_fx_visibility_for_test")) < 1.0,
			"最低档全套特效共同平滑淡出")
		milestone_fx.call("_process", decay_fade + 0.05)
		_check(not bool(milestone_fx.call("is_active")) \
			and not bool(note_field.call("is_combo_gold_fx_enabled")),
			"逐级降档完成后才释放百连材质与粒子")
		note_field.call("set_combo_gold_fx_level", 1)
		note_field.call("set_combo_lane_fx_enabled", false)
		var receptors: Array = note_field.get("_receptors")
		var receptor_gold_material := (receptors[0] as Sprite2D).material as ShaderMaterial \
			if not receptors.is_empty() else null
		_check(bool(note_field.call("is_combo_gold_fx_enabled")) \
			and receptor_gold_material != null \
			and float(receptor_gold_material.get_shader_parameter("outline_pixels")) >= 2.5 \
			and float(receptor_gold_material.get_shader_parameter("fx_strength")) >= 1.0,
			"50 Combo 时 Key 贴图先启用可见金色描边、流光和闪烁")
		note_field.call("set_combo_lane_fx_enabled", true)
		note_field.call("set_combo_gold_fx_level", 3)
		var capped_gold_fill := float(receptor_gold_material.get_shader_parameter("gold_fill"))
		note_field.call("set_combo_gold_fx_level", 7)
		note_field.call("set_combo_lane_fx_enabled", true)
		_check(int(note_field.call("combo_gold_fx_level_for_test")) == 3 \
			and is_equal_approx(float(receptor_gold_material.get_shader_parameter("gold_fill")),
				capped_gold_fill),
			"箭头金化在 300 Combo 后封顶，不再继续加深")
		var expected_gold_lanes := 14 if int(note_field.get("track_count")) >= 10 else 7
		_check(int(note_field.call("combo_lane_fx_count_for_test")) == expected_gold_lanes \
			and int(note_field.call("combo_lane_particle_system_count_for_test")) == expected_gold_lanes * 2 \
			and bool(note_field.call("combo_lane_fx_visible_for_test")),
			"百连期间每位玩家的左手、五踏板、右手七条轨道显示金色渐变粒子描边",
			"expected=%d lanes=%d particles=%d visible=%s" % [expected_gold_lanes,
				int(note_field.call("combo_lane_fx_count_for_test")),
				int(note_field.call("combo_lane_particle_system_count_for_test")),
				str(note_field.call("combo_lane_fx_visible_for_test"))])
		_check(int(note_field.call("combo_lane_flow_material_count_for_test")) == expected_gold_lanes * 2 \
			and int(note_field.call("combo_lane_flow_line_count_for_test")) == expected_gold_lanes * 2 \
			and int(note_field.call("combo_lane_glow_line_count_for_test")) == expected_gold_lanes * 4 \
			and int(note_field.call("combo_lane_peak_particle_amount_for_test")) >= 30 \
			and float(note_field.call("combo_lane_flow_intensity_for_test")) >= 1.7,
			"七轨百连特效只在两侧描边运行高速流光、白金核心炫光和渐变金粒子")
		_check(int(note_field.call("combo_lane_body_fill_count_for_test")) == 0 \
			and float(note_field.call("combo_lane_edge_bottom_for_test")) >= 1080.0,
			"轨道本体保持完全隐藏，金色描边延伸到 1080p 画布底部之外")
		note_field.call("set_combo_gold_fx_level", 0)
		_check(not bool(note_field.call("is_combo_gold_fx_enabled")) \
			and (receptors[0] as Sprite2D).material == null \
			and not bool(note_field.call("combo_lane_fx_visible_for_test")),
			"断连后 Key 金色材质和七轨粒子描边干净释放")

	var gold_field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(gold_field)
	gold_field.setup(5, 4.0, false)
	gold_field.load_notes([
		JudgeSystem.JudgeNote.new(1, "tap", 1.0, 1.0),
		JudgeSystem.JudgeNote.new(2, "hold", 0.9, 1.15),
	])
	gold_field.update_field(0.8, 0.016)
	gold_field.set_combo_gold_fx_level(1)
	var gold_items: Array = gold_field.get("_render_notes")
	var tap_head := gold_items[0].get("head") as Sprite2D
	var hold_head := gold_items[1].get("head") as Sprite2D
	var hold_neck := gold_items[1].get("neck") as Sprite2D
	var hold_body := gold_items[1].get("body") as Sprite2D
	var hold_tail := gold_items[1].get("tail") as Sprite2D
	_check(tap_head != null and tap_head.material is ShaderMaterial \
		and hold_head != null and hold_head.material is ShaderMaterial \
		and hold_neck != null and hold_neck.material is ShaderMaterial \
		and hold_body != null and hold_body.material is ShaderMaterial \
		and hold_tail != null and hold_tail.material is ShaderMaterial,
		"百连持续期间 Tap 与 Hold 头/mask/repeat/tail 全部启用纯金高亮描边")
	gold_field.update_field(0.8, 8.0)
	_check(gold_field.is_combo_gold_fx_enabled() \
		and tap_head.material != null and hold_head.material != null \
		and hold_neck.material != null and hold_body.material != null and hold_tail.material != null,
		"金色音符描边超过旧 5 秒限制后仍持续")
	gold_field.set_combo_gold_fx_level(0)
	_check(not gold_field.is_combo_gold_fx_enabled() \
		and tap_head.material == null and hold_head.material == null \
		and hold_neck.material == null and hold_body.material == null and hold_tail.material == null,
		"Combo 断掉后金色音符材质关闭且不污染对象池")
	root.remove_child(gold_field)
	gold_field.free()
	_check(stage_spectrum != null and stage_spectrum.has_method("sample_color_for_test") \
		and stage_spectrum.has_method("sample_glow_color"),
		"Stage 频谱提供分离的核心色与外发光渐变采样")
	if stage_spectrum != null and stage_spectrum.has_method("sample_color_for_test"):
		var low_color: Color = stage_spectrum.call("sample_color_for_test", 0.0, 0.15)
		var high_color: Color = stage_spectrum.call("sample_color_for_test", 0.72, 1.0)
		_check(low_color.a >= 0.95 and high_color.a >= 0.95 \
			and Vector4(low_color.r, low_color.g, low_color.b, low_color.a).distance_to(
				Vector4(high_color.r, high_color.g, high_color.b, high_color.a)) > 0.35,
			"频谱保持高饱和青/蓝/紫/粉层次，不使用浅色半透明线",
			"low=%s high=%s" % [low_color, high_color])
		var core_color: Color = stage_spectrum.call("sample_color_for_test", 0.88, 0.8)
		var glow_color: Color = stage_spectrum.call("sample_glow_color", 0.88, 0.8)
		_check(Vector3(core_color.r, core_color.g, core_color.b).distance_to(
			Vector3(glow_color.r, glow_color.g, glow_color.b)) > 0.08,
			"频谱核心线与外发光使用分离色相，避免整圈颜色重合")
		_check(float(stage_spectrum.get("line_width")) >= 2.0 \
			and float(stage_spectrum.get("glow_width")) > float(stage_spectrum.get("line_width")),
			"频谱使用清晰核心线与更宽发光层",
			"line=%s glow=%s" % [stage_spectrum.get("line_width"), stage_spectrum.get("glow_width")])
	_check(gameplay.has_method("_update_stage_motion"), "Stage 唱片支持按音乐时间旋转")
	if gameplay.has_method("_update_stage_motion") and stage_board != null:
		gameplay.call("_update_stage_motion", 0.0)
		var r0 := stage_board.rotation
		gameplay.call("_update_stage_motion", 1.0)
		_check(absf(stage_board.rotation - r0) > 0.1, "Stage 唱片一秒内发生可见旋转")

	# 9.9 Combo：全场只保留一套完整计数组，锚点固定在屏幕中心。
	score_system.current_combo = 12
	score_system.last_judge = "perfect"
	gameplay.call("_update_hud")
	await process_frame
	var combo_group := hud.get_node_or_null("ComboGroup") as Control
	var combo_digits := hud.get_node_or_null("ComboGroup/Digits") as Control
	var credit_center := gameplay.get_node_or_null("BottomCreditCenter") as CenterContainer
	var credit_label := gameplay.get_node_or_null("BottomCreditCenter/BottomCreditRow/CreditLabel") as Label
	var combo_group_count := 0
	for child in hud.get_children():
		if str(child.name).begins_with("ComboGroup"):
			combo_group_count += 1
	_check(combo_group_count == 1 and hud.get_node_or_null("ComboGroupRight") == null,
		"游戏场景只存在一套计数组", "count=%d" % combo_group_count)
	_check(combo_group != null and combo_group.visible \
		and combo_group.position.distance_to(Vector2(960, 540)) < 1.0,
		"计数组锚点位于 1920×1080 屏幕中心", str(combo_group.position) if combo_group else "null")
	_check(combo_group != null and combo_group.pivot_offset.distance_to(Vector2.ZERO) < 0.1,
		"计数组缩放锚点就是计数组中心", str(combo_group.pivot_offset) if combo_group else "null")
	_check(combo_digits != null and combo_digits.get_child_count() >= 3,
		"Combo 使用 x + 数字精灵图串而非系统字体", str(combo_digits.get_child_count()) if combo_digits else "null")
	_check(gameplay.has_method("_combo_texture_for_test"),
		"计数组提供当前箭头皮肤的判定/数字纹理解析接口")
	if gameplay.has_method("_combo_texture_for_test"):
		var current_combo_texture: Texture2D = gameplay.call("_combo_texture_for_test", "digit", "1")
		root.get_node("SettingsStore").arrow_skin = "01"
		gameplay.call("_on_setting_changed", "arrow_skin")
		await process_frame
		var switched_combo_texture: Texture2D = gameplay.call("_combo_texture_for_test", "digit", "1")
		_check(current_combo_texture != null and switched_combo_texture != null \
			and current_combo_texture != switched_combo_texture,
			"计数组数字纹理随箭头皮肤即时切换")
		root.get_node("SettingsStore").arrow_skin = "原版默认"
		gameplay.call("_on_setting_changed", "arrow_skin")
		await process_frame
	_check(credit_center != null and credit_label != null \
		and credit_center.position.y > 900.0 and credit_label.text.begins_with("CREDIT"),
		"Gameplay 底部正中显示公共联网信用标",
		"center=%s text=%s" % [credit_center.position, credit_label.text] if credit_label else "null")
	var credit_before := int(root.get_node("GameState").credits)
	root.get_node("GameState").insert_coin(1)
	await process_frame
	_check(credit_label != null and credit_label.text.contains("%d/" % (credit_before + 1)),
		"Gameplay 公共信用标随信用变化实时更新", credit_label.text if credit_label else "null")
	score_system.current_combo = 1
	gameplay.call("_update_hud")
	_check(combo_group != null and not combo_group.visible, "Combo 小于 2 时不强制常驻")

	# ESC 背景设置必须真正重建 Gameplay 背景层，不得只改右侧预览。
	_check(gameplay.has_method("background_state_for_test"), "Gameplay 提供背景运行态验证接口")
	if gameplay.has_method("background_state_for_test"):
		var initial_background: Dictionary = gameplay.call("background_state_for_test")
		_check(bool(initial_background["has_vinyl"]), "默认动态背景在 Gameplay 中真实生效")
		settings.background_mode = "图片"
		gameplay.call("_on_setting_changed", "background_mode")
		await process_frame
		var image_background: Dictionary = gameplay.call("background_state_for_test")
		_check(bool(image_background["has_image"]) and not bool(image_background["has_vinyl"]),
			"ESC 切换图片背景后立即替换动态背景")
		settings.background_mode = "动态背景"
		settings.dynamic_background_mode = "唱片"
		gameplay.call("_on_setting_changed", "dynamic_background")
		await process_frame
		var dynamic_background: Dictionary = gameplay.call("background_state_for_test")
		_check(bool(dynamic_background["has_vinyl"]) and not bool(dynamic_background["has_image"]),
			"ESC 切回唱片动态背景后立即恢复运行态")

	# 9.7/9.8 Hold 与手键：身体不可纵向强拉伸，必须有 neck、平铺身体、持续 tick 特效。
	var field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	field.setup(10, 1.0)
	var judge_script = load("res://core/judge_system.gd")
	var hold = judge_script.JudgeNote.new(2, "hold", 1.0, 3.0, [1.5, 2.0, 2.5])
	field.load_notes([hold])
	field.update_field(0.0, 0.016)
	var item: Dictionary = field.get("_render_notes")[0]
	var body := item.get("body") as Sprite2D
	var neck := item.get("neck") as Sprite2D
	var head := item.get("head") as Sprite2D
	var tail := item.get("tail") as Sprite2D
	_check(body != null and absf(body.scale.y - 1.0) < 0.04,
		"Hold 身体由平铺纹理生成，不再强制纵向拉伸", str(body.scale) if body else "null")
	_check(neck != null and neck.texture != null and neck.visible, "Hold 使用 arrow_mask 作为头身过渡段")
	_check(head != null and tail != null and head.modulate.a >= 0.999 \
		and body.modulate.a >= 0.999 and tail.modulate.a >= 0.999,
		"普通箭头与 Hold 各段保持完全不透明，禁止对象池 alpha 污染")
	_check(field.has_method("hold_geometry_for_test"), "Hold 提供可验证的头身尾拼接几何契约")
	if field.has_method("hold_geometry_for_test"):
		var geometry: Dictionary = field.call("hold_geometry_for_test", 210.0, 840.0, 122.0, 36.0, 28.0)
		_check(absf(float(geometry["mask_top"]) - 192.0) < 0.1 \
			and absf(float(geometry["tail_top"]) - 840.0) < 0.1 \
			and float(geometry["body_top"]) >= float(geometry["mask_bottom"]) - 0.6,
			"Hold 按原版规则：mask 跨头中心、repeat 接续、tail 从终点向下展开",
			str(geometry))
	var lane_centers: Array = field.get("_lane_x")
	_check(lane_centers == [202.0, 344.0, 486.0, 628.0, 770.0,
		1150.0, 1292.0, 1434.0, 1576.0, 1718.0],
		"双踏板 10 轨使用原版 1920×1080 精确中心", str(lane_centers))
	var perfect_report = judge_script.JudgeReport.new("tap", 2, "perfect", 0.0, 5000, 1, 1.0, 1.0)
	field.call("on_report", perfect_report)
	_check((field.get("_zone_judge_sprites") as Dictionary).is_empty() \
		and (field.get("_judge_popups") as Array).is_empty(),
		"NoteField 不再额外绘制独立 Perfect，判定只由中央计数组显示")
	var hand_receptors: Array = field.get("_hand_receptors")
	_check(hand_receptors.size() >= 2 and (hand_receptors[0] as Sprite2D).texture != null,
		"手键默认素材真实显示")
	_check(field.has_method("load_hand_events") and field.has_method("hand_target_for_test"),
		"手键具有独立于判定链的运行轨迹加载与锚点接口")
	if field.has_method("load_hand_events") and field.has_method("hand_target_for_test"):
		field.call("load_hand_events", [
			{"dir": "tt", "start_sec": 1.0, "end_sec": 1.0, "type": "tap", "player": 1},
			{"dir": "bb", "start_sec": 1.2, "end_sec": 2.0, "type": "hold", "player": 1},
			{"dir": "ll", "start_sec": 1.4, "end_sec": 1.4, "type": "tap", "player": 1},
			{"dir": "rr", "start_sec": 1.6, "end_sec": 1.6, "type": "tap", "player": 1},
		])
		field.update_field(0.0, 0.016)
		var middle_x := float(lane_centers[2])
		var tt_target: Vector2 = field.call("hand_target_for_test", "tt", 1)
		var bb_target: Vector2 = field.call("hand_target_for_test", "bb", 1)
		var ll_target: Vector2 = field.call("hand_target_for_test", "ll", 1)
		var rr_target: Vector2 = field.call("hand_target_for_test", "rr", 1)
		_check(absf(tt_target.x - middle_x) < 1.0 and absf(bb_target.x - middle_x) < 1.0,
			"上手/下手轨迹与命中特效统一落在中键轨道",
			"tt=%s bb=%s middle=%s" % [tt_target, bb_target, middle_x])
		_check(ll_target.x < middle_x and rr_target.x > float(lane_centers[4]),
			"左右手键仍使用独立左右锚点", "ll=%s rr=%s" % [ll_target, rr_target])
		_check(int(field.call("active_hand_visual_count_for_test")) >= 4,
			"手键 tap/hold 在到达判定线前具有可见运行轨迹",
			str(field.call("active_hand_visual_count_for_test")))
	_check(field.has_method("hand_effect_transform_for_test"),
		"手键击中特效提供方向变换契约")
	if field.has_method("hand_effect_transform_for_test"):
		var ll_transform: Dictionary = field.call("hand_effect_transform_for_test", "ll")
		var rr_transform: Dictionary = field.call("hand_effect_transform_for_test", "rr")
		var tt_transform: Dictionary = field.call("hand_effect_transform_for_test", "tt")
		var bb_transform: Dictionary = field.call("hand_effect_transform_for_test", "bb")
		_check(float(ll_transform["scale_x_sign"]) == 1.0 \
			and float(rr_transform["scale_x_sign"]) == -1.0,
			"右手击中特效相对左手做水平镜像")
		_check(float(tt_transform["rotation_degrees"]) == 90.0 \
			and float(bb_transform["rotation_degrees"]) == -90.0,
			"上手/下手击中特效方向不再颠倒")
	field.call("load_hand_events", [
		{"dir": "rr", "start_sec": 0.0, "end_sec": 1.0, "type": "hold", "player": 1},
	])
	field.update_field(0.2, 0.016)
	_check(field.has_method("active_hand_effect_count_for_test") \
		and int(field.call("active_hand_effect_count_for_test")) == 1,
		"手键 Hold 到达判定线后启动一个循环击中特效")
	field.update_field(1.1, 0.016)
	_check(int(field.call("active_hand_effect_count_for_test")) == 0,
		"手键 Hold 结束后停止并释放循环击中特效")
	_check(field.has_method("set_hand_pressed"), "手键具有按下/松开状态接口")
	if field.has_method("set_hand_pressed"):
		field.call("set_hand_pressed", "ll", 1, true)
		var hand := hand_receptors[0] as Sprite2D
		_check(hand.scale.x > field.call("_note_scale") * 0.9,
			"手键按下后产生可见缩放/高亮")
		field.call("set_hand_pressed", "ll", 1, false)
	field.call("on_report", judge_script.JudgeReport.new("tap", 2, "cool", 86.0, 4000, 1, 1.0, 1.0))
	var timing_hint := field.get_node_or_null("TimingHintP1") as Label
	_check(timing_hint != null and timing_hint.size.x <= 150.0 and timing_hint.size.y <= 42.0 \
		and timing_hint.z_index > combo_group.z_index and timing_hint.text == "+86 ms",
		"延时判定 UI 缩到最小，只显示有符号毫秒差",
		"rect=%s z=%s text=%s" % [timing_hint.get_rect(), timing_hint.z_index, timing_hint.text] if timing_hint else "null")
	_check(timing_hint != null and not timing_hint.has_theme_stylebox_override("normal") \
		and timing_hint.get_theme_constant("outline_size") == 0,
		"延时判定 UI 无边框、无背景、无额外文案")

	# 9.2/9.10：暂停菜单真实隔离输入，局部假 FPS 隐藏，使用全局右下状态条。
	var esc_menu = gameplay.get("esc_menu")
	var local_fps := hud.get_node_or_null("Fps") as Label
	_check(local_fps != null and not local_fps.visible,
		"游戏 HUD 不重复显示左/右上假 FPS，统一使用全局右下状态条")
	esc_menu.open_menu()
	await process_frame
	var menu_root := esc_menu.get_node_or_null("GameplayPauseMenu") as Control
	_check(menu_root != null and menu_root.size == Vector2(1920, 1080) \
		and menu_root.mouse_filter == Control.MOUSE_FILTER_STOP,
		"ESC 暂停菜单全屏隔离底层输入")
	esc_menu.call("_set_tab", 3)
	await process_frame
	_check(esc_menu.has_method("binding_position_for_test"), "键位页提供五键踏板位置契约")
	if esc_menu.has_method("binding_position_for_test"):
		var bl: Vector2 = esc_menu.call("binding_position_for_test", 0, 0)
		var tl: Vector2 = esc_menu.call("binding_position_for_test", 0, 1)
		var cc: Vector2 = esc_menu.call("binding_position_for_test", 0, 2)
		var tr: Vector2 = esc_menu.call("binding_position_for_test", 0, 3)
		var br: Vector2 = esc_menu.call("binding_position_for_test", 0, 4)
		_check(bl.x < cc.x and tl.x < cc.x and tr.x > cc.x and br.x > cc.x \
			and tl.y < cc.y and tr.y < cc.y and bl.y > cc.y and br.y > cc.y,
			"键位设置按原版左上/右上/中心/左下/右下五键几何排列")
	esc_menu.close_menu()

	# 清理。
	field.queue_free()
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
	print("ALL GAMEPLAY VISUAL CONTRACT TESTS PASSED" if _failures == 0 else
		"%d GAMEPLAY VISUAL CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
