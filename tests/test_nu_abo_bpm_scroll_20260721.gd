extends SceneTree
## Nu ABO 等 DIY JSON 花活谱：判定仍按秒，视觉位置按作者 BPMS 的 beat 距离计算。

const SmParserScript := preload("res://core/sm_parser.gd")
const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
]

var failures := 0
var _created: Array[Node] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _run() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var service: Node = load(entry[1]).new()
			service.name = entry[0]
			root.add_child(service)
			_created.append(service)
	await process_frame
	var note_field_script: GDScript = load("res://scenes/gameplay/note_field.gd")
	var field: Node = note_field_script.new()
	root.add_child(field)
	field.set("scroll_speed_mult", 4.0)
	var speed := 630.0 * float(field.get("scroll_speed_mult"))

	# 取自原版 Nu ABO 的关键结构：95 BPM 基准，随后在相邻短区间切到 1045 / 4.13。
	var bpms := [
		[0.0, 95.0],
		[20.0, 1045.0],
		[20.2291666667, 4.13],
		[20.25, 1045.0],
	]
	var timeline: Array = SmParserScript.build_timeline(bpms)
	var offset := 1.684
	field.configure_bpm_scroll(bpms, timeline, offset)
	_check(field.bpm_scroll_enabled_for_test(),
		"Nu ABO 多段 BPMS 启用作者原生视觉变速")

	var chart_sec := SmParserScript.beat_to_sec(20.0, timeline) - offset
	var note_beat := 20.25
	var note_sec := SmParserScript.beat_to_sec(note_beat, timeline) - offset
	var actual := float(field.call("scroll_y_for_event_test", note_sec, note_beat, chart_sec, speed))
	var pixels_per_beat := speed * 60.0 / 95.0
	var expected := float(field.call("receptor_y_for_test")) + 0.25 * pixels_per_beat
	var fixed_seconds := float(field.call("scroll_y_for_test", note_sec, chart_sec, speed))
	_check(absf(actual - expected) < 0.05,
		"Nu ABO 音符按 beat 距离而不是固定秒速定位",
		"actual=%.3f expected=%.3f" % [actual, expected])
	_check(absf(actual - fixed_seconds) > 200.0,
		"1045/4.13 花活 BPM 不再被固定秒速滚动吞掉",
		"bpm=%.3f fixed=%.3f" % [actual, fixed_seconds])

	# 常速谱按 beat 计算应与旧固定秒速完全等价，避免普通歌曲发生回归。
	var constant_bpms := [[0.0, 120.0]]
	var constant_timeline: Array = SmParserScript.build_timeline(constant_bpms)
	field.configure_bpm_scroll(constant_bpms, constant_timeline, 0.0)
	var constant_chart_sec := 10.0
	var constant_note_sec := 10.75
	var constant_note_beat := SmParserScript.sec_to_beat(constant_note_sec, constant_timeline)
	var beat_y := float(field.call("scroll_y_for_event_test",
		constant_note_sec, constant_note_beat, constant_chart_sec, speed))
	var second_y := float(field.call("scroll_y_for_test",
		constant_note_sec, constant_chart_sec, speed))
	_check(absf(beat_y - second_y) < 0.05,
		"常速谱启用 beat 渲染后与原固定秒速位置一致",
		"beat=%.3f second=%.3f" % [beat_y, second_y])

	var real_path := "res://songs/diy/社区竞速/NUABO#10/NUABO.json"
	var real_result: Dictionary = SmParserScript.build_json_events(real_path)
	var real_bpms: Array = real_result.get("bpms", [])
	var keeps_1045 := real_bpms.any(func(entry):
		return entry is Array and entry.size() >= 2 and absf(float(entry[1]) - 1045.0) < 0.01)
	var keeps_413 := real_bpms.any(func(entry):
		return entry is Array and entry.size() >= 2 and absf(float(entry[1]) - 4.13) < 0.01)
	_check(str(real_result.get("error", "")).is_empty() and real_bpms.size() > 20
		and keeps_1045 and keeps_413,
		"当前 songs 中 Nu ABO 真实谱面保留原版 1045 / 4.13 变速事件",
		"bpms=%d error=%s" % [real_bpms.size(), str(real_result.get("error", ""))])
	var real_events: Array = real_result.get("events", [])
	_check(not real_events.is_empty() and real_events.all(func(event):
		return event is Dictionary and event.has("start_beat") and event.has("end_beat")),
		"Nu ABO 真实音符携带 beat 坐标进入视觉变速链")
	field.configure_bpm_scroll(real_bpms, real_result.get("timeline", []),
		float(real_result.get("offset", 0.0)))
	var receptor_y := float(field.call("receptor_y_for_test"))
	var drift_samples := [0, real_events.size() / 2, maxi(0, real_events.size() - 1)]
	var max_raw_alignment_error := 0.0
	for sample_index in drift_samples:
		var event: Dictionary = real_events[int(sample_index)]
		var event_y := float(field.call("scroll_y_for_event_test",
			float(event.get("start_sec", 0.0)), float(event.get("start_beat", NAN)),
			float(event.get("start_sec", 0.0)), speed))
		max_raw_alignment_error = maxf(max_raw_alignment_error, absf(event_y - receptor_y))
	_check(max_raw_alignment_error < 0.05,
		"Nu ABO 从开头到结尾的真实音符在判定秒都精确落到判定线，不再越玩越漂移",
		"max_error=%.6f" % max_raw_alignment_error)

	# 原版使用同一“当前谱面秒”同时驱动判定与渲染。Godot 若把平滑时钟交给
	# NoteField、原始音频时钟交给 Judge，高 BPM 区只差几十毫秒就会错开数百像素。
	var gameplay_script: GDScript = load("res://scenes/gameplay/gameplay.gd")
	var gameplay: Control = gameplay_script.new()
	var has_visual_clock_contract := gameplay.has_method("note_visual_time_for_test")
	_check(has_visual_clock_contract,
		"Gameplay 提供判定/视觉同源时钟契约")
	if has_visual_clock_contract:
		var raw_chart_time := note_sec
		var smoothed_chart_time := raw_chart_time - 0.032
		var visual_chart_time := float(gameplay.call(
			"note_visual_time_for_test", raw_chart_time, smoothed_chart_time))
		_check(absf(visual_chart_time - raw_chart_time) < 0.000001,
			"变速谱渲染使用判定同源的原始音频时钟，不使用累计滞后的平滑时钟",
			"raw=%.6f smooth=%.6f visual=%.6f" % [
				raw_chart_time, smoothed_chart_time, visual_chart_time])
	gameplay.free()

	root.remove_child(field)
	field.free()
	for service in _created:
		if is_instance_valid(service):
			root.remove_child(service)
			service.free()
	await process_frame
	quit(1 if failures > 0 else 0)
