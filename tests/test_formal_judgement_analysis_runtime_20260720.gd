extends SceneTree
## 正式对局分析接入：判定缓冲、资格过滤、结算载荷与结算覆盖层。

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
	root.get_node("SettingsStore").autoplay = false
	root.get_node("SettingsStore").show_ready_animation = false

	var songs: Array = root.get_node("SongLibrary").get_songs("竞速", "club")
	_check(not songs.is_empty(), "正式分析测试找到真实谱面")
	if songs.is_empty():
		_finish()
		return
	var song: Dictionary = songs[0]
	var payload := {
		"sm": song["sm"], "mp3": song["mp3"], "cover": song["cover"],
		"name": song["name"], "star": song["star"], "mode": "竞速", "submode": "club",
		"sm_key": song["sm_key"], "prefer_double": false, "couple": false,
		"target_charttype": str(song.get("charttype", "")), "style": str(song.get("style", "")),
		"bpm": float(song.get("bpm", 120.0)),
	}
	root.get_node("SceneRouter").payload = payload
	var gameplay: Control = load("res://scenes/gameplay/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	for i in 30:
		await process_frame
		if bool(gameplay.get("_chart_ready")):
			break
	_check(bool(gameplay.get("_chart_ready")), "正式 Gameplay 完成真实谱面加载")
	_check(gameplay.get("_run_analytics") != null, "正式对局创建判定分析会话")
	_check(bool(gameplay.get("_analysis_eligible")), "非自动正式对局具备长期分析资格")

	var reports: Array = [
		JudgeSystem.JudgeReport.new("tap", 0, "perfect", 12.0, 5000, 1, 1.0, 1.0, 0),
		JudgeSystem.JudgeReport.new("tap", 1, "cool", -25.0, 4000, 1, 2.0, 2.0, 1),
		JudgeSystem.JudgeReport.new("tap", 2, "miss", -220.0, 0, 0, 18.0, 18.0, 2),
		JudgeSystem.JudgeReport.new("tap", 3, "miss", -220.0, 0, 0, 20.0, 20.0, 3),
	]
	gameplay.call("_apply_reports", reports)
	var bundle: Dictionary = gameplay.call("analysis_bundle_for_test")
	var summary: Dictionary = bundle.get("analysis_summary", {})
	_check(int(summary.get("total", 0)) == 4, "正式判定事件进入分析缓冲", str(summary))
	_check((summary.get("worst_windows", []) as Array).size() >= 1,
		"正式分析载荷包含问题时间段")
	_check(bundle.get("analysis_events", []) is Array \
		and (bundle.get("analysis_events", []) as Array).size() == 4,
		"结算载荷携带当前局逐音符复盘事件")
	_check((root.get_node("AnalyticsStore").get_chart_history(str(song["sm_key"])) as Array).size() == 1,
		"正式合格成绩写入长期分析趋势")

	root.get_node("SettingsStore").autoplay = true
	root.get_node("SceneRouter").payload = payload
	var autoplay_gameplay: Control = load("res://scenes/gameplay/gameplay.tscn").instantiate()
	root.add_child(autoplay_gameplay)
	for i in 30:
		await process_frame
		if bool(autoplay_gameplay.get("_chart_ready")):
			break
	_check(not bool(autoplay_gameplay.get("_analysis_eligible")), "自动播放明确失去长期分析资格")
	var auto_bundle: Dictionary = autoplay_gameplay.call("analysis_bundle_for_test")
	_check(not bool(auto_bundle.get("analysis_eligible", true)), "自动播放结算载荷保留资格原因")
	_check((root.get_node("AnalyticsStore").get_chart_history(str(song["sm_key"])) as Array).size() == 1,
		"自动播放不会污染长期趋势")

	root.remove_child(gameplay)
	gameplay.free()
	root.remove_child(autoplay_gameplay)
	autoplay_gameplay.free()
	_finish()


func _finish() -> void:
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.08).timeout
	quit(1 if _failures > 0 else 0)
