extends SceneTree

const RewardCenterScript := preload("res://ui/reward_center.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _run() -> void:
	var rewards = root.get_node("RewardService")
	rewards.persist_enabled = false
	rewards.reset_for_test()
	rewards.unlock("title_daily_rookie", "center-title", "test")
	rewards.unlock("frame_neon_cyan", "center-frame", "test")
	rewards.unlock("card_grid_blue", "center-card", "test")

	var center: RewardCenter = RewardCenterScript.new()
	center.name = "RewardInventoryPanel"
	center.size = Vector2(1560, 900)
	root.add_child(center)
	await process_frame
	_check(center.get_node_or_null("RewardPreviewIdentity") != null,
		"奖励中心使用统一完整玩家身份预览")
	_check(center.get_node_or_null("RewardRow0") != null,
		"奖励中心显示奖励目录条目")
	_check(RewardCatalog.rarity_display_name("common") == "普通"
		and RewardCatalog.rarity_display_name("rare") == "稀有"
		and RewardCatalog.rarity_display_name("epic") == "史诗"
		and RewardCatalog.rarity_display_name("legendary") == "传说",
		"奖励稀有度统一提供中文显示名")
	var first_meta := center.get_node_or_null("RewardRow0/RewardMeta") as Label
	_check(first_meta != null and not first_meta.text.contains("COMMON")
		and not first_meta.text.contains("RARE") and not first_meta.text.contains("EPIC")
		and not first_meta.text.contains("LEGENDARY"),
		"奖励列表不再显示英文稀有度", first_meta.text if first_meta else "missing")
	_check(center.get_node_or_null("Ownershipowned") != null
		and center.get_node_or_null("Ownershiplocked") != null
		and center.get_node_or_null("Typeavatar_frame") != null,
		"奖励中心提供拥有状态与类型筛选")
	_check(center.get_node_or_null("UnreadSummary") != null
		and not (center.get_node("UnreadSummary") as Label).text.is_empty(),
		"奖励中心显示新奖励红点摘要")
	_check(center.has_method("_step_focus") and not (center.get("_focus_buttons") as Array).is_empty(),
		"奖励中心建立键盘与踏板焦点循环")

	center.call("_select_reward", "frame_neon_cyan", false)
	await process_frame
	var detail_title := center.get("_detail_title") as Label
	_check(detail_title != null and detail_title.text.ends_with("/  普通"),
		"奖励详情标题显示中文稀有度", detail_title.text if detail_title else "missing")
	var action := center.get_node("RewardActionButton") as Button
	_check(not action.disabled and action.text == "装备",
		"已拥有奖励可在预览后装备")
	action.pressed.emit()
	await process_frame
	_check(rewards.equipped("avatar_frame") == "frame_neon_cyan",
		"奖励中心装备动作写入正式头像框槽位")
	center.call("_select_reward", "frame_neon_cyan", false)
	await process_frame
	_check((center.get_node("RewardActionButton") as Button).text == "取消装备",
		"已装备奖励提供取消装备动作")
	(center.get_node("RewardActionButton") as Button).pressed.emit()
	await process_frame
	_check(rewards.equipped("avatar_frame").is_empty(),
		"取消装备恢复默认头像框")

	center.call("_set_ownership_filter", "locked")
	await process_frame
	_check(center.get_node_or_null("RewardRow0") != null,
		"未解锁筛选显示可获取奖励及条件")
	center.call("_set_type_filter", "profile_card")
	await process_frame
	_check(center.get_node_or_null("RewardRow0") != null,
		"玩家卡类型筛选可用")

	# 五个实际展示面必须存在统一奖励节点。
	var song_select: Control = load("res://scenes/song_select/song_select.gd").new()
	var top_bar := Control.new()
	top_bar.name = "TopBar"
	top_bar.size = Vector2(1920, 150)
	song_select.add_child(top_bar)
	song_select.call("_build_top_profile_badge", top_bar)
	var song_identity := top_bar.get_node_or_null("SongSelectProfileBadge")
	_check(song_identity != null and song_identity.get_node_or_null("RewardAvatarFrame") != null
		and song_identity.get_node_or_null("TitleBadge") != null,
		"选歌玩家卡真实消费称号与头像框")
	song_select.free()

	var esc = load("res://ui/esc_menu.gd").new(false)
	root.add_child(esc)
	await process_frame
	esc.call("_set_tab", 4)
	await process_frame
	_check(esc.get_node_or_null("ModernMenu/ContentPanel/ContentBody/ProfileIdentityCard/EquippedAvatarFrame") != null
		and esc.get_node_or_null("ModernMenu/ContentPanel/ContentBody/ProfileIdentityCard/EquippedTitleBadge") != null,
		"ESC 用户信息真实显示装备外观")
	root.remove_child(esc)
	esc.free()

	var profile: Control = load("res://scenes/profile/profile.tscn").instantiate()
	root.add_child(profile)
	await process_frame
	_check(profile.get_node_or_null("EquippedAvatarFrame") != null
		and profile.get_node_or_null("EquippedTitleBadge") != null,
		"个人中心主页面真实显示装备外观")
	root.remove_child(profile)
	profile.free()

	# Gameplay/Settlement 用源码和场景冒烟共同保证，不启动真实长音频流程。
	var gameplay_text := FileAccess.get_file_as_string("res://scenes/gameplay/gameplay.gd")
	var settlement_text := FileAccess.get_file_as_string("res://scenes/settlement/settlement.gd")
	_check(gameplay_text.contains("EquippedRewardAvatarFrame")
		and gameplay_text.contains("EquippedRewardTitleBadge"),
		"Gameplay HUD 接入独立奖励层")
	_check(settlement_text.contains("SettlementPlayerIdentity"),
		"结算安全区接入统一玩家身份卡")

	root.remove_child(center)
	center.free()
	rewards.reset_for_test()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.1).timeout
	quit(1 if failures > 0 else 0)
