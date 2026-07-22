extends SceneTree
## 快捷入口与 ESC 信息架构回归：大模式/选歌共用入口组件，挑战和奖励归入 ESC。

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _run() -> void:
	var rewards = root.get_node("RewardService")
	var challenges = root.get_node("ChallengeService")
	rewards.persist_enabled = false
	challenges.persist_enabled = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	rewards.reset_for_test()
	rewards.grant("frame_neon_cyan", "ui-contract")
	rewards.grant("title_daily_rookie", "ui-contract")

	var mode_select: Control = load("res://scenes/mode_select/mode_select.tscn").instantiate()
	root.add_child(mode_select)
	await process_frame
	var mode_rail := mode_select.get_node_or_null("TopBar/FeatureQuickAccessRail") as Control
	_check(mode_rail != null, "大模式页使用共享快捷入口组件")
	_check(mode_rail != null and mode_rail.get_node_or_null("TrainingEntry") != null \
		and mode_rail.get_node_or_null("ChallengeEntry") != null,
		"大模式页快捷入口同时包含训练室和今日挑战")
	_check(mode_rail != null and mode_rail.get_parent() == mode_select.get_node("TopBar") \
		and mode_rail.position.y < 30.0 and mode_rail.position.x + mode_rail.size.x <= 1890.0,
		"大模式页快捷入口收进顶栏且不压住中央模式横幅")
	_check(mode_select.get_node_or_null("TrainingRoomButton") == null \
		and mode_select.get_node_or_null("ChallengeCenterButton") == null,
		"大模式页移除旧普通按钮入口")
	if mode_rail != null:
		mode_rail.call("emit_training_for_test")
		_check(root.get_node("TrainingSession").is_entry_armed(), "共享训练入口可切换训练选歌状态")
		mode_rail.call("emit_challenge_for_test")
		await process_frame
		var mode_esc = mode_select.get_node_or_null("FeatureEscMenu")
		_check(mode_esc != null and bool(mode_esc.call("is_open")), "大模式页挑战入口打开统一 ESC 菜单")
		_check(mode_esc != null and int(mode_esc.call("active_tab_for_test")) == 5,
			"大模式页挑战入口直达 ESC 今日挑战页")
		if mode_esc != null:
			mode_esc.call("close_menu")
	root.remove_child(mode_select)
	mode_select.free()
	root.get_node("TrainingSession").cancel_entry()

	var song_select: Control = load("res://scenes/song_select/song_select.tscn").instantiate()
	root.add_child(song_select)
	await process_frame
	await process_frame
	var song_rail := song_select.get_node_or_null("TopBar/FeatureQuickAccessRail") as Control
	_check(song_rail != null, "选歌页加入共享快捷入口组件")
	_check(song_rail != null and song_rail.get_node_or_null("TrainingEntry") != null \
		and song_rail.get_node_or_null("ChallengeEntry") != null,
		"选歌页快捷入口同时包含训练室和今日挑战")
	var profile_badge := song_select.get_node_or_null("TopBar/SongSelectProfileBadge") as Control
	_check(song_rail != null and profile_badge != null \
		and song_rail.position.x + song_rail.size.x < profile_badge.position.x,
		"选歌页快捷入口位于玩家资料左侧且互不重叠")
	if song_rail != null:
		song_rail.call("emit_challenge_for_test")
		await process_frame
		var song_esc = song_select.get("esc_menu")
		_check(song_esc != null and bool(song_esc.call("is_open")), "选歌页挑战入口打开现有 ESC 菜单")
		_check(song_esc != null and int(song_esc.call("active_tab_for_test")) == 5,
			"选歌页挑战入口直达今日挑战页")
		_check(song_esc != null and song_esc.get_node_or_null(
			"ModernMenu/ContentPanel/ContentBody/ChallengeDashboard") != null,
			"今日挑战成为 ESC 菜单正式内容页")
		if song_esc != null:
			song_esc.call("_set_tab", 4)
			await process_frame
			var backpack := song_esc.get_node_or_null(
				"ModernMenu/ContentPanel/ContentBody/ProfileProgressCard/MyBackpackButton") as Button
			_check(backpack != null and backpack.size.y >= 72.0,
				"ESC 用户信息页使用单一我的背包入口，不再内嵌奖励装配卡片")
			_check(song_esc.get_node_or_null(
				"ModernMenu/ContentPanel/ContentBody/ProfileProgressCard/ProfileRewardCard") == null,
				"ESC 用户信息页已移除旧奖励卡片式装配区")
			if backpack != null:
				backpack.pressed.emit()
				await process_frame
				var center := song_esc.get_node_or_null(
					"RewardInventoryOverlay/RewardInventoryPanel") as Control
				_check(center != null, "点击我的背包打开完整奖励背包界面")
				if center != null:
					center.call("_set_ownership_filter", "locked")
					await process_frame
					var locked_row := center.get_node_or_null("RewardRow0") as Button
					var locked_thumb := locked_row.get_node_or_null("Thumbnail") as Control if locked_row else null
					var locked_state := locked_row.get_node_or_null("RewardState") as Label if locked_row else null
					_check(locked_row != null and locked_thumb != null
						and bool(locked_thumb.get("_locked"))
						and locked_state != null and locked_state.text.contains("LOCKED"),
						"未解锁奖励整项灰化并带明确锁定标识")
					center.call("_set_ownership_filter", "owned")
					await process_frame
					var owned_row := center.get_node_or_null("RewardRow0") as Button
					var owned_thumb := owned_row.get_node_or_null("Thumbnail") as Control if owned_row else null
					_check(owned_row != null and owned_thumb != null and not bool(owned_thumb.get("_locked")),
						"已拥有奖励卡片展示独立彩色缩略图")
					if owned_row != null:
						owned_row.pressed.emit()
						await process_frame
						var action := center.get_node_or_null("RewardActionButton") as Button
						_check(action != null and not action.disabled,
							"完整背包中已拥有奖励可以预览并装备")
						if action != null:
							action.pressed.emit()
							await process_frame
						_check(not rewards.equipped("title").is_empty() \
							or not rewards.equipped("avatar_frame").is_empty() \
							or not rewards.equipped("profile_card").is_empty(),
							"完整背包装备动作写入奖励槽位")
	root.remove_child(song_select)
	song_select.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.1).timeout
	quit(1 if failures > 0 else 0)
