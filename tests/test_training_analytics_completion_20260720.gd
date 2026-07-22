extends SceneTree
## 训练室剩余纯逻辑：判定事件生命周期、序列化、多局趋势、存档迁移与性能。

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
	_test_hold_end_and_serialization()
	_test_analytics_math_and_suggestion()
	await _test_analytics_store()
	_test_dynamic_bpm_preroll()
	quit(1 if _failures > 0 else 0)


func _test_hold_end_and_serialization() -> void:
	var judge: JudgeSystem = JudgeSystem.new()
	var hold: JudgeSystem.JudgeNote = JudgeSystem.JudgeNote.new(2, "hold", 1.0, 2.0, [1.5, 2.0])
	judge.load_chart([hold])
	var head: Array = judge.handle_press(2, 1.0)
	var reports: Array = []
	reports.append_array(head)
	reports.append_array(judge.update(1.6, func(_track: int): return true))
	reports.append_array(judge.update(2.1, func(_track: int): return true))
	var end_reports: Array = reports.filter(func(report): return report.type == "hold_end")
	_check(end_reports.size() == 1, "Hold 完成后只产生一个 hold_end 生命周期事件", str(end_reports.size()))
	if not end_reports.is_empty():
		_check(not bool(end_reports[0].scoring), "hold_end 不参与正式计分")
	var serialized: Dictionary = JudgeSystem.report_to_dict(head[0])
	var restored: JudgeSystem.JudgeReport = JudgeSystem.report_from_dict(serialized)
	_check(restored != null and restored.type == "hold_head" and restored.note_index == 0,
		"JudgeReport 可无损序列化并恢复稳定 note_index", str(serialized))

	var score: ScoreSystem = ScoreSystem.new(15000)
	score.settle_all(reports)
	var analytics: JudgementAnalytics = JudgementAnalytics.new(5)
	for report in reports:
		analytics.add_report(report, score.current_combo, false)
	var summary: Dictionary = analytics.summary()
	var score_count: int = int(score.counts["perfect"]) + int(score.counts["cool"]) \
		+ int(score.counts["good"]) + int(score.counts["miss"])
	_check(int(summary.get("total", -1)) == score_count,
		"分析聚合判定总数与 ScoreSystem 一致", "%s / %s" % [summary.get("total"), score_count])
	_check(int(summary.get("event_total", 0)) == reports.size(),
		"分析额外保留 hold_end 生命周期事件", str(summary.get("event_total")))


func _test_analytics_math_and_suggestion() -> void:
	var analytics: JudgementAnalytics = JudgementAnalytics.new(5)
	for i in 10:
		var report: JudgeSystem.JudgeReport = JudgeSystem.JudgeReport.new(
			"tap", i % 5, "perfect", float(i * 10), 5000, 1,
			float(i), float(i), i)
		analytics.add_report(report, i + 1, false)
	var summary: Dictionary = analytics.summary()
	_check(is_equal_approx(float(summary.get("trimmed_mean_diff_ms", -1.0)), 45.0),
		"判定分析输出截尾平均", str(summary.get("trimmed_mean_diff_ms")))
	var histories: Array = []
	for median in [-16.0, -14.0, -18.0, -15.0, -17.0]:
		histories.append({"sample_count": 160, "median_diff_ms": median})
	var suggestion: Dictionary = JudgementAnalytics.offset_suggestion(histories)
	_check(bool(suggestion.get("enough_samples", false)), "至少三局稳定样本可生成偏移建议")
	_check(str(suggestion.get("direction", "")) == "late" \
		and int(suggestion.get("suggested_adjustment_ms", 0)) < 0,
		"稳定晚按给出负向偏移建议", str(suggestion))
	_check(str(suggestion.get("confidence", "")) in ["中", "高"],
		"偏移建议包含置信度", str(suggestion))
	var insufficient: Dictionary = JudgementAnalytics.offset_suggestion(histories.slice(0, 2))
	_check(not bool(insufficient.get("enough_samples", true)), "不足三局时明确拒绝偏移建议")

	var perf: JudgementAnalytics = JudgementAnalytics.new(10)
	var start_usec: int = Time.get_ticks_usec()
	for i in 10000:
		var report: JudgeSystem.JudgeReport = JudgeSystem.JudgeReport.new(
			"tap", i % 10, "miss" if i % 17 == 0 else "perfect",
			float((i % 21) - 10), 0 if i % 17 == 0 else 5000,
			0 if i % 17 == 0 else 1, float(i) * 0.02, float(i) * 0.02, i)
		perf.add_report(report, i, false)
	var perf_summary: Dictionary = perf.summary()
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_check(int(perf_summary.get("total", 0)) == 10000, "10000 个判定事件完整聚合")
	_check(elapsed_ms < 1500.0, "10000 个判定事件处理无明显卡顿", "%.1fms" % elapsed_ms)


