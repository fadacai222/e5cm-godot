extends SceneTree
## 奖励条件可达性、资格隔离、挑战奖励绑定与进度显示回归。

const Generator := preload("res://core/challenge_generator.gd")
const Catalog := preload("res://core/reward_catalog.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])


func _official_run(index: int, star := 15, miss := 0, grade := "S") -> Dictionary:
	return {
		"run_id": "reward-complete-%d" % index,
		"eligible": true,
		"training": false,
		"autoplay": false,
		"debug": false,
		"failed": false,
		"chart_hash": "chart-%d" % index,
		"star": star,
		"miss": miss,
		"grade": grade,
		"completed_hour": 12,
		"full_combo": false,
		"all_perfect": false,
	}


func _run() -> void:
	var rewards = root.get_node("RewardService")
	var milestones = root.get_node("RewardMilestoneService")
	var profile_store = root.get_node("ProfileStore")
	var challenge_service = root.get_node("ChallengeService")
	var original_profile: Dictionary = profile_store.profile.duplicate(true)
	var original_records: Dictionary = profile_store.records.duplicate(true)
	var original_challenges: Dictionary = challenge_service.snapshot()
	var original_rewards: Dictionary = rewards.snapshot()
	var original_milestones: Dictionary = milestones.snapshot_for_test() \
		if milestones.has_method("snapshot_for_test") else {}

	rewards.persist_enabled = false
	profile_store.persist_enabled = false
	challenge_service.persist_enabled = false
	milestones.persist_enabled = false
	rewards.reset_for_test()
	milestones.reset_for_test()

	var unreachable: Array[String] = []
	for reward_id in Catalog.new().ids():
		if not rewards.is_challenge_reward(reward_id) \
				and milestones.progress_for_reward(reward_id).is_empty():
			unreachable.append(reward_id)
	_check(unreachable.is_empty(),
		"奖励目录每个条目都具备挑战来源或可执行里程碑规则",
		str(unreachable))

	# 10 张不同的 15★以上正式谱面解锁炽焰环；重复谱面不重复累计。
	for index in 9:
		milestones.process_official_run(_official_run(index, 15, 0, "S"))
	milestones.process_official_run(_official_run(8, 15, 0, "S").merged({"run_id": "duplicate-chart"}, true))
	_check(not rewards.owns("frame_flame")
		and int(milestones.progress_for_reward("frame_flame").get("current", -1)) == 9,
		"重复高难谱面不重复累计炽焰环进度")
	milestones.process_official_run(_official_run(9, 15, 0, "S"))
	_check(rewards.owns("frame_flame"), "连续完成 10 张不同 15★以上谱面解锁炽焰环")

	# 低难或失败会中断连续高难进度。
	rewards.reset_for_test()
	milestones.reset_for_test()
	for index in 4:
		milestones.process_official_run(_official_run(index, 15, 0, "A"))
	milestones.process_official_run(_official_run(90, 14, 0, "S"))
	_check(int(milestones.progress_for_reward("frame_flame").get("current", -1)) == 0,
		"低于 15★的正式谱面会中断高难连胜")
	for index in range(4, 7):
		milestones.process_official_run(_official_run(index, 16, 0, "A"))
	var failed := _official_run(91, 18, 0, "S")
	failed["failed"] = true
	milestones.process_official_run(failed)
	_check(int(milestones.progress_for_reward("frame_flame").get("current", -1)) == 0,
		"失败的正式高难谱面会中断高难连胜")

	# 冰晶与棱镜主题挑战具有明确、可执行的条件。
	rewards.reset_for_test()
	milestones.reset_for_test()
	for index in 5:
		milestones.process_official_run(_official_run(index, 15, 2, "A"))
	_check(rewards.owns("frame_ice"),
		"完成 5 张不同 15★以上且 MISS≤2 的谱面解锁冰晶环")
	for index in range(20, 23):
		milestones.process_official_run(_official_run(index, 17, 0, "S"))
	_check(rewards.owns("frame_prism"),
		"完成 3 张不同 17★以上 S 评价谱面解锁棱镜环")

	# 收藏型奖励不再是死奖励。
	rewards.unlock("title_prism_oracle", "test:prism-oracle", "test")
	milestones.evaluate_existing_state()
	_check(rewards.owns("card_prism_myth"), "棱镜环与棱镜先知组成的收藏链解锁棱镜神话玩家卡")

	rewards.reset_for_test()
	var epic_ids: Array[String] = []
	for item in rewards.all_rewards():
		if str(item.get("rarity", "")) == "epic":
			epic_ids.append(str(item.get("id", "")))
	for index in mini(8, epic_ids.size()):
		rewards.unlock(epic_ids[index], "test:epic:%d" % index, "test")
	milestones.evaluate_existing_state()
	_check(rewards.owns("title_galaxy_lord"), "拥有 8 件史诗奖励解锁银河领主")

	rewards.reset_for_test()
	var legendary_ids: Array[String] = []
	for item in rewards.all_rewards():
		var reward_id := str(item.get("id", ""))
		if str(item.get("rarity", "")) == "legendary" \
				and reward_id not in ["frame_vip_crown", "title_rhythm_god"]:
			legendary_ids.append(reward_id)
	for index in mini(5, legendary_ids.size()):
		rewards.unlock(legendary_ids[index], "test:legend:%d" % index, "test")
	milestones.evaluate_existing_state()
	_check(rewards.owns("frame_vip_crown"), "拥有 5 件传说奖励解锁 VIP 王冠头像框")
	for reward_id in legendary_ids:
		rewards.unlock(reward_id, "test:all-legend:" + reward_id, "test")
	milestones.evaluate_existing_state()
	_check(rewards.owns("title_rhythm_god"), "完成全部其他传说里程碑解锁巅峰节奏神")

	# 夜间奖励使用真实时间条件，而不是随机周常。
	rewards.reset_for_test()
	milestones.reset_for_test()
	var night_run := _official_run(100, 8, 0, "A")
	night_run["completed_hour"] = 23
	milestones.process_official_run(night_run)
	_check(rewards.owns("title_night_walker"), "22:00 至次日 05:59 完成正式谱面解锁夜光行者")

	# 挑战池只发放挑战专属奖励，里程碑奖励不再随机提前获得。
	var capabilities := {
		"modes": {"花式": {"count": 10, "stars": [5, 10, 15, 18]}},
		"has_unplayed": true,
		"has_breakable_record": true,
		"has_random_source": true,
		"two_player": true,
		"owned_rewards": [],
	}
	var generated := Generator.new().generate_daily("2026-07-23", "reward-audit", capabilities, 30)
	var forbidden := ["frame_minimal_silver", "title_precision_master", "frame_pulse",
		"frame_data_grid", "card_neon_wave", "frame_prism"]
	var no_forbidden := true
	var difficulty_bound := true
	for task in generated:
		var reward_id := str(task.get("reward_id", ""))
		no_forbidden = no_forbidden and reward_id not in forbidden
		if str(task.get("difficulty", "normal")) in ["advanced", "challenge"]:
			difficulty_bound = difficulty_bound and reward_id in ["title_rhythm_worker", "frame_neon_magenta"]
	_check(no_forbidden, "挑战池不再混入等级、统计、收藏和首次通关奖励", str(generated))
	_check(difficulty_bound, "进阶及高难每日挑战只发对应的进阶挑战奖励", str(generated))

	# 已拥有挑战奖励转化为可见的奖励碎片补偿，不再领到空气。
	rewards.reset_for_test()
	rewards.unlock("title_daily_rookie", "test:owned", "test")
	var duplicate_task := {
		"id": "daily_duplicate_reward", "period": "daily", "template_id": "launch_game",
		"difficulty": "normal", "reward_id": "title_daily_rookie",
		"completed": true, "claimed": false,
	}
	var claimed: Dictionary = challenge_service.claim_task_reward_for_test(duplicate_task)
	_check(bool(claimed.get("claimed", false))
		and int(rewards.duplicate_shards()) > 0
		and int(claimed.get("duplicate_compensation", 0)) > 0,
		"重复挑战奖励自动转换为奖励碎片补偿", str(claimed))
	var shards_after_first := int(rewards.duplicate_shards())
	var repeated_claim: Dictionary = challenge_service.claim_task_reward_for_test(duplicate_task)
	_check(int(rewards.duplicate_shards()) == shards_after_first
		and int(repeated_claim.get("duplicate_compensation", -1)) == 0,
		"同一挑战补偿重试保持幂等，崩溃恢复不会重复刷碎片",
		"before=%d after=%d task=%s" % [shards_after_first,
			int(rewards.duplicate_shards()), str(repeated_claim)])
	for index in range(1, 5):
		rewards.grant_duplicate_compensation("title_daily_rookie", "challenge:shard-fill-%d" % index)
	var redeem_result: Dictionary = rewards.redeem_with_shards("frame_neon_cyan")
	_check(bool(redeem_result.get("ok", false)) and rewards.owns("frame_neon_cyan")
		and int(rewards.duplicate_shards()) == 0,
		"奖励碎片可兑换未拥有的挑战专属奖励，形成补偿闭环",
		str(redeem_result))
	var blocked_redeem: Dictionary = rewards.redeem_with_shards("frame_flame")
	_check(not bool(blocked_redeem.get("ok", true)) and not rewards.owns("frame_flame"),
		"奖励碎片不能绕过高难里程碑兑换炽焰环",
		str(blocked_redeem))
	for index in 10:
		rewards.grant_duplicate_compensation("title_daily_rookie", "challenge:ui-shard-fill-%d" % index)
	var exchange_center = load("res://ui/reward_center.gd").new()
	root.add_child(exchange_center)
	await process_frame
	exchange_center.call("_select_reward", "title_rhythm_worker", false)
	var exchange_button = exchange_center.get("_action_button") as Button
	_check(exchange_button != null and not exchange_button.disabled \
		and exchange_button.text.contains("碎片兑换"),
		"奖励中心为可兑换的挑战奖励显示碎片兑换按钮",
		exchange_button.text if exchange_button != null else "missing")
	exchange_button.pressed.emit()
	await process_frame
	await process_frame
	_check(rewards.owns("title_rhythm_worker") and int(rewards.duplicate_shards()) == 0,
		"玩家可在奖励中心实际完成碎片兑换")
	root.remove_child(exchange_center)
	exchange_center.free()
	exchange_center = null

	# AUTO/调试成绩不写官方记录、经验和统计。
	profile_store.profile = profile_store._default_profile()
	profile_store.records = {}
	var settlement_script = load("res://scenes/settlement/settlement.gd")
	var settlement = settlement_script.new()
	settlement.payload = {
		"run_id": "auto-no-progress", "challenge_eligible": false,
		"autoplay": true, "debug_run": false, "失败": false,
		"sm_key": "auto/chart.sm", "曲目名": "AUTO TEST", "本局最高分": 1350000,
		"歌曲时长秒": 180.0, "评级": "S", "本局最大combo": 999,
		"mode": "竞速", "当前关卡": 1, "cool数": 0, "good数": 0, "miss数": 0,
	}
	settlement.call("_persist_results")
	var auto_stats: Dictionary = profile_store.profile.get("统计", {})
	_check(profile_store.records.is_empty()
		and int(auto_stats.get("累计评价S数", 0)) == 0
		and int(auto_stats.get("最大Combo", 0)) == 0
		and int(profile_store.get_mode_progress("竞速").get("累计首数", 0)) == 0,
		"AUTO 成绩不污染官方记录、等级、S 数、Combo 与累计首数")
	settlement.free()
	settlement = null
	settlement_script = null

	# 背包可以读取实时进度，而不只显示静态条件。
	milestones.reset_for_test()
	for index in 3:
		milestones.process_official_run(_official_run(index, 15, 0, "A"))
	rewards.grant_duplicate_compensation("title_daily_rookie", "challenge:final-shard-display")
	var progress: Dictionary = milestones.progress_for_reward("frame_flame")
	_check(int(progress.get("current", -1)) == 3 and int(progress.get("target", -1)) == 10
		and str(progress.get("text", "")).contains("3 / 10"),
		"奖励服务可返回真实获取进度", str(progress))
	var reward_center = load("res://ui/reward_center.gd").new()
	root.add_child(reward_center)
	await process_frame
	reward_center.call("_select_reward", "frame_flame", false)
	var detail_source = reward_center.get("_detail_source") as Label
	var unread_summary := reward_center.get_node_or_null("UnreadSummary") as Label
	_check(detail_source != null and detail_source.text.contains("3 / 10"),
		"奖励中心详情真实显示 3 / 10 获取进度",
		detail_source.text if detail_source != null else "missing")
	_check(unread_summary != null and unread_summary.text.contains("奖励碎片"),
		"奖励中心顶部显示重复奖励碎片余额",
		unread_summary.text if unread_summary != null else "missing")
	root.remove_child(reward_center)
	reward_center.free()
	reward_center = null
	await process_frame

	profile_store.profile = original_profile
	profile_store.records = original_records
	challenge_service.replace_state_for_test(original_challenges)
	rewards.replace_state_for_test(original_rewards)
	if not original_milestones.is_empty():
		milestones.replace_state_for_test(original_milestones)
	var audio_director = root.get_node_or_null("AudioDirector")
	if audio_director != null and audio_director.has_method("release_for_shutdown"):
		audio_director.release_for_shutdown()
	await process_frame
	await create_timer(0.12).timeout
	print("ALL REWARD UNLOCK COMPLETENESS TESTS PASSED" if failures == 0 else
		"%d REWARD UNLOCK COMPLETENESS TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
