extends SceneTree
## DIY JSON 异常时长回归：终局极低 BPM 不得生成千分钟歌曲，Gameplay 以音频长度收口。

const SmParserScript := preload("res://core/sm_parser.gd")

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	_test_terminal_freeze_sample()
	_test_real_sugarfree()
	if _failures == 0:
		print("ALL DIY DURATION REGRESSION TESTS PASSED")
	else:
		print("%d DIY DURATION REGRESSION TEST(S) FAILED" % _failures)
	quit(_failures)


func _test_terminal_freeze_sample() -> void:
	var path := "user://test_diy_terminal_freeze_duration.json"
	var payload := {
		"scoreInfo": {"offset": 0.0, "version": 3},
		"bpms": [
			{"lineNo": 0, "bpmVal": 128.0},
			{"lineNo": 96, "bpmVal": 999.0},
			{"lineNo": 192, "bpmVal": 0.001},
		],
		"boards": [{"lineDatas": [
			{"lineNo": 96, "arrows": [{"aType": 1, "player": 1, "length": 0}]},
			{"lineNo": 288, "arrows": [{"aType": 7, "player": 1, "length": 0}]},
		]}],
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var result := SmParserScript.build_events(path, false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var events: Array = result.get("events", [])
	var timeline: Array = result.get("timeline", [])
	var duration_timeline: Array = result.get("duration_timeline", [])
	_check(events.size() == 2
		and float(result.get("duration", 99999.0)) < 5.0
		and not timeline.is_empty() and is_equal_approx(float(timeline[-1][2]), 0.001)
		and not duration_timeline.is_empty()
		and not is_equal_approx(float(duration_timeline[-1][2]), 0.001),
		"末尾 0.001 BPM 仅从总时长估算时间轴移除",
		"duration=%s timeline=%s duration_timeline=%s" % [
			result.get("duration"), timeline, duration_timeline])


func _test_real_sugarfree() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join(
		"songs/diy/社区竞速/SugarFree(슈가프리)(BigRoomver.)#11/SugarFree(슈가프리)(BigRoomver.).json")
	if not FileAccess.file_exists(path):
		print("  SKIP  SugarFree 真实 DIY 谱面不在当前测试环境")
		return
	var result := SmParserScript.build_events(path, false)
	var events: Array = result.get("events", [])
	var duration := float(result.get("duration", 0.0))
	var timeline: Array = result.get("timeline", [])
	var patches: Array = result.get("compat_patches", [])
	_check(str(result.get("error", "")).is_empty()
		and not events.is_empty() and duration > 150.0 and duration < 180.0
		and not timeline.is_empty() and is_equal_approx(float(timeline[-1][2]), 0.001)
		and patches.has("terminal_low_bpm_excluded_from_duration"),
		"SugarFree 总时长恢复正常且作者锁尾 BPM 保留",
		"duration=%.3f patches=%s error=%s" % [duration, patches,
			str(result.get("error", ""))])
