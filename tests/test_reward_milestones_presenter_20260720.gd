extends SceneTree

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
	var milestones = root.get_node("RewardMilestoneService")
	var presenter = root.get_node("RewardPresenter")
	var profile_store = root.get_node("ProfileStore")
	var challenge_service = root.get_node("ChallengeService")
	var original_profile: Dictionary = profile_store.profile.duplicate(true)
	var original_records: Dictionary = profile_store.records.duplicate(true)
	var original_challenges: Dictionary = challenge_service.snapshot()
	var original_milestones: Dictionary = milestones.snapshot_for_test()
	rewards.persist_enabled = false
	profile_store.persist_enabled = false
	milestones.persist_enabled = false
	profile_store.profile = profile_store._default_profile()
	profile_store.records = {}
	milestones.reset_for_test()
	rewards.reset_for_test()
	presenter.reset_for_test()

	var official := {
		"run_id": "reward-official-1", "eligible": true, "training": false,
		"autoplay": false, "debug": false, "failed": false,
		"full_combo": true, "all_perfect": true,
	}
	var unlocked: Array[String] = milestones.process_official_run(official)
	_check("title_full_combo" in unlocked and "frame_all_perfect" in unlocked,
		"正式全连与全 P 解锁当前版本成就奖励")
	_check(rewards.owns("title_full_combo") and rewards.owns("frame_all_perfect"),
		"成就奖励写入统一奖励库存")
	_check(presenter.pending_count_for_test() == 3,
		"首次正式全 P 同时解锁银框、全连称号与完美光环并进入合并提示队列",
		"pending=%d unlocked=%s" % [presenter.pending_count_for_test(), str(unlocked)])
	presenter.force_safe_present_for_test()
	await process_frame
	var popup := presenter.get_node_or_null("RewardUnlockPopup")
	_check(popup != null and popup.get_node_or_null("UnlockedReward0") != null
		and popup.get_node_or_null("UnlockedReward1") != null
		and popup.get_node_or_null("UnlockedReward2") != null,
		"多个奖励在同一个街机解锁提示中合并展示")
	presenter.reset_for_test()

	rewards.reset_for_test()
	var autoplay := official.duplicate(true)
	autoplay["run_id"] = "reward-autoplay"
	autoplay["autoplay"] = true
	_check(milestones.process_official_run(autoplay).is_empty()
		and not rewards.owns("title_full_combo"),
		"自动播放不解锁正式全连奖励")
	var failed := official.duplicate(true)
	failed["run_id"] = "reward-failed"
	failed["failed"] = true
	_check(milestones.process_official_run(failed).is_empty(),
		"失败成绩不解锁成就奖励")

	var training_config := {"problem_windows": [{"start_sec": 10.0, "end_sec": 15.0}]}
	var summary := {"total": 20, "chart_key": "reward-training-chart"}
	_check("title_training_focus" in milestones.process_training_completion(training_config, summary)
		and rewards.owns("title_training_focus"),
		"完成问题区间训练解锁问题终结者称号")
	_check(milestones.process_training_completion({}, summary).is_empty(),
		"普通整曲训练不伪装成问题区间奖励")

	rewards.reset_for_test()
	var fancy_progress: Dictionary = profile_store.get_mode_progress("花式")
	fancy_progress["等级"] = 10
	profile_store.set_mode_progress("花式", fancy_progress)
	milestones.evaluate_existing_state()
	_check(rewards.owns("title_fancy_lv10"),
		"花式等级达到 10 自动解锁模式称号")

	rewards.reset_for_test()
	for mode in ["花式", "竞速", "DIY"]:
		var progress: Dictionary = profile_store.get_mode_progress(mode)
		progress["等级"] = 40
		progress["累计首数"] = 100
		profile_store.set_mode_progress(mode, progress)
	var milestone_state: Dictionary = milestones.snapshot_for_test()
	var unique_charts := {}
	for index in 100:
		unique_charts["reward-milestone-chart-%d" % index] = true
	milestone_state["unique_completed_charts"] = unique_charts
	milestones.replace_state_for_test(milestone_state)
	profile_store.profile["统计"] = {
		"累计评价S数": 100,
		"最大Combo": 500,
		"游玩时长分钟": 2000,
	}
	milestones.evaluate_existing_state()
	_check(rewards.owns("title_precision_master") and rewards.owns("title_combo_king")
		and rewards.owns("title_rhythm_master") and rewards.owns("title_star_conqueror")
		and rewards.owns("title_battle_hardened") and rewards.owns("title_legend_performer")
		and rewards.owns("title_beat_sovereign") and rewards.owns("title_cyber_ronin")
		and rewards.owns("title_frost_core") and rewards.owns("title_ember_crown")
		and rewards.owns("title_matrix_ghost") and rewards.owns("title_sakura_dream")
		and rewards.owns("title_void_watcher") and rewards.owns("title_prism_oracle")
		and rewards.owns("title_midas_destiny"),
		"统计与三模式等级可解锁八类新增代码称号链")
	_check(rewards.owns("frame_starburst") and rewards.owns("card_black_gold_vip")
		and rewards.owns("card_fancy_stage") and rewards.owns("card_speed_lightning")
		and rewards.owns("card_diy_blueprint"),
		"扩展头像框与玩家卡里程碑均可实际获得")

	rewards.reset_for_test()
	var streak_state: Dictionary = challenge_service.snapshot()
	streak_state["streak"] = {"current": 7, "best": 7, "last_completed_date": "2026-07-20"}
	challenge_service.replace_state_for_test(streak_state)
	milestones.evaluate_existing_state()
	_check(rewards.owns("title_streak_3") and rewards.owns("frame_streak_7")
		and not rewards.owns("card_streak_30"),
		"连续活跃 7 天解锁 3 日称号和 7 日头像框，不越级发 30 日玩家卡")

	profile_store.profile = original_profile
	profile_store.records = original_records
	challenge_service.replace_state_for_test(original_challenges)
	milestones.replace_state_for_test(original_milestones)
	rewards.reset_for_test()
	presenter.reset_for_test()
	await process_frame
	quit(1 if failures > 0 else 0)
