extends SceneTree
## SM 解析器对照测试：与旧版 Python 解析器的 baseline.json 逐项比对。
## 运行：godot --headless --path . --script res://tests/test_sm_parser.gd

const SmParserScript := preload("res://core/sm_parser.gd")
const ChartBuilderScript := preload("res://core/chart_builder.gd")

const BASELINE := "res://parity/fixtures/sm_parser_baseline.json"

var _failures := 0
var _asset_loader: Node


func _initialize() -> void:
	_asset_loader = root.get_node_or_null("AssetLoader")
	await process_frame
	if _asset_loader == null:
		print("FAIL AssetLoader autoload 不存在")
		quit(1)
		return
	if not FileAccess.file_exists(BASELINE):
		print("FAIL 找不到 baseline.json，请先在旧工程运行 export_baseline.py")
		quit(1)
		return
	var baseline = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	if not (baseline is Array) or baseline.is_empty():
		print("FAIL baseline.json 解析失败")
		quit(1)
		return

	var idx := 0
	for entry in baseline:
		idx += 1
		_compare(idx, entry)
	_test_diy_json_chart()

	if _failures == 0:
		print("ALL %d BASELINE CASES PASSED" % baseline.size())
	else:
		print("%d CASE(S) FAILED" % _failures)
	quit(_failures)


func _test_diy_json_chart() -> void:
	var path := "user://test_diy_chart.json"
	var payload := {
		"scoreInfo": {"offset": 0.25, "version": 3},
		"bpms": [{"lineNo": 0, "bpmVal": 120.0}],
		"boards": [{"lineDatas": [
			{"lineNo": 96, "arrows": [
				{"aType": 1, "player": 1, "length": 0},
				{"aType": 3, "player": 1, "length": 96},
			]},
			{"lineNo": 192, "arrows": [
				{"aType": 7, "player": 2, "length": 96},
			]},
		]}],
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var result := SmParserScript.build_events(path, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var events: Array = result.get("events", [])
	var hands: Array = result.get("hand_events", [])
	var ok := str(result.get("error", "")).is_empty() and events.size() == 2 \
		and hands.size() == 1 and int(result.get("columns", 0)) == 10 \
		and str(events[1].get("type", "")) == "hold" \
		and int(events[1].get("track", -1)) == 9 \
		and absf(float(events[0].get("start_sec", 0.0)) - 0.25) < 0.001
	if ok:
		print("  PASS  DIY JSON 谱面解析（脚/手/Hold/2P/offset）")
	else:
		_failures += 1
		print("  FAIL  DIY JSON 谱面解析 -> %s" % str(result))


func _compare(idx: int, entry: Dictionary) -> void:
	var sm_path := str(_asset_loader.call("abs_path", str(entry["sm"])))
	var prefer_double := bool(entry["优先double"])
	var result := SmParserScript.build_events(sm_path, prefer_double)

	var tag := "#%d %s double=%s" % [idx, str(entry["sm"]).get_file(), prefer_double]
	var ok := true
	var detail := ""

	var events: Array = result["events"]
	var taps := 0
	var holds := 0
	for e in events:
		if str(e["type"]) == "tap":
			taps += 1
		else:
			holds += 1

	if events.size() != int(entry["事件数"]):
		ok = false; detail += " 事件数 %d≠%d" % [events.size(), int(entry["事件数"])]
	if taps != int(entry["tap数"]):
		ok = false; detail += " tap %d≠%d" % [taps, int(entry["tap数"])]
	if holds != int(entry["hold数"]):
		ok = false; detail += " hold %d≠%d" % [holds, int(entry["hold数"])]
	if (result["hand_events"] as Array).size() != int(entry["手键数"]):
		ok = false; detail += " 手键 %d≠%d" % [(result["hand_events"] as Array).size(), int(entry["手键数"])]
	if int(result["columns"]) != int(entry["列数"]):
		ok = false; detail += " 列数 %d≠%d" % [int(result["columns"]), int(entry["列数"])]
	if str(result["charttype"]) != str(entry["charttype"]):
		ok = false; detail += " charttype %s≠%s" % [result["charttype"], entry["charttype"]]
	if absf(float(result["offset"]) - float(entry["offset"])) > 1e-4:
		ok = false; detail += " offset %f≠%f" % [float(result["offset"]), float(entry["offset"])]
	if absf(float(result["duration"]) - float(entry["总时长"])) > 1e-3:
		ok = false; detail += " 时长 %f≠%f" % [float(result["duration"]), float(entry["总时长"])]

	# bpms 对照
	var bpms: Array = result["bpms"]
	var base_bpms: Array = entry["bpms"]
	if bpms.size() != base_bpms.size():
		ok = false; detail += " bpms段数 %d≠%d" % [bpms.size(), base_bpms.size()]
	else:
		for i in bpms.size():
			if absf(float(bpms[i][0]) - float(base_bpms[i][0])) > 1e-4 \
					or absf(float(bpms[i][1]) - float(base_bpms[i][1])) > 1e-4:
				ok = false; detail += " bpms[%d]不一致" % i
				break

	# 前10事件逐项对照
	var base_first: Array = entry["前10事件"]
	for i in mini(base_first.size(), events.size()):
		var be: Dictionary = base_first[i]
		var ge: Dictionary = events[i]
		if int(ge["track"]) != int(be["轨道"]) or str(ge["type"]) != str(be["类型"]) \
				or absf(float(ge["start_sec"]) - float(be["开始秒"])) > 1e-4 \
				or absf(float(ge["end_sec"]) - float(be["结束秒"])) > 1e-4:
			ok = false
			detail += " 事件[%d] (%d,%s,%.4f)≠(%d,%s,%.4f)" % [
				i, int(ge["track"]), ge["type"], float(ge["start_sec"]),
				int(be["轨道"]), be["类型"], float(be["开始秒"])]
			break

	# tick 总数与总分（判定点规则）
	var timeline: Array = result["timeline"]
	var offset := float(result["offset"])
	var b2s := func(beat: float) -> float:
		return SmParserScript.beat_to_sec(beat, timeline) - offset
	var chart := ChartBuilderScript.build(events, b2s)
	var tick_total := 0
	for note in chart["notes"]:
		tick_total += (note.tick_secs as Array).size()
	if tick_total != int(entry["tick总数"]):
		ok = false; detail += " tick总数 %d≠%d" % [tick_total, int(entry["tick总数"])]
	if int(chart["total_score"]) != int(entry["总分"]):
		ok = false; detail += " 总分 %d≠%d" % [int(chart["total_score"]), int(entry["总分"])]

	if ok:
		print("  PASS  %s (事件%d tick%d 总分%d)" % [tag, events.size(), tick_total, int(chart["total_score"])])
	else:
		_failures += 1
		print("  FAIL  %s ->%s" % [tag, detail])
