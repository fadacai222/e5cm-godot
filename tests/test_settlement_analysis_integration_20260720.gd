extends SceneTree
## 结算分析集成：按钮显隐、流程冻结、关闭恢复、问题片段直达训练设置。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["TrainingSession", "res://autoload/training_session.gd"],
	["AnalyticsStore", "res://autoload/analytics_store.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SceneRouter", "res://autoload/scene_router.gd"],
]

var _failures := 0

func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	await process_frame
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("AnalyticsStore").persist_enabled = false
	var song := {"sm": "test.sm", "mp3": "test.mp3", "cover": "", "name": "分析测试曲",
		"star": 8, "mode": "竞速", "submode": "club", "sm_key": "analysis-integration",
		"prefer_double": false, "couple": false, "target_charttype": "", "style": "", "bpm": 150.0}
	var summary := {"total": 120, "sample_count": 110, "average_diff_ms": -8.0,
		"median_diff_ms": -7.0, "standard_deviation_ms": 14.0, "early_count": 40,
		"late_count": 70, "perfect": 95, "cool": 15, "good": 5, "miss": 5,
		"track_count": 5, "chart_duration": 100.0, "per_track": [],
		"worst_windows": [{"start_sec": 42.0, "end_sec": 47.0, "loss": 20.0, "miss_count": 2}]}
	for track in 5:
		summary["per_track"].append({"track": track, "sample_count": 20,
			"average_diff_ms": -5.0, "median_diff_ms": -5.0,
			"counts": {"perfect": 18, "cool": 1, "good": 0, "miss": 1}})
	root.get_node("SceneRouter").payload = {"曲目名": "分析测试曲", "sm_key": "analysis-integration",
		"mode": "竞速", "submode": "club", "cover": "", "star": 8,
		"本局最高分": 500000, "本局最大combo": 100, "歌曲时长秒": 100.0,
		"百分比": "95.00%", "百分比数值": 95.0, "评级": "S", "失败": false,
		"当前关卡": 1, "结算后S数": 1, "三把S赠送": false, "是否赠送第四把": false,
		"perfect数": 95, "cool数": 15, "good数": 5, "miss数": 5,
		"是否全perfect": false, "是否全连": false,
		"analysis_summary": summary, "analysis_events": [],
		"analysis_trend": {"chart_runs": 3, "mode_runs": 8, "global_runs": 12,
			"chart_suggestion": {"enough_samples": true, "confidence": "中",
				"direction": "late", "suggested_adjustment_ms": -5, "median_diff_ms": -7.0}},
		"analysis_song": song}
	var settlement: Control = load("res://scenes/settlement/settlement.tscn").instantiate()
	root.add_child(settlement)
	await process_frame
	settlement.call("_enter_phase2")
	var button := settlement.get_node_or_null("JudgementAnalysisButton") as Button
	_check(button != null and button.visible, "结算第二阶段显示判定分析按钮")
	settlement.call("_open_analysis")
	_check(bool(settlement.call("analysis_open_for_test")), "结算内原地打开分析覆盖层")
	var before_t := float(settlement.get("_t"))
	settlement.call("_process", 2.0)
	_check(is_equal_approx(float(settlement.get("_t")), before_t), "分析打开期间结算倒计时冻结")
	var panel := settlement.get_node("JudgementAnalysisPanel")
	var config: Dictionary = panel.call("selected_training_config_for_test")
	_check(float(config.get("start_sec", -1.0)) <= 42.0 and float(config.get("end_sec", 0.0)) >= 47.0,
		"结算问题片段生成训练区间", str(config))
	panel.call("close_analysis")
	var before_phase := int(settlement.get("_phase"))
	settlement.call("_process", 0.5)
	_check(int(settlement.get("_phase")) > before_phase \
		or float(settlement.get("_t")) > before_t,
		"关闭分析后结算流程继续")
	root.remove_child(settlement)
	settlement.free()
	root.get_node("TrainingSession").reset_all()
	root.get_node("SceneRouter").payload = {}
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.12).timeout
	quit(1 if _failures > 0 else 0)
