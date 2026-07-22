extends SceneTree
## 结算判定分析覆盖层：总览、时间轴、2P 分轨、问题片段训练入口与输入关闭。

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
		return
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

	var panel_script: Script = load("res://ui/judgement_analysis_panel.gd") as Script
	var timeline_script: Script = load("res://ui/judgement_timeline.gd") as Script
	_check(panel_script != null, "判定分析全屏面板脚本存在")
	_check(timeline_script != null, "判定时间轴控件脚本存在")
	if panel_script == null or timeline_script == null:
		_finish()
		return

	var panel: Control = panel_script.new()
	root.add_child(panel)
	await process_frame
	var events: Array = []
	for i in 80:
		events.append({
			"note_index": i, "track": i % 10, "type": "tap",
			"judge": "miss" if i % 19 == 0 else ("good" if i % 11 == 0 else "perfect"),
			"diff_ms": float((i % 17) - 8), "start_sec": float(i),
			"end_sec": float(i), "scoring": true,
		})
	var per_track: Array = []
	for track in 10:
		per_track.append({
			"track": track, "sample_count": 8,
			"average_diff_ms": float(track - 5), "median_diff_ms": float(track - 5),
			"counts": {"perfect": 6, "cool": 1, "good": 0, "miss": 1},
		})
	var summary := {
		"total": 80, "event_total": 80, "sample_count": 75,
		"average_diff_ms": -4.0, "trimmed_mean_diff_ms": -3.5,
		"median_diff_ms": -3.0, "standard_deviation_ms": 12.0,
		"early_count": 30, "late_count": 45,
		"perfect": 65, "cool": 5, "good": 5, "miss": 5,
		"per_track": per_track, "track_count": 10, "chart_duration": 90.0,
		"worst_windows": [
			{"start_sec": 18.0, "end_sec": 23.0, "loss": 19.0, "miss_count": 2},
			{"start_sec": 52.0, "end_sec": 57.0, "loss": 12.0, "miss_count": 1},
		],
	}
	panel.call("open_analysis", {
		"summary": summary,
		"events": events,
		"trend": {"chart_runs": 4, "mode_runs": 12, "global_runs": 20,
			"mode_average_diff_ms": -5.0, "global_average_diff_ms": -2.0,
			"chart_suggestion": {"enough_samples": true, "confidence": "中",
				"direction": "late", "suggested_adjustment_ms": -5,
				"median_diff_ms": -4.0}},
		"song": {"name": "UI测试曲", "sm": "a.sm", "mp3": "a.mp3", "sm_key": "chart-ui"},
	})
	await process_frame
	_check(panel.call("is_open"), "判定分析面板可打开")
	_check(panel.get_node_or_null("AnalysisFrame") != null, "分析面板使用独立全屏街机框架")
	_check(panel.get_node_or_null("OverviewContent") != null, "分析总览显示平均偏移与分轨数据")
	_check(panel.get_node_or_null("OverviewContent/Player1Tracks") != null \
		and panel.get_node_or_null("OverviewContent/Player2Tracks") != null,
		"10轨成绩按 1P/2P 并排显示")
	panel.call("show_timeline_for_test")
	await process_frame
	_check(panel.get_node_or_null("TimelineContent/JudgementTimeline") != null,
		"时间轴页绘制歌曲判定分布")
	_check(int(panel.call("problem_window_count_for_test")) == 2,
		"时间轴页识别并可切换问题区间")
	var config: Dictionary = panel.call("selected_training_config_for_test")
	_check(float(config.get("start_sec", -1.0)) <= 18.0 \
		and float(config.get("end_sec", 0.0)) >= 23.0,
		"问题区间可生成预填训练配置", str(config))
	panel.call("close_analysis")
	_check(not panel.call("is_open"), "分析面板可通过统一关闭接口退出")

	root.remove_child(panel)
	panel.free()
	_finish()


func _finish() -> void:
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.05).timeout
	quit(1 if _failures > 0 else 0)
