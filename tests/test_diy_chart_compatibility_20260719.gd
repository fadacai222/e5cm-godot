extends SceneTree
## DIY JSON 特效谱兼容规则：双时间轴、异常 BPM、假音符与真实花活谱回归。

const SmParserScript := preload("res://core/sm_parser.gd")

var _failures := 0
var _temp_paths: Array[String] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _write_chart(name: String, bpms: Array, lines: Array,
		extra_board := {}) -> String:
	var path := "user://%s.json" % name
	var board := {"lineDatas": lines}
	for key in extra_board.keys():
		board[key] = extra_board[key]
	var data := {
		"scoreInfo": {"offset": 0.0, "version": 3},
		"bpms": bpms,
		"boards": [board],
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_temp_paths.append(path)
	return path


func _cleanup() -> void:
	for path in _temp_paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_temp_paths.clear()


func _initialize() -> void:
	_test_terminal_freeze_uses_dual_timeline()
	_test_mid_song_slowdown_is_preserved()
	_test_bpm_normalization_is_deterministic()
	_test_fake_notes_are_render_only()
	_test_real_effect_charts()
	_cleanup()
	print("ALL DIY CHART COMPATIBILITY TESTS PASSED" if _failures == 0 else
		"%d DIY CHART COMPATIBILITY TEST(S) FAILED" % _failures)
	quit(_failures)


func _test_terminal_freeze_uses_dual_timeline() -> void:
	var path := _write_chart("compat_terminal_freeze", [
		{"lineNo": 0, "bpmVal": 128.0},
		{"lineNo": 96, "bpmVal": 999.0},
		{"lineNo": 192, "bpmVal": 0.001},
	], [
		{"lineNo": 96, "arrows": [{"aType": 1, "player": 1, "length": 0}]},
		{"lineNo": 288, "arrows": [{"aType": 7, "player": 1, "length": 0}]},
	])
	var result: Dictionary = SmParserScript.build_json_events(path)
	var event_timeline: Array = result.get("timeline", [])
	var duration_timeline: Array = result.get("duration_timeline", [])
	var patches: Array = result.get("compat_patches", [])
	_check(not event_timeline.is_empty()
		and is_equal_approx(float(event_timeline[-1][2]), 0.001)
		and not duration_timeline.is_empty()
		and not is_equal_approx(float(duration_timeline[-1][2]), 0.001)
		and float(result.get("duration", 99999.0)) < 5.0
		and patches.has("terminal_low_bpm_excluded_from_duration"),
		"锁尾 BPM 只从总时长估算移除，作者事件时间轴保持原样",
		"duration=%s event=%s duration_timeline=%s patches=%s" % [
			result.get("duration"), event_timeline, duration_timeline, patches])


func _test_mid_song_slowdown_is_preserved() -> void:
	var path := _write_chart("compat_mid_slowdown", [
		{"lineNo": 0, "bpmVal": 128.0},
		{"lineNo": 96, "bpmVal": 0.5},
		{"lineNo": 98, "bpmVal": 128.0},
	], [
		{"lineNo": 96, "arrows": [{"aType": 1, "player": 1, "length": 0}]},
		{"lineNo": 99, "arrows": [{"aType": 7, "player": 1, "length": 0}]},
	])
	var result: Dictionary = SmParserScript.build_json_events(path)
	var timeline: Array = result.get("timeline", [])
	var has_half_bpm := timeline.any(func(segment):
		return is_equal_approx(float(segment[2]), 0.5))
	_check(has_half_bpm and float(result.get("duration", 0.0)) > 4.0
		and not (result.get("compat_patches", []) as Array).has(
			"terminal_low_bpm_excluded_from_duration"),
		"中途短暂低 BPM 花活保留，不被锁尾补丁误伤", str(result))


func _test_bpm_normalization_is_deterministic() -> void:
	var path := _write_chart("compat_bpm_normalize", [
		{"lineNo": 192, "bpmVal": 160.0},
		{"lineNo": -96, "bpmVal": 88.0},
		{"lineNo": 96, "bpmVal": 100.0},
		{"lineNo": 96, "bpmVal": 200.0},
		{"lineNo": 144, "bpmVal": 0.0},
		{"lineNo": 160, "bpmVal": -10.0},
	], [
		{"lineNo": -10, "arrows": [{"aType": 1, "player": 1, "length": 0}]},
		{"lineNo": 96, "arrows": [{"aType": 4, "player": 9, "length": -48}]},
		{"lineNo": 192, "arrows": [{"aType": 7, "player": 1, "length": 0}]},
	])
	var result: Dictionary = SmParserScript.build_json_events(path)
	var bpms: Array = result.get("bpms", [])
	var events: Array = result.get("events", [])
	var patches: Array = result.get("compat_patches", [])
	var bpm_at_one := -1.0
	for entry in bpms:
		if is_equal_approx(float(entry[0]), 1.0):
			bpm_at_one = float(entry[1])
	_check(bpms.size() == 3 and is_equal_approx(float(bpms[0][0]), 0.0)
		and is_equal_approx(float(bpms[0][1]), 200.0)
		and is_equal_approx(bpm_at_one, 200.0)
		and events.size() == 2
		and int(events[0].get("player", 0)) == 2
		and str(events[0].get("type", "")) == "tap"
		and patches.has("invalid_bpm_entries_ignored")
		and patches.has("duplicate_bpm_lines_collapsed")
		and patches.has("invalid_note_fields_sanitized"),
		"BPM 乱序/重复/非法值和音符异常字段采用确定性安全规则",
		"bpms=%s events=%s patches=%s" % [bpms, events, patches])


func _test_fake_notes_are_render_only() -> void:
	var path := _write_chart("compat_fake_notes", [
		{"lineNo": 0, "bpmVal": 120.0},
		{"lineNo": 96, "bpmVal": 10000000.0},
		{"lineNo": 192, "bpmVal": 120.0},
	], [
		{"lineNo": 96, "arrows": [
			{"aType": 1, "player": 1, "length": 0, "isFaked": true},
			{"aType": 4, "player": 1, "length": 0},
		]},
		{"lineNo": 192, "arrows": [{"aType": 7, "player": 1, "length": 0}]},
	], {"bpmSpeeds": [{"lineNo": 96, "speed": 64.0, "length": 0.25}]})
	var result: Dictionary = SmParserScript.build_json_events(path)
	var events: Array = result.get("events", [])
	var fake_events: Array = result.get("fake_events", [])
	var pulses: Array = result.get("visual_pulses", [])
	_check(events.size() == 2 and fake_events.size() == 1
		and bool(fake_events[0].get("render_only", false))
		and is_finite(float(fake_events[0].get("render_start_sec", NAN)))
		and pulses.size() == 1
		and float(result.get("duration", INF)) < 10.0,
		"百万 BPM 假音符只渲染不判定，bpmSpeeds 转为安全视觉脉冲",
		"events=%s fake=%s pulses=%s duration=%s" % [events, fake_events,
			pulses, result.get("duration")])


func _real_chart(relative_path: String) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join(relative_path)
	if not FileAccess.file_exists(path):
		return {"skip": true, "path": path}
	return SmParserScript.build_json_events(path)


func _test_real_effect_charts() -> void:
	var sugar := _real_chart(
		"songs/diy/社区竞速/SugarFree(슈가프리)(BigRoomver.)#11/SugarFree(슈가프리)(BigRoomver.).json")
	if not bool(sugar.get("skip", false)):
		var sugar_timeline: Array = sugar.get("timeline", [])
		_check(float(sugar.get("duration", 0.0)) > 150.0
			and float(sugar.get("duration", 9999.0)) < 180.0
			and not sugar_timeline.is_empty()
			and is_equal_approx(float(sugar_timeline[-1][2]), 0.001),
			"真实 SugarFree：时长正常但 0.001 BPM 事件花活仍保留", str(sugar))

	var one_two_three := _real_chart(
		"songs/diy/社区竞速/123（OneTwoThree）#9/123（OneTwoThree）.json")
	if not bool(one_two_three.get("skip", false)):
		_check(float(one_two_three.get("duration", 0.0)) > 100.0
			and float(one_two_three.get("duration", 9999.0)) < 300.0,
			"真实 123：999.98999→0.001 锁尾不会膨胀时长",
			str(one_two_three.get("duration")))

	var fiesta := _real_chart(
		"songs/diy/社区竞速/1,2Fiesta（瓶子）#11/1,2Fiesta（瓶子）.json")
	if not bool(fiesta.get("skip", false)):
		var fiesta_bpms: Array = fiesta.get("bpms", [])
		var keeps_0566 := fiesta_bpms.any(func(entry):
			return is_equal_approx(float(entry[1]), 0.566))
		var keeps_13110 := fiesta_bpms.any(func(entry):
			return is_equal_approx(float(entry[1]), 13110.0))
		_check(keeps_0566 and keeps_13110
			and is_finite(float(fiesta.get("duration", NAN))),
			"真实 1,2Fiesta：中途 0.566/13110 BPM 花活完整保留",
			"duration=%s" % fiesta.get("duration"))

	var l_chart := _real_chart("songs/diy/社区竞速/L#11/L.json")
	if not bool(l_chart.get("skip", false)):
		var all_finite := true
		for event in l_chart.get("events", []):
			all_finite = all_finite and is_finite(float(event.get("start_sec", NAN))) \
				and is_finite(float(event.get("end_sec", NAN)))
		_check(all_finite and is_finite(float(l_chart.get("duration", NAN)))
			and float(l_chart.get("duration", INF)) < 400.0,
			"真实 L：一百亿 BPM 与 0.8 BPM 组合不会溢出或卡死",
			"duration=%s" % l_chart.get("duration"))