func _test_analytics_store() -> void:
	var path: String = "user://test_training_analytics_completion.json"
	var corrupt_path: String = path + ".corrupt"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))
	var store_script: Script = load("res://autoload/analytics_store.gd") as Script
	_check(store_script != null, "AnalyticsStore 脚本存在")
	if store_script == null:
		return
	var store: Node = store_script.new()
	store.set("data_path", path)
	store.set("persist_enabled", true)
	root.add_child(store)
	await process_frame
	for i in 12:
		store.call("record_run", "chart-A", "竞速", {
			"sample_count": 150, "median_diff_ms": -12.0 - float(i % 3),
			"average_diff_ms": -12.0, "early_count": 20, "late_count": 130,
			"perfect": 120, "cool": 20, "good": 5, "miss": 5,
			"timestamp": i,
		}, true)
	var history: Array = store.call("get_chart_history", "chart-A")
	_check(history.size() == 10, "每谱面最多保存最近 10 局", str(history.size()))
	var trend: Dictionary = store.call("get_trend", "chart-A", "竞速")
	_check(int(trend.get("chart_runs", 0)) == 10 and int(trend.get("mode_runs", 0)) >= 10,
		"AnalyticsStore 同时提供谱面、模式与全局趋势", str(trend))
	_check(FileAccess.file_exists(path), "AnalyticsStore 写入独立分析文件")

	var ignored: bool = bool(store.call(
		"record_run", "chart-A", "竞速", {"sample_count": 999}, false))
	_check(not ignored and (store.call("get_chart_history", "chart-A") as Array).size() == 10,
		"无资格成绩不会写入长期趋势")
	root.remove_child(store)
	store.free()

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken json")
	file.close()
	var recovery: Node = store_script.new()
	recovery.set("data_path", path)
	recovery.set("persist_enabled", false)
	root.add_child(recovery)
	await process_frame
	_check((recovery.call("get_chart_history", "chart-A") as Array).is_empty(),
		"分析文件损坏时只重置分析数据")
	_check(bool(recovery.call("was_corrupt_on_load_for_test")), "损坏恢复状态可诊断")
	root.remove_child(recovery)
	recovery.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_path))


func _test_dynamic_bpm_preroll() -> void:
	var runtime: TrainingRuntime = TrainingRuntime.new({
		"bpm": 120.0,
		"training_config": {"start_sec": 10.0, "end_sec": 20.0, "speed": 1.0,
			"loop_count": 3, "auto_rewind_sec": 0.0,
			"show_timing": true, "metronome": true},
	})
	var timeline: Array = [[0.0, 0.0, 120.0], [16.0, 8.0, 240.0]]
	runtime.set_timeline(timeline, 0.0)
	_check(is_equal_approx(runtime.bpm_at(4.0), 120.0) \
		and is_equal_approx(runtime.bpm_at(10.0), 240.0),
		"训练运行时按时间轴读取动态 BPM")
	var lead: float = runtime.preroll_seconds(10.0)
	_check(lead >= 0.5 and lead <= 2.0,
		"动态 BPM 预备拍限制在 2～4 拍合理区间", str(lead))
	_check(runtime.should_emit_metronome(10.0), "动态 BPM 节拍器在片段起点触发")
	_check(not runtime.should_emit_metronome(10.1), "同一动态 BPM 拍内不重复触发")
