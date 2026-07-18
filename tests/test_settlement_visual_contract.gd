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

	# 阶段一：所有坐标均来自原版 1600×900 布局 ×1.2。
	_check(_near(settlement.get_node_or_null("SettlementPanel") as Control,
		Rect2(115.2, 120.0, 840.0, 840.0)), "1P 成绩玩家框使用原版位置与尺寸")
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

	# 阶段二：经验窗不再占满屏幕，数字、双模式经验条、段位图按原版布局。
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
	_check(_near(reward, Rect2(686.4, 326.4, 770.4, 386.4)),
		"经验奖励窗使用原版 reward_bg 矩形", str(reward.get_rect()) if reward else "null")
	var exp_digits := settlement.get_node_or_null("ExperienceRewardPanel/RewardWindow/ExpDigits") as Control
	_check(_near(exp_digits, Rect2(283.2, 19.2, 187.2, 114.0)),
		"奖励经验数字使用原版 reward_digits 局部矩形",
		str(exp_digits.get_rect()) if exp_digits else "null")
	_check(reward != null and reward.get_node_or_null("StyleExperienceBarFrame") != null
		and reward.get_node_or_null("SpeedExperienceBarFrame") != null,
		"经验窗同时显示花式与竞速两条原版经验条")
	_check(reward != null and reward.get_node_or_null("RankIcon") != null,
		"经验窗包含段位徽章槽")
	_check(reward != null and reward.get_node_or_null("LevelUpEffect") != null,
		"跨多级经验结算显示升级动画层")
	var speed_clip := reward.get_node_or_null("SpeedExperienceBarFillClip") as Control if reward else null
	var initial_exp_width := speed_clip.size.x if speed_clip else -1.0
	await create_timer(1.55).timeout
	var level_up_effect := reward.get_node_or_null("LevelUpEffect") as TextureRect if reward else null
	_check(speed_clip != null and absf(speed_clip.size.x - initial_exp_width) > 2.0,
		"第三把结算经验条按进度片段真实增长",
		"before=%.1f after=%.1f" % [initial_exp_width, speed_clip.size.x] if speed_clip else "null")
	_check(bool(settlement.get("_upgrade_started")) and level_up_effect != null \
		and level_up_effect.visible and level_up_effect.modulate.a > 0.05,
		"经验条跨级时真实触发升级动画，而非仅创建隐藏节点")

	# 第 1/2 把虽不写存档，也必须展示缓存经验增长，避免玩家误以为经验系统失效。
	settlement.set("_exp_result", {
		"显示奖励窗": true, "预览缓存": true, "缓存把数": 2,
		"正式局总经验": 90,
		"经验结算": {"原等级": 1, "等级": 10, "原经验": 0.0, "经验": 0.0,
			"等级所需经验": 5, "是否升级": true, "升级次数": 9},
	})
	settlement.call("_enter_phase2")
	await process_frame
	var cached_hint := settlement.get_node_or_null(
		"ExperienceRewardPanel/RewardWindow/CachedExperienceHint") as Label
	var cached_upgrade := settlement.get_node_or_null(
		"ExperienceRewardPanel/RewardWindow/LevelUpEffect") as TextureRect
	_check(cached_hint != null and cached_hint.text.contains("第 2 / 3 把") \
		and cached_hint.text.contains("已缓存"),
		"第1/2把结算明确显示经验已缓存、第三把统一入账",
		cached_hint.text if cached_hint else "missing")
	_check(cached_upgrade == null,
		"缓存经验预览不伪造正式升级动画")

	# 阶段三：用第三把结算进入“继续挑战”分支，核对提示、倒计时和默认焦点。
	(settlement.get("payload") as Dictionary)["当前关卡"] = 3
	settlement.call("_enter_phase3")
	await process_frame
	var prompt := settlement.get_node("Phase3Prompt") as TextureRect
	var countdown_digits := settlement.get_node_or_null("Phase3CountdownDigits") as Control
	var yes_button := settlement.get_node("Phase3Yes") as TextureButton
	var no_button := settlement.get_node("Phase3No") as TextureButton
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
