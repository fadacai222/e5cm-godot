extends SceneTree
## 原版结算三阶段视觉/交互契约：成绩框、评级/徽章、经验窗和流程3提示。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
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


func _near(control: Control, expected: Rect2, tolerance := 1.2) -> bool:
	return control != null and control.position.distance_to(expected.position) <= tolerance \
		and control.size.distance_to(expected.size) <= tolerance


func _payload(player_index := 1) -> Dictionary:
	return {
		"玩家序号": player_index,
		"曲目名": "结算契约测试曲",
		"sm_key": "qa/settlement-contract.sm",
		"mode": "竞速",
		"submode": "club",
		"cover": "",
		"star": 12,
		"本局最高分": 987654,
		"本局最大combo": 432,
		"歌曲时长秒": 60.0,
		"百分比": "96.20%",
		"百分比数值": 96.2,
		"评级": "S",
		"失败": false,
		"当前关卡": 1,
		"结算后S数": 1,
		"三把S赠送": false,
		"是否赠送第四把": false,
		"perfect数": 300,
		"cool数": 20,
		"good数": 2,
		"miss数": 0,
		"是否全perfect": false,
		"是否全连": true,
	}


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame
	var profile_store = root.get_node("ProfileStore")
	profile_store.persist_enabled = false
	profile_store.profile = profile_store.call("_default_profile")
	profile_store.records = {}
	root.get_node("GameState").persist_credits = false
	root.get_node("GameState").credits = 3
	root.get_node("SceneRouter").payload = _payload(1)

	var settlement := (load("res://scenes/settlement/settlement.tscn") as PackedScene).instantiate() as Control
	root.add_child(settlement)
	await process_frame

	var stored_speed: Dictionary = profile_store.get_mode_progress("竞速")
	var displayed_speed: Dictionary = profile_store.get_mode_progress_for_display("竞速")
	_check(int(stored_speed.get("等级", 0)) == 5 \
		and absf(float(stored_speed.get("经验", 0.0)) - 3.0) < 0.01 \
		and int(stored_speed.get("累计歌曲", 0)) == 1,
		"第一把经验立即写入正式存档并累计歌曲数", str(stored_speed))
	_check(displayed_speed == stored_speed,
		"个人中心直接读取正式进度，不再依赖易丢失的内存预览", str(displayed_speed))

	# 阶段一：所有坐标均来自原版 1600×900 布局 ×1.2。
	_check(_near(settlement.get_node_or_null("SettlementPanel") as Control,
		Rect2(115.2, 120.0, 840.0, 840.0)), "1P 成绩玩家框使用原版位置与尺寸")
	var settlement_identity := settlement.get_node_or_null("SettlementPlayerIdentity") as Control
	_check(settlement_identity != null and settlement_identity.position.x >= 1490.0
		and settlement_identity.position.x + settlement_identity.size.x <= 1920.0,
		"结算身份卡位于右侧安全区且不覆盖原成绩面板")
	var grade := settlement.get_node("GradeSprite") as TextureRect
	_check(grade.size.distance_to(Vector2(190.8, 165.6)) <= 1.2
		and (settlement.get("_grade_target_position") as Vector2).distance_to(Vector2(211.2, 739.2)) <= 1.2,
		"主评级图使用原版 grade_main 目标矩形",
		"target=%s size=%s" % [settlement.get("_grade_target_position"), grade.size])
	_check(grade.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"评级贴图保持素材比例")

	var expected_rects := {
		"Miss": Rect2(561.6, 356.4, 254.4, 60.0),
		"Good": Rect2(554.4, 417.6, 261.6, 64.8),
		"Cool": Rect2(554.4, 483.6, 261.6, 64.8),
		"Perfect": Rect2(554.4, 548.4, 261.6, 64.8),
		"Combo": Rect2(554.4, 615.6, 261.6, 64.8),
		"Accuracy": Rect2(562.8, 688.8, 280.8, 60.0),
		"Score": Rect2(552.0, 804.0, 302.4, 60.0),
	}
	for node_name in expected_rects:
		var slot := settlement.get_node_or_null(node_name) as Control
		_check(_near(slot, expected_rects[node_name]), "%s 数字槽使用原版矩形" % node_name,
			str(slot.get_rect()) if slot else "null")
		var label := slot.get_node_or_null("Value") as Label if node_name == "Score" and slot != null \
			else slot as Label
		_check(label != null and label.clip_text == false, "%s 数字不截断高位" % node_name)
	var score := settlement.get_node("Score/Value") as Label
	_check(score.get_theme_font_size("font_size") == 53
		and score.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"总分使用原版 44px×1.2 字号并居中", str(score.get_theme_font_size("font_size")))
	var miss := settlement.get_node("Miss") as Label
	_check(miss.get_theme_font_size("font_size") == 36
		and miss.get_theme_color("font_outline_color").is_equal_approx(Color8(166, 19, 27)),
		"MISS 数字使用原版字号和红色描边")

	# 数值完成后：评级、全连徽章、新纪录按独立原版槽位入场。
	settlement.set("_t", 3.0)
	settlement.call("_update_phase1")
	var top_badge := settlement.get_node_or_null("TopStatusBadge") as TextureRect
	var new_record := settlement.get_node_or_null("NewRecordBadge") as TextureRect
	_check(_near(top_badge, Rect2(160.8, 139.2, 753.6, 223.2)),
		"全连/失败徽章使用原版 top_badge 槽位",
		str(top_badge.get_rect()) if top_badge else "null")
	_check(top_badge != null and top_badge.visible and top_badge.texture != null,
		"全连局显示原版全连徽章")
	_check(_near(new_record, Rect2(564.0, 58.8, 559.2, 140.4)),
		"新纪录使用原版 new_record 槽位",
		str(new_record.get_rect()) if new_record else "null")
	_check(new_record != null and new_record.visible, "新最高分显示新纪录徽章")

	# 阶段二：经验窗不再占满屏幕，数字、三模式经验条、段位图按紧凑布局显示。
	settlement.set("_exp_result", {
		"显示奖励窗": true,
		"正式局总经验": 135,
		"正式局歌曲": [{"评级": "S", "基础经验": 15, "连续S倍率": 3,
			"奖励倍率": 3.0, "最终经验": 135}],
		"经验结算": {"原等级": 4, "等级": 6, "原经验": 2.0, "经验": 3.0,
			"等级所需经验": 5, "是否升级": true, "升级次数": 2},
	})
	settlement.call("_enter_phase2")
	await process_frame
	var reward := settlement.get_node_or_null("ExperienceRewardPanel/RewardWindow") as TextureRect
	_check(_near(reward, Rect2(686.4, 294.0, 770.4, 451.2)),
		"经验奖励窗扩高后完整容纳三条经验进度", str(reward.get_rect()) if reward else "null")
	var exp_digits := settlement.get_node_or_null("ExperienceRewardPanel/RewardWindow/ExpDigits") as Control
	_check(_near(exp_digits, Rect2(283.2, 19.2, 187.2, 114.0)),
		"奖励经验数字使用原版 reward_digits 局部矩形",
		str(exp_digits.get_rect()) if exp_digits else "null")
	_check(reward != null and reward.get_node_or_null("StyleExperienceBarFrame") != null
		and reward.get_node_or_null("SpeedExperienceBarFrame") != null
		and reward.get_node_or_null("DiyExperienceBarFrame") != null,
		"经验窗同时显示花式、竞速与 DIY 三条经验条")
	_check(reward != null and reward.get_node_or_null("RankIcon") != null,
		"经验窗包含段位徽章槽")
	_check(reward != null and reward.get_node_or_null("LevelUpEffect") != null,
		"跨多级经验结算显示升级动画层")
	var style_frame := reward.get_node_or_null("StyleExperienceBarFrame") as TextureRect if reward else null
	var style_clip := reward.get_node_or_null("StyleExperienceBarFillClip") as Control if reward else null
	var style_fill := style_clip.get_node_or_null("StyleExperienceBarFill") as TextureRect \
		if style_clip != null else null
	_check(style_frame != null and style_clip != null and style_fill != null \
		and style_clip.position.distance_to(style_frame.position) < 0.1 \
		and absf(style_clip.size.y - style_frame.size.y) < 0.1 \
		and style_fill.size.distance_to(style_frame.size) < 0.1,
		"结算经验填充纹理与外框使用同一完整矩形",
		"frame=%s clip=%s fill=%s" % [style_frame.get_rect(), style_clip.get_rect(), style_fill.get_rect()] \
			if style_frame and style_clip and style_fill else "missing")
	var speed_clip := reward.get_node_or_null("SpeedExperienceBarFillClip") as Control if reward else null
	var speed_frame := reward.get_node_or_null("SpeedExperienceBarFrame") as TextureRect if reward else null
	_check(speed_clip != null and speed_frame != null \
		and speed_clip.position.distance_to(speed_frame.position) < 0.1 \
		and absf(speed_clip.size.y - speed_frame.size.y) < 0.1,
		"动画经验条从外框左边界开始且高度完全一致")
	var diy_clip := reward.get_node_or_null("DiyExperienceBarFillClip") as Control if reward else null
	var diy_frame := reward.get_node_or_null("DiyExperienceBarFrame") as Control if reward else null
	var diy_background := reward.get_node_or_null("DiyExperienceBarBackground") as Control if reward else null
	var diy_level := reward.get_node_or_null("DiyLevelLabel") as Label if reward else null
	var diy_label := reward.get_node_or_null("DiyExperienceLabel") as Label if reward else null
	_check(diy_clip != null and diy_frame != null and diy_background != null \
		and diy_level != null and diy_label != null and diy_label.size.x >= 120.0 \
		and diy_clip.position.distance_to(diy_frame.position) < 0.1 \
		and diy_background.get_rect() == diy_frame.get_rect() \
		and diy_frame.position.y > speed_frame.position.y \
		and diy_frame.position.y + diy_frame.size.y <= reward.size.y,
		"DIY 第三经验条位于竞速条下方、标题不截断且不溢出奖励窗",
		"clip=%s frame=%s reward=%s" % [diy_clip.get_rect(), diy_frame.get_rect(), reward.get_rect()] \
			if diy_clip and diy_frame and reward else "missing")
	var initial_exp_width := speed_clip.size.x if speed_clip else -1.0
	await create_timer(1.55).timeout
	var level_up_effect := reward.get_node_or_null("LevelUpEffect") as TextureRect if reward else null
	_check(speed_clip != null and absf(speed_clip.size.x - initial_exp_width) > 2.0,
		"第三把结算经验条按进度片段真实增长",
		"before=%.1f after=%.1f" % [initial_exp_width, speed_clip.size.x] if speed_clip else "null")
	_check(bool(settlement.get("_upgrade_started")) and level_up_effect != null \
		and level_up_effect.visible and level_up_effect.modulate.a > 0.05,
		"经验条跨级时真实触发升级动画，而非仅创建隐藏节点")
	var upgrade_flower_names := [
		"LevelUpFlowerLeftTop", "LevelUpFlowerRightTop",
		"LevelUpFlowerLeftBottom", "LevelUpFlowerRightBottom",
	]
	var visible_flower_count := 0
	var all_flowers_behind := true
	for flower_name in upgrade_flower_names:
		var flower := reward.get_node_or_null(flower_name) as TextureRect if reward else null
		if flower != null and flower.visible and flower.modulate.a > 0.05:
			visible_flower_count += 1
		if flower == null or level_up_effect == null or flower.z_index >= level_up_effect.z_index:
			all_flowers_behind = false
	_check(visible_flower_count == 4 and all_flowers_behind,
		"升级动画包含四朵花纹并从主升级图后方冒出",
		"visible=%d behind=%s" % [visible_flower_count, str(all_flowers_behind)])

	# DIY 局必须把经验增长动画落到第三条，而不是继续误用竞速条。
	(settlement.get("payload") as Dictionary)["mode"] = "DIY"
	settlement.set("_exp_result", {
		"显示奖励窗": true,
		"正式局总经验": 3,
		"经验结算": {"原等级": 3, "等级": 3, "原经验": 1.0, "经验": 4.0,
			"等级所需经验": 5, "是否升级": false, "升级次数": 0},
	})
	settlement.call("_enter_phase2")
	await process_frame
	var diy_reward := settlement.get_node_or_null("ExperienceRewardPanel/RewardWindow") as TextureRect
	var active_diy_clip := diy_reward.get_node_or_null("DiyExperienceBarFillClip") as Control \
		if diy_reward else null
	var active_speed_clip := diy_reward.get_node_or_null("SpeedExperienceBarFillClip") as Control \
		if diy_reward else null
	var initial_diy_width := active_diy_clip.size.x if active_diy_clip else -1.0
	var initial_speed_width := active_speed_clip.size.x if active_speed_clip else -1.0
	await create_timer(1.55).timeout
	_check(active_diy_clip != null and active_speed_clip != null \
		and active_diy_clip.size.x > initial_diy_width + 2.0 \
		and absf(active_speed_clip.size.x - initial_speed_width) < 0.1,
		"DIY 结算只驱动第三条经验增长动画",
		"diy %.1f->%.1f speed %.1f->%.1f" % [initial_diy_width, active_diy_clip.size.x,
			initial_speed_width, active_speed_clip.size.x] if active_diy_clip and active_speed_clip else "missing")

	# 第 1/2 把必须明确告诉玩家已落盘，并允许正式升级动画立即出现。
	(settlement.get("payload") as Dictionary)["mode"] = "竞速"
	settlement.set("_exp_result", {
		"显示奖励窗": true, "预览缓存": false, "缓存把数": 2,
		"经验增加值": 60, "正式局总经验": 90,
		"经验结算": {"原等级": 7, "等级": 16, "原经验": 0.0, "经验": 0.0,
			"等级所需经验": 5, "是否升级": true, "升级次数": 9},
	})
	settlement.call("_enter_phase2")
	await process_frame
	var persistence_hint := settlement.get_node_or_null(
		"ExperienceRewardPanel/RewardWindow/ExperiencePersistenceHint") as Label
	var persisted_upgrade := settlement.get_node_or_null(
		"ExperienceRewardPanel/RewardWindow/LevelUpEffect") as TextureRect
	_check(persistence_hint != null and persistence_hint.text.contains("第 2 / 3 把") \
		and persistence_hint.text.contains("已写入存档") \
		and persistence_hint.text.contains("+90"),
		"第1/2把结算明确显示经验已经持久化及本局累计值",
		persistence_hint.text if persistence_hint else "missing")
	_check(persisted_upgrade != null,
		"单曲正式入账跨级时立即创建升级动画")

	# 阶段三：第 1/2 把的 NEXT STAGE 必须先切成独立全黑场。
	(settlement.get("payload") as Dictionary)["当前关卡"] = 1
	(settlement.get("payload") as Dictionary)["失败"] = false
	settlement.call("_enter_phase3")
	await process_frame
	var next_stage_blackout := settlement.get_node_or_null("Phase3Blackout") as ColorRect
	var next_stage_prompt := settlement.get_node_or_null("Phase3Prompt") as TextureRect
	_check(str(settlement.get("_p3_type")) == "自动提示" \
		and next_stage_blackout != null and next_stage_blackout.visible \
		and next_stage_prompt != null and next_stage_prompt.visible and next_stage_prompt.texture != null,
		"第1把成功后 NEXT STAGE 在纯黑场上独立显示")

	# 第三把结算进入“继续挑战”分支，核对提示、倒计时和默认焦点。
	(settlement.get("payload") as Dictionary)["当前关卡"] = 3
	settlement.call("_enter_phase3")
	await process_frame
	var blackout := settlement.get_node_or_null("Phase3Blackout") as ColorRect
	var prompt := settlement.get_node("Phase3Prompt") as TextureRect
	var countdown_digits := settlement.get_node_or_null("Phase3CountdownDigits") as Control
	var yes_button := settlement.get_node("Phase3Yes") as TextureButton
	var no_button := settlement.get_node("Phase3No") as TextureButton
	_check(blackout != null and blackout.visible and blackout.color.is_equal_approx(Color.BLACK) \
		and blackout.position.distance_to(Vector2.ZERO) < 0.1 \
		and blackout.size.distance_to(settlement.size) < 0.1 \
		and blackout.z_index < prompt.z_index,
		"NEXT STAGE 使用全屏纯黑独立底层而非叠加在结算画面上",
		"blackout=%s prompt_z=%d" % [blackout.get_rect(), prompt.z_index] if blackout else "missing")
	_check(_near(prompt, Rect2(376.8, 368.4, 1189.2, 223.2)),
		"流程3提示使用原版 flow3_prompt 槽位", str(prompt.get_rect()))
	_check(countdown_digits != null and countdown_digits.visible,
		"流程3倒计时使用原版数字图集而非系统字体")
	_check(yes_button.position.y + yes_button.size.y <= 1080.0
		and no_button.position.y + no_button.size.y <= 1080.0,
		"是/否按钮完整位于 1080p 可视区域")
	_check(yes_button.visible and yes_button.modulate != Color.WHITE,
		"继续挑战默认焦点为“是”")

	# 结算音效播完后必须接回 UI BGM，不能让结算后半段静音。
	settlement.set("_t", float(settlement.get("_settlement_sfx_duration")) + 0.01)
	settlement.call("_update_settlement_audio")
	var audio_director = root.get_node("AudioDirector")
	_check(bool(settlement.get("_settlement_bgm_started")) \
		and audio_director.call("current_bgm_path_for_test") == root.get_node("AssetLoader").sound("音乐_UI"),
		"结算音效结束后自动继续播放循环 UI BGM",
		str(audio_director.call("current_bgm_path_for_test")))

	# 2P 玩家框应镜像到右侧，而不是与 1P 重叠。
	settlement.free()
	profile_store.records = {}
	root.get_node("SceneRouter").payload = _payload(2)
	var settlement_p2 := (load("res://scenes/settlement/settlement.tscn") as PackedScene).instantiate() as Control
	root.add_child(settlement_p2)
	await process_frame
	_check(_near(settlement_p2.get_node("SettlementPanel") as Control,
		Rect2(964.8, 120.0, 840.0, 840.0)), "2P 成绩玩家框镜像到右侧")

	settlement_p2.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL SETTLEMENT VISUAL CONTRACT TESTS PASSED" if _failures == 0 else
		"%d SETTLEMENT VISUAL CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
