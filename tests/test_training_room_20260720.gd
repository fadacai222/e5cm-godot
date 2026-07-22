extends SceneTree
## 训练室第一阶段契约：入口、配置规范化、训练载荷隔离和片段时钟。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_training_room_20260720.gd

var _failures := 0


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	_failures += 1
	push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var training_script := load("res://autoload/training_session.gd") as Script
	_check(training_script != null, "TrainingSession 脚本存在")
	if training_script == null:
		quit(1)
		return

	var training: Node = training_script.new()
	training.call("arm_entry")
	_check(bool(training.call("is_entry_armed")), "大模式页可武装训练入口")

	var config: Dictionary = training.call("create_config", 120.0, -8.0, 999.0, 0.62, 4, 5.0, false, true)
	_check(is_equal_approx(float(config.get("start_sec", -1.0)), 0.0), "训练起点不会小于 0", str(config))
	_check(is_equal_approx(float(config.get("end_sec", -1.0)), 120.0), "训练终点不会超过歌曲长度", str(config))
	_check(is_equal_approx(float(config.get("speed", -1.0)), 0.5), "非法速度归一到支持档位", str(config))
	_check(int(config.get("loop_count", 0)) == 3, "非法循环次数归一到支持档位", str(config))

	var short_config: Dictionary = training.call("create_config", 90.0, 88.0, 88.5, 1.0, 1, 0.0, false, true)
	_check(float(short_config.get("end_sec", 0.0)) - float(short_config.get("start_sec", 0.0)) >= 5.0 - 0.001,
		"训练片段最短为 5 秒", str(short_config))

	var song := {
		"sm": "C:/songs/test.sm", "mp3": "C:/songs/test.mp3", "cover": "",
		"name": "测试曲", "star": 8, "mode": "竞速", "submode": "club",
		"sm_key": "songs/test.sm", "prefer_double": false, "couple": false,
	}
	var decorated: Dictionary = training.call("begin", song, config)
	_check(bool(decorated.get("training_mode", false)), "训练载荷带明确资格隔离标记", str(decorated))
	_check(decorated.get("training_config", {}) is Dictionary, "训练载荷包含规范化配置")
	_check(bool(training.call("is_active")), "开始训练后会话标记为 active")
	_check(not bool(training.call("is_entry_armed")), "开始训练后清除入口武装状态")

	training.call("finish")
	_check(not bool(training.call("is_active")), "结束训练后清理 active 状态")

	var analytics_script := load("res://core/judgement_analytics.gd") as Script
	_check(analytics_script != null, "判定分析算法脚本存在")
	if analytics_script != null:
		var analytics = analytics_script.new(5)
		var report_script := load("res://core/judge_system.gd") as Script
		var early = report_script.JudgeReport.new("tap", 0, "perfect", 20.0, 5000, 1, 1.0, 1.0)
		var late = report_script.JudgeReport.new("tap", 1, "cool", -10.0, 4000, 1, 2.0, 2.0)
		var miss = report_script.JudgeReport.new("tap", 1, "miss", -250.0, 0, 0, 3.0, 3.0)
		analytics.add_report(early, 1)
		analytics.add_report(late, 2)
		analytics.add_report(miss, 0)
		var live_summary: Dictionary = analytics.quick_summary()
		_check(int(live_summary.get("total", 0)) == 3 \
			and not live_summary.has("worst_windows"),
			"实时 HUD 使用轻量增量汇总，不计算重型窗口", str(live_summary))
		var summary: Dictionary = analytics.summary()
		_check(int(summary.get("total", 0)) == 3, "判定分析汇总总事件数", str(summary))
		_check(int(summary.get("early_count", 0)) == 1, "正偏差统计为 Early", str(summary))
		_check(int(summary.get("late_count", 0)) == 1, "负偏差统计为 Late", str(summary))
		_check(is_equal_approx(float(summary.get("average_diff_ms", 0.0)), 5.0),
			"平均偏移排除 Miss", str(summary))
		analytics = null

	var runtime_script := load("res://core/training_runtime.gd") as Script
	_check(runtime_script != null, "TrainingRuntime 纯数据运行时存在")
	if runtime_script != null:
		var runtime_payload := {
			"training_config": training.call("create_config", 120.0, 10.0, 20.0,
				1.0, 3, 0.0, true, true),
			"bpm": 120.0,
		}
		var runtime = runtime_script.new(runtime_payload)
		var source_events := [
			{"track": 0, "type": "tap", "start_sec": 5.0, "end_sec": 5.0},
			{"track": 0, "type": "tap", "start_sec": 12.0, "end_sec": 12.0},
			{"track": 1, "type": "hold", "start_sec": 8.0, "end_sec": 14.0},
			{"track": 2, "type": "hold", "start_sec": 18.0, "end_sec": 25.0},
			{"track": 3, "type": "tap", "start_sec": 20.0, "end_sec": 20.0},
		]
		var sliced: Array = runtime.slice_events(source_events, [], 0.0)
		_check(sliced.size() == 3, "训练裁谱只保留与 [起点,终点) 相交的音符", str(sliced))
		_check(is_equal_approx(float(sliced[1].get("start_sec", -1.0)), 10.0),
			"跨越起点的 Hold 会裁到片段起点", str(sliced[1]))
		_check(is_equal_approx(float(sliced[2].get("end_sec", -1.0)), 20.0),
			"跨越终点的 Hold 会裁到片段终点", str(sliced[2]))
		_check(bool(runtime.should_emit_metronome(10.0)), "节拍器在新拍点触发")
		_check(not bool(runtime.should_emit_metronome(10.1)), "同一拍内不重复触发节拍器")
		runtime.clamp_segment(3.0)
		_check(is_equal_approx(float(runtime.start_sec), 0.0) \
			and is_equal_approx(float(runtime.end_sec), 3.0),
			"不足 5 秒的极短歌曲退化为整首训练")
		runtime = null

	var conductor_script := load("res://scenes/gameplay/conductor.gd") as Script
	var conductor = conductor_script.new(null)
	conductor.start(2.0, 42.0)
	_check(is_equal_approx(float(conductor.call("start_chart_sec_for_test")), 42.0),
		"Conductor 支持从训练片段起点启动")
	conductor.free()
	training.free()

	var mode_text := FileAccess.get_file_as_string("res://scenes/mode_select/mode_select.gd")
	var feature_entry_text := FileAccess.get_file_as_string("res://ui/feature_quick_access_rail.gd")
	_check(mode_text.contains("FeatureQuickAccessRail") \
		and feature_entry_text.contains("TrainingEntry"),
		"大模式选择界面通过统一街机快捷组件提供训练室入口")
	var router_text := FileAccess.get_file_as_string("res://autoload/scene_router.gd")
	_check(router_text.contains("training_setup"), "场景路由登记训练设置页")
	var song_select_text := FileAccess.get_file_as_string("res://scenes/song_select/song_select.gd")
	_check(song_select_text.contains("TrainingSession.is_entry_armed"), "选歌确认会进入训练设置而非正式游戏")
	var gameplay_text := FileAccess.get_file_as_string("res://scenes/gameplay/gameplay.gd")
	_check(gameplay_text.contains("_finish_training"), "训练结束走独立流程，不进入正式结算")

	quit(1 if _failures > 0 else 0)
