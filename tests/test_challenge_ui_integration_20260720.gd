extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _caps() -> Dictionary:
	return {
		"modes": {
			"花式": {"count": 4, "stars": [4, 8]},
			"竞速": {"count": 4, "stars": [5, 10]},
			"DIY": {"count": 4, "stars": [4, 9]},
		},
		"has_unplayed": true,
		"has_breakable_record": true,
		"has_random_source": false,
		"two_player": false,
	}

func _prepare_state() -> void:
	var service = root.get_node("ChallengeService")
	var date := Time.get_date_string_from_system()
	var week: String = str(service.iso_week_key(date))
	service.initialize_for_test("ui-profile", date, week,
		int(Time.get_unix_time_from_system()), int(Time.get_time_zone_from_system().get("bias", 0)),
		_caps(), 20)
	var state: Dictionary = service.snapshot()
	var daily: Array = state.get("daily", [])
	daily[0] = {
		"id": "daily-ui-clear", "period": "daily", "template_id": "clear_any",
		"category": "clear", "difficulty": "normal", "params": {}, "target": 1,
		"progress": 0.0, "completed": false, "claimed": false,
		"reward_id": "frame_neon_cyan", "description": "完成任意一首歌曲",
		"catalog_version": 1, "eligibility_version": 1,
	}
	state["daily"] = daily
	service.replace_state_for_test(state)

func _run() -> void:
	var service = root.get_node("ChallengeService")
	var rewards = root.get_node("RewardService")
	service.persist_enabled = false
	rewards.persist_enabled = false
	rewards.reset_for_test()
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("AnalyticsStore").persist_enabled = false
	_prepare_state()

	var mode_select: Control = load("res://scenes/mode_select/mode_select.tscn").instantiate()
	root.add_child(mode_select)
	await process_frame
	var rail := mode_select.get_node_or_null("TopBar/FeatureQuickAccessRail") as Control
	var mode_esc = mode_select.get_node_or_null("FeatureEscMenu")
	_check(rail != null and rail.get_node_or_null("ChallengeEntry") != null,
		"大模式选择页显示统一今日挑战入口")
	mode_select.call("_open_challenge_center")
	await process_frame
	_check(mode_esc != null and bool(mode_esc.call("is_open")), "挑战入口打开统一 ESC 菜单")
	_check(mode_esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/ChallengeDashboard/DailyColumn/TaskRow0") != null,
		"ESC 挑战页显示每日任务卡片")
	_check(mode_esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/ChallengeDashboard/WeeklyColumn/TaskRow0") != null,
		"ESC 挑战页显示周常任务卡片")
	mode_esc.call("close_menu")
	root.remove_child(mode_select)
	mode_select.free()

	rewards.grant("frame_neon_cyan", "ui-test")
	var profile: Control = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(profile)
	await process_frame
	_check(profile.get_node_or_null("MyRewardsButton") != null, "个人中心提供我的奖励入口")
	var profile_avatar := profile.get_node_or_null("ProfileAvatar") as TextureRect
	var avatar_material := profile_avatar.material as ShaderMaterial if profile_avatar else null
	var profile_reward_frame := profile.get_node_or_null("EquippedAvatarFrame") as Control
	_check(avatar_material != null and avatar_material.shader != null
		and avatar_material.shader.resource_path == "res://fx/circular_avatar_mask.gdshader",
		"个人中心头像使用圆形裁切，不再显示方形头像")
	var profile_hole: Rect2 = profile_reward_frame.call("avatar_hole_rect_for_test") \
		if profile_reward_frame != null else Rect2()
	_check(profile_reward_frame != null and profile_reward_frame.size.x > profile_avatar.size.x + 40.0
		and profile_hole.get_center().distance_to(profile_avatar.get_rect().get_center()) < 1.0
		and absf(profile_hole.size.x - (profile_avatar.size.x - 6.0)) < 2.0,
		"个人中心奖励头像框按透明孔径包住头像边缘",
		"avatar=%s frame=%s hole=%s" % [profile_avatar.get_rect(), profile_reward_frame.get_rect(), profile_hole])
	profile.call("_open_rewards")
	await process_frame
	var reward_overlay := profile.get_node_or_null("RewardInventoryOverlay")
	_check(reward_overlay != null, "个人中心可查看奖励库存")
	var reward_row := reward_overlay.get_node_or_null("RewardInventoryPanel/RewardRow0") as Button
	_check(reward_row != null and reward_row.get_node_or_null("Thumbnail") != null,
		"奖励库存卡片显示独立奖励缩略图")
	profile.call("_close_rewards")
	root.remove_child(profile)
	profile.free()

	rewards.reset_for_test()
	_prepare_state()
	root.get_node("SceneRouter").payload = {
		"run_id": "challenge-settlement-run-1", "challenge_eligible": true,
		"autoplay": false, "debug_run": false, "random_song": false, "players": 1,
		"hidden_mode": "关闭", "track_mode": "正常", "direction_mode": "关闭",
		"曲目名": "挑战测试曲", "sm_key": "challenge-test-chart", "mode": "竞速",
		"submode": "club", "cover": "", "star": 10, "本局最高分": 800000,
		"本局最大combo": 180, "歌曲时长秒": 120.0, "百分比": "97.00%",
		"百分比数值": 97.0, "评级": "S", "失败": false, "当前关卡": 1,
		"结算后S数": 1, "三把S赠送": false, "是否赠送第四把": false,
		"perfect数": 500, "cool数": 20, "good数": 1, "miss数": 0,
		"是否全perfect": false, "是否全连": true,
	}
	var settlement: Control = load("res://scenes/settlement/settlement.tscn").instantiate()
	root.add_child(settlement)
	await process_frame
	var changes: Array = settlement.get("_challenge_changes")
	_check(not changes.is_empty(), "正式结算提交标准 RunResult 并推进挑战")
	_check(rewards.owns("frame_neon_cyan"), "挑战完成后奖励自动入库")
	var state_after: Dictionary = service.snapshot()
	_check(bool((state_after.get("daily", []) as Array)[0].get("completed", false)),
		"结算后的挑战状态标记完成")
	settlement.call("_enter_phase2")
	await process_frame
	var popup := settlement.get_node_or_null("ChallengeProgressPopup")
	_check(popup != null and popup.visible, "经验阶段显示非阻塞挑战推进提示")
	var before_t := float(settlement.get("_t"))
	settlement.call("_process", 0.5)
	_check(float(settlement.get("_t")) > before_t, "挑战提示不会冻结或延长结算流程")
	root.remove_child(settlement)
	settlement.free()
	root.get_node("SceneRouter").payload = {}
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.1).timeout
	quit(1 if failures > 0 else 0)
