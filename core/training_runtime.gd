class_name TrainingRuntime
extends RefCounted
## Gameplay 内的训练运行时状态与纯数据逻辑。
## 不操作场景节点，不写正式存档；Gameplay 只负责音频、判定器和 UI 的编排。

var config := {}
var start_sec := 0.0
var end_sec := 0.0
var runtime_start_sec := 0.0
var speed := 1.0
var loop_target := -1
var loop_index := 1
var auto_rewind_sec := 0.0
var show_timing := true
var metronome := false
var bpm := 0.0
var timeline: Array = []
var timeline_offset := 0.0
var last_beat_index := -999999
var problem_windows: Array = []
var problem_window_index := 0

var chart_notes: Array = []
var hand_events: Array = []
var analytics: JudgementAnalytics


func _init(payload: Dictionary) -> void:
	config = (payload.get("training_config", {}) as Dictionary).duplicate(true)
	start_sec = maxf(0.0, float(config.get("start_sec", 0.0)))
	end_sec = maxf(start_sec + TrainingSession.MIN_SEGMENT_SECONDS,
		float(config.get("end_sec", start_sec + TrainingSession.MIN_SEGMENT_SECONDS)))
	runtime_start_sec = start_sec
	speed = clampf(float(config.get("speed", 1.0)), 0.5, 1.0)
	loop_target = int(config.get("loop_count", -1))
	auto_rewind_sec = clampf(float(config.get("auto_rewind_sec", 0.0)), 0.0, 10.0)
	show_timing = bool(config.get("show_timing", true))
	metronome = bool(config.get("metronome", false))
	bpm = maxf(0.0, float(payload.get("bpm", 0.0)))
	if config.get("problem_windows", []) is Array:
		problem_windows = (config.get("problem_windows", []) as Array).duplicate(true)
		problem_window_index = clampi(int(config.get("problem_window_index", 0)), 0,
			maxi(0, problem_windows.size() - 1))


func clamp_segment(chart_duration: float) -> void:
	var duration := maxf(0.0, chart_duration)
	if duration <= TrainingSession.MIN_SEGMENT_SECONDS:
		start_sec = 0.0
		end_sec = duration
	else:
		start_sec = clampf(start_sec, 0.0,
			maxf(0.0, duration - TrainingSession.MIN_SEGMENT_SECONDS))
		end_sec = clampf(end_sec, start_sec + TrainingSession.MIN_SEGMENT_SECONDS,
			duration)
	runtime_start_sec = start_sec
	config["start_sec"] = start_sec
	config["end_sec"] = end_sec
	config["song_duration"] = duration


func slice_events(source: Array, timeline: Array, offset: float) -> Array:
	var sliced: Array = []
	for raw_event in source:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = (raw_event as Dictionary).duplicate(true)
		var event_start := float(event.get("start_sec", 0.0))
		var event_end := maxf(event_start, float(event.get("end_sec", event_start)))
		var event_type := str(event.get("type", "tap"))
		if event_start >= end_sec or event_end < start_sec:
			continue
		if event_type == "tap":
			if event_start >= start_sec:
				sliced.append(event)
			continue
		if event_start < start_sec:
			event["start_sec"] = start_sec
			if event.has("start_beat") and not timeline.is_empty():
				event["start_beat"] = SmParser.sec_to_beat(start_sec + offset, timeline)
		if event_end > end_sec:
			event["end_sec"] = end_sec
			if event.has("end_beat") and not timeline.is_empty():
				event["end_beat"] = SmParser.sec_to_beat(end_sec + offset, timeline)
		if float(event.get("end_sec", start_sec)) >= float(event.get("start_sec", start_sec)):
			sliced.append(event)
	return sliced


func capture_chart(notes: Array, hands: Array, track_count: int) -> void:
	chart_notes = notes.duplicate()
	hand_events = hands.duplicate(true)
	analytics = JudgementAnalytics.new(track_count)


func reset_analysis(track_count: int) -> void:
	if analytics == null:
		analytics = JudgementAnalytics.new(track_count)
	else:
		analytics.reset(track_count)


func add_report(report: JudgeSystem.JudgeReport, combo_after: int, auto_generated: bool) -> Dictionary:
	if analytics != null:
		analytics.add_report(report, combo_after, auto_generated)
	var rewind_at := -1.0
	if report.judge == "miss" and auto_rewind_sec > 0.0:
		rewind_at = maxf(start_sec, float(report.start_sec) - auto_rewind_sec)
	return {
		"timing_diff": null if report.type == "hold_tick" else report.time_diff_ms,
		"rewind_at": rewind_at,
	}


func set_timeline(source: Array, offset: float) -> void:
	timeline = source.duplicate(true)
	timeline_offset = offset
	last_beat_index = -999999


func bpm_at(chart_time: float) -> float:
	if timeline.is_empty():
		return bpm
	var source_sec := chart_time + timeline_offset
	var selected: Array = timeline[0]
	for raw_segment in timeline:
		var segment: Array = raw_segment
		if float(segment[1]) <= source_sec + 1e-6:
			selected = segment
		else:
			break
	return maxf(0.0, float(selected[2]))


func preroll_seconds(at_sec := -1.0) -> float:
	var target := runtime_start_sec if at_sec < 0.0 else at_sec
	var local_bpm := bpm_at(target)
	if local_bpm <= 0.0:
		return 1.35
	# 以 4 拍为目标，同时把实际等待限制在 0.5～2 秒；
	# 极慢曲自动退化为 2 拍左右，极快曲仍保留至少约 4 拍的可感知提示。
	return clampf(4.0 * 60.0 / local_bpm, 0.5, 2.0)


func should_emit_metronome(chart_time: float) -> bool:
	if not metronome or chart_time < runtime_start_sec:
		return false
	var beat_value: float
	if not timeline.is_empty():
		beat_value = SmParser.sec_to_beat(chart_time + timeline_offset, timeline)
	else:
		if bpm <= 0.0:
			return false
		beat_value = chart_time * bpm / 60.0
	var beat_index := int(floor(beat_value + 1e-6))
	if beat_index == last_beat_index:
		return false
	last_beat_index = beat_index
	return true


func notes_from(from_sec: float) -> Array:
	var result: Array = []
	for note in chart_notes:
		if float(note.start_sec) + 0.001 >= from_sec:
			result.append(note)
	return result


func hands_from(from_sec: float) -> Array:
	var result: Array = []
	for event in hand_events:
		if event is Dictionary and float(event.get("start_sec", 0.0)) + 0.001 >= from_sec:
			result.append((event as Dictionary).duplicate(true))
	return result


func score_for_notes(notes: Array) -> int:
	var points := 0
	for note in notes:
		points += 1
		if str(note.type) == "hold":
			points += (note.tick_secs as Array).size()
	return maxi(5000, points * 5000)


func set_runtime_start(requested_sec: float) -> void:
	runtime_start_sec = clampf(requested_sec, start_sec, maxf(start_sec, end_sec - 0.1))
	last_beat_index = -999999


func has_more_loops() -> bool:
	return loop_target < 0 or loop_index < loop_target


func advance_loop() -> void:
	loop_index += 1


func has_problem_windows() -> bool:
	return not problem_windows.is_empty()


func select_problem_window(direction: int, chart_duration: float) -> bool:
	if problem_windows.is_empty():
		return false
	problem_window_index = (problem_window_index + direction + problem_windows.size()) % problem_windows.size()
	var window: Dictionary = problem_windows[problem_window_index]
	var duration := maxf(0.1, chart_duration)
	var requested_start := maxf(0.0, float(window.get("start_sec", 0.0)) - 2.0)
	var requested_end := minf(duration, float(window.get("end_sec", requested_start + 5.0)) + 2.0)
	var minimum_segment := minf(TrainingSession.MIN_SEGMENT_SECONDS, duration)
	start_sec = clampf(requested_start, 0.0, maxf(0.0, duration - minimum_segment))
	end_sec = clampf(requested_end, minf(duration, start_sec + minimum_segment), duration)
	runtime_start_sec = start_sec
	loop_index = 1
	config["start_sec"] = start_sec
	config["end_sec"] = end_sec
	config["problem_window_index"] = problem_window_index
	last_beat_index = -999999
	return true


func live_summary() -> Dictionary:
	return analytics.quick_summary() if analytics != null else {}


func summary() -> Dictionary:
	return analytics.summary() if analytics != null else {}
